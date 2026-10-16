# Search

In-memory index in `metro_core/search` built from `station` + `station_name`.
~300 stations × ~6 names → linear scoring over precomputed keys is < 2 ms; no FTS needed.

## Normalization (both index and query)
1. Unicode NFC; lowercase; strip punctuation; collapse spaces.
2. Expand abbreviations from data table (`sec`→`sector`, `stn`→`station`, `chk`→`chowk`, `ph`→`phase`, `mkt`→`market`, `int'l`→`international`) — list lives in dataset `meta`, not code.
3. Remove stop-words (`metro`, `station`, `stn`).
4. **Devanagari**: strip ZWJ/ZWNJ, nukta folding (ज़→ज), chandrabindu→anusvara; transliterate to a Latin skeleton (ITRANS-like table) so "राजीव चौक" can also match Latin keys.
5. **Phonetic key** (Indian-English tuned): `aa→a, ee→i, oo→u, w→v, ph→f, sh→s, z→j, ck→k`, drop `h` after consonants, collapse doubles. ("Rajeev Chok" and "Rajiv Chowk" → same key.)

## Tiers and score
| Tier | Match | Base |
|---|---|---|
| 1 | exact normalized name (any lang) | 1000 |
| 2 | prefix of name, or every query token prefixes a name token ("raj ch") | 800 |
| 3 | exact/prefix on alias/old name/landmark | 600 |
| 4 | fuzzy: Damerau-Levenshtein on tokens (≤1 edit for 4–7 chars, ≤2 for ≥8) or phonetic-key equality | 400 − 50×edits |
| — | popularity tiebreak | + min(popularity, 50) |
| — | user recents/favourites | + 30 |
Within a tier: shorter name first, then popularity. Tie never reorders tiers.
Return top 20; empty query → recents + favourites + nearest (if location).

## Requirements met
English, Hindi, misspellings (fuzzy + phonetic), aliases (data), partial names (prefix/tokens).
Landmark search (e.g. "AIIMS") resolves via `station_name.kind=landmark` and gate landmarks → station.

## Shared with assistant
`SearchIndex.resolve(text, {minScore})` returns ranked candidates with confidence; the
assistant uses it for slot filling and asks for clarification when top-2 scores are close.

## Tests
Table-driven `test/search_cases.yaml`: query → expected top-1 (and must-not-appear).
Includes Hindi, Hinglish spellings, typos, abbreviations, landmark, and a non-existent name
(must return empty, not a random fuzzy hit — fuzzy threshold enforces a minimum score).

## Implemented in M4 (ADR-041..045)
Code: `packages/metro_core/lib/src/search/` (`normalizer`, `devanagari`, `edit_distance`, `search_models`, `search_index`).
Where this differs from the draft above, the ADRs win:
- **Order:** exact name > exact alias/code > prefix > substring > fuzzy (alias before prefix). Bands: 1000 / 900 /
  800 name-prefix, 700 alias-prefix / 600, 500 substring / 400, 350 fuzzy (minus 50 per edit). Popularity is a
  tie-break, not additive. No recents/favourites/nearest here: the app (M5) reorders around the pure index.
- **API:** `SearchIndex.fromSnapshot(snapshot, {config})` then `search(query, options: SearchOptions(limit, scope,
  onlyOpen))` -> `List<SearchResult>`. A result is a `StationSummary` (id, name_en, name_hi?, aliases, lines with
  codes and colours, service ids, lat/lng, status, `isInterchange`, provenance) or a `LineSummary`, plus a
  `SearchMatch` (tier, field, matched stored text, score, edits, `phonetic`). Closed/planned entities are hidden unless
  `onlyOpen: false`. Everything shown is copied from the dataset; unknown stays null.
- **Indexed text:** `station.name_en/name_hi`, every `station_name` row (alias, old, misspelling, landmark),
  `station_line.station_code`, line `name_en/name_hi/short_name`. Gate landmarks arrive with gate data (not in the
  dataset yet). The `resolve(text, minScore)` helper for the assistant is M9.
- **Typos:** transposition/insert/delete/substitute, spelling variants (phonetic skeleton), spacing, one wrong word of a
  longer name, typo in the leading part of a long query. Queries under 4 characters are never fuzzy; garbage
  returns nothing.
- **Hindi:** nukta/chandrabindu/ZWJ folding, Devanagari digits, vowel-length and anusvara variants, Hindi query vs
  Latin-only station (and the reverse) via the phonetic skeleton; no Hindi name is ever generated.
- **CLI:** `dart run tools/data_pipeline/bin/build.dart search "<query>" [--input f] [--limit n] [--stations|--lines]
  [--all] [--json]`, `search --self-check`.
- **Tests:** `search_normalizer_test`, `search_test` (ranking, English, typos, aliases, codes, Hindi/Unicode, lines,
  NULL semantics, determinism under shuffled rows, properties, fuzz), `search_cases.yaml` + `search_cases_test`
  (table-driven, 50+ cases on an invented network), `search_perf_test`, pipeline `search` CLI tests.
- **Known data findings (not search bugs):** the Hindi name of `rohini-west` is still the old Rohini West spelling while
  the English name is the renamed station; 73 stations have no Hindi name; `A.I.I.M.S.` is only reachable as "aiims"
  (dots join) and by its code.
