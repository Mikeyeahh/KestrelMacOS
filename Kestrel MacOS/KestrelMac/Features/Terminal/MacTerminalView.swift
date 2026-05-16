//
//  MacTerminalView.swift
//  Kestrel Mac
//
//  macOS terminal view using SwiftTerm's NSView-based TerminalView.
//  Mirrors the iOS TerminalView + SSHTerminalContainer architecture
//  adapted for macOS with tab bar, inspector panel, and status bar.
//

import SwiftUI
import SwiftTerm
import AppKit

// MARK: - Terminal Tab Model

class MacTerminalTab: Identifiable, ObservableObject {
    let id = UUID()
    let server: Server
    @Published var transcript: String = ""
    @Published var isReconnecting = false
    @Published var reconnectFailed = false
    @Published var reconnectAttempts = 0
    @Published var cursorLine: Int = 1
    @Published var cursorCol: Int = 1
    let maxReconnectAttempts = 3

    init(server: Server) {
        self.server = server
    }
}

// MARK: - Mac Terminal View (Outer Structure)

struct MacTerminalView: View {
    let server: Server
    var onClose: (() -> Void)?

    @EnvironmentObject var sessionManager: SSHSessionManager
    @EnvironmentObject var revenueCatService: RevenueCatService
    @StateObject private var tab: MacTerminalTab
    @State private var showInspector: Bool = false
    @State private var showingAISheet = false
    @State private var showingPaywall = false
    @State private var showingPasswordPrompt = false
    @State private var passwordInput = ""
    @State private var connectionError: String?
    @State private var aiSelectedText = ""
    @AppStorage("mac.terminal.showInspector") private var inspectorPreference = false

    init(server: Server, onClose: (() -> Void)? = nil) {
        self.server = server
        self.onClose = onClose
        self._tab = StateObject(wrappedValue: MacTerminalTab(server: server))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content: terminal + optional inspector
            HSplitView {
                MacTerminalPane(
                    tab: tab,
                    session: sessionManager.activeSession(for: server.id),
                    onAIRequest: { selectedText in
                        if revenueCatService.canAccess(.aiAssistant) {
                            aiSelectedText = selectedText
                            showingAISheet = true
                        } else {
                            showingPaywall = true
                        }
                    },
                    onReconnect: {
                        sessionManager.closeSession(serverID: server.id)
                        tab.reconnectFailed = false
                        connectionError = nil
                        connectSession()
                    },
                    onClose: {
                        sessionManager.closeSession(serverID: server.id)
                    },
                    connectionError: connectionError
                )

                // Inspector pane (toggle-able)
                if showInspector {
                    MacInspectorView(
                        server: server,
                        statsEngine: sessionManager.statsEngine(for: server.id)
                    )
                    .frame(width: 200)
                }
            }

            // Status bar
            MacTerminalStatusBar(
                tab: tab,
                session: sessionManager.activeSession(for: server.id),
                statsEngine: sessionManager.statsEngine(for: server.id)
            )
        }
        .background(KestrelColors.background)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button {
                        sessionManager.closeSession(serverID: server.id)
                        onClose?()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                    .help("Close Terminal")

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showInspector.toggle()
                            inspectorPreference = showInspector
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .foregroundStyle(
                                showInspector ? KestrelColors.phosphorGreen : KestrelColors.textMuted
                            )
                    }
                    .help("Toggle Inspector")
                }
            }
        }
        .sheet(isPresented: $showingAISheet) {
            MacAIOverlaySheet(
                tab: tab,
                selectedText: aiSelectedText,
                session: sessionManager.activeSession(for: server.id)
            )
        }
        .sheet(isPresented: $showingPaywall) {
            MacPaywallView()
        }
        .sheet(isPresented: $showingPasswordPrompt) {
            VStack(spacing: 16) {
                Image(systemName: "key.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(KestrelColors.phosphorGreen)

                Text("Password Required")
                    .font(KestrelFonts.display(16, weight: .bold))
                    .foregroundStyle(KestrelColors.textPrimary)

                Text("\(server.username)@\(server.host)")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textMuted)

                if let error = connectionError {
                    Text(error)
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.red)
                        .multilineTextAlignment(.center)
                }

                SecureField("Password", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit { submitPassword() }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        showingPasswordPrompt = false
                        passwordInput = ""
                    }

                    Button("Connect") {
                        submitPassword()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KestrelColors.phosphorGreen)
                    .disabled(passwordInput.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 340)
        }
        .accessibilityLabel("SSH Terminal for \(server.name)")
        .onAppear {
            showInspector = inspectorPreference
            connectSession()
            HandoffManager.shared.advertiseTerminalSession(server: server)
        }
        .onDisappear {
            HandoffManager.shared.stopAdvertising()
        }
        .focusedSceneValue(\.macTerminalActions, MacTerminalActions(
            newTab: {},
            closeTab: {},
            clearTerminal: {},
            increaseFontSize: {},
            decreaseFontSize: {}
        ))
    }

    // MARK: - Actions

    private func connectSession() {
        Task {
            // Clean up any stale session first
            if let existing = sessionManager.activeSession(for: server.id), !existing.isConnected {
                sessionManager.closeSession(serverID: server.id)
            }

            // Already connected — just ensure shell is active
            if let existing = sessionManager.activeSession(for: server.id), existing.isConnected {
                if !existing.isShellActive { try? existing.startShell() }
                return
            }

            // Ensure password exists in macOS Keychain before connecting
            if server.authMethod != "privateKey" {
                let hasPassword = (try? KeychainService.loadPassword(for: server.id)) != nil
                if !hasPassword {
                    passwordInput = ""
                    connectionError = nil
                    showingPasswordPrompt = true
                    return
                }
            }

            do {
                let session = try await sessionManager.openSession(for: server)
                if !session.isShellActive { try session.startShell() }
            } catch {
                print("[SSH] Connection error for \(server.name): \(error)")
                connectionError = error.localizedDescription
                tab.reconnectFailed = true
            }
        }
    }

    private func submitPassword() {
        guard !passwordInput.isEmpty else { return }
        showingPasswordPrompt = false

        Task {
            try? KeychainService.savePassword(passwordInput, for: server.id)
            passwordInput = ""

            tab.reconnectFailed = false
            do {
                let session = try await sessionManager.openSession(for: server)
                if !session.isShellActive { try session.startShell() }
            } catch {
                print("[SSH] Connection error after password: \(error)")
                connectionError = error.localizedDescription
                tab.reconnectFailed = true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 36))
                .foregroundStyle(KestrelColors.textFaint)
            Text("No active sessions")
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KestrelColors.background)
    }
}

