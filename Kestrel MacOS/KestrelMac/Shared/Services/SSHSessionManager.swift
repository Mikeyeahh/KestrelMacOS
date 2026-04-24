//
//  SSHSessionManager.swift
//  Kestrel Mac
//
//  Real SSH session management using Citadel.
//

import Foundation
import Citadel
import Crypto
import NIOSSH
import NIO

// MARK: - Session State

enum SessionState: Equatable, Sendable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case error(String)

    var displayName: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .authenticating: "Authenticating…"
        case .connected: "Connected"
        case .error(let message): "Error: \(message)"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .disconnected, .error: true
        default: false
        }
    }
}

// MARK: - SSH Session Error

enum SSHSessionError: LocalizedError {
    case notConnected
    case alreadyConnected
    case shellAlreadyActive
    case authenticationFailed(String)
    case connectionFailed(String)
    case commandFailed(String)
    case privateKeyNotFound
    case invalidPrivateKey
    case passwordNotFound

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Not connected to server"
        case .alreadyConnected:
            "Already connected to server"
        case .shellAlreadyActive:
            "Interactive shell is already active"
        case .authenticationFailed(let reason):
            "Authentication failed: \(reason)"
        case .connectionFailed(let reason):
            "Connection failed: \(reason)"
        case .commandFailed(let reason):
            "Command failed: \(reason)"
        case .privateKeyNotFound:
            "Private key not found in Keychain"
        case .invalidPrivateKey:
            "Could not parse private key"
        case .passwordNotFound:
            "Password not found in Keychain — please re-enter your password in server settings"
        }
    }
}

// MARK: - SSH Session

@Observable
@MainActor
final class SSHSession: Identifiable {
    let id = UUID()
    let serverID: UUID
    let host: String
    let port: Int
    let username: String
    let authMethod: String      // "password", "privateKey", "sshAgent"
    let privateKeyID: UUID?
    let useMosh: Bool

    private(set) var state: SessionState = .disconnected
    private(set) var output: String = ""
    private(set) var connectedAt: Date?

    var isConnected: Bool { state == .connected }

    private var client: SSHClient?
    private var keepaliveTask: Task<Void, Never>?
    private var shellTask: Task<Void, Never>?
    private var shellWriter: TTYStdinWriter?

    // MOSH support
    private var moshProcess: Process?
    private var moshInputPipe: Pipe?

    var isShellActive: Bool {
        shellTask != nil && !(shellTask?.isCancelled ?? true)
    }

    // MARK: - Init

    nonisolated init(
        serverID: UUID,
        host: String,
        port: Int,
        username: String,
        authMethod: String,
        privateKeyID: UUID? = nil,
        useMosh: Bool = false
    ) {
        self.serverID = serverID
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.privateKeyID = privateKeyID
        self.useMosh = useMosh
    }

    // MARK: - Connect

