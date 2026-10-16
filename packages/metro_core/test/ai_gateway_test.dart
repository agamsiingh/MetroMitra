import 'package:metro_core/metro_core.dart';
import 'package:test/test.dart';

import 'assistant_cases_test.dart' show fixtureAssistant;
import 'support/fixture.dart' show loadFixture;

void main() {
  final snapshot = loadFixture();
  final search = SearchIndex.fromSnapshot(snapshot);
  final check = AiPostCheck(snapshot, search);

  test('offline gateway is unconfigured and unavailable', () async {
    const g = OfflineAiGateway();
    expect(g.configured, isFalse);
    final r = await g.ask(
      const AiRequest(
        question: 'q',
        locale: 'en',
        grounding: [],
        datasetVersion: 'v',
      ),
    );
    expect(r, isA<AiUnavailable>());
  });

  test('marked station names must exist; markers are removed', () {
    expect(
      check.verify('Take the metro to [[TEST Alpha]] and walk.'),
      'Take the metro to TEST Alpha and walk.',
    );
    expect(check.verify('Go to [[Narnia Central]] now.'), isNull);
  });

  test('an unmarked "X Station" that is not in the data is refused', () {
    expect(check.verify('Get off at Narnia Central Station.'), isNull);
  });

  test('amounts and times not in the grounding are refused', () {
    expect(check.verify('The fare is ₹40.'), isNull);
    expect(check.verify('The last train leaves at 23:30.'), isNull);
    const g = [AiFact('fare', '₹40 token')];
    expect(check.verify('The fare is ₹40.', grounding: g), 'The fare is ₹40.');
  });

  test('empty and over-long text is refused', () {
    expect(check.verify('  '), isNull);
    expect(check.verify('a' * (AiPostCheck.maxLength + 1)), isNull);
  });

  test('general advice with no station names passes', () {
    expect(
      check.verify('Keep your card ready before the gate and mind the gap.'),
      isNotNull,
    );
  });

  test('grounding holds only dataset facts about named places', () {
    final a = fixtureAssistant(snapshot);
    final q = a.understand('how do I reach test zeta from test alpha');
    final facts = AiGrounding.build(snapshot, q);
    expect(facts, isNotEmpty);
    expect(facts.every((f) => f.key == 'station' || f.key == 'line'), isTrue);
    expect(facts.map((f) => f.value).join(), contains('TEST'));
    expect(
      AiGrounding.build(snapshot, a.understand('tell me a joke')),
      isEmpty,
    );
  });
}
