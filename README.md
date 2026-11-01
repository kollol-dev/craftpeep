# CraftPeep

> Working name. Rename freely.

A native macOS app for live desktop widgets that you can create three ways: describe one to an AI,
build it visually, or write it by hand. Mac first, iPhone later.

**Status:** early design. The widget spec v0.1 is drafted; the code is a skeleton.

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
| `Docs/SPEC.md` | Widget spec v0.1 overview: anatomy, data sources, components, expressions |
| `Schema/widget.schema.json` | JSON Schema for validation and editor autocomplete |
| `Examples/` | Clock, markets ticker and AI news briefing example widgets |
| `Sources/WidgetSpec` | Codable models, validation, versioning |
| `Sources/WidgetExpr` | `{{ }}` expression interpreter |
| `Sources/WidgetData` | Data sources, scheduler, caching, permission enforcement |
| `Sources/WidgetRender` | SwiftUI rendering of a spec plus data |
| `Tests/` | Unit tests |
| `App/` | macOS app target (to be created in Xcode) |

## Getting started

Requires a recent Xcode with Swift 6 (see `Package.swift` for the tools version).

```sh
swift build
swift test
```

Then create the macOS app target as described in `App/README.md`.

## Roadmap

1. Spec models: decode the example widgets, with tests
2. Expression interpreter with tests for every function
3. Renderer: draw the clock, then lists and conditionals
4. Floating desktop widget window with persisted position
5. Data sources: time, http, rss behind a scheduler, with network permissions enforced
6. Settings form and install/permission sheet, Keychain for secrets
7. Spec editor with live preview
8. AI builder: provider abstraction, schema-constrained generation, validate and retry
9. Distribution: signing, notarisation, DMG, updates, licensing
10. Later: visual builder, data source builder, gallery and shareable setups, iPhone app

## Notes

This project is inspired by the idea of describing a widget in plain language and getting a live one.
It reimplements concepts from scratch: no code, assets, names or branding from other apps.

## License

To be decided.
