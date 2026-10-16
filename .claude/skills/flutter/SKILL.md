---
name: flutter
description: Conventions for writing MetroMitra Flutter/Dart code — workspace layout, layers, Riverpod 3 without codegen, go_router, drift, dependency rules, verify command. Use when adding or changing any Dart code in app/ or packages/.
---

# Flutter conventions (MetroMitra)

Spec: docs/architecture.md. Read it once per milestone, not per file.

## Placement
- Domain logic (routing, fare, search, assistant, validation, geo) → `packages/metro_core` (pure Dart: no `package:flutter`, no plugins, no HTTP).
- Platform/data adapters (files, drift user DB, location, HTTP, ads, billing) → `app/lib/shared/data`.
- Screen state → `app/lib/features/<feature>/application` (Notifier/AsyncNotifier).
- Widgets → `features/<feature>/presentation`; reusable components → `shared/widgets`.

## Rules
- Riverpod 3, no codegen. Providers that need runtime objects (snapshot, user DB) throw until overridden in `app/bootstrap.dart`.
- Inject `Clock`, `LocationSource`, `AiGateway`, `http.Client` via providers — never call `DateTime.now()` or plugins directly in logic.
- Money = int paise; distances = int metres; times = int minutes/seconds. No `double` money.
- No metro literals (station names, line colours, fares) in code — read from `MetroSnapshot`.
- Strings via ARB (`app/lib/app/l10n/app_en.arb`, `app_hi.arb`); add both languages together.
- Immutable models (`final` fields, `const` constructors, `==`/`hashCode` via records or manual).
- Add an interface only when there are ≥ 2 implementations or a test double is required.
- New dependency → ADR row in docs/decisions.md.
- Heavy work (dataset load, graph build) in `Isolate.run`.

## Verify before finishing
```sh
dart run tools/check.dart   # format, analyze, tests, secrets scan
```
Then update docs/progress.md.
