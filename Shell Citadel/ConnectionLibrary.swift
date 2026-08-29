//
//  ConnectionLibrary.swift
//  Shell Citadel
//
//  Michael's model, 2026-08-29: "add a saved connections library i can pick from in any
//  tab" — "each connection had a button that made the chosen connection live in the open
//  or focused tab."
//
//  So the LIBRARY owns the definition and a TAB merely runs one. That is the inversion of
//  what tabs shipped with a few hours earlier, where each tab owned its own lone profile
//  and nothing was reusable.
//
//  ONE STORE, SHARED BY EVERY TAB. Editing an entry changes it everywhere it is running,
//  which is the point of a library and also the thing to be careful about.
//
import Combine
import Foundation
import SwiftUI

@MainActor
final class ConnectionLibrary: ObservableObject {
    static let shared = ConnectionLibrary()

    @Published private(set) var connections: [ConnectionProfile] = []

    private let key = "connectionLibrary"

    private init() { load() }

    // MARK: - Mutation

    func add(_ profile: ConnectionProfile) {
        connections.append(profile)
        save()
    }

    func update(_ profile: ConnectionProfile) {
        guard let i = connections.firstIndex(where: { $0.id == profile.id }) else {
            add(profile); return
        }
        connections[i] = profile
        save()
    }

    /// Deleting a saved connection also forgets its password, because leaving a Keychain
    /// entry behind for something the user believes they deleted is a small lie.
    func delete(_ profile: ConnectionProfile) {
        connections.removeAll { $0.id == profile.id }
        _ = CredentialStore.delete(for: profile)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ConnectionProfile].self, from: data)
        else { return }
        connections = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// One-time lift of the pre-library profile so an existing install opens with his Mac
    /// already in the list instead of an empty library and a lost setup.
    func adoptIfEmpty(_ profile: ConnectionProfile) {
        guard connections.isEmpty, profile.isComplete else { return }
        add(profile)
    }
}
