import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

final _now = DateTime.utc(2026, 10, 5);

ValidationReport _validate(MetroSnapshot s) => validateSnapshot(s, now: _now);

Map<String, String> _meta(MetroSnapshot s, Map<String, String?> change) {
  final m = {...s.meta};
  change.forEach((k, v) => v == null ? m.remove(k) : m[k] = v);
  return m;
}

void main() {
  final base = loadFixture();

  group('valid fixture', () {
    final report = _validate(base);

    test('has no errors', () {
      expect(report.errors, isEmpty, reason: report.toString());
      expect(report.isValid, isTrue);
    });

    test('reports warnings for unverified/community data, never as errors', () {
      expect(report.hasWarning('community-gate'), isTrue);
      expect(report.hasWarning('community-platform'), isTrue);
      expect(report.hasWarning('missing-hindi-alias'), isTrue);
    });
  });

  /// One broken rule at a time: `code` must be reported as an error.
  final cases = <String, (MetroSnapshot Function(), String)>{
    // ---- schema / meta
    'schema version too new': (
      () => base.copyWith(meta: _meta(base, {'schema_version': '99'})),
      'schema-version',
    ),
    'schema version too old': (
      () => base.copyWith(meta: _meta(base, {'schema_version': '0'})),
      'schema-version',
    ),
    'schema version not a number': (
      () => base.copyWith(meta: _meta(base, {'schema_version': 'one'})),
      'schema-version',
    ),
    'missing meta key': (
      () => base.copyWith(meta: _meta(base, {'city': null})),
      'meta-missing',
    ),
    'bad dataset version': (
      () => base.copyWith(meta: _meta(base, {'dataset_version': 'v1'})),
      'dataset-version',
    ),
    'bad bbox': (
      () => base.copyWith(meta: _meta(base, {'bbox': '10,10,5,5'})),
      'bbox',
    ),
    // ---- unique ids
    'duplicate station id': (
      () => base.copyWith(stations: [...base.stations, base.stations.first]),
      'duplicate-id',
    ),
    'duplicate line id': (
      () => base.copyWith(lines: [...base.lines, base.lines.first]),
      'duplicate-id',
    ),
    'duplicate service id': (
      () => base.copyWith(services: [...base.services, base.services.first]),
      'duplicate-id',
    ),
    'duplicate edge id': (
      () => base.copyWith(edges: [...base.edges, base.edges.first]),
      'duplicate-id',
    ),
    'duplicate gate number': (
      () => base.copyWith(gates: [...base.gates, base.gates.first]),
      'duplicate-id',
    ),
    'duplicate station code on a line': (
      () => base.copyWith(
        stationLines: replaceWhere(
          base.stationLines,
          (x) => x.stationId == 'test-beta',
          (x) => StationLine(
            stationId: x.stationId,
            lineId: x.lineId,
            stationCode: 'R1',
          ),
        ),
      ),
      'duplicate-id',
    ),
    'id not a slug': (
      () => base.copyWith(
        stations: replaceWhere(
          base.stations,
          (s) => s.id == 'test-delta',
          (s) => stationWith(s, id: 'Test Delta'),
        ),
      ),
      'bad-id',
    ),
    'gate id does not match station and number': (
      () => base.copyWith(
        gates: replaceWhere(
          base.gates,
          (g) => g.id == 'test-beta:g1',
          (g) => Gate(
            id: 'test-beta:g7',
            stationId: g.stationId,
            number: g.number,
            provenance: g.provenance,
          ),
        ),
      ),
      'bad-id',
    ),
    // ---- references
    'edge to unknown station': (
      () => base.copyWith(
        edges: replaceWhere(
          base.edges,
          (e) => e == base.edges.first,
          (e) => edgeWith(e, to: 'ghost'),
        ),
      ),
      'missing-ref',
    ),
    'service stop at unknown station': (
      () => base.copyWith(
        serviceStops: replaceWhere(
          base.serviceStops,
          (s) => s.seq == 1 && s.serviceId == 'test-red-main',
          (s) => stopWith(s, stationId: 'ghost'),
        ),
      ),
      'missing-ref',
    ),
    'station_line to unknown line': (
      () => base.copyWith(
        stationLines: [
          ...base.stationLines,
          const StationLine(stationId: 'test-alpha', lineId: 'ghost'),
        ],
      ),
      'missing-ref',
    ),
    'line with unknown operator': (
      () => base.copyWith(
        lines: [
          ...base.lines,
          const Line(
            id: 'test-x',
            operatorId: 'ghost',
            nameEn: 'x',
            nameHi: 'x',
            colorHex: '#000000',
            textColorHex: '#FFFFFF',
            sort: 9,
            status: OperatingStatus.open,
          ),
        ],
      ),
      'missing-ref',
    ),
    'fact with unknown source': (
      () => base.copyWith(
        stations: replaceWhere(
          base.stations,
          (s) => s.id == 'test-delta',
          (s) => stationWith(
            s,
            provenance: const Provenance(
              sourceId: 'ghost',
              confidence: Confidence.community,
            ),
          ),
        ),
      ),
      'missing-ref',
    ),
    'gate landmark for unknown gate': (
      () => base.copyWith(
        gateLandmarks: [
          ...base.gateLandmarks,
          const GateLandmark(
            gateId: 'ghost:g1',
            textEn: 'x',
            kind: GateLandmarkKind.other,
          ),
        ],
      ),
      'missing-ref',
    ),
    'facility uses gate of another station': (
      () => base.copyWith(
        facilities: [
          ...base.facilities,
          const Facility(
            stationId: 'test-beta',
            type: FacilityType.atm,
            gateId: 'test-alpha:g1',
            provenance: prov,
          ),
        ],
      ),
      'gate-station-mismatch',
    ),
    // ---- orphans
    'orphan station': (
      () => base.copyWith(
        stations: [
          ...base.stations,
          stationWith(base.stations.first, id: 'test-lonely'),
        ],
      ),
      'orphan-station',
    ),
    'orphan line': (
      () => base.copyWith(
        lines: [
          ...base.lines,
          const Line(
            id: 'test-idle',
            operatorId: 'test-op-a',
            nameEn: 'TEST Idle',
            nameHi: 'x',
            colorHex: '#000000',
            textColorHex: '#FFFFFF',
            sort: 9,
            status: OperatingStatus.open,
          ),
        ],
      ),
      'orphan-line',
    ),
    'orphan service': (
      () => base.copyWith(
        services: [
          ...base.services,
          const LineService(id: 'test-empty', lineId: 'test-red', name: 'x'),
        ],
      ),
      'orphan-service',
    ),
    // ---- coordinates
    'latitude out of range': (
      () => base.copyWith(
        stations: replaceWhere(
          base.stations,
          (s) => s.id == 'test-delta',
          (s) => stationWith(s, lat: 91),
        ),
      ),
      'bad-coordinate',
    ),
    'NaN coordinate': (
      () => base.copyWith(
        stations: replaceWhere(
          base.stations,
          (s) => s.id == 'test-delta',
          (s) => stationWith(s, lng: double.nan),
        ),
      ),
      'bad-coordinate',
    ),
    'coordinate outside bbox': (
      () => base.copyWith(
        stations: replaceWhere(
          base.stations,
          (s) => s.id == 'test-delta',
          (s) => stationWith(s, lat: 19.07, lng: 72.87),
        ),
      ),
      'coordinate-outside-bbox',
    ),
    'gate with lat but no lng': (
      () => base.copyWith(
        gates: [
          ...base.gates,
          const Gate(
            id: 'test-delta:g1',
            stationId: 'test-delta',
            number: 1,
            lat: 28.6,
            provenance: prov,
          ),
        ],
      ),
      'bad-coordinate',
    ),
    'half a map position': (
      () => base.copyWith(
        stations: replaceWhere(
          base.stations,
          (s) => s.id == 'test-delta',
          (s) => stationWith(s, mapX: 1),
        ),
      ),
      'bad-map-position',
    ),
    // ---- names, colours
    'empty Hindi name': (
      () => base.copyWith(
        stations: replaceWhere(
          base.stations,
          (s) => s.id == 'test-delta',
          (s) => stationWith(s, nameHi: '  '),
        ),
      ),
      'empty-name',
    ),
    'line colour not hex': (
      () => base.copyWith(
        lines: replaceWhere(
          base.lines,
          (l) => l.id == 'test-red',
          (l) => Line(
            id: l.id,
            operatorId: l.operatorId,
            nameEn: l.nameEn,
            nameHi: l.nameHi,
            colorHex: 'red',
            textColorHex: l.textColorHex,
            sort: l.sort,
            status: l.status,
          ),
        ),
      ),
      'bad-colour',
    ),
    // ---- provenance
    'verified fact without verified_on': (
      () => base.copyWith(
        stations: replaceWhere(
          base.stations,
          (s) => s.id == 'test-delta',
          (s) => stationWith(
            s,
            provenance: const Provenance(
              sourceId: 'test-fixture',
              confidence: Confidence.verified,
            ),
          ),
        ),
      ),
      'missing-verified-on',
    ),
    'impossible verified_on date': (
      () => base.copyWith(
        stations: replaceWhere(
          base.stations,
          (s) => s.id == 'test-delta',
          (s) => stationWith(
            s,
            provenance: const Provenance(
              sourceId: 'test-fixture',
              confidence: Confidence.verified,
              verifiedOn: '2026-02-31',
            ),
          ),
        ),
      ),
      'bad-date',
    ),
    // ---- service stops
    'gap in stop sequence': (
      () => base.copyWith(
        serviceStops: replaceWhere(
          base.serviceStops,
          (s) => s.serviceId == 'test-green-main' && s.seq == 2,
          (s) => stopWith(s, seq: 5),
        ),
      ),
      'bad-seq',
    ),
    'distance not increasing': (
      () => base.copyWith(
        serviceStops: replaceWhere(
          base.serviceStops,
          (s) => s.serviceId == 'test-green-main' && s.seq == 2,
          (s) => stopWith(s, dist: 10),
        ),
      ),
      'bad-distance',
    ),
    // ---- edges / connections
    'missing reverse edge': (
      () => base.copyWith(
        edges: base.edges
            .where((e) => e.id != 'test-red-main:test-beta>test-alpha')
            .toList(),
      ),
      'missing-edge',
    ),
    'edge between non-consecutive stops': (
      () => base.copyWith(
        edges: [
          ...base.edges,
          const Edge(
            id: 'skip',
            serviceId: 'test-red-main',
            fromStation: 'test-alpha',
            toStation: 'test-gamma',
            travelS: 200,
            distanceM: 2500,
            provenance: prov,
          ),
        ],
      ),
      'edge-not-adjacent',
    ),
    'edge to itself': (
      () => base.copyWith(
        edges: replaceWhere(
          base.edges,
          (e) => e == base.edges.first,
          (e) => edgeWith(e, to: e.fromStation),
        ),
      ),
      'bad-edge',
    ),
    'zero travel time': (
      () => base.copyWith(
        edges: replaceWhere(
          base.edges,
          (e) => e == base.edges.first,
          (e) => edgeWith(e, travelS: 0),
        ),
      ),
      'bad-edge',
    ),
    'negative distance': (
      () => base.copyWith(
        edges: replaceWhere(
          base.edges,
          (e) => e == base.edges.first,
          (e) => edgeWith(e, distanceM: -5),
        ),
      ),
      'bad-edge',
    ),
    'network split in two': (
      () => base.copyWith(
        edges: base.edges
            .where(
              (e) =>
                  !{'test-gamma', 'test-delta'}.containsAll({
                    e.fromStation,
                    e.toStation,
                  }) ||
                  e.serviceId != 'test-red-main',
            )
            .toList(),
      ),
      'disconnected-network',
    ),
    // ---- line relationships
    'service stop without station_line': (
      () => base.copyWith(
        stationLines: base.stationLines
            .where((x) => !(x.stationId == 'test-delta'))
            .toList(),
      ),
      'line-relationship',
    ),
    'station_line without any service stop': (
      () => base.copyWith(
        stationLines: [
          ...base.stationLines,
          const StationLine(stationId: 'test-alpha', lineId: 'test-blue'),
        ],
      ),
      'line-relationship',
    ),
    'interchange without transfer rows': (
      () => base.copyWith(transfers: const []),
      'missing-transfer',
    ),
    'transfer from a line to itself': (
      () => base.copyWith(
        transfers: [
          ...base.transfers,
          const Transfer(
            stationId: 'test-gamma',
            fromLine: 'test-red',
            toLine: 'test-red',
            walkM: 1,
            walkS: 1,
            provenance: prov,
          ),
        ],
      ),
      'bad-transfer',
    ),
    // ---- walk links
    'walk link to itself': (
      () => base.copyWith(
        walkLinks: [
          const WalkLink(
            id: 'loop',
            fromStation: 'test-alpha',
            toStation: 'test-alpha',
            walkM: 10,
            walkS: 10,
            requiresExit: true,
            provenance: prov,
          ),
        ],
      ),
      'bad-walk-link',
    ),
    'walk link with zero distance': (
      () => base.copyWith(
        walkLinks: [
          const WalkLink(
            id: 'zero',
            fromStation: 'test-alpha',
            toStation: 'test-beta',
            walkM: 0,
            walkS: 0,
            requiresExit: false,
            provenance: prov,
          ),
        ],
      ),
      'bad-walk-link',
    ),
    // ---- platforms
    'platform on a line that does not serve the station': (
      () => base.copyWith(
        platforms: [
          ...base.platforms,
          const Platform(
            stationId: 'test-alpha',
            lineId: 'test-blue',
            number: '1',
            provenance: prov,
          ),
        ],
      ),
      'bad-platform',
    ),
    'platform towards a station off the service': (
      () => base.copyWith(
        platforms: [
          const Platform(
            stationId: 'test-gamma',
            lineId: 'test-red',
            number: '9',
            towardsStationId: 'test-iota',
            serviceId: 'test-red-main',
            provenance: prov,
          ),
        ],
      ),
      'bad-platform',
    ),
    // ---- fares
    'no fare slabs at all for a system': (
      () => base.copyWith(
        fareSlabs: base.fareSlabs
            .where((x) => x.fareSystemId != 'test-fare-b')
            .toList(),
      ),
      'fare-slab-gap',
    ),
    'gap between fare slabs': (
      () => base.copyWith(
        fareSlabs: base.fareSlabs
            .where(
              (x) =>
                  !(x.fareSystemId == 'test-fare-a' &&
                      x.minKm == 2 &&
                      x.dayType == DayType.regular),
            )
            .toList(),
      ),
      'fare-slab-gap',
    ),
    'first fare slab not at 0 km': (
      () => base.copyWith(
        fareSlabs: base.fareSlabs
            .where(
              (x) =>
                  !(x.fareSystemId == 'test-fare-a' &&
                      x.minKm == 0 &&
                      x.dayType == DayType.regular),
            )
            .toList(),
      ),
      'fare-slab-gap',
    ),
    'last fare slab not open-ended': (
      () => base.copyWith(
        fareSlabs: replaceWhere(
          base.fareSlabs,
          (x) => x.fareSystemId == 'test-fare-b',
          (x) => FareSlab(
            fareSystemId: x.fareSystemId,
            dayType: x.dayType,
            minKm: x.minKm,
            maxKm: 50,
            amountPaise: x.amountPaise,
          ),
        ),
      ),
      'fare-slab-gap',
    ),
    'zero fare amount': (
      () => base.copyWith(
        fareSlabs: replaceWhere(
          base.fareSlabs,
          (x) => x.fareSystemId == 'test-fare-b',
          (x) => FareSlab(
            fareSystemId: x.fareSystemId,
            dayType: x.dayType,
            minKm: x.minKm,
            maxKm: x.maxKm,
            amountPaise: 0,
          ),
        ),
      ),
      'bad-fare',
    ),
    'discount over 100 percent': (
      () => base.copyWith(
        fareDiscounts: [
          ...base.fareDiscounts,
          const FareDiscount(
            fareSystemId: 'test-fare-b',
            media: FareMedia.token,
            kind: FareDiscountKind.base,
            percent: 150,
          ),
        ],
      ),
      'bad-fare',
    ),
    'off-peak discount without windows': (
      () => base.copyWith(
        fareDiscounts: [
          ...base.fareDiscounts,
          const FareDiscount(
            fareSystemId: 'test-fare-b',
            media: FareMedia.smartCard,
            kind: FareDiscountKind.offPeak,
            percent: 10,
          ),
        ],
      ),
      'bad-fare',
    ),
    'fare override for unknown station': (
      () => base.copyWith(
        fareOverrides: [
          const FareOverride(
            fareSystemId: 'test-fare-a',
            fromStation: 'test-alpha',
            toStation: 'ghost',
            dayType: DayType.regular,
            amountPaise: 100,
            sourceId: 'test-fixture',
            verifiedOn: '2026-10-01',
          ),
        ],
      ),
      'missing-ref',
    ),
    'fare override with zero amount': (
      () => base.copyWith(
        fareOverrides: [
          const FareOverride(
            fareSystemId: 'test-fare-a',
            fromStation: 'test-alpha',
            toStation: 'test-beta',
            dayType: DayType.regular,
            amountPaise: 0,
            sourceId: 'test-fixture',
            verifiedOn: '2026-10-01',
          ),
        ],
      ),
      'bad-fare',
    ),
    'operator without a fare system': (
      () => base.copyWith(
        operators: [
          ...base.operators.where((o) => o.id != 'test-op-b'),
          const Operator(
            id: 'test-op-b',
            nameEn: 'b',
            nameHi: 'b',
            fareSystemId: '',
          ),
        ],
      ),
      'missing-ref',
    ),
    // ---- timings
    'first departure after last': (
      () => base.copyWith(
        timings: [
          const Timing(
            serviceId: 'test-red-main',
            stationId: 'test-alpha',
            directionTerminalId: 'test-zeta',
            dayType: DayType.regular,
            firstDep: 900,
            lastDep: 800,
            provenance: prov,
          ),
        ],
      ),
      'bad-timing',
    ),
    'timing beyond 48 hours': (
      () => base.copyWith(
        timings: [
          const Timing(
            serviceId: 'test-red-main',
            stationId: 'test-alpha',
            directionTerminalId: 'test-zeta',
            dayType: DayType.regular,
            firstDep: 360,
            lastDep: 4000,
            provenance: prov,
          ),
        ],
      ),
      'bad-timing',
    ),
    'timing for a station not on the service': (
      () => base.copyWith(
        timings: [
          const Timing(
            serviceId: 'test-red-main',
            stationId: 'test-eta',
            directionTerminalId: 'test-zeta',
            dayType: DayType.regular,
            firstDep: 360,
            lastDep: 1380,
            provenance: prov,
          ),
        ],
      ),
      'bad-timing',
    ),
  };

  group('hard failures', () {
    cases.forEach((name, c) {
      test(name, () {
        final report = _validate(c.$1());
        expect(report.isValid, isFalse, reason: 'expected failure: $name');
        expect(
          report.hasError(c.$2),
          isTrue,
          reason: 'wanted ${c.$2}, got:\n$report',
        );
      });
    });
  });

  group('unknown data stays unknown (nullable fields)', () {
    MetroSnapshot unknown() => base.copyWith(
      stations: replaceWhere(
        base.stations,
        (s) => s.id == 'test-delta',
        (s) => Station(
          id: s.id,
          nameEn: s.nameEn,
          lat: s.lat,
          lng: s.lng,
          status: s.status,
          provenance: s.provenance,
        ),
      ),
    );

    test('missing Hindi name: error in release, warning in draft', () {
      expect(_validate(unknown()).hasError('missing-hindi-name'), isTrue);
      final d = validateSnapshot(
        unknown(),
        now: _now,
        mode: ValidationMode.draft,
      );
      expect(d.isValid, isTrue, reason: d.toString());
      expect(d.hasWarning('missing-hindi-name'), isTrue);
    });

    test('a BLANK Hindi name is an error in both modes', () {
      final s = base.copyWith(
        stations: replaceWhere(
          base.stations,
          (s) => s.id == 'test-delta',
          (s) => stationWith(s, nameHi: ' '),
        ),
      );
      expect(
        validateSnapshot(
          s,
          now: _now,
          mode: ValidationMode.draft,
        ).hasError('empty-name'),
        isTrue,
      );
    });

    test('unknown travel time, walk time and fare system are valid', () {
      final s = base.copyWith(
        edges: [
          for (final e in base.edges)
            Edge(
              id: e.id,
              serviceId: e.serviceId,
              fromStation: e.fromStation,
              toStation: e.toStation,
              distanceM: e.distanceM,
              provenance: e.provenance,
            ),
        ],
        transfers: [
          for (final t in base.transfers)
            Transfer(
              stationId: t.stationId,
              fromLine: t.fromLine,
              toLine: t.toLine,
              provenance: t.provenance,
            ),
        ],
        fareSystems: const [],
        fareSlabs: const [],
        fareDiscounts: const [],
        fareOverrides: const [],
        operators: [
          for (final o in base.operators)
            Operator(id: o.id, nameEn: o.nameEn, nameHi: o.nameHi),
        ],
      );
      final r = _validate(s);
      expect(r.errors, isEmpty, reason: r.toString());
    });

    test('a zero or negative travel time is still an error', () {
      final s = base.copyWith(
        edges: replaceWhere(
          base.edges,
          (e) => e == base.edges.first,
          (e) => edgeWith(e, travelS: -1),
        ),
      );
      expect(_validate(s).hasError('bad-edge'), isTrue);
    });

    test('disconnected network and missing transfers only warn in draft', () {
      final s = base.copyWith(
        transfers: const [],
        edges: base.edges
            .where(
              (e) =>
                  !({
                        'test-gamma',
                        'test-delta',
                      }.containsAll({e.fromStation, e.toStation}) &&
                      e.serviceId == 'test-red-main'),
            )
            .toList(),
      );
      final d = validateSnapshot(s, now: _now, mode: ValidationMode.draft);
      expect(d.hasWarning('missing-transfer'), isTrue);
      expect(d.hasWarning('disconnected-network'), isTrue);
      expect(_validate(s).hasError('disconnected-network'), isTrue);
    });
  });

  group('draft stage and origin rows', () {
    test('a dataset marked draft is rejected by release rules only', () {
      final s = base.copyWith(meta: {...base.meta, 'stage': 'draft'});
      expect(_validate(s).hasError('draft-dataset'), isTrue);
      expect(
        validateSnapshot(s, now: _now, mode: ValidationMode.draft).isValid,
        isTrue,
      );
    });

    test('an unknown stage value is an error', () {
      final s = base.copyWith(meta: {...base.meta, 'stage': 'beta'});
      expect(
        validateSnapshot(
          s,
          now: _now,
          mode: ValidationMode.draft,
        ).hasError('bad-stage'),
        isTrue,
      );
    });

    Origin o({
      String entity = 'station',
      String id = 'test-alpha',
      String source = 'test-fixture',
      String field = 'record',
    }) => Origin(
      entity: entity,
      entityId: id,
      field: field,
      sourceId: source,
      status: OriginStatus.imported,
    );

    test('valid origin rows pass', () {
      final r = _validate(
        base.copyWith(
          origins: [
            o(),
            o(entity: 'line', id: 'test-red', field: 'color_hex'),
          ],
        ),
      );
      expect(r.errors, isEmpty);
    });

    test('origin for an unknown entity row, source or kind', () {
      expect(
        _validate(
          base.copyWith(origins: [o(id: 'ghost')]),
        ).hasError('missing-ref'),
        isTrue,
      );
      expect(
        _validate(
          base.copyWith(origins: [o(source: 'ghost')]),
        ).hasError('missing-ref'),
        isTrue,
      );
      expect(
        _validate(
          base.copyWith(origins: [o(entity: 'planet')]),
        ).hasError('bad-origin'),
        isTrue,
      );
    });

    test('duplicate origin rows', () {
      expect(
        _validate(base.copyWith(origins: [o(), o()])).hasError('duplicate-id'),
        isTrue,
      );
    });
  });

  group('warnings never block', () {
    test('stale verification is a warning', () {
      final s = base.copyWith(
        stations: replaceWhere(
          base.stations,
          (s) => s.id == 'test-delta',
          (s) => stationWith(
            s,
            provenance: const Provenance(
              sourceId: 'test-fixture',
              confidence: Confidence.verified,
              verifiedOn: '2024-01-01',
            ),
          ),
        ),
      );
      final r = _validate(s);
      expect(r.isValid, isTrue, reason: r.toString());
      expect(r.hasWarning('stale-verification'), isTrue);
    });

    test(
      'a route that passes a station twice is a warning (loop with spur)',
      () {
        final s = base.copyWith(
          serviceStops: replaceWhere(
            base.serviceStops,
            (x) => x.serviceId == 'test-green-main' && x.seq == 2,
            (x) => stopWith(x, stationId: 'test-kappa'),
          ),
        );
        final r = _validate(s);
        expect(r.hasWarning('repeated-stop'), isTrue);
        expect(r.hasError('repeated-stop'), isFalse);
      },
    );

    test('unused source is a warning', () {
      final s = base.copyWith(
        sources: [
          ...base.sources,
          const Source(id: 'spare', name: 'spare', license: 'CC0'),
        ],
      );
      final r = _validate(s);
      expect(r.isValid, isTrue);
      expect(r.hasWarning('unused-source'), isTrue);
    });
  });

  test('every hard-failure case breaks only validity, not the loader', () {
    // Sanity: the unmodified fixture stays valid after the cases ran.
    expect(_validate(base).isValid, isTrue);
  });
}
