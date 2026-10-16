import 'package:metro_core/src/dataset/schema.dart';
import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/provenance.dart';
import 'package:metro_core/src/model/snapshot.dart';

enum Severity { error, warning }

enum ValidationMode { release, draft }

class ValidationIssue {
  const ValidationIssue(this.severity, this.code, this.message);

  final Severity severity;

  /// Stable machine-readable code (tests assert on it).
  final String code;
  final String message;

  @override
  String toString() => '${severity.name.toUpperCase()} [$code] $message';
}

class ValidationReport {
  const ValidationReport(this.issues);

  final List<ValidationIssue> issues;

  List<ValidationIssue> get errors =>
      issues.where((i) => i.severity == Severity.error).toList();
  List<ValidationIssue> get warnings =>
      issues.where((i) => i.severity == Severity.warning).toList();

  /// Hard failures absent. Warnings never block.
  bool get isValid => errors.isEmpty;

  bool hasError(String code) => errors.any((i) => i.code == code);
  bool hasWarning(String code) => warnings.any((i) => i.code == code);

  @override
  String toString() => issues.join('\n');
}

final _slug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _hex = RegExp(r'^#[0-9A-Fa-f]{6}$');
final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _datasetVersion = RegExp(r'^\d{4}\.\d{2}\.\d+$');

/// Maximum minutes in a service day incl. post-midnight running (48 h).
const _maxServiceMinutes = 48 * 60;

/// Validates a dataset. Hard failures (errors) reject a build or an install;
/// warnings are reported only (docs/data-model.md "Validation").
///
/// [mode] `release` (default) is what the app and every shipped dataset must
/// pass. `draft` downgrades gaps the pipeline legitimately leaves while data is
/// being curated (unknown Hindi names, unmerged interchanges) to warnings;
/// structural integrity rules stay errors in both modes.
ValidationReport validateSnapshot(
  MetroSnapshot s, {
  DateTime? now,
  ValidationMode mode = ValidationMode.release,
}) {
  final v = _Validator(s, now ?? DateTime.now(), mode)..run();
  return ValidationReport(v.issues);
}

class _Validator {
  _Validator(this.s, this.now, this.mode);

  final MetroSnapshot s;
  final DateTime now;
  final ValidationMode mode;
  final List<ValidationIssue> issues = [];

  late final Set<String> sources = {for (final x in s.sources) x.id};
  late final Set<String> operators = {for (final x in s.operators) x.id};
  late final Set<String> lines = {for (final x in s.lines) x.id};
  late final Set<String> services = {for (final x in s.services) x.id};
  late final Set<String> stations = {for (final x in s.stations) x.id};
  late final Set<String> fareSystems = {for (final x in s.fareSystems) x.id};
  late final Set<String> gates = {for (final x in s.gates) x.id};
  late final Map<String, String> serviceLine = {
    for (final x in s.services) x.id: x.lineId,
  };
  late final Map<String, List<String>> stopsByService = () {
    final m = <String, List<(int, String)>>{};
    for (final st in s.serviceStops) {
      m.putIfAbsent(st.serviceId, () => []).add((st.seq, st.stationId));
    }
    return {
      for (final e in m.entries)
        e.key: (e.value..sort((a, b) => a.$1.compareTo(b.$1)))
            .map((r) => r.$2)
            .toList(),
    };
  }();

  void error(String code, String msg) =>
      issues.add(ValidationIssue(Severity.error, code, msg));
  void warn(String code, String msg) =>
      issues.add(ValidationIssue(Severity.warning, code, msg));

  /// Error in release mode, warning while the dataset is a draft.
  void gap(String code, String msg) =>
      mode == ValidationMode.release ? error(code, msg) : warn(code, msg);

  void run() {
    _meta();
    _uniqueIds();
    _slugs();
    _names();
    _references();
    _coordinates();
    _colours();
    _provenance();
    _orphans();
    _serviceStops();
    _edges();
    _lineRelationships();
    _transfers();
    _walkLinks();
    _connectivity();
    _stationFacts();
    _fares();
    _timings();
    _origins();
    _warnings();
  }

  // ---- meta / schema compatibility

  List<double>? _bbox;

