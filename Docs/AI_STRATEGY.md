# AI Strategy

Status: implemented in part, 11 November 2026. The provider abstraction, summaries, briefing, ledger and budget exist; see ROADMAP.md (M4b) for what was built, what differs from this document, and what has not been tested against a real model. The widget builder, classification refinement and weekly reports are not started.

## Principles

1. **Optional.** With no provider configured, ingestion, clustering, rule-based classification, ranking, search, widgets and a non-AI digest all work.
2. **Never on the refresh path.** Fetching and storing data makes no AI calls.
3. **No tools, no actions.** Models receive text and return text or a structured object. Nothing a model returns can trigger a fetch, a file write, a setting change or a network call. This is the main defence against prompt injection (see SECURITY.md).
4. **Bring your own.** The user's key or the user's local model. No CraftPeep-operated AI service.
5. **Labelled.** AI output is always marked, with model and time, and linked to the stored clusters it used.

## Provider abstraction

```swift
protocol AIProvider: Sendable {
    var id: ProviderID { get }
    func capabilities(for model: ModelID) -> ModelCapabilities     // structured output, context size, known price
    func complete(_ request: AIRequest) async throws -> AIResponse // text or schema-constrained JSON, plus token usage
}

struct AIRequest: Sendable {
    var feature: AIFeature          // summary | briefing | classify | widgetBuilder
    var system: String
    var messages: [AIMessage]
    var responseSchema: JSONSchema? // nil for prose
    var maxOutputTokens: Int
    var timeout: Duration
}
```

Two implementations cover the required providers:

| Implementation | Covers | Notes |
|---|---|---|
| `AnthropicProvider` | Claude models through the Messages API | Native structured output and prompt caching. |
| `OpenAICompatibleProvider` | OpenAI, Ollama, LM Studio, OpenRouter, and Gemini through its OpenAI-compatible endpoint | Base URL, key and model are user settings. Capability differences (structured output support, usage reporting) are detected per endpoint, with a plain-JSON-plus-validation fallback. |

A dedicated Gemini client is added only if the compatible endpoint proves insufficient. A subscription route through the Claude Code or Codex CLIs, which Kakuchi offers, is not planned: it requires launching external executables, which the sandbox does not allow.

Features call a `ModelRouter`, not a provider:

```
feature -> ModelRouter -> (budget check) -> provider for that feature -> usage ledger
```

The user assigns a provider and model per feature class, with a sensible default: a small, cheap model for summaries and classification; a stronger model for the briefing and the widget builder. Default suggestions in Settings are read from a small bundled table that can be updated, not hard-coded in feature code. Fallback is explicit and ordered (for example, cloud then local); a fallback that changes where data is sent is never automatic unless the user enabled it.

## Capabilities by release

| Capability | Release | Input | Output | Cached by |
|---|---|---|---|---|
| Cluster summary | MVP | Titles, excerpts, publishers and timestamps of a cluster's members | Two or three sentences plus "why it matters" | Hash of member content hashes and prompt version |
| Morning briefing | MVP | Top-ranked clusters from the last 24 hours with their summaries, classifications and the user's interests | Structured sections answering the brief's seven questions, each item citing cluster IDs | One per local date; regenerate on request |
| Widget builder | v0.2 | User request, template catalogue, query schema, valid entity and symbol lists | Template and params object | Not cached |
| Classification refinement | v0.2 | Batches of unclassified top-ranked clusters | Kind plus confidence band per cluster | Per cluster, by content hash |
| Weekly reports | v0.3 | Daily briefings and top clusters of the week | Structured report | Per ISO week |
| Conversational search, research assistance | Later | FTS results selected by the app | Answer with citations | |

The briefing is built in two steps to keep it grounded. The app, not the model, selects which clusters go in (ranking). The model explains and connects them. Every briefing item must reference a cluster ID from the input; items citing unknown IDs are dropped by the validator. The model is instructed to state when something is a single unverified report, and the verification status is passed in as data.

Without AI, the briefing view shows a digest: the same ranked selection with titles, sources, classifications and ranking reasons.

## Cost and resource management

| Mechanism | Detail |
|---|---|
| Ledger | Every call writes `ai_usage`: feature, provider, model, tokens as reported by the provider, estimated cost where the price is known, outcome. Unknown prices are shown as unknown, not zero. |
| Budgets | Daily and monthly limits in tokens or estimated currency, per provider. Checked before each call. |
| Degradation | When a budget is exhausted or the provider fails: summaries stop being generated, existing ones remain, the briefing falls back to the digest, and a status line in Settings and the menu bar says why. No retries against a 429 beyond the provider's `Retry-After`. |
| Deduplication | Summaries are keyed by input hash; unchanged clusters are never re-sent. |
| Selectivity | Auto-summarise only the top N ranked clusters per refresh (default small); everything else on demand when opened. |
| Batching | Classification refinement runs in batches on a schedule, not per article. |
| Prompt caching | Stable system prompts first, variable content last, so provider-side caching applies where supported. |
| Local models | Counted in the ledger by tokens with zero cost; subject to a concurrency limit of one so they do not starve the machine. |
| Timeouts and retries | Per-feature timeout; one retry with backoff for transient failures; none for validation failures beyond the builder's two correction rounds. |

Rough sizing for MVP defaults, to be measured, not assumed: on the order of 20 to 40 summary calls and one briefing call per day. That is small enough that a daily budget is a safety net, not a constraint.

## Disclosure and control

- First use of any cloud provider shows what is sent (titles and excerpts of public articles, the user's interest keywords, the user's own prompts) and to whom.
- The user's reading history and saved items are not sent. Interest keywords are sent only for the briefing and can be excluded.
- A local-only mode restricts all AI features to an endpoint on this Mac.
- Keys live in the Keychain, are never logged, and never appear in exports or widget files.

## Prompt handling

- Prompts are versioned files in the `AI` target; the version is part of every cache key.
- Retrieved text is passed in a clearly delimited data section, with a system instruction that the section is untrusted material to be described and never obeyed. This reduces, but does not eliminate, injection; the structural defences in SECURITY.md are what the design relies on.
- Outputs are length-capped and rendered as plain text. No Markdown links or images from model output are made live; links shown beside AI text come from stored article URLs.

## Testing

- Provider clients are tested against recorded responses, including error shapes: 401, 429 with and without `Retry-After`, 5xx, malformed JSON, truncated output, timeout.
- A `FakeProvider` drives feature tests deterministically.
- Briefing and builder validators are tested with adversarial fixtures: unknown cluster IDs, out-of-range params, extra fields, injected instructions inside article excerpts.
- A small, manually run evaluation set (real clusters, expected properties of a good summary) is kept for comparing models and prompt versions. It is not part of CI.
