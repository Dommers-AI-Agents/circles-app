# In-app tutorial video (2026-11)

The "Watch the video" in the home tour and Help plays
`tutorial/tutorial.mov` from Firebase Storage. This folder re-makes it.

1. **Account:** `tester-alex@favcircles.com` ("Alex", Charlotte, follows Wes and
   Brittany, seven saved Charlotte places). Its token goes into the recorder
   sim's App Group as `clip-auth-handoff.json` (see the memory note on
   simulator capture) so the app opens signed in.
2. **Sim:** "Tutorial Recorder 17PM" (no iCloud), location 35.2169,-80.8592.
3. `./record.sh` films one take: the `TutorialRecordingTour` UI test walks the
   app and logs marks; Amélie's is saved on camera, so unsave it before a retake.
4. `beats/*.txt` are the narration lines; `cd beats && python3 gen.py` voices
   them (edge-tts Ava).
5. `python3 build.py` builds `out/favcircles-tutorial.mp4` with captions and the
   brand cards.
