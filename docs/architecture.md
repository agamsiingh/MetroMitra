# Flutter architecture

## Shape
Pub workspace with three packages. Small on purpose: one app, one pure-Dart core,
one CLI. The core is shared by the app and the data pipeline, so the validation,
routing and fare rules that check the dataset at build time are the same ones that
run on the device.

```
MetroMitra/
├─ CLAUDE.md
├─ pubspec.yaml                  # workspace root (app, packages/metro_core, tools/data_pipeline)
├─ analysis_options.yaml         # very_good_analysis
├─ app/                          # Flutter app (package: metromitra)
│  ├─ lib/
│  │  ├─ main.dart
│  │  ├─ app/                    # composition root
│  │  │  ├─ bootstrap.dart       # open dataset + user DB, ProviderScope overrides
│  │  │  ├─ router.dart          # go_router, StatefulShellRoute (Go · Map · Ask)
│  │  │  ├─ theme/               # tokens, ColorScheme, text theme
│  │  │  └─ l10n/                # ARB en/hi + generated
│  │  ├─ features/
│  │  │  ├─ home/      {application/, presentation/}
│  │  │  ├─ search/    {application/, presentation/}   # station picker
│  │  │  ├─ route/     {application/, presentation/}
│  │  │  ├─ journey/   {application/, presentation/}
│  │  │  ├─ station/   {application/, presentation/}
│  │  │  ├─ nearby/    {application/, presentation/}
│  │  │  ├─ map/       {application/, presentation/}   # CustomPainter renderer
│  │  │  ├─ assistant/ {application/, presentation/}
│  │  │  └─ settings/  {application/, presentation/}   # premium, about, licences
│  │  └─ shared/
│  │     ├─ data/        # dataset_store (file mgmt), user_db (drift), location, updater, ai_client
│  │     ├─ providers.dart  # metroSnapshotProvider, routerServiceProvider, ...
│  │     └─ widgets/     # design-system components
│  ├─ assets/data/metro.sqlite (+ metro.manifest.json)   # bundled dataset (generated)
│  ├─ assets/fonts/
│  ├─ test/  integration_test/
├─ packages/metro_core/          # PURE DART
│  └─ lib/src/
│     ├─ model/          # Station, Line, LineService, Gate, Fare..., immutable
│     ├─ dataset/        # MetroSnapshot + SQLite reader (package:sqlite3) + schema version
│     ├─ validation/     # dataset invariants (used by pipeline AND app after download)
│     ├─ graph/          # graph build from snapshot
│     ├─ routing/        # Dijkstra, profiles, itinerary builder, last-train check
│     ├─ fare/           # fare systems, slabs, discounts, overrides
│     ├─ search/         # normalizer, transliteration, ranker
│     ├─ geo/            # haversine, nearest stations
│     ├─ map/            # map geometry model + hit-test grid (no rendering)
│     ├─ assistant/      # intents, slot extraction, handlers, Answer/Fact model
│     └─ ai/             # AiGateway interface + request/response models (no HTTP)
├─ tools/
│  ├─ data_pipeline/     # Dart CLI: fetch → merge → validate → build sqlite → sign → diff
│  └─ check.dart         # format + analyze + test + check_secrets (adapted from Briskit)
├─ data/
│  ├─ curated/           # hand-maintained YAML overlays (source of truth for non-OSM facts)
│  ├─ cache/             # raw downloads with hashes (gitignored except lock file)
│  └─ fixtures/          # tiny synthetic networks for tests
└─ docs/  .claude/skills/
```

## Layers (clean architecture, kept thin)
| Layer | Where | Depends on |
|---|---|---|
| Domain (entities + services: routing, fare, search, assistant) | `metro_core` | nothing (pure Dart, `sqlite3` only in `dataset/`) |
| Data (dataset files, user DB, location, HTTP, ads, billing) | `app/lib/shared/data` | domain |
| Application (Riverpod Notifiers/providers per feature) | `features/*/application` | domain, data via providers |
| Presentation (widgets) | `features/*/presentation`, `shared/widgets` | application |

Rules: widgets never touch data classes directly; no repository interfaces "just in
case" — introduce an interface only where there are ≥ 2 implementations or a test
double is needed (dataset store, location, AI gateway, clock).

## Key runtime objects
- `MetroSnapshot` — immutable in-memory copy of the dataset (~300 stations; < 5 MB RAM),
  loaded once in a background isolate at startup. Holds pre-built `MetroGraph`,
  `SearchIndex`, `FareEngine`, `MapGeometry`.
- `metroSnapshotProvider` (AsyncNotifier) — swapped atomically after a data update.
- `Clock` provider — all time logic (last train, off-peak fare) goes through it for tests.

## State management
Riverpod 3 without codegen. `Notifier`/`AsyncNotifier` per screen controller;
derived values as plain `Provider`s (e.g. `routeOptionsProvider(from,to)` family).
No global mutable singletons.

## Navigation
go_router with `StatefulShellRoute.indexedStack` for Go/Map/Ask. Deep links:
`/route?from=<id>&to=<id>`, `/station/<id>` (used by share and assistant actions).

## Packages (minimal)
flutter_riverpod · go_router · sqlite3 + sqlite3_flutter_libs · drift · geolocator ·
url_launcher · wakelock_plus · http · cryptography (Ed25519) · in_app_review ·
google_mobile_ads + in_app_purchase (M11 only) · flutter_localizations/intl.
Any new dependency → ADR in decisions.md.

## Reuse from sibling repos
Adapt `D:\Briskit\scripts\check_secrets.dart` and the very_good_analysis config
(`analysis_options.yaml` with style-only rules relaxed). Do not import Briskit packages.
