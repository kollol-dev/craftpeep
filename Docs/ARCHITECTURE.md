# CraftPeep Architecture

Status: accepted direction, 10 November 2026. Describes the target; see "Current state" for what exists. Where the code and this document differ, the differences are listed under "Implemented so far".

## Current state of the repository

| Exists | Notes |
|---|---|
| `Packages/CraftPeepKit` targets `Domain`, `Persistence`, `Ingestion`, `Intelligence` | Ingestion (M2) and clustering, classification, tagging, ranking (M3). 80 tests. |
| `WidgetSpec` (Codable models, loader, validation, spec 0.2) and `WidgetExpr` (lexer, parser, interpreter, 20 functions, templates) | 63 tests. Used by the desktop widget. |
| `WidgetRuntime`, `WidgetRender` | Store-bound widget resolution and rendering; one bundled widget (News List). 18 tests. |
| `App/CraftPeep` | Sandboxed app: three-pane reader, story detail, Settings, menu bar item. `App/` holds composition and the one `AppModel`; `Features/`, `MenuBar/` and `DesignSystem/` hold views. |
| `Docs/SPEC.md`, `Schema/widget.schema.json`, three example widgets | Spec v0.1 draft. |

### Implemented so far, and where it differs from the target below

- **Schema is at v8:** v8 adds `style` and `tint` to `widget_instance`. v7 adds `widget_instance` (which widget, its settings, size and position). Earlier: v5 adds summaries, briefings and the AI usage ledger; v6 adds repositories, star snapshots and a `meta` key-value table. Earlier: v3 adds `cluster_state` (read, saved, favourite); v4 is a data fix for future-dated articles. Earlier: v1 has `source`, `article`, `article_fts`, `fetch_log`; v2 adds `cluster`, `article.cluster_id`, `cluster_entity`, `interest`. User state, summaries, briefings, AI usage and widget instances arrive as later migrations with the code that uses them.
- **No `entity` table.** Entities come from the bundled rules file, so `cluster_entity` stores the name and kind directly. A table of entities becomes worthwhile when users can add their own.
- **`cluster.independent_count`** was added to the design: sources doing their own reporting, excluding community aggregators. Ranking uses it so that a Hacker News link to an article does not count as a second report.
- **No `title_sig` column.** Headlines are tokenised in memory at clustering time; a few thousand per run takes milliseconds.
- **Rules live in the package** at `Sources/Intelligence/Resources/classification.rules.json`. User overrides are not implemented.
- **Community signal is stored on the article** (`score`, `comment_count`, `discussion_url`) and the cluster's values are derived from its members.
- **Adapters do not fetch.** `SourceAdapter` supplies an Accept header and `parse`; `IngestionService` performs the request, so size limits and conditional requests are applied in one place.
- **The source catalogue is a package resource** at `Sources/Ingestion/Resources/sources.catalog.json`, not a top-level `Resources/` folder, so it is bundled without app-side configuration.
- **Scheduling is a loop in the app model**, not `NSBackgroundActivityScheduler`: every five minutes it asks ingestion to refresh whatever is due. There is no per-host rate limiter; six sources are fetched at a time and no host appears more than twice in the catalogue.
- **Views do not observe the database yet.** The app model reloads after a refresh.

The repository was started as a general widget app. The brief makes it an intelligence platform with widgets as one surface. The existing code is kept, because a declarative spec with a bounded expression interpreter is exactly the "never execute generated code" design the brief requires. What changes is what widgets bind to (see [WIDGET_SYSTEM.md](WIDGET_SYSTEM.md)) and the order of work.

## Technology choices