  void _meta() {
    for (final key in MetaKeys.required) {
      if ((s.meta[key] ?? '').trim().isEmpty) {
        error('meta-missing', 'meta.$key is missing or empty');
      }
    }
    final stage = s.meta[MetaKeys.stage];
    if (stage != null && stage != 'draft' && stage != 'release') {
      error('bad-stage', 'meta.stage must be draft or release, got "$stage"');
    } else if (stage == 'draft' && mode == ValidationMode.release) {
      error('draft-dataset', 'dataset is a draft (meta.stage=draft)');
    }
    final schema = s.schemaVersion;
    if (s.meta.containsKey(MetaKeys.schemaVersion) && schema == null) {
      error('schema-version', 'meta.schema_version is not an integer');
    } else if (schema != null &&
        (schema < minSupportedSchemaVersion || schema > currentSchemaVersion)) {
      error(
        'schema-version',
        'schema_version $schema outside supported range '
            '[$minSupportedSchemaVersion, $currentSchemaVersion]',
      );
    }
    final version = s.datasetVersion;
    if (version != null && !_datasetVersion.hasMatch(version)) {
      error(
        'dataset-version',
        'dataset_version "$version" is not YYYY.MM.patch',
      );
    }
    final raw = s.meta[MetaKeys.bbox];
    if (raw != null) {
      final parts = raw.split(',').map((e) => double.tryParse(e.trim()));
      final list = parts.toList();
      if (list.length != 4 ||
          list.any((e) => e == null || !e.isFinite) ||
          list[0]! >= list[2]! ||
          list[1]! >= list[3]!) {
        error('bbox', 'meta.bbox must be "minLat,minLng,maxLat,maxLng"');
      } else {
        _bbox = list.cast<double>();
      }
    }
  }

  // ---- identity

  void _dup(String table, Iterable<String> keys) {
    final seen = <String>{};
    for (final k in keys) {
      if (!seen.add(k)) error('duplicate-id', '$table: duplicate "$k"');
    }
  }

  void _uniqueIds() {
    _dup('source', s.sources.map((x) => x.id));
    _dup('operator', s.operators.map((x) => x.id));
    _dup('line', s.lines.map((x) => x.id));
    _dup('line_service', s.services.map((x) => x.id));
    _dup('station', s.stations.map((x) => x.id));
    _dup('fare_system', s.fareSystems.map((x) => x.id));
    _dup('gate', s.gates.map((x) => x.id));
    _dup('edge', s.edges.map((x) => x.id));
    _dup('walk_link', s.walkLinks.map((x) => x.id));
    _dup('service_stop', s.serviceStops.map((x) => '${x.serviceId}#${x.seq}'));
    _dup(
      'station_name',
      s.stationNames.map(
        (x) => '${x.stationId}|${x.text}|${x.lang}|${x.kind.wire}',
      ),
    );
    _dup(
      'station_line',
      s.stationLines.map((x) => '${x.stationId}|${x.lineId}'),
    );
    _dup(
      'transfer',
      s.transfers.map((x) => '${x.stationId}|${x.fromLine}|${x.toLine}'),
    );
    _dup(
      'platform',
      s.platforms.map((x) => '${x.stationId}|${x.lineId}|${x.number}'),
    );
    _dup('accessibility', s.accessibility.map((x) => x.stationId));
    _dup(
      'gate number',
      s.gates.map((x) => '${x.stationId}|${x.number}'),
    );
    _dup(
      'fare_slab',
      s.fareSlabs.map(
        (x) => '${x.fareSystemId}|${x.dayType.wire}|${x.minKm}',
      ),
    );
    _dup(
      'fare_discount',
      s.fareDiscounts.map(
        (x) => '${x.fareSystemId}|${x.media.wire}|${x.kind.wire}',
      ),
    );
    _dup(
      'fare_override',
      s.fareOverrides.map(
        (x) =>
            '${x.fareSystemId}|${x.fromStation}|${x.toStation}|${x.dayType.wire}',
      ),
    );
    _dup(
      'timing',
      s.timings.map(
        (x) =>
            '${x.serviceId}|${x.stationId}|${x.directionTerminalId}|${x.dayType.wire}',
      ),
    );
    // A station code must be unique within its line.
    _dup(
      'station_code',
      s.stationLines
          .where((x) => x.stationCode != null)
          .map((x) => '${x.lineId}|${x.stationCode}'),
    );
  }

  void _slugs() {
    void check(String table, Iterable<String> ids) {
      for (final id in ids) {
        if (!_slug.hasMatch(id)) {
          error('bad-id', '$table: id "$id" is not a lowercase slug');
        }
      }
    }

    check('source', s.sources.map((x) => x.id));
    check('operator', s.operators.map((x) => x.id));
    check('line', s.lines.map((x) => x.id));
    check('line_service', s.services.map((x) => x.id));
    check('station', s.stations.map((x) => x.id));
    check('fare_system', s.fareSystems.map((x) => x.id));
    for (final g in s.gates) {
      if (g.id != '${g.stationId}:g${g.number}') {
        error(
          'bad-id',
          'gate "${g.id}" must be "<station>:g<number>" '
              '(${g.stationId}:g${g.number})',
        );
      }
    }
  }

