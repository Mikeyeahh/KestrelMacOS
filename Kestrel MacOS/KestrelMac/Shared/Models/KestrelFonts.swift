//
//  KestrelFonts.swift
//  Kestrel Mac
//
//  Identical copy of the iOS font definitions — keep in sync.
//  Replace with shared DesignSystem/Theme/KestrelFonts.swift when targets are unified.
//

import SwiftUI
import AppKit

// MARK: - App Font (whole-UI typeface; synced via user_settings)
//
// Defined here (rather than a standalone file) because the macOS target uses
// classic Xcode groups — keeping it in an already-compiled file avoids a
// project.pbxproj edit. Raw values match the iOS/Windows ids so the choice
// syncs across platforms.

enum AppFontID: String, CaseIterable, Identifiable {
    case jetbrainsMono = "jetbrains-mono"
    case ibmPlexMono   = "ibm-plex-mono"
    case spaceMono     = "space-mono"
    case inter         = "inter"
    case outfit        = "outfit"
    case system        = "system"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jetbrainsMono: "JetBrains Mono"
        case .ibmPlexMono:   "IBM Plex Mono"
        case .spaceMono:     "Space Mono"
        case .inter:         "Inter"
        case .outfit:        "Outfit"
        case .system:        "System"
        }
    }

    var isMono: Bool {
        switch self {
        case .jetbrainsMono, .ibmPlexMono, .spaceMono: true
        case .inter, .outfit, .system: false
        }
    }

    /// Bundled font family base name (the "-Regular" PostScript stem). `nil`
    /// uses the system font. NOTE: the matching .ttf files must be added to the
    /// app's Fonts resources (target membership + ATSApplicationFontsPath);
    /// until then this falls back to the system font.
    var baseFontName: String? {
        switch self {
        case .jetbrainsMono: "JetBrainsMono-Regular"
        case .ibmPlexMono:   "IBMPlexMono-Regular"
        case .spaceMono:     "SpaceMono-Regular"
        case .inter:         "Inter18pt-Regular"
        case .outfit:        "Outfit-Regular"
        case .system:        nil
        }
    }

    var systemDesign: Font.Design { isMono ? .monospaced : .default }
}

/// Singleton that persists and provides the active UI font. Mirrors `ThemeManager`.
final class FontManager {
    static let shared = FontManager()

    var currentFontID: AppFontID {
        didSet {
            UserDefaults.standard.set(currentFontID.rawValue, forKey: "app.font")
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: "app.font") ?? ""
        self.currentFontID = AppFontID(rawValue: stored) ?? .jetbrainsMono
    }
}

enum KestrelFonts {
    /// Builds a Font for a SPECIFIC app font id — used by the Settings picker so
    /// each tile previews in its own typeface, and internally by the helpers
    /// below for the active choice. Falls back to the system font when the
    /// bundled .ttf isn't installed yet.
    static func fontForID(_ font: AppFontID, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let base = font.baseFontName {
            let weighted = weightedName(base: base, weight: weight)
            if NSFont(name: weighted, size: size) != nil {
                return .custom(weighted, size: size)
            }
            if NSFont(name: base, size: size) != nil {
                return .custom(base, size: size).weight(weight)
            }
        }
        return .system(size: size, weight: weight, design: font.systemDesign)
    }

    private static func weightedName(base: String, weight: Font.Weight) -> String {
        let suffix: String
        switch weight {
        case .bold, .heavy, .black: suffix = "-Bold"
        case .semibold, .medium:    suffix = "-Medium"
        default:                    suffix = "-Regular"
        }
        return base.replacingOccurrences(of: "-Regular", with: suffix)
    }

    private static func resolved(_ size: CGFloat, weight: Font.Weight) -> Font {
        fontForID(FontManager.shared.currentFontID, size: size, weight: weight)
    }

    /// Monospaced/technical text — now follows the chosen app font (still the
    /// system monospaced design when "System" is selected).
    static func mono(_ size: CGFloat) -> Font { resolved(size, weight: .regular) }

    /// Bold variant of the app font.
    static func monoBold(_ size: CGFloat) -> Font { resolved(size, weight: .bold) }

    /// Display/heading font. Follows the chosen app font so the whole UI matches.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        resolved(size, weight: weight)
    }
}
