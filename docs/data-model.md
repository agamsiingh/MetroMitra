# Metro data model

One canonical, versioned dataset → compiled to **`metro.sqlite`** (read-only on device).
Authoring happens in `data/curated/*.yaml` + OSM/Wikidata extracts; the pipeline
(docs/metro-data-sources.md) merges, validates and compiles.

## Versioning
- `dataset_version`: calendar semver `YYYY.MM.patch` (e.g. `2026.10.1`).
- `schema_version`: integer; app declares supported range `[min,max]`.
- Every release has `metro.manifest.json` (see sync.md) with sha256 + Ed25519 signature.

## Identity rules
- IDs are stable lowercase slugs, never reused: station `rajiv-chowk`, line `yellow`,
  service `blue-main`, gate `rajiv-chowk:g3`. Renamed station → keep ID, update names, add old name as alias.
- Every fact row carries provenance: `source_id`, `confidence`, `verified_on`.
- `confidence ∈ {official, verified, derived, community}`
  - official: from an operator notification/publication we're permitted to use
  - verified: checked by our team (field/photo/official page) on `verified_on`
  - derived: computed by the pipeline (e.g. fare from distance)
  - community: OSM/Wikidata, not yet verified
  UI labels anything not official/verified; the assistant states the caveat.

## Tables (schema v1)
```text
meta(key PK, value)                      -- dataset_version, schema_version, built_at, city, attribution
source(id PK, name, url, license, retrieved_at, notes)

operator(id PK, name_en, name_hi, fare_system_id)          -- DMRC, NMRC (Aqua), Rapid Metro Gurugram...
line(id PK, operator_id, name_en, name_hi, short_name, color_hex, text_color_hex, sort, status)
line_service(id PK, line_id, name, is_loop, through_service_of NULL)   -- branches/loops/through-running
service_stop(service_id, seq, station_id, dist_from_start_m, PK(service_id, seq))

station(id PK, name_en, name_hi, lat, lng, popularity, status, opened_on, map_x, map_y,
        source_id, confidence, verified_on)
station_name(station_id, text, lang, kind)   -- kind: official|alias|old|misspelling|landmark
station_line(station_id, line_id, station_code)

edge(id PK, service_id, from_station, to_station, travel_s, distance_m, source_id, confidence)
   -- directed; both directions stored; travel_s includes dwell
transfer(station_id, from_line, to_line, walk_m, walk_s, step_free, notes_en, notes_hi,
         source_id, confidence, verified_on)            -- in-station interchange
walk_link(id PK, from_station, to_station, walk_m, walk_s, requires_exit, step_free,
          notes_en, notes_hi, source_id, confidence)    -- out-of-system (e.g. separate operators)

platform(station_id, line_id, number, towards_station_id, service_id, notes_en, notes_hi, ...)
gate(id PK, station_id, number, name_en, name_hi, lat, lng, is_open, has_lift, has_ramp,
     has_escalator, is_step_free, ...provenance)
gate_landmark(gate_id, text_en, text_hi, kind)       -- kind: road|landmark|bus|rail|mall...
facility(station_id, type, gate_id NULL, location_en, location_hi, ...)  -- type enum: atm, toilet, ...
accessibility(station_id, lifts, escalators, tactile_path, wheelchair_available, notes_en, notes_hi, ...)
parking(id PK, station_id, name_en, name_hi, car, two_wheeler, cycle, tariff_id, ...)
parking_tariff(id PK, vehicle, period, max_hours NULL, amount_paise, notes_en, ...)

fare_system(id PK, operator_id, currency, effective_from, source_id)
fare_slab(fare_system_id, day_type, min_km, max_km, amount_paise)   -- day_type: regular|sunday_holiday
fare_discount(fare_system_id, media, kind, percent, windows_json)   -- e.g. smart_card 10%, off_peak +10%
fare_override(fare_system_id, from_station, to_station, day_type, amount_paise, source_id, verified_on)

timing(service_id, station_id, direction_terminal_id, day_type, first_dep, last_dep, source_id, verified_on)
headway(service_id, day_type, from_time, to_time, minutes)

map_line_path(service_id, seq, x, y)     -- schematic geometry (docs/map.md)
map_label(station_id, x, y, anchor, zoom_min)
geo_line_path(service_id, seq, lat, lng) -- geographic geometry for Nearby mini-map
```
Money is integer **paise**; never `double`. Times are minutes since 00:00 service day
(may exceed 24:00 for post-midnight). Distances in metres.

