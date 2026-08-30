# Shell Citadel — chunks

> # 🛑 BEFORE SUBMITTING: UNITED STATES ONLY
>
> **Michael, 2026-08-27:** *"please be extra sure when we submitt to app store connect
> that we only allow the united states be the only region the app is available."*
>
> **In App Store Connect → Pricing and Availability → set availability to the United
> States and NOTHING else.** The default is every territory Apple sells in. It is a
> silent default — nothing warns you, and it is chosen for you unless you change it.
>
> **WHY IT IS NOT COSMETIC.** This app is an SSH client, so it ships strong encryption.
> Encryption is export-controlled by the US, and shipping it into other territories
> raises questions this project has no reason to answer. Selling only inside the US
> removes the entire class of problem rather than managing it.
>
> ✅ **CONFIRMED 2026-08-27 AS HIS GENERAL RULE, not a Shell Citadel exception.**
> *"for my standing rule, i try to limit my app store connect to the united states only,
> i may ocasionally forget and include central south america and canada."*
> The memory that said "Americas only" had written up his occasional slips as intent and
> has been corrected → `feedback_english_only_americas_only_distribution`.
> **So this applies to every app of his, and this app has the extra encryption reason
> on top.**
>
> **Re-check this after EVERY submission.** Adding a new version does not reset it, but
> an accidental "add all territories" click is one tap wide and there is no confirmation.

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

### 📋 Submission checklist — the things that are easy to miss

- [ ] 🛑 **Availability: UNITED STATES ONLY.** See the banner at the top of this file.
      Apple's default is every territory. Verify it after every submission.
- [x] **Export compliance declared in the app** (`ITSAppUsesNonExemptEncryption = NO`).
      Without it App Store Connect asks by hand on EVERY upload, and a wrong answer on a
      tired evening is a compliance problem rather than a rejection. Added 2026-08-27.
- [x] **Privacy manifest** (`PrivacyInfo.xcprivacy`). Required by Apple. Ours is the
      easy case — collects nothing, no tracking, no account — but "nothing" still has to
      be declared. Added 2026-08-27.
- [x] **Camera usage string**, verified present in the BUILT Info.plist, not just the
      project file. Added 2026-08-27.
- [ ] ⚠️ **Reviewers have no Mac to connect to.** A reviewer opens the app, sees a login
      form, cannot connect, and can reject it as non-functional. This is a known way SSH
      clients get turned down. Decide BEFORE submitting: detailed review notes, or a
      demonstration mode that shows the interface without a host.
- [ ] ⚠️ **Archive must use the Release configuration — VERIFY, do not assume.**
      Product → Scheme → Edit Scheme → Archive → Build Configuration = **Release**, and
      tick **Shared** while there. There is currently NO `.xcscheme` file in the project,
      so Xcode auto-generates it and the setting lives only in per-user data: invisible to
      version control, unverifiable from disk, and changeable by one stray click with
      nothing to show it happened. Sharing it makes the scheme a real file that can be
      diffed and checked.
      **Why it matters here specifically:** everything inside `#if DEBUG` — the signal
      light simulator — is compiled out of Release and only Release. If Archive ever built
      Debug, debug controls would ship. That is the Tally Matrix Clock near-rejection,
      2026-08-27: *"the debug info looked industrial and cool so i thought it would be a
      cool easteregg but app store connect didnt agree."*
- [ ] **Screenshots** at 1242×2688 → `reference_app_store_screenshot_sizes`.
- [ ] **English only** → `feedback_english_only_americas_only_distribution`.

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

---

## 📍 LOCATION PIN DROP + MAP SNAPSHOT — his idea, 2026-08-28 07:25
> *"I want to add when i get back after my morning routine i would like to add a location pin drop
> with a small map snapshot in shell citadel"*

**Captured, not started — he said "when i get back."** Filed here rather than left in the
idea-capture log, because a bedtime or morning idea that stays only in the log is no better off
than one he never typed.

**Why it fits the app he is already building.** 2.5 established the shape: **the phone captures
something and it lands in the chat thread so Claude can process it.** A pin drop is the same
gesture with a different sensor — camera → photo, GPS → place. His framing for 2.5 was
*"i want the image or scan to land in the chat thread so it gets sent to you for processing,"* and
a location behaves identically.

