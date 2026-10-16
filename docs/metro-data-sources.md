# Metro data & map sources — research and licensing

Researched 2026-10-05. **Not legal advice** — get a short legal review before launch
(ODbL share-alike scope + OTD/DMRC permission). Re-check terms each release.

## Source evaluation
| Source | What it has | Licence / terms | Verdict |
|---|---|---|---|
| **OpenStreetMap** (Delhi Metro relation 2536305; per-line route relations, e.g. Red 447214, Pink 5425208) via Overpass API | Station nodes + coordinates, line geometry, ordered route relations, some `railway=subway_entrance` gates, some Hindi `name:hi` | **ODbL 1.0** — commercial use OK; attribution required; derivative *databases* distributed publicly must be offered under ODbL | **Primary** for geometry, station positions, line topology, entrances. |
| **Wikidata** | Station items: en/hi labels, coordinates, line membership (P81), adjacent stations (P197), opening dates | **CC0** — no restrictions | **Primary** for Hindi names, aliases, cross-check of topology & opening dates. |
| **Delhi Open Transit Data (otd.delhi.gov.in) — DMRC static GTFS** | stops (262), routes (36), trips, stop_times; last updated 2023-08-10 | Requires a usage form. T&C §7: *"Modification of any of the Contents or use of the Contents for any other purpose will be a violation"*; §22 allows accurate reproduction with prominent acknowledgement. Ambiguous for a processed, bundled dataset. Also stale (pre-Phase-4 extensions) | **Do not bundle** without written permission. Use for internal validation of travel times/headways only after submitting the usage form. **Action: owner requests written permission from DoT GNCTD / DMRC.** |
| **DMRC website / app / notices** | Gates, platforms, facilities, parking, first/last train, fare notifications | Website content copyrighted; facts themselves are not, but no scraping. | **Manual verification reference only.** Our team records facts by hand into `data/curated/` with `verified_on`. Fare rules come from public fare notifications (cite). |
| **data.gov.in (OGD)** | Occasional DMRC ridership/station datasets | **GODL-India** — commercial use + derivatives allowed with attribution | Use when a relevant dataset exists (popularity from ridership). |
| Google Maps / Places | — | Terms prohibit extraction/caching | **Never.** Directions only via external app intent (no SDK, no key). |
| Reference apps' screenshots, maps (e.g. "© Tilzmatic Tech" map), copy | — | Proprietary | **Never.** Not a data source. |
| Official DMRC network map PDF/image | Schematic map | Copyrighted | **Never bundled.** We generate our own map (map.md). |
| OSM tile servers (tile.openstreetmap.org) | Raster basemap | Tile usage policy forbids heavy app use / offline prefetch | **Not used.** V1 has no basemap. |

## Gap analysis (what open data does NOT reliably give us)
| Data | Open source coverage | Plan |
|---|---|---|
| Station list, coords, lines, order | Good (OSM + Wikidata) | Automated |
| Hindi names | Partial | Wikidata + OSM `name:hi` + manual review |
| Travel time between stations | Not in OSM | Derive from distance & line speed profile (`derived`), calibrate against public journey times; replace with OTD GTFS if permission granted |
| Gates numbers & landmarks | Partial (OSM entrances) | **Manual curation** (biggest effort; see Risks) |
| Platforms & direction | Rare | Manual curation; direction itself is derived from service order (always available) |
| Facilities, lifts, parking | Sparse | Manual curation; launch with top-100 stations verified, rest marked "Not yet verified" |
| Fares | Rules public | Encode slabs + discounts from notification; fare distance from our graph; verify sample pairs → `fare_override` where mismatched |
| First/last train | Public notices | Manual per line/terminal + offsets; `verified_on` |

## Pipeline (tools/data_pipeline) — automatic download & processing
```
fetch   → Overpass query (pinned query file) + Wikidata SPARQL → data/cache/*.json
          (each download recorded in data/cache/lock.json: url, sha256, retrieved_at)
merge   → normalize OSM + Wikidata → apply data/curated overlays (curated always wins)
derive  → edge distances/times, fare distances, schematic map layout, labels
validate→ metro_core validation + known-journey regression (fail = no build)
build   → metro.sqlite (schema vN) + attribution rows in `source` table
sign    → manifest.json with sha256 + Ed25519 signature (key from CI secret only)
diff    → human-readable changelog vs previous release (stations added/renamed, fare changes)
```
`--offline` rebuilds from cache (CI and tests never hit the network).
Releases: GitHub Release / CDN bucket (sync.md). The bundled asset is refreshed each app release.

