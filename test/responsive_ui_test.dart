// Drives the real app at phone, landscape, tablet and desktop sizes.
// Any RenderFlex overflow or exception during build/layout fails the test.
import 'package:daily_budget/app.dart';
import 'package:daily_budget/data/db/app_database.dart';
import 'package:daily_budget/domain/entities/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const sizes = {
  'small phone 320×568': Size(320, 568),
  'phone 390×844': Size(390, 844),
  'phone landscape 844×390': Size(844, 390),
  'tablet 820×1180': Size(820, 1180),
  'desktop 1440×900': Size(1440, 900),
};

Future<AppDatabase> launch(WidgetTester tester, Size size, AppSettings settings) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = memoryDb();
  final overrides = await testOverrides(db: db, settings: settings);
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: const DailyBudgetApp()));
  // Splash animation (3.6 s) + fade to the next page.
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
  return db;
}

/// Unmounts the app and closes the DB inside the test body, so stream /
/// snackbar timers are flushed before the framework checks for leftovers.
Future<void> finish(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
  await db.close();
  await tester.pump(const Duration(seconds: 1));
}

/// Scrolls the page down, then up, until [f] is built and visible.
Future<void> scrollTo(WidgetTester tester, Finder f) async {
  if (f.evaluate().isNotEmpty) return;
  final page = find.byType(Scrollable).first;
  try {
    await tester.scrollUntilVisible(f, 200, scrollable: page, maxScrolls: 30);
  } on StateError {
    await tester.scrollUntilVisible(f, -200, scrollable: page, maxScrolls: 30);
  }
}

