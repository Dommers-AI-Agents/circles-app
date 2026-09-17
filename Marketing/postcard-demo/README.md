# Postcard teaser (~15s)

Shows both halves of the postcard feature: the free in-app send, and the paid
printed card Lob mails for $3.99.

    ./driver.sh && ./build.sh     # -> out/favcircles-postcard.mp4 (+ -ig.mp4)

Same pipeline as `../widgets-demo`: `driver.sh` drives the simulator by OCR and
logs marks, `build.sh` normalizes the take, cuts dead time, lays the narration
from `beats/`, and wraps it in the house-style navy brand cards (see the
`demo-video-brand-card-opener` note).

## Two OCR traps on this screen

**The caption.** "Greetings from ___" is printed across the postcard preview
*and* is the label of the form field below it. OCR finds the preview first, so
anchoring on those words taps an image and the typing lands in whichever field
still had focus — it mangled the message field for a whole take before I caught
it. Anchor on the section header, `CAPTION ON THE CARD`, and tap ~40pt below.

**Typing replaces, never appends.** The draft persists, so every text field
starts with the last take's content. Each typing step sends Cmd-A first.

## Known gap: the mail switch does not flip on camera

The finished cut shows the "Mail a printed postcard · $3.99" row, but the
switch stays OFF while the narration describes the printed card.

A synthetic click flips that SwiftUI `Toggle` exactly once and then never
again in the same session — tapping the label, the switch, the row centre, the
subtitle, with an instant click and with a held press, all verified against
`ocrfind "Full name"` (the address form only exists while the switch is on).
Every other tap in the take lands normally, so it is specific to this control.
Do not add a blind retry: the tap sometimes *does* land, and a second tap turns
it back off, which is how an earlier cut ended up showing an off switch after
three "successful" attempts.

Worth another look before the next cut — the address form sliding in is the
strongest single frame the paid half has.

## The take deliberately stops before Send

The last beat rests on "Send postcard" without tapping it.

- The Apple Pay sheet needs a payment card in Wallet and a simulator has none,
  so the tap would open Wallet's card setup, not the sheet.
- `POSTCARD_MAIL_ENABLED` is live, so a real tap would place a real Lob order
  against the live account and mail a real postcard.

To put the actual Apple Pay sheet on camera, shoot those few seconds on a
device and splice them in — `../list-demo/build.sh` already does phone-clip
splicing (`PHONE_CLIP`/`PHONE_IN`/`PHONE_OUT`).

## Stage prerequisites

The driver assumes all of this is already true; it does not set it up.

1. **The Mac is unlocked with the Simulator window visible.** Taps go through
   `cliclick` at screen coordinates, so a locked screen or sleeping display
   fails at `frame.sh` with "Can't get window 1 of process Simulator".
2. `/private/tmp/claude-501/demo_udid` holds the booted device's UDID.
3. The app on that simulator is **signed in** — a reinstall drops the session
   and lands on the login screen.
4. The account has **at least one connection**, or "Choose a connection" has an
   empty list and the digital half has nothing to show.
5. The simulator's photo library has **at least one good photo**
   (`xcrun simctl addmedia <udid> <file.jpg>`). The driver taps the first
   thumbnail in the grid.
6. The app build includes the Apple Pay visibility fix (commit b9e4f76).
   Before it, `supportsPayment` asked whether a card was already in Wallet, so
   on a simulator the "Mail a printed postcard" row never rendered at all and
   the paid half of this video could not be shot.

## Tuning

Beat text lives in `beats/*.txt`; regenerate audio with
`python3.13 beats/gen.py` (needs `edge_tts`; the system `python3` does not have
it). `PROTECT` in `build.sh` holds each mark's window open against the auto
cutter — widen an entry if a beat feels rushed.
