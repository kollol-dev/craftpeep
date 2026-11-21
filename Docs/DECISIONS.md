# Architectural Decision Records

Status values: **Proposed** (awaiting approval), **Accepted**, **Superseded**.

ADR-001 to ADR-011 were **Accepted** by the owner on 10 November 2026. ADR-012 onward carry their own status.

## ADR-001 Product direction: intelligence platform, with the existing widget engine kept as a surface

**Context.** The repository was started as a general declarative widget app (spec v0.1, loader, validator, expression interpreter, 59 passing tests). The project brief defines an intelligence platform in which widgets are one display surface.

**Decision.** Keep `WidgetSpec` and `WidgetExpr`. Build the intelligence engine next. Widgets bind to the local store through a `query` data source rather than fetching for themselves.

**Consequences.** README and SPEC need rewriting to match. The widget renderer and builder move later in the order of work. The existing tests remain valid.

**Alternative rejected.** Continue the general widget app and add news widgets: this reproduces Kakuchi with fewer features and cannot cluster, rank or brief because there is no shared store.

## ADR-002 Persistence: SQLite through GRDB

**Decision.** Use GRDB, pinned to an exact version, behind repository protocols defined in `Domain`.

**Why.** The workload is SQL-shaped (bulk upserts, ranking joins, FTS5). GRDB provides migrations, FTS5, WAL concurrency and observation. SwiftData has no FTS and weaker migration control; the raw C API means writing those facilities ourselves.

**Cost.** The project's first third-party dependency. Reversible at the `Persistence` target boundary.

## ADR-003 Rename the package to `CraftPeepKit` and widen it

**Decision.** One package, renamed, holding `Domain`, `Persistence`, `Ingestion`, `Intelligence`, `AI`, `WidgetSpec`, `WidgetExpr`, `WidgetRuntime`, `WidgetRender`, `DesignSystem` as targets.

**Why.** Targets give enforced dependency direction and fast `swift test` without the overhead of several packages. "WidgetProCore" no longer describes the contents.

## ADR-004 Minimum OS: macOS 15 (package also declares iOS 18)

**Context.** The manifest says macOS 14 and iOS 17, marked as placeholders.

**Decision.** macOS 15.

**Why.** The first user is on a current system; the current release is two versions newer. Supporting 14 buys reach the product does not need yet and costs availability checks. Raising a minimum later is easy; lowering it is not, so this is the conservative end of "recent". Going to macOS 26 would simplify Liquid Glass adoption but drops more machines than is justified today.

## ADR-005 App Sandbox on from the first build; direct distribution first

**Decision.** Sandboxed, entitlements limited to network client and Keychain, plus user-selected files for import and export. Ship as a notarised Developer ID build; keep App Store eligibility.

**Why.** Nothing planned needs to leave the sandbox, and retrofitting it later is painful. It also limits the damage of any parser bug.

**Consequence.** No subscription-CLI AI route, no command or file capabilities for widgets.

## ADR-006 Widget spec 0.2: `query` source and templates; remove `commands` and `files`; disable `http`, `rss`, `system`, `ai` sources

**Decision.** As described in WIDGET_SYSTEM.md.

**Why.** Store-bound widgets need no network permission, refresh for free and inherit clustering and ranking. Removing command and file capabilities closes a class of risk the product has no use for. Templates make AI generation reliable.

**Cost.** Changes to tested models and schema; example widgets rewritten.

## ADR-007 AI: optional, user-supplied, no tools; Anthropic and OpenAI-compatible clients

**Decision.** As described in AI_STRATEGY.md. Two provider implementations cover the listed providers. Models never receive tools and never see retrieved content in the widget builder.

## ADR-008 Rules before models for credibility and classification

**Decision.** Source tier is set only by catalogue or user. Hype Filter kind comes from ordered rules; an optional model pass handles only what rules leave unclassified, and is stored and shown as a model judgement.

**Why.** Deterministic, explainable, free, testable, and works with AI off.

## ADR-009 No embeddings or vector store in the MVP

**Decision.** FTS5 for search; URL and title-similarity clustering. Revisit with measurements.

## ADR-010 Market data through the user's own provider key

**Decision.** `MarketDataProvider` protocol; no bundled key; provider chosen after a spike. Unofficial endpoints are not used.

**Open, with findings from 12 November 2026** (see DATA_SOURCES.md): a free Twelve Data key covers US shares and forex in real time but not London-listed shares, and index values are not documented on any plan. Choices for the owner:

1. **US watchlist and FX only, on Twelve Data's free plan.** Works today at no cost. No FTSE 100, no index levels; the Markets view would say so plainly.
2. **The same, plus US index proxies:** show SPY, QQQ and DIA, labelled as tracking funds, never as the index. Still nothing for the UK.
3. **Defer markets** until a source for UK shares and index levels is found, and go to the widget platform (M6) next.
4. **Accept a paid plan** as the requirement for UK data. Conflicts with "useful without a subscription" for that part of the app.

**Decided by the owner on 12 November 2026: option 3, defer markets.** No market data code is written until a source for UK shares and index levels is found. The widget platform (M6) goes next. The earlier recommendation, kept for the record, was option 2. It delivers most of the value for the seven named companies at no cost, is honest about what it shows, and leaves the provider protocol ready for a UK source.

## ADR-011 Not building: Reddit API ingestion, system-data widgets, notch and lock-screen surfaces, full-article scraping

**Why.** Terms risk (Reddit), off-mission and already well served by Kakuchi (system and placement features), copyright and fragility (scraping).

## ADR-012 Distribution: free and open source, macOS first

**Status.** Accepted (owner's answer, 10 November 2026).

**Decision.** CraftPeep is released free and open source. The macOS version ships first. A paid version is possible later but is not being designed for now.

**Consequences.**

- The repository is public, so nothing secret is ever committed: no API keys, no personal contact details in a User-Agent, no private feed URLs in the default catalogue.
- Data licensing: user-supplied keys remain the model for market data and AI. A free app where each user holds their own provider agreement fits "personal, non-commercial" free tiers far better than a paid app would. Any default source whose terms forbid commercial use is recorded as such in DATA_SOURCES.md so that a future paid version knows what must be re-licensed or made opt-in.
- Dependencies must have licences compatible with the chosen project licence. GRDB is MIT.

**Open.** The project licence (README still says "to be decided"). Recommendation: **Apache-2.0** or **MIT** if the aim is maximum adoption; **GPL-3.0** if the aim is to stop closed forks while keeping the option of a paid build, since the sole copyright holder can always release their own code under other terms. A later paid version is simplest if outside contributions are accepted under a contributor agreement or kept minimal. This is the owner's call and blocks nothing until the repository is made public.

## Resolved questions

1. Sold, distributed or personal? Free and open source; paid version possibly later (ADR-012).
2. ADR-001 to ADR-006: approved.
3. Reddit thread: the original post was supplied and is analysed in REFERENCE_ANALYSIS.md. The comments were not supplied.
