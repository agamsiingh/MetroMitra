import 'dart:math';

import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

import 'support/search_net.dart';

/// Realistic-size synthetic network: ~400 stations (more than any Indian
/// metro city), each with an English name, a Hindi name for most, an alias for
/// some and a code for many. Names are generated from invented syllables.
List<SStation> generate(int n, Random rnd) {
  const first = [
    'Kamal',
    'Raghav',
    'Sundar',
    'Mohan',
    'Gopal',
    'Anand',
    'Shiv',
    'Lakshmi',
    'Hari',
    'Jor',
    'Mayur',
    'Uttam',
    'Ashok',
    'Vijay',
    'Patel',
    'Nehru',
    'Gandhi',
    'Tilak',
    'Ram',
    'Sita',
    'Krishna',
    'Indra',
    'Moti',
    'Subhash',
  ];
  const second = [
    'Nagar',
    'Vihar',
    'Chowk',
    'Bagh',
    'Park',
    'Gate',
    'Enclave',
    'Colony',
    'Market',
    'Marg',
    'Puri',
    'Kunj',
    'Road',
    'Place',
    'Garden',
    'Extension',
  ];
  const hiFirst = [
    'कमल',
    'राघव',
    'सुंदर',
    'मोहन',
    'गोपाल',
    'आनंद',
    'शिव',
    'लक्ष्मी',
    'हरि',
    'जोर',
    'मयूर',
    'उत्तम',
    'अशोक',
    'विजय',
    'पटेल',
    'नेहरू',
    'गांधी',
    'तिलक',
    'राम',
    'सीता',
    'कृष्ण',
    'इंद्र',
    'मोती',
    'सुभाष',
  ];
  const hiSecond = [
    'नगर',
    'विहार',
    'चौक',
    'बाग',
    'पार्क',
    'गेट',
    'एन्क्लेव',
    'कॉलोनी',
    'मार्केट',
    'मार्ग',
    'पुरी',
    'कुंज',
    'रोड',
    'प्लेस',
    'गार्डन',
    'एक्सटेंशन',
  ];
  final seen = <String>{};
  final out = <SStation>[];
  var i = 0;
  while (out.length < n) {
    final a = rnd.nextInt(first.length);
    final b = rnd.nextInt(second.length);
    final num = rnd.nextInt(4) == 0 ? ' ${1 + rnd.nextInt(30)}' : '';
    final en = '${first[a]} ${second[b]}$num';
    if (!seen.add(en)) continue;
    out.add(
      SStation(
        's${i++}',
        en,
        hi: rnd.nextInt(10) < 8 ? '${hiFirst[a]} ${hiSecond[b]}$num' : null,
        aliases: rnd.nextInt(5) == 0 ? [alias('Old ${first[a]}')] : const [],
        codes: rnd.nextInt(3) == 0
            ? {'l-red': 'C${i.toRadixString(36).toUpperCase()}'}
            : const {},
        popularity: rnd.nextInt(60),
      ),
    );
  }
  return out;
}

String typo(String s, Random rnd) {
  if (s.length < 4) return s;
  final i = 1 + rnd.nextInt(s.length - 2);
  switch (rnd.nextInt(3)) {
    case 0:
      return s.substring(0, i) + s.substring(i + 1);
    case 1:
      return '${s.substring(0, i)}${s[i + 1 < s.length ? i + 1 : i]}${s[i]}${s.substring(i + 2 > s.length ? s.length : i + 2)}';
    default:
      return '${s.substring(0, i)}x${s.substring(i)}';
  }
}

void main() {
  final rnd = Random(2026);
  final stations = generate(400, rnd);
  final snap = buildSearchNet(stations);

  late SearchIndex index;

  test('building the index for 400 stations is fast', () {
    final sw = Stopwatch()..start();
    index = SearchIndex.fromSnapshot(snap);
    sw.stop();
    expect(index.entityCount, greaterThan(400));
    expect(sw.elapsedMilliseconds, lessThan(500));
  });

  test(
    'a realistic keystroke workload stays well inside one frame (16 ms)',
    () {
      // Per station: every prefix of the English name (typing), the full name
      // with a typo, a Hindi prefix, a code. ~ 400 * (10 + 3) queries.
      final queries = <String>[];
      for (final s in stations) {
        final en = s.en;
        for (var len = 1; len <= en.length; len += 2) {
          queries.add(en.substring(0, len));
        }
        queries
          ..add(typo(en, rnd))
          ..add(typo(en.toLowerCase(), rnd));
        if (s.hi != null) {
          queries.add(s.hi!.substring(0, (s.hi!.length / 2).ceil()));
        }
        if (s.codes.isNotEmpty) queries.add(s.codes.values.first);
      }
      // warm-up (JIT)
      queries.take(300).forEach(index.search);
      final times = <int>[];
      final sw = Stopwatch();
      for (final q in queries) {
        sw
          ..reset()
          ..start();
        final r = index.search(q);
        sw.stop();
        times.add(sw.elapsedMicroseconds);
        expect(r.length, lessThanOrEqualTo(20));
      }
      times.sort();
      final p50 = times[times.length ~/ 2];
      final p99 = times[(times.length * 0.99).floor()];
      final max = times.last;
      // Printed on purpose so a slow machine shows the numbers.
      // ignore: avoid_print
      print(
        'search perf over ${queries.length} queries: '
        'p50 ${p50}us  p99 ${p99}us  max ${max}us',
      );
      expect(p50, lessThan(4000), reason: 'median under 4 ms');
      expect(p99, lessThan(16000), reason: 'p99 under one 60 fps frame');
    },
  );

  test('worst cases: single letters, long garbage and no-match typos', () {
    final sw = Stopwatch()..start();
    [
      'a',
      'k',
      'ra',
      'nagar',
      'zzzzzzzz',
      'x' * 100,
      'kamal nagar vihar chowk park',
    ].forEach(index.search);
    for (var i = 0; i < 100; i++) {
      index.search('qwertyuiop$i');
    }
    sw.stop();
    expect(sw.elapsedMilliseconds / 107, lessThan(16));
  });

  test('results for the same workload are identical on every run', () {
    final a = [
      for (final s in ['kamal', 'raghav ch', 'sundr'])
        index.search(s).map((r) => r.entityId).join(','),
    ];
    final b = [
      for (final s in ['kamal', 'raghav ch', 'sundr'])
        SearchIndex.fromSnapshot(
          snap,
        ).search(s).map((r) => r.entityId).join(','),
    ];
    expect(a, b);
  });

  test('a generated network passes its own self-check', () {
    expect(index.selfCheck(), isEmpty);
  });
}
