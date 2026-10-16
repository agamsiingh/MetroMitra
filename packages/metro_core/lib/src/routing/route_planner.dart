import 'package:metro_core/src/fare/fare_engine.dart';
import 'package:metro_core/src/fare/fare_quote.dart';
import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/network.dart';
import 'package:metro_core/src/model/provenance.dart';
import 'package:metro_core/src/model/snapshot.dart';
import 'package:metro_core/src/routing/itinerary.dart';
import 'package:metro_core/src/routing/travel_time.dart';
import 'package:metro_core/src/util/min_heap.dart';

/// Tunables that are policy, not network data (docs/routing.md).
class RoutingConfig {
  const RoutingConfig({
    this.detourFactor = 1.5,
    this.detourSlackS = 600,
    this.maxAlternatives = 3,
  });

  /// Alternatives slower than `fastest * detourFactor + detourSlackS` are
  /// dropped.
  final double detourFactor;
  final int detourSlackS;
  final int maxAlternatives;
}

enum _Kind { board, ride, transfer, through, alight, walk }

/// Cost vector. Compared lexicographically in a profile-specific order.
class _Cost {
  const _Cost(this.time, this.changes, this.walkM, this.stops);

  static const zero = _Cost(0, 0, 0, 0);
  final int time;
  final int changes;
  final int walkM;
  final int stops;

  _Cost operator +(_Cost o) => _Cost(
    time + o.time,
    changes + o.changes,
    walkM + o.walkM,
    stops + o.stops,
  );

  int at(int i) => switch (i) {
    0 => time,
    1 => changes,
    2 => walkM,
    _ => stops,
  };
}

/// Priority of (time, changes, walk, stops) per profile; every profile ends
/// with the remaining components so ties are broken the same way every time.
const _order = {
  RoutingProfile.fastest: [0, 1, 2, 3],
  RoutingProfile.easiest: [1, 0, 2, 3],
  RoutingProfile.lessWalking: [2, 1, 0, 3],
  RoutingProfile.fewestStops: [3, 1, 0, 2],
};

int _compare(_Cost a, _Cost b, List<int> order) {
  for (final i in order) {
    final c = a.at(i).compareTo(b.at(i));
    if (c != 0) return c;
  }
  return 0;
}

class _Visit {
  _Visit(this.service, this.seq, this.stationIndex, this.station, this.line);

  final LineService service;

  /// Index within the service's stop list; one per *visit*, so a station that
  /// a service passes twice has two nodes and no teleporting between them.
  final int seq;
  final int stationIndex;
  final String station;
  final Line line;
}

class _Arc {
  _Arc(
    this.kind,
    this.from,
    this.to,
    this.cost, {
    this.edge,
    this.rideEstimated = false,
    this.forward = true,
    this.transferKind,
    this.row,
    this.walkSEstimated = false,
    this.walkMEstimated = false,
    this.link,
    this.linkFrom,
    this.linkTo,
  });

  final _Kind kind;
  final int from;
  final int to;
  final _Cost cost;
  final Edge? edge;
  final bool rideEstimated;
  final bool forward;
  final TransferKind? transferKind;
  final Transfer? row;
  final bool walkSEstimated;
  final bool walkMEstimated;
  final WalkLink? link;
  final String? linkFrom;
  final String? linkTo;
}

/// Deterministic multi-profile router (docs/routing.md, ADR-035).
///
/// Graph: one node per *stop visit* `(service, position)`, plus per station an
/// "arrive" hub (reached by alighting; can only end the trip or take a
/// walk-link) and a "depart" hub (the origin, or reached by a walk-link; can
/// only board). The hub split means a rider cannot skip an interchange's walk
/// by alighting and re-boarding. Nothing is invented: an interchange exists
/// only if the dataset has a `transfer` row (or the same service visits the
/// station twice / the same line has several services), and unknown times use
/// the documented [TravelTimeModel] fallback, reported as assumptions.
class RoutePlanner {
  RoutePlanner(
    this.snapshot, {
    this.model = const TravelTimeModel(),
    this.config = const RoutingConfig(),
    this.fareEngine,
  }) {
    _build();
  }

  final MetroSnapshot snapshot;
  final TravelTimeModel model;
  final RoutingConfig config;
  final FareEngine? fareEngine;

  final _stationIndex = <String, int>{};
  final _stationIds = <String>[];
  final _visits = <_Visit>[];
  final _visitsAt = <List<int>>[];
  late final List<List<_Arc>> _adj;
  final _stopsByService = <String, List<String>>{};
  int get _visitCount => _visits.length;

