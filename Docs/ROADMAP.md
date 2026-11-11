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

### M3 Intelligence core — complete, with three items moved to M4

- [x] Scheduling: per-source intervals, exponential backoff for failing sources (capped at a day), checked every five minutes while the app runs
- [x] Clustering tiers 1 and 2, with a labelled headline fixture and measured precision and recall
- [x] Rules engine: Hype Filter kind with the rule that fired, verification status, entity and topic tagging
- [x] Ranking with reasons; interests and mutes in the store and the ranker
- [x] Catalogue grown to 34 verified sources
- [x] Retention: articles older than 90 days are neither stored nor kept; fetch log kept 14 days
- [x] App: Top (ranked, last three days) and Latest views, one row per story, a popover listing every source for a story

Moved to M4, because they are UI that belongs with Settings and the menu bar: launch at login, menu bar agent mode, and a screen for editing interests and mutes. Until then interests can only be set in the database.

Measured on 10 November 2026:

- Labelled fixture (60 synthetic headlines, 12 multi-article stories): pairwise precision 1.00, recall 0.73. No wrong merges. The misses are same-story pairs whose headlines share few words.
- Live catalogue (965 articles, 34 sources, no failures): 8 multi-source stories found, all 8 correct on inspection, clustered in under half a second. Recall on live data is unknown; I saw at least one missed pair (two differently worded reports of the same share listing).
- Classification on live data: 111 of 957 stories received a kind; the rest are honestly unclassified. A first pass of the rules mislabelled several headlines ("toilet paper" as research, "might" as speculation); those rules were tightened and the cases are now tests.
- The existing database from M2 migrated in place (schema v1 to v2) on launch.

Not verified: the Top/Latest switch, the sources popover and the row layout have not been looked at on screen.

Known limits carried forward:

- Title-only clustering will keep missing differently worded reports of one story. The next step, if it matters in daily use, is rarity weighting of tokens or on-device sentence embeddings (tier 3). Measure first.
- Two Hacker News submissions pointing at a site's home page would merge by URL.
- Entity tagging is by name, so "Claude Monet" tags Anthropic. Recorded as a test.
- A cluster is not recomputed when one of its sources is deleted; there is no way to delete a source yet.
- Most stories have no kind. Raising coverage needs either many more rules or the optional model pass planned for v0.2.

### M4 Intelligence experience (v0.1 release candidate) — split into three

M4 was too large to build and check as one piece, so it is split. The first part is done.

#### M4a Reading experience — complete

- [x] Three-pane window: sidebar (Overview, AI Intelligence, Technology News, Saved), story list, story detail
- [x] Story detail: every source with tier and time, support level, kind with the rule that produced it, timeline, ranking reasons
- [x] Read state, Read Later, Favourite; saved stories are exempt from clean-up
- [x] Search within a section; filter by kind
- [x] Overview header: a plain count of the last day (not AI)
- [x] Settings: story row density, menu bar item, open at login, sources (switch off, add a feed, remove an added feed, health), interests and mutes
- [x] Menu bar item with unread count of the top 20 stories, five unread stories, refresh, open app
- [x] Keyboard: Cmd-1 to 4 for sections, Return to open, Cmd-D Read Later, Shift-Cmd-D Favourite, Cmd-U mark unread, Cmd-R refresh
- [x] Fix: publication dates in the future are treated as missing (a feed's scheduled posts had shown as "in 18 hours" and ranked as new)

Checked on 11 November 2026: 150 package tests pass. The app photographs its own windows in a debug mode, and from those pictures the story list, detail pane, Overview header, Settings tabs and menu bar panel were inspected. Not checked: the sidebar and toolbar buttons (translucent chrome comes out blank in the self-capture), keyboard shortcuts, VoiceOver, open at login, and adding a feed through the UI.

Not done from the original M4a intent, and why:

- A separate `DesignSystem` package target. The shared styles are one small file in the app; a target would be ceremony.
- Hiding the Dock icon when only the menu bar is in use. The app keeps running with its window closed, which is the part that matters for refresh.
- Source priority ordering. Interests already do this job per topic.

#### M4b AI layer — built; not yet exercised against a real model

- [x] `AI` target: provider protocol, Anthropic (Messages API) and OpenAI-compatible clients, Keychain storage, usage ledger, daily token budget, one retry on transient failures
- [x] Story summaries on request, cached by the content of the story's articles
- [x] Daily briefing answering the brief's questions; every item must cite stories it was given, or it is dropped
- [x] The Overview count stays as the fallback when AI is off or fails
- [x] AI settings pane: provider, model, key, daily limit, automatic briefing (off by default), test connection, usage today, and a statement of what is sent
- [x] Schema v5: summaries, briefings, usage ledger

Checked on 11 November 2026:

- 184 package tests pass. The AI tests use recorded response shapes and cover request bodies, headers, error mapping, refusal and truncation, budget, retry, caching, and a prompt-injection fixture.
- The real network transport reached the Ollama server on this Mac and mapped its "model not found" reply correctly.

Not checked, and it matters:

- **No real model has written a summary or briefing yet.** No API key was available to the build process, and the local Ollama server has no model installed. The quality of the prompts is therefore unknown, and the exact request shape has not been accepted by a live Anthropic or OpenAI endpoint.
- The Keychain store has not been exercised inside the sandboxed app.
- The OpenAI-compatible request details (token parameter names, `response_format`) are from memory, not from current provider documentation.

Choices made here that differ from AI_STRATEGY.md as first written:

- **One model for everything, default Claude Opus 5.5.** The plan was a cheap model for summaries and a stronger one for the briefing. A per-feature model picker is more settings than the feature has earned; the user can choose Haiku 5.5 for everything if cost matters. Summaries run at low effort, the briefing at medium.
- **Summaries are written only when asked.** Automatic summarising of the top stories after each refresh was planned and left out: it spends money without the user acting. The briefing can be made automatic, and that is off by default.
- **Interest keywords are not sent** to the provider at all, which is stricter than planned.
- **No provider fallback chain** (cloud to local). For Claude models that support it, the request asks Anthropic to retry a declined request on another of its models within the same call.
- **Briefing story links are stored inside the briefing**, not in a join table.

#### M4c First widget

- [ ] Spec 0.2 `query` source, `WidgetRuntime`, `WidgetRender` for News List, one desktop-level panel with persisted position

#### Before calling it v0.1

- [ ] Accessibility pass with VoiceOver; performance budgets measured
- [ ] Two weeks of daily use; changes from that fortnight take priority over M5

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
