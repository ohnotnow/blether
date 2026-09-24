# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "pocket-tts>=3.2.0",
#   "soundfile>=0.13",
#   "numpy",
# ]
# ///
"""blether's Pocket helper: Kyutai's Pocket TTS on the CPU, kept alive by the app, spoken to in JSON lines.

Run with `uv run Helpers/pocket.py [added-voices-dir]`. Kyutai's own package, PyTorch on the CPU; on the M6 it made
speech 13 to 17 times faster than real time (2026-09-24). The named voices come from Kyutai's
ungated repo; only cloning from your own audio needs their terms accepted, and this helper does not
clone (training/pocket_clone.py does).

Same protocol as kokoro.py. The model is the English one for every voice: the French, German,
Italian, Spanish and Portuguese speakers read English with their accent, which is the point.
Kyutai's catalogue is joined by blether's own voices, one saved state per file in pocket-voices/
next to this script, named after the file, and by the voices a person added in Settings, in the
folder given as the first argument. An added voice replaces a bundled or catalogue one of the same
id. They are cloned from 10 s clips (blether-xhLum); a longer clip made the state three times the
size and, past 30 s, broke generation. The app restarts this helper when the added voices change.
  helper -> app   {"event": "status", "message": "..."}            any number, before ready
  helper -> app   {"event": "ready", "voices": [{"id", "name", "language"}, ...]}   once
  helper -> app   {"event": "fatal", "message": "..."}             then exit 1
  app -> helper   {"id": "...", "text": "...", "voice": "alba", "out": "/abs/path.wav"}
                  An unknown voice (a profile just switched from another provider) speaks as alba.
  helper -> app   {"id": "...", "ok": true}  or  {"id": "...", "ok": false, "error": "..."}
Output is 24 kHz mono 16-bit PCM WAV, every clip brought to the same loudness (see normalised).
stderr is free-form logging.
"""

import json
import sys
import time
from pathlib import Path

# The protocol owns stdout; libraries get stderr (see kokoro.py).
PROTOCOL_OUT = sys.stdout
sys.stdout = sys.stderr

DEFAULT_VOICE = "alba"
OWN_VOICES = Path(__file__).parent / "pocket-voices"
# A cloned voice keeps the level of its clip: on 2026-09-24 one came out 20 dB quieter than another,
# which peaked above full scale and clipped. So every clip is scaled to one speech level, with a
# ceiling. Always on: switching it off would give a voice its clip's accident of a level, not a quiet
# voice; a quieter role is a per-role volume, if anyone asks (blether-NkYN3).
TARGET_RMS_DB = -20.0
PEAK_CEILING_DB = -1.0
# Samples quieter than this are pauses, left out of the average.
SPEECH_FLOOR_DB = -50.0
# The language each catalogue voice was recorded in; everything else is English.
VOICE_LANGUAGES = {
    "estelle": "fr", "juergen": "de", "giovanni": "it", "lola": "es", "rafael": "pt",
}


def send(obj: dict) -> None:
    PROTOCOL_OUT.write(json.dumps(obj) + "\n")
    PROTOCOL_OUT.flush()


def status(message: str) -> None:
    send({"event": "status", "message": message})


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def normalised(audio):
    """Scaled so the speech averages TARGET_RMS_DB, or less if that would push a peak past the ceiling."""
    import numpy as np

    speech = audio[np.abs(audio) > 10 ** (SPEECH_FLOOR_DB / 20)]
    peak = float(np.max(np.abs(audio))) if audio.size else 0.0
    if speech.size == 0 or peak == 0.0:
        return audio
    rms = float(np.sqrt(np.mean(speech**2)))
    gain = min(10 ** (TARGET_RMS_DB / 20) / rms, 10 ** (PEAK_CEILING_DB / 20) / peak)
    return audio * gain


def voice_entry(voice_id: str) -> dict:
    return {
        "id": voice_id,
        "name": voice_id.replace("_", " ").replace("-", " ").title(),
        "language": VOICE_LANGUAGES.get(voice_id, "en"),
    }


def main() -> int:
    try:
        status("loading libraries")
        import soundfile as sf
        from pocket_tts import TTSModel
        from pocket_tts.utils.utils import _ORIGINS_OF_PREDEFINED_VOICES

        status("loading model (first run downloads it)")
        t0 = time.perf_counter()
        model = TTSModel.load_model()
        own = {p.stem: p for p in sorted(OWN_VOICES.glob("*.safetensors"))}
        if len(sys.argv) > 1:
            own |= {p.stem: p for p in sorted(Path(sys.argv[1]).glob("*.safetensors"))}
        catalogue = [v for v in sorted(_ORIGINS_OF_PREDEFINED_VOICES) if v not in own]
        voices = [voice_entry(v) for v in sorted(own)] + [voice_entry(v) for v in catalogue]
        log(f"model loaded in {time.perf_counter() - t0:.1f}s, {len(voices)} voices")

        # A voice's state takes a second or two to fetch the first time; keep each one after that.
        states: dict = {}

        def state_for(voice: str):
            if voice not in states:
                states[voice] = model.get_state_for_audio_prompt(own.get(voice, voice))
            return states[voice]

        status("warming up")
        t0 = time.perf_counter()
        model.generate_audio(state_for(DEFAULT_VOICE), "Ready.")
        log(f"warm-up took {time.perf_counter() - t0:.1f}s")
    except BaseException as exc:  # noqa: BLE001
        send({"event": "fatal", "message": f"{type(exc).__name__}: {exc}"})
        return 1

    send({"event": "ready", "voices": voices})
    known = {v["id"] for v in voices}

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
            request_id = request["id"]
            text, voice, out = request["text"], request["voice"], request["out"]
        except (ValueError, KeyError, TypeError) as exc:
            log(f"bad request ignored: {exc!r}: {line[:200]}")
            continue
        if voice not in known:
            log(f"no voice {voice!r}, speaking as {DEFAULT_VOICE}")
            voice = DEFAULT_VOICE
        t0 = time.perf_counter()
        try:
            audio = normalised(model.generate_audio(state_for(voice), text).numpy())
            sf.write(out, audio, model.sample_rate, subtype="PCM_16")
        except BaseException as exc:  # noqa: BLE001
            send({"id": request_id, "ok": False, "error": f"{type(exc).__name__}: {exc}"[:300]})
            continue
        log(f"{voice}: {len(audio) / model.sample_rate:.1f}s of audio in {time.perf_counter() - t0:.2f}s")
        send({"id": request_id, "ok": True})
    return 0


if __name__ == "__main__":
    sys.exit(main())
