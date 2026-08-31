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
    /// ⚠️ THE TRANSCRIPT HAS TO READ HIS FONT SIZE, and for a long time it did not.
    /// Michael, 2026-08-30, repeatedly and finally: "And fix the font for christ sake."
    ///
    /// The chat view was on `TerminalFont.mono(.callout)` — a Dynamic Type size, about
    /// 16pt — while his configured `fontSize` of 36 was read only by the dumb terminal.
    /// So the slider he was given did nothing to the screen he actually reads, and the
    /// app looked nothing like the Terminal window it is meant to mirror. Chasing the
    /// TYPEFACE (NF vs NFM) was the wrong hunt: the letters are identical between those
    /// two and only the icon widths differ. It was the SIZE the whole time.
    @ObservedObject private var appearance = TerminalAppearance.shared
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

    /// The real transcript, held while the demonstration borrows the screen.
    ///
    /// ⚠️ HIS BUG, 2026-08-31: *"When i tapped demo it cleared what you respondede to my
    /// last question."* Starting the demo called `lines.removeAll()` on live content and
    /// ending it cleared again, so a reply he was still reading was destroyed by a button
    /// labelled Demo. **A demonstration must not be able to lose the user's work** — the
    /// screen is borrowed, not taken.
    @State private var savedLines: [TranscriptLine] = []
    /// When his last message went out with no reply back yet. Non-nil is what puts the
    /// waiting row on screen. Michael, 2026-08-30: "i cant tell on my ipad."
    ///
    /// ⚠️ ATTACH MODE ONLY. Direct mode's answer comes straight back on the same call, so
    /// there is no gap to fill and a waiting row there would flicker for a frame and lie
    /// for the rest.
    @State private var waitingSince: Date?
    /// Bumped to ask the composer for the caret. See [[CommandField]] for why this is a
    /// counter rather than a Bool. Raised on first appearance, after a send, after a
    /// picture or a pin, and whenever a sheet closes — every point where iOS may have
    /// handed first responder to something else and not given it back.
    /// Starts at 1, not 0: 1 is the first request, and it is what makes the caret land
    /// in the field the moment the view appears. 0 is reserved to mean "never auto-focus".
    @State private var focusRequest = 1
    /// The transcript's own usable width, measured rather than assumed, so the point size
    /// can be derived from his column count the same way the dumb terminal does it.
    @State private var transcriptWidth: Double = 0
    /// Needed only by the Lines fit mode, which divides it by the row count.
    @State private var transcriptHeight: Double = 0
    /// A stable id for the waiting row so the scroller can reach it. The transcript
    /// scrolls to `lines.last`, which would leave this row below the fold — the one row
    /// he actually needs to see.
    private static let waitingRowID = "waiting-row"
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var pickedFromLibrary: PhotosPickerItem?
    /// Shown in the composer so it is always obvious where a command will run —
    /// the one piece of state a fresh-shell-per-command design would otherwise hide.
    @State private var workingDirectory = ""
    /// A connection chosen from the library while this tab is still live. Holding it here
    /// rather than applying it is what makes the challenge possible.
    @State private var pendingConnection: ConnectionProfile?
    /// A connection being filled in right now — typically the host he just typed, which
    /// needs only a password before it can go.
    @State private var editingProfile: ConnectionProfile?
    /// Who and where the FAR END says it is — not what he typed. See connect().
    @State private var remoteUser = ""
    /// The dumb terminal. Direct mode runs on this, not on the exec-per-command path.
    @StateObject private var pty = PTYSession()
    @State private var remoteHost = ""

    // ── ONE STORED PROFILE PER TAB. Michael, 2026-08-29: "we may need to add tab
    // abilities to citadel so i can have multiple terminals open" — because with a single
    // profile it was Claude OR the Pi, never both, and pointing it at one wiped the other.
    //
    // The key is injected rather than hard-coded so each tab persists its own host,
    // username and mode. The default keeps the pre-tabs key, so an existing install opens
    // its first tab already configured instead of forgetting his Mac.
    @AppStorage private var storedProfile: Data
    @Environment(\.scenePhase) private var scenePhase
    /// Which pair of tones to use. The app follows the system appearance by his ruling
    /// ("i want the background to be system light or dark mode"), so the text has to
    /// follow it too — a color picked against near-black is unreadable on white.
    @Environment(\.colorScheme) private var colorScheme

    init(profileKey: String = "connectionProfile") {
        _storedProfile = AppStorage(wrappedValue: Data(), profileKey)
    }

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
                statusStrip
                // A DUMB TERMINAL, WHEN THAT IS WHAT THIS IS. Direct mode on a live
                // connection hands the whole screen to the PTY — his shell, his prompt,
                // his output, no rows composed by us. Everything else keeps the
                // conversation view, which is right for attach mode and for the
                // not-yet-connected state where he is typing a destination.
                if connected && !isDemo && profile.mode == .direct {
                    DumbTerminalView(pty: pty)
                } else {
                    transcript
                    Divider()
                    composer
                }
            }
            .navigationTitle(profile.name.isEmpty ? "Shell Citadel" : profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingAbout, onDismiss: { focusRequest += 1 }) { AboutView() }
            .fullScreenCover(isPresented: $showingCamera, onDismiss: { focusRequest += 1 }) {
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
            .sheet(item: $editingProfile) { pending in
                PasswordFirstEditor(profile: pending) { finished, secret in
                    profile = finished
                    password = secret
                    persistProfile()
                    if finished.isComplete && !secret.isEmpty { connect() }
                }
            }
            .sheet(isPresented: $showingSettings, onDismiss: { persistProfile(); focusRequest += 1 }) {
                // THE SLIDERS ICON OPENS THE SHARED LIBRARY, NOT THIS TAB'S FORM.
                // Michael, 2026-08-29: "each connection had a button that made the chosen
                // connection live in the open or focused tab."
                ConnectionLibraryView(current: profile, isLive: connected) { chosen in
                    if connected {
                        // HIS RULING: "prompts a challenge before dropping the previous
                        // open connection." Never drop a live session silently.
                        pendingConnection = chosen
                    } else {
                        adopt(chosen)
                    }
                }
            }
            .task {
                restoreProfile()
                // One-time lift so an existing install finds his Mac already in the
                // library instead of an empty list and a setup he has to retype.
                ConnectionLibrary.shared.adoptIfEmpty(profile)
            }
            // HIS RULING, 2026-08-29: "prompts a challenge before dropping the previous
            // open connection." A live session is work in progress; swapping it out from
            // under him without asking is the same shape as every other silent failure.
            .confirmationDialog(
                pendingConnection.map { "Switch this tab to “\($0.name)”?" } ?? "",
                isPresented: Binding(get: { pendingConnection != nil },
                                     set: { if !$0 { pendingConnection = nil } }),
                titleVisibility: .visible
            ) {
                Button("Disconnect and switch", role: .destructive) {
                    if let chosen = pendingConnection { adopt(chosen) }
                    pendingConnection = nil
                }
                Button("Stay connected", role: .cancel) { pendingConnection = nil }
            } message: {
                Text("This tab is connected to \(profile.name.isEmpty ? profile.host : profile.name). Switching closes that session. Other tabs are unaffected.")
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }

                // ONE low-power fix per foregrounding, so the cached position the message
                // stamp reads is from this trip to the phone rather than the last one.
                // NOT a timer and NOT per message — `startUpdatingLocation` would hold the
                // radio open for the life of the session. See [[LocationStamp]].
                LocationStamp.shared.refresh()

                // iOS suspends a backgrounded app within seconds, so the SSH connection
                // does not survive a trip to another app or a locked screen. The tmux
                // session on the Mac does — that is the whole point of attach mode — so
                // coming back should just pick the conversation up.
                guard !connected, !isBusy,
                      profile.isComplete, !password.isEmpty else { return }
                connect()
            }
            .task {
                // Asked once, on first appearance, and never again — a permission dialog
                // that reappears is how an app gets denied permanently.
                LocationStamp.shared.requestAuthorizationIfNeeded()
                LocationStamp.shared.refresh()
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
        ToolbarItem(placement: .topBarTrailing) {
            // THE WAY IN, WITH NO CONFIGURATION — moved here from the input row on
            // 2026-08-29. A reviewer opens the app cold and must still find this without
            // a hostname, a username or a Mac of their own. The toolbar is visible on
            // launch, so it keeps doing its job; the input row is now only for typing.
            HStack(spacing: 12) {
                if isDemo {
                    Button("End", action: endDemo)
                } else {
                    if profile.isComplete && !connected {
                        Button("Connect", action: connect)
                            .disabled(password.isEmpty || isBusy)
                    }
                    // ITS OPPOSITE, IN THE SAME PLACE. Michael, 2026-08-30, from the iPad:
                    // "theres no disconnect button on the ipad please put one next to the
                    // connect button."
                    //
                    // He was right that there was nothing: Connect renders only while
                    // DISCONNECTED, so once the session was up that corner of the toolbar
                    // was empty and the only way out was to kill the app. A connection you
                    // can start and cannot stop is a one-way door.
                    //
                    // ⚠️ THIS DISCONNECTS THE PHONE, NOT THE WORK. The tmux session on the
                    // Mac keeps running — that is the whole point of attach mode — so this
                    // is hanging up, not stopping anything. Nothing is lost and reconnecting
                    // resumes where the reply channel left off. See [[VoiceMark]].
                    if connected {
                        Button("Disconnect", action: disconnect)
                            .disabled(isBusy)
                            .tint(.red)
                    }
                    Button("Demo", action: startDemo)
                }
            }
            .font(.callout)
        }
        // ⚠️ THE STATUS IS NO LONGER IN THE TOOLBAR. Michael, 2026-08-30 08:13:
        // "maybe the connected statis that is missing on the iPhone" — he was right, the
        // principal slot was being squeezed out entirely by Disconnect and Demo on a
        // phone-width bar, so the one indicator that says whether the app is alive was
        // invisible on the device he carries. It lives in `statusStrip` now, below the
        // bar, where nothing competes for the width.
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
                                .font(transcriptFont)
                                .foregroundStyle(.secondary)
                            Text(line.text)
                                .textSelection(.enabled)
                                // TWO TONES, ONE COLOUR. His lines darker, Claude's
                                // lighter, both derived from the terminal color he set
                                // — see TerminalAppearance.mineColor / theirsColor.
                                // `.system` stays neutral gray on purpose: app notices
                                // are neither of them speaking.
                                .foregroundStyle(colorFor(line.source))
                                // ALL ONE FACE. Michael, 2026-08-29, holding the app up
                                // beside his Mac terminal: "the font is different." He is
                                // right — mixing a proportional face into a terminal
                                // transcript is the tell that it is a chat window wearing
                                // terminal clothes. A terminal is monospaced throughout,
                                // including its own notices.
                                .font(transcriptFont)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(line.id)
                    }

                    // HIS ANSWER TO "IS IT LOCKED UP?", 2026-08-30 06:39. It sits at the
                    // bottom of the conversation, below his own last line, which is where
                    // he is already looking after pressing send. See [[WaitingIndicator]]
                    // for why it shows a clock instead of claiming Claude is typing.
                    // The waiting row USED to live here, at the bottom of the
                    // transcript, and that is precisely why he could not rely on it: it
                    // scrolled out of view under his own message. It is in `statusStrip`
                    // now, which never scrolls. Do not put it back.
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                // Measured on the CONTENT, inside the horizontal padding, so the number
                // is the width a line of text really has rather than the screen's.
                .background(
                    GeometryReader { geo in
                        Color.clear.onChange(of: geo.size.width, initial: true) { _, w in
                            transcriptWidth = w
                            appearance.measuredWidth = w
                        }
                    }
                )
            }
            // ⚠️ MEASURED ON THE SCROLLVIEW, NOT ON ITS CONTENT. The reader inside the
            // stack above sees the CONTENT height, which grows with the conversation and
            // is not what "how many lines fit on screen" means. The Lines fit mode needs
            // the VIEWPORT, so it is measured out here.
            .background(
                GeometryReader { geo in
                    Color.clear.onChange(of: geo.size.height, initial: true) { _, h in
                        transcriptHeight = h
                        appearance.measuredHeight = h
                    }
                }
            )
            // A HARD top edge, not the default soft one. Michael, 2026-08-23, from a
            // screenshot: his own line was sitting behind the translucent bar and the
            // settings button, half readable. The soft glass edge is right for content
            // you glance at — it hints that there is more above. This transcript is the
            // RECORD he goes back to and re-reads, and a line he cannot read is a line he
            // has lost. `.hard` gives the bar a real edge so nothing bleeds through it.
            // (`scrollEdgeEffectStyle` is iOS 26+; the app's floor is 27, so no guard.)
            .scrollEdgeEffectStyle(.hard, for: .top)
            .onChange(of: lines.count) {
                if waitingSince != nil {
                    withAnimation { proxy.scrollTo(Self.waitingRowID, anchor: .bottom) }
                } else if let last = lines.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            // NOT `.onChange(of: waitingSince)` any more — see the row's own `onAppear`
            // above for why that could never work.
        }
    }

    /// HIS DESIGN, 2026-08-30 08:13, and it is better than the row it replaces:
    /// "How anout relocatimg the animation to small text under where the settings slider
    ///  and connecdisconnecy is maybe the connected statis that is missing on the iPhone
    ///  is alternates between connected and waiting connected is a green light and waiting
    ///  for message is yellow"
    ///
    /// Two problems, one answer. The waiting indicator was living at the bottom of the
    /// transcript, where it scrolled out of view under his own message — the whole reason
    /// he reported it four times as inconsistent. And the connection status was being
    /// squeezed out of the toolbar entirely on a phone. Putting the status here, in a
    /// fixed strip that never scrolls, fixes both: it is always on screen, and it has room
    /// to say more than one word.
    ///
    /// THE LIGHT AND THE WORD MEAN DIFFERENT THINGS and that is preserved from the old
    /// toolbar item: "Connected" is what the app BELIEVES, the light is what has been
    /// MEASURED in the last ten seconds. They disagree exactly when it matters — a socket
    /// killed by a lock screen leaves the word saying Connected while the light goes red.
    /// See [[LinkLight]]. Waiting is layered ON TOP of that, never instead of it: a yellow
    /// dot means "your message is away and nothing has come back yet", which is only
    /// meaningful while connected.
    private var statusStrip: some View {
        HStack(spacing: 6) {
            if isDemo {
                // A THIRD STATE, deliberately not green and not red. Green would be a lie
                // and red reads as a fault. Orange says "this is not real" without
                // suggesting something is broken.
                Circle().fill(.orange).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.primary.opacity(0.25), lineWidth: 0.5))
                Text(DemoMode.statusLabel)
                    .foregroundStyle(.orange)
            } else if let since = waitingSince {
                // HIS COLOUR, HIS MEANING: "waiting for message is yellow".
                Circle().fill(.yellow).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.primary.opacity(0.25), lineWidth: 0.5))
                WaitingIndicator(since: since)
            } else {
                LinkLightView(light: link)
                Text(connected ? "Connected" : "Not connected")
                    .foregroundStyle(connected ? .green : .secondary)
            }
            Spacer(minLength: 0)
        }
        // ⚠️ MESLO, NOT THE SYSTEM FACE. Michael, 2026-08-30 09:09: "the font is not
        // nerdy." I shipped this strip on `.font(.caption)` — the system font — which put
        // "Connected" and the waiting clock in a different typeface from every other line
        // on screen.
        //
        // The rule was already written down, in the transcript, from the last time he
        // caught it: "ALL ONE FACE. Michael, 2026-08-29: 'the font is different.' He is
        // right — mixing a proportional face into a terminal transcript is the tell that
        // it is a chat window wearing terminal clothes." A status strip is not an
        // exception to that; it is the most visible line in the app.
        .font(TerminalFont.mono(.caption))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
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
                // THE DELIBERATE HALF OF THE LOCATION FEATURE. Michael, 2026-08-28 07:29:
                // "i want a map pin snapshot in the plus to drop a location pin".
                //
                // Precision is asked for HERE and nowhere else, because he asked for it by
                // tapping. Every other message runs on the coarse cached fix. See
                // [[LocationStamp]] for why that split is his design and not a shortcut.
                Divider()
                Button {
                    dropPin()
                } label: {
                    Label("Drop a Pin", systemImage: "mappin.and.ellipse")
                }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
            }
            .disabled(!connected || isBusy)
            .accessibilityLabel("Send a picture or a location")

            // THE PROMPT IS NOT WELCOME IN THIS ROW ON A PHONE.
            //
            // Michael, 2026-08-29 21:40, with a photograph: "It says michael and i bairly
            // have room to type." The label was rendering a full shell prompt —
            // `michaelfluharty@Michaels-MacBook-Air:~ $`, about forty monospace characters —
            // in the same HStack as the text field, so his sentence was clipped to
            // "eeds work" before he had finished typing it.
            //
            // It is wrong twice over in ATTACH mode: he is talking to Claude through tmux,
            // not to a shell, so a shell prompt is misleading AND it is eating the width.
            // The prompt he asked for this morning was for the DIRECT terminal, where the
            // remote machine draws its own prompt inside the screen — that one is real and
            // is untouched by this.
            //
            // So: nothing at all when connected. A bare ">" when disconnected, because
            // there the row IS the destination line and one character earns its place.
            if !connected {
                Text(">")
                    .font(TerminalFont.mono(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // A UIKit field, not a TextField: SwiftUI cannot switch off smart
            // punctuation, and a keyboard that turns two spaces into ". " or "--"
            // into an em dash corrupts commands. See CommandField.
            CommandField(text: $draft,
                         placeholder: isDemo ? "Simulated — not connected"
                                    : (connected
                                       ? (profile.mode == .attach ? "Say something" : "Type a command")
                                       : "ssh user@host"),
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
                         // STRICT WHENEVER NOT CONNECTED. Michael typed
                         // `fluhartyml@pihole.local` and iOS handed it back as
                         // `Fluhartyml@pihole.local`; SSH usernames are case-sensitive, so
                         // that fails auth with the right password. While disconnected he
                         // is typing a DESTINATION, which is shell-shaped input no matter
                         // what mode the profile happens to carry.
                         strict: !connected || profile.mode == .direct,
                         // HE TYPES ON A HARDWARE KEYBOARD AND HAD BEEN LOSING WHOLE
                         // PARAGRAPHS TO A FIELD THAT NEVER TOOK THE CARET.
                         focusRequest: focusRequest,
                         onSubmit: send)
                .frame(maxWidth: .infinity)
                .frame(height: 30)

            if isBusy {
                ProgressView()
            } else {
                // THE INPUT ROW IS THE SEND ARROW AND NOTHING ELSE. Michael, 2026-08-29:
                // "the connect demo is not good im a dumb terminal" — Connect and Demo were
                // occupying the place his text goes, in a mode whose whole promise is that
                // you type a destination and press send. They now live in the toolbar,
                // where Demo is still findable cold by a reviewer with no Mac.
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }

        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        // ⚠️ ROOM FOR SOMETHING THAT IS NOT OURS TO MOVE.
        //
        // Michael, 2026-08-30 08:48, from the iPad: "The a is over the (^) send button too."
        //
        // With a hardware keyboard attached, iPadOS floats its own control at the bottom
        // right — collapsed it is a small [A], expanded it opens into the predictive-text
        // strip with the dictation microphone. Collapsed, it parks exactly on top of the
        // send arrow. It is a system overlay: the app cannot move it, hide it, or know
        // where it is.
        //
        // His workaround was to keep the strip permanently open. That works and it costs
        // him a band of screen forever, and it only works while he remembers. Reserving
        // the corner costs nothing and he never thinks about it again.
        //
        // 44pt is Apple's own minimum touch target, which is the right size for the space
        // a floating control needs.
        .padding(.bottom, 44)
        // Lives on the composer, not in the menu — the composer is still on screen when
        // the menu goes away, so the sheet has somewhere to be presented from.
        .photosPicker(isPresented: $showingLibrary,
                      selection: $pickedFromLibrary,
                      matching: .images)
    }

    /// A real shell prompt: who you are, where you are connected, and where you are
    /// standing. Michael, 2026-08-29: "it should show the current connection and current
    /// path at that prompt just like on a terminal."
    ///
    /// The path is abbreviated to its last component, and the home directory shows as `~`,
    /// because a full path on a phone eats the whole composer — which is the same reason
    /// every real shell does exactly this.
    /// Kept for the connection header and any regular-width surface that wants it.
    /// **Deliberately no longer rendered in the composer row** — see the comment there.
    private var promptLabel: String {
        guard connected else { return ">" }
        let who = remoteUser.isEmpty ? profile.username : remoteUser
        let where_ = remoteHost.isEmpty ? profile.host : remoteHost
        let path: String
        if workingDirectory.isEmpty {
            path = "~"
        } else if workingDirectory == "/Users/\(who)"
                    || workingDirectory == "/home/\(who)" {
            path = "~"
        } else {
            path = (workingDirectory as NSString).lastPathComponent
        }
        if who.isEmpty || where_.isEmpty { return "\(path) >" }
        return "\(who)@\(where_):\(path) $"
    }

    // MARK: - Actions

    /// Hang up. Deliberately the plain opposite of `connect()` and nothing more.
    ///
    /// ⚠️ IT DOES NOT ASK, AND THAT IS THE POINT. A confirmation dialog would be right
    /// for something destructive; this destroys nothing. The tmux session on the Mac
    /// carries on, the reply channel remembers its byte offset, and Connect brings it all
    /// back. Making him tap twice to hang up would be treating a reversible act as a
    /// dangerous one.
    ///
    /// The PTY is stopped first: in direct mode it holds a channel on the same
    /// authenticated client, and tearing the client down underneath it leaves a reader
    /// blocked on a socket nobody is going to write to — the same wedge shape that lost
    /// two of his messages on 2026-08-29.
    private func disconnect() {
        isBusy = true
        Task {
            pty.stop()
            await session.close()
            connected = false
            link.markDown()
            remoteUser = ""
            remoteHost = ""
            workingDirectory = ""
            append(.system, "Disconnected. Your session on the Mac is still running — tap Connect to come back to it.")
            isBusy = false
        }
    }

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

                // A CONNECTION THAT WORKED IS WORTH KEEPING. Michael, 2026-08-29: "if i
                // successfully make a connection it should auto save to the connections
                // list." Saving only on success is the point — an untested host typed
                // from memory would otherwise clutter the library with things that do not
                // work. Proof first, then persistence.
                let library = ConnectionLibrary.shared
                if !library.connections.contains(where: {
                    $0.host.caseInsensitiveCompare(profile.host) == .orderedSame
                    && $0.username == profile.username
                    && $0.port == profile.port
                }) {
                    var saved = profile
                    if saved.name.trimmingCharacters(in: .whitespaces).isEmpty
                        || saved.name == "My Mac" {
                        saved.name = profile.host
                    }
                    library.add(saved)
                    append(.system, "Saved “\(saved.name)” to your connections.")
                }

                if await session.trustedOnFirstUse {
                    // Said out loud rather than passed over: the first connection to a
                    // host is the one moment this app cannot verify anything.
                    append(.system, "First time connecting to this machine — its key has been remembered. If it ever changes, the connection will be refused.")
                }
                // SHOW WHAT A FRESH TERMINAL SHOWS. Michael, 2026-08-29, holding up a
                // new Terminal window beside the app: "that shows a new terminal window
                // that should show in the shell citadel."
                //
                // An SSH exec channel gets no message-of-the-day, because that is printed
                // by an interactive LOGIN shell and this is not one. So ask for it
                // explicitly rather than inventing a greeting — a fabricated "Last login"
                // line would be a small lie about a real machine, and the whole point is
                // that this is his actual Pi talking.
                // ASK THE MACHINE WHO AND WHERE IT IS. Michael, 2026-08-29: "i want it
                // to echo the current connection, i dont want to show my interpretation."
                //
                // The prompt used to be assembled from the profile — from what HE TYPED.
                // That is my rendering of his input, not the host's own answer, and the
                // two can differ: he typed `pihole.local`, the machine calls itself
                // `pihole`. So the prompt now comes from whoami/hostname on the far end.
                if let who = try? await session.run("whoami"),
                   let where_ = try? await session.run("hostname -s 2>/dev/null || hostname") {
                    remoteUser = who.trimmingCharacters(in: .whitespacesAndNewlines)
                    remoteHost = where_.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                // The machine's own message of the day, printed verbatim. An SSH exec
                // channel gets none by itself, because that belongs to an interactive
                // login shell — so ask for it rather than inventing a greeting.
                if let motd = try? await session.run("cat /etc/motd 2>/dev/null"),
                   !motd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    append(.system, motd.trimmingCharacters(in: .newlines), isOutput: true)
                }

                if profile.mode == .attach {
                    startVoiceChannel()
                } else if let live = session.authenticatedClient {
                    // DIRECT MODE IS NOW A REAL TERMINAL. Same authenticated connection,
                    // so he is not asked for the password twice.
                    pty.start(client: live,
                              cols: TerminalAppearance.shared.cols,
                              rows: TerminalAppearance.shared.rows)
                }
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
        // Straight back to him. Sending is the moment he is most likely to keep typing,
        // and it is also where `isBusy` flips and the row rebuilds around the field.
        focusRequest += 1
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
                    //
                    // THE SILENT STAMP RIDES ALONG HERE, and only here. Michael, 2026-08-28:
                    // "an undisclosed gps location stamp imbeded in every message sent from
                    // human to claude in citadel". It is appended to what GOES UP, never to
                    // what is drawn in his bubble — `append(.you, text)` above is untouched,
                    // which is what "undisclosed" meant.
                    //
                    // Direct mode deliberately gets NOTHING: those are shell commands run on
                    // a machine, not sentences said to Claude, and a coordinate glued to
                    // `ls -la` would be corruption rather than metadata.
                    //
                    // Empty string when there is no fix — a message must never be held up
                    // or altered because location was unavailable.
                    try await session.send(text + LocationStamp.shared.messageSuffix())
                    // The clock starts when the message is AWAY, not when he pressed
                    // send — the upload is not part of the wait he is asking about.
                    waitingSince = Date()
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
                waitingSince = nil
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

    /// A · THE PIN DROP. A fresh precise fix, a rendered map, and the picture goes to
    /// BOTH places he asked for. Michael, 2026-08-29 22:43:
    /// "The snapshot goes in the thread and photo album" — the thread for Claude, the
    /// album for him.
    ///
    /// ORDER MATTERS AND IT IS DELIBERATE: the upload to the Mac happens FIRST, and the
    /// photo library save is allowed to fail without taking the pin drop with it. If he
    /// declines Photos access, or the save fails, the coordinate and the map still
    /// reached Claude — which is the half that does work. The reverse order would let a
    /// permission dialog swallow the message.
    private func dropPin() {
        guard connected, !isBusy else { return }
        isBusy = true
        Task {
            do {
                let fix = try await LocationStamp.shared.preciseFix()
                let image = try await LocationStamp.snapshot(at: fix.coordinate)
                guard let data = PhotoSend.prepare(image) else {
                    throw LocationStamp.Failure.snapshotFailed
                }

                let name = LocationStamp.filename()
                let path = try await session.upload(data, filename: name)

                // PRECISE here, unlike the message stamp. His ruling, 2026-08-28 07:44:
                // "Digests and threads have top secret clearance so they can see precise
                // accuracy if it happens on the pin drop." Rounding this one would throw
                // away the exact thing he tapped the button to get.
                let c = fix.coordinate
                let coords = String(format: "%.6f, %.6f", c.latitude, c.longitude)

                // The receipt on his side, before it is sent — the same rule as a
                // photograph. A pin that vanishes into a conversation is one he cannot
                // later prove he dropped.
                append(.you, "📍 \(coords) — \(data.count / 1024) KB")
                // ⚠️ NO NEWLINE. Same trap as the message stamp: `send` pastes into a tmux
                // buffer and then presses Enter, so a newline in here is a keystroke that
                // submits early. His first real pin arrived as
                // "28.940900, -95.297888/Users/michaelfluharty/..." with the coordinate
                // welded to the path. A separator has to be visible AND newline-free.
                try await session.send("📍 I dropped a pin: \(coords) — \(path)")

                do {
                    try await LocationStamp.saveToPhotoLibrary(image)
                } catch {
                    // Said, not swallowed. He asked for the album copy specifically, so
                    // silently not making one would be a lie of omission.
                    append(.system, "Sent, but not saved to Photos: \(error.localizedDescription)")
                }
            } catch {
                append(.system, (error as? LocalizedError)?.errorDescription
                       ?? Diagnosis.sentence(for: error, while: .sending))
            }
            isBusy = false
        }
    }

    // MARK: - Demonstration

    private func startDemo() {
        isDemo = true
        // Keep what was on screen. The demo still starts clean — it has to be readable —
        // but clean is achieved by setting the real transcript ASIDE, not by deleting it.
        savedLines = lines
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
        // ACCEPT A BARE user@host TOO. Michael, 2026-08-29: "what if i type
        // fluhartyml@pihole in the text line?" — he would, and demanding the `ssh` prefix
        // to accept something that is unambiguously a destination is pedantry, not rigour.
        var parts = line.split(separator: " ").map(String.init)
        if parts.first == "ssh" {
            parts.removeFirst()
        } else if !(parts.first ?? "").contains("@") {
            append(.system, "Not connected. Type `user@host` — or `ssh user@host` — to connect, or use the sliders to pick a saved connection.")
            return
        }

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
            // OPEN AN EDITOR FOR THE HOST HE JUST TYPED — not the library.
            // Michael, 2026-08-29: "It didnt give me a chance to type it." Sending him to
            // an empty Connections list when he had just named a machine was a dead end:
            // the one field he needed was nowhere on screen.
            append(.system, "Password needed for \(user)@\(host).")
            editingProfile = next
        }
    }

    private func endDemo() {
        isDemo = false
        // Give the screen back exactly as it was. Anything that arrived during the demo
        // was scripted and belongs to nobody, so it is the saved transcript that wins.
        lines = savedLines
        savedLines = []
    }

    /// ⚠️ THE BACKGROUND IS DELIBERATELY NOT SET HERE. Michael, 2026-08-30 09:05:
    /// "i want the background to be system light or dark mode". Leaving it unset is what
    /// makes that true — the transcript sits on the system background and follows the
    /// device. Painting it would break exactly what he asked for.
    /// His size, his face — and by HIS control, which is the column count and not the
    /// slider. Michael, 2026-08-30 11:40: "I use the column vs lines because its easier to
    /// type then use the slider."
    ///
    /// ⚠️ THE TWO SCREENS USED TO DISAGREE. The dumb terminal has always honored
    /// `fitToColumns` — on, the column count is authoritative and the point size is
    /// derived from the available width; off, the slider wins. The transcript ignored both
    /// and sat at a flat `fontSize`, so with fitting ON the terminal sized itself to 85
    /// columns while the conversation did something else entirely. One setting, two
    /// answers.
    ///
    /// Now it is the same rule in both places, from the same helper, so 85 × 20 means the
    /// same thing wherever he is looking.
    ///
    /// Floor of 11pt so a slider dragged to nothing cannot make the conversation
    /// unreadable; no ceiling, because 36 is his and it is deliberate.
    private var transcriptFont: Font {
        .custom(TerminalFont.regular, size: max(11, transcriptSize))
    }

    private var transcriptSize: Double {
        switch appearance.fitMode {
        case .columns:
            guard transcriptWidth > 0 else { return appearance.fontSize }
            return TerminalAppearance.sizeToFit(columns: appearance.cols, width: transcriptWidth)
        case .lines:
            guard transcriptHeight > 0 else { return appearance.fontSize }
            return TerminalAppearance.sizeToFit(rows: appearance.rows, height: transcriptHeight)
        case .manual:
            return appearance.fontSize
        }
    }

    private func colorFor(_ source: TranscriptLine.Source) -> Color {
        let dark = colorScheme == .dark
        switch source {
        case .you:    return TerminalAppearance.shared.mineColor(dark: dark)
        case .claude: return TerminalAppearance.shared.theirsColor(dark: dark)
        case .system: return .secondary
        }
    }

    private func append(_ source: TranscriptLine.Source, _ text: String, isOutput: Bool = false) {
        lines.append(.init(source, text, isOutput: isOutput))

        // THE WAIT ENDS HERE, FOR EVERY PATH AT ONCE. Clearing it at each call site
        // instead would mean remembering to do it in the voice channel, in the error
        // handler, on disconnect — and the one that got forgotten would leave a clock
        // ticking forever under a conversation that had already moved on.
        //
        // A `.system` line counts too: "Disconnected", or a diagnosis sentence, is an
        // answer about why nothing is coming, so leaving the row spinning underneath it
        // would be the app contradicting itself.
        if source != .you { waitingSince = nil }
    }

    // MARK: - Persistence
    //
    // The profile is not secret and lives in UserDefaults. The password never does —
    // it goes to the Keychain via CredentialStore.

    /// Make a library connection live in THIS tab. Ends the current session first —
    /// deliberately explicit rather than relying on the old session being garbage
    /// collected, because a half-open SSH channel is exactly the kind of thing that looks
    /// fine until it does not.
    private func adopt(_ chosen: ConnectionProfile) {
        if connected {
            Task { await session.close() }
            connected = false
            link.stop()
            pty.stop()
            remoteUser = ""
            remoteHost = ""
        }
        profile = chosen
        password = CredentialStore.password(for: chosen) ?? ""
        workingDirectory = ""
        persistProfile()
        // "a button that made the chosen connection LIVE in the open or focused tab" —
        // live means connected, so go, when there is a password to go with.
        if profile.isComplete && !password.isEmpty {
            connect()
        } else {
            append(.system, profile.isComplete
                   ? "Ready. \(profile.name) needs a password — open the sliders."
                   : "Dumb terminal mode — please use sliders to configure first.")
        }
    }

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
