import 'dart:math' as math;

/// Strips the time component, keeping the local calendar day.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Whole calendar days between two dates, immune to DST shifts.
int calendarDaysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

/// A budget period: [start] inclusive, [end] exclusive.
class BudgetCycle {
  const BudgetCycle(this.start, this.end);

  final DateTime start;
  final DateTime end;

  /// The cycle containing [date] for a cycle that begins on [startDay] of each
  /// month. A start day beyond a month's length (e.g. 31 in February) clamps
  /// to that month's last day.
  factory BudgetCycle.containing(DateTime date, int startDay) {
    assert(startDay >= 1 && startDay <= 31);
    final day = dateOnly(date);
    DateTime startIn(int year, int month) {
      final normalized = DateTime(year, month, 1);
      return DateTime(normalized.year, normalized.month,
          math.min(startDay, daysInMonth(normalized.year, normalized.month)));
    }

    var start = startIn(day.year, day.month);
    if (day.isBefore(start)) start = startIn(day.year, day.month - 1);
    final end = startIn(start.year, start.month + 1);
    return BudgetCycle(start, end);
  }

  /// The period containing [date], for a budget the user set from [start] to
  /// [endInclusive]. A whole-month span (e.g. 18 Oct – 17 Nov) repeats
  /// monthly on the same day; any other span repeats with the same length.
  factory BudgetCycle.repeating(DateTime start, DateTime endInclusive, DateTime date) {
    final s = dateOnly(start);
    final e = dateOnly(endInclusive);
    final monthly = BudgetCycle.containing(s, s.day);
    if (monthly.start == s && DateTime(e.year, e.month, e.day + 1) == monthly.end) {
      return BudgetCycle.containing(date, s.day);
    }
    final length = math.max(1, calendarDaysBetween(s, e) + 1);
    final k = (calendarDaysBetween(s, dateOnly(date)) / length).floor();
    final from = DateTime(s.year, s.month, s.day + k * length);
    return BudgetCycle(from, DateTime(from.year, from.month, from.day + length));
  }

  int get totalDays => calendarDaysBetween(start, end);

  /// Days left including [day] itself (always at least 1).
  int daysRemainingFrom(DateTime day) =>
      calendarDaysBetween(dateOnly(day), end).clamp(1, totalDays);

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}

/// A signed spend entry: expenses are positive, refunds negative.
class SpendEntry {
  const SpendEntry(this.at, this.amount);
  final DateTime at;
  final double amount;
}

/// Everything the home screen needs for "today".
class DailyBudget {
  const DailyBudget({
    required this.cycle,
    required this.spendable,
    required this.baseDailyLimit,
    required this.dailyLimit,
    required this.spentToday,
    required this.spentBeforeToday,
    required this.daysRemaining,
  });

  final BudgetCycle cycle;

  /// Monthly budget minus fixed expenses.
  final double spendable;

  /// Even split of [spendable] across the whole cycle.
  final double baseDailyLimit;

  /// Today's allowance. Fixed for the day: it only depends on spending
  /// before today, so the ring doesn't shift as you spend.
  final double dailyLimit;
  final double spentToday;
  final double spentBeforeToday;
  final int daysRemaining;

  double get spentInCycle => spentBeforeToday + spentToday;
  double get remainingToday => dailyLimit - spentToday;
  double get monthRemaining => spendable - spentInCycle;
  bool get isOverLimit => spentToday > dailyLimit + 0.005;

  /// What can be spent today without breaking the day or the month.
  double get safeToSpend =>
      math.max(0, math.min(remainingToday, monthRemaining)).toDouble();

  /// 0..1+ fill for the progress ring.
  double get progress {
    if (dailyLimit <= 0) return spentToday > 0 ? 1 : 0;
    return spentToday / dailyLimit;
  }
}

/// One calendar day in a cycle: what the limit was (or will be) and what
/// was spent.
class DayLimit {
  const DayLimit(this.day, this.limit, this.spent, {required this.isFuture});
  final DateTime day;
  final double limit;
  final double spent;
  final bool isFuture;