  void _names() {
    void need(String table, String id, String en, String? hi) {
      if (en.trim().isEmpty) error('empty-name', '$table $id: name_en empty');
      if (hi == null) {
        gap('missing-hindi-name', '$table $id: name_hi is unknown (null)');
      } else if (hi.trim().isEmpty) {
        error('empty-name', '$table $id: name_hi empty');
      }
    }

    for (final x in s.operators) {
      need('operator', x.id, x.nameEn, x.nameHi);
    }
    for (final x in s.lines) {
      need('line', x.id, x.nameEn, x.nameHi);
    }
    for (final x in s.stations) {
      need('station', x.id, x.nameEn, x.nameHi);
    }
    for (final x in s.sources) {
      if (x.name.trim().isEmpty || x.license.trim().isEmpty) {
        error('empty-name', 'source ${x.id}: name and license are required');
      }
    }
    for (final n in s.stationNames) {
      if (n.text.trim().isEmpty) {
        error('empty-name', 'station_name for ${n.stationId}: empty text');
      }
      if (n.lang != 'en' && n.lang != 'hi') {
        error('bad-lang', 'station_name ${n.stationId}: lang "${n.lang}"');
      }
    }
  }

  // ---- references

  void _ref(String what, String value, Set<String> target, String targetName) {
    if (!target.contains(value)) {
      error('missing-ref', '$what -> $targetName "$value" does not exist');
    }
  }

  void _references() {
    for (final x in s.operators) {
      final fs = x.fareSystemId;
      if (fs != null) {
        _ref('operator ${x.id}.fare_system', fs, fareSystems, 'fare_system');
      }
    }
    for (final x in s.fareSystems) {
      _ref('fare_system ${x.id}.operator', x.operatorId, operators, 'operator');
      _ref('fare_system ${x.id}.source', x.sourceId, sources, 'source');
    }
    for (final x in s.lines) {
      _ref('line ${x.id}.operator', x.operatorId, operators, 'operator');
    }
    for (final x in s.services) {
      _ref('service ${x.id}.line', x.lineId, lines, 'line');
      final t = x.throughServiceOf;
      if (t != null) {
        _ref('service ${x.id}.through_service_of', t, services, 'line_service');
        if (t == x.id) {
          error('bad-through-service', 'service ${x.id} continues into itself');
        }
      }
    }
    for (final x in s.serviceStops) {
      _ref(
        'service_stop ${x.serviceId}#${x.seq}.service',
        x.serviceId,
        services,
        'line_service',
      );
      _ref(
        'service_stop ${x.serviceId}#${x.seq}.station',
        x.stationId,
        stations,
        'station',
      );
    }
    for (final x in s.stationNames) {
      _ref(
        'station_name "${x.text}".station',
        x.stationId,
        stations,
        'station',
      );
    }
    for (final x in s.stationLines) {
      _ref(
        'station_line ${x.stationId}.station',
        x.stationId,
        stations,
        'station',
      );
      _ref('station_line ${x.stationId}.line', x.lineId, lines, 'line');
    }
    for (final x in s.edges) {
      _ref('edge ${x.id}.service', x.serviceId, services, 'line_service');
      _ref('edge ${x.id}.from', x.fromStation, stations, 'station');
      _ref('edge ${x.id}.to', x.toStation, stations, 'station');
    }
    for (final x in s.transfers) {
      final w = 'transfer ${x.stationId}';
      _ref('$w.station', x.stationId, stations, 'station');
      _ref('$w.from_line', x.fromLine, lines, 'line');
      _ref('$w.to_line', x.toLine, lines, 'line');
    }
    for (final x in s.walkLinks) {
      _ref('walk_link ${x.id}.from', x.fromStation, stations, 'station');
      _ref('walk_link ${x.id}.to', x.toStation, stations, 'station');
    }
    for (final x in s.platforms) {
      final w = 'platform ${x.stationId}/${x.lineId}/${x.number}';
      _ref('$w.station', x.stationId, stations, 'station');
      _ref('$w.line', x.lineId, lines, 'line');
      if (x.towardsStationId != null) {
        _ref('$w.towards', x.towardsStationId!, stations, 'station');
      }
      if (x.serviceId != null) {
        _ref('$w.service', x.serviceId!, services, 'line_service');
      }
    }
    for (final x in s.gates) {
      _ref('gate ${x.id}.station', x.stationId, stations, 'station');
    }
    for (final x in s.gateLandmarks) {
      _ref('gate_landmark "${x.textEn}".gate', x.gateId, gates, 'gate');
    }
    for (final x in s.facilities) {
      _ref('facility ${x.type.wire}.station', x.stationId, stations, 'station');
      final g = x.gateId;
      if (g != null) {
        _ref('facility ${x.type.wire}.gate', g, gates, 'gate');
        if (gates.contains(g) && !g.startsWith('${x.stationId}:')) {
          error(
            'gate-station-mismatch',
            'facility at ${x.stationId} uses gate $g of another station',
          );
        }
      }
    }
    for (final x in s.accessibility) {
      _ref(
        'accessibility ${x.stationId}.station',
        x.stationId,
        stations,
        'station',
      );
    }
    for (final x in s.fareSlabs) {
      _ref('fare_slab.system', x.fareSystemId, fareSystems, 'fare_system');
    }
    for (final x in s.fareDiscounts) {
      _ref('fare_discount.system', x.fareSystemId, fareSystems, 'fare_system');
    }
    for (final x in s.fareOverrides) {
      final w = 'fare_override ${x.fromStation}->${x.toStation}';
      _ref('$w.system', x.fareSystemId, fareSystems, 'fare_system');
      _ref('$w.from', x.fromStation, stations, 'station');
      _ref('$w.to', x.toStation, stations, 'station');
      _ref('$w.source', x.sourceId, sources, 'source');
    }
    for (final x in s.timings) {
      final w = 'timing ${x.serviceId}/${x.stationId}';
      _ref('$w.service', x.serviceId, services, 'line_service');
      _ref('$w.station', x.stationId, stations, 'station');
      _ref('$w.terminal', x.directionTerminalId, stations, 'station');
    }
  }

