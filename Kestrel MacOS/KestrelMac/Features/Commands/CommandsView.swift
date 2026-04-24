//
//  CommandsView.swift
//  Kestrel Mac
//
//  Created by Mike on 10/04/2026.
//

import SwiftUI

struct CommandsView: View {
    var body: some View {
        VStack {
            ContentUnavailableView(
                "Command Library",
                systemImage: "terminal",
                description: Text("Save and organize frequently used commands.")
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Commands")
    }
}
