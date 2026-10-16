---
name: metro-data
description: How to add, correct or verify Delhi Metro data (stations, lines, gates, platforms, fares, timings, map overrides) and run the data pipeline. Use for any change under data/ or tools/data_pipeline, or when a metro fact looks wrong.
---

# Metro data workflow

Specs: docs/data-model.md (schema, provenance), docs/metro-data-sources.md (licences).

## Golden rules
1. Never copy data from reference apps, Google Maps, DMRC map images or scraped DMRC pages.
2. Allowed automatic sources: OpenStreetMap (ODbL) and Wikidata (CC0) via the pipeline `fetch`.
3. Every curated fact needs `provenance: {source, confidence, verified_on}`. If you can't cite it, don't add it.
4. IDs are stable slugs; never rename/reuse. Renames → update names + add old name as alias.
5. Curated overlays (`data/curated/`) always win over OSM/Wikidata.

## Common tasks
- **New station / line opening:** add to OSM-backed fetch (re-run `fetch`) or curated YAML; add en+hi names; add transfers if interchange; add known journey covering it.
- **Gate/platform/facility:** edit `data/curated/stations/<id>.yaml`.
- **Fare change:** add a new `fare_system` row with `effective_from` (don't edit history); update fare cases in known_journeys.
- **Map label clash:** `data/curated/map_overrides.yaml`.

## Pipeline
```sh
dart run tools/data_pipeline/bin/build.dart --offline     # from cache
dart run tools/data_pipeline/bin/build.dart --fetch       # refresh OSM/Wikidata (network)
dart run tools/data_pipeline/bin/inspect.dart station <id># query instead of dumping sqlite
```
Build fails on any validation error. Read the `diff` output and check it matches intent.
Do not read `data/cache/*` or the sqlite file into context.
