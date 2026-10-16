import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/network.dart';
import 'package:metro_core/src/model/snapshot.dart';
import 'package:metro_core/src/search/edit_distance.dart';
import 'package:metro_core/src/search/normalizer.dart';
import 'package:metro_core/src/search/search_models.dart';

class _Entity {
  const _Entity({
    required this.station,
    required this.line,
    required this.primary,
    required this.popularity,
    required this.open,
  });

  final StationSummary? station;
  final LineSummary? line;

  /// Normalised primary name length, for tie-breaking (shorter first).
  final int primary;
  final int popularity;
  final bool open;

  SearchKind get kind => station != null ? SearchKind.station : SearchKind.line;
  String get id => station?.id ?? line!.id;
  String get sortName => station?.nameEn ?? line!.nameEn;
}

class _Entry {
  const _Entry({
    required this.entity,
    required this.field,
    required this.original,
    required this.text,
    required this.isName,
    this.isCode = false,
  });

  final int entity;
  final MatchField field;
  final String original;
  final NormalizedText text;

  /// Official name (en/hi) as opposed to alias-class values.
  final bool isName;

  /// Station codes: exact and prefix matches only.
  final bool isCode;
}

// Score bands (docs/search.md). Bands never overlap, so a lower tier can never
// outrank a higher one; the small "closeness" bonus stays below 50.
const _exactName = 1000;
const _exactAlias = 900;
const _prefixName = 800;
const _prefixAlias = 700;
const _substringName = 600;
const _substringAlias = 500;
const _fuzzyName = 400;
const _fuzzyAlias = 350;
const _editPenalty = 50;

/// Deterministic in-memory search over a [MetroSnapshot]: stations (English
/// and Hindi names, aliases, old names, misspellings, landmarks, station
/// codes) and lines. Nothing here touches the network or the clock; the same
/// snapshot and query always give the same ordered result.
///
/// Ranking (ADR-041): exact name > exact alias/code > prefix > substring >
/// fuzzy; inside a band by closeness, then popularity, then shorter name,
/// then name and id. Results never contain data that is not in the dataset: a
/// missing Hindi name stays null even though Hindi queries can *match* English
/// names phonetically.
class SearchIndex {
  SearchIndex._(this._normalizer, this._entities, this._entries);

