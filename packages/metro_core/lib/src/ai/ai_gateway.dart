import 'package:metro_core/src/assistant/assistant_models.dart';
import 'package:metro_core/src/model/snapshot.dart';
import 'package:metro_core/src/search/search_index.dart';
import 'package:metro_core/src/search/search_models.dart';

/// One verified fact sent along with a question so the model can only draw on
/// the dataset (docs/ai.md "Grounding"). Never a position.
class AiFact {
  const AiFact(this.key, this.value);

  final String key;
  final String value;

  Map<String, String> toJson() => {'key': key, 'value': value};
}

class AiRequest {
  const AiRequest({
    required this.question,
    required this.locale,
    required this.grounding,
    required this.datasetVersion,
  });

  final String question;

  /// `en` or `hi`.
  final String locale;
  final List<AiFact> grounding;
  final String datasetVersion;
}

sealed class AiResult {
  const AiResult();
}

/// Generated text that passed the on-device check. It is *not* a metro fact.
final class AiAnswer extends AiResult {
  const AiAnswer(this.text);

  final String text;
}

/// An answer came back but cannot be shown (failed the post-check, empty,
/// refused by the service).
final class AiRefused extends AiResult {
  const AiRefused(this.reason);

  final String reason;
}

/// No answer was possible: no network, timeout, rate limit, not configured.
final class AiUnavailable extends AiResult {
  const AiUnavailable(this.reason);

  final String reason;
}

/// The only way the app reaches an LLM: through our own proxy (docs/ai.md).
abstract interface class AiGateway {
  /// False when no service is configured: the app then offers nothing AI.
  bool get configured;

  /// Never throws: every failure is an [AiResult].
  Future<AiResult> ask(AiRequest request);
}

/// Always unavailable (no proxy configured).
class OfflineAiGateway implements AiGateway {
  const OfflineAiGateway();

  @override
  bool get configured => false;

  @override
  Future<AiResult> ask(AiRequest request) async =>
      const AiUnavailable('not configured');
}

/// Facts about the places a question names, from the dataset only.
abstract final class AiGrounding {
  /// At most [maxFacts] facts; empty when the question names no known place.
  static List<AiFact> build(
    MetroSnapshot snapshot,
    ParsedQuestion q, {
    int maxFacts = 12,
  }) {
    final ids = <String>{
      for (final id in [
        q.fromId,
        q.toId,
        q.stationId,
        q.destinationId,
      ])
        ?id,
    };
    final facts = <AiFact>[];
    for (final id in ids) {
      final s = snapshot.station(id);
      if (s == null) continue;
      final lines = snapshot.linesAt(id).map((l) => l.nameEn).toList();
      facts.add(
        AiFact(
          'station',
          '${s.nameEn}${s.nameHi == null ? '' : ' / ${s.nameHi}'}'
              '${lines.isEmpty ? '' : '; lines: ${lines.join(', ')}'}'
              '${lines.length > 1 ? '; interchange' : ''}',
        ),
      );
    }
    final line = q.lineId == null ? null : snapshot.line(q.lineId!);
    if (line != null) facts.add(AiFact('line', line.nameEn));
    return facts.take(maxFacts).toList();
  }
}

/// Checks generated text against the dataset before it is shown
/// (docs/ai.md "Post-check"). The proxy asks the model to wrap every station
/// name as `[[Name]]`; here each marked name must be a station, alias or code
/// in the dataset, and amounts and clock times must come from the grounding.
/// Conservative on purpose: when in doubt the answer is refused.
class AiPostCheck {
  AiPostCheck(this.snapshot, this.search);

  final MetroSnapshot snapshot;
  final SearchIndex search;

  static const maxLength = 1500;

  static final _marked = RegExp(r'\[\[(.{1,80}?)\]\]');
  static final _unmarkedStation = RegExp(
    r"((?:[A-Z][\w.'-]*\s+){1,4})(?:Metro\s+)?[Ss]tation\b",
  );
  static final _money = RegExp(r'(?:₹|Rs\.?\s?|INR\s?)\s?\d+');
  static final _clock = RegExp(r'\b\d{1,2}[:.]\d{2}\s?(?:[AaPp][Mm])?');

  /// The text to show (markers removed) or null when it must be refused.
  String? verify(String text, {List<AiFact> grounding = const []}) {
    final t = text.trim();
    if (t.isEmpty || t.length > maxLength) return null;
    for (final m in _marked.allMatches(t)) {
      if (!_isKnownPlace(m.group(1)!)) return null;
    }
    final unmarked = t.replaceAll(_marked, '');
    for (final m in _unmarkedStation.allMatches(unmarked)) {
      final name = m.group(1)!.trim();
      // "the Blue ..." style lead-ins are fine; only a full unknown name fails
      if (name.split(' ').length >= 2 && !_isKnownPlace(name)) return null;
    }
    final given = grounding.map((f) => f.value).join(' ');
    for (final re in [_money, _clock]) {
      for (final m in re.allMatches(t)) {
        if (!given.contains(m.group(0)!.trim())) return null;
      }
    }
    return t.replaceAllMapped(_marked, (m) => m.group(1)!);
  }

  bool _isKnownPlace(String name) {
    final hits = search.search(
      name.trim(),
      options: const SearchOptions(limit: 3, scope: SearchScope.stations),
    );
    return hits.any(
      (h) => h.match.tier == MatchTier.exact || h.match.tier == MatchTier.alias,
    );
  }
}
