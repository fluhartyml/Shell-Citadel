//
//  Dictation.swift
//  Shell Citadel
//
//  THE LISTENING HALF OF HANDS FREE.
//
//  Michael, 2026-08-31 17:31, overruling a design I had just argued for:
//  "the app is not armed to go hands free untill i tap both the speaker on and the
//  microphone."
//
//  I had proposed the microphone arming ITSELF whenever the app was open, on the
//  grounds that a tap is not hands free. He was right to overrule it. Arming is not
//  the part that has to be hands free — the CONVERSATION is. And a terminal that
//  starts listening the moment it is opened is a microphone you did not ask for.
//  Two deliberate taps, then it is his.
//
//  Then, 17:32: "does it type what i say and enter when i stop talking?" — yes, and
//  that is the whole interaction:
//
//      speak → words appear in the composer → you stop → it sends
//
//  ⚠️ THE PAUSE IS A SETTING, NOT A CONSTANT. 17:33: "should we have a sensitivity?"
//  Half-second steps from 0.5 to 5 (17:36), because anything finer is false precision
//  on a measurement of how long a person takes to think. It lives with the speech
//  settings and not behind a long press: it is set once and never touched again, and a
//  hidden gesture for that is a control nobody finds. He had already failed to find a
//  toggle sitting in plain sight two sheets down.
//
//  ⚠️ FOREGROUND ONLY, AND THIS IS A REAL LIMIT, NOT A DETAIL.
//  iOS will not keep a third-party microphone open with the screen locked without the
//  `audio` background mode, which is a claim about the app that App Review reads
//  closely. So this covers "app open, AirPods in". It does NOT cover the phone in a
//  pocket at three in the morning — that is what the Siri intents are for, and it is
//  why the two mechanisms are not redundant. → [[VoiceIntents]]
//
//  ⚠️ ON DEVICE. `SFSpeechRecognizer` is asked for on-device recognition explicitly.
//  Nothing said in this room goes to a server for transcription. That is not a nicety
//  in an app whose entire premise is that it talks to a machine the user already owns
//  with no account and no phone-home. → [[Connection]]
//

import AVFoundation
import AudioToolbox
import Combine
import Foundation
import Speech
import SwiftUI

@MainActor
final class Dictation: ObservableObject {

    static let shared = Dictation()

    /// Green when armed. Nothing is listening until this is true, and only a tap makes
    /// it true. See the note above about why it does not arm itself.
    @Published private(set) var isListening = false

    /// What has been heard so far in this utterance, shown live in the composer.
    ///
    /// ⚠️ DERIVED, NOT ASSIGNED, since 2026-09-02. It is `committed` + the run in flight.
    /// See `committed` for why.
    @Published private(set) var partial = ""

    /// ⚠️ HIS BUG, 2026-09-02: "when i say something then pause for a moment but not long
    /// enough to send it replaces my previous thoughts with the new ones."
    ///
    /// **The recogniser segments underneath us.** On-device recognition finalises after
    /// its own short silence — shorter than `pauseSeconds` — and the NEXT run starts its
    /// transcript over from empty. The old code assigned that fresh transcript straight
    /// into `partial`, so a mid-sentence pause did not merely fail to extend the
    /// sentence: **it erased the first half of it.**
    ///
    /// So one utterance is now potentially several runs. `committed` holds the runs that
    /// have already finalised; the callback only ever assigns the run in flight. Run
    /// boundaries stop being visible to him, which is the whole point — he was never
    /// starting a new thought, the microphone just thought he was.
    ///
    /// **This is why "leave the microphone on" did not help him:** the mic stayed open
    /// the entire time. It is the RECOGNISER that restarts, not the audio.
    private var committed = ""

    /// The live text: everything finalised this utterance, plus the run still going.
    private func recomposePartial(runText: String) {
        let joined = committed.isEmpty ? runText
                   : runText.isEmpty  ? committed
                   : committed + " " + runText
        partial = joined.trimmingCharacters(in: .whitespaces)
    }

