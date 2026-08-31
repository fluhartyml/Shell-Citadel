//
//  SpokenOutput.swift
//  Shell Citadel
//
//  READ IT OUT LOUD AS IT ARRIVES.
//
//  Michael, 2026-08-31 16:02: "If citadel says everything the server puts on the screen
//  it covers if claude says anything via the terminal and being hands free i can talk
//  back."
//
//  That is a better shape than the one built an hour earlier. The Siri intents PULL —
//  you have to ask to be caught up. This PUSHES: output speaks itself the moment it
//  lands, so the loop closes without him asking for each half of it.
//
//  ⭐ WHY IT MATTERS MORE THAN CONVENIENCE. On 2026-08-29 he spent thirty-five minutes
//  alone at 183–208 bpm. At that rate typing is hard and talking is not. A terminal that
//  speaks and listens is the difference between reaching someone and not.
//
//  ⚠️ THIS IS NOT THE SIRI VOICE, AND THE DIFFERENCE IS NOT COSMETIC.
//
//  Apple does not expose Siri's voices to third-party synthesis. AVSpeechSynthesizer can
//  use any voice the user has DOWNLOADED — including Enhanced and Premium ones, which
//  are good — but not Siri's. Siri's own voice is reachable only by returning an
//  IntentDialog from an App Intent, which is why `VoiceIntents.swift` is not made
//  redundant by this file. Two mechanisms, two voices, on purpose.
//
//  He spent an afternoon on 2026-08-31 trying to reach one specific voice. Do not let a
//  future session tell him this file delivers it.
//
//  ⚠️ FOREGROUND ONLY, DELIBERATELY. Speaking with the app backgrounded or the screen
//  locked needs the `audio` background mode in Info.plist, which is a claim about the
//  app that App Review reads closely and which changes how the app behaves for everyone.
//  Not added on a guess. → open question in ROADMAP.md.
//
//  ⚠️ AND IT IS PER-DEVICE. His call, 16:02 and again at 15:55: the slider sheet rather
//  than the connection sheet, because whether the room is quiet is a fact about the
//  DEVICE, not about the Mac being talked to. On in bed on the phone; off on the iPad
//  with someone in the room. UserDefaults is per-device and is exactly right here.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

@MainActor
final class SpokenOutput: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    /// ⚠️ TRUE WHILE THE APP IS TALKING, and the microphone MUST be deaf while it is.
    ///
    /// HIS BUG, 2026-08-31 18:18, and it arrived as the strangest possible symptom: my
    /// own reply came back to me as his next message, word for word. Speaker on,
    /// microphone on, no headphones — the phone spoke, heard itself, transcribed itself
    /// and sent it. A conversation with nobody in it.
    ///
    /// AirPods hide this, which is worse than it failing outright: it would have worked
    /// perfectly in testing and looped the first time he set the phone down.
    @Published private(set) var isSpeaking = false

    static let shared = SpokenOutput()

    private let synthesizer = AVSpeechSynthesizer()

    private enum Key {
        static let enabled = "spokenOutputEnabled"
        static let voice = "spokenOutputVoiceIdentifier"
    }

    /// Off by default. A terminal that starts talking the first time it is opened, in
    /// whatever room it was opened in, is a bad surprise — and this one is likely to be
    /// opened somewhere quiet.
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Key.enabled)
            if !isEnabled { stop() }
        }
    }

    /// Empty means "whatever the system picks for the current language".
    @Published var voiceIdentifier: String {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: Key.voice) }
    }

    override private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Key.enabled)
        voiceIdentifier = UserDefaults.standard.string(forKey: Key.voice) ?? ""
        super.init()
        synthesizer.delegate = self
    }

    private func unusedInit() {
        isEnabled = UserDefaults.standard.bool(forKey: Key.enabled)
        voiceIdentifier = UserDefaults.standard.string(forKey: Key.voice) ?? ""
    }

    // MARK: - Voices

    /// English voices installed on THIS device, best quality first.
    ///
    /// Sorted by quality rather than alphabetically because the difference between a
    /// premium voice and a compact one is the difference between listening to it for an
    /// hour and turning it off — and the good ones are the ones he has bothered to
    /// download.
    var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { a, b in
                if a.quality.rawValue != b.quality.rawValue {
                    return a.quality.rawValue > b.quality.rawValue
                }
                return a.name < b.name
            }
    }

    private var chosenVoice: AVSpeechSynthesisVoice? {
        if !voiceIdentifier.isEmpty,
           let exact = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            return exact
        }
        // No stored choice: take the best English voice on the device rather than the
        // compact default, which is the one that sounds like a robot.
        return availableVoices.first
    }

    // MARK: - Speaking

    /// Say a line, if speaking is on and there is anything worth saying.
    ///
    /// ⚠️ NOT EVERYTHING ON SCREEN IS SPEAKABLE, and pretending otherwise is how this
    /// feature becomes unusable. A prompt like `~ %`, a bare exit code, or a line of box
    /// drawing carries nothing to the ear and interrupts what is actually being read.
    /// Filtering is not a shortcut here — it is what makes the rest audible.
    func speak(_ text: String) {
        guard isEnabled else { return }
        let clean = Self.speakable(text)
        guard !clean.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = chosenVoice
        // No rate override. A downloaded voice has a cadence it was tuned for, and
        // forcing a number onto it makes it wobble — measured on the Mac the same day,
        // where 200 words a minute on a neural voice sounded like a tape with a slipping
        // belt. His words: "it sounds like its fighting its speed."
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    // MARK: - What is worth hearing

    /// Strip what cannot be heard and refuse what is not worth hearing.
    static func speakable(_ raw: String) -> String {
        // Escape sequences and control characters. Attach mode reads a plain-sentence
        // side channel precisely so this is rare, but direct-mode output can still carry
        // colour codes from a program that does not check whether it has a tty.
        var text = raw.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[A-Za-z]",
            with: "",
            options: .regularExpression)
        text = String(text.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        })
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return "" }

        // A shell prompt is not a sentence. Reading "tilde percent" after every command
        // is the fastest way to make someone turn this off.
        let promptOnly = text.range(of: "^[~\\w./@:-]{0,40}\\s*[%$#>]$",
                                    options: .regularExpression) != nil
        if promptOnly { return "" }

        // Nothing pronounceable in it at all — rules, box drawing, a row of dashes.
        guard text.rangeOfCharacter(from: .alphanumerics) != nil else { return "" }

        return text
    }
}
