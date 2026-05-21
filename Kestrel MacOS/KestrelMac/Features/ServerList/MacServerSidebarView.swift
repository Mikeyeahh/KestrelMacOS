//
//  MacServerSidebarView.swift
//  Kestrel Mac
//
//  macOS sidebar — the Mac equivalent of the iOS ServersView,
//  adapted for a compact NavigationSplitView sidebar column.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Active View

enum SidebarActiveView: Hashable {
    case cloud
    case terminal(Server)
    case dashboard(Server)
    case files(Server)
    case vnc(Server)
    case rdp(Server)
    case multiExec
}

// MARK: - Mac Server Sidebar View

struct MacServerSidebarView: View {
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var sessionManager: SSHSessionManager
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var revenueCatService: RevenueCatService

    @Binding var selectedServer: Server?
    @Binding var activeView: SidebarActiveView?

    @State private var searchText = ""
    @State private var serverToDelete: Server?
    @State private var showingDeleteConfirmation = false
    @State private var serverToEdit: Server?
    @State private var showingAddSheet = false
    @State private var groupToDelete: ServerGroup?
    @State private var showingDeleteGroup = false
    @State private var showingPaywall = false
    @State private var showingNewGroupAlert = false
    @State private var newGroupName = ""
    @State private var newGroupError: String?
    @State private var groupForColorEdit: ServerGroup?
    @State private var pendingGroupColor: Color = KestrelColors.phosphorGreen
    /// Groups whose contents are expanded. Empty by default → every group
    /// starts collapsed, so the sidebar opens as a tidy list of folders.
    @State private var expandedGroups: Set<UUID> = []
    @State private var didSeedExpansion = false
    @State private var showingRenameGroup = false
    @State private var renameGroupTarget: ServerGroup?
    @State private var renameGroupName = ""

    // MARK: - Filtered Servers

    private var filteredServers: [Server] {
        guard !searchText.isEmpty else { return serverRepository.servers }
        let query = searchText.lowercased()
        return serverRepository.servers.filter {
            $0.name.lowercased().contains(query) ||
            $0.host.lowercased().contains(query)
        }
    }

