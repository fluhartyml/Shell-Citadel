//
//  VoiceMark.swift
//  Shell Citadel
//
//  THE PASSIVE QUEUE.  Michael's phrase, on his front porch, 2026-08-23:
//  "we deed a passive queue."
//
//  The queue already existed and nobody was using it. `~/.claude-voice/out.txt` on the
//  Mac is append-only and never truncated, so every sentence Claude has ever written is
//  still sitting there. What was missing was the phone remembering how far it had read.
//
//  WHAT IT REPLACES:  the voice channel opened with `tail -n 0 -F`, meaning START AT THE
//  END. That was deliberate — it stopped a fresh connection replaying an old session's
//  whole transcript. The unintended consequence was that every reply written while the
//  phone was locked, backgrounded or out of range was skipped PERMANENTLY, and skipped
//  silently. Michael locks his phone by habit before pocketing it, so this fired on
//  every single trip between rooms.
//
//  It also lands on the rule he set the day before: audio is the live channel, text is
//  the recap. A locked phone misses BOTH — he does not hear it, and the recap never
//  arrives. There was no third copy on his side. The Mac's copy was always fine.
//
//  WHY A BYTE OFFSET AND NOT A LINE COUNT: `tail -c +N` is a single flag and needs no
//  state on the Mac. Nothing runs there, nothing is installed, nothing is cleaned up.
//  That is what makes the queue passive.
//
//  The mark advances only over COMPLETE lines. A partial line held in the reader's
//  buffer is deliberately left uncounted, so a connection dropping mid-sentence causes
//  that sentence to be re-read whole rather than resumed halfway.
//

import Foundation

/// Where the phone had read up to in a Mac's voice file, per connection.
enum VoiceMark {

    private static let prefix = "voiceMark."

    /// One mark per host+user+file. Changing the voice path in Settings starts a fresh
    /// mark rather than resuming into a different file at a meaningless offset.
    private static func key(for destination: SSHDestination) -> String {
        "\(prefix)\(destination.username)@\(destination.host):\(destination.port)|\(destination.voicePath)"
    }

    /// Bytes already read and shown. 0 means "never connected to this file".
    static func offset(for destination: SSHDestination) -> Int {
        UserDefaults.standard.integer(forKey: key(for: destination))
    }

    static func set(_ offset: Int, for destination: SSHDestination) {
        UserDefaults.standard.set(offset, forKey: key(for: destination))
    }

    /// Used when the far-side file has shrunk — it was rotated, replaced, or emptied, so
    /// the old offset points at nothing meaningful and keeping it would skip real lines.
    static func clear(for destination: SSHDestination) {
        UserDefaults.standard.removeObject(forKey: key(for: destination))
    }
}

/// One line off the voice channel, carrying how far into the file it ends.
///
/// The offset travels WITH the line rather than being counted by the caller, because the
/// caller sees decoded text and the file is measured in bytes — and a sentence with an
/// em dash or an accent in it is longer on disk than it looks on screen.
struct VoiceChunk {
    let text: String
    /// Total bytes consumed once this line has been shown.
    let offsetAfter: Int
}
