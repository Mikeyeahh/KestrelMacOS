//
//  MacVNCView.swift
//  Kestrel Mac
//
//  VNC launcher — opens macOS Screen Sharing for the selected server.
//

import SwiftUI
import AppKit

struct MacVNCView: View {
    let server: Server
    @State private var launchError: String?

    private var effectivePort: Int {
        server.vncPort ?? 5900
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(KestrelColors.phosphorGreen)

            // Title
            Text(server.name)
                .font(KestrelFonts.display(22, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)

            Text("\(server.host):\(effectivePort)")
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.textMuted)

            // Launch button
            Button {
                openScreenSharing()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Open Screen Sharing")
                }
                .font(KestrelFonts.monoBold(13))
                .foregroundStyle(KestrelColors.background)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(KestrelColors.phosphorGreen)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Error
            if let launchError {
                Text(launchError)
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.red)
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)
            }

            // Info
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(KestrelColors.textFaint)
                Text("Opens the built-in macOS Screen Sharing app")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }

            if let group = server.group, !group.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text(group)
                        .font(KestrelFonts.mono(10))
                }
                .foregroundStyle(KestrelColors.textFaint)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KestrelColors.background)
    }

    private func openScreenSharing() {
        launchError = nil
        let urlString = "vnc://\(server.host):\(effectivePort)"
        guard let url = URL(string: urlString) else {
            launchError = "Invalid VNC URL: \(urlString)"
            return
        }
        NSWorkspace.shared.open(url)
    }
}
