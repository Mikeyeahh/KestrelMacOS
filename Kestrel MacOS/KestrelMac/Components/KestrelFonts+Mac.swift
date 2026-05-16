//
//  KestrelFonts+Mac.swift
//  Kestrel Mac
//
//  macOS-specific typography extensions.
//

import SwiftUI
import AppKit

extension KestrelFonts {
    /// Terminal monospaced font — follows the active theme's `monoFontName`
    /// when available (e.g. JetBrains Mono for the Termio theme), otherwise
    /// prefers Cascadia Code, then SF Mono, then Menlo.
    static func systemMono(_ size: CGFloat) -> Font {
        if let name = ThemeManager.shared.current.monoFontName,
           NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        if NSFont(name: "CascadiaCode-Regular", size: size) != nil {
            return .custom("CascadiaCode-Regular", size: size)
        }
        if NSFont(name: "SFMono-Regular", size: size) != nil {
            return .custom("SFMono-Regular", size: size)
        }
        return .custom("Menlo", size: size)
    }

    /// Compact monospaced font for the menu bar extra.
    static func menuBarMono(_ size: CGFloat) -> Font {
        if let _ = NSFont(name: "SFMono-Regular", size: size) {
            return .custom("SFMono-Regular", size: size)
        }
        return .custom("Menlo", size: size)
    }

    /// Small system font for sidebar items — 11pt.
    static var sidebarLabel: Font {
        .system(size: 11)
    }
}
