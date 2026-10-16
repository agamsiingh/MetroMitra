# Requirements

IDs are referenced by tests (`// covers: FR-ROUTE-2`) and milestones.

## Functional

### Search (FR-SEARCH)
1. Find a station by English or Hindi name, alias, partial name or common misspelling.
2. Ranking: exact > prefix > alias > fuzzy > popularity tiebreak (docs/search.md).
3. Results show line chips; recents shown before typing; "Use my location" row when allowed.

### Route (FR-ROUTE)
1. From/To with swap; compute automatically once both are set.
2. Profiles: **Fastest**, **Easiest** (fewest changes), **Less walking**; fewest-stops available to assistant/internal.
3. Each result: total time, changes, stops, fare (token + smart card + off-peak), first boarding platform + direction ("towards <terminal>").
4. Interchange steps: station, walk distance/time, target line, platform, direction.
5. Show alternatives only when they differ; else state "best for all preferences".
6. Last-train warning when the trip can't be completed before the last train (current time or chosen departure).
7. Out-of-system walking links (exit and re-enter) are flagged with separate fares.
8. Share route as plain text.
9. Save to recents automatically.

### Journey mode (FR-JOURNEY)
1. Steps: walk to station → entry gate → platform & direction → ride (remaining stops) → interchange → ride → best exit gate.
2. Progress via time estimate; user can tap "I'm at <station>" to correct; GPS used opportunistically when permitted.
3. Screen stays awake (toggle); large text; works offline.
4. "Get off at next stop" alert (in-app, vibration) — V1 in-foreground only.
5. Best destination exit chosen from gate landmarks if destination landmark given, else default exit.

### Station (FR-STATION)
1. Lines, platforms (platform → direction), gates with landmarks, facilities, accessibility (lifts per gate, ramps, step-free), parking (capacity + tariff), first/last train per direction.
2. Actions: Route from / Route to here, Directions (hands off to external maps app), Show on map.
3. Every section shows "Last verified <date>" or "Unverified" from data provenance.

### Nearby (FR-NEARBY)
1. Nearest N stations by straight-line distance with walk-time estimate and lines.
2. Geographic mini-map of nearby stations (no basemap tiles in V1).
3. No-permission path: explain value, offer "Pick a station instead".

### Map (FR-MAP)
1. Offline vector network map; pan/zoom; tap station → station sheet.
2. Highlight a computed route (others dimmed).
3. Search-to-locate on map.
4. Attribution visible (ODbL / sources).

### Assistant (FR-ASSIST)
1. Offline intents: route, nearest station, gate/exit, platform, fare, first/last train, interchange, facilities, accessibility, parking, line info.
2. English, Hindi and Hinglish input.
3. Answers built only from dataset facts; each answer exposes its sources.
4. Unknown/unsupported → capability hint; if online AI enabled + network → offer AI answer, labelled.
5. Offline + unsupported → "Connect to internet for an AI answer."

### Data (FR-DATA)
1. Bundled dataset works on first launch offline.
2. Background-safe update check (≤ 1/day, foreground), signed + hashed, atomic swap, rollback.
3. About → Data shows dataset version, date, sources & licences.

### Settings (FR-SET)
Language (en/hi/system), theme (system/light/dark), keep-awake default, location usage,
ads consent (UMP), premium purchase/restore, licences, feedback (mailto), privacy policy.

## Non-functional (NFR)
| ID | Requirement |
|---|---|
| NFR-PERF-1 | Cold start to interactive Home ≤ 1.5 s on a mid-range device (e.g. 4 GB RAM, 2021 SoC) |
| NFR-PERF-2 | Route computation (all profiles) ≤ 50 ms; search per keystroke ≤ 16 ms |
| NFR-PERF-3 | Map pans/zooms at 60 fps on mid-range |
| NFR-SIZE-1 | Release APK/AAB download ≤ 25 MB (dataset ≤ 3 MB compressed) |
| NFR-OFF-1 | All core features (product.md V1, except updates/AI/ads) with zero network |
| NFR-A11Y-1 | TalkBack labels on all interactive elements; touch targets ≥ 48 dp (primary ≥ 56 dp) |
| NFR-A11Y-2 | Usable at 200 % font scale; WCAG AA contrast; line colour never the only signal |
| NFR-I18N-1 | English + Hindi UI; station names in both scripts |
| NFR-PRIV-1 | No account; location never leaves device (except explicit AI question, see ai.md) |
| NFR-SEC-1 | No secrets in the app binary; datasets signature-verified |
| NFR-REL-1 | Corrupt/incompatible dataset never crashes the app (fallback to bundled) |
| NFR-COMPAT-1 | Android 7.0+ (API 24) — confirm against Flutter 3.44 minimum |
