//
//  MacCommandLibraryView.swift
//  Kestrel Mac
//
//  macOS command library with split-view master/detail layout.
//  Same commands as iOS, adapted for Mac screen width.
//

import SwiftUI

// MARK: - Mac Command Library View

struct MacCommandLibraryView: View {
    @EnvironmentObject var sessionManager: SSHSessionManager
    @EnvironmentObject var serverRepository: ServerRepository
    @EnvironmentObject var revenueCatService: RevenueCatService
    @StateObject private var commandRepo = CommandRepository()

    @State private var searchText = ""
    @State private var selectedCategory: CommandCategory? = nil
    @State private var selectedCommand: SavedCommand?
    @State private var showingAddSheet = false
    @State private var commandToEdit: SavedCommand?
    @State private var showingEditSheet = false
    @State private var showingPaywall = false

    // Variable resolution
    @State private var variableValues: [String: String] = [:]
    @State private var showingSendConfirmation = false
    @State private var broadcastToAll = false

    // MARK: - Filtered Commands

    private var filteredCommands: [SavedCommand] {
        var result = commandRepo.commands
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                $0.command.lowercased().contains(q) ||
                ($0.commandDescription?.lowercased().contains(q) ?? false)
            }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            commandListPanel
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 320)
            commandDetailPanel
                .frame(maxWidth: .infinity)
        }
        .background(KestrelColors.background)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search commands…")
        .sheet(isPresented: $showingAddSheet) {
            MacAddEditCommandSheet(mode: .add) { name, command, category, desc in
                let cmd = SavedCommand(name: name, command: command, category: category, commandDescription: desc)
                commandRepo.addCommand(cmd)
                selectedCommand = cmd
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let cmd = commandToEdit {
                MacAddEditCommandSheet(mode: .edit(cmd)) { name, command, category, desc in
                    cmd.name = name
                    cmd.command = command
                    cmd.category = category
                    cmd.commandDescription = desc
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            MacPaywallView()
        }
    }

    // MARK: - Left Panel: Command List

    private var commandListPanel: some View {
        VStack(spacing: 0) {
            // Category pills
            categoryPills

            // Command list
            List(selection: $selectedCommand) {
                // Favourites
                let favs = filteredCommands.filter(\.isFavourite)
                if !favs.isEmpty {
                    Section {
                        ForEach(favs) { cmd in
                            commandRow(cmd).tag(cmd)
                        }
                    } header: {
                        Text("FAVOURITES")
                            .font(KestrelFonts.mono(9))
                            .tracking(1.0)
                            .foregroundStyle(KestrelColors.textFaint)
                    }
                }

                // All
                Section {
                    ForEach(filteredCommands) { cmd in
                        commandRow(cmd).tag(cmd)
                    }
                } header: {
                    Text(selectedCategory?.displayName.uppercased() ?? "ALL COMMANDS")
                        .font(KestrelFonts.mono(9))
                        .tracking(1.0)
                        .foregroundStyle(KestrelColors.textFaint)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            // Add button at bottom
            HStack {
                Button {
                    if revenueCatService.canAccess(.commandLibraryEdit) {
                        showingAddSheet = true
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Label("New Command", systemImage: "plus")
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                        if !revenueCatService.isProOrBundle {
                            ProBadge()
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text("\(filteredCommands.count)")
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(KestrelColors.backgroundCard)
            .overlay(alignment: .top) {
                Rectangle().fill(KestrelColors.cardBorder).frame(height: 1)
            }
        }
        .background(KestrelColors.background)
    }

    // MARK: - Category Pills

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                categoryPill("All", nil)
                ForEach(CommandCategory.allCases, id: \.self) { cat in
                    categoryPill(cat.displayName, cat)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(KestrelColors.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(KestrelColors.cardBorder).frame(height: 1)
        }
    }

    private func categoryPill(_ label: String, _ cat: CommandCategory?) -> some View {
        let isSelected = selectedCategory == cat
        return Button {
            withAnimation(.snappy(duration: 0.15)) { selectedCategory = cat }
        } label: {
            Text(label)
                .font(KestrelFonts.mono(10))
                .foregroundStyle(isSelected ? KestrelColors.background : KestrelColors.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? KestrelColors.phosphorGreen : KestrelColors.backgroundCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? KestrelColors.phosphorGreen : KestrelColors.cardBorder,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Command Row

    private func commandRow(_ cmd: SavedCommand) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cmd.name)
                        .font(KestrelFonts.monoBold(12))
                        .foregroundStyle(KestrelColors.textPrimary)
                        .lineLimit(1)
                    categoryBadge(cmd.category)
                }
                Text(String(cmd.command.prefix(40)))
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.phosphorGreen.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if cmd.isFavourite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(KestrelColors.amber)
            }

            if cmd.useCount > 5 {
                Text("\(cmd.useCount)")
                    .font(KestrelFonts.mono(8))
                    .foregroundStyle(KestrelColors.textFaint)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(KestrelColors.textFaint.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                if revenueCatService.canAccess(.commandLibraryEdit) {
                    commandToEdit = cmd; showingEditSheet = true
                } else {
                    showingPaywall = true
                }
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .disabled(cmd.isBuiltIn)

            Button { commandRepo.duplicate(cmd) } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cmd.command, forType: .string)
            } label: {
                Label("Copy Command", systemImage: "doc.on.doc")
            }

            Button { sendToTerminal(cmd) } label: {
                Label("Send to Terminal", systemImage: "paperplane.fill")
            }

            Divider()

            Button {
                cmd.isFavourite.toggle()
            } label: {
                Label(cmd.isFavourite ? "Unfavourite" : "Favourite", systemImage: cmd.isFavourite ? "star.slash" : "star")
            }

            if !cmd.isBuiltIn {
                Divider()
                Button(role: .destructive) { commandRepo.deleteCommand(cmd) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func categoryBadge(_ cat: CommandCategory) -> some View {
        Text(cat.displayName.uppercased())
            .font(KestrelFonts.mono(7))
            .fontWeight(.bold)
            .tracking(0.5)
            .foregroundStyle(cat.color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(cat.color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Right Panel: Command Detail

    @ViewBuilder
    private var commandDetailPanel: some View {
        if let cmd = selectedCommand {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    detailHeader(cmd)

                    Divider().overlay(KestrelColors.cardBorder)

                    // Command code block
                    commandCodeBlock(cmd)

                    // Variable inputs
                    let vars = CommandVariableParser.extractVariables(from: cmd.command)
                    if !vars.isEmpty {
                        variableInputs(vars)
                    }

                    // Live preview
                    if !vars.isEmpty {
                        livePreview(cmd)
                    }

                    Divider().overlay(KestrelColors.cardBorder)

                    // Target server selector
                    serverSelector

                    // Send button
                    sendButton(cmd)
                }
                .padding(20)
            }
            .background(KestrelColors.background)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 32))
                    .foregroundStyle(KestrelColors.textFaint)
                Text("Select a command")
                    .font(KestrelFonts.mono(13))
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KestrelColors.background)
        }
    }

    // MARK: - Detail Subviews

    private func detailHeader(_ cmd: SavedCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(cmd.name)
                    .font(KestrelFonts.display(20, weight: .bold))
                    .foregroundStyle(KestrelColors.textPrimary)
                categoryBadge(cmd.category)
                if cmd.isBuiltIn {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(KestrelColors.textFaint)
                        .help("Built-in command (read-only)")
                }
                Spacer()
                Button {
                    cmd.isFavourite.toggle()
                } label: {
                    Image(systemName: cmd.isFavourite ? "star.fill" : "star")
                        .font(.system(size: 16))
                        .foregroundStyle(cmd.isFavourite ? KestrelColors.amber : KestrelColors.textFaint)
                }
                .buttonStyle(.plain)
            }

            if let desc = cmd.commandDescription, !desc.isEmpty {
                Text(desc)
                    .font(KestrelFonts.mono(12))
                    .foregroundStyle(KestrelColors.textMuted)
            }

            HStack(spacing: 12) {
                if cmd.useCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9))
                        Text("Used \(cmd.useCount) times")
                    }
                    .font(KestrelFonts.mono(10))
                    .foregroundStyle(KestrelColors.textFaint)
                }
            }
        }
    }

    private func commandCodeBlock(_ cmd: SavedCommand) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("COMMAND")
                    .font(KestrelFonts.mono(9))
                    .tracking(1.0)
                    .foregroundStyle(KestrelColors.textFaint)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd.command, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textMuted)
                }
                .buttonStyle(.plain)
            }

            // Command text with variable highlighting
            highlightedCommand(cmd.command)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                )
                .textSelection(.enabled)
        }
    }

    private func highlightedCommand(_ command: String) -> Text {
        // Split command into segments, highlighting {variables} in amber
        let pattern = #"\{[a-zA-Z_][a-zA-Z0-9_]*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return Text(command)
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.phosphorGreen)
        }

        let nsString = command as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: command, range: fullRange)

        var result = Text("")
        var lastEnd = 0

        for match in matches {
            let range = match.range
            if range.location > lastEnd {
                let prefix = nsString.substring(with: NSRange(location: lastEnd, length: range.location - lastEnd))
                result = result + Text(prefix)
                    .font(KestrelFonts.mono(13))
                    .foregroundStyle(KestrelColors.phosphorGreen)
            }
            let varText = nsString.substring(with: range)
            result = result + Text(varText)
                .font(KestrelFonts.monoBold(13))
                .foregroundStyle(KestrelColors.amber)
            lastEnd = range.location + range.length
        }

        if lastEnd < nsString.length {
            let suffix = nsString.substring(from: lastEnd)
            result = result + Text(suffix)
                .font(KestrelFonts.mono(13))
                .foregroundStyle(KestrelColors.phosphorGreen)
        }

        return result
    }

    private func variableInputs(_ vars: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("VARIABLES")
                    .font(KestrelFonts.mono(9))
                    .tracking(1.0)
                    .foregroundStyle(KestrelColors.textFaint)
                Spacer()
                Button("Clear All") {
                    for v in vars { variableValues[v] = "" }
                }
                .font(KestrelFonts.mono(9))
                .foregroundStyle(KestrelColors.textFaint)
                .buttonStyle(.plain)
            }

            ForEach(vars, id: \.self) { varName in
                VStack(alignment: .leading, spacing: 3) {
                    Text(CommandVariableParser.displayName(for: varName))
                        .font(KestrelFonts.mono(10))
                        .foregroundStyle(KestrelColors.textMuted)
                    TextField(varName, text: variableBinding(for: varName))
                        .font(KestrelFonts.mono(12))
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(KestrelColors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(KestrelColors.cardBorder, lineWidth: 1)
                        )
                }
            }
        }
        .onAppear {
            for v in vars where variableValues[v] == nil {
                variableValues[v] = ""
            }
        }
    }

    private func livePreview(_ cmd: SavedCommand) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PREVIEW")
                .font(KestrelFonts.mono(9))
                .tracking(1.0)
                .foregroundStyle(KestrelColors.textFaint)

            Text(CommandVariableParser.resolve(command: cmd.command, variables: variableValues))
                .font(KestrelFonts.mono(12))
                .foregroundStyle(KestrelColors.phosphorGreen)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1)
                )
        }
    }

    private var serverSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TARGET")
                .font(KestrelFonts.mono(9))
                .tracking(1.0)
                .foregroundStyle(KestrelColors.textFaint)

            let sessions = sessionManager.connectedSessions
            if sessions.isEmpty {
                Text("No active sessions — connect to a server first")
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textFaint)
            } else {
                ForEach(serverRepository.servers.filter { server in
                    sessionManager.activeSession(for: server.id)?.isConnected == true
                }) { server in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(KestrelColors.phosphorGreen)
                            .frame(width: 6, height: 6)
                        Text(server.name)
                            .font(KestrelFonts.mono(11))
                            .foregroundStyle(KestrelColors.textPrimary)
                        Text(server.host)
                            .font(KestrelFonts.mono(10))
                            .foregroundStyle(KestrelColors.textFaint)
                        Spacer()
                    }
                    .padding(8)
                    .background(KestrelColors.backgroundCard)
                    .cornerRadius(6)
                }

                Toggle("Send to all active sessions", isOn: $broadcastToAll)
                    .font(KestrelFonts.mono(11))
                    .foregroundStyle(KestrelColors.textMuted)
                    .tint(KestrelColors.phosphorGreen)
            }
        }
    }

    private func sendButton(_ cmd: SavedCommand) -> some View {
        let resolved = CommandVariableParser.resolve(command: cmd.command, variables: variableValues)
        let sessions = sessionManager.connectedSessions
        let isDangerous = resolved.contains("sudo") || resolved.contains("rm ")

        return Button {
            if isDangerous {
                showingSendConfirmation = true
            } else {
                executeSend(cmd, resolved: resolved)
            }
        } label: {
            HStack {
                Image(systemName: "paperplane.fill")
                Text(broadcastToAll && sessions.count > 1
                     ? "Send to \(sessions.count) sessions"
                     : "Send to Terminal")
            }
            .font(KestrelFonts.monoBold(13))
            .foregroundStyle(sessions.isEmpty ? KestrelColors.textFaint : KestrelColors.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(sessions.isEmpty ? KestrelColors.backgroundCard : KestrelColors.phosphorGreen)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(sessions.isEmpty)
        .confirmationDialog("Send command?", isPresented: $showingSendConfirmation, titleVisibility: .visible) {
            Button("Send", role: .destructive) { executeSend(cmd, resolved: resolved) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This command contains sudo or rm. Confirm execution:\n\(resolved)")
        }
    }

    // MARK: - Actions

    private func sendToTerminal(_ cmd: SavedCommand) {
        let vars = CommandVariableParser.extractVariables(from: cmd.command)
        let resolved = vars.isEmpty ? cmd.command : CommandVariableParser.resolve(command: cmd.command, variables: variableValues)
        executeSend(cmd, resolved: resolved)
    }

    private func executeSend(_ cmd: SavedCommand, resolved: String) {
        let sessions = sessionManager.connectedSessions
        if broadcastToAll {
            for session in sessions { session.send(resolved + "\n") }
        } else if let first = sessions.first {
            first.send(resolved + "\n")
        }
        cmd.useCount += 1
    }

    private func variableBinding(for key: String) -> Binding<String> {
        Binding(
            get: { variableValues[key] ?? "" },
            set: { variableValues[key] = $0 }
        )
    }
}

// MARK: - Add/Edit Command Sheet

enum MacCommandSheetMode {
    case add
    case edit(SavedCommand)
}

struct MacAddEditCommandSheet: View {
    let mode: MacCommandSheetMode
    let onSave: (String, String, CommandCategory, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var command = ""
    @State private var category: CommandCategory = .custom
    @State private var commandDescription = ""

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var detectedVariables: [String] {
        CommandVariableParser.extractVariables(from: command)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text(isEditing ? "Edit Command" : "New Command")
                    .font(KestrelFonts.monoBold(14))
                    .foregroundStyle(KestrelColors.textPrimary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .foregroundStyle(KestrelColors.textMuted)
            }
            .padding()

            Divider().overlay(KestrelColors.cardBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NAME").font(KestrelFonts.mono(9)).tracking(1.0).foregroundStyle(KestrelColors.textFaint)
                        TextField("e.g. Check disk usage", text: $name)
                            .font(KestrelFonts.mono(13))
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(KestrelColors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(KestrelColors.cardBorder, lineWidth: 1))
                    }

                    // Command
                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMMAND").font(KestrelFonts.mono(9)).tracking(1.0).foregroundStyle(KestrelColors.textFaint)
                        TextEditor(text: $command)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(KestrelColors.phosphorGreen)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 80, maxHeight: 160)
                            .padding(8)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(KestrelColors.cardBorderGreen, lineWidth: 1))

                        Text("Use {variableName} for dynamic values")
                            .font(KestrelFonts.mono(9))
                            .foregroundStyle(KestrelColors.textFaint)
                    }

                    // Detected variables
                    if !detectedVariables.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(detectedVariables, id: \.self) { v in
                                Text("{\(v)}")
                                    .font(KestrelFonts.mono(10))
                                    .foregroundStyle(KestrelColors.amber)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(KestrelColors.amber.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // Category
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CATEGORY").font(KestrelFonts.mono(9)).tracking(1.0).foregroundStyle(KestrelColors.textFaint)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(CommandCategory.allCases, id: \.self) { cat in
                                    Button { category = cat } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: cat.icon).font(.system(size: 9))
                                            Text(cat.displayName).font(KestrelFonts.mono(10))
                                        }
                                        .foregroundStyle(category == cat ? KestrelColors.background : KestrelColors.textMuted)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(category == cat ? KestrelColors.phosphorGreen : KestrelColors.backgroundCard)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DESCRIPTION").font(KestrelFonts.mono(9)).tracking(1.0).foregroundStyle(KestrelColors.textFaint)
                        TextField("What does this command do?", text: $commandDescription)
                            .font(KestrelFonts.mono(12))
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(KestrelColors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(KestrelColors.cardBorder, lineWidth: 1))
                    }

                    // Save
                    Button {
                        onSave(name.trimmed, command.trimmed, category, commandDescription.isEmpty ? nil : commandDescription)
                        dismiss()
                    } label: {
                        Text(isEditing ? "Save Changes" : "Add Command")
                            .font(KestrelFonts.monoBold(13))
                            .foregroundStyle(isValid ? KestrelColors.background : KestrelColors.textFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(isValid ? KestrelColors.phosphorGreen : KestrelColors.backgroundCard)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(!isValid)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 480, minHeight: 450)
        .background(KestrelColors.background)
        .onAppear {
            if case .edit(let cmd) = mode {
                name = cmd.name
                command = cmd.command
                category = cmd.category
                commandDescription = cmd.commandDescription ?? ""
            }
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
