//
//  MenuBarView.swift
//  Kestrel Mac
//
//  Menu bar companion — always visible in the macOS menu bar.
//  Shows fleet status, active sessions, and quick actions.
//

import SwiftUI
import AppKit
import UserNotifications

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var sessionManager: SSHSessionManager
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var supabaseService: SupabaseService

    @State private var showingActiveSessions = false

    private var activeSessions: [SSHSession] {
        sessionManager.connectedSessions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(KestrelColors.cardBorder)
            serverList
            if !activeSessions.isEmpty {
                Divider().overlay(KestrelColors.cardBorder)
                activeSessionsSection
            }
            Divider().overlay(KestrelColors.cardBorder)
            quickActions
            Divider().overlay(KestrelColors.cardBorder)
            ospreyRow
            Divider().overlay(KestrelColors.cardBorder)
            footer
        }
        .frame(width: 280)
        .background(KestrelColors.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("◈ KESTREL")
                .font(KestrelFonts.mono(10))
                .tracking(2)
                .foregroundStyle(KestrelColors.phosphorGreen)

            Spacer()

            // Sync status
            HStack(spacing: 4) {
                Circle()
                    .fill(syncDotColor)
                    .frame(width: 5, height: 5)
                Text(syncLabel)
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            }

            // Settings
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var syncDotColor: SwiftUI.Color {
        switch supabaseService.syncState {
        case .synced: return KestrelColors.phosphorGreen
        case .syncing: return KestrelColors.amber
        case .error: return KestrelColors.red
        case .idle: return KestrelColors.textFaint
        }
    }

    private var syncLabel: String {
        switch supabaseService.syncState {
        case .synced: return "Synced"
        case .syncing: return "Syncing…"
        case .error: return "Error"
        case .idle:
            if let date = supabaseService.lastSyncDate {
                return date.formatted(.relative(presentation: .named))
            }
            return "Not synced"
        }
    }

    // MARK: - Server List

    private var serverList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if serverRepository.servers.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 16))
                            .foregroundStyle(KestrelColors.textFaint)
                        Text("No servers configured")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                    .padding(.vertical, 14)
                    Spacer()
                }
            } else {
                ForEach(serverRepository.servers) { server in
                    menuBarServerRow(server)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func menuBarServerRow(_ server: Server) -> some View {
        Button {
            // Open main window focused on this server's terminal
            NSApp.activate(ignoringOtherApps: true)
            // Post notification that sidebar should select this server
            NotificationCenter.default.post(
                name: .kestrelOpenServer,
                object: nil,
                userInfo: ["serverID": server.id]
            )
        } label: {
            HStack(spacing: 8) {
                // Status dot with pulse
                MenuBarStatusDot(status: server.status)

                // Server name
                Text(server.name)
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Env badge
                Text(server.serverEnvironment.badge)
                    .font(KestrelFonts.mono(7))
                    .fontWeight(.bold)
                    .foregroundStyle(server.serverEnvironment.colour)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(server.serverEnvironment.colour.opacity(0.12))
                    .clipShape(Capsule())

                // Quick connect arrow
                if sessionManager.activeSession(for: server.id)?.isConnected != true {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Active Sessions

    private var activeSessionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    showingActiveSessions.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(KestrelColors.phosphorGreen)
                        .frame(width: 5, height: 5)
                    Text("\(activeSessions.count) active session\(activeSessions.count == 1 ? "" : "s")")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                    Spacer()
                    Image(systemName: showingActiveSessions ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(KestrelColors.textFaint)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingActiveSessions {
                ForEach(activeSessions) { session in
                    if let server = serverRepository.servers.first(where: { $0.id == session.serverID }) {
                        HStack(spacing: 8) {
                            Text(server.name)
                                .font(KestrelFonts.mono(10))
                                .foregroundStyle(KestrelColors.textMuted)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                NSApp.activate(ignoringOtherApps: true)
                                NotificationCenter.default.post(
                                    name: .kestrelOpenServer,
                                    object: nil,
                                    userInfo: ["serverID": server.id]
                                )
                            } label: {
                                Text("Bring to front")
                                    .font(KestrelFonts.mono(9))
                                    .foregroundStyle(KestrelColors.phosphorGreen)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            Spacer()

            quickActionButton("plus", "New") {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .kestrelAddServer, object: nil)
            }

            quickActionButton("antenna.radiowaves.left.and.right", "Scan") {
                // TODO: trigger OSPREY bridge import
            }

            quickActionButton("arrow.triangle.2.circlepath", "Sync") {
                Task { try? await supabaseService.syncNow() }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func quickActionButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(KestrelColors.textMuted)
                Text(label)
                    .font(KestrelFonts.mono(8))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .frame(width: 52, height: 40)
            .background(KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - OSPREY Row

    private var ospreyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 10))
                .foregroundStyle(KestrelColors.blue)

            Text("OSPREY")
                .font(KestrelFonts.mono(9))
                .fontWeight(.bold)
                .tracking(1)
                .foregroundStyle(KestrelColors.blue)

            Spacer()

            // TODO: check OspreyBridgeService for real status
            Text("Connected")
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            // Open OSPREY via URL scheme
            if let url = URL(string: "osprey://") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("Open Kestrel")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.phosphorGreen)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("v1.0")
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Menu Bar Status Dot (animated)

struct MenuBarStatusDot: View {
    let status: ServerStatus
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 6, height: 6)
            .shadow(color: status.color.opacity(isPulsing ? 0.5 : 0), radius: isPulsing ? 4 : 0)
            .onAppear {
                guard status == .online else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let kestrelOpenServer = Notification.Name("kestrelOpenServer")
    static let kestrelAddServer = Notification.Name("kestrelAddServer")
}

// MARK: - Fleet Status Monitor

@MainActor
class FleetStatusMonitor: ObservableObject {
    @Published var fleetStatus: FleetStatus = .idle

    enum FleetStatus {
        case idle       // no servers configured
        case allGood    // all servers reachable
        case warning    // some warnings
        case alert      // one or more servers down
    }

    private var timer: Timer?
    private weak var sessionManager: SSHSessionManager?
    private weak var serverRepository: ServerRepository?

    func start(sessionManager: SSHSessionManager, serverRepository: ServerRepository) {
        self.sessionManager = sessionManager
        self.serverRepository = serverRepository
        updateStatus()

        // Check every 15 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
                self?.sendNotificationsIfNeeded()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func updateStatus() {
        guard let repo = serverRepository else { fleetStatus = .idle; return }
        let servers = repo.servers
        guard !servers.isEmpty else { fleetStatus = .idle; return }

        let hasWarning = servers.contains { $0.status == .warning }
        let hasOffline = servers.contains { $0.status == .offline && $0.isConnected }

        if hasOffline {
            fleetStatus = .alert
        } else if hasWarning {
            fleetStatus = .warning
        } else {
            fleetStatus = .allGood
        }
    }

    private func sendNotificationsIfNeeded() {
        guard fleetStatus == .alert else { return }
        let content = UNMutableNotificationContent()
        content.title = "Kestrel"
        content.body = "One or more monitored servers are unreachable."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "fleet-alert-\(Date.now.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Menu bar icon colour based on fleet status.
    var iconColor: NSColor {
        switch fleetStatus {
        case .idle: .secondaryLabelColor
        case .allGood: NSColor(red: 0, green: 1, blue: 0.255, alpha: 1) // phosphorGreen
        case .warning: NSColor(red: 1, green: 0.722, blue: 0, alpha: 1) // amber
        case .alert: NSColor(red: 1, green: 0.231, blue: 0.361, alpha: 1) // red
        }
    }
}
