//
//  TerminalView.swift
//  Shell Citadel
//
//  The face. Typed input first, on purpose: voice layered on top of an unproven
//  transport is untestable, so the typed path proves the spine and the microphone
//  bolts on afterwards.
//

import SwiftUI

struct TerminalView: View {
    @State private var lines: [TranscriptLine] = [
        .init(.system, "Shell Citadel — not connected.")
    ]
    @State private var draft = ""
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                Divider()
                composer
            }
            .navigationTitle("Shell Citadel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About Shell Citadel")
                }
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(line.prompt)
                                .foregroundStyle(.secondary)
                            Text(line.text)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .font(.system(.body, design: .monospaced))
                        .id(line.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .onChange(of: lines.count) {
                if let last = lines.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Text(">")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            TextField("Say something", text: $draft, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...4)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lines.append(.init(.you, text))
        draft = ""
        // The transport lands here next: send-keys into the tmux session, and the
        // reply arrives on the voice channel. Nothing is wired yet, and this view
        // says so rather than pretending.
        lines.append(.init(.system, "Not connected — no transport wired yet."))
    }
}

#Preview {
    TerminalView()
}
