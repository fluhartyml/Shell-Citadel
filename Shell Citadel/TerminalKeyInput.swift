//
//  TerminalKeyInput.swift
//  Shell Citadel
//
//  Michael, 2026-08-29: "I should be able to type inside the terminal … like i can on a
//  real terminal."
//
//  A real terminal has no input box. You type, the bytes go to the shell, and the SHELL
//  echoes them back — which is why your own typing appears in the same stream as the
//  output, and why backspace and Ctrl-C behave. A composer at the bottom is a chat window's
//  idea, not a terminal's.
//
//  So this view draws nothing. It becomes first responder, captures keystrokes, and hands
//  each one straight to the PTY. There is NO local echo on purpose: if this drew the
//  characters itself they would appear twice, and worse, they would appear even when the
//  far end never received them.
//
import SwiftUI
import UIKit

struct TerminalKeyInput: UIViewRepresentable {
    let onBytes: (String) -> Void
    @Binding var isFocused: Bool

    func makeUIView(context: Context) -> KeyCatcher {
        let v = KeyCatcher()
        v.onBytes = onBytes
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: KeyCatcher, context: Context) {
        v.onBytes = onBytes
        // ⛔ NOT WHILE SOMETHING IS PRESENTED OVER THE TERMINAL.
        //
        // This ran on every redraw with no window test at all, so while the Connection
        // settings sheet was open this invisible catcher — sitting in the terminal
        // BEHIND the sheet — took the keyboard straight back off the Password field.
        // Michael, 2026-09-03, after the composer had already been guarded: "the cursur
        // blinked a few times then went away." Guarding one thief left the other one.
        //
        // A presented sheet owns the key window, so this is the whole question: is the
        // terminal actually the thing on screen?
        let onTop = v.window?.isKeyWindow == true
        if isFocused, onTop, !v.isFirstResponder { v.becomeFirstResponder() }
        // Giving it UP stays unconditional — releasing the keyboard is never the thing
        // that steals from someone else.
        if !isFocused, v.isFirstResponder { v.resignFirstResponder() }
    }

    final class KeyCatcher: UIView, UIKeyInput {
        var onBytes: ((String) -> Void)?

        override var canBecomeFirstResponder: Bool { true }

        // MARK: UIKeyInput

        /// Always true: the shell decides what is deletable, not us. Reporting false would
        /// make iOS swallow backspace at the start of a line, which is exactly when a
        /// shell still wants the byte — a wrapped command line is one line to bash.
        var hasText: Bool { true }

        func insertText(_ text: String) {
            // Return is CR on a terminal, not LF. Sending "\n" makes some shells and most
            // full-screen programs behave oddly, because they are waiting for the key a
            // keyboard actually sends.
            onBytes?(text == "\n" ? "\r" : text)
        }

        /// Last time a delete was sent, so the hardware key and `deleteBackward` cannot
        /// both fire for one press and erase two characters. Michael, 2026-08-29: "Delete
        /// doesnt back space" — the fix is a hardware binding, and this stops the fix from
        /// creating a worse bug than the one it cures.
        private var lastDelete = Date.distantPast

        func deleteBackward() { sendDelete() }

        func sendDelete() {
            guard Date().timeIntervalSince(lastDelete) > 0.02 else { return }
            lastDelete = Date()
            // DEL (0x7F) is what a terminal Backspace sends, and what `stty erase` is set
            // to on Debian by default. BS (0x08) only moves the cursor left on many
            // systems, which looks like nothing happening.
            onBytes?("\u{7F}")
        }

        var keyboardType: UIKeyboardType {
            get { .asciiCapable } set { }
        }
        var autocorrectionType: UITextAutocorrectionType {
            get { .no } set { }
        }
        var autocapitalizationType: UITextAutocapitalizationType {
            get { .none } set { }
        }
        var spellCheckingType: UITextSpellCheckingType {
            get { .no } set { }
        }
        var smartQuotesType: UITextSmartQuotesType {
            get { .no } set { }
        }
        var smartDashesType: UITextSmartDashesType {
            get { .no } set { }
        }
        var smartInsertDeleteType: UITextSmartInsertDeleteType {
            get { .no } set { }
        }

        // MARK: Hardware keyboard
        //
        // He works on an iPad with a Magic Keyboard, so the arrows, tab, escape and the
        // control chords are not decoration — they are how a shell is actually driven.
        // History with the up arrow is the single most used key at any prompt.

        override var keyCommands: [UIKeyCommand]? {
            var commands: [UIKeyCommand] = [
                UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(up)),
                UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(down)),
                UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(left)),
                UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(right)),
                UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(esc)),
                UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tab)),
                // The Magic Keyboard's Delete. Without this it is swallowed before
                // `deleteBackward` is ever reached on a non-text responder.
                UIKeyCommand(input: "\u{8}", modifierFlags: [], action: #selector(backspace)),
                UIKeyCommand(input: "\u{7F}", modifierFlags: [], action: #selector(backspace)),
            ]
            // Ctrl-A … Ctrl-Z as their real control codes.
            for scalar in UnicodeScalar("a").value...UnicodeScalar("z").value {
                let letter = String(UnicodeScalar(scalar)!)
                commands.append(UIKeyCommand(input: letter,
                                             modifierFlags: .control,
                                             action: #selector(control(_:))))
            }
            commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
            return commands
        }

        @objc private func up() { onBytes?("\u{1B}[A") }
        @objc private func down() { onBytes?("\u{1B}[B") }
        @objc private func right() { onBytes?("\u{1B}[C") }
        @objc private func left() { onBytes?("\u{1B}[D") }
        @objc private func esc() { onBytes?("\u{1B}") }
        @objc private func tab() { onBytes?("\t") }
        @objc private func backspace() { sendDelete() }

        @objc private func control(_ command: UIKeyCommand) {
            guard let letter = command.input?.uppercased().unicodeScalars.first,
                  letter.value >= 64, letter.value <= 95 else { return }
            onBytes?(String(UnicodeScalar(UInt8(letter.value - 64))))
        }
    }
}
