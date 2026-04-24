//
//  MacImportServersSheet.swift
//  Kestrel Mac
//
//  Sheet for importing servers from MobaXterm, Termius,
//  SSH Config, or Kestrel JSON exports.
//

import SwiftUI
import UniformTypeIdentifiers

struct MacImportServersSheet: View {
    @EnvironmentObject var serverRepository: ServerRepository
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSource: ImportSource = .mobaXterm
    @State private var importResult: ImportResult?
    @State private var errorMessage: String?
    @State private var isFilePickerPresented = false
    @State private var selectedServers: Set<UUID> = []
    @State private var isImporting = false
    @State private var importComplete = false
    @State private var importedCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider().overlay(KestrelColors.cardBorder)

            if let result = importResult {
                // Preview imported servers
                previewSection(result)
            } else {
                // Source selection + file picker
                sourceSelectionSection
            }

            Divider().overlay(KestrelColors.cardBorder)

            // Footer
            footer
        }
        .frame(width: 620, height: 560)
        .background(KestrelColors.background)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: selectedSource.allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 16))
                .foregroundStyle(KestrelColors.phosphorGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text("Import Servers")
                    .font(KestrelFonts.display(16, weight: .bold))
                    .foregroundStyle(KestrelColors.textPrimary)
                Text("Import SSH connections from other apps")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textMuted)
            }

            Spacer()

            if importComplete {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KestrelColors.phosphorGreen)
                    Text("\(importedCount) imported")
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Source Selection

    private var sourceSelectionSection: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("SELECT SOURCE")
                .font(KestrelFonts.mono(9))
                .tracking(1.2)
                .foregroundStyle(KestrelColors.textFaint)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(ImportSource.allCases) { source in
                    sourceCard(source)
                }
            }
            .padding(.horizontal, 40)

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(KestrelColors.red)
                    Text(errorMessage)
                        .font(KestrelFonts.mono(11))
                        .foregroundStyle(KestrelColors.red)
                }
                .padding(.horizontal, 20)
            }

            Button {
                isFilePickerPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text("Choose File")
                }
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.phosphorGreen)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(KestrelColors.phosphorGreenDim)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    private func sourceCard(_ source: ImportSource) -> some View {
        Button {
            selectedSource = source
            errorMessage = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: source.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(selectedSource == source ? KestrelColors.phosphorGreen : KestrelColors.textMuted)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.rawValue)
                        .font(KestrelFonts.monoBold(12))
                        .foregroundStyle(selectedSource == source ? KestrelColors.textPrimary : KestrelColors.textMuted)
                    Text(source.fileLabel)
                        .font(KestrelFonts.mono(9))
                        .foregroundStyle(KestrelColors.textFaint)
                        .lineLimit(1)
                }

                Spacer()

                if selectedSource == source {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KestrelColors.phosphorGreen)
                        .font(.system(size: 14))
                }
            }
            .padding(10)
            .background(selectedSource == source ? KestrelColors.phosphorGreenDim : KestrelColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        selectedSource == source ? KestrelColors.phosphorGreen.opacity(0.4) : KestrelColors.cardBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview

    private func previewSection(_ result: ImportResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar
            HStack(spacing: 10) {
                Text("\(result.servers.count) server\(result.servers.count == 1 ? "" : "s") found")
                    .font(KestrelFonts.monoBold(12))
                    .foregroundStyle(KestrelColors.textPrimary)

                if result.skippedCount > 0 {
                    Text("(\(result.skippedCount) non-SSH skipped)")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textFaint)
                }

                Spacer()

                Button {
                    if selectedServers.count == result.servers.count {
                        selectedServers.removeAll()
                    } else {
                        selectedServers = Set(result.servers.map(\.id))
                    }
                } label: {
                    Text(selectedServers.count == result.servers.count ? "Deselect All" : "Select All")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
                .buttonStyle(.plain)

                Button {
                    importResult = nil
                    errorMessage = nil
                    selectedServers.removeAll()
                } label: {
                    Text("Back")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().overlay(KestrelColors.cardBorder)

            // Server list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(result.servers) { server in
                        serverRow(server)
                    }
                }
            }

            // Warnings
            if !result.warnings.isEmpty {
                Divider().overlay(KestrelColors.cardBorder)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(KestrelColors.amber)
                            .font(.system(size: 10))
                        ForEach(result.warnings.prefix(5), id: \.self) { warning in
                            Text(warning)
                                .font(KestrelFonts.mono(9))
                                .foregroundStyle(KestrelColors.amber)
                        }
                        if result.warnings.count > 5 {
                            Text("+\(result.warnings.count - 5) more")
                                .font(KestrelFonts.mono(9))
                                .foregroundStyle(KestrelColors.textFaint)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func serverRow(_ server: Server) -> some View {
        let isSelected = selectedServers.contains(server.id)
        return HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? KestrelColors.phosphorGreen : KestrelColors.textFaint)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(KestrelFonts.monoBold(11))
                    .foregroundStyle(KestrelColors.textPrimary)
                    .lineLimit(1)
                Text("\(server.username.isEmpty ? "—" : server.username)@\(server.host):\(server.port)")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            if let group = server.group, !group.isEmpty {
                Text(group)
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(KestrelColors.backgroundCard)
                    .clipShape(Capsule())
            }

            Text(server.authMethod == "privateKey" ? "Key" : "Password")
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? KestrelColors.phosphorGreenDim : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedServers.remove(server.id)
            } else {
                selectedServers.insert(server.id)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if importResult != nil {
                Text("\(selectedServers.count) selected")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textFaint)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            if let result = importResult {
                Button {
                    performImport(result)
                } label: {
                    HStack(spacing: 4) {
                        if isImporting { ProgressView().scaleEffect(0.5) }
                        Text("Import \(selectedServers.count) Server\(selectedServers.count == 1 ? "" : "s")")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(KestrelColors.phosphorGreen)
                .disabled(selectedServers.isEmpty || isImporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    // MARK: - Actions

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        errorMessage = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Cannot access file — permission denied."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let parsed = try ServerImportService.parse(source: selectedSource, data: data)
                if parsed.servers.isEmpty {
                    errorMessage = "No SSH servers found in this file."
                } else {
                    importResult = parsed
                    selectedServers = Set(parsed.servers.map(\.id))
                }
            } catch {
                errorMessage = error.localizedDescription
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func performImport(_ result: ImportResult) {
        isImporting = true
        let toImport = result.servers.filter { selectedServers.contains($0.id) }

        for server in toImport {
            serverRepository.addServer(server)
        }

        importedCount = toImport.count
        isImporting = false
        importComplete = true

        // Auto-dismiss after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
        }
    }
}
