# Offline architecture

## Principle
Offline is the default path. The network is an *enhancement* that can only add newer
data, AI answers or ads — it is never on the critical path of any core feature.

| Works with zero network | Needs network |
|---|---|
| Search, routes (all profiles), fares, map, station info, gates, platforms, first/last train, journey mode, nearby (GPS works offline), offline assistant, recents/favourites | Dataset updates · online AI answers · ads · purchases (Play) · feedback email · external maps directions |

## Storage
| Item | Location | Notes |
|---|---|---|
| Bundled dataset | `assets/data/metro.sqlite` + manifest | Always valid; last-resort fallback |
| Active dataset | `<appSupport>/datasets/<version>/metro.sqlite` | Copied from assets on first run or when bundled is newer |
| Previous dataset | `<appSupport>/datasets/<prev>/` | Kept for rollback; older ones deleted |
| Pointer | `<appSupport>/datasets/current.json` | Written atomically (write temp → rename) |
| User DB | `<appSupport>/user.sqlite` (drift) | Migrations versioned and tested |
| Fonts/icons | bundled | No runtime font downloads (`google_fonts` not used) |

## Startup sequence (bootstrap.dart)
1. Native splash shows.
2. Read `current.json` → choose dataset; if missing/invalid → bundled.
3. Open read-only sqlite in a background isolate → check `schema_version` within app range →
   `PRAGMA quick_check` → load `MetroSnapshot` + build graph/search/map structures.
4. On any failure: log (non-PII), mark that version bad, fall back to previous → bundled.
5. Open user DB (run migrations). Provide both via ProviderScope overrides. First frame.
Budget: steps 2–5 ≤ 600 ms on mid-range device.

## Connectivity handling
- No connectivity plugin polling. Online features just attempt requests with short timeouts
  (5 s connect) and map failures to an `Offline` state.
- The assistant decides offline/online per question, not globally.
- Updater runs only when app is foreground, ≤ once per 24 h, and never during an active journey.

## Failure matrix
| Failure | Behaviour |
|---|---|
| Downloaded dataset corrupt / bad signature / bad hash | Discard, keep current, retry next day |
| Dataset needs newer app (`min_app_version`) | Skip, show "Update app for latest stations" in Settings |
| Dataset loads but validation fails on device | Mark bad, rollback |
| User DB migration fails | Back up file, recreate empty DB, inform user that recents were reset |
| Location unavailable | Nearby falls back to picker; From field not auto-filled |
| Ads SDK fails | Slot collapses (reserved height released), no retry loop |

## Implemented in M5 (ADR-046..048)
`app/lib/bootstrap/`: `dataset_bootstrap.dart` (candidates, policy, loader, results), `bootstrap_providers.dart`
(Riverpod wiring, developer override, bundled-asset candidate), `bootstrap_gate.dart` (loading/failure UI),
`metro_services.dart` (snapshot + search + fares + planner). Not yet: `current.json` pointer, previous-version
rollback and the user DB (M10 / a later milestone). Run the app on a built draft:
`flutter run --dart-define=METROMITRA_DATASET=<path to metro.sqlite> --dart-define=METROMITRA_ALLOW_DRAFT=true`
(debug builds only; the path must be readable by the app, e.g. pushed to app storage on Android).

## Implemented in M7
The map needs no network at all: it is drawn from the loaded snapshot (no tiles, no map plugin; a test opens an `HttpOverrides` guard that fails on any connection).

## Implemented in M10
`current.json` pointer, previous-version rollback and bundled fallback are in (`DatasetStore`, bootstrap candidates: dev override -> `updated <v>` -> `previous <v>` -> bundled). See sync.md "Implemented in M10". A failed, corrupted, unsigned, incompatible or invalid update never changes what loads.
