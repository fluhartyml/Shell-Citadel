//
//  VoiceIntents.swift
//  Shell Citadel
//
//  HANDS FREE. Michael, 2026-08-31: "Use shell citadel hands free" — and, one message
//  earlier, "Can siri intents work?" He answered his own question; this is that answer
//  built.
//
//  ⭐ WHY APP INTENTS AND NOT A MICROPHONE IN THIS APP.
//
//  The obvious build is a wake word and a listening loop inside Shell Citadel. It is
//  the wrong build, for reasons that are the platform's and not ours:
//
//    • iOS has NO public wake-word API. You would be shipping your own keyword spotter.
//    • Background microphone access is gated hard. "Always listening with the screen
//      off" is the part that cannot be assumed.
//    • And the speaking half is worse. On 2026-08-31 the Mac's `say` began aborting
//      because the Siri neural voice model lives in a Group Container the calling
//      process cannot read. An afternoon went into it and the voice he actually wanted
//      was never reachable.
//
//  App Intents hand all three back for free: Siri IS the wake word, Siri does the
//  transcription, and an IntentDialog is SPOKEN BY SIRI IN THE SYSTEM VOICE — the exact
//  voice that was unreachable on the Mac. This app never touches a speech model.
//
//  ⚠️ LATENCY IS THE ARCHITECTURE, NOT A DETAIL.
//
//  Siri intents are turn-based and they time out. A reply from Claude takes seconds to
//  tens of seconds. So NOTHING here waits for Claude to answer. `Send` delivers and
//  confirms delivery; `CatchUp` reads what has arrived since. Two short round trips
//  instead of one long one that fails intermittently — and intermittent is worse than
//  broken, because it gets trusted.
//
//  This mirrors what the app already does: the voice channel is TAILED, never awaited.
//
//  ⚠️ AND EVERY INTENT OPENS ITS OWN CONNECTION. An intent may run while the app is not
//  in the foreground, so there is no live session to borrow. Each one connects, does one
//  thing, and closes. That is why they are all small.
//

import AppIntents
import Foundation

// MARK: - The connection, as something Siri can name

/// A saved connection, exposed so a spoken phrase can say WHICH machine.
///
/// The library is the source of truth (`ConnectionLibrary.shared`); this is a thin
/// mirror of it for the intent system, holding an id and a name and nothing else. No
/// credential ever crosses into this type.
struct ConnectionEntity: AppEntity {

    var id: UUID
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Connection")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var defaultQuery = ConnectionQuery()
}

/// Lets Siri list the saved connections and match one by spoken name.
///
/// `EntityStringQuery` is the half that matters for speech: without it, "send to my
/// mac" cannot resolve, and the user is made to disambiguate from a list every time —
/// which is not hands free.
struct ConnectionQuery: EntityStringQuery {

    @MainActor
    private func all() -> [ConnectionEntity] {
        ConnectionLibrary.shared.connections
            .filter { $0.isComplete }
            .map { ConnectionEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ConnectionEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ConnectionEntity] {
        all()
    }

    /// Spoken matching. Case-insensitive contains rather than equality, because Siri
    /// transcribes "my mac" for a connection saved as "My Mac" and a strict match would
    /// fail on the capital letters alone.
    @MainActor
    func entities(matching string: String) async throws -> [ConnectionEntity] {
        let needle = string.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all() }
        return all().filter { $0.name.lowercased().contains(needle) }
    }
}

// MARK: - Shared plumbing

enum VoiceIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noConnections
    case notFound
    case noPassword(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noConnections:
            "There are no saved connections yet. Open Shell Citadel and add one first."
        case .notFound:
            "I could not find that connection."
        case .noPassword(let name):
            "There is no saved password for \(name). Open Shell Citadel and connect once by hand first."
        }
    }
}

enum VoiceIntentBridge {

    /// Resolve the connection to act on: the one named, or the only one saved.
    ///
    /// Falling back to "the only one" is deliberate. Most people who buy this have one
    /// Mac, and making them say its name every time is the difference between hands free
    /// and dictation with extra steps.
    @MainActor
    static func profile(named entity: ConnectionEntity?) throws -> ConnectionProfile {
        let saved = ConnectionLibrary.shared.connections.filter { $0.isComplete }
        guard !saved.isEmpty else { throw VoiceIntentError.noConnections }
        guard let entity else {
            guard saved.count == 1, let only = saved.first else { throw VoiceIntentError.notFound }
            return only
        }
        guard let match = saved.first(where: { $0.id == entity.id }) else {
            throw VoiceIntentError.notFound
        }
        return match
    }

    /// Connect, do one thing, close. Always closes, including on the way out of a throw —
    /// an intent that leaks an SSH connection would leave one behind every time Siri is
    /// used, and nothing in the UI would ever show it.
    static func withSession<T>(_ profile: ConnectionProfile,
                               _ body: (SSHSession) async throws -> T) async throws -> T {
        guard let password = CredentialStore.password(for: profile) else {
            throw VoiceIntentError.noPassword(profile.name)
        }
        let session = SSHSession()
        try await session.connect(to: profile.destination, password: password)
        do {
            let result = try await body(session)
            await session.close()
            return result
        } catch {
            await session.close()
            throw error
        }
    }

    /// Siri SPEAKS whatever comes back, so a wall of terminal output is a punishment.
    /// Trim it to something a person can hear, and say plainly that it was trimmed
    /// rather than stopping mid-sentence and letting them think that was the answer.
    static func speakable(_ raw: String, limit: Int = 600) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "It ran, and returned nothing." }
        guard text.count > limit else { return text }
        let cut = String(text.prefix(limit))
        return cut + "… That is the first part. The rest is on screen in Shell Citadel."
    }
}

