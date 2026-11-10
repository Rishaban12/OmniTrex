import 'package:daily_budget/presentation/providers.dart';
import 'package:daily_budget/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('Reset data is the last item and asks Cancel / Okay', (tester) async {
    final db = memoryDb();
    final container = ProviderContainer(overrides: await testOverrides(db: db, settings: setUpUser));
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() => container.read(transactionRepoProvider).addManual(amount: 300, categoryId: null));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    final reset = find.text('Reset data');
    await tester.scrollUntilVisible(reset, 300);
    await tester.pumpAndSettle();
    // Nothing is below the Reset button.
    final list = tester.widget<ListView>(find.byType(ListView).first);
    final children = (list.childrenDelegate as SliverChildListDelegate).children;
    expect(find.descendant(of: find.byWidget(children.last), matching: reset), findsOneWidget);

    // Cancel → nothing changes.
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(find.text('Reset data?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Reset data?'), findsNothing);
    expect(container.read(settingsProvider).setupDone, isTrue);
    expect(await tester.runAsync(() => container.read(transactionRepoProvider).all()), hasLength(1));

    // Okay → data wiped, back to setup.
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Okay'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).setupDone, isFalse);
    expect(await tester.runAsync(() => container.read(transactionRepoProvider).all()), isEmpty);
  });
}
