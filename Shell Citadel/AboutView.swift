//
//  AboutView.swift
//  Shell Citadel
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    /// Starts the demonstration in the terminal behind this sheet.
    ///
    /// ⚠️ WHY DEMO MOVED HERE, 2026-08-31. It sat in the toolbar pill beside Disconnect,
    /// which gave a control you use ONCE the same permanent prime space as the one that
    /// ends your session. Michael: "the main screen is getting cluttered… I like moving
    /// the demo to the i."
    ///
    /// It also removes a real hazard rather than only tidying: Demo REPLACES what is on
    /// screen, and it was one thumb-width from Disconnect. Two destructive-feeling
    /// controls side by side in a pill on a phone is a mis-tap waiting to happen.
    var onStartDemo: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Shell Citadel")
                        .font(.title2.weight(.semibold))
                    Text("A terminal you talk to.")
                        .foregroundStyle(.secondary)
                }

                if let onStartDemo {
                    Section {
                        Button("Run the demonstration") {
                            dismiss()
                            onStartDemo()
                        }
                    } footer: {
                        // Says what it costs, because the last version of this button
                        // destroyed the transcript and he lost a reply he was reading.
                        // It no longer does — the screen is given back when the demo
                        // ends — and saying so is what makes the button safe to press.
                        Text("Walks through the setup with nothing connected. Your conversation is put back when it finishes.")
                    }
                }

                // ⚠️ THE SPOKEN PHRASES ARE NOT SUGGESTIONS — THEY ARE THE API.
                // Siri drops any phrase that does not contain the app name, so these
                // must match `ShellCitadelShortcuts` in VoiceIntents.swift EXACTLY.
                // If a phrase is edited there, edit it here in the same commit or this
                // screen starts teaching people utterances that silently do nothing.
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        phrase("Send a message with Shell Citadel",
                               "Dictates a line and delivers it. Works with the phone locked.")
                        phrase("Catch me up with Shell Citadel",
                               "Reads back what has come in since you last listened.")
                        phrase("Run a command with Shell Citadel",
                               "Runs it and reads the answer aloud.")
                    }
                } header: {
                    Text("Hands free")
                } footer: {
                    // Says WHY it is two steps, because the alternative reads as a bug.
                    // A single "ask and wait" intent times out while a reply is still
                    // being written, and an intermittent failure gets trusted, which is
                    // worse than one that never worked.
                    Text("Sending and listening are separate on purpose. A reply can take longer than Siri will wait, so sending confirms it arrived, and catching up reads the answer whenever it is ready.")
                }

                Section("Not official") {
                    Text(Attribution.disclaimer)
                }

                Section("Built with") {
                    ForEach(Attribution.components) { component in
                        NavigationLink {
                            LicenseView(component: component)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(component.name)
                                Text("\(component.holder) · \(component.license)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// One spoken phrase and what it does. The phrase is styled as the thing you SAY,
    /// so it does not read as a heading you could paraphrase — Siri will not match a
    /// paraphrase.
    private func phrase(_ spoken: String, _ effect: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\u{201C}\(spoken)\u{201D}")
                .font(.callout.weight(.medium))
            Text(effect)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct LicenseView: View {
    let component: Attribution.Component

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Link(component.url, destination: URL(string: component.url)!)
                Text(component.text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(component.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    AboutView()
}
