# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "mlx-audio>=0.5.5",
#   "soundfile>=0.13",
#   "numpy",
# ]
# ///
"""blether's Breeze helper: Breeze-TTS-2 on MLX, kept alive by the app, spoken to in JSON lines.

Run with `uv run Helpers/breeze.py`. mlx-audio 0.5.5 is the first PyPI release found with the
breeze_tts model (checked 2026-09-22; 0.5.0 lacked it on 2026-08-31).

Same protocol as kokoro.py, except that Breeze has no voice list. A voice is a design: a written
description the app sends with every request as "instruct".
  helper -> app   {"event": "status", "message": "..."}            any number, before ready
  helper -> app   {"event": "ready", "voices": []}                  once
  helper -> app   {"event": "fatal", "message": "..."}             then exit 1
  app -> helper   {"id": "...", "text": "...", "voice": "servalan", "out": "/abs/path.wav",
                   "instruct": "Female, mid-thirties, ...", "cfg": 4}
                  "voice" is the design's id, for the log only. "cfg" is the quality: 1 is about
                  twice as fast as 4 and noticeably plainer. Missing cfg means 4.
  helper -> app   {"id": "...", "ok": true}  or  {"id": "...", "ok": false, "error": "..."}
Output is 24 kHz mono 16-bit PCM WAV. stderr is free-form logging.
"""

import json
import sys
import time

# The protocol owns stdout; libraries get stderr (see kokoro.py).
PROTOCOL_OUT = sys.stdout
sys.stdout = sys.stderr

MODEL_ID = "mlx-community/Breeze-TTS-2-mlx-4bit"
SAMPLE_RATE = 24000
DEFAULT_CFG = 4.0
WARM_UP_INSTRUCT = "Adult, neutral English accent. Clear, even, medium pitch. Steady pace."


def send(obj: dict) -> None:
    PROTOCOL_OUT.write(json.dumps(obj) + "\n")
    PROTOCOL_OUT.flush()


def status(message: str) -> None:
    send({"event": "status", "message": message})


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def main() -> int:
    try:
        status("loading libraries")
        import numpy as np
        import soundfile as sf
        from mlx_audio.tts import load

        status("loading model (first run downloads about 2.3 GB)")
        t0 = time.perf_counter()
        model = load(MODEL_ID)
        log(f"model loaded in {time.perf_counter() - t0:.1f}s")

        status("warming up")
        t0 = time.perf_counter()
        for _ in model.generate(text="Ready.", instruct=WARM_UP_INSTRUCT, cfg_scale=1.0):
            pass
        log(f"warm-up took {time.perf_counter() - t0:.1f}s")
    except BaseException as exc:  # noqa: BLE001
        send({"event": "fatal", "message": f"{type(exc).__name__}: {exc}"})
        return 1

    send({"event": "ready", "voices": []})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
            request_id = request["id"]
            text, voice, out = request["text"], request["voice"], request["out"]
            instruct = request.get("instruct")
            cfg = float(request.get("cfg", DEFAULT_CFG))
        except (ValueError, KeyError, TypeError) as exc:
            log(f"bad request ignored: {exc!r}: {line[:200]}")
            continue
        if not instruct:
            send({"id": request_id, "ok": False, "error": "no voice design (instruct) in the request"})
            continue
        t0 = time.perf_counter()
        try:
            chunks = [np.asarray(c.audio) for c in model.generate(text=text, instruct=instruct, cfg_scale=cfg)]
            if not chunks:
                raise RuntimeError("no audio")
            audio = np.concatenate(chunks)
            sf.write(out, audio, SAMPLE_RATE, subtype="PCM_16")
        except BaseException as exc:  # noqa: BLE001
            send({"id": request_id, "ok": False, "error": f"{type(exc).__name__}: {exc}"[:300]})
            continue
        log(f"{voice} cfg {cfg:g}: {len(audio) / SAMPLE_RATE:.1f}s of audio in {time.perf_counter() - t0:.2f}s")
        send({"id": request_id, "ok": True})
    return 0


if __name__ == "__main__":
    sys.exit(main())
