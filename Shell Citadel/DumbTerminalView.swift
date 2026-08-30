//
//  DumbTerminalView.swift
//  Shell Citadel
//
//  Michael, 2026-08-29: "I want a dumb terminal to be a dumb terminal."
//
//  So there is no app voice in here. No transcript rows, no per-line prompt glyph drawn by
//  us, no "Connected to …" notice. One text buffer holding exactly what the far end sent,
//  including its own prompt, because the shell on the other side is a real login shell on
//  a PTY. What you type is what it gets.
//
import SwiftUI

struct DumbTerminalView: View {
    @ObservedObject var pty: PTYSession
    @ObservedObject var appearance = TerminalAppearance.shared

    /// Whether the key catcher holds first responder. Tapping the screen takes it, the
    /// way clicking a terminal window does.
    @State private var typing = true
    @State private var line = ""
    /// The width the stream actually has. The geometry sent to the far end is computed
    /// from this, not assumed — a shell told 80 columns while drawing into 46 will run
    /// `top` off the edge of the screen.
    @State private var streamWidth: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            stream
            controls
            // SUPPLEMENTAL, NOT PRIMARY. Michael, 2026-08-29: "the cursor should be next
            // to $ and not in the chat bar — only the chat bar should stay but be
            // supplemental for when i am in tmux chat mode with you." Typing goes into the
            // screen beside the shell's own prompt; this stays for sending a whole line at
            // once, which is what talking to Claude through tmux actually is.
            composer
        }
        .background(appearance.background.color)
    }

    private var stream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // AN EXPLICIT BLINKING CURSOR. Michael, 2026-08-29: "The blinking cursor
                // needs to be explicit." The shell's own cursor is invisible here because
                // we strip the escape sequences that would position and draw it, so the
                // block is ours — parked at the end of the buffer, which is where the
                // shell's cursor is whenever it is waiting for you.
                //
                // 530ms is the classic terminal blink interval, and TimelineView drives it
                // without a Timer to own or invalidate.
                TimelineView(.periodic(from: .now, by: 0.53)) { context in
                    let lit = Int(context.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0
                    (Text(pty.screen.isEmpty ? "" : pty.screen)
                     + Text(lit && pty.isRunning ? "\u{2588}" : "\u{2007}"))
                    .font(.custom(TerminalFont.regular, size: effectiveSize))
                    .foregroundStyle(appearance.text.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .id("bottom")
            }
            // TYPE INTO THE TERMINAL, NOT INTO A BOX. Michael, 2026-08-29: "I should be
            // able to type inside the terminal … like i can on a real terminal." The
            // catcher draws nothing; the characters you see are the SHELL echoing them,
            // which is why backspace and Ctrl-C behave the way they do at a real prompt.
            .overlay {
                TerminalKeyInput(onBytes: { pty.send($0) }, isFocused: $typing)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { typing = true }
            .onChange(of: pty.screen) { _, _ in
                withAnimation(.none) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { streamWidth = geo.size.width - 16 }
                        .onChange(of: geo.size.width) { _, w in streamWidth = w - 16 }
                }
            )
            .onChange(of: effectiveGeometry.cols) { _, _ in reportGeometry() }
            .onChange(of: appearance.rows) { _, _ in reportGeometry() }
            .onChange(of: pty.isRunning) { _, running in if running { reportGeometry() } }
        }
    }

    /// The keys a shell needs that a phone keyboard does not have. Not decoration:
    /// without ^C a runaway command cannot be stopped, and the session is just stuck.
    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                key("^C") { pty.sendControl("C") }
                key("^D") { pty.sendControl("D") }
                key("^L") { pty.sendControl("L") }
                key("^Z") { pty.sendControl("Z") }
                key("tab") { pty.send("\t") }
                key("esc") { pty.send("\u{1B}") }
                key("↑") { pty.send("\u{1B}[A") }
                key("↓") { pty.send("\u{1B}[B") }
                Spacer(minLength: 12)
                key(typing ? "hide ⌨" : "type") { typing.toggle() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .background(appearance.background.color.opacity(0.9))
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom(TerminalFont.regular, size: max(11, appearance.fontSize - 2)))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(appearance.text.color.opacity(0.45), lineWidth: 1))
                .foregroundStyle(appearance.text.color)
        }
        .buttonStyle(.plain)
    }


    /// One whole line at a time, for talking to Claude in a tmux session — where a
    /// sentence is the unit, not a keystroke. Ordinary shell work happens in the screen
    /// above; this is the other half of what he does here.
    private var composer: some View {
        HStack(spacing: 8) {
            CommandField(text: $line,
                         placeholder: "send a whole line",
                         isEnabled: pty.isRunning,
                         strict: true,
                         // 0 = never auto-focus. The PTY screen above owns the keyboard
                         // here; a composer that grabbed first responder on appearance
                         // would eat everything he types at the shell.
                         focusRequest: 0,
                         onSubmit: submitLine)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            Button(action: submitLine) { Image(systemName: "arrow.up.circle.fill") }
                .disabled(line.trimmingCharacters(in: .whitespaces).isEmpty || !pty.isRunning)
                .foregroundStyle(appearance.text.color)
                .accessibilityLabel("Send line")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(appearance.background.color)
        .overlay(alignment: .top) {
            Rectangle().frame(height: 0.5)
                .foregroundStyle(appearance.text.color.opacity(0.25))
        }
    }

    private func submitLine() {
        guard !line.isEmpty else { return }
        // CR, like the Return key — the shell is on a PTY and expects what a keyboard sends.
        pty.send(line + "\r")
        line = ""
    }

    /// Point size actually used: derived from the column count when he is fitting to
    /// columns, otherwise his slider value.
    private var effectiveSize: Double {
        guard appearance.fitToColumns, streamWidth > 0 else { return appearance.fontSize }
        return TerminalAppearance.sizeToFit(columns: appearance.cols, width: streamWidth)
    }

    /// What the far end is told. When fitting, that is exactly his column count; when not,
    /// it is however many whole characters fit, so the two never disagree.
    private var effectiveGeometry: (cols: Int, rows: Int) {
        guard streamWidth > 0 else { return (appearance.cols, appearance.rows) }
        let c = appearance.fitToColumns
            ? appearance.cols
            : TerminalAppearance.columnsThatFit(width: streamWidth, at: appearance.fontSize)
        return (c, appearance.rows)
    }

    private func reportGeometry() {
        let g = effectiveGeometry
        pty.resize(cols: g.cols, rows: g.rows)
    }

}
