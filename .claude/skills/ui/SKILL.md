---
name: ui
description: Building or changing MetroMitra screens and widgets — design tokens, components, states, accessibility, ad placement rules. Use for any change under app/lib/features/*/presentation or app/lib/shared/widgets.
---

# UI

Specs: docs/ux.md (rules, states, ads), docs/design-system.md (tokens, components),
docs/screens.md (per-screen). Read only the section for the screen you're building.

## Checklist per screen
- One filled primary button. Primary targets ≥ 56 dp, rows ≥ 64 dp.
- Implement all states with `StateView`: loading (>300 ms), empty, error, offline (online features only), denied (location), partial data.
- Colours from theme tokens; line colours from data with computed text contrast; never colour-only meaning (always show line name).
- Strings in ARB en + hi. Station names: UI language + other script subtitle.
- Semantics labels on icons/buttons; route steps read as full sentences.
- Test at 200 % font scale and dark mode.
- Provenance footer on station data sections.
- **Ads:** only in Home (below recents), Station detail bottom, Settings. Never picker, route, journey, map, assistant.
- No custom rating dialogs; In-App Review only after a completed journey.

## Done
Widget tests cover each state; goldens only for timeline/step card/map highlight.
