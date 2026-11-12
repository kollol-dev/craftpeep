# Widget System

Status: the store-bound `query` source, the runtime, the renderer, the News List and the desktop window are implemented (11 November 2026). The gallery and an AI builder that chooses among bundled widgets and their settings are implemented too (12 November 2026); composing new layouts by AI is not, and is not planned. Where this document and the code differ, ROADMAP.md (M4c) lists the differences. [SPEC.md](SPEC.md) describes spec v0.1 as currently implemented in `WidgetSpec` and `WidgetExpr`. This document describes how that work is adapted to CraftPeep and what changes in spec v0.2.

## Position

A widget is a declarative JSON document rendered by trusted SwiftUI code. No model output is ever executed. The existing spec, loader, validator and expression interpreter already satisfy this and are kept.

Three things change relative to spec v0.1.

### 1. Widgets bind to the store, not to the network

In v0.1 each widget declares its own `http` and `rss` sources and fetches for itself. That is the container model: two news widgets fetch twice, nothing is deduplicated, there is no history, and every widget carries a network permission.

In CraftPeep, ingestion owns all fetching. A widget declares a **query** against the local store:

```json
"data": {
  "stories": {
    "type": "query",
    "from": "clusters",
    "where": { "entities": ["OpenAI", "Anthropic", "Google DeepMind"], "kinds": ["shipping", "announcement"], "sinceHours": 48 },
    "sort": "rank",
    "limit": 5
  }
}
```

Consequences:

- A widget of this kind needs no network permission at all. Its install sheet says "reads your CraftPeep stories".
- Refresh is free: the widget observes the database and redraws when ingestion writes.
- Clustering, classification, ranking and read state apply automatically.
- The AI builder only has to choose a template and fill a query, a much smaller target than inventing HTTP calls and JSON paths.

`from` is a closed set: `clusters`, `quotes`, `repositories`, `briefing`, later `facts`, `events`. `where` fields are validated per collection. A query compiles to a parameterised repository call, never to SQL text from the spec.

### 2. Templates sit on top of the component vocabulary

The brief asks for fixed templates; the repo has a component tree (`vstack`, `text`, `list`, `chart`, and so on). These are compatible. A **template** is a parameterised component tree shipped with the app:

| Template | Parameters | Release |
|---|---|---|
| News List | query, count, show summary, show source, density | MVP |
| Stock Watchlist | symbols, show sparkline, show change as percent or value | v0.2 |
| Metric Grid | list of metric bindings, columns | v0.2 |
| Single Metric | one binding, comparison period | v0.2 |
| Sparkline Chart | series binding, range | v0.2 |
| Repository List | language, topic, window, count | v0.2 |
| Timeline | cluster or entity, range | v0.3 |
| Comparison | two or more entities and a metric | v0.3 |
| Event Calendar | calendars, horizon | v0.3 |
| Research List | categories, interests, count | v0.3 |

A widget instance references a template and supplies parameters:

```json
{ "spec": "0.2", "template": "news-list", "params": { "query": { ... }, "count": 5, "showSummary": true } }
```

The runtime expands it to a full component tree. Free-form `view` trees remain valid spec for hand-written widgets and a possible later "advanced" builder mode, but the AI builder targets templates. This keeps generation reliable, keeps every generated widget on a tested layout, and means a template improvement reaches every instance.

### 3. Capabilities removed or gated

| v0.1 capability | Decision | Reason |
|---|---|---|
| `permissions.commands` | Remove from the schema | Arbitrary command execution contradicts the security model and the sandbox. Present in the models today, never implemented. |
| `permissions.files` | Remove | Same. |
| `system` sources (CPU, battery, Now Playing) | Remove from scope | Off-mission; Kakuchi's territory. `time` stays. |
| `http`, `rss` sources inside a widget | Keep in the spec, disabled in the runtime until a later release | Useful for a personal one-off (a build status endpoint). When enabled: HTTPS only, hosts declared and approved, redirects confined to declared hosts, private and loopback addresses refused, response size capped, `secrets.*` only in headers. Never offered by the AI builder. |
| `ai` source inside a widget | Replace with a binding to stored summaries and briefings | Widgets must not spend AI budget on refresh. The intelligence layer generates; widgets display. |

