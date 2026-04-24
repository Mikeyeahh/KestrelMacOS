//
//  WindowChromeModifier.swift
//  Kestrel Mac
//
//  Created by Mike on 10/04/2026.
//

import SwiftUI

struct WindowChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minWidth: 800, minHeight: 500)
    }
}

extension View {
    func kestrelWindowChrome() -> some View {
        modifier(WindowChromeModifier())
    }
}
