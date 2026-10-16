import 'dart:convert';

import 'package:metro_core/src/fare/fare_quote.dart';
import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/fare.dart';
import 'package:metro_core/src/model/snapshot.dart';
import 'package:metro_core/src/routing/itinerary.dart';
import 'package:metro_core/src/util/min_heap.dart';

/// Splits an itinerary into tickets: a new ticket starts when the operator
/// changes or the rider leaves the paid area (`walk_link.requires_exit`).
List<List<RideLeg>> ticketSegments(List<Leg> legs) {
  final groups = <List<RideLeg>>[];
  var current = <RideLeg>[];
  void close() {
    if (current.isNotEmpty) groups.add(current);
    current = <RideLeg>[];
  }

  for (final leg in legs) {
    switch (leg) {
      case RideLeg():
        if (current.isNotEmpty && current.last.operatorId != leg.operatorId) {
          close();
        }
        current.add(leg);
      case WalkLeg():
        if (leg.requiresExit) close();
      case TransferLeg():
        break;
    }
  }
  close();
  return groups;
}

/// Computes fares only from fare data in the dataset (docs/routing.md "Fare").
///
/// Rules, in order, per ticket:
///  1. a `fare_override` for the exact (from, to, day type) pair, else
///  2. the `fare_slab` for the shortest distance between the two stations
///     *inside that operator's network* (sum of edge distances).
/// Then discounts of the requested media are applied (percentages of the
/// listed fare are added together, capped at 100, result rounded half up to
/// whole paise). No dataset fare data => [FareQuote] says so; nothing is
/// invented and no default fare exists.
class FareEngine {
  FareEngine(this.snapshot) {
    for (final l in snapshot.lines) {
      _operatorOfLine[l.id] = l.operatorId;
    }
  }

  final MetroSnapshot snapshot;
  final _operatorOfLine = <String, String>{};
  final _graphs = <String, Map<String, List<(String, int)>>>{};

  FareQuote quote(List<Leg> legs, [FareRequest request = const FareRequest()]) {
    final groups = ticketSegments(legs);
    if (groups.isEmpty) return const FareQuote.none();
    final segments = [
      for (final g in groups)
        _segment(
          g.first.operatorId,
          g.first.fromStationId,
          g.last.toStationId,
          request,
        ),
    ];
    final priced = segments.where((s) => s.priced).length;
    final status = priced == segments.length
        ? FareStatus.available
        : priced == 0
        ? FareStatus.unavailable
        : FareStatus.partial;
    Confidence? weakest;
    String? currency;
    var total = 0;
    for (final s in segments) {
      if (s.confidence != null &&
          (weakest == null || s.confidence!.index > weakest.index)) {
        weakest = s.confidence;
      }
      total += s.amountPaise ?? 0;
      final sys = s.fareSystemId == null
          ? null
          : snapshot.fareSystems.where((f) => f.id == s.fareSystemId);
      currency ??= sys == null || sys.isEmpty ? null : sys.first.currency;
    }
    return FareQuote(
      status: status,
      segments: segments,
      separateTicket: segments.length > 1,
      totalPaise: status == FareStatus.available ? total : null,
      currency: status == FareStatus.available ? currency : null,
      confidence: weakest,
    );
  }

