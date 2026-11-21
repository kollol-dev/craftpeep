# Reference Analysis

Two reference products: Kakuchi (desktop widgets, below) and NetNewsWire (feed reader, at the end).

## Kakuchi

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


## NetNewsWire

Researched 21 November 2026 from netnewswire.com (home page, FAQ, privacy policy), the NetNewsWire blog (posts from April to November 2026) and the GitHub README. The app itself was not installed or run.

### What it is (confirmed from those pages)

| Area | Observation |
|---|---|
| Product | A free, open-source RSS reader for Mac, iPhone and iPad. Version 7.3 (18–19 November 2026). Mac needs macOS 15; iOS needs iOS 26. |
| Lineage and project | First released in 2002; rebooted in 2018. MIT licence. About 10,600 stars, 790 forks and 90 contributors on GitHub. Made by volunteers; the README asks people not to send money. |
| Formats | RSS, Atom, JSON Feed and RSS-in-JSON. Enclosures and Media RSS from 7.3. |
| Reading | Shows the articles themselves, with customisable article themes (a community catalogue of them), a Reader view for feeds that publish only summaries (it calls a server hosted by Feedbin), and thumbnails and feed images in the timeline (off by default because they cost bandwidth, memory and storage). |
| Organising | Folders, starred articles, "All Unread" and "Today" smart feeds (Today is the last 24 hours), hiding read articles and read feeds, search, multiple accounts. |
| Ordering | Chronological. No ranking. The home page pitches it as an alternative to "big tech social media and their algorithms". |
| Sync | iCloud, Feedbin, Feedly, BazQux, Inoreader, NewsBlur, The Old Reader and FreshRSS. |
| Mac specifics | Single-key keyboard shortcuts, column layout (7.2), multiple windows, customisable toolbar, AppleScript, a status bar, a Safari extension for adding feeds, OPML import and export, background refreshing. |
| Housekeeping | An activity view, an activity log, an error log, account statistics with a database vacuum, and a "Dinosaurs" window listing feeds that have not updated in a chosen number of months. Unread counts can be hidden or shown as a dot (7.2), explicitly to remove the feeling of having to catch up. |
| Defaults | Sixteen default feeds for new users, so there is something to read straight away. |
| Privacy | No account. Opt-in crash logs only. The website uses no cookies, JavaScript or trackers. |

### How it compares with CraftPeep as built

| | NetNewsWire | CraftPeep |
|---|---|---|
| Job | Read the feeds you chose, in order, and keep track of what you read | Tell you which stories matter today across your sources, and why |
| Unit | An article | A story: one row however many sources reported it |
| Order | Chronological | Ranked with stated reasons (Top) or chronological (Latest) |
| Article text | Rendered in full, themed | Never rendered: headline, excerpt, open the original. HTML from feeds is untrusted by design |
| Duplicates across sources | Shown separately | Grouped, with every source listed |
| Provenance labels | None | Source tier, support level, rule-based kind with the rule shown |
| Summaries and briefing | None | Optional AI, off by default, bring your own key |
| Beyond feeds | — | Hacker News signal, GitHub's rising repositories, desktop widgets, a menu bar item |
| Formats | RSS, Atom, JSON Feed, RSS-in-JSON | RSS, Atom and JSON Feed (added after this comparison) |
| Folders, per-feed view | Yes | Per-source view added after this comparison; no folders |
| Mark all read, hide read | Yes | Mark All as Read added; no hiding of read stories |
| OPML import and export | Yes | Added after this comparison |
| Keyboard | Single-key shortcuts | Single-key shortcuts added after this comparison |
| Sync and iPhone | Yes, nine options | No (Phase 2 and 3) |
| Stale and failing feeds | Dinosaurs window, error and activity logs | Failing and quiet-for-30-days filters added; no activity log |
| Maturity | 24 years, thousands of users, 90 contributors | Unreleased, one user, untested interactions |

### What this means

**As a feed reader, CraftPeep loses on every axis, and should not try to win there.** NetNewsWire is free, open source, mature, synced, on the iPhone, and shows articles properly. Someone who wants to read their feeds should use it. CraftPeep is worth building only as the layer above: the morning view of what matters, grouped and explained, with the reading done in the browser or in a reader.

**There is a real philosophical difference, and some users will choose NetNewsWire because of it.** NetNewsWire's pitch is that you are in control and no algorithm decides. CraftPeep ranks. The answer is the one already in the design: the ranking is a few named rules with the reasons shown, the user can follow and mute topics, and Latest is one click away. It is worth saying this plainly on the project page.

**The two can sit side by side.** A user can keep NetNewsWire for reading and use CraftPeep for the overview, with the same feed list in both. That makes OPML import the single most useful thing to borrow: it is how such a user brings their feeds across in one step.

### Worth borrowing, in order

Built on 21 November 2026: all six.

1. **OPML import and export.** The way users move feed lists between apps; small to build; the OPML parser can reuse the feed parser's limits.
2. **JSON Feed.** Some independent blogs publish only JSON Feed. A second small parser.
3. **A view of one source's stories, and Mark All as Read.** Basic expectations of anything that shows feeds.
4. **Single-key shortcuts** (j/k or arrows, space, m for read, s for save). Already in the requirements; not built.
5. **A stale-sources list and a fetch log view.** The data is already stored (`fetch_log`, `last_ok_at`).
6. **Hiding the unread badge, or showing a dot.** NetNewsWire added this to remove the pressure to catch up; CraftPeep's menu bar badge creates the same pressure.

Not worth borrowing now: rendering article HTML and themes (conflicts with CraftPeep treating feed HTML as untrusted, and duplicates what a reader does well), thumbnails (bandwidth, and CraftPeep is text-first), and third-party sync services (CraftPeep's sync is a later, separate decision).

### Confirmations of earlier decisions

- **macOS 15 as the minimum** is the same choice NetNewsWire made for its current version.
- **A curated default feed list** is long-standing NetNewsWire practice; its reason (something to read straight away) is the same. NetNewsWire ships 16; CraftPeep ships 34, which may be more than a newcomer needs.
- **Free, open source and maintained by volunteers is viable** for a Mac reader. NetNewsWire uses MIT, a data point for the open licence question in ADR-012.
- **Standard controls pay off.** NetNewsWire's blog credits them for supporting a new iPhone form factor with no work; CraftPeep's interface uses standard controls throughout.
