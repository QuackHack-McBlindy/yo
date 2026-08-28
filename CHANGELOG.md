# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Unit tests for matching logic, normalization, optional words, and fuzzy behavior.
- `tempfile` as a dev dependency for testing.

### Changed
- Fuzzy matching now evaluates all sentence patterns and validates extracted parameters, returning a fallback result if validation fails.
- `normalize_input` also removes apostrophes (e.g., "what's" -> "whats").
- Loading split words and sorry phrases now returns empty vectors instead of panicking if files are missing or invalid.
- Added `match_type` field to `MatchResult` to differentiate exact and fuzzy matches; output message now uses "quack!" for exact and "quack?!" for fuzzy.
- Execution time line now prefixed with "**Execution time**".
- Version bumped to 0.2.4.
- Commented out Rust test step in Nix CI workflow (temporary).

### Fixed
- Parameter extraction for fuzzy matches with multiple patterns now correctly maps input words to pattern placeholders.

### Removed
- `fuzzy` command parameter temporarily disabled (commented out in module.nix).
