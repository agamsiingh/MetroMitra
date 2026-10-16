# UX architecture

## Information architecture
```
Home (Go) ───────────────┬─ Station picker (full screen) ─→ Route results ─→ Journey mode
  │  "Where do you want   │                                    │
  │   to go?"             │                                    └─ Station detail (sheet/page)
  │  Recents / Nearby     ├─ Nearby ─→ Station detail
  │                       └─ Settings (Premium, Language, About, Data & licences)
Map  ─→ Station sheet ─→ Route from/to
Ask  (Assistant) ─→ answer cards ─→ Route / Station
```
**Bottom navigation: 3 destinations — Go · Map · Ask.** Nearby, Station and
Settings are reached in context (no tab). Compare: references use 4 tabs + 17 tiles.

## Core flows
**F1 Repeat trip (≤ 2 taps):** Home → tap a recent → Route results (computed instantly).

**F2 New trip:** Home → tap "Where do you want to go?" → picker (To) → pick →
From defaults to *nearest station* (if location granted) else picker opens for From →
Route results. No "Show route" button; results compute as soon as both are set.

**F3 Ride:** Route results → **Start journey** (primary button) → step cards; current
step large, next step preview; "I'm at…" correction; arrival → best exit.

**F4 Station lookup:** search/map/nearby → Station detail, sections in fixed order:
Lines & platforms → Gates & exits → Accessibility → Facilities → Parking → Timings.

**F5 Question:** Ask tab → type/tap a suggestion chip → answer card with action button
("Open route", "Open station") and source line.

## Interaction rules
- One filled primary button per screen; secondary actions are text/tonal.
- Primary touch targets ≥ 56 dp; list rows ≥ 64 dp.
- Never more than 3 route alternatives; label by *why* ("Easiest · 0 changes").
- Intermediate stops collapsed ("12 stops") with expand; interchanges always expanded.
- Direction always phrased as **"towards <terminal>"** + platform number when known.
- Line identity = colour **+ name text** (never colour alone).
- Station names render in the selected UI language with the other script as a subtitle.
- Back always returns to the previous context with state preserved (From/To kept).

## States (every screen defines all four)
| State | Rule |
|---|---|
| Loading | Skeletons only if > 300 ms; dataset loads before first frame finishes (native splash) |
| Empty | Explain + one action (e.g. no recents → "Your trips appear here" + search button) |
| Error | Plain language + recovery action; never a raw exception |
| Partial data | Show what exists; missing section → "Not yet verified for this station" + "Report" (mailto) |
| Offline | Silent for core features. Only online features show an offline chip |
| Location denied | Explain once; "Pick a station" fallback; link to settings if permanently denied |

## Ads (if not premium)
Allowed: Home below recents (native, 1 slot), Station detail end of page, Settings.
Forbidden: station picker, route results, journey mode, map, assistant answers,
any screen during an active journey. No interstitial/app-open/rewarded. Ads load lazily
and never shift layout of content above them (reserved height).

## Review prompt
Use Play In-App Review API only after a completed journey, max once per 90 days,
never on launch, never as a custom star dialog.

## Accessibility checklist
TalkBack order follows reading order; route step cards announce as sentences
("Board Yellow Line towards Samaypur Badli from platform 2") — generated from data;
respects font scale to 200 %; reduce-motion honoured; haptics on journey alerts;
colour-blind safe: line chips carry text, map lines carry labels at zoom.

## Copy tone
Short, imperative, friendly. Hindi copy written natively, not machine-translated
(review before release). No jargon ("interchange" → "Change trains" in UI copy).