  factory SearchIndex.fromSnapshot(
    MetroSnapshot s, {
    SearchConfig? config,
  }) {
    final normalizer = SearchNormalizer(
      config ?? SearchConfig.fromMeta(s.meta),
    );
    final entities = <_Entity>[];
    final entries = <_Entry>[];

    final linesById = {for (final l in s.lines) l.id: l};
    final sortedLines = [...s.lines]..sort((a, b) => a.sort.compareTo(b.sort));
    final lineRank = {
      for (var i = 0; i < sortedLines.length; i++) sortedLines[i].id: i,
    };
    final stationLinesBy = <String, List<StationLine>>{};
    for (final sl in s.stationLines) {
      stationLinesBy.putIfAbsent(sl.stationId, () => []).add(sl);
    }
    final namesBy = <String, List<StationName>>{};
    for (final n in s.stationNames) {
      namesBy.putIfAbsent(n.stationId, () => []).add(n);
    }
    final servicesAt = <String, Set<String>>{};
    final stationsOfLine = <String, Set<String>>{};
    final lineOfService = {for (final v in s.services) v.id: v.lineId};
    for (final st in s.serviceStops) {
      servicesAt.putIfAbsent(st.stationId, () => {}).add(st.serviceId);
      final line = lineOfService[st.serviceId];
      if (line != null) {
        stationsOfLine.putIfAbsent(line, () => {}).add(st.stationId);
      }
    }

    for (final st in [...s.stations]..sort((a, b) => a.id.compareTo(b.id))) {
      final refs = [
        for (final sl in stationLinesBy[st.id] ?? const <StationLine>[])
          if (linesById[sl.lineId] != null)
            StationLineRef(
              lineId: sl.lineId,
              lineNameEn: linesById[sl.lineId]!.nameEn,
              lineNameHi: linesById[sl.lineId]!.nameHi,
              colorHex: linesById[sl.lineId]!.colorHex,
              operatorId: linesById[sl.lineId]!.operatorId,
              stationCode: sl.stationCode,
            ),
      ]..sort((a, b) => lineRank[a.lineId]!.compareTo(lineRank[b.lineId]!));
      final aliases = [
        for (final n in namesBy[st.id] ?? const <StationName>[])
          if (n.kind != NameKind.official) n,
      ];
      final summary = StationSummary(
        id: st.id,
        nameEn: st.nameEn,
        nameHi: st.nameHi,
        lat: st.lat,
        lng: st.lng,
        status: st.status,
        provenance: st.provenance,
        popularity: st.popularity,
        lines: List.unmodifiable(refs),
        serviceIds: List.unmodifiable(
          (servicesAt[st.id] ?? const <String>{}).toList()..sort(),
        ),
        aliases: List.unmodifiable(aliases),
      );
      final index = entities.length;
      final primary = normalizer.normalize(st.nameEn);
      entities.add(
        _Entity(
          station: summary,
          line: null,
          primary: primary.text.length,
          popularity: st.popularity,
          open: st.status == OperatingStatus.open,
        ),
      );

      final seen = <String>{};
      void add(
        MatchField field,
        String text, {
        required bool isName,
        bool isCode = false,
      }) {
        final n = isCode
            ? NormalizedText([normalizer.foldCompact(text)], const [])
            : normalizer.normalize(text);
        if (n.isEmpty || n.text.isEmpty) return;
        if (!seen.add('${isCode ? 'c' : 'n'}|${n.text}|${field.name}')) return;
        entries.add(
          _Entry(
            entity: index,
            field: field,
            original: text,
            text: n,
            isName: isName,
            isCode: isCode,
          ),
        );
      }

      add(MatchField.nameEn, st.nameEn, isName: true);
      if (st.nameHi != null) add(MatchField.nameHi, st.nameHi!, isName: true);
      for (final n in namesBy[st.id] ?? const <StationName>[]) {
        if (n.kind == NameKind.official) {
          add(
            n.lang == 'hi' ? MatchField.nameHi : MatchField.nameEn,
            n.text,
            isName: true,
          );
        } else {
          add(
            switch (n.kind) {
              NameKind.old => MatchField.oldName,
              NameKind.misspelling => MatchField.misspelling,
              NameKind.landmark => MatchField.landmark,
              _ => MatchField.alias,
            },
            n.text,
            isName: false,
          );
        }
      }
      for (final r in refs) {
        if (r.stationCode != null) {
          add(
            MatchField.stationCode,
            r.stationCode!,
            isName: false,
            isCode: true,
          );
        }
      }
    }

    for (final l in sortedLines) {
      final index = entities.length;
      final summary = LineSummary(
        id: l.id,
        operatorId: l.operatorId,
        nameEn: l.nameEn,
        nameHi: l.nameHi,
        shortName: l.shortName,
        colorHex: l.colorHex,
        status: l.status,
        serviceIds: List.unmodifiable(
          [
            for (final v in s.services)
              if (v.lineId == l.id) v.id,
          ]..sort(),
        ),
        stationCount: (stationsOfLine[l.id] ?? const <String>{}).length,
      );
      entities.add(
        _Entity(
          station: null,
          line: summary,
          primary: normalizer.normalize(l.nameEn).text.length,
          popularity: 0,
          open: l.status == OperatingStatus.open,
        ),
      );
      void add(MatchField f, String text, {required bool isName}) {
        final n = normalizer.normalize(text);
        if (n.isEmpty) return;
        entries.add(
          _Entry(
            entity: index,
            field: f,
            original: text,
            text: n,
            isName: isName,
          ),
        );
      }

      add(MatchField.nameEn, l.nameEn, isName: true);
      if (l.nameHi != null) add(MatchField.nameHi, l.nameHi!, isName: true);
      if (l.shortName != null) {
        add(MatchField.lineShortName, l.shortName!, isName: false);
      }
    }
    return SearchIndex._(normalizer, entities, entries);
  }

  final SearchNormalizer _normalizer;
  final List<_Entity> _entities;
  final List<_Entry> _entries;

  int get entityCount => _entities.length;
  int get entryCount => _entries.length;

