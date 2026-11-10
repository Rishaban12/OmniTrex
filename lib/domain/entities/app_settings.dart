import 'package:flutter/material.dart';

import '../services/daily_limit_calculator.dart';

class Currency {
  const Currency(this.code, this.symbol, this.locale);
  final String code;
  final String symbol;
  final String locale;

  static const all = [
    Currency('INR', '₹', 'en_IN'),
    Currency('USD', '\$', 'en_US'),
    Currency('EUR', '€', 'en_US'),
    Currency('GBP', '£', 'en_GB'),
    Currency('JPY', '¥', 'en_US'),
    Currency('AED', 'AED ', 'en_US'),
    Currency('SGD', 'S\$', 'en_US'),
  ];

  static Currency byCode(String code) =>
      all.firstWhere((c) => c.code == code, orElse: () => all.first);
}

class AppSettings {
  const AppSettings({
    this.onboardingSeen = false,
    this.setupDone = false,
    this.monthlyBudget = 0,
    this.cycleStartDay = 1,
    this.periodStart,
    this.periodEnd,
    this.rollover = true,
    this.currencyCode = 'INR',
    this.themeMode = ThemeMode.light,
    this.reminderEnabled = false,
    this.reminderMinutes = 21 * 60,
    this.overLimitAlert = true,
    this.autoTrackingEnabled = false,
    this.morningLimit = true,
    this.weeklyInsight = true,
  });

  final bool onboardingSeen;
  final bool setupDone;
  final double monthlyBudget;

  /// Fallback when no explicit period is set (older installs).
  final int cycleStartDay;

  /// Budget period chosen in setup: start and end, both inclusive.
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final bool rollover;
  final String currencyCode;
  final ThemeMode themeMode;
  final bool reminderEnabled;

  /// Minutes after midnight.
  final int reminderMinutes;
  final bool overLimitAlert;
  final bool autoTrackingEnabled;

  /// 6 AM "Today's limit is …" notification.
  final bool morningLimit;

  /// Sunday 7 PM "which category was high this week" check.
  final bool weeklyInsight;

  Currency get currency => Currency.byCode(currencyCode);
  TimeOfDay get reminderTime =>
      TimeOfDay(hour: reminderMinutes ~/ 60, minute: reminderMinutes % 60);

  /// The budget period containing [date].
  BudgetCycle cycleFor(DateTime date) => periodStart != null && periodEnd != null
      ? BudgetCycle.repeating(periodStart!, periodEnd!, date)
      : BudgetCycle.containing(date, cycleStartDay);

  AppSettings copyWith({
    bool? onboardingSeen,
    bool? setupDone,
    double? monthlyBudget,
    int? cycleStartDay,
    DateTime? periodStart,
    DateTime? periodEnd,
    bool? rollover,
    String? currencyCode,
    ThemeMode? themeMode,
    bool? reminderEnabled,
    int? reminderMinutes,
    bool? overLimitAlert,
    bool? autoTrackingEnabled,
    bool? morningLimit,
    bool? weeklyInsight,
  }) =>
      AppSettings(
        weeklyInsight: weeklyInsight ?? this.weeklyInsight,
        morningLimit: morningLimit ?? this.morningLimit,
        onboardingSeen: onboardingSeen ?? this.onboardingSeen,
        setupDone: setupDone ?? this.setupDone,
        monthlyBudget: monthlyBudget ?? this.monthlyBudget,
        cycleStartDay: cycleStartDay ?? this.cycleStartDay,
        periodStart: periodStart ?? this.periodStart,
        periodEnd: periodEnd ?? this.periodEnd,
        rollover: rollover ?? this.rollover,
        currencyCode: currencyCode ?? this.currencyCode,
        themeMode: themeMode ?? this.themeMode,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        reminderMinutes: reminderMinutes ?? this.reminderMinutes,
        overLimitAlert: overLimitAlert ?? this.overLimitAlert,
        autoTrackingEnabled: autoTrackingEnabled ?? this.autoTrackingEnabled,
      );

  Map<String, Object> toJson() => {
        'onboardingSeen': onboardingSeen,
        'setupDone': setupDone,
        'monthlyBudget': monthlyBudget,
        'cycleStartDay': cycleStartDay,
        if (periodStart != null) 'periodStart': _day(periodStart!),
        if (periodEnd != null) 'periodEnd': _day(periodEnd!),
        'rollover': rollover,
        'currencyCode': currencyCode,
        'themeMode': themeMode.name,
        'reminderEnabled': reminderEnabled,
        'reminderMinutes': reminderMinutes,
        'overLimitAlert': overLimitAlert,
        'autoTrackingEnabled': autoTrackingEnabled,
        'morningLimit': morningLimit,
        'weeklyInsight': weeklyInsight,
      };

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        onboardingSeen: j['onboardingSeen'] as bool? ?? (j['setupDone'] as bool? ?? false),
        setupDone: j['setupDone'] as bool? ?? false,
        monthlyBudget: (j['monthlyBudget'] as num?)?.toDouble() ?? 0,
        cycleStartDay: j['cycleStartDay'] as int? ?? 1,
        periodStart: DateTime.tryParse(j['periodStart'] as String? ?? ''),
        periodEnd: DateTime.tryParse(j['periodEnd'] as String? ?? ''),
        rollover: j['rollover'] as bool? ?? true,
        currencyCode: j['currencyCode'] as String? ?? 'INR',
        // Light unless the user explicitly picked dark.
        themeMode: j['themeMode'] == ThemeMode.dark.name ? ThemeMode.dark : ThemeMode.light,
        reminderEnabled: j['reminderEnabled'] as bool? ?? false,
        reminderMinutes: j['reminderMinutes'] as int? ?? 21 * 60,
        overLimitAlert: j['overLimitAlert'] as bool? ?? true,
        autoTrackingEnabled: j['autoTrackingEnabled'] as bool? ?? false,
        morningLimit: j['morningLimit'] as bool? ?? true,
        weeklyInsight: j['weeklyInsight'] as bool? ?? true,
      );
}