// MARK: - Focused Value for Keyboard Shortcuts

struct MacTerminalActions {
    var newTab: () -> Void
    var closeTab: () -> Void
    var clearTerminal: () -> Void
    var increaseFontSize: () -> Void
    var decreaseFontSize: () -> Void
}

struct MacTerminalActionsKey: FocusedValueKey {
    typealias Value = MacTerminalActions
}

extension FocusedValues {
    var macTerminalActions: MacTerminalActions? {
        get { self[MacTerminalActionsKey.self] }
        set { self[MacTerminalActionsKey.self] = newValue }
    }
}

// MARK: - Mac Session Tab Bar

struct MacSessionTabBar: View {
    let tabs: [MacTerminalTab]
    @Binding var activeTabID: UUID?
    var onAddTab: () -> Void
    var onCloseTab: (MacTerminalTab) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    tabButton(tab)
                }

                Button(action: onAddTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(KestrelColors.textMuted)
                        .frame(width: 24, height: 24)
                        .background(KestrelColors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 30)
        .background(KestrelColors.background.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(KestrelColors.cardBorder)
                .frame(height: 1)
        }
    }

    private func tabButton(_ tab: MacTerminalTab) -> some View {
        let isActive = tab.id == activeTabID

        return HStack(spacing: 5) {
            Circle()
                .fill(tab.server.serverEnvironment.colour)
                .frame(width: 6, height: 6)

            Text(tab.server.name)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(isActive ? KestrelColors.textPrimary : KestrelColors.textMuted)
                .lineLimit(1)

            Button {
                onCloseTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(KestrelColors.textFaint)
                    .frame(width: 14, height: 14)
                    .background(isActive ? KestrelColors.textFaint.opacity(0.2) : Color.clear)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isActive ? KestrelColors.backgroundCard : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .bottom) {
            if isActive {
                Capsule()
                    .fill(KestrelColors.phosphorGreen)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
                    .offset(y: 1)
            }
        }
        .onTapGesture { activeTabID = tab.id }
    }
}

// MARK: - Mac Terminal Pane

struct MacTerminalPane: View {
    @ObservedObject var tab: MacTerminalTab
    let session: SSHSession?
    var onAIRequest: ((String) -> Void)?
    var onReconnect: (() -> Void)?
    var onClose: (() -> Void)?
    var connectionError: String?

