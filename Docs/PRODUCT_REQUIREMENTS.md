# CraftPeep Product Requirements

Status: draft for approval, 10 November 2026. Nothing in this document is implemented unless [ROADMAP.md](ROADMAP.md) says so.

## 1. Product

CraftPeep is a local-first macOS app that collects technology, AI, developer and market information, removes duplicates, labels what each item is and where it came from, ranks it against the user's interests, and explains it in a short briefing. Selected views can be pinned to the desktop as widgets.

**Primary user:** a senior software engineer who wants a ten-minute morning read instead of an hour across HN, RSS, X, GitHub and a markets app.

**The test:** the user opens it every weekday morning for a month without being reminded.

## 2. Principles

1. Intelligence before presentation. A widget is only as good as the store behind it.
2. Every item shows its source, publication time, retrieval time and what kind of thing it is.
3. Useful with AI switched off. AI adds summaries, briefings and the widget builder; it is never on the refresh path.
4. Local-first, no account, sandboxed.
5. Never fabricate. A missing number is shown as missing.
6. Ship a narrow thing that works daily before widening.

## 3. Scope challenge

The brief lists seven modules. Assessed honestly:

| Module | Verdict | Reason |
|---|---|---|
| Technology news | MVP | Free official feeds, clear value, exercises the whole pipeline. |
| AI intelligence | MVP | Same pipeline with a curated source set and an AI-specific view. Almost free once news works. |
| Personal briefing | MVP (morning only) | The defining feature. One briefing type done well beats five done thinly. |
| Developer intelligence | v0.2 | GitHub has an official API and release feeds. No official trending endpoint, so "trending" must be defined by us (see DATA_SOURCES.md). |
| Markets and economics | v0.2 | Highest licensing risk. Free tiers are non-commercial and index coverage is unverified. Needs a provider decision first. |
| Company and business | v0.3, reduced | Structured earnings for US filers are available from SEC EDGAR. Layoffs, hiring trends, market share and executive changes have no reliable free structured source and should be news stories tagged with a company, not structured data. |
| Learning and discovery | Folded into the briefing | As a standalone module it invites generic recommendations. It becomes the "explore next" section of the briefing, driven by what the user actually read and saved. Revisit as its own view only if that section proves valuable. |

## 4. MVP (v0.1)

### Included

| ID | Requirement |
|---|---|
| ING-1 | RSS and Atom ingestion from a curated catalogue plus user-added feeds. |
| ING-2 | Hacker News ingestion (top, best, new above a points threshold) with points and comment counts. |
| ING-3 | Conditional requests (ETag, Last-Modified), per-source refresh interval, backoff on failure, per-source health visible in Settings. |
| ING-4 | Users can add, remove, pause and prioritise sources. |
| NRM-1 | Normalise to one article model: canonical URL, title, excerpt, publisher, published and retrieved timestamps. |
| NRM-2 | Deduplicate by canonical URL. Cluster related articles by title similarity and shared links within a time window. All member articles and sources are retained. |
| CLS-1 | Source credibility tier from a rules file shipped with the app and editable by the user. |
| CLS-2 | Hype Filter category by rules, with the rule that fired shown to the user. Unknown is an allowed answer. |
| CLS-3 | Topic and company tagging by keyword and entity lists. |
| RNK-1 | Ranking from transparent factors (source tier, cluster size, community signal, recency, interest match). The UI states reasons, not a score. |
| UX-1 | Main window: Overview, AI Intelligence, Technology News, Saved, Settings. |
| UX-2 | Story detail: cluster headline, all sources with timestamps, classification with reason, open original. |
| UX-3 | Read state, read later, favourites. |
| UX-4 | Full-text search over titles and excerpts. |
| UX-5 | Offline: everything already stored is readable; stale data is labelled with its age. |
| AI-1 | Optional provider configuration: Anthropic and any OpenAI-compatible endpoint (covers OpenAI, Ollama, LM Studio, OpenRouter). Keys in Keychain. |
| AI-2 | Per-cluster summary, generated on demand or for top-ranked clusters, cached by content hash. |
| AI-3 | Morning briefing covering the seven questions in the brief, with every claim linked to a stored cluster. |
| AI-4 | Usage ledger: requests, tokens, estimated cost per provider and feature. Daily budget with graceful stop. |
| MB-1 | Menu bar item: unread important count, briefing status, top five stories, open main window. |
| WG-1 | One desktop widget template (News List) bound to a store query, in a floating desktop-level window with persisted position. Proves the widget pipeline end to end. |
| SYS-1 | Launch at login, optional. Runs as a menu bar app when the main window is closed. |
| SYS-2 | Retention policy with a user setting; saved items are exempt. |

### Acceptance for v0.1

- Cold launch to a populated Overview from the local store in under one second on an M-series Mac.
- A refresh of 40 feeds completes in under 15 seconds on a normal connection and makes no AI calls.
- The same story from three publishers and HN appears once, with four sources.
- With no AI key configured, every view except summary and briefing works.
- With the network off, the app opens and reads.
- Idle CPU with the app in the menu bar is effectively zero between refreshes.

## 5. Deferred