    func connect() async throws {
        guard state != .connected else {
            throw SSHSessionError.alreadyConnected
        }

        state = .connecting

        if useMosh {
            try await connectViaMosh()
            return
        }

        do {
            state = .authenticating
            let sshAuth = try buildAuthenticationMethod()

            let sshClient = try await SSHClient.connect(
                host: host,
                port: port,
                authenticationMethod: sshAuth,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                algorithms: .all
            )

            self.client = sshClient
            self.state = .connected
            self.connectedAt = .now

            sshClient.onDisconnect { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.state == .connected else { return }
                    self.handleDisconnect()
                }
            }

            startKeepalive()
        } catch {
            print("[SSH] Connection failed: \(error)")
            let friendlyMessage = Self.friendlyErrorMessage(for: error, authMethod: authMethod)
            state = .error(friendlyMessage)
            throw SSHSessionError.connectionFailed(friendlyMessage)
        }
    }

    // MARK: - Execute Command

    func execute(_ command: String) async throws -> String {
        guard let client, isConnected else {
            throw SSHSessionError.notConnected
        }

        do {
            let buffer = try await client.executeCommand(command, mergeStreams: true)
            let result = String(buffer: buffer)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as SSHClient.CommandFailed {
            throw SSHSessionError.commandFailed("Exit code \(error.exitCode)")
        } catch {
            throw SSHSessionError.commandFailed(error.localizedDescription)
        }
    }

    // MARK: - Interactive Shell

    func startShell() throws {
        guard let client, isConnected else {
            throw SSHSessionError.notConnected
        }

        guard !isShellActive else {
            throw SSHSessionError.shellAlreadyActive
        }

        output = ""

        shellTask = Task { [weak self] in
            guard let self else { return }

            do {
                let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: 80,
                    terminalRowHeight: 24,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([
                        .ECHO: 1,
                        .ICANON: 1
                    ])
                )

                if #available(macOS 15.0, *) {
                    try await client.withPTY(ptyRequest) { [weak self] inbound, outbound in
                        guard let self else { return }

                        await MainActor.run {
                            self.shellWriter = outbound
                        }

                        for try await event in inbound {
                            switch event {
                            case .stdout(let buffer):
                                let text = String(buffer: buffer)
                                await MainActor.run {
                                    self.output.append(text)
                                }
                            case .stderr(let buffer):
                                let text = String(buffer: buffer)
                                await MainActor.run {
                                    self.output.append(text)
                                }
                            }
                        }
                    }
                } else {
                    let stream = try await client.executeCommandStream("bash -l", inShell: true)
                    for try await event in stream {
                        switch event {
                        case .stdout(let buffer):
                            let text = String(buffer: buffer)
                            await MainActor.run {
                                self.output.append(text)
                            }
                        case .stderr(let buffer):
                            let text = String(buffer: buffer)
                            await MainActor.run {
                                self.output.append(text)
                            }
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.output.append("\r\n[Shell ended: \(error.localizedDescription)]\r\n")
                    }
                }
            }

            await MainActor.run {
                self.shellWriter = nil
                self.shellTask = nil
            }
        }
    }

    func send(_ input: String) {
        if useMosh, let pipe = moshInputPipe {
            pipe.fileHandleForWriting.write(Data(input.utf8))
            return
        }

        guard let shellWriter else { return }

        Task {
            var buffer = ByteBufferAllocator().buffer(capacity: input.utf8.count)
            buffer.writeString(input)
            try? await shellWriter.write(buffer)
        }
    }

    func resizeTerminal(cols: Int, rows: Int) {
        guard let shellWriter else { return }
        guard cols > 0, rows > 0 else { return }

        Task {
            try? await shellWriter.changeSize(
                cols: cols,
                rows: rows,
                pixelWidth: 0,
                pixelHeight: 0
            )
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        shellTask?.cancel()
        shellTask = nil
        shellWriter = nil

        if useMosh {
            moshProcess?.terminate()
            moshProcess = nil
            moshInputPipe = nil
        } else {
            Task {
                try? await client?.close()
                client = nil
            }
        }

        state = .disconnected
        connectedAt = nil
    }

    // MARK: - Private Helpers

    // MARK: - MOSH Connection

    private func connectViaMosh() async throws {
        // Locate the mosh binary
        let moshPaths = ["/opt/homebrew/bin/mosh", "/usr/local/bin/mosh", "/usr/bin/mosh"]
        guard let moshPath = moshPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            state = .error("mosh not found — install via: brew install mosh")
            throw SSHSessionError.connectionFailed("mosh binary not found. Install with: brew install mosh")
        }

        state = .authenticating
        output = ""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: moshPath)

        var args = ["\(username)@\(host)"]
        if port != 22 {
            args.append(contentsOf: ["--ssh=ssh -p \(port)"])
        }
        process.arguments = args

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        self.moshProcess = process
        self.moshInputPipe = inputPipe

        // Read stdout asynchronously
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.output.append(text)
            }
        }

        // Read stderr asynchronously
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.output.append(text)
            }
        }

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.output.append("\r\n[MOSH session ended]\r\n")
                self.moshProcess = nil
                self.moshInputPipe = nil
                if self.state == .connected {
                    self.state = .error("Connection lost")
                }
            }
        }

        do {
            try process.run()
            state = .connected
            connectedAt = .now
        } catch {
            state = .error("Failed to launch mosh: \(error.localizedDescription)")
            throw SSHSessionError.connectionFailed("Failed to launch mosh: \(error.localizedDescription)")
        }
    }

    private func buildAuthenticationMethod() throws -> SSHAuthenticationMethod {
        switch authMethod {
        case "privateKey":
            guard let keyID = privateKeyID else {
                throw SSHSessionError.privateKeyNotFound
            }
            let pem = try KeychainService.loadPrivateKey(for: keyID)
            return try parsePrivateKeyAuth(pem: pem)

        default:
            // "password" and "sshAgent" both fall back to password
            let password = try loadPasswordFromKeychain()
            return .passwordBased(username: username, password: password)
        }
    }

    private func loadPasswordFromKeychain() throws -> String {
        do {
            return try KeychainService.loadPassword(for: serverID)
        } catch {
            throw SSHSessionError.passwordNotFound
        }
    }

    private func parsePrivateKeyAuth(pem: String) throws -> SSHAuthenticationMethod {
        if let ed25519Key = try? Curve25519.Signing.PrivateKey(sshEd25519: pem) {
            return .ed25519(username: username, privateKey: ed25519Key)
        }

        if let rsaKey = try? Insecure.RSA.PrivateKey(sshRsa: pem) {
            return .rsa(username: username, privateKey: rsaKey)
        }

        if let p256Key = try? P256.Signing.PrivateKey(sshP256: pem) {
            return .p256(username: username, privateKey: p256Key)
        }

        throw SSHSessionError.invalidPrivateKey
    }

    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                guard let self, self.isConnected else { break }

                do {
                    _ = try await self.execute("echo 1")
                } catch {
                    await MainActor.run {
                        self.handleDisconnect()
                    }
                    break
                }
            }
        }
    }

    private static func friendlyErrorMessage(for error: Error, authMethod: String) -> String {
        let message = String(describing: error).lowercased()

        if message.contains("authentication") || message.contains("auth") ||
           message.contains("permission denied") || message.contains("userauth") {
            if authMethod == "privateKey" {
                return "Authentication failed — the server rejected your private key"
            }
            return "Invalid username or password — please check your credentials and try again"
        }

        if message.contains("connection refused") || message.contains("connrefused") {
            return "Connection refused — check the host address and port"
        }

        if message.contains("no route to host") || message.contains("host unreachable") ||
           message.contains("network is unreachable") {
            return "Host unreachable — check the address and your network connection"
        }

        if message.contains("name or service not known") || message.contains("nodename nor servname") ||
           message.contains("could not resolve") || message.contains("dns") {
            return "Could not resolve hostname — check the server address"
        }

        if message.contains("timed out") || message.contains("timeout") {
            return "Connection timed out — the server may be offline or unreachable"
        }

        return error.localizedDescription
    }

    private func handleDisconnect() {
        print("[SSH] handleDisconnect called — previous state: \(state)")
        keepaliveTask?.cancel()
        keepaliveTask = nil
        shellTask?.cancel()
        shellTask = nil
        shellWriter = nil
        client = nil
        connectedAt = nil

        if state == .connected {
            state = .error("Connection lost")
        }
    }
}