    @AppStorage("mac.terminal.fontSize") private var fontSize: Double = 12
    @AppStorage("mac.terminal.colorScheme") private var colorSchemeName = TerminalColorScheme.matchAppThemeID
    @AppStorage("app.theme") private var appThemeRaw = AppThemeID.phosphor.rawValue

    private var terminalScheme: TerminalColorScheme {
        if colorSchemeName == TerminalColorScheme.matchAppThemeID {
            let id = AppThemeID(rawValue: appThemeRaw) ?? .phosphor
            return .forAppTheme(id)
        }
        return TerminalColorScheme(rawValue: colorSchemeName) ?? .kestrel
    }

    var body: some View {
        ZStack {
            MacSwiftTermView(
                tab: tab,
                session: session,
                fontSize: CGFloat(fontSize),
                colorScheme: terminalScheme,
                onCursorUpdate: { line, col in
                    tab.cursorLine = line
                    tab.cursorCol = col
                },
                onSelectionRequest: { text in
                    onAIRequest?(text)
                }
            )

            // Reconnecting overlay
            if tab.isReconnecting || tab.reconnectFailed {
                reconnectingOverlay
            }
        }
    }

    private var reconnectingOverlay: some View {
        VStack(spacing: 12) {
            if tab.reconnectFailed {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 24))
                    .foregroundStyle(KestrelColors.red)
                Text("Connection Lost")
                    .font(KestrelFonts.monoBold(13))
                    .foregroundStyle(KestrelColors.textPrimary)

                if let error = connectionError {
                    Text(error)
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 250)
                }

                HStack(spacing: 10) {
                    Button {
                        onReconnect?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Reconnect")
                        }
                        .font(KestrelFonts.monoBold(11))
                        .foregroundStyle(KestrelColors.background)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(KestrelColors.phosphorGreen)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onClose?()
                    } label: {
                        Text("Close")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.textMuted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(KestrelColors.backgroundCard)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(KestrelColors.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ProgressView()
                    .tint(KestrelColors.phosphorGreen)
                Text("Reconnecting… (\(tab.reconnectAttempts)/\(tab.maxReconnectAttempts))")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textMuted)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - SwiftTerm NSViewRepresentable Bridge

// MARK: - Terminal Color Scheme

enum TerminalColorScheme: String, CaseIterable {
    case kestrel = "Kestrel"
    case classic = "Classic Green"
    case amber = "Amber"
    case solarized = "Solarized Dark"
    case dracula = "Dracula"
    case midnight = "Midnight"
    case arctic = "Arctic"
    case mono = "Mono"

    static let matchAppThemeID = "_match"

    static func forAppTheme(_ id: AppThemeID) -> TerminalColorScheme {
        switch id {
        case .phosphor: .kestrel
        case .dracula:  .dracula
        case .midnight: .midnight
        case .arctic:   .arctic
        case .ember:    .amber
        case .mono:     .mono
        }
    }

    var foreground: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .kestrel: (0, 1, 0.255)
        case .classic: (0, 1, 0)
        case .amber: (1, 0.722, 0)
        case .solarized: (0.514, 0.580, 0.588)
        case .dracula: (0.973, 0.973, 0.949)
        case .midnight: (0.85, 0.90, 1.0)
        case .arctic: (0.78, 0.92, 1.0)
        case .mono: (1, 1, 1)
        }
    }

