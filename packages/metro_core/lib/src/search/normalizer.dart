import 'package:metro_core/src/search/devanagari.dart';

/// Language-level search settings. These are generic spelling conventions,
/// **not** metro facts: no station, line or place name appears here.
///
/// A dataset may override both tables through optional `meta` keys
/// `search_abbreviations` (`sec=sector;stn=station`) and `search_stop_words`
/// (`metro;station`), so they can change without a code release.
class SearchConfig {
  const SearchConfig({
    this.abbreviations = defaultAbbreviations,
    this.stopWords = defaultStopWords,
    this.maxQueryLength = 100,
    this.minSubstringLength = 3,
  });

  factory SearchConfig.fromMeta(Map<String, String> meta) {
    final abbr = meta['search_abbreviations'];
    final stop = meta['search_stop_words'];
    return SearchConfig(
      abbreviations: abbr == null
          ? defaultAbbreviations
          : {
              for (final pair in abbr.split(';'))
                if (pair.contains('='))
                  pair.split('=').first.trim().toLowerCase(): pair
                      .split('=')
                      .last
                      .trim()
                      .toLowerCase(),
            },
      stopWords: stop == null
          ? defaultStopWords
          : {
              for (final w in stop.split(';'))
                if (w.trim().isNotEmpty) w.trim().toLowerCase(),
            },
    );
  }

  static const defaultAbbreviations = {
    'sec': 'sector',
    'stn': 'station',
    'chk': 'chowk',
    'ph': 'phase',
    'mkt': 'market',
    'intl': 'international',
  };
  static const defaultStopWords = {'metro', 'station', 'stn'};

  final Map<String, String> abbreviations;
  final Set<String> stopWords;

  /// Longer queries are truncated (bounds the work per keystroke).
  final int maxQueryLength;

  /// Substring matching starts at this many characters (avoids noise).
  final int minSubstringLength;
}

/// A normalised search text: [tokens] joined by one space is [text];
/// [key] is the phonetic skeleton used for fuzzy matching.
class NormalizedText {
  NormalizedText(this.tokens, this.keyTokens)
    : text = tokens.join(' '),
      compact = tokens.join(),
      key = keyTokens.join(' '),
      compactKey = keyTokens.join(),
      compactLength = tokens.join().runes.length,
      compactKeyLength = keyTokens.join().runes.length;

  final List<String> tokens;
  final List<String> keyTokens;
  final String text;
  final String compact;
  final String key;
  final String compactKey;

  /// Code-point lengths of [compact] / [compactKey].
  final int compactLength;
  final int compactKeyLength;

  bool get isEmpty => tokens.isEmpty;
}

const _latinFold = <String, String>{
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ō': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ß': 'ss',
  'ś': 's',
  'ṣ': 's',
  'ṇ': 'n',
  'ṭ': 't',
  'ḍ': 'd',
};

/// Precomposed nukta letters U+0958..U+095F -> their base letters.
const _nuktaBase = <int, int>{
  0x0958: 0x0915,
  0x0959: 0x0916,
  0x095A: 0x0917,
  0x095B: 0x091C,
  0x095C: 0x0921,
  0x095D: 0x0922,
  0x095E: 0x092B,
  0x095F: 0x092F,
};

const _romanNumerals = {
  'i': '1',
  'ii': '2',
  'iii': '3',
  'iv': '4',
  'v': '5',
  'vi': '6',
  'vii': '7',
  'viii': '8',
  'ix': '9',
  'x': '10',
};

final _wordChar = RegExp(r'[\p{L}\p{M}\p{N}]', unicode: true);

/// Normalises query and indexed text identically (docs/search.md, ADR-041).
///
/// No Unicode-normalisation package is used: the foldings that matter for
/// Delhi names are done explicitly (Latin diacritics, Devanagari nukta,
/// chandrabindu -> anusvara, zero-width joiners, Devanagari digits).
class SearchNormalizer {
  const SearchNormalizer(this.config);

