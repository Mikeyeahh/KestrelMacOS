//
//  KestrelComponents.swift
//  Kestrel Mac
//
//  Shared design components — identical to iOS KestrelComponents.
//  Replace with shared DesignSystem/Components/KestrelComponents.swift when targets are unified.
//

import SwiftUI

// MARK: - StatusDot

struct StatusDot: View {
    let status: ServerStatus

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
            .shadow(color: status.color.opacity(isPulsing ? 0.6 : 0.2), radius: isPulsing ? 6 : 2)
            .accessibilityLabel(status.accessibilityLabel)
            .onAppear {
                guard status == .online else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

// Reacts to live SSH session state via Observation, with a fallback to the
// server's last known status when there is no active session.
struct LiveServerStatusDot: View {
    let session: SSHSession?
    let fallback: ServerStatus

    var body: some View {
        StatusDot(status: session?.isConnected == true ? .online : fallback)
    }
}

// MARK: - EnvBadge

struct EnvBadge: View {
    let env: ServerEnvironment
    var compact: Bool = false

    var body: some View {
        Text(env.badge)
            .font(KestrelFonts.mono(compact ? 8 : 9))
            .fontWeight(.bold)
            .tracking(compact ? 0.5 : 0.8)
            .foregroundStyle(env.colour)
            .padding(.horizontal, compact ? 4 : 7)
            .padding(.vertical, compact ? 1 : 3)
            .background(env.colour.opacity(0.15))
            .clipShape(Capsule())
            .accessibilityLabel("\(env.displayName) environment")
    }
}

// MARK: - MiniBar

struct MiniBar: View {
    let progress: Double
    var color: Color = KestrelColors.phosphorGreen

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))

                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("\(Int(progress * 100)) percent")
    }
}

// MARK: - ServerConnectionLabel

struct ServerConnectionLabel: View {
    let username: String
    let host: String
    var port: Int? = nil
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 0) {
            Text(username)
                .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.8))
            Text("@")
                .foregroundStyle(KestrelColors.textFaint)
            Text(host)
                .foregroundStyle(KestrelColors.textPrimary.opacity(0.85))
            if let port, port != 22 {
                Text(":")
                    .foregroundStyle(KestrelColors.textFaint)
                Text("\(port)")
                    .foregroundStyle(KestrelColors.textMuted)
            }
        }
        .font(KestrelFonts.mono(size))
        .lineLimit(1)
        .accessibilityLabel("\(username) at \(host)\(port != nil && port != 22 ? " port \(port!)" : "")")
    }
}

// MARK: - SectionLabel

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(KestrelFonts.mono(11))
            .tracking(1.5)
            .foregroundStyle(KestrelColors.textMuted)
            .accessibilityAddTraits(.isHeader)
    }
}
