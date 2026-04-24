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
    case amber = "Amber"
    case dracula = "Dracula"
    case arctic = "Arctic"

    var id: String { rawValue }
    var theme: AppTheme { AppTheme.named(self) }

    var icon: String {
        switch self {
        case .phosphor: "terminal"
        case .midnight: "moon.stars"
        case .amber: "sun.dust"
        case .dracula: "moon"
        case .arctic: "snowflake"
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

    static func named(_ id: AppThemeID) -> AppTheme {
        switch id {
        case .phosphor:  return phosphor
        case .midnight:  return midnight
        case .amber:     return amberTheme
        case .dracula:   return dracula
        case .arctic:    return arctic
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
