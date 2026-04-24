//
//  TerminalView.swift
//  Kestrel Mac
//
//  Created by Mike on 10/04/2026.
//

import SwiftUI

struct TerminalView: View {
    let server: Server
    @State private var tabs: [TerminalTab] = [TerminalTab(title: "Session 1")]
    @State private var selectedTabID: UUID?

    struct TerminalTab: Identifiable {
        let id = UUID()
        var title: String
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    Button(action: { selectedTabID = tab.id }) {
                        Text(tab.title)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedTabID == tab.id ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: addTab) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)

            Divider()

            // Terminal content placeholder — integrate SwiftTerm here
            ZStack {
                Color.black
                Text("Terminal session for \(server.name)")
                    .foregroundStyle(.green)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .onAppear {
            if selectedTabID == nil { selectedTabID = tabs.first?.id }
        }
    }

    private func addTab() {
        let tab = TerminalTab(title: "Session \(tabs.count + 1)")
        tabs.append(tab)
        selectedTabID = tab.id
    }
}
