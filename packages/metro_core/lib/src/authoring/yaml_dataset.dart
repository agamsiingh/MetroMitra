import 'dart:io';

import 'package:metro_core/src/dataset/schema.dart';
import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/fare.dart';
import 'package:metro_core/src/model/network.dart';
import 'package:metro_core/src/model/provenance.dart';
import 'package:metro_core/src/model/snapshot.dart';
import 'package:metro_core/src/model/station_facts.dart';
import 'package:yaml/yaml.dart';

/// Thrown for malformed authoring YAML (unknown key, missing field, bad type).
/// The message carries the path of the offending node.
class AuthoringException extends FormatException {
  AuthoringException(super.message);
}

/// Parses the authoring format (`dataset.yaml`, see data/fixtures/mini_network)
/// into a [MetroSnapshot]. Strict: unknown keys are errors so typos cannot
/// silently drop facts. It only *parses*; semantic checks are in
/// `validateSnapshot`.
///
/// Derived on load (marked by the provenance given in the file):
/// - `station_line` rows from service stops,
/// - directed `edge` rows from `next_travel_s` on consecutive stops.
abstract final class YamlDatasetLoader {
  static MetroSnapshot loadFile(String path) =>
      parse(File(path).readAsStringSync(), origin: path);

  static MetroSnapshot parse(String text, {String origin = 'dataset'}) {
    final Object? doc;
    try {
      doc = loadYaml(text);
    } on YamlException catch (e) {
      throw AuthoringException('$origin: ${e.message}');
    }
    if (doc is! YamlMap) {
      throw AuthoringException('$origin: top level must be a map');
    }
    final all = <_Obj>[];
    final snapshot = _build(_Obj(doc, origin, all));
    // Every key of every node must have been consumed: typos are errors.
    for (final o in all) {
      o._checkAllKeysUsed();
    }
    return snapshot;
  }

