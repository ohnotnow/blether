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

blether is a LAN-only tool. Out of the box it listens on this Mac alone.
Turn on "Listen on the network" and it accepts replies from any machine on
your network with no password or token, so keep it on a network you trust
and never expose the port to the internet.

## Status

Five providers: [Kokoro-82M](https://huggingface.co/mlx-community/Kokoro-82M-bf16)
running locally on Apple Silicon through MLX, and ElevenLabs, OpenAI, xAI
and Mistral over their APIs with your own keys. One LLM writes a short
Marvin preamble, compresses long replies for listening, and quips in
character when Claude is waiting for you. A settings window covers the lot:
the LLM endpoint, model and key, a key per provider, your personas, profiles
with a provider and a voice and persona per role, and switches for speaking,
the preamble, the reply, notifications and listening on the network. A hook
on another machine, or in one project, picks its profile by URL. No
listening yet. A Claude Code Stop hook posts the reply to the app and you
hear it, replies queue rather than talk over each other, and a hotkey stops
everything.

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

## Kokoro

Kokoro runs in a small Python helper that blether starts when it launches and
stops when it quits. You need [uv](https://docs.astral.sh/uv/) installed:

```sh
brew install uv
```

The first launch downloads the model (about 340 MB) into your Hugging Face
cache and builds the helper's environment, which takes a minute or two; the
menubar says "Kokoro: warming up" until it is ready. After that the helper
stays warm, so a reply is spoken within a second of the words being ready.
It uses about 670 MB of memory while blether runs and is gone when you quit.

Voices are Kokoro's own, grouped by language in Settings. If blether cannot
find uv, the menubar says so and Settings > Advanced has a field for its
path.

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

Two details of that command line. `--data-binary @-` posts the payload
Claude Code pipes to the hook on stdin, unchanged. `-m 5` gives curl five
seconds, so if blether is not running a hook costs you at most that.

Claude Code normally waits for a hook to finish before handing the session
back to you. `"async": true` tells it to fire the hook and move on. blether
answers the request as soon as the payload decodes, before any speech work,
so the hook is quick either way, but async keeps it from ever getting in
your way.

The `Notification` entry is optional. Claude Code fires it when Claude is
waiting for you, a permission prompt or an idle session, and blether answers
with one short line in character, in a language picked at random from the
list in Settings > Behaviour. The last ten lines are fed back to the LLM so
it does not repeat itself. If something is already playing the line is
dropped rather than queued, and if the LLM fails you hear a beep instead.
Leave the entry out, or turn Notifications off in Settings > Behaviour, and
those events are ignored.

The language list is one language per line with a weight after a space, such
as `French 5`; higher weights come up more often, and the name is sent to the
LLM as written, so `Glaswegian 3` works too. Kokoro pronounces English,
French, Spanish, Italian, Portuguese, Hindi and Chinese properly. Japanese
needs extra Python packages the helper does not install, so a Japanese line
is read as if it were English.

## Voices and personas

A persona is a name and a one-line character description that slots into
"in the voice of...". Marvin ships as the default and you can add your own in
the Profiles, voices and personas section of the settings window. Each role,
the preamble, the reply and the notification, gets a persona (or none) and a
voice from the profile's provider, grouped by language where the provider
says which language a voice is.

## Profiles

A profile is a name plus a voice and persona for each role. A fresh install
has one, called Default. Add more in the Profiles, voices and personas
section of Settings: pick the profile you are editing, rename it, and choose
its voices and personas below. One profile is marked as the default and is
used whenever a hook names no profile, or names one that does not exist.

A hook picks a profile with `?profile=<name>` on the hook URL. Per project,
per agent and per machine are all just different URLs. For one project, put
the same hook in that project's `.claude/settings.json` with the profile
name on the end:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -m 5 -X POST -H 'Content-Type: application/json' --data-binary @- 'http://127.0.0.1:8765/hook?profile=scottish'",
            "async": true
          }
        ]
      }
    ]
  }
}
```

Names are matched ignoring case. A name with spaces goes in the URL
percent-encoded, and the settings window shows the exact string to paste
under each profile.

## Providers

A provider is a speech service. Five are built in: Kokoro, which runs on
this Mac for free, and ElevenLabs, OpenAI, xAI and Mistral, which need an
account and a key. Paste each key in Settings > Providers; it goes into your
macOS Keychain and is sent only to that service. Then pick the provider on
each profile in the Profiles section, so the Pi's Hermes can speak through
xAI while your local Claude uses ElevenLabs and a third profile stays on
Kokoro.

The voice pickers follow the provider. ElevenLabs, xAI and Mistral list the
voices your account can use once a key is saved; OpenAI's list is fixed
(alloy, ash, ballad, coral, echo, fable, onyx, nova, sage, shimmer, verse,
marin and cedar). If a list cannot be fetched, or you know an id the list
does not show, type it into the voice field instead.

The API providers bill per character, so a reply spoken through one is
capped at 800 characters after the LLM has compressed it, where Kokoro
allows 3000. ElevenLabs and xAI also understand a few inline delivery tags,
so with those two the LLM is told it may add one or two.

## Remote mode

Claude Code on another machine can send its replies here to be spoken, each
with its own profile, so you hear which Claude is asking. Tick "Listen on
the network" in Settings > Behaviour and relaunch blether. macOS may ask
once whether blether may accept incoming connections. On the other machine
install the same curl hook, pointed at this Mac and naming a profile:

```
curl -s -m 5 -X POST -H 'Content-Type: application/json' --data-binary @- 'http://<your-mac>.local:8765/hook?profile=pi'
```

There is no token to set up. Anyone on the network can post to it, which is
the trade for a tool that stays this simple; see the note at the top. The
claude-speaks `remote-hook.py` and its Hermes plugin keep working unchanged,
because the token they send is ignored.

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
only the preamble. The fourth, "Listen on the network", is remote mode.

## Logs

blether writes one line per event to `~/Library/Logs/blether.log`: each hook
that arrives, what the LLM wrote, what Kokoro rendered and how long it took,
and anything that failed. When the file passes 5 MB at launch it is renamed
`blether.log.1` and a fresh one starts. Console.app shows it too.

## How it works

The app listens on `127.0.0.1:8765`, or on every interface when "Listen on
the network" is on. The hook is a one-line curl that posts the Stop payload
to `/hook`, with `?profile=` naming which profile speaks. The app pulls out
the reply and strips the markdown. The LLM writes a one-line preamble in Marvin's voice and, for
replies over 60 words, a compressed version of the reply. Each line is
rendered to audio by Kokoro and added to a queue that plays one clip at a
time. A reply that arrives while audio is already playing skips the
preamble. Which provider renders the audio is the profile's choice.

Kokoro lives in `Helpers/kokoro.py`, bundled into the app and run with
`uv run`. The app talks to it in JSON lines over stdin and stdout: the
helper announces `ready` with its voices once the model is loaded and warm,
then each request carries text, a voice id and a file path, and each reply
says whether the WAV was written. That file is the reference for wiring a
different local model to the same protocol.

What blether keeps in `UserDefaults` (domain `uk.ohnotnow.blether`):
`llmBaseURL`, `llmModel`, `llmExtraBody`, `personas`, `profiles`,
`defaultProfileID`, `isEnabled`, `speaksPreamble`, `speaksMainReply`,
`speaksNotifications`, `notificationLanguages`, `recentQuips`,
`listensOnLAN`, `uvPath`, and the two shortcuts under
`KeyboardShortcuts_stopTalking` and `KeyboardShortcuts_toggleSpeaking`. An
older `roles` key is read once to seed the Default profile and never written
again. The LLM key and the provider keys are in Keychain only, one item
each.

## Licence

MIT. Copyright 2026 ohnotnow.