**Two halves, and they are separable:**
1. **The pin** — the coordinate itself, which is what Claude can actually act on (Home Assistant
   geofencing, "how far am I from home", filing a photo by where it was taken).
2. **The map snapshot** — a small rendered image for HIM, so the message is readable at a glance
   rather than a pair of numbers. `MKMapSnapshotter` renders one without presenting a map view.

**Open questions — HIS, not to be pre-decided:**
- **What triggers it?** A `+` menu item beside the camera button he already asked for, or automatic
  on every message? **Automatic is a surveillance-shaped default and should not be assumed.**
- **Coarse or precise?** iOS offers both; coarse is enough for "which town", precise is needed for
  "which building."
- **Does the snapshot go in the thread, or only the coordinate?** An image costs tokens every time
  it is re-read in context; a coordinate costs almost nothing. **This is the same lesson as the
  screen-reading cost measured 2026-08-27** — images are cheap once and expensive forever after.

**⚠️ Privacy — flag before building, do not inherit it.** `NSLocationWhenInUseUsageDescription` is
required, App Store review reads it, and location is the most scrutinised permission there is.
It also touches his existing rule: **store location in the data model, never write it into photo
EXIF** — iOS's own camera setting stays the single authority.
→ [[feedback_photo_location_privacy]]

**Distribution constraint unchanged:** United States only. → the submission checklist above.

### 📌 REFINED 2026-08-28 07:29 — two features, not one
> *"since you suggested i want a map pin snapshot in the plus to drop a location pin and i would
> like an undisclosed gps location stamp imbeded in every message sent from human to claude in
> citadel"*

**A. THE PIN DROP — explicit, in the `+` menu.** A deliberate act: he taps, it drops a pin, the
snapshot goes in the thread. Fresh GPS fix is appropriate here because he asked for it by tapping.

**B. THE SILENT STAMP — every human→Claude message carries a coordinate.** Not rendered in the
bubble; it rides along as metadata for Claude to use.

**Why B is genuinely useful and not just data for its own sake:** it answers *where he was* when he
said something. A bedtime idea from the porch, a photo filed by the place it was taken, "how far am
I from home", a Home Assistant action that depends on whether he is in the house. The idea-capture
log already timestamps every message he types; **this is the same log gaining a second axis.**

**⚙️ RECOMMENDATION — use the LAST KNOWN location, not a fresh fix per message.**
`CLLocationManager.location` returns the cached last fix instantly, costs no battery, and is
accurate enough for "which place". A fresh fix per message would spin the GPS radio on every line
he types — and **battery is already a stated constraint of his** (see the Battery section above).
**Fresh fix belongs to A, the explicit pin, where he has asked for precision by tapping.**
A coordinate is also nearly free in tokens, unlike a snapshot image.

**⚠️ ONE THING THAT MUST NOT BE INHERITED SILENTLY — "undisclosed" and the App Store.**
Inside his own build, sending his own location from his own phone to his own Mac, with no third
party and no server, this is unremarkable — **it is his data about himself.**
**But "undisclosed" cannot survive App Store review.** A privacy nutrition label and
`NSLocationWhenInUseUsageDescription` are mandatory, and location collection must be declared **even
when it is invisible in the UI.** Undeclared background location is one of the most reliably caught
rejections there is. **Personal build: fine as described. Shipped build: the collection is declared
in the label, and only the on-screen DISPLAY stays silent.** Those are compatible — "undisclosed"
can mean "not shown in the bubble" without meaning "not declared to Apple."
**His call; flagged so it is a decision and not an accident.** → [[feedback_photo_location_privacy]]
(same rule still holds: location lives in the data model, never written into photo EXIF).

### ⭐ 2026-08-29 — TODAY GAVE B A REASON IT DID NOT HAVE YESTERDAY

**He re-asked for this at 22:38, hours after a 35-minute tachycardia at 183–208 bpm that he rode out
alone in the house.** Yesterday the silent stamp was useful metadata — *where was he when he said
that*. **Today it is part of the safety layer.**

**If he messages Claude during an episode, a coordinate riding along means Claude knows where he is
without him having to type it** — at exactly the moment typing is hardest. And the gap identified in
`Workshop/Lighthouse-Heartbeat-Bridge-DESIGN-2026-08-29.md` is *"the twenty minutes before he
presses anything"*, where the one genuinely useful thing Claude can do is **text a human**. **A text
that says where he is beats one that does not.**

