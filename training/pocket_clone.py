# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "pocket-tts>=3.2.0",
#   "soundfile>=0.13",
#   "numpy",
# ]
# ///
"""Turn a short clip of someone speaking into a Pocket voice for blether.

    uv run training/pocket_clone.py my-voice.mp3 ["Voice Name"]

Writes <name>.safetensors and <name>-preview.wav next to the clip. Listen to the preview, then
add the .safetensors file in blether under Settings > TTS Providers > Pocket voices.
See training/README.md for the Hugging Face step this needs first.
"""

import re
import sys
from pathlib import Path

# Ten seconds is as good as thirty to the ear and a third of the file size; a 38 s clip made a voice
# that stopped after a second or two every time (ant blether-xhLum).
CLIP_SECONDS = 10
PREVIEW = (
    "I have been through the failing tests. Two of them were flaky, and one was a genuine bug "
    "in the date parsing. It is fixed now, and the build is green."
)
NO_CLONING = """Pocket could not download the weights it needs for cloning.

They are gated: accept Kyutai's terms at https://huggingface.co/kyutai/pocket-tts
(while logged in to Hugging Face), then log in on this Mac with

    uvx hf auth login

and run this script again."""


def voice_id(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(__doc__, file=sys.stderr)
        return 2
    clip = Path(sys.argv[1]).expanduser().resolve()
    if not clip.is_file():
        print(f"No such file: {clip}", file=sys.stderr)
        return 2
    name = voice_id(sys.argv[2] if len(sys.argv) == 3 else clip.stem)
    if not name:
        print("The voice name needs at least one letter or digit.", file=sys.stderr)
        return 2

    import soundfile as sf
    from pocket_tts import TTSModel, export_model_state

    model = TTSModel.load_model()
    if not model.has_voice_cloning:
        print(NO_CLONING, file=sys.stderr)
        return 1

    audio, rate = sf.read(clip)
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    used = min(len(audio) / rate, CLIP_SECONDS)
    print(f"{clip.name}: {len(audio) / rate:.1f}s, cloning from the first {used:.1f}s")
    cut = clip.with_name(f"{name}-first{CLIP_SECONDS}s.wav")
    sf.write(cut, audio[: rate * CLIP_SECONDS], rate)
    try:
        state = model.get_state_for_audio_prompt(cut)
    finally:
        cut.unlink(missing_ok=True)

    voice = clip.with_name(f"{name}.safetensors")
    export_model_state(state, voice)
    preview = clip.with_name(f"{name}-preview.wav")
    sf.write(preview, model.generate_audio(state, PREVIEW).numpy(), model.sample_rate, subtype="PCM_16")
    print(f"Wrote {voice}")
    print(f"Listen first: {preview}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
