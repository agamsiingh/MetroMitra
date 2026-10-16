import 'package:metro_core/src/assistant/assistant_models.dart';
import 'package:metro_core/src/assistant/lexicon.dart';
import 'package:metro_core/src/fare/fare_engine.dart';
import 'package:metro_core/src/fare/fare_quote.dart';
import 'package:metro_core/src/journey/journey.dart';
import 'package:metro_core/src/model/enums.dart';
import 'package:metro_core/src/model/provenance.dart';
import 'package:metro_core/src/model/snapshot.dart';
import 'package:metro_core/src/routing/itinerary.dart';
import 'package:metro_core/src/routing/route_planner.dart';
import 'package:metro_core/src/search/normalizer.dart';
import 'package:metro_core/src/search/search_index.dart';
import 'package:metro_core/src/search/search_models.dart';

/// When/what for fare and timing answers. Supplied by the caller (no clock
/// in here).
class AssistantContext {
  const AssistantContext({
    this.dayType = DayType.regular,
    this.minuteOfDay,
  });

  final DayType dayType;
  final int? minuteOfDay;
}

/// A place mentioned in the question, resolved through the search index.
class _Place {
  _Place(
    this.start,
    this.end,
    this.text,
    this.candidates, {
    this.isLine = false,
  });

  final int start;
  final int end; // exclusive
  final String text;

  /// Canonical ids; more than one = ambiguous.
  final List<String> candidates;
  final bool isLine;
  AssistantSlot? role;
}

/// Outcome of reading the question.
class _Reading {
  _Reading(this.intent, this.places, this.unresolved, this.tokens);

  final AssistantIntent intent;
  final List<_Place> places;

  /// Content words that are not a known place.
  final List<String> unresolved;
  final List<String> tokens;
}

/// The offline assistant (docs/ai.md, deterministic part): rules + lexicon
/// intent detection, slot filling through the search index, handlers over
/// metro_core services, answers as templates + facts. It never produces free
/// text and never guesses a place: an unknown name is "not found", two equal
/// matches are a question back to the user.
class OfflineAssistant {
  OfflineAssistant({
    required this.snapshot,
    required this.search,
    required this.planner,
    required this.fares,
  });

  final MetroSnapshot snapshot;
  final SearchIndex search;
  final RoutePlanner planner;
  final FareEngine fares;

  /// Lowest match score a non-exact place may have (docs/ai.md: unknown names
  /// never fall through to fuzzy guessing below the minimum score).
  static const minPlaceScore = 300;

  /// Longest place name, in words, looked for.
  static const maxPlaceWords = 6;

  String get _version => snapshot.datasetVersion ?? '';

  // ------------------------------------------------------------------ public

  /// Answers [text]. Never throws for any input.
  AssistantAnswer ask(
    String text, {
    AssistantContext context = const AssistantContext(),
  }) {
    final r = _read(text);
    if (r.intent == AssistantIntent.unknown) return _unknown();
    // Words that are not a known place matter only when a place the intent
    // needs is missing: then the unknown words are taken as that place and
    // reported "not found" (never matched to something else).
    final q0 = _fill(r);
    if (r.unresolved.isNotEmpty &&
        !r.places.any((p) => p.candidates.length > 1) &&
        !_hasRequiredSlots(q0)) {
      return _notFound(r.intent, r.unresolved.join(' '));
    }
    // an ambiguous place: ask which one
    for (final p in r.places) {
      if (p.candidates.length > 1) {
        final q = _fill(r);
        return AssistantAnswer(
          intent: r.intent,
          kind: AnswerKind.clarify,
          template: AnswerTemplate.clarifyStation,
          datasetVersion: _version,
          facts: {'text': p.text},
          choices: p.candidates,
          slot: p.role ?? _defaultSlot(r.intent),
          question: q,
        );
      }
    }
    return answer(_fill(r), context: context);
  }

  static bool _hasRequiredSlots(ParsedQuestion q) => switch (q.intent) {
    AssistantIntent.route ||
    AssistantIntent.fare ||
    AssistantIntent.interchange => q.fromId != null && q.toId != null,
    AssistantIntent.platform => q.stationId != null && q.destinationId != null,
    AssistantIntent.firstLast ||
    AssistantIntent.gateExit ||
    AssistantIntent.facilities ||
    AssistantIntent.accessibility ||
    AssistantIntent.parking => q.stationId != null,
    AssistantIntent.lineInfo => q.lineId != null,
    AssistantIntent.nearestStation || AssistantIntent.unknown => true,
  };

