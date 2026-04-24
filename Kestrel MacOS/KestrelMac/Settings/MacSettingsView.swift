//
//  MacSettingsView.swift
//  Kestrel Mac
//
//  macOS Settings window with tab-based navigation.
//  Uses @AppStorage with same keys as iOS for shared preferences.
//

import SwiftUI
import ServiceManagement
import AppKit

// MARK: - Mac Settings View

struct MacSettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            TerminalSettingsTab()
                .tabItem { Label("Terminal", systemImage: "terminal") }

            SSHKeysSettingsTab()
                .tabItem { Label("SSH Keys", systemImage: "key") }

            AISettingsTab()
                .tabItem { Label("AI", systemImage: "sparkles") }

            SyncSettingsTab()
                .tabItem { Label("Sync", systemImage: "cloud") }

            OspreySettingsTab()
                .tabItem { Label("OSPREY", systemImage: "network") }

            NotificationSettingsTab()
                .tabItem { Label("Alerts", systemImage: "bell") }
        }
        .frame(width: 500, height: 460)
        .background {
            SettingsWindowStyler()
        }
    }
}

/// Ensures the Settings window has standard title bar buttons visible
private struct SettingsWindowStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = false
            window.backgroundColor = nil
            window.styleMask.insert(.closable)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Tab 0: Appearance

struct AppearanceSettingsTab: View {
    @AppStorage("app.theme") private var selectedTheme = "Phosphor"

    var body: some View {
        Form {
            Section("System Theme") {
                HStack(spacing: 16) {
                    ForEach(AppThemeID.allCases) { themeID in
                        Button {
                            selectedTheme = themeID.rawValue
                            ThemeManager.shared.currentThemeID = themeID
                        } label: {
                            VStack(spacing: 8) {
                                // Preview swatch
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(themeID.theme.background)
                                        .frame(width: 72, height: 52)

                                    VStack(spacing: 4) {
                                        Circle()
                                            .fill(themeID.theme.accent)
                                            .frame(width: 12, height: 12)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(themeID.theme.accent.opacity(0.4))
                                            .frame(width: 32, height: 4)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(themeID.theme.textFaint)
                                            .frame(width: 22, height: 3)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(
                                            selectedTheme == themeID.rawValue
                                                ? themeID.theme.accent
                                                : Color.gray.opacity(0.3),
                                            lineWidth: selectedTheme == themeID.rawValue ? 2 : 1
                                        )
                                )

                                Text(themeID.rawValue)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(
                                        selectedTheme == themeID.rawValue ? .primary : .secondary
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Preview") {
                HStack(spacing: 12) {
                    let theme = (AppThemeID(rawValue: selectedTheme) ?? .phosphor).theme

                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.background)
                        .frame(height: 60)
                        .overlay {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(theme.accent)
                                    .frame(width: 8, height: 8)
                                Text("user@server:~$")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(theme.accent)
                                Spacer()
                                Text("PROD")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(theme.red)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(theme.red.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            .padding(.horizontal, 12)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(theme.cardBorderAccent, lineWidth: 1)
                        )
                }
            }
        }
    }
}

// MARK: - Tab 1: General

struct GeneralSettingsTab: View {
    @AppStorage("settings.defaultPort") private var defaultPort = 22
    @AppStorage("settings.connectionTimeout") private var connectionTimeout = 30
    @AppStorage("settings.keepaliveInterval") private var keepaliveInterval = 30.0
    @AppStorage("settings.autoReconnect") private var autoReconnect = true
    @AppStorage("settings.autoReconnectRetries") private var autoReconnectRetries = 3
    @AppStorage("settings.defaultUsername") private var defaultUsername = ""
    @AppStorage("settings.launchAtLogin") private var launchAtLogin = false
    @AppStorage("settings.showMenuBarExtra") private var showMenuBarExtra = true

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Default SSH Port:", value: $defaultPort, format: .number)

                Picker("Connection Timeout:", selection: $connectionTimeout) {
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                }

                HStack {
                    Text("Keepalive Interval:")
                    Slider(value: $keepaliveInterval, in: 15...120, step: 5)
                    Text("\(Int(keepaliveInterval))s")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                }

                Toggle("Auto-reconnect on disconnect", isOn: $autoReconnect)

                if autoReconnect {
                    Stepper("Retry attempts: \(autoReconnectRetries)", value: $autoReconnectRetries, in: 1...10)
                }

                TextField("Default Username:", text: $defaultUsername)
                    .textContentType(.username)
            }

            Section("System") {
                Toggle("Start at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLoginItem(enabled: enabled)
                    }
                Toggle("Show in menu bar", isOn: $showMenuBarExtra)
            }
        }
    }

    private func setLoginItem(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — user can manage in System Settings
            }
        }
    }
}

