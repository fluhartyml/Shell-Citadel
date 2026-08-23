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

## 4 You speak to it — ⏸ BACK BURNER, his call 2026-08-23
Microphone, "hey claude" to start, "full stop" to finish. The wake phrase doubles as
barge-in. **Known problem to solve here:** dictated speech arrives punctuated and
spaced, and a shell wants exact characters — the app has to fix that, not the user.

**Parked, and for a good reason:** *"i can still use iOS to dictate to you so that's on
the back burner."* Most of this chunk arrived for free on 2026-08-22 by *un*-breaking the
keyboard — the composer had been hardened for shell commands, and in Attach mode he is
writing English, not commands. Making the keyboard mode-aware handed back the predictive
bar and the system dictation microphone. **He has been dictating to Claude from the porch
ever since.**

So what is left here is only the hands-free half: a wake phrase, barge-in, and never
touching the screen. That is a refinement on something that already works, not a
prerequisite for anything. **Do not re-propose it.** He will say when.

## 5 ✅ It reaches the tmux session — DONE 2026-08-22, out of order
Attach mode end to end on the real iPhone 16e: `send-keys` in, the voice file tailed
out. He typed from the phone, it arrived in the running Claude Code session, and the
reply came back to the phone. Done the same afternoon as chunk 1, ahead of the plan,
because it was the thing he actually wanted.

**Two bugs that only hardware could find:**
- `tmux` was not on the PATH of an SSH *exec* channel (Homebrew's `/opt/homebrew/bin`
  is absent from `/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.`). Now resolved by
  absolute path, with real sentences for "not installed" and "no such session".
- The voice path's leading `~` was inside single quotes, so it never expanded — the
  app tailed a directory literally named `~`, silently, forever. Fixed, and the
  channel now announces itself so silence cannot be mistaken for breakage.

**Known gap — ✅ HANDLED 2026-08-23, the passive queue.** Backgrounding the app or
locking the screen does drop the connection, and iOS suspending a backgrounded app is not
something the app can argue with. But the connection was never the damage: the voice
channel opened with `tail -n 0 -F` — *start at the end* — so every reply written while the
phone was away was skipped **permanently and silently.**

His name for the fix, from his front porch: *"we deed a passive queue."* And the queue
already existed — `out.txt` on the Mac is append-only and never truncated. What was
missing was the phone remembering how far it had read. `VoiceMark.swift` stores a byte
offset per host+user+file; the channel resumes with `tail -c +N`. Nothing runs on the Mac,
which is what makes it passive.

## 6 Ship it
App Store listing, the Haynes/Chilton-style manual covering the tmux upgrade path,
and the privacy story — no internet, no account, no server, which most remote-access
apps cannot say.

---

**Not in any chunk, deliberately:** interactive programs (vim, top, less) need a PTY,
and streaming output needs a different channel. Both are real limits, both are worth
stating rather than blurring, and neither blocks any chunk above.