    var background: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .kestrel: (0, 0, 0)
        case .classic: (0, 0, 0)
        case .amber: (0.05, 0.03, 0)
        case .solarized: (0, 0.169, 0.212)
        case .dracula: (0.157, 0.165, 0.212)
        case .midnight: (0.039, 0.055, 0.102)
        case .arctic: (0.039, 0.086, 0.157)
        case .mono: (0, 0, 0)
        }
    }

    var ansiPalette: [(UInt8, UInt8, UInt8)] {
        switch self {
        case .kestrel:
            [
                (0x1A, 0x1A, 0x1A), (0xFF, 0x3B, 0x5C), (0x00, 0xFF, 0x41), (0xFF, 0xB8, 0x00),
                (0x00, 0xC8, 0xFF), (0xCC, 0x66, 0xFF), (0x00, 0xE5, 0xCC), (0xCC, 0xCC, 0xCC),
                (0x55, 0x55, 0x55), (0xFF, 0x6B, 0x82), (0x66, 0xFF, 0x7F), (0xFF, 0xD7, 0x4D),
                (0x4D, 0xDA, 0xFF), (0xDD, 0x99, 0xFF), (0x4D, 0xF0, 0xDD), (0xFF, 0xFF, 0xFF),
            ]
        case .classic:
            [
                (0x00, 0x00, 0x00), (0xCC, 0x00, 0x00), (0x00, 0xCC, 0x00), (0xCC, 0xCC, 0x00),
                (0x00, 0x00, 0xCC), (0xCC, 0x00, 0xCC), (0x00, 0xCC, 0xCC), (0xCC, 0xCC, 0xCC),
                (0x55, 0x55, 0x55), (0xFF, 0x55, 0x55), (0x55, 0xFF, 0x55), (0xFF, 0xFF, 0x55),
                (0x55, 0x55, 0xFF), (0xFF, 0x55, 0xFF), (0x55, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF),
            ]
        case .amber:
            [
                (0x1A, 0x10, 0x00), (0xCC, 0x44, 0x00), (0xFF, 0xB8, 0x00), (0xFF, 0xDD, 0x55),
                (0xCC, 0x88, 0x00), (0xFF, 0x88, 0x44), (0xFF, 0xCC, 0x66), (0xCC, 0xAA, 0x66),
                (0x66, 0x44, 0x00), (0xFF, 0x66, 0x22), (0xFF, 0xCC, 0x33), (0xFF, 0xEE, 0x88),
                (0xFF, 0xAA, 0x33), (0xFF, 0xAA, 0x77), (0xFF, 0xDD, 0x99), (0xFF, 0xEE, 0xCC),
            ]
        case .solarized:
            [
                (0x07, 0x36, 0x42), (0xDC, 0x32, 0x2F), (0x85, 0x99, 0x00), (0xB5, 0x89, 0x00),
                (0x26, 0x8B, 0xD2), (0xD3, 0x36, 0x82), (0x2A, 0xA1, 0x98), (0xEE, 0xE8, 0xD5),
                (0x00, 0x2B, 0x36), (0xCB, 0x4B, 0x16), (0x58, 0x6E, 0x75), (0x65, 0x7B, 0x83),
                (0x83, 0x94, 0x96), (0x6C, 0x71, 0xC4), (0x93, 0xA1, 0xA1), (0xFD, 0xF6, 0xE3),
            ]
        case .dracula:
            [
                (0x28, 0x2A, 0x36), (0xFF, 0x55, 0x55), (0x50, 0xFA, 0x7B), (0xF1, 0xFA, 0x8C),
                (0xBD, 0x93, 0xF9), (0xFF, 0x79, 0xC6), (0x8B, 0xE9, 0xFD), (0xF8, 0xF8, 0xF2),
                (0x62, 0x72, 0xA4), (0xFF, 0x6E, 0x6E), (0x69, 0xFF, 0x94), (0xFF, 0xFB, 0xA6),
                (0xD6, 0xAC, 0xFF), (0xFF, 0x92, 0xDF), (0xA4, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF),
            ]
        case .midnight:
            [
                (0x0A, 0x0E, 0x1A), (0xFF, 0x3B, 0x5C), (0x66, 0xCC, 0x88), (0xFF, 0xB8, 0x00),
                (0x5B, 0x9C, 0xFF), (0xA8, 0x8B, 0xFF), (0x66, 0xD9, 0xEF), (0xCC, 0xD6, 0xE5),
                (0x3A, 0x4A, 0x66), (0xFF, 0x6B, 0x82), (0x88, 0xE0, 0xA8), (0xFF, 0xD7, 0x4D),
                (0x88, 0xC0, 0xFF), (0xC4, 0xAE, 0xFF), (0x99, 0xE8, 0xF5), (0xFF, 0xFF, 0xFF),
            ]
        case .arctic:
            [
                (0x0A, 0x16, 0x28), (0xFF, 0x5C, 0x6B), (0x66, 0xE0, 0xC8), (0xFF, 0xC8, 0x4D),
                (0x00, 0xD4, 0xFF), (0x99, 0xC8, 0xFF), (0x4D, 0xE8, 0xE8), (0xD6, 0xE8, 0xF5),
                (0x3A, 0x5A, 0x7A), (0xFF, 0x8B, 0x99), (0x99, 0xF0, 0xDD), (0xFF, 0xDC, 0x88),
                (0x66, 0xE4, 0xFF), (0xBB, 0xDC, 0xFF), (0x88, 0xF5, 0xF5), (0xFF, 0xFF, 0xFF),
            ]
        case .mono:
            [
                (0x00, 0x00, 0x00), (0xBB, 0xBB, 0xBB), (0xCC, 0xCC, 0xCC), (0xDD, 0xDD, 0xDD),
                (0xAA, 0xAA, 0xAA), (0xBB, 0xBB, 0xBB), (0xCC, 0xCC, 0xCC), (0xEE, 0xEE, 0xEE),
                (0x55, 0x55, 0x55), (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF),
                (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF),
            ]
        }
    }
}