  static MetroSnapshot _build(_Obj root) {
    final meta = {
      for (final e in root.map('meta').entries) e.key: e.value,
    };
    // schema_version is owned by the code, but a file may state it so that an
    // incompatible authoring file is caught by validation, not silently fixed.
    meta.putIfAbsent(MetaKeys.schemaVersion, () => '$currentSchemaVersion');

    final sources = [
      for (final o in root.list('sources'))
        Source(
          id: o.str('id'),
          name: o.str('name'),
          url: o.optStr('url'),
          license: o.str('license'),
          retrievedAt: o.optStr('retrieved_at'),
          notes: o.optStr('notes'),
        ),
    ];

    final operators = <Operator>[];
    final fareSystems = <FareSystem>[];
    final slabs = <FareSlab>[];
    final discounts = <FareDiscount>[];
    final overrides = <FareOverride>[];
    final operatorFare = <String, String>{};
    for (final o in root.list('fare_systems')) {
      final id = o.str('id');
      final op = o.str('operator');
      operatorFare[op] = id;
      fareSystems.add(
        FareSystem(
          id: id,
          operatorId: op,
          currency: o.str('currency'),
          effectiveFrom: o.str('effective_from'),
          sourceId: o.str('source'),
        ),
      );
      for (final sl in o.list('slabs')) {
        slabs.add(
          FareSlab(
            fareSystemId: id,
            dayType: DayType.parse(sl.str('day_type')),
            minKm: sl.integer('min_km'),
            maxKm: sl.optInt('max_km'),
            amountPaise: sl.integer('amount_paise'),
          ),
        );
      }
      for (final d in o.list('discounts')) {
        discounts.add(
          FareDiscount(
            fareSystemId: id,
            media: FareMedia.parse(d.str('media')),
            kind: FareDiscountKind.parse(d.str('kind')),
            percent: d.integer('percent'),
            windowsJson: d.optStr('windows_json'),
          ),
        );
      }
      for (final ov in o.list('overrides')) {
        overrides.add(
          FareOverride(
            fareSystemId: id,
            fromStation: ov.str('from'),
            toStation: ov.str('to'),
            dayType: DayType.parse(ov.str('day_type')),
            amountPaise: ov.integer('amount_paise'),
            sourceId: ov.str('source'),
            verifiedOn: ov.str('verified_on'),
          ),
        );
      }
    }
    for (final o in root.list('operators')) {
      final id = o.str('id');
      operators.add(
        Operator(
          id: id,
          nameEn: o.str('name_en'),
          nameHi: o.optStr('name_hi'),
          // Missing fare system is reported by validation, not a parse error.
          fareSystemId: o.optStr('fare_system') ?? operatorFare[id],
        ),
      );
    }

    final lines = <Line>[];
    final services = <LineService>[];
    final stops = <ServiceStop>[];
    final stationLines = <StationLine>[];
    final edges = <Edge>[];
    for (final l in root.list('lines')) {
      final lineId = l.str('id');
      lines.add(
        Line(
          id: lineId,
          operatorId: l.str('operator'),
          nameEn: l.str('name_en'),
          nameHi: l.optStr('name_hi'),
          shortName: l.optStr('short_name'),
          colorHex: l.str('color'),
          textColorHex: l.str('text_color'),
          sort: l.integer('sort'),
          status: OperatingStatus.parse(l.str('status')),
        ),
      );
      for (final sv in l.list('services')) {
        final svcId = sv.str('id');
        services.add(
          LineService(
            id: svcId,
            lineId: lineId,
            name: sv.str('name'),
            isLoop: sv.optBool('is_loop') ?? false,
            throughServiceOf: sv.optStr('through_service_of'),
          ),
        );
        final edgeProv = sv.has('edge_provenance')
            ? _prov(sv.obj('edge_provenance'))
            : null;
        final list = sv.list('stops');
        for (var i = 0; i < list.length; i++) {
          final st = list[i];
          final station = st.str('station');
          stops.add(
            ServiceStop(
              serviceId: svcId,
              seq: i,
              stationId: station,
              distFromStartM: st.integer('dist_m'),
            ),
          );
          final code = st.optStr('code');
          if (!stationLines.any(
            (x) => x.stationId == station && x.lineId == lineId,
          )) {
            stationLines.add(
              StationLine(
                stationId: station,
                lineId: lineId,
                stationCode: code,
              ),
            );
          }
          final next = st.optInt('next_travel_s');
          if (next != null) {
            if (i + 1 >= list.length) {
              throw AuthoringException(
                '${st.path}: next_travel_s on the last stop',
              );
            }
            if (edgeProv == null) {
              throw AuthoringException(
                '${sv.path}: next_travel_s needs edge_provenance',
              );
            }
            final to = list[i + 1];
            final toStation = to.str('station');
            final dist = to.integer('dist_m') - st.integer('dist_m');
            edges
              ..add(
                Edge(
                  id: '$svcId:$station>$toStation',
                  serviceId: svcId,
                  fromStation: station,
                  toStation: toStation,
                  travelS: next,
                  distanceM: dist,
                  provenance: edgeProv,
                ),
              )
              ..add(
                Edge(
                  id: '$svcId:$toStation>$station',
                  serviceId: svcId,
                  fromStation: toStation,
                  toStation: station,
                  travelS: next,
                  distanceM: dist,
                  provenance: edgeProv,
                ),
              );
          }
        }
      }
    }

    final stations = <Station>[];
    final names = <StationName>[];
    final platforms = <Platform>[];
    final gates = <Gate>[];
    final landmarks = <GateLandmark>[];
    final facilities = <Facility>[];
    final accessibility = <Accessibility>[];
    for (final s in root.list('stations')) {
      final id = s.str('id');
      final provenance = _prov(s.obj('provenance'));
      final nm = s.obj('names');
      final en = nm.str('en');
      final hi = nm.optStr('hi');
      stations.add(
        Station(
          id: id,
          nameEn: en,
          nameHi: hi,
          lat: s.number('lat'),
          lng: s.number('lng'),
          popularity: s.optInt('popularity') ?? 0,
          status: OperatingStatus.parse(s.str('status')),
          openedOn: s.optStr('opened_on'),
          mapX: s.optNumber('map_x'),
          mapY: s.optNumber('map_y'),
          provenance: provenance,
        ),
      );
      names.add(
        StationName(
          stationId: id,
          text: en,
          lang: 'en',
          kind: NameKind.official,
        ),
      );
      if (hi != null) {
        names.add(
          StationName(
            stationId: id,
            text: hi,
            lang: 'hi',
            kind: NameKind.official,
          ),
        );
      }
      for (final a in s.list('aliases')) {
        names.add(
          StationName(
            stationId: id,
            text: a.str('text'),
            lang: a.str('lang'),
            kind: NameKind.parse(a.str('kind')),
          ),
        );
      }
      Provenance childProv(_Obj o) =>
          o.has('provenance') ? _prov(o.obj('provenance')) : provenance;
      for (final p in s.list('platforms')) {
        platforms.add(
          Platform(
            stationId: id,
            lineId: p.str('line'),
            number: p.str('number'),
            towardsStationId: p.optStr('towards'),
            serviceId: p.optStr('service'),
            notesEn: p.optStr('notes_en'),
            notesHi: p.optStr('notes_hi'),
            provenance: childProv(p),
          ),
        );
      }
      for (final g in s.list('gates')) {
        final number = g.integer('number');
        final gateId = '$id:g$number';
        gates.add(
          Gate(
            id: gateId,
            stationId: id,
            number: number,
            nameEn: g.optStr('name_en'),
            nameHi: g.optStr('name_hi'),
            lat: g.optNumber('lat'),
            lng: g.optNumber('lng'),
            isOpen: g.optBool('is_open'),
            hasLift: g.optBool('has_lift'),
            hasRamp: g.optBool('has_ramp'),
            hasEscalator: g.optBool('has_escalator'),
            isStepFree: g.optBool('is_step_free'),
            provenance: childProv(g),
          ),
        );
        for (final lm in g.list('landmarks')) {
          landmarks.add(
            GateLandmark(
              gateId: gateId,
              textEn: lm.str('text_en'),
              textHi: lm.optStr('text_hi'),
              kind: GateLandmarkKind.parse(lm.str('kind')),
            ),
          );
        }
      }
      for (final f in s.list('facilities')) {
        final gate = f.optInt('gate');
        facilities.add(
          Facility(
            stationId: id,
            type: FacilityType.parse(f.str('type')),
            gateId: gate == null ? null : '$id:g$gate',
            locationEn: f.optStr('location_en'),
            locationHi: f.optStr('location_hi'),
            provenance: childProv(f),
          ),
        );
      }
      if (s.has('accessibility')) {
        final a = s.obj('accessibility');
        accessibility.add(
          Accessibility(
            stationId: id,
            lifts: a.optInt('lifts'),
            escalators: a.optInt('escalators'),
            tactilePath: a.optBool('tactile_path'),
            wheelchairAvailable: a.optBool('wheelchair_available'),
            notesEn: a.optStr('notes_en'),
            notesHi: a.optStr('notes_hi'),
            provenance: childProv(a),
          ),
        );
      }
    }

    final transfers = [
      for (final t in root.list('transfers'))
        Transfer(
          stationId: t.str('station'),
          fromLine: t.str('from_line'),
          toLine: t.str('to_line'),
          walkM: t.optInt('walk_m'),
          walkS: t.optInt('walk_s'),
          stepFree: t.optBool('step_free'),
          notesEn: t.optStr('notes_en'),
          notesHi: t.optStr('notes_hi'),
          provenance: _prov(t.obj('provenance')),
        ),
    ];
    final walkLinks = [
      for (final w in root.list('walk_links'))
        WalkLink(
          id: w.str('id'),
          fromStation: w.str('from'),
          toStation: w.str('to'),
          walkM: w.integer('walk_m'),
          walkS: w.integer('walk_s'),
          requiresExit: w.boolean('requires_exit'),
          stepFree: w.optBool('step_free'),
          notesEn: w.optStr('notes_en'),
          notesHi: w.optStr('notes_hi'),
          provenance: _prov(w.obj('provenance')),
        ),
    ];
    final timings = [
      for (final t in root.list('timings'))
        Timing(
          serviceId: t.str('service'),
          stationId: t.str('station'),
          directionTerminalId: t.str('terminal'),
          dayType: DayType.parse(t.str('day_type')),
          firstDep: t.integer('first_dep'),
          lastDep: t.integer('last_dep'),
          provenance: _prov(t.obj('provenance')),
        ),
    ];

    return MetroSnapshot(
      meta: meta,
      sources: sources,
      operators: operators,
      lines: lines,
      services: services,
      serviceStops: stops,
      stations: stations,
      stationNames: names,
      stationLines: stationLines,
      edges: edges,
      transfers: transfers,
      walkLinks: walkLinks,
      platforms: platforms,
      gates: gates,
      gateLandmarks: landmarks,
      facilities: facilities,
      accessibility: accessibility,
      fareSystems: fareSystems,
      fareSlabs: slabs,
      fareDiscounts: discounts,
      fareOverrides: overrides,
      timings: timings,
    );
  }

