# MetroMitra

Offline-first Delhi Metro navigation app. Promise: **"Delhi Metro without confusion."**
Usability over feature count. Android / Play Store first.

## Working method
1. Read this file, then `docs/progress.md` (current milestone + next step).
2. Read ONLY the docs listed for that milestone in `docs/implementation-plan.md`.
3. Inspect relevant code → implement ONE milestone → test → update `docs/progress.md` → STOP.
4. Never start a future milestone early. Never regenerate completed work.
5. Record new architectural decisions in `docs/decisions.md` (ADR format).

## Layout
`app/` Flutter app (feature-first) · `packages/metro_core/` pure Dart domain
(models, routing, fare, search, assistant) · `tools/data_pipeline/` Dart CLI that
builds the signed dataset · `data/` curated sources + test fixtures · `docs/`.
Details: [docs/architecture.md](docs/architecture.md).

## Critical rules
- **No metro business data in code or UI** (stations, lines, colours, fares, gates,
  timings). Everything comes from the dataset (`metro.sqlite`). Test fixtures live in `data/fixtures/`.
- **Never fabricate metro info.** Assistant answers are built only from dataset facts;
  unknown → say so. Unverified/derived values are labelled (`confidence`).
- `metro_core` is pure Dart: no Flutter, no network, no platform plugins.
- Core features work with zero internet. Network is only for data updates, optional AI, ads.
- No API keys/secrets in the app. Online AI goes through our proxy (docs/security.md).
- Ads never appear in station picker, route results, journey mode or assistant answers.
- Essential navigation is never paywalled.
- Strings in ARB (en, hi). Line colours come from data; app colours from theme tokens.
- Location is optional; every location feature has a no-permission path.

## Stack
Flutter 3.44 / Dart 3.12 · pub workspace · Riverpod 3 (no codegen) · go_router ·
drift (user DB) + sqlite3 (read-only dataset) · very_good_analysis.

## Commands (repo root)
```sh
flutter pub get
dart run tools/data_pipeline/bin/build.dart --offline   # rebuild dataset from cache
dart run tools/check.dart                                # format, analyze, test (all packages)
cd app && flutter build apk --release
```

## Docs index
product · requirements · ux · design-system · screens · architecture · data-model ·
metro-data-sources · routing · search · map · offline · ai · sync · security ·
testing · implementation-plan · decisions · progress  → all in `docs/`.
Skills in `.claude/skills/` (flutter, metro-data, routing, ai, ui, qa).