// MARK: - SwiftTerm NSViewRepresentable Bridge

struct MacSwiftTermView: NSViewRepresentable {
    let tab: MacTerminalTab
    let session: SSHSession?
    let fontSize: CGFloat
    let colorScheme: TerminalColorScheme
    var onCursorUpdate: ((Int, Int) -> Void)?
    var onSelectionRequest: ((String) -> Void)?

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let font = terminalFont(size: fontSize)
        let tv = SwiftTerm.TerminalView(frame: .zero)
        tv.font = font

        applyColorScheme(to: tv)

        let terminal = tv.getTerminal()
        terminal.changeScrollback(10_000)

        tv.terminalDelegate = context.coordinator

        let magnify = NSMagnificationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMagnify(_:))
        )
        tv.addGestureRecognizer(magnify)

        return tv
    }

    func updateNSView(_ tv: SwiftTerm.TerminalView, context: Context) {
        if tv.font.pointSize != fontSize {
            tv.font = terminalFont(size: fontSize)
        }

        // Reapply color scheme when it changes
        applyColorScheme(to: tv)

        context.coordinator.session = session
        context.coordinator.onCursorUpdate = onCursorUpdate
        context.coordinator.onSelectionRequest = onSelectionRequest

        if let session, session.isConnected {
            context.coordinator.startOutputObservation(session: session, terminalView: tv)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, fontSize: fontSize)
    }

    // MARK: - Font

    private func terminalFont(size: CGFloat) -> NSFont {
        NSFont(name: "SFMono-Regular", size: size)
            ?? NSFont(name: "Menlo", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - Color Scheme Application

    private func applyColorScheme(to tv: SwiftTerm.TerminalView) {
        let fg = colorScheme.foreground
        let bg = colorScheme.background

        tv.nativeBackgroundColor = NSColor(red: bg.0, green: bg.1, blue: bg.2, alpha: 1)
        tv.nativeForegroundColor = NSColor(red: fg.0, green: fg.1, blue: fg.2, alpha: 0.88)

        // Cursor matches foreground
        let terminal = tv.getTerminal()
        terminal.cursorColor = SwiftTerm.Color(
            red: UInt16(fg.0 * 65535),
            green: UInt16(fg.1 * 65535),
            blue: UInt16(fg.2 * 65535)
        )

        // ANSI palette
        let colors = colorScheme.ansiPalette.map { r, g, b in
            SwiftTerm.Color(red: UInt16(r) << 8, green: UInt16(g) << 8, blue: UInt16(b) << 8)
        }
        tv.installColors(colors)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, TerminalViewDelegate {
        var session: SSHSession?
        var onCursorUpdate: ((Int, Int) -> Void)?
        var onSelectionRequest: ((String) -> Void)?
        private var fontSize: CGFloat
        private var baseFontSize: CGFloat
        private var observedSessionID: UUID?
        private var outputObserverTask: Task<Void, Never>?
        private var inputBuffer = ""

        init(session: SSHSession?, fontSize: CGFloat) {
            self.session = session
            self.fontSize = fontSize
            self.baseFontSize = fontSize
        }

        deinit {
            outputObserverTask?.cancel()
        }

        // MARK: - Output Observation

        func startOutputObservation(session: SSHSession, terminalView: SwiftTerm.TerminalView) {
            if observedSessionID != session.serverID {
                outputObserverTask?.cancel()
                observedSessionID = session.serverID
            } else if outputObserverTask != nil && !(outputObserverTask?.isCancelled ?? true) {
                return
            }

            outputObserverTask = Task { @MainActor in
                var lastLength = 0
                while !Task.isCancelled {
                    let currentOutput = session.output
                    if currentOutput.count > lastLength {
                        let newContent = String(currentOutput.dropFirst(lastLength))
                        lastLength = currentOutput.count
                        terminalView.feed(text: newContent)
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }

        // MARK: - Magnification Gesture

        @objc func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
            guard let tv = gesture.view as? SwiftTerm.TerminalView else { return }
            switch gesture.state {
            case .began:
                baseFontSize = tv.font.pointSize
            case .changed, .ended:
                let newSize = baseFontSize * (1 + gesture.magnification)
                let clamped = min(max(newSize, 8), 24).rounded()
                let font = NSFont(name: "SFMono-Regular", size: clamped)
                    ?? NSFont(name: "Menlo", size: clamped)
                    ?? NSFont.monospacedSystemFont(ofSize: clamped, weight: .regular)
                tv.font = font
                fontSize = clamped
            default:
                break
            }
        }

        // MARK: - TerminalViewDelegate

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            guard newCols > 0, newRows > 0 else { return }
            Task { @MainActor in
                session?.resizeTerminal(cols: newCols, rows: newRows)
            }
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            let string = String(bytes: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                session?.send(string)
            }

            // Track cursor position via input
            if string.contains("\r") || string.contains("\n") {
                inputBuffer = ""
            } else {
                inputBuffer.append(string)
            }
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}

        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        }

        func bell(source: SwiftTerm.TerminalView) {
            NSSound.beep()
        }

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            if let string = String(data: content, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(string, forType: .string)
            }
        }

        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
            onCursorUpdate?(endY + 1, 1)
        }
    }
}

