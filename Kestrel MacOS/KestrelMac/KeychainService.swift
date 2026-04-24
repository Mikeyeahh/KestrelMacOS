//
//  KeychainService.swift
//  Kestrel Mac
//
//  Keychain access for SSH private keys and passwords.
//

import Foundation
import Security

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed
    case deleteFailed(OSStatus)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Failed to save to Keychain (status: \(status))"
        case .loadFailed:
            "Item not found in Keychain"
        case .deleteFailed(let status):
            "Failed to delete from Keychain (status: \(status))"
        case .encodingFailed:
            "Failed to encode data"
        }
    }
}

struct KeychainService {
    private static let service = "com.kestrel.ssh-keys"
    private static let passwordService = "com.kestrel.ssh-passwords"

    // MARK: - Private Keys

    static func savePrivateKey(_ pem: String, for keyID: UUID) throws {
        guard let data = pem.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        try? deletePrivateKey(for: keyID)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyID.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func loadPrivateKey(for keyID: UUID) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyID.uuidString,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let pem = String(data: data, encoding: .utf8) else {
            throw KeychainError.loadFailed
        }

        return pem
    }

    static func deletePrivateKey(for keyID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyID.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - SSH Passwords

    static func savePassword(_ password: String, for serverID: UUID) throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        try? deletePassword(for: serverID)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: passwordService,
            kSecAttrAccount as String: serverID.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func loadPassword(for serverID: UUID) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: passwordService,
            kSecAttrAccount as String: serverID.uuidString,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.loadFailed
        }

        return password
    }

    static func deletePassword(for serverID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: passwordService,
            kSecAttrAccount as String: serverID.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - VNC / RDP Passwords

    private static let vncPasswordService = "com.kestrel.vnc-passwords"
    private static let rdpPasswordService = "com.kestrel.rdp-passwords"

    static func saveVNCPassword(_ password: String, for serverID: UUID) throws {
        try saveGenericPassword(password, service: vncPasswordService, serverID: serverID)
    }

    static func loadVNCPassword(for serverID: UUID) throws -> String {
        try loadGenericPassword(service: vncPasswordService, serverID: serverID)
    }

    static func deleteVNCPassword(for serverID: UUID) throws {
        try deleteGenericPassword(service: vncPasswordService, serverID: serverID)
    }

    static func saveRDPPassword(_ password: String, for serverID: UUID) throws {
        try saveGenericPassword(password, service: rdpPasswordService, serverID: serverID)
    }

    static func loadRDPPassword(for serverID: UUID) throws -> String {
        try loadGenericPassword(service: rdpPasswordService, serverID: serverID)
    }

    static func deleteRDPPassword(for serverID: UUID) throws {
        try deleteGenericPassword(service: rdpPasswordService, serverID: serverID)
    }

    // MARK: - Generic password helpers

    private static func saveGenericPassword(_ password: String, service: String, serverID: UUID) throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        try? deleteGenericPassword(service: service, serverID: serverID)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private static func loadGenericPassword(service: String, serverID: UUID) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID.uuidString,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.loadFailed
        }

        return password
    }

    private static func deleteGenericPassword(service: String, serverID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverID.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
