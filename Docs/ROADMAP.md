# Roadmap

Status: proposed, 10 November 2026. Checkboxes reflect what is actually in the repository.

## Changes from the brief's roadmap, and why

| Change | Reason |
|---|---|
| Engine before UI polish: ingestion and persistence come before navigation and design system | The brief's own rule: no elaborate presentation over unreliable data. A headless engine is also the easiest thing to test. |
| A thin UI appears with the first data, then grows | Avoids both a UI with nothing in it and an engine nobody can look at. |
| One desktop widget is pulled forward into the MVP | The spec and expression engine already exist. One store-bound widget on the desktop proves the whole widget pipeline cheaply and tests the riskiest AppKit assumption early. |
| The AI widget builder moves after extended data | A builder with one template and one data type has nothing to choose between. |
| Markets gets a spike before it gets a milestone | Licensing and coverage are unknown; an hour with real keys decides the provider. |
| Learning and Company modules are reduced | See PRODUCT_REQUIREMENTS.md section 3. |

## Milestones

### M0 Discovery — complete except one item

- [x] Kakuchi site analysis
- [x] Reddit launch post analysis
- [ ] Reddit comment analysis (comments not available)
- [x] Requirements, MVP scope, architecture, data model, AI strategy, threat assessment
- [x] Data source research (several items marked for verification)

### M1 Decisions and housekeeping — complete

ADRs approved 10 November 2026.

- [x] Rename package to `CraftPeepKit`; rename "WidgetPro" in docs, schema and examples
- [x] Remove the duplicate spec test file in `Sources/`
- [x] Set platform minimums (macOS 15, iOS 18); add GRDB 7.12.0
- [x] Update README to match the new direction
- [x] App Sandbox with outgoing network only (it was already on; network client added)

Done when: `swift test` passes, the app builds sandboxed, README is accurate.

### M2 Ingestion vertical slice — complete

- [x] `Domain` types and protocols
- [x] `Persistence`: schema v1, migrator, article and source repositories, FTS
- [x] `Ingestion`: HTTP client with conditional GET, RSS and Atom parser, HN adapter, canonical URL, normaliser, validator, URL-level dedupe
- [x] Source catalogue with 16 verified feeds plus Hacker News
- [x] Refresh (on launch when stale, and manual) and a plain story list in the app, newest first, with source and timestamps
- [x] Tests from synthetic fixtures: well-formed, malformed, oversized, not-modified, duplicate, missing dates; database reopen test

Verified on 10 November 2026: 103 package tests pass; the live smoke test fetched 992 stories from 17 sources in about one second with no failures, and a second refresh added none (11 sources answered 304); the sandboxed app did the same on launch and kept its data across a relaunch. Not verified: the story list was not inspected visually or with VoiceOver.

Known gaps carried into M3: no automated test opens a database created by an older schema (there is only one schema so far); the size cap is tested through the fake client, not against a real oversized response.

Done when: launching the app and pressing refresh stores real stories from ten feeds and HN, a second refresh adds no duplicates and mostly receives 304s, and a relaunch shows the stored stories offline.

### M3 Intelligence core

- [ ] Scheduler with per-source intervals, backoff and health; launch at login; menu bar agent mode
- [ ] Clustering tiers 1 and 2, with a labelled headline fixture and measured precision and recall
- [ ] Rules engine: source tier, Hype Filter kind, verification status, entity and topic tagging
- [ ] Ranking with reasons; interests and mutes
- [ ] Catalogue grown to about 30 verified feeds
- [ ] Retention job

Done when: the same story from several sources shows as one cluster with all sources, each cluster shows a kind with its basis or "unclassified", and the ranked list is one I would actually read.

### M4 Intelligence experience (v0.1 release candidate)

- [ ] Design system: type scale, spacing, tokens, row and card components, three densities
- [ ] Navigation: Overview, AI Intelligence, Technology News, Saved, Settings
- [ ] Story detail, read state, read later, favourites, search
- [ ] Source management UI with health
- [ ] `AI` target: provider protocol, Anthropic and OpenAI-compatible clients, Keychain, ledger, budget
- [ ] Cluster summaries; morning briefing with the non-AI digest fallback
- [ ] Menu bar Pulse
- [ ] Widget slice: spec 0.2 `query` source, `WidgetRuntime`, `WidgetRender` for News List, one desktop-level panel with persisted position
- [ ] Accessibility pass; performance budgets measured

