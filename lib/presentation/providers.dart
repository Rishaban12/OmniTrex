import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/auto_tracking_service.dart';
import '../application/reset_pocketplan.dart';
import '../application/todo_widget_sync.dart';
import '../data/repositories/note_repository.dart';
import '../data/repositories/todo_repository.dart';
import '../platform/home_widget_service.dart';
import '../data/db/app_database.dart';
import '../data/repositories/budget_repositories.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/settings_store.dart';
import '../domain/entities/app_settings.dart';
import '../domain/services/daily_limit_calculator.dart';
import '../domain/services/morning_limit.dart';
import '../domain/services/spend_summary.dart';
import '../domain/services/weekly_insight.dart';
import 'common.dart' show Money;
import '../platform/auto_tracking_bridge.dart';
import '../platform/notification_service.dart';

// --- Infrastructure (overridden in main) ----------------------------------

final sharedPrefsProvider =
    Provider<SharedPreferences>((_) => throw UnimplementedError());

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final settingsStoreProvider =
    Provider((ref) => SettingsStore(ref.watch(sharedPrefsProvider)));
final transactionRepoProvider =
    Provider((ref) => TransactionRepository(ref.watch(databaseProvider)));
final categoryRepoProvider =
    Provider((ref) => CategoryRepository(ref.watch(databaseProvider)));
final fixedExpenseRepoProvider =
    Provider((ref) => FixedExpenseRepository(ref.watch(databaseProvider)));
final pendingRepoProvider =
    Provider((ref) => PendingMessageRepository(ref.watch(databaseProvider)));

final todoRepoProvider = Provider((ref) => TodoRepository(ref.watch(databaseProvider)));

// --- MindNotes --------------------------------------------------------------

final noteRepoProvider = Provider((ref) => NoteRepository(ref.watch(databaseProvider)));

/// Text in the MindNotes search box.
final noteQueryProvider = StateProvider<String>((_) => '');

/// Notes matching the search, pinned first, newest edits first.
final notesProvider = StreamProvider<List<NoteRow>>(
    (ref) => ref.watch(noteRepoProvider).watchAll(query: ref.watch(noteQueryProvider)));
final homeWidgetServiceProvider = Provider((_) => HomeWidgetService());
final todoWidgetSyncProvider = Provider((ref) {
  final sync = TodoWidgetSync(ref.watch(todoRepoProvider), ref.watch(homeWidgetServiceProvider));
  ref.onDispose(sync.dispose);
  return sync;
});

/// Picks up notes struck out on the home-screen widget: at launch and each
/// time the app comes back to the front.
final widgetTogglesProvider = Provider<void>((ref) {
  final sync = ref.watch(todoWidgetSyncProvider);
  if (!sync.isSupported) return;
  sync.applyWidgetToggles();
  final listener = AppLifecycleListener(onResume: sync.applyWidgetToggles);
  ref.onDispose(listener.dispose);
});

/// Pushes to-dos to the home-screen widget whenever they change (from any
/// screen, and after midnight clean-up).
final todoWidgetUpdaterProvider = Provider<void>((ref) {
  ref.watch(activeTodosProvider);
  ref.watch(upcomingTodosProvider);
  ref.read(todoWidgetSyncProvider).schedule(ref.watch(todayProvider));
});

/// Runs on first use and again each time the date changes: deletes to-dos
/// whose day / week / month is over.
final todoHousekeepingProvider = Provider<void>((ref) {
  ref.read(todoRepoProvider).purgeExpired(ref.watch(todayProvider));
});

/// DoList: to-dos whose start…end includes today.
final activeTodosProvider = StreamProvider<List<TodoRow>>(
    (ref) => ref.watch(todoRepoProvider).watchActive(ref.watch(todayProvider)));

/// DoList: to-dos starting after today.
final upcomingTodosProvider = StreamProvider<List<TodoRow>>(
    (ref) => ref.watch(todoRepoProvider).watchUpcoming(ref.watch(todayProvider)));

final autoTrackingBridgeProvider = Provider((_) => AutoTrackingBridge());
final notificationServiceProvider = Provider((_) => NotificationService());

final autoTrackingServiceProvider = Provider((ref) => AutoTrackingService(
      bridge: ref.watch(autoTrackingBridgeProvider),
      transactions: ref.watch(transactionRepoProvider),
      pending: ref.watch(pendingRepoProvider),
    ));

