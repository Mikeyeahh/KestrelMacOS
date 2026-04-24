//
//  NotificationManager.swift
//  Kestrel Mac
//
//  UserNotifications for service alerts, sync conflicts, and disconnects.
//  Uses the same notification identifiers as iOS to avoid duplicates.
//

import Foundation
import UserNotifications
import AppKit

// MARK: - Notification Identifiers

enum KestrelNotificationID {
    static let serviceFailure = "kestrel.service.failure"
    static let syncConflict = "kestrel.sync.conflict"
    static let sessionDisconnect = "kestrel.session.disconnect"
}

// MARK: - Notification Manager

@MainActor
class KestrelNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = KestrelNotificationManager()

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Service Failure

    func notifyServiceFailure(serverName: String, serviceName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Service Alert — \(serverName)"
        content.body = "\(serviceName) has stopped on \(serverName)."
        content.sound = .default
        content.categoryIdentifier = KestrelNotificationID.serviceFailure
        content.threadIdentifier = serverName

        let request = UNNotificationRequest(
            identifier: "\(KestrelNotificationID.serviceFailure).\(serverName).\(serviceName)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Sync Conflict

    func notifySyncConflict(detail: String) {
        let content = UNMutableNotificationContent()
        content.title = "Kestrel — Sync Conflict"
        content.body = detail
        content.sound = .default
        content.categoryIdentifier = KestrelNotificationID.syncConflict

        let request = UNNotificationRequest(
            identifier: "\(KestrelNotificationID.syncConflict).\(Date.now.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Session Disconnect

    func notifySessionDisconnect(serverName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Disconnected — \(serverName)"
        content.body = "SSH session to \(serverName) was disconnected unexpectedly."
        content.sound = .default
        content.categoryIdentifier = KestrelNotificationID.sessionDisconnect
        content.threadIdentifier = serverName

        let request = UNNotificationRequest(
            identifier: "\(KestrelNotificationID.sessionDisconnect).\(serverName).\(Date.now.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.identifier
        await MainActor.run {
            // Activate app when notification is tapped
            NSApp.activate(ignoringOtherApps: true)

            if id.hasPrefix(KestrelNotificationID.sessionDisconnect) {
                // Could navigate to the disconnected server
            }
        }
    }
}
