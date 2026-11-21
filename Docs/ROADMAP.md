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
- Fixed 21 November 2026: near-identical submissions to one community source now join, and Show/Ask/Tell/Launch HN posts join only by link. Labelled fixture after the change (64 headlines): precision 1.00, recall 0.74. No same-source duplicates were on the live front page that day, so the live effect is unmeasured; the reported case is a test.
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

#### M4c First widget — complete

- [x] Spec 0.2: a `query` data source that reads stories from the local store; the `commands` and `files` permissions are refused
- [x] `WidgetRuntime`: resolves a widget's settings and queries against the store, through the same ranking and mutes the main window uses
- [x] `WidgetRender`: a pure render tree (tested without a screen) and SwiftUI views that draw it
- [x] News List, shipped as an ordinary widget file with three sizes and two settings
- [x] A desktop-level window, draggable, with its position remembered; a Widget tab in Settings (off by default)
- [x] States drawn: loading, stories, nothing to show, failure; freshness always stated, old data says it is old

Checked on 11 November 2026: 206 package tests pass. From the app's own screenshots, the widget drew six real ranked stories from its JSON definition, and the Widget settings tab rendered. With the widget switched on, the system reported its window at the level just above the desktop icons, below normal windows, at the saved position.

Not checked: dragging the window and the position being saved by a real drag; clicking a headline in the desktop window; behaviour across Spaces, Mission Control, Stage Manager and a second display; how the translucent background looks over a wallpaper.

Decisions that differ from WIDGET_SYSTEM.md as first written:

- **The News List is a widget file with settings, not a "template plus params".** A bundled file whose settings the user adjusts is the same idea with one fewer mechanism. A separate template layer can be added if the AI builder needs it.
- **Size decides how many stories show** (3, 6, 10), using the spec's per-size views.
- **The widget's placement is in preferences, not a `widget_instance` table**, while there is exactly one widget.
- **The query collection is called `stories`**, not `clusters`: it is the word the user sees.
- **Spec 0.1 files still load.** Nothing was removed from 0.1 except the two permissions that were never implemented.

#### Before calling it v0.1

- [ ] Accessibility pass with VoiceOver; performance budgets measured
- [ ] Two weeks of daily use; changes from that fortnight take priority over M5

### M5 Extended data (v0.2, part 1) — GitHub done; markets waiting on a decision

#### M5a Developer Radar — complete

- [x] GitHub adapter on the official repository search API, without a token: three searches per refresh, at most every six hours, one hour after a failure
- [x] Star snapshots, one per repository per day; growth measured between CraftPeep's own readings
- [x] Ranking by stars per day, stating for each repository whether the figure is measured or an estimate from age
- [x] Developer Radar view: language filter, search, detail pane, open on GitHub
- [x] Follow Releases: adds a repository's own release feed as a source, so new versions arrive as stories labelled Shipping
- [x] Schema v6: repositories, snapshots, a small key-value table

Checked on 12 November 2026: 218 package tests pass. A live run fetched 131 repositories with no failed queries. GitHub's response headers confirmed the unauthenticated search limit of ten requests a minute.

Known limits:

- **Every figure is an estimate until the second day.** With one reading there is nothing to measure against, so the list shows "stars since creation" and says so. Older repositories only appear once two readings exist.
- **Candidates are limited to what three searches return** (new repositories, and active ones tagged `llm` or `ai-agents`). A fast-growing older project outside those tags will not be seen. Widening this is a matter of adding searches.
- **No GitHub token support.** Not needed at this request rate; it would raise the limits if more searches are added.
- **Security advisories are not included.**

#### M5b Markets — deferred by the owner on 12 November 2026

No market code will be written until a source for UK shares and index levels is found. The findings below stand.

Research on 12 November 2026, from the providers' own pages (details in DATA_SOURCES.md):

- **Twelve Data, free plan:** 8 requests a minute, 800 a day; real-time US shares and ETFs and real-time forex. London-listed shares are not on the free plan (end-of-day global data starts at the $79 plan). Whether index values are available on any plan was not stated on the pages read. Free-plan data may not be used commercially.
- **Finnhub:** pricing and API pages could not be read (JavaScript only). Its terms say every listed plan is for personal use only.
- **Neither set of terms addresses an app that ships no key and has each user bring their own.**

