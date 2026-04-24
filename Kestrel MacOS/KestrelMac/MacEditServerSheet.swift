//
//  MacEditServerSheet.swift
//  Kestrel Mac
//
//  Add or edit a server. Saves to ServerRepository and Keychain.
//

import SwiftUI

struct MacEditServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var serverRepository: ServerRepository

    /// When non-nil, editing an existing server.
    let editingServer: Server?

    init(editing server: Server? = nil) {
        self.editingServer = server
    }

    private var isEditing: Bool { editingServer != nil }

    // MARK: - Connection Type (UI-level)

    /// The dropdown presents MOSH as its own option, even though at the storage
    /// layer MOSH is just `connectionType == "ssh"` + `useMosh = true`.
    private enum ConnectionTypeOption: String, CaseIterable, Identifiable {
        case ssh
        case mosh
        case vnc
        case rdp

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .ssh:  "SSH"
            case .mosh: "SSH + MOSH"
            case .vnc:  "VNC"
            case .rdp:  "RDP"
            }
        }

        var icon: String {
            switch self {
            case .ssh, .mosh: "terminal"
            case .vnc:        "rectangle.on.rectangle"
            case .rdp:        "desktopcomputer"
            }
        }

        var defaultPort: Int {
            switch self {
            case .ssh, .mosh: 22
            case .vnc:        5900
            case .rdp:        3389
            }
        }

        /// How this option maps to the stored connectionType column.
        var connectionType: String {
            switch self {
            case .ssh, .mosh: "ssh"
            case .vnc:        "vnc"
            case .rdp:        "rdp"
            }
        }

        var useMosh: Bool { self == .mosh }

        static func from(connectionType: String, useMosh: Bool) -> ConnectionTypeOption {
            switch connectionType {
            case "vnc": return .vnc
            case "rdp": return .rdp
            default:    return useMosh ? .mosh : .ssh
            }
        }
    }

    // MARK: - Form State

    @State private var connectionTypeOption: ConnectionTypeOption = .ssh
    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authMethod = "password"
    @State private var password = ""
    @State private var environment = "other"
    @State private var group = ""
    @State private var notes = ""

    // MARK: - Validation

    private var isValid: Bool {
        guard !name.isEmpty, !host.isEmpty, Int(port) != nil else { return false }
        switch connectionTypeOption {
        case .vnc:
            return true
        default:
            return !username.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(isEditing ? "Edit Server" : "Add Server")
                    .font(KestrelFonts.monoBold(14))
                    .foregroundStyle(KestrelColors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(KestrelColors.textFaint)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider().overlay(KestrelColors.cardBorder)

            // Form
            Form {
                Section("Protocol") {
                    Picker("Type", selection: $connectionTypeOption) {
                        ForEach(ConnectionTypeOption.allCases) { option in
                            Label(option.displayName, systemImage: option.icon).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: connectionTypeOption) { _, newValue in
                        // Only auto-update port if current value equals the previous default,
                        // so a user's manual override survives switching.
                        if let current = Int(port), isDefaultPort(current) {
                            port = String(newValue.defaultPort)
                        }
                    }
                }

                Section("Connection") {
                    TextField("Name", text: $name)
                    TextField("Host", text: $host)
                    TextField("Port", text: $port)

                    if connectionTypeOption != .vnc {
                        TextField("Username", text: $username)
                    }
                }

                Section("Authentication") {
                    if connectionTypeOption == .ssh || connectionTypeOption == .mosh {
                        Picker("Method", selection: $authMethod) {
                            Text("Password").tag("password")
                            Text("Private Key").tag("privateKey")
                        }

                        if authMethod == "password" {
                            SecureField("Password", text: $password)
                        }
                    } else {
                        SecureField("Password", text: $password)
                    }
                }

                Section("Organisation") {
                    Picker("Environment", selection: $environment) {
                        Text("Production").tag("production")
                        Text("Staging").tag("staging")
                        Text("Development").tag("development")
                        Text("Other").tag("other")
                    }

                    TextField("Group (optional)", text: $group)
                    TextField("Notes (optional)", text: $notes)
                }
            }
            .formStyle(.grouped)

            Divider().overlay(KestrelColors.cardBorder)

            // Bottom buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Add Server") { saveServer() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
                    .buttonStyle(.borderedProminent)
                    .tint(KestrelColors.phosphorGreen)
            }
            .padding(16)
        }
        .frame(width: 440, height: 580)
        .background(KestrelColors.background)
        .onAppear { populateFromEditing() }
    }

    private func isDefaultPort(_ value: Int) -> Bool {
        value == 22 || value == 5900 || value == 3389
    }

    // MARK: - Actions

    private func populateFromEditing() {
        guard let server = editingServer else { return }
        connectionTypeOption = .from(connectionType: server.connectionType, useMosh: server.useMosh)
        name = server.name
        host = server.host
        username = server.username
        authMethod = server.authMethod
        environment = server.environment
        group = server.group ?? ""
        notes = server.notes ?? ""

        // Populate port from the protocol-specific column, falling back to server.port
        switch connectionTypeOption {
        case .vnc:
            port = String(server.vncPort ?? server.port)
        case .rdp:
            port = String(server.rdpPort ?? server.port)
        case .ssh, .mosh:
            port = String(server.port)
        }

        // Load password from the appropriate keychain entry
        switch connectionTypeOption {
        case .vnc:
            if let stored = try? KeychainService.loadVNCPassword(for: server.id) {
                password = stored
            }
        case .rdp:
            if let stored = try? KeychainService.loadRDPPassword(for: server.id) {
                password = stored
            }
        case .ssh, .mosh:
            if let stored = try? KeychainService.loadPassword(for: server.id) {
                password = stored
            }
        }
    }

    private func saveServer() {
        guard isValid, let portNum = Int(port) else { return }

        let effectiveUsername = connectionTypeOption == .vnc ? "" : username
        let effectiveAuthMethod = (connectionTypeOption == .ssh || connectionTypeOption == .mosh) ? authMethod : "password"
        let vncPort = connectionTypeOption == .vnc ? portNum : nil
        let rdpPort = connectionTypeOption == .rdp ? portNum : nil

        if let existing = editingServer {
            var updated = existing
            updated.connectionType = connectionTypeOption.connectionType
            updated.useMosh = connectionTypeOption.useMosh
            updated.name = name
            updated.host = host
            updated.port = portNum
            updated.username = effectiveUsername
            updated.authMethod = effectiveAuthMethod
            updated.environment = environment
            updated.group = group.isEmpty ? nil : group
            updated.notes = notes.isEmpty ? nil : notes
            updated.vncPort = vncPort
            updated.rdpPort = rdpPort
            updated.updatedAt = .now
            serverRepository.updateServer(updated)

            savePassword(for: existing.id)
        } else {
            let server = Server(
                name: name,
                host: host,
                port: portNum,
                username: effectiveUsername,
                authMethod: effectiveAuthMethod,
                group: group.isEmpty ? nil : group,
                environment: environment,
                notes: notes.isEmpty ? nil : notes,
                updatedAt: .now,
                connectionType: connectionTypeOption.connectionType,
                useMosh: connectionTypeOption.useMosh,
                vncPort: vncPort,
                rdpPort: rdpPort
            )
            serverRepository.addServer(server)

            savePassword(for: server.id)
        }

        dismiss()
    }

    private func savePassword(for serverID: UUID) {
        guard !password.isEmpty else { return }
        switch connectionTypeOption {
        case .vnc:
            try? KeychainService.saveVNCPassword(password, for: serverID)
        case .rdp:
            try? KeychainService.saveRDPPassword(password, for: serverID)
        case .ssh, .mosh:
            if authMethod == "password" {
                try? KeychainService.savePassword(password, for: serverID)
            }
        }
    }
}
