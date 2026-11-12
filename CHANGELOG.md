# Changelog

Significant changes, newest first. Nothing has been released yet.

## Unreleased

### Added

- AI widget builder (M6b). Describe a widget in words; the model picks a widget from the gallery and its settings, which are checked against the catalogue, previewed with live data, and added only on approval. Existing widgets can be changed the same way.

- Widget platform, first part (M6a).
  - Several widgets on the desktop at once, each with its own size, settings and position. Schema v7.
  - Rising Repositories widget; `query` sources can now read repositories.
  - Widgets tab in Settings with a gallery, live previews and settings controls generated from each widget's definition.

- Developer Radar (M5a).
  - Fast-growing GitHub repositories from the official search API, with no token needed.
  - Star growth measured from CraftPeep's own daily readings; estimates are labelled as estimates.
  - Follow Releases adds a project's release feed, so new versions appear as stories.
  - Schema v6: repositories, star snapshots, key-value settings for the engine.

- First desktop widget (M4c), off by default.
  - Widget spec 0.2 with a `query` source that reads stories from the local store and needs no permissions.
  - `WidgetRuntime` and `WidgetRender`: declarative widget files drawn with native SwiftUI; nothing is executed.
  - News List widget in three sizes, in a desktop-level window that remembers where it was put.

### Changed

- Widget files may no longer ask for `commands` or `files` permissions; those were never implemented and are now refused.

- AI layer (M4b), off by default.
  - `AI` target with Anthropic and OpenAI-compatible providers over plain HTTPS; no SDK dependency.
  - Story summaries on request, cached; a daily briefing whose every item cites stored stories.
  - API keys in the Keychain; usage ledger with estimated cost; daily token limit. Schema v5.
  - AI settings pane with a plain statement of what is sent and to whom.

- Reading experience (M4a).
  - Three-pane window with Overview, AI Intelligence, Technology News and Saved.
  - Story detail showing every source, support level, the rule behind a label, and ranking reasons.
  - Read state, Read Later and Favourite; saved stories are never cleaned up. Schema v3.
  - Filter by kind; search within a section.
  - Settings: row density, menu bar item, open at login, sources (switch off, add, remove, health), interests and mutes.
  - Menu bar item with an unread count and the top unread stories.
  - Debug-only helper that lets the app photograph its own windows for UI checks.

### Fixed

- Publication dates in the future are now treated as missing. Scheduled posts in one feed had shown as "in 18 hours" and ranked as brand new. Schema v4 corrects stored rows.

### Added earlier

- Intelligence core (M3): `Intelligence` target.
  - Story clustering by shared URL and by headline similarity across sources within 72 hours.
  - Rule-based Hype Filter classification, recording which rule fired and a confidence band.
  - Verification status from source tiers; company, technology and topic tagging.
  - Ranking by named factors with human-readable reasons; interests and mutes.
  - Schema v2: clusters, cluster entities, interests.
- Due-based refresh with exponential backoff for failing sources, checked every five minutes.
- Retention: articles older than 90 days are not stored and are removed; fetch log kept 14 days.
- Catalogue grown from 17 to 34 verified sources.
- App: Top and Latest views with one row per story, reasons for ranking, and a popover listing every source.
- Opt-in live evaluation that prints clusters, labels and the ranked list from the real catalogue.

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