  // Node layout: [0,V) visit "fresh" (just boarded / changed here, has not
  // ridden yet), [V,2V) visit "rode" (arrived by train), then the arrive hubs
  // and depart hubs. Only a "rode" node may alight or change, so boarding and
  // immediately leaving cannot be used to dodge an interchange walk.
  int _rode(int v) => _visitCount + v;
  int _arrive(int s) => 2 * _visitCount + s;
  int _depart(int s) => 2 * _visitCount + _stationIds.length + s;

  /// Visit index of a visit node (fresh or rode).
  int _v(int node) => node < _visitCount ? node : node - _visitCount;

  void _build() {
    final open = [
      for (final s in snapshot.stations)
        if (s.status == OperatingStatus.open) s.id,
    ]..sort();
    for (final id in open) {
      _stationIndex[id] = _stationIds.length;
      _stationIds.add(id);
      _visitsAt.add([]);
    }

    final stopLists = <String, List<ServiceStop>>{};
    for (final s in snapshot.serviceStops) {
      stopLists.putIfAbsent(s.serviceId, () => []).add(s);
    }
    final edgeBy = <String, Edge>{};
    for (final e in snapshot.edges) {
      edgeBy.putIfAbsent(
        '${e.serviceId}|${e.fromStation}|${e.toStation}',
        () => e,
      );
    }
    final services = [...snapshot.services]
      ..sort((a, b) => a.id.compareTo(b.id));

    // visits
    final visitOf = <String, List<int>>{}; // service -> visit per position
    for (final svc in services) {
      final line = snapshot.line(svc.lineId);
      final stops = (stopLists[svc.id] ?? [])
        ..sort((a, b) => a.seq.compareTo(b.seq));
      _stopsByService[svc.id] = [for (final s in stops) s.stationId];
      if (line == null || line.status != OperatingStatus.open) {
        visitOf[svc.id] = List.filled(stops.length, -1);
        continue;
      }
      final idx = <int>[];
      for (var i = 0; i < stops.length; i++) {
        final si = _stationIndex[stops[i].stationId];
        if (si == null) {
          idx.add(-1);
          continue;
        }
        idx.add(_visits.length);
        _visitsAt[si].add(_visits.length);
        _visits.add(_Visit(svc, i, si, stops[i].stationId, line));
      }
      visitOf[svc.id] = idx;
    }

    final total = 2 * _visits.length + 2 * _stationIds.length;
    _adj = List.generate(total, (_) => <_Arc>[]);
    void add(_Arc a) => _adj[a.from].add(a);

    // ride arcs (both directions along the service order)
    for (final svc in services) {
      final stops = _stopsByService[svc.id]!;
      final idx = visitOf[svc.id]!;
      // A station the service visits twice marks a seam (ring + spur). The
      // dataset does not say a train continues through it, so a rider who
      // arrives there must change (never assumed otherwise, ADR-036).
      final seen = <String>{};
      final repeated = {
        for (final s in stops)
          if (!seen.add(s)) s,
      };
      bool seam(int i) =>
          i > 0 && i < stops.length - 1 && repeated.contains(stops[i]);
      void ride(int i, int j, {required bool forward}) {
        if (idx[i] < 0 || idx[j] < 0) return;
        final e = edgeBy['${svc.id}|${stops[i]}|${stops[j]}'];
        if (e == null) return; // unknown connection: not routable
        final est = e.travelS == null;
        final s = e.travelS ?? model.estimateRideS(e.distanceM);
        for (final fromNode in [idx[i], if (!seam(i)) _rode(idx[i])]) {
          add(
            _Arc(
              _Kind.ride,
              fromNode,
              _rode(idx[j]),
              _Cost(s, 0, 0, 1),
              edge: e,
              rideEstimated: est,
              forward: forward,
            ),
          );
        }
      }

      for (var i = 0; i + 1 < stops.length; i++) {
        ride(i, i + 1, forward: true);
        ride(i + 1, i, forward: false);
      }
      for (var i = 0; i < stops.length; i++) {
        if (idx[i] < 0 || !seam(i)) continue;
        // change trains at the seam without moving to the other visit
        add(
          _Arc(
            _Kind.transfer,
            _rode(idx[i]),
            idx[i],
            _Cost(
              model.transferWalkS + model.boardWaitS,
              1,
              model.transferWalkM,
              0,
            ),
            transferKind: TransferKind.repeatedStop,
            walkSEstimated: true,
            walkMEstimated: true,
          ),
        );
      }
      if (svc.isLoop && stops.length > 2) {
        ride(stops.length - 1, 0, forward: true);
        ride(0, stops.length - 1, forward: false);
      }
    }

    // through-running: same train continues into another service
    final byId = {for (final s in services) s.id: s};
    for (final svc in services) {
      final other = byId[svc.throughServiceOf];
      if (other == null) continue;
      final a = visitOf[svc.id]!;
      final b = visitOf[other.id]!;
      if (a.isEmpty || b.isEmpty) continue;
      for (final i in {0, a.length - 1}) {
        for (final j in {0, b.length - 1}) {
          if (a[i] < 0 || b[j] < 0) continue;
          if (_visits[a[i]].station != _visits[b[j]].station) continue;
          for (final (x, y) in [(a[i], b[j]), (b[j], a[i])]) {
            add(
              _Arc(
                _Kind.through,
                _rode(x),
                _rode(y),
                _Cost.zero,
                transferKind: TransferKind.throughRunning,
              ),
            );
          }
        }
      }
    }

    // transfers
    final rows = <String, Transfer>{};
    for (final t in snapshot.transfers) {
      rows.putIfAbsent('${t.stationId}|${t.fromLine}|${t.toLine}', () => t);
    }
    for (var s = 0; s < _stationIds.length; s++) {
      final here = _visitsAt[s];
      for (final a in here) {
        for (final b in here) {
          if (a == b) continue;
          final va = _visits[a];
          final vb = _visits[b];
          TransferKind kind;
          Transfer? row;
          if (va.line.id != vb.line.id) {
            row = rows['${va.station}|${va.line.id}|${vb.line.id}'];
            if (row == null) continue; // no interchange in the dataset
            kind = TransferKind.lineChange;
          } else if (va.service.id == vb.service.id) {
            kind = TransferKind.repeatedStop;
          } else {
            kind = TransferKind.sameLineChange;
          }
          final sEst = row?.walkS == null;
          final mEst = row?.walkM == null;
          final walkS = row?.walkS ?? model.transferWalkS;
          final walkM = row?.walkM ?? model.transferWalkM;
          add(
            _Arc(
              _Kind.transfer,
              _rode(a),
              b,
              _Cost(walkS + model.boardWaitS, 1, walkM, 0),
              transferKind: kind,
              row: row,
              walkSEstimated: sEst,
              walkMEstimated: mEst,
            ),
          );
        }
      }
      // board / alight
      for (final v in here) {
        add(
          _Arc(
            _Kind.board,
            _depart(s),
            v,
            _Cost(model.boardWaitS, 0, 0, 0),
          ),
        );
        add(_Arc(_Kind.alight, _rode(v), _arrive(s), _Cost.zero));
      }
    }

    // out-of-system walks (one row, usable both ways: ADR-025)
    final links = [...snapshot.walkLinks]..sort((a, b) => a.id.compareTo(b.id));
    for (final w in links) {
      final a = _stationIndex[w.fromStation];
      final b = _stationIndex[w.toStation];
      if (a == null || b == null) continue;
      for (final (x, y) in [(a, b), (b, a)]) {
        add(
          _Arc(
            _Kind.walk,
            _arrive(x),
            _depart(y),
            _Cost(w.walkS, 1, w.walkM, 0),
            link: w,
            linkFrom: _stationIds[x],
            linkTo: _stationIds[y],
          ),
        );
      }
    }
  }