These are schema changes to existing, tested code and are listed in DECISIONS.md for approval.

## Layers

```
Definition                     Data                          Rendering
----------                     ----                          ---------
widget_instance row            WidgetRuntime                 WidgetRender
  spec_json (validated)          resolve template              SwiftUI component per type
  settings                       compile query bindings        template layouts per size
  size, position                 observe repositories          theme tokens
                                 evaluate {{ }} with           loading / empty / error /
                                 WidgetExpr (step-limited)     stale states
                                 -> WidgetViewModel
```

- **Definition** is inert data. Loading a definition performs no I/O.
- **Data** is the only layer that touches repositories. It produces an immutable view model: resolved values plus a state (`loading`, `ready(asOf:)`, `empty`, `stale(asOf:)`, `failed(reason)`).
- **Rendering** is a pure function of view model and size. It cannot fetch, and it has no access to the expression scope beyond what the runtime resolved.

Every template must define all five states. `stale` is shown when the newest underlying data is older than the template's expectation, with the age visible.

## Hosting

| Surface | Mechanism | Release |
|---|---|---|
| In-app preview and gallery | SwiftUI view in the main window | MVP |
| Desktop | One borderless `NSPanel` per widget at desktop level, SwiftUI hosted inside, position persisted per display | MVP (one widget type) |
| Floating / always on top | Same panel at floating level | M7 |
| Menu bar Pulse | Purpose-built view, not a generic widget host | MVP |
| System widgets (WidgetKit) | Separate extension reading a shared container; timeline-driven, refresh budget set by the system | Later |

Desktop panels and WidgetKit widgets are different things with different limits. The same spec can feed both because rendering is a pure function of view model and size, but WidgetKit cannot update live and cannot run our observers. Nothing in the UI should call the desktop panels "system widgets".

## AI builder workflow (v0.2)

```
1  User describes the widget
2  Builder prompt = system instructions + template catalogue + query schema
                    + lists of valid entities, sources and symbols from the store
                    (no article text, no feed content)
3  Model returns a structured object: { template, params, name, rationale }
4  Decode -> schema validation -> semantic validation
     - template exists; params match its schema
     - every entity, source and symbol exists, or is reported back as unknown
     - limits within bounds
5  On failure: send the validation errors back, at most two retries
6  Preview with live data from the store
7  User approves -> persist widget_instance -> place
8  Edits ("show only three", "add Meta") send the current spec plus the request
   and return a JSON patch limited to params; validated the same way
```

Notes:

- Provider structured-output features are used where available; the validator is the authority regardless.
- The builder never sees retrieved content, so a hostile headline cannot influence widget generation.
- If the request cannot be met by any template or data the store has, the builder says so and names what is missing. It does not approximate with a different widget silently.
- Simple edits (count, size, sort, add or remove an entity) are also available as ordinary settings controls, with no AI involved.

## Changes to existing code implied by this document

1. Add `query` to `WidgetDataSourceType` with a typed payload; add `template` and `params` to `WidgetDefinition`; bump the spec to 0.2 and refuse 0.1 files with a clear message or migrate them.
2. Remove `commands` and `files` from `WidgetPermissions` and the schema.
3. Rename the placeholder `WidgetData` target to `WidgetRuntime`.
4. Replace `ai` and `system` source types as described.
5. Rename "WidgetPro" to CraftPeep in SPEC.md, the schema `$schema` URL and example IDs.
6. Delete the duplicate `Sources/WidgetSpec/WidgetSpecTests.swift`.

None of this is done. It is scheduled in M4 and M5 of [ROADMAP.md](ROADMAP.md), except item 6, which is housekeeping.
