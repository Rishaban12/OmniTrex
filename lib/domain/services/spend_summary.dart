import 'daily_limit_calculator.dart' show dateOnly;

/// One spend line for summaries: category (null = uncategorised), when, and
/// a signed amount (expenses positive, refunds negative).
typedef CategorySpend = ({int? categoryId, DateTime at, double amount});

/// Pure totals used by the charts and the categories screen.
class SpendSummary {
  const SpendSummary._();

  /// Net spend per category. With [day], only that calendar day counts.
  static Map<int?, double> byCategory(Iterable<CategorySpend> entries, {DateTime? day}) {
    final only = day == null ? null : dateOnly(day);
    final out = <int?, double>{};
    for (final e in entries) {
      if (only != null && dateOnly(e.at) != only) continue;
      out[e.categoryId] = (out[e.categoryId] ?? 0) + e.amount;
    }
    return out;
  }

  /// Sum of the fixed monthly costs (rent, EMI…).
  static double fixedTotal(Iterable<double> amounts) => amounts.fold(0.0, (s, a) => s + a);
}
