import 'daily_limit_calculator.dart';

/// When the next 6 AM "Today's limit" notification fires, and the budget it
/// should announce. Pure: tests drive it with any [now].
class MorningLimit {
  const MorningLimit._();

  static const hour = 6;

  /// Next 6:00 AM strictly after [now] (today if it's still early, else tomorrow).
  static DateTime nextFireTime(DateTime now) {
    final today = DateTime(now.year, now.month, now.day, hour);
    return today.isAfter(now) ? today : DateTime(now.year, now.month, now.day + 1, hour);
  }

  /// How many mornings are booked ahead, so the reminder keeps coming even
  /// if the app isn't opened for a few days.
  static const daysAhead = 7;

  /// The next [count] 6 AM times after [now], one per day.
  static List<DateTime> upcoming(DateTime now, {int count = daysAhead}) {
    final first = nextFireTime(now);
    return [for (var i = 0; i < count; i++) DateTime(first.year, first.month, first.day + i, hour)];
  }

  /// The budget as it will stand at [fireAt], counting every expense known
  /// so far. [cycleFor] picks the budget period for a date (it may be a new
  /// one tomorrow, in which case earlier spending no longer counts).
  static DailyBudget budgetAt({
    required DateTime fireAt,
    required double monthlyBudget,
    required double fixedExpenses,
    required bool rollover,
    required BudgetCycle Function(DateTime) cycleFor,
    required Iterable<SpendEntry> entries,
  }) =>
      DailyLimitCalculator.fromEntries(
        monthlyBudget: monthlyBudget,
        fixedExpenses: fixedExpenses,
        cycle: cycleFor(fireAt),
        now: fireAt,
        entries: entries,
        rollover: rollover,
      );
}
