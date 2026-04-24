//
//  SFTPSession.swift
//  Kestrel Mac
//
//  Stub SFTP session — replace with shared Core/Networking/SFTP/SFTPSession.swift from iOS target.
//

import Foundation

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
         modified: Date? = nil, permissions: String = "-rw-r--r--", owner: String = "root") {
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
class SFTPSession: ObservableObject {
    let serverID: UUID
    let serverName: String

    @Published private(set) var isConnected = false
    @Published private(set) var currentPath: String = "/"
    @Published private(set) var items: [SFTPFileItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var pathHistory: [String] = ["/"]

    init(serverID: UUID, serverName: String) {
        self.serverID = serverID
        self.serverName = serverName
    }

    func connect(server: Server) async throws {
        isLoading = true
        error = nil
        // TODO: integrate real SFTP connection via Citadel
        isConnected = true
        currentPath = "/home/\(server.username)"
        pathHistory = [currentPath]
        items = []
        isLoading = false
    }

    func navigateTo(_ path: String) async throws {
        isLoading = true
        error = nil
        // TODO: list remote directory via SFTP
        currentPath = path
        if pathHistory.last != path { pathHistory.append(path) }
        items = []
        isLoading = false
    }

    func navigateUp() async throws {
        let parent = (currentPath as NSString).deletingLastPathComponent
        try await navigateTo(parent.isEmpty ? "/" : parent)
    }

    func goBack() async throws {
        guard pathHistory.count > 1 else { return }
        pathHistory.removeLast()
        if let prev = pathHistory.last {
            try await navigateTo(prev)
        }
    }

    func refresh() async throws {
        try await navigateTo(currentPath)
    }

    func readFile(at path: String) async throws -> Data {
        // TODO: read file via SFTP
        return Data()
    }

    func writeFile(at path: String, data: Data) async throws {
        // TODO: write file via SFTP
    }

    func deleteItem(at path: String, isDirectory: Bool) async throws {
        // TODO: delete item via SFTP
        try await refresh()
    }

    func createDirectory(named name: String) async throws {
        // TODO: create directory via SFTP
        try await refresh()
    }

    func rename(at path: String, to newName: String) async throws {
        // TODO: rename via SFTP
        try await refresh()
    }

    func uploadFile(localURL: URL, remotePath: String, progress: @escaping (Double) -> Void) async throws {
        // TODO: upload file via SFTP with progress
        progress(1.0)
        try await refresh()
    }

    func downloadFile(remotePath: String, localURL: URL, progress: @escaping (Double) -> Void) async throws {
        // TODO: download file via SFTP with progress
        progress(1.0)
    }

    // TODO: Scaffold for cross-server transfer
    // func transfer(from sourcePath: String, to destination: SFTPSession, destinationPath: String) async throws {
    //     let data = try await readFile(at: sourcePath)
    //     try await destination.writeFile(at: destinationPath, data: data)
    // }

    func disconnect() {
        isConnected = false
        items = []
        currentPath = "/"
        pathHistory = ["/"]
    }
}