  // ---- coordinates, colours

  bool _validCoord(double lat, double lng) =>
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;

  bool _inBox(double lat, double lng) {
    final b = _bbox;
    if (b == null) return true; // bbox error already reported
    return lat >= b[0] && lng >= b[1] && lat <= b[2] && lng <= b[3];
  }

  void _coord(String what, double lat, double lng) {
    if (!_validCoord(lat, lng)) {
      error('bad-coordinate', '$what: invalid coordinate ($lat, $lng)');
    } else if (!_inBox(lat, lng)) {
      error('coordinate-outside-bbox', '$what: ($lat, $lng) outside meta.bbox');
    }
  }

  void _coordinates() {
    for (final x in s.stations) {
      _coord('station ${x.id}', x.lat, x.lng);
      if ((x.mapX == null) != (x.mapY == null)) {
        error(
          'bad-map-position',
          'station ${x.id}: map_x/map_y must be both set or both null',
        );
      }
    }
    for (final g in s.gates) {
      if ((g.lat == null) != (g.lng == null)) {
        error(
          'bad-coordinate',
          'gate ${g.id}: lat/lng must be both set or both null',
        );
      } else if (g.lat != null) {
        _coord('gate ${g.id}', g.lat!, g.lng!);
      }
    }
  }

  void _colours() {
    for (final l in s.lines) {
      if (!_hex.hasMatch(l.colorHex)) {
        error('bad-colour', 'line ${l.id}: color_hex "${l.colorHex}"');
      }
      if (!_hex.hasMatch(l.textColorHex)) {
        error('bad-colour', 'line ${l.id}: text_color_hex "${l.textColorHex}"');
      }
    }
  }

  // ---- provenance

  void _prov(String what, Provenance p) {
    _ref('$what.source', p.sourceId, sources, 'source');
    final d = p.verifiedOn;
    if (d != null && !_validDate(d)) {
      error(
        'bad-date',
        '$what: verified_on "$d" is not a valid YYYY-MM-DD date',
      );
    }
    if (p.confidence.requiresVerifiedOn && d == null) {
      error(
        'missing-verified-on',
        '$what: ${p.confidence.wire} fact needs verified_on',
      );
    }
  }

  bool _validDate(String d) {
    if (!_isoDate.hasMatch(d)) return false;
    final parsed = DateTime.tryParse(d);
    return parsed != null && parsed.toIso8601String().startsWith(d);
  }

  void _provenance() {
    for (final x in s.stations) {
      _prov('station ${x.id}', x.provenance);
      if (x.openedOn != null && !_validDate(x.openedOn!)) {
        error('bad-date', 'station ${x.id}: opened_on "${x.openedOn}"');
      }
    }
    for (final x in s.edges) {
      _prov('edge ${x.id}', x.provenance);
    }
    for (final x in s.transfers) {
      _prov('transfer ${x.stationId} ${x.fromLine}->${x.toLine}', x.provenance);
    }
    for (final x in s.walkLinks) {
      _prov('walk_link ${x.id}', x.provenance);
    }
    for (final x in s.platforms) {
      _prov('platform ${x.stationId}/${x.lineId}/${x.number}', x.provenance);
    }
    for (final x in s.gates) {
      _prov('gate ${x.id}', x.provenance);
    }
    for (final x in s.facilities) {
      _prov('facility ${x.type.wire}@${x.stationId}', x.provenance);
    }
    for (final x in s.accessibility) {
      _prov('accessibility ${x.stationId}', x.provenance);
    }
    for (final x in s.timings) {
      _prov('timing ${x.serviceId}/${x.stationId}', x.provenance);
    }
    for (final x in s.fareOverrides) {
      if (!_validDate(x.verifiedOn)) {
        error(
          'bad-date',
          'fare_override ${x.fromStation}->${x.toStation}: verified_on "${x.verifiedOn}"',
        );
      }
    }
    for (final x in s.fareSystems) {
      if (!_validDate(x.effectiveFrom)) {
        error(
          'bad-date',
          'fare_system ${x.id}: effective_from "${x.effectiveFrom}"',
        );
      }
    }
  }

