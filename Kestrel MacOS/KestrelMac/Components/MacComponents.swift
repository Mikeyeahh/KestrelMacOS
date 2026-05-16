//
//  MacComponents.swift
//  Kestrel Mac
//
//  macOS-specific component adaptations of the Kestrel design system.
//  Uses the same KestrelColors constants as iOS (#00FF9C, #FFB800, #FF3B5C, #00C8FF).
//

import SwiftUI
import AppKit

// MARK: - Mac Title Bar

struct MacTitleBar: View {
    let serverName: String
    let status: ServerStatus
    let activeTabCount: Int
    @Binding var selectedView: MacViewMode
    var syncStatus: SyncStatus = .idle
    var onAddTab: (() -> Void)? = nil
    var onCloseTab: (() -> Void)? = nil

    enum MacViewMode: String, CaseIterable {
        case terminal = "Terminal"
        case dashboard = "Dashboard"
    }

    enum SyncStatus {
        case idle, syncing, synced, error

        var icon: String {
            switch self {
            case .idle: "cloud"
            case .syncing: "arrow.triangle.2.circlepath.icloud"
            case .synced: "checkmark.icloud"
            case .error: "exclamationmark.icloud"
            }
        }

        var color: Color {
            switch self {
            case .idle: KestrelColors.textFaint
            case .syncing: KestrelColors.amber
            case .synced: KestrelColors.phosphorGreen
            case .error: KestrelColors.red
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Server name + status
            HStack(spacing: 6) {
                Circle()
                    .fill(status.color)
                    .frame(width: 7, height: 7)
                Text(serverName)
                    .font(KestrelFonts.monoBold(12))
                    .foregroundStyle(KestrelColors.textPrimary)
            }

            Divider()
                .frame(height: 14)

            // Tab controls
            HStack(spacing: 4) {
                Text("\(activeTabCount) session\(activeTabCount == 1 ? "" : "s")")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textMuted)

                Button(action: { onAddTab?() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                .buttonStyle(.plain)

                Button(action: { onCloseTab?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(KestrelColors.textFaint)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // View toggle
            Picker("", selection: $selectedView) {
                ForEach(MacViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            // Sync status
            Image(systemName: syncStatus.icon)
                .font(.system(size: 12))
                .foregroundStyle(syncStatus.color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(KestrelColors.background.opacity(0.95))
    }
}

// MARK: - Transparent Title Bar Bridge

struct TransparentTitleBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                TransparentTitleBarHelper()
            }
    }
}

private struct TransparentTitleBarHelper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = NSColor.black
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func transparentTitleBar() -> some View {
        modifier(TransparentTitleBarModifier())
    }
}

// MARK: - Mac Toolbar Content

struct MacToolbarContent: ToolbarContent {
    let serverName: String
    let serverOS: String
    @Binding var selectedView: MacTitleBar.MacViewMode

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: { selectedView = .terminal }) {
                Label("Terminal", systemImage: "keyboard")
                    .foregroundStyle(
                        selectedView == .terminal
                            ? KestrelColors.phosphorGreen
                            : KestrelColors.textMuted
                    )
            }
            .help("Terminal")
        }

        ToolbarItem(placement: .navigation) {
            Button(action: { selectedView = .dashboard }) {
                Label("Dashboard", systemImage: "chart.bar")
                    .foregroundStyle(
                        selectedView == .dashboard
                            ? KestrelColors.phosphorGreen
                            : KestrelColors.textMuted
                    )
            }
            .help("Dashboard")
        }

        ToolbarItem(placement: .navigation) {
            Button(action: {}) {
                Label("Files", systemImage: "folder")
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .help("SFTP Browser")
        }

        ToolbarItem(placement: .navigation) {
            Button(action: {}) {
                Label("Services", systemImage: "square.stack.3d.up")
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .help("Services")
        }

        ToolbarItem(placement: .navigation) {
            Button(action: {}) {
                Label("AI", systemImage: "sparkles")
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .help("AI Assistant")
        }

        ToolbarItem(placement: .principal) {
            Spacer()
        }

        ToolbarItem(placement: .status) {
            HStack(spacing: 4) {
                Text(serverName)
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textPrimary)
                Text("·")
                    .foregroundStyle(KestrelColors.textFaint)
                Text(serverOS)
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textMuted)
            }
        }
    }
}

// MARK: - Mac Sidebar Row

struct MacSidebarRow: View {
    let server: Server
    let isSelected: Bool
    var pingMs: Int? = nil

    var body: some View {
        HStack(spacing: 8) {
            // Left accent bar for active state
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? server.status.color : Color.clear)
                .frame(width: 3, height: 22)

            // Status dot
            Circle()
                .fill(server.status.color)
                .frame(width: 6, height: 6)

            // Server name
            Text(server.name)
                .font(KestrelFonts.mono(12))
                .foregroundStyle(
                    isSelected ? KestrelColors.textPrimary : KestrelColors.textMuted
                )
                .lineLimit(1)

            Spacer(minLength: 4)

            // Environment badge
            Text(server.serverEnvironment.badge)
                .font(KestrelFonts.mono(8))
                .fontWeight(.bold)
                .tracking(0.5)
                .foregroundStyle(server.serverEnvironment.colour)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(server.serverEnvironment.colour.opacity(0.12))
                .clipShape(Capsule())

            // Ping
            if let pingMs {
                Text("\(pingMs)ms")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            }
        }
        .frame(height: 32)
        .padding(.horizontal, 6)
        .background(
            isSelected
                ? KestrelColors.phosphorGreenDim
                : Color.clear
        )
        .cornerRadius(6)
    }
}

// MARK: - Mac Sidebar Section Header

struct MacSidebarSectionHeader: View {
    let title: String
    var accentColor: Color? = nil