    /// ⚠️ PROOF THAT SOUND IS ARRIVING, not a claim that it might be.
    ///
    /// His ask, 2026-08-31 18:13: "its green but not listening can it have a sound uv
    /// embellishment." A coloured button reports a FLAG — green because a variable is
    /// true — and it stays green while nothing whatsoever reaches the microphone. That is
    /// exactly what happened: see the tap below. This is measured off the live audio
    /// buffer, so a moving indicator means real sound is really arriving. It cannot be
    /// green and wrong.
    @Published private(set) var level: Double = 0

    private var lastLevelPublish = Date.distantPast

    /// The problem, in a sentence, when there is one. Shown rather than swallowed —
    /// a microphone that quietly does nothing is the worst version of this feature.
    @Published private(set) var problem: String?

    /// Seconds of silence that mean "I have finished talking."
    ///
    /// Half-second steps, 0.5 to 5, his ruling.
    ///
    /// ⚠️ DEFAULT CUT 2.0 → 1.5 ON 2026-09-02. His words: "Two seconds is an eternity."
    /// The default protects whoever never opens Settings, and the two failures are not
    /// symmetric: too long reads as SLOW, too short reads as BROKEN — fragmented
    /// half-sentences that look like the feature does not work. So the default errs long
    /// and the stepper takes it down. Clause pauses run 300–600 ms and sentence pauses
    /// 500–1000 ms, which puts 1.0 s at the top of the range where an ordinary
    /// think-mid-sentence pause starts getting clipped; 1.5 clears it with margin.
    /// He runs 1.0 on his own devices — he is not the default user.
    ///
    /// ⛔ This value must NOT be tuned to dodge the run-boundary wipe (see `partial`
    /// assignment below). That is a separate fault and gets fixed on its own merits.
    @Published var pauseSeconds: Double {
        didSet { UserDefaults.standard.set(pauseSeconds, forKey: Key.pause) }
    }

    private enum Key { static let pause = "dictationPauseSeconds" }

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?

    /// ⚠️ WHICH RECOGNITION RUN A CALLBACK BELONGS TO, and it is load-bearing.
    ///
    /// HIS BUG, 2026-08-31 18:08: "Sent twice… after you say once and pause for send it
    /// doesnt wait for your next sentence."
    ///
    /// `task.cancel()` does not stop the callback. The cancelled task still delivers a
    /// FINAL result afterwards, which refilled `partial` with the sentence just sent and
    /// restarted the silence clock — so the same words were committed a second time.
    /// Every callback now carries the generation it was created under and stale ones are
    /// dropped on the floor.
    private var generation = 0

    /// Called with the finished sentence when the pause elapses. The view owns what
    /// "send" means; this file only decides WHEN.
    var onUtterance: ((String) -> Void)?

    /// ⚠️ SAY WHAT WENT WRONG, IN THE TRANSCRIPT, WHERE HE IS ALREADY LOOKING.
    ///
    /// HIS BUG, 2026-08-31 18:12: "it didnt start listening after i pressed the red mic
    /// to tirn green then i said can you hear me nothing happened."
    ///
    /// The first version set a `problem` string that NOTHING EVER DISPLAYED. A microphone
    /// that fails quietly is the worst possible version of this feature — you cannot tell
    /// a denied permission from a missing model from a broken app, and you stand there
    /// talking to something that is not listening. This app exists partly because of
    /// exactly that failure shape elsewhere. → [[Diagnosis]]
    var onNotice: ((String) -> Void)?

    /// Called when an utterance ended with a cancel phrase, so the view can clear the
    /// composer rather than leaving half a discarded sentence sitting in it.
    var onCancelled: (() -> Void)?

    private func notice(_ sentence: String) {
        problem = sentence
        onNotice?(sentence)
    }

