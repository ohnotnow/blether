# Blether: the gory details

## The shape of it

Blether is one macOS menubar app with two listeners and one queue.

- `HookServer` on `127.0.0.1:8765` (or every interface when "Listen on the
  network" is on) receives Claude Code hook payloads.
- `ChannelServer` on `127.0.0.1:8766` is an MCP server that Claude Code
  sessions connect to, so transcribed speech can be pushed back into them.
- `PlaybackQueue` plays audio clips one at a time. When the last clip of a
  reply finishes, it can turn on the microphone.

Everything is wired together at launch in `Sources/Blether/BletherApp.swift`.

## A reply, end to end

1. Claude Code's Stop hook posts its JSON payload to `/hook`, with
   `?profile=<name>` optionally naming a profile and `?pid=$PPID` naming the
   Claude Code process. Blether answers as soon as the payload decodes.
2. `HookPayload` pulls out the last assistant reply and `SpeechText` strips
   the markdown.
3. `SpeechPipeline` hands the text to `Speech/ReplyPlanner`. One LLM call
   writes a one-line preamble in the persona's voice and, for replies over
   60 words, a compressed version of the reply for listening. A reply that
   arrives while audio is already playing skips the preamble, as does any
   reply while listening is on.
4. If tone is on, `Speech/ToneClassifier` labels the reply's mood (nine
   styles, neutral through sarcasm to shameful). Mistral expresses it by
   picking the styled variant of the voice, OpenAI by a delivery
   instruction. The other providers ignore it. Only the reply clip is
   coloured.
5. `Speech/Pronunciations` swaps each clip's text for its phonetic
   spellings (below). The planner and the LLM never see the swapped text.
6. The profile's provider renders each line to audio. API providers are
   capped at 800 characters after compression, Kokoro at 3000, because the
   API providers bill per character.
7. Clips join `PlaybackQueue` and play in order. Stop kills the current clip
   and drops the queue. With listening on, stop skips straight to the mic.
   With "Keep recent clips" on, `Speech/RecentClips` copies each clip to
   `~/Library/Application Support/blether/recent` first, as
   `<yyyy-MM-dd HH.mm.ss> <role>.<ext>` (a taken name gets a number),
   and drops the oldest beyond ten. The queue deletes the original after
   playing, as ever.

A Notification hook event goes through `Speech/QuipPlanner` instead: one
short in-character line, in a language picked by weighted random from the
list in Settings, with the last ten quips fed back to the LLM. If something
is already playing the quip is dropped, and if the LLM fails you hear a
beep.

Prompts are Swift constants in `Speech/Prompts.swift`.

### Pronunciations

The Original | Replacement table on the General page is `[Pronunciation]`
in settings. `Pronunciations.apply` runs each pair in list order as a
case-insensitive regular expression: the original, escaped, preceded by
the start of the text or whitespace and followed by the end, whitespace or
punctuation. The boundary is whitespace rather than `\b` so entries that
begin with a dot (".env", ".gitignore") match; the old Python version used
`\b` and those never fired. Possessives count as the word, so "Claude's"
becomes "clawed's", which is what a voice wants. A port of
`apply_word_replacements` from claude-speaks.

## The LLM

One LLM, reached over any OpenAI-compatible chat completions endpoint by
`LLM/ChatCompletionsClient`. `LLM/LLMProvider` holds the presets (Anthropic
through their compatible endpoint, OpenAI, xAI, Mistral, and a generic
"OpenAI compatible" entry). The default is Ollama at
`http://127.0.0.1:11434/v1` with `maternion/minicpm5:2b`. If the LLM fails,
the reply is read raw with a spoken heads-up.

`LLM/ExtraBody` merges a user-supplied JSON object into every request; it
cannot replace `model` or `messages`. The reason it exists: with Ollama and
a reasoning model, a 40-word summary can take a minute of hidden thinking.
`{"reasoning_effort": "none"}` stops that on the compatible endpoint.
`"low"` and Ollama's own `"think": false` were tried and did not.

`LLM/FirstAnswerLLM` is a small wrapper that clears the first-run "Set up"
badge once any LLM has answered.

## Speech providers

`Providers/Provider.swift` is the protocol and `ProviderRegistry` holds the
five: Kokoro, ElevenLabs, OpenAI, xAI and Mistral. The four API providers
share `SpeechHTTP`. Keys live in the macOS Keychain, one item each, under
the service `uk.ohnotnow.blether` (`Settings/KeychainStore.swift`). OpenAI,
xAI and Mistral share one key between their speech and LLM roles.

ElevenLabs, xAI and Mistral list the voices an account can use once a key
is saved; OpenAI's list is fixed. ElevenLabs and xAI understand a few inline
delivery tags, so the LLM is told it may add one or two for those.

`Speech/VoiceSampler` renders and caches the per-voice sample behind the
Play buttons under Application Support, so an API voice is billed once.

### Kokoro