  /// Best route(s) between two stations: one per profile, identical routes
  /// merged and tagged with every profile they win.
  RouteResult plan(
    String fromId,
    String toId, {
    FareRequest fareRequest = const FareRequest(),
  }) {
    for (final id in [fromId, toId]) {
      if (snapshot.station(id) == null) {
        return RouteResult(RouteStatus.unknownStation, detail: id);
      }
    }
    if (fromId == toId) return const RouteResult(RouteStatus.sameStation);
    for (final id in [fromId, toId]) {
      final i = _stationIndex[id];
      if (i == null || _visitsAt[i].isEmpty) {
        return RouteResult(RouteStatus.notServed, detail: id);
      }
    }
    final from = _stationIndex[fromId]!;
    final to = _stationIndex[toId]!;

    final found = <RoutingProfile, (Itinerary, _Cost)>{};
    for (final p in RoutingProfile.values) {
      final r = _search(from, to, p);
      if (r != null) found[p] = r;
    }
    if (found.isEmpty) {
      return RouteResult(RouteStatus.noRoute, detail: '$fromId>$toId');
    }
    final fastest = found[RoutingProfile.fastest]!.$1.totalTimeS;
    final limit = fastest * config.detourFactor + config.detourSlackS;
    final bySignature = <String, Itinerary>{};
    for (final p in RoutingProfile.values) {
      final r = found[p];
      if (r == null) continue;
      if (p != RoutingProfile.fastest && r.$1.totalTimeS > limit) continue;
      final sig = r.$1.signature;
      final prior = bySignature[sig];
      bySignature[sig] = prior == null
          ? r.$1.withProfiles([p])
          : prior.withProfiles([...prior.profiles, p]);
    }
    final list = bySignature.values.take(config.maxAlternatives).toList();
    return RouteResult(
      RouteStatus.ok,
      itineraries: [for (final i in list) _finish(i, fareRequest)],
    );
  }

