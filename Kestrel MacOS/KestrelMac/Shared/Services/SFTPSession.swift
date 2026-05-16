//
//  SFTPSession.swift
//  Kestrel Mac
//
//  SFTP session wrapper around Citadel's SFTPClient. Adapted from the iOS
//  Core/Networking/SFTP implementation; uses the Mac target's `Server`
//  model and `KeychainService`.
//

import Foundation
import Citadel
import Crypto
import _CryptoExtras
import NIO
import NIOFoundationCompat
import NIOSSH

// MARK: - SFTP File Item

struct SFTPFileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modified: Date?
    let permissions: String
    let owner: String

    init(name: String, path: String, isDirectory: Bool, size: UInt64 = 0,
         modified: Date? = nil, permissions: String = "-rw-r--r--", owner: String = "") {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.permissions = permissions
        self.owner = owner
    }

    var icon: String {
        if isDirectory { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md", "log", "csv":     return "doc.text.fill"
        case "json", "xml", "yaml", "yml":  return "curlybraces"
        case "swift", "py", "js", "ts",
             "go", "rs", "rb", "sh", "bash": return "chevron.left.forwardslash.chevron.right"
        case "conf", "cfg", "ini", "env",
             "toml":                          return "gearshape.fill"
        case "jpg", "jpeg", "png", "gif",
             "svg", "webp":                   return "photo.fill"
        case "zip", "tar", "gz", "bz2",
             "xz", "7z":                      return "archivebox.fill"
        default:                              return "doc.fill"
        }
    }

    var formattedSize: String {
        if isDirectory { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    var isTextFile: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["txt", "md", "log", "csv", "json", "xml", "yaml", "yml",
                "swift", "py", "js", "ts", "go", "rs", "rb", "sh", "bash",
                "conf", "cfg", "ini", "env", "toml", "html", "css"].contains(ext)
    }

    var syntaxLanguage: String? {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "sh", "bash": return "shell"
        case "py": return "python"
        case "conf", "cfg", "ini", "env": return "conf"
        case "md": return "markdown"
        case "log": return "log"
        default: return nil
        }
    }
}

// MARK: - SFTP Session

@MainActor
final class SFTPSession: ObservableObject {
    let serverID: UUID
    let serverName: String

