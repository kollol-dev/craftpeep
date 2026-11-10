# Changelog

Significant changes, newest first. Nothing has been released yet.

## Unreleased

### Added

- Ingestion slice (M2): `Domain`, `Persistence` and `Ingestion` targets.
  - RSS 2.0, RSS 1.0 and Atom parser; Hacker News adapter using the Algolia search API.
  - HTTPS-only client with conditional requests, no cookies, a 5 MB response cap and a 200-item cap per feed.
  - Plain-text cleaning, URL canonicalisation, validation, per-source deduplication.
  - SQLite schema v1 (sources, articles, fetch log) with FTS5 search, through GRDB 7.12.0.
  - Bundled catalogue of 16 feeds plus Hacker News, each checked on 10 November 2026.
  - Refresh service: bounded concurrency, per-source failure isolation, health recorded per source.
- App: searchable story list, refresh on launch when stale and on Cmd+R, failing-source popover.
- Opt-in live smoke test for the catalogue (`CRAFTPEEP_LIVE=1`).
- Project documentation under `Docs/` and `CLAUDE.md`.

### Changed

- Product direction: intelligence platform with widgets as one surface (ADR-001).
- Package renamed from `WidgetProCore` to `CraftPeepKit`; `WidgetData` target renamed `WidgetRuntime`.
- Minimum macOS 15 (was 14 in the package and 26.6 in the app project). The package also declares iOS 18.
- App Sandbox now allows outgoing network connections.
- "WidgetPro" naming replaced in the widget schema and examples.

### Removed

- A duplicate copy of the widget spec tests that had been placed in `Sources/`.
