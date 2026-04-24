//
//  ServerListView.swift
//  Kestrel Mac
//
//  Created by Mike on 10/04/2026.
//

import SwiftUI

struct ServerListView: View {
    @EnvironmentObject var serverRepository: ServerRepository
    @Binding var selectedServer: Server?

    var body: some View {
        List(serverRepository.servers, selection: $selectedServer) { server in
            ServerRow(server: server)
                .tag(server)
        }
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { /* TODO: add server sheet */ }) {
                    Label("Add Server", systemImage: "plus")
                }
            }
        }
    }
}

struct ServerRow: View {
    let server: Server

    var body: some View {
        HStack {
            Circle()
                .fill(server.isConnected ? .green : .gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading) {
                Text(server.name)
                    .font(.body)
                Text(server.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
