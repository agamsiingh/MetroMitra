# Design system

Original identity. Do not reuse the reference apps' palette (sage/serif/orange-navy),
fonts, icons, map or splash.

## Brand
- Name: MetroMitra. Mark (since M0, ADR-017): owner-supplied logo `app/assets/brand/logo.jpg` — train front,
  red ring, navy wordmark banner ("Metro" white, "Mitra" red). Launcher icons/splash are derived from it
  (`python tools/brand/make_icons.py`). It replaces the earlier blue→saffron "M" concept.
- **Logo risk (open):** the nose roundel resembles the DMRC logo and the ring+bar resembles the London
  Underground roundel — see decisions.md "Logo risk". Resolve before release. Avoid the DMRC logo and the
  words "official"/"DMRC" in branding. Store listing must say "Not affiliated with DMRC".
- The logo's red/navy is the *brand mark*, not the UI palette: UI colours stay the tokens below.

## Colour tokens (Material 3, seeded)
| Token | Light | Dark | Use |
|---|---|---|---|
| `brand.primary` | `#1E5BD8` (metro blue) | `#9DB8FF` | primary actions, focus |
| `brand.secondary` | `#F57C1F` (saffron) | `#FFB77C` | highlights, journey progress |
| `surface` | `#FAFBFD` | `#101318` | backgrounds |
| `surfaceContainer` | `#F0F2F7` | `#1A1E25` | cards (use sparingly) |
| `success` / `warning` / `error` | M3 defaults, AA-checked | | last-train warning = warning |

Generate full schemes with `ColorScheme.fromSeed` then override the tokens above.
**Line colours are data** (`line.color_hex`), never theme tokens; text on line colour
uses computed contrast (black/white by luminance).

## Typography
- Latin: **Inter** (OFL). Devanagari: **Noto Sans Devanagari** (OFL). Bundled for offline.
- Scale (sp): display 32/40 · title 22/28 · body 16/24 · label 14/20 · caption 12/16.
- Station names in route/journey: title weight 600. Numbers (time, fare) use tabular figures.

## Spacing & shape
4-pt grid; screen padding 16; section gap 24; card radius 16; button radius 28 (pill);
minimal elevation (0–1); separation by whitespace and dividers before cards.

## Components (app/lib/shared/widgets)
| Component | Notes |
|---|---|
| `DestinationBar` | Home hero search field, 64 dp, opens picker |
| `StationField` pair + swap | From/To with swap FAB-small |
| `LineChip` | colour dot + line name; data-driven colour |
| `RouteSummary` | time · changes · stops · fare, tabular figures |
| `StepCard` | journey/route step; icon + one sentence + detail line |
| `StopTimeline` | vertical line in line colour, collapsible stop group |
| `InfoSection` | titled section with provenance footer ("Verified 12 Aug 2026") |
| `StateView` | empty / error / offline / denied variants |
| `AnswerCard` | assistant answer + action + source |

## Iconography & motion
Material Symbols Rounded only (no third-party glyphs). Motion: 200 ms standard easing,
shared-axis for push navigation, no decorative animation on journey screens; respect
`MediaQuery.disableAnimations`.

## Dark mode
Full support; map uses a dark palette with line colours brightened to keep 3:1 contrast
against background.
