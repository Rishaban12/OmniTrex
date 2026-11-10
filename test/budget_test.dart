import 'package:daily_budget/domain/services/daily_limit_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final nov = BudgetCycle(DateTime(2026, 11, 1), DateTime(2026, 12, 1)); // 30 days

  DailyBudget calc({
    double budget = 30000,
    double fixed = 0,
    BudgetCycle? cycle,
    DateTime? today,
    double before = 0,
    double spent = 0,
    bool rollover = true,
  }) =>
      DailyLimitCalculator.calculate(
        monthlyBudget: budget,
        fixedExpenses: fixed,
        cycle: cycle ?? nov,
        today: today ?? DateTime(2026, 11, 1),
        spentBeforeToday: before,
        spentToday: spent,
        rollover: rollover,
      );

  group('positive', () {
    test('day one: even split of spendable', () {
      final b = calc(fixed: 15000);
      expect(b.spendable, 15000);
      expect(b.dailyLimit, 500);
      expect(b.daysRemaining, 30);
      expect(b.safeToSpend, 500);
    });

    test('rollover carries unused money forward', () {
      // 10 days in, only ₹2,000 spent of a ₹10,000 pace.
      final b = calc(today: DateTime(2026, 11, 11), before: 2000);
      expect(b.dailyLimit, 1400); // 28000 / 20
    });

    test('last day: limit is everything left', () {
      final b = calc(today: DateTime(2026, 11, 30), before: 29000);
      expect(b.daysRemaining, 1);
      expect(b.dailyLimit, 1000);
    });

    test('safe to spend never exceeds what is left for the month', () {
      final b = calc(today: DateTime(2026, 11, 30), before: 29900, spent: 50);
      expect(b.safeToSpend, closeTo(50, 0.001));
    });
  });

  group('negative / edge cases', () {
    test('fixed costs bigger than the budget → limit 0, month negative', () {
      final b = calc(budget: 10000, fixed: 12000);
      expect(b.spendable, -2000);
      expect(b.dailyLimit, 0);
      expect(b.safeToSpend, 0);
      expect(b.monthRemaining, -2000);
    });

    test('zero budget', () {
      final b = calc(budget: 0, spent: 10);
      expect(b.dailyLimit, 0);
      expect(b.isOverLimit, isTrue);
      expect(b.progress, 1);
    });

    test('progress is 0 with no limit and no spend (no divide-by-zero)', () {
      expect(calc(budget: 0).progress, 0);
    });

    test('overspending earlier shrinks today, never below 0', () {
      final b = calc(today: DateTime(2026, 11, 20), before: 35000);
      expect(b.dailyLimit, 0);
      expect(b.monthRemaining, -5000);
    });

    test('rollover off ignores savings but still absorbs overspend', () {
      expect(calc(today: DateTime(2026, 11, 11), before: 0, rollover: false).dailyLimit, 1000);
      expect(calc(today: DateTime(2026, 11, 11), before: 20000, rollover: false).dailyLimit, 500);
    });

    test('refund larger than today\'s spend clamps to 0', () {
      final b = DailyLimitCalculator.fromEntries(
        monthlyBudget: 3000,
        fixedExpenses: 0,
        cycle: nov,
        now: DateTime(2026, 11, 5, 12),
        entries: [SpendEntry(DateTime(2026, 11, 5, 9), 100), SpendEntry(DateTime(2026, 11, 5, 10), -300)],
        rollover: true,
      );
      expect(b.spentToday, 0);
    });

    test('entries outside the cycle are ignored', () {
      final b = DailyLimitCalculator.fromEntries(
        monthlyBudget: 3000,
        fixedExpenses: 0,
        cycle: nov,
        now: DateTime(2026, 11, 5, 12),
        entries: [SpendEntry(DateTime(2026, 10, 31, 23, 59), 999), SpendEntry(DateTime(2026, 12, 1), 999)],
        rollover: true,
      );
      expect(b.spentInCycle, 0);
    });

    test('date outside the cycle still yields at least one remaining day', () {
      expect(nov.daysRemainingFrom(DateTime(2027, 1, 1)), 1);
    });
  });

  group('cycles', () {
    test('year rollover', () {
      final c = BudgetCycle.containing(DateTime(2026, 12, 20), 15);
      expect((c.start, c.end), (DateTime(2026, 12, 15), DateTime(2027, 1, 15)));
    });

    test('leap year February with a day-30 start', () {
      final c = BudgetCycle.containing(DateTime(2028, 2, 29), 30);
      expect(c.start, DateTime(2028, 2, 29));
      expect(c.end, DateTime(2028, 3, 30));
    });

    test('one-day custom period repeats daily', () {
      final c = BudgetCycle.repeating(DateTime(2026, 11, 1), DateTime(2026, 11, 1), DateTime(2026, 11, 9));
      expect((c.start, c.totalDays), (DateTime(2026, 11, 9), 1));
    });

    test('end before start is treated as one day (no crash)', () {
      final c = BudgetCycle.repeating(DateTime(2026, 11, 10), DateTime(2026, 11, 5), DateTime(2026, 11, 10));
      expect(c.totalDays, 1);
    });
  });
}
