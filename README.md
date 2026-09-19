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
character when Claude is waiting for you. An optional classifier reads the
mood of each reply so Mistral and OpenAI voices can match it. A settings
window covers the lot: the LLM endpoint, model and key, a key per provider,
tone, your personas, profiles with a provider and a voice and persona per
role, and switches for speaking, the preamble, the reply, notifications,
listening after replies and listening on the network. A hook
on another machine, or in one project, picks its profile by URL. A Claude
Code Stop hook posts the reply to the app and you hear it, replies queue
rather than talk over each other, and a hotkey stops everything. And it
listens: when a reply finishes, the microphone opens, you answer out loud,
and your words land in the Claude Code session that spoke.

## The LLM

The words are written by one LLM, reached through any OpenAI-compatible chat
completions endpoint. Out of the box that is [Ollama](https://ollama.com) on
this Mac at `http://127.0.0.1:11434/v1` with the model `maternion/minicpm5:2b`,
so nothing is spent and no key is needed. If Ollama is not running you still
hear the reply, prefixed with a heads-up that the LLM fell over.

To point it elsewhere, open "Settings..." from the menubar and go to the LLM
page. It offers Anthropic (through their OpenAI-compatible endpoint), OpenAI,
xAI and Mistral with the address filled in and a model suggested, plus
"OpenAI compatible" for Ollama, LM Studio, OpenRouter and anything else with
a base URL. Pick one to edit it, paste its key if it needs one (into your
macOS Keychain, sent only to that service; OpenAI, xAI and Mistral share the
key you gave them as speech providers), then switch on "Use this provider".
Looking at a provider does not switch to it. Until some LLM has answered
once, the LLM page wears a "Set up" badge and the menubar says replies are
being read raw. Changes take effect on the next reply.

Some endpoints take fields that are not standard OpenAI. The Advanced group
on the LLM page holds an extra request body, a JSON object
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
find uv, the menubar says so and Settings > Listening has a field for its
path, with a Restart button beside it.

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

Builds are ad-hoc signed, which is fine to run but means each new build is
a different program to the keychain, so it asks for your password before
handing over the stored API keys. If you rebuild often, sign every build with
the same certificate instead: run `security find-identity -v -p codesigning`, and put the
certificate's hash and the team id from that line in an untracked `local.mk`
next to the Makefile:

```make
SIGN = 0123456789ABCDEF0123456789ABCDEF01234567
TEAM = ABCDE12345
```

An Apple Development certificate is the usual one. The certificate's name
does not work in place of the hash. Tick "Always Allow" once and the
prompt is gone.

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

Three details of that command line. `--data-binary @-` posts the payload
Claude Code pipes to the hook on stdin, unchanged. `-m 5` gives curl five
seconds, so if blether is not running a hook costs you at most that.
`?pid=$PPID` on the Stop hook tells blether which Claude Code process the
reply came from: the hook runs under `sh`, whose parent is Claude Code
itself, so the shell fills it in. Listening uses it to find the right
session when a resumed session's ids stop matching; if you never listen,
leave it in anyway, it costs nothing.

Claude Code normally waits for a hook to finish before handing the session
back to you. `"async": true` tells it to fire the hook and move on. blether
answers the request as soon as the payload decodes, before any speech work,
so the hook is quick either way, but async keeps it from ever getting in
your way.

The `Notification` entry is optional. Claude Code fires it when Claude is
waiting for you, a permission prompt or an idle session, and blether answers
with one short line in character, in a language picked at random from the
list in Settings > General. The last ten lines are fed back to the LLM so
it does not repeat itself. If something is already playing the line is
dropped rather than queued, and if the LLM fails you hear a beep instead.
Leave the entry out, or turn Notifications off in Settings > General, and
those events are ignored.

The language list is one language per line with a weight after a space, such
as `French 5`; higher weights come up more often, and the name is sent to the
LLM as written, so `Glaswegian 3` works too. Kokoro pronounces English,
French, Spanish, Italian, Portuguese, Hindi and Chinese properly. Japanese
needs extra Python packages the helper does not install, so a Japanese line
is read as if it were English.

## Voices and personas

A persona is a name and a one-line character description that slots into
"in the voice of...". Marvin ships as the default and you can add your own on
the Personas page of the settings window. Each role,
the preamble, the reply and the notification, gets a persona (or none) and a
voice from the profile's provider, grouped by language where the provider
says which language a voice is.

## Profiles

A profile is a name plus a voice and persona for each role. A fresh install
has one, called Default. Add more on the Profiles page of Settings: pick the
profile you are editing, rename it, and choose its voices and personas
below. Names must be unique, since hooks find profiles by name. Every voice
row has a Play button that speaks a short sample in that voice, kept on disk
under Application Support so an API voice is billed once, and a Voice id
field for ids the provider's list does not carry. Switching a profile's
provider remembers the voices it had, so switching back restores them. One
profile is marked as the default and is used whenever a hook names no
profile, or names one that does not exist; the menubar menu has a "Default
profile" submenu for changing it without opening Settings.

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
account and a key. Paste each key in Settings > TTS Providers; it goes into
your macOS Keychain and is sent only to that service. Then pick the provider
on each profile on the Profiles page, so the Pi's Hermes can speak through
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

## Tone

Off by default. Switched on, blether works out the mood of each reply,
one of nine styles from neutral through sarcasm to shameful, and the voice
matches it where the provider can: Mistral by picking the styled variant
of the voice, OpenAI by a delivery instruction. Kokoro, ElevenLabs and xAI
sound the same either way. The preamble and the notification line are
not affected; Marvin is always Marvin.

The Tone group on the LLM page has three choices. "Jev" is a small classification model
from Typesafe built for exactly this kind of question; it needs its own
key, pasted in the row that appears when you pick it. "Your LLM" asks the
model you already configured, which works but adds a second call per
reply. If the classifier fails, the reply is spoken neutral and the log
says why; you will not hear about it.

## Remote mode

Claude Code on another machine can send its replies here to be spoken, each
with its own profile, so you hear which Claude is asking. Tick "Listen on
the network" in Settings > General and press Restart. macOS may ask
once whether blether may accept incoming connections. On the other machine
install the same curl hook, pointed at this Mac and naming a profile:

```
curl -s -m 5 -X POST -H 'Content-Type: application/json' --data-binary @- 'http://<your-mac>.local:8765/hook?profile=pi'
```

There is no token to set up. Anyone on the network can post to it, which is
the trade for a tool that stays this simple; see the note at the top. The
claude-speaks `remote-hook.py` and its Hermes plugin keep working unchanged,
because the token they send is ignored.

## Listen after Claude replies

Tick "Listening" in the menubar, or "Listen after Claude replies" in
Settings > General. From then on, when a reply finishes playing you hear
a tick, the microphone is open, and you talk. Two and a half seconds of
quiet sends what you said (a pop; the "Pause before sending" slider in
Settings > Listening moves this between one and six seconds), fifteen
seconds with no speech gives up
(a thud), and a single answer is capped at ninety seconds. Your words are
transcribed on this Mac and arrive in the Claude Code session that spoke,
as if you had typed them. Nothing leaves the machine.

Off is the default, and off means the microphone never opens. The first
time you turn it on, blether downloads the speech model,
[Canary 180m flash](https://huggingface.co/nvidia/canary-180m-flash) as
packaged by the [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp)
authors (218 MB, into `~/Library/Application Support/blether/models`), and
the menubar says so while it does. The first load on a machine takes about
ten seconds while Metal compiles its kernels; after that the ears are ready
in well under a second. macOS asks once for microphone permission, naming
blether.

The Microphone picker in Settings > Listening lists every input device, with
"System default" first. Choose one and blether uses it whenever it listens;
if it is not connected at the time, the system default is used and the
menubar says so. English only for now.

The preamble is skipped while listening is on, so the mic opens sooner. If
two replies arrive back to back, the first one to finish gets the
microphone and the other is logged and skipped. Claude is told, through the
channel, to prefer plain questions over the AskUserQuestion dialog while
you are talking, because a dialog blocks delivery until someone reaches the
keyboard. You can also just say "go hands-free" or "stop listening" to
Claude: the channel offers a `handsfree` tool that flips the same switch.

## Install the channel

Your words reach a session through Claude Code's channels research
preview: an MCP server that can push text into a running session. blether
is that server, on `127.0.0.1:8766`, and Claude Code reaches it through a
one-line shell command that pipes the session to that port with `nc`.
Register it once, for every project:

```sh
claude mcp add --scope user blether -- sh -c '( echo "blether $CLAUDE_CODE_SESSION_ID $PPID"; cat ) | nc 127.0.0.1 8766'
```

Then start each session you want to talk to with the channel flag:

```sh
claude --dangerously-load-development-channels server:blether
```

Claude Code shows a full-screen warning about development channels every
launch (choose "I am using this for local development"), and asks once per
project before using a new MCP server. The flag is not in `claude --help`
while channels are in preview, but it works. `/mcp` in the session should
list blether with its one tool. Some organisation accounts have channels
switched off; if the flag is refused, that is why, and a personal account
works.

Two things to know. If you quit or relaunch blether, every session's pipe
to it closes and Claude Code does not reopen it: run `/mcp` in each session
and reconnect blether, or restart the session. And a session started without
the flag still gets its replies spoken, but a spoken answer to it has
nowhere to go: you hear the thud, and the log and menubar say which session
had no channel.

## Stop talking

Pick "Stop talking" from the menubar, or record a global shortcut under
"Settings..." in the same menu. Stop kills the clip that is playing and
drops everything queued behind it. With listening on, stopping a reply skips
straight to the microphone, so you can interrupt Claude and answer; if the
microphone is already open, stop closes it without sending anything. The
shortcut is remembered between launches.

## Turning it off

When you are deep in a terminal discussion, hearing three seconds of every
reply and then stopping it is worse than silence. Untick "Speaking" in the
menubar, or record a "Toggle speaking" shortcut in Settings. Off means a
reply is dropped before any LLM call or speech work, so nothing is spent,
and the menubar robot's eyes and mouth close so the silence is explained. Whatever
is playing when you turn it off stops at once.

Two smaller switches live on the General page of Settings: "Preamble"
drops the in-character line, and "Reply" drops the reply itself so you hear
only the preamble. "Listen after Claude replies" is the microphone, and
"Listen on the network" is remote mode.

## Logs

blether writes one line per event to `~/Library/Logs/blether.log`: each hook
that arrives, each LLM call and how long it took, what Kokoro rendered,
each recording (how long, how loud, how much was speech), where a transcript
went, and anything that failed. The words themselves, what Claude said,
what the LLM wrote and what you said, are not logged unless you switch on
"Log the words too" on the General page; off, the line shows a character
count instead. The same page shows the log's path with "Open in Finder" and
"Clear" buttons. When the file passes 5 MB at launch it is renamed
`blether.log.1` and a fresh one starts. Console.app shows it too.

If a recording transcribes to nothing, the log says "heard nothing worth
sending" and the audio is kept at `~/Library/Logs/blether-last-empty.wav`
so you can listen to what the model was given. The usual cause is a very
quiet recording; the model also returns nothing for a clip that begins or
ends with more than about a second of digital silence, which is why
recordings are trimmed to the speech before transcription.

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

Listening is the same shape in reverse. When a reply's last clip finishes,
or is stopped, the app opens the microphone through AVAudioEngine,
converts whatever the device gives to 16 kHz mono, and watches the level:
speech followed by 2.5 s of quiet ends the recording, which is trimmed to
the speech and handed to Canary 180m flash through the vendored
[transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) Swift
binding in `Packages/TranscribeCpp` (a prebuilt framework on Metal, one
model kept warm). The text is written to the channel connection whose
session id, or failing that Claude Code pid, matches the reply's hook, as a
`notifications/claude/channel` message, and Claude Code shows it in that
session as `<channel source="blether">`. The channel protocol itself, the
MCP handshake and the `handsfree` tool, is a couple of hundred lines in
`Sources/Blether/Listening/ChannelServer.swift`; there is no relay
program, just `nc`.

What blether keeps in `UserDefaults` (domain `uk.ohnotnow.blether`):
`llmBaseURL`, `llmModel`, `llmExtraBody`, `personas`, `profiles`,
`defaultProfileID`, `isEnabled`, `speaksPreamble`, `speaksMainReply`,
`speaksNotifications`, `notificationLanguages`, `recentQuips`, `toneSource`,
`listensOnLAN`, `listensAfterReply`, `microphoneID`, `uvPath`, and the two shortcuts under
`KeyboardShortcuts_stopTalking` and `KeyboardShortcuts_toggleSpeaking`. An
older `roles` key is read once to seed the Default profile and never written
again. The LLM key, the provider keys and the Jev key are in Keychain only, one
item each.

## Licence

MIT. Copyright 2026 ohnotnow.

`Packages/TranscribeCpp` is the Swift binding from
[transcribe.cpp](https://github.com/handy-computer/transcribe.cpp), MIT,
vendored with its licence files; its prebuilt framework is downloaded from
their GitHub release at build time. The speech model,
[Canary 180m flash](https://huggingface.co/nvidia/canary-180m-flash), is
NVIDIA's, CC-BY-4.0, downloaded from Hugging Face on first use.
