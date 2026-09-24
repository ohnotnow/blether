# Blether

Blether gives Claude Code a voice and, if you want, ears. It is a macOS
menubar app that reads Claude's replies aloud in a voice you choose, and
can listen for your answer so you reply by talking into your mic.

## Overview

Each Claude you run can sound like itself: the session on the Raspberry Pi
can be a serious English voice, the local Mac one a sarcastic French voice,
a third can speak English with a Korean accent. You hear which Claude is
talking, and if you answer out loud your words go to the right session.

The voices, the text-to-speech providers and the LLM that writes the words
are all configurable, and the whole thing can run on-device on an Apple
Silicon Mac with 16 GB or more of memory.

Blether is a LAN-only tool. Out of the box it listens on localhost only.
Turn on "Listen on the network" and it accepts replies from any machine on
your network with no password or token, so keep it on a network you trust
and never expose the port to the internet.

The name is Scots for a long chatty back-and-forth.

## What it does

- A Claude Code Stop hook posts each reply to Blether and you hear it.
  Replies queue rather than talk over each other, and a hotkey stops
  everything.
- One LLM writes a short in-character preamble, compresses long replies for
  listening, and quips in character when Claude is waiting for you.
- Profiles pair a speech provider with a voice and persona per role, and a
  hook picks its profile by URL.
- Optional tone: a classifier reads the mood of each reply and voices that
  can match it do.
- Optional listening: when a reply finishes, the microphone opens, you
  answer, and your words land in the Claude Code session that spoke.
  Transcription is on-device.
- Two word lists: words the transcriber keeps mishearing, and words the
  voice mispronounces with what to say instead.

## Providers

Text-to-speech, pick one per profile:

