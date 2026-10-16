import 'package:metro_core/metro_core.dart';

/// One-line text for a search result (CLI).
String describeSearchResult(SearchResult r) {
  final m = r.match;
  final how =
      '${m.tier.name}/${m.field.name}'
      '${m.edits > 0 ? ' ~${m.edits}' : ''}${m.phonetic ? ' phonetic' : ''}'
      ' "${m.matchedText}" ${m.score}';
  final s = r.station;
  if (s != null) {
    final lines = s.lines
        .map(
          (l) => l.stationCode == null
              ? l.lineNameEn
              : '${l.lineNameEn} (${l.stationCode})',
        )
        .join(', ');
    return '${s.nameEn} | ${s.nameHi ?? '-'} | $lines'
        '${s.isInterchange ? ' | interchange' : ''}'
        ' | ${s.lat},${s.lng} | [$how] #${s.id}';
  }
  final l = r.line!;
  return 'LINE ${l.nameEn} | ${l.nameHi ?? '-'} | ${l.stationCount} stations'
      ' | [$how] #${l.id}';
}

Map<String, Object?> searchResultJson(SearchResult r) {
  final m = r.match;
  final match = {
    'tier': m.tier.name,
    'field': m.field.name,
    'matched_text': m.matchedText,
    'score': m.score,
    'edits': m.edits,
    'phonetic': m.phonetic,
  };
  final s = r.station;
  if (s != null) {
    return {
      'kind': 'station',
      'id': s.id,
      'name_en': s.nameEn,
      'name_hi': s.nameHi,
      'lat': s.lat,
      'lng': s.lng,
      'status': s.status.wire,
      'interchange': s.isInterchange,
      'lines': [
        for (final l in s.lines)
          {
            'id': l.lineId,
            'name_en': l.lineNameEn,
            'name_hi': l.lineNameHi,
            'color': l.colorHex,
            'station_code': l.stationCode,
          },
      ],
      'services': s.serviceIds,
      'aliases': [
        for (final a in s.aliases)
          {'text': a.text, 'lang': a.lang, 'kind': a.kind.wire},
      ],
      'provenance': {
        'source': s.provenance.sourceId,
        'confidence': s.provenance.confidence.wire,
        'verified_on': s.provenance.verifiedOn,
      },
      'match': match,
    };
  }
  final l = r.line!;
  return {
    'kind': 'line',
    'id': l.id,
    'name_en': l.nameEn,
    'name_hi': l.nameHi,
    'short_name': l.shortName,
    'color': l.colorHex,
    'status': l.status.wire,
    'services': l.serviceIds,
    'station_count': l.stationCount,
    'match': match,
  };
}

/// The `search` section of build-report.json: how searchable the data is and
/// whether every station can be found by its own names and codes.
Map<String, Object?> searchReport(MetroSnapshot s) {
  final index = SearchIndex.fromSnapshot(s);
  final problems = index.selfCheck();
  return {
    'searchable_entities': index.entityCount,
    'searchable_names_and_codes': index.entryCount,
    'stations_without_hindi_name': s.stations
        .where((x) => x.nameHi == null)
        .length,
    'aliases': s.stationNames.where((n) => n.kind != NameKind.official).length,
    'station_codes': s.stationLines.where((l) => l.stationCode != null).length,
    'self_check_problems': problems.length,
    'self_check_examples': problems.take(10).toList(),
  };
}
