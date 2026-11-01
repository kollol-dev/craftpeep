# CraftPeep

A native macOS app for live desktop widgets that you can create three ways: describe one to an AI,
build it visually, or write it by hand. Mac first, iPhone later.

**Status:** early development. The widget spec v0.1 is drafted, the core package decodes and validates
widget files, and a macOS app shell builds and runs. There are no real widgets on screen yet.

## Idea

Every widget is a single declarative JSON file. The AI builder, the visual builder, the spec editor and
hand-written files all produce and edit the same format. The Mac app renders it with SwiftUI, and the same
core package can later power an iPhone app through WidgetKit.

Principles:

- Declarative, not executable: safe to share, previewable without running anything, portable to iOS.
- Permissions are data: the install sheet is generated from the spec and enforced by the runtime.
- Secrets never live in widget files (Keychain only).
- Small closed vocabulary first; grow it from real user requests.

## Repository layout

| Path | Contents |
|---|---|
| `App/CraftPeep/` | macOS app (Xcode project, SwiftUI) |
| `Packages/WidgetProCore/` | Swift package: `Sources/` and `Tests/` |
| `Docs/SPEC.md` | Widget spec v0.1 overview: anatomy, data sources, components, expressions |
| `Schema/widget.schema.json` | JSON Schema for validation and editor autocomplete |
| `Examples/` | Clock, markets ticker and AI news briefing example widgets |
| `scripts/build-dmg.sh` | Builds a Release app and packages it as a DMG (local use) |

Package targets:

| Target | Purpose |
|---|---|
| `WidgetSpec` | Codable models, loader, validation, version handling |
| `WidgetExpr` | `{{ }}` expression interpreter (not started) |
| `WidgetData` | Data sources, scheduler, caching, permission enforcement (not started) |
| `WidgetRender` | SwiftUI rendering of a spec plus data (not started) |

## Getting started

Requires a recent Xcode with Swift 6 and macOS 14 or later.

Run the package tests:

```sh
cd Packages/WidgetProCore
swift test
```

Run the app: open `App/CraftPeep/CraftPeep.xcodeproj` in Xcode, choose **My Mac**, press Cmd+R.

Build a DMG for local use:

```sh
./scripts/build-dmg.sh
```

The DMG is not notarised, so macOS may block it on first launch: open System Settings > Privacy & Security
and choose **Open Anyway**.

## Writing a widget

Start from a file in `Examples/` and check it against `Schema/widget.schema.json`. The core package also
validates rules the schema cannot express, for example that every network host a data source uses is
declared in `permissions.network`.

## Roadmap

- [x] App shell linked to the core package
- [ ] 1. Spec models, loader and validation, with tests against the example widgets
- [ ] 2. Expression interpreter with tests for every function
- [ ] 3. Renderer: draw the clock, then lists and conditionals
- [ ] 4. Floating desktop widget window with persisted position
- [ ] 5. Data sources: time, http, rss behind a scheduler, with network permissions enforced
- [ ] 6. Settings form and install/permission sheet, Keychain for secrets
- [ ] 7. Spec editor with live preview
- [ ] 8. AI builder: provider abstraction, schema-constrained generation, validate and retry
- [ ] 9. Distribution: signing, notarisation, DMG, updates, licensing
- [ ] 10. Later: visual builder, data source builder, gallery and shareable setups, iPhone app

## Notes

This project is inspired by the idea of describing a widget in plain language and getting a live one.
It reimplements concepts from scratch: no code, assets, names or branding from other apps.

## License

To be decided.