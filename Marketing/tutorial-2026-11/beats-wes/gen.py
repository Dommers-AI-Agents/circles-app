# gen.py — edge-tts narration for every beats/*.txt (AvaNeural, same voice as
# the tutorials). "FavCircles" is spelled "FaveCircles" for the TTS so it says
# "Fave", not "Fav"; the .txt keeps the real spelling for on-screen captions.
# Also writes <beat>.words.json (word-boundary offsets, seconds) so build.sh
# can sync overlays to specific spoken words.
import asyncio, glob, json, os, re, sys
import edge_tts
VOICE = "en-US-AvaNeural"
D = os.path.dirname(os.path.abspath(__file__))
only = set(sys.argv[1:])
async def one(txt):
    name = os.path.basename(txt)[:-4]
    if only and name not in only: return
    text = open(txt).read().strip()
    spoken = text.replace("favcircles.com", "FaveCircles dot com").replace("FavCircles", "FaveCircles")
    words = []
    with open(f"{D}/{name}.mp3", "wb") as f:
        async for chunk in edge_tts.Communicate(spoken, VOICE, rate="+5%", boundary="WordBoundary").stream():
            if chunk["type"] == "audio": f.write(chunk["data"])
            elif chunk["type"] == "WordBoundary":
                words.append({"w": chunk["text"], "t": chunk["offset"] / 1e7, "d": chunk["duration"] / 1e7})
    json.dump(words, open(f"{D}/{name}.words.json", "w"))
    print(name, f"{words[-1]['t']+words[-1]['d']:.2f}s" if words else "", "|", text)
async def main():
    for txt in sorted(glob.glob(f"{D}/*.txt")): await one(txt)
asyncio.run(main())
