# CLAUDE.md

Hello. You are in blether, a macOS menubar app in Swift that speaks Claude
CLI replies aloud. It is the successor to two Python projects, claude-speaks
and claude-listens. As of 2026-09-17 slices 1 to 3 and 6 are built: the
hook listener, a playback queue with a stop hotkey, one LLM that writes a
persona preamble and compresses long replies, a settings window with a
master on/off switch, and Kokoro-82M on MLX as the voice, run in a resident
Python helper. Listening and further speech providers are still to come. README.md says what the app does; this file says how we
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
6. The latest handover note (`ant list`, the newest "Handover" title). It
   says where things stand and what is next.
7. The `/swift` skill, if it is installed (`~/.claude/skills/swift/SKILL.md`).
   An informal notepad of macOS Swift gotchas from earlier projects, not
   rules. blether departs from it in one place: no App Sandbox (see the
   decisions table for why).
8. Only if you need the history and have the sibling checkouts:
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
preamble) and, from slice 4, notification. In the settings window they are
shown as Reply and Preamble.

## Layout

- `Sources/Blether/`: `BletherApp.swift` wires everything at launch.
  `HookServer` listens on 127.0.0.1:8765, `SpeechPipeline` turns a reply
  into clips via `Speech/ReplyPlanner`, `Providers/` synthesise them
  (`KokoroProvider` over `HelperProcess`, which keeps `Helpers/kokoro.py`
  alive and talks JSON lines to it), `PlaybackQueue` plays them one at a
  time. The log is `~/Library/Logs/blether.log`. `Settings/` holds the
  UserDefaults-backed store (`AppSettings`) and the settings window, one
  file per section. `LLM/` is the chat-completions client.
- `Tests/BletherTests/`: XCTest, one file per source file, fakes under
  `Support/` (including `fake_helper.py`, so the suite never needs uv or
  Kokoro). `make test` runs them; the build is warning-free under strict
  concurrency and should stay so.
- `Blether.xcodeproj` is generated from `project.yml` by xcodegen and is
  not tracked.

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

## Sibling repos

`../claude-speaks` and `../claude-listens` keep running as-is until
blether can replace them, then get archived with a pointer here. Do not
modify them from a blether session; if a fact about them matters, read
it from their code and write it down here.