// MARK: - Citadel Key Parsing Helpers

extension Curve25519.Signing.PrivateKey {
    init(sshEd25519 pem: String) throws {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.contains("BEGIN OPENSSH PRIVATE KEY") else {
            throw SSHSessionError.invalidPrivateKey
        }

        let lines = trimmed.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64String = lines.joined()
        guard let data = Data(base64Encoded: base64String) else {
            throw SSHSessionError.invalidPrivateKey
        }

        guard data.count >= 32 else {
            throw SSHSessionError.invalidPrivateKey
        }

        self = try Curve25519.Signing.PrivateKey(rawRepresentation: data.suffix(32))
    }
}

extension P256.Signing.PrivateKey {
    init(sshP256 pem: String) throws {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("BEGIN") else {
            throw SSHSessionError.invalidPrivateKey
        }

        let lines = trimmed.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64String = lines.joined()
        guard let data = Data(base64Encoded: base64String) else {
            throw SSHSessionError.invalidPrivateKey
        }

        try self.init(derRepresentation: data)
    }
}

// MARK: - Server Stats Engine

@Observable
@MainActor
final class ServerStatsEngine {
    struct Stats {
        var cpuPercent: Double = 0
        var memoryUsedPercent: Double = 0
        var memoryUsed: UInt64 = 0
        var memoryTotal: UInt64 = 0
        var diskMounts: [DiskMount] = []
        var netInterfaces: [NetInterface] = []
        var processes: [ProcessInfo] = []
        var uptime: String = "—"
        var load1m: Double = 0
        var load5m: Double = 0
        var load15m: Double = 0
        var osName: String = ""
        var kernelVersion: String = ""
        var pingMs: Int?
    }

