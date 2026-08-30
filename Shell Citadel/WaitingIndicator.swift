//
//  WaitingIndicator.swift
//  Shell Citadel
//
//  Michael, 2026-08-30 06:39, from the iPad:
//  "You also need to have that working or typing animation so i know youre not locked up
//   during your LONG delay betwenn my sending of a response and your reply"
//
//  He raised it twice. First at 04:42 — "It takes a long time to get a responce from you,
//  that's okay is there a way to see a typing animation or similar to show tou are working"
//  — and the answer he got then was wrong, because I assumed he was attached to the tmux
//  pane and could see Claude Code's own spinner. He is not. Shell Citadel is a CHAT
//  CLIENT: it pushes into tmux with paste-buffer and reads replies by tailing a file. It
//  never sees the pane, so it never sees the spinner. The indicator has to be built here.
//
//  ── ⚠️ WHAT THIS CAN AND CANNOT HONESTLY CLAIM ─────────────────────────────────
//  This app has NO WAY TO KNOW whether Claude is thinking, stuck, or dead. All it knows
//  is: a message was sent at time T, and nothing has come back on the reply channel yet.
//
//  So it must not say "Claude is typing". That is a claim about the far end that this
//  side cannot support, and a fake typing animation over a crashed session is exactly the
//  false-green this project keeps hunting down — the cycler that logged CYCLED over an
//  empty pane, the voice channel that failed silently for a day.
//
//  It says "Waiting for a reply" and it SHOWS THE CLOCK. The elapsed time is the honest
//  part: forty seconds reads as thinking, four minutes reads as go and look. It answers
//  his actual question — "is it locked up?" — better than a spinner does, because a
//  spinner spins just as smoothly either way.
//
//  The dots animate so the row is alive on screen; the number is what carries the meaning.
//

import Combine
import SwiftUI

struct WaitingIndicator: View {

    /// When the message went out. The row renders nothing without it.
    let since: Date

    /// Drives both the dots and the clock from one timer, so they can never disagree.
    @State private var elapsed: TimeInterval = 0
    @State private var phase = 0

    /// `Timer.publish` is Combine, hence the import — the one place in this app that
    /// needs it, and it is worth the dependency for a row that has to keep moving while
    /// nothing else on screen is.
    ///
    /// Half a second: fast enough that the dots read as motion, slow enough that it is
    /// not spending battery redrawing a three-character row. The seconds display only
    /// changes on every other tick and that is fine — nobody is timing a race.
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // No prompt column and no font of its own any more. This used to be a row in
            // the transcript and needed to line up with it; since 2026-08-30 it lives in
            // the fixed status strip beside a yellow dot, and it inherits that strip's
            // caption font so it matches "Connected" exactly rather than shouting.
            Text(label)
                // Announced as one changing value rather than as new text every half
                // second, which would make VoiceOver read the row aloud continuously.
                .accessibilityLabel("Waiting for a reply, \(Int(elapsed)) seconds")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(tick) { _ in
            elapsed = Date().timeIntervalSince(since)
            phase = (phase + 1) % 4
        }
        .onAppear { elapsed = Date().timeIntervalSince(since) }
    }

    /// `Waiting for a reply ..    1m 12s`
    ///
    /// The dots are padded to a fixed three characters so the text after them does not
    /// jitter left and right — a line that shifts while you are reading it is worse than
    /// a still one.
    private var label: String {
        let dots = String(repeating: ".", count: phase)
        let pad = String(repeating: " ", count: 3 - phase)
        return "Waiting for a reply \(dots)\(pad) \(Self.clock(elapsed))"
    }

    /// Seconds under a minute, then minutes and seconds. No hours: if it ever gets that
    /// far the number has already made its point.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        if whole < 60 { return "\(whole)s" }
        return "\(whole / 60)m \(whole % 60)s"
    }
}
