---
name: qa
description: Verifying a MetroMitra milestone before reporting it done — required test suites, offline and anti-fabrication checks, release checklist. Use at the end of every milestone and before any release.
---

# QA

Spec: docs/testing.md.

## End of every milestone
1. `dart run tools/check.dart` green (format, analyze, tests, secrets).
2. New logic has tests that reference requirement IDs (`// covers: FR-...`).
3. If data/routing/fare changed: known-journeys regression green.
4. If assistant changed: assistant corpus + anti-fabrication suite green.
5. If startup/data loading changed: offline integration test + corrupt-dataset tests green.
6. `cd app && flutter build apk --release` succeeds; note APK size vs NFR-SIZE-1.
7. Update docs/progress.md (Done row + next step). Report: what was built, tests, builds, remaining, next milestone. Stop.

## Release checklist (manual, device)
- Airplane mode: search, route, map, station, journey, assistant all work.
- TalkBack pass on Home → Route → Journey. 200 % font. Dark mode. Hindi UI.
- Low-end device: cold start ≤ 1.5 s, map 60 fps.
- Location: deny, approximate, precise, GPS off.
- No ads on forbidden screens; premium hides all ads; restore works.
- Data update: install older dataset, update, rollback on corrupted file.
- Data safety form and privacy policy match actual behaviour.