// MARK: - Send

/// Say something to the machine without touching the keyboard.
///
/// In ATTACH mode this pastes into the tmux session exactly as the app's own composer
/// does, tag and all, so Claude cannot tell a spoken message from a typed one.
/// In DIRECT mode there is no session to type into, so the text is run as a command and
/// the output is spoken back — which is the honest behaviour for that mode rather than
/// pretending a conversation exists.
struct SendToShellCitadelIntent: AppIntent {

    static var title: LocalizedStringResource = "Send a Message"

    static var description = IntentDescription(
        "Sends a line to a saved connection without opening the app.",
        categoryName: "Terminal"
    )

    /// Deliberately false. The whole point is that this works with the phone locked and
    /// the app closed; opening the app would defeat it.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Message", requestValueDialog: "What should I send?")
    var message: String

    @Parameter(title: "Connection")
    var connection: ConnectionEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$message) to \(\.$connection)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let profile = try VoiceIntentBridge.profile(named: connection)
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .result(dialog: "There was nothing to send.")
        }

        switch profile.mode {
        case .attach:
            try await VoiceIntentBridge.withSession(profile) { session in
                try await session.send(text)
            }
            // NOT "here is the answer" — the answer has not been written yet. Confirming
            // DELIVERY is the honest thing an intent can promise inside its timeout.
            return .result(dialog: "Sent. Ask me to catch you up when you want the reply.")

        case .direct:
            let output = try await VoiceIntentBridge.withSession(profile) { session in
                try await session.run(text)
            }
            return .result(dialog: IntentDialog(stringLiteral: VoiceIntentBridge.speakable(output)))
        }
    }
}

// MARK: - Catch up

/// Read back what has arrived since — the other half of a conversation that cannot
/// happen inside one intent.
///
/// It reads the tail of the voice file rather than the terminal, because that file is
/// plain sentences by construction. A redraw stream full of escape codes cannot be
/// spoken, which is the same reason attach mode has a side channel at all.
struct CatchUpIntent: AppIntent {

    static var title: LocalizedStringResource = "Catch Me Up"

    static var description = IntentDescription(
        "Reads aloud the most recent lines from the connection's spoken-text file.",
        categoryName: "Terminal"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Connection")
    var connection: ConnectionEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Catch me up from \(\.$connection)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let profile = try VoiceIntentBridge.profile(named: connection)

        let path = profile.voicePath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            return .result(dialog: "No spoken-text file is set for \(profile.name).")
        }

        // ⚠️ THE PATH IS LEFT UNQUOTED ON PURPOSE: it is a user setting that routinely
        // begins with `~`, and quoting it would stop the shell expanding the home
        // directory — the file would silently never be found. It is the user's own
        // machine and their own setting.
        let output = try await VoiceIntentBridge.withSession(profile) { session in
            try await session.run("tail -c 1200 \(path) 2>/dev/null")
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Nothing new has been written yet.")
        }
        return .result(dialog: IntentDialog(stringLiteral: VoiceIntentBridge.speakable(trimmed)))
    }
}

// MARK: - Run a command

/// The plain terminal case: run something and hear the answer.
///
/// Separate from Send because the two mean different things and merging them would make
/// the spoken phrases ambiguous. "Send" is a message to whatever is listening; "run" is
/// a command to the shell.
struct RunCommandIntent: AppIntent {

    static var title: LocalizedStringResource = "Run a Command"

    static var description = IntentDescription(
        "Runs a shell command on a saved connection and reads the answer back.",
        categoryName: "Terminal"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Command", requestValueDialog: "What should I run?")
    var command: String

    @Parameter(title: "Connection")
    var connection: ConnectionEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$command) on \(\.$connection)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let profile = try VoiceIntentBridge.profile(named: connection)
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .result(dialog: "There was no command to run.")
        }
        let output = try await VoiceIntentBridge.withSession(profile) { session in
            try await session.run(text)
        }
        return .result(dialog: IntentDialog(stringLiteral: VoiceIntentBridge.speakable(output)))
    }
}

// MARK: - The spoken phrases

/// ⚠️ EVERY PHRASE MUST CONTAIN `\(.applicationName)`. Siri requires the app name in the
/// utterance; a phrase without it is silently dropped, and the shortcut appears to work
/// everywhere except by voice — which is the only place it was for.
///
/// The phrasings are deliberately plain and several per intent, because a person in bed
/// at three in the morning does not remember which wording was blessed.
struct ShellCitadelShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendToShellCitadelIntent(),
            phrases: [
                "Send a message with \(.applicationName)",
                "Tell \(.applicationName) to send a message",
                "Send this with \(.applicationName)"
            ],
            shortTitle: "Send a Message",
            systemImageName: "paperplane"
        )
        AppShortcut(
            intent: CatchUpIntent(),
            phrases: [
                "Catch me up with \(.applicationName)",
                "What is new in \(.applicationName)",
                "Read \(.applicationName) to me"
            ],
            shortTitle: "Catch Me Up",
            systemImageName: "ear"
        )
        AppShortcut(
            intent: RunCommandIntent(),
            phrases: [
                "Run a command with \(.applicationName)",
                "Run something on \(.applicationName)"
            ],
            shortTitle: "Run a Command",
            systemImageName: "terminal"
        )
    }
}