| Concern | Choice | Alternatives considered | Reasoning |
|---|---|---|---|
| Language | Swift 6, strict concurrency | | Already in use. Actors fit the ingestion pipeline. |
| UI | SwiftUI, with AppKit for desktop-level windows and the status item if needed | Pure AppKit | SwiftUI is enough for lists, detail and settings. Window level, collection behaviour and click-through are AppKit-only. |
| Persistence | SQLite through GRDB | SwiftData; raw SQLite C API; Core Data | See below. **Needs approval: new dependency.** |
| Search | SQLite FTS5 | Embeddings | FTS5 is sufficient for titles and excerpts and costs nothing. |
| Networking | URLSession | Alamofire | No need. |
| Feed parsing | Foundation `XMLParser` with our own RSS/Atom mapping | FeedKit | About 300 lines, no dependency, full control over size limits. Revisit if real-world feeds prove painful. |
| Charts | Swift Charts | | Native. |
| Secrets | Keychain (data protection keychain) | | Required. |
| Tests | Swift Testing for new code, XCTest stays for existing suites | | Both run under `swift test`. |
| Minimum OS | macOS 15, iOS 18 in the package manifest | macOS 14 (current manifest); macOS 26 | See DECISIONS.md ADR-004. |
| Distribution | Developer ID, notarised DMG first; sandboxed so the App Store stays possible | App Store first | Faster iteration; nothing planned needs to leave the sandbox. |

### Persistence: why GRDB

| Option | For | Against |
|---|---|---|
| **GRDB** | Direct SQL with typed records; FTS5 support; a migrator designed for versioned schemas; WAL with concurrent reads; database observation that drives SwiftUI; mature and widely used. | A third-party dependency (the only one proposed). |
| SwiftData | First-party, least code for simple models. | No FTS. Schema migration and background-context behaviour have been recurring pain points in public reports. Opaque SQL makes ingestion-scale upserts and ranking queries awkward. Weak fit for "data is a database" workloads. |
| Raw SQLite C API | No dependency. | We would write a worse GRDB: statement caching, row decoding, migrations, observation. |

The workload is thousands of inserts per day, deduplicating upserts, ranking joins and full-text search. That is a SQL workload. Repositories hide GRDB from everything above the persistence target, so the choice is reversible at one module boundary.

## High-level architecture

```
                        +--------------------------------------------+
                        |                 CraftPeep.app              |
                        |  Main window   Menu bar Pulse   Desktop    |
                        |  (SwiftUI)     (MenuBarExtra)   widget     |
                        |                                 windows    |
                        |                                 (NSPanel)  |
                        +-----------+------------+-----------+-------+
                                    |            |           |
                         observes   |            |           | renders spec + rows
                                    v            v           v
+----------------+        +-----------------------------------------+
|   AI layer     |<------>|            Intelligence layer           |
| Provider proto |  asks  |  Clustering  Classification  Ranking    |
| Anthropic      |  for   |  Briefing assembly   Store queries      |
| OpenAI-compat  |  text  +-------------------+---------------------+
| Usage ledger   |                            |
| Budget         |                            | reads / writes via repositories
+-------+--------+                            v
        |                 +-----------------------------------------+
        |                 |        Persistence (SQLite, GRDB)       |
        +---------------->|  articles  clusters  sources  FTS5      |
          usage records   |  summaries briefings widgets  ai_usage  |
                          +-------------------^---------------------+
                                              |
                                              | normalised articles
                          +-------------------+---------------------+
                          |            Ingestion layer              |
                          |  Scheduler -> Adapter -> Parse ->       |
                          |  Normalise -> Validate -> Dedupe ->     |
                          |  Persist        Rate limiter, backoff   |
                          +----+--------+--------+--------+---------+
                               |        |        |        |
                              RSS      HN     GitHub   Markets ...
                               |        |        |        |
                               v        v        v        v
                                  External sources (HTTPS)

   Widget pipeline:  Widget spec (JSON) -> validate -> bind store query -> SwiftUI template
   AI is never on the path between "External sources" and "Persistence".
```

Rules the diagram encodes:

1. UI reads the store and nothing else. It never calls an adapter or a provider directly.
2. Ingestion writes; intelligence reads and annotates; AI is called only by intelligence, with a budget check first.
3. Retrieved content flows down into the store as data. It never flows into anything that decides what the app does.

## Modules

One Swift package, several targets. Targets exist where a dependency boundary is worth enforcing, not for the diagram.

