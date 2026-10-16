# Testing strategy

Most logic lives in pure-Dart `metro_core`, so most tests are fast `dart test` with no device.

## Layers
| Layer | Tool | Scope |
|---|---|---|
| Unit (core) | `dart test` in packages/metro_core | routing, fare, search, assistant, validation, geo, map hit-test |
| Pipeline | `dart test` in tools/data_pipeline | merge rules, overlay precedence, sqlite build, signing, diff |
| Widget | `flutter test` | each screen's states (loading/empty/error/offline/denied/partial) |
| Golden (few) | `flutter test --tags golden` | route timeline, step card, map highlight — light/dark, 200 % text |
| DB migration | drift `SchemaVerifier` with stored schema snapshots | every user-DB version → latest |
| Integration | `integration_test` on emulator | cold start offline, route → journey, data update swap & rollback |
| Manual release checklist | airplane mode, TalkBack, Hindi, low-end device | before each Play release |

## Test data
- `data/fixtures/mini_network/` — synthetic 20-station network covering: branch line, loop,
  ring, through-running service, in-station interchange with long walk, out-of-system walk link,
  two operators with different fare systems, missing gate data, unverified platform.
- Real dataset regression: `data/curated/known_journeys.yaml` — human-verified pairs with
  expected lines, interchange stations, change count and fare (from official sources).
  Runs in the pipeline (build gate) **and** in CI.

## Required suites (from brief)
| Suite | Key cases |
|---|---|
| Route correctness | fixture exact paths per profile; known journeys; path edges exist; same station → empty itinerary |
| Interchange | correct transfer station & direction after change; through-service avoids false change; out-of-system walk flagged separate ticket |
| Route edge cases | loop direction, branch split, unreachable (disconnected fixture) → typed error, closed station excluded, ties deterministic |
| Search | `search_cases.yaml` en/hi/typos/aliases/partials/landmarks; nonexistent → empty |
| Fare | slab boundaries (exact km edges), smart-card + off-peak windows at boundary minutes, Sunday/holiday, overrides win, cross-operator sum, paise rounding |
| Offline mode | app boots & routes with network disabled (fake HTTP client throwing); no core provider depends on network |
| Network unavailable | updater/AI/ads timeouts → correct states, no crash, no retry storm |
| Assistant answers | `assistant_cases.yaml` ≥ 150 utterances → intent+slots+template |
| **Anti-fabrication** | unknown station/landmark, missing gate/platform/timing, ambiguous names → `missing`/`clarify`, never a value; property test: every number/station in rendered text ∈ answer.facts |
| Map data | every station positioned, paths ordered, no overlapping markers, hit-test nearest |
| Database migration | user DB v1→vN; dataset schema range checks |
| Corrupted/invalid data | truncated file, bad sha, bad signature, missing table, FK break, schema too new → fallback chain |

## Conventions
- Tests reference requirement IDs: `// covers: FR-ROUTE-6`.
- Inject `Clock`, `AiGateway`, `LocationSource`, `HttpClient`; no real network in tests.
- CI: `dart run tools/check.dart` (format, analyze, all tests, secrets, pipeline `--offline` validate).
- Coverage target: metro_core ≥ 90 % lines; app ≥ 60 % (states over pixels).
