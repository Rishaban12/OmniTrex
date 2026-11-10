import 'package:daily_budget/app.dart';
import 'package:daily_budget/domain/entities/app_settings.dart';
import 'package:daily_budget/domain/services/daily_limit_calculator.dart';
import 'package:daily_budget/domain/services/morning_limit.dart';
import 'package:daily_budget/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('MorningLimit (pure)', () {
    test('upcoming: 7 mornings from the next 6 AM, across month end', () {
      final late = MorningLimit.upcoming(DateTime(2026, 11, 28, 22));
      expect(late, hasLength(7));
      expect(late.first, DateTime(2026, 11, 29, 6));
      expect(late[2], DateTime(2026, 12, 1, 6));
      expect(late.last, DateTime(2026, 12, 5, 6));
      final early = MorningLimit.upcoming(DateTime(2026, 11, 10, 5, 59), count: 2);
      expect(early, [DateTime(2026, 11, 10, 6), DateTime(2026, 11, 11, 6)]);
    });

    test('negative: a booked morning is never in the past or at 6:00 sharp now', () {
      final now = DateTime(2026, 11, 10, 6);
      expect(MorningLimit.upcoming(now).first, DateTime(2026, 11, 11, 6));
    });

    test('future mornings announce rising limits when nothing more is spent (rollover)', () {
      final nov = BudgetCycle(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
      final limits = [
        for (final at in MorningLimit.upcoming(DateTime(2026, 11, 10, 12), count: 3))
          MorningLimit.budgetAt(
            fireAt: at,
            monthlyBudget: 30000,
            fixedExpenses: 0,
            rollover: true,
            cycleFor: (_) => nov,
            entries: [SpendEntry(DateTime(2026, 11, 2), 3000)],
          ).dailyLimit,
      ];
      expect(limits[0], closeTo(27000 / 20, 0.001)); // 11 Nov
      expect(limits[1], closeTo(27000 / 19, 0.001)); // 12 Nov
      expect(limits[2], closeTo(27000 / 18, 0.001));
    });

    test('fires today at 6 if it is still early, else tomorrow', () {
      expect(MorningLimit.nextFireTime(DateTime(2026, 11, 8, 5, 59)), DateTime(2026, 11, 8, 6));
      expect(MorningLimit.nextFireTime(DateTime(2026, 11, 8, 6)), DateTime(2026, 11, 9, 6));
      expect(MorningLimit.nextFireTime(DateTime(2026, 11, 8, 21, 30)), DateTime(2026, 11, 9, 6));
      expect(MorningLimit.nextFireTime(DateTime(2026, 12, 31, 23)), DateTime(2027, 1, 1, 6));
    });

    BudgetCycle nov(DateTime d) => BudgetCycle(DateTime(2026, 11, 1), DateTime(2026, 12, 1));

    test('tomorrow\'s limit counts everything spent so far, today included', () {
      // 30-day ₹3,000 month; ₹800 spent by the evening of 8 Nov.
      final b = MorningLimit.budgetAt(
        fireAt: DateTime(2026, 11, 9, 6),
        monthlyBudget: 3000,
        fixedExpenses: 0,
        rollover: true,
        cycleFor: nov,
        entries: [SpendEntry(DateTime(2026, 11, 3), 300), SpendEntry(DateTime(2026, 11, 8, 20), 500)],
      );
      expect(b.daysRemaining, 22); // 9–30 Nov
      expect(b.dailyLimit, closeTo((3000 - 800) / 22, 0.01));
      expect(b.spentToday, 0); // nothing spent yet on the 9th at 6 AM
    });

    test('negative: overspent month → limit announced as 0', () {
      final b = MorningLimit.budgetAt(
        fireAt: DateTime(2026, 11, 9, 6),
        monthlyBudget: 1000,
        fixedExpenses: 0,
        rollover: true,
        cycleFor: nov,
        entries: [SpendEntry(DateTime(2026, 11, 8), 1500)],
      );
      expect(b.dailyLimit, 0);
    });

    test('a new budget period tomorrow starts fresh', () {
      final b = MorningLimit.budgetAt(
        fireAt: DateTime(2026, 12, 1, 6),
        monthlyBudget: 3100,
        fixedExpenses: 0,
        rollover: true,
        cycleFor: (d) => BudgetCycle.containing(d, 1),
        entries: [SpendEntry(DateTime(2026, 11, 30), 2999)],
      );
      expect(b.dailyLimit, 100); // 3100 / 31 December days
    });
  });

  group('6 AM notification scheduling', () {
    Future<(ProviderContainer, FakeNotifications)> setUpContainer(AppSettings settings) async {
      final db = memoryDb();
      final fake = FakeNotifications();
      final c = ProviderContainer(overrides: await testOverrides(db: db, settings: settings, notifications: fake));
      addTearDown(() async {
        c.dispose();
        await db.close();
      });
      return (c, fake);
    }

    Future<void> settle(ProviderContainer c) async {
      // Let the DB streams deliver, then evaluate the scheduler.
      await c.read(cycleTransactionsProvider.future);
      await c.read(fixedExpensesProvider.future);
      c.read(morningLimitNotificationProvider);
      await Future<void>.delayed(Duration.zero);
    }

    test('positive: schedules "Today\'s limit is ₹…" for the next 6 AM', () async {
      final (c, fake) = await setUpContainer(setUpUser);
      final sub = c.listen(morningLimitNotificationProvider, (_, _) {});
      await settle(c);
      expect(fake.morning, isNotEmpty);
      final next = fake.morning.first;
      expect(next.title, startsWith('Today\'s limit is ₹'));
      expect(next.at.hour, 6);
      expect(next.at.isAfter(DateTime.now()), isTrue);
      sub.close();
    });

    test('positive: the next 7 mornings are booked, one per day at 6 AM', () async {
      final (c, fake) = await setUpContainer(setUpUser);
      final sub = c.listen(morningLimitNotificationProvider, (_, _) {});
      await settle(c);
      final days = fake.morning;
      expect(days, hasLength(MorningLimit.daysAhead));
      for (final (i, d) in days.indexed) {
        expect(d.at.hour, 6);
        if (i > 0) expect(dateOnly(d.at).difference(dateOnly(days[i - 1].at)).inHours, inInclusiveRange(23, 25));
      }
      expect(days.every((d) => d.title.startsWith('Today\'s limit is ')), isTrue);
      sub.close();
    });

    test('positive: spending reschedules with a lower amount', () async {
      final (c, fake) = await setUpContainer(setUpUser);
      final sub = c.listen(morningLimitNotificationProvider, (_, _) {});
      await settle(c);
      final before = fake.morning.first.title;
      await c.read(transactionRepoProvider).addManual(amount: 5000, categoryId: null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await settle(c);
      expect(fake.morning.first.title, isNot(before));
      sub.close();
    });

    test('negative: switched off or not set up → cancelled, never scheduled', () async {
      for (final s in [setUpUser.copyWith(morningLimit: false), const AppSettings()]) {
        final (c, fake) = await setUpContainer(s);
        final sub = c.listen(morningLimitNotificationProvider, (_, _) {});
        await settle(c);
        expect(fake.morning, isEmpty);
        expect(fake.morningCancels, greaterThan(0));
        sub.close();
      }
    });
  });

  group('over-limit alert (whole app)', () {
    setUpAll(loadRoboto);

    Future<FakeNotifications> overspend(WidgetTester tester, AppSettings settings, List<String> amounts) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = memoryDb();
      final fake = FakeNotifications();
      await tester.pumpWidget(ProviderScope(
        overrides: await testOverrides(db: db, settings: settings, notifications: fake),
        child: const DailyBudgetApp(),
      ));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PocketPlan', skipOffstage: false));
      await tester.pumpAndSettle();
      for (final a in amounts) {
        await tester.tap(find.byTooltip('Add expense'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, a);
        await tester.tap(find.widgetWithText(ActionChip, 'Food'));
        await tester.pumpAndSettle();
        // Let any 2 s popup clear before tapping + again.
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      await db.close();
      return fake;
    }

    // ₹30,000 over 30 days → ~₹1,000/day.
    testWidgets('positive: going over the limit notifies once (no repeat while still over)', (tester) async {
      final fake = await overspend(tester, setUpUser, ['200', '5000', '300']);
      expect(fake.overLimit, hasLength(1));
      expect(fake.overLimit.single, contains('Spent ₹5,200'));
    });

    testWidgets('positive: back under the limit, then over again → a second alert', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = memoryDb();
      final fake = FakeNotifications();
      await tester.pumpWidget(ProviderScope(
        overrides: await testOverrides(db: db, settings: setUpUser, notifications: fake),
        child: const DailyBudgetApp(),
      ));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PocketPlan', skipOffstage: false));
      await tester.pumpAndSettle();

      Future<void> add(String a) async {
        await tester.tap(find.byTooltip('Add expense'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, a);
        await tester.tap(find.widgetWithText(ActionChip, 'Food'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      }

      await add('5000');
      expect(fake.overLimit, hasLength(1));
      // Still over: no repeat.
      await add('100');
      expect(fake.overLimit, hasLength(1));

      // Delete both → under again (re-arms), then cross once more.
      await tester.runAsync(() async {
        await db.delete(db.transactions).go();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await add('4000');
      expect(fake.overLimit, hasLength(2));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      await db.close();
    });

    testWidgets('negative: staying under the limit never notifies', (tester) async {
      final fake = await overspend(tester, setUpUser, ['10', '20']);
      expect(fake.overLimit, isEmpty);
    });

    testWidgets('negative: alert switched off → no notification', (tester) async {
      final fake = await overspend(tester, setUpUser.copyWith(overLimitAlert: false), ['9000']);
      expect(fake.overLimit, isEmpty);
    });
  });
}