**This raises B's priority and lowers its cost of being imperfect.** A cached fix that is five
minutes and two hundred metres stale is still the difference between *"he is at the house"* and
*nothing at all*.

**⚠️ It does NOT make it a safety system**, and must not be described as one. His **pendant** is the
dispatch path, with his address already on file at a staffed monitoring centre. **This is context
for a message, not a beacon.** → [[he-has-a-monitored-panic-necklace]] · [[feedback_fail_safe_principle]]

### ✅ 2026-08-29 22:42 — HE ANSWERED THE OPEN QUESTIONS

> ***"Course for regular chat precice for the pin drop picture of the map"***

| | Accuracy | Snapshot image? |
|---|---|---|
| **B — the silent stamp on every message** | **Coarse** | No — coordinate only |
| **A — the explicit pin drop** | **Precise** | **Yes** — he wants the map picture |

**⭐ And iOS has a sanctioned mechanism for exactly this split**, so it is his design rather than a
workaround: run the app at **reduced accuracy** (`kCLLocationAccuracyReduced`) as the normal state,
and call **`requestTemporaryFullAccuracyAuthorization(withPurposeKey:)`** when he taps the pin drop.
The system asks once, grants precision for that stated purpose, and returns to reduced afterwards.

**Three things that makes better at once:**
- **Battery** — the radio is not spun for full precision on every line he types.
- **App Store review** — reduced-by-default with a named purpose key is the pattern Apple documents
  and expects; it reads as restraint rather than collection.
- **Honesty** — the purpose key is user-visible text explaining *why* precision is needed at that
  moment, and "drop a pin on the map" is an easy sentence to write truthfully.

### ✅ 22:43 — AND WHERE THE SNAPSHOT GOES

> ***"The snapshot goes in the thread and photo album"***

**Both. The thread for Claude, the album for him.**

- **Thread** — so it lands in the conversation like a photo does, the 2.5 shape.
- **Photo album** — saved to Photos, which needs **add-only** access
  (`PHPhotoLibrary` `.addOnly`, `NSPhotoLibraryAddUsageDescription`). **The app never needs to READ
  his library**, and add-only is both the correct level and the lighter ask at review.

**A good consequence, possibly unintended:** once they are in Photos, his pin drops become
**browsable by date alongside everything else he shoots, findable without the app**. The record
outlives the tool — the same property that made today's cardiac photographs worth having.

**⚠️ Existing rule still holds:** location lives in the data model; **do not write coordinates into
photo EXIF.** iOS's own camera setting stays the single authority. A map snapshot *depicts* a place,
which is not the same thing as stamping one into metadata. → [[feedback_photo_location_privacy]]

**All three open questions are now closed.** Remaining before building is mechanical only: the
`NSLocationWhenInUseUsageDescription` string, the temporary-full-accuracy purpose key text, the
`NSPhotoLibraryAddUsageDescription` string, and whether the thread copy is re-sent on every context
read or referenced once (images are cheap once and expensive forever after — the 2026-08-27 lesson).

**Still nothing built.**

#### ✅ DECIDED 2026-08-28 07:40 — accuracy per feature
> *"For the pin drop i want precise location and for the chat thread i want general"*

| Feature | Accuracy | Source |
|---|---|---|
| **A · Pin drop** (`+` menu, deliberate) | **precise** | fresh fix, `kCLLocationAccuracyBest` |
| **B · Message stamp** (every human→Claude line) | **general** | cached last-known, **rounded before it is stored** |

**How "general" is produced — round it, do not geocode it.** Truncate to **2 decimal places**:

| Precision | Ground distance | Answers |
|---|---|---|
| 0.1° | ~11 km | which town |
| **0.01°** | **~1.1 km** | **which neighbourhood ← this one** |
| 0.001° | ~110 m | which building |

**Why rounding and not `CLGeocoder`.** A reverse-geocoded place name reads beautifully — "Surfside
Beach, TX" — and **requires a network call.** This app's founding property is that everything built
so far works **with no internet at all, on the LAN.** Rounding is offline, instant, and free.
**Do not spend the app's best property on a nicety.**

**Round at the source, by default** — the stamp is stored rounded rather than stored precise and
merely displayed rounded. That is what he asked for and it keeps the data matching the intent.