  // ---- orphans & service structure

  void _orphans() {
    final onService = {for (final st in s.serviceStops) st.stationId};
    for (final x in s.stations) {
      if (!onService.contains(x.id)) {
        error('orphan-station', 'station ${x.id} is on no service');
      }
    }
    final linesWithService = {for (final x in s.services) x.lineId};
    for (final x in s.lines) {
      if (!linesWithService.contains(x.id)) {
        error('orphan-line', 'line ${x.id} has no service');
      }
    }
    final servicesWithStops = stopsByService.keys.toSet();
    for (final x in s.services) {
      if (!servicesWithStops.contains(x.id)) {
        error('orphan-service', 'service ${x.id} has no stops');
      }
    }
    final linesOfOperator = {for (final x in s.lines) x.operatorId};
    for (final x in s.operators) {
      if (!linesOfOperator.contains(x.id)) {
        error('orphan-operator', 'operator ${x.id} has no line');
      }
    }
  }

  void _serviceStops() {
    final bySvc = <String, List<_StopRef>>{};
    for (final st in s.serviceStops) {
      bySvc
          .putIfAbsent(st.serviceId, () => [])
          .add(_StopRef(st.seq, st.stationId, st.distFromStartM));
    }
    for (final MapEntry(key: id, value: stops) in bySvc.entries) {
      stops.sort((a, b) => a.seq.compareTo(b.seq));
      if (stops.length < 2) {
        error('short-service', 'service $id has fewer than 2 stops');
      }
      for (var i = 0; i < stops.length; i++) {
        if (stops[i].seq != i) {
          error(
            'bad-seq',
            'service $id: stop sequence must be 0..n-1 without gaps',
          );
          break;
        }
      }
      final isLoop = s.service(id)?.isLoop ?? false;
      final seen = <String>{};
      for (var i = 0; i < stops.length; i++) {
        final isClosingStop =
            isLoop &&
            i == stops.length - 1 &&
            stops[i].stationId == stops.first.stationId;
        if (!seen.add(stops[i].stationId) && !isClosingStop) {
          // Real routes can pass a station twice (a loop with a spur). The
          // edge/adjacency rules still guard the graph, so this only warns.
          warn(
            'repeated-stop',
            'service $id visits ${stops[i].stationId} more than once',
          );
        }
      }
      if (stops.isNotEmpty && stops.first.dist != 0) {
        error(
          'bad-distance',
          'service $id: first stop dist_from_start_m must be 0',
        );
      }
      for (var i = 1; i < stops.length; i++) {
        if (stops[i].dist <= stops[i - 1].dist) {
          error(
            'bad-distance',
            'service $id: dist_from_start_m must strictly increase (seq ${stops[i].seq})',
          );
        }
      }
      if (isLoop &&
          stops.length >= 2 &&
          stops.first.stationId != stops.last.stationId) {
        error('bad-loop', 'loop service $id must end at its first station');
      }
    }
  }

  // ---- edges: the graph must follow the service stop order exactly

  void _edges() {
    final byKey = <String, int>{};
    for (final e in s.edges) {
      if (e.fromStation == e.toStation) {
        error('bad-edge', 'edge ${e.id} connects ${e.fromStation} to itself');
      }
      final travel = e.travelS;
      if (travel != null && travel <= 0) {
        error('bad-edge', 'edge ${e.id}: travel_s must be > 0 (or unknown)');
      }
      if (e.distanceM <= 0) {
        error('bad-edge', 'edge ${e.id}: distance_m must be > 0');
      }
      final key = '${e.serviceId}|${e.fromStation}|${e.toStation}';
      byKey[key] = (byKey[key] ?? 0) + 1;
    }
    for (final MapEntry(:key, value: n) in byKey.entries) {
      if (n > 1) error('duplicate-edge', 'edge $key stored $n times');
    }

    for (final MapEntry(key: id, value: stops) in stopsByService.entries) {
      final expected = <String>{};
      for (var i = 0; i + 1 < stops.length; i++) {
        expected
          ..add('$id|${stops[i]}|${stops[i + 1]}')
          ..add('$id|${stops[i + 1]}|${stops[i]}');
      }
      for (final key in expected) {
        if (!byKey.containsKey(key)) {
          error(
            'missing-edge',
            'service $id lacks edge ${key.substring(id.length + 1).replaceFirst('|', ' -> ')}',
          );
        }
      }
      for (final e in s.edges.where((e) => e.serviceId == id)) {
        if (!expected.contains('$id|${e.fromStation}|${e.toStation}')) {
          error(
            'edge-not-adjacent',
            'edge ${e.id} joins stations that are not consecutive on service $id',
          );
        }
      }
    }
  }

