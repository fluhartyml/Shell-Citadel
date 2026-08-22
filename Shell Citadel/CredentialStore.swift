//
//  CredentialStore.swift
//  Shell Citadel
//
//  The password lives in the Keychain and nowhere else.
//
//  WHY NOT UserDefaults: UserDefaults is a plist in the app container — plain text,
//  included in backups, readable by anything that gets at the container. A host key
//  fingerprint can live there because it is a value to COMPARE against, not a secret.
//  A password that opens a shell on someone's Mac cannot.
//
//  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is deliberate on both halves:
//  WhenUnlocked means a locked phone in someone else's hands does not give up the
//  password, and ThisDeviceOnly keeps it out of iCloud Keychain and out of backups,
//  so it cannot follow a restore onto a device the owner no longer controls.
//
//  The password is never logged, never put in an error message, and never written
//  into the transcript — the shell command built in SSHSession contains the text the
//  user typed, never the credential.
//

import Foundation
import Security

enum CredentialStore {

    private static let service = "com.nightgard.Shell-Citadel.ssh"

    /// Keyed by the connection, so more than one machine can be saved later without
    /// the profiles colliding.
    private static func account(for profile: ConnectionProfile) -> String {
        "\(profile.username)@\(profile.host):\(profile.port)"
    }

    // MARK: - Save

    @discardableResult
    static func save(password: String, for profile: ConnectionProfile) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let account = account(for: profile)

        // Delete first: SecItemAdd fails with errSecDuplicateItem rather than
        // overwriting, and an "update or add" branch is more code for the same result.
        delete(for: profile)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Read

    static func password(for profile: ConnectionProfile) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: profile),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return password
    }

    // MARK: - Delete

    @discardableResult
    static func delete(for profile: ConnectionProfile) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: profile),
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
