//
//  MacRDPView.swift
//  Kestrel Mac
//
//  RDP launcher — generates a .rdp file and opens it with
//  Microsoft Remote Desktop or the system default handler.
//

import SwiftUI
import AppKit

struct MacRDPView: View {
    let server: Server
    @State private var launchError: String?

    private var effectivePort: Int {
        server.rdpPort ?? 3389
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "desktopcomputer")
                .font(.system(size: 56))
                .foregroundStyle(KestrelColors.blue)

            // Title
            Text(server.name)
                .font(KestrelFonts.display(22, weight: .bold))
                .foregroundStyle(KestrelColors.textPrimary)

            Text("\(server.username.isEmpty ? "" : "\(server.username)@")\(server.host):\(effectivePort)")
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.textMuted)

            // Launch button
            Button {
                openRemoteDesktop()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Open Remote Desktop")
                }
                .font(KestrelFonts.monoBold(13))
                .foregroundStyle(KestrelColors.background)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(KestrelColors.blue)
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
                Text("Requires Microsoft Remote Desktop from the App Store")
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

    private func openRemoteDesktop() {
        launchError = nil

        let rdpContent = """
        full address:s:\(server.host):\(effectivePort)
        username:s:\(server.username)
        prompt for credentials:i:1
        desktopwidth:i:1920
        desktopheight:i:1080
        session bpp:i:32
        """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(server.name)-\(UUID().uuidString.prefix(8)).rdp")

        do {
            try rdpContent.write(to: tempURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tempURL)

            // Clean up temp file after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                try? FileManager.default.removeItem(at: tempURL)
            }
        } catch {
            launchError = "Failed to create RDP file: \(error.localizedDescription)"
        }
    }
}