  FareSegment _segment(
    String operatorId,
    String from,
    String to,
    FareRequest req,
  ) {
    FareSegment gap(FareGap g, {String? system, int? distanceM}) => FareSegment(
      operatorId: operatorId,
      fromStationId: from,
      toStationId: to,
      fareSystemId: system,
      distanceM: distanceM,
      gap: g,
    );

    final systemId = snapshot.operators
        .where((o) => o.id == operatorId)
        .map((o) => o.fareSystemId)
        .firstOrNull;
    final system = systemId == null
        ? null
        : snapshot.fareSystems.where((f) => f.id == systemId).firstOrNull;
    if (system == null) return gap(FareGap.noFareSystem);

    final override = snapshot.fareOverrides
        .where(
          (o) =>
              o.fareSystemId == system.id &&
              o.fromStation == from &&
              o.toStation == to &&
              o.dayType == req.dayType,
        )
        .firstOrNull;

    final distanceM = _distanceM(operatorId, from, to);
    int listed;
    FareBasis basis;
    Confidence confidence;
    String sourceId;
    if (override != null) {
      listed = override.amountPaise;
      basis = FareBasis.override;
      confidence = Confidence.verified;
      sourceId = override.sourceId;
    } else {
      if (distanceM == null) {
        return gap(FareGap.noDistance, system: system.id);
      }
      final slab = _slab(system.id, req.dayType, distanceM);
      if (slab == null) {
        return gap(FareGap.noSlab, system: system.id, distanceM: distanceM);
      }
      listed = slab.amountPaise;
      basis = FareBasis.slab;
      confidence = Confidence.derived;
      sourceId = system.sourceId;
    }

    final notes = <String>[];
    var percent = 0;
    final applied = <String>[];
    for (final d in snapshot.fareDiscounts) {
      if (d.fareSystemId != system.id) continue;
      if (d.media != req.media && d.media != FareMedia.any) continue;
      if (d.kind == FareDiscountKind.offPeak) {
        if (req.minuteOfDay == null) {
          notes.add('off-peak discount not applied: time unknown');
          continue;
        }
        final inside = _inWindow(d, req);
        if (inside == null) {
          return gap(
            FareGap.badDiscountWindow,
            system: system.id,
            distanceM: distanceM,
          );
        }
        if (!inside) continue;
      }
      percent += d.percent;
      applied.add('${d.kind.wire}:${d.percent}');
    }
    percent = percent.clamp(0, 100);
    final amount = (listed * (100 - percent) + 50) ~/ 100;
    return FareSegment(
      operatorId: operatorId,
      fromStationId: from,
      toStationId: to,
      fareSystemId: system.id,
      distanceM: distanceM,
      basis: basis,
      listedPaise: listed,
      amountPaise: amount,
      discountPercent: percent,
      appliedDiscounts: applied,
      confidence: confidence,
      sourceId: sourceId,
      notes: notes,
    );
  }

  FareSlab? _slab(String systemId, DayType day, int distanceM) {
    for (final s in snapshot.fareSlabs) {
      if (s.fareSystemId != systemId || s.dayType != day) continue;
      if (distanceM >= s.minKm * 1000 &&
          (s.maxKm == null || distanceM < s.maxKm! * 1000)) {
        return s;
      }
    }
    return null;
  }

  /// null = the window could not be read.
  bool? _inWindow(FareDiscount d, FareRequest req) {
    try {
      final windows = jsonDecode(d.windowsJson ?? '[]') as List<Object?>;
      for (final w in windows) {
        final m = w! as Map<String, Object?>;
        final days = m['days'];
        final from = m['from']! as int;
        final to = m['to']! as int;
        final dayOk = days == 'all' || days == req.dayType.wire;
        if (dayOk && req.minuteOfDay! >= from && req.minuteOfDay! < to) {
          return true;
        }
      }
      return false;
    } on Object {
      return null;
    }
  }

  Map<String, List<(String, int)>> _graph(String operatorId) =>
      _graphs.putIfAbsent(operatorId, () {
        final g = <String, List<(String, int)>>{};
        for (final e in snapshot.edges) {
          final lineId = snapshot.service(e.serviceId)?.lineId;
          if (lineId == null || _operatorOfLine[lineId] != operatorId) continue;
          g.putIfAbsent(e.fromStation, () => []).add((
            e.toStation,
            e.distanceM,
          ));
        }
        return g;
      });

  /// Shortest distance between two stations using only [operatorId]'s edges.
  int? _distanceM(String operatorId, String from, String to) {
    final g = _graph(operatorId);
    final dist = <String, int>{from: 0};
    final heap = MinHeap<(int, String)>((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    })..add((0, from));
    while (heap.isNotEmpty) {
      final (d, u) = heap.removeFirst();
      if (d > (dist[u] ?? d)) continue;
      if (u == to) return d;
      for (final (v, w) in g[u] ?? const <(String, int)>[]) {
        final nd = d + w;
        if (nd < (dist[v] ?? 1 << 62)) {
          dist[v] = nd;
          heap.add((nd, v));
        }
      }
    }
    return null;
  }
}
