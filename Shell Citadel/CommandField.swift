//
//  CommandField.swift
//  Shell Citadel
//
//  A text field that does not help.
//
//  WHY THIS EXISTS: SwiftUI's TextField exposes `.autocorrectionDisabled()` and
//  `.textInputAutocapitalization(.never)` — and that is not enough. The keyboard's
//  SMART PUNCTUATION is a separate set of behaviors, living on UITextInputTraits
//  with no SwiftUI equivalent, and every one of them is wrong in a command field:
//
//    smartInsertDeleteType  — two spaces become ". ". This one bit Michael on the
//                             very first command sent from the phone: he typed
//                             `who am i` and the Mac received `who. am i?`.
//    smartQuotesType        — "  becomes “ ”. A shell does not know curly quotes;
//                             `echo "hi"` silently stops being a quoted string.
//    smartDashesType        — -- becomes —. Every long flag in existence breaks.
//
//  A helpful keyboard is a hostile one here. The whole job of this view is to hand
//  the shell the exact characters that were typed.
//
//  Also set: no capitalisation, no autocorrect, no predictive bar, and
//  `.asciiCapable` so the keyboard itself offers plain characters first.
//

import SwiftUI
import UIKit

/// A field that keeps HIS size for HIS text, and shrinks only the PLACEHOLDER.
///
/// Michael, 2026-09-03, opening the app cold on an iPhone 11 Pro: the one instruction
/// on screen read `ssh user@h…` — clipped one character into the thing it was trying
/// to teach. The string in the code is the whole `ssh user@host`; it never fit, because
/// this field draws at his configured terminal size (36pt) and thirteen monospace
/// characters at 36pt do not fit a phone row once the `+`, the `>` and the send arrow
/// have taken their width. He then typed the destination backwards — `host@user` — with
/// the example that would have told him the order sitting truncated above the keyboard.
///
/// ⚠️ ONLY THE PLACEHOLDER SHRINKS. His own typing stays at the size he chose: this is
/// the field he judges the app by (2026-08-30 09:53, "the font where i am typing is
/// where i see"), and text that resized itself mid-sentence would be a worse bug than
/// the one being fixed. The instant he types, his size is back.
final class FittingTextField: UITextField {
    /// Set instead of `placeholder`, because the fitted version is written as an
    /// attributed string and a later plain assignment would silently discard it.
    var placeholderText: String = "" {
        didSet { guard placeholderText != oldValue else { return }; refitPlaceholder() }
    }
    /// His configured terminal size — the ceiling. The placeholder is never drawn
    /// larger than this, only smaller when it has to be.
    var baseFontSize: Double = 36 {
        didSet { guard baseFontSize != oldValue else { return }; refitPlaceholder() }
    }

    /// What the last fit was computed against, so layout passes that change nothing
    /// do not rewrite the attributed string — which would schedule another layout.
    private var fittedFor: (text: String, size: Double, width: Double)?

    override func layoutSubviews() {
        super.layoutSubviews()
        refitPlaceholder()
    }

    private func refitPlaceholder() {
        guard !placeholderText.isEmpty else {
            attributedPlaceholder = nil
            fittedFor = nil
            return
        }
        let width = Double(placeholderRect(forBounds: bounds).width)
        // Before first layout there is no width to fit to. Leave it; layoutSubviews
        // runs again with a real one.
        guard width > 1 else { return }

        let key = (placeholderText, baseFontSize, width)
        if let done = fittedFor,
           done.text == key.0, done.size == key.1, abs(done.width - key.2) < 0.5 {
            return
        }

        let size = Self.sizeThatFits(placeholderText, in: width, startingAt: baseFontSize)
        attributedPlaceholder = NSAttributedString(
            string: placeholderText,
            attributes: [
                .font: Self.terminalFont(size),
                // UIKit's own placeholder grey. Named explicitly because supplying an
                // attributed placeholder replaces the default styling wholesale.
                .foregroundColor: UIColor.placeholderText
            ]
        )
        fittedFor = key
    }

    /// One measurement, not a loop: the face is monospaced, so width scales linearly
    /// with point size and the right answer is arithmetic.
    private static func sizeThatFits(_ string: String, in width: Double, startingAt base: Double) -> Double {
        let measured = Double((string as NSString)
            .size(withAttributes: [.font: terminalFont(base)]).width)
        guard measured > width, measured > 0 else { return base }
        // A hair under, so rounding cannot put the last glyph back over the edge.
        let fitted = base * (width / measured) * 0.98
        // Floor of 11pt matches the transcript's: an instruction too small to read is
        // no better than one that is cut off.
        return max(11, min(base, fitted))
    }

