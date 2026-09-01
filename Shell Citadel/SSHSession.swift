//
//  SSHSession.swift
//  Shell Citadel
//
//  The transport. Two channels over one connection, which is the whole design:
//
//    SCREEN  ← nothing yet. The raw terminal is a later, optional view.
//    VOICE   ← `tail -f` on a file that only ever contains sentences.
//    INPUT   → `tmux send-keys` into the running session.
//
//  WHY send-keys AND tail INSTEAD OF A TERMINAL: Claude Code inside tmux emits a
//  terminal stream — escape codes, spinners, redraws. Speaking that aloud is
//  gibberish, and parsing it back into sentences is a losing game. So the app never
//  reads the terminal. It types into the session, and it reads a side channel that
//  Claude writes deliberately. No emulator, no ANSI handling, no cursor tracking.
//
//  A consequence worth stating: this client does not see command output. It sees what
//  Claude chose to say. That is the point, not a gap.
//

import Foundation
import UIKit
import Citadel
import NIOCore

/// Where to connect, and to which tmux session.
struct SSHDestination: Sendable, Equatable {
    var host: String
    var port: Int = 22
    var username: String
    /// The tmux session name the Mac launcher creates. `Claude.command` uses "claude".
    var tmuxSession: String = "claude"
    /// The file Claude appends spoken sentences to, read as the voice channel.
    var voicePath: String = "~/.claude-voice/out.txt"
}

enum SSHSessionError: Error, LocalizedError {
    case notConnected
    case tmuxNotFound
    case noSuchSession(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Not connected."
        case .tmuxNotFound:
            "tmux is not installed on the Mac, and Attach mode needs it. Direct mode does not \u{2014} switch modes in Connection settings, or install tmux on the Mac."
        case .noSuchSession(let name):
            "No tmux session named \(name) is running on the Mac. Run tmux ls there to see which sessions exist."
        }
    }
}

