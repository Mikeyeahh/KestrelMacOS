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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Server")
            }
        }
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
                MacSidebarSectionHeader(title: group.name)
                    .contextMenu {
                        Button(role: .destructive) {
                            groupToDelete = group
                            showingDeleteGroup = true
                        } label: {
                            Label("Delete Group", systemImage: "trash")
                        }
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
        }
        .onMove { source, destination in
            serverRepository.moveServer(from: source, to: destination, inGroup: group)
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
    let sessionManager: SSHSessionManager

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

            // Reuse shared StatusDot component
            StatusDot(status: server.status)
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
