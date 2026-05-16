//
//  AppTheme.swift
//  Kestrel Mac
//
//  System UI theme definitions. Each theme controls app chrome colors
//  (backgrounds, borders, accents, text). Terminal color schemes are separate.
//

import SwiftUI

// MARK: - Theme Identifier

enum AppThemeID: String, CaseIterable, Identifiable {
    case phosphor = "Phosphor"
    case midnight = "Midnight"
    case dracula = "Dracula"
    case arctic = "Arctic"
    case ember = "Ember"

    var id: String { rawValue }
    var theme: AppTheme { AppTheme.named(self) }

    var icon: String {
        switch self {
        case .phosphor: "terminal"
        case .midnight: "moon.stars"
        case .dracula: "moon"
        case .arctic: "snowflake"
        case .ember: "flame"
        }
    }
}

// MARK: - Theme Definition

struct AppTheme {
    let accent: Color
    let accentDim: Color
    let background: Color
    let backgroundCard: Color
    let backgroundCardAccent: Color
    let cardBorder: Color
    let cardBorderAccent: Color
    let amber: Color
    let red: Color
    let blue: Color
    let textPrimary: Color
    let textMuted: Color
    let textFaint: Color
    /// Optional bundled mono font family name. When non-nil and the font is
    /// installed, `KestrelFonts.mono(_:)` will use it instead of the system
    /// monospaced design.
    var monoFontName: String? = nil

    static func named(_ id: AppThemeID) -> AppTheme {
        switch id {
        case .phosphor:  return phosphor
        case .midnight:  return midnight
        case .amber:     return amberTheme
        case .dracula:   return dracula
        case .arctic:    return arctic
        case .ember:     return ember
        }
    }

    // MARK: - Phosphor (Default — matches original hardcoded values)

    private static let phosphor = AppTheme(
        accent:              Color(red: 0, green: 1, blue: 0.255),
        accentDim:           Color(red: 0, green: 1, blue: 0.255).opacity(0.15),
        background:          Color(red: 0, green: 0, blue: 0),
        backgroundCard:      Color.white.opacity(0.04),
        backgroundCardAccent: Color(red: 0, green: 1, blue: 0.255).opacity(0.04),
        cardBorder:          Color.white.opacity(0.07),
        cardBorderAccent:    Color(red: 0, green: 1, blue: 0.255).opacity(0.18),
        amber:               Color(red: 1, green: 0.722, blue: 0),
        red:                 Color(red: 1, green: 0.231, blue: 0.361),
        blue:                Color(red: 0, green: 0.784, blue: 1),
        textPrimary:         Color.white,
        textMuted:           Color.white.opacity(0.7),
        textFaint:           Color.white.opacity(0.45)
    )

    // MARK: - Midnight

    private static let midnight = AppTheme(
        accent:              Color(red: 0.357, green: 0.612, blue: 1),
        accentDim:           Color(red: 0.357, green: 0.612, blue: 1).opacity(0.15),
        background:          Color(red: 0.039, green: 0.055, blue: 0.102),
        backgroundCard:      Color.white.opacity(0.04),
        backgroundCardAccent: Color(red: 0.357, green: 0.612, blue: 1).opacity(0.04),
        cardBorder:          Color.white.opacity(0.07),
        cardBorderAccent:    Color(red: 0.357, green: 0.612, blue: 1).opacity(0.18),
        amber:               Color(red: 1, green: 0.722, blue: 0),
        red:                 Color(red: 1, green: 0.231, blue: 0.361),
        blue:                Color(red: 0, green: 0.784, blue: 1),
        textPrimary:         Color.white,
        textMuted:           Color.white.opacity(0.7),
        textFaint:           Color.white.opacity(0.45)
    )

    // MARK: - Amber

