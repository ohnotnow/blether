# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "mlx-audio>=0.5.1",
#   "misaki[en]>=0.9.4",
#   "soundfile>=0.13",
#   "numpy",
#   "en-core-web-sm",
# ]
# [tool.uv.sources]
# en-core-web-sm = { url = "https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl" }
# ///
"""blether's Kokoro helper: Kokoro-82M on MLX, kept alive by the app, spoken to in JSON lines.

Run with `uv run Helpers/kokoro.py`. The inline metadata above is the whole environment; uv caches
it centrally and writes nothing next to this file.

Protocol (one JSON object per line, flushed):
  helper -> app   {"event": "status", "message": "..."}            any number, before ready
  helper -> app   {"event": "ready", "voices": [{"id", "name", "language"}, ...]}   once
  helper -> app   {"event": "fatal", "message": "..."}             then exit 1
  app -> helper   {"id": "...", "text": "...", "voice": "bm_george", "out": "/abs/path.wav", "lang": "b"}
                  "lang" is optional: Kokoro's code for the language of the TEXT, default British English.
                  The voice only sets the timbre, so a Japanese voice reads English text with an accent,
                  which is what claude-speaks always did and what the user likes.
  helper -> app   {"id": "...", "ok": true}  or  {"id": "...", "ok": false, "error": "..."}
Output is 24 kHz mono 16-bit PCM WAV. stderr is free-form logging.

The pinned spacy wheel is not optional: misaki raises SystemExit (not Exception) when it is
missing, because spacy shells out to pip and uv venvs have none. Generation is wrapped in
BaseException for the same reason.
"""

import json
import sys
import time
from pathlib import Path

# The protocol owns stdout. Libraries print progress there (mlx-audio announces each pipeline it
# creates), so hand them stderr and keep the real stdout for our own lines only.
PROTOCOL_OUT = sys.stdout
sys.stdout = sys.stderr

MODEL_ID = "mlx-community/Kokoro-82M-bf16"
SAMPLE_RATE = 24000
# Kokoro's code for the language the text is in, not the voice's origin. The replies are English.
DEFAULT_LANG = "b"
# Kokoro's voice ids start with a language letter; this is its own table.
LANGUAGES = {"a": "en-US", "b": "en-GB", "e": "es", "f": "fr", "h": "hi", "i": "it", "j": "ja", "p": "pt-BR", "z": "zh"}


def send(obj: dict) -> None:
    PROTOCOL_OUT.write(json.dumps(obj) + "\n")
    PROTOCOL_OUT.flush()


def status(message: str) -> None:
    send({"event": "status", "message": message})


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def voice_entry(voice_id: str) -> dict:
    prefix, _, rest = voice_id.partition("_")
    return {
        "id": voice_id,
        "name": rest.capitalize() if rest else voice_id,
        "language": LANGUAGES.get(prefix[:1], prefix),
    }


def list_voices() -> list[dict]:
    from huggingface_hub import snapshot_download

    voices_dir = Path(snapshot_download(MODEL_ID)) / "voices"
    return [voice_entry(p.stem) for p in sorted(voices_dir.glob("*.safetensors"))]


def main() -> int:
    try:
        status("loading libraries")
        import numpy as np
        import soundfile as sf
        from mlx_audio.tts import load

        status("loading model (first run downloads about 340 MB)")
        t0 = time.perf_counter()
        model = load(MODEL_ID)
        voices = list_voices()
        if not voices:
            raise RuntimeError("model has no voices folder")
        log(f"model loaded in {time.perf_counter() - t0:.1f}s, {len(voices)} voices")

        # Each language gets its own pipeline, built lazily on first use at a few seconds each, so
        # warm the default one now rather than on the user's first reply. Others warm on demand.
        status("warming up")
        t0 = time.perf_counter()
        for _ in model.generate(text="Ready.", voice=voices[0]["id"], speed=1.0, lang_code=DEFAULT_LANG):
            pass
        log(f"warm-up took {time.perf_counter() - t0:.1f}s")
    except BaseException as exc:  # noqa: BLE001  misaki can raise SystemExit
        send({"event": "fatal", "message": f"{type(exc).__name__}: {exc}"})
        return 1

    send({"event": "ready", "voices": voices})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
            request_id = request["id"]
            text, voice, out = request["text"], request["voice"], request["out"]
            lang = request.get("lang", DEFAULT_LANG)
        except (ValueError, KeyError, TypeError) as exc:
            log(f"bad request ignored: {exc!r}: {line[:200]}")
            continue
        t0 = time.perf_counter()
        try:
            chunks = [np.asarray(c.audio) for c in model.generate(text=text, voice=voice, speed=1.0, lang_code=lang)]
            if not chunks:
                raise RuntimeError("no audio")
            audio = np.concatenate(chunks)
            sf.write(out, audio, SAMPLE_RATE, subtype="PCM_16")
        except BaseException as exc:  # noqa: BLE001
            send({"id": request_id, "ok": False, "error": f"{type(exc).__name__}: {exc}"[:300]})
            continue
        log(f"{voice}: {len(audio) / SAMPLE_RATE:.1f}s of audio in {time.perf_counter() - t0:.2f}s")
        send({"id": request_id, "ok": True})
    return 0


if __name__ == "__main__":
    sys.exit(main())
