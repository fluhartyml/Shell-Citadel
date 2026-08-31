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

    /// ⭐ THE SCRIPT TEACHES THE SETUP. Michael's change, 2026-08-30:
    /// *"can we use it to teac the user how to open tmux and run claude?"*
    ///
    /// It is a better demo than the generic one it replaced, because it does both jobs
    /// at once. The reviewer still sees every feature working — a command and its
    /// output, a reply arriving on its own, the catch-up, the picture flow — and a real
    /// user watching the same thirty seconds learns the exact words they have to type.
    /// The old script demonstrated the app to someone who already knew what to do with
    /// it; nobody is in that position on first launch.
    ///
    /// ── WHY `screen` AND NOT `tmux` ────────────────────────────────────────────────
    ///
    /// The first version of this script taught tmux, and Michael caught it in one
    /// question: *"should we assume they have tmux installed?"*
    ///
    /// We cannot. macOS does not ship tmux — measured on his own Mac, it lives at
    /// /opt/homebrew/bin/tmux with nothing at /usr/bin/tmux. So a new user types the
    /// very first command in the tutorial and gets "command not found", at the exact
    /// moment they have decided to trust the app.
    ///
    /// The obvious patch is a `brew install tmux` beat, and he took that apart too:
    /// *"if we show them in a tytorial then it implies we endorce homebrew."* He is
    /// right, and the cost is larger than the endorsement. A tutorial that installs
    /// Homebrew makes THIS app answerable for software it does not ship, cannot fix,
    /// and never chose — when brew fails, or wants Command Line Tools, or breaks on an
    /// OS update, the user blames Shell Citadel.
    ///
    /// `/usr/bin/screen` is already on every Mac. Same trick — a session that outlives
    /// the disconnect — with nothing to install and nobody endorsed. tmux still works
    /// for anyone who has it; the app is an SSH client and does not care. So the last
    /// beat names it in one line rather than teaching it.
    ///
    /// ⚠️ AND NOTHING HERE MAY DESCRIBE MICHAEL'S OWN SETUP AS IF IT WERE EVERYONE'S.
    /// He caught this one too, 2026-08-30: *"is claude listen txt on all claudes or is
    /// that specific to my setup"* — specific to his. `~/.claude-voice/out.txt` is not a
    /// Claude Code feature; it exists because he and Claude built the script and hooks
    /// that write it. No stock install has that directory. The beat used to name that
    /// exact path, so a stranger watching the demo was told to listen to a file they do
    /// not have and never will, with nothing explaining why it stayed empty. It now
    /// describes what the feature DOES and names the setting instead. Same fault as his
    /// name appearing in a button label earlier the same day.
    ///
    /// ⚠️ THE COMMANDS HERE ARE REAL AND MUST STAY REAL. Someone will type them. A
    /// plausible-looking command that does not work is worse than no demo. Every string
    /// below was verified against a live `screen` session on 2026-08-30, including the
    /// listing format, which is `PID.name` and a tab before `(Detached)`.
    static let script: [Beat] = [
        .init(source: .system,
              text: "This is a demonstration. Nothing is connected and nothing is being sent. It walks through the setup once, so the steps are here when you need them.",
              isOutput: false, delay: 0.3),

        .init(source: .system,
              text: "On your Mac, first: System Settings → General → Sharing → Remote Login, switched on. Then put that Mac's name, your username and your password into Settings here.",
              isOutput: false, delay: 1.8),

        // ⚠️ HIS ASK, 2026-08-31: "can you do a mock ssh username@my-macbook-air.local
        // then a nextline where it shows a password?"
        //
        // Shown because it is the form everyone already knows, and because it is a REAL
        // feature of this app rather than decoration: the composer parses
        // `ssh [user@]host [-p port]` — and a bare `user@host` too, his call on 08-29:
        // "what if i type fluhartyml@pihole in the text line?"
        //
        // ⚠️ AND THE PASSWORD BEAT IS THE APP'S OWN SENTENCE, NOT A UNIX PROMPT.
        // Real ssh prints "user@host's password:" and reads it invisibly from the
        // terminal. THIS APP DOES NOT DO THAT — it prints "Password needed for …" and
        // opens the Connection sheet, because a password typed into a transcript would
        // be a password sitting in a transcript. Showing the Unix prompt here would
        // teach a keystroke that does not exist, which is the one thing this file
        // forbids. The line below is copied from `connectFromSSHLine`.
        .init(source: .system,
              text: "You can also just type it, the way you would in any terminal.",
              isOutput: false, delay: 1.5),

        .init(source: .you, text: "ssh username@my-macbook-air.local",
              isOutput: false, delay: 1.5),

        .init(source: .system,
              text: "Password needed for username@my-macbook-air.local.",
              isOutput: false, delay: 1.2),

        .init(source: .system,
              text: "The Connection sheet opens with the host and username already filled, so the password is the only thing left to type. It is kept in the Keychain and never asked for again.",
              isOutput: false, delay: 1.8),

        // ⚠️ HIS ASK, 2026-08-31: "the demo probably should narrate you only need to ssh
        // to a server and shell connect will save it in the slider icon settings."
        //
        // VERIFIED BEFORE WRITING, not assumed — `connect()` adds the profile to
        // ConnectionLibrary on SUCCESS only, and appends this exact sentence. His own
        // ruling, 08-29: "if i successfully make a connection it should auto save to the
        // connections list." Proof first, then persistence, so an untested host typed
        // from memory never clutters the library.
        //
        // The name below is the host because that is what the code substitutes when the
        // profile name is still empty or the default.
        .init(source: .system,
              text: "Saved “my-macbook-air.local” to your connections.",
              isOutput: false, delay: 1.3),

        .init(source: .system,
              text: "That is the only time you type it. It is in the connections list behind the sliders now — open that in any tab and pick it, and the password comes with it.",
              isOutput: false, delay: 1.8),

        .init(source: .you, text: "screen -S claude", isOutput: false, delay: 1.6),
        .init(source: .claude, text: "~ %", isOutput: true, delay: 0.9),

        .init(source: .system,
              text: "That made a session named claude, using screen, which is already on every Mac. The session belongs to the Mac, not to this app — so it keeps running when you close your phone, lose signal, or walk away.",
              isOutput: false, delay: 1.6),

        .init(source: .you, text: "claude", isOutput: false, delay: 1.4),
        .init(source: .claude,
              text: "Welcome to Claude Code. Type your request, or /help for commands.",
              isOutput: true, delay: 1.0),

        // ⚠️ VENDOR NEUTRALITY — added 2026-08-31, and it is a SUBMISSION requirement,
        // not a nicety. The demo named one assistant three times, and the case for this
        // app being submittable at all rests on it being a terminal rather than any
        // vendor's client. Michael, 2026-08-29: "in theory the user could use chatgpt or
        // siri's lm cli tool." A reviewer skimming a Claude-only walkthrough sees a
        // Claude client, which is the Guideline 4.1(a) shape that already cost him
        // Audio Universe. So the neutrality is now DEMONSTRATED rather than argued.
        //
        // The command below is real and its output was captured from a live shell on
        // 2026-08-31, per the standard the rest of this script holds itself to.
        .init(source: .system,
              text: "That assistant is one example, not a requirement. Shell Citadel is a terminal — anything you can run over SSH runs here, and the app does not care what it is.",
              isOutput: false, delay: 1.5),

        .init(source: .you, text: "df -h /", isOutput: false, delay: 1.4),
        .init(source: .claude,
              text: "Filesystem        Size    Used   Avail Capacity  Mounted on\n/dev/disk3s3s1   926Gi    12Gi   181Gi     7%    /",
              isOutput: true, delay: 1.0),

        .init(source: .system,
              text: "Watching a file on the Mac for new lines. Settings calls it Spoken text — point it at any file a program appends plain sentences to.",
              isOutput: false, delay: 0.9),

        .init(source: .you, text: "which disks are nearly full?", isOutput: false, delay: 1.6),
        .init(source: .claude,
              text: "The 1TB external is at 72 percent with 293 gigabytes free. Nothing needs attention today.",
              isOutput: false, delay: 1.4),

        .init(source: .you, text: "📷 rack-label.jpg — 412 KB", isOutput: false, delay: 1.8),
        .init(source: .claude,
              text: "That is the service tag on the back of the server. I can read it: it ends 7QX4L2.",
              isOutput: false, delay: 1.3),

        .init(source: .system,
              text: "Closing the app now would leave all of that running. Press Control-A then D to step out of the session without stopping it.",
              isOutput: false, delay: 1.7),
        .init(source: .claude, text: "[detached from 82263.claude]",
              isOutput: true, delay: 0.9),

        .init(source: .system,
              text: "You were away — catching up on what you missed.",
              isOutput: false, delay: 1.6),
        .init(source: .claude,
              text: "The overnight job finished while your phone was locked. This line was written twenty minutes ago and was waiting for you — the app remembers how far it had read, so nothing is skipped.",
              isOutput: false, delay: 1.0),
        .init(source: .system, text: "Caught up. Anything below this is live.",
              isOutput: false, delay: 0.9),

        .init(source: .you, text: "screen -r claude", isOutput: false, delay: 1.6),
        .init(source: .claude, text: "~ %", isOutput: true, delay: 0.9),
        .init(source: .system,
              text: "Same session, hours later, nothing lost. That is the whole point of the two commands above. Forgotten the name? screen -ls lists them.",
              isOutput: false, delay: 1.4),

        .init(source: .system,
              text: "If you already use tmux, it works exactly the same way here — tmux new -s claude, and tmux attach -t claude. Nothing to install either way.",
              isOutput: false, delay: 1.6),

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
