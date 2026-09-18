#!/usr/bin/env python3
"""A stand-in for Helpers/kokoro.py that speaks the same JSON-lines protocol with no dependencies.

Flags: --delay N  seconds to wait before `ready`;  --fatal  print a fatal event and exit 1.
Per request: voice "bad" is refused; text "crash" exits 3 without replying; text "hang" never
replies; text "garble" replies with an id only; anything else writes 0.2 s of silence and says ok.
A request carrying "lang" also writes that code to "<out>.lang", so tests can see what went on the wire.
"""
import json
import sys
import time
import wave

args = sys.argv[1:]
if "--fatal" in args:
    print(json.dumps({"event": "fatal", "message": "fake could not start"}), flush=True)
    sys.exit(1)
if "--delay" in args:
    time.sleep(float(args[args.index("--delay") + 1]))

print(json.dumps({"event": "status", "message": "fake warming"}), flush=True)
print(json.dumps({"event": "ready", "voices": [
    {"id": "af_heart", "name": "Heart", "language": "en-US"},
    {"id": "bm_george", "name": "George", "language": "en-GB"},
]}), flush=True)
print("fake ready", file=sys.stderr, flush=True)

for line in sys.stdin:
    request = json.loads(line)
    text, voice, out, request_id = request["text"], request["voice"], request["out"], request["id"]
    if text == "crash":
        print("fake crashing", file=sys.stderr, flush=True)
        sys.exit(3)
    if text == "hang":
        continue
    if text == "garble":
        print(json.dumps({"id": request_id}), flush=True)
        continue
    if voice == "bad":
        print(json.dumps({"id": request_id, "ok": False, "error": "unknown voice"}), flush=True)
        continue
    with wave.open(out, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(24000)
        f.writeframes(b"\x00\x00" * 4800)
    if "lang" in request:
        with open(out + ".lang", "w") as f:
            f.write(request["lang"])
    print(json.dumps({"id": request_id, "ok": True}), flush=True)
