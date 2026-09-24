# Making your own Pocket voice

Blether's Pocket provider speaks in saved voices: a small `.safetensors`
file that holds what the model remembered after hearing someone talk.
`pocket_clone.py` makes one from a clip of speech, and blether adds it
under Settings > TTS Providers > Pocket voices.

Only clone a voice you have the right to use: your own, one you designed
(on ElevenLabs, say), or someone who has said yes. Kyutai's terms ask
the same.

## Once: the Hugging Face step

Using a saved voice needs nothing, but making one needs Kyutai's cloning
weights, which are gated.

1. Log in to [Hugging Face](https://huggingface.co) and accept the terms
   on [kyutai/pocket-tts](https://huggingface.co/kyutai/pocket-tts).
2. On this Mac, run `uvx hf auth login` and paste an access token from
   your Hugging Face settings (read access is enough).

## Each voice

Put a clip in this folder and run, from the repo root:

```
uv run training/pocket_clone.py training/my-voice.mp3 "My Voice"
```

The name is optional; without it the clip's file name is used. You get
`my-voice.safetensors` and `my-voice-preview.wav` next to the clip.
Listen to the preview, and if you like it, add the `.safetensors` file in
blether. The first run downloads the model and takes a minute; after that
it is a few seconds.

## What makes a good clip

- Ten seconds of one person speaking is enough. The script uses the
  first ten seconds, so put the best speech at the start.
- Clean audio: no music, no background noise, no long pauses.
- Speak in the mood you want back. The voice keeps the delivery as well
  as the sound, so a cheerful clip gives a cheerful voice.
- The model reads English. A voice from another language reads English
  with its accent.

Anything you put here other than this README and the script is ignored
by git, so your clips stay on your Mac.
