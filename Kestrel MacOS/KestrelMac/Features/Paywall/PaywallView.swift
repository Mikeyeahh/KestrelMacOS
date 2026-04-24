//
//  PaywallView.swift
//  Kestrel Mac
//
//  Created by Mike on 10/04/2026.
//

import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var revenueCatService: RevenueCatService

    var body: some View {
        VStack(spacing: 20) {
            Text("Kestrel Pro")
                .font(.largeTitle.bold())

            Text("Unlock all features")
                .font(.title3)
                .foregroundStyle(.secondary)

            // TODO: Display RevenueCat offerings
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
    }
}