  final SearchConfig config;

  NormalizedText normalize(String raw) {
    final cleaned = _fold(
      raw.length > config.maxQueryLength
          ? raw.substring(0, config.maxQueryLength)
          : raw,
    );
    var tokens = [
      for (final t in cleaned.split(' '))
        if (t.isNotEmpty) config.abbreviations[t] ?? t,
    ];
    // "Mayur Vihar - I" and "mayur vihar 1" meet in the middle: a trailing
    // roman numeral becomes its digit (only after a first word).
    if (tokens.length > 1 && _romanNumerals.containsKey(tokens.last)) {
      tokens[tokens.length - 1] = _romanNumerals[tokens.last]!;
    }
    final kept = [
      for (final t in tokens)
        if (!config.stopWords.contains(t)) t,
    ];
    // A query made only of stop-words ("metro station") must still search.
    if (kept.isNotEmpty) tokens = kept;
    return NormalizedText(tokens, [for (final t in tokens) phoneticKey(t)]);
  }

  /// Folded text with every space removed: how station codes are compared
  /// (no abbreviation or stop-word handling).
  String foldCompact(String raw) => _fold(
    raw.length > config.maxQueryLength
        ? raw.substring(0, config.maxQueryLength)
        : raw,
  ).replaceAll(' ', '');

  /// Lower-cased, folded, punctuation-free text with single spaces.
  String _fold(String s) {
    final out = StringBuffer();
    for (final rune in s.runes) {
      if (rune == 0x200C ||
          rune == 0x200D ||
          rune == 0x00AD ||
          rune == 0xFEFF) {
        continue;
      }
      if (rune == 0x093C) continue; // nukta
      var r = _nuktaBase[rune] ?? rune;
      if (r == 0x0901 || r == 0x0900) r = 0x0902; // chandrabindu -> anusvara
      if (r >= 0x0966 && r <= 0x096F) r = 0x30 + (r - 0x0966); // digits
      final ch = String.fromCharCode(r);
      if (ch == "'" || ch == '’' || ch == 'ʼ' || ch == '`' || ch == '.') {
        continue; // join: "a.i.i.m.s." -> "aiims", "int'l" -> "intl"
      }
      if (!_wordChar.hasMatch(ch)) {
        out.write(' ');
        continue;
      }
      final lower = ch.toLowerCase();
      out.write(_latinFold[lower] ?? lower);
    }
    return out.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Phonetic skeleton of one token (Indian-English tuned; Devanagari tokens
  /// are first transliterated to Latin). Used only for fuzzy matching.
  String phoneticKey(String token) {
    var s = hasDevanagari(token) ? transliterateDevanagariWord(token) : token;
    for (final (from, to) in _phoneticRules) {
      s = s.replaceAll(from, to);
    }
    // h after a consonant is aspiration ("kh", "bh", "sh"): drop it.
    s = s.replaceAllMapped(
      RegExp('([bcdfgjklmnpqrstvxz])h'),
      (m) => m[1]!,
    );
    if (s.endsWith('y')) s = '${s.substring(0, s.length - 1)}i';
    return _collapseDoubles(s);
  }
}

const _phoneticRules = <(String, String)>[
  ('ph', 'f'),
  ('ck', 'k'),
  ('q', 'k'),
  ('x', 'ks'),
  ('au', 'o'),
  ('ow', 'o'),
  ('ou', 'o'),
  ('w', 'v'),
  ('z', 'j'),
  ('aa', 'a'),
  ('ee', 'i'),
  ('ii', 'i'),
  ('oo', 'u'),
  ('uu', 'u'),
];

String _collapseDoubles(String s) {
  final b = StringBuffer();
  int? last;
  for (final r in s.runes) {
    if (r != last) b.writeCharCode(r);
    last = r;
  }
  return b.toString();
}