    struct DiskMount: Identifiable {
        var id: String { mountPoint }
        let mountPoint: String
        let size: UInt64
        let used: UInt64
        var usedPercent: Double { size > 0 ? Double(used) / Double(size) * 100 : 0 }
    }

    struct NetInterface: Identifiable {
        var id: String { name }
        let name: String
        var rxMbps: Double = 0
        var txMbps: Double = 0
    }

    struct ProcessInfo: Identifiable {
        var id: String { "\(pid)" }
        let pid: Int
        let command: String
        let cpuPercent: Double
        let memPercent: Double
    }

    private let session: SSHSession
    private(set) var stats: Stats?
    private(set) var isPolling: Bool = false
    private var pollingTask: Task<Void, Never>?
    private var pollInterval: TimeInterval
    private var previousNetStats: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousNetTimestamp: Date?

    init(session: SSHSession, pollInterval: TimeInterval = 3.0) {
        self.session = session
        self.pollInterval = pollInterval
    }

    func startPolling() {
        guard !isPolling else { return }
        isPolling = true

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                guard self.session.isConnected else {
                    self.isPolling = false
                    break
                }
                await self.fetchStats()
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    private func fetchStats() async {
        let combinedCommand = """
        echo "===CPU===" && top -bn1 | grep 'Cpu(s)' 2>/dev/null || echo "N/A" && \
        echo "===MEMORY===" && free -b 2>/dev/null || echo "N/A" && \
        echo "===DISK===" && df -B1 --output=source,size,used,avail,target 2>/dev/null || df -B1 2>/dev/null || echo "N/A" && \
        echo "===NETWORK===" && cat /proc/net/dev 2>/dev/null || echo "N/A" && \
        echo "===UPTIME===" && uptime -p 2>/dev/null || uptime 2>/dev/null || echo "N/A" && \
        echo "===LOAD===" && cat /proc/loadavg 2>/dev/null || echo "N/A" && \
        echo "===PROCESSES===" && ps aux --sort=-%cpu 2>/dev/null | head -11 || echo "N/A" && \
        echo "===END==="
        """

        do {
            let output = try await session.execute(combinedCommand)
            let sections = parseSections(output)

            let cpu = parseCPU(sections["CPU"] ?? "")
            let memory = parseMemory(sections["MEMORY"] ?? "")
            let disk = parseDisk(sections["DISK"] ?? "")
            let network = parseNetwork(sections["NETWORK"] ?? "")
            let uptime = parseUptime(sections["UPTIME"] ?? "")
            let load = parseLoad(sections["LOAD"] ?? "")
            let processes = parseProcesses(sections["PROCESSES"] ?? "")

            stats = Stats(
                cpuPercent: cpu,
                memoryUsedPercent: memory.total > 0 ? Double(memory.used) / Double(memory.total) * 100 : 0,
                memoryUsed: memory.used,
                memoryTotal: memory.total,
                diskMounts: disk,
                netInterfaces: network,
                processes: processes,
                uptime: uptime,
                load1m: load.0,
                load5m: load.1,
                load15m: load.2
            )
        } catch {
            // Silently fail — stats are best-effort
        }
    }

    private func parseSections(_ output: String) -> [String: String] {
        var sections: [String: String] = [:]
        let markers = ["CPU", "MEMORY", "DISK", "NETWORK", "UPTIME", "LOAD", "PROCESSES"]

        for (index, marker) in markers.enumerated() {
            let start = "===\(marker)==="
            let end = index + 1 < markers.count ? "===\(markers[index + 1])===" : "===END==="

            if let startRange = output.range(of: start),
               let endRange = output.range(of: end) {
                let content = String(output[startRange.upperBound..<endRange.lowerBound])
                sections[marker] = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return sections
    }

    private func parseCPU(_ raw: String) -> Double {
        let components = raw.components(separatedBy: ",")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("id") {
                let parts = trimmed.components(separatedBy: .whitespaces)
                if let idle = Double(parts.first ?? "") {
                    return max(0, 100.0 - idle)
                }
            }
        }
        return 0
    }

    private func parseMemory(_ raw: String) -> (total: UInt64, used: UInt64) {
        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            guard line.lowercased().hasPrefix("mem:") else { continue }
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 3 else { continue }
            let total = UInt64(parts[1]) ?? 0
            let used = UInt64(parts[2]) ?? 0
            return (total, used)
        }
        return (0, 0)
    }

    private func parseDisk(_ raw: String) -> [DiskMount] {
        var mounts: [DiskMount] = []
        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 5, !parts[0].hasPrefix("Filesystem") else { continue }
            let fs = parts[0]
            guard fs.hasPrefix("/dev/"), !fs.hasPrefix("/dev/loop") else { continue }
            let size = UInt64(parts[1]) ?? 0
            let used = UInt64(parts[2]) ?? 0
            let mountPoint = parts.last ?? parts[4]
            guard size > 0, !mountPoint.hasPrefix("/snap/") else { continue }
            mounts.append(DiskMount(mountPoint: mountPoint, size: size, used: used))
        }
        return mounts
    }