// MARK: - Tab 2: Terminal

struct TerminalSettingsTab: View {
    @AppStorage("mac.terminal.fontSize") private var fontSize: Double = 12
    @AppStorage("mac.terminal.fontName") private var fontName = "SFMono-Regular"
    @AppStorage("mac.terminal.colorScheme") private var colorScheme = "Kestrel"
    @AppStorage("mac.terminal.cursorStyle") private var cursorStyle = "block"
    @AppStorage("mac.terminal.scrollbackLines") private var scrollbackLines = 10000
    @AppStorage("mac.terminal.optionAsMeta") private var optionAsMeta = true
    @AppStorage("mac.terminal.audibleBell") private var audibleBell = false

    private let fonts = ["SFMono-Regular", "Menlo", "CascadiaCode-Regular", "Monaco"]
    private let fontLabels = ["SF Mono", "Menlo", "Cascadia Code", "Monaco"]

    private var currentScheme: TerminalColorScheme {
        TerminalColorScheme(rawValue: colorScheme) ?? .kestrel
    }

    var body: some View {
        Form {
            Section("Font") {
                HStack {
                    Text("Size:")
                    Slider(value: $fontSize, in: 10...18, step: 1)
                    Text("\(Int(fontSize))pt")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                }

                // Live preview
                Text("user@host:~$")
                    .font(.custom(fontName, size: fontSize))
                    .foregroundStyle(Color(
                        red: currentScheme.foreground.0,
                        green: currentScheme.foreground.1,
                        blue: currentScheme.foreground.2
                    ))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(
                        red: currentScheme.background.0,
                        green: currentScheme.background.1,
                        blue: currentScheme.background.2
                    ))
                    .cornerRadius(6)

                Picker("Font:", selection: $fontName) {
                    ForEach(Array(zip(fonts, fontLabels)), id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
            }

            Section("Appearance") {
                Picker("Colour Scheme:", selection: $colorScheme) {
                    ForEach(TerminalColorScheme.allCases, id: \.rawValue) { scheme in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(
                                    red: scheme.background.0,
                                    green: scheme.background.1,
                                    blue: scheme.background.2
                                ))
                                .frame(width: 16, height: 16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(Color(
                                            red: scheme.foreground.0,
                                            green: scheme.foreground.1,
                                            blue: scheme.foreground.2
                                        ), lineWidth: 1)
                                )
                            Text(scheme.rawValue)
                        }
                        .tag(scheme.rawValue)
                    }
                }

                Picker("Cursor Style:", selection: $cursorStyle) {
                    Text("Block").tag("block")
                    Text("Underline").tag("underline")
                    Text("Bar").tag("bar")
                }
            }

            Section("Behaviour") {
                Picker("Scrollback Lines:", selection: $scrollbackLines) {
                    Text("1,000").tag(1000)
                    Text("5,000").tag(5000)
                    Text("10,000").tag(10000)
                    Text("Unlimited").tag(Int.max)
                }

                Toggle("Option key acts as Meta", isOn: $optionAsMeta)
                Toggle("Audible bell", isOn: $audibleBell)
            }
        }
    }
}