actor SSHSession {
    private var client: SSHClient?
    private var destination: SSHDestination?
    private var trust: HostKeyTrust?

    var isConnected: Bool { client != nil }

    /// Drops the session without trying to talk to a far end that is already gone.
    /// Called when a send fails: at that point the connection is not coming back on
    /// its own, and pretending otherwise is what left Michael with a Connected header
    /// and no way to reconnect short of relaunching.
    func markDisconnected() {
        client = nil
        trust = nil
    }

    /// True when this host was seen for the first time on the current connection,
    /// so the UI can say so instead of letting a blind first trust pass silently.
    var trustedOnFirstUse: Bool { trust?.didTrustOnFirstUse ?? false }

    /// The live client, so a dumb terminal can open a PTY on the SAME authenticated
    /// connection rather than asking him for the password a second time.
    var authenticatedClient: SSHClient? { client }

    // MARK: - Connect

    func connect(to destination: SSHDestination, password: String) async throws {
        await close()

        let trust = HostKeyTrust(host: destination.host)
        let client = try await SSHClient.connect(
            host: destination.host,
            port: destination.port,
            authenticationMethod: .passwordBased(
                username: destination.username,
                password: password
            ),
            hostKeyValidator: .custom(trust),
            reconnect: .never
        )

        self.client = client
        self.destination = destination
        self.trust = trust
    }

    func close() async {
        if let client { try? await client.close() }
        client = nil
        destination = nil
        trust = nil
    }

    // MARK: - Direct mode  —  run a command, read the answer

    /// Runs one command and returns its output as text.
    ///
    /// This is the mode a customer with one Mac uses, and the reason it needs no tmux
    /// and no side channel: a discrete command produces ordinary text. `ls`, `git
    /// status`, `df -h` come back readable — and therefore SPEAKABLE — because nothing
    /// interactive is redrawing a screen. The escape-code problem belongs to attach
    /// mode alone.
    ///
    /// stderr is merged in on purpose: a customer who runs a command that fails wants
    /// to hear WHY, and splitting the streams would leave them with silence.
    /// Where the next command will run. Direct mode opens a fresh shell every time,
    /// so this is tracked here rather than by the far end.
    private(set) var workingDirectory = ""

    func setWorkingDirectory(_ path: String) {
        workingDirectory = path.trimmingCharacters(in: .whitespaces)
    }

    /// Runs `pwd` after the command so a `cd` inside it is picked up. Without this,
    /// `cd somewhere` appears to work and then silently does nothing.
    func runTrackingDirectory(_ command: String) async throws -> String {
        let prefix = workingDirectory.isEmpty ? "" : "cd \(Self.shellQuoted(workingDirectory)) && "
        // The marker separates the command's own output from the pwd probe, so a
        // command that happens to print a path cannot be mistaken for the new cwd.
        let marker = "__SHELL_CITADEL_PWD__"
        let output = try await run("\(prefix)\(command); printf '\\n%s\\n' \(Self.shellQuoted(marker)); pwd")

        guard let range = output.range(of: marker, options: .backwards) else { return output }
        let body = String(output[output.startIndex..<range.lowerBound])
        let pwd = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !pwd.isEmpty { workingDirectory = pwd }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func run(_ command: String) async throws -> String {
        guard let client else { throw SSHSessionError.notConnected }

        // Collected by hand rather than via executeCommand(), because that throws on a
        // non-zero exit and DISCARDS the output — leaving the user with
        // "CommandFailed error 1" when the Mac actually said "command not found".
        // A failed command's message is the most useful thing on the screen; losing it
        // to an exit code is the opposite of helping.
        var collected = ""
        let stream = try await client.executeCommandStream(command)
        do {
            for try await chunk in stream {
                switch chunk {
                case .stdout(let buffer), .stderr(let buffer):
                    var reader = buffer
                    collected += reader.readString(length: reader.readableBytes) ?? ""
                }
            }
        } catch {
            // The command ran and failed. Show what it said; only fall back to the
            // raw error when the shell gave us nothing to show.
            let text = collected.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { throw error }
            return text
        }
        return collected.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Attach mode  —  tmux send-keys

    /// Delivers a line into the running tmux session. The MacBook attached to the same
    /// session watches it appear.
    ///
    /// ⚠️ USES A PASTE BUFFER, NOT `send-keys -l`. This looks like a detail and is not.
    ///
    /// `send-keys -l` types the text LITERALLY — one character at a time, at roughly
    /// three characters a second over SSH. On 2026-08-25 Michael sent a sentence from the
    /// porch, watched nothing arrive for minutes, and reported: "My terminals looked like
    /// they got stuck. Hopefully tmux kept everything going in the background." Nothing
    /// was stuck. It was still typing. He then could not recall what he had written,
    /// and the half-delivered words had to be read back out of the pane to recover them.
    ///
    /// `set-buffer` + `paste-buffer` hands the whole string over in ONE operation —
    /// measured at 0.065s for 783 characters against roughly four minutes typed. It also
    /// removes a second failure: every typed character is a chance for the pty buffer to
    /// fill and block the writer mid-sentence.
    ///
    /// The buffer name is deliberately odd so it can never clobber a buffer Michael is
    /// using himself, and `-d` deletes it the moment it has been pasted. The Enter that
    /// submits stays a separate, deliberate key.
    /// `stamped` defaults to FALSE so a plain terminal stays a plain terminal. See
    /// `ConnectionProfile.stampMessages` for why the default is the important part.
    func send(_ text: String, stamped useStamp: Bool = false) async throws {
        guard let client, let destination else { throw SSHSessionError.notConnected }
        _ = client

        let tmux = try await tmuxExecutable()
        let session = Self.shellQuoted(destination.tmuxSession)

        // Check the session exists first, so a typo in the session name produces a
        // sentence instead of an exit code.
        let check = try? await run("\(tmux) has-session -t \(session) && echo OK")
        guard check?.contains("OK") == true else {
            throw SSHSessionError.noSuchSession(destination.tmuxSession)
        }

        // THE TIMESTAMP IS FOR CLAUDE, NOT FOR MICHAEL. His words, from outside the
        // house: "I don't need to see the time stamps you do." A long turn means several
        // of his messages arrive together, and without a sent-time Claude cannot tell
        // which are current and which were overtaken minutes ago. Showing them in the
        // app would have solved the wrong half of it.
        // The SOURCE tag. Michael, 2026-08-23: "give shell citadel the SC tag please."
        // Both apps send through the same tmux session, so without this Claude cannot
        // tell which one he is typing in. Lighthouse sends LH from the phone and Mac
        // from the desk; this is the third.
        let stamped = useStamp ? "[\(Self.sentStamp()) \(Self.sourceTag)] \(text)" : text
        let body = Self.shellQuoted(stamped)
        let buffer = "shell-citadel-msg"
        // ⚠️ `-p` IS LOAD-BEARING: IT IS BRACKETED PASTE, AND WITHOUT IT THE FRONT OF A
        // LONG MESSAGE IS LOST.
        //
        // Michael, 2026-08-30 09:21, sent a 455-character line. It arrived on the Mac
        // missing its first EIGHTEEN characters — the whole "[09:21 SC-iPad] " tag plus
        // two letters — while all 17 repeats at the end survived. Losing the tag then
        // defeated the echo guard in capture-prompt.py, so the Mac read it as
        // desk-typed and echoed his own words back at him: one bug, two symptoms.
        //
        // MEASURED, NOT GUESSED. The same command was run against a throwaway tmux
        // session whose only job was `cat > file`: 455 bytes in, 456 out (the newline),
        // front intact. So tmux delivers it perfectly and the loss is in the RECEIVING
        // program.
        //
        // Cause: without `-p`, `paste-buffer` replays the buffer as ordinary keystrokes.
        // A TUI that has bracketed paste enabled is waiting for the ESC[200~ marker and
        // handles a raw burst differently — the leading characters arrive before its
        // input handling settles and are dropped. `-p` wraps the payload in the
        // bracketed-paste markers, so the far end takes it as ONE block instead of a
        // race of individual keys.
        //
        // → the same failure family as the two messages that died in wedged tmux
        //   processes on 2026-08-29: delivery that reports success and loses content.
        // ⚠️ THE PAUSE BEFORE Enter IS LOAD-BEARING — it is the other edge of `-p`.
        //
        // Michael, 2026-08-31 19:4x: "i typed that previous message on my iphone and it
        // appeared in the chat line on tmux claude so i pressed enter to send it." Then,
        // two messages later, "that time it didnt go to the tmux chat bar" — so it is
        // INTERMITTENT, which is the signature of a race rather than a broken command.
        //
        // `paste-buffer` returns once tmux has handed the bytes to the pane, NOT once the
        // receiving program has finished settling the bracketed-paste block. Fire Enter
        // in that gap and it lands INSIDE the block, where a TUI reads it as a literal
        // newline in the pasted text instead of a submit. His message then sits in the
        // composer waiting for a keystroke from him — delivery that reports success and
        // quietly makes him do the last step by hand.
        //
        // ⚠️ DO NOT "FIX" THIS BY DROPPING `-p`. That is the trade, and the other side of
        // it is worse: without `-p` his 455-character message arrived missing its first
        // eighteen characters (see the note above). Losing the front of a message is
        // silent; a stranded Enter is at least visible on screen. Keep both — the wrapper
        // AND the daylight after it.
        //
        // 0.3s is imperceptible per message and generous next to the settle it covers.
        _ = try await run("""
            \(tmux) set-buffer -b \(buffer) -- \(body) \
              && \(tmux) paste-buffer -d -p -b \(buffer) -t \(session) \
              && sleep 0.3 \
              && \(tmux) send-keys -t \(session) Enter
            """)
    }

    // MARK: - Finding tmux

    private var cachedTmuxPath: String?

    /// FOUND THE HARD WAY, on a real phone: an SSH *exec* channel is not a login
    /// shell, so it gets a minimal PATH \u{2014} on this Mac
    /// `/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.` \u{2014} which does NOT include
    /// Homebrew's `/opt/homebrew/bin`. Plain `tmux` is therefore "command not found",
    /// and Citadel reports that as `CommandFailed error 1`, which tells nobody anything.
    ///
    /// Resolved once per connection and cached. If tmux genuinely is not installed,
    /// that is a sentence the user can act on, not an error code.
    // MARK: - Sending a picture

    /// Where photographs land on the Mac. NOT inside the apartment repo — a photograph
    /// of a medical document or of the inside of his house must not become a commit by
    /// accident. Michael's own classification scheme treats anything untagged as
    /// TopSecret, and this folder inherits that.
    static let inboxFolderName = "Claude Inbox"

    /// Push bytes to the Mac over the connection that is ALREADY OPEN.
    ///
    /// WHY NOT A SECOND APP.  The obvious design is a Mac companion that receives files
    /// and hands them on. It has no job. The thing on the other end is Claude reading the
    /// Mac's filesystem directly, so the entire requirement is "get the bytes onto the
    /// disk and say where they are". A companion app would add a second target to sign, a
    /// process that has to be running, and a new way for a photograph to silently vanish.
    ///
    /// WHY THE HOME DIRECTORY IS ASKED FOR RATHER THAN ASSUMED.  SFTP does not expand
    /// `~` — it is a protocol, not a shell, and a path beginning with a tilde is simply a
    /// directory called "~". The exec channel DOES expand it, so the shell is asked once
    /// for the real path and everything after that is absolute.
    ///
    /// - Returns: the absolute path on the Mac, ready to be quoted into a message.
    func upload(_ data: Data, filename: String) async throws -> String {
        guard let client else { throw SSHSessionError.notConnected }

        let home = try await run("printf %s \"$HOME\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !home.isEmpty else { throw SSHSessionError.notConnected }

        let directory = "\(home)/\(Self.inboxFolderName)"
        // `mkdir -p` over the exec channel rather than SFTP's createDirectory, because
        // mkdir is idempotent and createDirectory throws when the folder already exists —
        // which it will, every time after the first.
        _ = try await run("mkdir -p \(Self.shellQuoted(directory))")

        let remotePath = "\(directory)/\(filename)"

        let sftp = try await client.openSFTP()
        do {
            var buffer = ByteBufferAllocator().buffer(capacity: data.count)
            buffer.writeBytes(data)
            try await sftp.withFile(filePath: remotePath,
                                    flags: [.create, .write, .truncate]) { file in
                try await file.write(buffer)
            }
            try await sftp.close()
        } catch {
            // Close even on failure. An SFTP channel left open survives as long as the
            // connection does, and the connection is meant to last all day.
            try? await sftp.close()
            throw error
        }

        return remotePath
    }

    private func tmuxExecutable() async throws -> String {
        if let cachedTmuxPath { return cachedTmuxPath }

        // Explicit locations first (these work in the minimal PATH), then a login
        // shell as a fallback for anyone with tmux somewhere unusual.
        let probe = "for p in /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux /bin/tmux; do [ -x \"$p\" ] && echo \"$p\" && exit 0; done; command -v tmux 2>/dev/null || true"
        let found = (try? await run(probe))?
            .split(separator: "\n").first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""

        guard !found.isEmpty else { throw SSHSessionError.tmuxNotFound }
        let quoted = Self.shellQuoted(found)
        cachedTmuxPath = quoted
        return quoted
    }

    // MARK: - Voice  ←  tail -f

    /// How many bytes the voice file currently holds, so the caller can tell how much of
    /// what arrives is CATCH-UP and how much is live. Returns 0 if it cannot be read —
    /// a missing file is not an error here, it is simply nothing said yet.
    func voiceFileSize() async throws -> Int {
        guard destination != nil else { throw SSHSessionError.notConnected }
        let path = Self.remotePath(destination!.voicePath)
        // run() rather than executeCommand(): the latter throws on a non-zero exit and
        // throws the output away with it, which is how "command not found" became
        // "CommandFailed error 1" the first time round.
        let text = try await run("mkdir -p \"$(dirname \(path))\" && touch \(path) && wc -c < \(path)")
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Sentences Claude has chosen to say, one line at a time, as they are written.
    ///
    /// THE PASSIVE QUEUE (Michael, 2026-08-23). `startingAtByte` resumes from where this
    /// phone last read, so locking the screen or walking out of range costs nothing —
    /// the Mac's file kept everything, and the reconnect fills in the gap in order.
    ///
    /// `startingAtByte == 0` keeps the ORIGINAL behavior, `tail -n 0 -F`: start at the
    /// end. That is right for a first-ever connection, where replaying months of an old
    /// session at someone would be worse than showing them nothing.
    ///
    /// `-F` (rather than `-f`) is kept either way: it follows the file across rotation
    /// and recreation instead of holding a dead handle.
    ///
    /// See [[VoiceMark]] for why the offset is bytes and not lines.
    func voiceLines(startingAtByte startOffset: Int = 0) async throws -> AsyncThrowingStream<VoiceChunk, Error> {
        guard let client, let destination else { throw SSHSessionError.notConnected }

        let path = Self.remotePath(destination.voicePath)
        // `tail -c +N` is 1-based: +1 is the whole file, so N is (bytes read) + 1.
        let follow = startOffset > 0 ? "tail -c +\(startOffset + 1) -F \(path)" : "tail -n 0 -F \(path)"
        let raw = try await client.executeCommandStream(
            "mkdir -p \"$(dirname \(path))\" && touch \(path) && \(follow)",
            inShell: true
        )

        return AsyncThrowingStream { continuation in
            Task {
                // stdout arrives in arbitrary chunks, not neatly per line, so partial
                // lines are held back until their newline shows up. Speaking half a
                // sentence would be worse than speaking it a moment later.
                var pending = ""
                // The mark only ever advances over COMPLETE lines. Whatever is still in
                // `pending` when a connection dies is left uncounted on purpose, so that
                // sentence is re-read whole next time rather than resumed mid-word.
                var consumed = startOffset
                do {
                    for try await chunk in raw {
                        guard case .stdout(let outBuffer) = chunk else { continue }
                        var reader = outBuffer
                        guard let text = reader.readString(length: reader.readableBytes) else { continue }
                        pending += text

                        while let newline = pending.firstIndex(of: "\n") {
                            let line = String(pending[pending.startIndex..<newline])
                            pending = String(pending[pending.index(after: newline)...])
                            // Counted whether or not it is shown: blank separator lines
                            // occupy bytes too, and skipping them in the count would
                            // walk the mark backwards a little on every message.
                            consumed += line.utf8.count + 1
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty {
                                continuation.yield(VoiceChunk(text: trimmed, offsetAfter: consumed))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Local time, 24-hour, for the sent-stamp.
    /// `SC-iPad` / `SC-iPhone`. Michael, 2026-08-30: "Can sc destinguish an iphone or an
    /// ipad? For the timestamp?"
    ///
    /// He runs the same app on both and they are not interchangeable to him: the iPhone
    /// is what is in his hand away from the desk, the iPad is what he reads long replies
    /// on. Knowing which one a sentence came from is knowing how much screen he has and
    /// how easily he can type — and this morning is the case in point, when a reply
    /// sized for the iPad was unreadable on the phone.
    ///
    /// Computed once: the idiom cannot change for the life of the process, and reading it
    /// per message would be a main-actor hop on every send.
    static let sourceTag: String = {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:   return "SC-iPad"
        case .phone: return "SC-iPhone"
        // Mac Catalyst, Vision, TV, CarPlay, anything Apple adds later. Falls back to the
        // plain tag rather than inventing a name for a device this app is not shipped on.
        default:     return "SC"
        }
    }()

    static func sentStamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - Quoting

    /// Single-quote for /bin/sh. Everything inside single quotes is literal, so the
    /// only case needing care is a single quote itself, which is closed, escaped and
    /// reopened. Building these commands by interpolation without this is how a
    /// spoken sentence containing a quote or a semicolon becomes a shell command.
    /// Quotes a path while still letting a LEADING `~/` mean the remote home folder.
    ///
    /// FOUND ON HARDWARE: shellQuoted() wraps everything in single quotes, and inside
    /// single quotes `~` is a literal character. So the default voice path became a
    /// file inside a directory actually NAMED "~", which does not exist — the app
    /// tailed nothing, forever, without complaining. Michael could send to the Mac and
    /// never saw a reply come back.
    ///
    /// `"$HOME"` is used rather than expanding here, because only the far end knows
    /// whose home it is.
    static func remotePath(_ value: String) -> String {
        if value == "~" { return "\"$HOME\"" }
        if value.hasPrefix("~/") {
            let rest = String(value.dropFirst(2))
            return "\"$HOME\"/" + shellQuoted(rest)
        }
        return shellQuoted(value)
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