// --- Settings ---------------------------------------------------------------

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsStoreProvider).load();

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await ref.read(settingsStoreProvider).save(state);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// --- Time -------------------------------------------------------------------

/// Emits the current time every minute so "today" rolls over at midnight.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});

final todayProvider = Provider<DateTime>((ref) {
  final now = ref.watch(clockProvider).value ?? DateTime.now();
  return dateOnly(now);
});

final cycleProvider = Provider<BudgetCycle>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings.cycleFor(ref.watch(todayProvider));
});

// --- Data streams -----------------------------------------------------------

final cycleTransactionsProvider = StreamProvider<List<TxnRow>>((ref) {
  final cycle = ref.watch(cycleProvider);
  return ref.watch(transactionRepoProvider).watchBetween(cycle.start, cycle.end);
});

final todayTransactionsProvider = Provider<AsyncValue<List<TxnRow>>>((ref) {
  final today = ref.watch(todayProvider);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  return ref.watch(cycleTransactionsProvider).whenData((list) => list
      .where((t) => !t.occurredAt.isBefore(today) && t.occurredAt.isBefore(tomorrow))
      .toList());
});

/// Last 14 days (may span the previous cycle), for the charts.
final weekTransactionsProvider = StreamProvider<List<TxnRow>>((ref) {
  final today = ref.watch(todayProvider);
  return ref.watch(transactionRepoProvider).watchBetween(
      DateTime(today.year, today.month, today.day - 13),
      DateTime(today.year, today.month, today.day + 1));
});

final categoriesProvider = StreamProvider<List<CategoryRow>>(
    (ref) => ref.watch(categoryRepoProvider).watchAll());

final categoryMapProvider = Provider<Map<int, CategoryRow>>((ref) => {
      for (final c in ref.watch(categoriesProvider).value ?? const <CategoryRow>[])
        c.id: c,
    });

final fixedExpensesProvider = StreamProvider<List<FixedExpenseRow>>(
    (ref) => ref.watch(fixedExpenseRepoProvider).watchAll());

/// Sum of the fixed monthly costs: the single source for every budget number
/// (null while loading).
final fixedTotalProvider = Provider<double?>((ref) => ref
    .watch(fixedExpensesProvider)
    .whenData((list) => SpendSummary.fixedTotal(list.map((f) => f.amount)))
    .value);

/// Settings → Reset data.
final resetPocketPlanProvider = Provider(
    (ref) => ResetPocketPlan(ref.watch(databaseProvider), ref.read(settingsProvider.notifier).update));

final pendingMessagesProvider = StreamProvider<List<PendingMessageRow>>(
    (ref) => ref.watch(pendingRepoProvider).watchAll());

// --- Derived budget ---------------------------------------------------------

final dailyBudgetProvider = Provider<AsyncValue<DailyBudget>>((ref) {
  final settings = ref.watch(settingsProvider);
  final txns = ref.watch(cycleTransactionsProvider);
  final fixed = ref.watch(fixedExpensesProvider);
  final today = ref.watch(todayProvider);
  if (txns is AsyncError) return AsyncError(txns.error!, txns.stackTrace!);
  if (fixed is AsyncError) return AsyncError(fixed.error!, fixed.stackTrace!);
  if (!txns.hasValue || !fixed.hasValue) return const AsyncLoading();

  final now = DateTime.now();
  return AsyncData(DailyLimitCalculator.fromEntries(
    monthlyBudget: settings.monthlyBudget,
    fixedExpenses: ref.watch(fixedTotalProvider) ?? 0,
    cycle: ref.watch(cycleProvider),
    now: DateTime(today.year, today.month, today.day, now.hour, now.minute),
    entries: txns.value!.map((t) => t.spendEntry),
    rollover: settings.rollover,
  ));
});

/// Limit + spend for each day of the current cycle (calendar view).
final cycleDaysProvider = Provider<List<DayLimit>>((ref) {
  final settings = ref.watch(settingsProvider);
  final txns = ref.watch(cycleTransactionsProvider).value ?? const <TxnRow>[];
  return DailyLimitCalculator.cycleDays(
    monthlyBudget: settings.monthlyBudget,
    fixedExpenses: ref.watch(fixedTotalProvider) ?? 0,
    cycle: ref.watch(cycleProvider),
    today: ref.watch(todayProvider),
    entries: txns.map((t) => t.spendEntry),
    rollover: settings.rollover,
  );
});

