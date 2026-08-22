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

    /// True when this host was seen for the first time on the current connection,
    /// so the UI can say so instead of letting a blind first trust pass silently.
    var trustedOnFirstUse: Bool { trust?.didTrustOnFirstUse ?? false }

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

    /// Types a line into the running tmux session, exactly as if it had been typed at
    /// the keyboard. The MacBook attached to the same session watches it appear.
    ///
    /// `-l` sends the text literally, so tmux does not interpret words like "Enter"
    /// inside it; the Enter that submits is a separate, deliberate key.
    func send(_ text: String) async throws {
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

        let body = Self.shellQuoted(text)
        _ = try await run("\(tmux) send-keys -t \(session) -l \(body) && \(tmux) send-keys -t \(session) Enter")
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

    /// Sentences Claude has chosen to say, one line at a time, as they are written.
    ///
    /// `tail -n 0 -F` starts at the end (no replay of an old session) and keeps
    /// following the file even if it is rotated or recreated.
    func voiceLines() async throws -> AsyncThrowingStream<String, Error> {
        guard let client, let destination else { throw SSHSessionError.notConnected }

        let path = Self.shellQuoted(destination.voicePath)
        let raw = try await client.executeCommandStream(
            "mkdir -p \"$(dirname \(path))\" && touch \(path) && tail -n 0 -F \(path)",
            inShell: true
        )

        return AsyncThrowingStream { continuation in
            Task {
                // stdout arrives in arbitrary chunks, not neatly per line, so partial
                // lines are held back until their newline shows up. Speaking half a
                // sentence would be worse than speaking it a moment later.
                var pending = ""
                do {
                    for try await chunk in raw {
                        guard case .stdout(let outBuffer) = chunk else { continue }
                        var reader = outBuffer
                        guard let text = reader.readString(length: reader.readableBytes) else { continue }
                        pending += text

                        while let newline = pending.firstIndex(of: "\n") {
                            let line = String(pending[pending.startIndex..<newline])
                            pending = String(pending[pending.index(after: newline)...])
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { continuation.yield(trimmed) }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Quoting

    /// Single-quote for /bin/sh. Everything inside single quotes is literal, so the
    /// only case needing care is a single quote itself, which is closed, escaped and
    /// reopened. Building these commands by interpolation without this is how a
    /// spoken sentence containing a quote or a semicolon becomes a shell command.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
