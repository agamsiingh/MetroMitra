import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:yaml/yaml.dart';

/// One official line (or branch) compared with the built dataset.
class ReferenceRow {
  const ReferenceRow({
    required this.no,
    required this.name,
    required this.officialStations,
    required this.officialKm,
    required this.datasetStations,
    required this.datasetKm,
    required this.accepted,
  });

  final String no;
  final String name;
  final int officialStations;
  final double officialKm;

  /// Distinct stations on the matching services; null when the line is not
  /// in the dataset at all.
  final int? datasetStations;

  /// Sum of the matching services' lengths (from `dist_from_start_m`).
  final double? datasetKm;

  /// The difference is documented in the reference file's `accepted` list.
  final bool accepted;

  bool get countMatches => datasetStations == officialStations;

  /// Dataset length as a share of the official length (1.0 = equal).
  double? get lengthRatio =>
      datasetKm == null || officialKm == 0 ? null : datasetKm! / officialKm;
}

class ReferenceReport {
  const ReferenceReport(this.rows, this.officialTotal, this.datasetTotal);

  final List<ReferenceRow> rows;
  final int officialTotal;

  /// Sum of the per-line counts the way the reference counts them (a station
  /// on two DMRC lines counts twice).
  final int datasetTotal;

  /// Count mismatches nobody has explained yet.
  List<ReferenceRow> get unexplained => [
    for (final r in rows)
      if (!r.countMatches && !r.accepted) r,
  ];
}

/// Compares per-line station counts and lengths with an official reference
/// (`data/curated/reference/*.yaml`). Read-only: nothing in the dataset is
/// changed, and the reference never becomes data.
ReferenceReport checkReference(MetroSnapshot snapshot, YamlMap reference) {
  final accepted = {
    for (final a in (reference['accepted'] as YamlList?) ?? YamlList())
      '${(a as YamlMap)['line']}',
  };
  final stopsByService = <String, List<ServiceStop>>{};
  for (final s in snapshot.serviceStops) {
    (stopsByService[s.serviceId] ??= []).add(s);
  }
  final rows = <ReferenceRow>[];
  var datasetTotal = 0;
  for (final raw in reference['lines'] as YamlList) {
    final l = raw as YamlMap;
    final lineId = l['line'] as String;
    final serviceId = l['service'] as String?;
    final services = [
      for (final s in snapshot.services)
        if (s.lineId == lineId && (serviceId == null || s.id == serviceId)) s,
    ];
    int? count;
    double? km;
    if (services.isNotEmpty) {
      final stations = <String>{};
      var metres = 0;
      for (final s in services) {
        final stops = stopsByService[s.id] ?? const [];
        stations.addAll(stops.map((x) => x.stationId));
        if (stops.isNotEmpty) {
          metres += stops
              .map((x) => x.distFromStartM)
              .reduce((a, b) => a > b ? a : b);
        }
      }
      count = stations.length;
      km = metres / 1000;
      datasetTotal += count;
    }
    rows.add(
      ReferenceRow(
        no: '${l['no']}',
        name: l['name'] as String,
        officialStations: l['stations'] as int,
        officialKm: (l['km'] as num).toDouble(),
        datasetStations: count,
        datasetKm: km,
        accepted: accepted.contains('${l['no']}'),
      ),
    );
  }
  return ReferenceReport(
    rows,
    reference['dmrc_total_stations'] as int,
    datasetTotal,
  );
}

/// Plain-text table for the CLI and the docs.
List<String> formatReference(ReferenceReport r) => [
  'line | official stations | dataset | official km | dataset km (ratio)',
  for (final x in r.rows)
    '${x.no} ${x.name} | ${x.officialStations} | '
        '${x.datasetStations ?? 'missing'}'
        '${x.countMatches ? '' : (x.accepted ? ' (accepted)' : ' MISMATCH')} | '
        '${x.officialKm.toStringAsFixed(3)} | '
        '${x.datasetKm?.toStringAsFixed(3) ?? '-'}'
        '${x.lengthRatio == null ? '' : ' (${(x.lengthRatio! * 100).round()} %)'}',
  'total | ${r.officialTotal} | ${r.datasetTotal}',
];
