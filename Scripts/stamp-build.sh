#!/bin/sh
# Sets the app's BUILD NUMBER, and records the commit that produced it.
#
# RUN THIS IMMEDIATELY BEFORE BUILDING.
#
# ─── THE BUILD NUMBER IS THE GIT COMMIT COUNT ───────────────────────────────────
# Michael, 2026-09-04: "lets make that number the build number of the app from now on
# so it is uniform viewable in the app in xcode and app store connect. legally without
# it being a debugging artifact that flags rejection."
#
# The SHA itself cannot be the build number, and neither can its base-10 conversion.
# CFBundleVersion must be period-separated NON-NEGATIVE INTEGERS, and App Store Connect
# requires each upload's build number to be HIGHER than the last one in that version
# train. A SHA is a hash: 0x68c0c9d is 109841565, but the next commit could hash to
# something smaller, and Apple would refuse the upload.
#
# ⚠️ AND MICHAEL WAS RIGHT WHERE I WAS WRONG. He said git's number "has to increase and
# not go down becaue it has to be a counter number" — and git HAS one:
#
#     git rev-list --count HEAD
#
# The commit count. It increments by exactly one per commit, it never goes down on a
# branch, it is an integer, and it names a specific commit. It satisfies Apple's
# monotonic rule and stays tied to the repository, which the date only faked. Using it
# as CFBundleVersion is long-standing iOS practice, not a workaround.
#
#   Build 95  ->  commit 68c0c9d
#
# The count answers "is this newer?", the SHA answers "which commit exactly?", and the
# About sheet shows both so either question can be answered from the device.
#
# It is ordinary version metadata, not a debug artifact, so it carries no review risk.
#
# ⚠️ ONE PROPERTY TO KNOW: the count is per-branch. Commits made on a side branch and
# merged later can make two different builds share a number. On this repo's single
# working branch that does not arise, and the SHA disambiguates it if it ever does.
#
# ─── WHY THIS IS NOT AN XCODE BUILD PHASE ───────────────────────────────────────
# This project sets ENABLE_USER_SCRIPT_SANDBOXING = YES. A sandboxed Run Script phase
# cannot read .git or write into the built product. Turning that setting off to gain a
# version label would trade a real security boundary for a convenience, so the stamp is
# generated first and compiled in like any other source.
#
# Absolute path to git: a script does not inherit an interactive shell's PATH.
set -e
GIT=/usr/bin/git
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

BUILD_NUMBER=$($GIT rev-list --count HEAD 2>/dev/null || echo 1)

COMMIT=$($GIT rev-parse --short HEAD 2>/dev/null || echo "nogit")
BRANCH=$($GIT rev-parse --abbrev-ref HEAD 2>/dev/null || echo "nogit")

# A dirty tree means the binary is that commit PLUS something unrecorded. Say so — a
# stamp that claims a clean commit it isn't is worse than no stamp. The two files this
# script rewrites must not count as dirt.
DIRT=$($GIT status --porcelain -- . \
        ':!Shell Citadel/BuildStamp.swift' \
        ':!Shell Citadel.xcodeproj/project.pbxproj' 2>/dev/null)
if [ -n "$DIRT" ]; then
    COMMIT="${COMMIT}+"
fi

BUILT=$(date "+%Y-%m-%d %H:%M")

# 1. The build number itself — this is the value Xcode and App Store Connect show.
/usr/bin/sed -i '' \
    -e "s|CURRENT_PROJECT_VERSION = .*;|CURRENT_PROJECT_VERSION = $BUILD_NUMBER;|" \
    "$ROOT/Shell Citadel.xcodeproj/project.pbxproj"

# 2. The commit behind it, for the About sheet.
/usr/bin/sed -i '' \
    -e "s|static let commit = \".*\"|static let commit = \"$COMMIT\"|" \
    -e "s|static let branch = \".*\"|static let branch = \"$BRANCH\"|" \
    -e "s|static let built = \".*\"|static let built = \"$BUILT\"|" \
    "$ROOT/Shell Citadel/BuildStamp.swift"

echo "build number: $BUILD_NUMBER   commit: $COMMIT ($BRANCH)"