Done when: the v0.1 acceptance criteria in PRODUCT_REQUIREMENTS.md hold, and I have used it every weekday for two weeks. Changes from that fortnight take priority over M5.

### M5 Extended data (v0.2, part 1)

- [ ] Market data spike and provider decision; `MarketDataProvider`, quotes, bars, watchlist, Markets view
- [ ] GitHub adapter: rising repositories from search, star snapshots, release feeds; Developer Radar view
- [ ] Templates: Stock Watchlist, Single Metric, Metric Grid, Sparkline, Repository List

### M6 Widget platform (v0.2, part 2)

- [ ] Template catalogue and params schemas; Widget Gallery; My Widgets
- [ ] AI builder: generate, validate, retry, preview, install, conversational edits
- [ ] Multiple widgets, drag, resize between declared sizes, remove
- [ ] Optional AI classification refinement

### M7 Desktop experience

- [ ] Multi-display placement, saved layouts, always-on-top, stacks if still wanted
- [ ] Notifications for high-priority clusters, with a strict default threshold
- [ ] Global shortcut
- [ ] Hands-on review of Kakuchi's canvas behaviour before designing this

### M8 Companies and macro (v0.3)

- [ ] SEC EDGAR facts for the watchlist; Companies view; reported figures with period, currency and filing link
- [ ] FRED, ONS, BoE series; FX reference rates; economic calendar approach decided
- [ ] Weekly reports; evening briefing
- [ ] arXiv with interest filtering; Research List, Timeline, Comparison, Event Calendar templates

### M9 Production release

- [ ] Onboarding, empty states, error copy
- [ ] Performance, battery and memory profiling against budgets
- [ ] Security review against SECURITY.md; data source terms re-read
- [ ] Signing, notarisation, update mechanism (a decision of its own: Sparkle would be a second dependency)
- [ ] Decide App Store submission

### M10 iPhone

- [ ] iOS app on the shared package; WidgetKit widgets; sync design and decision

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Scope: seven modules, ten templates, three surfaces, two platforms | High | High | The MVP is two modules and one briefing. Nothing from M5 onward starts until v0.1 has been used daily for two weeks. |
| Briefing quality is mediocre, so the defining feature is not compelling | Medium | High | App selects, model explains; evaluation set; measure against the "would I read this" test early in M4, before polish. |
| Clustering over-merges or under-merges | Medium | Medium | Labelled fixture, conservative thresholds, bias towards under-merging, an "unmerge" action later if needed. |
| Market data cannot be licensed acceptably for free, especially UK and index values | High | Medium | User's own key; ETF proxies labelled as proxies; spike before committing; markets is not in the MVP. |
| Feeds for some AI labs do not exist | Medium | Medium | Verify per source; use HN coverage by domain and official alternates; never build on scraping. |
| Desktop-level windows behave badly with Spaces, Stage Manager, desktop-click-to-reveal or multiple displays | Medium | Medium | One widget in M4 exercises this early; full canvas deferred to M7; floating panel is the fallback surface. |
| Prompt injection produces misleading summaries | High | Low to medium | Structural limits in SECURITY.md; sources always visible. |
| Existing widget spec work pulls effort back towards a general widget app | Medium | Medium | Widgets bind to the store; `http` and `system` sources disabled; builder after data. |
| Background refresh expectations versus macOS reality | Medium | Low | Menu bar agent with launch at login; briefing generated on first wake after schedule; documented plainly. |
| Publisher or API terms change | Medium | Medium | Adapter boundary; per-source disable; terms recorded in DATA_SOURCES.md. |
| Single developer, evenings | High | Medium | Small milestones with a usable result each; M2 is deliberately a few sessions of work. |

## Recommended first implementation task

**M1 housekeeping (under an hour), then M2: the ingestion vertical slice.**

Why this and not navigation, the design system or the renderer:

- It is the foundation everything else reads from, and it has no dependency on any undecided question except the persistence choice.
- It is almost entirely pure logic, so it can be built test-first from recorded fixtures and verified without a UI.
- It produces something real on day one: actual stories in a list.
- It forces the schema, the adapter contract and the repository boundary into existence while they are cheap to change.

Scope, acceptance criteria and tests are listed under M2 above. Before starting it I need decisions on ADR-001 to ADR-004.