| Target | Depends on | Contents |
|---|---|---|
| `Domain` | nothing | Value types: `Article`, `StoryCluster`, `Source`, `SourceTier`, `StoryKind`, `Briefing`, `Interest`. Protocols for repositories and adapters. Pure, `Sendable`, no I/O. |
| `Persistence` | Domain, GRDB | Schema, migrations, repository implementations, FTS. |
| `Ingestion` | Domain | `SourceAdapter` protocol, RSS/Atom parser, HN adapter, HTTP client wrapper with conditional GET, rate limiter, scheduler, URL canonicaliser. |
| `Intelligence` | Domain | Clustering, rule-based classification, tagging, ranking, briefing assembly. Takes repository and AI protocols by injection. |
| `AI` | Domain | `AIProvider` protocol, Anthropic and OpenAI-compatible clients, usage ledger, budget, prompt templates. |
| `WidgetSpec` | nothing | Existing. |
| `WidgetExpr` | nothing | Existing. |
| `WidgetRuntime` | WidgetSpec, WidgetExpr, Domain | Replaces the placeholder `WidgetData`. Resolves a spec's data bindings to store queries and produces a view model. |
| `WidgetRender` | WidgetSpec, WidgetExpr | SwiftUI components and templates. |
| `DesignSystem` | nothing | Type scale, spacing, colour tokens, row and card components. |

Not created as separate modules until there is code that needs them: Notifications, MarketData (an adapter family inside Ingestion plus tables), Settings (a feature folder in the app), Dashboard (app feature folder), Networking (a file in Ingestion), Core.

The app target holds composition (dependency container built once at launch and passed down), feature views, window management and the menu bar.

## Directory structure

```
CraftPeep/
  CLAUDE.md
  README.md
  Docs/
  Schema/widget.schema.json
  Examples/
  Resources/
    sources.catalog.json          default feeds with tier and topics
    classification.rules.json     credibility and hype rules
  Packages/CraftPeepKit/          renamed from WidgetProCore
    Package.swift
    Sources/
      Domain/
      Persistence/
        Migrations/
        Repositories/
      Ingestion/
        Adapters/                 RSSAdapter, HackerNewsAdapter
        Parsing/
        Scheduling/
      Intelligence/
        Clustering/
        Classification/
        Ranking/
        Briefing/
      AI/
        Providers/
      WidgetSpec/
      WidgetExpr/
      WidgetRuntime/
      WidgetRender/
      DesignSystem/
    Tests/
      <Target>Tests/
      Fixtures/                   recorded feeds and API responses
  App/CraftPeep/
    CraftPeep.xcodeproj
    CraftPeep/
      App/                        entry point, composition, app delegate
      Features/
        Overview/  News/  AIIntelligence/  StoryDetail/  Saved/  Settings/
      MenuBar/
      Desktop/                    NSPanel hosting, placement persistence
  scripts/
```

## Data model (schema v1, MVP)

Types are SQLite. Timestamps are Unix seconds, UTC. IDs are integer primary keys unless stated.

