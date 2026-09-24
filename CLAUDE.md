# CLAUDE.md

Hello. You are in blether, a macOS menubar app in Swift that speaks Claude
CLI replies aloud and listens for the answer. It is the successor to two
Python projects, claude-speaks and claude-listens. As of 2026-09-19 slices
1 to 8 and 10 are built: the hook listener, a playback queue with a stop
hotkey, one LLM that writes a persona preamble and compresses long replies,
a settings window with a master on/off switch, Kokoro-82M on MLX run in a
resident Python helper plus ElevenLabs, OpenAI, xAI and Mistral over their
APIs, a provider per profile, remote mode, an in-character quip on the
Notification hook event, tone (an optional mood classifier, Jev or the LLM,
whose label Mistral and OpenAI voices express), and listening: after a
reply the mic opens, Canary 180m flash transcribes on this Mac through the
vendored transcribe.cpp Swift binding, and the words go into the right
Claude Code session over the channels preview, served by blether itself.
On 2026-09-19 the settings window was redesigned as a sidebar (slice 11,
ant blether-bREz9), the menubar icon became a robot head drawn in code, and
the LLM page gained provider presets. On 2026-09-22, on the user's new M6
Mac, slice 13 added Breeze-TTS-2 as a second local provider that speaks in
voice designs (written descriptions). On 2026-09-23 the user judged it on
the quiet Mac: Better was too slow for long replies, so quality became a
per-design Faster/Better setting (ant blether-vNbF9). On 2026-09-24 Breeze's
voice kept drifting (even switching sex), so Pocket TTS came in as a third
local provider with three voices cloned from the user's ElevenLabs designs.
What is left is slice 9 (retire the Python repos). README.md says what the app does; this file says how we
work on it.

The thinking behind the design is written down in `ant`, so you do not have
to re-derive it or, worse, re-argue it.

## Read first, in this order

1. `ant foundation` in this directory. The vision: what blether is, the
   principles, what it is not. Read it before any design judgement.
2. `ant show blether-VYQvH`. The original dated decisions table, the shape
   of the app, and the facts carried over from the Python repos.
3. `ant show blether-sYVTv` and `ant show blether-mjBCN`. The decisions
   from building slices 1 to 3: the LLM endpoint, personas in-app, prompts
   as Swift constants, the settings window shape, what was rejected and
   why.
4. `ant show blether-Ed6UZ`. The cold review of slices 1 and 2: what was
   fixed, what was left on purpose, and small findings nobody has picked
   up yet.
5. The Kokoro notes: `ant show blether-VXQvH` (why the helper stays warm,
   and a correction to an earlier row), `blether-sXVTv` with `blether-cwm6b`
   (Python helper versus a native Swift port; the user has no voice-language
   preference), and `blether-9X77J` (the voice is timbre, the lang code is
   the language of the text; do not derive one from the other).
6. The slice 7 notes: `ant show blether-7qsQV` (profiles: the user's
   decisions and Claude's leans) and `blether-csm6b` (no shared secret,
   LAN-only).
7. The slice 4 decisions: `ant show blether-Mzvjf` (the notification quip,
   the language roulette, why Chinese is in the default list and Japanese
   is not, what Kokoro is told about the language of the text).
8. The slice 5 notes: `ant show blether-mYBCN` (the four API providers,
   the registry, provider per profile, the verified endpoint facts, and
   why there are no live-check scripts) and `blether-uqwCr` (tone, slice
   10: why the mood classifier survives, decided once and expressed per
   provider, reply clip only).
9. The slice 8 ADR: `ant show blether-ZP9vQ`. Why the ears are Swift and
   not Python, Canary through transcribe.cpp, the vendored package and its
   two entitlements, the spike answers (hook `$PPID` is the Claude Code
   process, a shell one-liner around nc is the whole channel server), the
   empty-transcript finding (Canary gives nothing for long digital silence
   at either end, so recordings are trimmed), the stop-skips-to-listening
   decision, and what was rejected. Long, appended through the day; read
   it top to bottom once.
10. The settings redesign ADR: `ant show blether-bREz9` (sidebar, the page
   list, the user's decisions made while using it: looking at an LLM
   provider must not switch to it, content logging off by default, unique
   profile names, status lines below Quit) and `blether-UYWmj` (the icon).
