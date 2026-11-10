import 'package:daily_budget/domain/services/weekly_insight.dart';
import 'package:daily_budget/presentation/common.dart';
import 'package:daily_budget/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const food = 1, travel = 2, bills = 3;
String name(int? id) => switch (id) { food => 'Food', travel => 'Travel', bills => 'Bills', _ => 'Uncategorized' };
final money = Money('INR').call;

// Week under test: Mon 9 Nov – Sun 15 Nov 2026.
final mon = DateTime(2026, 11, 9);
WeekSpend at(int? cat, int day, double amount, {int month = 11}) =>
    (categoryId: cat, at: DateTime(2026, month, day, 12), amount: amount);

/// Four normal history weeks (12 Oct – 8 Nov): Food 1,000/wk, Travel 500/wk.
final history = [
  for (final d in [13, 20, 27]) ...[at(food, d, 1000, month: 10), at(travel, d, 500, month: 10)],
  at(food, 3, 1000), at(travel, 3, 500),
];

void main() {
  group('timing', () {
    test('fires Sunday 7 PM of this week, or next week once it has passed', () {
      expect(WeeklyInsight.nextFireTime(DateTime(2026, 11, 11, 9)), DateTime(2026, 11, 15, 19)); // Wed
      expect(WeeklyInsight.nextFireTime(DateTime(2026, 11, 15, 18, 59)), DateTime(2026, 11, 15, 19));
      expect(WeeklyInsight.nextFireTime(DateTime(2026, 11, 15, 19)), DateTime(2026, 11, 22, 19));
      expect(WeeklyInsight.nextFireTime(DateTime(2026, 12, 28)), DateTime(2027, 1, 3, 19)); // across the year
    });

    test('mondayOf', () {
      expect(WeeklyInsight.mondayOf(DateTime(2026, 11, 15, 23)), mon);
      expect(WeeklyInsight.mondayOf(mon), mon);
    });
  });

  group('positive — high categories', () {
    test('Travel doubled vs usual → "Travel is high this week"', () {
      final r = WeeklyInsight.analyze(
          weekStart: mon, entries: [...history, at(food, 10, 1000), at(travel, 11, 1200)]);
      expect(r.high.map((h) => h.categoryId), [travel]);
      final m = WeeklyInsight.message(r, name: name, money: money);
      expect(m.title, 'Travel is high this week');
      expect(m.body, '₹1,200 (usually ₹500).');
    });

    test('several high → biggest excess first, others listed', () {
      final r = WeeklyInsight.analyze(
          weekStart: mon, entries: [...history, at(food, 10, 2500), at(travel, 11, 900)]);
      expect(r.high.map((h) => h.categoryId), [food, travel]);
      expect(WeeklyInsight.message(r, name: name, money: money).body, contains('Travel is also high'));
    });

    test('brand-new category with no history but big share is flagged', () {
      final r = WeeklyInsight.analyze(
          weekStart: mon, entries: [...history, at(food, 10, 900), at(bills, 12, 3000)]);
      expect(r.high.single.categoryId, bills);
      expect(WeeklyInsight.message(r, name: name, money: money).body, contains('% of your week'));
    });

    test('first week ever: a category with ≥ 40% share is high', () {
      final r = WeeklyInsight.analyze(weekStart: mon, entries: [at(food, 10, 300), at(travel, 11, 900)]);
      expect(r.high.single.categoryId, travel);
    });
  });

  group('negative — nothing flagged', () {
    test('normal week → "balanced"', () {
      final r = WeeklyInsight.analyze(
          weekStart: mon, entries: [...history, at(food, 10, 1100), at(travel, 11, 550)]);
      expect(r.high, isEmpty);
      expect(WeeklyInsight.message(r, name: name, money: money).title, contains('balanced'));
    });

    test('tiny amounts are ignored even if they spike', () {
      final r = WeeklyInsight.analyze(weekStart: mon, entries: [...history, at(bills, 10, 60)]);
      expect(r.high, isEmpty);
    });

    test('no expenses this week', () {
      final r = WeeklyInsight.analyze(weekStart: mon, entries: history);
      expect(r.total, 0);
      expect(WeeklyInsight.message(r, name: name, money: money).body, 'No expenses logged this week.');
    });

    test('refunds reduce the week (a refunded trip is not "high")', () {
      final r = WeeklyInsight.analyze(
          weekStart: mon, entries: [...history, at(travel, 10, 1500), at(travel, 12, -1200), at(food, 11, 1000)]);
      expect(r.high, isEmpty);
    });

    test('spending outside the week or history window is ignored', () {
      final r = WeeklyInsight.analyze(weekStart: mon, entries: [at(travel, 16, 5000), at(travel, 1, 5000, month: 9)]);
      expect(r.total, 0);
    });
  });

  group('scheduling', () {
    Future<(ProviderContainer, FakeNotifications)> container(settings) async {
      final db = memoryDb();
      final fake = FakeNotifications();
      final c = ProviderContainer(overrides: await testOverrides(db: db, settings: settings, notifications: fake));
      addTearDown(() async {
        c.dispose();
        await db.close();
      });
      return (c, fake);
    }

    test('positive: schedules for the coming Sunday 7 PM and updates as you spend', () async {
      final (c, fake) = await container(setUpUser);
      final sub = c.listen(weeklyInsightNotificationProvider, (_, _) {});
      await c.read(weeklyWindowTransactionsProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(fake.weekly.last.at.weekday, DateTime.sunday);
      expect(fake.weekly.last.at.hour, 19);

      await c.read(transactionRepoProvider).addManual(amount: 4000, categoryId: null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fake.weekly.last.title, 'Uncategorized is high this week');
      sub.close();
    });

    test('negative: switched off → cancelled, never scheduled', () async {
      final (c, fake) = await container(setUpUser.copyWith(weeklyInsight: false));
      final sub = c.listen(weeklyInsightNotificationProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fake.weekly, isEmpty);
      expect(fake.weeklyCancels, greaterThan(0));
      sub.close();
    });
  });
}
