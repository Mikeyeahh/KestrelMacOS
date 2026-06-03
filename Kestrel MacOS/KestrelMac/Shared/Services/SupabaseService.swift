//
//  SupabaseService.swift
//  Kestrel Mac
//
//  Supabase integration for auth and cloud sync.
//

import Foundation
import Supabase

// MARK: - Connected Device

struct ConnectedDevice: Identifiable, Codable {
    let id: UUID
    let userId: UUID?
    let name: String
    let type: DeviceType
    let lastActive: Date
    let hasActiveSessions: Bool

    enum DeviceType: String, Codable {
        case mac, iphone, ipad, windows, linux, unknown

        // Decode unknown raw values to `.unknown` instead of throwing, so a
        // device type added by another platform (e.g. Windows writes
        // "windows") never breaks decoding of the whole device list.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = DeviceType(rawValue: raw) ?? .unknown
        }

        var icon: String {
            switch self {
            case .mac: "laptopcomputer"
            case .iphone: "iphone"
            case .ipad: "ipad"
            case .windows: "pc"
            case .linux: "terminal"
            case .unknown: "desktopcomputer"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name, type
        case lastActive = "last_active"
        case hasActiveSessions = "has_active_sessions"
    }

    init(id: UUID = UUID(), userId: UUID? = nil, name: String, type: DeviceType, lastActive: Date = .now, hasActiveSessions: Bool = false) {
        self.id = id
        self.userId = userId
        self.name = name
        self.type = type
        self.lastActive = lastActive
        self.hasActiveSessions = hasActiveSessions
    }
}

// MARK: - Sync Status

enum SyncState: Equatable {
    case idle
    case syncing
    case synced
    case error(String)
}

// MARK: - Sync Log Entry

struct SyncLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let action: String
    let detail: String
}

// MARK: - Supabase Client

private let supabaseClient = SupabaseClient(
    supabaseURL: URL(string: "https://uuawctfqhouzamkjfzcu.supabase.co")!,
    supabaseKey: "sb_publishable_CJUNTVbOOG1bZ09w-V_WEA_Em-LOQ9l"
)

// MARK: - Supabase Service