  static Provenance _prov(_Obj o) {
    final p = Provenance(
      sourceId: o.str('source'),
      confidence: Confidence.parse(o.str('confidence')),
      verifiedOn: o.optStr('verified_on'),
    );
    return p;
  }
}

/// Typed, path-aware access to a YAML map that tracks which keys were read.
class _Obj {
  _Obj(this._m, this.path, this._all) {
    _all.add(this);
  }

  final YamlMap _m;
  final String path;
  final List<_Obj> _all;
  final Set<String> _used = {};

  bool has(String k) => _m.containsKey(k) && _m[k] != null;

  Object? _get(String k) {
    _used.add(k);
    return _m[k];
  }

  Never _bad(String k, String want) => throw AuthoringException(
    '$path.$k: expected $want, got ${_m[k].runtimeType}',
  );

  String str(String k) {
    final v = _get(k);
    if (v == null) throw AuthoringException('$path: missing "$k"');
    return v is String ? v : _scalarString(v, k);
  }

  String _scalarString(Object v, String k) =>
      v is num || v is bool ? '$v' : _bad(k, 'string');

  String? optStr(String k) {
    final v = _get(k);
    if (v == null) return null;
    return v is String ? v : _scalarString(v, k);
  }

  int integer(String k) {
    final v = _get(k);
    if (v == null) throw AuthoringException('$path: missing "$k"');
    return v is int ? v : _bad(k, 'integer');
  }