    @Published private(set) var isConnected = false
    @Published private(set) var currentPath: String = "/"
    @Published private(set) var items: [SFTPFileItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var pathHistory: [String] = ["/"]

    private var sshClient: SSHClient?
    private var sftpClient: SFTPClient?

    init(serverID: UUID, serverName: String) {
        self.serverID = serverID
        self.serverName = serverName
    }

    // MARK: - Connect

    func connect(server: Server) async throws {
        isLoading = true
        error = nil

        do {
            let auth = try buildAuth(server: server)

            let client = try await SSHClient.connect(
                host: server.host,
                port: server.port,
                authenticationMethod: auth,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                algorithms: .all
            )

            self.sshClient = client
            self.sftpClient = try await client.openSFTP()
            self.isConnected = true
            self.currentPath = "/"
            self.pathHistory = ["/"]

            // Try to start in home directory; fall back to "/".
            if let resolved = try? await resolveHome(),
               let homeItems = try? await listDirectory(resolved) {
                currentPath = resolved
                pathHistory = [resolved]
                items = homeItems
            } else {
                try await navigateTo("/")
            }

            isLoading = false
        } catch {
            isLoading = false
            self.error = error.localizedDescription
            throw error
        }
    }

    // MARK: - Navigation

    func navigateTo(_ path: String) async throws {
        isLoading = true
        error = nil

        do {
            let listing = try await listDirectory(path)
            currentPath = path
            items = listing
            if pathHistory.last != path {
                pathHistory.append(path)
            }
            isLoading = false
        } catch {
            isLoading = false
            self.error = "Failed to list directory: \(error.localizedDescription)"
            throw error
        }
    }

    func navigateUp() async throws {
        let parent = (currentPath as NSString).deletingLastPathComponent
        let target = parent.isEmpty ? "/" : parent
        try await navigateTo(target)
    }

    func goBack() async throws {
        guard pathHistory.count > 1 else { return }
        pathHistory.removeLast()
        if let previous = pathHistory.last {
            isLoading = true
            error = nil
            do {
                let listing = try await listDirectory(previous)
                currentPath = previous
                items = listing
                isLoading = false
            } catch {
                isLoading = false
                self.error = "Failed to navigate back: \(error.localizedDescription)"
                throw error
            }
        }
    }

    func refresh() async throws {
        try await navigateTo(currentPath)
    }

    // MARK: - File Operations

    func readFile(at path: String) async throws -> Data {
        guard let sftp = sftpClient else { throw SSHSessionError.notConnected }
        let file = try await sftp.openFile(filePath: path, flags: .read)
        let buffer = try await file.readAll()
        try await file.close()
        return Data(buffer: buffer)
    }

    func writeFile(at path: String, data: Data) async throws {
        guard let sftp = sftpClient else { throw SSHSessionError.notConnected }
        let file = try await sftp.openFile(
            filePath: path,
            flags: [.write, .create, .truncate]
        )
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        try await file.write(buffer, at: 0)
        try await file.close()
    }

    func deleteItem(at path: String, isDirectory: Bool) async throws {
        guard let sftp = sftpClient else { throw SSHSessionError.notConnected }
        if isDirectory {
            try await sftp.rmdir(at: path)
        } else {
            try await sftp.remove(at: path)
        }
        try await refresh()
    }

    func createDirectory(named name: String) async throws {
        guard let sftp = sftpClient else { throw SSHSessionError.notConnected }
        let newPath = (currentPath as NSString).appendingPathComponent(name)
        try await sftp.createDirectory(atPath: newPath)
        try await refresh()
    }

    func rename(at path: String, to newName: String) async throws {
        guard let sftp = sftpClient else { throw SSHSessionError.notConnected }
        let parent = (path as NSString).deletingLastPathComponent
        let newPath = (parent as NSString).appendingPathComponent(newName)
        try await sftp.rename(at: path, to: newPath)
        try await refresh()
    }

    func uploadFile(localURL: URL, remotePath: String, progress: @escaping (Double) -> Void) async throws {
        progress(0)
        let data = try Data(contentsOf: localURL)
        try await writeFile(at: remotePath, data: data)
        progress(1.0)
        try await refresh()
    }

    func downloadFile(remotePath: String, localURL: URL, progress: @escaping (Double) -> Void) async throws {
        progress(0)
        let data = try await readFile(at: remotePath)
        try data.write(to: localURL, options: .atomic)
        progress(1.0)
    }

    // MARK: - Disconnect

    func disconnect() {
        Task { [sftpClient, sshClient] in
            try? await sftpClient?.close()
            try? await sshClient?.close()
        }
        sftpClient = nil
        sshClient = nil
        isConnected = false
        items = []
        currentPath = "/"
        pathHistory = ["/"]
    }

    // MARK: - Private

    private func listDirectory(_ path: String) async throws -> [SFTPFileItem] {
        guard let sftp = sftpClient else { throw SSHSessionError.notConnected }

        let listing = try await sftp.listDirectory(atPath: path)
        var fileItems: [SFTPFileItem] = []

        for nameMessage in listing {
            for component in nameMessage.components {
                let name = component.filename
                guard name != "." && name != ".." else { continue }

                let rawPerms = component.attributes.permissions ?? 0
                let isDir = (rawPerms & 0o40000) != 0
                let size = component.attributes.size ?? 0
                let modified = component.attributes.accessModificationTime?.modificationTime
                let fullPath = (path as NSString).appendingPathComponent(name)
                let perms = formatPermissions(rawPerms, isDirectory: isDir)

                fileItems.append(SFTPFileItem(
                    name: name,
                    path: fullPath,
                    isDirectory: isDir,
                    size: size,
                    modified: modified,
                    permissions: perms,
                    owner: ""
                ))
            }
        }

        return fileItems.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func formatPermissions(_ mode: UInt32, isDirectory: Bool) -> String {
        var s = isDirectory ? "d" : "-"
        s += (mode & 0o400) != 0 ? "r" : "-"
        s += (mode & 0o200) != 0 ? "w" : "-"
        s += (mode & 0o100) != 0 ? "x" : "-"
        s += (mode & 0o040) != 0 ? "r" : "-"
        s += (mode & 0o020) != 0 ? "w" : "-"
        s += (mode & 0o010) != 0 ? "x" : "-"
        s += (mode & 0o004) != 0 ? "r" : "-"
        s += (mode & 0o002) != 0 ? "w" : "-"
        s += (mode & 0o001) != 0 ? "x" : "-"
        return s
    }

    private func resolveHome() async throws -> String? {
        guard let ssh = sshClient else { return nil }
        let buffer = try await ssh.executeCommand("echo $HOME", mergeStreams: true)
        let home = String(buffer: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return home.isEmpty ? nil : home
    }

    private func buildAuth(server: Server) throws -> SSHAuthenticationMethod {
        switch server.authMethod {
        case "privateKey":
            guard let keyID = server.privateKeyID else {
                throw SSHSessionError.privateKeyNotFound
            }
            let pem = try KeychainService.loadPrivateKey(for: keyID)
            if let ed25519Key = try? Curve25519.Signing.PrivateKey(sshEd25519: pem) {
                return .ed25519(username: server.username, privateKey: ed25519Key)
            }
            if let rsaKey = try? Insecure.RSA.PrivateKey(sshRsa: pem) {
                return .rsa(username: server.username, privateKey: rsaKey)
            }
            if let p256Key = try? P256.Signing.PrivateKey(sshP256: pem) {
                return .p256(username: server.username, privateKey: p256Key)
            }
            throw SSHSessionError.invalidPrivateKey

        default:
            // "password" and "sshAgent" both fall back to keychain password.
            let password = try KeychainService.loadPassword(for: server.id)
            return .passwordBased(username: server.username, password: password)
        }
    }
}
