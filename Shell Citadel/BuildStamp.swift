//
//  BuildStamp.swift
//  Shell Citadel
//
//  ⚠️ THE VALUES BELOW ARE REWRITTEN BY `Scripts/stamp-build.sh`. Do not hand-edit them.
//
//  WHY THIS FILE EXISTS, 2026-09-04. Every build of this app reported itself as
//  "1.0 (1)" — MARKETING_VERSION and CURRENT_PROJECT_VERSION have never changed — so
//  there was no way, from a device, to tell which build was installed on it. That cost
//  a full day: an iPad kept working while three phones did not, and the difference
//  between them could not be named. Michael: "we need to get the github number in a
//  debugging display to see on the app."
//
//  WHY IT IS A GENERATED SOURCE FILE AND NOT A BUILD PHASE. The obvious approach is a
//  Run Script phase that writes the commit into Info.plist. This project has
//  ENABLE_USER_SCRIPT_SANDBOXING = YES, which would block that script from reading
//  .git and writing into the built product. Turning the sandbox off to gain a debug
//  label would be trading a real security setting for a convenience, so the stamp is
//  generated BEFORE the build instead of during it.
//
//  WHAT THE VALUES MEAN. `commit` is the short SHA of HEAD at the moment the stamp was
//  generated; a trailing "+" means the working tree had uncommitted changes, so the
//  binary is that commit PLUS something unrecorded. `built` is when the stamp was
//  generated, which is within seconds of the build that carries it.

enum BuildStamp {
    /// Short SHA of HEAD when this build was stamped. "+" suffix = uncommitted changes.
    static let commit = "68c0c9d+"

    /// Branch HEAD was on when this build was stamped.
    static let branch = "location-only-on-pin-drop"

    /// Local time the stamp was generated — effectively the build time.
    static let built = "2026-09-04 05:42"

    /// One line for a cramped display: `b958b3d · 09-04 05:40`.
    static var short: String { "\(commit) · \(built)" }

    /// True when the running binary was never stamped — an older build, or one built
    /// without the script. Worth showing differently, because "unstamped" is itself
    /// the answer to "which build is this": an old one.
    static var isStamped: Bool { commit != "unstamped" }
}
