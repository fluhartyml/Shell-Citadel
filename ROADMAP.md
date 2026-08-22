# Shell Citadel — chunks

Michael, 2026-08-22: *"im loosing interest in this project — but — in order for me to
keep interest i want to chunk it into managable pieces."*

Each chunk ends with something he can hold. No chunk depends on finishing the one
after it.

---

## 1 ✅ Talks to the Mac — DONE 2026-08-22
Connects over SSH, runs commands, prints real output, `cd` sticks, settings persist.
Nine commits. Verified by running: `who am i` and `ls` both answered from the phone.

## 2 It looks like yours
Icon built in Image Producer and installed. Light + dark, never tinted — his art, not
Claude's. Short, visual, and it makes the thing feel like a product instead of a test
harness. **Recommended next.**

## 3 It speaks the answer
Direct-mode output read aloud on the phone. No wake phrase yet, no microphone — just
run a command and hear the result with the screen off. This is the first moment the
app does something a normal SSH client does not.

## 4 You speak to it
Microphone, "hey claude" to start, "full stop" to finish. The wake phrase doubles as
barge-in. **Known problem to solve here:** dictated speech arrives punctuated and
spaced, and a shell wants exact characters — the app has to fix that, not the user.

## 5 It reaches the tmux session
Attach mode wired end to end: `send-keys` in, the voice file tailed out. This is the
one where he is talking to *Claude* from the phone rather than to a bare shell.
Needs the Mac side to write spoken text to a known file.

## 6 Ship it
App Store listing, the Haynes/Chilton-style manual covering the tmux upgrade path,
and the privacy story — no internet, no account, no server, which most remote-access
apps cannot say.

---

**Not in any chunk, deliberately:** interactive programs (vim, top, less) need a PTY,
and streaming output needs a different channel. Both are real limits, both are worth
stating rather than blurring, and neither blocks any chunk above.
