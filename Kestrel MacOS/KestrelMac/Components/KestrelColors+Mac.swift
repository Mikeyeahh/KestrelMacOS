//
//  KestrelColors+Mac.swift
//  Kestrel Mac
//
//  macOS-specific colour adaptations.
//  All accent colours (phosphorGreen, amber, red, blue) remain identical to iOS.
//

import SwiftUI
import AppKit

extension KestrelColors {
    // MARK: - macOS Surface Colours

    /// Native window background — adapts to system appearance automatically.
    static let macWindowBackground = Color(NSColor.windowBackgroundColor)

    /// Sidebar / source list background.
    static let macSidebarBackground = Color(NSColor.controlBackgroundColor)

    /// Toolbar region — slightly translucent window background.
    static let macToolbarBackground = Color(NSColor.windowBackgroundColor).opacity(0.95)
}
