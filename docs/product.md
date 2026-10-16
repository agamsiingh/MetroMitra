# Product

## Vision
**MetroMitra** ("metro friend") — the calmest way to ride the Delhi Metro.
Promise: **"Delhi Metro without confusion."**

Most metro apps compete on feature count (17+ home tiles, ads in every flow).
MetroMitra competes on *clarity*: open app → say where you're going → know exactly
which gate, platform, direction, interchange and exit. Works underground, offline.

## Users
| Persona | Need | Design consequence |
|---|---|---|
| Daily commuter | Fast repeat trips, fare, last train | Recents + one-tap repeat; last-train warning |
| Occasional rider / tourist | "Which platform? Which side?" | Step-by-step journey mode with direction "towards X" |
| Elderly / low digital literacy | Big text, no clutter, Hindi | Large targets, Hindi UI, one action per screen |
| Accessibility user | Lifts, ramps, step-free interchanges | Accessibility data on station + "least walking" route |
| Visitor with a landmark | "Nearest exit for AIIMS?" | Destination exit = gate + landmarks |

## Jobs to be done (ranked)
1. Get me from A to B — route, fare, time, changes.
2. Guide me during the trip — platform, direction, interchange, which exit.
3. Tell me about a station — gates, lifts, parking, facilities.
4. Which station is near me?
5. Answer a quick metro question (offline).

## Product principles
1. **One primary action per screen.** Home = "Where do you want to go?"
2. **Answer, don't browse.** Fold first/last train, fare, platform into the route result instead of separate screens.
3. **Offline is the default**, not a mode.
4. **Truth over completeness.** Missing data is shown as missing, never guessed.
5. **Respect the journey.** No ads, popups or rating prompts during route/journey.
6. **Original identity.** No cloning of reference UIs, assets, maps or copy.

## V1 scope (MVP)
Home · Station search · Route (Fastest / Easiest / Less walking) · Journey mode ·
Station detail (lines, platforms, gates/exits, facilities, accessibility, parking) ·
Nearby · Offline vector metro map with route highlight · Offline assistant ·
Data updates · Settings (language, theme, about, licences, premium).

## Non-goals for V1
Live train positions/crowding · ticket purchase / QR tickets · card recharge ·
buses/RRTS/autos · accounts & cloud sync · social features · other cities
(architecture allows it; see decisions ADR-014).

## Monetization
- Free: all navigation (search, routes, fares, map, journey, station info, assistant offline).
- Ads: native/banner only on non-critical surfaces (docs/ux.md §Ads). No interstitials, app-open or rewarded ads.
- **Premium (one-time Play purchase):** ad-free, advanced route comparison
  (side-by-side, custom transfer tolerance), personalization (saved Home/Work, pinned trips, themes).

## Success metrics
- Time to first route from cold start ≤ 10 s median (search + pick both stations).
- ≥ 95 % route requests answered with zero network.
- Assistant: ≥ 85 % of common questions answered deterministically; 0 fabricated facts (test-enforced).
- Crash-free sessions ≥ 99.5 %; Play rating ≥ 4.5.
- Data freshness: new stations/lines in-app ≤ 7 days after opening (via data update, no app release).

## Reference app analysis — what we keep / fix
| Observed in references | Verdict |
|---|---|
| 17-tile home grid, banner ad on top | **Fix:** single search-first home |
| From/To card with swap | Keep, auto-compute (no "Show Route" button) |
| Summary row: minutes · changes · stations · fare | Keep, add smart-card fare + platform |
| Line-coloured numbered stop timeline | Keep, collapse intermediate stops, promote interchanges to instruction cards |
| Separate screens for fare, first/last train, gates, parking | **Fix:** fold into route result / station detail |
| Near-me list with line chips + distance | Keep, add walk time and "route from here" |
| Raster third-party map image with watermark, no highlight | **Fix:** own vector map, route highlight, tap stations |
| Ads inside route/fare/gate screens, rating modal on home | **Fix:** never in flows; review prompt only after a completed journey |
| Premium + settings + about mixed on one tab | **Fix:** premium is one row in Settings |
| Developer personal identity on splash/about | Not applicable — do not copy |
