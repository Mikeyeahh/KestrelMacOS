//
//  KestrelColors.swift
//  Kestrel Mac
//
//  Theme-aware color palette. All properties delegate to the active AppTheme
//  so existing call sites work without changes.
//

import SwiftUI

enum KestrelColors {
    private static var theme: AppTheme { ThemeManager.shared.current }

    // MARK: - Backgrounds

    static var background: Color { theme.background }
    static var backgroundCard: Color { theme.backgroundCard }
    static var backgroundCardGreen: Color { theme.backgroundCardAccent }

    // MARK: - Borders

    static var cardBorder: Color { theme.cardBorder }
    static var cardBorderGreen: Color { theme.cardBorderAccent }

    // MARK: - Accents

    static var phosphorGreen: Color { theme.accent }
    static var phosphorGreenDim: Color { theme.accentDim }
    static var amber: Color { theme.amber }
    static var red: Color { theme.red }
    static var blue: Color { theme.blue }

    // MARK: - Text

    static var textPrimary: Color { theme.textPrimary }
    static var textMuted: Color { theme.textMuted }
    static var textFaint: Color { theme.textFaint }
}
