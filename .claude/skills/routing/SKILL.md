---
name: routing
description: Working on route finding, fare calculation, interchanges, last-train checks or journey progress in metro_core. Use when touching packages/metro_core/lib/src/{graph,routing,fare} or debugging a wrong route/fare.
---

# Routing & fare

Spec: docs/routing.md. Model: nodes = (station, service) + station hubs; Dijkstra with
lexicographic cost tuples per profile.

## Checklist for any change
1. Reproduce with the 20-station fixture (`data/fixtures/mini_network`) first; add a failing test.
2. Keep costs non-negative and additive (Dijkstra correctness).
3. Direction = service terminal in travel direction; loops use the data's loop direction name.
4. Through-running services must not count as a change.
5. Cross-operator trips → per-operator fare + `separateTicket` warning.
6. Thresholds (detour factor, default wait) come from config/data, not literals in algorithms.
7. Determinism: tie-break by station ID so results are stable across runs.
8. Run known-journeys regression: `dart test packages/metro_core -t known_journeys`.

## Debugging a wrong route
Print the leg list via the pipeline `inspect route <from> <to> --profile fastest` — don't
dump the graph. Usually the cause is data (missing transfer row, wrong edge time), not the algorithm.
Fix data per the metro-data skill.
