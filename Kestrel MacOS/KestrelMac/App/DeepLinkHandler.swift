//
//  DeepLinkHandler.swift
//  Kestrel Mac
//
//  Deep link handling, Handoff, and Spotlight integration.
//

import SwiftUI
import CoreSpotlight
import AppKit

// MARK: - Deep Link Route

enum DeepLinkRoute {
    case connect(host: String, port: Int, user: String?)
    case terminal(serverID: UUID)
    case files(serverID: UUID, path: String?)
    case ospreyImport(host: String)
    case authCallback(url: URL)

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let pairs: [(String, String)] = (components.queryItems ?? []).compactMap {
            guard let value = $0.value else { return nil }
            return ($0.name, value)
        }
        let params = Dictionary(uniqueKeysWithValues: pairs)

        switch (url.scheme, url.host) {
        case ("kestrel", "auth"):
            self = .authCallback(url: url)

        case ("kestrel", "connect"):
            guard let host = params["host"] else { return nil }
            self = .connect(
                host: host,
                port: Int(params["port"] ?? "22") ?? 22,
                user: params["user"]
            )

        case ("kestrel", "terminal"):
            guard let idStr = params["serverID"], let id = UUID(uuidString: idStr) else { return nil }
            self = .terminal(serverID: id)

        case ("kestrel", "files"):
            guard let idStr = params["serverID"], let id = UUID(uuidString: idStr) else { return nil }
            self = .files(serverID: id, path: params["path"])

        case ("osprey", "import"):
            guard let host = params["host"] else { return nil }
            self = .ospreyImport(host: host)

        default:
            return nil
        }
    }
}

// MARK: - Deep Link Handler

@MainActor
class DeepLinkHandler: ObservableObject {
    static let shared = DeepLinkHandler()

    @Published var pendingRoute: DeepLinkRoute?
    @Published var pendingConnectHost: String?
    @Published var pendingConnectPort: Int = 22
    @Published var pendingConnectUser: String?
    @Published var showAddServerSheet = false

    func handle(url: URL) {
        guard let route = DeepLinkRoute(url: url) else { return }
        NSApp.activate(ignoringOtherApps: true)

        switch route {
        case .authCallback(let callbackURL):
            Task {
                await handleAuthCallback(callbackURL)
            }

        case .connect(let host, let port, let user):
            pendingConnectHost = host
            pendingConnectPort = port
            pendingConnectUser = user
            showAddServerSheet = true

        case .terminal(let serverID):
            NotificationCenter.default.post(
                name: .kestrelOpenServer,
                object: nil,
                userInfo: ["serverID": serverID, "view": "terminal"]
            )

        case .files(let serverID, let path):
            NotificationCenter.default.post(
                name: .kestrelOpenServer,
                object: nil,
                userInfo: ["serverID": serverID, "view": "files", "path": path as Any]
            )

        case .ospreyImport(let host):
            pendingConnectHost = host
            showAddServerSheet = true
        }

        pendingRoute = route
    }

    private func handleAuthCallback(_ url: URL) async {
        await SupabaseService.shared.handleAuthCallback(url)
    }
}

// MARK: - Handoff Activity Types

enum KestrelActivityType {
    static let terminal = "com.getosprey.kestrel.terminal"
    static let dashboard = "com.getosprey.kestrel.dashboard"
    static let files = "com.getosprey.kestrel.files"
}

// MARK: - Handoff Activity Manager

@MainActor
class HandoffManager {
    static let shared = HandoffManager()

    private var currentActivity: NSUserActivity?

    func advertiseTerminalSession(server: Server) {
        let activity = NSUserActivity(activityType: KestrelActivityType.terminal)
        activity.title = "Terminal — \(server.name)"
        activity.userInfo = [
            "serverID": server.id.uuidString,
            "serverName": server.name
        ]
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        // isEligibleForPrediction is iOS-only

        currentActivity?.invalidate()
        currentActivity = activity
        activity.becomeCurrent()
    }

    func advertiseDashboard(server: Server) {
        let activity = NSUserActivity(activityType: KestrelActivityType.dashboard)
        activity.title = "Dashboard — \(server.name)"
        activity.userInfo = [
            "serverID": server.id.uuidString,
            "serverName": server.name
        ]
        activity.isEligibleForHandoff = true
        currentActivity?.invalidate()
        currentActivity = activity
        activity.becomeCurrent()
    }

    func advertiseFiles(server: Server, path: String) {
        let activity = NSUserActivity(activityType: KestrelActivityType.files)
        activity.title = "Files — \(server.name)"
        activity.userInfo = [
            "serverID": server.id.uuidString,
            "serverName": server.name,
            "path": path
        ]
        activity.isEligibleForHandoff = true
        currentActivity?.invalidate()
        currentActivity = activity
        activity.becomeCurrent()
    }

    func handleIncomingActivity(_ activity: NSUserActivity) {
        guard let serverIDStr = activity.userInfo?["serverID"] as? String,
              let serverID = UUID(uuidString: serverIDStr) else { return }

        NSApp.activate(ignoringOtherApps: true)

        let view: String
        switch activity.activityType {
        case KestrelActivityType.terminal: view = "terminal"
        case KestrelActivityType.dashboard: view = "dashboard"
        case KestrelActivityType.files: view = "files"
        default: view = "terminal"
        }

        NotificationCenter.default.post(
            name: .kestrelOpenServer,
            object: nil,
            userInfo: ["serverID": serverID, "view": view]
        )
    }

    func stopAdvertising() {
        currentActivity?.invalidate()
        currentActivity = nil
    }
}

// MARK: - Spotlight Indexer

class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    func indexServer(_ server: Server) {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = server.name
        attributes.contentDescription = "\(server.host) · \(server.serverEnvironment.displayName)"
        attributes.keywords = [server.name, server.host, server.serverEnvironment.displayName]
        attributes.url = URL(string: "kestrel://terminal?serverID=\(server.id)")

        let item = CSSearchableItem(
            uniqueIdentifier: server.id.uuidString,
            domainIdentifier: "com.getosprey.kestrel.servers",
            attributeSet: attributes
        )

        CSSearchableIndex.default().indexSearchableItems([item])
    }

    func removeServer(_ server: Server) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [server.id.uuidString])
    }

    func reindexAll(servers: [Server]) {
        // Remove all, then re-add
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: ["com.getosprey.kestrel.servers"]) { _ in
            let items = servers.map { server in
                let attrs = CSSearchableItemAttributeSet(contentType: .content)
                attrs.title = server.name
                attrs.contentDescription = "\(server.host) · \(server.serverEnvironment.displayName)"
                attrs.url = URL(string: "kestrel://terminal?serverID=\(server.id)")
                return CSSearchableItem(
                    uniqueIdentifier: server.id.uuidString,
                    domainIdentifier: "com.getosprey.kestrel.servers",
                    attributeSet: attrs
                )
            }
            CSSearchableIndex.default().indexSearchableItems(items)
        }
    }
}