// MARK: - Mac Inspector View

struct MacInspectorView: View {
    let server: Server
    let statsEngine: ServerStatsEngine?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Section 1: Live Stats
                liveStatsSection

                Divider().overlay(KestrelColors.cardBorder)

                // Section 2: Top Processes
                processesSection

                Divider().overlay(KestrelColors.cardBorder)

                // Section 3: Connected Devices
                connectedDevicesSection
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
        .background(KestrelColors.backgroundCard)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(KestrelColors.cardBorder)
                .frame(width: 1)
        }
    }

    // MARK: - Live Stats

    @ViewBuilder
    private var liveStatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STATS")
                .font(KestrelFonts.mono(9))
                .tracking(1.2)
                .foregroundStyle(KestrelColors.textFaint)

            if let stats = statsEngine?.stats {
                // CPU
                inspectorStatRow(
                    label: "CPU",
                    value: "\(Int(stats.cpuPercent))%",
                    progress: stats.cpuPercent / 100,
                    color: cpuColor(stats.cpuPercent)
                )

                // Memory
                inspectorStatRow(
                    label: "MEM",
                    value: "\(Int(stats.memoryUsedPercent))%",
                    progress: stats.memoryUsedPercent / 100,
                    color: KestrelColors.blue
                )

                // Disk
                if let disk = stats.diskMounts.first {
                    inspectorStatRow(
                        label: "DISK",
                        value: "\(Int(disk.usedPercent))%",
                        progress: disk.usedPercent / 100,
                        color: KestrelColors.amber
                    )
                }

                // Network
                if let net = stats.netInterfaces.first {
                    HStack {
                        Text("NET")
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textFaint)
                            .frame(width: 32, alignment: .leading)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("↓ \(String(format: "%.1f", net.rxMbps)) Mbps")
                                .font(KestrelFonts.mono(9))
                                .foregroundStyle(KestrelColors.phosphorGreen)
                            Text("↑ \(String(format: "%.1f", net.txMbps)) Mbps")
                                .font(KestrelFonts.mono(9))
                                .foregroundStyle(KestrelColors.blue)
                        }
                    }
                }
            } else {
                // Skeleton placeholders
                ForEach(0..<3, id: \.self) { _ in
                    skeletonRow
                }
            }
        }
    }

    private func inspectorStatRow(label: String, value: String, progress: Double, color: SwiftUI.Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
                Spacer()
                Text(value)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textPrimary)
                    .monospacedDigit()
            }
            MiniBar(progress: progress, color: color)
        }
    }

    private func cpuColor(_ percent: Double) -> SwiftUI.Color {
        if percent > 85 { return KestrelColors.red }
        if percent > 60 { return KestrelColors.amber }
        return KestrelColors.phosphorGreen
    }

    private var skeletonRow: some View {
        VStack(spacing: 3) {
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(KestrelColors.textFaint.opacity(0.3))
                    .frame(width: 28, height: 10)
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(KestrelColors.textFaint.opacity(0.3))
                    .frame(width: 32, height: 10)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(KestrelColors.textFaint.opacity(0.15))
                .frame(height: 4)
        }
    }

    // MARK: - Top Processes

    @ViewBuilder
    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROCESSES")
                .font(KestrelFonts.mono(9))
                .tracking(1.2)
                .foregroundStyle(KestrelColors.textFaint)

            if let stats = statsEngine?.stats, !stats.processes.isEmpty {
                ForEach(stats.processes.prefix(6)) { proc in
                    HStack(spacing: 4) {
                        Text(proc.command.components(separatedBy: "/").last ?? proc.command)
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textMuted)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(Int(proc.cpuPercent))%")
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(cpuColor(proc.cpuPercent))
                            .monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            // TODO: kill process via SSH
                        } label: {
                            Label("Kill Process (\(proc.pid))", systemImage: "xmark.circle")
                        }
                    }
                }
            } else {
                Text("Connect to view processes")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            }
        }
    }

    // MARK: - Connected Devices

    @ViewBuilder
    private var connectedDevicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEVICES")
                .font(KestrelFonts.mono(9))
                .tracking(1.2)
                .foregroundStyle(KestrelColors.textFaint)

            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 10))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                Text("This Mac")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textMuted)
                Spacer()
                Text("now")
                    .font(KestrelFonts.mono(8))
                    .foregroundStyle(KestrelColors.textFaint)
            }

            // Placeholder for other devices from SupabaseService
            Text("Sync more devices via Kestrel Cloud")
                .font(KestrelFonts.mono(8))
                .foregroundStyle(KestrelColors.textFaint)
                .padding(.top, 4)
        }
    }
}