  int? optInt(String k) {
    final v = _get(k);
    if (v == null) return null;
    return v is int ? v : _bad(k, 'integer');
  }

  double number(String k) {
    final v = _get(k);
    if (v == null) throw AuthoringException('$path: missing "$k"');
    return v is num ? v.toDouble() : _bad(k, 'number');
  }

  double? optNumber(String k) {
    final v = _get(k);
    if (v == null) return null;
    return v is num ? v.toDouble() : _bad(k, 'number');
  }

  bool boolean(String k) {
    final v = _get(k);
    if (v == null) throw AuthoringException('$path: missing "$k"');
    return v is bool ? v : _bad(k, 'boolean');
  }

  bool? optBool(String k) {
    final v = _get(k);
    if (v == null) return null;
    return v is bool ? v : _bad(k, 'boolean');
  }

  /// Plain string map (used for `meta`).
  Map<String, String> map(String k) {
    final v = _get(k);
    if (v is! YamlMap) throw AuthoringException('$path: "$k" must be a map');
    return {for (final e in v.entries) '${e.key}': '${e.value}'};
  }

  _Obj obj(String k) {
    final v = _get(k);
    if (v is! YamlMap) throw AuthoringException('$path: "$k" must be a map');
    return _Obj(v, '$path.$k', _all);
  }

  List<_Obj> list(String k) {
    final v = _get(k);
    if (v == null) return const [];
    if (v is! YamlList) throw AuthoringException('$path: "$k" must be a list');
    return [
      for (var i = 0; i < v.length; i++)
        if (v[i] is YamlMap)
          _Obj(v[i] as YamlMap, '$path.$k[$i]', _all)
        else
          throw AuthoringException('$path.$k[$i]: must be a map'),
    ];
  }

  void _checkAllKeysUsed() {
    final unknown = _m.keys.map((e) => '$e').where((k) => !_used.contains(k));
    if (unknown.isNotEmpty) {
      throw AuthoringException('$path: unknown key(s) ${unknown.join(', ')}');
    }
  }
}