[Kokoro-82M](https://huggingface.co/mlx-community/Kokoro-82M-bf16) runs on
Apple Silicon through MLX, inside a Python helper, `Helpers/kokoro.py`,
that is bundled into the app. `Providers/HelperProcess` starts it with
`uv run` at launch and stops it at quit. The script's inline metadata
(`mlx-audio`) is its whole environment; uv builds and caches it on first
run.

The protocol is JSON lines over stdin and stdout. The helper prints `ready`
with its voice list once the model is loaded and warm; each request carries
text, a voice id, a language code and an output path; each reply says
whether the WAV was written. Stdout belongs to the protocol, so library
progress chatter is redirected. That file is the reference if you want to
wire a different local model to the same contract.

Numbers: the first launch downloads about 340 MB into the Hugging Face
cache and takes a minute or two to build the environment. Warm, a reply is
spoken within about a second of the words being ready. The helper uses
about 670 MB of memory while Blether runs.

The voice is timbre; the language code is the language of the text. Kokoro
pronounces English, French, Spanish, Italian, Portuguese, Hindi and Chinese.
Japanese needs extra packages the helper does not install, so Japanese text
is read as English.

If uv is not on the path, the menubar says so and Settings > Listening has
a field for its location (`Providers/UVLocator`).

## Profiles, personas and roles

A **profile** is a name plus a provider, and a voice and persona for each of
three **roles**: main (the reply), monologue (the preamble) and
notification (the quip). Settings shows the roles as Reply, Preamble and
Notification. A **persona** is a name and a one-line character description
slotted into "in the voice of...". Marvin ships as the default.

Hooks find profiles by name, matched ignoring case, so names are unique.
An unknown or missing name falls back to the default profile. Switching a
profile's provider remembers the voices it had per provider.

## Listening

The ears are Swift, in `Sources/Blether/Listening/`, one file per idea.

- `Microphone` captures through AVAudioEngine and converts whatever the
  device gives to 16 kHz mono chunks. `AudioInputDevice` lists inputs
  through CoreAudio; a chosen device that is not connected falls back to the
  system default.
- `SilenceDetector` is pure and clocked by chunk count. Speech followed by
  2.5 s of quiet (adjustable, one to six seconds) ends the recording.
  Fifteen seconds with no speech gives up. One answer is capped at ninety
  seconds.
- `Recording` is one attempt from the mic opening to send or cancel. It is
  trimmed to the speech before transcription, because Canary returns nothing for a
  clip that begins or ends with more than about a second of digital
  silence.
- `Sounds` is the three cues: a tick when the mic opens, a pop on send, a
  thud on give-up or no channel.
- `ModelStore` downloads the model (218 MB) into
  `~/Library/Application Support/blether/models` on first use.
- `Transcriber` is an actor over the vendored transcribe.cpp model and
  session. The first load on a machine takes about ten seconds while Metal
  compiles its kernels; after that the ears are ready in well under a
  second. English only for now.
- `Ears` owns the one recording that may be live, the listening switch,
  and a deliver closure that gets the text plus the session key. Before
  delivery the transcript goes through `WordCorrector` (below).

The mic is turned on by `PlaybackQueue.enqueue(onFinished:)` on a reply's
last clip. The handler waits until nothing else is playing, and `stop()`
fires it too. If two replies finish back to back, the first gets the mic
and the other is logged and skipped.

### Heard words

Canary offers no vocabulary biasing (transcribe.cpp's `initialPrompt` is
Whisper only), so mishearings are fixed after the fact, the way Handy does
it. `Listening/WordCorrector` is a port of Handy's `apply_custom_words`,
pure, with Levenshtein and Soundex written inline:

- Each transcript token and each listed word is reduced to a match key,
  lowercase ASCII alphanumerics, so "Charge B," and "ChargeBee" compare as
  `chargeb` and `chargebee`. Non-ASCII words in the list are skipped.
- The transcript is walked with windows of three, two and one tokens,
  never crossing punctuation inside the window, and the closest match
  across the sizes wins. That is how "live wire" becomes "livewire".
- The score is edit distance over the longer length. Pairs whose lengths
  differ by more than a quarter (or two characters) are skipped, so
  "openaigpt" cannot match "openai". When both are alphabetic and share a
  Soundex code the score is multiplied by 0.3. Anything under 0.18,
  Handy's default, is accepted: one letter out in an eight-letter word,
  or about four when the two sound alike.
- The replacement keeps the window's leading and trailing punctuation and
  the case pattern of the first token.

The threshold is not adjustable. One consequence, kept on purpose and
tested: a listed two-letter word swallows its soundalikes, "id" turns "it"
into "id", because one letter out of two is forgiven by the Soundex bonus.
So the Listening page warns off short words and the `heard_words` channel
tool refuses anything under three letters. A wild miss ("daughter" for
"env") is beyond fuzzy matching; the fix is saying the word differently.

The list is `heardWords` in settings, one string, split on whitespace and
commas. `Listening/HeardWordsTool` is the channel tool behind it: `add`
trims, dedupes case-insensitively, refuses short words by name and always
replies with the whole list; `list` just replies.

### Canary and transcribe.cpp

The model is NVIDIA's
[Canary 180m flash](https://huggingface.co/nvidia/canary-180m-flash), as
packaged by the [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp)
authors. `Packages/TranscribeCpp` is their Swift binding, vendored from tag
v0.2.3 with a `Package.swift` pointing at the release xcframework by URL
and checksum (a prebuilt framework on Metal, one model kept warm). The
framework is ad-hoc signed by its authors, which is why
`Sources/Blether/Blether.entitlements` disables library validation (the
hardened runtime stays on) and declares audio input. Without both, the app
either fails to launch or never shows the mic prompt. The microphone usage
string is in `project.yml`, because `Info.plist` is generated by xcodegen.

## The channel

Claude Code's channels research preview lets an MCP server push text into a
running session. Blether is that server.

Each session connects with a one-line shell command that announces itself
and then pipes stdio to port 8766:

```sh
sh -c '( echo "blether $CLAUDE_CODE_SESSION_ID $PPID"; cat ) | nc 127.0.0.1 8766'
```

The first line is the **session key**: the session id and the Claude Code
pid. (`$PPID` inside the hook or the MCP command is Claude Code itself,
because both run under `sh` whose parent is Claude Code.) After that line
the connection is plain JSON-RPC, handled by hand in
`Listening/ChannelServer.swift`: the MCP handshake, two tools (`handsfree`,
which flips the listening switch, and `heard_words`, which adds to or lists
the mishearing list), and instructions telling Claude that channel events
are the user speaking, to prefer plain questions over dialogs while the
mic is in use, and to add a heard word only when the user says one was
misheard. The `heard_words` description says what the corrector can and
cannot fix, so Claude knows when reaching for it is pointless.

A transcript is delivered as a `notifications/claude/channel` message on
the connection whose session key matches the reply's hook.
`SessionRegistry` does the lookup: session id first, then Claude Code pid
(a resumed session's id stops matching, its pid does not), then the only
connection if there is just one. Claude Code shows the text in that session
as `<channel source="blether">`.

Relaunching Blether closes every channel connection and Claude Code does
not reopen them; each session runs `/mcp` and reconnects, or restarts.

## Remote mode

"Listen on the network" rebinds the hook server to every interface. There
is no token and no TLS; anyone on the network can post. The token the old
claude-speaks `remote-hook.py` sends is accepted and ignored.

## Settings and storage

`Settings/AppSettings` is a UserDefaults-backed store, domain
`uk.ohnotnow.blether`. Keys: `llmBaseURL`, `llmModel`, `llmExtraBody`,
`personas`, `profiles`, `defaultProfileID`, `isEnabled`, `speaksPreamble`,
`speaksMainReply`, `speaksNotifications`, `notificationLanguages`,
`recentQuips`, `toneSource`, `listensOnLAN`, `listensAfterReply`,
`microphoneID`, `uvPath`, `heardWords`, `pronunciations`,
`keepsRecentClips`, and the two shortcuts under
`KeyboardShortcuts_stopTalking` and `KeyboardShortcuts_toggleSpeaking`. An
older `roles` key is read once to seed the Default profile and never
written again. The LLM key, the provider keys and the Jev key are in
Keychain only.

The settings window (`Settings/SettingsView`) is a sidebar of pages:
General, Profiles, Personas, TTS Providers, LLM, Listening. Each page is
one or two `*Section` files.

`MenuBarIcon` draws the robot head in code as a template image; there is no
icon asset. Its eyes and mouth close when speaking is off.

## Logs

One line per event to `~/Library/Logs/blether.log`: each hook that arrives,
each LLM call and how long it took, what Kokoro rendered, each recording
(how long, how loud, how much was speech), where a transcript went, and
anything that failed. Lines that would carry spoken or heard words go
through `Log.content`, which shows a character count unless "Log the words
too" is on. When the file passes 5 MB at launch it is renamed
`blether.log.1`. Console.app shows it too.

When a heard word changed a transcript the log says so, both versions
through `Log.content`.

If a recording transcribes to nothing, the log says "heard nothing worth
sending" and the audio is kept at `~/Library/Logs/blether-last-empty.wav`
so you can hear what the model was given. The usual cause is a very quiet
recording.

## Build and tests

`project.yml` is the source of truth; xcodegen generates `Blether.xcodeproj`,
which is not tracked. `make` builds Release, `make run` launches, `make test`
runs the XCTest suite.

`Tests/BletherTests/` has one file per source file. Fakes under `Support/`
include `fake_helper.py`, so the suite never needs uv, Kokoro, the
microphone, the model or the network. The channel tests use a real loopback
socket on port 0.

## Origins

Blether replaces two Python projects, claude-speaks and claude-listens,
rebuilt as one Swift app. The design notes and the decisions behind it
(why the ears are Swift and not Python, why there is no shared secret, why
the Kokoro helper stays warm) are kept in the repository's `ant` notebook;
`CLAUDE.md` lists which to read.