  /// Answers an already understood question (also used after the user
  /// picked a station for a clarification).
  AssistantAnswer answer(
    ParsedQuestion q, {
    AssistantContext context = const AssistantContext(),
  }) {
    for (final id in [q.fromId, q.toId, q.stationId, q.destinationId]) {
      if (id != null && snapshot.station(id) == null) {
        return _notFound(q.intent, id);
      }
    }
    return switch (q.intent) {
      AssistantIntent.route => _route(q),
      AssistantIntent.nearestStation => AssistantAnswer(
        intent: q.intent,
        kind: AnswerKind.answer,
        template: AnswerTemplate.nearestOpen,
        datasetVersion: _version,
        actions: const [OpenNearbyAction()],
      ),
      AssistantIntent.gateExit => _gates(q),
      AssistantIntent.platform => _platform(q),
      AssistantIntent.fare => _fare(q, context),
      AssistantIntent.firstLast => _firstLast(q, context),
      AssistantIntent.interchange => _interchange(q),
      AssistantIntent.facilities => _facilities(q),
      AssistantIntent.accessibility => _accessibility(q),
      AssistantIntent.parking => _parking(q),
      AssistantIntent.lineInfo => _lineInfo(q),
      AssistantIntent.unknown => _unknown(),
    };
  }

  /// The question as understood, without answering (for tests/diagnostics).
  ParsedQuestion understand(String text) => _fill(_read(text));

  // ------------------------------------------------------------------ reading

  static final _punctuation = RegExp(
    r'[?!.,;:।|/\\()\[\]{}"“”‘’`]',
  );

