//
//  FileManagerView.swift
//  Kestrel Mac
//
//  Created by Mike on 10/04/2026.
//

import SwiftUI

struct FileManagerView: View {
    let server: Server

    var body: some View {
        VStack {
            ContentUnavailableView(
                "SFTP Browser",
                systemImage: "folder",
                description: Text("Connect to \(server.name) to browse remote files.")
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