  // ---- station_line <-> service_stop consistency

  void _lineRelationships() {
    final fromStops = <String>{};
    for (final MapEntry(key: svc, value: stops) in stopsByService.entries) {
      final line = serviceLine[svc];
      if (line == null) continue;
      for (final st in stops) {
        fromStops.add('$st|$line');
      }
    }
    final declared = {
      for (final x in s.stationLines) '${x.stationId}|${x.lineId}',
    };
    for (final k in fromStops.difference(declared)) {
      error(
        'line-relationship',
        'station_line missing for ${k.replaceFirst('|', ' on line ')}',
      );
    }
    for (final k in declared.difference(fromStops)) {
      error(
        'line-relationship',
        'station_line ${k.replaceFirst('|', ' / ')} has no service stop',
      );
    }
    for (final sv in s.services) {
      final t = sv.throughServiceOf;
      if (t == null) continue;
      final other = s.service(t);
      if (other != null && other.lineId == sv.lineId) {
        // Through-running is between two lines; same-line pattern links are invalid.
        error(
          'bad-through-service',
          'service ${sv.id} continues into ${other.id} of the same line',
        );
      }
    }
  }

  void _transfers() {
    final linesAt = <String, Set<String>>{};
    for (final x in s.stationLines) {
      linesAt.putIfAbsent(x.stationId, () => {}).add(x.lineId);
    }
    final have = {
      for (final t in s.transfers) '${t.stationId}|${t.fromLine}|${t.toLine}',
    };
    for (final MapEntry(key: st, value: ls) in linesAt.entries) {
      if (ls.length < 2) continue;
      for (final a in ls) {
        for (final b in ls) {
          if (a != b && !have.contains('$st|$a|$b')) {
            gap(
              'missing-transfer',
              'interchange $st needs a transfer $a -> $b',
            );
          }
        }
      }
    }
    for (final t in s.transfers) {
      if (t.fromLine == t.toLine) {
        error(
          'bad-transfer',
          'transfer at ${t.stationId} from a line to itself',
        );
      }
      final ls = linesAt[t.stationId] ?? {};
      if (!ls.contains(t.fromLine) || !ls.contains(t.toLine)) {
        error(
          'bad-transfer',
          'transfer at ${t.stationId} uses a line that does not serve it',
        );
      }
      if ((t.walkM ?? 0) < 0 || (t.walkS ?? 0) < 0) {
        error('bad-transfer', 'transfer at ${t.stationId}: negative walk');
      }
    }
  }

  void _walkLinks() {
    for (final w in s.walkLinks) {
      if (w.fromStation == w.toStation) {
        error(
          'bad-walk-link',
          'walk_link ${w.id} connects a station to itself',
        );
      }
      if (w.walkM <= 0 || w.walkS <= 0) {
        error(
          'bad-walk-link',
          'walk_link ${w.id}: walk_m and walk_s must be > 0',
        );
      }
    }
  }

  // ---- connectivity per operator (stations are shared across lines, so edges
  // alone connect interchanges)

  void _connectivity() {
    final lineOperator = {for (final l in s.lines) l.id: l.operatorId};
    final parent = <String, String>{};
    String find(String x) {
      var r = x;
      while ((parent[r] ?? r) != r) {
        r = parent[r]!;
      }
      parent[x] = r;
      return r;
    }

    void union(String a, String b) {
      parent.putIfAbsent(a, () => a);
      parent.putIfAbsent(b, () => b);
      parent[find(a)] = find(b);
    }

    final stationOperators = <String, Set<String>>{};
    for (final x in s.stationLines) {
      final op = lineOperator[x.lineId];
      if (op != null) {
        stationOperators.putIfAbsent(x.stationId, () => {}).add(op);
      }
    }
    for (final op in operators) {
      parent.clear();
      for (final e in s.edges) {
        final svcLine = serviceLine[e.serviceId];
        if (svcLine == null || lineOperator[svcLine] != op) continue;
        union(e.fromStation, e.toStation);
      }
      final roots = <String>{};
      for (final st in stationOperators.entries) {
        if (st.value.contains(op) && parent.containsKey(st.key)) {
          roots.add(find(st.key));
        }
      }
      // Stations of this operator without any edge are reported by orphan rules.
      if (roots.length > 1) {
        gap(
          'disconnected-network',
          'operator $op network splits into ${roots.length} disconnected parts',
        );
      }
    }
  }

