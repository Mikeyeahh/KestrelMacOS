//
//  ServerImportService.swift
//  Kestrel Mac
//
//  Parses SSH connection exports from MobaXterm, Termius, iTerm2,
//  mRemoteNG, ~/.ssh/config, and Kestrel's own JSON format into Server models.
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Import Source

enum ImportSource: String, CaseIterable, Identifiable {
    case mobaXterm = "MobaXterm"
    case termius = "Termius"
    case iTerm2 = "iTerm2"
    case mRemoteNG = "mRemoteNG"
    case sshConfig = "SSH Config"
    case kestrelJSON = "Kestrel JSON"

    var id: String { rawValue }

    var fileLabel: String {
        switch self {
        case .mobaXterm:  "MobaXterm Sessions (.mxtsessions)"
        case .termius:    "Termius CSV Export (.csv)"
        case .iTerm2:     "iTerm2 Profiles (.json / .plist)"
        case .mRemoteNG:  "mRemoteNG Connections (.xml)"
        case .sshConfig:  "SSH Config File (config)"
        case .kestrelJSON: "Kestrel Export (.json)"
        }
    }

    var icon: String {
        switch self {
        case .mobaXterm:  "rectangle.stack"
        case .termius:    "tablecells"
        case .iTerm2:     "terminal"
        case .mRemoteNG:  "network"
        case .sshConfig:  "doc.text"
        case .kestrelJSON: "bird"
        }
    }

    var allowedTypes: [UTType] {
        switch self {
        case .mobaXterm:  [.data, .plainText]
        case .termius:    [.commaSeparatedText, .plainText]
        case .iTerm2:     [.json, .propertyList, .data]
        case .mRemoteNG:  [.xml, .data]
        case .sshConfig:  [.data, .plainText]
        case .kestrelJSON: [.json]
        }
    }
}

// MARK: - Import Result

struct ImportResult {
    var servers: [Server]
    var warnings: [String]
    var skippedCount: Int
}

// MARK: - Import Service

enum ServerImportService {

    static func parse(source: ImportSource, data: Data) throws -> ImportResult {
        switch source {
        case .kestrelJSON: return try parseKestrelJSON(data)
        case .iTerm2:      return try parseITerm2(data)
        case .mRemoteNG:   return try parseMRemoteNG(data)
        default: break
        }

        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252) else {
            throw ImportError.unreadableFile
        }

