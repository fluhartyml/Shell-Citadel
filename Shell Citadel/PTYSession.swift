//
//  PTYSession.swift
//  Shell Citadel
//
//  Michael, 2026-08-29: "I want a dumb terminal to be a dumb terminal."
//
//  WHAT WAS WRONG WITH THE OLD PATH. Direct mode ran each command in a NEW shell over an
//  exec channel, then the app printed its own notices and composed its own prompt from
//  what he had TYPED. Every part of that is the app interpreting: a prompt that is not the
//  machine's prompt, a greeting the machine never sent, and a shell with no memory between
//  lines. His words: "i want it to echo the current connection, i dont want to show my
//  interpretation."
//
//  WHAT THIS IS INSTEAD. One persistent shell on a pseudo-terminal. The remote prints its
//  own prompt because it is a real login shell; what it sends is what you see; what you
//  type is what it gets. The app has no voice inside the stream at all.
//
import Citadel
import Combine
import Foundation
import NIOCore
import NIOSSH

@MainActor
final class PTYSession: ObservableObject {
    /// Everything the far end has sent, exactly as it sent it (minus escape sequences we
    /// cannot draw — see ANSI.strip).
    @Published private(set) var screen = ""
    @Published private(set) var isRunning = false
    @Published private(set) var failure: String?

    private var writer: TTYStdinWriter?
    private var task: Task<Void, Never>?

    /// Start a login shell on the far end. `client` is an already-authenticated session.
    func start(client: SSHClient, cols: Int = 80, rows: Int = 24) {
        guard task == nil else { return }
        isRunning = true
        failure = nil
        screen = ""

        task = Task { [weak self] in
            do {
                try await client.withPTY(
                    .init(
                        wantReply: true,
                        term: "xterm-256color",
                        terminalCharacterWidth: cols,
                        terminalRowHeight: rows,
                        terminalPixelWidth: 0,
                        terminalPixelHeight: 0,
                        terminalModes: .init([:])
                    )
                ) { inbound, outbound in
                    await self?.adopt(outbound)
                    for try await chunk in inbound {
                        switch chunk {
                        case .stdout(let buffer), .stderr(let buffer):
                            // stderr is merged deliberately: a terminal does not sort a
                            // machine's words into two columns, and splitting them would
                            // hide the half that says why something failed.
                            await self?.appendRaw(String(buffer: buffer))
                        }
                    }
                }
            } catch {
                await self?.finish(error: error)
                return
            }
            await self?.finish(error: nil)
        }
    }

    /// Send exactly these bytes. A line needs its own newline — the caller decides,
    /// because a dumb terminal does not add punctuation on your behalf.
    func send(_ text: String) {
        guard let writer else { return }
        Task { try? await writer.write(ByteBuffer(string: text)) }
    }

    /// Control characters, by name, because they are what makes a terminal usable:
    /// interrupt a runaway command, end input, clear the screen.
    func sendControl(_ character: Character) {
        guard let ascii = character.uppercased().first?.asciiValue,
              ascii >= 64, ascii <= 95 else { return }
        send(String(UnicodeScalar(ascii - 64)))
    }

    func resize(cols: Int, rows: Int) {
        guard let writer else { return }
        Task { try? await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0) }
    }

    func stop() {
        task?.cancel()
        task = nil
        writer = nil
        isRunning = false
    }

    // MARK: - Private

    private func adopt(_ outbound: TTYStdinWriter) { writer = outbound }

    private func appendRaw(_ text: String) {
        screen.append(ANSI.strip(text))
        // A terminal that grows without limit eventually stops being usable on a phone.
        // Keep the tail; a dumb terminal has no scrollback obligation beyond what fits.
        if screen.count > 200_000 {
            screen = String(screen.suffix(150_000))
        }
    }

    private func finish(error: Error?) {
        isRunning = false
        writer = nil
        task = nil
        if let error { failure = "\(error)" }
    }
}

/// The minimum needed to render a real shell's output as text.
///
/// A full terminal emulator maintains a grid and honours cursor movement. This does not —
/// it removes the sequences it cannot draw so the words survive, which is the honest
/// middle ground between a raw byte dump and pretending to be xterm. Colour is dropped
/// rather than shown wrong.
enum ANSI {
    static func strip(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        var i = input.startIndex
        while i < input.endIndex {
            let c = input[i]
            if c == "\u{1B}" {                      // ESC
                var j = input.index(after: i)
                guard j < input.endIndex else { break }
                if input[j] == "[" {                // CSI … final byte @–~
                    j = input.index(after: j)
                    while j < input.endIndex, !("\u{40}"..."\u{7E}").contains(input[j]) {
                        j = input.index(after: j)
                    }
                    if j < input.endIndex { j = input.index(after: j) }
                } else if input[j] == "]" {         // OSC … BEL or ST
                    j = input.index(after: j)
                    while j < input.endIndex, input[j] != "\u{07}", input[j] != "\u{1B}" {
                        j = input.index(after: j)
                    }
                    if j < input.endIndex { j = input.index(after: j) }
                } else {
                    j = input.index(after: j)
                }
                i = j
            } else if c == "\r" {
                // Carriage return without a newline redraws the same line. Keep it simple:
                // treat a lone CR as a line break rather than losing the text behind it.
                let next = input.index(after: i)
                if next < input.endIndex, input[next] == "\n" {
                    out.append("\n"); i = input.index(after: next)
                } else {
                    out.append("\n"); i = next
                }
            } else if c == "\u{07}" {               // BEL
                i = input.index(after: i)
            } else if c == "\u{08}" {               // BS — a real backspace from the shell
                if !out.isEmpty { out.removeLast() }
                i = input.index(after: i)
            } else {
                out.append(c)
                i = input.index(after: i)
            }
        }
        return out
    }
}
