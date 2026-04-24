//
//  ThemeManager.swift
//  Kestrel Mac
//
//  Singleton that persists and provides the active system UI theme.
//

import Foundation

final class ThemeManager {
    static let shared = ThemeManager()

    var currentThemeID: AppThemeID {
        didSet {
            UserDefaults.standard.set(currentThemeID.rawValue, forKey: "app.theme")
        }
    }

    var current: AppTheme { currentThemeID.theme }

    private init() {
        let stored = UserDefaults.standard.string(forKey: "app.theme") ?? ""
        self.currentThemeID = AppThemeID(rawValue: stored) ?? .phosphor
    }
}
