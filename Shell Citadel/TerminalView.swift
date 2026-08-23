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
    @Environment(\.scenePhase) private var scenePhase

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
            .onChange(of: scenePhase) { _, phase in
                // iOS suspends a backgrounded app within seconds, so the SSH connection
                // does not survive a trip to another app or a locked screen. The tmux
                // session on the Mac does — that is the whole point of attach mode — so
                // coming back should just pick the conversation up.
                guard phase == .active, !connected, !isBusy,
                      profile.isComplete, !password.isEmpty else { return }
                connect()
            }
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
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(line.text)
                                .textSelection(.enabled)
                                .foregroundStyle(line.source == .system ? .secondary : .primary)
                                // Output keeps its columns; prose gets to be readable.
                                .font(line.isOutput
                                      ? .system(.callout, design: .monospaced)
                                      : .system(.callout))
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(line.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            // A HARD top edge, not the default soft one. Michael, 2026-08-23, from a
            // screenshot: his own line was sitting behind the translucent bar and the
            // settings button, half readable. The soft glass edge is right for content
            // you glance at — it hints that there is more above. This transcript is the
            // RECORD he goes back to and re-reads, and a line he cannot read is a line he
            // has lost. `.hard` gives the bar a real edge so nothing bleeds through it.
            // (`scrollEdgeEffectStyle` is iOS 26+; the app's floor is 27, so no guard.)
            .scrollEdgeEffectStyle(.hard, for: .top)
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
                         // NOT disabled while busy: disabling a UITextField makes iOS
                         // resign first responder, which drops the keyboard after every
                         // single command and never brings it back. Michael hit this the
                         // moment he tried to hold a conversation from the phone. The
                         // send is guarded instead.
                         isEnabled: connected,
                         strict: profile.mode == .direct,
                         onSubmit: send)
                .frame(maxWidth: .infinity)
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
                append(.system, Diagnosis.sentence(for: error, while: .connecting))
            }
            isBusy = false
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        draft = ""
        append(.you, text, isOutput: profile.mode == .direct)
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
                            append(.claude, String(line), isOutput: true)
                        }
                    }
                case .attach:
                    // Nothing comes back here — the reply arrives on the voice channel,
                    // whenever the session gets round to answering.
                    try await session.send(text)
                }
            } catch {
                append(.system, Diagnosis.sentence(for: error, while: .sending))
                // The connection is gone. Say so, and put the Connect button back.
                // Michael went out of wifi range: the error appeared, the header still
                // read "Connected", the composer still accepted text, and the only way
                // back was to quit and relaunch the app.
                await session.markDisconnected()
                connected = false
                append(.system, "Disconnected. Tap Connect to try again.")
            }
            isBusy = false
        }
    }

    /// Attach mode only: sentences appear as the session writes them — and, since
    /// 2026-08-23, the ones written while this phone was away arrive first.
    ///
    /// THE PASSIVE QUEUE. Michael locks his phone by habit before pocketing it, which
    /// backgrounds the app and kills the connection. Nothing on the Mac stops — that is
    /// what tmux is for — but the channel used to resume at the END of the file, so
    /// every sentence written during the lock was skipped, permanently and silently.
    /// The file kept all of it the whole time. See [[VoiceMark]].
    private func startVoiceChannel() {
        Task {
            let destination = profile.destination
            do {
                var mark = VoiceMark.offset(for: destination)
                let size = (try? await session.voiceFileSize()) ?? 0

                // The file got SMALLER than where this phone had read to, so it was
                // emptied, rotated or replaced. The old offset now points into the
                // middle of different content; keeping it would silently skip real
                // lines, which is the exact failure this whole change exists to remove.
                if mark > size {
                    VoiceMark.clear(for: destination)
                    mark = 0
                    append(.system, "The replies file was replaced on the Mac — starting fresh.")
                }

                let missed = max(0, size - mark)
                let lines = try await session.voiceLines(startingAtByte: mark)

                // Said out loud, because this channel failed SILENTLY once: the
                // path never resolved, nothing arrived, and nothing complained.
                // A channel that is listening should say so, so that silence
                // afterwards means "nothing was written" and not "it is broken".
                append(.system, "Listening for replies on \(profile.voicePath).")
                if mark > 0 && missed > 0 {
                    // Without this the catch-up reads as Claude suddenly talking to
                    // itself. Saying where the boundary is costs one line.
                    append(.system, "You were away — catching up on what you missed.")
                }

                var caughtUp = !(mark > 0 && missed > 0)
                for try await chunk in lines {
                    append(.claude, chunk.text)
                    VoiceMark.set(chunk.offsetAfter, for: destination)
                    if !caughtUp && chunk.offsetAfter >= size {
                        caughtUp = true
                        append(.system, "Caught up. Anything below this is live.")
                    }
                }
                append(.system, "Voice channel closed.")
            } catch {
                append(.system, Diagnosis.sentence(for: error, while: .listening))
                await session.markDisconnected()
                connected = false
            }
        }
    }

    private func append(_ source: TranscriptLine.Source, _ text: String, isOutput: Bool = false) {
        lines.append(.init(source, text, isOutput: isOutput))
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
