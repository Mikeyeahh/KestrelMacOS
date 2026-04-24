//
//  CloudSyncView.swift
//  Kestrel Mac
//
//  Created by Mike on 10/04/2026.
//

import SwiftUI

struct CloudSyncView: View {
    @EnvironmentObject var supabaseService: SupabaseService

    var body: some View {
        VStack {
            ContentUnavailableView(
                "Cloud Sync",
                systemImage: "cloud",
                description: Text("Sign in to sync servers and settings across devices.")
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Cloud Sync")
    }
}
