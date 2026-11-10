import 'daily_limit_calculator.dart';

/// Decides when the "over today's limit" alert fires: on each change from
/// under → over (when switched on). Once fired it stays quiet while you are
/// still over (even across app restarts); dropping back under re-arms it.
class OverLimitAlert {
  /// True when the alert should be re-armed: today's spending is back
  /// within the limit after an alert today.
  static bool shouldRearm({required DailyBudget? current, required String? lastAlertDay, required DateTime now}) =>
      current != null && !current.isOverLimit && lastAlertDay == dayKey(now);

  const OverLimitAlert._();

  /// "2026-11-10": the key stored after an alert so it isn't repeated.
  static String dayKey(DateTime now) => dateOnly(now).toIso8601String().substring(0, 10);

  static bool shouldAlert({
    required DailyBudget? previous,
    required DailyBudget? current,
    required bool enabled,
    required String? lastAlertDay,
    required DateTime now,
  }) {
    if (!enabled || current == null || !current.isOverLimit) return false;
    if (previous?.isOverLimit ?? false) return false; // already over before this change
    return lastAlertDay != dayKey(now);
  }

  static String message(DailyBudget b, String Function(double) money) =>
      'Spent ${money(b.spentToday)} of ${money(b.dailyLimit)} today.';
}