## Implemented in M1 (`packages/metro_core`, schema v1)
DDL: `lib/src/dataset/schema.dart` (single source). Tables present: meta, source, fare_system,
operator, line, line_service, station, service_stop, station_name, station_line, edge, transfer,
walk_link, platform, gate, gate_landmark, facility, accessibility, fare_slab, fare_discount,
fare_override, timing. **Not yet** (added with the milestone that needs them, schema bump if
breaking): parking, parking_tariff, headway, map_line_path, map_label, geo_line_path.
Conventions: ADR-025 in decisions.md. Required `meta` keys: dataset_version, schema_version,
built_at, city, attribution, bbox (`minLat,minLng,maxLat,maxLng`). Validation: `validateSnapshot`
(codes asserted in `test/validation_test.dart`). Fixture: `data/fixtures/mini_network/dataset.yaml`
(TEST DATA). Build: `dart run tools/data_pipeline/bin/build.dart build --allow-test-data`.

### M2 additions
Nullable (unknown = NULL): `name_hi`, `operator.fare_system_id`, `edge.travel_s`, `transfer.walk_m/walk_s`.
New: `origin(entity, entity_id, field, source_id, external_id, status, detail)`, `source.version`, `source.sha256`,
`meta.stage`. Draft vs release validation: ADR-027. Overlay format: `data/curated/overlays.yaml` header.

### M3 additions
No schema change. Conventions now relied on by routing/fare: a `transfer` row is directional (both directions are
stored) and a missing row means *no interchange*; `walk_s`/`walk_m` NULL = unknown (fallback estimate, reported);
`edge.travel_s` NULL = unknown; `fare_slab` bands are metres-compared half-open ranges; `fare_override` is exact
(from, to, day type); `origin.detail` holds the curation audit text (reason | source | verified_on). See routing.md.

## Curated YAML (authoring) — example shape
```yaml
# data/curated/stations/example-station.yaml   (values illustrative only)
id: example-station
names: { en: Example Station, hi: उदाहरण स्टेशन }
aliases: [Exmpl, Example Stn]
gates:
  - number: 1
    landmarks: [{ text_en: Towards Main Road, kind: road }]
    has_lift: true
    provenance: { source: team-survey, confidence: verified, verified_on: 2026-09-01 }
```

## Validation (metro_core/validation, run in pipeline and after download)
Hard failures (build/install rejected):
- FK integrity; unique IDs; every station on ≥ 1 service; every service's stops connected by edges.
- Graph connected per operator; every interchange in `station_line` has transfer rows.
- Colours valid hex; names non-empty in en **and** hi; coordinates inside NCR bbox.
- Fares: slab coverage without gaps; overrides reference existing pairs; amounts > 0.
- Timings: first < last (service-day minutes); platforms reference real stations/services.
- Known-journey regression table passes (testing.md).
Warnings (report only): `community` confidence on gates/platforms; missing Hindi alias; stale `verified_on` > 12 months.

## User data (separate drift DB `user.sqlite`, migrations tested)
`recent_trip(from_id, to_id, profile, used_at)` · `favourite(kind, station_id, label)` ·
`setting(key, value)` · `journey_state(json)` (resume after process death).
User rows reference station IDs; on dataset swap, unknown IDs are hidden, not deleted.
