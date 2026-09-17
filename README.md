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

Slice 2. Apple system voices, one LLM that writes a short Marvin preamble and
compresses long replies for listening, no settings window yet, no listening.
A Claude Code Stop hook posts the reply to the app and you hear it, replies
queue rather than talk over each other, and a hotkey stops everything. More
providers (ElevenLabs, OpenAI, xAI, Mistral, Kokoro on MLX) and the rest are
on the way.

## The LLM

The words are written by one LLM, reached through any OpenAI-compatible chat
completions endpoint. Out of the box that is [Ollama](https://ollama.com) on
this Mac at `http://127.0.0.1:11434/v1` with the model `maternion/minicpm5:2b`,
so nothing is spent and no key is needed. If Ollama is not running you still
hear the reply, prefixed with a heads-up that the LLM fell over.

Until the settings window arrives you can point it elsewhere from the shell:

```sh
defaults write uk.ohnotnow.blether llmBaseURL https://api.openai.com/v1
defaults write uk.ohnotnow.blether llmModel gpt-5.6-luna
```

Some endpoints take fields that are not standard OpenAI. Anything you put in
`llmExtraBody` is merged into every request (it cannot replace the model or
the messages). With Ollama and a reasoning model this one is worth having,
otherwise a 40-word summary can take a minute of hidden thinking:

```sh
defaults write uk.ohnotnow.blether llmExtraBody -string '{"reasoning_effort": "none"}'
```

(`"low"` and Ollama's own `"think": false` were tried and did not stop the
thinking on the compatible endpoint; `"none"` did.)

An API key, if the endpoint needs one, lives in your Keychain: add a generic
password in Keychain Access with the service `uk.ohnotnow.blether` and the
account `llm`. Changes take effect on the next reply.

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

A speech-bubble icon appears in the menubar. There is no Dock icon and no
main window.

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

## Stop talking

Pick "Stop talking" from the menubar, or record a global shortcut under
"Settings..." in the same menu. Stop kills the clip that is playing and
drops everything queued behind it. The shortcut is remembered between
launches.

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
`llmBaseURL`, `llmModel`, `llmExtraBody`, `personas`, `roles`, and the stop shortcut under
`KeyboardShortcuts_stopTalking`. The LLM key is in Keychain only.

## Licence

MIT. Copyright 2026 ohnotnow.