| Release | Feature | Why deferred |
|---|---|---|
| v0.2 | AI widget builder (natural language to spec, validate, preview, install, conversational edits) | Needs at least three templates and a stable store query language to be worth building. |
| v0.2 | Templates: Stock Watchlist, Metric Grid, Single Metric, Sparkline, Repository List | Depend on markets and GitHub data. |
| v0.2 | Markets: watchlist, indices or labelled proxies, FX, historical charts | Provider and licence decision outstanding. |
| v0.2 | Developer Radar: GitHub rising repositories, release tracking, security advisories | Second adapter family; no dependency on AI. |
| v0.2 | Widget Gallery, My Widgets, multiple widgets on a canvas | Follows from more than one template. |
| v0.3 | Company view: earnings from SEC EDGAR, earnings calendar | Requires XBRL mapping work and a calendar source. |
| v0.3 | Macro indicators and economic calendar | Three separate official sources with different shapes. |
| v0.3 | Weekly reports, evening briefing | Variants of the morning briefing once its quality is proven. |
| v0.3 | Timeline, Comparison, Event Calendar, Research List templates | |
| v0.3 | arXiv research tracking | Useful, but needs its own relevance filter to avoid a firehose. |
| Later | Notifications, global shortcut, saved layouts, stacks, multi-display placement rules | Desktop polish (M7). |
| Later | Conversational search, research assistant | Needs proof that FTS is not enough. |
| Later | Embeddings for clustering and search | Only if title-based clustering measurably fails. |
| Later | WidgetKit widgets, iPhone app, sync | Phase 2 and 3. |
| Later | MCP server (read-only access to the store) | Cheap and attractive, but not before the store is stable. |
| Not planned | Reddit ingestion via API | Terms restrict commercial use; see DATA_SOURCES.md. |
| Not planned | Notch, lock screen, system gauges, moods, running commands, web-page widgets | Kakuchi's territory, off-mission, and incompatible with the sandbox. |
| Not planned | Full-article scraping and storage | Copyright and fragility. |
| Not planned | Using a Claude or ChatGPT subscription through a CLI | Requires spawning external binaries; breaks the sandbox. |

## 6. Non-functional requirements

| Area | Requirement |
|---|---|
| Platform | macOS 15 or later (proposed, see DECISIONS.md). Apple silicon and Intel if the SDK still allows; not a goal to optimise for Intel. |
| Sandbox | App Sandbox on from the first build. Entitlements: outgoing network, Keychain. No file access beyond user-selected import/export. |
| Privacy | No account, no telemetry. The only network destinations are the sources the user has enabled and the AI provider the user configured. A Network Activity panel lists them. |
| Accessibility | Full keyboard navigation, VoiceOver labels on every row and control, Dynamic Type equivalents via scalable text styles, no information by colour alone. |
| Performance | Budgets in section 4. Refresh work off the main actor. |
| Reliability | One failing source never blocks others. Schema migrations are tested from every released version. |
| Honesty | Every number carries provider, timestamp and status (real-time, delayed, end of day, proxy). |

## 7. Information that must always be shown

| Item type | Always visible |
|---|---|
| Article | Publisher, published time, retrieved time, source tier. |
| Cluster | Number of sources, earliest and latest publication, classification and its basis (rule or model). |
| AI text | Marked as AI-generated, with model name and generation time, and links to the clusters it drew from. |
| Quote (v0.2) | Provider, timestamp, market status, real-time/delayed/end-of-day, currency. |
| Financial fact (v0.3) | Reporting period, currency, filing link, reported versus estimated. |

## 8. UI and UX direction

**Character:** a reading tool, closer to Mail or a good feed reader than to a dashboard of tiles. Dense text, strong hierarchy, almost no chrome.

| Aspect | Direction |
|---|---|
| Window | `NavigationSplitView`: sidebar, story list, detail. Standard toolbar with search and refresh. Native controls throughout. |
| Sidebar (MVP) | Overview, AI Intelligence, Technology News, Saved, then Settings in the app menu. Companies, Markets, Developer Radar, Widget Gallery and My Widgets appear when they have content, not as empty placeholders. |
| Overview | Top of the page is the briefing (or the digest without AI). Below it, ranked clusters grouped by "Shipping and released", "Announcements", "Research", "Business". |
| Story row | Headline, one-line excerpt, then a metadata line: kind badge, best source, source count, age, community signal. The ranking reason is available on hover and to VoiceOver. |
| Story detail | Summary if present (labelled AI), then every source with tier, publisher and time, then related clusters. One primary action: open original. |
| Density | Compact, balanced and dense, implemented as three values of one spacing and line-count scale, not three layouts. |
| Type | System font. Headlines in a semibold text style, metadata in a secondary caption style. Numbers in monospaced digits. |
| Colour | Semantic system colours. One accent. Kind badges differ by label and symbol as well as tint. Positive and negative market colours are paired with arrows or signs. |
| Dark mode | Designed first in dark, verified in light, using system materials rather than custom backgrounds. |
| Motion | Only for state changes that need explaining (a row moving on re-rank, a widget entering). Respect Reduce Motion. |
| Freshness | A quiet "Updated 4 min ago" in the toolbar; per-item age always present; stale data dimmed with its age stated. |
| Empty and error states | Say what happened and what to do, per source or per feature. Never a blank pane. |
| Keyboard | Arrow and j/k navigation, space to page, return to open, s to save, r to refresh, Cmd-F search, Cmd-1…5 for sidebar sections. |
| Menu bar Pulse | A small popover: briefing status, five stories, unread count, open app. No scrolling feed. |
| Desktop widget | Same row components as the main list at widget density, on a system material, no custom themes in MVP. |

Avoided: card grids for text content, gradients and glow, per-widget theme pickers, charts without a question to answer, and any numeric "importance score".

## 9. Open product questions

1. Is CraftPeep intended for sale? This decides how strict the data-licensing posture must be (several free tiers are personal-use only).
2. Should sources be curated by default (opinionated starter catalogue) or empty until the user adds feeds? Recommendation: curated, about 30 feeds, all removable.
3. Is X/Twitter a required source? No workable official free route exists; assumed out of scope.
