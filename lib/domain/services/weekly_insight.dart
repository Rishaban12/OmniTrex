import 'daily_limit_calculator.dart' show dateOnly;

/// One expense for the weekly analysis (refunds as negative amounts).
typedef WeekSpend = ({int? categoryId, DateTime at, double amount});

class HighCategory {
  const HighCategory(this.categoryId, this.thisWeek, this.usual);
  final int? categoryId;
  final double thisWeek;

  /// Average of the previous weeks; 0 when there's no history yet.
  final double usual;
}

class WeeklyInsightResult {
  const WeeklyInsightResult(this.weekStart, this.total, this.high);
  final DateTime weekStart;
  final double total;

  /// Highest excess first.
  final List<HighCategory> high;
}

/// Finds categories that are unusually high in the Monday–Sunday week.
/// Pure: drive with any data / dates in tests.
class WeeklyInsight {
  const WeeklyInsight._();

  static const lookbackWeeks = 4;

  /// "High" = ≥ 30% above the usual weekly amount (average of the previous
  /// [lookbackWeeks] weeks), or — with no history — ≥ 40% of this week's
  /// spending. Amounts under [minAmount] are ignored.
  static const aboveUsual = 1.3;
  static const shareWithoutHistory = 0.4;
  static const minAmount = 100.0;

  static DateTime mondayOf(DateTime d) {
    final day = dateOnly(d);
    return DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));
  }

  /// Next Sunday 7 PM strictly after [now] (this Sunday if still before 7 PM).
  static DateTime nextFireTime(DateTime now) {
    final sunday = DateTime(now.year, now.month, now.day + (DateTime.sunday - now.weekday), 19);
    return sunday.isAfter(now) ? sunday : DateTime(sunday.year, sunday.month, sunday.day + 7, 19);
  }

  static WeeklyInsightResult analyze({required DateTime weekStart, required Iterable<WeekSpend> entries}) {
    final start = mondayOf(weekStart);
    final end = DateTime(start.year, start.month, start.day + 7);
    final historyStart = DateTime(start.year, start.month, start.day - 7 * lookbackWeeks);

    final thisWeek = <int?, double>{};
    final history = <int?, double>{};
    for (final e in entries) {
      if (!e.at.isBefore(start) && e.at.isBefore(end)) {
        thisWeek[e.categoryId] = (thisWeek[e.categoryId] ?? 0) + e.amount;
      } else if (!e.at.isBefore(historyStart) && e.at.isBefore(start)) {
        history[e.categoryId] = (history[e.categoryId] ?? 0) + e.amount;
      }
    }
    final total = thisWeek.values.fold(0.0, (s, v) => s + v);
    final hasHistory = history.values.any((v) => v > 0);

    final high = <HighCategory>[];
    for (final MapEntry(key: id, value: spent) in thisWeek.entries) {
      if (spent < minAmount) continue;
      final usual = (history[id] ?? 0) / lookbackWeeks;
      final isHigh = hasHistory
          ? (usual > 0 ? spent >= usual * aboveUsual : spent >= total * shareWithoutHistory)
          : total > 0 && spent / total >= shareWithoutHistory;
      if (isHigh) high.add(HighCategory(id, spent, usual));
    }
    high.sort((a, b) => (b.thisWeek - b.usual).compareTo(a.thisWeek - a.usual));
    return WeeklyInsightResult(start, total, high);
  }

  /// Notification text, e.g. title "Travel is high this week",
  /// body "₹2,400 (usually ₹1,200). Food also high."
  static ({String title, String body}) message(
    WeeklyInsightResult r, {
    required String Function(int? categoryId) name,
    required String Function(double) money,
  }) {
    if (r.total <= 0) {
      return (title: 'Weekly spending check', body: 'No expenses logged this week.');
    }
    if (r.high.isEmpty) {
      return (title: 'Spending looks balanced this week 👍', body: 'Total ${money(r.total)} — no category stood out.');
    }
    final top = r.high.first;
    final usual = top.usual > 0 ? ' (usually ${money(top.usual)})' : ' — ${(top.thisWeek / r.total * 100).round()}% of your week';
    final others = r.high.skip(1).map((h) => name(h.categoryId)).toList();
    final also = others.isEmpty ? '' : ' ${others.join(', ')} ${others.length == 1 ? 'is' : 'are'} also high.';
    return (
      title: '${name(top.categoryId)} is high this week',
      body: '${money(top.thisWeek)}$usual.$also',
    );
  }
}
