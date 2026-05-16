//
//  KestrelMacApp.swift
//  Kestrel Mac
//
//  Created by Mike on 10/04/2026.
//

import SwiftUI
import RevenueCat

@main
struct KestrelMacApp: App {
    @StateObject private var revenueCatService = RevenueCatService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @StateObject private var sshSessionManager = SSHSessionManager()
    @StateObject private var serverRepository = ServerRepository()
    @StateObject private var deepLinkHandler = DeepLinkHandler.shared
    @StateObject private var notificationManager = KestrelNotificationManager.shared
    @AppStorage("app.theme") private var themeID = "Phosphor"

    init() {
        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: "appl_NrjcEYMRTSJeVklytqRaAFhQcPm")
    }

    var body: some Scene {
        WindowGroup {
            MacContentView()
                .id(themeID)
                .onChange(of: themeID) { _, newValue in
                    if let id = AppThemeID(rawValue: newValue) {
                        ThemeManager.shared.currentThemeID = id
                    }
                }
                .environmentObject(revenueCatService)
                .environmentObject(supabaseService)
                .environmentObject(sshSessionManager)
                .environmentObject(serverRepository)
                .environmentObject(deepLinkHandler)
                .preferredColorScheme(.dark)
                .transparentTitleBar()
                .onReceive(NotificationCenter.default.publisher(for: .kestrelSyncNow)) { _ in
                    Task { try? await supabaseService.syncNow() }
                }
            // Sync task lives outside .id() so theme changes don't kill it
            .task {
                // Wait up to 5 seconds for Supabase session to restore
                for _ in 0..<10 {
                    if supabaseService.isAuthenticated { break }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                print("[Sync] Auth state: \(supabaseService.isAuthenticated), email: \(supabaseService.userEmail ?? "nil")")
                await serverRepository.loadFromCloud()
                serverRepository.startAutoSync()
            }
            .onChange(of: supabaseService.isAuthenticated) { _, isAuthed in
                if isAuthed {
                    print("[Sync] Auth flipped to true, syncing now")
                    Task {
                        await serverRepository.loadFromCloud()
                        serverRepository.startAutoSync()
                    }
                } else {
                    print("[Sync] Auth flipped to false, clearing local state")
                    serverRepository.clearAll()
                    sshSessionManager.closeAllSessions()
                }
            }
        }
        .defaultSize(width: 1400, height: 900)
        // Deep link handling
        .handlesExternalEvents(matching: ["kestrel", "osprey"])
        // Handoff from iOS
        .commands {
            KestrelMenuCommands()
        }

        Settings {
            MacSettingsView()
                .environmentObject(revenueCatService)
                .environmentObject(supabaseService)
                .environmentObject(serverRepository)
                .preferredColorScheme(.dark)
        }

        MenuBarExtra("Kestrel", systemImage: "server.rack") {
            MenuBarView()
                .environmentObject(sshSessionManager)
                .environmentObject(serverRepository)
                .environmentObject(supabaseService)
        }
        .menuBarExtraStyle(.window)
    }
}
