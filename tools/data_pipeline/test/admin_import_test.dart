import 'dart:convert';

import 'package:data_pipeline/src/admin_import.dart';
import 'package:data_pipeline/src/overlay.dart';
import 'package:test/test.dart';

String _export(Map<String, Object?> tables) => jsonEncode({
  'format': 'metromitra-curated/1',
  'exported_at': '2026-10-16T00:00:00.000Z',
  'tables': tables,
  'skipped': <String>[],
});

Map<String, Object?> _station([Map<String, Object?> extra = const {}]) => {
  'station_id': 'rajiv-chowk',
  'name_hi': 'राजीव चौक',
  'aliases': [
    {'text': 'CP', 'lang': 'en', 'kind': 'alias'},
  ],
  'source': 'DMRC station signage',
  'verified_on': '2026-10-01',
  'confidence': 'official',
  ...extra,
};

void main() {
  test('approved station rows become station overlays', () {
    final a = AdminImport.parse(
      _export({
        'curated_stations': [_station()],
      }),
    );
    expect(a.stations, hasLength(1));
    final s = a.stations.single;
    expect(s.id, 'rajiv-chowk');
    expect(s.nameHi, 'राजीव चौक');
    expect(s.nameEn, isNull, reason: 'empty stays unknown');
    expect(s.lat, isNull);
    expect(s.aliases.single.text, 'CP');
    expect(s.curation.source, 'DMRC station signage');
    expect(s.curation.verifiedOn, '2026-10-01');
    expect(a.sha256, hasLength(64));
  });

  test('a row without provenance is refused, not imported', () {
    for (final k in ['source', 'verified_on', 'confidence']) {
      expect(
        () => AdminImport.parse(
          _export({
            'curated_stations': [
              _station({k: null}),
            ],
          }),
        ),
        throwsA(isA<OverlayException>()),
        reason: k,
      );
    }
  });

  test('tables the dataset cannot hold yet are counted, never guessed', () {
    final a = AdminImport.parse(
      _export({
        'curated_stations': <Object>[],
        'curated_gates': [
          {'station_id': 'a', 'gate_no': '1'},
        ],
        'curated_fares': <Object>[],
      }),
    );
    expect(a.stations, isEmpty);
    expect(a.notImported, {'curated_gates': 1});
  });

  test('wrong format, bad JSON, duplicates and bad values are refused', () {
    expect(
      () => AdminImport.parse('{"format":"other","tables":{}}'),
      throwsA(isA<OverlayException>()),
    );
    expect(
      () => AdminImport.parse('{not json'),
      throwsA(isA<OverlayException>()),
    );
    expect(
      () => AdminImport.parse(
        _export({
          'curated_stations': [_station(), _station()],
        }),
      ),
      throwsA(isA<OverlayException>()),
    );
    expect(
      () => AdminImport.parse(
        _export({
          'curated_stations': [
            _station({'lat': '28.6'}),
          ],
        }),
      ),
      throwsA(isA<OverlayException>()),
    );
    expect(
      () => AdminImport.parse(
        _export({
          'curated_stations': [
            _station({'verified_on': '01/10/2026'}),
          ],
        }),
      ),
      throwsA(isA<OverlayException>()),
    );
  });

  test('no export file means nothing to import', () {
    final a = AdminImport.load('does/not/exist.json');
    expect(a.stations, isEmpty);
    expect(a.file, isNull);
  });
}
