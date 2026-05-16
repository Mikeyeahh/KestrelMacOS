//
//  KestrelFonts.swift
//  Kestrel Mac
//
//  Identical copy of the iOS font definitions — keep in sync.
//  Replace with shared DesignSystem/Theme/KestrelFonts.swift when targets are unified.
//

import SwiftUI
import AppKit

enum KestrelFonts {
    /// Monospaced font for technical text. Uses the active theme's
    /// `monoFontName` when it's set and the font is installed; otherwise
    /// falls back to the system monospaced design.
    static func mono(_ size: CGFloat) -> Font {
        if let name = ThemeManager.shared.current.monoFontName,
           NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, design: .monospaced)
    }

    /// Bold variant of the monospaced font.
    static func monoBold(_ size: CGFloat) -> Font {
        if let baseName = ThemeManager.shared.current.monoFontName {
            let boldName = baseName.replacingOccurrences(of: "-Regular", with: "-Bold")
            if NSFont(name: boldName, size: size) != nil {
                return .custom(boldName, size: size)
            }
            if NSFont(name: baseName, size: size) != nil {
                return .custom(baseName, size: size).weight(.semibold)
            }
        }
        return .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// Display font using system rounded design.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