So a free key can cover the seven US watchlist companies and GBP/USD and EUR/GBP, with quotes and daily history. It cannot cover FTSE 100 constituents or, as far as the pages show, index levels. Options are in DECISIONS.md under ADR-010.

- [x] Decision: deferred
- [ ] `MarketDataProvider`, quotes, daily bars, watchlist, Markets view
- [ ] Templates: Stock Watchlist, Single Metric, Sparkline, Repository List

### M6 Widget platform (v0.2, part 2) — split in two

#### M6a Several widgets, a gallery, generated settings — complete

- [x] `query` sources can read repositories as well as stories
- [x] A second bundled widget, Rising Repositories, defined entirely as a widget file
- [x] Any number of widgets on the desktop, each with its own size, settings and remembered position (schema v7)
- [x] Widgets tab in Settings: what is on the desktop, and a gallery with a live preview and Add to Desktop
- [x] Each widget's settings controls are generated from the settings its file declares; a new widget needs no settings code
- [x] Right-click a desktop widget for its size, Settings, and Remove

Checked on 12 November 2026: 225 package tests pass. From the app's own screenshots, both widgets drew real data from their JSON definitions, and the Widgets tab listed two test widgets with controls generated from their declared settings. With those two widgets stored, the system window list showed two windows at desktop level with the right sizes, one at its saved position and one at the default. The test widgets were then removed.

Not checked by a person: dragging, right-click menus on the desktop, the generated controls being operated, and how several widgets behave across Spaces and displays.

Not built, from the original M6 list:

- **Resizing by dragging.** Size is a three-way choice, which is what the spec's per-size views support.
- **A separate My Widgets screen.** The Widgets tab in Settings does that job.
- **Importing a widget file from disk.** The loader and validator exist; there is no file picker yet. Worth adding with the builder, since both need an install-and-review step.

#### M6b AI widget builder — built; not yet run against a real model

- [x] Describe a widget in words; the model chooses a widget from the gallery, a size, and values for the settings that widget declares, or says nothing fits
- [x] Every part of the answer is checked against the catalogue: an invented widget is rejected (with one corrective retry), and an unknown setting or disallowed value is dropped and shown to the user as left out
- [x] A live preview with real data, then Add to Desktop or Discard; nothing is installed without approval
- [x] Change with Words on an existing widget; what the request does not mention is kept
- [x] Without AI, the gallery and the ordinary settings controls do everything the builder does

Checked on 12 November 2026: 236 package tests pass, the builder's with recorded replies.

Not checked: **the builder has never spoken to a real model**, like the rest of the AI layer, so how well a model follows the catalogue is unknown. The flow in the Widgets tab has not been operated.

What the builder is, and is not: with two widgets and three settings between them, it is a natural-language front end to choices the gallery already offers in two clicks. Its value grows with the catalogue. It does not compose layouts or write widget files, by design.

Not built: optional AI classification refinement for unlabelled stories. It should wait until the AI layer has been seen working.

#### M6c Widget appearance — complete (owner request, 14 November 2026)

- [x] Five styles per widget, in the spirit of the system's own: Automatic (translucent, follows the Mac), Light, Dark, Clear, Tinted (filled with the widget's colour)
- [x] Nine colours per widget, used for the header and, when tinted, the background
- [x] Native-feeling chrome: the system widgets' large continuous corner, a hairline edge, and solid white text on tinted widgets where the system's translucent label colours wash out
- [x] Both bundled widgets have a header with a symbol in the widget's colour
- [x] Style and colour from the right-click menu on the desktop, or in Settings → Widgets with colour swatches and a live preview beside each widget
- [x] Schema v8 (style and tint per widget). Widget files are unchanged: their "accent" colour now means the colour the user picked