/// Keeps the 6 AM "Today's limit is ₹…" notification scheduled with fresh
/// numbers: re-runs whenever expenses, fixed costs, settings or the date
/// change, and reschedules (or cancels) the single pending notification.
final morningLimitNotificationProvider = Provider<void>((ref) {
  final settings = ref.watch(settingsProvider);
  ref.watch(todayProvider); // also refresh after midnight
  final txns = ref.watch(cycleTransactionsProvider).value;
  final fixed = ref.watch(fixedTotalProvider);
  final notifications = ref.read(notificationServiceProvider);

  if (!settings.setupDone || !settings.morningLimit) {
    notifications.cancelMorningLimit();
    return;
  }
  if (txns == null || fixed == null) return; // still loading

  // Book the next 7 mornings, each with the limit it will have if nothing
  // else is spent, so the reminder keeps coming even if the app stays closed.
  final money = Money(settings.currencyCode);
  final entries = [for (final t in txns) t.spendEntry];
  notifications.scheduleMorningLimits([
    for (final fireAt in MorningLimit.upcoming(DateTime.now()))
      if (MorningLimit.budgetAt(
        fireAt: fireAt,
        monthlyBudget: settings.monthlyBudget,
        fixedExpenses: fixed,
        rollover: settings.rollover,
        cycleFor: settings.cycleFor,
        entries: entries,
      )
          case final b)
        (
          at: fireAt,
          title: 'Today\'s limit is ${money(b.dailyLimit)}',
          body: '${money(b.monthRemaining)} left this month · ${b.daysRemaining} days to go',
        ),
  ]);
});

/// Expenses from the start of the lookback window to the end of this week
/// (Monday–Sunday), for the weekly check.
final weeklyWindowTransactionsProvider = StreamProvider<List<TxnRow>>((ref) {
  final fire = WeeklyInsight.nextFireTime(DateTime.now());
  final monday = WeeklyInsight.mondayOf(fire);
  final from = DateTime(monday.year, monday.month, monday.day - 7 * WeeklyInsight.lookbackWeeks);
  ref.watch(todayProvider); // move the window as days pass
  return ref.watch(transactionRepoProvider).watchBetween(from, DateTime(monday.year, monday.month, monday.day + 7));
});

/// Keeps the Sunday 7 PM "Travel is high this week" notification scheduled
/// with the latest numbers (re-runs whenever expenses or categories change).
final weeklyInsightNotificationProvider = Provider<void>((ref) {
  final settings = ref.watch(settingsProvider);
  final txns = ref.watch(weeklyWindowTransactionsProvider).value;
  final cats = ref.watch(categoryMapProvider);
  final notifications = ref.read(notificationServiceProvider);

  if (!settings.setupDone || !settings.weeklyInsight) {
    notifications.cancelWeeklyInsight();
    return;
  }
  if (txns == null) return; // still loading

  final fireAt = WeeklyInsight.nextFireTime(DateTime.now());
  final result = WeeklyInsight.analyze(
    weekStart: fireAt,
    entries: _summaryLines(txns),
  );
  final money = Money(settings.currencyCode);
  final msg = WeeklyInsight.message(result,
      name: (id) => cats[id]?.name ?? 'Uncategorized', money: money.call);
  notifications.scheduleWeeklyInsight(fireAt, msg.title, msg.body);
});

List<CategorySpend> _summaryLines(List<TxnRow> txns) =>
    [for (final t in txns) (categoryId: t.categoryId, at: t.occurredAt, amount: t.signedAmount)];

/// Net spend per category id (null = uncategorized) in the current cycle.
final categorySpendProvider = Provider<Map<int?, double>>((ref) =>
    SpendSummary.byCategory(_summaryLines(ref.watch(cycleTransactionsProvider).value ?? const [])));

/// Net spend per category id for today only (Insights pie chart).
final todayCategorySpendProvider = Provider<Map<int?, double>>((ref) => SpendSummary.byCategory(
      _summaryLines(ref.watch(cycleTransactionsProvider).value ?? const []),
      day: ref.watch(todayProvider),
    ));