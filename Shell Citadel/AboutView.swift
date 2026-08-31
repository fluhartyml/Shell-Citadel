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