  // ---- station facts

  void _stationFacts() {
    final servicesByLine = <String, Set<String>>{};
    for (final x in s.services) {
      servicesByLine.putIfAbsent(x.lineId, () => {}).add(x.id);
    }
    final lineAt = {
      for (final x in s.stationLines) '${x.stationId}|${x.lineId}',
    };
    for (final p in s.platforms) {
      final w = 'platform ${p.stationId}/${p.lineId}/${p.number}';
      if (p.number.trim().isEmpty) error('bad-platform', '$w: empty number');
      if (!lineAt.contains('${p.stationId}|${p.lineId}')) {
        error('bad-platform', '$w: line does not serve the station');
      }
      final svc = p.serviceId;
      if (svc != null) {
        if (!(servicesByLine[p.lineId]?.contains(svc) ?? false)) {
          error('bad-platform', '$w: service $svc is not of line ${p.lineId}');
        }
        if (!(stopsByService[svc]?.contains(p.stationId) ?? false)) {
          error(
            'bad-platform',
            '$w: service $svc does not stop at the station',
          );
        }
        final towards = p.towardsStationId;
        if (towards != null &&
            !(stopsByService[svc]?.contains(towards) ?? false)) {
          error('bad-platform', '$w: towards station is not on service $svc');
        }
      }
    }
    for (final a in s.accessibility) {
      for (final (name, n) in [
        ('lifts', a.lifts),
        ('escalators', a.escalators),
      ]) {
        if (n != null && n < 0) {
          error('bad-accessibility', 'accessibility ${a.stationId}: $name < 0');
        }
      }
    }
    for (final g in s.gates) {
      if (g.number <= 0) error('bad-gate', 'gate ${g.id}: number must be > 0');
    }
  }

  // ---- fares

  void _fares() {
    for (final fs in s.fareSystems) {
      if (fs.currency.trim().isEmpty) {
        error('bad-fare', 'fare_system ${fs.id}: currency empty');
      }
      for (final day in DayType.values) {
        final slabs =
            s.fareSlabs
                .where((x) => x.fareSystemId == fs.id && x.dayType == day)
                .toList()
              ..sort((a, b) => a.minKm.compareTo(b.minKm));
        if (slabs.isEmpty) {
          if (day == DayType.regular) {
            error(
              'fare-slab-gap',
              'fare_system ${fs.id}: no regular fare slabs',
            );
          }
          continue;
        }
        if (slabs.first.minKm != 0) {
          error(
            'fare-slab-gap',
            'fare_system ${fs.id}/${day.wire}: first slab must start at 0 km',
          );
        }
        for (var i = 0; i < slabs.length; i++) {
          final slab = slabs[i];
          final isLast = i == slabs.length - 1;
          if (slab.amountPaise <= 0) {
            error(
              'bad-fare',
              'fare_system ${fs.id}/${day.wire}: amount must be > 0',
            );
          }
          if (slab.maxKm == null && !isLast) {
            error(
              'fare-slab-gap',
              'fare_system ${fs.id}/${day.wire}: open-ended slab must be last',
            );
          } else if (slab.maxKm != null) {
            if (slab.maxKm! <= slab.minKm) {
              error(
                'fare-slab-gap',
                'fare_system ${fs.id}/${day.wire}: empty slab at ${slab.minKm} km',
              );
            }
            if (!isLast && slabs[i + 1].minKm != slab.maxKm) {
              error(
                'fare-slab-gap',
                'fare_system ${fs.id}/${day.wire}: gap or overlap after ${slab.maxKm} km',
              );
            }
            if (isLast) {
              error(
                'fare-slab-gap',
                'fare_system ${fs.id}/${day.wire}: last slab must be open-ended',
              );
            }
          }
        }
      }
    }
    for (final d in s.fareDiscounts) {
      if (d.percent <= 0 || d.percent > 100) {
        error(
          'bad-fare',
          'fare_discount ${d.fareSystemId}/${d.kind.wire}: percent must be 1-100',
        );
      }
      if (d.kind == FareDiscountKind.offPeak && (d.windowsJson ?? '').isEmpty) {
        error(
          'bad-fare',
          'fare_discount ${d.fareSystemId}: off_peak needs windows_json',
        );
      }
    }
    for (final o in s.fareOverrides) {
      if (o.amountPaise <= 0) {
        error(
          'bad-fare',
          'fare_override ${o.fromStation}->${o.toStation}: amount must be > 0',
        );
      }
      if (o.fromStation == o.toStation) {
        error('bad-fare', 'fare_override ${o.fromStation}: from == to');
      }
    }
  }

