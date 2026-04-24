//
//  MacSFTPView.swift
//  Kestrel Mac
//
//  macOS SFTP file manager with two-panel Finder-like layout.
//  Uses the same SFTPSession/SFTPFileItem models as iOS.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Mac SFTP View

struct MacSFTPView: View {
    let server: Server

    @EnvironmentObject var sessionManager: SSHSessionManager
    @StateObject private var sftpSession: SFTPSession
    @State private var selectedItem: SFTPFileItem?
    @State private var viewMode: ViewMode = .list
    @State private var sortKey: SortKey = .name
    @State private var showHiddenFiles = false
    @State private var showPreview = false
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var showingDeleteConfirmation = false
    @State private var itemToDelete: SFTPFileItem?
    @State private var showingEditor = false
    @State private var editorContent = ""
    @State private var editorFilePath = ""
    @State private var editorOriginalContent = ""
    @State private var showingUnsavedAlert = false
    @State private var transfers: [TransferItem] = []
    @State private var showingTransfers = false
    @State private var renameItemID: UUID?
    @State private var renameText = ""

    enum ViewMode: String, CaseIterable {
        case list = "List"
        case grid = "Grid"
    }

    enum SortKey: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case modified = "Modified"
        case type = "Type"
    }

    init(server: Server) {
        self.server = server
        _sftpSession = StateObject(wrappedValue: SFTPSession(serverID: server.id, serverName: server.name))
    }

    // MARK: - Sorted/Filtered Items

    private var displayItems: [SFTPFileItem] {
        var result = sftpSession.items
        if !showHiddenFiles {
            result = result.filter { !$0.name.hasPrefix(".") }
        }
        switch sortKey {
        case .name: result.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        case .size: result.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.size > b.size
        }
        case .modified: result.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
        }
        case .type: result.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let extA = (a.name as NSString).pathExtension
            let extB = (b.name as NSString).pathExtension
            return extA.localizedCaseInsensitiveCompare(extB) == .orderedAscending
        }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if sftpSession.isConnected {
                connectedContent
            } else if sftpSession.isLoading {
                loadingState
            } else if let error = sftpSession.error {
                errorState(error)
            } else {
                disconnectedState
            }
        }
        .proGated(feature: .sftpFiles)
        .background(KestrelColors.background)
        .onAppear { connectIfNeeded() }
        .alert("New Folder", isPresented: $showingNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName; newFolderName = ""
                Task { try? await sftpSession.createDirectory(named: name) }
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .confirmationDialog("Delete Item", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    Task { try? await sftpSession.deleteItem(at: item.path, isDirectory: item.isDirectory) }
                }
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: {
            if let item = itemToDelete { Text("Delete \"\(item.name)\"? This cannot be undone.") }
        }
        .sheet(isPresented: $showingEditor) {
            MacFileEditorSheet(
                fileName: (editorFilePath as NSString).lastPathComponent,
                content: $editorContent,
                originalContent: editorOriginalContent,
                onSave: { saveEditedFile() },
                onDismissUnsaved: { showingUnsavedAlert = true }
            )
        }
    }

    // MARK: - Connected Content

    private var connectedContent: some View {
        VStack(spacing: 0) {
            fileToolbar
            HSplitView {
                directoryTree
                    .frame(minWidth: 180, idealWidth: 200, maxWidth: 260)
                VStack(spacing: 0) {
                    fileListPanel
                    if showPreview, let item = selectedItem, !item.isDirectory {
                        Divider()
                        filePreviewPanel(item)
                    }
                }
            }
            transferBar
        }
    }

    // MARK: - File Toolbar

    private var fileToolbar: some View {
        HStack(spacing: 8) {
            // Breadcrumb path
            breadcrumbPath

            Spacer()

            // View toggle
            Picker("", selection: $viewMode) {
                Image(systemName: "list.bullet").tag(ViewMode.list)
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
            }
            .pickerStyle(.segmented)
            .frame(width: 70)

            // Sort
            Menu {
                ForEach(SortKey.allCases, id: \.self) { key in
                    Button {
                        sortKey = key
                    } label: {
                        HStack {
                            Text(key.rawValue)
                            if sortKey == key { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11))
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)

            // Hidden files
            Button {
                showHiddenFiles.toggle()
            } label: {
                Image(systemName: showHiddenFiles ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(showHiddenFiles ? KestrelColors.phosphorGreen : KestrelColors.textFaint)
            }
            .buttonStyle(.plain)
            .help(showHiddenFiles ? "Hide hidden files" : "Show hidden files")

            // Preview toggle
            Button {
                showPreview.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 11))
                    .foregroundStyle(showPreview ? KestrelColors.phosphorGreen : KestrelColors.textMuted)
            }
            .buttonStyle(.plain)
            .help("Toggle file preview")

            Divider().frame(height: 16)

            // Upload
            Button {
                openUploadPicker()
            } label: {
                Image(systemName: "arrow.up.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .buttonStyle(.plain)
            .help("Upload file")

            // New folder
            Button {
                showingNewFolder = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .buttonStyle(.plain)
            .help("New folder")

            // Transfer progress
            if !transfers.isEmpty {
                Button {
                    showingTransfers.toggle()
                } label: {
                    HStack(spacing: 3) {
                        ProgressView().scaleEffect(0.4)
                        Text("\(transfers.count)")
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textMuted)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingTransfers) {
                    transferPopover
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(KestrelColors.backgroundCard)
        .overlay(alignment: .bottom) {
            Rectangle().fill(KestrelColors.cardBorder).frame(height: 1)
        }
    }

    // MARK: - Breadcrumb Path

    private var breadcrumbPath: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                let components = pathComponents(sftpSession.currentPath)
                ForEach(Array(components.enumerated()), id: \.offset) { index, comp in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                    Button {
                        Task { try? await sftpSession.navigateTo(comp.fullPath) }
                    } label: {
                        Text(comp.name)
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(
                                index == components.count - 1
                                    ? KestrelColors.phosphorGreen
                                    : KestrelColors.textMuted
                            )
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Directory Tree (Left Panel)

    private var directoryTree: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Quick access bookmarks
            Text("QUICK ACCESS")
                .font(KestrelFonts.mono(9))
                .tracking(1.0)
                .foregroundStyle(KestrelColors.textFaint)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(bookmarks, id: \.self) { path in
                Button {
                    Task { try? await sftpSession.navigateTo(path) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(KestrelColors.amber)
                        Text((path as NSString).lastPathComponent)
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(
                                sftpSession.currentPath.hasPrefix(path)
                                    ? KestrelColors.textPrimary
                                    : KestrelColors.textMuted
                            )
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        sftpSession.currentPath == path
                            ? KestrelColors.phosphorGreenDim
                            : Color.clear
                    )
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .overlay(KestrelColors.cardBorder)
                .padding(.vertical, 6)

            // Directory tree from current listing
            Text("DIRECTORIES")
                .font(KestrelFonts.mono(9))
                .tracking(1.0)
                .foregroundStyle(KestrelColors.textFaint)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    // Navigate up
                    if sftpSession.currentPath != "/" {
                        Button {
                            Task { try? await sftpSession.navigateUp() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.turn.up.left")
                                    .font(.system(size: 10))
                                    .foregroundStyle(KestrelColors.phosphorGreen)
                                Text("..")
                                    .font(KestrelFonts.mono(11))
                                    .foregroundStyle(KestrelColors.phosphorGreen)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(displayItems.filter(\.isDirectory)) { dir in
                        Button {
                            Task { try? await sftpSession.navigateTo(dir.path) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(KestrelColors.amber)
                                Text(dir.name)
                                    .font(KestrelFonts.mono(11))
                                    .foregroundStyle(KestrelColors.textMuted)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .background(KestrelColors.background)
        .overlay(alignment: .trailing) {
            Rectangle().fill(KestrelColors.cardBorder).frame(width: 1)
        }
    }

    private let bookmarks = ["/etc", "/var/log", "/home", "/opt", "/tmp"]

    // MARK: - File List Panel (Right Main)

    private var fileListPanel: some View {
        Group {
            if sftpSession.isLoading {
                VStack {
                    Spacer()
                    ProgressView().tint(KestrelColors.phosphorGreen)
                    Spacer()
                }
            } else if displayItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 28))
                        .foregroundStyle(KestrelColors.textFaint)
                    Text("Empty directory")
                        .font(KestrelFonts.mono(12))
                        .foregroundStyle(KestrelColors.textMuted)
                    Spacer()
                }
            } else {
                switch viewMode {
                case .list: fileListView
                case .grid: fileGridView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KestrelColors.background)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    // MARK: - List View

    private var fileListView: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("").frame(width: 28) // icon
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Size").frame(width: 80, alignment: .trailing)
                Text("Modified").frame(width: 120, alignment: .trailing)
                Text("Permissions").frame(width: 90, alignment: .trailing)
            }
            .font(KestrelFonts.mono(9))
            .foregroundStyle(KestrelColors.textFaint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(KestrelColors.backgroundCard)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayItems) { item in
                        fileListRow(item)
                    }
                }
            }
        }
    }

    private func fileListRow(_ item: SFTPFileItem) -> some View {
        HStack(spacing: 0) {
            Image(systemName: item.icon)
                .font(.system(size: 13))
                .foregroundStyle(item.isDirectory ? KestrelColors.amber : KestrelColors.textMuted)
                .frame(width: 28)

            // Name (with inline rename support)
            if renameItemID == item.id {
                TextField("", text: $renameText)
                    .font(KestrelFonts.mono(12))
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename(item) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(item.name)
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(item.formattedSize)
                .font(KestrelFonts.mono(10))
                .foregroundStyle(KestrelColors.textMuted)
                .frame(width: 80, alignment: .trailing)

            if let modified = item.modified {
                Text(modified, style: .date)
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
                    .frame(width: 120, alignment: .trailing)
            } else {
                Text("—")
                    .frame(width: 120, alignment: .trailing)
                    .foregroundStyle(KestrelColors.textFaint)
            }

            Text(item.permissions)
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(selectedItem?.id == item.id ? KestrelColors.phosphorGreenDim : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedItem = item
        }
        .onTapGesture(count: 2) {
            if item.isDirectory {
                Task { try? await sftpSession.navigateTo(item.path) }
            } else {
                previewOrEdit(item)
            }
        }
        .contextMenu { fileContextMenu(item) }
        .onDrag {
            NSItemProvider(object: item.path as NSString)
        }
    }

    // MARK: - Grid View

    private var fileGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach(displayItems) { item in
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 28))
                            .foregroundStyle(item.isDirectory ? KestrelColors.amber : KestrelColors.textMuted)
                            .frame(height: 36)
                        Text(item.name)
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 90, height: 80)
                    .background(selectedItem?.id == item.id ? KestrelColors.phosphorGreenDim : KestrelColors.backgroundCard)
                    .cornerRadius(6)
                    .onTapGesture { selectedItem = item }
                    .onTapGesture(count: 2) {
                        if item.isDirectory {
                            Task { try? await sftpSession.navigateTo(item.path) }
                        } else {
                            previewOrEdit(item)
                        }
                    }
                    .contextMenu { fileContextMenu(item) }
                }
            }
            .padding(10)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func fileContextMenu(_ item: SFTPFileItem) -> some View {
        if item.isDirectory {
            Button { Task { try? await sftpSession.navigateTo(item.path) } } label: {
                Label("Open", systemImage: "folder")
            }
        } else {
            Button { previewOrEdit(item) } label: {
                Label("Open", systemImage: "eye")
            }
            if item.isTextFile {
                Button { openEditor(for: item) } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            Button { downloadFile(item) } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }

        Button {
            renameItemID = item.id
            renameText = item.name
        } label: {
            Label("Rename", systemImage: "pencil.line")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.path, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            itemToDelete = item
            showingDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - File Preview Panel

    private func filePreviewPanel(_ item: SFTPFileItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(item.isDirectory ? KestrelColors.amber : KestrelColors.textMuted)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(KestrelFonts.monoBold(12))
                        .foregroundStyle(KestrelColors.textPrimary)
                        .lineLimit(1)
                    Text(item.formattedSize)
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                previewInfoRow("Permissions", item.permissions)
                previewInfoRow("Owner", item.owner)
                if let modified = item.modified {
                    previewInfoRow("Modified", modified.formatted(.dateTime))
                }
                previewInfoRow("Path", item.path)
            }

            HStack(spacing: 8) {
                Button { downloadFile(item) } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                }
                .buttonStyle(.plain)

                if item.isTextFile {
                    Button { openEditor(for: item) } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(height: 200)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(KestrelColors.backgroundCard)
    }

    private func previewInfoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(KestrelFonts.mono(10))
                .foregroundStyle(KestrelColors.textMuted)
                .lineLimit(1)
        }
    }

    // MARK: - Transfer Bar

    @ViewBuilder
    private var transferBar: some View {
        if !transfers.isEmpty {
            HStack(spacing: 8) {
                ProgressView(value: transfers.first?.progress ?? 0)
                    .tint(KestrelColors.phosphorGreen)
                    .frame(width: 120)
                Text(transfers.first?.fileName ?? "")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textMuted)
                    .lineLimit(1)
                Spacer()
                Text("\(transfers.count) transfer\(transfers.count == 1 ? "" : "s")")
                    .font(KestrelFonts.mono(9))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(KestrelColors.backgroundCard)
            .overlay(alignment: .top) {
                Rectangle().fill(KestrelColors.cardBorder).frame(height: 1)
            }
        }
    }

    private var transferPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TRANSFERS")
                .font(KestrelFonts.mono(9))
                .tracking(1.0)
                .foregroundStyle(KestrelColors.textFaint)
            ForEach(transfers) { transfer in
                HStack(spacing: 6) {
                    Image(systemName: transfer.isUpload ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9))
                        .foregroundStyle(KestrelColors.phosphorGreen)
                    Text(transfer.fileName)
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textMuted)
                        .lineLimit(1)
                    Spacer()
                    ProgressView(value: transfer.progress)
                        .frame(width: 60)
                        .tint(KestrelColors.phosphorGreen)
                    Button {
                        transfers.removeAll { $0.id == transfer.id }
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(KestrelColors.phosphorGreen)
            Text("Connecting to \(server.name)…")
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28))
                .foregroundStyle(KestrelColors.red)
            Text("Connection Failed")
                .font(KestrelFonts.monoBold(13))
                .foregroundStyle(KestrelColors.textPrimary)
            Text(message)
                .font(KestrelFonts.mono(11))
                .foregroundStyle(KestrelColors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                connectIfNeeded()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.phosphorGreen)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disconnectedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 36))
                .foregroundStyle(KestrelColors.textFaint)
            Text("SFTP File Manager")
                .font(KestrelFonts.display(16, weight: .semibold))
                .foregroundStyle(KestrelColors.textMuted)
            Button {
                connectIfNeeded()
            } label: {
                Label("Connect", systemImage: "bolt.fill")
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.phosphorGreen)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(KestrelColors.phosphorGreenDim)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func connectIfNeeded() {
        guard !sftpSession.isConnected, !sftpSession.isLoading else { return }
        Task { try? await sftpSession.connect(server: server) }
    }

    private func previewOrEdit(_ item: SFTPFileItem) {
        selectedItem = item
        showPreview = true
    }

    private func openEditor(for item: SFTPFileItem) {
        editorFilePath = item.path
        editorContent = ""
        editorOriginalContent = ""
        showingEditor = true
        Task {
            let data = try await sftpSession.readFile(at: item.path)
            let text = String(data: data, encoding: .utf8) ?? "[Binary file]"
            editorContent = text
            editorOriginalContent = text
        }
    }

    private func saveEditedFile() {
        Task {
            if let data = editorContent.data(using: .utf8) {
                try? await sftpSession.writeFile(at: editorFilePath, data: data)
            }
            editorOriginalContent = editorContent
        }
    }

    private func commitRename(_ item: SFTPFileItem) {
        guard !renameText.isEmpty, renameText != item.name else {
            renameItemID = nil
            return
        }
        Task {
            try? await sftpSession.rename(at: item.path, to: renameText)
            renameItemID = nil
        }
    }

    private func downloadFile(_ item: SFTPFileItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let transfer = TransferItem(fileName: item.name, isUpload: false)
            transfers.append(transfer)
            Task {
                try? await sftpSession.downloadFile(remotePath: item.path, localURL: url) { prog in
                    if let idx = transfers.firstIndex(where: { $0.id == transfer.id }) {
                        transfers[idx].progress = prog
                    }
                }
                transfers.removeAll { $0.id == transfer.id }
            }
        }
    }

    private func openUploadPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                let remotePath = (sftpSession.currentPath as NSString).appendingPathComponent(url.lastPathComponent)
                let transfer = TransferItem(fileName: url.lastPathComponent, isUpload: true)
                transfers.append(transfer)
                Task {
                    try? await sftpSession.uploadFile(localURL: url, remotePath: remotePath) { prog in
                        if let idx = transfers.firstIndex(where: { $0.id == transfer.id }) {
                            transfers[idx].progress = prog
                        }
                    }
                    transfers.removeAll { $0.id == transfer.id }
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        let basePath = sftpSession.currentPath
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let remotePath = (basePath as NSString).appendingPathComponent(url.lastPathComponent)
                let transfer = TransferItem(fileName: url.lastPathComponent, isUpload: true)
                Task { @MainActor in
                    transfers.append(transfer)
                    try? await sftpSession.uploadFile(localURL: url, remotePath: remotePath) { prog in
                        if let idx = transfers.firstIndex(where: { $0.id == transfer.id }) {
                            transfers[idx].progress = prog
                        }
                    }
                    transfers.removeAll { $0.id == transfer.id }
                }
            }
        }
    }

    // MARK: - Path Helpers

    private struct PathComponent {
        let name: String
        let fullPath: String
    }

    private func pathComponents(_ path: String) -> [PathComponent] {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        var components = [PathComponent(name: "/", fullPath: "/")]
        var acc = ""
        for part in parts {
            acc += "/\(part)"
            components.append(PathComponent(name: String(part), fullPath: acc))
        }
        return components
    }
}

// MARK: - Transfer Item

struct TransferItem: Identifiable {
    let id = UUID()
    let fileName: String
    let isUpload: Bool
    var progress: Double = 0
}

// MARK: - Mac File Editor Sheet

struct MacFileEditorSheet: View {
    let fileName: String
    @Binding var content: String
    let originalContent: String
    var onSave: () -> Void
    var onDismissUnsaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var hasChanges: Bool { content != originalContent }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(fileName)
                    .font(KestrelFonts.monoBold(13))
                    .foregroundStyle(KestrelColors.textPrimary)
                if hasChanges {
                    Circle()
                        .fill(KestrelColors.amber)
                        .frame(width: 6, height: 6)
                }
                Spacer()
                Button("Save") {
                    onSave()
                }
                .disabled(!hasChanges)
                .keyboardShortcut("s", modifiers: .command)

                Button("Close") {
                    if hasChanges { onDismissUnsaved() }
                    else { dismiss() }
                }
            }
            .padding()

            Divider().overlay(KestrelColors.cardBorder)

            // Editor
            TextEditor(text: $content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(KestrelColors.phosphorGreen)
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(KestrelColors.background)
    }
}
