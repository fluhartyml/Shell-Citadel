#!/bin/sh
# Rewrites Shell Citadel/BuildStamp.swift with the current commit and time.
#
# RUN THIS IMMEDIATELY BEFORE BUILDING. It is deliberately NOT an Xcode build phase:
# this project has ENABLE_USER_SCRIPT_SANDBOXING = YES, and a sandboxed phase cannot
# read .git or write into the built product. Rather than weaken that setting for a
# debug label, the stamp is generated first and compiled in like any other source.
#
# Absolute path to git: a build-time script does not inherit an interactive shell's
# PATH, and this has bitten this apartment before.
set -e
GIT=/usr/bin/git
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

COMMIT=$($GIT rev-parse --short HEAD 2>/dev/null || echo "nogit")
BRANCH=$($GIT rev-parse --abbrev-ref HEAD 2>/dev/null || echo "nogit")

# A dirty tree means the binary is that commit PLUS something unrecorded. Say so,
# because a stamp that claims a clean commit it isn't is worse than no stamp.
# BuildStamp.swift is itself rewritten by this script, so it must not count as dirt.
if [ -n "$($GIT status --porcelain -- . ':!Shell Citadel/BuildStamp.swift' 2>/dev/null)" ]; then
    COMMIT="${COMMIT}+"
fi

BUILT=$(date "+%m-%d %H:%M")
FILE="$ROOT/Shell Citadel/BuildStamp.swift"

/usr/bin/sed -i '' \
    -e "s|static let commit = \".*\"|static let commit = \"$COMMIT\"|" \
    -e "s|static let branch = \".*\"|static let branch = \"$BRANCH\"|" \
    -e "s|static let built = \".*\"|static let built = \"$BUILT\"|" \
    "$FILE"

echo "stamped: $COMMIT ($BRANCH) $BUILT"
