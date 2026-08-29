//
//  DemoMode.swift
//  Shell Citadel
//
//  THE PROBLEM THIS SOLVES IS NOT A USER PROBLEM.
//
//  An App Review reviewer opens Shell Citadel, is shown a form asking for a hostname, a
//  username and a password, and has none of those. They have no Mac of their own with
//  Remote Login switched on. So they see a form that does nothing, and an app that does
//  nothing is rejected as non-functional. This is a known and ordinary way that SSH
//  clients get turned down, and it has nothing to do with whether the app is any good.
//
//  Michael, 2026-08-27: "maybe a demo mode so we (or i) dont forget."
//
//  WHY A MODE AND NOT REVIEW NOTES.  Review notes are the other answer, and they are
//  worse for one specific reason: they have to be written again, correctly, on every
//  single submission, by a man who is doing this alone and will do it on tired evenings.
//  A mode is written once and is still there in two years. His words are the whole
//  argument — "so we (or i) dont forget."
//
//  ── TWO RULES THIS FILE MUST NEVER BREAK ───────────────────────────────────────
//
//  1. IT MUST NEVER LOOK LIKE A REAL CONNECTION. Not to a reviewer, not to a curious
//     user, not to Michael glancing at his own phone. Simulating a connection and
//     letting someone believe it is real is itself a rejection reason, and it would be
//     dishonest even if it were not. The banner is always on screen and never
//     dismissible.
//
//  2. NOTHING HERE MAY TOUCH THE NETWORK. No SSHSession, no sockets, no upload. The
//     demo is a script and a text field. If this file ever imports Citadel, something
//     has gone wrong.
//

import Foundation

enum DemoMode {

    /// Always visible while the demo is running. Deliberately blunt.
    ///
    /// Michael's wording, 2026-08-27: "maybe it obviously shows 'simulated connection. . .'
    /// or similar in any connection screen?" — and his word is the better one. "Demo"
    /// describes what WE are doing; "simulated connection" describes what the reader is
    /// looking at, which is the thing they need to not be misled about.
    static let banner = "SIMULATED — not connected, nothing is being sent"

    /// Shown wherever connection state is displayed.
    ///
    /// ⚠️ IT SAYS BOTH THINGS ON PURPOSE, AND THE SECOND HALF IS THE IMPORTANT ONE.
    ///
    /// The first attempt read "Simulated connection", and Michael took it apart in one
    /// sentence, 2026-08-27: *"'simulated connection' would include connected and
    /// disconnected quite literally wouldnt it?"*
    ///
    /// He is right. That phrase is a MODE label sitting in a STATE slot — it describes
    /// what kind of session this is, in the exact place the header otherwise answers
    /// "am I connected?". And it is equally true whether the simulation is pretending to
    /// be up or pretending to be down, so it reports nothing about the only question
    /// that spot exists to answer.
    ///
    /// So: "Simulated" is the mode. "not connected" is the literal, unhedged truth about
    /// the socket — deliberately the SAME WORDS the app uses when it genuinely is not
    /// connected, because it genuinely is not.
    static let statusLabel = "Simulated · not connected"

    /// The scripted transcript, shown a line at a time so the app looks alive rather
    /// than pre-filled. Content is written to demonstrate the FEATURES a reviewer needs
    /// to see working — a command and its output, a reply arriving on its own, and the
    /// picture flow — without claiming anything untrue about what is happening.
    struct Beat {
        let source: TranscriptLine.Source
        let text: String
        let isOutput: Bool
        /// Seconds to wait before showing this line.
        let delay: Double
    }

    static let script: [Beat] = [
        .init(source: .system,
              text: "This is a demonstration. Nothing is connected and nothing is being sent. Enter your own Mac's details in Settings to use it for real.",
              isOutput: false, delay: 0.3),

        .init(source: .you, text: "uptime", isOutput: false, delay: 1.2),
        .init(source: .claude,
              text: "09:41  up 3 days, 14:22, 2 users, load averages: 1.42 1.51 1.47",
              isOutput: true, delay: 0.9),

        .init(source: .system,
              text: "Listening for replies on ~/.claude-voice/out.txt.",
              isOutput: false, delay: 0.8),

        .init(source: .you, text: "which disks are nearly full?", isOutput: false, delay: 1.6),
        .init(source: .claude,
              text: "The 1TB external is at 72 percent with 293 gigabytes free. Nothing needs attention today.",
              isOutput: false, delay: 1.4),

        .init(source: .system,
              text: "You were away — catching up on what you missed.",
              isOutput: false, delay: 1.6),
        .init(source: .claude,
              text: "The overnight job finished while your phone was locked. This line was written twenty minutes ago and was waiting for you — the app remembers how far it had read, so nothing is skipped.",
              isOutput: false, delay: 1.0),
        .init(source: .system, text: "Caught up. Anything below this is live.",
              isOutput: false, delay: 0.9),

        .init(source: .you, text: "📷 rack-label.jpg — 412 KB", isOutput: false, delay: 1.8),
        .init(source: .claude,
              text: "That is the service tag on the back of the server. I can read it: it ends 7QX4L2.",
              isOutput: false, delay: 1.3),

        .init(source: .system,
              text: "End of demonstration. Everything above was scripted. Open Settings to connect to your own machine.",
              isOutput: false, delay: 1.6),
    ]

    /// What the composer says back to anything typed during the demo. Honest, and it
    /// points at the way out.
    static func reply(to typed: String) -> String {
        "Nothing is connected, so that was not sent anywhere. Open Settings to add your own Mac and use Shell Citadel for real."
    }
}
