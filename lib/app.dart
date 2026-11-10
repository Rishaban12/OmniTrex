import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/services/over_limit_alert.dart';
import 'presentation/common.dart';
import 'presentation/providers.dart';
import 'presentation/screens/add_expense_sheet.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/hub_screen.dart';
import 'presentation/screens/insights_screen.dart';
import 'presentation/screens/review_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/theme.dart';

/// Widest the app content gets on large screens.
const maxContentWidth = 720.0;

/// Lets app-level listeners show popups without a screen's context.
final rootNavigatorKey = GlobalKey<NavigatorState>();

class DailyBudgetApp extends ConsumerWidget {
  const DailyBudgetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final onboardingSeen = ref.watch(settingsProvider.select((s) => s.onboardingSeen));
    // DoList housekeeping: on launch and whenever the date rolls over, drop
    // yesterday's / last week's / last month's to-dos.
    ref.watch(todoHousekeepingProvider);
    // 6 AM "Today's limit" notification, kept up to date.
    ref.watch(morningLimitNotificationProvider);
    // Sunday 7 PM "Travel is high this week" check, kept up to date.
    ref.watch(weeklyInsightNotificationProvider);
    // DoList home-screen widget, kept up to date.
    ref.watch(todoWidgetUpdaterProvider);
    // Notes struck out on the widget → saved in the app.
    ref.watch(widgetTogglesProvider);
    // Over-limit alert from anywhere in the app (manual or SMS expense):
    // phone notification once per day + an in-app popup.
    ref.listen(dailyBudgetProvider, (prev, next) async {
      final store = ref.read(settingsStoreProvider);
      final now = DateTime.now();
      final b = next.value;
      // Back under the limit → the next crossing alerts again.
      if (OverLimitAlert.shouldRearm(current: b, lastAlertDay: store.lastOverLimitAlert, now: now)) {
        await store.clearLastOverLimitAlert();
        return;
      }
      if (b == null ||
          !OverLimitAlert.shouldAlert(
            previous: prev?.value,
            current: b,
            enabled: ref.read(settingsProvider).overLimitAlert,
            lastAlertDay: store.lastOverLimitAlert,
            now: now,
          )) {
        return;
      }
      await store.setLastOverLimitAlert(OverLimitAlert.dayKey(now));
      final msg = OverLimitAlert.message(b, ref.read(moneyProvider).call);
      await ref.read(notificationServiceProvider).showOverLimit(msg);
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) showSnack(ctx, 'Over today\'s limit — $msg', icon: Icons.warning_rounded);
    });
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'OmniTrex',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      // Phones use the full width; tablets/desktop get a centred column so
      // lines and tiles keep phone-like proportions.
      builder: (context, child) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: child,
          ),
        ),
      ),
      home: _LaunchGate(
        next: onboardingSeen ? const HubScreen() : const OnboardingScreen(),
      ),
    );
  }
}

/// Plays the splash animation once per launch, then fades to [next].
/// While the animation runs, it warms up what PocketPlan and DoList need, so
/// opening either is instant instead of waiting on the database/images.
class _LaunchGate extends ConsumerStatefulWidget {
  const _LaunchGate({required this.next});
  final Widget next;

  @override
  ConsumerState<_LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends ConsumerState<_LaunchGate> {
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    // Warm-up waits until the logo has finished sliding (~1.3 s) so it can't
    // make the animation stutter, and still finishes before the splash ends.
    Future.delayed(const Duration(milliseconds: 1300), _warmUp);
  }

  void _warmUp() {
    if (!mounted) return;
    // Start the (non-auto-dispose) data streams: opens + migrates the DB and
    // loads expenses, categories, fixed costs, review queue and to-dos.
    for (final p in [
      cycleTransactionsProvider,
      categoriesProvider,
      fixedExpensesProvider,
      pendingMessagesProvider,
      activeTodosProvider,
      upcomingTodosProvider,
      weekTransactionsProvider,
    ]) {
      ref.read(p);
    }
    // Decode the hub illustrations ahead of time.
    for (final a in const [
      'lib/data/static/dailynotes.png',
      'lib/data/static/expense.png',
      'lib/data/static/MindNotes.png',
    ]) {
      precacheImage(AssetImage(a), context);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        child: _splashDone
            ? KeyedSubtree(key: const ValueKey('next'), child: widget.next)
            : SplashScreen(
                key: const ValueKey('splash'),
                onDone: () => setState(() => _splashDone = true),
              ),
      );
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final bridge = ref.read(autoTrackingBridgeProvider);
    bridge.onMessagesAvailable = _drain;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _drain();
      if (await bridge.takeLaunchAction() == 'quick_add' && mounted) {
        showAddExpenseSheet(context);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(clockProvider);
      _drain();
    }
  }

  void _drain() {
    if (ref.read(settingsProvider).autoTrackingEnabled) {
      ref.read(autoTrackingServiceProvider).drainFromDevice();
    }
  }

  @override
  Widget build(BuildContext context) {
    // (Over-limit alert lives in DailyBudgetApp so it works on every screen.)
    final pendingCount = ref.watch(pendingMessagesProvider).value?.length ?? 0;
    void toToday() => setState(() => _tab = 0);
    // Back (app bar arrow or phone button) on Insights / Parser / Settings
    // returns to Today; only Today's back leaves PocketPlan.
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) toToday();
      },
      child: Scaffold(
      body: IndexedStack(index: _tab, children: [
        HomeScreen(onOpenReview: () => setState(() => _tab = 2)),
        InsightsScreen(onBack: toToday),
        ReviewScreen(onBack: toToday),
        SettingsScreen(onBack: toToday),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          const NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Insights'),
          NavigationDestination(
            icon: Badge(isLabelVisible: pendingCount > 0, label: Text('$pendingCount'),
                child: const Icon(Icons.inbox_outlined)),
            selectedIcon: const Icon(Icons.inbox),
            label: 'Parser',
          ),
          const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
      ),
    );
  }
}
