# CraftPeep

Peek into what's happening in technology, AI and the world.

CraftPeep is a native macOS app that collects technology and AI news from official feeds, removes duplicates,
shows where each story came from and how fresh it is, and (in later milestones) ranks, explains and pins it to
your desktop as widgets. Local-first, no account, sandboxed. Free and open source. Mac first, iPhone later.

**Status:** early development. The app fetches 16 feeds and the Hacker News front page, stores them in a local
SQLite database, and shows a searchable story list. There is no clustering, ranking, AI or widget rendering yet.
See [Docs/ROADMAP.md](Docs/ROADMAP.md) for what is done and what is next.

## What works today

- Refresh on launch (when stored stories are older than 15 minutes) and on demand with Cmd+R.
- RSS 2.0, RSS 1.0 and Atom parsing; Hacker News through the Algolia search API.
- Conditional requests, so unchanged feeds cost a 304.
- Plain-text cleaning of everything fetched, https only, per-response size and item caps.
- No duplicate stories from the same source across refreshes.
- Full-text search over titles and excerpts.
- Per-source health: a failing feed is listed with its error and never blocks the others.
- Works offline from the local store.
- The widget spec engine (declarative JSON models, validation, `{{ }}` expression interpreter). It is not
  connected to the app yet.

## Repository layout

| Path | Contents |
|---|---|
| `App/CraftPeep/` | macOS app (Xcode project, SwiftUI) |
| `Packages/CraftPeepKit/` | Swift package with all non-UI code |
| `Docs/` | Requirements, architecture, data sources, security, roadmap, decisions |
| `Schema/`, `Examples/` | Widget spec JSON Schema and example widgets (spec v0.1) |
| `scripts/build-dmg.sh` | Builds a Release app and packages it as a DMG (local use) |

Package targets:

| Target | Purpose | State |
|---|---|---|
| `Domain` | Value types and repository protocols. No I/O. | In use |
| `Persistence` | SQLite schema, migrations, repositories, full-text search (GRDB) | In use |
| `Ingestion` | HTTP client, feed parser, Hacker News adapter, cleaning, refresh service, source catalogue | In use |
| `WidgetSpec` | Codable widget models, loader, validation | Built, not wired to the app |
| `WidgetExpr` | Expression interpreter for widget files | Built, not wired to the app |
| `WidgetRuntime`, `WidgetRender` | Widget data binding and SwiftUI rendering | Not started |

## Getting started

Requires Xcode with Swift 6 and macOS 15 or later.

```sh
cd Packages/CraftPeepKit
swift test
```

Check the bundled feed list against the real network (not part of the normal test run):

```sh
cd Packages/CraftPeepKit
CRAFTPEEP_LIVE=1 swift test --filter LiveSmokeTests
```

Run the app: open `App/CraftPeep/CraftPeep.xcodeproj` in Xcode, choose **My Mac**, press Cmd+R.

Build a DMG for local use:

```sh
./scripts/build-dmg.sh
```

The DMG is not notarised, so macOS may block it on first launch: open System Settings > Privacy & Security
and choose **Open Anyway**.

## Privacy

CraftPeep has no account and sends no telemetry. It connects only to the feeds in
[sources.catalog.json](Packages/CraftPeepKit/Sources/Ingestion/Resources/sources.catalog.json), without cookies.
Stories are stored in the app's sandbox container. See [Docs/SECURITY.md](Docs/SECURITY.md).

## Dependencies

One: [GRDB.swift](https://github.com/groue/GRDB.swift) (MIT), pinned to an exact version.

## Acknowledgements

The idea of describing a widget in plain language came from other desktop widget apps. CraftPeep reimplements
concepts from scratch: no code, assets, names or branding from other apps.

## Licence

To be decided before the repository is made public. See ADR-012 in [Docs/DECISIONS.md](Docs/DECISIONS.md).