    private static let amberTheme = AppTheme(
        accent:              Color(red: 1, green: 0.722, blue: 0),
        accentDim:           Color(red: 1, green: 0.722, blue: 0).opacity(0.15),
        background:          Color(red: 0.051, green: 0.039, blue: 0),
        backgroundCard:      Color.white.opacity(0.04),
        backgroundCardAccent: Color(red: 1, green: 0.722, blue: 0).opacity(0.04),
        cardBorder:          Color.white.opacity(0.07),
        cardBorderAccent:    Color(red: 1, green: 0.722, blue: 0).opacity(0.18),
        amber:               Color(red: 1, green: 0.584, blue: 0),
        red:                 Color(red: 1, green: 0.231, blue: 0.361),
        blue:                Color(red: 0, green: 0.784, blue: 1),
        textPrimary:         Color.white,
        textMuted:           Color.white.opacity(0.7),
        textFaint:           Color.white.opacity(0.45)
    )

    // MARK: - Dracula

    private static let dracula = AppTheme(
        accent:              Color(red: 0.741, green: 0.576, blue: 0.976),
        accentDim:           Color(red: 0.741, green: 0.576, blue: 0.976).opacity(0.15),
        background:          Color(red: 0.157, green: 0.165, blue: 0.212),
        backgroundCard:      Color.white.opacity(0.05),
        backgroundCardAccent: Color(red: 0.741, green: 0.576, blue: 0.976).opacity(0.05),
        cardBorder:          Color.white.opacity(0.08),
        cardBorderAccent:    Color(red: 0.741, green: 0.576, blue: 0.976).opacity(0.18),
        amber:               Color(red: 1, green: 0.722, blue: 0),
        red:                 Color(red: 1, green: 0.333, blue: 0.333),
        blue:                Color(red: 0.514, green: 0.831, blue: 0.976),
        textPrimary:         Color(red: 0.973, green: 0.973, blue: 0.949),
        textMuted:           Color(red: 0.973, green: 0.973, blue: 0.949).opacity(0.7),
        textFaint:           Color(red: 0.973, green: 0.973, blue: 0.949).opacity(0.45)
    )

    // MARK: - Ember (warm onyx + amber)

    private static let ember = AppTheme(
        accent:              Color(red: 0.910, green: 0.659, blue: 0.220),   // #E8A838
        accentDim:           Color(red: 0.910, green: 0.659, blue: 0.220).opacity(0.15),
        background:          Color(red: 0.055, green: 0.055, blue: 0.055),   // #0E0E0E
        backgroundCard:      Color(red: 0.098, green: 0.098, blue: 0.098),   // #191919
        backgroundCardAccent: Color(red: 0.910, green: 0.659, blue: 0.220).opacity(0.06),
        cardBorder:          Color(red: 0.180, green: 0.180, blue: 0.180),   // #2E2E2E
        cardBorderAccent:    Color(red: 0.910, green: 0.659, blue: 0.220).opacity(0.35),
        amber:               Color(red: 0.910, green: 0.659, blue: 0.220),
        red:                 Color(red: 0.973, green: 0.443, blue: 0.443),   // #F87171
        blue:                Color(red: 0.514, green: 0.831, blue: 0.976),
        textPrimary:         Color(red: 0.878, green: 0.867, blue: 0.835),   // #E0DDD5 cream
        textMuted:           Color(red: 0.533, green: 0.533, blue: 0.533),   // #888888
        textFaint:           Color(red: 0.533, green: 0.533, blue: 0.533).opacity(0.6),
        monoFontName:        "JetBrainsMono-Regular"
    )

    // MARK: - Arctic

    private static let arctic = AppTheme(
        accent:              Color(red: 0, green: 0.831, blue: 1),
        accentDim:           Color(red: 0, green: 0.831, blue: 1).opacity(0.15),
        background:          Color(red: 0.039, green: 0.086, blue: 0.157),
        backgroundCard:      Color.white.opacity(0.04),
        backgroundCardAccent: Color(red: 0, green: 0.831, blue: 1).opacity(0.04),
        cardBorder:          Color.white.opacity(0.07),
        cardBorderAccent:    Color(red: 0, green: 0.831, blue: 1).opacity(0.18),
        amber:               Color(red: 1, green: 0.722, blue: 0),
        red:                 Color(red: 1, green: 0.231, blue: 0.361),
        blue:                Color(red: 0, green: 0.784, blue: 1),
        textPrimary:         Color.white,
        textMuted:           Color.white.opacity(0.7),
        textFaint:           Color.white.opacity(0.45)
    )
}