| Provider | Needs | Notes |
|---|---|---|
| [Kokoro-82M](https://huggingface.co/mlx-community/Kokoro-82M-bf16) | Nothing - runs on-device | Default. English, French, Spanish, Italian, Portuguese, Hindi, Chinese |
| [Breeze-TTS-2](https://huggingface.co/mlx-community/Breeze-TTS-2-mlx-4bit) | A fast Mac - runs on-device | Voices you describe in words. Non-commercial licence, see below |
| [Pocket TTS](https://kyutai.org/blog/2026-01-13-pocket-tts/) | Nothing - runs on-device, on the CPU | English. Kyutai's voices plus three of Blether's own, see below |
| ElevenLabs | API key | Lists your account's voices |
| OpenAI | API key | Fixed voice list |
| xAI | API key | Lists your account's voices |
| Mistral | API key | Lists your account's voices; voices can express tone |

The LLM that writes the words, one global choice, any OpenAI-compatible
chat completions endpoint:

| Preset | Needs |
|---|---|
| Ollama, LM Studio, or any compatible endpoint | Nothing, runs locally |
| Anthropic | API key |
| OpenAI | API key |
| xAI | API key |
| Mistral | API key |

Any API keys go into your secure macOS Keychain.

The optional tone classifier is either your LLM or
[Jev](https://typesafe.ai), a small classification model that also needs its
own key.

## Build

You need the Xcode command line tools, XcodeGen, and uv for Kokoro:

```sh
xcode-select --install
brew install xcodegen uv
```

Then:

```sh
make        # builds build/Build/Products/Release/Blether.app
make run    # builds and launches it
make test   # runs the unit tests
```

A robot head appears in the menubar. There is no Dock icon and no main
window.

Builds are ad-hoc signed, which means each new build is a different program
to the keychain, so it asks for your password before handing over the
stored API keys. If you rebuild often, sign every build with the same
certificate instead: run `security find-identity -v -p codesigning` and put
the certificate's hash and team id in an untracked `local.mk` next to the
Makefile:

```make
SIGN = 0123456789ABCDEF0123456789ABCDEF01234567
TEAM = ABCDE12345
```

An Apple Development certificate is the usual one. Tick "Always Allow"
once.

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
            "command": "curl -s -m 5 -X POST -H 'Content-Type: application/json' --data-binary @- \"http://127.0.0.1:8765/hook?pid=$PPID\"",
            "async": true
          }
        ]
      }
    ],
    "Notification": [
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

Keep `?pid=$PPID` on the Stop hook: listening uses it to find the right
session.

The `Notification` entry is optional. When Claude is waiting for you, a
permission prompt or an idle session, Blether speaks one short line in
character, in a language picked at random from the list in Settings >
General. The list is one language per line with a weight after a space,
such as `French 5`; the name is sent to the LLM as written, so
`Glaswegian 3` works too. A profile that speaks through a local model
(Kokoro, Breeze or Pocket) always quips in English: small local models
can turn another language into a long stream of loud gibberish.

## First run

The first launch downloads the Kokoro model (about 340 MB) and builds the
helper's environment; the menubar says "Kokoro: warming up" until it is
ready. If Blether cannot find uv, the menubar says so and Settings >
Listening has a field for its path.

Out of the box the LLM is [Ollama](https://ollama.com) at
`http://127.0.0.1:11434/v1` with the model `maternion/minicpm5:2b`. If
Ollama is not running you still hear the reply, prefixed with a heads-up
that the LLM fell over. To use something else, open "Settings..." from the
menubar, go to the LLM page, pick a preset, paste its key, and switch on
"Use this provider".

With Ollama and a reasoning model, put this in the Advanced group's extra
request body, otherwise a 40-word summary can take a minute of hidden
thinking:

```json
{"reasoning_effort": "none"}
```

## Profiles and personas

A persona is a name and a one-line character description that slots into
"in the voice of...". Marvin ships as the default; add your own on the
Personas page.

A profile is a name plus a provider, and a voice and persona for each role:
the reply, the preamble and the notification line. A fresh install has one,
called Default. Add more on the Profiles page. Each voice row has a Voice
id field for ids the provider's list does not carry. One profile is the
default and speaks whenever a hook names no profile or an unknown one; the
menubar has a "Default profile" submenu for changing it.

A hook picks a profile with `?profile=<name>` on the URL. For one project,
put the same hook in that project's `.claude/settings.json` with the
profile name on the end:

```
curl -s -m 5 -X POST -H 'Content-Type: application/json' --data-binary @- 'http://127.0.0.1:8765/hook?profile=sarcastic'
```

Names are matched ignoring case. The settings window shows the exact
string to paste under each profile.

## Tone

Off by default. Switched on, Blether works out the mood of each reply and
the voice matches it where the provider can: Mistral by picking the styled
variant of the voice, OpenAI by a delivery instruction. Kokoro, ElevenLabs,
xAI and Breeze sound the same either way. The preamble is not affected. Choose the
classifier in the Tone group on the LLM page. If it fails, the reply is
spoken neutral and the log says why.

## Breeze

Breeze-TTS-2 builds a voice from a written description, such as "Female,
late twenties, Danish-accented English. Slightly dusky, low alto.
Hesitant, thoughtful delivery with small pauses." Blether ships four of
these voice designs; add and edit your own under Settings > TTS Providers,
then pick one per role in a profile like any other voice. The more the
description says about the voice itself (sex, age, accent, pitch,
texture, pace), the more it sounds like the same person from clip to clip.

It needs a fast Mac. On an M1 it made speech four to eight times slower
than it plays; on an M6 it keeps up at the Faster quality setting and
takes about twice as long as the speech at Better. Each design has its own
quality, so a short preamble can be Better while the reply is Faster; for
one voice at both, add the design twice. Kokoro is much quicker
on any Mac. A long reply is cut shorter for Breeze than for Kokoro so the
wait stays around a minute at most.

Like Kokoro it runs through uv. It only starts once a profile uses it,
and the first time it downloads about 2.3 GB; the menubar says "Breeze:
warming up" meanwhile.

The model is under the BreezeBlue Research and Non-Commercial licence (see
the [model page](https://huggingface.co/mlx-community/Breeze-TTS-2-mlx-4bit)).
Blether's MIT licence does not change that: Breeze is for research and
non-commercial use only.

## Pocket

[Pocket TTS](https://kyutai.org/blog/2026-01-13-pocket-tts/) is Kyutai's
small text-to-speech model. It runs on the CPU and makes speech many times
faster than it plays, so replies start almost at once and the voice stays
the same from clip to clip. It speaks English; its French, German,
Italian, Spanish and Portuguese voices read English with their accent.

Blether ships three voices of its own for it: Servalan, Chanteuse and
Danish Detective, cloned from speech made with voices designed on
ElevenLabs. They are listed first, then Kyutai's catalogue.

Like Kokoro it runs through uv. It only starts once a profile uses it,
and the first time it downloads the model; the menubar says "Pocket:
warming up" meanwhile. Using the voices needs no Hugging Face account.

## Pronunciations

The voices say some words badly: "kubectl", ".env", "sqlite". The
Pronunciations table on the General page pairs each with what to say
instead, such as "cube-control", "dot-env" and "sequel-lite". The swap
happens just before synthesis, on whole words in any case, and the LLM
still reads the original, so a persona told to say "clawed" for "claude"
does not get confused about who it is.

## Remote mode

Claude Code on another machine can send its replies here to be spoken, each
with its own profile. Tick "Listen on the network" in Settings > General
and press Restart. macOS may ask once whether Blether may accept incoming
connections. On the other machine install the same curl hook, pointed at
this Mac and naming a profile:

```
curl -s -m 5 -X POST -H 'Content-Type: application/json' --data-binary @- 'http://your-ip-address:8765/hook?profile=pi'
```

## Listen after Claude replies

Tick "Listening" in the menubar, or "Listen after Claude replies" in
Settings > General. From then on, when a reply finishes playing you hear a
tick, the microphone is open, and you talk. Two and a half seconds of quiet
sends what you said (a pop; adjustable in Settings > Listening), fifteen
seconds with no speech gives up (a thud), and one answer is capped at
ninety seconds. Your words arrive in the Claude Code session that spoke,
as if you had typed them.

Listening is off by default, so the microphone never opens. The first
time you turn it on, Blether downloads the speech model (218 MB) and macOS
asks once for microphone permission. English only for now.

The preamble is skipped while listening is on. You can also just say "go
hands-free" or "stop listening" to Claude and it will use the MCP to toggle it.

### Heard words

The transcriber is good at English and poor at names: "laravel" comes out
as "lara vel", "livewire" as "live wire". Put the words it keeps getting
wrong in "Heard words" on the Listening page, separated by spaces or
commas. Anything heard that is close enough in spelling or sound is
spelled the listed way before it is sent. Short words match too easily,
so leave them out. You can also tell Claude "add fluxui to the heard
words" and it will do it through the channel, so the word is not
forgotten by the time you open Settings.

## Install the channel

Your words reach a session through [Claude Code's channels research
preview](https://code.claude.com/docs/en/channels-reference). Register Blether as the channel once:

```sh
claude mcp add --scope user blether -- sh -c '( echo "blether $CLAUDE_CODE_SESSION_ID $PPID"; cat ) | nc 127.0.0.1 8766'
```

Then start each session you want to talk to with the channel flag:

```sh
claude --dangerously-load-development-channels server:blether
# or add a shell alias to your ~/.bashrc or ~/.zshrc if you use the listen feature a lot
alias claudel="claude --dangerously-load-development-channels server:blether"
```

Claude Code shows a warning about development channels every
launch (choose "I am using this for local development"), and asks once per
project before using a new MCP server. The flag is not in `claude --help`
while channels are in preview, but it works. `/mcp` in the session should
list blether with its two tools, `handsfree` and `heard_words`. Some organisation accounts have channels
switched off; if the flag is refused, that is why.

If you quit or relaunch Blether, every session's connection to it closes:
run `/mcp` in each session and reconnect blether, or restart the session.
A session started without the flag still gets its replies spoken, but a
spoken answer to it has nowhere to go.

## Stopping and switching off

"Stop talking" in the menubar, or a global shortcut recorded in Settings,
kills the clip that is playing and drops everything queued behind it. With
listening on, stop skips straight to the microphone, so you can interrupt
Claude and answer.

Untick "Speaking" in the menubar, or record a "Toggle speaking" shortcut,
to switch Blether off. Off drops a reply before any LLM call or speech
work, and the robot's eyes and mouth close. Two smaller switches on the
General page drop just the preamble or just the reply.

## Logs

Blether writes one line per event to `~/Library/Logs/blether.log`. The
words themselves are not logged unless you switch on "Log the words too"
on the General page.

"Keep recent clips", on the same page and off by default, keeps the last
ten clips Blether spoke as files, named by time and role, for playing to
someone who wants to hear what it does. "Open in Finder" takes you to
them. It never keeps what the microphone heard.

## Going deeper

[TECHNICAL_OVERVIEW.md](TECHNICAL_OVERVIEW.md) has the rest: the reply
pipeline, the Kokoro helper protocol, how the channel and session matching
work, what is stored where, and the numbers.

## Built on

Blether stands on other people's open source work:

- [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp),
  whose Swift binding runs the transcription model. MIT.
- [Canary 180m flash](https://huggingface.co/nvidia/canary-180m-flash),
  NVIDIA's speech recognition model, which does the actual transcription.
  CC-BY-4.0.
- [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), the default
  local text-to-speech model, run through
  [mlx-audio](https://github.com/Blaizzy/mlx-audio). Apache-2.0.
- [Breeze-TTS-2](https://huggingface.co/BreezeBlue/Breeze-TTS-2), the
  local model that speaks voice designs, as the 4-bit MLX conversion,
  also through mlx-audio. BreezeBlue Research and Non-Commercial licence.
- [Pocket TTS](https://kyutai.org/blog/2026-01-13-pocket-tts/), Kyutai's
  CPU text-to-speech model, run through their
  [pocket-tts](https://pypi.org/project/pocket-tts/) package, which also
  cloned Blether's own voices. The package is MIT, the model CC-BY-4.0.

## Licence

MIT. Copyright 2026 ohnotnow.

`Packages/TranscribeCpp` is vendored with its licence files; its prebuilt
framework is downloaded from their GitHub release at build time. The speech
model is downloaded from Hugging Face on first use.
