//
//  FeedbackView.swift
//  Shell Citadel
//
//  Contact the developer — a bug report, a crash report, or a feature request,
//  pre-formatted into an email with the diagnostics already filled in.
//
//  Michael, 2026-09-01: "please put the contact developer with an emailed crash report
//  and how we did that for the other live apps in the app store and a feature request
//  gateway (maybe it sends a preformatted email?)"
//
//  ⭐ PORTED, NOT INVENTED. This follows the shape already shipping in CryoTunes Player,
//  Memory Aid LockBox and TakeAChanceOnMe: a type picker, a free-text box, a device-info
//  block appended automatically, and MFMailComposeViewController. Same structure so that
//  reports from every app of his arrive looking the same in his inbox.
//
//  ── ⛔ NO DIAGNOSTICS. THIS IS A PIPELINE, NOT A TELEMETRY CHANNEL ────────────────
//  Michael, 2026-09-01: "i dont want personal information. i just want a pipeline to
//  communicate with users."
//
//  The first cut of this file appended a device block — hardware model, iOS version,
//  free storage, locale — because that is what the other apps send and what bug reports
//  conventionally carry. HE CUT IT, and he is right to. Every one of those fields is
//  something about the PERSON, collected without them typing it, and none of it is worth
//  what it costs: an app that quietly harvests a profile in order to be helpful is the
//  thing this whole project keeps refusing to be.
//
//  ⭐ AND THEN THE CORRECTION THAT SETTLES IT: "the way its set up in the other apps is
//  the standard and we developed it in the past."
//
//  ⛔ SO THIS BLOCK MATCHES CryoTunes Player, Memory Aid LockBox and TakeAChanceOnMe
//  EXACTLY — app, device model, system, free storage, locale. It is not a fresh design
//  decision and must not be treated as one. It was worked out with him in an earlier
//  session, it ships in live apps, and reports from every app of his arrive looking the
//  same in his inbox because of it.
//
//  ⚠️ THE MISTAKE THIS COMMENT EXISTS TO PREVENT: I redesigned a settled standard from
//  first principles, cut fields, then asked him to re-decide each one. He had already
//  decided. **A pattern already shipping in his live apps is an answer, not a question.**
//  Check the other apps before inventing.
//
//  THE ONE GENUINE DIFFERENCE, and it is additive rather than a redesign: this app is a
//  TERMINAL. Host, username, port, tmux session, remote paths and the Keychain password
//  are NOT in this email and must never be — those are the machines the user connects to,
//  not their phone. The other apps have no equivalent to leave out.
//
//  ⭐ AND HIS REASON FOR IT, which is not the one I assumed: "it makes the email look
//  official." The block is not only debugging data — it is a SIGNAL TO THE SENDER. A bare
//  paragraph typed into a mail app feels like shouting into a void; the same paragraph
//  under a formatted header reads like a filed report, and people write better reports
//  and expect a reply when it looks like somewhere real to send one.
//
//  ⚠️ SO DO NOT "TIDY" THIS BLOCK AWAY on the grounds that a field is not strictly
//  needed for debugging. Its usefulness is partly in how it LOOKS to the person sending
//  it, and that function does not show up in a list of what the developer will act on.
//
//  ⚠️ NOTHING IS SENT SILENTLY. MFMailComposeViewController shows the whole message,
//  diagnostics included, and they can edit or delete any of it before tapping Send.
//

import SwiftUI
import MessageUI
import UIKit

struct FeedbackView: View {

    /// What went wrong, or what he wants. Set by whichever button opened this sheet.
    var initialType: FeedbackType = .bug

    @Environment(\.dismiss) private var dismiss
    @State private var feedbackType: FeedbackType = .bug
    @State private var feedbackText = ""
    @State private var showingMailSheet = false
    @State private var showingMailUnavailable = false

    enum FeedbackType: String, CaseIterable, Identifiable {
        case bug = "Bug Report"
        case crash = "Crash Report"
        case feature = "Feature Request"
        var id: String { rawValue }
    }

    /// ⚠️ MODEL IDENTIFIER, NOT A DEVICE NAME. `utsname().machine` gives "iPhone17,5" —
    /// the hardware model. It is deliberately NOT `UIDevice.current.name`, which on many
    /// phones is literally the owner's first name.
    private var deviceModel: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingCString: $0) ?? "Unknown" }
        }
    }

    /// The standard block, same fields and same order as his other live apps.
    private var deviceInfo: String {
        let device = UIDevice.current
        let storage: String = {
            guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
                  let free = attrs[.systemFreeSize] as? Int64 else { return "Unknown" }
            return ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
        }()
        return """

        --- Device Info ---
        App: Shell Citadel \(version)
        Device: \(deviceModel)
        System: \(device.systemName) \(device.systemVersion)
        Storage Available: \(storage)
        Locale: \(Locale.current.identifier)
        """
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $feedbackType) {
                        ForEach(FeedbackType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextEditor(text: $feedbackText)
                        .frame(minHeight: 160)
                        .overlay(alignment: .topLeading) {
                            if feedbackText.isEmpty {
                                Text(placeholder)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text(headerText)
                } footer: {
                    // Says plainly what leaves the phone — and here that is a short list.
                    Text("Sends your message with your app version, device model, iOS version, free storage and locale. You see the whole email before it sends. Nothing about the machines you connect to is included.")
                }

                Section {
                    Button {
                        if MFMailComposeViewController.canSendMail() {
                            showingMailSheet = true
                        } else {
                            showingMailUnavailable = true
                        }
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Contact the Developer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingMailSheet) {
                MailComposeView(
                    subject: "Shell Citadel \(feedbackType.rawValue) — \(version)",
                    body: composedBody,
                    recipient: "michael.fluharty@mac.com"
                )
            }
            .alert("Mail Not Available", isPresented: $showingMailUnavailable) {
                Button("OK") { }
            } message: {
                Text("Set up a mail account in Settings, or write to michael.fluharty@mac.com directly.")
            }
            .onAppear { feedbackType = initialType }
        }
    }

    private var headerText: String {
        switch feedbackType {
        case .bug:     return "What happened?"
        case .crash:   return "What were you doing when it quit?"
        case .feature: return "What would you like it to do?"
        }
    }

    private var placeholder: String {
        switch feedbackType {
        case .bug:     return "What you did, what happened, and what you expected instead."
        case .crash:   return "What you were doing when the app quit, and whether it happens every time."
        case .feature: return "Describe the feature and what it would let you do."
        }
    }

    /// ⚠️ A CRASH REPORT NEEDS THE STEPS, NOT JUST THE STACK. iOS already sends Apple the
    /// crash log; what Apple cannot send is what the person was doing. That is the only
    /// thing this email can add, so the opener asks for it directly.
    private var opener: String {
        switch feedbackType {
        case .bug:
            return "Thank you for using Shell Citadel. Tell me what went wrong and I will see what I can do."
        case .crash:
            return "Thank you for using Shell Citadel. Tell me what you were doing when it quit — the steps matter more than the crash itself, because iOS already sends me the crash log but cannot tell me what led to it."
        case .feature:
            return "Thank you for using Shell Citadel. Tell me what you would like it to do and I will see what I can do."
        }
    }

    private var composedBody: String {
        """
        \(opener)


        \(feedbackText)


        \(deviceInfo)
        """
    }
}

/// Wraps `MFMailComposeViewController` so SwiftUI can present it. Identical in shape to
/// the one in CryoTunes Player, deliberately — same behaviour, same dismissal.
struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let recipient: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            dismiss()
        }
    }
}
