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

## 2.5 📷 Photos and screenshots, phone → Claude — **PRIORITY, above 3 and 4**
Michael, 2026-08-23: *"i am going to need a way for citidel to send you photos and
screenshots"* and, an hour later, *"stt and tts is lower priority than getting a photo or
screenshot from my phone to you."* **His ordering, stated plainly — this outranks both
speech chunks.**

**Why it is not a nice-to-have.** Two separate needs landed on it the same morning:

- **It is the missing eye for the homelab.** The bring-up he wants to run through this app
  starts at the rack, and Claude is blind there — `screencapture` sees the MacBook's screen,
  not a cable, a label, or an amber light. Everything in phase 1 of the homelab plan needs
  him to show me something physical.
- **It is how he reports a bug from the phone.** All day he has been saying *"please look"*
  and I capture his Mac. From the couch or the porch, with only the phone, there is no
  equivalent — he can describe an app's misbehaviour but not show it.

**MAP BEFORE CODING — his standing rule, and this one earns it.** SSH can carry the bytes
without difficulty; none of the real questions are about transport:

- Where do they land on the Mac, and under what name, so I can find them without being told?
- How does he pick or take one from inside the app — camera, photo library, screenshot roll?
- **How do I learn a new one arrived?** This is the interesting half. Today the traffic is
  one-directional per turn; a photo dropped on the Mac is invisible to me until something
  says so. The voice file solved the same shape in the other direction.
- Photo-library access needs a usage string and a permission prompt, and the Photos
  permission is a different one from the camera's.
- **Privacy stays the product's spine:** the file goes to *his* Mac and nowhere else. No
  service, no upload, no account. That property must survive this feature intact.

### ✅ ANSWERED 2026-08-25 — the UI, and the interesting half

**The control:** *"I want to add a plus next ti the predictive text boxes to add a camera capture
function to shell citadel."* **A `+` beside the predictive text boxes**, opening camera capture —
and he said *"image or scan"*, so a document scan is wanted alongside a plain photo.
**VisionKit's document scanner gives deskew and edge-crop for free** and is the same machinery as
his own Snap&ScanKeeper.

**And this settles the question the chunk called the interesting half — "how do I learn a new one
arrived?"** His answer: *"I want the image or scan to land in the chat thread so it gets sent to you
for processing."*

**So it is not a side channel at all — it is a message.** The split:

```
TRANSPORT   the bytes go over the existing SSH connection to the Mac.
            send-keys cannot carry them and never will.
THREAD      the send-keys line that follows carries the PATH, so it arrives as an
            ordinary chat message and Claude opens the file in that same turn.
```

**Nothing new has to be invented to make Claude see it** — reading a local image mid-turn is
already routine (every "verify the screen" on 2026-08-24/25 was exactly that). **The path staying
in the prompt also means the transcript keeps the reference**, so the record survives, and the
idea-capture hook logs it like any other line.

**Still open:** the landing folder and naming convention (a consistent one — e.g.
`~/.claude-voice/inbox/` — would let Claude watch it and drop the need to type a path at all), and
the camera/Photos permission strings, which are two separate prompts.

**Privacy is untouched by this:** the file goes to his Mac and nowhere else. No service, no upload,
no account.

## 3 It speaks the answer — ⏬ below 2.5, his call 2026-08-23
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

**Known gap — ✅ HANDLED AND VERIFIED BY HIM 2026-08-23, the passive queue.**
*"I just unlocked my iPhone and saw your anything below this is live"* — built at 08:00,
installed at 08:15, confirmed at 09:26 by the exact habit it was written for: he locked the
phone walking in off the porch. **Not a build-green claim; he ran it.**

**✅ PROPERLY EXERCISED 10:21.** The 09:26 run had nothing to catch up on — he unlocked, the app
reconnected, and the lines arrived live. So the *replay* had never actually run. Second test:
five NUMBERED lines written into the file while the screen was locked, numbered so a gap would
be obvious rather than something he had to notice. His report: **"All five showed ant the
disconnect reconnect dialogue showed."** No line lost, and the new dropped-connection sentence
appeared in place of `NIOSSH error 1`.

**Both boundary markers confirmed by him.** *"You were away — catching up on what you missed"*
above the replayed block (10:23), and *"Caught up. Anything below this is live"* below it — the
latter seen at 09:26 and the reason he noticed the fix at all. **Nothing about the passive queue
is left unverified.**

**What the gap was.** Backgrounding the app or locking the screen does drop the connection, and iOS suspending a backgrounded app is not
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

---