/// Scrolls [f] into view like a user would (short screens), then taps it.
/// Use `skipOffstage: false` finders for items that may start off-screen.
Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    // Not built yet: scroll the page down, then up, until it appears.
    final page = find.byType(Scrollable).first;
    try {
      await tester.scrollUntilVisible(f, 200, scrollable: page, maxScrolls: 30);
    } on StateError {
      await tester.scrollUntilVisible(f, -200, scrollable: page, maxScrolls: 30);
    }
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadRoboto);

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    group(name, () {
      testWidgets('new user: splash → onboarding → hub → setup → PocketPlan', (tester) async {
        final db = await launch(tester, size, const AppSettings());

        expect(find.text('Plan ahead.\nGet things done.'), findsOneWidget);
        await tapAndSettle(tester, find.byIcon(Icons.arrow_forward_rounded).last);
        await tapAndSettle(tester, find.byIcon(Icons.arrow_forward_rounded).last);
        expect(find.text('What\'s next?'), findsOneWidget);

        // Theme toggle (top right) switches light ↔ dark without breaking layout.
        await tapAndSettle(tester, find.byIcon(Icons.light_mode_rounded));
        expect(Theme.of(tester.element(find.text('What\'s next?'))).brightness, Brightness.dark);
        await tapAndSettle(tester, find.byIcon(Icons.dark_mode_rounded));
        expect(Theme.of(tester.element(find.text('What\'s next?'))).brightness, Brightness.light);

        await tapAndSettle(tester, find.text('PocketPlan', skipOffstage: false));
        expect(find.text('Set up your budget'), findsOneWidget);

        // Negative: saving without an amount shows the validation error.
        await tapAndSettle(tester, find.text('Start tracking'));
        // (On short screens the field may be scrolled above the button.)
        expect(find.text('Enter your monthly budget', skipOffstage: false), findsOneWidget);

        final amount = find.widgetWithText(TextFormField, 'Monthly amount', skipOffstage: false);
        await tester.ensureVisible(amount);
        await tester.pumpAndSettle();
        await tester.enterText(amount, '30000');
        // Close the keyboard (user taps Done) — a focused field keeps pulling
        // the page back to itself on short screens.
        await tester.testTextInput.receiveAction(TextInputAction.done);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text('Start tracking', skipOffstage: false));
        expect(find.text('left today'), findsOneWidget);
        await finish(tester, db);
      });

      testWidgets('PocketPlan: every tab, add expense, fixed panel, calendar', (tester) async {
        final db = await launch(tester, size, setUpUser);
        await tapAndSettle(tester, find.text('PocketPlan', skipOffstage: false));
        expect(find.text('left today'), findsOneWidget);

        // Negative: saving with no amount keeps the sheet open.
        await tapAndSettle(tester, find.byTooltip('Add expense'));
        await tapAndSettle(tester, find.widgetWithText(ActionChip, 'Food'));
        expect(find.text('Add expense'), findsOneWidget);

        // Positive: amount + category saves and shows in "Spent today".
        await tester.enterText(find.byType(TextField).first, '250');
        await tapAndSettle(tester, find.widgetWithText(ActionChip, 'Food'));
        expect(find.text('Add expense'), findsNothing);
        expect(find.text('₹250'), findsWidgets);

        // Fixed-expenses panel and month calendar open without overflow.
        await tapAndSettle(tester, find.text('Fixed expenses'));
        expect(find.text('No fixed expenses yet.'), findsOneWidget);
        await tapAndSettle(tester, find.byTooltip('Show month'));
        expect(find.text('M'), findsOneWidget);

        for (final tab in ['Insights', 'Parser', 'Settings', 'Today']) {
          await tapAndSettle(tester, find.text(tab).last);
        }

        // Back arrow on Insights / Parser / Settings → PocketPlan Today, not the hub.
        for (final tab in ['Insights', 'Parser', 'Settings']) {
          await tapAndSettle(tester, find.text(tab).last);
          await tapAndSettle(tester, find.byType(BackButton).hitTestable());
          // Still inside PocketPlan, on the Today tab.
          expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0, reason: 'back from $tab');
          expect(find.text('What\'s next?'), findsNothing);
        }

        // Parser: a sample message goes through the real pipeline.
        await tapAndSettle(tester, find.text('Parser').last);
        await tapAndSettle(tester, find.text('Test the message parser'));
        await tapAndSettle(tester, find.text('Sample 1'));
        await tapAndSettle(tester, find.text('Parse'));
        expect(find.textContaining('Logged debit'), findsOneWidget);
        await finish(tester, db);
      });

      testWidgets('DoList: today list with start/end dates, add, complete, edit, delete', (tester) async {
        final db = await launch(tester, size, setUpUser);
        await tapAndSettle(tester, find.text('DoList', skipOffstage: false));
        // One "Today" list; no week / month sections or switches.
        expect(find.text('Nothing planned for today yet', skipOffstage: false), findsOneWidget);
        expect(find.text('This week', skipOffstage: false), findsNothing);
        expect(find.byType(SegmentedButton), findsNothing);

        // Negative: blank to-do is refused.
        await tapAndSettle(tester, find.byTooltip('Add to-do'));
        expect(find.text('Start'), findsOneWidget);
        expect(find.text('End'), findsOneWidget);
        // Date + time shown in the fields, e.g. "8 Nov, 9:30 AM".
        expect(find.textContaining(RegExp(r'\d+ \w{3}, \d{1,2}:\d{2} [AP]M')), findsNWidgets(2));
        await tapAndSettle(tester, find.text('Add'));
        expect(find.text('Write something to do'), findsOneWidget);

        // Positive: default dates = today → appears in Today.
        const task = 'Buy milk and bread for the week';
        await tester.enterText(find.byType(TextField).first, task);
        await tapAndSettle(tester, find.text('Add'));
        await scrollTo(tester, find.text(task));
        expect(find.text(task), findsOneWidget);
        expect(find.text('Today', skipOffstage: false), findsNothing); // progress card removed

        // Complete it.
        await tapAndSettle(tester, find.text(task));
        expect(tester.widget<Text>(find.text(task)).style?.decoration, TextDecoration.lineThrough);

        // Edit → delete.
        final note = find.text(task, skipOffstage: false);
        await tester.ensureVisible(note);
        await tester.pumpAndSettle();
        await tester.longPress(note);
        await tester.pumpAndSettle();
        expect(find.text('Edit to-do'), findsOneWidget);
        await tapAndSettle(tester, find.text('Delete'));
        expect(find.text('Nothing planned for today yet', skipOffstage: false), findsOneWidget);
        await finish(tester, db);
      });

      testWidgets('MindNotes: write, find, pin, edit, delete', (tester) async {
        final db = await launch(tester, size, setUpUser);
        await tapAndSettle(tester, find.text('MindNotes', skipOffstage: false));
        expect(find.text('No notes yet — tap + to write your first one'), findsOneWidget);

        // Negative: a new note left empty is not kept.
        await tapAndSettle(tester, find.byTooltip('New note'));
        await tapAndSettle(tester, find.byType(BackButton));
        expect(find.text('No notes yet — tap + to write your first one'), findsOneWidget);

        // Positive: write one; it saves on the way back.
        await tapAndSettle(tester, find.byTooltip('New note'));
        await tester.enterText(find.byType(TextField).at(0), 'Kite plan');
        await tester.enterText(find.byType(TextField).at(1), 'Buy string and paper\nFly on Sunday');
        await tapAndSettle(tester, find.byType(BackButton));
        expect(find.text('Kite plan'), findsOneWidget);
        expect(find.textContaining('Buy string'), findsOneWidget);

        // Search: match and no match.
        await tester.enterText(find.byType(TextField).first, 'zebra');
        await tester.pumpAndSettle();
        expect(find.text('No notes match your search'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'KITE');
        await tester.pumpAndSettle();
        expect(find.text('Kite plan'), findsOneWidget);
        await tapAndSettle(tester, find.byTooltip('Clear search'));

        // Pin + edit: shows under "Pinned" with the new title.
        await tapAndSettle(tester, find.text('Kite plan'));
        await tapAndSettle(tester, find.byTooltip('Pin to top'));
        await tester.enterText(find.byType(TextField).at(0), 'Kite day');
        await tapAndSettle(tester, find.byType(BackButton));
        expect(find.text('Pinned'), findsOneWidget);
        expect(find.text('Kite day'), findsOneWidget);

        // Delete asks first: Cancel keeps it, Delete removes it.
        await tapAndSettle(tester, find.text('Kite day'));
        await tapAndSettle(tester, find.byTooltip('Delete note'));
        await tapAndSettle(tester, find.text('Cancel'));
        expect(find.text('Kite day'), findsOneWidget);
        await tapAndSettle(tester, find.byTooltip('Delete note'));
        await tapAndSettle(tester, find.text('Delete'));
        expect(find.text('No notes yet — tap + to write your first one'), findsOneWidget);
        await finish(tester, db);
      });
    });
  }

  // Phones set to a bigger system font (Accessibility → Font size).
  for (final scale in [1.3, 1.6]) {
    testWidgets('large font ×$scale on a 360×740 phone: hub, every PocketPlan tab, DoList', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final db = await launch(tester, const Size(360, 740), setUpUser);
      expect(find.text('What\'s next?'), findsOneWidget);

      await tapAndSettle(tester, find.text('PocketPlan', skipOffstage: false));
      await tapAndSettle(tester, find.text('Fixed expenses'));
      await tapAndSettle(tester, find.byTooltip('Show month'));
      for (final tab in ['Insights', 'Parser', 'Settings', 'Today']) {
        await tapAndSettle(tester, find.text(tab).last);
      }
      await tapAndSettle(tester, find.byTooltip('Add expense'));
      expect(find.text('Add expense'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // close the sheet
      await tester.pumpAndSettle();

      Navigator.of(tester.element(find.byType(NavigationBar))).pop();
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text('DoList', skipOffstage: false));
      await tapAndSettle(tester, find.byTooltip('Add to-do'));
      expect(find.text('Start'), findsOneWidget);
      await finish(tester, db);
    });
  }
}
