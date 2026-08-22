//
//  CommandField.swift
//  Shell Citadel
//
//  A text field that does not help.
//
//  WHY THIS EXISTS: SwiftUI's TextField exposes `.autocorrectionDisabled()` and
//  `.textInputAutocapitalization(.never)` — and that is not enough. The keyboard's
//  SMART PUNCTUATION is a separate set of behaviours, living on UITextInputTraits
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
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator

        applyTraits(to: field)
        field.returnKeyType = .send

        field.font = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                                           weight: .regular)
        field.adjustsFontForContentSizeCategory = true
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

    func updateUIView(_ field: UITextField, context: Context) {
        applyTraits(to: field)
        // Only write back when it actually differs, so the caret is not reset on
        // every keystroke as SwiftUI re-runs the body.
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        field.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let parent: CommandField

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
