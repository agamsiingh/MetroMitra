import 'package:metro_core/metro_core.dart' hide Platform;
import 'package:metromitra/bootstrap/metro_services.dart';

/// A line serving a station, with the colours the dataset gives it.
class LineChipData {
  const LineChipData({
    required this.lineId,
    required this.nameEn,
    required this.colorHex,
    required this.textColorHex,
    this.nameHi,
    this.code,
  });

  final String lineId;
  final String nameEn;
  final String? nameHi;
  final String colorHex;
  final String textColorHex;

  /// Station code on this line; null = none in the dataset.
  final String? code;
}

/// One row of the station picker. [id] is the canonical station id: it is
/// what selecting a row returns; names are display only.
class StationOption {
  const StationOption({
    required this.id,
    required this.nameEn,
    required this.lines,
    required this.isInterchange,
    required this.isSimilar,
    this.nameHi,
    this.matchedText,
  });

  final String id;
  final String nameEn;
  final String? nameHi;
  final List<LineChipData> lines;
  final bool isInterchange;

  /// Text of an alias / old name / code the query matched, when the match was
  /// not on the station's own name (so the row can say why it is listed).
  final String? matchedText;

  /// A fuzzy ("did you mean") match rather than a direct one.
  final bool isSimilar;
}

class PickerResults {
  const PickerResults({
    required this.query,
    this.direct = const [],
    this.similar = const [],
  });

  final String query;
  final List<StationOption> direct;
  final List<StationOption> similar;

  bool get isBlank => query.trim().isEmpty;
  bool get isEmpty => direct.isEmpty && similar.isEmpty;
}

/// Searches stations only (open stations), via the M4 index, and turns the
/// results into picker rows. Deterministic: same dataset + query, same rows.
PickerResults searchStationOptions(
  MetroServices services,
  String query, {
  int limit = 20,
}) {
  if (query.trim().isEmpty) return PickerResults(query: query);
  final results = services.search.search(
    query,
    options: SearchOptions(scope: SearchScope.stations, limit: limit),
  );
  final direct = <StationOption>[];
  final similar = <StationOption>[];
  for (final r in results) {
    final s = r.station!;
    final fuzzy = r.match.tier == MatchTier.fuzzy;
    final option = StationOption(
      id: s.id,
      nameEn: s.nameEn,
      nameHi: s.nameHi,
      isInterchange: s.isInterchange,
      isSimilar: fuzzy,
      matchedText: switch (r.match.field) {
        MatchField.nameEn || MatchField.nameHi => null,
        _ => r.match.matchedText,
      },
      lines: [
        for (final l in s.lines)
          LineChipData(
            lineId: l.lineId,
            nameEn: l.lineNameEn,
            nameHi: l.lineNameHi,
            colorHex: l.colorHex,
            textColorHex:
                services.snapshot.line(l.lineId)?.textColorHex ?? '#FFFFFF',
            code: l.stationCode,
          ),
      ],
    );
    (fuzzy ? similar : direct).add(option);
  }
  return PickerResults(query: query, direct: direct, similar: similar);
}

/// Display data for a station id, or null if the id is not in the dataset.
StationOption? stationOptionFor(MetroServices services, String id) {
  final s = services.snapshot.station(id);
  if (s == null) return null;
  return StationOption(
    id: s.id,
    nameEn: s.nameEn,
    nameHi: s.nameHi,
    isInterchange: services.snapshot.linesAt(id).length >= 2,
    isSimilar: false,
    lines: [
      for (final l in services.snapshot.linesAt(id))
        LineChipData(
          lineId: l.id,
          nameEn: l.nameEn,
          nameHi: l.nameHi,
          colorHex: l.colorHex,
          textColorHex: l.textColorHex,
        ),
    ],
  );
}
