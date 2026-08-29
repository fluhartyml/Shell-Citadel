//
//  PasswordFirstEditor.swift
//  Shell Citadel
//
//  Michael typed `ssh fluhartyml@pihole.local`, the app said "password needed — opening
//  settings", and then showed him an EMPTY Connections list. His report: "It didnt give
//  me a chance to type it."
//
//  He had already supplied the host, the user and the port by typing them. The only thing
//  missing was the secret, so that is the only thing this asks for. Everything else is
//  shown as confirmation, not as work.
//
import SwiftUI

struct PasswordFirstEditor: View {
    @State var profile: ConnectionProfile
    let onConnect: (ConnectionProfile, String) -> Void

    @State private var password = ""
    @FocusState private var passwordFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Address") {
                        Text(profile.host).font(TerminalFont.mono(.body))
                    }
                    LabeledContent("User") {
                        Text(profile.username).font(TerminalFont.mono(.body))
                    }
                    if profile.port != 22 {
                        LabeledContent("Port") { Text("\(profile.port)") }
                    }
                } header: {
                    Text("Connecting to")
                } footer: {
                    Text("Taken from what you typed. Change it in Connections afterwards if it needs a different name or mode.")
                }

                Section {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($passwordFocused)
                        .onSubmit(go)
                } header: {
                    Text("Password")
                } footer: {
                    Text("Kept in this device's Keychain — never in iCloud, never in a backup. Tap the field to fill it from Passwords.")
                }
            }
            .navigationTitle(profile.host)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect", action: go)
                        .disabled(password.isEmpty)
                }
            }
            // The password field is the only thing to do here, so put the cursor in it.
            .onAppear { passwordFocused = true }
        }
    }

    private func go() {
        guard !password.isEmpty else { return }
        onConnect(profile, password)
        dismiss()
    }
}
