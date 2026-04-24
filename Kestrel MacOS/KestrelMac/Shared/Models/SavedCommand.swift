//
//  SavedCommand.swift
//  Kestrel Mac
//
//  Stub model — replace with shared Core/Models/SavedCommand.swift from iOS target.
//

import SwiftUI

// MARK: - Command Category

enum CommandCategory: String, Codable, CaseIterable {
    case system, networking, docker, kubernetes, git, nginx, files, custom

    var icon: String {
        switch self {
        case .system: "cpu"
        case .networking: "network"
        case .docker: "shippingbox"
        case .kubernetes: "helm"
        case .git: "point.3.connected.trianglepath.dotted"
        case .nginx: "server.rack"
        case .files: "folder"
        case .custom: "terminal"
        }
    }

    var displayName: String {
        switch self {
        case .system: "System"
        case .networking: "Network"
        case .docker: "Docker"
        case .kubernetes: "K8s"
        case .git: "Git"
        case .nginx: "Nginx"
        case .files: "Files"
        case .custom: "Custom"
        }
    }

    var color: Color {
        switch self {
        case .system: KestrelColors.blue
        case .networking: KestrelColors.phosphorGreen
        case .docker: KestrelColors.blue
        case .kubernetes: KestrelColors.blue
        case .git: KestrelColors.amber
        case .nginx: KestrelColors.phosphorGreen
        case .files: KestrelColors.amber
        case .custom: .purple
        }
    }
}

// MARK: - Saved Command

class SavedCommand: Identifiable, ObservableObject, Hashable {
    static func == (lhs: SavedCommand, rhs: SavedCommand) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: UUID
    @Published var name: String
    @Published var command: String
    @Published var category: CommandCategory
    @Published var commandDescription: String?
    @Published var isFavourite: Bool
    @Published var useCount: Int
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        category: CommandCategory = .custom,
        commandDescription: String? = nil,
        isFavourite: Bool = false,
        useCount: Int = 0,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.category = category
        self.commandDescription = commandDescription
        self.isFavourite = isFavourite
        self.useCount = useCount
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Command Variable Parser

enum CommandVariableParser {
    static func extractVariables(from command: String) -> [String] {
        let pattern = #"\{([a-zA-Z_][a-zA-Z0-9_]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(command.startIndex..., in: command)
        let matches = regex.matches(in: command, range: range)
        var seen = Set<String>()
        var result: [String] = []
        for match in matches {
            if let varRange = Range(match.range(at: 1), in: command) {
                let name = String(command[varRange])
                if !seen.contains(name) { seen.insert(name); result.append(name) }
            }
        }
        return result
    }

    static func resolve(command: String, variables: [String: String]) -> String {
        var result = command
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    static func displayName(for variable: String) -> String {
        variable.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Command Repository (stub)

@MainActor
class CommandRepository: ObservableObject {
    @Published var commands: [SavedCommand] = []

    func addCommand(_ cmd: SavedCommand) { commands.append(cmd) }

    func deleteCommand(_ cmd: SavedCommand) {
        commands.removeAll { $0.id == cmd.id }
    }

    func duplicate(_ cmd: SavedCommand) {
        let dupe = SavedCommand(
            name: "\(cmd.name) (copy)",
            command: cmd.command,
            category: cmd.category,
            commandDescription: cmd.commandDescription
        )
        commands.append(dupe)
    }
}