// MARK: - Mac Terminal Status Bar

struct MacTerminalStatusBar: View {
    @ObservedObject var tab: MacTerminalTab
    let session: SSHSession?
    let statsEngine: ServerStatsEngine?

    var body: some View {
        HStack(spacing: 0) {
            // Left: connection status
            HStack(spacing: 5) {
                Circle()
                    .fill(session?.isConnected == true ? KestrelColors.phosphorGreen : KestrelColors.red)
                    .frame(width: 6, height: 6)
                Text(session?.isConnected == true ? "Connected" : "Disconnected")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Centre: server · host:port
            HStack(spacing: 4) {
                Text(tab.server.name)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textPrimary)
                Text("·")
                    .foregroundStyle(KestrelColors.textFaint)
                Text("\(tab.server.host):\(tab.server.port)")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textMuted)
            }

            // Centre-right: OS + kernel
            if let stats = statsEngine?.stats, !stats.osName.isEmpty {
                HStack(spacing: 4) {
                    Text("·")
                        .foregroundStyle(KestrelColors.textFaint)
                    Text(stats.osName)
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textFaint)
                    if !stats.kernelVersion.isEmpty {
                        Text(stats.kernelVersion)
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                }
            }

            Spacer()

            // Right: cursor position + encoding
            HStack(spacing: 8) {
                Text("Ln \(tab.cursorLine), Col \(tab.cursorCol)")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
                    .monospacedDigit()
                Text("UTF-8")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(KestrelColors.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }
}

// MARK: - Mac AI Overlay Sheet

struct MacAIOverlaySheet: View {
    let tab: MacTerminalTab
    let selectedText: String
    let session: SSHSession?

    @Environment(\.dismiss) private var dismiss

    @State private var customPrompt = ""
    @State private var response = ""
    @State private var isStreaming = false
    @State private var extractedCommands: [String] = []
    @State private var streamingTask: Task<Void, Never>?
    @State private var showingRunConfirmation = false
    @State private var commandToRun = ""

    private let quickPrompts = [
        "Explain this output",
        "What went wrong?",
        "How do I fix this?",
    ]

    private let systemPrompt = """
    You are an expert Linux/networking sysadmin assistant embedded in a terminal app. \
    Analyse the terminal output provided and explain what it means. \
    If there is an error, identify the root cause clearly and provide the specific command to fix it. \
    Be concise and technical.
    """

    private var contextLines: String {
        if !selectedText.isEmpty { return selectedText }
        let lines = tab.transcript
            .components(separatedBy: "\n")
            .suffix(20)
            .joined(separator: "\n")
        return lines.isEmpty ? "(no terminal output)" : lines
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("AI Assistant")
                    .font(KestrelFonts.monoBold(13))
                    .foregroundStyle(KestrelColors.textPrimary)
                Spacer()
                Button("Done") {
                    streamingTask?.cancel()
                    dismiss()
                }
                .foregroundStyle(KestrelColors.textMuted)
            }
            .padding()

            Divider().overlay(KestrelColors.cardBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Context preview
                    contextCard

                    // Quick prompts
                    quickPromptsRow

                    // Custom prompt
                    customPromptField

                    // Response
                    if !response.isEmpty || isStreaming {
                        responseCard
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(KestrelColors.background)
        .confirmationDialog(
            "Run this command?",
            isPresented: $showingRunConfirmation,
            titleVisibility: .visible
        ) {
            Button("Run") { session?.send(commandToRun + "\n") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(commandToRun)
        }
        .onDisappear { streamingTask?.cancel() }
    }

    // MARK: - Subviews

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TERMINAL CONTEXT")
                    .font(KestrelFonts.mono(9))
                    .tracking(1.2)
                    .foregroundStyle(KestrelColors.textFaint)
                Spacer()
                Text("\(contextLines.components(separatedBy: "\n").count) lines")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            ScrollView {
                Text(contextLines)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)
            .padding(8)
            .background(KestrelColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
            )
        }
    }

    private var quickPromptsRow: some View {
        HStack(spacing: 8) {
            ForEach(quickPrompts, id: \.self) { prompt in
                Button { sendPrompt(prompt) } label: {
                    Text(prompt)
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.purple.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(.purple.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isStreaming)
            }
        }
    }

    private var customPromptField: some View {
        HStack(spacing: 8) {
            TextField("Ask about the output…", text: $customPrompt)
                .font(KestrelFonts.mono(12))
                .textFieldStyle(.plain)
                .padding(8)
                .background(KestrelColors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                )
                .onSubmit {
                    if !customPrompt.isEmpty { sendPrompt(customPrompt) }
                }

            Button { sendPrompt(customPrompt) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(customPrompt.isEmpty ? KestrelColors.textFaint : .purple)
            }
            .buttonStyle(.plain)
            .disabled(customPrompt.isEmpty || isStreaming)
        }
    }

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)
                Text("AI Response")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(.purple)
                Spacer()
                if isStreaming {
                    Button {
                        streamingTask?.cancel()
                        isStreaming = false
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.red)
                    }
                    .buttonStyle(.plain)
                    ProgressView()
                        .scaleEffect(0.5)
                        .tint(.purple)
                }
            }

