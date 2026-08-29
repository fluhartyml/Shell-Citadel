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

    @State private var line = ""
    @FocusState private var focused: Bool
    /// The width the stream actually has. The geometry sent to the far end is computed
    /// from this, not assumed — a shell told 80 columns while drawing into 46 will run
    /// `top` off the edge of the screen.
    @State private var streamWidth: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            stream
            controls
            composer
        }
        .background(appearance.background.color)
    }

    private var stream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(pty.screen.isEmpty ? " " : pty.screen)
                    .font(.custom(TerminalFont.regular, size: effectiveSize))
                    .foregroundStyle(appearance.text.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .id("bottom")
            }
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
                .background(appearance.text.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(appearance.text.color)
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            // NO PROMPT DRAWN HERE. The prompt is whatever the shell just printed above,
            // because that is the machine's, not ours.
            CommandField(text: $line,
                         placeholder: "",
                         isEnabled: pty.isRunning,
                         strict: true,
                         onSubmit: submit)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            Button(action: submit) {
                Image(systemName: "return")
            }
            .disabled(!pty.isRunning)
            .foregroundStyle(appearance.text.color)
            .accessibilityLabel("Send line")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(appearance.background.color)
        .overlay(alignment: .top) {
            Rectangle().frame(height: 0.5).foregroundStyle(appearance.text.color.opacity(0.25))
        }
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

    private func submit() {
        // The newline is added here and nowhere else: a dumb terminal sends the line the
        // moment you press return, exactly as typed, and adds nothing else to it.
        pty.send(line + "\n")
        line = ""
    }
}
