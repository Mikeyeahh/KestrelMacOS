//
//  ServerRepository.swift
//  Kestrel Mac
//
//  Server storage with Supabase cloud sync.
//

import Foundation

@MainActor
class ServerRepository: ObservableObject {
    @Published var servers: [Server] = []
    @Published var groups: [ServerGroup] = []
    @Published var isSyncing = false

    private var supabase: SupabaseService { SupabaseService.shared }

    // MARK: - Initial Load

    func loadFromCloud() async {
        guard supabase.isAuthenticated else {
            print("[CloudSync] loadFromCloud skipped — not authenticated")
            return
        }
        isSyncing = true
        do {
            let remoteServers = try await supabase.fetchServers()
            print("[CloudSync] Fetched \(remoteServers.count) servers from cloud")
            mergeServers(remoteServers)
            let remoteGroups = try await supabase.fetchGroups()
            print("[CloudSync] Fetched \(remoteGroups.count) groups from cloud")
            groups = remoteGroups.sorted { $0.orderIndex < $1.orderIndex }
            isSyncing = false
        } catch {
            print("[CloudSync] loadFromCloud failed: \(error)")
            isSyncing = false
        }
    }

    private func mergeServers(_ remoteServers: [Server]) {
        let localByID = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })
        var merged: [Server] = []

        for remote in remoteServers {
            var server = remote
            if let local = localByID[remote.id] {
                // Preserve runtime states
                server.status = local.status
                server.cpuUsage = local.cpuUsage
                server.os = local.os
                server.isConnected = local.isConnected
            }
            merged.append(server)
        }
        
        servers = merged.sorted { $0.orderIndex < $1.orderIndex }
    }

    // MARK: - Servers

    func addServer(_ server: Server) {
        servers.append(server)
        Task { try? await supabase.upsertServer(server) }
    }

    func removeServer(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        Task { try? await supabase.deleteServer(server) }
    }

    func updateServer(_ server: Server) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
            Task { try? await supabase.upsertServer(server) }
        }
    }

    func servers(inGroup groupName: String) -> [Server] {
        servers
            .filter { $0.group == groupName }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    var ungroupedServers: [Server] {
        servers
            .filter { $0.group == nil || $0.group?.isEmpty == true }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    func moveServer(from source: IndexSet, to destination: Int, inGroup group: String?) {
        if let group {
            var grouped = servers(inGroup: group)
            grouped.move(fromOffsets: source, toOffset: destination)
            for (i, moved) in grouped.enumerated() {
                if let idx = servers.firstIndex(where: { $0.id == moved.id }) {
                    servers[idx].orderIndex = i
                    Task { [server = servers[idx]] in try? await supabase.upsertServer(server) }
                }
            }
        } else {
            var ungrouped = ungroupedServers
            ungrouped.move(fromOffsets: source, toOffset: destination)
            for (i, moved) in ungrouped.enumerated() {
                if let idx = servers.firstIndex(where: { $0.id == moved.id }) {
                    servers[idx].orderIndex = i
                    Task { [server = servers[idx]] in try? await supabase.upsertServer(server) }
                }
            }
        }
    }

    // MARK: - Sync

    func startAutoSync() {
        Task {
            await syncWithCloud()
            
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if supabase.isAuthenticated {
                    await syncWithCloud()
                }
            }
        }
    }

    func syncWithCloud() async {
        guard supabase.isAuthenticated else { return }
        isSyncing = true
        do {
            // Pull from cloud — remote is source of truth for what exists.
            // Individual add/update/delete operations already push immediately,
            // so the sync loop only needs to pull.
            let remoteServers = try await supabase.fetchServers()
            mergeServers(remoteServers)
            let remoteGroups = try await supabase.fetchGroups()
            groups = remoteGroups.sorted { $0.orderIndex < $1.orderIndex }
            try await supabase.syncNow()
            isSyncing = false
        } catch {
            print("[CloudSync] syncWithCloud failed: \(error)")
            isSyncing = false
        }
    }

    // MARK: - Groups

    func addGroup(_ group: ServerGroup) {
        groups.append(group)
        Task { try? await supabase.upsertGroup(group) }
    }

    func removeGroup(_ group: ServerGroup) {
        groups.removeAll { $0.id == group.id }
        Task { try? await supabase.deleteGroup(group) }
    }

    func updateGroup(_ group: ServerGroup) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx] = group
            Task { try? await supabase.upsertGroup(group) }
        }
    }

    func loadGroupsFromCloud() async {
        guard supabase.isAuthenticated else { return }
        do {
            let remoteGroups = try await supabase.fetchGroups()
            groups = remoteGroups.sorted { $0.orderIndex < $1.orderIndex }
        } catch {
            // Silently fail — groups will stay local-only
        }
    }

    func clearAll() {
        servers = []
        groups = []
    }
}
