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
            "Runs a command and reads the answer back. Turn on Remote Login on the Mac and that is the whole setup."
        case .attach:
            "Types into a session that is already running, so work survives losing the connection. Needs tmux on the Mac."
        }
    }
}

/// Everything the user can set. Deliberately NOT the password — see `CredentialStore`.
struct ConnectionProfile: Codable, Equatable, Sendable {
    var name: String = "My Mac"

    /// A hostname, a Tailscale name, a .local name, or an IP. The app does not care
    /// which, and does not need to: a LAN address and a VPN address are the same
    /// thing to SSH, which is why remote access needs no second code path.
    var host: String = ""
    var port: Int = 22
    var username: String = ""

    var mode: ConnectionMode = .direct

    // MARK: Advanced — attach mode only

    /// The tmux session to type into. `tmux ls` on the Mac lists these.
    var tmuxSession: String = "claude"

    /// A file on the Mac that receives plain sentences, read as the voice channel.
    /// Only meaningful in attach mode, because a redraw stream cannot be spoken.
    var voicePath: String = "~/.claude-voice/out.txt"

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