            Text(response + (isStreaming ? "▌" : ""))
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Extracted commands
            ForEach(extractedCommands, id: \.self) { command in
                Button {
                    commandToRun = command
                    showingRunConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Text("$")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                        Text(command)
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textPrimary)
                            .lineLimit(2)
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                    }
                    .padding(8)
                    .background(KestrelColors.phosphorGreenDim)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.purple.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - AI Actions

    private func sendPrompt(_ prompt: String) {
        guard !isStreaming else { return }
        isStreaming = true
        response = ""
        extractedCommands = []
        customPrompt = ""

        let fullPrompt = """
        Terminal output:
        ```
        \(contextLines)
        ```

        User question: \(prompt)
        """

        streamingTask = Task { await streamResponse(prompt: fullPrompt) }
    }

    private func streamResponse(prompt: String) async {
        let apiKey = UserDefaults.standard.string(forKey: "claude_api_key") ?? ""

        guard !apiKey.isEmpty else {
            // Simulated fallback
            let placeholder = "To enable AI analysis, add your Claude API key in Settings → Account."
            for char in placeholder {
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .milliseconds(15))
                await MainActor.run { response.append(char) }
            }
            await MainActor.run { isStreaming = false }
            return
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "stream": true,
            "system": systemPrompt,
            "messages": [["role": "user", "content": prompt]]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            await MainActor.run { response = "Error: Failed to encode request."; isStreaming = false }
            return
        }
        request.httpBody = httpBody

        do {
            let (bytes, httpResponse) = try await URLSession.shared.bytes(for: request)
            guard (httpResponse as? HTTPURLResponse)?.statusCode == 200 else {
                await MainActor.run { response = "Error: API request failed."; isStreaming = false }
                return
            }

            for try await line in bytes.lines {
                guard !Task.isCancelled else { break }
                guard line.hasPrefix("data: ") else { continue }
                let jsonString = String(line.dropFirst(6))
                guard jsonString != "[DONE]",
                      let data = jsonString.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                if event["type"] as? String == "content_block_delta",
                   let delta = event["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    await MainActor.run { response.append(text) }
                }
                if event["type"] as? String == "message_stop" { break }
            }

            await MainActor.run { isStreaming = false; extractCommands() }
        } catch {
            if !Task.isCancelled {
                await MainActor.run { response += "\n\n[Error: \(error.localizedDescription)]"; isStreaming = false; extractCommands() }
            }
        }
    }

    private func extractCommands() {
        let lines = response.components(separatedBy: "\n")
        var inCodeBlock = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inCodeBlock.toggle(); continue }
            if inCodeBlock && !trimmed.isEmpty {
                let cleaned = trimmed.hasPrefix("$ ") ? String(trimmed.dropFirst(2)) : trimmed
                if !cleaned.hasPrefix("#") && !cleaned.isEmpty { extractedCommands.append(cleaned) }
            } else if trimmed.hasPrefix("$ ") {
                extractedCommands.append(String(trimmed.dropFirst(2)))
            }
        }
    }
}