  Itinerary _finish(Itinerary it, FareRequest request) {
    final extra = <RouteWarning>[];
    final tickets = ticketSegments(it.legs);
    if (tickets.length > 1) {
      extra.add(const RouteWarning(RouteWarningCode.separateTicket));
    }
    final quote = fareEngine?.quote(it.legs, request);
    if (quote == null) return it.withFare(const FareQuote.none(), extra);
    return it.withFare(quote, extra);
  }

  (Itinerary, _Cost)? _search(int from, int to, RoutingProfile profile) {
    final order = _order[profile]!;
    final n = _adj.length;
    final dist = List<_Cost?>.filled(n, null);
    final prev = List<_Arc?>.filled(n, null);
    final done = List<bool>.filled(n, false);
    final heap = MinHeap<(_Cost, int)>((a, b) => _compare(a.$1, b.$1, order));
    final start = _depart(from);
    dist[start] = _Cost.zero;
    heap.add((_Cost.zero, start));
    while (heap.isNotEmpty) {
      final (c, u) = heap.removeFirst();
      if (done[u]) continue;
      done[u] = true;
      for (final arc in _adj[u]) {
        final nc = c + arc.cost;
        final old = dist[arc.to];
        if (old == null || _compare(nc, old, order) < 0) {
          dist[arc.to] = nc;
          prev[arc.to] = arc;
          heap.add((nc, arc.to));
        }
      }
    }
    // A trip ends by alighting at the destination, or by a walk-link that
    // lands on it.
    var target = -1;
    for (final cand in [_arrive(to), _depart(to)]) {
      final d = dist[cand];
      if (d == null) continue;
      if (target < 0 || _compare(d, dist[target]!, order) < 0) target = cand;
    }
    if (target < 0) return null;
    final arcs = <_Arc>[];
    for (var node = target; node != start;) {
      final a = prev[node]!;
      arcs.add(a);
      node = a.from;
    }
    return (_toItinerary(arcs.reversed.toList(), profile), dist[target]!);
  }