    private static func terminalFont(_ size: Double) -> UIFont {
        UIFont(name: TerminalFont.regular, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

struct CommandField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool
    /// `true` for Direct mode, where the text is a SHELL COMMAND and every keyboard
    /// convenience is a hazard. `false` for Attach mode, where the text is ENGLISH
    /// addressed to Claude — there, autocorrect, the predictive bar and the dictation
    /// microphone are the point, and switching them off was a mistake.
    ///
    /// Michael, 2026-08-22: "iphone keyboard needs suggestive text and dictation."
    /// He was typing sentences to me and I had given him a keyboard built for `ls`.
    var strict: Bool

    /// A counter the parent bumps to say "put the caret in here now".
    ///
    /// ⚠️ WHY A COUNTER AND NOT A BOOL. Michael, 2026-08-30 06:48, from the iPad:
    /// "The say something doesnt automatically take focus i have to tap before typing,
    ///  ive been typing paragraphs then i look down to send and no text"
    ///
    /// He is on a hardware keyboard. With no first responder, every keystroke goes
    /// nowhere — not to a background field, NOWHERE — so a paragraph he has already
    /// composed is simply gone, and he only finds out when he looks down. That is the
    /// same class of failure as the two Shell Citadel messages that died in wedged tmux
    /// processes: his words, destroyed by this side, discovered afterwards.
    ///
    /// A Bool cannot express "focus again" once it is already true — the second request
    /// is not a change and SwiftUI never re-runs. A monotonic counter always changes, so
    /// every request lands.
    var focusRequest: Int
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> FittingTextField {
        let field = FittingTextField()
        field.delegate = context.coordinator

        applyTraits(to: field)
        field.returnKeyType = .send

        // His desktop terminal face, not the system mono — the whole point is that what he
        // types here looks like what he types in Terminal.app. Falls back to the system
        // monospaced font if registration ever fails, so the field is never unreadable.
        // ⚠️ HIS SIZE, NOT DYNAMIC TYPE — AND THIS IS THE FIELD HE ACTUALLY JUDGES THE
        // APP BY. Michael, 2026-08-30 09:53: "the font where i am typing is where i see
        // and think you arnt changing the font because it never changed here."
        //
        // He is right, and I had fixed the wrong half. The transcript was moved onto his
        // configured `fontSize` minutes earlier and visibly changed; this line kept
        // sizing itself from `preferredFont(forTextStyle: .body)`, so the one piece of
        // text he looks at while typing stayed exactly as it was. From where he sits,
        // nothing had happened. Three rounds of "the font is not right" were about this
        // field.
        applyFont(to: field)
        field.adjustsFontForContentSizeCategory = false
        // The field must never DRIVE the layout's width. A UITextField's intrinsic
        // width grows with its content, and left alone it widened the whole column —
        // which stretched the transcript above it and cost those lines their wrapping.
        // Michael saw his own typing push my sentences out of shape.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        field.addTarget(context.coordinator,
                        action: #selector(Coordinator.textChanged(_:)),
                        for: .editingChanged)
        return field
    }

    /// Take the caret, but only when it can actually be taken.
    ///
    /// `becomeFirstResponder()` fails silently on a view that is not in a window yet,
    /// which is exactly where `makeUIView` runs — so this is called from `updateUIView`
    /// and hops to the next runloop turn, by which point the field is on screen.
    private func focus(_ field: UITextField, _ coordinator: Coordinator) {
        guard field.isEnabled else { return }
        DispatchQueue.main.async {
            guard field.window != nil, !field.isFirstResponder else { return }
            field.becomeFirstResponder()
        }
        coordinator.lastFocusRequest = focusRequest
    }

    /// One place, so creation and update cannot disagree. Floor of 11pt matches the
    /// transcript's: a slider dragged to nothing must not make his own typing invisible.
    private func applyFont(to field: UITextField) {
        let size = max(11, TerminalAppearance.shared.fontSize)
        field.font = UIFont(name: TerminalFont.regular, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        // The placeholder's ceiling is the same number, so the two can never disagree.
        (field as? FittingTextField)?.baseFontSize = size
    }

    /// Applied on creation AND on update, because the mode can change while the app
    /// is running and the keyboard must follow it.
    private func applyTraits(to field: UITextField) {
        if strict {
            // Direct mode: hand the shell exactly what was typed.
            //   smartInsertDeleteType — two spaces become ". "
            //   smartQuotesType       — " becomes a curly quote, breaking `echo "hi"`
            //   smartDashesType       — -- becomes an em dash, breaking every long flag
            field.smartInsertDeleteType = .no
            field.smartQuotesType = .no
            field.smartDashesType = .no
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
            field.spellCheckingType = .no
            field.inlinePredictionType = .no
            field.keyboardType = .asciiCapable
        } else {
            // Attach mode: this is prose for a human-facing conversation. Give back
            // the predictive bar, the dictation microphone, and ordinary correction.
            field.smartInsertDeleteType = .default
            field.smartQuotesType = .default
            field.smartDashesType = .default
            field.autocorrectionType = .default
            field.autocapitalizationType = .sentences
            field.spellCheckingType = .default
            field.inlinePredictionType = .default
            field.keyboardType = .default
        }
    }

    func updateUIView(_ field: FittingTextField, context: Context) {
        applyTraits(to: field)
        // So dragging the size slider moves this field too, live, like everything else.
        applyFont(to: field)
        // Only write back when it actually differs, so the caret is not reset on
        // every keystroke as SwiftUI re-runs the body.
        if field.text != text { field.text = text }
        field.placeholderText = placeholder
        field.isEnabled = isEnabled

        // ⚠️ ZERO MEANS NEVER TAKE THE CARET BY ITSELF, and that is not a default worth
        // losing. The dumb terminal has its OWN composer under a live PTY screen, and
        // there the keystrokes belong to the terminal — a field that grabs first
        // responder on appearance would swallow everything he types at the shell.
        // So auto-focus is opt-in: the conversation composer starts at 1, the dumb
        // terminal's passes 0 and behaves exactly as it did before.
        guard focusRequest > 0 else { return }
        if context.coordinator.lastFocusRequest != focusRequest {
            focus(field, context.coordinator)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let parent: CommandField
        /// The last request number acted on. Anything different is a fresh ask, and
        /// re-running the body with the same number must NOT re-grab the caret from
        /// something else he has tapped into.
        var lastFocusRequest = 0

        init(_ parent: CommandField) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            return false   // keep the keyboard up; the next command usually follows
        }
    }
}
