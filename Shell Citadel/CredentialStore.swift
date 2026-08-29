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

    /// Keyed by the connection's OWN IDENTITY, not its address.
    ///
    /// This used to be "user@host:port" — which meant the Keychain key changed the moment
    /// the user edited any of those three fields. Editing a saved connection therefore
    /// looked the password up under a key that no longer matched: the old entry was
    /// orphaned and never cleaned up, and the connection silently lost its credential with
    /// nothing on screen saying so. Michael hit exactly that, 2026-08-29, on a saved Mac
    /// whose user name and host were both wrong and could not be corrected.
    ///
    /// The profile's `id` is a UUID that never changes, so a credential now survives any
    /// edit of the connection details. `legacyAccount` exists only to migrate entries
    /// saved by the old scheme; see `password(for:)`.
    private static func account(for profile: ConnectionProfile) -> String {
        profile.id.uuidString
    }

    /// The pre-2026-08-29 key. Read-only — nothing new is ever written under it.
    private static func legacyAccount(for profile: ConnectionProfile) -> String {
        "\(profile.username)@\(profile.host):\(profile.port)"
    }

    // MARK: - Save

    @discardableResult
    static func save(password: String, for profile: ConnectionProfile) -> Bool {
        // An empty password means FORGET IT, not "no change". Before this, a blank field
        // was silently ignored, so a saved password could never be cleared once set.
        guard !password.isEmpty else {
            remove(account: account(for: profile))
            remove(account: legacyAccount(for: profile))
            return true
        }
        return write(password: password, account: account(for: profile))
    }

    private static func write(password: String, account: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        // Delete first: SecItemAdd fails with errSecDuplicateItem rather than
        // overwriting, and an "update or add" branch is more code for the same result.
        remove(account: account)

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
        if let found = read(account: account(for: profile)) { return found }

        // Migration: nothing under the id key, so look for an entry saved by the old
        // "user@host:port" scheme. If one is there, move it to the id key and delete the
        // old one, so this runs at most once per connection and nothing is left behind.
        // Deliberately silent — the user never asked for a migration and does not need to
        // know one happened; they just find their password still works.
        let legacy = legacyAccount(for: profile)
        guard let carried = read(account: legacy) else { return nil }
        _ = write(password: carried, account: account(for: profile))
        remove(account: legacy)
        return carried
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

    /// Deletes under BOTH keys. A connection saved before 2026-08-29 may still have an
    /// entry under the old "user@host:port" account, and deleting only one of the two
    /// would leave a credential behind for something the user believes is gone.
    @discardableResult
    static func delete(for profile: ConnectionProfile) -> Bool {
        let a = remove(account: account(for: profile))
        let b = remove(account: legacyAccount(for: profile))
        return a || b
    }

    @discardableResult
    private static func remove(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
