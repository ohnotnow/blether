# CLAUDE.md

Hello. You are in blether, the Swift successor to two Python projects,
claude-speaks and claude-listens. As of 2026-09-16 nothing has been built
here: the repo holds this file, an ant notebook and an empty ait tracker.
The thinking that got us here is written down, so you do not have to
re-derive it or, worse, re-argue it.

## Read first, in this order

1. `ant foundation` in this directory. The vision: what blether is, the
   principles, what it is not. Read it before any design judgement.
2. `ant show blether-VYQvH`. The dated decisions table, the leaned-on
   shape of the app, the hard-won facts from both Python repos, and the
   user's deferred items.
3. Only if you need the history: `../claude-speaks` has `ant show
   cs-XKtxA` and `ant show cs-Ed6UZ` (the two conversations, including
   how two sessions went wrong), and `../claude-listens` has
   `TECHNICAL_OVERVIEW.md` for the channels wire contract.

## Things that are decided

Swift, one menubar app for speaking and listening. The name. Open source,
Makefile build, no App Store. Named sources carry provider plus voice plus
persona; the LLM is one global choice. Providers are personality, not
plumbing, and the provider list is the product. The full table with dates
is in the adr above. Do not re-open refactor-versus-rewrite; that cost the
user an evening already.

## Vocabulary

A speech service (Apple voices, ElevenLabs, OpenAI, xAI, Mistral, Kokoro)
is a **provider**. Never "engine": in the old code that meant Kokoro's
cli-versus-mlx setting, and using it for providers derailed a whole
conversation.

## An ant id quirk

ant ids appear to be generated deterministically per database, so the
first two entries here came out as `blether-AkRXV` and `blether-VYQvH`,
the same suffixes as `cs-AkRXV` and `cs-VYQvH` in claude-speaks (which
are the persona notes). If a note here references a cs- id, it means the
one in `../claude-speaks/.ant`, not a sibling here. Always say which
database when cross-referencing.

## Conventions

- British English in everything user-visible.
- Simple over clever. Small files. YAGNI. Resist abstracting for
  symmetry; the old providers folder is what that produces.
- No git commits, pushes or branch operations unless asked.
- The user cannot answer questions buried in a document. If a decision
  is needed, ask in the conversation, then record the answer in ant.
- Record load-bearing decisions in ant as you go, dated, marked as the
  user's decision or as a lean. Track work in ait.

## Sibling repos

`../claude-speaks` and `../claude-listens` keep running as-is until
blether can replace them, then get archived with a pointer here. Do not
modify them from a blether session; if a fact about them matters, read
it from their code and write it down here.