    private func parseNetwork(_ raw: String) -> [NetInterface] {
        var interfaces: [NetInterface] = []
        let now = Date()
        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            guard line.contains(":") else { continue }
            let split = line.components(separatedBy: ":")
            guard split.count >= 2 else { continue }
            let name = split[0].trimmingCharacters(in: .whitespaces)
            guard name != "lo" else { continue }
            let values = split[1].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard values.count >= 9 else { continue }
            let bytesReceived = UInt64(values[0]) ?? 0
            let bytesSent = UInt64(values[8]) ?? 0

            var rxMbps: Double = 0
            var txMbps: Double = 0
            if let prev = previousNetStats[name], let prevTime = previousNetTimestamp {
                let elapsed = now.timeIntervalSince(prevTime)
                if elapsed > 0 {
                    let rxDelta = bytesReceived > prev.rx ? bytesReceived - prev.rx : 0
                    let txDelta = bytesSent > prev.tx ? bytesSent - prev.tx : 0
                    rxMbps = Double(rxDelta) * 8.0 / elapsed / 1_000_000.0
                    txMbps = Double(txDelta) * 8.0 / elapsed / 1_000_000.0
                }
            }
            previousNetStats[name] = (rx: bytesReceived, tx: bytesSent)
            interfaces.append(NetInterface(name: name, rxMbps: rxMbps, txMbps: txMbps))
        }
        previousNetTimestamp = now
        return interfaces
    }

    private func parseUptime(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("up ") ? String(trimmed.dropFirst(3)) : trimmed
    }

    private func parseLoad(_ raw: String) -> (Double, Double, Double) {
        let parts = raw.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 3 else { return (0, 0, 0) }
        return (Double(parts[0]) ?? 0, Double(parts[1]) ?? 0, Double(parts[2]) ?? 0)
    }

    private func parseProcesses(_ raw: String) -> [ProcessInfo] {
        var processes: [ProcessInfo] = []
        let lines = raw.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            guard index > 0 else { continue }
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 11 else { continue }
            let pid = Int(parts[1]) ?? 0
            let cpu = Double(parts[2]) ?? 0
            let mem = Double(parts[3]) ?? 0
            let command = parts[10...].joined(separator: " ")
            processes.append(ProcessInfo(pid: pid, command: command, cpuPercent: cpu, memPercent: mem))
        }
        return processes
    }
}

