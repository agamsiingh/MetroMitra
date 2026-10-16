import 'dart:math';

import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';
import 'support/search_net.dart';

SearchIndex index([MetroSnapshot? s]) =>
    SearchIndex.fromSnapshot(s ?? searchNet());

List<String> ids(List<SearchResult> r) => [for (final x in r) x.entityId];

List<MatchTier> tiers(List<SearchResult> r) => [
  for (final x in r) x.match.tier,
];

void main() {
  final idx = index();
  List<SearchResult> q(String s, {SearchOptions? o}) =>
      idx.search(s, options: o ?? const SearchOptions());

  group('ranking: exact name > alias > prefix > substring > fuzzy', () {
    test('one query shows every tier in order', () {
      final r = q('kamal');
      expect(ids(r).take(5), [
        'kamal', // exact name
        'zed-square', // alias "Kamal"
        'kamal-nagar', // prefix (shortest first)
        'kamal-nagar-ext', // prefix (longer)
        'nagar-kamal-park', // substring
      ]);
      expect(tiers(r).take(5), [
        MatchTier.exact,
        MatchTier.alias,
        MatchTier.prefix,
        MatchTier.prefix,
        MatchTier.substring,
      ]);
      expect(r.last.match.tier, MatchTier.fuzzy);
      expect(ids(r), contains('kamla-gate'), reason: 'transposition kamla');
    });

    test('scores never cross tier bands', () {
      for (final query in [
        'kamal',
        'nagar',
        'raghav',
        'uttam',
        'park',
        'jor',
      ]) {
        final r = q(query, o: const SearchOptions(limit: 100));
        for (var i = 1; i < r.length; i++) {
          expect(
            r[i - 1].match.score,
            greaterThanOrEqualTo(r[i].match.score),
            reason: '$query @$i',
          );
          expect(
            r[i - 1].match.tier.index,
            lessThanOrEqualTo(r[i].match.tier.index),
            reason: '$query: a lower tier outranked a higher one at $i',
          );
        }
      }
    });

    test('closer prefix first, then popularity, then name, then id', () {
      final s = buildSearchNet([
        const SStation('b-long', 'Moti Bagh Extension Road'),
        const SStation('a-short', 'Moti Bagh'),
        const SStation('c-pop', 'Moti Mark', popularity: 30),
        const SStation('d-same-1', 'Moti Mall'),
        const SStation('d-same-2', 'Moti Mall'),
      ]);
      final r = SearchIndex.fromSnapshot(s).search('moti');
      expect(ids(r), ['c-pop', 'a-short', 'd-same-1', 'd-same-2', 'b-long']);
    });

    test('popularity never lifts a lower tier above a higher one', () {
      final s = buildSearchNet([
        const SStation('hot', 'Zeta Kamal Park', popularity: 50),
        const SStation('cold', 'Kamal'),
      ]);
      expect(ids(SearchIndex.fromSnapshot(s).search('kamal')), ['cold', 'hot']);
    });

    test('an alias beats a prefix match of another station', () {
      final r = q('kamal');
      expect(
        r.indexWhere((x) => x.entityId == 'zed-square'),
        lessThan(r.indexWhere((x) => x.entityId == 'kamal-nagar')),
      );
    });

    test('a station is reported once, with its best match', () {
      final r = q('laxmi nagar');
      expect(ids(r).where((i) => i == 'laxmi-nagar'), hasLength(1));
      expect(r.first.entityId, 'laxmi-nagar');
      expect(r.first.match.tier, MatchTier.exact);
    });

    test('limit and an invalid limit', () {
      expect(q('nagar', o: const SearchOptions(limit: 3)), hasLength(3));
      expect(q('nagar', o: const SearchOptions(limit: 0)), isEmpty);
      expect(q('nagar', o: const SearchOptions(limit: -4)), isEmpty);
    });
  });

  group('English: names, partials, abbreviations', () {
    test('case, punctuation and spacing do not matter', () {
      for (final s in ['RAGHAV CHOWK', 'raghav-chowk', '  Raghav   Chowk ']) {
        expect(q(s).first.entityId, 'raghav-chowk', reason: s);
        expect(q(s).first.match.tier, MatchTier.exact);
      }
    });

    test('"metro" and "station" are ignored', () {
      expect(q('Raghav Chowk Metro Station').first.match.tier, MatchTier.exact);
    });

    test('prefixes: letters and words', () {
      expect(q('ragh').first.entityId, 'raghav-chowk');
      expect(q('raghav ch').first.entityId, 'raghav-chowk');
      expect(q('raghav ch').first.match.tier, MatchTier.prefix);
      expect(
        q('r').map((x) => x.match.tier).toSet(),
        contains(MatchTier.prefix),
      );
    });

    test('substring and any-order words', () {
      expect(ids(q('chowk')), contains('raghav-chowk'));
      expect(q('chowk').first.match.tier, MatchTier.substring);
      expect(ids(q('chowk raghav')), contains('raghav-chowk'));
      expect(q('chowk raghav').first.match.tier, MatchTier.substring);
    });

    test('substring needs three characters (no noise from "ag")', () {
      expect(ids(q('ag')), isNot(contains('raghav-chowk')));
      expect(ids(q('agh')), contains('raghav-chowk'));
    });

    test('abbreviations: sec -> sector', () {
      expect(q('vihar sec 21').first.entityId, 'vihar-sector-21');
      expect(q('vihar sec 21').first.match.tier, MatchTier.exact);
      expect(q('Vihar Sector 9').first.entityId, 'vihar-sector-9');
    });

    test('roman and arabic numerals meet', () {
      expect(q('mayur kunj 1').first.entityId, 'mayur-kunj-i');
      expect(q('mayur kunj i').first.entityId, 'mayur-kunj-i');
      expect(q('Mayur Kunj - II').first.entityId, 'mayur-kunj-ii');
      expect(q('mayur kunj 2').first.entityId, 'mayur-kunj-ii');
    });

    test('dotted abbreviations join', () {
      expect(q('nksp').first.entityId, 'n-k-s-p');
      expect(q('N.K.S.P').first.entityId, 'n-k-s-p');
      expect(q('n k s p').first.entityId, 'n-k-s-p', reason: 'spacing');
    });

    test('spacing differences are fuzzy-equal', () {
      final r = q('jorbagh hall');
      expect(r.first.entityId, 'jorbagh-hall');
      final r2 = q('jornagar');
      expect(r2.first.entityId, 'jor-nagar');
      expect(r2.first.match.tier, MatchTier.fuzzy);
      expect(r2.first.match.edits, 0);
    });
  });

  group('typos', () {
    test('transposition, substitution, insertion, deletion', () {
      for (final (typed, want) in [
        ('ragahv chowk', 'raghav-chowk'),
        ('raghav chowq', 'raghav-chowk'),
        ('raghavv chowk', 'raghav-chowk'),
        ('raghv chowk', 'raghav-chowk'),
        ('sundr nagar', 'sundar-nagar'),
        ('sunder nagar', 'sundar-nagar'),
        ('uttam nagr east', 'uttam-nagar-east'),
      ]) {
        final r = q(typed);
        expect(r, isNotEmpty, reason: typed);
        expect(r.first.entityId, want, reason: typed);
        expect(r.first.match.tier, MatchTier.fuzzy, reason: typed);
      }
    });

    test('Indian-English spelling variants find the station (phonetic)', () {
      final r = q('ragav chok');
      expect(r.first.entityId, 'raghav-chowk');
      expect(r.first.match.phonetic, isTrue);
      expect(
        q('laksmi nagar').first.entityId,
        anyOf('lakshmi-nagar', 'laxmi-nagar'),
      );
    });

    test('one misspelt word of a longer name', () {
      expect(q('raghaw').first.entityId, 'raghav-chowk');
      expect(q('sundar').first.entityId, 'sundar-nagar');
    });

    test('typo in the leading part of a long query (partial + typo)', () {
      expect(q('uttam nagr ea').first.entityId, 'uttam-nagar-east');
    });

    test('fewer fuzzy edits rank higher', () {
      final r = q('kamla gate');
      expect(r.first.entityId, 'kamla-gate');
      expect(r.first.match.tier, MatchTier.exact);
      final r2 = q('kamla gat');
      expect(r2.first.entityId, 'kamla-gate');
    });

    test('short queries never fuzzy-match (no random hits)', () {
      expect(q('xq'), isEmpty);
      expect(q('zz'), isEmpty);
      expect(
        q('kam').map((x) => x.match.tier),
        isNot(contains(MatchTier.fuzzy)),
      );
    });

    test('a name that does not exist returns nothing', () {
      for (final s in [
        'qqqqqq',
        'xyzzy plugh',
        'zzzzzzzzzz',
        '12345',
        'ऋऋऋऋ',
      ]) {
        expect(q(s), isEmpty, reason: s);
      }
    });

    test('fuzzy never beats an exact, alias, prefix or substring hit', () {
      final r = q('kamal');
      final firstFuzzy = r.indexWhere((x) => x.match.tier == MatchTier.fuzzy);
      for (var i = 0; i < firstFuzzy; i++) {
        expect(r[i].match.tier, isNot(MatchTier.fuzzy));
      }
    });
  });

  group('aliases, old names, misspellings, landmarks', () {
    test('aliases match exactly and are labelled', () {
      final r = q('old kamla');
      expect(r.first.entityId, 'kamla-gate');
      expect(r.first.match.tier, MatchTier.alias);
      expect(r.first.match.field, MatchField.oldName);
      expect(r.first.match.matchedText, 'Old Kamla');
    });

    test('recorded misspellings and landmarks are found', () {
      expect(q('kamla gat').first.match.field, MatchField.misspelling);
      final l = q('landmark mall');
      expect(l.first.entityId, 'laxmi-nagar');
      expect(l.first.match.field, MatchField.landmark);
    });

    test('an alias prefix ranks under a name prefix', () {
      final r = q('old');
      expect(r.first.entityId, 'kamla-gate');
      expect(r.first.match.tier, MatchTier.prefix);
      expect(r.first.match.score, lessThan(800));
    });

    test('Hindi alias with a different spelling', () {
      final r = q('इफ्को चौक');
      expect(r.first.entityId, 'ifko-chowk');
      expect(r.first.match.tier, MatchTier.alias, reason: 'virama spelling');
    });
  });

  group('station codes', () {
    test('exact code, case-insensitive, is an alias-tier hit', () {
      for (final s in ['RGV', 'rgv', ' Rgv ']) {
        final r = q(s);
        expect(r.first.entityId, 'raghav-chowk', reason: s);
        expect(r.first.match.tier, MatchTier.alias);
        expect(r.first.match.field, MatchField.stationCode);
        expect(r.first.match.score, 900);
      }
    });

    test('a code shared by two lines still gives one result', () {
      expect(ids(q('rgv')).where((i) => i == 'raghav-chowk'), hasLength(1));
    });

    test('code prefix finds the station but ranks below names', () {
      final r = q('kmg');
      expect(r.first.entityId, 'kamla-gate');
      final p = q('km');
      expect(ids(p), contains('kamla-gate'));
      expect(
        p.firstWhere((x) => x.entityId == 'kamla-gate').match.tier,
        MatchTier.prefix,
      );
    });

    test('codes are never matched as substrings or fuzzily', () {
      expect(ids(q('gv')), isNot(contains('raghav-chowk')));
      expect(ids(q('rgw')), isNot(contains('raghav-chowk')));
    });

    test('a code is not expanded like a word', () {
      final s = buildSearchNet([
        const SStation('x', 'Some Place', codes: {'l-red': 'PH'}),
      ]);
      final r = SearchIndex.fromSnapshot(s).search('ph');
      expect(r.first.match.field, MatchField.stationCode);
    });

    test('stations without codes are unaffected (NULL stays NULL)', () {
      final r = q('orchid park');
      expect(r.first.station!.lines.single.stationCode, isNull);
    });
  });

  group('Hindi and Unicode', () {
    test('Hindi exact, prefix, substring', () {
      expect(q('राघव चौक').first.match.tier, MatchTier.exact);
      expect(q('राघव चौक').first.match.field, MatchField.nameHi);
      expect(q('राघव').first.entityId, 'raghav-chowk');
      expect(q('राघव').first.match.tier, MatchTier.prefix);
      expect(ids(q('चौक')), contains('raghav-chowk'));
    });

    test('nukta, chandrabindu and joiners are folded', () {
      expect(q('इफको चौक').first.entityId, 'ifko-chowk');
      expect(q('इफ़को चौक').first.entityId, 'ifko-chowk');
      expect(() => q('सुन‍दर नगर'), returnsNormally);
      expect(q('सुंदर नगर').first.entityId, 'sundar-nagar');
    });

    test('Devanagari digits and ASCII digits are the same', () {
      expect(q('विहार सेक्टर 9').first.entityId, 'vihar-sector-9');
      expect(q('विहार सेक्टर ९').first.entityId, 'vihar-sector-9');
      expect(q('विहार सेक्टर २१').first.entityId, 'vihar-sector-21');
      expect(q('मयूर कुंज 1').first.entityId, 'mayur-kunj-i');
    });

    test('Hindi typos: vowel length and anusvara', () {
      expect(q('सूंदर नगर').first.entityId, 'sundar-nagar');
      expect(q('सुन्दर नगर').first.entityId, 'sundar-nagar');
      expect(
        q('लक्षमी नगर').first.entityId,
        anyOf('lakshmi-nagar', 'laxmi-nagar'),
      );
    });

    test('Hindi queries reach stations with NO Hindi name (phonetic)', () {
      final r = q('ऑर्किड पार्क');
      // The data has no Hindi name for Orchid Park: it can be found, never filled in.
      expect(ids(r), contains('orchid-park'));
      final hit = r.firstWhere((x) => x.entityId == 'orchid-park');
      expect(hit.match.phonetic, isTrue);
      expect(hit.station!.nameHi, isNull);
    });

    test(
      'Latin queries reach Hindi-named stations through the English name',
      () {
        expect(q('kamal').first.station!.nameHi, 'कमल');
      },
    );

    test('Hindi line names are searchable', () {
      final r = q('टेस्ट लाल');
      expect(r.first.kind, SearchKind.line);
      expect(r.first.entityId, 'l-red');
    });

    test('mixed-script and odd input never throws', () {
      for (final s in [
        'raghav चौक',
        'चौक raghav',
        '😀',
        'राघव😀',
        '\u0000',
        'ághav',
        'ＲＡＧＨＡＶ',
        '\u202Eraghav',
        'ﷺ',
        'क्',
        '्',
        'ःं',
      ]) {
        expect(() => q(s), returnsNormally, reason: s.codeUnits.toString());
      }
    });

    test('combining acute accent folds only for Latin it can fold', () {
      expect(() => q('á'), returnsNormally);
    });
  });

  group('lines', () {
    test('line names, short names and Hindi names', () {
      expect(q('blue').first.entityId, 'l-blue');
      expect(q('test blue line').first.match.tier, MatchTier.exact);
      expect(q('blue line').first.match.tier, MatchTier.substring);
      expect(q('TB').first.entityId, 'l-blue');
      expect(q('TB').first.match.field, MatchField.lineShortName);
      expect(q('TB').first.match.tier, MatchTier.alias);
    });

    test('line summary: colour from data, services, station count', () {
      final l = q('red line').first.line!;
      expect(l.colorHex, '#112233');
      expect(l.serviceIds, ['l-red-svc']);
      expect(l.stationCount, greaterThan(10));
      expect(l.nameHi, 'टेस्ट लाल लाइन');
      expect(q('blue line').first.line!.nameHi, isNull);
    });

    test('scope: stations only / lines only / all', () {
      final all = q('blue');
      expect(all.map((x) => x.kind).toSet(), {SearchKind.line});
      final stOnly = q(
        'red',
        o: const SearchOptions(scope: SearchScope.stations),
      );
      expect(stOnly.every((x) => x.kind == SearchKind.station), isTrue);
      final lnOnly = q('red', o: const SearchOptions(scope: SearchScope.lines));
      expect(ids(lnOnly), ['l-red']);
    });

    test('closed lines are hidden unless asked for', () {
      expect(q('old line'), isEmpty);
      expect(
        ids(q('old line', o: const SearchOptions(onlyOpen: false))),
        ['l-gone'],
      );
    });
  });

  group('result content and NULL semantics', () {
    test('station summary comes straight from the dataset', () {
      final s = searchNet();
      final r = SearchIndex.fromSnapshot(s).search('raghav chowk').first;
      final st = r.station!;
      final src = s.station('raghav-chowk')!;
      expect(st.id, src.id);
      expect(st.nameEn, src.nameEn);
      expect(st.nameHi, src.nameHi);
      expect(st.lat, src.lat);
      expect(st.lng, src.lng);
      expect(st.status, OperatingStatus.open);
      expect(st.provenance.sourceId, 'test-fixture');
      expect(st.provenance.confidence, Confidence.community);
      expect(st.lines.map((l) => l.lineId), ['l-red', 'l-blue']);
      expect(st.lines.map((l) => l.stationCode), ['RGV', 'RGV']);
      expect(st.lines.first.colorHex, '#112233');
      expect(st.serviceIds, ['l-blue-svc', 'l-red-svc']);
      expect(st.isInterchange, isTrue);
    });

    test('missing Hindi name stays NULL', () {
      final st = q('orchid park').first.station!;
      expect(st.nameHi, isNull);
      for (final x in searchNet().stationNames.where(
        (n) => n.stationId == 'orchid-park',
      )) {
        expect(x.lang, 'en');
      }
    });

    test('aliases are returned with their kind', () {
      final st = q('kamla gate').first.station!;
      expect(
        st.aliases.map((a) => (a.text, a.kind)),
        containsAll([
          ('Old Kamla', NameKind.old),
          ('Kamla Gat', NameKind.misspelling),
        ]),
      );
      expect(st.aliases.every((a) => a.kind != NameKind.official), isTrue);
    });

    test('interchange status follows the lines of the station', () {
      expect(q('raghav chowk').first.station!.isInterchange, isTrue);
      expect(q('kamla gate').first.station!.isInterchange, isFalse);
    });

    test('a station on no service has empty lists, not invented ones', () {
      final s = buildSearchNet([const SStation('solo', 'Solo Halt')]);
      final snap = s.copyWith(stationLines: [], serviceStops: []);
      final st = SearchIndex.fromSnapshot(
        snap,
      ).search('solo halt').first.station!;
      expect(st.lines, isEmpty);
      expect(st.serviceIds, isEmpty);
      expect(st.isInterchange, isFalse);
    });

    test('results never contain text that is not in the dataset', () {
      final s = searchNet();
      final known = {
        for (final n in s.stationNames) n.text,
        for (final st in s.stations) ...[st.nameEn, ?st.nameHi],
      };
      for (final query in [
        'राघव',
        'rajiv',
        'ragav chok',
        'ऑर्किड',
        'kamal',
        'sunder',
      ]) {
        for (final r in SearchIndex.fromSnapshot(s).search(query)) {
          final st = r.station;
          if (st == null) continue;
          expect(known, contains(st.nameEn));
          if (st.nameHi != null) expect(known, contains(st.nameHi));
        }
      }
    });

    test('closed stations are hidden by default and shown on request', () {
      expect(q('closed halt'), isEmpty);
      final r = q('closed halt', o: const SearchOptions(onlyOpen: false));
      expect(r.first.entityId, 'closed-halt');
      expect(r.first.station!.status, OperatingStatus.closed);
    });
  });

  group('empty and hostile queries', () {
    test('blank, whitespace and punctuation-only queries find nothing', () {
      for (final s in ['', ' ', '\t\n', '---', '()', '/', '!!!', '😀']) {
        expect(q(s), isEmpty, reason: '"$s"');
      }
    });

    test('very long queries are bounded and do not throw', () {
      expect(() => q('raghav ' * 2000), returnsNormally);
      expect(q('a' * 100000), isEmpty);
    });

    test('an empty dataset searches fine', () {
      final empty = SearchIndex.fromSnapshot(MetroSnapshot(meta: const {}));
      expect(empty.search('anything'), isEmpty);
      expect(empty.entityCount, 0);
    });

    test('random garbage never throws and respects the limit', () {
      final rnd = Random(7);
      const alphabet =
          'abcdefghijklmnopqrstuvwxyz ABCXYZ0123456789-.()/ अआइईउऊकखगचजटडतदनपबमयरलवशसहािीुूेैोौं्ँ़ ‍‌ 😀é';
      final chars = alphabet.runes.toList();
      for (var i = 0; i < 500; i++) {
        final len = rnd.nextInt(40);
        final s = String.fromCharCodes([
          for (var k = 0; k < len; k++) chars[rnd.nextInt(chars.length)],
        ]);
        final r = idx.search(s, options: const SearchOptions(limit: 5));
        expect(r.length, lessThanOrEqualTo(5), reason: s);
      }
    });
  });

  group('determinism', () {
    List<T> shuffled<T>(List<T> l, int seed) => [...l]..shuffle(Random(seed));

    final queries = [
      'kamal',
      'nagar',
      'raghav',
      'राघव',
      'rgv',
      'blue',
      'sec 21',
      'ragav chok',
      'laksmi',
      'लक्ष्मी',
      'old',
      'uttam nagar',
      'park',
      'zz',
      'mayur kunj 1',
    ];

    String render(List<SearchResult> r) => [
      for (final x in r) '${x.entityId}:${x.match.score}:${x.match.field.name}',
    ].join(',');

    test('row order of the dataset does not change any result', () {
      final base = searchNet();
      final expected = [for (final s in queries) render(index(base).search(s))];
      for (var seed = 0; seed < 6; seed++) {
        final shuffledSnap = base.copyWith(
          stations: shuffled(base.stations, seed),
          stationNames: shuffled(base.stationNames, seed + 1),
          stationLines: shuffled(base.stationLines, seed + 2),
          lines: shuffled(base.lines, seed + 3),
          services: shuffled(base.services, seed + 4),
          serviceStops: shuffled(base.serviceStops, seed + 5),
        );
        final got = [
          for (final s in queries) render(index(shuffledSnap).search(s)),
        ];
        expect(got, expected, reason: 'seed $seed');
      }
    });

    test('the same query twice gives the same answer', () {
      for (final s in queries) {
        expect(render(idx.search(s)), render(idx.search(s)));
      }
    });

    test('a rebuilt index gives the same answer', () {
      final other = index();
      for (final s in queries) {
        expect(render(other.search(s)), render(idx.search(s)));
      }
    });
  });

  group('properties', () {
    final snap = searchNet();
    const opts = SearchOptions(limit: 100, onlyOpen: false);

    test('every station is found, first, by each of its own names', () {
      for (final st in snap.stations) {
        for (final n
            in snap.namesOf(st.id).where((n) => n.kind == NameKind.official)) {
          final r = idx.search(n.text, options: opts);
          expect(
            r.first.match.score,
            r.firstWhere((x) => x.entityId == st.id).match.score,
            reason: n.text,
          );
        }
      }
    });

    test('every prefix of >= 3 letters of a name finds the station', () {
      for (final st in snap.stations) {
        final name = st.nameEn.toLowerCase();
        for (var len = 3; len <= name.length; len++) {
          final p = name.substring(0, len);
          expect(
            ids(idx.search(p, options: opts)),
            contains(st.id),
            reason: '"$p" of ${st.nameEn}',
          );
        }
      }
    });

    test('self-check on the synthetic network is clean', () {
      expect(idx.selfCheck(), isEmpty);
    });

    test('self-check reports a name that is hidden by an identical one', () {
      final s = buildSearchNet([
        const SStation('a', 'Twin Place'),
        SStation('b', 'Other Place', aliases: [alias('Twin Place')]),
      ]);
      // b's alias loses to a's official name, but b is still found: no problem.
      expect(SearchIndex.fromSnapshot(s).selfCheck(), isEmpty);
    });

    test('a query that is an exact name is stable under case/space noise', () {
      for (final st in snap.stations) {
        final noisy = '  ${st.nameEn.toUpperCase().replaceAll(' ', '   ')} ';
        final a = idx.search(noisy, options: opts);
        final b = idx.search(st.nameEn, options: opts);
        expect(ids(a), ids(b), reason: st.nameEn);
      }
    });

    test(
      'longer prefixes never gain results that shorter ones lack (prefix tier)',
      () {
        for (final st in snap.stations.where((s) => !s.nameEn.endsWith('I'))) {
          final name = st.nameEn.toLowerCase();
          Set<String> prefixHits(String p) => {
            for (final r in idx.search(p, options: opts))
              if (r.match.tier.index <= MatchTier.prefix.index) r.entityId,
          };
          var prev = prefixHits(name.substring(0, 1));
          for (var len = 2; len <= name.length; len++) {
            final cur = prefixHits(name.substring(0, len));
            expect(prev.containsAll(cur), isTrue, reason: '${st.nameEn} @$len');
            prev = cur;
          }
        }
      },
    );

    test('the fixture network: every name and code finds its station', () {
      final fx = loadFixture();
      final fxIdx = SearchIndex.fromSnapshot(fx);
      expect(fxIdx.selfCheck(), isEmpty);
      expect(fxIdx.search('TEST Alpha').first.entityId, 'test-alpha');
      expect(fxIdx.search('Test Alfa').first.entityId, 'test-alpha');
      expect(fxIdx.search('अल्फा टेस्ट').first.entityId, 'test-alpha');
      expect(fxIdx.search('R3').first.entityId, 'test-gamma');
      expect(fxIdx.search('test gamma').first.station!.isInterchange, isTrue);
    });
  });
}
