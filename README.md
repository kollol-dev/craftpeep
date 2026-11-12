# CraftPeep

Peek into what's happening in technology, AI and the world.

CraftPeep is a native macOS app that collects technology and AI news from official feeds, groups reports of the
same story, shows where each one came from and how fresh it is, and ranks them with the reasons visible. Later
milestones add briefings and desktop widgets. Local-first, no account, sandboxed. Free and open source. Mac first, iPhone later.

**Status:** early development. The app fetches 33 feeds, the Hacker News front page and GitHub's search API, groups reports of the
same story, labels and ranks them by rules, and presents them in a three-pane reader with a menu bar companion.
Optional AI summaries and a daily briefing are built but have not yet been run against a real model. Two desktop widgets are included (News List and Rising Repositories); none is on the desktop until you add it.
See [Docs/ROADMAP.md](Docs/ROADMAP.md) for what is done and what is next.

## What works today

- Each source refreshes on its own interval while the app runs; failing sources back off. Cmd+R refreshes everything.
- One row per story: the same story from several sources is grouped, with every source listed.
- Rule-based labels (shipping, announcement, research, funding and so on) that record which rule fired. Most stories are left unlabelled rather than guessed.
- Top view ranked by source authority, independent coverage, community interest and recency, with the reasons shown. Latest view is newest first.
- Overview, AI Intelligence, Technology News and Saved views; a detail pane listing every source for a story.
- Read state, Read Later and Favourite. Filter by kind. Follow or mute companies, technologies and words.
- Developer Radar: fast-growing GitHub repositories, with each growth figure marked as measured or estimated; follow a project's releases in one click.
- Add your own RSS or Atom feeds; switch any source off.
- A menu bar item showing how many top stories are unread.
- Stories older than 90 days are dropped unless you saved them.
- RSS 2.0, RSS 1.0 and Atom parsing; Hacker News through the Algolia search API.
- Conditional requests, so unchanged feeds cost a 304.
- Plain-text cleaning of everything fetched, https only, per-response size and item caps.
- Full-text search over titles and excerpts.
- Per-source health: a failing feed is listed with its error and never blocks the others.
- Works offline from the local store.
- Desktop widgets: a News List and Rising Repositories, each defined as a declarative JSON file and drawn natively. Add as many as you like from Settings → Widgets. Widgets read the local store;
  they cannot fetch, run commands or read files.

## Repository layout

| Path | Contents |
|---|---|
| `App/CraftPeep/` | macOS app (Xcode project, SwiftUI) |
| `Packages/CraftPeepKit/` | Swift package with all non-UI code |
| `Docs/` | Requirements, architecture, data sources, security, roadmap, decisions |
| `Schema/`, `Examples/` | Widget spec JSON Schema (v0.2) and example widgets written for v0.1; the examples use network sources the app does not run |
| `scripts/build-dmg.sh` | Builds a Release app and packages it as a DMG (local use) |

Package targets:

| Target | Purpose | State |
|---|---|---|
| `Domain` | Value types and repository protocols. No I/O. | In use |
| `Persistence` | SQLite schema, migrations, repositories, full-text search (GRDB) | In use |
| `Ingestion` | HTTP client, feed parser, Hacker News adapter, cleaning, refresh service, source catalogue | In use |
| `Intelligence` | Clustering, classification rules, tagging, ranking | In use |
| `AI` | Provider clients, Keychain, usage ledger and budget, summaries, briefing | In use, untested against a live model |
| `WidgetSpec` | Codable widget models, loader, validation | In use |
| `WidgetExpr` | Expression interpreter for widget files | In use |
| `WidgetRuntime` | Resolves a widget's settings and store queries; holds the bundled widgets | In use |
| `WidgetRender` | Pure render tree and the SwiftUI views that draw it | In use |

## Getting started

Requires Xcode with Swift 6 and macOS 15 or later.

```sh
cd Packages/CraftPeepKit
swift test
```

Two tests use the real network and only run on request. The first checks every bundled feed; the second prints
what clustering, labelling and ranking make of today's news:

```sh
cd Packages/CraftPeepKit
CRAFTPEEP_LIVE=1 swift test --filter LiveSmokeTests
CRAFTPEEP_LIVE=1 swift test --filter LiveEvaluationTests
```

Run the app: open `App/CraftPeep/CraftPeep.xcodeproj` in Xcode, choose **My Mac**, press Cmd+R.

Build a DMG for local use:

```sh
./scripts/build-dmg.sh
```

The DMG is not notarised, so macOS may block it on first launch: open System Settings > Privacy & Security
and choose **Open Anyway**.

## Privacy

CraftPeep has no account and sends no telemetry. AI is off unless you switch it on and supply your own key or a local model; when on, it sends the headlines and excerpts of the stories being summarised to the provider you chose, and nothing else. Otherwise it connects only to the feeds in
[sources.catalog.json](Packages/CraftPeepKit/Sources/Ingestion/Resources/sources.catalog.json), without cookies.
Stories are stored in the app's sandbox container. See [Docs/SECURITY.md](Docs/SECURITY.md).

## Dependencies

One: [GRDB.swift](https://github.com/groue/GRDB.swift) (MIT), pinned to an exact version.

## Acknowledgements

The idea of describing a widget in plain language came from other desktop widget apps. CraftPeep reimplements
concepts from scratch: no code, assets, names or branding from other apps.

## Licence

To be decided before the repository is made public. See ADR-012 in [Docs/DECISIONS.md](Docs/DECISIONS.md).
