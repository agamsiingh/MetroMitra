import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/network.dart';
import 'package:metro_core/src/model/provenance.dart';

enum SearchKind { station, line }

enum SearchScope { all, stations, lines }

/// How a result matched, strongest first (docs/search.md, ADR-041).
enum MatchTier {
  /// Normalised official name equals the query.
  exact,

  /// Normalised alias / old name / misspelling / landmark / station code
  /// equals the query.
  alias,

  /// The query is the start of a name (or each query word starts the
  /// corresponding leading word).
  prefix,

  /// The query occurs inside a name, or its words start words of the name in
  /// any order.
  substring,

  /// Within a small edit distance, phonetically equal (also across Hindi and
  /// Latin script), or equal apart from spacing.
  fuzzy,
}

/// Which stored value matched.
enum MatchField {
  nameEn,
  nameHi,
  alias,
  oldName,
  misspelling,
  landmark,
  stationCode,
  lineShortName,
}

class SearchMatch {
  const SearchMatch({
    required this.tier,
    required this.field,
    required this.matchedText,
    required this.score,
    this.edits = 0,
    this.phonetic = false,
  });

  final MatchTier tier;
  final MatchField field;

  /// The stored text that matched, exactly as in the dataset.
  final String matchedText;

  /// Higher is better. Tier bands never overlap: exact 1000, alias 900,
  /// name prefix 800 / alias prefix 700, name substring 600 / alias
  /// substring 500, fuzzy 400 / 350 minus 50 per edit.
  final int score;
  final int edits;

  /// Matched through the phonetic skeleton (spelling variants, Hindi vs Latin).
  final bool phonetic;

  @override
  String toString() =>
      'SearchMatch(${tier.name}, ${field.name}, "$matchedText", $score)';
}

class StationLineRef {
  const StationLineRef({
    required this.lineId,
    required this.lineNameEn,
    required this.colorHex,
    required this.operatorId,
    this.lineNameHi,
    this.stationCode,
  });

  final String lineId;
  final String lineNameEn;
  final String? lineNameHi;
  final String colorHex;
  final String operatorId;

  /// null = no code in the dataset.
  final String? stationCode;
}

/// Everything shown for a station hit. Values are copied from the dataset;
/// unknown stays null (a missing Hindi name is never filled in).
class StationSummary {
  const StationSummary({
    required this.id,
    required this.nameEn,
    required this.lat,
    required this.lng,
    required this.status,
    required this.provenance,
    required this.lines,
    required this.serviceIds,
    required this.aliases,
    required this.popularity,
    this.nameHi,
  });

  final String id;
  final String nameEn;
  final String? nameHi;
  final double lat;
  final double lng;
  final OperatingStatus status;
  final Provenance provenance;
  final int popularity;

  /// Lines serving the station, in line sort order.
  final List<StationLineRef> lines;
  final List<String> serviceIds;

  /// Every non-official name (alias, old, misspelling, landmark).
  final List<StationName> aliases;

  /// Served by two or more lines.
  bool get isInterchange => lines.length >= 2;
}

class LineSummary {
  const LineSummary({
    required this.id,
    required this.operatorId,
    required this.nameEn,
    required this.colorHex,
    required this.status,
    required this.serviceIds,
    required this.stationCount,
    this.nameHi,
    this.shortName,
  });

  final String id;
  final String operatorId;
  final String nameEn;
  final String? nameHi;
  final String? shortName;
  final String colorHex;
  final OperatingStatus status;
  final List<String> serviceIds;
  final int stationCount;
}

class SearchResult {
  const SearchResult.station(StationSummary this.station, this.match)
    : kind = SearchKind.station,
      line = null;

  const SearchResult.line(LineSummary this.line, this.match)
    : kind = SearchKind.line,
      station = null;

  final SearchKind kind;
  final SearchMatch match;
  final StationSummary? station;
  final LineSummary? line;

  String get entityId => kind == SearchKind.station ? station!.id : line!.id;
}

class SearchOptions {
  const SearchOptions({
    this.limit = 20,
    this.scope = SearchScope.all,
    this.onlyOpen = true,
  });

  final int limit;
  final SearchScope scope;

  /// Hide closed / planned stations and lines (default: a rider cannot use
  /// them).
  final bool onlyOpen;
}
