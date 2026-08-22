//
//  AboutView.swift
//  Shell Citadel
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Shell Citadel")
                        .font(.title2.weight(.semibold))
                    Text("A terminal you talk to.")
                        .foregroundStyle(.secondary)
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
