//
//  MicGate.swift
//  Shell Citadel
//
//  THE MICROPHONE GATE — read on the audio thread, written by the speech delegate.
//
//  WHY THIS EXISTS AS ITS OWN OBJECT, 2026-08-31.
//
//  Michael found the app talking to itself at 18:18 — my reply came back as his next
//  message, word for word. A guard went in the same evening. He then found it STILL
//  looping and named the fix himself: "you need that fault to work when i send you text
//  from my iphone and turn off when you send a reply." Half duplex. The mic goes deaf
//  while the app talks, and comes back after.
//
//  ⚠️ THE FIRST GUARD WAS RIGHT IN INTENT AND LEAKY IN CONSTRUCTION, THREE WAYS:
//
//  1. IT WAS CHECKED ASYNCHRONOUSLY. The audio tap runs on a real-time audio thread and
//     did `Task { @MainActor in guard !isSpeaking ... }`. A flag read on a DIFFERENT
//     thread from the one capturing is a race, not a gate: audio captured while the app
//     was talking could be appended after the flag cleared.
//
//  2. THE FLAG ITSELF WAS SET LATE. `didStart` is nonisolated and hopped to the main
//     actor to set `isSpeaking`, so the first moments of every utterance were admitted
//     through a gate that had not shut yet.
//
//  3. IT SHUT AND OPENED INSTANTLY. Speech ends, flag clears, but the room's reverb and
//     whatever the recogniser had already buffered are still in flight. A gate with no
//     tail lets the end of the app's own sentence through.
//
//  So this gate is: a plain lock, read SYNCHRONOUSLY from the audio thread, shut
//  SYNCHRONOUSLY from the delegate with no actor hop, and reopened only after a grace
//  period.
//
//  ⚠️ AND IT DOES NOT TOUCH THE AUDIO ENGINE. The obvious reading of "turn the mic off"
//  is to stop the engine or remove the tap and put it back. That is exactly the bug he
//  hit at 18:12 — "its green but not listening" — when a refactor removed the tap and
//  every visible signal still said working. Tearing down capture to achieve silence
//  risks not getting it back; withholding the DATA achieves the same silence and cannot
//  fail closed. The engine runs continuously; the gate decides what counts.
//
//  → Skills Lab: "Test in the worse configuration" — AirPods hide this entirely.
//

import Foundation

/// Whether the microphone's audio should be believed right now.
///
/// `@unchecked Sendable` is deliberate and the lock is why: every stored property is
/// accessed only inside `lock`, so this is safe to read from the audio thread and write
/// from the speech delegate without involving an actor.
final class MicGate: @unchecked Sendable {

    static let shared = MicGate()

    /// How long the gate stays shut after the app stops talking.
    ///
    /// Covers two things at once: the room's acoustic tail, and audio the recogniser had
    /// already buffered before the synthesiser finished. Long enough to swallow the end
    /// of my own sentence; short enough that his reply straight afterwards is not eaten.
    static let grace: TimeInterval = 0.6

    private let lock = NSLock()
    private var speaking = false
    private var shutUntil: CFAbsoluteTime = 0

    private init() {}

    /// True when captured audio is his voice rather than the app's own.
    ///
    /// Called per audio buffer on the capture thread, so it must not allocate, hop, or
    /// await. A lock and two comparisons.
    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !speaking && CFAbsoluteTimeGetCurrent() >= shutUntil
    }

    /// Shut the gate. Call this SYNCHRONOUSLY the moment speech begins — before any
    /// `Task`, before any actor hop — or the first words go out through an open gate.
    func shut() {
        lock.lock()
        speaking = true
        lock.unlock()
    }

    /// Speech has stopped. The gate stays shut for `grace` seconds more.
    func openAfterGrace() {
        lock.lock()
        speaking = false
        shutUntil = CFAbsoluteTimeGetCurrent() + Self.grace
        lock.unlock()
    }
}
