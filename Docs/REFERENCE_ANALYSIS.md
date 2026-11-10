# Reference Analysis: Kakuchi

Researched 10 November 2026. Kakuchi is used as inspiration only; nothing here is copied from it.

## Research coverage

| Material | Status |
|---|---|
| kakuchi.app home, /features, /ai, /why, /compare, /compare/widgetai, /changelog, /privacy, /community, /guides/build-a-mac-widget-with-ai | Read in full |
| Reddit thread `r/macapps/comments/1xk7u8t` | **Original post read** (text supplied by the owner). **Comments not available**: reddit.com is blocked for the fetch tool and the built-in browser. |
| The app itself | Not installed or run. Everything below comes from the vendor's own pages. |
| Independent reviews | None found. The only third-party page is a Peerlist listing that repeats the vendor copy. |

**Consequence:** the feature-request half of deliverable 2 is still outstanding, because it lives in the comments. Nothing below guesses at what commenters said.

## The Reddit launch post

Statements by the author (Himanshu, who describes himself as a software engineer at Google building Kakuchi as a side project):

| Statement in the post | What it tells us |
|---|---|
| The motivating problem was checking TechCrunch, the Hacker News front page and a few subreddits several times a day, and wanting the headlines on the desktop | Kakuchi began from the same itch as CraftPeep. Its answer was a general widget builder; the news problem is solved one widget at a time, with no shared store. |
| Hacker News, Reddit (any subreddit) and any RSS feed are built in | Matches the site. |
| For a site with no feed, the user asks for its latest posts and the widget reads the page and extracts headlines | Model-written page scraping per widget. Flexible, fragile when a page changes, and outside CraftPeep's "official feeds only" rule. |
| Examples beyond news: a water counter with a button, a flight countdown with destination weather, open GitHub pull requests with review status | Stateful and personal widgets are a selling point. CraftPeep's spec has no per-widget state and that stays out of scope. |
| Preview first, then iterate conversationally ("smaller", "top 5 only") | Same loop CraftPeep plans; in CraftPeep those two edits are setting changes, with or without AI. |
| Runs on Claude Code, Codex or similar, so no API key; own key and local models also work | Matches the site. |
| Existing Übersicht widgets run unchanged | **Confirms** the earlier inference that "classic desktop widgets" means Übersicht. |
| "Native Swift, about 7 MB, macOS 14+, notarized" | The shell is native; widgets are still web content per the site. Small download. |
| No account and no analytics in the app | Consistent with the privacy policy (analytics are on the website only). |
| $14.99 launch, $24 later, no trial, 14-day refund | Matches the site. |
| Compared against Übersicht (free, but hand-written) and Apple's widgets (fixed by installed apps) | He positions against authoring effort and fixed catalogues, not against news or intelligence tools. |

What the post changes in this analysis:

1. The news use case is not incidental to Kakuchi; it is the origin story. A casual user who only wants headlines on the desktop is already served for $15. CraftPeep has to earn its place through what a widget container cannot do: one story from five sources shown once, a ranking with reasons, a briefing, search across history.
2. CraftPeep is now free and open source, which removes price as a point of comparison in both directions.
3. Page-reading for feedless sites is a real convenience CraftPeep will not match. The honest answer in the product is to say a source has no feed and offer the official alternatives listed in DATA_SOURCES.md.

## What Kakuchi is (confirmed from its site)

A general-purpose Mac widget platform: "50+ live widgets for your desktop, notch, menu bar and lock screen", plus an AI builder that writes new widgets from a description.

| Area | Confirmed observation |
|---|---|
| Maturity | Version 0.0.2 build 16, dated 9 November 2026. Very new. Community gallery has one widget. |
| Price | $14.99 one-time launch price, $24 regular. Licence key, 14-day refund, no free tier, no subscription. |
| Distribution | Direct download, not the Mac App Store. The site says it uses system features the App Store does not allow. macOS 14+. |
| Placement | Six places: desktop (under windows, persists across Spaces, full screen, sleep, restart), notch shelf, menu bar item per widget, lock screen (off by default), keep-on-top over full-screen apps with optional click-through, edge docking. "Glance": hold double-Control to overlay all widgets. |
| Layout | Drag, corner resize, no-overlap snapping, auto-arrange grid with undo, stacks, multiple copies with separate settings, per-display placement, lock positions, hide all. |
| Widget format | Web technologies. The site states widgets are HTML, CSS, SVG and canvas, and that they are "JSX files you can open and edit". Marketing imagery shows `.tsx` files importing from a `kakuchi` module with hooks. An optional design kit makes them look native. |
| Compatibility | "Classic desktop widgets run unchanged" and an existing widgets folder can be reused. |
| Settings | Each widget declares settings; the app renders a native form. Secret fields go to the Keychain. Hot reload per widget. |
| AI builder | Chat on the left, live preview on the right. The model writes widget code; the app renders it off-screen and feeds screenshot and errors back so the model self-corrects. The model is steered to expose changeable things as settings, so later edits change a setting rather than code. |
| AI providers | Three routes: an existing Claude or ChatGPT subscription via the Claude Code or Codex CLIs, an API key (Anthropic, OpenAI, Gemini, OpenRouter, any OpenAI-compatible endpoint), or a local model (Ollama, LM Studio). No AI resale. |
| MCP | Built-in stdio MCP server with 15 tools (read docs, list/sample data sources, create/update/preview widget with screenshot, place, settings, theme, delete). |
| Data | 17 native macOS sources (system, CPU, memory, disk, battery, network, Bluetooth, audio, displays, apps, Now Playing, calendar, reminders, photos, files, input counts). Feeds: RSS/Atom, Hacker News, Reddit. A Web Page widget embeds any site. |
| Refresh | A source runs only while a widget on screen uses it. Everything pauses when the display sleeps. |
| Security model | Widgets declare the sites they talk to; redirects must stay on those sites. Widgets that run commands, use the network or read files are listed in an install sheet for approval. Previews never run commands. AI can only edit or delete widgets it made. Widget pages run under a content security policy. |
| Privacy | No account. Site uses Google Analytics. Sharing a widget uploads its code and a screenshot, stored with Supabase, and checks the licence key. |
| Themes | Ten themes, six "moods" (theme plus backdrop layer), shareable "setups" (widgets, positions, theme, wallpaper in one file, secrets excluded). |

