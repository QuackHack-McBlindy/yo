# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Fixed

### Removed

## [0.2.5] - 08-30-2026

### Added
- `voice.speak` option per script to send stdout to text‑to‑speech after execution.
- `TranscriptionProcessor` in `transcription.rs` encapsulating transcription and command execution.
- Helper functions for sound playback, async notifications, and IP persistence.

### Changed
- `yo-rs` main server rewritten with Tokio async runtime; network handlers now use async streams.
- Default Whisper model changed from `small` to `tiny` in `packages/yo-rs.nix`.
- Changed `lib.foldl` to strict `lib.foldl'` in `assertions.nix` for prefix conflict detection to reduce the risk of stack overflow.

### Fixed

### Removed

## [0.2.4] - 08-28-2026

### Added
- Unit tests for matching logic, normalization, optional words, and fuzzy behavior.
- `tempfile` as a dev dependency for testing.
- `ttsClients` option in `services.nix` to hardcode client IPs for TTS streaming.
- Transcription benchmark logging to `~/.config/yo/whisper-bench.txt`.
- `match_type` field in `MatchResult` to distinguish exact and fuzzy matches.

### Changed
- Upgraded `whisper-rs` from 0.8 to 0.16, with API adaptations (e.g., `WhisperContext::new_with_params`, `full_n_segments`, `get_segment`).
- Fuzzy matching now evaluates all sentence patterns and validates extracted parameters, returning a fallback result if validation fails.
- `normalize_input` also removes apostrophes and collapses extra whitespace.
- Loading split words and sorry phrases now returns empty vectors instead of panicking if files are missing or invalid.
- Output message now uses "quack!" for exact matches and "quack?!" for fuzzy matches.
- Execution time line now prefixed with "**Execution time**".
- Version bumped to 0.2.4.
- Nix module changes: disabled `fuzzy` command parameter (temporary), added number formatting for large counts, changed help output structure, and added `/etc/yo/table.md`.
- `yo-say` now reads `clients.json` from both `$HOME/.config/yo/` and `/etc/yo/`.
- CI workflow: commented out Rust test step.

### Fixed
- Parameter extraction for fuzzy matches with multiple patterns now correctly maps input words to pattern placeholders.
- Transcription timing now always measured and logged (removed debug-gating).

### Removed
- `fuzzy` command parameter temporarily disabled (commented out in module.nix).
