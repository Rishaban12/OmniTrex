// Regression: ticking a note must mark exactly that note and leave every
// note where it was — even when several were added in the same second
// (creation time is stored to the second, so ties used to reshuffle).
import 'package:daily_budget/data/repositories/todo_repository.dart';
import 'package:daily_budget/presentation/screens/dolist_screen.dart';
import 'package:daily_budget/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  setUpAll(loadRoboto);

  const titles = ['i want to sleep', 'I want to read', 'i want to live', 'i want to study'];

  for (final width in [390.0, 742.0]) {
    testWidgets('tap marks the tapped note and nothing moves (width $width)', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final db = memoryDb();
      final repo = TodoRepository(db);
      final today = DateTime.now();
      // Added back-to-back → same createdAt second.
      for (final t in titles) {
        await tester.runAsync(() => repo.add(title: t, start: today));
      }
      await tester.pumpWidget(ProviderScope(
        overrides: await testOverrides(db: db, settings: setUpUser),
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const DoListScreen()),
      ));
      await tester.pumpAndSettle();

      Map<String, Offset> positions() => {for (final t in titles) t: tester.getCenter(find.text(t))};
      final before = positions();

      for (final tapped in ['i want to sleep', 'i want to study']) {
        await tester.tap(find.text(tapped));
        await tester.pumpAndSettle();
        expect(positions(), before, reason: 'notes moved after ticking "$tapped"');
      }

      final done = {for (final r in (await tester.runAsync(() => repo.listActive(today)))!) r.title: r.done};
      expect(done, {
        'i want to sleep': true,
        'I want to read': false,
        'i want to live': false,
        'i want to study': true,
      });

      // The struck-through text is on the tapped notes only.
      bool struck(String t) =>
          tester.widget<Text>(find.text(t)).style?.decoration == TextDecoration.lineThrough;
      expect(titles.where(struck), ['i want to sleep', 'i want to study']);

      // Pencil on "I want to read" edits that note only, without ticking it.
      final readNote = find.ancestor(of: find.text('I want to read'), matching: find.byType(StickyNote));
      await tester.tap(find.descendant(of: readNote, matching: find.byTooltip('Edit')));
      await tester.pumpAndSettle();
      expect(find.text('Edit to-do'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'I want to read 20 pages');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final after = {for (final r in (await tester.runAsync(() => repo.listActive(today)))!) r.title: r.done};
      expect(after['I want to read 20 pages'], isFalse);
      expect(after.containsKey('I want to read'), isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      await db.close();
    });
  }
}