## Inferences (not confirmed)

| Inference | Basis | Confidence |
|---|---|---|
| Widgets render in web views (WKWebView or similar), one per widget or pooled | "Widgets are web technologies", CSP statement, Web Page widget | High, but unverified |
| Not sandboxed | Runs shell commands, lock-screen presence, counts key presses, direct download only | Medium-high |
| Resource cost scales with widget count more steeply than native rendering would | Web view per widget | Speculative. No measurements available |
| Subscription route shells out to the user's installed `claude` / `codex` CLI | Site says sign-in happens in those tools and Kakuchi never sees it | High |

I have no evidence about its internal architecture beyond these.

## Strengths worth learning from

1. **Bring-your-own AI with three routes.** Removes the AI cost objection completely and makes a one-time price viable.
2. **Render-and-correct loop.** The model sees the actual render and errors before the user does. The declarative equivalent for CraftPeep is validate-and-retry against the schema, which is cheaper and deterministic.
3. **Settings as the edit surface.** "Add TSLA" changes a setting, not the widget. CraftPeep's spec already has `settings`; the builder should prefer setting changes over view edits.
4. **Install sheet generated from declared permissions.** Same principle as CraftPeep's "permissions are data".
5. **Visibility-driven refresh.** Simple rule, easy to explain, good for battery.
6. **Copies with separate settings**, stacks, and one-click arrange are cheap wins once a canvas exists.

## Weaknesses and openings

1. **It is a container, not a source of insight.** It shows whatever a widget fetches. There is no shared store, no deduplication, no history, no ranking, no briefing. Two news widgets fetch and render independently. This is exactly the gap CraftPeep's intelligence engine fills.
2. **Generated executable code.** JSX with network, file and command capability is flexible but puts the security burden on an approval sheet the user must read. A shared setup file can carry a command-running widget. CraftPeep's declarative spec removes this class of risk rather than gating it.
3. **Not portable.** Web-view widgets with shell access cannot move to WidgetKit or iPhone. A declarative spec can.
4. **No App Store path** by its own admission.
5. **No provenance or freshness model.** Nothing on the site addresses source credibility, timestamps or data licensing for markets data.
6. **Breadth over depth at v0.0.2.** Six placements and 50 widgets at that version number suggests wide, thin coverage. Unverified without running it.

## Feature comparison

| Capability | Kakuchi | CraftPeep (target) | CraftPeep MVP |
|---|---|---|---|
| Primary job | Put any widget anywhere | Explain what matters in tech, AI and markets | News and AI intelligence with briefing |
| Main surface | Desktop widgets | Main window dashboard, plus widgets and menu bar | Main window, menu bar, one desktop widget type |
| Shared data store with history | No | Yes (SQLite) | Yes |
| Deduplication and story clustering | No | Yes | Yes (URL and title tiers) |
| Source credibility and hype classification | No | Yes | Yes (rules first) |
| Briefings | No | Yes | Morning briefing |
| Full-text search across history | No | Yes | Yes |
| Widget format | Generated JSX in a web view | Declarative JSON, native SwiftUI | Declarative JSON, native SwiftUI |
| AI builder output | Code | Schema-validated spec | Deferred to the release after MVP |
| Widget can run commands or read files | Yes, with approval | No, by design | No |
| System data widgets (CPU, battery, Now Playing) | Yes, 17 sources | Not a goal | No |
| Notch, lock screen, Glance, moods | Yes | Not planned | No |
| Menu bar | Any widget as an item | One purpose-built Pulse | Minimal Pulse |
| BYO AI key, local model | Yes | Yes | Yes (Anthropic, OpenAI-compatible incl. Ollama) |
| Subscription via CLI | Yes | Not planned (conflicts with sandbox) | No |
| MCP server | Yes | Possible later, read-only first | No |
| Sandbox / App Store eligible | No | Yes, kept as a constraint | Yes |
| iPhone | No | Phase 2 | No |

## Positioning

Kakuchi answers "what can I put on my desktop?". CraftPeep answers "what happened, and why does it matter to me?". The widget layer is a display surface for an intelligence store, not the product.

Do not compete on placement breadth, widget count or system gauges. One developer already ships all of that for $15, and the two apps can sit side by side on the same Mac. Compete on:

- A local store that sees every source at once, so it can cluster, rank and summarise.
- Provenance and freshness on every item.
- Widgets that are safe by construction and portable to iPhone.

## Outstanding research

1. The Reddit thread's comments: feature requests, complaints, developer replies.
2. Hands-on evaluation of Kakuchi (resource use with ten widgets, builder quality, failure modes). Worth an hour and $15 before the widget canvas is designed (M7).
3. WidgetAI (getwidgetai.com) and Orbl, both named on Kakuchi's compare page and closer to parts of CraftPeep's scope. Not yet reviewed.
