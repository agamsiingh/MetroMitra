import 'dart:math' as math;

import 'package:data_pipeline/src/config.dart';
import 'package:data_pipeline/src/conflict.dart';
import 'package:data_pipeline/src/lock.dart';
import 'package:data_pipeline/src/normalize.dart';
import 'package:data_pipeline/src/overlay.dart';
import 'package:data_pipeline/src/util.dart';
import 'package:metro_core/metro_core.dart';

const osmSourceId = 'osm-overpass';
const wikidataSourceId = 'wikidata';
const curatedSourceId = 'mitra-curated';
const derivedSourceId = 'mitra-derived';

class MergeResult {
  const MergeResult({
    required this.snapshot,
    required this.conflicts,
    required this.overrides,
    required this.stats,
  });

  /// Canonical dataset (stage not yet set; see the build step).
  final MetroSnapshot snapshot;
  final List<Conflict> conflicts;
  final List<OverrideRecord> overrides;
  final Map<String, Object?> stats;

  List<Conflict> get blocking => conflicts.where((c) => c.blocking).toList();
}

/// Cluster = all stop nodes of ONE line that share a name.
class _Cluster {
  _Cluster(this.id, this.lineId, this.nodes);

  final String id;
  final String lineId;
  final List<OsmStop> nodes;

  late final String name = _mostCommon([for (final n in nodes) n.name])!;
  late final String? nameHi = _mostCommon([
    for (final n in nodes)
      if (n.nameHi != null) n.nameHi!,
  ]);
  late final Set<String> qids = {
    for (final n in nodes)
      if (n.wikidata != null) n.wikidata!,
  };
  late final double lat = round6(
    nodes.map((n) => n.lat).reduce((a, b) => a + b) / nodes.length,
  );
  late final double lng = round6(
    nodes.map((n) => n.lng).reduce((a, b) => a + b) / nodes.length,
  );
}

class _Station {
  _Station(this.clusters);

  final List<_Cluster> clusters;
  late String id;
  late String nameEn;
  String? nameHi;
  late double lat;
  late double lng;
  String? qid;
  OriginStatus nameEnStatus = OriginStatus.imported;
  String nameEnSource = osmSourceId;
  String? nameEnDetail;
  String nameHiSource = osmSourceId;
  OriginStatus nameHiStatus = OriginStatus.imported;
  bool coordsFromWikidata = false;
  final List<String> aliasesEn = [];
  final List<String> aliasesHi = [];
  final List<String> oldNames = [];
  String? curatedNameEn;
  String? curatedNameEnDetail;
  String? curatedNameHi;
  bool coordsCurated = false;

  Iterable<OsmStop> get nodes => clusters.expand((c) => c.nodes);
  Set<String> get lineIds => {for (final c in clusters) c.lineId};
}

/// Audit text stored in `origin.detail` for curated decisions.
String _curationDetail(String what, Curation c) =>
    '$what | reason: ${c.reason} | source: ${c.source} | '
    'verified_on: ${c.verifiedOn}';