        switch source {
        case .mobaXterm:  return parseMobaXterm(text)
        case .termius:    return parseTermiusCSV(text)
        case .sshConfig:  return parseSSHConfig(text)
        default:          throw ImportError.invalidFormat
        }
    }

    // MARK: - MobaXterm (.mxtsessions)

    private static func parseMobaXterm(_ text: String) -> ImportResult {
        var servers: [Server] = []
        var warnings: [String] = []
        var skipped = 0
        var currentFolder: String?

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Section headers like [Bookmarks] or [Bookmarks_1]
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentFolder = nil
                continue
            }

            // SubRep= defines the folder name for the current section
            if trimmed.hasPrefix("SubRep=") {
                let folderName = trimmed.replacingOccurrences(of: "SubRep=", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentFolder = folderName.isEmpty ? nil : folderName
                continue
            }

            // ImgNum= lines — skip
            if trimmed.hasPrefix("ImgNum=") { continue }

            // Session lines: Name= #icon#fields#terminal#...
            guard let equalsRange = trimmed.range(of: "=") else { continue }
            let sessionName = String(trimmed[trimmed.startIndex..<equalsRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[equalsRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)

            guard !sessionName.isEmpty, !value.isEmpty else { continue }

            // Split by # to get major groups
            let groups = value.components(separatedBy: "#")
            // groups[0] is empty (before first #), groups[1] is icon, groups[2] is connection fields
            guard groups.count >= 3 else {
                skipped += 1
                continue
            }

            let connectionFields = groups[2].components(separatedBy: "%")

            // Field 0 = session type. 0 = SSH, 7 = SFTP
            guard let sessionType = connectionFields.first,
                  sessionType == "0" || sessionType == "7" else {
                skipped += 1
                continue
            }

            let host = mobaUnescape(connectionFields[safe: 1] ?? "")
            guard !host.isEmpty else {
                skipped += 1
                continue
            }

            let port = Int(connectionFields[safe: 2] ?? "") ?? 22
            let username = mobaUnescape(connectionFields[safe: 3] ?? "")
            let hasPrivateKey = !(connectionFields[safe: 14] ?? "").isEmpty
            let authMethod = hasPrivateKey ? "privateKey" : "password"

            if username.isEmpty {
                warnings.append("\(sessionName): no username specified")
            }

            let server = Server(
                name: sessionName,
                host: host,
                port: port,
                username: username,
                authMethod: authMethod,
                group: currentFolder,
                environment: "other",
                colour: "#00FF41",
                tags: ["imported", "mobaxterm"],
                orderIndex: servers.count
            )
            servers.append(server)
        }

        return ImportResult(servers: servers, warnings: warnings, skippedCount: skipped)
    }

    private static func mobaUnescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "__PTVIRG__", with: ";")
            .replacingOccurrences(of: "__DBLQUO__", with: "\"")
            .replacingOccurrences(of: "__PIPE__", with: "|")
            .replacingOccurrences(of: "__DIEZE__", with: "#")
            .replacingOccurrences(of: "__PERCENT__", with: "%")
    }

    // MARK: - Termius CSV

    private static func parseTermiusCSV(_ text: String) -> ImportResult {
        var servers: [Server] = []
        var warnings: [String] = []
        var skipped = 0

        let rows = parseCSVRows(text)
        guard rows.count > 1 else {
            return ImportResult(servers: [], warnings: ["File appears empty or has no data rows"], skippedCount: 0)
        }

        // Normalise header names to lowercase for flexible matching
        let header = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        let iGroup    = header.firstIndex(of: "groups")     ?? header.firstIndex(of: "group")
        let iLabel    = header.firstIndex(of: "label")      ?? header.firstIndex(of: "name")
        let iTags     = header.firstIndex(of: "tags")
        let iHost     = header.firstIndex(of: "hostname/ip") ?? header.firstIndex(of: "hostname") ?? header.firstIndex(of: "host") ?? header.firstIndex(of: "ip")
        let iProtocol = header.firstIndex(of: "protocol")
        let iPort     = header.firstIndex(of: "port")
        let iUsername = header.firstIndex(of: "username")    ?? header.firstIndex(of: "user")
        let iSSHKey   = header.firstIndex(of: "ssh_key")    ?? header.firstIndex(of: "sshkey") ?? header.firstIndex(of: "key")

        guard let hostIdx = iHost else {
            return ImportResult(servers: [], warnings: ["Could not find a hostname column in the CSV header"], skippedCount: 0)
        }

        for row in rows.dropFirst() {
            guard row.count > hostIdx else { skipped += 1; continue }

            let host = row[hostIdx].trimmingCharacters(in: .whitespaces)
            guard !host.isEmpty else { skipped += 1; continue }

            // Skip non-SSH protocols if a protocol column exists
            if let pi = iProtocol {
                let proto = row[safe: pi]?.lowercased().trimmingCharacters(in: .whitespaces) ?? "ssh"
                if !proto.isEmpty && proto != "ssh" && proto != "sftp" {
                    skipped += 1
                    continue
                }
            }

            let label = row[safe: iLabel ?? -1]?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = label.isEmpty ? host : label
            let port = Int(row[safe: iPort ?? -1]?.trimmingCharacters(in: .whitespaces) ?? "") ?? 22
            let username = row[safe: iUsername ?? -1]?.trimmingCharacters(in: .whitespaces) ?? ""
            let group = row[safe: iGroup ?? -1]?.trimmingCharacters(in: .whitespaces)
            let hasKey = !(row[safe: iSSHKey ?? -1]?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty
            let authMethod = hasKey ? "privateKey" : "password"

            var tags = ["imported", "termius"]
            if let ti = iTags, let tagStr = row[safe: ti]?.trimmingCharacters(in: .whitespaces), !tagStr.isEmpty {
                tags.append(contentsOf: tagStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            }

            if username.isEmpty {
                warnings.append("\(name): no username specified")
            }

            let server = Server(
                name: name,
                host: host,
                port: port,
                username: username,
                authMethod: authMethod,
                group: group?.isEmpty == true ? nil : group,
                environment: "other",
                colour: "#00FF41",
                tags: tags,
                orderIndex: servers.count
            )
            servers.append(server)
        }

        return ImportResult(servers: servers, warnings: warnings, skippedCount: skipped)
    }

    /// Basic RFC 4180 CSV parser that handles quoted fields.
    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        for char in text {
            if inQuotes {
                if char == "\"" {
                    // Peek-ahead handled by state: next char decides
                    inQuotes = false
                } else {
                    currentField.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\r":
                    break // ignore CR
                case "\n":
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                default:
                    currentField.append(char)
                }
            }
        }

        // Flush last row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }

        return rows
    }

    // MARK: - SSH Config

    private static func parseSSHConfig(_ text: String) -> ImportResult {
        var servers: [Server] = []
        var warnings: [String] = []

        struct SSHHost {
            var name: String = ""
            var hostName: String = ""
            var port: Int = 22
            var user: String = ""
            var identityFile: String = ""
        }

        var current: SSHHost?

        func flush(_ h: SSHHost) {
            let host = h.hostName.isEmpty ? h.name : h.hostName
            guard !host.isEmpty, !host.contains("*"), !host.contains("?") else { return }

            let name = h.name.isEmpty ? host : h.name
            let hasKey = !h.identityFile.isEmpty
            if h.user.isEmpty {
                warnings.append("\(name): no User specified")
            }

            servers.append(Server(
                name: name,
                host: host,
                port: h.port,
                username: h.user,
                authMethod: hasKey ? "privateKey" : "password",
                environment: "other",
                colour: "#00FF41",
                tags: ["imported", "ssh-config"],
                orderIndex: servers.count
            ))
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            if key == "host" {
                if let c = current { flush(c) }
                current = SSHHost(name: value)
            } else if var c = current {
                switch key {
                case "hostname":     c.hostName = value
                case "port":         c.port = Int(value) ?? 22
                case "user":         c.user = value
                case "identityfile": c.identityFile = value
                default: break
                }
                current = c
            }
        }
        if let c = current { flush(c) }

        return ImportResult(servers: servers, warnings: warnings, skippedCount: 0)
    }

    // MARK: - iTerm2 (JSON / plist profiles)

    private static func parseITerm2(_ data: Data) throws -> ImportResult {
        var servers: [Server] = []
        var warnings: [String] = []
        var skipped = 0

        // Extract the profiles array from either JSON or plist
        let profiles: [[String: Any]]
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let p = json["Profiles"] as? [[String: Any]] {
            profiles = p
        } else if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            // Bare array of profiles
            profiles = json
        } else if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let p = (plist["New Bookmarks"] ?? plist["Profiles"]) as? [[String: Any]] {
            profiles = p
        } else {
            throw ImportError.invalidFormat
        }

        for profile in profiles {
            let name = profile["Name"] as? String ?? ""
            let customCommand = profile["Custom Command"] as? String ?? "No"
            let command = profile["Command"] as? String ?? ""

            // Only import profiles that run an SSH command
            guard customCommand == "Yes", !command.isEmpty else {
                skipped += 1
                continue
            }

            let (host, port, username) = parseSSHCommand(command)
            guard !host.isEmpty else {
                skipped += 1
                continue
            }

            // Build tags from iTerm2's Tags array (slashes denote hierarchy)
            var tags = ["imported", "iterm2"]
            var group: String?
            if let iTags = profile["Tags"] as? [String] {
                for tag in iTags {
                    // Use the first tag path component as a group name
                    let parts = tag.components(separatedBy: "/")
                    if group == nil, let first = parts.first, !first.isEmpty {
                        group = first
                    }
                    tags.append(contentsOf: parts)
                }
            }

            if username.isEmpty {
                warnings.append("\(name.isEmpty ? host : name): no username in ssh command")
            }

            let server = Server(
                name: name.isEmpty ? host : name,
                host: host,
                port: port,
                username: username,
                authMethod: "password",
                group: group,
                environment: "other",
                colour: "#00FF41",
                tags: tags,
                orderIndex: servers.count
            )
            servers.append(server)
        }

        return ImportResult(servers: servers, warnings: warnings, skippedCount: skipped)
    }

    /// Extracts host, port, and username from an ssh command string.
    /// Handles patterns like: `ssh user@host`, `ssh -p 2222 user@host`, `ssh host -l user -p 22`
    private static func parseSSHCommand(_ command: String) -> (host: String, port: Int, username: String) {
        let tokens = command.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        var host = ""
        var port = 22
        var username = ""
        var skipNext = false

        for (i, token) in tokens.enumerated() {
            if skipNext { skipNext = false; continue }

            // Skip the "ssh" binary itself
            if i == 0 && token.lowercased().hasSuffix("ssh") { continue }

            if token == "-p", i + 1 < tokens.count {
                port = Int(tokens[i + 1]) ?? 22
                skipNext = true
            } else if token == "-l", i + 1 < tokens.count {
                username = tokens[i + 1]
                skipNext = true
            } else if token.hasPrefix("-") {
                // Other flags — skip (and skip their argument if it's a known flag+value pair)
                let valuedFlags: Set<String> = ["-i", "-o", "-F", "-J", "-L", "-R", "-D", "-W", "-b", "-c", "-e", "-m", "-S"]
                if valuedFlags.contains(token) { skipNext = true }
            } else if token.contains("@") {
                let parts = token.split(separator: "@", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    username = parts[0]
                    host = parts[1]
                }
            } else if host.isEmpty {
                host = token
            }
        }

        return (host, port, username)
    }

    // MARK: - mRemoteNG (XML)

    private static func parseMRemoteNG(_ data: Data) throws -> ImportResult {
        let parser = MRemoteNGParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { throw ImportError.invalidFormat }

        if parser.servers.isEmpty && parser.skipped == 0 {
            throw ImportError.invalidFormat
        }

        return ImportResult(servers: parser.servers, warnings: parser.warnings, skippedCount: parser.skipped)
    }

    // MARK: - Kestrel JSON

    private static func parseKestrelJSON(_ data: Data) throws -> ImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try decoding as an array of Server directly
        if let servers = try? decoder.decode([Server].self, from: data) {
            let reIDed = servers.map { s in
                Server(
                    name: s.name, host: s.host, port: s.port,
                    username: s.username, authMethod: s.authMethod,
                    group: s.group, environment: s.environment,
                    colour: s.colour, tags: s.tags,
                    orderIndex: s.orderIndex, notes: s.notes
                )
            }
            return ImportResult(servers: reIDed, warnings: [], skippedCount: 0)
        }

        // Try as a wrapper object with a "servers" key
        if let wrapper = try? decoder.decode([String: [Server]].self, from: data),
           let servers = wrapper["servers"] {
            let reIDed = servers.map { s in
                Server(
                    name: s.name, host: s.host, port: s.port,
                    username: s.username, authMethod: s.authMethod,
                    group: s.group, environment: s.environment,
                    colour: s.colour, tags: s.tags,
                    orderIndex: s.orderIndex, notes: s.notes
                )
            }
            return ImportResult(servers: reIDed, warnings: [], skippedCount: 0)
        }

        throw ImportError.invalidFormat
    }
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case unreadableFile
    case invalidFormat
    case noServersFound

    var errorDescription: String? {
        switch self {
        case .unreadableFile: "Could not read the file. Check encoding."
        case .invalidFormat:  "File format not recognised."
        case .noServersFound: "No servers found in the file."
        }
    }
}