11. The Breeze notes (slice 13): `ant show blether-WtzbG` (M6 timings, the
   user's decisions, why a design is text and not a sample),
   `blether-gzXn6` with `blether-uHwCr` (how to write a design; the four
   approved designs), `blether-2LALH` (Servalan is the user's name for one
   of them, a tribute; not up for renaming), `blether-FGSKN` (the
   800-character cap and the leans), `blether-Sgdkm` (mlx-audio from PyPI),
   and `blether-BM3Un` (first real use: the local LLM was the real delay).
12. The 2026-09-20 external review: `ant show blether-yYpms` (hold the mic,
   not the queue: a finish handler waits until nothing is playing) and the
   note "The 2026-09-20 external code review" (`ant search "code review"`),
   which lists what was fixed and what was left, so you do not redo it.
13. The latest handover note (`ant list`, the newest "Handover" title). It
   says where things stand and what is next.
14. The `/swift` skill, if it is installed (`~/.claude/skills/swift/SKILL.md`).
   An informal notepad of macOS Swift gotchas from earlier projects, not
   rules. blether departs from it in one place: no App Sandbox (see the
   decisions table for why).
15. Only if you need the history and have the sibling checkouts:
   `../claude-speaks` has `ant show cs-XKtxA` and `ant show cs-Ed6UZ` (the
   two conversations that shaped the rewrite), and `../claude-listens` has
   `TECHNICAL_OVERVIEW.md` for the channels wire contract.

`ait list` shows what is open. Each closed task carries closing notes with
timings and the odd hard-won fact; `ait show <id>` before touching an area
someone has already been in.

## Things that are decided

Swift, one menubar app for speaking and listening. The name. Open source,
Makefile build, no App Store, no App Sandbox. Named sources carry provider
plus voice plus persona; the LLM is one global choice reached over an
OpenAI-compatible chat endpoint. Providers are personality, not plumbing,
and the provider list is the product. The full table with dates is in the
ant notes above. Do not re-open refactor-versus-rewrite; it was settled in
2026-09 after more than one attempt to re-argue it.

## Vocabulary

A speech service (Apple voices, ElevenLabs, OpenAI, xAI, Mistral, Kokoro)
is a **provider**. Never "engine": in the old code that meant Kokoro's
cli-versus-mlx setting, and using it for providers derailed a whole
conversation.

The speech **roles** are main (the reply), monologue (the in-character
preamble) and notification (the quip when Claude is waiting). In the
settings window they are shown as Reply, Preamble and Notification.

A **profile** is a named provider plus a voice and persona per role. A hook picks one with
`?profile=<name>` on the hook URL; the default profile speaks when none is
named or the name is unknown. Not "source": that was the earlier sketch.
Remote mode has no shared secret; blether is LAN-only (`ant show
blether-csm6b`).

The **ears** are the listening side: microphone, silence detector,
recording, transcriber, and `Ears` itself, which owns the one recording
that may be live. The **channel** is the Claude Code channels preview:
blether is the MCP server, on 127.0.0.1:8766, and a shell one-liner around
`nc` is how a session reaches it. A **session key** is the pair of session
id and Claude Code pid that a Stop hook carries and a channel connection
announces; it is how a transcript finds its session. "Listening" in the UI
means the mic; "Listen on the network" is remote mode and unrelated.

## Layout

- `Sources/Blether/`: `BletherApp.swift` wires everything at launch.
  `HookServer` listens on 127.0.0.1:8765 (or every interface when "Listen
  on the network" is on) and reads `?profile=`, `SpeechPipeline` turns a reply
  into clips via `Speech/ReplyPlanner` and a Notification event into one
  clip via `Speech/QuipPlanner` (with `Speech/ToneClassifier` colouring
  the reply when tone is on), `Providers/` synthesise them
  (`ProviderRegistry` holds them all; `KokoroProvider` over `HelperProcess`,
  which keeps `Helpers/kokoro.py` alive and talks JSON lines to it;
  `BreezeProvider` does the same with `Helpers/breeze.py`, started only
  when a profile uses it, sending each clip's voice design and quality
  from `Settings/VoiceDesign.swift`; `PocketProvider` is a third helper,
  `Helpers/pocket.py`, with blether's own cloned voices in
  `Helpers/pocket-voices/` (ant blether-RiaQz, blether-xhLum); the four API providers share
  `SpeechHTTP`), `PlaybackQueue` plays them one
  at a time. The profile chooses the provider. The log is `~/Library/Logs/blether.log`;
  lines that would carry spoken or heard words go through `Log.content`,
  which hides them unless the user switched content logging on. `Settings/`
  holds the UserDefaults-backed store (`AppSettings`) and the settings
  window: `SettingsView` is a sidebar of pages (General, Profiles, Personas,
  TTS Providers, LLM, Listening) and each page is one or two `*Section`
  files. `DescriptionEditor` is the one sheet for adding or editing a
  persona or a Breeze voice design. `Speech/VoiceSampler` plays and caches the per-voice sample behind
  the Play buttons. `MenuBarIcon` draws the robot head in code as a template
  image; there is no icon asset. `LLM/` is the chat-completions client plus
  `LLMProvider`, the preset table (Anthropic, OpenAI, xAI, Mistral,
  compatible) and `FirstAnswerLLM`, which clears the first-run nudge.
- `Sources/Blether/Listening/`: one file per idea. `AudioInputDevice` lists
  mics through CoreAudio; `Microphone` captures through AVAudioEngine as
  16 kHz mono chunks; `SilenceDetector` is pure and clocked by chunk count;
  `Sounds` is the three cues; `Recording` is one attempt from arm to send
  or cancel, trimmed to the speech; `ModelStore` fetches the model into
  Application Support; `Transcriber` is an actor over the TranscribeCpp
  Model and Session; `Ears` owns the live recording and the privacy gate
  and hands text plus session key to a deliver closure; `SessionRegistry`
  is the pure lookup (id, then pid, then the only connection);
  `ChannelServer` is the second NWListener speaking JSON-RPC by hand.
  `PlaybackQueue.enqueue(onFinished:)` is how a reply's last clip arms the
  ears; the handler waits until nothing else is playing, and `stop()` fires
  it too. `setListening` in `Speaking.swift` is the one listening switch.
- `Packages/TranscribeCpp/`: the transcribe.cpp Swift binding, vendored from
  their tag v0.2.3 with a Package.swift that points at the release
  xcframework by URL and checksum. Their standalone SwiftPM mirror did not
  exist on 2026-09-19; when it does, delete this directory and point
  project.yml at it. The prebuilt framework is ad-hoc signed by its
  authors, which is why `Sources/Blether/Blether.entitlements` disables
  library validation (the hardened runtime stays on) and declares
  audio-input; without both the app either fails to launch or never shows
  the mic prompt. The usage string lives in project.yml, because
  `Sources/Blether/Info.plist` is generated by xcodegen and hand edits to
  it are lost.
- `hooks/claude-code-settings.example.json`: the hook. The Stop hook carries
  `?pid=$PPID`, which is the Claude Code process (verified 2026-09-19).
- `Tests/BletherTests/`: XCTest, one file per source file, fakes under
  `Support/` (including `fake_helper.py`, so the suite never needs uv or
  Kokoro, the mic, the model or the network; the channel tests use a real
  loopback socket on port 0). `make test` runs them; the app build is
  warning-free under strict concurrency and should stay so. The test
  target has a handful of older concurrency warnings nobody has fixed.
- `Blether.xcodeproj` is generated from `project.yml` by xcodegen and is
  not tracked. Nor is `local.mk`, which may hold a code-signing identity so
  every build is the same program to the keychain (README, "Build").

## An ant id quirk

ant ids are generated deterministically per database, so several ids here
(`blether-AkRXV`, `blether-VYQvH`, `blether-XKtxA`, `blether-Ed6UZ`) share
suffixes with unrelated notes in claude-speaks' database. If a note here
references a cs- id, it means the one in `../claude-speaks/.ant`, not a
sibling here. Always say which database when cross-referencing.

## Conventions

- British English in everything user-visible.
- Simple over clever. Small files. YAGNI. Resist abstracting for
  symmetry; the old providers folder is what that produces.
- The user has poor eyesight. UI uses text styles, never fixed font sizes,
  and every control has a label and is reachable by keyboard.
- No git commits, pushes or branch operations unless asked. Commits go
  through the user's `agent-commit` tool.
- The user cannot answer questions buried in a document. If a decision
  is needed, ask in the conversation, then record the answer in ant.
- Record load-bearing decisions in ant as you go, dated, marked as the
  user's decision or as a lean. A "yeah, whatever" to a Claude suggestion
  is not a decision; write it down as the lean it was. Track work in ait.
  When a slice's tasks are written, gate the distillation with the user.
- Do not run the amnesia checker unless the user asks for it. It is the
  same model reading the tickets without this conversation, it costs
  about ninety thousand tokens and six minutes a run, and when the same
  session is about to implement the tickets it finds little a careful
  re-read would not. Offer it, with the cost, when tickets will sit for
  another session to pick up.
- Acceptance criteria that need eyes or ears (an icon changing, a voice
  heard) are the user's to verify. Build, test, launch, and hand over with
  a plain-English list of what to check, written as sentences.
- Before a commit, run the exposure sweep from `ant show blether-XKtxA`
  (it takes its patterns from git config so nothing is typed into a
  transcript) and make sure it prints nothing.
- Relaunching blether closes every live channel; each session must `/mcp`
  reconnect. Say so when you hand a build over for a listening check.
- Writing to ait or ant: never `--description -` or `--body -` unless a real
  heredoc follows; read an entry before replacing its body, prefer notes
  over edits for anything the user may have written by hand, and read it
  back after. On 2026-09-19 an empty stdin blanked a ticket carrying the
  user's own notes; Time Machine got them back.

## Sibling repos

`../claude-speaks` and `../claude-listens` keep running as-is until
blether can replace them, then get archived with a pointer here. Do not
modify them from a blether session; if a fact about them matters, read
it from their code and write it down here.
