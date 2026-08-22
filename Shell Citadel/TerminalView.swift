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
            Text(">")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            TextField(connected ? "Say something" : "Connect first", text: $draft, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...4)
                .disabled(!connected || isBusy)
                .onSubmit(send)

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

    // MARK: - Actions

    private func connect() {
        isBusy = true
        let profile = profile
        let password = password
        Task {
            do {
                try await session.connect(to: profile.destination, password: password)
                CredentialStore.save(password: password, for: profile)
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
                    let output = try await session.run(text)
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
                for try await line in try await session.voiceLines() {
                    append(.claude, line)
                }
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
