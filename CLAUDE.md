# CraftPeep

Personal technology, AI and markets intelligence app. macOS first, iPhone later. Native Swift, local-first, sandboxed.

The owner is a senior software engineer. Be direct, give opinions with reasons, and say when an idea is weaker than an alternative. Do not explain basics.

## Read first

| Document | Purpose |
|---|---|
| [Docs/PRODUCT_REQUIREMENTS.md](Docs/PRODUCT_REQUIREMENTS.md) | What is in the MVP and what is deferred |
| [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) | Modules, data model, pipeline, platform findings |
| [Docs/WIDGET_SYSTEM.md](Docs/WIDGET_SYSTEM.md) and [Docs/SPEC.md](Docs/SPEC.md) | Widget spec and execution |
| [Docs/AI_STRATEGY.md](Docs/AI_STRATEGY.md) | Provider abstraction, cost control |
| [Docs/DATA_SOURCES.md](Docs/DATA_SOURCES.md) | Per-source API status and terms |
| [Docs/SECURITY.md](Docs/SECURITY.md) | Threat model |
| [Docs/ROADMAP.md](Docs/ROADMAP.md) | Milestones and current state |
| [Docs/DECISIONS.md](Docs/DECISIONS.md) | ADRs; check status before relying on one |
| [Docs/REFERENCE_ANALYSIS.md](Docs/REFERENCE_ANALYSIS.md) | Kakuchi research |

## Invariants

1. The intelligence engine comes before presentation. Do not build widget or UI features over data that is not reliable yet.
2. Never execute model-generated code. Models produce text or schema-validated JSON only. Models get no tools.
3. AI is optional and never on the data refresh path.
4. Retrieved content is untrusted: plain text only, never rendered as HTML, never able to change instructions or trigger actions.
5. Every stored item keeps its source, original URL, published time and retrieved time. Clustering and summarising never discard provenance.
6. Never fabricate data, API capabilities or facts about other products. Missing is shown as missing.
7. Secrets live only in the Keychain. Never in files, logs, exports or widget specs.
8. App Sandbox stays on.
9. Official APIs and feeds only. No scraping as a dependency. Check a provider's current terms before writing its adapter and record the result in DATA_SOURCES.md.
10. UI reads the store. It never calls adapters or AI providers directly.

## Ask before

Major architecture changes, new dependencies, changing persistence, cloud services, expensive infrastructure, product scope changes. Small, clearly specified tasks proceed without an approval loop.

## Working rules

- Before substantial work: inspect the code and the relevant document, state the approach, trade-offs, risks and acceptance criteria, and wait for approval.
- During: small increments, app stays buildable, tests written with the code, no drive-by refactors, follow existing conventions.
- After: build, run tests, check warnings, then report what was done, what was verified and what is outstanding. If something could not be built or run, say so. No mocks hiding failures.
- Keep documents true to the implementation. Do not describe planned work as done.

## Commands

```sh
cd Packages/CraftPeepKit && swift test                                   # all package tests
cd Packages/CraftPeepKit && CRAFTPEEP_LIVE=1 swift test --filter LiveSmokeTests        # real network, checks the catalogue
cd Packages/CraftPeepKit && CRAFTPEEP_LIVE=1 swift test --filter LiveEvaluationTests   # real network, prints clusters and ranking
xcodebuild -project App/CraftPeep/CraftPeep.xcodeproj -scheme CraftPeep -destination 'platform=macOS' -derivedDataPath build build
./scripts/build-dmg.sh                      # local unsigned DMG
open --env CRAFTPEEP_SNAPSHOT=overview,select,panels build/Build/Products/Debug/CraftPeep.app   # debug build photographs its own windows
```

Open `App/CraftPeep/CraftPeep.xcodeproj` in Xcode to run the app.

## Conventions

- Swift 6, strict concurrency. Value types and protocols in `Domain`; dependencies injected, no singletons.
- Adapters separate `fetch` from `parse`; parsers are tested from recorded fixtures with no network.
- Typed errors per layer. Background failures surface as per-source or per-feature status, not alerts.
- British English in user-facing text and documentation.
- New tests use Swift Testing; the widget suites remain XCTest.
- Classification is rules first. When a rule misfires on real headlines, tighten the rule and add the headline as a test; do not add a model call.
- Clustering changes must keep the labelled fixture at zero wrong merges; report the measured precision and recall.
- Test fixtures are synthetic. Do not commit copies of real publishers' feeds.
- To check UI without screen access, use the snapshot mode above; PNGs land in the app container under `Application Support/CraftPeep/snapshots`. Sidebar and toolbar chrome come out blank.
- App builds can take several minutes; run `xcodebuild` in the background.
- The repository is open source: never commit keys, personal details or private feed URLs.
