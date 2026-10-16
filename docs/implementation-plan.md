# Implementation plan

One milestone per session. Each milestone lists the **only** docs to read.
Done = acceptance met + `tools/check.dart` green + `progress.md` updated.

| # | Milestone | Read | Deliverable / acceptance |
|---|---|---|---|
| M0 | Scaffold | architecture, design-system, security | Workspace (app, metro_core, data_pipeline), lints, `tools/check.dart` with secrets scan, theme tokens, fonts, ARB en/hi, go_router shell (Go/Map/Ask) with placeholder screens & `StateView`. App builds APK. |
| M1 | Dataset schema + fixture | data-model, testing | `metro_core` models + SQLite reader + validation; `mini_network` fixture compiled to sqlite by pipeline `build` from YAML; validation tests incl. corrupt cases. |
| M2 | Real data pipeline | metro-data-sources, data-model | `fetch` (Overpass + Wikidata, pinned queries, lock file), `merge` with curated overlays, `derive` edge times, `sign`, `diff`. Produces real `metro.sqlite` (stations/lines/edges/transfers/names). Attribution rows. |
| M3 | Routing + fare | routing | Graph, Dijkstra profiles, alternatives, itinerary, fare engine, last-train check. Fixture + known-journeys tests. |
| M4 | Search | search | Normalizer, transliteration, tiers, `search_cases.yaml` passing; perf test < 16 ms. |
| M5 | Bootstrap + Home + Picker + Route results | offline, ux, screens S1–S3 | Dataset loading/fallback chain, user DB (recents), S1–S3 complete with all states. Offline integration test. |
| M6 | Station detail + Nearby | screens S5–S6, security (location) | S5 sections w/ provenance, S6 with permission flows, external directions intent. |
| M7 | Map | map | Pipeline layout step, renderer, hit-test, route highlight, a11y. |
| M8 | Journey mode | routing (progress), screens S4 | Step engine, corrections, keep-awake, arrival exit, resume after process death. |
| M9 | Offline assistant | ai (deterministic part) | Intents, lexicons, slot filling, templates, clarifications, anti-fabrication suite. |
| M10 | Data updates | sync, offline | Manifest, signature, download, validate, swap, rollback; integration test. |
| M11 | Online AI | ai, security | Proxy (separate repo/folder `server/ai-proxy`), `ProxyAiGateway`, post-check, rate limit. |
| M12 | Monetization + settings | product (monetization), ux (ads), security | Ads in allowed slots only (lint test asserting forbidden routes have no ad widget), UMP, premium purchase/restore, settings, licences page. |
| M13 | Release hardening | testing, security | A11y audit, perf profiling on low-end device, Hindi copy review, Data safety, store listing, privacy policy. |

**Parallel human track (starts now, owner):** curate gates/landmarks, platforms, facilities,
parking, first/last train for the top-100 stations into `data/curated/` (template from M1),
request OTD/DMRC permission, fill `known_journeys.yaml` (≥ 50 verified pairs), trademark check.

MVP release = M0–M10 + M12–M13 (M11 online AI can ship in 1.1).

## Future features (post-V1)
Live service notices · offline-capable basemap (licensed) · timetable routing (RAPTOR) if GTFS
licensed · journey ongoing notification + "get off next" in background · home-screen widget
for saved trips · Wear OS glance · other metros (Mumbai, Bengaluru…) via per-city datasets ·
RRTS/bus multimodal · crowd hints · voice input (on-device speech) · iOS release.

## Token / context-saving strategy
- CLAUDE.md stays < 70 lines: rules + pointers only. Specs live in docs/, one topic per file.
- Each milestone row above names the only docs to read; skills (`.claude/skills/*`) load on demand
  and hold *procedures/checklists*, not specs (they link to docs).
- `progress.md` is the resume point: current milestone, next step, blockers, 5-line session log.
- Never read generated files (`*.g.dart`, l10n output, `data/cache/*`, `metro.sqlite`); query the
  dataset with the pipeline CLI (`inspect` command, added in M2) instead of dumping it.
- Tests use the 20-station fixture, so debugging never needs the full dataset in context.
- Subagents only for isolated research (licence checks, data verification) or parallel audits.
- When context gets large mid-milestone: write state to progress.md, continue from it.

## Risks
| Risk | Impact | Mitigation |
|---|---|---|
| Gate/platform/facility data has no open source | Journey mode & station screens thin | Human curation track now; top-100 first; "Not yet verified" states; report button |
| OTD/DMRC licence ambiguity | Can't use official GTFS/timings | Build on OSM/Wikidata + curated; request permission early |
| Fare mismatch vs DMRC matrix (slab edges) | Wrong fare shown | Verified overrides; known-journeys fare checks; "estimated" label |
| Network changes (Phase 4 openings, renames) | Stale app | Signed OTA dataset updates in days; stable IDs + aliases |
| Map schematization effort | M7 slip | Ship simplified geographic layout first; octilinear later |
| Underground GPS | Journey progress wrong | Time-based + user correction; never auto-skip interchanges |
| Name/trademark ("MetroMitra", DMRC marks) | Store takedown | OPEN-4 check; no DMRC logo; "not affiliated" notice |
| AI cost/abuse | Bill spikes | Proxy rate limits, small model, opt-in, offline-first |
| Ads/Play policy (location + ads + Data safety) | Rejection | No background location, UMP, accurate Data safety form |
| Scope creep toward reference-app feature list | Complexity, clutter | V1 scope in product.md is the contract; new features → future list |