  /// Ranked results for [query]; empty for a blank query or no match. A query
  /// that is only punctuation or whitespace finds nothing.
  List<SearchResult> search(
    String query, {
    SearchOptions options = const SearchOptions(),
  }) {
    final q = _normalizer.normalize(query);
    if (q.isEmpty || q.text.isEmpty) return const [];
    final rawCompact = _normalizer.foldCompact(query);
    final best = <int, SearchMatch>{};
    for (final e in _entries) {
      final ent = _entities[e.entity];
      if (options.onlyOpen && !ent.open) continue;
      if (options.scope == SearchScope.stations &&
          ent.kind != SearchKind.station) {
        continue;
      }
      if (options.scope == SearchScope.lines && ent.kind != SearchKind.line) {
        continue;
      }
      final m = _match(q, rawCompact, e);
      if (m == null) continue;
      final prior = best[e.entity];
      if (prior == null || _betterMatch(m, prior)) best[e.entity] = m;
    }
    final ids = best.keys.toList()
      ..sort((a, b) {
        final ma = best[a]!;
        final mb = best[b]!;
        var c = mb.score.compareTo(ma.score);
        if (c != 0) return c;
        final ea = _entities[a];
        final eb = _entities[b];
        c = eb.popularity.compareTo(ea.popularity);
        if (c != 0) return c;
        c = ea.primary.compareTo(eb.primary);
        if (c != 0) return c;
        c = ea.kind.index.compareTo(eb.kind.index);
        if (c != 0) return c;
        c = ea.sortName.compareTo(eb.sortName);
        if (c != 0) return c;
        return ea.id.compareTo(eb.id);
      });
    final limit = options.limit < 1 ? 0 : options.limit;
    return [
      for (final i in ids.take(limit))
        _entities[i].station != null
            ? SearchResult.station(_entities[i].station!, best[i]!)
            : SearchResult.line(_entities[i].line!, best[i]!),
    ];
  }

  static bool _betterMatch(SearchMatch a, SearchMatch b) {
    if (a.score != b.score) return a.score > b.score;
    if (a.edits != b.edits) return a.edits < b.edits;
    if (a.field.index != b.field.index) return a.field.index < b.field.index;
    return a.matchedText.compareTo(b.matchedText) < 0;
  }

  SearchMatch? _match(NormalizedText q, String rawCompact, _Entry e) {
    SearchMatch make(
      MatchTier tier,
      int base, {
      int bonus = 0,
      int edits = 0,
      bool phonetic = false,
    }) => SearchMatch(
      tier: tier,
      field: e.field,
      matchedText: e.original,
      score: base + bonus - edits * _editPenalty,
      edits: edits,
      phonetic: phonetic,
    );

    if (e.isCode) {
      final code = e.text.tokens.single;
      if (rawCompact == code) return make(MatchTier.alias, _exactAlias);
      if (rawCompact.isNotEmpty && code.startsWith(rawCompact)) {
        return make(
          MatchTier.prefix,
          _prefixAlias,
          bonus: _closeness(code.length, rawCompact.length),
        );
      }
      return null;
    }

    final qt = q.text;
    final nt = e.text.text;
    if (qt == nt) {
      return e.isName
          ? make(MatchTier.exact, _exactName)
          : make(MatchTier.alias, _exactAlias);
    }
    if (_isPrefix(q, e.text)) {
      return make(
        MatchTier.prefix,
        e.isName ? _prefixName : _prefixAlias,
        bonus: _closeness(nt.length, qt.length),
      );
    }
    final cfg = _normalizer.config;
    if (q.compact.length >= cfg.minSubstringLength && _isSubstring(q, e.text)) {
      return make(
        MatchTier.substring,
        e.isName ? _substringName : _substringAlias,
        bonus: _closeness(nt.length, qt.length),
      );
    }
    return _fuzzy(q, e, make);
  }

  static int _closeness(int nameLen, int queryLen) {
    final extra = nameLen - queryLen;
    return 49 - (extra < 0 ? 0 : (extra > 49 ? 49 : extra));
  }

  static bool _isPrefix(NormalizedText q, NormalizedText n) {
    if (n.text.startsWith(q.text)) return true;
    if (q.tokens.length > 1 && q.tokens.length <= n.tokens.length) {
      for (var i = 0; i < q.tokens.length; i++) {
        if (!n.tokens[i].startsWith(q.tokens[i])) return false;
      }
      return true;
    }
    return false;
  }

  static bool _isSubstring(NormalizedText q, NormalizedText n) {
    if (n.text.contains(q.text)) return true;
    if (q.tokens.length < 2) return false;
    // every query word starts a different word of the name, in any order
    final used = List<bool>.filled(n.tokens.length, false);
    for (final t in q.tokens) {
      var found = false;
      for (var i = 0; i < n.tokens.length; i++) {
        if (!used[i] && n.tokens[i].startsWith(t)) {
          used[i] = true;
          found = true;
          break;
        }
      }
      if (!found) return false;
    }
    return true;
  }