  bool get isOver => !isFuture && spent > limit + 0.005;
}

class DailyLimitCalculator {
  const DailyLimitCalculator._();

  /// Limit and spend for every day of [cycle].
  ///
  /// Past days and today use the limit that applied on that day (based on
  /// spending before it). Future days get the projected limit: what's left
  /// after today split evenly over the remaining days.
  static List<DayLimit> cycleDays({
    required double monthlyBudget,
    required double fixedExpenses,
    required BudgetCycle cycle,
    required DateTime today,
    required Iterable<SpendEntry> entries,
    required bool rollover,
  }) {
    final todayDate = dateOnly(today);
    final perDay = <DateTime, double>{};
    for (final e in entries) {
      if (!cycle.contains(e.at)) continue;
      final d = dateOnly(e.at);
      perDay[d] = (perDay[d] ?? 0) + e.amount;
    }

    DailyBudget on(DateTime day, double before, double spent) => calculate(
          monthlyBudget: monthlyBudget,
          fixedExpenses: fixedExpenses,
          cycle: cycle,
          today: day,
          spentBeforeToday: before,
          spentToday: spent,
          rollover: rollover,
        );

    final out = <DayLimit>[];
    var before = 0.0;
    double? futureLimit;
    for (var d = cycle.start; d.isBefore(cycle.end); d = DateTime(d.year, d.month, d.day + 1)) {
      if (d.isAfter(todayDate)) {
        futureLimit ??= on(d, before, 0).dailyLimit;
        out.add(DayLimit(d, futureLimit, 0, isFuture: true));
      } else {
        final spent = perDay[d] ?? 0;
        out.add(DayLimit(d, on(d, before, spent).dailyLimit, spent, isFuture: false));
        before += spent;
      }
    }
    return out;
  }

  /// Daily limit = (budget − fixed − spent before today) ÷ remaining days.
  ///
  /// With [rollover] on, unused money from previous days raises future limits.
  /// With it off, the limit never exceeds the even daily split, but overspending
  /// still lowers it so the month total stays within budget.
  static DailyBudget calculate({
    required double monthlyBudget,
    required double fixedExpenses,
    required BudgetCycle cycle,
    required DateTime today,
    required double spentBeforeToday,
    required double spentToday,
    required bool rollover,
  }) {
    final spendable = monthlyBudget - fixedExpenses;
    final daysRemaining = cycle.daysRemainingFrom(today);
    final baseDaily = cycle.totalDays == 0 ? 0.0 : spendable / cycle.totalDays;
    final rolling = (spendable - spentBeforeToday) / daysRemaining;
    final limit = rollover ? rolling : math.min(baseDaily, rolling);

    return DailyBudget(
      cycle: cycle,
      spendable: spendable,
      baseDailyLimit: math.max(0, baseDaily).toDouble(),
      dailyLimit: math.max(0, limit).toDouble(),
      spentToday: math.max(0, spentToday).toDouble(),
      spentBeforeToday: math.max(0, spentBeforeToday).toDouble(),
      daysRemaining: daysRemaining,
    );
  }

  /// Splits [entries] into before-today / today totals for the cycle.
  static DailyBudget fromEntries({
    required double monthlyBudget,
    required double fixedExpenses,
    required BudgetCycle cycle,
    required DateTime now,
    required Iterable<SpendEntry> entries,
    required bool rollover,
  }) {
    final today = dateOnly(now);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    var before = 0.0, todaySpent = 0.0;
    for (final e in entries) {
      if (!cycle.contains(e.at)) continue;
      if (e.at.isBefore(today)) {
        before += e.amount;
      } else if (e.at.isBefore(tomorrow)) {
        todaySpent += e.amount;
      }
    }
    return calculate(
      monthlyBudget: monthlyBudget,
      fixedExpenses: fixedExpenses,
      cycle: cycle,
      today: today,
      spentBeforeToday: before,
      spentToday: todaySpent,
      rollover: rollover,
    );
  }
}
