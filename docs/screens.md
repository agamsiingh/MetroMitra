# Screens (V1)

Format: purpose · primary action · content · states. Wireframes are indicative.

## S1 Home (tab "Go")
Primary: **Where do you want to go?**
```
MetroMitra                         ⚙
┌───────────────────────────────┐
│ 🔍 Where do you want to go?   │  ← 64dp, opens S2 (To)
└───────────────────────────────┘
[◎ Nearby stations]  [🗺 Metro map]   ← two tonal buttons
Recent journeys
  Adarsh Nagar → Anand Vihar ISBT    ›   (example; real data from user DB)
  ...
(native ad slot — below recents, non-premium only)
```
States: no recents → hint text; location unavailable → Nearby button still opens S6 with fallback.

## S2 Station picker (full screen)
Primary: pick a station. Search field autofocus; before typing: "Use my location"
(nearest station), Recents, Favourites. Results: name (UI lang) + other-script subtitle + line chips.
States: no match → "No station called '<q>'" + suggestions from fuzzy tier.

## S3 Route results
Primary: **Start journey**.
Top: From/To pair with swap. Profile chips: Fastest · Easiest · Less walking (only distinct ones).
Summary: `48 min · 1 change · 22 stops · ₹43 token / ₹39 card`.
First instruction card: "Board <Line> towards <terminal> · Platform <n>".
Timeline: segments by line, collapsed stops, interchange cards (walk m/min, platform, direction).
Footer: last-train info, fare breakdown (tap), Share, Show on map.
States: same station → inline message; unreachable (data gap) → explain + report; last train missed → warning banner.

## S4 Journey mode
Primary: context-dependent single action ("I'm on the train" / "I've changed" / "Done").
Current step huge; remaining stops counter; next step preview; best exit at end with landmarks.
Keep-awake on; no ads; back asks "End journey?".

## S5 Station detail
Primary: **Route from here / to here** (split button).
Sections: Lines & platforms → Gates & exits (landmarks, lift/ramp icons) → Accessibility →
Facilities → Parking (capacity, tariff) → First/last train per direction. Provenance footer per section.
Secondary: Directions (external maps intent), Show on map.

## S6 Nearby
Primary: tap a station. List: name, lines, distance, walk min. Toggle list/geo mini-map.
States: permission rationale → request; denied → "Pick a station"; GPS off → enable prompt; timeout 10 s → last known + "approximate".

## S7 Map (tab)
Primary: tap a station. Vector map; search-to-locate field; zoom buttons (a11y);
route highlight when opened from S3; attribution button.

## S8 Assistant (tab "Ask")
Primary: ask. Suggestion chips (localized): "How do I reach…", "Fare to…", "Last metro from…".
Answer cards with actions + "Source: dataset v2026.10.1 · verified <date>".
Offline unsupported → "Connect to internet for an AI answer." Online AI answers carry "AI · may be inaccurate".

## S9 Settings
Language · Theme · Keep screen awake · Location · Premium (buy/restore) · Ads privacy (UMP) ·
Data & licences (dataset version, sources, ODbL notice, OSS licences) · Feedback · Privacy policy · About.

## System
Native splash only (no branded "presents" screen). No onboarding carousel; permissions asked in context.

## Implemented in M5 (S1-S3)
- **S1 Home:** From and To fields (name in the UI language, other script as subtitle if present, line chips), swap,
  "Find route" (disabled until two different stations are chosen; same station shows an inline message). No Nearby /
  Map buttons yet (M6/M7) and no recents (needs the user DB). A draft/test-data banner is always visible.
- **S2 Picker:** autofocus field, blank / no-result / did-you-mean states, rows as in ADR-049. Opens full screen above the tab bar.
- **S3 Results:** as ADR-050. Not yet: "Start journey" (M8), first-instruction/platform card (no platform data), last-train
  banner (no timing data; the check exists in metro_core), Share, Show on map.

## Implemented in M6 (S5-S6)
- **S5 Station detail** (`/station/:id`): names, status, interchange, Route from/to here, lines with codes, services,
  aliases, location, Platforms / Gates / Facilities / Accessibility (records or "Not in the data yet."), provenance
  footer. Not yet: first/last train, parking, directions intent, Show on map.
- **S6 Nearby** (`/go/nearby`, Home button): rationale -> request -> list (name, lines, straight-line distance) with
  denied / unavailable / services-off / invalid / none-nearby states. No list/map toggle (map is M7), no walk minutes.

## Implemented in M7 (S7 + route map)
- **S7 Map tab** (`/map`, `/map?station=<id>`): whole network or one station; From/To rings; zoom +/-/fit buttons; note for
  stations without coordinates; dataset attribution. **Route map** (`/go/route/map?from=&to=&opt=`): duration with the
  M5 "About N min" notice, line chips, highlighted route, legend for changes and walks.
- Not yet: search-to-locate field on the map, label levels, Start journey from the map.

## Implemented in M8 (S4 Journey mode)
- **S3:** filled "Start journey" (primary); "Show on map" stays secondary.
- **S4** (`/journey`): step count, big current step (enter / board + platform / ride with stops left and "Now around X
  (estimated)" / change with walk / stay on board / walk / exit with gates), one primary action ("I'm inside the
  station", "I'm on the train", "I've got off", "I've changed", "I've arrived", "Done"), "I'm at…" sheet, "Use my
  location" (one fix, snapped within 250 m), next-step preview, approximate-times note, keep-screen-on switch, back/close
  -> "End journey?". Home shows "Journey in progress · Continue / End" and explains a journey that could not be restored.
- Not in M8: best exit for a destination landmark (no landmark input yet), background/notification progress (V2).

## Implemented in M9 (S8 Ask, offline)
Ask tab: intro, suggestion chips (route / fare / last metro insert a question start; nearest sends), question bubbles,
answer cards (headline + detail lines, source line "Source: metro data <version> · <confidence>", actions: Open route /
Open station / Nearby stations / Choose station), clarify chips on the latest answer only, 500-char input cap. No ads.
