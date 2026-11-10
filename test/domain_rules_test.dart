import 'package:daily_budget/domain/services/amount_input.dart';
import 'package:daily_budget/domain/services/daily_limit_calculator.dart';
import 'package:daily_budget/domain/services/over_limit_alert.dart';
import 'package:daily_budget/domain/services/spend_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AmountInput — what the user types', () {
    test('positive: plain, decimal, grouped and with a currency prefix', () {
      expect(AmountInput.parse('250'), 250);
      expect(AmountInput.parse(' 99.5 '), 99.5);
      expect(AmountInput.parse('.75'), 0.75);
      expect(AmountInput.parse('1,00,000'), 100000);
      expect(AmountInput.parse('100,000.25'), 100000.25);
      expect(AmountInput.parse('₹120'), 120);
      expect(AmountInput.parse('Rs. 45'), 45);
    });

    test('rounded to paise', () {
      expect(AmountInput.parse('10.006'), 10.01);
      expect(AmountInput.parse('10.004'), 10);
    });

    test('negative: empty, text, zero, minus, broken numbers', () {
      for (final bad in [null, '', '   ', 'abc', '12abc', '0', '0.00', '-50', '- 5', '1.2.3', '1e5', 'NaN', 'Infinity', '.']) {
        expect(AmountInput.parse(bad), isNull, reason: '"$bad"');
      }
    });

    test('negative: above the ₹10 crore cap (typo guard)', () {
      expect(AmountInput.parse('100000000'), AmountInput.max);
      expect(AmountInput.parse('100000001'), isNull);
    });

    test('require() is the repository guard', () {
      expect(AmountInput.require(1), 1);
      for (final bad in [0.0, -1.0, double.nan, double.infinity, AmountInput.max + 1]) {
        expect(() => AmountInput.require(bad), throwsArgumentError, reason: '$bad');
      }
    });
  });

  group('SpendSummary — totals', () {
    final lines = <CategorySpend>[
      (categoryId: 1, at: DateTime(2026, 11, 9, 20), amount: 400), // yesterday
      (categoryId: 1, at: DateTime(2026, 11, 10, 9), amount: 120),
      (categoryId: 2, at: DateTime(2026, 11, 10, 13), amount: 300),
      (categoryId: 2, at: DateTime(2026, 11, 10, 18), amount: -100), // refund
      (categoryId: null, at: DateTime(2026, 11, 10, 23, 59), amount: 50),
      (categoryId: 1, at: DateTime(2026, 11, 11, 0, 0), amount: 999), // tomorrow
    ];

    test('whole period: refunds net out, uncategorised kept', () {
      expect(SpendSummary.byCategory(lines), {1: 1519, 2: 200, null: 50});
    });

    test('one day only: yesterday and tomorrow are excluded (Insights pie)', () {
      expect(SpendSummary.byCategory(lines, day: DateTime(2026, 11, 10, 15)), {1: 120, 2: 200, null: 50});
    });

    test('negative: a day with nothing gives an empty map', () {
      expect(SpendSummary.byCategory(lines, day: DateTime(2026, 11, 1)), isEmpty);
      expect(SpendSummary.byCategory(const []), isEmpty);
    });

    test('fixed total', () {
      expect(SpendSummary.fixedTotal([9000, 3000, 499.5]), 12499.5);
      expect(SpendSummary.fixedTotal(const []), 0);
    });
  });

  group('OverLimitAlert — when the alert fires', () {
    final nov = BudgetCycle(DateTime(2026, 11, 1), DateTime(2026, 12, 1));
    final now = DateTime(2026, 11, 10, 15);
    DailyBudget day(double spent) => DailyLimitCalculator.calculate(
          monthlyBudget: 30000,
          fixedExpenses: 0,
          cycle: nov,
          today: now,
          spentBeforeToday: 0,
          spentToday: spent,
          rollover: false,
        ); // limit 1000

    bool should({DailyBudget? prev, required DailyBudget cur, bool enabled = true, String? last}) =>
        OverLimitAlert.shouldAlert(previous: prev, current: cur, enabled: enabled, lastAlertDay: last, now: now);

    test('positive: crossing the limit alerts, with the numbers in the text', () {
      expect(should(prev: day(900), cur: day(1100)), isTrue);
      expect(should(cur: day(1100)), isTrue, reason: 'first value already over');
      expect(OverLimitAlert.message(day(1100), (v) => '₹${v.round()}'), 'Spent ₹1100 of ₹1000 today.');
    });

    test('negative: exactly at the limit, or under it, does not alert', () {
      expect(should(prev: day(0), cur: day(1000)), isFalse);
      expect(should(prev: day(0), cur: day(999.99)), isFalse);
    });

    test('negative: already over before this expense → no repeat', () {
      expect(should(prev: day(1100), cur: day(1300)), isFalse);
    });

    test('negative: switched off, or already alerted today', () {
      expect(should(prev: day(0), cur: day(1100), enabled: false), isFalse);
      expect(should(prev: day(0), cur: day(1100), last: '2026-11-10'), isFalse);
      expect(should(prev: day(0), cur: day(1100), last: '2026-11-09'), isTrue, reason: 'new day alerts again');
    });

    test('re-arm: back under the limit after today\'s alert → next crossing alerts again', () {
      expect(OverLimitAlert.shouldRearm(current: day(800), lastAlertDay: '2026-11-10', now: now), isTrue);
      expect(OverLimitAlert.shouldRearm(current: day(1100), lastAlertDay: '2026-11-10', now: now), isFalse,
          reason: 'still over: stay quiet (no repeat on app reopen)');
      expect(OverLimitAlert.shouldRearm(current: day(800), lastAlertDay: null, now: now), isFalse);
      expect(OverLimitAlert.shouldRearm(current: null, lastAlertDay: '2026-11-10', now: now), isFalse);
    });

    test('day key is the local date', () {
      expect(OverLimitAlert.dayKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    });
  });
}
