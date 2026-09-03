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

    /// Supplied when this form is editing a SAVED connection from the library, where
    /// committing has to be a deliberate act with a way to back out. Left nil when the
    /// form edits a tab's own live profile, which is bound directly and needs only "Done".
    var onSave: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    // ⬜ `usernameLooksWrong` LIVED HERE AND IS GONE ON PURPOSE — see the Sign in section.
    //
    // Its reasoning was sound and is worth keeping: Michael's saved Mac held his macOS
    // *full* name, "Michael Fluharty", instead of his short name, and the only symptom was
    // a connection that never worked. A field that can be silently wrong deserves to say
    // so. What changed is WHERE it says it — a permanent line in the footer rather than an
    // orange alert that appears mid-typing and reads as a defect — and that the save now
    // repairs the value instead of only complaining about it.

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
                    // ⛔ THIS USED TO BE AN ORANGE ⚠️ THAT APPEARED WHEN THE NAME HELD A
                    // SPACE, AND IT READ AS A FAULT IN THE APP.
                    //
                    // Michael, 2026-09-03, from the iPhone 16e: *"The red caution looks
                    // like a bug."* He was right, and the timing made it worse — AutoFill
                    // had just filled `michael fluharty` from his Passwords vault, so the
                    // app appeared to be rejecting what it had itself put in the field one
                    // tap earlier. A triangle and a hot colour say *something is broken*,
                    // not *here is how SSH names work*.
                    //
                    // It is also redundant now: `ConnectionProfile.normalized()` strips the
                    // space at the save, and in his case that produces `michaelfluharty`,
                    // which is his real short account name — so the save does not merely
                    // make the value legal, it makes it correct. His ruling on the whole
                    // class: *"i dont think warnings, it just fails silently but when it
                    // saves to connections it normalizes and strips illegal characters."*
                    //
                    // ⚠️ BUT THE SENTENCE ITSELF IS NOT DELETED. Full-name-instead-of-short-
                    // name is the mistake that cost him this morning, and three credentials
                    // in his vault are variants of it. So the explanation moves into the
                    // footer below, in the same grey as everything else, and it is ALWAYS
                    // there rather than appearing on a keystroke — documentation cannot
                    // startle you, an alert that pops in can.
                    // → [[feedback_never_satisfy_a_request_by_deleting_the_work]]
                } header: {
                    Text("Sign in")
                } footer: {
                    // SHORTENED AT HIS WORD, 2026-09-03: *"You are too verbous"* / *"Shorten the
                    // text."* Four sentences to three, and "the other machine" became
                    // "the remote server" — his correction, and the more precise term.
                    Text("Short account name, no spaces. Password stays on this device. The remote server needs Remote Login on.")
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
                            TextField("main", text: $profile.tmuxSession)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        LabeledContent("Spoken text") {
                            TextField("~/session-output.txt", text: $profile.voicePath)
                        }
                        LabeledContent("Photo folder") {
                            // Where + -> a photograph lands on the far end, relative to
                            // its home directory. A setting rather than a constant
                            // because it creates a real directory on someone else's
                            // machine, and they should get to name it.
                            TextField("Uploads", text: $profile.uploadFolder)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    } header: {
                    // ⚠️ ATTACH MODE ONLY, because direct mode never stamped and
                    // must never start. A coordinate glued to `ls -la` is corruption.
                    // "and place" came out 2026-08-31: the stamp no longer carries a
                    // coordinate, so the old label promised something it stopped doing.
                    // A settings label that overstates is worse than a vague one.
                    Toggle("Tag messages with time and device", isOn: $profile.stampMessages)
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
                if let onCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel, action: onCancel)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let onSave {
                        Button("Save", action: onSave)
                            .disabled(!profile.isComplete)
                    } else {
                        Button("Done") { dismiss() }
                            .disabled(!profile.isComplete)
                    }
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
