//
//  TranscriptLine.swift
//  Shell Citadel
//
//  One line of the metaphorical terminal.
//
//  WHY A TRANSCRIPT AND NOT A TERMINAL BUFFER: Claude Code running inside tmux
//  emits a terminal STREAM — escape codes, spinners, boxes, redraws. That stream
//  is not speakable and it is not readable as conversation. So the scrollback
//  here holds sentences, not output, and the raw terminal is a separate view.
//

import Foundation

struct TranscriptLine: Identifiable, Hashable {
    enum Source: Hashable {
        case you        // typed, or spoken and transcribed — rendered the same
        case claude     // arrives on the voice channel: sentences only
        case system     // connection state, errors, notices
    }

    let id = UUID()
    let source: Source
    let text: String
    let at: Date

    init(_ source: Source, _ text: String, at: Date = Date()) {
        self.source = source
        self.text = text
        self.at = at
    }

    /// The prompt shown ahead of the line. Not a `$` — this terminal is a costume,
    /// so the prompt can say who is talking instead.
    var prompt: String {
        switch source {
        case .you:    return ">"
        case .claude: return "·"
        case .system: return "—"
        }
    }
}
