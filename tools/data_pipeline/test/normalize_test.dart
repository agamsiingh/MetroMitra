import 'dart:convert';

import 'package:data_pipeline/data_pipeline.dart';
import 'package:test/test.dart';

import 'support/support.dart';

void main() {
  group('OSM parsing', () {
    final osm = normalizeOsm(MiniOsm.bytes(), network: 'Test Net');

    test(
      'keeps only subway routes of the configured network, ordered by id',
      () {
        expect(osm.routes.map((r) => r.id), [11, 12, 21, 22]);
        expect(osm.baseTimestamp, '2026-10-05T00:00:00Z');
        expect(osm.issues, isEmpty);
      },
    );

    test('ignores other networks and other route types', () {
      final data = overpassBytes([
        osmNode(1, 'A', 28.6, 77.1),
        osmNode(2, 'B', 28.7, 77.2),
        osmRelation(10, 'x', [1, 2], network: 'Other Net'),
        osmRelation(11, 'y', [1, 2], route: 'bus'),
        osmRelation(12, 'z', [1, 2]),
      ]);
      expect(normalizeOsm(data, network: 'Test Net').routes.map((r) => r.id), [
        12,
      ]);
    });

    test(
      'stops keep route order, names, Hindi names, codes and coordinates',
      () {
        final r = osm.routes.first;
        expect(r.stops.map((s) => s.name), [
          'TEST Central',
          'TEST East',
          'TEST North',
        ]);
        expect(r.stops.first.nameHi, 'टेस्ट सेंट्रल');
        expect(r.stops.first.wikidata, 'Q1000');
        expect(r.stops.first.ref, 'A1');
        expect(r.stops.first.lat, 28.6);
        expect(r.stops.first.lng, 77.1);
        expect(r.lineWikidata, 'Q9001');
        expect(r.operator, 'TEST Operator');
      },
    );

    test('way members and non-stop roles are ignored', () {
      // osmRelation adds a way member to every relation
      expect(osm.routes.first.stops, hasLength(3));
    });

    test('absent Hindi name stays null (never transliterated)', () {
      expect(osm.routes.first.stops.last.name, 'TEST North');
      expect(osm.routes.first.stops.last.nameHi, isNull);
    });

    test('whitespace in names is tidied, nothing else is changed', () {
      final data = overpassBytes([
        osmNode(1, '  TEST   Spaced  Name ', 28.6, 77.1),
        osmNode(2, 'TEST (Odd) - Name', 28.7, 77.2),
        osmRelation(10, 'r', [1, 2]),
      ]);
      final stops = normalizeOsm(data, network: 'Test Net').routes.single.stops;
      expect(stops[0].name, 'TEST Spaced Name');
      expect(stops[1].name, 'TEST (Odd) - Name');
    });

    test('multi-valued alt_name/old_name are split on ;', () {
      final data = overpassBytes([
        osmNode(
          1,
          'A',
          28.6,
          77.1,
          tags: {
            'alt_name': 'Foo; Bar',
            'old_name': 'Baz',
            'alt_name:hi': 'फू',
          },
        ),
        osmNode(2, 'B', 28.7, 77.2),
        osmRelation(10, 'r', [1, 2]),
      ]);
      final s = normalizeOsm(
        data,
        network: 'Test Net',
      ).routes.single.stops.first;
      expect(s.altNames, ['Foo', 'Bar']);
      expect(s.oldNames, ['Baz']);
      expect(s.altNamesHi, ['फू']);
    });
  });

  group('colour normalisation', () {
    test('accepts #rgb and #rrggbb, upper-cases', () {
      expect(normalizeColour('#c62828'), '#C62828');
      expect(normalizeColour('#abc'), '#AABBCC');
      expect(normalizeColour(' #112233 '), '#112233');
    });

    test('rejects names and junk', () {
      expect(normalizeColour('red'), isNull);
      expect(normalizeColour('#12345'), isNull);
      expect(normalizeColour('#GGGGGG'), isNull);
      expect(normalizeColour(null), isNull);
    });

    test('a bad colour tag becomes an issue and a null colour', () {
      final data = overpassBytes([
        osmNode(1, 'A', 28.6, 77.1),
        osmNode(2, 'B', 28.7, 77.2),
        osmRelation(10, 'r', [1, 2], colour: 'red'),
      ]);
      final osm = normalizeOsm(data, network: 'Test Net');
      expect(osm.routes.single.colour, isNull);
      expect(osm.issues.single.code, 'bad-colour');
    });
  });

  group('OSM problems are reported, not swallowed', () {
    test('a stop node missing from the download', () {
      final data = overpassBytes([
        osmNode(1, 'A', 28.6, 77.1),
        osmNode(2, 'B', 28.7, 77.2),
        osmRelation(10, 'r', [1, 2, 999]),
      ]);
      final osm = normalizeOsm(data, network: 'Test Net');
      expect(osm.issues.map((i) => i.code), ['missing-node']);
      expect(osm.issues.single.message, contains('999'));
      expect(osm.routes.single.stops, hasLength(2));
    });

    test('an unnamed stop node', () {
      final data = overpassBytes([
        {
          'type': 'node',
          'id': 1,
          'lat': 28.6,
          'lon': 77.1,
          'tags': <String, String>{},
        },
        osmNode(2, 'B', 28.7, 77.2),
        osmNode(3, 'C', 28.8, 77.3),
        osmRelation(10, 'r', [1, 2, 3]),
      ]);
      final osm = normalizeOsm(data, network: 'Test Net');
      expect(osm.issues.map((i) => i.code), contains('bad-stop'));
    });

    test(
      'a relation with fewer than two usable stops is skipped and reported',
      () {
        final data = overpassBytes([
          osmNode(1, 'A', 28.6, 77.1),
          osmRelation(10, 'r', [1]),
        ]);
        final osm = normalizeOsm(data, network: 'Test Net');
        expect(osm.routes, isEmpty);
        expect(osm.issues.single.code, 'short-route');
      },
    );
  });

  group('corrupted OSM input', () {
    void bad(String why, List<int> bytes, [String? contains]) {
      test(why, () {
        expect(
          () => normalizeOsm(bytes, network: 'Test Net'),
          throwsA(
            isA<SourceFormatException>().having(
              (e) => e.message,
              'message',
              contains == null ? anything : containsString(contains),
            ),
          ),
        );
      });
    }

    bad('not JSON', utf8.encode('<html>'), 'not valid JSON');
    bad('JSON array at top level', utf8.encode('[1,2]'), 'not an object');
    bad('no elements', utf8.encode('{"a":1}'), 'elements');
    bad(
      'element without id',
      utf8.encode('{"elements":[{"type":"node"}]}'),
      'no type/id',
    );
    bad(
      'relation without members',
      utf8.encode(
        '{"elements":[{"type":"relation","id":1,"tags":{"route":"subway","network":"Test Net"}}]}',
      ),
      'members',
    );
  });

  group('Wikidata parsing', () {
    const rules = NormalizationRules(
      stripSuffixesEn: [' metro station'],
      stripSuffixesHi: [' मेट्रो स्टेशन', ', दिल्ली'],
    );

    test(
      'merges rows per station, strips configured suffixes, reads Point(lng lat)',
      () {
        final wd = normalizeWikidata(MiniWd.bytes(), rules);
        expect(wd.stations.keys, ['Q1000']);
        final s = wd.stations['Q1000']!;
        expect(s.labelEn, 'TEST Central');
        expect(s.labelHi, 'टेस्ट सेंट्रल');
        expect(s.lat, 28.6001);
        expect(s.lng, 77.1001);
        expect(s.lines.map((l) => l.qid), ['Q9001', 'Q9002']);
        expect(wd.lines['Q9001']!.labelHi, 'टेस्ट अल्फा लाइन');
      },
    );

    test('Hindi locality suffix is stripped only when configured', () {
      final bytes = sparqlBytes([
        wdRow('Q1', en: 'X metro station', hi: 'उत्तम नगर पूर्व, दिल्ली'),
      ]);
      expect(
        normalizeWikidata(bytes, rules).stations['Q1']!.labelHi,
        'उत्तम नगर पूर्व',
      );
      expect(
        normalizeWikidata(
          bytes,
          const NormalizationRules(),
        ).stations['Q1']!.labelHi,
        'उत्तम नगर पूर्व, दिल्ली',
      );
    });

    test('a label that is only the suffix is kept', () {
      expect(
        stripSuffixes(' metro station', [' metro station']),
        'metro station',
      );
    });

    test('missing labels and coordinates stay null', () {
      final wd = normalizeWikidata(sparqlBytes([wdRow('Q2')]), rules);
      final s = wd.stations['Q2']!;
      expect([s.labelEn, s.labelHi, s.lat, s.lng], [null, null, null, null]);
    });

    test('output order is deterministic (sorted by QID)', () {
      final wd = normalizeWikidata(
        sparqlBytes([wdRow('Q9'), wdRow('Q10'), wdRow('Q2')]),
        rules,
      );
      expect(wd.stations.keys.toList(), ['Q10', 'Q2', 'Q9']);
    });

    test('corrupted input', () {
      for (final b in [
        '',
        'oops',
        '{"results": 1}',
        '{"results":{"bindings":[1]}}',
        '{"results":{"bindings":[{}]}}',
      ]) {
        expect(
          () => normalizeWikidata(utf8.encode(b), rules),
          throwsA(isA<SourceFormatException>()),
          reason: b,
        );
      }
    });
  });
}

Matcher containsString(String s) => contains(s);