    private func filteredServers(inGroup groupId: UUID) -> [Server] {
        filteredServers
            .filter { serverRepository.effectiveGroupId($0) == groupId }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private var filteredUngrouped: [Server] {
        filteredServers
            .filter { serverRepository.effectiveGroupId($0) == nil }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            serverList

            Spacer(minLength: 0)

            bottomSection
        }
        .background(KestrelColors.background)
        .onAppear {
            // On launch, top-level (root) folders are expanded so their
            // contents show, while nested folders start collapsed. Seeded
            // once per launch; manual toggles are kept afterwards.
            guard !didSeedExpansion else { return }
            didSeedExpansion = true
            for root in childGroups(of: nil) {
                expandedGroups.insert(root.id)
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search servers")
        .confirmationDialog(
            "Delete Server",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let server = serverToDelete {
                    sessionManager.closeSession(serverID: server.id)
                    withAnimation(.snappy) {
                        serverRepository.removeServer(server)
                    }
                    if selectedServer?.id == server.id {
                        selectedServer = nil
                        activeView = nil
                    }
                }
                serverToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                serverToDelete = nil
            }
        } message: {
            if let server = serverToDelete {
                Text("Delete \"\(server.name)\"? This cannot be undone.")
            }
        }
        .confirmationDialog(
            "Delete Group",
            isPresented: $showingDeleteGroup,
            titleVisibility: .visible
        ) {
            Button("Delete Group Only", role: .destructive) {
                if let group = groupToDelete {
                    deleteGroup(group, includeServers: false)
                }
                groupToDelete = nil
            }
            if let group = groupToDelete,
               serverRepository.servers.contains(where: { serverRepository.effectiveGroupId($0) == group.id }) {
                Button("Delete Group & Servers", role: .destructive) {
                    deleteGroup(group, includeServers: true)
                    groupToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                groupToDelete = nil
            }
        } message: {
            if let group = groupToDelete {
                let count = serverRepository.servers.filter { serverRepository.effectiveGroupId($0) == group.id }.count
                Text("Delete \"\(group.name)\"? This group has \(count) server\(count == 1 ? "" : "s").")
            }
        }
        .sheet(item: $serverToEdit) { server in
            MacEditServerSheet(editing: server)
        }
        .sheet(isPresented: $showingAddSheet) {
            MacEditServerSheet()
        }
        .sheet(isPresented: $showingPaywall) {
            MacPaywallView()
        }
        .sheet(item: $groupForColorEdit) { group in
            GroupColorEditor(
                groupName: group.name,
                color: $pendingGroupColor,
                onSave: {
                    saveGroupColor(group, color: pendingGroupColor)
                    groupForColorEdit = nil
                },
                onCancel: { groupForColorEdit = nil }
            )
        }
        .toolbar {
            // Add Group / Add Server are disabled while the user is not
            // signed in — the welcome overlay sits on top of the content,
            // but window toolbar items live in the chrome above it and
            // would otherwise stay tappable through the overlay.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newGroupName = ""
                    newGroupError = nil
                    showingNewGroupAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New Group")
                .disabled(!supabaseService.isAuthenticated)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if !revenueCatService.isProOrBundle && serverRepository.servers.count >= RevenueCatService.freeServerLimit {
                        showingPaywall = true
                    } else {
                        showingAddSheet = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Server")
                .disabled(!supabaseService.isAuthenticated)
            }
        }
        .alert("New Group", isPresented: $showingNewGroupAlert) {
            TextField("Group name", text: $newGroupName)
            Button("Create") { createNewGroup() }
            Button("Cancel", role: .cancel) {
                newGroupName = ""
                newGroupError = nil
            }
        } message: {
            if let newGroupError {
                Text(newGroupError)
            } else {
                Text("Enter a name for the new group.")
            }
        }
        .alert("Rename Group", isPresented: $showingRenameGroup) {
            TextField("Group name", text: $renameGroupName)
            Button("Rename") { renameGroup() }
            Button("Cancel", role: .cancel) { renameGroupTarget = nil }
        } message: {
            Text("Enter a new name for this group.")
        }
    }

    // MARK: - New Group

    private func createNewGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            newGroupError = "Group name cannot be empty."
            showingNewGroupAlert = true
            return
        }
        let exists = serverRepository.groups.contains {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !exists else {
            newGroupError = "A group named \"\(trimmed)\" already exists."
            showingNewGroupAlert = true
            return
        }
        let nextOrder = (serverRepository.groups.map(\.orderIndex).max() ?? -1) + 1
        withAnimation(.snappy) {
            serverRepository.addGroup(ServerGroup(name: trimmed, orderIndex: nextOrder))
        }
        newGroupName = ""
        newGroupError = nil
    }

    // MARK: - Server List

    private var serverList: some View {
        List(selection: $selectedServer) {
            // Cloud sync row — top item
            cloudSyncRow

            // Groups (nested tree) + servers, flattened to depth-tagged rows.
            ForEach(sidebarRows) { row in
                sidebarRowView(row)
            }

            // Empty state
            if filteredServers.isEmpty && searchText.isEmpty {
                emptyState
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Cloud Sync Row

    private var cloudSyncRow: some View {
        Button {
            selectedServer = nil
            activeView = .cloud
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "cloud")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KestrelColors.phosphorGreen)

                Text("Kestrel Cloud")
                    .font(KestrelFonts.monoBold(12))
                    .foregroundStyle(KestrelColors.textPrimary)

                Spacer()

                // Animated green dot when synced
                Circle()
                    .fill(KestrelColors.phosphorGreen)
                    .frame(width: 6, height: 6)
                    .shadow(color: KestrelColors.phosphorGreen.opacity(0.5), radius: 3)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                activeView == .cloud
                    ? KestrelColors.blue.opacity(0.08)
                    : Color.clear
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Multi-Exec Row

    private var multiExecRow: some View {
        Button {
            selectedServer = nil
            activeView = .multiExec
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KestrelColors.amber)

                Text("Multi-Exec")
                    .font(KestrelFonts.monoBold(12))
                    .foregroundStyle(KestrelColors.textPrimary)

                Spacer()

                Text("⌘⇧E")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                activeView == .multiExec
                    ? KestrelColors.amber.opacity(0.08)
                    : Color.clear
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sidebar Row Model
    //
    // Groups form a tree (via `parentId`). The list is rendered from a
    // flattened, depth-tagged walk of that tree so nesting + collapse can
    // live inside a plain `List`. A collapsed group omits its descendants.

    private enum SidebarRow: Identifiable {
        case group(ServerGroup, depth: Int)
        case server(Server, depth: Int)
        case ungroupedHeader

        var id: String {
            switch self {
            case .group(let g, _): return "group-\(g.id.uuidString)"
            case .server(let s, _): return "server-\(s.id.uuidString)"
            case .ungroupedHeader: return "ungrouped-header"
            }
        }
    }

    private func childGroups(of parentId: UUID?) -> [ServerGroup] {
        serverRepository.groups
            .filter { $0.parentId == parentId }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private var sidebarRows: [SidebarRow] {
        var rows: [SidebarRow] = []
        func walk(_ group: ServerGroup, depth: Int) {
            rows.append(.group(group, depth: depth))
            guard expandedGroups.contains(group.id) else { return }
            for server in filteredServers(inGroup: group.id) {
                rows.append(.server(server, depth: depth + 1))
            }
            for child in childGroups(of: group.id) {
                walk(child, depth: depth + 1)
            }
        }
        for root in childGroups(of: nil) {
            walk(root, depth: 0)
        }
        let ungrouped = filteredUngrouped
        if !ungrouped.isEmpty {
            rows.append(.ungroupedHeader)
            for server in ungrouped {
                rows.append(.server(server, depth: 1))
            }
        }
        return rows
    }

    @ViewBuilder
    private func sidebarRowView(_ row: SidebarRow) -> some View {
        switch row {
        case .group(let group, let depth):
            groupHeaderRow(group, depth: depth)
        case .server(let server, let depth):
            serverRowView(server, depth: depth)
        case .ungroupedHeader:
            MacSidebarSectionHeader(title: "Ungrouped")
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    handleSidebarDrop(providers, ontoGroupId: nil)
                }
        }
    }

    // MARK: - Group Header Row

    @ViewBuilder
    private func groupHeaderRow(_ group: ServerGroup, depth: Int) -> some View {
        let isExpanded = expandedGroups.contains(group.id)
        let count = filteredServers(inGroup: group.id).count
        HStack(spacing: 6) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(KestrelColors.textFaint)
                .frame(width: 10)
            Text(group.name.uppercased())
                .font(KestrelFonts.mono(10))
                .fontWeight(.medium)
                .tracking(1.2)
                .foregroundStyle(Color(hex: group.colour) ?? KestrelColors.textFaint)
            Spacer()
            if !isExpanded && count > 0 {
                Text("\(count)")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            }
        }
        .padding(.leading, CGFloat(depth) * 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture { toggleExpanded(group.id) }
        .contextMenu {
            Button {
                renameGroupTarget = group
                renameGroupName = group.name
                showingRenameGroup = true
            } label: {
                Label("Rename Group", systemImage: "pencil")
            }
            Button {
                pendingGroupColor = Color(hex: group.colour) ?? KestrelColors.phosphorGreen
                groupForColorEdit = group
            } label: {
                Label("Change Color…", systemImage: "paintpalette")
            }
            Divider()
            Button(role: .destructive) {
                groupToDelete = group
                showingDeleteGroup = true
            } label: {
                Label("Delete Group", systemImage: "trash")
            }
        }
        .onDrag {
            NSItemProvider(object: "group:\(group.id.uuidString)" as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleSidebarDrop(providers, ontoGroupId: group.id)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func serverRowView(_ server: Server, depth: Int) -> some View {
        MacServerRow(
            server: server,
            isSelected: selectedServer?.id == server.id,
            sessionManager: sessionManager
        )
        .tag(server)
        .padding(.leading, CGFloat(depth) * 12)
        .onTapGesture {
            selectedServer = server
            switch server.connectionProtocol {
            case .vnc: activeView = .vnc(server)
            case .rdp: activeView = .rdp(server)
            case .ssh: activeView = .terminal(server)
            }
        }
        .contextMenu {
            serverContextMenu(for: server)
        }
        .onDrag {
            NSItemProvider(object: server.id.uuidString as NSString)
        }
    }

    private func toggleExpanded(_ id: UUID) {
        withAnimation(.snappy) {
            if expandedGroups.contains(id) {
                expandedGroups.remove(id)
            } else {
                expandedGroups.insert(id)
            }
        }
    }

    // MARK: - Drag & Drop
    //
    // A dragged payload is either a server id (raw UUID string) or a group
    // id (prefixed `group:`). Dropping a server onto a group joins it;
    // dropping a group onto a group nests it; dropping either on the
    // Ungrouped header (`ontoGroupId == nil`) moves it back to the root.

    private func handleSidebarDrop(_ providers: [NSItemProvider], ontoGroupId targetGroupId: UUID?) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            accepted = true
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let payload = object as? String else { return }
                Task { @MainActor in
                    if payload.hasPrefix("group:") {
                        let raw = String(payload.dropFirst("group:".count))
                        if let gid = UUID(uuidString: raw) {
                            reparentGroup(gid, toParentId: targetGroupId)
                        }
                    } else if let sid = UUID(uuidString: payload) {
                        moveServer(id: sid, toGroupId: targetGroupId)
                    }
                }
            }
        }
        return accepted
    }

    private func moveServer(id: UUID, toGroupId target: UUID?) {
        guard var server = serverRepository.servers.first(where: { $0.id == id }) else { return }
        if serverRepository.effectiveGroupId(server) == target { return }
        // Write the canonical id; clear the legacy name so it can't drift.
        server.groupId = target
        server.group = nil
        server.updatedAt = .now
        withAnimation(.snappy) {
            serverRepository.updateServer(server)
        }
    }

    /// Re-parent a group. Ignores self-drops, no-op moves, and any move that
    /// would create a cycle (dropping a group onto one of its descendants).
    private func reparentGroup(_ id: UUID, toParentId newParent: UUID?) {
        guard var group = serverRepository.groups.first(where: { $0.id == id }) else { return }
        if id == newParent || group.parentId == newParent { return }
        if let newParent, isDescendant(newParent, of: id) { return }
        group.parentId = newParent
        withAnimation(.snappy) {
            serverRepository.updateGroup(group)
        }
    }

    private func isDescendant(_ candidate: UUID, of ancestor: UUID) -> Bool {
        var current = serverRepository.groups.first(where: { $0.id == candidate })
        while let parent = current?.parentId {
            if parent == ancestor { return true }
            current = serverRepository.groups.first(where: { $0.id == parent })
        }
        return false
    }

    // MARK: - Rename Group

    private func renameGroup() {
        guard let group = renameGroupTarget else { return }
        let trimmed = renameGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != group.name else {
            renameGroupTarget = nil
            return
        }
        // Migrate any members still referencing this group by its old name
        // onto the stable id, so the rename can't orphan them.
        for server in serverRepository.servers
        where server.groupId == nil && server.group == group.name {
            var migrated = server
            migrated.groupId = group.id
            migrated.group = nil
            migrated.updatedAt = .now
            serverRepository.updateServer(migrated)
        }
        var updated = group
        updated.name = trimmed
        serverRepository.updateGroup(updated)
        renameGroupTarget = nil
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func serverContextMenu(for server: Server) -> some View {
        switch server.connectionProtocol {
        case .ssh:
            let session = sessionManager.activeSession(for: server.id)

            if session?.isConnected == true {
                Button {
                    sessionManager.closeSession(serverID: server.id)
                } label: {
                    Label("Disconnect", systemImage: "bolt.slash")
                }
            } else {
                Button {
                    Task { try? await sessionManager.openSession(for: server) }
                } label: {
                    Label("Connect", systemImage: "bolt.fill")
                }
            }

            Divider()

            Button {
                selectedServer = server
                activeView = .terminal(server)
            } label: {
                Label("Open Terminal", systemImage: "terminal")
            }

            Button {
                selectedServer = server
                activeView = .dashboard(server)
            } label: {
                Label("Open Dashboard", systemImage: "chart.bar")
            }

            Button {
                selectedServer = server
                activeView = .files(server)
            } label: {
                Label("Open Files", systemImage: "folder")
            }

        case .vnc:
            Button {
                selectedServer = server
                activeView = .vnc(server)
            } label: {
                Label("Open Screen Sharing", systemImage: "rectangle.on.rectangle")
            }

        case .rdp:
            Button {
                selectedServer = server
                activeView = .rdp(server)
            } label: {
                Label("Open Remote Desktop", systemImage: "desktopcomputer")
            }
        }

        Divider()

        Button {
            serverToEdit = server
        } label: {
            Label("Edit Server", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            serverToDelete = server
            showingDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 24))
                .foregroundStyle(KestrelColors.textFaint)
            Text("No servers yet")
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowBackground(Color.clear)
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(KestrelColors.cardBorder)

            if !revenueCatService.isProOrBundle {
                Button {
                    showingPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundStyle(KestrelColors.phosphorGreen)

                        Text("Upgrade to Pro")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.textPrimary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
                    .overlay(KestrelColors.cardBorder)
            }

            // User account row
            SettingsLink {
                HStack(spacing: 8) {
                    // Avatar circle with initial
                    Circle()
                        .fill(KestrelColors.phosphorGreenDim)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(String((supabaseService.userEmail ?? "K").prefix(1)).uppercased())
                                .font(KestrelFonts.monoBold(11))
                                .foregroundStyle(KestrelColors.phosphorGreen)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(supabaseService.userEmail?.components(separatedBy: "@").first ?? "Kestrel")
                                .font(KestrelFonts.mono(11))
                                .foregroundStyle(KestrelColors.textPrimary)
                                .lineLimit(1)

                            if revenueCatService.isProOrBundle {
                                Text("PRO")
                                    .font(KestrelFonts.mono(8))
                                    .fontWeight(.bold)
                                    .tracking(0.5)
                                    .foregroundStyle(KestrelColors.phosphorGreen)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(KestrelColors.phosphorGreenDim)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(KestrelColors.textFaint)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .background(KestrelColors.background)
    }

    // MARK: - Group Color

    private func saveGroupColor(_ group: ServerGroup, color: Color) {
        var updated = group
        updated.colour = color.toHex()
        withAnimation(.snappy) {
            serverRepository.updateGroup(updated)
        }
    }

    // MARK: - Group Deletion

    private func deleteGroup(_ group: ServerGroup, includeServers: Bool) {
        withAnimation(.snappy) {
            let members = serverRepository.servers.filter {
                serverRepository.effectiveGroupId($0) == group.id
            }
            if includeServers {
                for server in members {
                    sessionManager.closeSession(serverID: server.id)
                    serverRepository.removeServer(server)
                }
            } else {
                // Ungroup the servers
                for server in members {
                    var updated = server
                    updated.groupId = nil
                    updated.group = nil
                    updated.updatedAt = .now
                    serverRepository.updateServer(updated)
                }
            }
            serverRepository.removeGroup(group)
        }
    }
}

// MARK: - Mac Server Row

struct MacServerRow: View {
    let server: Server
    let isSelected: Bool
    @ObservedObject var sessionManager: SSHSessionManager

    private var pingMs: Int? {
        sessionManager.statsEngine(for: server.id)?.stats?.pingMs
    }

    private var protocolIcon: String {
        switch server.connectionProtocol {
        case .vnc: "rectangle.on.rectangle"
        case .rdp: "desktopcomputer"
        case .ssh: server.useMosh ? "antenna.radiowaves.left.and.right" : "terminal"
        }
    }

    private var protocolIconColor: Color {
        switch server.connectionProtocol {
        case .vnc: KestrelColors.phosphorGreen
        case .rdp: KestrelColors.blue
        case .ssh: server.useMosh ? KestrelColors.amber : KestrelColors.textFaint
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Left accent bar for active/selected state
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? KestrelColors.phosphorGreen : Color.clear)
                .frame(width: 2, height: 22)

            // Observes the live SSH session so the dot flips red→green on connect.
            LiveServerStatusDot(
                session: sessionManager.activeSession(for: server.id),
                fallback: server.status
            )
            .scaleEffect(0.85)

            // Protocol icon
            Image(systemName: protocolIcon)
                .font(.system(size: 9))
                .foregroundStyle(protocolIconColor)

            // Server name
            Text(server.name)
                .font(KestrelFonts.systemMono(11))
                .foregroundStyle(
                    isSelected ? KestrelColors.textPrimary : KestrelColors.textMuted
                )
                .lineLimit(1)

            Spacer(minLength: 4)

            // Trailing: env badge + ping
            EnvBadge(env: server.serverEnvironment, compact: true)

            if let pingMs {
                Text("\(pingMs)ms")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
                    .monospacedDigit()
            }
        }
        .frame(height: 32)
        .padding(.horizontal, 6)
        .background(
            isSelected
                ? KestrelColors.phosphorGreen.opacity(0.08)
                : Color.clear
        )
        .cornerRadius(6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(server.name), \(server.status.accessibilityLabel), \(server.serverEnvironment.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Group Color Editor

private struct GroupColorEditor: View {
    let groupName: String
    @Binding var color: Color
    let onSave: () -> Void
    let onCancel: () -> Void

    private let presets: [String] = [
        "#00FF9C", // phosphor green
        "#FFB800", // amber
        "#FF3B5C", // red
        "#00C8FF", // blue
        "#B380FF", // violet
        "#FF7A45", // orange
        "#9CA3AF"  // grey
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Group Color")
                .font(KestrelFonts.display(15, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)

            Text(groupName)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textMuted)

            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { hex in
                    let presetColor = Color(hex: hex) ?? KestrelColors.phosphorGreen
                    Button {
                        color = presetColor
                    } label: {
                        Circle()
                            .fill(presetColor)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        color.toHex().caseInsensitiveCompare(hex) == .orderedSame
                                            ? KestrelColors.textPrimary
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(hex)
                }
            }

            ColorPicker("Custom", selection: $color, supportsOpacity: false)
                .font(KestrelFonts.mono(11))

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave() }
                    .buttonStyle(.borderedProminent)
                    .tint(KestrelColors.phosphorGreen)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(KestrelColors.background)
    }
}
