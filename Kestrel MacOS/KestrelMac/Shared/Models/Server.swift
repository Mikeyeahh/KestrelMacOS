//
//  Server.swift
//  Kestrel Mac
//
//  Codable model matching the Supabase "servers" table.
//  Must stay aligned with the iOS SyncableServer schema so both
//  platforms can decode rows inserted by the other.
//

import SwiftUI

// MARK: - Server

struct Server: Identifiable, Hashable, Codable {
    let id: UUID
    var userId: UUID?
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: String
    var privateKeyID: UUID?
    var group: String?
    var environment: String
    var colour: String
    var tags: [String]
    var orderIndex: Int
    var notes: String?
    var updatedAt: Date?
    var connectionType: String
    var useMosh: Bool
    var vncPort: Int?
    var rdpPort: Int?

    // Runtime-only properties — NOT encoded/decoded from Supabase
    var status: ServerStatus = .offline
    var cpuUsage: Double = 0
    var os: String = "Linux"
    var isConnected: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name, host, port, username
        case authMethod = "auth_method"
        case privateKeyID = "private_key_id"
        case group, environment, colour, tags
        case orderIndex = "order_index"
        case notes
        case updatedAt = "updated_at"
        case connectionType = "connection_type"
        case useMosh = "use_mosh"
        case vncPort = "vnc_port"
        case rdpPort = "rdp_port"
    }

    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        authMethod: String = "password",
        privateKeyID: UUID? = nil,
        group: String? = nil,
        environment: String = "other",
        colour: String = "#00FF41",
        status: ServerStatus = .offline,
        cpuUsage: Double = 0,
        os: String = "Linux",
        isConnected: Bool = false,
        tags: [String] = [],
        orderIndex: Int = 0,
        notes: String? = nil,
        updatedAt: Date? = nil,
        connectionType: String = "ssh",
        useMosh: Bool = false,
        vncPort: Int? = nil,
        rdpPort: Int? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.privateKeyID = privateKeyID
        self.group = group
        self.environment = environment
        self.colour = colour
        self.status = status
        self.cpuUsage = cpuUsage
        self.os = os
        self.isConnected = isConnected
        self.tags = tags
        self.orderIndex = orderIndex
        self.notes = notes
        self.updatedAt = updatedAt
        self.connectionType = connectionType
        self.useMosh = useMosh
        self.vncPort = vncPort
        self.rdpPort = rdpPort
    }

    // MARK: - Decodable Fallbacks
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decodeIfPresent(UUID.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try container.decode(String.self, forKey: .username)
        authMethod = try container.decodeIfPresent(String.self, forKey: .authMethod) ?? "password"
        privateKeyID = try container.decodeIfPresent(UUID.self, forKey: .privateKeyID)
        group = try container.decodeIfPresent(String.self, forKey: .group)
        environment = try container.decodeIfPresent(String.self, forKey: .environment) ?? "other"
        colour = try container.decodeIfPresent(String.self, forKey: .colour) ?? "#00FF41"
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        orderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex) ?? 0
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        connectionType = try container.decodeIfPresent(String.self, forKey: .connectionType) ?? "ssh"
        useMosh = try container.decodeIfPresent(Bool.self, forKey: .useMosh) ?? false
        vncPort = try container.decodeIfPresent(Int.self, forKey: .vncPort)
        rdpPort = try container.decodeIfPresent(Int.self, forKey: .rdpPort)
    }

    // MARK: - Hashable (exclude runtime-only props for stability)

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Server, rhs: Server) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Computed helpers for UI

    var serverEnvironment: ServerEnvironment {
        ServerEnvironment(rawValue: environment) ?? .other
    }

    var connectionProtocol: ConnectionProtocol {
        ConnectionProtocol(rawValue: connectionType) ?? .ssh
    }
}

// MARK: - ServerGroup

struct ServerGroup: Identifiable, Hashable, Codable {
    let id: UUID
    var userId: UUID?
    var name: String
    var colour: String
    var orderIndex: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name, colour
        case orderIndex = "order_index"
    }

    init(
        id: UUID = UUID(),
        userId: UUID? = nil,
        name: String,
        colour: String = "#00FF41",
        orderIndex: Int = 0
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.colour = colour
        self.orderIndex = orderIndex
    }
}

// MARK: - ServerEnvironment

enum ServerEnvironment: String, Codable, CaseIterable {
    case production
    case staging
    case development
    case other

    var displayName: String {
        switch self {
        case .production: "Production"
        case .staging: "Staging"
        case .development: "Development"
        case .other: "Other"
        }
    }

    var badge: String {
        switch self {
        case .production: "PROD"
        case .staging: "STAGE"
        case .development: "DEV"
        case .other: "OTHER"
        }
    }

    var colour: Color {
        switch self {
        case .production: KestrelColors.red
        case .staging: KestrelColors.amber
        case .development: KestrelColors.blue
        case .other: .gray
        }
    }
}

// MARK: - ServerStatus

enum ServerStatus: String, Codable, CaseIterable {
    case online
    case offline
    case warning

    var color: Color {
        switch self {
        case .online: KestrelColors.phosphorGreen
        case .offline: KestrelColors.red
        case .warning: KestrelColors.amber
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .online: "online"
        case .offline: "offline"
        case .warning: "warning"
        }
    }
}

// MARK: - ConnectionProtocol

enum ConnectionProtocol: String, Codable, CaseIterable {
    case ssh
    case vnc
    case rdp

    var displayName: String {
        switch self {
        case .ssh: "SSH"
        case .vnc: "VNC"
        case .rdp: "RDP"
        }
    }

    var icon: String {
        switch self {
        case .ssh: "terminal"
        case .vnc: "rectangle.on.rectangle"
        case .rdp: "desktopcomputer"
        }
    }

    var defaultPort: Int {
        switch self {
        case .ssh: 22
        case .vnc: 5900
        case .rdp: 3389
        }
    }
}