// MARK: - Tab 3: SSH Keys

struct SSHKeysSettingsTab: View {
    @State private var keys: [SSHKeyItem] = []
    @State private var showingGenerateSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("SSH Keys")
                    .font(.headline)
                Spacer()

                Button { showingGenerateSheet = true } label: {
                    Label("Generate", systemImage: "plus.circle")
                }

                Button { importKey() } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if keys.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "key")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No SSH keys")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Generate or import a key to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                Table(keys) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Type", value: \.keyType)
                    TableColumn("Fingerprint") { key in
                        Text(key.fingerprint)
                            .font(.system(.body, design: .monospaced))
                    }
                    TableColumn("Created") { key in
                        Text(key.created.formatted(.dateTime.month().day().year()))
                    }
                }
            }
        }
        .sheet(isPresented: $showingGenerateSheet) {
            // TODO: key generation sheet
            VStack(spacing: 12) {
                Text("Generate SSH Key").font(.headline)
                Text("Key generation will be available when KeychainService is integrated.")
                    .foregroundStyle(.secondary)
                Button("Done") { showingGenerateSheet = false }
            }
            .padding(24)
            .frame(width: 360, height: 180)
        }
    }

    private func importKey() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldLabel = "SSH Key:"
        panel.begin { response in
            guard response == .OK, let _ = panel.url else { return }
            // TODO: import key via KeychainService
        }
    }
}

struct SSHKeyItem: Identifiable {
    let id = UUID()
    let name: String
    let keyType: String
    let fingerprint: String
    let created: Date
}

// MARK: - Tab 4: AI Assistant

struct AISettingsTab: View {
    @AppStorage("settings.aiContextLines") private var aiContextLines: Double = 20
    @AppStorage("settings.aiAutoSuggest") private var aiAutoSuggest = false
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var isTestingAPI = false
    @State private var apiTestResult: String?

    var body: some View {
        Form {
            Section("API Key") {
                HStack {
                    if showAPIKey {
                        TextField("Claude API Key", text: $apiKey)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("Claude API Key", text: $apiKey)
                    }

                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                }

                HStack {
                    Button {
                        testAPIConnection()
                    } label: {
                        HStack(spacing: 4) {
                            if isTestingAPI {
                                ProgressView().scaleEffect(0.5)
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(apiKey.isEmpty || isTestingAPI)

                    if let result = apiTestResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.contains("Success") ? .green : .red)
                    }
                }

                Button("Save Key") {
                    UserDefaults.standard.set(apiKey, forKey: "claude_api_key")
                }
                .disabled(apiKey.isEmpty)
            }

            Section("Behaviour") {
                HStack {
                    Text("Context Lines:")
                    Slider(value: $aiContextLines, in: 10...50, step: 5)
                    Text("\(Int(aiContextLines))")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 28, alignment: .trailing)
                }

                Toggle("Auto-suggest on error output", isOn: $aiAutoSuggest)

                Button("Clear Conversation History") {
                    // TODO: clear AI history
                }
            }
        }
        .onAppear {
            apiKey = UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
        }
    }

    private func testAPIConnection() {
        isTestingAPI = true
        apiTestResult = nil

        Task {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let body: [String: Any] = [
                "model": "claude-sonnet-4-20250514",
                "max_tokens": 10,
                "messages": [["role": "user", "content": "Hi"]]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                apiTestResult = status == 200 ? "Success — API key valid" : "Error: HTTP \(status)"
            } catch {
                apiTestResult = "Error: \(error.localizedDescription)"
            }
            isTestingAPI = false
        }
    }
}

// MARK: - Tab 5: Sync & Account