  /// Edits allowed by query length: none below 4 characters (short queries
  /// must not turn into random hits), 1 for 4-7, 2 from 8.
  static int _maxEdits(int length) => length < 4 ? 0 : (length < 8 ? 1 : 2);

  SearchMatch? _fuzzy(
    NormalizedText q,
    _Entry e,
    SearchMatch Function(
      MatchTier,
      int, {
      int bonus,
      int edits,
      bool phonetic,
    })
    make,
  ) {
    final base = e.isName ? _fuzzyName : _fuzzyAlias;
    final n = e.text;
    final qc = q.compact;
    final nc = n.compact;
    final maxE = _maxEdits(q.compactLength);

    // Same letters, different spacing ("jorbagh" / "jor bagh").
    if (qc == nc) return make(MatchTier.fuzzy, base);
    // Same pronunciation skeleton (spelling variants, Hindi vs Latin script).
    final qk = q.compactKey;
    final nk = n.compactKey;
    if (qk.runes.length >= 3 && qk == nk) {
      return make(MatchTier.fuzzy, base, phonetic: true);
    }
    if (maxE == 0) return null;

    int? bestEdits;
    var phonetic = false;
    // [d] is already within its bound; [penalty] only affects the score so
    // that a whole-name typo outranks a typo in one word of a longer name.
    void consider(int? d, {required bool byKey, int penalty = 0}) {
      if (d == null) return;
      final total = d + penalty;
      if (bestEdits == null || total < bestEdits!) {
        bestEdits = total;
        phonetic = byKey;
      }
    }

    // Phonetic distances need a skeleton long enough to mean something
    // ("zzzzzz" collapses to "j", which must not match short names).
    int? keyDistance(String a, String b) {
      final la = a.length;
      final lb = b.length;
      final shorter = la < lb ? la : lb;
      if (shorter < 3 || (la - lb).abs() > 2) return null;
      return boundedEditDistance(
        a,
        b,
        _maxEdits(shorter) < maxE ? _maxEdits(shorter) : maxE,
      );
    }

    if ((q.compactLength - n.compactLength).abs() <= maxE) {
      consider(boundedEditDistance(qc, nc, maxE), byKey: false);
    }
    consider(keyDistance(qk, nk), byKey: true);
    // Typo in a leading part of a longer name ("kashmre ga").
    if (maxE >= 2) {
      for (var len = qc.length - 1; len <= qc.length + 1; len++) {
        if (len > 0 && len < nc.length) {
          consider(
            boundedEditDistance(qc, nc.substring(0, len), maxE - 1),
            byKey: false,
            penalty: 1,
          );
        }
      }
    }
    // One misspelt word of a longer name ("kamal" for "kamla gate").
    if (q.tokens.length == 1 && n.tokens.length > 1) {
      for (var i = 0; i < n.tokens.length; i++) {
        if ((qc.length - n.tokens[i].length).abs() <= maxE) {
          consider(
            boundedEditDistance(qc, n.tokens[i], maxE),
            byKey: false,
            penalty: 1,
          );
        }
        consider(keyDistance(qk, n.keyTokens[i]), byKey: true, penalty: 1);
      }
    }
    final b = bestEdits;
    if (b == null) return null;
    return make(MatchTier.fuzzy, base, edits: b, phonetic: phonetic);
  }

  /// Looks every station up by its own official names, aliases and codes.
  /// Official names must come first (tied results from stations with the same
  /// normalised name are accepted); other names and codes must appear in the
  /// results. Returns human-readable problems (empty = healthy). Used by the
  /// pipeline `search --self-check` to guard real data.
  List<String> selfCheck() {
    final problems = <String>[];
    const options = SearchOptions(limit: 50, onlyOpen: false);
    for (final e in _entries) {
      final ent = _entities[e.entity];
      final st = ent.station;
      if (st == null) continue;
      final results = search(e.original, options: options);
      final mine = results.where((r) => r.station?.id == st.id).firstOrNull;
      if (mine == null) {
        problems.add('${st.id}: "${e.original}" (${e.field.name}) not found');
        continue;
      }
      final isOfficial =
          e.field == MatchField.nameEn || e.field == MatchField.nameHi;
      if (isOfficial && mine.match.score < results.first.match.score) {
        problems.add(
          '${st.id}: "${e.original}" ranks below '
          '${results.first.entityId} (${results.first.match})',
        );
      }
    }
    return problems;
  }
}