/// Most frequent value; ties resolve to the lexicographically smallest, so
/// the choice is deterministic (and any disagreement is reported separately).
String? _mostCommon(List<String> values) {
  if (values.isEmpty) return null;
  final counts = <String, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final c = counts[b]!.compareTo(counts[a]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return keys.first;
}

/// Black or white text for a line colour (WCAG relative luminance).
String contrastText(String hex) {
  double channel(int v) {
    final c = v / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = int.parse(hex.substring(1, 3), radix: 16);
  final g = int.parse(hex.substring(3, 5), radix: 16);
  final b = int.parse(hex.substring(5, 7), radix: 16);
  final l = 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
  return l > 0.179 ? '#000000' : '#FFFFFF';
}

/// Normalised sources + curated overlay -> canonical snapshot + conflict report.
///
/// Policy (documented, deterministic, always reported):
/// - OSM is primary for geometry/topology; Wikidata only fills *unknown*
///   values and cross-checks the rest. Wikidata items are linked ONLY through
///   an explicit `wikidata` tag in OSM - never by fuzzy name matching.
/// - Stations are identified within one line by (line, normalised name).
///   Across lines they merge ONLY via a shared Wikidata id or a curated
///   `station_merges` entry; same-name stations are reported as candidates.
/// - Unknown stays null: Hindi names, fares, travel times, gates, platforms,
///   facilities, parking and timings are never invented.
MergeResult mergeSources({
  required OsmData osm,
  required WdData? wikidata,
  required Overlay overlay,
  required PipelineConfig config,
  required SourceLock lock,
}) {
  final log = ConflictLog(overlay.resolutions);
  final overrides = <OverrideRecord>[];
  final origins = <Origin>[];

  void err(
    String kind,
    String subject,
    String message, {
    String? field,
    Map<String, String?> candidates = const {},
  }) => log.report(
    Conflict(
      kind: kind,
      subject: subject,
      severity: ConflictSeverity.error,
      message: message,
      field: field,
      candidates: candidates,
    ),
  );
  Conflict warn(
    String kind,
    String subject,
    String message, {
    String? field,
    Map<String, String?> candidates = const {},
  }) => log.report(
    Conflict(
      kind: kind,
      subject: subject,
      severity: ConflictSeverity.warning,
      message: message,
      field: field,
      candidates: candidates,
    ),
  );

  for (final i in osm.issues) {
    final isError = i.code == 'missing-node' || i.code == 'bad-stop';
    log.report(
      Conflict(
        kind: 'source-${i.code}',
        subject: i.subject,
        severity: isError ? ConflictSeverity.error : ConflictSeverity.warning,
        message: i.message,
      ),
    );
  }

  // ---- A. operators and lines -------------------------------------------
  final operatorOverlay = {for (final o in overlay.operators) o.osmOperator: o};
  final groups = <String, List<OsmRoute>>{};
  for (final r in osm.routes) {
    final key = r.lineWikidata ?? 'ref:${r.ref ?? r.name}';
    groups.putIfAbsent(key, () => []).add(r);
  }
  String lineNameOf(OsmRoute r) {
    final i = r.name.indexOf(' (');
    return tidy(i > 0 ? r.name.substring(0, i) : r.name);
  }

  final lineIdByGroup = <String, String>{};
  final lines = <Line>[];
  final operatorsById = <String, Operator>{};
  final groupLineName = <String, String>{};
  final wdLines = wikidata?.lines ?? const <String, WdLine>{};
  final sortedGroupKeys = groups.keys.toList()..sort();
  final seenLineIds = <String, String>{};
  for (final key in sortedGroupKeys) {
    final routes = groups[key]!;
    final name = _mostCommon([for (final r in routes) lineNameOf(r)])!;
    final names = {for (final r in routes) lineNameOf(r)};
    final lineId = slug(name);
    if (lineId.isEmpty) {
      err('line-id', 'line:$key', 'Cannot derive an id for line "$name".');
      continue;
    }
    if (seenLineIds.containsKey(lineId)) {
      err(
        'line-id-collision',
        'line:$lineId',
        'Two OSM line groups produce the id "$lineId" ($key and ${seenLineIds[lineId]}).',
      );
      continue;
    }
    seenLineIds[lineId] = key;
    lineIdByGroup[key] = lineId;
    groupLineName[key] = name;
    if (names.length > 1) {
      warn(
        'line-name-inconsistent',
        'line:$lineId',
        'Relations of this line use different names.',
        candidates: {for (final n in names.toList()..sort()) n: n},
      );
    }
    final colours = {
      for (final r in routes)
        if (r.colour != null) r.colour!,
    };
    if (colours.length > 1) {
      warn(
        'line-colour-inconsistent',
        'line:$lineId',
        'Relations of this line carry different colours.',
        candidates: {for (final c in colours.toList()..sort()) c: c},
      );
    }
    final colour = _mostCommon([
      for (final r in routes)
        if (r.colour != null) r.colour!,
    ]);
    if (colour == null) {
      err(
        'line-colour-missing',
        'line:$lineId',
        'No usable colour tag on any relation of this line.',
      );
    }
    final operatorNames = {
      for (final r in routes)
        if (r.operator != null) r.operator!,
    };
    if (operatorNames.isEmpty) {
      err(
        'operator-missing',
        'line:$lineId',
        'No operator tag on any relation.',
      );
    }
    if (operatorNames.length > 1) {
      warn(
        'line-operator-inconsistent',
        'line:$lineId',
        'Relations of this line name different operators.',
        candidates: {for (final o in operatorNames.toList()..sort()) o: o},
      );
    }
    final opName = (operatorNames.toList()..sort()).firstOrNull ?? 'unknown';
    final opOverlay = operatorOverlay[opName];
    final opId = opOverlay?.id ?? slug(opName);
    if (!operatorsById.containsKey(opId)) {
      operatorsById[opId] = Operator(
        id: opId,
        nameEn: opName,
        nameHi: opOverlay?.nameHi,
      );
      origins.add(
        Origin(
          entity: 'operator',
          entityId: opId,
          field: 'record',
          sourceId: osmSourceId,
          status: OriginStatus.imported,
          externalId: 'operator-tag',
          detail: opName,
        ),
      );
      if (opOverlay != null) {
        origins.add(
          Origin(
            entity: 'operator',
            entityId: opId,
            field: 'id',
            sourceId: curatedSourceId,
            status: OriginStatus.curated,
            detail: opOverlay.curation.reason,
          ),
        );
        if (opOverlay.nameHi != null) {
          origins.add(
            Origin(
              entity: 'operator',
              entityId: opId,
              field: 'name_hi',
              sourceId: curatedSourceId,
              status: OriginStatus.curated,
              detail: opOverlay.curation.reason,
            ),
          );
        }
      }
    }
    final qid = routes
        .map((r) => r.lineWikidata)
        .whereType<String>()
        .firstOrNull;
    final wdLine = qid == null ? null : wdLines[qid];
    final ref = _mostCommon([
      for (final r in routes)
        if (r.ref != null) r.ref!,
    ]);
    lines.add(
      Line(
        id: lineId,
        operatorId: opId,
        nameEn: name,
        nameHi: wdLine?.labelHi,
        shortName: ref,
        colorHex: colour ?? '#000000',
        textColorHex: contrastText(colour ?? '#000000'),
        sort: 0,
        status: OperatingStatus.open,
      ),
    );
    final relIds = (routes.map((r) => 'relation/${r.id}').toList()..sort())
        .join(';');
    origins.add(
      Origin(
        entity: 'line',
        entityId: lineId,
        field: 'record',
        sourceId: osmSourceId,
        status: OriginStatus.imported,
        externalId: relIds,
      ),
    );
    origins.add(
      Origin(
        entity: 'line',
        entityId: lineId,
        field: 'color_hex',
        sourceId: osmSourceId,
        status: OriginStatus.normalized,
        detail: 'colour tag upper-cased',
      ),
    );
    origins.add(
      Origin(
        entity: 'line',
        entityId: lineId,
        field: 'text_color_hex',
        sourceId: derivedSourceId,
        status: OriginStatus.derived,
        detail: 'black/white by WCAG luminance of color_hex',
      ),
    );
    if (qid != null) {
      origins.add(
        Origin(
          entity: 'line',
          entityId: lineId,
          field: 'wikidata',
          sourceId: osmSourceId,
          status: OriginStatus.imported,
          externalId: qid,
        ),
      );
    }
    if (wdLine?.labelHi != null) {
      origins.add(
        Origin(
          entity: 'line',
          entityId: lineId,
          field: 'name_hi',
          sourceId: wikidataSourceId,
          status: OriginStatus.imported,
          externalId: qid,
        ),
      );
    }
  }
  // Deterministic line order: by id; `sort` = position.
  lines.sort((a, b) => a.id.compareTo(b.id));
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    lines[i] = Line(
      id: l.id,
      operatorId: l.operatorId,
      nameEn: l.nameEn,
      nameHi: l.nameHi,
      shortName: l.shortName,
      colorHex: l.colorHex,
      textColorHex: l.textColorHex,
      sort: i + 1,
      status: l.status,
    );
  }

  // ---- B. clusters (per line, per normalised name) ------------------------
  final clusters = <String, _Cluster>{}; // by cluster id
  final routeClusterSeq = <int, List<String>>{};
  for (final key in sortedGroupKeys) {
    final lineId = lineIdByGroup[key];
    if (lineId == null) continue;
    final byName = <String, List<OsmStop>>{};
    for (final r in groups[key]!) {
      for (final s in r.stops) {
        final list = byName.putIfAbsent(nameKey(s.name), () => []);
        if (!list.any((x) => x.nodeId == s.nodeId)) list.add(s);
      }
    }
    final clusterByKey = <String, String>{};
    for (final entry in byName.entries) {
      final probe = entry.value.first;
      final base = slug(_mostCommon([for (final n in entry.value) n.name])!);
      if (base.isEmpty) {
        err(
          'station-id',
          'osm-node/${probe.nodeId}',
          'Cannot derive an id from the name "${probe.name}".',
        );
        continue;
      }
      final c = _Cluster('$base@$lineId', lineId, entry.value);
      clusters[c.id] = c;
      clusterByKey[entry.key] = c.id;
    }
    for (final r in groups[key]!) {
      routeClusterSeq[r.id] = [
        for (final s in r.stops)
          if (clusterByKey[nameKey(s.name)] != null)
            clusterByKey[nameKey(s.name)]!,
      ];
    }
  }
  final clusterIds = clusters.keys.toList()..sort();
  for (final id in clusterIds) {
    final c = clusters[id]!;
    if (c.qids.length > 1) {
      err(
        'multiple-wikidata',
        'cluster:$id',
        'Stop nodes of one station carry different Wikidata ids.',
        candidates: {for (final q in c.qids.toList()..sort()) q: q},
      );
    }
    final spread = c.nodes
        .map((n) => haversineM(n.lat, n.lng, c.lat, c.lng))
        .reduce(math.max);
    if (spread > config.maxClusterSpreadM) {
      err(
        'cluster-spread',
        'cluster:$id',
        'Same-name stops of one line are ${spread.round()} m from their centre '
            '(limit ${config.maxClusterSpreadM.round()} m).',
      );
    }
    final hiKeys = {
      for (final n in c.nodes)
        if (n.nameHi != null) nameKey(n.nameHi!),
    };
    if (hiKeys.length > 1) {
      warn(
        'name-hi-inconsistent',
        'cluster:$id',
        'Stop nodes of one station carry different Hindi names.',
        field: 'name_hi',
        candidates: {
          for (final n in c.nodes)
            if (n.nameHi != null) 'osm-node/${n.nodeId}': n.nameHi,
        },
      );
    }
  }

  // ---- C. merging clusters into stations ---------------------------------
  final parent = {for (final id in clusterIds) id: id};
  String find(String x) {
    var r = x;
    while (parent[r] != r) {
      r = parent[r]!;
    }
    return r;
  }

  void union(String a, String b) {
    final ra = find(a);
    final rb = find(b);
    if (ra == rb) return;
    // Keep the smaller id as root so results are order independent.
    if (ra.compareTo(rb) < 0) {
      parent[rb] = ra;
    } else {
      parent[ra] = rb;
    }
  }

  final byQid = <String, List<String>>{};
  for (final id in clusterIds) {
    final c = clusters[id]!;
    if (c.qids.length == 1) byQid.putIfAbsent(c.qids.single, () => []).add(id);
  }
  for (final q in byQid.keys.toList()..sort()) {
    final ids = byQid[q]!;
    final lineSet = {for (final i in ids) clusters[i]!.lineId};
    if (lineSet.length != ids.length) {
      err(
        'wikidata-same-line-duplicate',
        'wikidata:$q',
        'Two stations of the same line carry the Wikidata id $q; not merged.',
        candidates: {for (final i in ids) i: i},
      );
      continue;
    }
    for (var i = 1; i < ids.length; i++) {
      union(ids.first, ids[i]);
    }
  }
  final curatedMergeId = <String, StationMerge>{};
  for (final m in overlay.merges) {
    final unknown = m.members.where((x) => !clusters.containsKey(x)).toList();
    if (unknown.isNotEmpty) {
      err(
        'overlay-unknown-cluster',
        'merge:${m.id}',
        'Curated merge refers to unknown cluster(s): ${unknown.join(', ')}.',
      );
      continue;
    }
    final lineSet = {for (final x in m.members) clusters[x]!.lineId};
    if (lineSet.length != m.members.length) {
      err(
        'overlay-merge-same-line',
        'merge:${m.id}',
        'Curated merge joins two stations of the same line.',
      );
      continue;
    }
    for (var i = 1; i < m.members.length; i++) {
      union(m.members.first, m.members[i]);
    }
    curatedMergeId[find(m.members.first)] = m;
  }
  final stationGroups = <String, List<_Cluster>>{};
  for (final id in clusterIds) {
    stationGroups.putIfAbsent(find(id), () => []).add(clusters[id]!);
  }
  final stations = <_Station>[
    for (final root in stationGroups.keys.toList()..sort())
      _Station(stationGroups[root]!..sort((a, b) => a.id.compareTo(b.id))),
  ];

  // station names, qids, coordinates
  for (final st in stations) {
    final subject = 'station:${st.clusters.first.id}';
    final names = {for (final c in st.clusters) c.name};
    st.nameEn = _mostCommon([
      for (final c in st.clusters) ...[for (final n in c.nodes) n.name],
    ])!;
    if ({for (final n in names) nameKey(n)}.length > 1) {
      final c = warn(
        'name-en-inconsistent',
        subject,
        'Merged stops carry different English names; using the most common.',
        field: 'name_en',
        candidates: {for (final c in st.clusters) c.id: c.name},
      );
      final use = c.resolution?.use;
      if (use != null && use != 'osm') {
        st.nameEn = use;
        st.nameEnStatus = OriginStatus.curatedOverride;
        st.nameEnSource = curatedSourceId;
        st.nameEnDetail = _curationDetail(
          'resolution ${c.id}: use "$use"',
          c.resolution!.curation,
        );
      }
    }
    final qids = {for (final c in st.clusters) ...c.qids};
    st.qid = qids.length == 1 ? qids.single : null;
    st.nameHi = _mostCommon([
      for (final c in st.clusters)
        for (final n in c.nodes)
          if (n.nameHi != null) n.nameHi!,
    ]);
    final all = st.nodes.toList();
    st.lat = round6(all.map((n) => n.lat).reduce((a, b) => a + b) / all.length);
    st.lng = round6(all.map((n) => n.lng).reduce((a, b) => a + b) / all.length);
    final nameKeyEn = nameKey(st.nameEn);
    for (final n in all) {
      for (final a in n.altNames) {
        if (nameKey(a) != nameKeyEn && !st.aliasesEn.contains(a)) {
          st.aliasesEn.add(a);
        }
      }
      for (final a in n.altNamesHi) {
        if (!st.aliasesHi.contains(a)) st.aliasesHi.add(a);
      }
      for (final o in n.oldNames) {
        if (!st.oldNames.contains(o)) st.oldNames.add(o);
      }
    }
    st.aliasesEn.sort();
    st.aliasesHi.sort();
    st.oldNames.sort();
  }

  // station ids (unique, stable)
  final baseCount = <String, int>{};
  for (final st in stations) {
    final merge = curatedMergeId[find(st.clusters.first.id)];
    final base = merge?.id ?? slug(st.nameEn);
    st.id = base;
    baseCount[base] = (baseCount[base] ?? 0) + 1;
  }
  final usedIds = <String>{};
  for (final st in stations) {
    if (baseCount[st.id]! > 1) {
      final lineSuffix = (st.lineIds.toList()..sort()).first;
      st.id = '${st.id}-$lineSuffix';
    }
    var candidate = st.id;
    var n = st.nodes.map((x) => x.nodeId).reduce(math.min);
    while (!usedIds.add(candidate)) {
      candidate = '${st.id}-$n';
      n++;
    }
    st.id = candidate;
  }
  stations.sort((a, b) => a.id.compareTo(b.id));
  final stationOfCluster = <String, _Station>{
    for (final st in stations)
      for (final c in st.clusters) c.id: st,
  };

  // interchange candidates (reported, never applied)
  final stripPattern = config.normalization.candidateStripPattern;
  final candidateRegex = stripPattern == null ? null : RegExp(stripPattern);
  String candidateKey(String name) => nameKey(
    candidateRegex == null ? name : name.replaceAll(candidateRegex, ''),
  );
  for (var i = 0; i < stations.length; i++) {
    for (var j = i + 1; j < stations.length; j++) {
      final a = stations[i];
      final b = stations[j];
      if (candidateKey(a.nameEn) != candidateKey(b.nameEn)) continue;
      if (a.lineIds.intersection(b.lineIds).isNotEmpty) continue;
      final d = haversineM(a.lat, a.lng, b.lat, b.lng).round();
      final near = d <= config.mergeCandidateRadiusM;
      warn(
        near ? 'interchange-candidate' : 'name-collision',
        '${a.id}+${b.id}',
        near
            ? 'Same name on different lines, $d m apart. Probably one '
                  'interchange station; NOT merged without a shared Wikidata '
                  'id or a curated station_merges entry.'
            : 'Same name on different lines but $d m apart; kept separate.',
        candidates: {
          for (final c in [...a.clusters, ...b.clusters]) c.id: c.name,
        },
      );
    }
  }

  // ---- D. Wikidata cross-check and fill ------------------------------------
  var unlinked = 0;
  final unlinkedIds = <String>[];
  for (final st in stations) {
    final subject = 'station:${st.id}';
    final qid = st.qid;
    if (qid == null) {
      unlinked++;
      unlinkedIds.add(st.id);
      continue;
    }
    if (wikidata == null) continue;
    final wd = wikidata.stations[qid];
    if (wd == null) {
      warn(
        'wikidata-entity-missing',
        subject,
        'OSM links to $qid, which is not in the Wikidata download.',
      );
      continue;
    }
    if (wd.labelEn != null && nameKey(wd.labelEn!) != nameKey(st.nameEn)) {
      final c = warn(
        'name-en-mismatch',
        subject,
        'OSM and Wikidata English names differ; keeping OSM unless resolved.',
        field: 'name_en',
        candidates: {'osm': st.nameEn, 'wikidata': wd.labelEn},
      );
      final use = c.resolution?.use;
      if (use == 'wikidata') {
        st.nameEn = wd.labelEn!;
        st.nameEnStatus = OriginStatus.curatedOverride;
        st.nameEnSource = wikidataSourceId;
        st.nameEnDetail = _curationDetail(
          'resolution ${c.id}: use Wikidata label of $qid (OSM had '
          '"${c.candidates['osm']}")',
          c.resolution!.curation,
        );
      } else if (use != null && use != 'osm') {
        st.nameEn = use;
        st.nameEnStatus = OriginStatus.curatedOverride;
        st.nameEnSource = curatedSourceId;
        st.nameEnDetail = _curationDetail(
          'resolution ${c.id}: use "$use"',
          c.resolution!.curation,
        );
      }
    }
    if (wd.labelHi != null) {
      if (st.nameHi == null) {
        st.nameHi = wd.labelHi;
        st.nameHiSource = wikidataSourceId;
        st.nameHiStatus = OriginStatus.normalized;
      } else if (nameKey(wd.labelHi!) != nameKey(st.nameHi!)) {
        final c = warn(
          'name-hi-mismatch',
          subject,
          'OSM and Wikidata Hindi names differ; keeping OSM unless resolved.',
          field: 'name_hi',
          candidates: {'osm': st.nameHi, 'wikidata': wd.labelHi},
        );
        final use = c.resolution?.use;
        if (use == 'wikidata') {
          st.nameHi = wd.labelHi;
          st.nameHiSource = wikidataSourceId;
          st.nameHiStatus = OriginStatus.curatedOverride;
        } else if (use != null && use != 'osm') {
          st.nameHi = use;
          st.nameHiSource = curatedSourceId;
          st.nameHiStatus = OriginStatus.curatedOverride;
        }
      }
    }
    if (wd.lat != null && wd.lng != null) {
      final d = haversineM(st.lat, st.lng, wd.lat!, wd.lng!);
      if (d > config.coordinateConflictM) {
        final c = warn(
          'coordinate-mismatch',
          subject,
          'OSM and Wikidata coordinates are ${d.round()} m apart; keeping OSM unless resolved.',
          field: 'lat_lng',
          candidates: {
            'osm': '${st.lat},${st.lng}',
            'wikidata': '${wd.lat},${wd.lng}',
          },
        );
        if (c.resolution?.use == 'wikidata') {
          st.lat = round6(wd.lat!);
          st.lng = round6(wd.lng!);
          st.coordsFromWikidata = true;
        }
      }
    }
  }

  // ---- E. curated overrides (always reported) ---------------------------------
  final stationById = {for (final st in stations) st.id: st};
  for (final o in overlay.stations) {
    final st = stationById[o.id];
    if (st == null) {
      err(
        'overlay-unknown-station',
        'station:${o.id}',
        'Curated station overlay refers to an unknown station id.',
      );
      continue;
    }
    final target = 'station:${o.id}';
    if (o.nameEn != null) {
      overrides.add(
        OverrideRecord(
          target: target,
          field: 'name_en',
          from: st.nameEn,
          to: o.nameEn,
          curation: o.curation,
        ),
      );
      st.nameEn = o.nameEn!;
      st.curatedNameEn = o.nameEn;
      st.curatedNameEnDetail = _curationDetail(
        'overlay name_en "${o.nameEn}"',
        o.curation,
      );
    }
    if (o.nameHi != null) {
      overrides.add(
        OverrideRecord(
          target: target,
          field: 'name_hi',
          from: st.nameHi,
          to: o.nameHi,
          curation: o.curation,
        ),
      );
      st.nameHi = o.nameHi;
      st.curatedNameHi = o.nameHi;
    }
    if (o.lat != null && o.lng != null) {
      overrides.add(
        OverrideRecord(
          target: target,
          field: 'lat_lng',
          from: '${st.lat},${st.lng}',
          to: '${o.lat},${o.lng}',
          curation: o.curation,
        ),
      );
      st.lat = round6(o.lat!);
      st.lng = round6(o.lng!);
      st.coordsCurated = true;
    } else if (o.lat != null || o.lng != null) {
      err(
        'overlay-bad-coordinate',
        target,
        'Curated override needs both lat and lng.',
      );
    }
    for (final a in o.aliases) {
      (a.lang == 'hi' ? st.aliasesHi : st.aliasesEn).add(a.text);
    }
  }
  final lineIndex = {for (var i = 0; i < lines.length; i++) lines[i].id: i};
  for (final o in overlay.lines) {
    final i = lineIndex[o.id];
    if (i == null) {
      err(
        'overlay-unknown-line',
        'line:${o.id}',
        'Curated line overlay refers to an unknown line id.',
      );
      continue;
    }
    final l = lines[i];
    final target = 'line:${o.id}';
    final color = o.color == null ? null : normalizeColour(o.color);
    if (o.color != null && color == null) {
      err(
        'overlay-bad-colour',
        target,
        'Curated colour "${o.color}" is not a hex colour.',
      );
      continue;
    }
    for (final (field, from, to) in [
      ('name_en', l.nameEn, o.nameEn),
      ('name_hi', l.nameHi, o.nameHi),
      ('short_name', l.shortName, o.shortName),
      ('color_hex', l.colorHex, color),
    ]) {
      if (to != null) {
        overrides.add(
          OverrideRecord(
            target: target,
            field: field,
            from: from,
            to: to,
            curation: o.curation,
          ),
        );
        origins.add(
          Origin(
            entity: 'line',
            entityId: o.id,
            field: field,
            sourceId: curatedSourceId,
            status: from == null
                ? OriginStatus.curated
                : OriginStatus.curatedOverride,
            detail: o.curation.reason,
          ),
        );
      }
    }
    final newColor = color ?? l.colorHex;
    lines[i] = Line(
      id: l.id,
      operatorId: l.operatorId,
      nameEn: o.nameEn ?? l.nameEn,
      nameHi: o.nameHi ?? l.nameHi,
      shortName: o.shortName ?? l.shortName,
      colorHex: newColor,
      textColorHex: contrastText(newColor),
      sort: l.sort,
      status: l.status,
    );
  }

  // ---- F. services, edges, relationships ---------------------------------------
  final services = <LineService>[];
  final serviceStops = <ServiceStop>[];
  final edges = <Edge>[];
  final stationLines = <StationLine>[];
  const derivedProv = Provenance(
    sourceId: derivedSourceId,
    confidence: Confidence.derived,
  );
  final codeOf = <String, String?>{}; // station|line -> code
  for (final st in stations) {
    for (final c in st.clusters) {
      final codes = {
        for (final n in c.nodes)
          if (n.ref != null) n.ref!,
      };
      if (codes.length > 1) {
        warn(
          'station-code-inconsistent',
          'station:${st.id}',
          'Stop nodes carry different station codes on line ${c.lineId}; using the smallest.',
          field: 'station_code',
          candidates: {for (final x in codes) x: x},
        );
      }
      codeOf['${st.id}|${c.lineId}'] = (codes.toList()..sort()).firstOrNull;
    }
  }
  // A station code must identify one station per line; ambiguous codes are
  // reported and left unknown (null) instead of guessing which station owns it.
  final codeOwners = <String, List<String>>{};
  codeOf.forEach((k, code) {
    if (code != null) {
      codeOwners
          .putIfAbsent('${k.split('|').last}|$code', () => [])
          .add(k.split('|').first);
    }
  });
  for (final e
      in codeOwners.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    if (e.value.length < 2) continue;
    final parts = e.key.split('|');
    warn(
      'station-code-duplicate',
      'line:${parts[0]}|code:${parts[1]}',
      'Station code ${parts[1]} is used by ${e.value.length} stations of line ${parts[0]}; left unknown (null).',
      field: 'station_code',
      candidates: {for (final s in e.value) s: parts[1]},
    );
    for (final s in e.value) {
      codeOf['$s|${parts[0]}'] = null;
    }
  }
  for (final key in sortedGroupKeys) {
    final lineId = lineIdByGroup[key];
    if (lineId == null) continue;
    final patterns = <String, List<OsmRoute>>{};
    final patternSeq = <String, List<String>>{};
    for (final r in groups[key]!) {
      var seq = <String>[];
      for (final cid in routeClusterSeq[r.id] ?? const <String>[]) {
        final sid = stationOfCluster[cid]!.id;
        if (seq.isEmpty || seq.last != sid) seq.add(sid);
      }
      if (seq.length < 2) continue;
      final rev = seq.reversed.toList();
      if (rev.join('>').compareTo(seq.join('>')) < 0) seq = rev;
      final k = seq.join('>');
      patterns.putIfAbsent(k, () => []).add(r);
      patternSeq[k] = seq;
    }
    final seen = <String>{};
    for (final k in patterns.keys.toList()..sort()) {
      final seq = patternSeq[k]!;
      final rels = patterns[k]!..sort((a, b) => a.id.compareTo(b.id));
      var sid = '$lineId-${seq.first}-${seq.last}';
      if (!seen.add(sid)) sid = '$sid-r${rels.first.id}';
      seen.add(sid);
      final visited = <String>{};
      final revisited = <String>{};
      for (final id in seq) {
        if (!visited.add(id)) revisited.add(id);
      }
      final isLoop = seq.length > 2 && seq.first == seq.last;
      if (revisited.length > (isLoop ? 1 : 0)) {
        warn(
          'service-revisits-station',
          'service:$sid',
          'The route passes ${(revisited.toList()..sort()).join(', ')} more '
              'than once. Kept as in OSM (a loop with a spur is real '
              'topology); routing must handle it.',
          candidates: {for (final r in rels) 'relation/${r.id}': r.name},
        );
      }
      services.add(
        LineService(
          id: sid,
          lineId: lineId,
          name: rels.first.name,
          isLoop: seq.length > 2 && seq.first == seq.last,
        ),
      );
      origins.add(
        Origin(
          entity: 'line_service',
          entityId: sid,
          field: 'record',
          sourceId: osmSourceId,
          status: OriginStatus.normalized,
          externalId: rels.map((r) => 'relation/${r.id}').join(';'),
          detail:
              'stop order of the route relation(s); opposite directions '
              'folded into one service',
        ),
      );
      var dist = 0.0;
      for (var i = 0; i < seq.length; i++) {
        final st = stationById[seq[i]]!;
        if (i > 0) {
          final prev = stationById[seq[i - 1]]!;
          final step = haversineM(prev.lat, prev.lng, st.lat, st.lng);
          dist += step;
          final metres = step.round();
          for (final (from, to) in [(prev.id, st.id), (st.id, prev.id)]) {
            edges.add(
              Edge(
                id: '$sid:$from>$to',
                serviceId: sid,
                fromStation: from,
                toStation: to,
                distanceM: metres,
                provenance: derivedProv,
              ),
            );
          }
        }
        serviceStops.add(
          ServiceStop(
            serviceId: sid,
            seq: i,
            stationId: st.id,
            distFromStartM: dist.round(),
          ),
        );
      }
    }
  }
  for (final st in stations) {
    for (final lineId in st.lineIds.toList()..sort()) {
      stationLines.add(
        StationLine(
          stationId: st.id,
          lineId: lineId,
          stationCode: codeOf['${st.id}|$lineId'],
        ),
      );
    }
  }
  final transfers = <Transfer>[];
  for (final st in stations) {
    final ls = st.lineIds.toList()..sort();
    // The interchange itself may be curated (verified against a cited
    // reference); its walking distance/time is still unknown (NULL).
    final curatedMerge = curatedMergeId[find(st.clusters.first.id)];
    final transferProv = curatedMerge == null
        ? derivedProv
        : Provenance(
            sourceId: curatedSourceId,
            confidence: Confidence.verified,
            verifiedOn: curatedMerge.curation.verifiedOn,
          );
    for (final a in ls) {
      for (final b in ls) {
        if (a == b) continue;
        transfers.add(
          Transfer(
            stationId: st.id,
            fromLine: a,
            toLine: b,
            provenance: transferProv,
          ),
        );
      }
    }
  }

  // ---- G. assemble ----------------------------------------------------------
  const osmProv = Provenance(
    sourceId: osmSourceId,
    confidence: Confidence.community,
  );
  final outStations = <Station>[];
  final names = <StationName>[];
  for (final st in stations) {
    outStations.add(
      Station(
        id: st.id,
        nameEn: st.nameEn,
        nameHi: st.nameHi,
        lat: st.lat,
        lng: st.lng,
        status: OperatingStatus.open,
        provenance: osmProv,
      ),
    );
    names.add(
      StationName(
        stationId: st.id,
        text: st.nameEn,
        lang: 'en',
        kind: NameKind.official,
      ),
    );
    if (st.nameHi != null) {
      names.add(
        StationName(
          stationId: st.id,
          text: st.nameHi!,
          lang: 'hi',
          kind: NameKind.official,
        ),
      );
    }
    final seenNames = <String>{
      'en|${st.nameEn}|official',
      if (st.nameHi != null) 'hi|${st.nameHi}|official',
    };
    void alias(String text, String lang, NameKind kind) {
      if (seenNames.add('$lang|$text|${kind.wire}')) {
        names.add(
          StationName(stationId: st.id, text: text, lang: lang, kind: kind),
        );
      }
    }

    for (final a in st.aliasesEn) {
      alias(a, 'en', NameKind.alias);
    }
    for (final a in st.aliasesHi) {
      alias(a, 'hi', NameKind.alias);
    }
    for (final o in st.oldNames) {
      alias(o, 'en', NameKind.old);
    }
    final nodeIds = (st.nodes.map((n) => 'node/${n.nodeId}').toList()..sort())
        .join(';');
    origins.add(
      Origin(
        entity: 'station',
        entityId: st.id,
        field: 'record',
        sourceId: osmSourceId,
        status: OriginStatus.imported,
        externalId: nodeIds,
      ),
    );
    origins.add(
      Origin(
        entity: 'station',
        entityId: st.id,
        field: 'name_en',
        sourceId: st.curatedNameEn != null ? curatedSourceId : st.nameEnSource,
        status: st.curatedNameEn != null
            ? OriginStatus.curatedOverride
            : st.nameEnStatus,
        externalId: st.nameEnSource == wikidataSourceId ? st.qid : null,
        detail: st.curatedNameEn != null
            ? st.curatedNameEnDetail
            : st.nameEnDetail,
      ),
    );
    if (st.nameHi != null) {
      origins.add(
        Origin(
          entity: 'station',
          entityId: st.id,
          field: 'name_hi',
          sourceId: st.curatedNameHi != null
              ? curatedSourceId
              : st.nameHiSource,
          status: st.curatedNameHi != null
              ? OriginStatus.curatedOverride
              : st.nameHiStatus,
          externalId: st.nameHiSource == wikidataSourceId ? st.qid : null,
        ),
      );
    }
    origins.add(
      Origin(
        entity: 'station',
        entityId: st.id,
        field: 'lat_lng',
        sourceId: st.coordsCurated
            ? curatedSourceId
            : st.coordsFromWikidata
            ? wikidataSourceId
            : st.nodes.length > 1
            ? derivedSourceId
            : osmSourceId,
        status: st.coordsCurated
            ? OriginStatus.curatedOverride
            : st.coordsFromWikidata
            ? OriginStatus.curatedOverride
            : st.nodes.length > 1
            ? OriginStatus.derived
            : OriginStatus.imported,
        detail:
            st.nodes.length > 1 && !st.coordsCurated && !st.coordsFromWikidata
            ? 'mean of ${st.nodes.length} stop nodes'
            : null,
      ),
    );
    if (st.qid != null) {
      origins.add(
        Origin(
          entity: 'station',
          entityId: st.id,
          field: 'wikidata',
          sourceId: osmSourceId,
          status: OriginStatus.imported,
          externalId: st.qid,
        ),
      );
    }
    if (st.clusters.length > 1) {
      final byCurated = curatedMergeId[find(st.clusters.first.id)] != null;
      origins.add(
        Origin(
          entity: 'station',
          entityId: st.id,
          field: 'merge',
          sourceId: byCurated ? curatedSourceId : osmSourceId,
          status: byCurated ? OriginStatus.curated : OriginStatus.derived,
          detail: byCurated
              ? _curationDetail(
                  'merged ${st.clusters.map((c) => c.id).join(' + ')}',
                  curatedMergeId[find(st.clusters.first.id)]!.curation,
                )
              : 'merged ${st.clusters.map((c) => c.id).join(' + ')} '
                    '(shared Wikidata id ${st.qid})',
        ),
      );
    }
  }

  // sources
  final sources = <Source>[];
  for (final r in config.remote) {
    final e = lock[r.id];
    if (e == null) continue;
    sources.add(
      Source(
        id: r.id,
        name: r.name,
        url: e.endpoint,
        license: r.license,
        retrievedAt: e.retrievedAt,
        version: e.sourceVersion ?? e.retrievedAt,
        sha256: e.sha256,
        notes:
            '${r.attribution} Licence: ${r.licenseUrl}. Records: ${e.records}.',
      ),
    );
  }
  for (final l in config.local) {
    sources.add(
      Source(
        id: l.id,
        name: l.name,
        license: l.license,
        notes: l.notes,
        version: l.id == curatedSourceId ? overlay.sha256 : null,
        sha256: l.id == curatedSourceId ? overlay.sha256 : null,
      ),
    );
  }
  sources.sort((a, b) => a.id.compareTo(b.id));

  final builtAt = lock.latestRetrievedAt ?? '1970-01-01T00:00:00Z';
  final built = DateTime.parse(builtAt);
  final meta = <String, String>{
    MetaKeys.datasetVersion:
        '${built.year}.${built.month.toString().padLeft(2, '0')}.${overlay.patch}',
    MetaKeys.schemaVersion: '$currentSchemaVersion',
    MetaKeys.builtAt: builtAt,
    MetaKeys.city: config.city,
    MetaKeys.bbox: config.bbox,
    MetaKeys.attribution: [
      for (final r in config.remote)
        if (lock[r.id] != null) r.attribution,
      'MetroMitra curated overlays and derived values. MetroMitra is not affiliated with DMRC.',
    ].join(' '),
  };

  log.reportUnmatchedResolutions();

  final snapshot = MetroSnapshot(
    meta: meta,
    sources: sources,
    operators: operatorsById.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id)),
    lines: lines,
    services: services..sort((a, b) => a.id.compareTo(b.id)),
    serviceStops: serviceStops
      ..sort((a, b) {
        final c = a.serviceId.compareTo(b.serviceId);
        return c != 0 ? c : a.seq.compareTo(b.seq);
      }),
    stations: outStations,
    stationNames: names
      ..sort((a, b) {
        final k = '${a.stationId}|${a.kind.wire}|${a.lang}|${a.text}'.compareTo(
          '${b.stationId}|${b.kind.wire}|${b.lang}|${b.text}',
        );
        return k;
      }),
    stationLines: stationLines,
    edges: edges..sort((a, b) => a.id.compareTo(b.id)),
    transfers: transfers,
    origins: _dedupe(origins)..sort((a, b) => a.key.compareTo(b.key)),
  );

  final conflicts = log.all
    ..sort((a, b) {
      final s = a.severity.index.compareTo(b.severity.index);
      return s != 0 ? s : a.id.compareTo(b.id);
    });
  return MergeResult(
    snapshot: snapshot,
    conflicts: conflicts,
    overrides: overrides,
    stats: {
      'osm_routes': osm.routes.length,
      'lines': lines.length,
      'stations': stations.length,
      'services': services.length,
      'edges': edges.length,
      'stations_with_wikidata': stations.length - unlinked,
      'stations_without_wikidata': unlinked,
      'stations_without_wikidata_ids': unlinkedIds,
      'stations_without_hindi_name': stations
          .where((s) => s.nameHi == null)
          .length,
      'interchange_stations': stations
          .where((s) => s.lineIds.length > 1)
          .length,
      'merge_candidates': conflicts
          .where((c) => c.kind == 'interchange-candidate')
          .length,
    },
  );
}

List<Origin> _dedupe(List<Origin> list) {
  final byKey = <String, Origin>{};
  for (final o in list) {
    byKey[o.key] = o; // later (curated) rows win over earlier ones
  }
  return byKey.values.toList();
}