// MARK: - mRemoteNG XML Parser Delegate

private class MRemoteNGParser: NSObject, XMLParserDelegate {
    var servers: [Server] = []
    var warnings: [String] = []
    var skipped = 0

    private var containerStack: [String] = []
    /// Tracks which depth levels are containers so we know when to pop.
    private var containerDepths: Set<Int> = []
    private var depth = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        depth += 1
        guard elementName == "Node" else { return }

        let nodeType = attributes["Type"] ?? ""
        let name = attributes["Name"] ?? ""

        if nodeType == "Container" {
            containerStack.append(name)
            containerDepths.insert(depth)
            return
        }

        guard nodeType == "Connection" else { return }

        let proto = attributes["Protocol"] ?? ""
        guard proto == "SSH2" || proto == "SSH1" else {
            skipped += 1
            return
        }

        let host = attributes["Hostname"] ?? ""
        guard !host.isEmpty else {
            skipped += 1
            return
        }

        let port = Int(attributes["Port"] ?? "") ?? 22
        let username = attributes["Username"] ?? ""
        let group = containerStack.last

        if username.isEmpty {
            warnings.append("\(name.isEmpty ? host : name): no username specified")
        }

        let server = Server(
            name: name.isEmpty ? host : name,
            host: host,
            port: port,
            username: username,
            authMethod: "password",
            group: group,
            environment: "other",
            colour: "#00FF41",
            tags: ["imported", "mremoteng"],
            orderIndex: servers.count,
            notes: attributes["Descr"]?.isEmpty == false ? attributes["Descr"] : nil
        )
        servers.append(server)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if elementName == "Node" && containerDepths.contains(depth) {
            containerDepths.remove(depth)
            containerStack.removeLast()
        }
        depth -= 1
    }
}

// MARK: - Safe Collection Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
