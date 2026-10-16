import 'package:metro_core/metro_core.dart';
import 'package:metro_core/src/search/devanagari.dart';
import 'package:metro_core/src/search/edit_distance.dart';
import 'package:test/test.dart';

void main() {
  const n = SearchNormalizer(SearchConfig());
  String text(String s) => n.normalize(s).text;
  String key(String s) => n.normalize(s).key;

  group('normalisation', () {
    test('lower-cases, strips punctuation, collapses spaces', () {
      expect(text('  Raghav   CHOWK '), 'raghav chowk');
      expect(text('Dilli-Haat / INA'), 'dilli haat ina');
      expect(text('Mayur Vihar - I (Pink)'), 'mayur vihar i pink');
    });

    test('dots and apostrophes join instead of splitting', () {
      expect(text('A.I.I.M.S.'), 'aiims');
      expect(text("Int'l Airport"), 'international airport');
      expect(text('St. Stephen’s'), 'st stephens');
    });

    test('Latin diacritics fold', () {
      expect(text('Café Ñandú'), 'cafe nandu');
      expect(text('Straße'), 'strasse');
    });

    test('abbreviations expand (generic words only)', () {
      expect(text('Vihar Sec 21'), 'vihar sector 21');
      expect(text('Chk'), 'chowk');
      expect(text('Ph 2 Mkt'), 'phase 2 market');
    });

    test('stop-words are dropped but never leave an empty query', () {
      expect(text('Raghav Chowk Metro Station'), 'raghav chowk');
      expect(text('metro station'), 'metro station');
      expect(text('stn'), 'station', reason: 'abbreviation, then kept');
    });

    test('a trailing roman numeral meets its digit', () {
      expect(text('Mayur Kunj - I'), 'mayur kunj 1');
      expect(text('Mayur Kunj II'), 'mayur kunj 2');
      expect(text('Mayur Kunj 1'), 'mayur kunj 1');
      expect(text('I'), 'i', reason: 'a lone numeral is just a word');
    });

    test('Devanagari digits become ASCII digits', () {
      expect(text('सेक्टर २१'), text('सेक्टर 21'));
      expect(text('कुंज - १'), 'कुंज 1');
    });

    test('Devanagari folding: nukta, chandrabindu, joiners', () {
      // precomposed क़ (U+0958) vs क + nukta (U+0915 U+093C) vs plain क
      expect(text('क़ला'), text('क़ला'));
      expect(text('क़ला'), text('कला'));
      expect(text('इफ़को'), text('इफको'));
      expect(text('आँख'), text('आंख'), reason: 'chandrabindu -> anusvara');
      expect(text('क‍ष'), text('कष'), reason: 'ZWJ removed');
      expect(text('क‌ष'), text('कष'), reason: 'ZWNJ removed');
    });

    test('Devanagari danda and punctuation split words', () {
      expect(text('राघव।चौक'), 'राघव चौक');
    });

    test('blank and punctuation-only input is empty', () {
      expect(n.normalize('').isEmpty, isTrue);
      expect(n.normalize('   ').isEmpty, isTrue);
      expect(n.normalize('---()//').isEmpty, isTrue);
      expect(n.normalize('😀😀').isEmpty, isTrue);
    });

    test('very long input is truncated', () {
      final r = n.normalize('a' * 5000);
      expect(r.text.length, 100);
    });

    test('is idempotent', () {
      for (final s in [
        'Mayur Kunj - I',
        'Sec 21 Ph II',
        'इफ़को चौक',
        'A.B.C',
      ]) {
        expect(text(text(s)), text(s), reason: s);
      }
    });

    test('the config can be replaced from dataset meta', () {
      final c = SearchConfig.fromMeta({
        'search_abbreviations': 'rd=road; mkt=market',
        'search_stop_words': 'halt',
      });
      final m = SearchNormalizer(c);
      expect(m.normalize('Link Rd Halt').text, 'link road');
      expect(m.normalize('Sec 5').text, 'sec 5', reason: 'defaults replaced');
      expect(
        SearchConfig.fromMeta(const {}).abbreviations,
        SearchConfig.defaultAbbreviations,
      );
    });
  });

  group('Devanagari transliteration (matching only)', () {
    String latin(String s) => transliterateDevanagariWord(s);

    test('basic words with schwa deletion', () {
      expect(latin('राघव'), 'raaghav');
      expect(latin('जनकपुरी'), 'janakpurii');
      expect(latin('कमल'), 'kamal');
      expect(latin('नगर'), 'nagar');
    });

    test('conjuncts and matras', () {
      expect(latin('सेक्टर'), 'sektar');
      expect(latin('वेस्ट'), 'vest');
      expect(latin('चौक'), 'chauk');
    });

    test('anusvara and independent vowels', () {
      expect(latin('इंद्रलोक'), 'indrlok');
      expect(latin('आनंद'), 'aanand');
      expect(latin('उत्तम'), 'uttam');
    });

    test('one-syllable words keep their vowel', () {
      expect(latin('न'), 'na');
    });

    test('Latin letters inside a Devanagari token pass through', () {
      expect(latin('एम7'), contains('7'));
    });

    test('hasDevanagari / isDevanagari', () {
      expect(hasDevanagari('abc राघव'), isTrue);
      expect(hasDevanagari('abc'), isFalse);
      expect(isDevanagari('अ'.runes.first), isTrue);
    });
  });

  group('phonetic key', () {
    test('Indian-English spelling variants collide', () {
      expect(key('Rajeev'), key('Rajiv'));
      expect(key('Raghav Chowk'), key('Raghav Chok'));
      expect(key('Sundar'), key('Sundar'));
      expect(key('Lakshmi'), key('Lakshmi'));
      expect(key('Bhagat'), key('Bagat'));
      expect(key('Jhandewalan'), key('Jandewalan'));
      expect(key('Phool Bagh'), key('Fool Bag'));
      expect(key('Vihar'), key('Wihar'));
      expect(key('Zoor'), key('Joor'));
    });

    test('Hindi and Latin spellings meet', () {
      expect(
        n.normalize('राघव चौक').compactKey,
        key('Raghav Chowk').replaceAll(' ', ''),
      );
      expect(n.normalize('कमल').compactKey, key('Kamal'));
      expect(n.normalize('नगर').compactKey, key('Nagar'));
    });

    test('long and short Hindi vowels collide', () {
      expect(n.normalize('सुंदर').compactKey, n.normalize('सूंदर').compactKey);
      expect(
        n.normalize('किर्ती').compactKey,
        n.normalize('कीर्ती').compactKey,
      );
    });

    test('different names stay different', () {
      expect(key('Kamal'), isNot(key('Komal')));
      expect(key('Raghav'), isNot(key('Rajiv')));
    });

    test('doubled letters collapse', () {
      expect(key('Uttam'), key('Utam'));
    });
  });

  group('edit distance (restricted Damerau-Levenshtein, code points)', () {
    int? d(String a, String b, [int max = 3]) => boundedEditDistance(a, b, max);

    test('identity, insert, delete, substitute, transpose', () {
      expect(d('kamal', 'kamal'), 0);
      expect(d('kamal', 'kamall'), 1);
      expect(d('kamal', 'kama'), 1);
      expect(d('kamal', 'kamel'), 1);
      expect(d('kamal', 'kamla'), 1);
    });

    test('empty strings', () {
      expect(d('', ''), 0);
      expect(d('', 'ab'), 2);
      expect(d('ab', ''), 2);
      expect(d('', 'abcd'), isNull);
    });

    test('bounded: returns null above the bound', () {
      expect(d('kamal', 'zzzzz', 2), isNull);
      expect(d('abcdef', 'abcdeghij', 2), isNull);
      expect(d('kamal', 'kamal', 0), 0);
      expect(d('kamal', 'kamel', 0), isNull);
    });

    test('is symmetric', () {
      for (final (a, b) in [
        ('raghav', 'ragahv'),
        ('kamal', 'kamla'),
        ('sundar', 'sunder'),
        ('abc', 'xyz'),
      ]) {
        expect(d(a, b), d(b, a));
      }
    });

    test('counts code points, so Devanagari is not over-charged', () {
      expect(d('कमल', 'कमला'), 1);
      expect(d('😀a', 'a'), 1);
    });
  });
}