    private init() {
        let stored = UserDefaults.standard.double(forKey: Key.pause)
        pauseSeconds = stored > 0 ? stored : 1.5
    }

    // MARK: - Arming

    func toggle() {
        isListening ? stop() : start()
    }

    func start() {
        guard !isListening else { return }
        problem = nil

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.notice("Not listening: speech recognition is off for Shell Citadel. Settings → Privacy & Security → Speech Recognition.")
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.notice("Not listening: the microphone is off for Shell Citadel. Settings → Privacy & Security → Microphone.")
                            return
                        }
                        self.beginSession()
                    }
                }
            }
        }
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            notice("Not listening: speech recognition is not available right now.")
            return
        }

        // ⚠️ AVAILABLE IS NOT THE SAME AS ON-DEVICE. `requiresOnDeviceRecognition` fails
        // silently when the offline model for this language has never been downloaded —
        // the recogniser reports itself available and then simply never returns a result.
        // Say so rather than leaving a green microphone that hears nothing.
        guard recognizer.supportsOnDeviceRecognition else {
            notice("Not listening: this device has no offline speech model for English yet. It usually arrives with a keyboard dictation language download.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // `.playAndRecord` because the app is very likely SPEAKING at the same time
            // — that is the whole point of hands free — and `.record` alone would cut
            // the spoken replies off. `.duckOthers` keeps a podcast audible underneath
            // rather than stopping it.
            try session.setCategory(.playAndRecord,
                                    mode: .spokenAudio,
                                    options: [.duckOthers, .allowBluetooth, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            notice("Not listening: could not start the microphone. \(error.localizedDescription)")
            return
        }

        // ⚠️ THE AUDIO TAP. WITHOUT THIS NOTHING IS LISTENING, AND IT LOOKS FINE.
        //
        // I deleted this by accident while extracting `beginRecognitionRun`, and the
        // result was his 18:12 report: "its green but not listening." The recogniser
        // started, the button went green, the permission prompts appeared and were
        // granted — and no audio was ever fed in, so it sat there recognising silence.
        // Every visible signal said working.
        //
        // ⚠️ IT APPENDS TO `self.request`, NOT A CAPTURED ONE. The request is replaced
        // after every sentence; a captured reference would feed the FIRST request
        // forever and go deaf after one utterance.
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // ⚠️ DEAF WHILE THE APP IS TALKING. Without this the speaker feeds the
            // microphone and the app holds a conversation with itself — his 18:18 report,
            // where my own reply came back as his next message word for word.
            Task { @MainActor in
                guard let self, !SpokenOutput.shared.isSpeaking else { return }
                self.request?.append(buffer)
            }

            // Root mean square of the frame, which is loudness — the actual signal
            // rather than a proxy for it. Republished about ten times a second; per
            // buffer would redraw hundreds of times a second for motion the eye cannot
            // follow.
            guard let channel = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += channel[i] * channel[i] }
            let scaled = min(1.0, Double((sum / Float(n)).squareRoot()) * 12)
            Task { @MainActor in
                guard let self else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastLevelPublish) > 0.1 else { return }
                self.lastLevelPublish = now
                self.level = scaled
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            notice("Not listening: could not start the audio engine. \(error.localizedDescription)")
            teardown()
            return
        }

        beginRecognitionRun()

        isListening = true
        AudioServicesPlaySystemSound(1113)   // the system "begin recording" tone
        notice("Listening. Say something and it will send after a \(String(format: "%.1f", pauseSeconds))-second pause.")
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        teardown()
        isListening = false
        committed = ""
        partial = ""
        level = 0
        AudioServicesPlaySystemSound(1114)   // the matching "end recording" tone
    }

    private func teardown() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Knowing when he has finished

    private func restartSilenceClock() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: pauseSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.commit() }
        }
    }

    /// ⚠️ SAYING IT IS THE ONLY WAY TO TAKE IT BACK.
    ///
    /// His problem, 2026-08-31 18:34: "how to backspace", then "maybe how to cancel what
    /// I said." He had tried saying "backspace backspace backspace delete delete delete"
    /// and watched it transcribed as words, because this recogniser has no editing
    /// commands.
    ///
    /// Tapping the microphone off, fixing the box and tapping it back on is three actions
    /// to unsay one sentence — and the entire premise is that his hands are not
    /// available. **A hands-free feature needs a hands-free undo.** So the cancel is a
    /// phrase.
    ///
    /// Matched at the END, not anywhere, so "I said scratch that and he laughed" is still
    /// a sentence rather than a cancelled one. The phrase has to be the last thing said,
    /// which is what a person does when correcting themselves.
    static let cancelPhrases = [
        "scratch that", "cancel that", "never mind", "nevermind", "delete that", "forget that"
    ]

    /// True when the utterance ends with a phrase that means "unsay that".
    static func isCancelled(_ text: String) -> Bool {
        let t = text.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
        return cancelPhrases.contains { t == $0 || t.hasSuffix(" " + $0) }
    }

    /// The pause elapsed. Hand over what was said and start listening for the next thing.
    private func commit() {
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        // Both halves, or the next utterance opens carrying the last one's words.
        committed = ""
        partial = ""

        if Self.isCancelled(text) {
            onCancelled?()
            notice("Scratched.")
            restartRecognition()
            return
        }
        // ⚠️ A COUGH IS NOT A SENTENCE. A single stray syllable picked up from the room
        // should not be sent to a live shell. Two characters is a low bar deliberately —
        // "ls" is a real command — but it stops the empty and one-letter noise that a
        // room full of a television produces.
        guard text.count >= 2 else {
            restartRecognition()
            return
        }
        onUtterance?(text)
        restartRecognition()
    }

    /// Start one recognition run. Every callback it creates is stamped with the current
    /// generation, so results arriving from a run we have already moved past are ignored
    /// rather than treated as new speech.
    private func beginRecognitionRun() {
        guard let recognizer, recognizer.isAvailable else { return }

        generation += 1
        let mine = generation

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // ⚠️ ON DEVICE, EXPLICITLY. See the header.
        request.requiresOnDeviceRecognition = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, mine == self.generation, self.isListening else { return }
                if SpokenOutput.shared.isSpeaking {
                    // Anything captured while the app was talking is the app's own voice.
                    // ⚠️ Clears BOTH halves, which preserves the pre-2026-09-02 behaviour
                    // exactly. Making this pause-instead-of-destroy is his separate idea
                    // ("maybe we should pause the dictation and not destroy it") and is
                    // deliberately NOT bundled in with the run-boundary fix.
                    self.committed = ""
                    self.partial = ""
                    return
                }
                if let result {
                    let runText = result.bestTranscription.formattedString
                    if result.isFinal {
                        // This run is closed. Bank it and start the next one empty, so
                        // the words survive a pause he did not intend as a send.
                        self.committed = self.committed.isEmpty
                            ? runText
                            : self.committed + " " + runText
                        self.recomposePartial(runText: "")
                    } else {
                        self.recomposePartial(runText: runText)
                    }
                    // EVERY new word restarts the clock. The pause means "silence since
                    // the last word", not "time since I started talking" — otherwise a
                    // long sentence would send itself out from under him mid-thought.
                    self.restartSilenceClock()
                }
                if error != nil {
                    // A recognition error mid-flight is common and not worth a banner —
                    // the audio tap is still live, so simply start a fresh run.
                    self.restartRecognition()
                }
            }
        }
    }

    /// Fresh run for the next utterance, without dropping the microphone. Rebuilding the
    /// whole audio session between sentences would put a gap in the conversation.
    private func restartRecognition() {
        guard isListening else { return }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        // The generation bump inside beginRecognitionRun is what makes the cancelled
        // task's trailing final result harmless.
        beginRecognitionRun()
    }

}