@MainActor
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    let client = supabaseClient

    @Published var isAuthenticated: Bool = false
    @Published var userEmail: String?
    @Published var userId: UUID?
    @Published var syncState: SyncState = .idle
    @Published var lastSyncDate: Date?
    @Published var connectedDevices: [ConnectedDevice] = []
    @Published var syncLog: [SyncLogEntry] = []
    @Published var authSuccessMessage: String?

    // Sync counts
    @Published var syncedServerCount: Int = 0
    @Published var syncedCommandCount: Int = 0
    @Published var syncedKeyCount: Int = 0
    @Published var syncedSessionCount: Int = 0

    private init() {
        Task { await checkExistingSession() }
    }

    // MARK: - Session

    private func checkExistingSession() async {
        do {
            let session = try await client.auth.session
            isAuthenticated = true
            userEmail = session.user.email
            userId = session.user.id
            appendLog(action: "Session restored", detail: userEmail ?? "")
            RevenueCatService.shared.checkDeveloperAccess(email: userEmail)

            // Auto-register this device and fetch the device list
            try? await registerDevice()
            try? await fetchDevices()
            await refreshCloudProStatus()
        } catch {
            isAuthenticated = false
        }
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        isAuthenticated = true
        userEmail = session.user.email
        userId = session.user.id
        appendLog(action: "Signed in", detail: email)
        RevenueCatService.shared.checkDeveloperAccess(email: userEmail)
        await refreshCloudProStatus()

        // Register this device and pull the device list
        try? await registerDevice()
        try? await fetchDevices()
    }

    /// Returns `true` if email confirmation is required
    func signUp(email: String, password: String) async throws -> Bool {
        let result = try await client.auth.signUp(
            email: email,
            password: password,
            redirectTo: URL(string: "kestrel://auth/callback")
        )
        if let session = result.session {
            isAuthenticated = true
            userEmail = session.user.email
            userId = session.user.id
            appendLog(action: "Signed up", detail: email)
            RevenueCatService.shared.checkDeveloperAccess(email: userEmail)
            await refreshCloudProStatus()
            return false
        } else {
            appendLog(action: "Sign up — check email", detail: email)
            return true
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
        isAuthenticated = false
        userEmail = nil
        userId = nil
        connectedDevices = []
        syncedServerCount = 0
        syncedCommandCount = 0
        syncedKeyCount = 0
        syncedSessionCount = 0
        await RevenueCatService.shared.resetForLogout()
        appendLog(action: "Signed out", detail: "")
    }

    func handleAuthCallback(_ url: URL) async {
        do {
            try await client.auth.session(from: url)
            let session = try await client.auth.session
            isAuthenticated = true
            userEmail = session.user.email
            userId = session.user.id
            appendLog(action: "Session restored", detail: userEmail ?? "")
            RevenueCatService.shared.checkDeveloperAccess(email: userEmail)
            
            // Auto-register this device and fetch the device list
            try? await registerDevice()
            try? await fetchDevices()
            await refreshCloudProStatus()

            authSuccessMessage = "Email verified! You have been logged in."
        } catch {
            authSuccessMessage = "Failed to verify email. Please try again."
        }
    }

    // MARK: - Pro Entitlement

    private struct SubscriptionRow: Decodable { let status: String? }

    /// Reads Pro from the `subscriptions` table (the service-role-written source
    /// of truth, shared with the iOS/Windows apps) and pushes it into the
    /// RevenueCat service so Pro bought on ANY platform — including RevenueCat
    /// Web Billing, which the native SDK's `customerInfo` never reports — shows
    /// in the UI. Best-effort: on any error we clear the cloud-Pro flag.
    func refreshCloudProStatus() async {
        // Link the RevenueCat SDK to this Supabase account so its customerInfo
        // reflects purchases from any device, then read the authoritative
        // subscriptions table (also covers Web Billing, which the SDK never sees).
        if let userId {
            await RevenueCatService.shared.identify(appUserID: userId.uuidString)
        }
        RevenueCatService.shared.cloudPro = await fetchProStatus()
    }

    /// True when the signed-in user has an active subscription row. RLS limits
    /// the query to the caller's own row, so this returns at most one row.
    func fetchProStatus() async -> Bool {
        guard let userId else { return false }
        do {
            let rows: [SubscriptionRow] = try await client
                .from("subscriptions")
                .select("status")
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first?.status == "active"
        } catch {
            return false
        }
    }

    // MARK: - Server Sync

    func fetchServers() async throws -> [Server] {
        guard let userId else { return [] }
        let servers: [Server] = try await client
            .from("servers")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        syncedServerCount = servers.count
        return servers
    }

    func upsertServer(_ server: Server) async throws {
        guard let userId else { return }
        var s = server
        s.userId = userId
        s.updatedAt = .now
        try await client
            .from("servers")
            .upsert(s)
            .execute()
    }

    func deleteServer(_ server: Server) async throws {
        try await client
            .from("servers")
            .delete()
            .eq("id", value: server.id.uuidString)
            .execute()
    }

    // MARK: - Group Sync

    func fetchGroups() async throws -> [ServerGroup] {
        guard let userId else { return [] }
        let groups: [ServerGroup] = try await client
            .from("server_groups")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        return groups
    }

    func upsertGroup(_ group: ServerGroup) async throws {
        guard let userId else { return }
        var g = group
        g.userId = userId
        try await client
            .from("server_groups")
            .upsert(g)
            .execute()
    }

    func deleteGroup(_ group: ServerGroup) async throws {
        try await client
            .from("server_groups")
            .delete()
            .eq("id", value: group.id.uuidString)
            .execute()
    }

    // MARK: - Full Sync

    func syncNow() async throws {
        syncState = .syncing
        do {
            let servers = try await fetchServers()
            syncedServerCount = servers.count
            syncState = .synced
            lastSyncDate = .now
            appendLog(action: "Sync complete", detail: "\(servers.count) servers")
        } catch {
            syncState = .error(error.localizedDescription)
            appendLog(action: "Sync failed", detail: error.localizedDescription)
            throw error
        }
    }

    // MARK: - Device Registration

    private static let deviceIdDefaultsKey = "kestrel.device.id"

    private static func persistedDeviceId() -> UUID {
        if let stored = UserDefaults.standard.string(forKey: deviceIdDefaultsKey),
           let id = UUID(uuidString: stored) {
            return id
        }
        let new = UUID()
        UserDefaults.standard.set(new.uuidString, forKey: deviceIdDefaultsKey)
        return new
    }

    func registerDevice() async throws {
        guard let userId else { return }
        let device = ConnectedDevice(
            id: Self.persistedDeviceId(),
            userId: userId,
            name: Host.current().localizedName ?? "Mac",
            type: .mac,
            lastActive: .now,
            hasActiveSessions: false
        )
        do {
            try await client
                .from("devices")
                .upsert(device)
                .execute()
        } catch {
            appendLog(action: "registerDevice failed", detail: error.localizedDescription)
            throw error
        }
    }

    func fetchDevices() async throws {
        guard let userId else { return }
        do {
            let devices: [ConnectedDevice] = try await client
                .from("devices")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            connectedDevices = devices
        } catch {
            appendLog(action: "fetchDevices failed", detail: error.localizedDescription)
            throw error
        }
    }

    func removeDevice(_ device: ConnectedDevice) async throws {
        try await client
            .from("devices")
            .delete()
            .eq("id", value: device.id.uuidString)
            .execute()
        connectedDevices.removeAll { $0.id == device.id }
    }

    // MARK: - Data Management

    func exportAllData() async throws -> Data {
        let servers = try await fetchServers()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(servers)
    }

    func deleteAccount() async throws {
        // Delete all user data first
        if let userId {
            try await client.from("servers").delete().eq("user_id", value: userId.uuidString).execute()
            try await client.from("devices").delete().eq("user_id", value: userId.uuidString).execute()
        }
        
        // Fully delete the authentication identity from Supabase auth.users
        try await client.rpc("delete_user").execute()
        
        try await signOut()
    }

    func clearLocalCache() {
        syncedServerCount = 0
        syncedCommandCount = 0
        syncedKeyCount = 0
        syncedSessionCount = 0
        lastSyncDate = nil
        syncLog.removeAll()
    }

    // MARK: - Helpers

    private func appendLog(action: String, detail: String) {
        syncLog.insert(SyncLogEntry(timestamp: .now, action: action, detail: detail), at: 0)
        if syncLog.count > 50 { syncLog = Array(syncLog.prefix(50)) }
    }
}