  // ---- timings

  void _timings() {
    for (final t in s.timings) {
      final w = 'timing ${t.serviceId}/${t.stationId}/${t.directionTerminalId}';
      if (t.firstDep < 0 || t.lastDep > _maxServiceMinutes) {
        error('bad-timing', '$w: minutes outside 0..$_maxServiceMinutes');
      }
      if (t.firstDep >= t.lastDep) {
        error('bad-timing', '$w: first_dep must be before last_dep');
      }
      final stops = stopsByService[t.serviceId];
      if (stops != null) {
        if (!stops.contains(t.stationId)) {
          error('bad-timing', '$w: station is not on the service');
        }
        if (!stops.contains(t.directionTerminalId)) {
          error('bad-timing', '$w: terminal is not on the service');
        }
      }
    }
  }

  // ---- warnings (never block)

  void _origins() {
    final entities = {
      'operator': operators,
      'line': lines,
      'line_service': services,
      'station': stations,
    };
    _dup('origin', s.origins.map((x) => x.key));
    for (final o in s.origins) {
      final what = 'origin ${o.entity}/${o.entityId}/${o.field}';
      final known = entities[o.entity];
      if (known == null) {
        error('bad-origin', '$what: unknown entity "${o.entity}"');
      } else {
        _ref('$what.entity', o.entityId, known, o.entity);
      }
      _ref('$what.source', o.sourceId, sources, 'source');
    }
  }

  void _warnings() {
    for (final g in s.gates) {
      if (g.provenance.confidence == Confidence.community) {
        warn(
          'community-gate',
          'gate ${g.id} is community-sourced (unverified)',
        );
      }
    }
    for (final p in s.platforms) {
      if (p.provenance.confidence == Confidence.community) {
        warn(
          'community-platform',
          'platform ${p.stationId}/${p.lineId}/${p.number} is community-sourced (unverified)',
        );
      }
    }
    final withHindiAlias = {
      for (final n in s.stationNames)
        if (n.lang == 'hi' && n.kind != NameKind.official) n.stationId,
    };
    for (final x in s.stations) {
      if (!withHindiAlias.contains(x.id)) {
        warn('missing-hindi-alias', 'station ${x.id} has no Hindi alias');
      }
    }
    final cutoff = now.subtract(const Duration(days: 365));
    void stale(String what, String? date) {
      final d = date == null ? null : DateTime.tryParse(date);
      if (d != null && d.isBefore(cutoff)) {
        warn(
          'stale-verification',
          '$what verified_on $date is older than 12 months',
        );
      }
    }

    for (final x in s.stations) {
      stale('station ${x.id}', x.provenance.verifiedOn);
    }
    for (final x in s.gates) {
      stale('gate ${x.id}', x.provenance.verifiedOn);
    }
    for (final x in s.platforms) {
      stale('platform ${x.stationId}/${x.number}', x.provenance.verifiedOn);
    }
    for (final x in s.timings) {
      stale('timing ${x.serviceId}/${x.stationId}', x.provenance.verifiedOn);
    }
    for (final x in s.fareOverrides) {
      stale('fare_override ${x.fromStation}->${x.toStation}', x.verifiedOn);
    }
    final used = <String>{
      ...s.origins.map((x) => x.sourceId),
      ...s.stations.map((x) => x.provenance.sourceId),
      ...s.edges.map((x) => x.provenance.sourceId),
      ...s.fareSystems.map((x) => x.sourceId),
      ...s.fareOverrides.map((x) => x.sourceId),
      ...s.gates.map((x) => x.provenance.sourceId),
      ...s.platforms.map((x) => x.provenance.sourceId),
      ...s.facilities.map((x) => x.provenance.sourceId),
      ...s.accessibility.map((x) => x.provenance.sourceId),
      ...s.transfers.map((x) => x.provenance.sourceId),
      ...s.walkLinks.map((x) => x.provenance.sourceId),
      ...s.timings.map((x) => x.provenance.sourceId),
    };
    for (final src in s.sources) {
      if (!used.contains(src.id)) {
        warn('unused-source', 'source ${src.id} is not referenced');
      }
    }
  }
}

/// Internal row for per-service stop checks.
class _StopRef {
  const _StopRef(this.seq, this.stationId, this.dist);

  final int seq;
  final String stationId;
  final int dist;
}
