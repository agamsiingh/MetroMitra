# Progress

Single source of truth for "where are we". Update at the end of every session.

## Current
- **Phase:** M11 Online AI - COMPLETE (2026-10-07). `dart run tools/check.dart` green. Dataset is still **draft**; nothing signed, published or bundled (a check now fails if a dataset is bundled).
- **Next:** M12 Monetization + settings (read: product monetization, ux ads, security). Still open before any release: owner-approved travel-time parameters (ADR-035), real fare data, walk times for the 54 interchange rows, Hindi names (72 stations; `rohini-west` Hindi name is the old one), remaining 14 name conflicts, native Hindi review of the new strings (M13).
- Licensing is a release gate: OPEN-2 + OTD/DMRC permission unresolved.

## Done
| Date | Milestone | Notes |
|---|---|---|
| 2026-10-05 | Blueprint | docs/*, CLAUDE.md, .claude/skills/* created. Licensing research in metro-data-sources.md. No app code. |
| 2026-10-05 | M0 Scaffold | Pub workspace (app, metro_core, data_pipeline), very_good_analysis, `tools/check.dart` (+secrets scan, core-purity check), theme tokens, Inter/Noto Devanagari fonts, ARB en/hi, go_router shell Go/Map/Ask, `StateView`, owner logo as launcher icon + splash, 8 tests. No metro data, no features. |
| 2026-10-05 | M1 Dataset foundation | Schema v1 (22 tables) in `metro_core/dataset/schema.dart`; immutable models; `MetroSnapshot`; sqlite writer + reader (version/corruption checks); `validateSnapshot` (~60 rules, errors+warnings); `DatasetRepository` (sqlite + in-memory); strict YAML authoring loader; TEST-DATA fixture `data/fixtures/mini_network` (12 stations, 3 lines, 2 operators); pipeline `validate`/`build`. 114 core + 12 pipeline tests. ADR-022…026. |
| 2026-10-05 | M2 Real pipeline | fetch (Overpass+Wikidata, lock, cache, safe failure) -> normalize -> overlays -> conflict check -> canonical -> validate -> sqlite; diff; sign/verify/keygen; inspect. Live run: 271 stations, 9 lines, 12 services, 524 edges, stage **draft**. 125 core + 209 pipeline tests. ADR-027..034. |
| 2026-10-06 | M3 Routing + fare | Curated overlay (25 interchange merges, 12 name resolutions, Rohini West, Pink seam); `metro_core/routing` (visit-node Dijkstra, 4 profiles, alternatives, itinerary, travel-time fallback, last-train check) and `metro_core/fare` (slab/override/discount engine, tickets); pipeline `route` command, `routing` report section, check guards. Real draft: 245 stations, 25 interchanges, ONE connected network. 222 core + 215 pipeline tests. ADR-035..040. |
| 2026-10-06 | M4 Search | `metro_core/search`: normaliser (Latin + Devanagari folding), phonetic/Hindi skeleton, bounded Damerau-Levenshtein, `SearchIndex` (stations + lines; names, Hindi, aliases, codes; tiers exact > alias > prefix > substring > fuzzy), pipeline `search` command (+`--self-check`), `search` report section, check guard. Real draft: 562 names/codes, self-check clean. ADR-041..045. |
| 2026-10-06 | M5 Bootstrap + Home + Picker + Results | Dataset bootstrap with candidates/policy/isolate loader and failure states; Home (From/To), station picker on the M4 index (ids, Hindi/English, lines, interchange, did-you-mean), route results on the M3 router (alternatives, timeline, changes/walks, seam, warnings, approximate-time notice, fare only from data). ARB en+hi. App tests 4 -> 105. ADR-046..051. |
| 2026-10-06 | M6 Station detail + Nearby | Station detail by canonical id (NULL-preserving), nearby finder in metro_core (haversine, id tie-break), location seam + geolocator, Nearby screen with all permission states, navigation from picker/Home/results. ARB +83 keys. ADR-052..054. |
| 2026-10-06 | M7 Map | Pure-Dart `MapGeometry` (projection, stop-to-stop segments, framing, grid hit-test), `CustomPaint` map with own camera, tap -> station detail, route overlay (lines, changes, walks only when present), framing for network/station/route, all error states, offline guard test, device-check doc, `METROMITRA_START_ROUTE` debug hook. ADR-055..057. |
| 2026-10-07 | M8 Journey mode | metro_core journey step engine (plan/state/engine, corrections, GPS snap, get-off-next), Journey screen (S4), Start journey on S3, keep-awake (wakelock_plus), resume after process death (`journey_state` in user.sqlite), Home continue banner, restore validation. ADR-058..060. |
| 2026-10-07 | M9 Offline assistant | metro_core assistant (lexicons en/Hinglish/hi, exact-then-loose place resolution via SearchIndex, intent scoring, slot roles, 12 intents, template+facts answers, clarifications), Ask tab (renderer, chips, picker, source line), 190-case corpus + anti-fabrication suite. Fixed M8 `platformFor` direction bug. ADR-061. |
| 2026-10-07 | M10 Data updates | Manifest/signature/decision logic in metro_core; app updater (https-only transport with timeouts + resume, store with `current.json`, staging, atomic install, rollback, prune), bootstrap order override > updated > previous > bundled, bad-version marking, 24 h check after first frame. Disabled until the owner supplies host URL + public key. 34 app + 6 core + 1 pipeline cross tests. ADR-062. |
| 2026-10-07 | M11 Online AI | metro_core `ai` (gateway interface, grounding, post-check), app `ProxyAiGateway` + Ask-tab AI card (labelled, offline wording, opt-out provider), `server/ai-proxy` (validation, rate limit, provider abstraction, key from env). All against loopback fakes; no proxy deployed, no key. ADR-063. |

## M11 contents
- metro_core: `src/ai/ai_gateway.dart` (+ `test/ai_gateway_test.dart`). App: `shared/data/ai/proxy_ai_gateway.dart`, `features/assistant/application/{ai_providers,assistant_controller}.dart`, `_AiCard`; ARB +6; tests `online_ai_test` (screen), `online_ai_gateway_test` (loopback; separate file because widget tests install a fake HttpClient). Proxy: `server/ai-proxy/{lib,bin,test}` (12 tests); wired into `tools/check.dart` and the secrets scan.

## M10 contents
- metro_core: `src/update/update_manifest.dart` (+ `test/update_manifest_test.dart`). Pipeline: cross test in `signing_test.dart`. App: `shared/data/updater/*`, `bootstrap/update_providers.dart`, gate trigger; tests `test/updater/{update_rig,dataset_update_test}.dart` (loopback server: full flow, corrupt/bad checksum/bad signature/untrusted key/malformed/schema/invalid dataset/draft/interrupt+resume/offline/timeout/rollback/prune/hostile pointer), boundary additions. Not done: Settings notice (M12), metered/data-saver rule, ETag, real host + key (owner).

## M9 contents
- metro_core: `src/assistant/*`, `test/assistant_cases.yaml` (190), `test/assistant_cases_test.dart`, `test/assistant_test.dart`, `dart_test.yaml` (tag `assistant`). App: `features/assistant/*`, `MetroServices.assistant`, `/ask` route; ARB +62 keys; tests `assistant_test`, boundary addition.

## M8 contents
- metro_core: `src/journey/journey.dart` (+ `test/journey_test.dart`). App: `features/journey/{application,presentation}`, `shared/data/{journey_store,keep_awake}.dart`, route `/journey`, Start journey on results, Home banner; ARB +54 keys; tests `journey_test`, boundary additions.

## M7 contents
- metro_core: `src/map/map_geometry.dart` (+ `test/map_geometry_test.dart`). App: `features/map/{application,presentation}`, routes `/map?station=`, `/go/route/map`; ARB +26 keys; tests `map_test`, boundary additions.
- docs/device-check.md: the manual checklist for M5-M7.

## M6 contents
- metro_core: `src/geo/nearby.dart` (+ `test/nearby_test.dart`). App: `features/station/*`, `features/nearby/*`, `shared/location/*`; routes `/station/:id`, `/go/nearby`; manifest location permissions (requested only from Nearby).
- Tests: `station_detail_test`, `nearby_test`, boundary additions (location plugin confined to shared/location; Location/Nearby code cannot store or send).

## M5 contents
- `app/lib/bootstrap/*`, `app/lib/features/go/{application,presentation}/*`, `app/lib/shared/{format,widgets}/*`; router: `/go`, `/go/pick/:end`, `/go/route?from=&to=` (ids only).
- Tests (`app/test`): `bootstrap_test` (21), `bootstrap_gate_test` (failure states, loading/retry, end-to-end through a real SQLite file), `station_picker_test`, `route_results_test` (alternatives, change/walk cards, seam, fares, same/unreachable/unknown/not-served, Hindi/NULL names, flow), `boundary_test`, `app_shell_test`; invented network in `test/support/test_network.dart`.
- Running on the real draft: see offline.md "Implemented in M5" (dart-defines, debug only). The release build has no dataset and shows "No metro data installed" by design until a verified dataset is bundled/downloaded.

## M4 contents
- `packages/metro_core/lib/src/search/*`; tests `search_normalizer_test`, `search_test`, `search_cases.yaml`/`search_cases_test`, `search_perf_test`, support `test/support/search_net.dart` (invented names); pipeline `src/search_report.dart`, `search` CLI tests, `search` section in build-report.json, `tools/check.dart` guard (self-check problems must be 0).
- Real-data probe: 728/732 one-typo queries rank the right station first, 172/172 Hindi names exact, ~1.8 ms/query.
- Not in M4 (by design): recents/favourites/nearest (app, M5), assistant `resolve` (M9), gate landmarks (no gate data), search UI.

## M3 contents
- `packages/metro_core/lib/src/routing/{travel_time,itinerary,route_planner,last_train}.dart`, `src/fare/{fare_quote,fare_engine}.dart`, `src/util/min_heap.dart`. Tests: `routing_test` (53), `fare_test` (31), `last_train_test` (10) + synthetic-network builder `test/support/net_builder.dart`.
- Pipeline: `route <from> <to> [--json] [--minute m]`, `route --components`; `src/route_report.dart`; `routing` section in build-report.json; `tools/check.dart` real-data guards (no un-curated interchange candidates, one connected network).
- Pipeline provenance: `origin.detail` audit text for curated merges / name resolutions; resolved names credit the real source (Wikidata); curated interchanges have `verified` transfer rows with NULL walk data.
- Data: `data/curated/overlays.yaml` now holds the curation with cited evidence. Dataset diff M2 -> M3: -47 per-line stations, +21 merged interchange stations, Rohini West renamed (Dr. Baba Saheb Ambedkar Hospital; old name kept as alias).
- Live state: draft; 245 stations, 25 interchanges, 1 connected network; 27 conflicts left, 13 resolved by curation, 14 open warnings (9 Hindi + 3 English name mismatches, 1 duplicate station code BIMR); 0 blocking. All 524 edges lack travel_s and all 54 interchange rows lack walk times, so every route time is an estimate; no fare data exists (quotes say "unavailable").
- Real known journeys table (`known_journeys.yaml`, >= 50 verified pairs) does not exist yet: owner track. Only fixture + property tests assert routes.

## M2 contents
- `tools/data_pipeline/lib/src/`: config, fetch, lock (+RawCache), normalize, overlay, conflict, merge, pipeline, diff, signing, util; CLI in `lib/data_pipeline.dart` (`fetch build validate diff sign verify keygen inspect`).
- Config/data: `data/sources/sources.yaml` + `queries/`, `data/curated/overlays.yaml` (empty by design), `data/cache/sources.lock.json` (commit; raw cache files are gitignored - archive them with a release).
- Outputs (gitignored): `build/pipeline/metro.sqlite`, `build-report.json` (inputs+hashes, conflicts, overrides, validation).
- metro_core: nullable fields, `origin` table, draft/release validation (ADR-027).
- Live state: draft; 0 cross-line merges; 83 stations lack Hindi names; 46 conflicts (27 interchange candidates, 9 Hindi + 7 English name mismatches, 1 coordinate, 1 revisiting route, 1 duplicate station code), 0 blocking.

## M1 contents
- `packages/metro_core/lib/src/{model,dataset,validation,authoring}/`; tests in `packages/metro_core/test/` (`validation_test` = one test per rule, `dataset_roundtrip_test` = write/read/corruption, `yaml_loader_test`).
- `tools/data_pipeline/lib/data_pipeline.dart`: `build`, `validate` (others print "not implemented"); `build` refuses `is_test_data` without `--allow-test-data`.
- `tools/check.dart` now also validates and builds the fixture.
- Schema doc: data-model.md "Implemented in M1". Not in schema yet: parking, headway, map_*, geo_line_path.
- **drift/user DB deferred to M5** (ADR-022) - no Flutter/drift code was added in M1.

## M0 contents (for orientation)
- `pubspec.yaml` workspace · `analysis_options.yaml` (very_good_analysis, style rules relaxed) · `.gitignore`
- `app/` package `metromitra`, appId `in.metromitra.app`, minSdk 24, Android only.
  `lib/main.dart`, `lib/app/{app,router}.dart`, `lib/app/theme/{tokens,app_theme}.dart`,
  `lib/app/l10n/app_{en,hi}.arb`, `lib/shared/widgets/{state_view,placeholder_screen}.dart`,
  empty `features/*/{application,presentation}` and `shared/data` folders, `assets/{brand,fonts,data}`.
- `packages/metro_core/` — `metro_core.dart` + `src/core_info.dart` (schema-version placeholder) + boundary test.
- `tools/data_pipeline/` — CLI stub (`bin/build.dart`, prints planned commands) + test.
- `tools/check.dart`, `tools/check_secrets.dart`, `tools/brand/make_icons.py`.
- `data/{curated,cache,fixtures}/` empty (`.gitkeep`). No metro data anywhere.

## Not done in M0 (by design)
- `bootstrap.dart`, Riverpod providers for snapshot/clock, drift user DB — M5. App does not use the dataset yet.
- `integration_test/` folder is empty; first integration test is M5.
- Release signing config still the Flutter debug placeholder (needs keystore before Play upload).
- Repo is not a git repository yet (owner decision; run `git init` when ready).
- very_good_analysis 11.0 available; staying on 10.x until a deliberate upgrade.

## Blockers / owner actions
- **Curate more** in `data/curated/overlays.yaml`: Hindi names (73 stations), the 9 Hindi + 3 English name mismatches, duplicate code BIMR. (Interchanges and Rohini West are done in M3; re-verify them against an official source before release.)
- **Approve routing parameters** (`TravelTimeModel` fallback-v1: 35 km/h, 25 s dwell, 180 s wait, 240 s / 200 m interchange) or supply real travel times / headways / walk times; supply a licensed or owner-verified fare table.
- Decide OPEN-2 (publish dataset under ODbL?) and send the OTD/DMRC permission request before any release.
- Set `METROMITRA_CONTACT` (URL/email you choose) for polite Overpass/Wikidata User-Agent; generate a signing key with `keygen` (store only in CI secrets).
- **Logo trademark risk** (decisions.md "Logo risk"): nose roundel ≈ DMRC logo; ring+bar ≈ London Underground roundel. Used as-is for now per owner instruction; resolve before store listing.
- Request written permission for OTD DMRC GTFS + DMRC station data (metro-data-sources.md).
- Start curation of top-100 stations; start `known_journeys.yaml`.
- Trademark/Play check for "MetroMitra" (OPEN-4).
- Hindi strings (incl. app name "मेट्रोमित्र") are first drafts; native review in M13.

## Session log (newest first, ≤ 5 lines each)
- 2026-10-16: Admin panel (ADR-065, docs/admin.md): Supabase schema + RLS + audit (`supabase/migrations/0001_admin.sql`, NOT yet run: needs the owner), Next.js admin (`admin/`: login, per-table editors with provenance/approval, UI settings, text overrides, export, audit, admins; 14 tests, builds), app remote settings (`features/remote_config`: banner, feature switches, brand colour, 2 texts; 36 tests). Live project checked with the publishable key: reachable, email sign-up enabled, tables absent (404) -> app falls back to defaults. Pipeline does not yet read gates/platforms/facilities/fares/timings.
- 2026-10-12: Overview map (live poster of the whole network, fits the screen) + tests; app tests 324 pass. Emulator: first install on a fresh emulator boot was damaged ("base.apk is not zip", SIGSEGV in the engine) - a clean uninstall/install fixed it, not an app bug. Found the owner's DMRC PDF viewer (pdfrx + asset): renders after ~1 min; licensing blocker logged.
- 2026-10-12: Map functions + official reference check (ADR-064). Counts match DMRC on 9/10 lines (Pink 46 vs 45: one under-construction station not identifiable, documented); New Delhi Yellow/Airport interchange was missing (routing detoured) - fixed by a cited curated merge; Dhaula Kuan walkway interchange not modelled (no walk time); distances 80-96 % of official (straight line) - labelled estimates. Added bilingual map labels, map station search, live tracking (watch stream, stops off-tab), route distance. Tests: map_live_test (16), reference_check_test (3), projection tests, route distance test. Emulator (profile, real draft, mock GPS): map search frames+rings the station, live tracking dot + nearest station updates as the mock GPS moves, denied permission shows a clear panel and the map keeps working. Full gate: app 320 pass; core 650/652 (two `search_perf_test` timing tests, load-sensitive, unchanged); pipeline + reference check pass.
- 2026-10-07: Device/emulator pass (Motorola phone + AVD, profile build, real draft). Phone showed "No metro data" only because Git Bash rewrote the `--dart-define` path (use `MSYS_NO_PATHCONV=1`). Emulator: Home, picker, route, route map, Ask (route answer + source), Nearby rationale all fine. Fixed the M7 issue: station markers now scale with on-screen density (dots for plain stations, small rings for interchanges at whole-network zoom; regression test). Not yet checked on device: Journey, Station detail, Hindi, dark mode.
- 2026-10-07: M11 done. Offline assistant returns `unknown` only when no intent word matches (a question naming a station becomes route/notFound/clarify), so AI triggers rarely by design; revisit with real usage. Not deployed: no proxy host, no model key (owner). Settings toggle + persisted token wait for M12.
- 2026-10-07: M10 done. Updater tested against a loopback HTTP server with a throwaway test key; nothing real published, no key or host embedded (updates are off until the owner supplies them). Test-pitfalls: Dart string escapes via python heredocs; `HttpResponse.detachSocket` after headers throws, so the cut-connection server writes the raw HTTP response itself. Name clash `sha256Hex` (pipeline vs core) -> core's is `contentSha256Hex`.
- 2026-10-07: M9 done. Emulator (profile, real draft): Ask tab, Hinglish route answer with source, "sector 18" -> chips (no guess), facility "missing" wording, Open route/station. Fixed on device: chip answer not scrolled into view; "no record of Toilet" casing (acronyms kept). Corpus found + fixed M8 `platformFor` direction bug. search_perf_test (unchanged 4 ms): passed in the first M9 check.dart (p50 3.77 ms), then 4.2-4.4 ms on a loaded machine (search code untouched since M4, also fails alone and without dart_test.yaml). New: Station detail last row under the gesture bar (no bottom safe-area padding). Not validated: Hindi typing on device (adb cannot type Devanagari).
- 2026-10-07: M8 done + first emulator run (Android 16 x86_64, AVD `metromitra_test`, profile build, real draft via dart-defines): Home, picker (EN+HI), results, journey (all step kinds seen, kill+resume, GPS snap, keep-awake on/off, End dialog) and Map render correctly. Fixed on device: location went through Play services (extra dialog, failed on "No thanks") -> platform LocationManager; plugin time limit did not fire (40 s hang) -> Dart timeout + regression test; no feedback while locating; "Platform unavailable" too loud; doubled "you should be there". One ANR seen while the emulator was overloaded (load 30, system_server restarted); not reproduced afterwards. Open (M7): at whole-network zoom station rings hide line colours. Not run: Nearby, Station detail, dark theme, real phone.
- 2026-10-06: M7 done. search_perf_test failed on a loaded machine (p50 4.4-6.3 ms vs the unchanged 4 ms limit, two full runs) and passed on a quieter one (p50 2.3-2.4 ms, full `check.dart` green); search code and threshold untouched, the test is load-sensitive. Test-pitfall: flutter_test `paints` matcher stops at the first draw call of a type that does not match, so map tests record a TestRecordingCanvas instead.
- 2026-10-06: M6 done. Android build needed `kotlin.incremental=false` (pub cache on C:, project on D:). search_perf_test (p50 < 4 ms) fails on this busy machine (4.4 ms; ADR-045 measured ~1.8 ms); search code untouched. No device/emulator run of the location prompt yet (tests use a fake LocationSource); first real check pending.
- 2026-10-06: M5 done. Found by tests: ListTile with 3 lines overflowed (replaced by a plain card), 'Station not found' shown twice (header + message, test fixed). Android debug APK build checked (sqlite3 hook) - see report. Dataset still draft.
- 2026-10-06: M4 done. Search worked on real data first run; bugs caught by tests: degenerate phonetic key ('zzzzzzzzzz' matched 5 stations -> skeleton must be >= 3 chars), typo in the first word of a longer name not matched (penalty was gating), 'ow' vs 'w' rule order, queries 2x slower than needed (join()/runes per entry -> precomputed). Dataset still draft.
- 2026-10-06: M3 done. Reference-checked 25 interchanges + Rohini West (rename, link was right) + Pink Line seam (branch has separate services, so a through ride was too optimistic: fixed to force a change). Test caught a board-then-alight walk-link loophole (fixed with fresh/rode node states). check.dart green: app 4, core 222, pipeline 215. Draft only; nothing signed/published.
- 2026-10-05: M2 done. Live fetch OK on 3rd attempt of exploration (Overpass 504 busy twice; exact-match query works). Bugs found by real data/tests: Content-Length vs gzip, copyWith dropped origins, diff swallowed corrupt files. Exploratory curl calls earlier in the session put the owner's email in the User-Agent (my mistake); pipeline never does.
- 2026-10-05: M1 done. Format/analyze clean; tests app 4, core 114, pipeline 12; fixture validates (15 warnings, 0 errors) and builds to sqlite; secrets + purity ok. No real metro data added.
- 2026-10-05: M0 scaffolded. Checks: format, analyze (3 pkgs), tests (app 4, core 1, pipeline 2), secrets, core purity all green. Logo wired into launcher + splash.
- 2026-10-05: Blueprint written. Researched OSM (ODbL), Wikidata (CC0), OTD T&C (modification clause), DMRC fare rules (2025-08-25 revision, smart card 10 % + off-peak 10 %).

## 2026-10-16 - admin panel connected end to end
- Supabase set up with `supabase/setup_all.sql` (one paste, safe to re-run). Public key can read `ui_config`/`ui_strings`
  only; anonymous writes are refused by row-level security (checked against the live project).
- Data pipeline reads approved admin rows: `data/curated/admin-approved.json` (written by `npm run export`, or
  `build --admin-export <file>`). Station names, Hindi names, aliases and coordinates are applied after `overlays.yaml`;
  gates/platforms/facilities/fares/timings are reported as `not_imported_yet` (ADR-029). Tests: `admin_import_test` (5).
- Emulator (fresh wipe; the old image had a corrupt system permissions file): profile build with Supabase on fetched
  and cached the live settings; Go and Map screens OK, all map buttons shown as the flags say.
- Owner still to do: turn off e-mail sign-up; try an edit (banner) and restart the app to see it.
