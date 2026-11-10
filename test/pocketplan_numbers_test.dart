// PocketPlan numbers end to end: real (in-memory) database, real providers,
// fixed "today" of 10 Nov 2026 in a 1–30 Nov budget (21 days left incl. today).
import 'package:daily_budget/data/db/app_database.dart';
import 'package:daily_budget/domain/entities/app_settings.dart';
import 'package:daily_budget/domain/services/daily_limit_calculator.dart';
import 'package:daily_budget/domain/services/sms_parser.dart';
import 'package:daily_budget/presentation/providers.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  final now = DateTime(2026, 11, 10, 12);
  late AppDatabase db;
  late ProviderContainer c;

  Future<void> start([AppSettings? settings]) async {
    db = memoryDb();
    c = ProviderContainer(overrides: [
      ...await testOverrides(db: db, settings: settings ?? setUpUser),
      clockProvider.overrideWith((ref) => Stream.value(now)),
    ]);
    // Keep the streams alive like the screens do.
    for (final p in [dailyBudgetProvider, cycleDaysProvider, categorySpendProvider, todayCategorySpendProvider]) {
      c.listen(p, (_, _) {}, fireImmediately: true);
    }
    await settle();
  }

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  DailyBudget budget() => c.read(dailyBudgetProvider).requireValue;
  Future<void> spend(double amount, DateTime at, {int? cat}) async {
    await c.read(transactionRepoProvider).addManual(amount: amount, categoryId: cat, at: at);
    await settle();
  }

  Future<void> refund(double amount, DateTime at) async {
    await c.read(transactionRepoProvider).ingest(ParsedTxn(
          raw: RawMessage(body: 'refund', source: MessageSource.sms, receivedAt: at),
          amount: amount,
          direction: TxnDirection.refund,
          occurredAt: at,
        ));
    await settle();
  }

  Future<void> fixed(List<(String, double)> items) async {
    await c.read(fixedExpenseRepoProvider).replaceAll(items);
    await settle();
  }

  group('daily limit', () {
    test('positive: no spending yet → whole budget over the days left', () async {
      await start();
      final b = budget();
      expect(b.daysRemaining, 21);
      expect(b.spendable, 30000);
      expect(b.baseDailyLimit, 1000);
      expect(b.dailyLimit, closeTo(30000 / 21, 0.001), reason: 'rollover on: unused days roll forward');
      expect(b.safeToSpend, closeTo(30000 / 21, 0.001));
      expect(b.progress, 0);
    });

    test('positive: fixed expenses come off first (rent + EMI)', () async {
      await start();
      await fixed([('Rent', 9000), ('EMI', 3000)]);
      expect(c.read(fixedTotalProvider), 12000);
      expect(budget().spendable, 18000);
      expect(budget().dailyLimit, closeTo(18000 / 21, 0.001));
    });

    test('positive: earlier spending lowers today, today\'s spending does not move it', () async {
      await start();
      await fixed([('Rent', 9000), ('EMI', 3000)]);
      await spend(2000, DateTime(2026, 11, 5, 10));
      final limit = (18000 - 2000) / 21;
      expect(budget().dailyLimit, closeTo(limit, 0.001));

      await spend(500, DateTime(2026, 11, 10, 9));
      final b = budget();
      expect(b.dailyLimit, closeTo(limit, 0.001), reason: 'fixed for the day');
      expect(b.spentToday, 500);
      expect(b.remainingToday, closeTo(limit - 500, 0.001));
      expect(b.safeToSpend, closeTo(limit - 500, 0.001));
      expect(b.progress, closeTo(500 / limit, 0.0001));
      expect(b.isOverLimit, isFalse);
      expect(b.monthRemaining, 18000 - 2500);
    });

    test('negative: going over → over-limit, safe to spend 0, remaining negative', () async {
      await start();
      await fixed([('Rent', 9000), ('EMI', 3000)]);
      await spend(2000, DateTime(2026, 11, 5));
      await spend(500, DateTime(2026, 11, 10, 9));
      await spend(400, DateTime(2026, 11, 10, 11));
      final b = budget();
      final limit = 16000 / 21;
      expect(b.spentToday, 900);
      expect(b.isOverLimit, isTrue);
      expect(b.remainingToday, closeTo(limit - 900, 0.001));
      expect(b.remainingToday, isNegative);
      expect(b.safeToSpend, 0);
      expect(b.progress, greaterThan(1));
    });

    test('reduction: a refund today brings it back under the limit', () async {
      await start();
      await fixed([('Rent', 9000), ('EMI', 3000)]);
      await spend(2000, DateTime(2026, 11, 5));
      await spend(900, DateTime(2026, 11, 10, 9));
      expect(budget().isOverLimit, isTrue);
      await refund(300, DateTime(2026, 11, 10, 10));
      final b = budget();
      expect(b.spentToday, 600);
      expect(b.isOverLimit, isFalse);
      expect(b.monthRemaining, 18000 - 2600);
    });

    test('reduction: a refund larger than today never makes spending negative', () async {
      await start();
      await spend(100, DateTime(2026, 11, 10, 9));
      await refund(500, DateTime(2026, 11, 10, 10));
      expect(budget().spentToday, 0);
      expect(budget().progress, 0);
    });

    test('rollover off: limit never above the even split, still absorbs overspend', () async {
      await start(setUpUser.copyWith(rollover: false));
      expect(budget().dailyLimit, 1000, reason: 'min(30000/30, 30000/21)');
      await spend(15000, DateTime(2026, 11, 3));
      expect(budget().dailyLimit, closeTo(15000 / 21, 0.001));
    });

    test('negative: fixed costs bigger than the budget → limit 0, month in minus', () async {
      await start();
      await fixed([('Rent', 35000)]);
      final b = budget();
      expect(b.spendable, -5000);
      expect(b.dailyLimit, 0);
      expect(b.safeToSpend, 0);
      expect(b.monthRemaining, -5000);
    });

    test('negative: whole month already spent → limit 0 for the rest', () async {
      await start();
      await spend(30000, DateTime(2026, 11, 2));
      expect(budget().dailyLimit, 0);
      await spend(10, DateTime(2026, 11, 10, 9));
      expect(budget().isOverLimit, isTrue);
    });

    test('spending outside this budget period is ignored', () async {
      await start();
      await spend(5000, DateTime(2026, 10, 31, 23, 59));
      await spend(5000, DateTime(2026, 12, 1));
      expect(budget().spentInCycle, 0);
    });
  });

  group('calendar (cycle days)', () {
    test('past days keep their own limit; future days share what is left', () async {
      await start();
      await fixed([('Rent', 9000), ('EMI', 3000)]);
      await spend(2000, DateTime(2026, 11, 5, 10));
      await spend(600, DateTime(2026, 11, 10, 9));
      final days = c.read(cycleDaysProvider);
      expect(days, hasLength(30));

      final nov5 = days[4];
      expect(nov5.spent, 2000);
      expect(nov5.limit, closeTo(18000 / 26, 0.001));
      expect(nov5.isOver, isTrue);

      final today = days[9];
      expect(today.isFuture, isFalse);
      expect(today.spent, 600);

      final future = days.skip(10);
      expect(future.every((d) => d.isFuture && d.spent == 0), isTrue);
      expect(future.first.limit, closeTo((18000 - 2600) / 20, 0.001));
      expect(future.map((d) => d.limit).toSet(), hasLength(1), reason: 'same projected limit');
    });
  });

  group('categories', () {
    test('pie = today only; categories screen = whole period, refunds netted', () async {
      await start();
      final cats = await c.read(categoriesProvider.future);
      final food = cats.firstWhere((x) => x.name == 'Food').id;
      final travel = cats.firstWhere((x) => x.name == 'Travel').id;
      await spend(400, DateTime(2026, 11, 9, 20), cat: food); // yesterday
      await spend(120, DateTime(2026, 11, 10, 9), cat: food);
      await spend(300, DateTime(2026, 11, 10, 13), cat: travel);

      expect(c.read(todayCategorySpendProvider), {food: 120, travel: 300});
      expect(c.read(categorySpendProvider), {food: 520, travel: 300});
    });
  });

  group('input safety (repositories)', () {
    test('negative: zero, negative, NaN and infinite amounts are refused', () async {
      await start();
      final repo = c.read(transactionRepoProvider);
      for (final bad in [0.0, -50.0, double.nan, double.infinity]) {
        expect(() => repo.addManual(amount: bad, categoryId: null), throwsArgumentError, reason: '$bad');
      }
      expect(await repo.all(), isEmpty);
    });

    test('negative: a bad fixed expense is refused and the old list is kept', () async {
      await start();
      await fixed([('Rent', 9000)]);
      final repo = c.read(fixedExpenseRepoProvider);
      expect(() => repo.replaceAll([('Rent', 9000), ('Bad', -1)]), throwsArgumentError);
      expect(() => repo.replaceAll([('  ', 100)]), throwsArgumentError);
      await settle();
      expect(c.read(fixedTotalProvider), 9000);
    });
  });

  group('reset data', () {
    test('wipes PocketPlan, keeps DoList, theme and currency', () async {
      await start(setUpUser.copyWith(themeMode: ThemeMode.dark, currencyCode: 'USD'));
      await fixed([('Rent', 9000)]);
      await spend(250, DateTime(2026, 11, 10, 9));
      final cats = c.read(categoryRepoProvider);
      await cats.add(name: 'Pets', icon: 'other', color: 0xFF000000);
      await c.read(todoRepoProvider).add(title: 'Keep me', start: now);

      await c.read(resetPocketPlanProvider)();
      await settle();

      expect(await c.read(transactionRepoProvider).all(), isEmpty);
      expect(c.read(fixedTotalProvider), 0);
      final names = (await c.read(categoriesProvider.future)).map((x) => x.name);
      expect(names, ['Food', 'Travel', 'Bills', 'Shopping', 'Other'], reason: 'back to defaults');
      expect((await c.read(todoRepoProvider).listNotEnded(now)).single.title, 'Keep me');

      final s = c.read(settingsProvider);
      expect(s.setupDone, isFalse, reason: 'goes back to budget setup');
      expect(s.monthlyBudget, 0);
      expect(s.onboardingSeen, isTrue);
      expect(s.themeMode, ThemeMode.dark);
      expect(s.currencyCode, 'USD');
    });
  });
}

/// Lets Drift's watch streams deliver after a write.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