  /// Lower-case words; punctuation is a separator, apostrophes are dropped.
  static List<String> tokenize(String text) => text
      .toLowerCase()
      .replaceAll("'", '')
      .replaceAll(_punctuation, ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  static bool _isMarker(String t) =>
      AssistantLexicon.fromBefore.contains(t) ||
      AssistantLexicon.fromAfter.contains(t) ||
      AssistantLexicon.toBefore.contains(t) ||
      AssistantLexicon.toAfter.contains(t) ||
      AssistantLexicon.atBefore.contains(t) ||
      AssistantLexicon.atAfter.contains(t);

  static bool _isFiller(String t) =>
      AssistantLexicon.filler.contains(t) || _isMarker(t);

  _Reading _read(String text) {
    final tokens = tokenize(text);
    if (tokens.length > 40) tokens.removeRange(40, tokens.length);
    final used = List<bool>.filled(tokens.length, false);
    final places = <_Place>[];

    // 1. places named exactly (official name, alias, code), longest first
    var i = 0;
    while (i < tokens.length) {
      _Place? found;
      if (!_isFiller(tokens[i])) {
        final maxLen = (tokens.length - i).clamp(0, maxPlaceWords);
        for (var len = maxLen; len >= 1 && found == null; len--) {
          // a name may end in a common word ("... Main", "Blue Line") but
          // never swallow a "to"/"from" marker after it
          if (_isMarker(tokens[i + len - 1])) continue;
          // nor span a "to" / "from" / "se" in the middle (saves searches)
          if (len > 2 && tokens.sublist(i + 1, i + len - 1).any(_isMarker)) {
            continue;
          }
          final phrase = tokens.sublist(i, i + len).join(' ');
          if (len == 1 && phrase.runes.length < 3) continue;
          if (len == 1 && _isLexiconWord(phrase)) continue;
          found = _exact(i, i + len, phrase);
        }
      }
      if (found != null) {
        places.add(found);
        for (var k = found.start; k < found.end; k++) {
          used[k] = true;
        }
        i = found.end;
      } else {
        i++;
      }
    }

    // 2. intent words (phrases first) among the remaining words
    final scores = <AssistantIntentWord, int>{};
    for (var k = 0; k + 1 < tokens.length; k++) {
      if (used[k] || used[k + 1]) continue;
      final pair = '${tokens[k]} ${tokens[k + 1]}';
      for (final e in AssistantLexicon.intentWords.entries) {
        final w = e.value[pair];
        if (w != null) {
          scores[e.key] = (scores[e.key] ?? 0) + w;
          used[k] = used[k + 1] = true;
        }
      }
    }
    for (var k = 0; k < tokens.length; k++) {
      if (used[k]) continue;
      var hit = false;
      for (final e in AssistantLexicon.intentWords.entries) {
        final w = e.value[tokens[k]];
        if (w != null) {
          scores[e.key] = (scores[e.key] ?? 0) + w;
          hit = true;
        }
      }
      if (hit && !_isFiller(tokens[k])) used[k] = true;
    }
    for (var k = 0; k < tokens.length; k++) {
      final t = tokens[k];
      if (AssistantLexicon.firstWords.contains(t) ||
          AssistantLexicon.lastWords.contains(t) ||
          AssistantLexicon.cardWords.contains(t)) {
        used[k] = true;
      }
    }

    // 3. other content words: a place by a looser match, or unknown
    final unresolved = <String>[];
    var k = 0;
    while (k < tokens.length) {
      if (used[k] || _isFiller(tokens[k])) {
        k++;
        continue;
      }
      var end = k;
      while (end < tokens.length && !used[end] && !_isFiller(tokens[end])) {
        end++;
      }
      final chunk = tokens.sublist(k, end).join(' ');
      final p = _loose(k, end, chunk);
      if (p == null) {
        unresolved.add(chunk);
      } else {
        places.add(p);
      }
      k = end;
    }
    places.sort((a, b) => a.start.compareTo(b.start));

    // 4. roles from the words around each place
    for (final p in places) {
      final before = p.start > 0 ? tokens[p.start - 1] : null;
      final after = p.end < tokens.length ? tokens[p.end] : null;
      final after2 = p.end + 1 < tokens.length ? tokens[p.end + 1] : null;
      if (AssistantLexicon.fromAfter.contains(after) ||
          AssistantLexicon.fromBefore.contains(before)) {
        p.role = AssistantSlot.from;
      } else if (AssistantLexicon.toBefore.contains(before) ||
          AssistantLexicon.toAfter.contains(after) ||
          (after == 'ke' && after2 == 'liye') ||
          (after == 'के' && after2 == 'लिए')) {
        p.role = AssistantSlot.to;
      } else if (AssistantLexicon.atBefore.contains(before) ||
          AssistantLexicon.atAfter.contains(after)) {
        p.role = AssistantSlot.station;
      }
    }

    // 5. the intent
    var intent = AssistantIntent.unknown;
    var best = 0;
    for (final w in AssistantLexicon.intentPriority) {
      final s = scores[w] ?? 0;
      if (s > best) {
        best = s;
        intent = _intentOf(w);
      }
    }
    final stations = places.where((p) => !p.isLine).length;
    final lines = places.where((p) => p.isLine).length;
    if (intent == AssistantIntent.lineInfo && lines == 0) {
      intent = stations > 0 ? AssistantIntent.route : AssistantIntent.unknown;
    }
    if (intent == AssistantIntent.unknown) {
      if (stations >= 1) {
        intent = AssistantIntent.route;
      } else if (lines >= 1) {
        intent = AssistantIntent.lineInfo;
      }
    }
    if (intent == AssistantIntent.route && stations == 0 && lines >= 1) {
      intent = AssistantIntent.lineInfo;
    }
    return _Reading(intent, places, unresolved, tokens);
  }

  bool _isLexiconWord(String t) =>
      AssistantLexicon.intentWords.values.any((m) => m.containsKey(t)) ||
      AssistantLexicon.firstWords.contains(t) ||
      AssistantLexicon.lastWords.contains(t) ||
      AssistantLexicon.cardWords.contains(t);

  static AssistantIntent _intentOf(AssistantIntentWord w) => switch (w) {
    AssistantIntentWord.route => AssistantIntent.route,
    AssistantIntentWord.nearest => AssistantIntent.nearestStation,
    AssistantIntentWord.gate => AssistantIntent.gateExit,
    AssistantIntentWord.platform => AssistantIntent.platform,
    AssistantIntentWord.fare => AssistantIntent.fare,
    AssistantIntentWord.firstLast => AssistantIntent.firstLast,
    AssistantIntentWord.interchange => AssistantIntent.interchange,
    AssistantIntentWord.facilities => AssistantIntent.facilities,
    AssistantIntentWord.accessibility => AssistantIntent.accessibility,
    AssistantIntentWord.parking => AssistantIntent.parking,
    AssistantIntentWord.lineInfo => AssistantIntent.lineInfo,
  };

  static const _searchOptions = SearchOptions(limit: 8, onlyOpen: false);

  /// A place whose official name, alias or code equals [phrase].
  _Place? _exact(int start, int end, String phrase) {
    final results = search.search(phrase, options: _searchOptions);
    final exact = [
      for (final r in results)
        if (r.match.tier == MatchTier.exact || r.match.tier == MatchTier.alias)
          r,
    ];
    if (exact.isEmpty) return null;
    final top = exact.first.match.score;
    final tied = [
      for (final r in exact)
        if (r.match.score == top) r,
    ];
    return _placeOf(start, end, phrase, tied);
  }

  /// A place matched less strictly (prefix, words in any order, small typo);
  /// below [minPlaceScore] it is not a match at all.
  _Place? _loose(int start, int end, String phrase) {
    final results = search.search(phrase, options: _searchOptions);
    if (results.isEmpty || results.first.match.score < minPlaceScore) {
      return null;
    }
    // Every entity matched at the best tier counts: a closer score (e.g. a
    // shorter name) is not a reason to pick one, so several = ask the user.
    final tier = results.first.match.tier;
    final tied = [
      for (final r in results)
        if (r.match.tier == tier && r.match.score >= minPlaceScore) r,
    ];
    return _placeOf(start, end, phrase, tied.take(5).toList());
  }

  _Place _placeOf(int start, int end, String text, List<SearchResult> rs) {
    // prefer stations over lines when both match equally
    final stations = [
      for (final r in rs)
        if (r.station != null) r.station!.id,
    ];
    if (stations.isNotEmpty) {
      return _Place(start, end, text, stations.toSet().toList());
    }
    return _Place(
      start,
      end,
      text,
      {for (final r in rs) r.line!.id}.toList(),
      isLine: true,
    );
  }

  AssistantSlot _defaultSlot(AssistantIntent i) => switch (i) {
    AssistantIntent.route ||
    AssistantIntent.fare ||
    AssistantIntent.interchange => AssistantSlot.to,
    _ => AssistantSlot.station,
  };

  /// Puts the places into the intent's slots.
  ParsedQuestion _fill(_Reading r) {
    // an ambiguous place fills no slot (the user is asked which one)
    String? single(_Place p) =>
        p.candidates.length == 1 ? p.candidates.first : null;
    final stations = [
      for (final p in r.places)
        if (!p.isLine) p,
    ];
    final line = r.places.where((p) => p.isLine && p.candidates.length == 1);
    final tokens = r.tokens.toSet();
    final first = tokens.any(AssistantLexicon.firstWords.contains);
    final last = tokens.any(AssistantLexicon.lastWords.contains);
    FacilityType? facility;
    for (var k = 0; k < r.tokens.length; k++) {
      final pair = k + 1 < r.tokens.length
          ? '${r.tokens[k]} ${r.tokens[k + 1]}'
          : null;
      facility ??=
          (pair == null ? null : AssistantLexicon.facilityTypes[pair]) ??
          AssistantLexicon.facilityTypes[r.tokens[k]];
    }

    String? from;
    String? to;
    String? at;
    final unassigned = <_Place>[];
    for (final p in stations) {
      switch (p.role) {
        case AssistantSlot.from:
          from ??= single(p);
        case AssistantSlot.to || AssistantSlot.destination:
          to ??= single(p);
        case AssistantSlot.station:
          at ??= single(p);
        case null:
          unassigned.add(p);
      }
    }

    switch (r.intent) {
      case AssistantIntent.route ||
          AssistantIntent.fare ||
          AssistantIntent.interchange:
        from ??= at;
        for (final p in unassigned) {
          if (from == null && (to != null || unassigned.length > 1)) {
            from = single(p);
            p.role = AssistantSlot.from;
          } else if (to == null) {
            to = single(p);
            p.role = AssistantSlot.to;
          } else {
            from ??= single(p);
          }
        }
        return ParsedQuestion(
          intent: r.intent,
          fromId: from,
          toId: to,
          wantsCard: tokens.any(AssistantLexicon.cardWords.contains),
        );
      case AssistantIntent.platform || AssistantIntent.firstLast:
        var station = at ?? from;
        var dest = to;
        for (final p in unassigned) {
          if (station == null) {
            station = single(p);
            p.role = AssistantSlot.station;
          } else {
            dest ??= single(p);
            p.role ??= AssistantSlot.destination;
          }
        }
        if (station == null &&
            dest != null &&
            r.intent == AssistantIntent.firstLast) {
          // "last metro to X" without a start: X is the station asked about
          station = dest;
          dest = null;
        }
        return ParsedQuestion(
          intent: r.intent,
          stationId: station,
          destinationId: dest,
          lineId: line.isEmpty ? null : line.first.candidates.first,
          wantsFirst: first,
          wantsLast: last,
        );
      case AssistantIntent.nearestStation ||
          AssistantIntent.gateExit ||
          AssistantIntent.facilities ||
          AssistantIntent.accessibility ||
          AssistantIntent.parking ||
          AssistantIntent.lineInfo ||
          AssistantIntent.unknown:
        final station =
            at ??
            from ??
            to ??
            (unassigned.isEmpty ? null : single(unassigned.first));
        for (final p in stations) {
          p.role ??= AssistantSlot.station;
        }
        return ParsedQuestion(
          intent: r.intent,
          stationId: station,
          lineId: line.isEmpty ? null : line.first.candidates.first,
          facility: facility,
          landmark:
              r.intent == AssistantIntent.gateExit && r.unresolved.isNotEmpty
              ? r.unresolved.join(' ')
              : null,
        );
    }
  }

  // ------------------------------------------------------------------ answers

  AssistantAnswer _ask(
    ParsedQuestion q,
    AnswerTemplate t,
    AssistantSlot slot,
  ) => AssistantAnswer(
    intent: q.intent,
    kind: AnswerKind.clarify,
    template: t,
    datasetVersion: _version,
    slot: slot,
    question: q,
    actions: [PickStationAction(slot)],
  );

  AssistantAnswer _notFound(AssistantIntent intent, String text) =>
      AssistantAnswer(
        intent: intent,
        kind: AnswerKind.notFound,
        template: AnswerTemplate.stationNotFound,
        datasetVersion: _version,
        facts: {'text': text},
      );

  AssistantAnswer _unknown() => AssistantAnswer(
    intent: AssistantIntent.unknown,
    kind: AnswerKind.unknown,
    template: AnswerTemplate.unknown,
    datasetVersion: _version,
  );

  AssistantAnswer _missing(
    ParsedQuestion q,
    AnswerTemplate t,
    Map<String, Object> facts, {
    List<AssistantAction> actions = const [],
  }) => AssistantAnswer(
    intent: q.intent,
    kind: AnswerKind.missing,
    template: t,
    datasetVersion: _version,
    facts: facts,
    actions: actions,
  );

  AssistantAnswer _ok(
    ParsedQuestion q,
    AnswerTemplate t,
    Map<String, Object> facts, {
    List<Provenance> sources = const [],
    List<AssistantAction> actions = const [],
  }) => AssistantAnswer(
    intent: q.intent,
    kind: AnswerKind.answer,
    template: t,
    datasetVersion: _version,
    facts: facts,
    sources: _distinct(sources),
    actions: actions,
  );

  static List<Provenance> _distinct(List<Provenance> ps) {
    final seen = <String>{};
    return [
      for (final p in ps)
        if (seen.add('${p.sourceId}|${p.confidence.wire}|${p.verifiedOn}')) p,
    ];
  }

  /// A routed itinerary, or an answer explaining why there is none.
  (Itinerary?, AssistantAnswer?) _itinerary(
    ParsedQuestion q, {
    FareRequest fareRequest = const FareRequest(),
  }) {
    final from = q.fromId;
    final to = q.toId;
    if (to == null) {
      return (null, _ask(q, AnswerTemplate.askTo, AssistantSlot.to));
    }
    if (from == null) {
      return (null, _ask(q, AnswerTemplate.askFrom, AssistantSlot.from));
    }
    final r = planner.plan(from, to, fareRequest: fareRequest);
    return switch (r.status) {
      RouteStatus.ok => (r.itineraries.first, null),
      RouteStatus.sameStation => (
        null,
        _ok(q, AnswerTemplate.routeSameStation, {'stationId': from}),
      ),
      RouteStatus.unknownStation => (null, _notFound(q.intent, r.detail ?? '')),
      RouteStatus.notServed || RouteStatus.noRoute => (
        null,
        _missing(q, AnswerTemplate.routeNone, {'fromId': from, 'toId': to}),
      ),
    };
  }

  // facts: fromId, toId, minutes, approx (bool), changes, stops,
  //        lineIds (List<String>), transferIds (List<String>)
  AssistantAnswer _route(ParsedQuestion q) {
    final (it, problem) = _itinerary(q);
    if (problem != null) return problem;
    return _ok(
      q,
      AnswerTemplate.routeSummary,
      {
        'fromId': q.fromId!,
        'toId': q.toId!,
        'minutes': (it!.totalTimeS / 60).round(),
        'approx': it.timeIsEstimate,
        'changes': it.changes,
        'stops': it.stops,
        'lineIds': _lines(it),
        'transferIds': _transfers(it),
      },
      sources: [for (final r in it.rides) ...r.provenance],
      actions: [OpenRouteAction(q.fromId!, q.toId!)],
    );
  }

  static List<String> _lines(Itinerary it) {
    final out = <String>[];
    for (final r in it.rides) {
      if (!out.contains(r.lineId)) out.add(r.lineId);
    }
    return out;
  }

  static List<String> _transfers(Itinerary it) => [
    for (final l in it.legs)
      if (l is TransferLeg && l.kind != TransferKind.throughRunning)
        l.stationId,
  ];

  // interchangeAt: fromId, toId, transferIds, lineIds | interchangeNone
  AssistantAnswer _interchange(ParsedQuestion q) {
    final (it, problem) = _itinerary(q);
    if (problem != null) return problem;
    final transfers = _transfers(it!);
    final facts = <String, Object>{
      'fromId': q.fromId!,
      'toId': q.toId!,
      'lineIds': _lines(it),
      'transferIds': transfers,
    };
    final actions = [OpenRouteAction(q.fromId!, q.toId!)];
    return transfers.isEmpty
        ? _ok(q, AnswerTemplate.interchangeNone, facts, actions: actions)
        : _ok(q, AnswerTemplate.interchangeAt, facts, actions: actions);
  }

  // fareFound: fromId, toId, paise, currency, cardPaise?, dayType,
  //            separateTicket (bool)
  AssistantAnswer _fare(ParsedQuestion q, AssistantContext c) {
    final request = FareRequest(
      dayType: c.dayType,
      minuteOfDay: c.minuteOfDay,
    );
    final (it, problem) = _itinerary(q, fareRequest: request);
    if (problem != null) return problem;
    final quote = it!.fare ?? fares.quote(it.legs, request);
    final facts = <String, Object>{'fromId': q.fromId!, 'toId': q.toId!};
    final actions = [OpenRouteAction(q.fromId!, q.toId!)];
    if (quote.status != FareStatus.available || quote.totalPaise == null) {
      return _missing(q, AnswerTemplate.fareMissing, facts, actions: actions);
    }
    final hasCard = snapshot.fareDiscounts.any(
      (d) => d.media == FareMedia.smartCard,
    );
    final card = hasCard
        ? fares.quote(
            it.legs,
            FareRequest(
              dayType: c.dayType,
              media: FareMedia.smartCard,
              minuteOfDay: c.minuteOfDay,
            ),
          )
        : null;
    return _ok(
      q,
      AnswerTemplate.fareFound,
      {
        ...facts,
        'paise': quote.totalPaise!,
        'currency': quote.currency ?? '',
        'dayType': c.dayType,
        'separateTicket': quote.separateTicket,
        if (card != null &&
            card.status == FareStatus.available &&
            card.totalPaise != null)
          'cardPaise': card.totalPaise!,
      },
      sources: [
        if (quote.confidence != null)
          Provenance(sourceId: 'fare', confidence: quote.confidence!),
      ],
      actions: actions,
    );
  }

  // gatesList: stationId, gates (List<GateInfo>)
  // gateForLandmark: stationId, landmark, gates | gateLandmarkUnknown
  AssistantAnswer _gates(ParsedQuestion q) {
    final id = q.stationId;
    if (id == null) {
      return _ask(q, AnswerTemplate.askStation, AssistantSlot.station);
    }
    final gates = JourneyPlan.gatesAt(snapshot, id);
    final open = OpenStationAction(id);
    if (gates.isEmpty) {
      return _missing(
        q,
        AnswerTemplate.gatesMissing,
        {'stationId': id},
        actions: [open],
      );
    }
    final landmark = q.landmark;
    if (landmark != null) {
      final want = _fold(landmark);
      final hits = [
        for (final g in gates)
          if ([
            ...g.landmarksEn,
            ...g.landmarksHi.whereType<String>(),
          ].any((l) => _fold(l).contains(want) || want.contains(_fold(l))))
            g,
      ];
      if (hits.isEmpty) {
        return _missing(
          q,
          AnswerTemplate.gateLandmarkUnknown,
          {'stationId': id, 'landmark': landmark, 'gates': gates},
          actions: [open],
        );
      }
      return _ok(
        q,
        AnswerTemplate.gateForLandmark,
        {'stationId': id, 'landmark': landmark, 'gates': hits},
        sources: [for (final g in hits) g.provenance],
        actions: [open],
      );
    }
    return _ok(
      q,
      AnswerTemplate.gatesList,
      {'stationId': id, 'gates': gates},
      sources: [for (final g in gates) g.provenance],
      actions: [open],
    );
  }

  static String _fold(String s) =>
      const SearchNormalizer(SearchConfig()).normalize(s).text;

  // platformFound: stationId, destinationId, lineId, towardsId?, number,
  //                verified (bool)
  AssistantAnswer _platform(ParsedQuestion q) {
    final id = q.stationId;
    if (id == null) {
      return _ask(q, AnswerTemplate.askStation, AssistantSlot.station);
    }
    final dest = q.destinationId;
    if (dest == null) {
      return _ask(q, AnswerTemplate.askDestination, AssistantSlot.destination);
    }
    final (it, problem) = _itinerary(
      ParsedQuestion(intent: q.intent, fromId: id, toId: dest),
    );
    if (problem != null) return problem;
    final ride = it!.rides.first;
    final p = JourneyPlan.platformFor(snapshot, ride);
    if (p == null) {
      return _missing(
        q,
        AnswerTemplate.platformMissing,
        {'stationId': id, 'destinationId': dest, 'lineId': ride.lineId},
        actions: [OpenStationAction(id)],
      );
    }
    final verified =
        p.provenance.confidence == Confidence.official ||
        p.provenance.confidence == Confidence.verified;
    return _ok(
      q,
      AnswerTemplate.platformFound,
      {
        'stationId': id,
        'destinationId': dest,
        'lineId': ride.lineId,
        'towardsId': ?ride.directionTerminalId,
        'number': p.number,
        'verified': verified,
      },
      sources: [p.provenance],
      actions: [OpenStationAction(id)],
    );
  }

  // firstLastFound: stationId, rows (List<TimingFact>), first, last (bool),
  //                 dayType
  AssistantAnswer _firstLast(ParsedQuestion q, AssistantContext c) {
    final id = q.stationId;
    if (id == null) {
      return _ask(q, AnswerTemplate.askStation, AssistantSlot.station);
    }
    var rows = [
      for (final t in snapshot.timingsAt(id))
        if (t.dayType == c.dayType) t,
    ];
    final dest = q.destinationId;
    if (dest != null && rows.isNotEmpty) {
      final r = planner.plan(id, dest);
      if (r.status == RouteStatus.ok) {
        final ride = r.itineraries.first.rides.first;
        rows = [
          for (final t in rows)
            if (t.serviceId == ride.serviceId &&
                t.directionTerminalId == ride.directionTerminalId)
              t,
        ];
      } else {
        rows = const [];
      }
    }
    if (rows.isEmpty) {
      return _missing(
        q,
        AnswerTemplate.firstLastMissing,
        {'stationId': id, 'dayType': c.dayType},
        actions: [OpenStationAction(id)],
      );
    }
    rows.sort((a, b) {
      final x = a.directionTerminalId.compareTo(b.directionTerminalId);
      return x != 0 ? x : a.serviceId.compareTo(b.serviceId);
    });
    final both = q.wantsFirst == q.wantsLast;
    return _ok(
      q,
      AnswerTemplate.firstLastFound,
      {
        'stationId': id,
        'dayType': c.dayType,
        'first': both || q.wantsFirst,
        'last': both || q.wantsLast,
        'rows': [
          for (final t in rows)
            TimingFact(
              terminalId: t.directionTerminalId,
              serviceId: t.serviceId,
              dayType: t.dayType,
              firstDep: t.firstDep,
              lastDep: t.lastDep,
              provenance: t.provenance,
            ),
        ],
      },
      sources: [for (final t in rows) t.provenance],
      actions: [OpenStationAction(id)],
    );
  }

  // facilitiesList: stationId, items (List<Facility>)
  // facilityFound: stationId, facility (FacilityType), items
  // facilityMissing: stationId, facility? (FacilityType)
  AssistantAnswer _facilities(ParsedQuestion q) {
    final id = q.stationId;
    if (id == null) {
      return _ask(q, AnswerTemplate.askStation, AssistantSlot.station);
    }
    final all = snapshot.facilitiesAt(id);
    final want = q.facility;
    final items = want == null
        ? all
        : all.where((f) => f.type == want).toList();
    final open = OpenStationAction(id);
    if (items.isEmpty) {
      // no record is "not in the data", never "there is none"
      return _missing(
        q,
        AnswerTemplate.facilityMissing,
        {'stationId': id, 'facility': ?want},
        actions: [open],
      );
    }
    return _ok(
      q,
      want == null
          ? AnswerTemplate.facilitiesList
          : AnswerTemplate.facilityFound,
      {'stationId': id, 'items': items, 'facility': ?want},
      sources: [for (final f in items) f.provenance],
      actions: [open],
    );
  }

  // accessibilityFound: stationId, lifts?, escalators?, tactile?, wheelchair?,
  //                     liftGates (List<int>)
  AssistantAnswer _accessibility(ParsedQuestion q) {
    final id = q.stationId;
    if (id == null) {
      return _ask(q, AnswerTemplate.askStation, AssistantSlot.station);
    }
    final a = snapshot.accessibilityAt(id);
    final liftGates = [
      for (final g in JourneyPlan.gatesAt(snapshot, id))
        if (g.hasLift ?? false) g.number,
    ];
    final facts = <String, Object>{
      'stationId': id,
      'lifts': ?a?.lifts,
      'escalators': ?a?.escalators,
      'tactile': ?a?.tactilePath,
      'wheelchair': ?a?.wheelchairAvailable,
      'liftGates': liftGates,
    };
    final open = OpenStationAction(id);
    if (facts.length == 2 && liftGates.isEmpty) {
      return _missing(
        q,
        AnswerTemplate.accessibilityMissing,
        {'stationId': id},
        actions: [open],
      );
    }
    return _ok(
      q,
      AnswerTemplate.accessibilityFound,
      facts,
      sources: [?a?.provenance],
      actions: [open],
    );
  }

  /// The dataset has no parking table yet (docs/data-model.md), so every
  /// parking question is "not in the data".
  AssistantAnswer _parking(ParsedQuestion q) {
    final id = q.stationId;
    if (id == null) {
      return _ask(q, AnswerTemplate.askStation, AssistantSlot.station);
    }
    return _missing(
      q,
      AnswerTemplate.parkingMissing,
      {'stationId': id},
      actions: [OpenStationAction(id)],
    );
  }

  // lineInfo: lineId, stationIds (first service, in order), serviceCount
  AssistantAnswer _lineInfo(ParsedQuestion q) {
    final id = q.lineId;
    final line = id == null ? null : snapshot.line(id);
    if (line == null) return _unknown();
    final services = snapshot.servicesOfLine(line.id)
      ..sort((a, b) => a.id.compareTo(b.id));
    if (services.isEmpty) {
      return _missing(q, AnswerTemplate.routeNone, {'lineId': line.id});
    }
    final stops = [
      for (final s in snapshot.stopsOf(services.first.id)) s.stationId,
    ];
    return _ok(
      q,
      AnswerTemplate.lineInfo,
      {
        'lineId': line.id,
        'stationIds': stops,
        'serviceCount': services.length,
      },
    );
  }
}
