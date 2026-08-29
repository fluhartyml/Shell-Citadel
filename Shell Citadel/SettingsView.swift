//
//  SettingsView.swift
//  Shell Citadel
//
//  Simple by default, Advanced behind a disclosure.
//
//  The ordering is the argument: a customer with one Mac should be able to fill in
//  three fields and connect. Everything tmux-shaped is hidden until they choose
//  Attach, because a setting you cannot use is just a question you cannot answer.
//

import SwiftUI

struct SettingsView: View {
    @Binding var profile: ConnectionProfile
    @Binding var password: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name") {
                        TextField("My Mac", text: $profile.name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Address") {
                        TextField("mac.local or 100.x.y.z", text: $profile.host)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    LabeledContent("Port") {
                        TextField("22", value: $profile.port, format: .number.grouping(.never))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                } header: {
                    Text("The machine")
                } footer: {
                    Text("A Mac, a Raspberry Pi, a server — anything running SSH. A name on your network, a Tailscale address, or an IP all work the same, so nothing changes when you leave the house.")
                }

                Section {
                    // .textContentType is what makes iOS offer AutoFill from the
                    // Passwords app. Michael's point, and a better answer than syncing
                    // anything ourselves: the credential is already saved on his
                    // devices, so the OS can fill it and this app stores nothing new.
                    LabeledContent("User name") {
                        TextField("your macOS account", text: $profile.username)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                    }
                    LabeledContent("Password") {
                        SecureField("required", text: $password)
                            .multilineTextAlignment(.trailing)
                            .textContentType(.password)
                    }
                } header: {
                    Text("Sign in")
                } footer: {
                    Text("Tap the password field to fill it from Passwords. It is kept in this device's Keychain — never in iCloud, never in a backup. On a Mac, turn on Remote Login in System Settings → General → Sharing; on a Pi, make sure the SSH service is enabled.")
                }

                Section {
                    LabeledContent("Start in") {
                        TextField("home folder", text: $profile.startingDirectory)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Starting folder")
                } footer: {
                    Text("Where commands begin. Leave it empty for your home folder. Changing folder with cd works from there, and is remembered between commands.")
                }

                Section("Mode") {
                    Picker("Mode", selection: $profile.mode) {
                        ForEach(ConnectionMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(profile.mode.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if profile.mode == .attach {
                    Section {
                        LabeledContent("Session") {
                            TextField("claude", text: $profile.tmuxSession)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        LabeledContent("Spoken text") {
                            TextField("~/.claude-voice/out.txt", text: $profile.voicePath)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } header: {
                    Text("Advanced")
                } footer: {
                        Text("Run `tmux ls` on that machine to see session names. The spoken-text file is whatever writes plain sentences there — an interactive session redraws its screen constantly, so it cannot be read aloud directly.")
                    }
                }

                AppearanceSettingsView()
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(!profile.isComplete)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var profile = ConnectionProfile()
    @Previewable @State var password = ""
    return SettingsView(profile: $profile, password: $password)
}
