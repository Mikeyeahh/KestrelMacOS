//
//  MacContentView.swift
//  Kestrel Mac
//
//  Created by Mike on 10/04/2026.
//

import SwiftUI

struct MacContentView: View {
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var sessionManager: SSHSessionManager
    @EnvironmentObject var deepLinkHandler: DeepLinkHandler
    @State private var selectedServer: Server?
    @State private var activeView: SidebarActiveView?

    /// Servers with open terminal tabs — persists across sidebar selection changes.
    @State private var openServers: [Server] = []
    @State private var activeOpenServerID: UUID?

    @State private var showingImportSheet = false

    // Per-window scene storage for restoring position
    @SceneStorage("window.selectedServerID") private var storedServerID: String?
    @SceneStorage("window.activeView") private var storedActiveView: String?

    var body: some View {
        NavigationSplitView {
            MacServerSidebarView(
                selectedServer: $selectedServer,
                activeView: $activeView
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
        } detail: {
            detailContent
        }
        // When sidebar selection changes, open a terminal tab for that server
        .onChange(of: activeView) { _, newView in
            if case .terminal(let server) = newView {
                openServerTab(server)
            }
        }
        // Deep link URL handling
        .onOpenURL { url in
            deepLinkHandler.handle(url: url)
        }
        // Handoff: receive activity from iOS
        .onContinueUserActivity(KestrelActivityType.terminal) { activity in
            HandoffManager.shared.handleIncomingActivity(activity)
        }
        .onContinueUserActivity(KestrelActivityType.dashboard) { activity in
            HandoffManager.shared.handleIncomingActivity(activity)
        }
        .onContinueUserActivity(KestrelActivityType.files) { activity in
            HandoffManager.shared.handleIncomingActivity(activity)
        }
        // Menu bar / deep link navigation via NotificationCenter
        .onReceive(NotificationCenter.default.publisher(for: .kestrelOpenServer)) { notification in
            handleOpenServer(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .kestrelAddServer)) { _ in
            deepLinkHandler.showAddServerSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .kestrelShowDashboard)) { _ in
            if let server = selectedServer {
                activeView = .dashboard(server)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kestrelShowFiles)) { _ in
            if let server = selectedServer {
                activeView = .files(server)
            }
        }
        // Advertise Handoff when server changes
        .onChange(of: selectedServer) { _, server in
            if let server {
                HandoffManager.shared.advertiseTerminalSession(server: server)
                storedServerID = server.id.uuidString
            } else {
                HandoffManager.shared.stopAdvertising()
                storedServerID = nil
            }
        }
        // Restore window state on appear
        .onAppear {
            restoreWindowState()
            KestrelNotificationManager.shared.requestPermission()
            SpotlightIndexer.shared.reindexAll(servers: serverRepository.servers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .kestrelImportServers)) { _ in
            showingImportSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .kestrelMultiExec)) { _ in
            selectedServer = nil
            activeView = .multiExec
        }
        // Sheet for Add Server from deep links
        .sheet(isPresented: $deepLinkHandler.showAddServerSheet) {
            MacEditServerSheet()
        }
        .sheet(isPresented: $showingImportSheet) {
            MacImportServersSheet()
        }
    }

    // MARK: - Open Server Tabs

    private func openServerTab(_ server: Server) {
        if !openServers.contains(where: { $0.id == server.id }) {
            openServers.append(server)
        }
        activeOpenServerID = server.id
    }

    private func closeServerTab(_ server: Server) {
        sessionManager.closeSession(serverID: server.id)
        openServers.removeAll { $0.id == server.id }
        if activeOpenServerID == server.id {
            activeOpenServerID = openServers.last?.id
        }
        if openServers.isEmpty {
            activeView = nil
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch activeView {
        case .cloud:
            MacCloudSyncView()

        case .terminal:
            terminalTabView

        case .dashboard(let server):
            MacDashboardView(server: server)

        case .files(let server):
            MacSFTPView(server: server)

        case .vnc(let server):
            MacVNCView(server: server)

        case .rdp(let server):
            MacRDPView(server: server)

        case .multiExec:
            MacMultiExecView()

        case nil:
            ContentUnavailableView(
                "No Server Selected",
                systemImage: "server.rack",
                description: Text("Select a server from the sidebar to get started.")
            )
        }
    }

    /// Tab bar for multiple open server terminals.
    private var terminalTabView: some View {
        VStack(spacing: 0) {
            // Tab bar (only show when multiple servers are open)
            if openServers.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(openServers, id: \.id) { server in
                            serverTab(server)
                        }
                    }
                }
                .background(KestrelColors.background)

                Divider().overlay(KestrelColors.cardBorder)
            }

            // Active server terminal
            if let activeID = activeOpenServerID,
               let server = openServers.first(where: { $0.id == activeID }) {
                MacTerminalView(server: server, onClose: { closeServerTab(server) })
                    .id(server.id)
            } else if let first = openServers.first {
                MacTerminalView(server: first, onClose: { closeServerTab(first) })
                    .id(first.id)
            }
        }
    }

    private func serverTab(_ server: Server) -> some View {
        let isActive = server.id == activeOpenServerID
        let isConnected = sessionManager.activeSession(for: server.id)?.isConnected ?? false

        return HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? KestrelColors.phosphorGreen : KestrelColors.red)
                .frame(width: 6, height: 6)

            Text(server.name)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(isActive ? KestrelColors.textPrimary : KestrelColors.textMuted)
                .lineLimit(1)

            // Close button
            Button {
                closeServerTab(server)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? KestrelColors.backgroundCard : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            activeOpenServerID = server.id
        }
    }

    // MARK: - Navigation Handling

    private func handleOpenServer(_ notification: Foundation.Notification) {
        guard let serverID = notification.userInfo?["serverID"] as? UUID else { return }
        guard let server = serverRepository.servers.first(where: { $0.id == serverID }) else { return }

        selectedServer = server

        let view = notification.userInfo?["view"] as? String ?? "terminal"
        switch view {
        case "dashboard": activeView = .dashboard(server)
        case "files": activeView = .files(server)
        default: activeView = .terminal(server)
        }
    }

    private func restoreWindowState() {
        if let idStr = storedServerID,
           let id = UUID(uuidString: idStr),
           let server = serverRepository.servers.first(where: { $0.id == id }) {
            selectedServer = server
            activeView = .terminal(server)
        }
    }
}
