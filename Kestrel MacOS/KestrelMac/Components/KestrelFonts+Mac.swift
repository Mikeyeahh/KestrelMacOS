//
//  KestrelFonts+Mac.swift
//  Kestrel Mac
//
//  macOS-specific typography extensions.
//

import SwiftUI
import AppKit

extension KestrelFonts {
    /// Terminal monospaced font — prefers SF Mono, falls back to Menlo.
    /// If you bundle Cascadia Code, it will be tried first.
    static func systemMono(_ size: CGFloat) -> Font {
        // Attempt Cascadia Code (only if bundled), then SF Mono, then Menlo
        if let _ = NSFont(name: "CascadiaCode-Regular", size: size) {
            return .custom("CascadiaCode-Regular", size: size)
        }
        if let _ = NSFont(name: "SFMono-Regular", size: size) {
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
