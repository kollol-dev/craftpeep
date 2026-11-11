# CraftPeep Widget Spec v0.2 (draft)

> **What runs today.** The app loads spec 0.1 and 0.2 files. It resolves `static`, `time` and `query` sources; `http`, `rss`, `system` and `ai` sources are declared here but deliberately not run. It draws `vstack`, `hstack`, `zstack`, `spacer`, `divider`, `text`, `number`, `icon`, `badge`, `button` and `list`; `image`, `progress` and `chart` are not drawn yet. The `commands` and `files` permissions from the first draft are refused. One widget ships: News List.

A widget is **one JSON file**. Every authoring method (AI builder, visual builder, spec editor, hand-written files) produces and edits this same format. The Mac app renders it with SwiftUI; the iPhone app can later render the same file through WidgetKit.

Files in this folder:

- `widget.schema.json` – JSON Schema (draft 2020-12) for editor validation and autocomplete
- `examples/clock.widget.json` – time source, settings, expressions in refresh and format
- `examples/markets.widget.json` – HTTP fan-out, secrets, list, conditional colour
- `examples/ai-news.widget.json` – RSS plus an AI summary source, conditional sections, tap actions

## Design principles

1. **Declarative, not executable.** No arbitrary code in the core format. This is what makes it safe to share, previewable without running anything, and portable to iOS.
2. **Permissions are data.** The install sheet is generated from `permissions`, so what the user approves is exactly what the runtime enforces.
3. **Secrets never live in the file.** Settings of type `secret` go to the Keychain and are excluded from shared Setups.
4. **Small closed vocabulary first.** A fixed set of components, data sources and functions. Grow it from real user requests.
5. **Degrade per platform.** Features that cannot run on iOS are declared, not hidden.

## Anatomy

| Key | Purpose |
|---|---|
| `spec`, `id`, `name`, `version` | Identity. `id` is reverse-DNS, `version` is semver. |
| `sizes`, `platforms` | Which sizes and platforms the widget supports. |
| `permissions` | `network` hosts, `system` sources, `ai`. A widget that only uses `query` sources needs none. |
| `settings` | Drives the auto-generated settings form. Types: string, number, boolean, select, color, stringList, secret. |
| `data` | Named data sources (below). Results are available as `data.<name>`. |
| `view` | One component tree per size; `default` is the fallback. |

## Data sources

| Type | What it does | Notes |
|---|---|---|
| `query` | Read stories from CraftPeep's local store | Spec 0.2. `from: "stories"`, optional `where` (`subject`, `entities`, `kinds`, `sinceHours`, `saved`), `sort` (`rank` or `latest`), `limit` up to 50. Needs no permission and makes no network request. Each story exposes `headline`, `excerpt`, `url`, `discussionURL`, `source`, `sources`, `sourceCount`, `kind`, `support`, `publishedAt`, `points`, `comments`, `isRead`, `isSaved`. |
| `static` | Literal value | For lookup tables and constants. |
| `time` | Current date and time | Exposes `.date`. |
| `http` | GET a JSON endpoint | Host must be in `permissions.network`. `path` picks a sub-object, `map` reshapes, `each` fans out one request per array element. |
| `rss` | Parse RSS or Atom | Items expose `title`, `link`, `published`, `summary`. |
| `system` | Battery, CPU, memory, network, calendar, Now Playing | Needs the matching `permissions.system` entry. |
| `ai` | Run a prompt over text with the user's AI provider | Needs `permissions.ai`. `cache` is mandatory in practice to cap cost. |

All sources accept `refresh`. The runtime only refreshes sources for widgets that are visible, and pauses everything when the display sleeps.

## Components

Layout: `vstack`, `hstack`, `zstack`, `spacer`, `divider`.
Content: `text`, `number`, `image`, `icon`, `badge`, `progress` (ring or bar), `chart` (line, area, sparkline, columns).
Structure: `list` (repeat a template over an array), `button`.

Any component can take `when` (conditional render) and `action` (`openURL`, `copy`, `refresh`).

Colours are tokens (`primary`, `secondary`, `accent`, `positive`, `negative`), hex values, or expressions that resolve to either. Themes remap the tokens, so one widget works across all themes without edits.

## Expressions

Anything in `{{ ... }}` is an expression. Strings can mix literal text and expressions.

**Scope:** `data.*`, `settings.*`, `secrets.*` (only in `http` URLs and headers), `now`, plus loop variables from `each`/`as`.

**Operators:** `+ - * / %`, comparisons, `&& || !`, ternary `a ? b : c`, property and index access.

**Functions (v0.1):** `format(value, pattern)`, `round`, `floor`, `ceil`, `clamp`, `min`, `max`, `sum`, `avg`, `count`, `join`, `map`, `filter`, `first`, `last`, `upper`, `lower`, `encode`, `ago`, `default`.

**Deliberately excluded:** assignment, loops, function definitions, network or file access. Expressions run in a small interpreter with an evaluation step limit, so they cannot hang a widget or touch anything outside the scope above.

## Authoring tiers mapped to the spec

| Tier | What the user edits |
|---|---|
| Remix | `settings` values only |
| Visual builder | `view` tree and bindings, `data` through the data source builder |
| Spec editor | The whole file, validated live against the schema |
| Expressions | `{{ }}` inside any string |
| Script mode (later, macOS only) | A separate `script` data source or component. Not part of v0.1, because it breaks iOS portability. |
| AI builder | Generates and patches the whole file, constrained to this schema |

Constraining the AI builder to the schema is a real advantage: generated output can be validated automatically, and a failed validation can be fed back to the model for a retry.

## iPhone considerations (to verify before committing)

- WidgetKit renders from timelines the system schedules, so 1-second refresh (as in the clock example) will not work on iOS. The runtime should clamp `refresh` per platform, and the clock should fall back to a system-provided live time view there.
- Widget extensions have tight memory and time budgets, and refresh frequency is limited by the system. Keep data fetching small and cache aggressively.
- `ai` sources probably need results precomputed by the main app and shared with the extension, rather than called from the extension itself.
- `system` sources differ by platform. `calendar` and `battery` exist on both; Now Playing, CPU and memory are Mac-only.

I have not verified these WidgetKit limits against current Apple documentation, so treat them as hypotheses to check before design is frozen.

## Open questions

1. **Expression library:** write a small interpreter, or embed an existing one (for example an open-source expression evaluator in Swift)? Writing one gives full control over safety limits.
2. **Data transforms:** is `map` plus expressions enough, or do you need a `transform` step (group, sort, dedupe) for sources like news feeds?
3. **Multi-request sources:** `each` fan-out is simple but can hammer an API. Add rate limits and request budgets per widget.
4. **Charts:** where does history come from? A widget has no storage in v0.1, so a price sparkline needs either an API that returns history or a small per-widget history store.
5. **Versioning:** how does a spec 0.2 widget behave on a 0.1 runtime? Suggest refusing with a clear update prompt rather than guessing.
6. **Interactivity:** v0.1 has only open-URL, copy and refresh. Toggles, timers and text input matter for to-do and habit widgets, and need a small per-widget state model.
