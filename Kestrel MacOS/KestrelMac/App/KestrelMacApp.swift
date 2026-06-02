//
//  KestrelMacApp.swift
//  Kestrel Mac
//
//  Created by Mike on 10/04/2026.
//

import SwiftUI
import RevenueCat
import StoreKit

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
                // Outside `.id(themeID)` so a theme switch doesn't reset it.
                .reviewPrompt()
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

// MARK: - App Review Prompts

/// Decides when to surface the system "rate this app" prompt. It asks only
/// after a few positive moments (successful connections) and never more than
/// once per app version. StoreKit additionally caps the prompt at three times
/// per year, so this stays well within Apple's guidance.
@MainActor
final class AppReviewManager: ObservableObject {
    static let shared = AppReviewManager()

    /// Flips to `true` when a prompt is warranted. The root view observes this,
    /// invokes the StoreKit request, then calls `markPrompted()`.
    @Published var pendingReviewRequest = false

    private let milestoneCountKey = "kestrel.review.milestoneCount"
    private let lastPromptedVersionKey = "kestrel.review.lastPromptedVersion"

    /// Successful connections required before we consider prompting.
    private let milestoneThreshold = 3

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private init() {}

    /// Record a positive moment (e.g. a server connected successfully).
    func recordMilestone() {
        let defaults = UserDefaults.standard
        // Already asked on this version — don't pester until the next update.
        guard defaults.string(forKey: lastPromptedVersionKey) != currentVersion else { return }

        let count = defaults.integer(forKey: milestoneCountKey) + 1
        defaults.set(count, forKey: milestoneCountKey)
        if count >= milestoneThreshold {
            pendingReviewRequest = true
        }
    }

    /// Called by the view layer once the prompt has been requested.
    func markPrompted() {
        pendingReviewRequest = false
        let defaults = UserDefaults.standard
        defaults.set(currentVersion, forKey: lastPromptedVersionKey)
        defaults.set(0, forKey: milestoneCountKey)
    }
}

private struct ReviewPromptModifier: ViewModifier {
    @Environment(\.requestReview) private var requestReview
    @ObservedObject private var manager = AppReviewManager.shared

    func body(content: Content) -> some View {
        content.onChange(of: manager.pendingReviewRequest) { _, pending in
            guard pending else { return }
            Task { @MainActor in
                // Brief delay so the prompt doesn't collide with the
                // connection UI that just appeared.
                try? await Task.sleep(for: .seconds(1.5))
                requestReview()
                manager.markPrompted()
            }
        }
    }
}

extension View {
    /// Surfaces the system review prompt at appropriate moments. Attach once
    /// near the app's root.
    func reviewPrompt() -> some View { modifier(ReviewPromptModifier()) }
}
