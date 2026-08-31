//
//  Connection.swift
//  Shell Citadel
//
//  What the user configures, and the two ways this app can talk to a Mac.
//
//  THE TWO MODES EXIST BECAUSE THE CUSTOMER IS NOT THE AUTHOR.
//  Michael runs several Macs and a rack; he wants to attach to a session that is
//  already running. Someone who buys this has one Mac and one terminal, and asking
//  them to install tmux to answer "what's in this folder" would be absurd. So:
//
//    .direct  — run a command, read the answer. Setup is Remote Login and nothing
//               else. Output is ordinary text, so it can simply be SPOKEN — there is
//               no escape-code problem here, because there is no interactive session.
//
//    .attach  — type into a running tmux session and read a side channel. This is the
//               power path. It buys persistence across disconnects and a session
//               shared with the desktop, and it costs tmux plus some setup.
//
//  Direct is the default and the one that ships. Attach lives behind Advanced.
//
//  NO INTERNET IS REQUIRED IN EITHER MODE. There is no account, no server of ours,
//  and nothing to sign up for — the app talks to a machine the user already owns,
//  over their own network or their own VPN. That is worth protecting as a property,
//  not just a fact: nothing here should ever grow a phone-home.
//

import Foundation

enum ConnectionMode: String, Codable, CaseIterable, Sendable {
    /// Run a command, read the answer. No tmux. The default.
    case direct
    /// Type into a running tmux session, read sentences from a side channel.
    case attach

    var title: String {
        switch self {
        case .direct: "Direct"
        case .attach: "Attach to session"
        }
    }

    var explanation: String {
        switch self {
        case .direct:
            "Runs a command and reads the answer back. Enable SSH on the machine and that is the whole setup."
        case .attach:
            "Types into a session that is already running, so work survives losing the connection. Needs tmux on that machine."
        }
    }
}

/// Everything the user can set. Deliberately NOT the password — see `CredentialStore`.
struct ConnectionProfile: Codable, Equatable, Sendable, Identifiable {
    /// Stable identity, so the library can hold several and a tab can say which one it
    /// is running. Defensively decoded like everything else here: a profile saved before
    /// the library existed simply gets a fresh id rather than failing to decode and
    /// silently wiping his settings.
    var id: UUID = UUID()

    var name: String = "My Mac"

    /// A hostname, a Tailscale name, a .local name, or an IP. The app does not care
    /// which, and does not need to: a LAN address and a VPN address are the same
    /// thing to SSH, which is why remote access needs no second code path.
    var host: String = ""
    var port: Int = 22
    var username: String = ""

    var mode: ConnectionMode = .direct

    /// Where commands start. Empty means the account's home directory, which is
    /// where a fresh SSH shell lands on its own.
    ///
    /// This exists because Direct mode runs every command in a NEW shell, so `cd`
    /// would otherwise evaporate the moment the command ends — type `cd Documents`,
    /// then `ls`, and you are back home wondering why. The app tracks the directory
    /// itself and starts each command there.
    var startingDirectory: String = ""

    // MARK: Advanced — attach mode only

    /// The tmux session to type into. `tmux ls` on the Mac lists these.
    var tmuxSession: String = "claude"

    /// ⚠️ OFF BY DEFAULT, AND THAT DEFAULT IS THE WHOLE POINT.
    ///
    /// Michael, 2026-08-31 18:5x: "that the stamp gets piped to the server because the
    /// text from the sever needs to be usable to any random server, not claude in tmux."
    ///
    /// Attach mode was prefixing every line with `[HH:MM SC-iPhone]` and appending a
    /// coordinate. Harmless when the far end is Claude reading prose — CORRUPTION when it
    /// is vim, a REPL, a build, or anyone else's tmux session. Attach mode was never
    /// Claude-only; it just happened to be that here.
    ///
    /// He then asked whether the far end could add the stamp instead, and answered it
    /// himself: "app store connect doesnt have Tmux claude." A hook on his Mac is not
    /// generic — a customer has nothing reading a sidecar. So the stamp is neither a
    /// client default nor a server feature. **It is a property of THIS CONNECTION**,
    /// where something on the far end is known to read sentences.
    ///
    /// Clean text ships. He turns it on for his.
    var stampMessages: Bool = false

    /// A file on the Mac that receives plain sentences, read as the voice channel.
    /// Only meaningful in attach mode, because a redraw stream cannot be spoken.
    var voicePath: String = "~/.claude-voice/out.txt"

    // MARK: - Decoding that survives the model growing
    //
    // Swift's synthesised decoder requires EVERY key to be present, even one with a
    // default value. So adding a single property to this struct makes every stored
    // profile fail to decode — and because the call site uses `try?`, it fails
    // SILENTLY and the user's settings reset to blank. That is exactly what happened
    // when `startingDirectory` was added: Michael's saved Mac vanished.
    //
    // decodeIfPresent with a fallback per field means an old profile still loads and
    // simply picks up defaults for anything it predates. Losing a user's typed
    // settings to a code change is not an acceptable failure mode.

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "My Mac"
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        mode = try c.decodeIfPresent(ConnectionMode.self, forKey: .mode) ?? .direct
        startingDirectory = try c.decodeIfPresent(String.self, forKey: .startingDirectory) ?? ""
        tmuxSession = try c.decodeIfPresent(String.self, forKey: .tmuxSession) ?? "claude"
        voicePath = try c.decodeIfPresent(String.self, forKey: .voicePath) ?? "~/.claude-voice/out.txt"
        stampMessages = try c.decodeIfPresent(Bool.self, forKey: .stampMessages) ?? false
    }

    var isComplete: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
        && !username.trimmingCharacters(in: .whitespaces).isEmpty
        && (1...65535).contains(port)
    }

    var destination: SSHDestination {
        SSHDestination(
            host: host.trimmingCharacters(in: .whitespaces),
            port: port,
            username: username.trimmingCharacters(in: .whitespaces),
            tmuxSession: tmuxSession,
            voicePath: voicePath
        )
    }
}
