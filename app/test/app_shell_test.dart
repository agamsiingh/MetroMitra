import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metromitra/app/l10n/generated/app_localizations.dart';
import 'package:metromitra/shared/widgets/state_view.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('shell shows Go, Map, Ask tabs and switches between them', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Go'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('Where do you want to go?'), findsOneWidget);

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.text('Metro map'), findsOneWidget);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    expect(find.text('Ask MetroMitra'), findsOneWidget);
  });

  testWidgets('Hindi locale renders translated tabs', (tester) async {
    await pumpApp(tester, locale: const Locale('hi'));
    expect(find.text('जाएँ'), findsOneWidget);
    expect(find.text('नक्शा'), findsOneWidget);
    expect(find.text('पूछें'), findsOneWidget);
  });

  group('StateView', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

    testWidgets('renders every kind with a title', (tester) async {
      for (final (kind, title) in [
        (StateViewKind.empty, 'Nothing here yet'),
        (StateViewKind.error, 'Something went wrong'),
        (StateViewKind.offline, "You're offline"),
        (StateViewKind.denied, 'Permission needed'),
      ]) {
        await pump(tester, StateView(kind: kind));
        expect(find.text(title), findsOneWidget, reason: '$kind');
      }
    });

    testWidgets('retry button appears only with a callback', (tester) async {
      await pump(tester, const StateView(kind: StateViewKind.error));
      expect(find.text('Try again'), findsNothing);

      var retried = false;
      await pump(
        tester,
        StateView(kind: StateViewKind.error, onRetry: () => retried = true),
      );
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });
  });
}
