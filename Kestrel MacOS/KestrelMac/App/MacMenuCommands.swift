//
//  MacMenuCommands.swift
//  Kestrel Mac
//
//  Native macOS menu bar commands.
//

import SwiftUI

// MARK: - Kestrel Menu Commands

struct KestrelMenuCommands: Commands {
    @FocusedValue(\.macTerminalActions) var terminalActions

    var body: some Commands {
        // Servers menu
        CommandMenu("Servers") {
            Button("New Server…") {
                NotificationCenter.default.post(name: .kestrelAddServer, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Import Servers…") {
                NotificationCenter.default.post(name: .kestrelImportServers, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Multi-Execute…") {
                NotificationCenter.default.post(name: .kestrelMultiExec, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            Button("Connect") {
                // Connect selected server
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button("Disconnect") {
                // Disconnect selected server
            }
        }

        // Terminal menu
        CommandMenu("Terminal") {
            Button("New Tab") {
                terminalActions?.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") {
                terminalActions?.closeTab()
            }
            .keyboardShortcut("w", modifiers: .command)

            Divider()

            Button("Clear Terminal") {
                terminalActions?.clearTerminal()
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Split Pane") {
                // Future: split terminal pane
            }
            .keyboardShortcut("d", modifiers: .command)

            Divider()

            Button("Increase Font Size") {
                terminalActions?.increaseFontSize()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Decrease Font Size") {
                terminalActions?.decreaseFontSize()
            }
            .keyboardShortcut("-", modifiers: .command)
        }

        // View menu additions
        CommandGroup(after: .toolbar) {
            Button("Show Inspector") {
                NotificationCenter.default.post(name: .kestrelToggleInspector, object: nil)
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Show Dashboard") {
                NotificationCenter.default.post(name: .kestrelShowDashboard, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Show Files") {
                NotificationCenter.default.post(name: .kestrelShowFiles, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        // Sync menu
        CommandMenu("Sync") {
            Button("Sync Now") {
                NotificationCenter.default.post(name: .kestrelSyncNow, object: nil)
            }

            Button("Open OSPREY") {
                if let url = URL(string: "osprey://") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - Additional Notification Names

extension Notification.Name {
    static let kestrelToggleInspector = Notification.Name("kestrelToggleInspector")
    static let kestrelShowDashboard = Notification.Name("kestrelShowDashboard")
    static let kestrelShowFiles = Notification.Name("kestrelShowFiles")
    static let kestrelSyncNow = Notification.Name("kestrelSyncNow")
    static let kestrelDeepLink = Notification.Name("kestrelDeepLink")
    static let kestrelImportServers = Notification.Name("kestrelImportServers")
    static let kestrelMultiExec = Notification.Name("kestrelMultiExec")
}
