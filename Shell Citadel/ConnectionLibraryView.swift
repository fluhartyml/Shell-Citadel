//
//  ConnectionLibraryView.swift
//  Shell Citadel
//
//  The sliders icon opens THIS in every tab — one shared list of saved connections, each
//  with a button that makes it live in the tab you are looking at. Michael, 2026-08-29.
//
//  DELETE IS A LONG PRESS, NOT A SWIPE. His standing rule: "i dont like swipe to delete /
//  i prefer long press to delete." It is also the safer gesture on the one action that
//  destroys something — a swipe has a direction, a distance and a velocity that can all go
//  wrong by accident; a long press has none of those.
//
import SwiftUI

struct ConnectionLibraryView: View {
    /// The connection this tab is currently running, so the list can mark it.
    let current: ConnectionProfile
    /// True when this tab has a live session — the caller decides whether to challenge.
    let isLive: Bool
    /// Make the chosen connection live in the focused tab.
    let onUse: (ConnectionProfile) -> Void

    @StateObject private var library = ConnectionLibrary.shared
    @Environment(\.dismiss) private var dismiss

    @State private var editing: ConnectionProfile?
    @State private var pendingDelete: ConnectionProfile?

    var body: some View {
        NavigationStack {
            Group {
                if library.connections.isEmpty {
                    ContentUnavailableView {
                        Label("No saved connections", systemImage: "server.rack")
                    } description: {
                        Text("Add a Mac, a Raspberry Pi, or anything else running SSH. Saved connections appear in every tab.")
                    } actions: {
                        Button("Add a connection") { editing = ConnectionProfile() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editing = ConnectionProfile()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add a connection")
                }
            }
            .sheet(item: $editing) { profile in
                ConnectionEditor(profile: profile)
            }
            .confirmationDialog(
                pendingDelete.map { "Delete “\($0.name)”?" } ?? "",
                isPresented: Binding(get: { pendingDelete != nil },
                                     set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let p = pendingDelete { library.delete(p) }
                    pendingDelete = nil
                }
                Button("Keep", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Its saved password is removed too. Any tab already connected stays connected.")
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(library.connections) { profile in
                    row(profile)
                }
            } footer: {
                Text("Tap a connection to run it in this tab. Touch and hold to edit or delete.")
            }
        }
    }

    private func row(_ profile: ConnectionProfile) -> some View {
        let isCurrent = profile.id == current.id
        return Button {
            onUse(profile)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: profile.mode == .attach ? "bolt.horizontal.circle" : "terminal")
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name.isEmpty ? profile.host : profile.name)
                        .font(.body)
                    Text(subtitle(profile))
                        .font(TerminalFont.mono(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    Text(isLive ? "live here" : "this tab")
                        .font(.caption2)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { editing = profile } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { pendingDelete = profile } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func subtitle(_ p: ConnectionProfile) -> String {
        let who = p.username.isEmpty ? "" : "\(p.username)@"
        let port = p.port == 22 ? "" : ":\(p.port)"
        let host = p.host.isEmpty ? "not configured" : p.host
        return "\(who)\(host)\(port)"
    }
}

/// Add or change one saved connection. Wraps the existing form so the fields, the
/// Advanced disclosure and the mode picker all stay exactly as they were.
///
/// **Saving is an explicit act.** This used to commit on `onDisappear`, which had two
/// problems: SwiftUI does not promise to run it on every dismissal path, and there was no
/// way to back out of an edit — every keystroke was already a decision. Now Save writes and
/// Cancel discards, which is also what makes it safe to type a wrong host and change your
/// mind. Michael, 2026-08-29: *"i need to be able to edit connection credentials after
/// connection save."*
private struct ConnectionEditor: View {
    @State var profile: ConnectionProfile
    @State private var password = ""
    @State private var loaded = false
    @StateObject private var library = ConnectionLibrary.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsView(
            profile: $profile,
            password: $password,
            onSave: {
                library.update(profile)
                // Always write, even when blank — an empty field now means "forget this
                // password", which was previously impossible.
                _ = CredentialStore.save(password: password, for: profile)
                dismiss()
            },
            onCancel: { dismiss() }
        )
        .onAppear {
            // Guard the load: onAppear can run again when the sheet returns to front,
            // and a second run would overwrite what the user has typed.
            guard !loaded else { return }
            password = CredentialStore.password(for: profile) ?? ""
            loaded = true
        }
    }
}
