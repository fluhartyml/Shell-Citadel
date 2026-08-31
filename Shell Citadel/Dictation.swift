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
    @Published private(set) var partial = ""

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
    /// Half-second steps, 0.5 to 5, his ruling. Two seconds is the default because it
    /// is long enough to think mid-sentence and short enough not to feel broken.
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

    private func notice(_ sentence: String) {
        problem = sentence
        onNotice?(sentence)
    }

    private init() {
        let stored = UserDefaults.standard.double(forKey: Key.pause)
        pauseSeconds = stored > 0 ? stored : 2.0
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
            Task { @MainActor in self?.request?.append(buffer) }

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

    /// The pause elapsed. Hand over what was said and start listening for the next thing.
    private func commit() {
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        partial = ""
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
                if let result {
                    self.partial = result.bestTranscription.formattedString
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
