//
//  Diagnosis.swift
//  Shell Citadel
//
//  Turning a library's error into a sentence a person can act on.
//
//  Michael, 2026-08-23, after locking his phone on the way in from the porch. His
//  transcript read:
//
//      Voice channel stopped: The operation couldn't be completed.
//      (NIOSSH.NIOSSHError error 1.)
//
//  Nothing in that line tells him what happened, whether it was his fault, or what to
//  do. What actually happened is ordinary and expected: iOS suspended the app when the
//  screen locked, so the SSH connection closed. The app already handles it — it marks
//  itself disconnected and reconnects when he comes back. The only broken part was the
//  telling.
//
//  This is the third time the same shape has bitten. `CommandFailed error 1` was really
//  "command not found" (2026-08-22). `error 1` again here. A raw error code reaching the
//  transcript is a bug in its own right, not a detail — he reads this on a phone, often
//  with no other screen, and an error he cannot parse is the same as no error at all.
//
//  RULE: never put `error.localizedDescription` straight into the transcript. Route it
//  through here. Where the underlying text is genuinely useful it is kept; where it says
//  nothing it is replaced by something that does.
//

import Foundation

enum Diagnosis {

    /// A sentence for the transcript, given an error and what was being attempted.
    static func sentence(for error: Error, while activity: Activity) -> String {
        // Our own errors are already written for a person — pass them through.
        if let known = error as? SSHSessionError {
            return known.errorDescription ?? activity.genericFailure
        }

        if isConnectionLost(error) {
            return activity.connectionLost
        }

        // Anything else: keep the real text, but say what it was doing when it failed,
        // because "The operation couldn't be completed" alone identifies nothing.
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? activity.genericFailure : "\(activity.prefix) \(detail)"
    }

    /// What Claude was doing, so the sentence can say something specific.
    enum Activity {
        case connecting
        case sending
        case listening

        var connectionLost: String {
            switch self {
            case .connecting:
                "Could not reach the remote server. It may be asleep, off this network, or SSH may be off."
            case .sending:
                "The connection dropped, so that message was not delivered. Tap Connect to try again."
            case .listening:
                // The ordinary case, and the one he hit: the screen locked, iOS suspended
                // the app, the socket closed. Nothing is lost — the tmux session on the
                // Mac kept running and the replies file kept growing.
                "The connection dropped — replies will resume from where you left off when you reconnect."
            }
        }

        var genericFailure: String {
            switch self {
            case .connecting: "Could not connect."
            case .sending:    "That message could not be sent."
            case .listening:  "The replies channel stopped."
            }
        }

        var prefix: String {
            switch self {
            case .connecting: "Could not connect:"
            case .sending:    "Could not send that:"
            case .listening:  "The replies channel stopped:"
            }
        }
    }

    /// Whether an error means "the pipe is gone" rather than "the far end said no".
    ///
    /// Deliberately matched on the SHAPE rather than on a specific NIOSSH case: the
    /// package is pinned to an exact version today, but the point of this file is to stop
    /// library internals leaking into the transcript, and hard-coding an internal enum
    /// would be doing the same thing one layer down. `POSIXError` and `URLError` are here
    /// because a dropped Wi-Fi link surfaces as those, not as an SSH error.
    private static func isConnectionLost(_ error: Error) -> Bool {
        let ns = error as NSError

        if ns.domain == NSPOSIXErrorDomain {
            // 32 EPIPE · 54 ECONNRESET · 57 ENOTCONN · 60 ETIMEDOUT · 64 EHOSTDOWN · 65 EHOSTUNREACH
            return [32, 54, 57, 60, 64, 65].contains(ns.code)
        }
        if ns.domain == NSURLErrorDomain {
            return true
        }
        // NIOSSH and NIO channel errors carry no useful message and no stable public
        // code, so they are recognized by their domain rather than by a case.
        let domain = ns.domain.lowercased()
        return domain.contains("niossh") || domain.contains("nioc") || domain.contains("citadel")
    }
}
