//
//  LinkLight.swift
//  Shell Citadel
//
//  A traffic light for the connection.  Michael, 2026-08-27:
//  "Something simple like a red nosignal yellow some interference and green for all
//   is functional"
//
//  WHY A HEARTBEAT AND NOT A FLAG.  The app already had a boolean `connected`, set
//  when the handshake succeeded and cleared when something threw. That is not the
//  same as "the link works now", and the gap between those two is exactly where he
//  keeps losing sessions:
//
//    A TCP socket does not announce its own death. When the phone locks, or the wifi
//    hands off between rooms, or cellular drops for a moment, the socket is gone and
//    NEITHER END KNOWS. Nothing throws. `connected` stays true. The next thing he
//    types goes into a pipe with no other end, and he finds out by waiting for a
//    reply that is never coming.
//
//  So green cannot mean "nothing has gone wrong yet" — that is the state that lies to
//  him. Green has to mean VERIFIED RECENTLY, which needs traffic of our own.
//
//  WHY NOT MEASURE THE VOICE CHANNEL INSTEAD.  It was the first idea and it is wrong.
//  `voiceLines` is a long-lived stream, and silence on it is the NORMAL case — Claude
//  is simply not talking. A quiet stream and a dead stream look identical from here,
//  which is the very confusion this view exists to end.
//
//  COST.  One `printf` every ten seconds. It opens an exec channel, writes two bytes
//  and closes. Chosen over `true` so there is output to prove the round trip actually
//  completed rather than merely opened.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class LinkLight {

    enum Quality {
        case red        // no signal — two beats missed, or never connected
        case yellow     // interference — slow, or one beat missed
        case green      // all functional — verified inside the last interval

        var colour: Color {
            switch self {
            case .red: .red
            case .yellow: .yellow
            case .green: .green
            }
        }

        /// Spoken by VoiceOver, and shown in the popover. Written as plain sentences
        /// because "yellow" on its own tells him a colour, not a situation.
        var summary: String {
            switch self {
            case .red: "No signal. Nothing you send will arrive."
            case .yellow: "Interference. The link is up but struggling."
            case .green: "All functional."
            }
        }
    }

    private(set) var quality: Quality = .red
    /// Milliseconds for the last completed heartbeat. `nil` when the last one failed.
    private(set) var roundTrip: Int?
    private(set) var lastGood: Date?

    private var missed = 0
    private var beat: Task<Void, Never>?

    #if DEBUG
    /// ⚠️ DEBUG BUILDS ONLY, AND THIS IS NOT A STYLE PREFERENCE.
    ///
    /// Michael, 2026-08-27: "we did submit debug info once in talley matrix clock once and
    /// had it almost rejected. the debug info looked industrial and cool so i thought it
    /// would be a cool easteregg but app store connect didnt agree."
    ///
    /// That is the whole warning. A debug surface does not look like a mistake — it looks
    /// like craft, which is exactly why it survives review of your own work and then fails
    /// review by Apple. So this is not hidden behind a setting or a gesture nobody knows.
    /// It is compiled OUT. In a Release build the property, the menu and every one of these
    /// strings are absent from the binary.
    ///
    /// WHY IT EXISTS: to see the light go yellow or red he otherwise has to genuinely
    /// degrade the connection — walk out of wifi range, lock the phone, wait. Testing the
    /// feature should not require leaving the room.
    var simulated: Quality? {
        didSet { if let simulated { quality = simulated } }
    }
    #endif

    /// How often to probe. Ten seconds is a compromise: short enough that green is a
    /// claim about NOW rather than about a minute ago, long enough that it is not
    /// noticeable traffic on a cellular connection he pays for.
    private let interval: Duration = .seconds(10)

    /// A heartbeat that never returns is the SIGNAL, not a bug to wait out. On a dead
    /// socket `run` can hang indefinitely — there is nothing to time out against at the
    /// TCP layer — so the deadline has to live here. Eight seconds sits inside the ten
    /// second interval so beats can never overlap.
    private let deadline: Duration = .seconds(8)

    // MARK: - Lifecycle

    func start(pinging session: SSHSession) {
        stop()
        // Optimistic yellow rather than green: the connection just succeeded, but this
        // view's whole promise is that green was MEASURED. It has not been yet.
        quality = .yellow
        missed = 0
        beat = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pulse(session)
                try? await Task.sleep(for: self?.interval ?? .seconds(10))
            }
        }
    }

    func stop() {
        beat?.cancel()
        beat = nil
    }

    /// Called when the app KNOWS the link is gone — a thrown error, an explicit
    /// disconnect. Skips straight to red rather than waiting out two missed beats,
    /// because we are not guessing at that point.
    func markDown() {
        stop()
        quality = .red
        roundTrip = nil
        missed = 0
    }

    // MARK: - The beat

    private func pulse(_ session: SSHSession) async {
        let started = ContinuousClock.now

        let ok = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                (try? await session.run("printf ok")) != nil
            }
            group.addTask { [deadline] in
                try? await Task.sleep(for: deadline)
                return false        // the deadline won: treat as a miss
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        guard !Task.isCancelled else { return }

        #if DEBUG
        // A forced value outranks the measurement, or the next beat would silently undo
        // what he just set and make the control look broken.
        if simulated != nil { return }
        #endif

        if ok {
            let ms = Int(started.duration(to: .now) / .milliseconds(1))
            roundTrip = ms
            lastGood = Date()
            missed = 0
            // Half a second is the line between "this feels immediate" and "this feels
            // like it is thinking about it". Above that, sending a long message is
            // still going to work but he should know before he commits to typing one.
            quality = ms < 500 ? .green : .yellow
        } else {
            roundTrip = nil
            missed += 1
            // One miss is a hiccup — a handoff between rooms, a moment of cellular.
            // Two in a row, twenty seconds apart, is a link that is not coming back
            // on its own.
            quality = missed >= 2 ? .red : .yellow
        }
    }
}

// MARK: - The view

/// Deliberately a filled circle and not bars. Bars imply a resolution this cannot
/// honestly deliver — there is no signal strength to measure, only "did a round trip
/// complete, and how fast". Three states, three colours, no false precision.
struct LinkLightView: View {
    let light: LinkLight
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            Circle()
                .fill(light.quality.colour)
                .frame(width: 12, height: 12)
                // Without this the yellow and green dots are nearly the same shape
                // against a light toolbar, and the whole point is glanceability.
                .overlay(Circle().stroke(.primary.opacity(0.25), lineWidth: 0.5))
        }
        .accessibilityLabel("Connection")
        .accessibilityValue(light.quality.summary)
        #if DEBUG
        // Long press. Compiled out of Release entirely — see `LinkLight.simulated`.
        // Every label says SIMULATED, so a screenshot taken in a debug build cannot be
        // mistaken for real behaviour either.
        .contextMenu {
            Section("Debug — not in release builds") {
                Button("SIMULATED green")  { light.simulated = .green }
                Button("SIMULATED yellow") { light.simulated = .yellow }
                Button("SIMULATED red")    { light.simulated = .red }
                Button("Stop simulating — use the real heartbeat") { light.simulated = nil }
            }
        }
        #endif
        .popover(isPresented: $showingDetail) {
            VStack(alignment: .leading, spacing: 8) {
                Text(light.quality.summary)
                    .font(.callout.weight(.semibold))
                if let ms = light.roundTrip {
                    Text("Round trip \(ms) ms")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let good = light.lastGood {
                    Text("Last verified \(good.formatted(date: .omitted, time: .standard))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }
}
