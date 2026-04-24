//
//  KestrelFonts.swift
//  Kestrel Mac
//
//  Identical copy of the iOS font definitions — keep in sync.
//  Replace with shared DesignSystem/Theme/KestrelFonts.swift when targets are unified.
//

import SwiftUI

enum KestrelFonts {
    /// Monospaced font for technical text.
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }

    /// Bold variant of the monospaced font.
    static func monoBold(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// Display font using system rounded design.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