struct SyncSettingsTab: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var revenueCatService: RevenueCatService
    @AppStorage("settings.syncFrequency") private var syncFrequency = "realtime"
    @AppStorage("settings.conflictResolution") private var conflictResolution = "latest"
    @State private var showingSignOut = false

    var body: some View {
        Form {
            Section("Account") {
                if supabaseService.isAuthenticated {
                    LabeledContent("Email", value: supabaseService.userEmail ?? "—")
                    LabeledContent("Plan", value: revenueCatService.planName)

                    Button("Sign Out", role: .destructive) {
                        showingSignOut = true
                    }
                } else {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sync") {
                Picker("Sync Frequency:", selection: $syncFrequency) {
                    Text("Realtime").tag("realtime")
                    Text("Every 5 minutes").tag("5min")
                    Text("Manual only").tag("manual")
                }

                Picker("Conflict Resolution:", selection: $conflictResolution) {
                    Text("Latest wins").tag("latest")
                    Text("Ask me").tag("ask")
                }

                Button("Sync Now") {
                    Task { try? await supabaseService.syncNow() }
                }

                Button("Export All Data") {
                    Task {
                        if let data = try? await supabaseService.exportAllData() {
                            let panel = NSSavePanel()
                            panel.nameFieldStringValue = "kestrel-export.json"
                            panel.begin { response in
                                if response == .OK, let url = panel.url {
                                    try? data.write(to: url)
                                }
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Sign Out", isPresented: $showingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { try? await supabaseService.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Tab 6: OSPREY

struct OspreySettingsTab: View {
    @AppStorage("settings.sharedVaultEnabled") private var sharedVaultEnabled = true
    @AppStorage("settings.autoImportLanScan") private var autoImportLanScan = false
    @State private var showingClearConfirmation = false

    var body: some View {
        Form {
            Section("Integration") {
                // TODO: check OspreyBridgeService.shared.hasOspreyInstalled
                LabeledContent("Status") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("OSPREY installed")
                    }
                }

                Toggle("Shared vault", isOn: $sharedVaultEnabled)
                Toggle("Auto-import LAN scan results", isOn: $autoImportLanScan)
            }

            Section("Actions") {
                Button("Clear Shared Data") {
                    showingClearConfirmation = true
                }

                Button("Open OSPREY") {
                    if let url = URL(string: "osprey://") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .confirmationDialog("Clear Shared Data", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                // TODO: clear OspreyBridgeService shared data
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all data shared between Kestrel and OSPREY.")
        }
    }
}

// MARK: - Tab 7: Notifications

struct NotificationSettingsTab: View {
    @EnvironmentObject var serverRepository: ServerRepository
    @AppStorage("settings.serviceAlerts") private var serviceAlerts = true
    @AppStorage("settings.notificationStyle") private var notificationStyle = "banner"
    @AppStorage("settings.dndStart") private var dndStart = 22
    @AppStorage("settings.dndEnd") private var dndEnd = 7

    var body: some View {
        Form {
            Section("Alerts") {
                Toggle("Service monitoring alerts", isOn: $serviceAlerts)

                Picker("Notification Style:", selection: $notificationStyle) {
                    Text("Banner").tag("banner")
                    Text("Alert").tag("alert")
                    Text("None").tag("none")
                }
            }

            Section("Watched Servers") {
                if serverRepository.servers.isEmpty {
                    Text("No servers configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(serverRepository.servers) { server in
                        WatchedServerRow(server: server)
                    }
                }
            }

            Section("Do Not Disturb") {
                HStack {
                    Text("Quiet hours:")
                    Picker("From", selection: $dndStart) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .frame(width: 90)
                    Text("to")
                    Picker("To", selection: $dndEnd) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .frame(width: 90)
                }
            }
        }
    }
}

struct WatchedServerRow: View {
    let server: Server
    @AppStorage private var isWatched: Bool

    init(server: Server) {
        self.server = server
        _isWatched = AppStorage(wrappedValue: false, "settings.watch.\(server.id.uuidString)")
    }

    var body: some View {
        Toggle(isOn: $isWatched) {
            HStack(spacing: 6) {
                Circle()
                    .fill(server.status.color)
                    .frame(width: 6, height: 6)
                Text(server.name)
            }
        }
    }
}