Checked on 14 November 2026: 236 package tests pass. From the app's own screenshots, all five styles drew the News List correctly, and two test widgets stored with the tinted and light styles appeared as real desktop windows in those styles. The test widgets were removed.

Not checked: the Clear style over a real wallpaper (the screenshots have no wallpaper behind them, so Clear looks like Dark there); the colour swatches and menus being operated.

Not built: free colour choice (nine fixed colours keep every combination legible), per-widget fonts, background images, and editing a widget's layout by hand. A layout editor would mean editing widget files directly, which is a much larger feature; say if you want it.

### Reader basics — complete (owner request after the NetNewsWire comparison, 21 November 2026)

- [x] JSON Feed 1.0 and 1.1, alongside RSS and Atom
- [x] OPML import (flattens folders, upgrades plain http to https, skips anything that is not a web address, marks every imported feed Unverified) and export (feed sources only)
- [x] Each enabled source listed in the sidebar; selecting one lists every story it reported, newest first
- [x] Mark All as Read for whatever list is showing (toolbar, Story menu, Command-K)
- [x] File entitlement widened from read-only to read-write for files the user picks, so an export can be saved

Checked: 253 package tests pass; two real JSON Feeds (jsonfeed.org and Daring Fireball) parsed fully; the built app carries the read-write user-selected file entitlement. Not checked: the import and export panels being operated, and importing a large real OPML file.

Still open from the comparison: single-key shortcuts, a stale-sources list, and an option to hide the unread badge.

### Reader basics, second part — complete (21 November 2026)

- [x] Single-key shortcuts while the story list has focus: J/K, Space or N for the next unread story, M, S, F, O or Return, R. Listed in Settings → General
- [x] Settings → Sources can show only failing sources, or sources quiet for 30 days (enabled, fetching fine, nothing new in a month), and each source shows when its newest story was published
- [x] Unread count can be a number, a dot or hidden, in the menu bar and on Overview
- [x] Fix: Open Original's menu shortcut is now Command-Return. Plain Return as a menu shortcut could fire while typing in the search field

Checked: 254 package tests pass; the General settings render with the new controls and shortcut list; against the real database, no source is failing and none has been quiet for 30 days (the quietest, Mistral AI, last published 17 days ago), so both filters correctly show zero today.

Not checked: the shortcuts themselves. Operating the app directly needs macOS Screen Recording permission for the Claude app, which is not granted, and the self-screenshot mode cannot press keys.

### Imported feeds: trust levels, plain http, clearer failures — complete (21 November 2026)

Prompted by the owner's OPML file (24 feeds, all working in NetNewsWire). Of the 19 it added, 13 fetched at once. The other six: one removed by its publisher (HTTP 410), two Reddit feeds and VentureBeat blocking feed readers (404/429), one temporary server error at hnrss.org, and one feed that redirects to plain http.

- [x] Plain-language failure messages that say whether retrying can help
- [x] Per-source permission for plain http, with redirects to http stopped and named otherwise (schema v9). Checked in the sandboxed app with a temporary copy of the redirecting feed: allowed, 15 stories; not allowed, the named redirect. The copies were removed.
- [x] A trust level menu for every source; changing it re-labels stored stories
- [x] Not done, deliberately: imitating another app's user agent to get past Reddit, or getting past VentureBeat's bot check

### Folders, widget views and widget redesign — complete (21 November 2026)

- [x] One optional folder per source (schema v10); sidebar folders with their own story lists, rename and remove; folder menu per source in Settings → Sources
- [x] OPML import keeps folders, export writes them; catalogue sources start in five folders
- [x] News widget view menu: Overview, AI, Latest, Saved, each folder; renaming a folder updates widgets showing it
- [x] Widget redesign: host-drawn header and footer, featured first story, source tiles, kind tags
- [x] Settings button in the sidebar

Checked: 276 package tests pass; the app migrated the real database to v10 and filed the 34 catalogue sources into folders; snapshots of both widgets at three sizes and five styles.

Not checked by operating the app: the sidebar folders and the widget's view menu (snapshot mode leaves sidebar chrome blank and cannot click), and the Sources tab of Settings.

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