## 💓 HEARTBEAT — asked 2026-08-24 05:13

> *"i was wondering about a shrll citidell heartbeat or equivalent"*

**RECORDED, NOT DESIGNED. Not started.**

**The motivating incident, same night:** he typed *"Are you there?"* at 22:29 — because three
replies had been typed and never sent, and **he had no way to distinguish a silent Claude from a
dead connection.** The header said "Connected" throughout.

**⚠️ And "Connected" has lied before.** On 2026-08-22 `connected` was set once and never unset, so
a link that had dropped out of wifi range still read Connected. That was fixed by unsetting it on
failure — but **the state is still believed rather than verified.** Nothing checks.

### Three different things could be meant, and they are not the same feature

1. **Transport heartbeat** — the app periodically confirms the SSH channel is genuinely alive
   (a cheap `tmux has-session`, or a keepalive), so the header reports a *tested* state instead of
   a remembered one. **This is the one that fixes the lying-header class of bug.**
2. **Liveness indicator** — something visible that ticks, so silence is distinguishable from
   death without him having to send anything.
3. **Claude-side presence** — proof the session is running, not just the link. Different failure:
   the SSH channel can be perfectly healthy while the session is wedged or has exited.

**⚠️ Whatever it is, it must not write to `out.txt`.** That file is the conversation transcript;
a heartbeat in it would put a tick every N seconds into the thing he reads. Keep liveness out of
the content channel — the same separation that made the voice file work in the first place.

**Which of the three he means is his call.** Ask before building.

### ⚡ Battery — his constraint, 2026-08-24 05:19

> *"we also need to be mindfull about battery consumption"*

**The honest picture, which may invert the concern:**

- **A heartbeat can only run while the app is FOREGROUND.** iOS suspends a backgrounded app within
  seconds — proven on 2026-08-22 when the SSH connection died on a trip to another app. So it
  cannot poll all night; it cannot poll at all once he leaves the app.
- **And while it is foreground, the screen is on** — which costs far more than any poll. **A
  heartbeat's own draw is close to noise against the display.**
- **The real cost is the persistent SSH connection and the `tail`**, holding the radio awake. That
  is already paid, heartbeat or not.

**So the design rule is not "make the heartbeat cheap." It is: do not let the heartbeat become a
reason to keep the app awake.** Anything that fights iOS suspension to keep ticking — background
modes, audio session tricks, keepalive timers — trades a real battery cost for a cosmetic
reassurance.

**Related and already flagged 2026-08-23:** keeping the voice channel *audible* while the phone is
locked would take the Now Playing slot, can interrupt his music, and drains battery. Apple's docs
unread. Same trade, same answer so far: not worth it.

**Cheapest honest option to consider first:** verify liveness **on foreground and on send** rather
than on a timer. Those are the two moments he actually cares, and both are free — the work is
happening anyway.

### 🔔 PUSH NOTIFICATIONS — his idea, 2026-08-24 05:20, and it may replace the heartbeat

> *"Maybe notifications by apple may help"*

**RECORDED, NOT DESIGNED.**

**Why it beats a heartbeat at the actual problem:** a push is delivered **by the system, with the
app not running.** No foreground requirement, no persistent SSH, no `tail` holding the radio. The
phone already maintains one push connection shared by every app, so **the marginal battery cost is
close to zero** — which is the exact constraint he raised one minute earlier.

**It also solves the real incident.** He asked *"Are you there?"* because silence was ambiguous.
A push makes a reply arrive whether or not he is watching, which is a better answer than a tick
telling him the pipe is healthy.

**⚠️ And it does NOT break "no internet, no account, no server" — because his Mac is the server.**
APNs needs something to send the push; that is a small watcher on the Mac reacting to new lines in
`out.txt`, authenticating with **his own Apple developer key**. Apple's push service sits in the
path, but there is no third party and no account to sign up for. His developer membership was
renewed 2026-08-19, so the credential side is available.

**What it would need — none of it decided:**
- An **APNs auth key** from his developer account, and the **bundle ID** registered for push.
- The app to register and hand its **device token** to the Mac once.
- A **watcher on the Mac** — the same shape as the `Stop` hook already written.
- A decision about **what the notification contains.** The full reply is convenient and puts vault-
  adjacent text on a lock screen; a bare "Claude replied" is private and forces the app open.
  **His call, and it is the interesting one.**

**⚠️ Push requires a real network path to Apple.** Everything built so far works with no internet
at all, on the LAN. This is the first feature that would not. **That is a genuine departure from
the app's founding property and he should decide it deliberately, not inherit it.**
