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

    // MARK: - Filtered Servers

    private var filteredServers: [Server] {
        guard !searchText.isEmpty else { return serverRepository.servers }
        let query = searchText.lowercased()
        return serverRepository.servers.filter {
            $0.name.lowercased().contains(query) ||
            $0.host.lowercased().contains(query)
        }
    }

    private func filteredServers(inGroup group: String) -> [Server] {
        filteredServers
            .filter { $0.group == group }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private var filteredUngrouped: [Server] {
        filteredServers
            .filter { $0.group == nil || $0.group?.isEmpty == true }
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
               serverRepository.servers.contains(where: { $0.group == group.name }) {
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
                let count = serverRepository.servers.filter { $0.group == group.name }.count
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newGroupName = ""
                    newGroupError = nil
                    showingNewGroupAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New Group")
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

            // Grouped servers
            ForEach(serverRepository.groups) { group in
                serverGroupSection(group: group)
            }

            // Ungrouped servers
            let ungrouped = filteredUngrouped
            if !ungrouped.isEmpty {
                Section {
                    serverRows(ungrouped, group: nil)
                } header: {
                    MacSidebarSectionHeader(title: "Ungrouped")
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            handleGroupDrop(providers, targetGroup: nil)
                        }
                }
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

    // MARK: - Server Group Section

    @ViewBuilder
    private func serverGroupSection(group: ServerGroup) -> some View {
        let groupServers = filteredServers(inGroup: group.name)

        if !groupServers.isEmpty || searchText.isEmpty {
            Section {
                serverRows(groupServers, group: group.name)
            } header: {
                MacSidebarSectionHeader(
                    title: group.name,
                    accentColor: Color(hex: group.colour)
                )
                    .contextMenu {
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
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        handleGroupDrop(providers, targetGroup: group.name)
                    }
            }
        }
    }

    // MARK: - Server Rows (with drag/drop reorder)

    @ViewBuilder
    private func serverRows(_ servers: [Server], group: String?) -> some View {
        ForEach(servers) { server in
            MacServerRow(
                server: server,
                isSelected: selectedServer?.id == server.id,
                sessionManager: sessionManager
            )
            .tag(server)
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
            .onDrop(of: [.text], isTargeted: nil) { providers in
                handleGroupDrop(providers, targetGroup: group)
            }
        }
        .onMove { source, destination in
            serverRepository.moveServer(from: source, to: destination, inGroup: group)
        }
    }

    // MARK: - Cross-Group Drop

    private func handleGroupDrop(_ providers: [NSItemProvider], targetGroup: String?) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            accepted = true
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let idString = object as? String,
                      let uuid = UUID(uuidString: idString) else { return }
                Task { @MainActor in
                    moveServer(id: uuid, toGroup: targetGroup)
                }
            }
        }
        return accepted
    }

    private func moveServer(id: UUID, toGroup target: String?) {
        guard var server = serverRepository.servers.first(where: { $0.id == id }) else { return }
        let trimmed = target?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newGroup: String? = (trimmed?.isEmpty == false) ? trimmed : nil
        if server.group == newGroup { return }
        server.group = newGroup
        server.updatedAt = .now
        withAnimation(.snappy) {
            serverRepository.updateServer(server)
        }
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
            if includeServers {
                for server in serverRepository.servers where server.group == group.name {
                    sessionManager.closeSession(serverID: server.id)
                    serverRepository.removeServer(server)
                }
            } else {
                // Ungroup the servers
                for server in serverRepository.servers where server.group == group.name {
                    var updated = server
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
