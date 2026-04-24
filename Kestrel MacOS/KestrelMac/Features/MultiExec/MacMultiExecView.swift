//
//  MacMultiExecView.swift
//  Kestrel Mac
//
//  Execute a command across multiple servers simultaneously
//  and display results side-by-side.
//

import SwiftUI

// MARK: - Multi-Exec Result

struct MultiExecResult: Identifiable {
    let id: UUID
    let serverName: String
    let host: String
    var output: String = ""
    var error: String?
    var status: Status = .pending
    var duration: TimeInterval?

    enum Status {
        case pending, running, success, failed

        var icon: String {
            switch self {
            case .pending:  "circle.dotted"
            case .running:  "progress.indicator"
            case .success:  "checkmark.circle.fill"
            case .failed:   "xmark.circle.fill"
            }
        }
    }
}

// MARK: - Multi-Exec View

struct MacMultiExecView: View {
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var sessionManager: SSHSessionManager

    @State private var selectedServerIDs: Set<UUID> = []
    @State private var command = ""
    @State private var results: [UUID: MultiExecResult] = [:]
    @State private var isExecuting = false

    /// Only SSH servers can be multi-exec'd.
    private var sshServers: [Server] {
        serverRepository.servers.filter { $0.connectionType == "ssh" }
    }

    var body: some View {
        HSplitView {
            // Left: server selection + command
            leftPanel
                .frame(minWidth: 240, maxWidth: 300)

            // Right: results
            rightPanel
                .frame(maxWidth: .infinity)
        }
        .background(KestrelColors.background)
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("MULTI-EXEC")
                    .font(KestrelFonts.mono(9))
                    .tracking(1.2)
                    .foregroundStyle(KestrelColors.textFaint)
                Text("Run a command on multiple servers")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .padding(14)

            Divider().overlay(KestrelColors.cardBorder)

            // Server list
            ScrollView {
                VStack(spacing: 1) {
                    // Quick actions
                    HStack {
                        Button("Select All") {
                            selectedServerIDs = Set(sshServers.map(\.id))
                        }
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .buttonStyle(.plain)

                        Button("None") {
                            selectedServerIDs.removeAll()
                        }
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textMuted)
                        .buttonStyle(.plain)

                        Spacer()

                        Text("\(selectedServerIDs.count) selected")
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    ForEach(sshServers) { server in
                        serverCheckboxRow(server)
                    }
                }
            }

            Divider().overlay(KestrelColors.cardBorder)

            // Command input
            VStack(alignment: .leading, spacing: 8) {
                Text("COMMAND")
                    .font(KestrelFonts.mono(9))
                    .tracking(1.2)
                    .foregroundStyle(KestrelColors.textFaint)

                TextEditor(text: $command)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(KestrelColors.backgroundCard)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                    )

                Button {
                    executeOnAll()
                } label: {
                    HStack(spacing: 6) {
                        if isExecuting {
                            ProgressView().scaleEffect(0.5)
                        }
                        Image(systemName: "play.fill")
                        Text("Execute on \(selectedServerIDs.count) Server\(selectedServerIDs.count == 1 ? "" : "s")")
                    }
                    .font(KestrelFonts.monoBold(11))
                    .foregroundStyle(KestrelColors.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        selectedServerIDs.isEmpty || command.isEmpty || isExecuting
                            ? KestrelColors.textFaint
                            : KestrelColors.phosphorGreen
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(selectedServerIDs.isEmpty || command.isEmpty || isExecuting)
            }
            .padding(14)
        }
        .background(KestrelColors.backgroundCard)
    }

    private func serverCheckboxRow(_ server: Server) -> some View {
        let isSelected = selectedServerIDs.contains(server.id)
        let isConnected = sessionManager.activeSession(for: server.id)?.isConnected ?? false

        return HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? KestrelColors.phosphorGreen : KestrelColors.textFaint)
                .font(.system(size: 14))

            Circle()
                .fill(isConnected ? KestrelColors.phosphorGreen : KestrelColors.textFaint)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(server.name)
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textPrimary)
                    .lineLimit(1)
                Text(server.host)
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isSelected ? KestrelColors.phosphorGreenDim : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedServerIDs.remove(server.id)
            } else {
                selectedServerIDs.insert(server.id)
            }
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        Group {
            if results.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "rectangle.stack")
                } description: {
                    Text("Select servers, enter a command, and click Execute")
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(Array(results.values).sorted(by: { $0.serverName < $1.serverName })) { result in
                            resultCard(result)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func resultCard(_ result: MultiExecResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                statusIcon(result.status)

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.serverName)
                        .font(KestrelFonts.monoBold(11))
                        .foregroundStyle(KestrelColors.textPrimary)
                    Text(result.host)
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(KestrelColors.textFaint)
                }

                Spacer()

                if let duration = result.duration {
                    Text(String(format: "%.1fs", duration))
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(KestrelColors.textFaint)
                }
            }

            // Output
            if !result.output.isEmpty {
                ScrollView {
                    Text(result.output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(KestrelColors.textMuted)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(KestrelColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Error
            if let error = result.error {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(KestrelFonts.mono(10))
                        .lineLimit(2)
                }
                .foregroundStyle(KestrelColors.red)
            }
        }
        .padding(12)
        .background(KestrelColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor(for: result.status), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusIcon(_ status: MultiExecResult.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundStyle(KestrelColors.textFaint)
        case .running:
            ProgressView()
                .scaleEffect(0.5)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(KestrelColors.phosphorGreen)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(KestrelColors.red)
        }
    }

    private func borderColor(for status: MultiExecResult.Status) -> Color {
        switch status {
        case .success: KestrelColors.phosphorGreen.opacity(0.3)
        case .failed:  KestrelColors.red.opacity(0.3)
        default:       KestrelColors.cardBorder
        }
    }

    // MARK: - Execution

    private func executeOnAll() {
        isExecuting = true
        results.removeAll()

        let serverIDs = Array(selectedServerIDs)
        let cmd = command

        // Initialize results
        for id in serverIDs {
            if let server = sshServers.first(where: { $0.id == id }) {
                results[id] = MultiExecResult(
                    id: id,
                    serverName: server.name,
                    host: server.host
                )
            }
        }

        Task {
            await withTaskGroup(of: (UUID, String?, String?, TimeInterval).self) { group in
                for serverID in serverIDs {
                    guard let server = sshServers.first(where: { $0.id == serverID }) else { continue }

                    group.addTask { [sessionManager] in
                        let start = Date()
                        do {
                            let session = try await sessionManager.openSession(for: server)
                            let output = try await session.execute(cmd)
                            return (serverID, output, nil, Date().timeIntervalSince(start))
                        } catch {
                            return (serverID, nil, error.localizedDescription, Date().timeIntervalSince(start))
                        }
                    }
                }

                for await (id, output, error, duration) in group {
                    results[id]?.output = output ?? ""
                    results[id]?.error = error
                    results[id]?.status = error == nil ? .success : .failed
                    results[id]?.duration = duration
                }
            }

            isExecuting = false
        }
    }
}