```sql
CREATE TABLE source (
  id            INTEGER PRIMARY KEY,
  kind          TEXT NOT NULL,            -- rss | hackernews | github | ...
  name          TEXT NOT NULL,
  url           TEXT NOT NULL UNIQUE,     -- feed URL or adapter-specific locator
  site_url      TEXT,
  tier          TEXT NOT NULL,            -- official | documentation | reporting | analysis | community | unverified
  tier_origin   TEXT NOT NULL,            -- catalog | user
  topics        TEXT NOT NULL DEFAULT '[]',   -- JSON array
  priority      INTEGER NOT NULL DEFAULT 0,
  enabled       INTEGER NOT NULL DEFAULT 1,
  refresh_secs  INTEGER NOT NULL,
  etag          TEXT,
  last_modified TEXT,
  last_fetch_at INTEGER,
  last_ok_at    INTEGER,
  fail_count    INTEGER NOT NULL DEFAULT 0,
  last_error    TEXT
);

CREATE TABLE cluster (
  id             INTEGER PRIMARY KEY,
  headline       TEXT NOT NULL,           -- from the best-tier member
  first_seen_at  INTEGER NOT NULL,
  last_seen_at   INTEGER NOT NULL,
  member_count   INTEGER NOT NULL DEFAULT 1,
  kind           TEXT,                    -- hype filter category, NULL = unclassified
  kind_basis     TEXT,                    -- rule:<id> | model:<name>
  kind_confidence TEXT,                   -- high | medium | low
  verification   TEXT NOT NULL DEFAULT 'unverified',  -- official | corroborated | single_source | unverified
  hn_points      INTEGER,
  hn_comments    INTEGER
);

CREATE TABLE article (
  id            INTEGER PRIMARY KEY,
  source_id     INTEGER NOT NULL REFERENCES source(id) ON DELETE CASCADE,
  cluster_id    INTEGER REFERENCES cluster(id) ON DELETE SET NULL,
  external_id   TEXT,                     -- feed guid or HN item id
  url           TEXT NOT NULL,
  canonical_url TEXT NOT NULL,
  title         TEXT NOT NULL,
  excerpt       TEXT,                     -- plain text, length-capped
  author        TEXT,
  published_at  INTEGER,                  -- NULL if the source gave none
  retrieved_at  INTEGER NOT NULL,
  content_hash  TEXT NOT NULL,            -- hash of title + excerpt
  title_sig     TEXT NOT NULL,            -- normalised token signature for clustering
  UNIQUE (source_id, canonical_url)
);
CREATE INDEX article_canonical ON article(canonical_url);
CREATE INDEX article_cluster   ON article(cluster_id);
CREATE INDEX article_published ON article(published_at DESC);

CREATE VIRTUAL TABLE article_fts USING fts5(
  title, excerpt, content='article', content_rowid='id', tokenize='porter unicode61'
);

CREATE TABLE entity (
  id    INTEGER PRIMARY KEY,
  kind  TEXT NOT NULL,                    -- company | technology | topic | person
  name  TEXT NOT NULL,
  aliases TEXT NOT NULL DEFAULT '[]',
  UNIQUE (kind, name)
);
CREATE TABLE cluster_entity (
  cluster_id INTEGER NOT NULL REFERENCES cluster(id) ON DELETE CASCADE,
  entity_id  INTEGER NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
  basis      TEXT NOT NULL,               -- rule | model
  PRIMARY KEY (cluster_id, entity_id)
);

CREATE TABLE cluster_state (              -- user state, kept apart from content
  cluster_id INTEGER PRIMARY KEY REFERENCES cluster(id) ON DELETE CASCADE,
  read_at    INTEGER,
  saved_at   INTEGER,
  favourite  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE interest (
  id INTEGER PRIMARY KEY,
  entity_id INTEGER REFERENCES entity(id),
  keyword   TEXT,
  weight    INTEGER NOT NULL DEFAULT 1    -- -1 mute, 1 follow, 2 priority
);

CREATE TABLE summary (
  id           INTEGER PRIMARY KEY,
  cluster_id   INTEGER NOT NULL REFERENCES cluster(id) ON DELETE CASCADE,
  input_hash   TEXT NOT NULL,             -- hash of member content hashes + prompt version
  text         TEXT NOT NULL,
  provider     TEXT NOT NULL,
  model        TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  UNIQUE (cluster_id, input_hash)
);

CREATE TABLE briefing (
  id          INTEGER PRIMARY KEY,
  kind        TEXT NOT NULL,              -- morning
  for_date    TEXT NOT NULL,              -- local date YYYY-MM-DD
  body        TEXT NOT NULL,              -- structured JSON sections
  provider    TEXT, model TEXT,           -- NULL for the non-AI digest
  created_at  INTEGER NOT NULL,
  UNIQUE (kind, for_date)
);
CREATE TABLE briefing_cluster (
  briefing_id INTEGER NOT NULL REFERENCES briefing(id) ON DELETE CASCADE,
  cluster_id  INTEGER NOT NULL REFERENCES cluster(id) ON DELETE CASCADE,
  position    INTEGER NOT NULL,
  PRIMARY KEY (briefing_id, cluster_id)
);

CREATE TABLE ai_usage (
  id INTEGER PRIMARY KEY,
  at INTEGER NOT NULL,
  feature TEXT NOT NULL,                  -- summary | briefing | classify | widget_builder
  provider TEXT NOT NULL, model TEXT NOT NULL,
  input_tokens INTEGER, output_tokens INTEGER,
  est_cost_micros INTEGER,                -- NULL when the price is unknown
  outcome TEXT NOT NULL                   -- ok | error | budget_blocked
);

CREATE TABLE widget_instance (
  id          TEXT PRIMARY KEY,           -- UUID
  spec_json   TEXT NOT NULL,              -- validated spec
  settings    TEXT NOT NULL DEFAULT '{}',
  size        TEXT NOT NULL,
  screen_id   TEXT, x REAL, y REAL,
  created_at  INTEGER NOT NULL
);

CREATE TABLE fetch_log (                  -- trimmed to the last N days
  id INTEGER PRIMARY KEY,
  source_id INTEGER NOT NULL REFERENCES source(id) ON DELETE CASCADE,
  at INTEGER NOT NULL,
  status INTEGER, items_new INTEGER, bytes INTEGER, duration_ms INTEGER, error TEXT
);
```