// MARK: - Session Manager Error

enum SessionManagerError: LocalizedError {
    case maxSessionsReached

    var errorDescription: String? {
        switch self {
        case .maxSessionsReached:
            "Maximum concurrent sessions reached (8). Close an existing session to connect."
        }
    }
}

// MARK: - SSH Session Manager

@MainActor
class SSHSessionManager: ObservableObject {
    static let maxConcurrentSessions = 8

    @Published private(set) var activeSessions: [UUID: SSHSession] = [:]
    @Published private(set) var statsEngines: [UUID: ServerStatsEngine] = [:]

    var sessionCount: Int { activeSessions.count }

    var connectedSessions: [SSHSession] {
        Array(activeSessions.values.filter(\.isConnected))
    }

    var hasCapacity: Bool {
        activeSessions.count < Self.maxConcurrentSessions
    }

    // MARK: - Session Lifecycle

    @discardableResult
    func openSession(for server: Server) async throws -> SSHSession {
        if let existing = activeSessions[server.id], existing.isConnected {
            return existing
        }

        // Clean up stale session for this server
        if let stale = activeSessions[server.id] {
            stale.disconnect()
            activeSessions.removeValue(forKey: server.id)
            statsEngines[server.id]?.stopPolling()
            statsEngines.removeValue(forKey: server.id)
        }

        // Prune all disconnected sessions to free capacity
        pruneDisconnectedSessions()

        guard hasCapacity else {
            throw SessionManagerError.maxSessionsReached
        }

        let session = SSHSession(
            serverID: server.id,
            host: server.host,
            port: server.port,
            username: server.username,
            authMethod: server.authMethod,
            privateKeyID: server.privateKeyID,
            useMosh: server.useMosh
        )

        activeSessions[server.id] = session

        do {
            try await session.connect()
            return session
        } catch {
            activeSessions.removeValue(forKey: server.id)
            throw error
        }
    }

    func closeSession(serverID: UUID) {
        statsEngines[serverID]?.stopPolling()
        statsEngines.removeValue(forKey: serverID)
        activeSessions[serverID]?.disconnect()
        activeSessions.removeValue(forKey: serverID)
    }

    func activeSession(for serverID: UUID) -> SSHSession? {
        activeSessions[serverID]
    }

    func statsEngine(for serverID: UUID) -> ServerStatsEngine? {
        if let engine = statsEngines[serverID] { return engine }
        guard let session = activeSessions[serverID], session.isConnected else { return nil }
        let engine = ServerStatsEngine(session: session)
        statsEngines[serverID] = engine
        engine.startPolling()
        return engine
    }

    func closeAllSessions() {
        for engine in statsEngines.values { engine.stopPolling() }
        statsEngines.removeAll()
        for session in activeSessions.values { session.disconnect() }
        activeSessions.removeAll()
    }

    func pruneDisconnectedSessions() {
        let stale = activeSessions.filter { !$0.value.isConnected }
        for (id, session) in stale {
            session.disconnect()
            activeSessions.removeValue(forKey: id)
        }
    }
}
