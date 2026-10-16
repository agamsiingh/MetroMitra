import 'package:data_pipeline/data_pipeline.dart';
import 'package:test/test.dart';

const _cur = '''
    reason: "checked on site"
    source: mitra-curated
    verified_on: "2026-10-01"
''';

void main() {
  test('an empty or comment-only overlay is valid', () {
    expect(Overlay.parse('').operators, isEmpty);
    expect(Overlay.parse('# nothing yet\n').stations, isEmpty);
    expect(Overlay.empty.patch, 0);
  });

  test('a missing overlay file is an empty overlay', () {
    expect(Overlay.load('/nonexistent/overlay.yaml').merges, isEmpty);
  });

  test('parses every supported section with curation metadata', () {
    final o = Overlay.parse('''
release: { patch: 3 }
operators:
  - osm_operator: "TEST Operator"
    id: test-op
    name_hi: "टेस्ट"
$_cur
lines:
  - id: test-alpha-line
    name_hi: "अल्फा"
    color: "#aabbcc"
$_cur
stations:
  - id: test-central
    name_en: "TEST Central X"
    lat: 28.6
    lng: 77.1
    aliases: [{text: "TC", lang: en, kind: alias}]
$_cur
station_merges:
  - id: test-east
    members: ["test-east@a", "test-east@b"]
$_cur
resolutions:
  - conflict: "name-en-mismatch|station:test-central|name_en"
    use: wikidata
$_cur
''');
    expect(o.patch, 3);
    expect(o.operators.single.id, 'test-op');
    expect(o.lines.single.color, '#aabbcc');
    expect(o.stations.single.aliases.single.text, 'TC');
    expect(o.merges.single.members, hasLength(2));
    expect(o.resolutions.single.use, 'wikidata');
    expect(o.resolutions.single.curation.verifiedOn, '2026-10-01');
    expect(o.sha256, hasLength(64));
  });

  test('the content hash changes with the content', () {
    expect(
      Overlay.parse('release: {patch: 1}').sha256,
      isNot(Overlay.parse('release: {patch: 2}').sha256),
    );
  });

  group(
    'gates, platforms, facilities, fares, timings, parking are rejected (M2)',
    () {
      for (final key in Overlay.reservedSections) {
        test(key, () {
          expect(
            () => Overlay.parse('$key: []'),
            throwsA(
              isA<OverlayException>().having(
                (e) => e.message,
                'm',
                allOf(contains(key), contains('reserved')),
              ),
            ),
          );
        });
      }
    },
  );

  group('every curated entry must carry reason, source and verified_on', () {
    for (final missing in ['reason', 'source', 'verified_on']) {
      test('missing $missing', () {
        final lines = _cur
            .split('\n')
            .where((l) => l.trim().isNotEmpty && !l.trim().startsWith(missing))
            .join('\n');
        expect(
          () => Overlay.parse(
            'operators:\n  - osm_operator: x\n    id: y\n$lines',
          ),
          throwsA(
            isA<OverlayException>().having(
              (e) => e.message,
              'm',
              contains(missing),
            ),
          ),
        );
      });
    }

    test('verified_on must be a date', () {
      expect(
        () => Overlay.parse(
          'operators:\n  - osm_operator: x\n    id: y\n    reason: r\n    source: s\n    verified_on: yesterday\n',
        ),
        throwsA(
          isA<OverlayException>().having(
            (e) => e.message,
            'm',
            contains('YYYY-MM-DD'),
          ),
        ),
      );
    });
  });

  group('structural errors', () {
    test('unknown key is rejected with its path', () {
      expect(
        () => Overlay.parse(
          'operators:\n  - osm_operator: x\n    id: y\n    typo: 1\n$_cur',
        ),
        throwsA(
          isA<OverlayException>().having(
            (e) => e.message,
            'm',
            allOf(contains('operators[0]'), contains('typo')),
          ),
        ),
      );
    });

    test('unknown top-level section is rejected', () {
      expect(
        () => Overlay.parse('stationz: []'),
        throwsA(isA<OverlayException>()),
      );
    });

    test('a resolution must pick exactly one of accept/use', () {
      for (final body in ['', '    accept: true\n    use: osm\n']) {
        expect(
          () => Overlay.parse('resolutions:\n  - conflict: c\n$body$_cur'),
          throwsA(
            isA<OverlayException>().having(
              (e) => e.message,
              'm',
              contains('exactly one'),
            ),
          ),
        );
      }
    });

    test('a merge needs at least two members', () {
      expect(
        () => Overlay.parse(
          'station_merges:\n  - id: a\n    members: [x]\n$_cur',
        ),
        throwsA(isA<OverlayException>()),
      );
    });

    test('wrong types', () {
      expect(
        () => Overlay.parse('release: 3'),
        throwsA(isA<OverlayException>()),
      );
      expect(
        () => Overlay.parse('operators: 3'),
        throwsA(isA<OverlayException>()),
      );
      expect(() => Overlay.parse('- a'), throwsA(isA<OverlayException>()));
    });

    test('invalid YAML', () {
      expect(
        () => Overlay.parse('a: [unclosed'),
        throwsA(isA<OverlayException>()),
      );
    });
  });
}
