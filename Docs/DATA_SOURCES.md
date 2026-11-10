# Data Sources and API Governance

Researched 10 November 2026. Each claim is marked:

- **Confirmed**: read from the provider's own page during this research.
- **Reported**: from third-party pages found by search; consistent but not checked against the provider.
- **Recalled**: from my prior knowledge, not re-checked. Verify against official documentation before implementing the adapter.

Rule for every adapter: its pull request includes a link to the provider's current terms and a note of what was checked.

## Summary

| Source | Route | Auth | Use in | Risk |
|---|---|---|---|---|
| Publication and company blogs | RSS/Atom | None | MVP | Low. Per-feed availability must be checked. |
| Hacker News | Official Firebase API, Algolia search API | None | MVP | Low |
| GitHub | REST API, per-repo Atom feeds | Optional token | v0.2 | Low. No trending endpoint. |
| arXiv | Official API | None | v0.3 | Low |
| SEC EDGAR | Official JSON APIs | None, User-Agent required | v0.3 | Low |
| Market prices | Commercial provider, user's own key | API key | v0.2 | **High.** Licence and coverage. |
| Macro (FRED, ONS, BoE) | Official APIs and downloads | Mixed | v0.3 | Medium. Three different shapes. |
| FX | ECB reference rates or the market provider | None / key | v0.2 | Low for daily rates |
| Reddit | Data API | OAuth | Not planned | **High.** Commercial terms. |
| X/Twitter | | | Not planned | No viable free route |

## RSS and Atom (MVP)

- **Route:** each publisher's own feed.
- **Confirmed on 10 November 2026** (HTTP 200, parsed, items stored by the live smoke test): TechCrunch, The Verge, Ars Technica, Wired, MIT Technology Review, OpenAI News, Google DeepMind, Google AI Blog, Hugging Face Blog, Mistral AI, NVIDIA Blog, Engineering at Meta, GitHub Blog, Apple Developer News, Swift.org, Simon Willison. URLs and tiers are in `Packages/CraftPeepKit/Sources/Ingestion/Resources/sources.catalog.json`.
- **Confirmed absent:** `anthropic.com/rss.xml` returns 404. No official Anthropic feed has been found, so Anthropic is currently covered only through Hacker News and other publishers. Not yet checked: Microsoft, xAI, Meta AI.
- Re-check the catalogue with `CRAFTPEEP_LIVE=1 swift test --filter LiveSmokeTests`.
- **Where no feed exists:** do not scrape the page as a foundation. Options, in order: an official alternative (GitHub releases feed, a changelog feed, a sitemap), HN coverage of that domain via Algolia, or leave the source out and say so.
- **Usage limits:** none published. Be a good client: conditional GET, minimum interval of 15 minutes per feed, honour `Retry-After` and `Cache-Control`, one identifying User-Agent (generic product name, no personal contact details unless the user opts in).
- **Rights:** a feed licenses reading, not republication. Store and show title, publisher, timestamp, link and the feed's own excerpt. Do not fetch and store full article bodies. AI summaries are generated from title and excerpt and always link out. If CraftPeep is ever sold, keep excerpts short and review publisher terms for the default catalogue.
- **Fallback:** a dead feed is marked unhealthy in Settings after repeated failures; nothing else breaks.

## Hacker News (MVP)

- **Official API (Firebase):** `hacker-news.firebaseio.com/v0`. Lists (`topstories`, `beststories`, `newstories`) and items. No key. Recalled: no documented rate limit. Reported: heavy sustained polling is throttled.
- **Algolia HN Search:** `hn.algolia.com/api`. Search by query, tags, date and points. Confirmed that the API page documents the endpoints. Reported, not confirmed: 10,000 requests per hour per IP and a 1,000-hit cap per query.
- **Plan:** use Algolia for "stories above N points in the last 24 hours" (one request returns titles, URLs, points and comment counts) and Firebase only for the live front-page order. This avoids one request per item.
- **Implemented:** the Algolia `search?tags=front_page` endpoint, polled at most every 15 minutes. Confirmed on 10 November 2026 that it returns 30 front-page stories with points and comment counts. The points-threshold query and the Firebase lists are not implemented.
- **Value beyond stories:** an HN item's URL is a strong clustering key (it is the article the discussion is about), and points/comments are the community-interest signal.
- **Attribution:** link to the HN discussion alongside the original article.

## GitHub (v0.2)

- **Trending:** Recalled: there is no official trending API; the trending page is HTML only. Scraping it is fragile and against the "prefer official APIs" rule. Search during this research found nothing contradicting that, but it did not positively confirm it.
- **Substitute, using the official search API:** repositories created in the last N days sorted by stars, and repositories pushed recently above a star threshold, filtered by language or topic. Store star counts on each fetch so CraftPeep computes its own star velocity over time. This is a better signal than the trending page once a week of history exists, and it is honest to label it "rising" rather than "trending".
- **Limits:** Confirmed from GitHub docs: search is limited to 30 requests per minute when authenticated; unauthenticated core REST is 60 requests per hour. Reported: unauthenticated search is 10 per minute. A fine-grained personal token with no scopes raises the limits and is optional.
- **Releases:** Recalled: every repository exposes `releases.atom`, so release tracking for a watchlist reuses the RSS adapter with no API quota.
- **Security advisories:** Recalled: the global advisories endpoint is public. Verify.

