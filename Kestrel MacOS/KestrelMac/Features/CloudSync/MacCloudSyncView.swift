//
//  MacCloudSyncView.swift
//  Kestrel Mac
//
//  macOS Cloud Sync and account management view.
//  Shown when user clicks "Kestrel Cloud" at the top of the sidebar.
//

import SwiftUI
import AppKit

// MARK: - Mac Cloud Sync View

struct MacCloudSyncView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var revenueCatService: RevenueCatService
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var sessionManager: SSHSessionManager

    @State private var showingSignOut = false
    @State private var showingDeleteAccount = false
    @State private var deleteConfirmText = ""
    @State private var showInspector = true
    @State private var showingImportSheet = false
    @AppStorage("mac.cloud.showInspector") private var inspectorPreference = true

    // Sign in form state
    @State private var signInEmail = ""
    @State private var signInPassword = ""
    @State private var isSigningIn = false
    @State private var isSigningUp = false
    @State private var authError: String?
    @State private var showConfirmEmail = false

    var body: some View {
        HSplitView {
            // Left: main content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if supabaseService.isAuthenticated {
                        accountSection
                        syncStatusCard
                        syncSummaryGrid
                        connectedDevicesSection
                        ospreyCard
                        dataManagementSection
                    } else {
                        signInSection
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity)
            .background(KestrelColors.background)

            // Right: inspector
            if showInspector && supabaseService.isAuthenticated {
                inspectorPanel
                    .frame(width: 220)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { showInspector.toggle(); inspectorPreference = showInspector }
                } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundStyle(showInspector ? KestrelColors.phosphorGreen : KestrelColors.textMuted)
                }
                .help("Toggle Inspector")
            }
        }
        .onAppear { showInspector = inspectorPreference }
        .sheet(isPresented: $showingImportSheet) {
            MacImportServersSheet()
                .environmentObject(serverRepository)
        }
        .task {
            guard supabaseService.isAuthenticated else { return }
            try? await supabaseService.fetchDevices()
            try? await supabaseService.syncNow()
            await serverRepository.loadFromCloud()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180 * 1_000_000_000) // 3 min
                guard supabaseService.isAuthenticated else { continue }
                try? await supabaseService.fetchDevices()
                try? await supabaseService.syncNow()
                await serverRepository.loadFromCloud()
            }
        }
    }

    // MARK: - Sign In Section

    private var signInSection: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "cloud")
                .font(.system(size: 48))
                .foregroundStyle(KestrelColors.phosphorGreen)

            Text("Kestrel Cloud")
                .font(KestrelFonts.display(22, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)

            Text("Sign in to sync servers and settings across devices.")
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField("Email", text: $signInEmail)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .frame(maxWidth: 300)

                SecureField("Password", text: $signInPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .frame(maxWidth: 300)

                if let authError {
                    Text(authError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if showConfirmEmail {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.badge")
                            .foregroundStyle(KestrelColors.phosphorGreen)
                        Text("Check your email to confirm your account, then sign in.")
                            .font(.caption)
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        performSignIn()
                    } label: {
                        HStack(spacing: 4) {
                            if isSigningIn { ProgressView().scaleEffect(0.5) }
                            Text("Sign In")
                        }
                        .frame(width: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KestrelColors.phosphorGreen)
                    .disabled(signInEmail.isEmpty || signInPassword.isEmpty || isSigningIn || isSigningUp)

                    Button {
                        performSignUp()
                    } label: {
                        HStack(spacing: 4) {
                            if isSigningUp { ProgressView().scaleEffect(0.5) }
                            Text("Create Account")
                        }
                        .frame(width: 120)
                    }
                    .disabled(signInEmail.isEmpty || signInPassword.isEmpty || isSigningIn || isSigningUp)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func performSignIn() {
        isSigningIn = true
        authError = nil
        Task {
            do {
                try await supabaseService.signIn(email: signInEmail, password: signInPassword)
                try? await supabaseService.fetchDevices()
                await serverRepository.loadFromCloud()
            } catch {
                authError = error.localizedDescription
            }
            isSigningIn = false
        }
    }

    private func performSignUp() {
        isSigningUp = true
        authError = nil
        showConfirmEmail = false
        Task {
            do {
                let needsConfirmation = try await supabaseService.signUp(email: signInEmail, password: signInPassword)
                if needsConfirmation {
                    showConfirmEmail = true
                }
            } catch {
                authError = error.localizedDescription
            }
            isSigningUp = false
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        DashboardCard {
            HStack(spacing: 14) {
                // Avatar
                Circle()
                    .fill(KestrelColors.phosphorGreenDim)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text(avatarInitial)
                            .font(KestrelFonts.display(22, weight: .bold))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(supabaseService.userEmail ?? "Not signed in")
                        .font(KestrelFonts.monoBold(13))
                        .foregroundStyle(KestrelColors.textPrimary)

                    // Plan badge
                    HStack(spacing: 6) {
                        Text(revenueCatService.isProUser ? "KESTREL PRO" : "FREE")
                            .font(KestrelFonts.mono(9))
                            .fontWeight(.bold)
                            .tracking(1.0)
                            .foregroundStyle(
                                revenueCatService.isProUser ? KestrelColors.phosphorGreen : KestrelColors.textFaint
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                revenueCatService.isProUser ? KestrelColors.phosphorGreenDim : KestrelColors.backgroundCard
                            )
                            .clipShape(Capsule())

                        if revenueCatService.hasSuiteBundle {
                            Text("SUITE")
                                .font(KestrelFonts.mono(8))
                                .fontWeight(.bold)
                                .foregroundStyle(KestrelColors.background)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(KestrelColors.amber)
                                .clipShape(Capsule())
                        }
                    }

                    if let renewal = revenueCatService.renewalDate {
                        Text("Renews \(renewal.formatted(.dateTime.month().day().year()))")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                }

                Spacer()

                VStack(spacing: 6) {
                    if let url = revenueCatService.manageSubscriptionURL {
                        Button("Manage Subscription") {
                            NSWorkspace.shared.open(url)
                        }
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .buttonStyle(.plain)
                    }

                    if supabaseService.isAuthenticated {
                        Button("Sign Out") {
                            showingSignOut = true
                        }
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.red)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .confirmationDialog("Sign Out", isPresented: $showingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { try? await supabaseService.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to sign in again to sync data.")
        }
    }

    private var avatarInitial: String {
        if let email = supabaseService.userEmail, let first = email.first {
            return String(first).uppercased()
        }
        return "?"
    }

    // MARK: - Sync Status Card

    private var syncStatusCard: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    // Animated status indicator
                    syncStatusIndicator

                    VStack(alignment: .leading, spacing: 2) {
                        Text(syncStatusText)
                            .font(KestrelFonts.monoBold(13))
                            .foregroundStyle(syncStatusColor)

                        if let lastSync = supabaseService.lastSyncDate {
                            Text("Last sync: \(lastSync.formatted(.relative(presentation: .named)))")
                                .font(KestrelFonts.mono(10))
                                .foregroundStyle(KestrelColors.textFaint)
                        }
                    }

                    Spacer()

                    Button {
                        Task { try? await supabaseService.syncNow() }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                    }
                    .buttonStyle(.plain)
                    .disabled(supabaseService.syncState == .syncing)
                }

                // E2E encryption badge
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                    Text("End-to-end encrypted")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(KestrelColors.phosphorGreenDim)
                .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var syncStatusIndicator: some View {
        switch supabaseService.syncState {
        case .synced:
            Circle()
                .fill(KestrelColors.phosphorGreen)
                .frame(width: 10, height: 10)
                .shadow(color: KestrelColors.phosphorGreen.opacity(0.5), radius: 4)
        case .syncing:
            ProgressView()
                .scaleEffect(0.6)
                .tint(KestrelColors.phosphorGreen)
        case .error:
            Circle()
                .fill(KestrelColors.red)
                .frame(width: 10, height: 10)
        case .idle:
            Circle()
                .fill(KestrelColors.textFaint)
                .frame(width: 10, height: 10)
        }
    }

    private var syncStatusText: String {
        switch supabaseService.syncState {
        case .synced: "SYNCED"
        case .syncing: "SYNCING..."
        case .error(let msg): msg
        case .idle: "NOT SYNCED"
        }
    }

    private var syncStatusColor: SwiftUI.Color {
        switch supabaseService.syncState {
        case .synced: KestrelColors.phosphorGreen
        case .syncing: KestrelColors.amber
        case .error: KestrelColors.red
        case .idle: KestrelColors.textFaint
        }
    }

    // MARK: - Sync Summary Grid

    private var syncSummaryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            syncStatCard("Servers", "\(supabaseService.syncedServerCount)", "server.rack", KestrelColors.phosphorGreen)
            syncStatCard("Commands", "\(supabaseService.syncedCommandCount)", "terminal", KestrelColors.blue)
            syncStatCard("SSH Keys", "\(supabaseService.syncedKeyCount)", "key", KestrelColors.amber)
            syncStatCard("Sessions", "\(supabaseService.syncedSessionCount)", "clock", KestrelColors.textMuted)
        }
    }

    private func syncStatCard(_ label: String, _ value: String, _ icon: String, _ color: SwiftUI.Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(KestrelFonts.display(20, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)
            Text(label.uppercased())
                .font(KestrelFonts.mono(8))
                .tracking(0.8)
                .foregroundStyle(KestrelColors.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Connected Devices

    private var connectedDevicesSection: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("CONNECTED DEVICES")
                    .font(KestrelFonts.mono(9))
                    .tracking(1.2)
                    .foregroundStyle(KestrelColors.textFaint)

                if supabaseService.connectedDevices.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("This Mac")
                                .font(KestrelFonts.mono(12))
                                .foregroundStyle(KestrelColors.textPrimary)
                            Text("Active now")
                                .font(KestrelFonts.mono(10))
                                .foregroundStyle(KestrelColors.phosphorGreen)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)

                    Text("Sign in on other devices to sync")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textFaint)
                } else {
                    ForEach(supabaseService.connectedDevices) { device in
                        deviceRow(device)
                    }
                }
            }
        }
    }

    private func deviceRow(_ device: ConnectedDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.type.icon)
                .font(.system(size: 14))
                .foregroundStyle(device.hasActiveSessions ? KestrelColors.phosphorGreen : KestrelColors.textMuted)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textPrimary)

                Text(device.lastActive.formatted(.relative(presentation: .named)))
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }

            Spacer()

            if device.hasActiveSessions {
                Text("Active")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(KestrelColors.phosphorGreenDim)
                    .clipShape(Capsule())
            }

            Button {
                Task { try? await supabaseService.removeDevice(device) }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .buttonStyle(.plain)
            .opacity(0.5)
        }
        .padding(.vertical, 4)
    }

    // MARK: - OSPREY Integration Card

    private var ospreyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("OSPREY")
                    .font(KestrelFonts.mono(11))
                    .fontWeight(.bold)
                    .tracking(2)
                    .foregroundStyle(KestrelColors.blue)
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(KestrelColors.blue)
            }

            Text("LAN scanner integration for host discovery")
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textMuted)

            HStack(spacing: 12) {
                Button {
                    // TODO: open import sheet
                } label: {
                    HStack(spacing: 4) {
                        Text("Import hosts")
                            .font(KestrelFonts.mono(11))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(KestrelColors.blue)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(KestrelColors.phosphorGreen)
                        .frame(width: 5, height: 5)
                    Text("Shared vault active")
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(KestrelColors.textFaint)
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [KestrelColors.blue.opacity(0.05), KestrelColors.phosphorGreen.opacity(0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [KestrelColors.blue.opacity(0.3), KestrelColors.phosphorGreen.opacity(0.15)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Data Management

    private var dataManagementSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    showingImportSheet = true
                } label: {
                    Label("Import servers from other apps", systemImage: "square.and.arrow.down")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        if let data = try? await supabaseService.exportAllData() {
                            let panel = NSSavePanel()
                            panel.nameFieldStringValue = "kestrel-export.json"
                            panel.allowedContentTypes = [.json]
                            panel.begin { response in
                                if response == .OK, let url = panel.url {
                                    try? data.write(to: url)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Export all data as JSON", systemImage: "arrow.down.doc")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                .buttonStyle(.plain)

                Button {
                    supabaseService.clearLocalCache()
                } label: {
                    Label("Clear local cache", systemImage: "trash")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                .buttonStyle(.plain)

                Button {
                    showingDeleteAccount = true
                } label: {
                    Label("Delete account", systemImage: "person.crop.circle.badge.minus")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        } label: {
            Text("Data & Privacy")
                .font(KestrelFonts.monoBold(12))
                .foregroundStyle(KestrelColors.textPrimary)
        }
        .tint(KestrelColors.textMuted)
        .padding(14)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
        )
        .alert("Delete Account", isPresented: $showingDeleteAccount) {
            TextField("Type DELETE to confirm", text: $deleteConfirmText)
            Button("Delete Account", role: .destructive) {
                guard deleteConfirmText == "DELETE" else { return }
                Task { try? await supabaseService.deleteAccount() }
            }
            Button("Cancel", role: .cancel) { deleteConfirmText = "" }
        } message: {
            Text("This permanently deletes your account and all synced data. Type DELETE to confirm.")
        }
    }

    // MARK: - Inspector Panel

    private var inspectorPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Fleet status
                fleetStatusSection

                Divider().overlay(KestrelColors.cardBorder)

                // Security info
                securityInfoSection

                Divider().overlay(KestrelColors.cardBorder)

                // Recent sync log
                syncLogSection
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
        .background(KestrelColors.backgroundCard)
        .overlay(alignment: .leading) {
            Rectangle().fill(KestrelColors.cardBorder).frame(width: 1)
        }
    }

    // MARK: - Fleet Status

    private var fleetStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FLEET")
                .font(KestrelFonts.mono(9))
                .tracking(1.2)
                .foregroundStyle(KestrelColors.textFaint)

            if serverRepository.servers.isEmpty {
                Text("No servers")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            } else {
                ForEach(serverRepository.servers) { server in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(server.status.color)
                            .frame(width: 6, height: 6)
                        Text(server.name)
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textMuted)
                            .lineLimit(1)
                        Spacer()
                        Text(server.serverEnvironment.badge)
                            .font(KestrelFonts.mono(7))
                            .foregroundStyle(server.serverEnvironment.colour)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    // MARK: - Security Info

    private var securityInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SECURITY")
                .font(KestrelFonts.mono(9))
                .tracking(1.2)
                .foregroundStyle(KestrelColors.textFaint)

            inspectorInfoRow("Encryption", "AES-256-GCM")
            inspectorInfoRow("Keys stored", "\(supabaseService.syncedKeyCount)")
            inspectorInfoRow("Vault", "App Group shared")
            inspectorInfoRow("Transport", "TLS 1.3")
        }
    }

    private func inspectorInfoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
            Spacer()
            Text(value)
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textMuted)
        }
    }

    // MARK: - Sync Log

    private var syncLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SYNC LOG")
                .font(KestrelFonts.mono(9))
                .tracking(1.2)
                .foregroundStyle(KestrelColors.textFaint)

            if supabaseService.syncLog.isEmpty {
                Text("No recent activity")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            } else {
                ForEach(supabaseService.syncLog.prefix(5)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.action)
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textMuted)
                        Text(entry.timestamp.formatted(.dateTime.hour().minute()))
                            .font(KestrelFonts.mono(8))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}
