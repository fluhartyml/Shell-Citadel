//
//  TerminalView.swift
//  Shell Citadel
//
//  The face. Typed input first, on purpose: voice layered on top of an unproven
//  transport is untestable, so the typed path proves the spine and the microphone
//  bolts on afterwards.
//
//  This is a CONVERSATION VIEW WEARING TERMINAL CLOTHES, and the clothes are the
//  right choice because that is the room the work already happens in. What it shows
//  is the transcript — what you said and what came back — not the terminal's output
//  stream. Spinners and redraws never reach here.
//

import SwiftUI

struct TerminalView: View {
    @State private var lines: [TranscriptLine] = []
    @State private var draft = ""
    @State private var showingAbout = false
    @State private var showingSettings = false
    @State private var isBusy = false

    @State private var profile = ConnectionProfile()
    @State private var password = ""
    @State private var session = SSHSession()
    @State private var connected = false
    /// Shown in the composer so it is always obvious where a command will run —
    /// the one piece of state a fresh-shell-per-command design would otherwise hide.
    @State private var workingDirectory = ""

    @AppStorage("connectionProfile") private var storedProfile = Data()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                Divider()
                composer
            }
            .navigationTitle(profile.name.isEmpty ? "Shell Citadel" : profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingAbout) { AboutView() }
            .sheet(isPresented: $showingSettings, onDismiss: persistProfile) {
                SettingsView(profile: $profile, password: $password)
            }
            .task { restoreProfile() }
        }
    }

    // MARK: - Chrome

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Connection settings")
        }
        ToolbarItem(placement: .principal) {
            // The prompt is a connection state, not a `$`. A terminal that is only a
            // costume can say something useful in that spot instead.
            Label(connected ? "Connected" : "Not connected",
                  systemImage: connected ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
                .font(.caption)
                .foregroundStyle(connected ? .green : .secondary)
                .labelStyle(.titleAndIcon)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingAbout = true
            } label: {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel("About Shell Citadel")
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
                                .foregroundStyle(line.source == .system ? .secondary : .primary)
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
            Text(promptLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // A UIKit field, not a TextField: SwiftUI cannot switch off smart
            // punctuation, and a keyboard that turns two spaces into ". " or "--"
            // into an em dash corrupts commands. See CommandField.
            CommandField(text: $draft,
                         placeholder: connected ? "Say something" : "Connect first",
                         isEnabled: connected && !isBusy,
                         onSubmit: send)
                .frame(height: 30)

            if isBusy {
                ProgressView()
            } else if connected {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            } else {
                Button("Connect", action: connect)
                    .disabled(!profile.isComplete || password.isEmpty || isBusy)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    /// The last path component, so a deep path does not eat the composer.
    private var promptLabel: String {
        guard connected, !workingDirectory.isEmpty else { return ">" }
        let name = (workingDirectory as NSString).lastPathComponent
        return "\(name) >"
    }

    // MARK: - Actions

    private func connect() {
        isBusy = true
        let profile = profile
        let password = password
        Task {
            do {
                try await session.connect(to: profile.destination, password: password)
                CredentialStore.save(password: password, for: profile)
                await session.setWorkingDirectory(profile.startingDirectory)
                connected = true
                append(.system, "Connected to \(profile.host) as \(profile.username).")

                if await session.trustedOnFirstUse {
                    // Said out loud rather than passed over: the first connection to a
                    // host is the one moment this app cannot verify anything.
                    append(.system, "First time connecting to this machine — its key has been remembered. If it ever changes, the connection will be refused.")
                }
                if profile.mode == .attach { startVoiceChannel() }
            } catch {
                append(.system, error.localizedDescription)
            }
            isBusy = false
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        append(.you, text)
        isBusy = true

        Task {
            do {
                switch profile.mode {
                case .direct:
                    // The answer comes straight back and is ordinary text.
                    let output = try await session.runTrackingDirectory(text)
                    workingDirectory = await session.workingDirectory
                    if output.isEmpty {
                        append(.system, "(no output)")
                    } else {
                        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
                            append(.claude, String(line))
                        }
                    }
                case .attach:
                    // Nothing comes back here — the reply arrives on the voice channel,
                    // whenever the session gets round to answering.
                    try await session.send(text)
                }
            } catch {
                append(.system, error.localizedDescription)
            }
            isBusy = false
        }
    }

    /// Attach mode only: sentences appear as the session writes them.
    private func startVoiceChannel() {
        Task {
            do {
                let lines = try await session.voiceLines()
                // Said out loud, because this channel failed SILENTLY once: the
                // path never resolved, nothing arrived, and nothing complained.
                // A channel that is listening should say so, so that silence
                // afterwards means "nothing was written" and not "it is broken".
                append(.system, "Listening for replies on \(profile.voicePath).")
                for try await line in lines {
                    append(.claude, line)
                }
                append(.system, "Voice channel closed.")
            } catch {
                append(.system, "Voice channel stopped: \(error.localizedDescription)")
            }
        }
    }

    private func append(_ source: TranscriptLine.Source, _ text: String) {
        lines.append(.init(source, text))
    }

    // MARK: - Persistence
    //
    // The profile is not secret and lives in UserDefaults. The password never does —
    // it goes to the Keychain via CredentialStore.

    private func restoreProfile() {
        if let decoded = try? JSONDecoder().decode(ConnectionProfile.self, from: storedProfile) {
            profile = decoded
            password = CredentialStore.password(for: decoded) ?? ""
        }
        if lines.isEmpty {
            append(.system, profile.isComplete
                   ? "Ready. Connect to \(profile.host)."
                   : "No Mac set up yet — open Connection settings to add one.")
        }
    }

    private func persistProfile() {
        if let encoded = try? JSONEncoder().encode(profile) { storedProfile = encoded }
        if !password.isEmpty { CredentialStore.save(password: password, for: profile) }
    }
}

#Preview {
    TerminalView()
}