## Attribution (in app: Settings → Data & licences; in store listing; in map corner)
- "Map and station data © OpenStreetMap contributors, available under the Open Database Licence (ODbL)."
- "Includes data from Wikidata (CC0)."
- Any OTD/DMRC data only if permission granted, with the exact acknowledgement they require.
- "MetroMitra is not affiliated with DMRC."

## ODbL obligation (decision needed — see decisions.md OPEN-2)
`metro.sqlite` mixes OSM-derived data with curated facts → treat it as a Derivative
Database. Recommended: publish each dataset release under ODbL in a public repo/release
(simple, compliant, good for trust). Alternative (keep curated facts proprietary) requires
structuring as a Collective Database — needs legal review.

## M2 findings (live run 2026-10-05, locked in data/cache/sources.lock.json)
- Overpass (exact `network="Delhi Metro"`, bbox in the query): 24 subway route relations (9 lines, DMRC only; Noida Aqua / Rapid Metro use other networks and are NOT included), 535 stop nodes, 559 elements. A regex network match plus recursion timed out twice (server busy); the exact-match query works. Stop nodes are per direction (not per station), so stations are rebuilt by (line, name).
- Wikidata (bbox + metro station class): 309 rows / 279 stations; 277 have Hindi labels. Only 32 of 271 OSM stations carry a `wikidata` tag, so most stations have no Wikidata link and no interchange link.
- Result: 271 stations, 12 services, 524 edges; 0 stations merged across lines (draft). 27 same-name interchange candidates await curation (`station_merges`).
- Source disagreements are listed in build-report.json (names, Hindi names, one coordinate, a suspicious `Rohini West` link whose Wikidata label differs entirely).
- Licensing: OSM (ODbL) and Wikidata (CC0) attribution is carried in `source` rows and `meta.attribution`. Publication licence for the combined database remains OPEN-2; nothing is published or bundled.

## Reference check against the official DMRC map (2026-10-12)
Source: DMRC "Metro Network in Delhi-NCR" map, as on August 2026 (PDF supplied by the owner). Used **only to verify**
the dataset, never copied into it: `data/curated/reference/dmrc_network_2026-08.yaml` holds the per-line figures from
its "Operational Network" table; `pipeline reference` (and `tools/check.dart`) compares them with the build.

| DMRC line | Official stations / km | Dataset stations / km (share) |
|---|---|---|
| 1 Red | 29 / 34.549 | 29 / 32.7 (95 %) |
| 2 Yellow | 37 / 49.019 | 37 / 45.7 (93 %) |
| 3 Blue (Dwarka Sec 21 - Noida Electronic City) | 50 / 56.114 | 50 / 54.1 (96 %) |
| 4 Blue (Yamuna Bank - Vaishali) | 8 / 8.511 | 8 / 8.1 (95 %) |
| 5 Green | 24 / 28.781 | 24 / 26.8 (93 %) |
| 6 Violet | 34 / 46.341 | 34 / 43.2 (93 %) |
| 7 Pink | 45 / 71.548 | **46** / 64.0 (89 %) |
| 8 Magenta | 33 / 49.195 | 33 / 44.5 (91 %) |
| 9 Grey | 4 / 5.491 | 4 / 4.4 (80 %) |
| Orange (Airport Express) | 7 / 24.917 | 7 / 22.1 (89 %) |
| DMRC total (per-line sum) | 271 | 272 |

Findings and actions:
- **Station counts match on 9 of 10 lines; terminals match.** Pink: the table lists 45 operational stations and one
  station of "Majlis Park - Maujpur-Babarpur" as under construction, but the map does not say which; the dataset (OSM) has
  all 8 stations of that section. Documented as accepted; not changed until a source names the station.
- **Interchange fixed:** the official map draws **New Delhi** as one Yellow / Airport Express interchange; the dataset had
  two unlinked stops, so trips from the Airport Express to the Yellow Line detoured via Dwarka Sector 21. Curated merge
  added (overlays.yaml, cited); now 244 stations, 26 interchanges.
- **Walkway interchange not modelled:** Dhaula Kuan (Airport Express) - Durgabai Deshmukh South Campus (Pink) is marked as
  an interchange "through walkway"; the schema needs a walk time that no source gives us, so it is left out (no
  fabricated walk time). Routes between those lines use other interchanges.
- **Distances are 80-96 % of the official line lengths**: edge distances are derived from station positions (straight
  line), the track is longer. The app labels every distance as an estimate.
- "Dwarka - Kakrola" is the official name (map), kept.
- Not in the dataset (scope: DMRC lines): Aqua Line (NMRC, 21), Rapid Metro Gurugram (11), Namo Bharat (15), Meerut Metro (12).
