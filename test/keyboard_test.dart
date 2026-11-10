// Regression: on a real phone the on-screen keyboard takes ~40% of the
// screen. Bottom sheets must scroll instead of overflowing (Galaxy M12 bug).
import 'package:daily_budget/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpAll(loadRoboto);

  // Galaxy M12-ish screen (720×1600 @ 2x ≈ 360×800) with a 330 dp keyboard.
  Future<void> withKeyboard(WidgetTester tester, Future<void> Function() body) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final db = memoryDb();
    await tester.pumpWidget(ProviderScope(
      overrides: await testOverrides(db: db, settings: setUpUser),
      child: const DailyBudgetApp(),
    ));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await body();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await db.close();
  }

  Future<void> openKeyboard(WidgetTester tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 660); // 330 dp
    await tester.pumpAndSettle();
  }

  testWidgets('Add expense sheet scrolls with the keyboard open', (tester) async {
    await withKeyboard(tester, () async {
      await tester.tap(find.text('PocketPlan', skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add expense'));
      await tester.pumpAndSettle();
      await openKeyboard(tester);
      // No overflow (would fail the test) and categories are reachable by scrolling.
      await tester.dragUntilVisible(
          find.widgetWithText(ActionChip, 'Food'), find.byType(SingleChildScrollView).last, const Offset(0, -80));
      expect(find.widgetWithText(ActionChip, 'Food'), findsOneWidget);
    });
  });

  testWidgets('DoList editor scrolls with the keyboard open', (tester) async {
    await withKeyboard(tester, () async {
      await tester.tap(find.text('DoList', skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add to-do'));
      await tester.pumpAndSettle();
      await openKeyboard(tester);
      await tester.dragUntilVisible(find.text('Add'), find.byType(SingleChildScrollView).last, const Offset(0, -80));
      expect(find.text('Add'), findsOneWidget);
    });
  });
}