  Itinerary _toItinerary(List<_Arc> arcs, RoutingProfile profile) {
    final legs = <Leg>[];
    final assumptions = <String>{};
    final warnings = <RouteWarning>[];

    LineService? service;
    Line? line;
    var stations = <String>[];
    var rideS = 0;
    var distanceM = 0;
    var wait = 0;
    var estimated = false;
    var forward = true;
    var prov = <Provenance>[];

    void begin(_Visit v, int waitS) {
      service = v.service;
      line = v.line;
      stations = [v.station];
      rideS = 0;
      distanceM = 0;
      wait = waitS;
      estimated = false;
      forward = true;
      prov = [];
    }

    void flush() {
      final svc = service;
      if (svc == null) return;
      final all = _stopsByService[svc.id]!;
      if (wait > 0) assumptions.add(Assumption.boardingWait);
      if (estimated) assumptions.add(Assumption.rideTimeEstimated);
      legs.add(
        RideLeg(
          serviceId: svc.id,
          lineId: line!.id,
          operatorId: line!.operatorId,
          stationIds: stations,
          rideS: rideS,
          distanceM: distanceM,
          waitS: wait,
          rideEstimated: estimated,
          provenance: prov,
          // A loop, or a ring that revisits a station, has no reliable
          // "towards" terminal in the data, so none is claimed.
          directionTerminalId:
              svc.isLoop || all.isEmpty || all.toSet().length != all.length
              ? null
              : (forward ? all.last : all.first),
        ),
      );
      service = null;
    }

    for (final a in arcs) {
      switch (a.kind) {
        case _Kind.board:
          begin(_visits[_v(a.to)], a.cost.time);
        case _Kind.ride:
          stations.add(_visits[_v(a.to)].station);
          rideS += a.cost.time;
          distanceM += a.edge!.distanceM;
          estimated = estimated || a.rideEstimated;
          forward = a.forward;
          final p = a.edge!.provenance;
          if (!prov.any(
            (x) =>
                x.sourceId == p.sourceId &&
                x.confidence == p.confidence &&
                x.verifiedOn == p.verifiedOn,
          )) {
            prov.add(p);
          }
        case _Kind.transfer || _Kind.through:
          final fromV = _visits[_v(a.from)];
          final toV = _visits[_v(a.to)];
          flush();
          final through = a.kind == _Kind.through;
          final walkS = through ? 0 : a.cost.time - model.boardWaitS;
          final waitS = through ? 0 : model.boardWaitS;
          if (!through) {
            assumptions.add(Assumption.boardingWait);
            if (a.walkSEstimated) {
              assumptions.add(Assumption.transferWalkTimeEstimated);
            }
            if (a.walkMEstimated) {
              assumptions.add(Assumption.transferWalkDistanceEstimated);
            }
          }
          final est = !through && (a.walkSEstimated || a.walkMEstimated);
          legs.add(
            TransferLeg(
              kind: a.transferKind!,
              stationId: fromV.station,
              fromServiceId: fromV.service.id,
              toServiceId: toV.service.id,
              fromLineId: fromV.line.id,
              toLineId: toV.line.id,
              walkS: walkS,
              walkM: a.cost.walkM,
              waitS: waitS,
              walkEstimated: est,
              stepFree: a.row?.stepFree,
              notesEn: a.row?.notesEn,
              notesHi: a.row?.notesHi,
              provenance: a.row?.provenance,
            ),
          );
          if (est && a.transferKind != TransferKind.repeatedStop) {
            warnings.add(
              RouteWarning(
                RouteWarningCode.unverifiedTransfer,
                stationId: fromV.station,
                legIndex: legs.length - 1,
              ),
            );
          }
          if (a.transferKind == TransferKind.repeatedStop) {
            warnings.add(
              RouteWarning(
                RouteWarningCode.repeatedStopChange,
                stationId: fromV.station,
                legIndex: legs.length - 1,
              ),
            );
          }
          begin(toV, 0);
        case _Kind.alight:
          flush();
        case _Kind.walk:
          final w = a.link!;
          legs.add(
            WalkLeg(
              linkId: w.id,
              fromStationId: a.linkFrom!,
              toStationId: a.linkTo!,
              walkS: w.walkS,
              walkM: w.walkM,
              requiresExit: w.requiresExit,
              stepFree: w.stepFree,
              provenance: w.provenance,
            ),
          );
      }
    }
    flush();

    var time = 0;
    var changes = 0;
    var stops = 0;
    var walk = 0;
    for (final l in legs) {
      time += l.durationS;
      switch (l) {
        case RideLeg():
          stops += l.stopCount;
        case TransferLeg():
          if (l.kind != TransferKind.throughRunning) {
            changes++;
            walk += l.walkM;
          }
        case WalkLeg():
          changes++;
          walk += l.walkM;
      }
    }
    return Itinerary(
      profiles: [profile],
      legs: legs,
      totalTimeS: time,
      changes: changes,
      stops: stops,
      walkM: walk,
      assumptions: assumptions.toList()..sort(),
      timeModelId: model.id,
      warnings: warnings,
    );
  }

  /// Groups of stations that can reach each other under the routing rules,
  /// largest first. More than one group means the network (or the data) is
  /// disconnected: routes between groups yield [RouteStatus.noRoute].
  List<List<String>> stationComponents() {
    final parent = List<int>.generate(_stationIds.length, (i) => i);
    int find(int x) {
      var r = x;
      while (parent[r] != r) {
        r = parent[r];
      }
      return r;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra == rb) return;
      if (ra < rb) {
        parent[rb] = ra;
      } else {
        parent[ra] = rb;
      }
    }

    int stationOf(int node) {
      if (node < 2 * _visitCount) return _visits[_v(node)].stationIndex;
      return (node - 2 * _visitCount) % _stationIds.length;
    }

    for (final arcs in _adj) {
      for (final a in arcs) {
        if (a.kind == _Kind.board || a.kind == _Kind.alight) continue;
        union(stationOf(a.from), stationOf(a.to));
      }
    }
    final groups = <int, List<String>>{};
    for (var s = 0; s < _stationIds.length; s++) {
      if (_visitsAt[s].isEmpty) continue;
      groups.putIfAbsent(find(s), () => []).add(_stationIds[s]);
    }
    return groups.values.toList()..sort((a, b) {
      final c = b.length.compareTo(a.length);
      return c != 0 ? c : a.first.compareTo(b.first);
    });
  }
}