    var body: some View {
        Text(title.uppercased())
            .font(KestrelFonts.mono(10))
            .fontWeight(.medium)
            .tracking(1.2)
            .foregroundStyle(accentColor ?? KestrelColors.textFaint)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

// MARK: - Hex Color Helpers

extension Color {
    /// Initialize a Color from a `#RRGGBB` or `#RRGGBBAA` hex string.
    /// Returns nil for malformed input.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8,
              let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        } else {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Returns a `#RRGGBB` representation of the color (alpha discarded).
    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Mac Sidebar Cloud Sync Row

struct MacSidebarSyncRow: View {
    let syncStatus: MacTitleBar.SyncStatus
    var lastSynced: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: syncStatus.icon)
                .font(.system(size: 11))
                .foregroundStyle(syncStatus.color)

            VStack(alignment: .leading, spacing: 1) {
                Text("Cloud Sync")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textMuted)
                if let lastSynced {
                    Text(lastSynced)
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(KestrelColors.textFaint)
                }
            }

            Spacer()
        }
        .frame(height: 32)
        .padding(.horizontal, 10)
    }
}

// MARK: - Mac Sidebar Account Row

struct MacSidebarAccountRow: View {
    let displayName: String
    var isSignedIn: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.system(size: 14))
                .foregroundStyle(
                    isSignedIn ? KestrelColors.phosphorGreen : KestrelColors.textFaint
                )

            Text(displayName)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textMuted)
                .lineLimit(1)

            Spacer()
        }
        .frame(height: 32)
        .padding(.horizontal, 10)
    }
}

// MARK: - Mac Content Split View

struct MacContentSplitView<Sidebar: View, Content: View, Inspector: View>: View {
    @Binding var showInspector: Bool
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var content: () -> Content
    @ViewBuilder var inspector: () -> Inspector

    var body: some View {
        NavigationSplitView {
            sidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 500)
        } detail: {
            HStack(spacing: 0) {
                content()
                    .frame(minWidth: 500)

                if showInspector {
                    Divider()
                    inspector()
                        .frame(width: 210)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
