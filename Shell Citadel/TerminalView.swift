///
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

import PhotosUI
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
    /// The MEASURED half of the connection state. `connected` is a belief; this is a
    /// claim about the last ten seconds. See [[LinkLight]].
    @State private var link = LinkLight()
    /// Running the scripted demonstration instead of a connection. See [[DemoMode]] —
    /// this exists for App Review, who have no Mac of their own to connect to.
    @State private var isDemo = false
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var pickedFromLibrary: PhotosPickerItem?
    /// Shown in the composer so it is always obvious where a command will run —
    /// the one piece of state a fresh-shell-per-command design would otherwise hide.
    @State private var workingDirectory = ""

    @AppStorage("connectionProfile") private var storedProfile = Data()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isDemo {
                    // ALWAYS ON SCREEN AND NOT DISMISSIBLE. A demonstration that can be
                    // mistaken for a live connection is dishonest, and it is also its
                    // own rejection reason.
                    Text(DemoMode.banner)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(.orange.opacity(0.9))
                        .foregroundStyle(.black)
                }
                transcript
                Divider()
                composer
            }
            .navigationTitle(profile.name.isEmpty ? "Shell Citadel" : profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingAbout) { AboutView() }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCapture { image in sendPicture(image) }
                    .ignoresSafeArea()
            }
            .onChange(of: pickedFromLibrary) { _, item in
                guard let item else { return }
                Task {
                    // loadTransferable rather than a URL: the bytes come straight into
                    // memory and no copy is made anywhere on the phone.
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        sendPicture(image)
                    }
                    pickedFromLibrary = nil
                }
            }
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
            //
            // THE LIGHT SITS BESIDE THE WORD, AND THEY MEAN DIFFERENT THINGS.
            // "Connected" is what the app BELIEVES — the handshake succeeded and nothing
            // has thrown since. The light is what has been MEASURED in the last ten
            // seconds. They disagree exactly when it matters: a socket killed by a lock
            // screen or a wifi handoff leaves the word saying Connected while the light
            // goes red. See [[LinkLight]].
            HStack(spacing: 6) {
                if isDemo {
                    // A THIRD STATE, deliberately not green and not red. Green would be a
                    // lie and red reads as a fault. Orange says "this is not real" without
                    // suggesting something is broken.
                    Circle().fill(.orange).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.primary.opacity(0.25), lineWidth: 0.5))
                    Label(DemoMode.statusLabel, systemImage: "theatermasks")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                } else {
                    LinkLightView(light: link)
                    Label(connected ? "Connected" : "Not connected",
                          systemImage: connected ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
                        .font(.caption)
                        .foregroundStyle(connected ? .green : .secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
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
                                .font(TerminalFont.mono(.callout))
                                .foregroundStyle(.secondary)
                            Text(line.text)
                                .textSelection(.enabled)
                                .foregroundStyle(line.source == .system ? .secondary : .primary)
                                // Output keeps its columns; prose gets to be readable.
                                .font(line.isOutput
                                      ? TerminalFont.mono(.callout)
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
            // THE PLUS, where iMessage puts it. He asked for it by that comparison, and
            // the comparison is the specification: it is the button you press when the
            // thing you want to say is not typeable. In a rack room that is most things —
            // a service tag, a cable that goes somewhere unexpected, an error on a screen
            // that cannot be copied.
            // ⚠️ THE PICKER IS NOT INSIDE THIS MENU, AND THAT IS DELIBERATE.
            //
            // It was, at first, and Michael found it dead on the device the moment it was
            // installed: "The plus isn't wired?"
            //
            // A `PhotosPicker` nested in a `Menu` has to present its own sheet, and the
            // menu tears down its presentation context as it dismisses — so the row is
            // tappable, looks correct, and does nothing. It fails silently, which is the
            // worst way for a button to fail.
            //
            // The supported shape is the `.photosPicker(isPresented:)` MODIFIER on a view
            // that stays alive, with the menu only flipping a flag. See the modifier on
            // the composer below.
            Menu {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
                Button {
                    showingLibrary = true
                } label: {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
            }
            .disabled(!connected || isBusy)
            .accessibilityLabel("Send a picture")

            Text(promptLabel)
                .font(TerminalFont.mono(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // A UIKit field, not a TextField: SwiftUI cannot switch off smart
            // punctuation, and a keyboard that turns two spaces into ". " or "--"
            // into an em dash corrupts commands. See CommandField.
            CommandField(text: $draft,
                         placeholder: isDemo ? "Simulated — not connected"
                                    : (connected ? "Say something" : "ssh user@host"),
                         // NOT disabled while busy: disabling a UITextField makes iOS
                         // resign first responder, which drops the keyboard after every
                         // single command and never brings it back. Michael hit this the
                         // moment he tried to hold a conversation from the phone. The
                         // send is guarded instead.
                         // DUMB TERMINAL MODE. Michael, 2026-08-29: he opened the app cold,
                         // tried to type `ssh fluhartyml@pihole.local` the way he would in
                         // any terminal, and could not — the field was dead and the button
                         // said Connect/Demo. Enabling it always is half the fix; `send`
                         // routes an ssh line to `connectFromSSHLine` so the arrow does
                         // something real instead of merely appearing.
                         isEnabled: true,
                         strict: profile.mode == .direct,
                         onSubmit: send)
                .frame(maxWidth: .infinity)
                .frame(height: 30)

            if isBusy {
                ProgressView()
            } else if connected || isDemo || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // The arrow appears as soon as there is something to send, connected or
                // not — in dumb-terminal mode what it sends is the ssh line itself.
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            } else if isDemo {
                Button("End", action: endDemo)
            } else {
                Button("Connect", action: connect)
                    .disabled(!profile.isComplete || password.isEmpty || isBusy)
                // THE WAY IN, WITH NO CONFIGURATION. A reviewer opens the app cold and
                // must be able to find this without a hostname, a username or a Mac.
                // If it is ever hidden behind Settings, it has stopped doing its job.
                Button("Demo", action: startDemo)
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        // Lives on the composer, not in the menu — the composer is still on screen when
        // the menu goes away, so the sheet has somewhere to be presented from.
        .photosPicker(isPresented: $showingLibrary,
                      selection: $pickedFromLibrary,
                      matching: .images)
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
                link.start(pinging: session)
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
        // Guarded FIRST, before anything reads `session`. The demo must never touch the
        // network — see the second rule at the top of [[DemoMode]].
        if isDemo {
            let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !typed.isEmpty else { return }
            draft = ""
            append(.you, typed)
            append(.system, DemoMode.reply(to: typed))
            return
        }

        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }

        // Not connected yet: the only thing that can be meant is "take me to a host".
        // Accept the exact line he would type in Terminal.
        if !connected && !isDemo {
            draft = ""
            append(.you, text, isOutput: true)
            connectFromSSHLine(text)
            return
        }

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
                link.markDown()
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
            var announced = false
            var backoff = 1

            // ⚠️ THE STREAM ENDING IS NOT THE SAME AS THE CONNECTION ENDING, AND THIS
            // LOOP EXISTS BECAUSE THIS APP USED TO CONFUSE THEM.
            //
            // Michael, 2026-08-27, from the phone: "the last message i sent from my
            // iphone says > this one seems to handle lost connections and lock screens
            // better i have no messages from you." He had sent five messages over ten
            // minutes. Every one of them ARRIVED. Every reply was written to out.txt on
            // the Mac. He saw none of them.
            //
            // The cause: sending and receiving are different channels. `send()` writes
            // into the tmux session and kept working perfectly. The replies arrive on a
            // separate long-lived stream, and when that stream ended — cleanly, no
            // error thrown — the old code appended "Voice channel closed." and STOPPED.
            // `connected` stayed true. The composer stayed enabled. He carried on
            // typing into an app that had quietly stopped listening.
            //
            // A one-way conversation that looks two-way is the worst failure this app
            // can have, because nothing on screen is wrong. So: while the connection is
            // up, the reply channel restarts itself. The byte offset in [[VoiceMark]]
            // means a restart loses nothing — it resumes exactly where it stopped.
            while !Task.isCancelled && connected {
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
                    backoff = 1     // a stream that opened is a working stream

                    // Said out loud, because this channel failed SILENTLY once: the
                    // path never resolved, nothing arrived, and nothing complained.
                    // A channel that is listening should say so, so that silence
                    // afterwards means "nothing was written" and not "it is broken".
                    //
                    // ANNOUNCED ONCE, not on every restart — a line that repeats every
                    // time the stream blinks is noise, and noise in the transcript is
                    // what makes a real warning easy to miss.
                    if !announced {
                        append(.system, "Listening for replies on \(profile.voicePath).")
                        announced = true
                    }
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

                    // Fell out of the stream with the connection still up. Silently
                    // reopen — he does not need to be told the plumbing hiccuped, he
                    // needs the next sentence to arrive.
                    guard connected, !Task.isCancelled else { break }
                    try? await Task.sleep(for: .seconds(backoff))
                    backoff = min(backoff * 2, 15)
                } catch {
                    append(.system, Diagnosis.sentence(for: error, while: .listening))
                    await session.markDisconnected()
                    connected = false
                    link.markDown()
                    break
                }
            }
        }
    }

    /// Compress, push over the connection that is already open, then say where it
    /// landed. The path IS the message — Claude reads the Mac's disk directly, so
    /// nothing needs to carry the bytes onward. See `SSHSession.upload`.
    private func sendPicture(_ image: UIImage) {
        guard connected, !isBusy else { return }
        guard let data = PhotoSend.prepare(image) else {
            append(.system, "That picture could not be prepared for sending.")
            return
        }
        let name = PhotoSend.filename()
        isBusy = true
        Task {
            do {
                let path = try await session.upload(data, filename: name)
                // Said in the transcript BEFORE it is sent to Claude, so there is a
                // record on his side of what he sent and how big it was. A photograph
                // that vanishes into a conversation with no receipt is one he cannot
                // later prove he sent.
                append(.you, "📷 \(name) — \(data.count / 1024) KB")
                try await session.send("📷 I sent you a picture: \(path)")
            } catch {
                append(.system, Diagnosis.sentence(for: error, while: .listening))
            }
            isBusy = false
        }
    }

    // MARK: - Demonstration

    private func startDemo() {
        isDemo = true
        lines.removeAll()
        Task {
            for beat in DemoMode.script {
                try? await Task.sleep(for: .seconds(beat.delay))
                guard isDemo else { return }     // he pressed End part way through
                append(beat.source, beat.text, isOutput: beat.isOutput)
            }
        }
    }

    /// Parse `ssh [user@]host [-p port]` and connect. Anything else is explained rather
    /// than swallowed — a dumb terminal that silently ignores what you typed is worse than
    /// one that will not let you type.
    ///
    /// The password is deliberately NOT invented here. If one is already in the Keychain
    /// for this host it is used; otherwise the Connection settings sheet opens with the
    /// host and username already filled, so the only thing left to enter is the secret.
    private func connectFromSSHLine(_ line: String) {
        var parts = line.split(separator: " ").map(String.init)
        guard parts.first == "ssh" else {
            append(.system, "Not connected. Type `ssh user@host` to connect, or use the sliders to pick a saved server.")
            return
        }
        parts.removeFirst()

        var port = 22
        if let i = parts.firstIndex(of: "-p"), i + 1 < parts.count, let p = Int(parts[i + 1]) {
            port = p
            parts.removeSubrange(i...(i + 1))
        }

        guard let target = parts.first, !target.isEmpty else {
            append(.system, "Missing a host. Try `ssh user@host`.")
            return
        }

        var user = profile.username
        var host = target
        if let at = target.firstIndex(of: "@") {
            user = String(target[target.startIndex..<at])
            host = String(target[target.index(after: at)...])
        }
        guard !host.isEmpty else {
            append(.system, "Missing a host. Try `ssh user@host`.")
            return
        }

        var next = profile
        next.name = host
        next.host = host
        next.username = user
        next.port = port
        next.mode = .direct          // a typed ssh line is always a plain shell
        profile = next

        if let saved = CredentialStore.password(for: next), !saved.isEmpty {
            password = saved
            connect()
        } else {
            append(.system, "Password needed for \(user)@\(host) — opening settings.")
            showingSettings = true
        }
    }

    private func endDemo() {
        isDemo = false
        lines.removeAll()
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
                   : "Dumb terminal mode — please use sliders to configure first.")
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
