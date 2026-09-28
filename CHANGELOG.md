# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-09-28

### Changed
- ElevenLabs now uses its `eleven_v4` model.
- ElevenLabs audio tags are no longer limited to a fixed list: the summariser may add up to three that describe the voice, and use capitals and punctuation for emphasis.

### Fixed
- The summariser now actually adds ElevenLabs and xAI tags. Its prompt had banned tags outright and only allowed them in an exception at the end, so smaller LLMs never used them.

## [1.0.0] - 2026-09-27

The first release: a macOS menubar app that speaks Claude Code replies aloud
and listens for your answer.

### Added
- Hook listener that speaks each Claude Code reply, with a playback queue and a stop hotkey.
- An LLM that writes an in-character preamble, compresses long replies and quips when Claude is waiting.
- Profiles pairing a provider with a voice and persona per role, chosen per hook with `?profile=`.
- Local providers Kokoro-82M, Breeze-TTS-2 and Pocket TTS, plus ElevenLabs, OpenAI, xAI, Mistral and Gemini via OpenRouter.
- Optional tone, a mood label per reply that some voices express.
- Optional listening: on-device transcription that sends your spoken answer to the right Claude Code session.
- Word lists for mishearings and pronunciations, and a `heard_words` channel tool.
- Remote mode to accept replies from other machines on the LAN.
- A background stream player that ducks under speech.
- Settings window, menubar robot icon, app icon and `make install`.

[Unreleased]: https://github.com/ohnotnow/blether/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/ohnotnow/blether/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ohnotnow/blether/releases/tag/v1.0.0
