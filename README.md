# blether

blether gives Claude Code a voice. It is a macOS menubar app that reads
Claude's replies aloud in a voice you choose, and (soon) listens back so you
can answer by talking. Each Claude you run can sound like itself: the session
on the Raspberry Pi can boom, the local one can be svelte, a third can speak
French. You hear which Claude is asking before you read a word.

The voice is not plumbing, it is personality. Which speech provider, which
voice, which character in the words: that is yours to pick, and every design
choice here protects it. blether is the successor to two Python projects,
claude-speaks and claude-listens, rebuilt as one Swift app. The name is Scots
for a long chatty back-and-forth.

## Status

Slice 3. Apple system voices, one LLM that writes a short Marvin preamble and
compresses long replies for listening, and a settings window for the lot: the
LLM endpoint, model and key, your personas, a voice and persona per role, and
switches for speaking, the preamble and the reply. No listening yet. A Claude
Code Stop hook posts the reply to the app and you hear it, replies queue
rather than talk over each other, and a hotkey stops everything. More
providers (ElevenLabs, OpenAI, xAI, Mistral, Kokoro on MLX) and the rest are
on the way.

## The LLM

The words are written by one LLM, reached through any OpenAI-compatible chat
completions endpoint. Out of the box that is [Ollama](https://ollama.com) on
this Mac at `http://127.0.0.1:11434/v1` with the model `maternion/minicpm5:2b`,
so nothing is spent and no key is needed. If Ollama is not running you still
hear the reply, prefixed with a heads-up that the LLM fell over.

To point it elsewhere, open "Settings..." from the menubar and change the
base URL and model in the LLM section. If the endpoint needs an API key,
paste it there too: it goes into your macOS Keychain and is sent only to that
endpoint. Changes take effect on the next reply.

Some endpoints take fields that are not standard OpenAI. The Advanced fold at
the bottom of the settings window holds an extra request body, a JSON object
merged into every request (it cannot replace the model or the messages).
With Ollama and a reasoning model this one is worth having, otherwise a
40-word summary can take a minute of hidden thinking:

```json
{"reasoning_effort": "none"}
```

(`"low"` and Ollama's own `"think": false` were tried and did not stop the
thinking on the compatible endpoint; `"none"` did.)

## Build

You need the Xcode command line tools and XcodeGen:

```sh
xcode-select --install
brew install xcodegen
```

Then:

```sh
make        # builds build/Build/Products/Release/Blether.app
make run    # builds and launches it
make test   # runs the unit tests
```

A speaker icon appears in the menubar. There is no Dock icon and no main
window.

## Install the hook

Add this to `~/.claude/settings.json` (merge it if you already have a
`hooks` section). The same JSON is in
[hooks/claude-code-settings.example.json](hooks/claude-code-settings.example.json).

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -m 5 -X POST -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:8765/hook",
            "async": true
          }
        ]
      }
    ]
  }
}
```

Restart your Claude Code session and Claude should start speaking.

Two details of that command line. `--data-binary @-` posts the payload
Claude Code pipes to the hook on stdin, unchanged. `-m 5` gives curl five
seconds, so if blether is not running a hook costs you at most that.

Claude Code normally waits for a hook to finish before handing the session
back to you. `"async": true` tells it to fire the hook and move on. blether
answers the request as soon as the payload decodes, before any speech work,
so the hook is quick either way, but async keeps it from ever getting in
your way.

## Voices and personas

A persona is a name and a one-line character description that slots into
"in the voice of...". Marvin ships as the default and you can add your own in
the Voices and personas section of the settings window. Each role, the
preamble and the reply, gets a persona (or none) and one of the Apple voices
installed on your Mac, grouped by language.

## Stop talking

Pick "Stop talking" from the menubar, or record a global shortcut under
"Settings..." in the same menu. Stop kills the clip that is playing and
drops everything queued behind it. The shortcut is remembered between
launches.

## Turning it off

When you are deep in a terminal discussion, hearing three seconds of every
reply and then stopping it is worse than silence. Untick "Speaking" in the
menubar, or record a "Toggle speaking" shortcut in Settings. Off means a
reply is dropped before any LLM call or speech work, so nothing is spent,
and the menubar speaker gains a slash so the silence is explained. Whatever
is playing when you turn it off stops at once.

Two smaller switches live in the Behaviour section of Settings: "Preamble"
drops the in-character line, and "Reply" drops the reply itself so you hear
only the preamble.

## How it works

The app listens on `127.0.0.1:8765`. The hook is a one-line curl that posts
the Stop payload to `/hook`. The app pulls out the reply and strips the
markdown. The LLM writes a one-line preamble in Marvin's voice and, for
replies over 60 words, a compressed version of the reply. Each line is
rendered to audio with an Apple voice and added to a queue that plays one
clip at a time. A reply that arrives while audio is already playing skips
the preamble. Everything happens inside the app, so there is nothing else
to install and nothing to keep running.

What blether keeps in `UserDefaults` (domain `uk.ohnotnow.blether`):
`llmBaseURL`, `llmModel`, `llmExtraBody`, `personas`, `roles`, `isEnabled`,
`speaksPreamble`, `speaksMainReply`, and the two shortcuts under
`KeyboardShortcuts_stopTalking` and `KeyboardShortcuts_toggleSpeaking`. The
LLM key is in Keychain only.

## Licence

MIT. Copyright 2026 ohnotnow.
