# Routing

## Requirements that drive the design
- ~300 stations, ~15 line services, ~20 interchanges, a few out-of-system walk links.
- Profiles: fastest, fewest changes ("Easiest"), least walking, fewest stops.
- Need direction ("towards X") and platform per boarding → must know the *service* ridden.
- Separate operators/fare systems (DMRC, NMRC Aqua, Rapid Metro Gurugram, Airport Express)
  and exit-and-re-enter links.
- Branches (Blue main/branch at Yamuna Bank), loops (Rapid Metro), ring-like Pink line,
  occasional through-running services.
- No licensed real-time/timetable data in V1 → time-independent routing + last-train check.

## Graph model
- **Node** = `(station, service)` "stop node", plus one **station hub node** per station
  (entry/exit point).
- **Edges**
  | Kind | From → To | Cost components |
  |---|---|---|
  | ride | stop(A,s) → stop(B,s), adjacent in service s | travel_s (incl. dwell), stops=1 |
  | board | hub(A) → stop(A,s) | wait = headway/2 (default from `headway`) |
  | alight | stop(A,s) → hub(A) | 0 |
  | transfer | stop(A,s1) → stop(A,s2) | walk_s + walk_m + wait(s2), changes=1 |
  | walk_link | hub(A) → hub(B) (out-of-system) | walk_s, walk_m, changes=1, exits=1 |
- Through-running: if `line_service.through_service_of` links two services, add a zero-walk,
  zero-change transfer edge with no extra wait.
- Directed edges store service order → direction terminal = last stop of the service in
  travel direction (loops use a named loop direction from data).

## Algorithm
**Dijkstra with a lexicographic cost vector per profile**, binary heap.
Costs are non-negative and additive, so Dijkstra is exact.

| Profile | Cost tuple (compared left → right) |
|---|---|
| fastest | (time_s, changes, walk_m) |
| easiest | (changes, time_s, walk_m) |
| less walking | (walk_m, changes, time_s) |
| fewest stops | (stops, changes, time_s) |

Plus guardrails: easiest/less-walking routes are discarded if > 1.5× fastest time + 10 min
(prevents absurd detours); thresholds in config, not code.

**Why not A\***: the graph has < 1 000 nodes; Dijkstra finishes in well under 1 ms and
A* heuristics on lexicographic costs add complexity for no gain.
**Why not RAPTOR/CSA**: those need trustworthy timetables (not licensed in V1). Revisit if
OTD GTFS permission is granted (ADR-004).
**Why not precomputed all-pairs**: 90 k pairs × profiles bloats the dataset; on-demand is instant.

## Output: `Itinerary`
```
Itinerary { profile, legs[], totalTime, changes, stops, walkM, fare: FareQuote,
            warnings[] (lastTrainRisk, unverifiedTransfer, separateTicket) }
Leg = RideLeg { service, line, fromStation, toStation, directionTerminal, platform?, stops[], time }
    | TransferLeg { station, fromLine, toLine, walkM, walkS, stepFree, notes }
    | WalkLeg { from, to, walkM, requiresExit, notes }
```
Alternatives: run all profiles, dedupe by leg sequence; return 1–3 distinct options,
each tagged with the profiles it wins.

## Fare (metro_core/fare)
Per fare system: fare distance = shortest-path distance within that operator's network
→ slab by `day_type` → discount by media (token / smart card) and time window (off-peak).
`fare_override` wins when present. Cross-operator trips = sum per operator segment and are
flagged `separateTicket`. Quote carries `confidence` (derived unless an override/verified sample matches).
Airport Express and other special-fare lines use their own fare system rows.

## Last-train check
For each RideLeg, look up `timing.last_dep` at the boarding station for the travel direction;
simulate arrival using leg times; warn if any boarding is after last departure.
Uses `Clock` provider; day type from calendar (Sunday/holiday list in data).

## Journey progress model
Expected timeline from itinerary times. Position = max(time-based estimate, user taps
"I'm at X", GPS snap to nearest station within 250 m when a fix exists).
Underground GPS is unreliable → never auto-advance past an interchange without confirmation.

## Tests (see testing.md)
Fixture network with branch, loop, ring, out-of-system walk, two operators; real-data
known-journeys table; properties: path edges exist, costs monotone, A→B and B→A same
changes count on symmetric networks, every station reachable.

## Implemented in M3 (ADR-035..040)
Code: `packages/metro_core/lib/src/{routing,fare}/`. Differences from the design above:
- **Nodes are stop visits** `(service, position)`, not `(station, service)`, so a service that visits a station twice
  cannot teleport between its visits. Each visit has a "fresh" (just boarded/changed) and a "rode" state; only "rode"
  nodes may alight or change. Per station an *arrive* hub (alighted; may only end the trip or take a walk link) and a
  *depart* hub (origin, or reached by a walk link; may only board). This makes alight-and-re-board impossible.
- **Interchanges** exist only from `transfer` rows (`lineChange`), different services of one line (`sameLineChange`,
  estimated), `through_service_of` (`throughRunning`, free, 0 changes) and **seams** (`repeatedStop`, below).
- **Seam rule (ADR-036):** at a station the same service visits twice, the rider must change; the repeated visit is
  never ridden through. Such services (and loops) claim no direction terminal.
- **Travel-time fallback (ADR-035):** dataset values win; NULLs use `TravelTimeModel` (`fallback-v1`): ride = dwell 25 s +
  distance / 35 km/h, boarding wait 180 s (first boarding, after a walk link, and in every change), interchange walk
  240 s / 200 m. Placeholders, not measurements. `Itinerary.assumptions` lists which were used
  (`ride_time_estimated`, `boarding_wait`, `transfer_walk_time_estimated`, `transfer_walk_distance_estimated`);
  `timeIsEstimate` is true whenever any is used (always today). The UI must label such times "approx.".
- **Result:** `RoutePlanner.plan(from, to)` -> `RouteResult{status, itineraries}`; statuses `ok, sameStation,
  unknownStation, notServed, noRoute`. Alternatives: one per profile, merged by leg signature, guard rail 1.5x + 600 s,
  max 3. `stationComponents()` reports disconnected parts. Closed/planned stations and non-open lines are not routable
  and cannot be passed through; a missing edge is never invented.
- **Fare (ADR-037):** `FareEngine.quote(legs, FareRequest)`; see the ADR for the exact rules. `FareQuote` says
  `available | partial | unavailable`, per-ticket `FareSegment` with basis (override/slab), source, confidence or `FareGap`.
- **Last train (ADR-040):** `checkLastTrain(snapshot, itinerary, departMinute:, dayType:)` -> warnings
  `lastTrainRisk | lastTrainUnknown`.
- **Tools:** `dart run tools/data_pipeline/bin/build.dart route <from> <to> [--json]` on any built dataset (drafts ok).

## Implemented in M8 (journey progress, ADR-058)
`packages/metro_core/lib/src/journey/journey.dart`: `JourneyPlan`, `JourneyState`, `JourneyEngine`. Per-stop time inside
a ride = ride seconds / stops (from the itinerary, so approximate whenever the itinerary is); the estimate is clamped to
the current ride and never advances a step; corrections reset the estimate base; GPS snap (250 m) is a correction.