**But this is a design choice, NOT a containment requirement — his ruling, 2026-08-28 07:44:**
> *"Digests and threads have top secret clearance so they can see precise accuracy if it happens on
> mistake or by design"*

**He is right and the earlier warning here was over-cautious.** The raw threads are already
`<#TopSecret>` in full and already hold his medical history, his accident and family detail; a
coordinate is far less sensitive than what is in there today. **The classification system he built
IS the control.** So a precise value landing in a thread — by accident or on purpose — is **not an
incident** and needs no special handling. **Do not re-litigate containment feature by feature when
the classification already covers it.**

**On the authorization, since iOS makes accuracy an app-level setting rather than a per-call one:**
the simple path is full-accuracy authorization with the stamp deliberately rounded in code, which
guarantees the pin drop works. The stricter path is to request **reduced** accuracy by default and
call `requestTemporaryFullAccuracyAuthorization(withPurposeKey:)` only for the pin — the app then
genuinely does not hold precision the rest of the time. **The stricter path matches what he asked
for more literally; the simple path is fewer moving parts. Not decided — his call at build time.**

---

## 📱 THE iPHONE ULTRA REPLACES THE iPAD MINI — his statement, 2026-08-29 13:13

> ***"the iphone ultra will replace my ipad mini"***

**He sharpened the timing himself: *"the ultra comes out in a few weks"* — so this is a layout requirement arriving in WEEKS, not a someday note.** The iPhone Ultra
(the book-style foldable, expected **~September 2026** alongside the iPhone 18 Pro) has **two
independent displays** — roughly **7.8" inner** and **5.5" cover**. The iPad mini is 8.3". So the
inner screen is a mini, and the outer screen is a phone, **in the same device, switching while the
app is running.**

**And it lands on a role this app already has.** At 12:00 the same day: *"Im going to have my ipad
mini at my livingroom chair so i can use it as central command."* **Shell Citadel is the central-
command app**, so it inherits the change.

### What that means for this codebase

**⚠️ There is currently NO adaptive layout in Shell Citadel at all** — verified 2026-08-29, zero
uses of `horizontalSizeClass`, `verticalSizeClass` or the interface idiom anywhere in the sources.
Every screen is one layout stretched to whatever it is given. That is survivable on a fixed-size
phone or iPad and **is not survivable on a device that changes size in your hands.**

**The sanctioned path is size classes, not fold detection.** The fold data — `foldState` and
`angleDegrees`, plus a built-in-display-count key — exists only as **private framework strings** in
iOS 27. **Private API is an App Store rejection**, and this app is on the ASC track. So:

- **Design for a dynamic range of sizes** (resizability), and let the size class do the work.
- **⚠️ There is NO resizable simulator in Xcode 27** — checked 2026-08-29 against
  `xcrun simctl list devicetypes` on Xcode 27.0 (27A5194q). No `Resizable` type, no fold type; the
  iPhone list tops out at the 17 series. **The apartment record said to use one; it is not there.**
- **Test the two size classes instead, which needs no new hardware and no new simulator:**
  **iPhone 17** (compact width) stands in for the cover screen, and **iPad mini (A17 Pro)** —
  8.3", against the Ultra's ~7.8" inner — stands in for the unfolded screen. If the layout is
  driven by size class rather than by device, those two sims prove both Ultra states.
- **Never special-case "is this a fold."** → [[reference_iphone_fold_adaptive_layout]]

### The shape it probably wants

Following the pattern already chosen for Inkwell Journal's Ultra layout (outer = compact single
panel, inner = grid):

| Surface | Terminal layout |
|---|---|
| **Cover screen (~5.5", compact)** | **One terminal, full screen.** The tab strip stays, but only the focused tab renders. This is the glance-and-type case. |
| **Inner screen (~7.8", regular)** | Room for **two terminals at once** — the Claude tab and the Pi tab side by side, which is exactly the problem tabs were added to solve on 8/29. |
| **iPad** | Same regular-width layout, more of it. |

**Do this BEFORE the hardware ships, not after.** Retrofitting adaptivity onto views that assume one
size is the expensive version, and the geometry work is already here — `Columns × Lines` with
fit-to-columns is *already* a resizable terminal. **The engine adapts; the chrome does not yet.**

**Not scheduled. Recorded because he said it, and because it is cheaper now than in October.**
→ [[feedback_design_it_right_first_not_patch_after]]