## Market prices (v0.2) — decision required

No provider was verified against its own terms in this research; the table is from third-party comparisons and needs checking.

| Provider | Free tier (reported) | Notes |
|---|---|---|
| Twelve Data | About 8 requests/minute, 800/day, delayed | Non-commercial on free tier. Actual capacity depends on credit weights and exchange entitlements. |
| Finnhub | About 60 calls/minute; free WebSocket | Commercial use restricted on free tier. Real-time limited. |
| Alpha Vantage | About 25 requests/day | Too low for a watchlist with charts. |
| Unofficial Yahoo endpoints | No terms that permit it | Rejected. Unlicensed and breaks without notice. |

Unknowns that decide the choice:

1. **LSE and FTSE 100 coverage on each tier.** Not found. UK equities and index values are frequently paid add-ons.
2. **Index values.** Index levels (S&P 500, NASDAQ, Dow, FTSE 100) are licensed by the index owners and are often absent from free tiers. Fallback: show a tracking ETF, labelled as a proxy with its real name, never presented as the index.
3. **Display and redistribution rights** if CraftPeep is distributed to others.

**Recommended approach:** a `MarketDataProvider` protocol with the user supplying their own key, the same model as AI. Each user holds their own agreement with the provider, the app ships no shared key, and quotas are per user. This is the only arrangement that plausibly survives distribution, and it still needs confirming in the chosen provider's terms. Build one adapter first, chosen after a one-hour spike that checks the seven watchlist tickers, two UK tickers, the four indices, GBP/USD and EUR/GBP against Twelve Data and Finnhub with real keys.

Every quote stored carries provider, timestamp, delay class and currency. A 24-hour-old price is shown as 24 hours old.

## Macro and FX (v0.3)

| Series | Source | Status |
|---|---|---|
| US CPI, Fed funds rate, US GDP, US unemployment | FRED API (St. Louis Fed) | Recalled: free key, JSON, a required attribution notice stating the product uses the FRED API and is not endorsed by the bank. Terms not re-read. |
| UK CPI, UK GDP, UK unemployment | ONS | Recalled: a public API and CSV time-series downloads exist; the API has been labelled beta. Not checked. |
| Bank Rate | Bank of England statistical database | Recalled: CSV download by series code, no formal API. Not checked. |
| GBP/USD, EUR/GBP daily | ECB euro reference rates | Recalled: free daily XML, around 16:00 CET, reference only, not tradable rates. Cross rates are derived. Label as "ECB reference". |
| Central bank announcements, economic calendar | No free official calendar API known | Open. Options: Fed and BoE press-release RSS for announcements; a hand-maintained yearly schedule file for meeting and release dates. |

Macro series change monthly or less. Fetch daily at most, store observations with their release date, and never interpolate.

## SEC EDGAR (v0.3)

- **Confirmed** from sec.gov: fair-access limit of 10 requests per second in total per user; the SEC may block excessive use. Reported: a declared User-Agent is required and missing ones receive 403.
- **Recalled:** `data.sec.gov` serves submissions and XBRL company facts as JSON with no key. This gives revenue, operating income, net income and EPS per reporting period, straight from filings, for all seven watchlist companies.
- **Limits of this source:** US filers only. No consensus estimates, so "earnings surprise" needs a second, probably paid, source; defer and do not approximate. No earnings calendar; future dates need company IR feeds or a provider.
- **UK and EU companies:** no equivalent free structured source identified. Open.

## arXiv (v0.3)

Recalled: official Atom-based API, no key, a courtesy limit of roughly one request every three seconds, metadata under a permissive licence, and an acknowledgement requested. Verify before building. Daily category listings (cs.AI, cs.LG, cs.CL) are a firehose; filter by the user's interests and by whether a paper is also being discussed on HN or linked from a tracked blog.

## Reddit (not planned)

- **Reported**, consistently across sources: free tier requires OAuth, allows about 100 queries per minute per client, and is non-commercial only; commercial use needs a contract with Reddit; unauthenticated traffic is blocked; terms last revised July 2026.
- Whether per-subreddit RSS feeds fall under the same terms was not established.
- **Recommendation:** leave Reddit out. If wanted later for personal use, let the user register their own Reddit app and enter their own credentials, and keep it off by default. HN already supplies the community-interest signal.

## Governance rules

1. Official API or feed first. No scraping as a dependency.
2. No shared API keys shipped in the app.
3. Per-source rate limiter and backoff in the ingestion layer, not in each adapter.
4. Every stored record keeps source ID, original URL and retrieval time.
5. A provider's attribution text, where required, lives next to the data it covers and in an Acknowledgements screen.
6. Before any public or paid release, re-read the terms of every default source and record the result here.
