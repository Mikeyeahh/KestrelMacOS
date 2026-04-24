//
//  DashboardView.swift
//  Kestrel Mac
//
//  Created by Mike on 10/04/2026.
//

import SwiftUI

struct DashboardView: View {
    let server: Server

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Server Dashboard")
                    .font(.title2.bold())

                GroupBox("Connection Info") {
                    LabeledContent("Host", value: server.host)
                    LabeledContent("Port", value: "\(server.port)")
                    LabeledContent("Username", value: server.username)
                    LabeledContent("Status", value: server.isConnected ? "Connected" : "Disconnected")
                }

                GroupBox("System Resources") {
                    Text("Connect to view live system metrics.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
