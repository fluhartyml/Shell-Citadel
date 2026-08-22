//
//  HostKeyTrust.swift
//  Shell Citadel
//
//  Trust-on-first-use for SSH host keys.
//
//  WHY THIS EXISTS AT ALL: Citadel ships `SSHHostKeyValidator.acceptAnything()`, and
//  its own doc comment says "not recommended for production use." Using it would mean
//  this app connects to whatever answers on that address — which is exactly the wrong
//  posture for a client meant to reach the Mac from outside the house over Tailscale.
//
//  WHAT THIS DOES INSTEAD, and what it does NOT do:
//    - First connection to a host: the key is recorded. That first moment is trusted
//      blindly, because there is nothing yet to compare against. That is the known
//      weakness of trust-on-first-use and it is not solved here.
//    - Every connection after: the key must match. If it changed, the connection is
//      REFUSED rather than repaired. A changed host key means either the server was
//      rebuilt or someone is standing in the middle, and this app cannot tell which.
//      Refusing and surfacing it is the fail-safe direction.
//
//  Storage is UserDefaults, holding a SHA-256 fingerprint — not a secret, just a value
//  to compare. It is tamperable by anything with access to the app container, which is
//  a real limit worth knowing rather than papering over.
//

import Foundation
import CryptoKit
import NIOCore
import NIOSSH

/// Thrown when a host presents a different key than the one recorded.
struct HostKeyChanged: Error, LocalizedError {
    let host: String
    let expected: String
    let received: String

    var errorDescription: String? {
        "The host key for \(host) has changed. Expected \(expected), got \(received). "
        + "Either the machine was rebuilt, or something is impersonating it. Not connecting."
    }
}

final class HostKeyTrust: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let host: String
    private let defaults: UserDefaults

    /// Set when a host is seen for the first time, so the UI can say so plainly
    /// rather than letting a blind trust pass silently.
    private(set) var didTrustOnFirstUse = false

    init(host: String, defaults: UserDefaults = .standard) {
        self.host = host
        self.defaults = defaults
    }

    private var storageKey: String { "hostkey.\(host)" }

    /// SHA-256 of the key's SSH wire format, base64 — the same shape OpenSSH prints.
    static func fingerprint(of key: NIOSSHPublicKey) -> String {
        var buffer = ByteBuffer()
        _ = key.write(to: &buffer)
        let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
        let digest = SHA256.hash(data: Data(bytes))
        return "SHA256:" + Data(digest).base64EncodedString()
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let received = Self.fingerprint(of: hostKey)

        guard let known = defaults.string(forKey: storageKey) else {
            // First sight. Record it and allow — the honest weak point of TOFU.
            defaults.set(received, forKey: storageKey)
            didTrustOnFirstUse = true
            validationCompletePromise.succeed(())
            return
        }

        if known == received {
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(
                HostKeyChanged(host: host, expected: known, received: received)
            )
        }
    }

    /// Deliberate, explicit reset — for when the machine really was rebuilt.
    /// Never called automatically: an app that quietly re-trusts a changed key
    /// has no host key checking at all.
    func forgetRecordedKey() {
        defaults.removeObject(forKey: storageKey)
    }
}