Added in later schema versions: `instrument`, `quote`, `price_bar` (v0.2); `repository`, `repo_snapshot` (v0.2); `financial_fact`, `econ_series`, `econ_observation`, `calendar_event` (v0.3); `layout` (M7).

Design points:

- **Article versus cluster.** Articles are immutable facts about what a source published. A cluster is the story. User state, classification and summaries attach to the cluster, so reading one source marks the story read.
- **Provenance survives everything.** Clustering only sets `article.cluster_id`. Nothing is merged or deleted.
- **Classification records its basis.** A rule ID or a model name, plus a confidence band. No numeric scores.
- **Summaries are keyed by input hash.** Unchanged content is never summarised twice; a new member article changes the hash.
- **Retention.** Default 90 days for unsaved clusters, 14 days for `fetch_log`; saved and favourited clusters are kept. Backup is a copy of one SQLite file; export and import are explicit user actions through a save panel.

## Ingestion pipeline

```
Scheduler (per-source due time, jitter, pause when offline or on low power)
  -> RateLimiter (per host)
  -> Adapter.fetch(since:)            returns raw payload or notModified
  -> Adapter.parse                    throws on malformed input
  -> Normaliser                       strip HTML to text, cap lengths, canonical URL, timestamps to UTC
  -> Validator                        http(s) only, non-empty title, sane dates
  -> Deduper                          (source, canonical_url) upsert; content_hash change detection
  -> Clusterer                        assign cluster_id
  -> Classifier and Tagger            rules
  -> Repository.write                 one transaction per source
  -> fetch_log
```

```swift
protocol SourceAdapter: Sendable {
    var kind: SourceKind { get }
    func fetch(_ source: Source, validators: HTTPValidators?) async throws -> FetchResult  // .notModified | .payload(Data, HTTPValidators)
    func parse(_ payload: Data, source: Source) throws -> [RawItem]
}
```

Fetch and parse are separate so parsing is tested from fixtures with no network. Each source runs in its own task; one failure is logged against that source and does not cancel the group.

**Scheduling reality on macOS:** refresh happens only while the app is running, which is why it runs as a menu bar app with optional launch at login. There is no system-granted background refresh for a quit app. A briefing scheduled for 07:00 is generated at the first opportunity after 07:00, including after wake from sleep. `NSBackgroundActivityScheduler` handles coalescing and power awareness.

## Clustering

Tiered, cheapest first, each tier measurable:

1. **Same canonical URL** across sources (for example, an HN item pointing at an article already ingested from that publisher's feed). Canonicalisation lower-cases host, removes fragments and tracking parameters, and resolves known redirect patterns without extra requests.
2. **Title similarity inside a 72-hour window.** Normalised token sets (stop words removed, light stemming), Jaccard above a threshold, with a boost when both titles share a named entity from the entity list. Candidate lookup uses FTS on the two or three rarest title tokens, so it is not quadratic.
3. **Deferred:** on-device sentence embeddings (Apple's NaturalLanguage framework) if tier 2's miss rate, measured against a hand-labelled fixture set, is unacceptable. No vector database either way; a few thousand vectors fit a brute-force scan.

A labelled fixture of roughly 200 real headlines with expected groupings is built in M3 so thresholds are tuned against data, not intuition. Over-merging is worse than under-merging: a missed merge shows two rows, a wrong merge hides a story.

## Classification

Rules first, in a JSON file shipped with the app and overridable by the user.

- **Source tier:** set per source in the catalogue. User-added feeds default to `unverified` until the user chooses. No model ever assigns a tier.
- **Hype Filter kind:** ordered rules over source tier, URL host and path, and title patterns. Examples: an article from arxiv.org is a Research Paper; a GitHub release URL is Shipping; an official-tier source with "introducing" or "now available" is a Product Announcement; funding and acquisition verbs with a company entity are Funding/M&A. No rule match leaves it unclassified, which is displayed as such.
- **Optional AI refinement** (after MVP): only for unclassified clusters in the top ranks, batched, cached, stored with `kind_basis = model:<name>` and shown as a model judgement. Research is never downgraded to marketing for lacking a product; the rule order guarantees research sources resolve first.
- **Verification:** `official` if any member is official-tier; `corroborated` if two or more independent reporting-tier sources; otherwise `single_source` or `unverified`.

## Ranking

A sum of small, named factors, each of which can produce a human-readable reason:

| Factor | Reason text example |
|---|---|
| Best source tier in cluster | "Official announcement from Anthropic" |
| Independent sources | "Covered by 5 sources" |
| Community signal | "640 points on Hacker News" |
| Interest match | "Matches your interest: Swift" |
| Kind preference | "Code released" |
| Recency decay | (no text) |
| Muted topics | removes the item |

Weights live in one configuration struct and a later settings pane. The UI shows the top two or three reasons, never the number. Ranking is a query plus a small pure function, so it is unit-tested with fixed inputs.

## Concurrency and state

- Persistence is accessed through repository protocols backed by a GRDB pool; reads are concurrent, writes serialised.
- Ingestion is an actor owning the schedule. Intelligence functions are pure where possible and take data in, return data out.
- Views use `@Observable` models fed by database observation. No singletons; one container constructed in the app entry point.
- Errors are typed per layer (`IngestionError`, `ProviderError`, `PersistenceError`) and surface as per-source or per-feature status, never as a global alert for a background failure.

## iPhone readiness without building it

- `Domain`, `Persistence`, `Intelligence`, `AI`, `WidgetSpec`, `WidgetExpr` contain no AppKit. That is enforced by the package's iOS platform declaration compiling in CI.
- AppKit lives only in the app's `Desktop` and `MenuBar` folders.
- Sync is undecided and not designed. The schema keeps user state (`cluster_state`, `interest`, `widget_instance`) in separate small tables so that those, not the article corpus, are what a future sync moves.

## macOS platform findings

| Topic | Finding | Status |
|---|---|---|
| Desktop-level windows | A borderless `NSPanel` with its level set just above the desktop icon level and collection behaviour `canJoinAllSpaces`, `stationary`, `ignoresCycle` sits under app windows and stays put in Mission Control. Apple's documentation confirms `stationary` windows are unaffected by Mission Control. | Documented behaviour for `stationary`; the exact level choice needs a prototype. |
| Sandbox | Window levels and collection behaviours are not known to be sandbox-restricted. | To verify in the M4 widget slice. |
| Click handling on the desktop | Desktop-level windows receive clicks only when not covered; interaction with Finder's desktop icons and "click wallpaper to reveal desktop" needs testing. | Risk, prototype early. |
| Multiple displays | Persist by display UUID with a fallback to the main display when a screen is absent. | Design, M7. |
| WidgetKit | A separate extension with system-scheduled timelines and its own refresh budget; it cannot host our live windows. Would read a shared container. | Deferred. Do not conflate with desktop windows. |
| Menu bar | `MenuBarExtra` with window style covers the Pulse. Fall back to `NSStatusItem` plus popover only if it limits us. | Low risk. |
| Launch at login | `SMAppService.mainApp`. | Low risk. |
| Global shortcut | Carbon hot-key registration works in the sandbox without Accessibility permission. | Deferred, M7. |
| Dock presence | Switchable activation policy: regular while the main window is open, accessory when only the menu bar is in use. | Low risk. |
