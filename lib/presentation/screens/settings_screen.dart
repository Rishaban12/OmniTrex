import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../domain/entities/app_settings.dart';
import '../common.dart';
import '../providers.dart';
import 'categories_screen.dart';
import 'setup_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.onBack});

  /// Back arrow action (PocketPlan: return to the Today tab).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final money = ref.watch(moneyProvider);
    final notifications = ref.read(notificationServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), leading: onBack == null ? null : BackButton(onPressed: onBack)),
      body: ListView(children: [
        const _Header('Budget'),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Monthly budget & fixed expenses'),
          subtitle: Builder(builder: (context) {
            final c = s.cycleFor(DateTime.now());
            final last = DateTime(c.end.year, c.end.month, c.end.day - 1);
            return Text('${money(s.monthlyBudget)} · '
                '${DateFormat('d MMM').format(c.start)} – ${DateFormat('d MMM').format(last)}');
          }),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SetupScreen(editing: true))),
        ),
        ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Categories'),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.redo),
          title: const Text('Roll over unused amount'),
          subtitle: const Text('Unspent money raises future daily limits'),
          value: s.rollover,
          onChanged: (v) => notifier.update((s) => s.copyWith(rollover: v)),
        ),
        // Theme moved to the "What's next?" page (top-right button).
        const _Header('Appearance'),
        ListTile(
          leading: const Icon(Icons.currency_exchange),
          title: const Text('Currency'),
          trailing: DropdownButton<String>(
            value: s.currencyCode,
            underline: const SizedBox(),
            items: [
              for (final c in Currency.all)
                DropdownMenuItem(value: c.code, child: Text('${c.symbol.trim()} ${c.code}')),
            ],
            onChanged: (v) => notifier.update((s) => s.copyWith(currencyCode: v)),
          ),
        ),
        const _Header('Notifications'),
        const _NotificationStatus(),
        SwitchListTile(
          secondary: const Icon(Icons.wb_sunny_outlined),
          title: const Text('Daily reminder'),
          subtitle: const Text('6:00 AM · "Today\'s limit is ₹…"'),
          value: s.morningLimit,
          onChanged: (v) async {
            if (v) await notifications.requestPermission();
            await notifier.update((s) => s.copyWith(morningLimit: v));
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.insights_rounded),
          title: const Text('Weekly spending check'),
          subtitle: const Text('Sunday 7:00 PM · which category was high this week'),
          value: s.weeklyInsight,
          onChanged: (v) async {
            if (v) await notifications.requestPermission();
            await notifier.update((s) => s.copyWith(weeklyInsight: v));
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.warning_amber),
          title: const Text('Over-limit alert'),
          subtitle: const Text('Notify when today\'s spending passes the limit'),
          value: s.overLimitAlert,
          onChanged: (v) async {
            if (v) await notifications.requestPermission();
            await notifier.update((s) => s.copyWith(overLimitAlert: v));
          },
        ),
        const _Header('Auto-tracking'),
        const _AutoTrackingSection(),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'All data stays on this device. Messages are parsed locally and never uploaded.',
            textAlign: TextAlign.center,
          ),
        ),
        // Reset — always the last item.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset data'),
            onPressed: () => _confirmReset(context, ref),
          ),
        ),
      ]),
    );
  }
}

Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reset data?'),
      content: const Text(
          'This deletes all expenses, fixed expenses, parser messages and your budget. '
          'DoList notes are kept. This can\'t be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: const Text('Okay'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  // Back to a fresh budget setup; DoList, theme and currency are kept.
  await ref.read(resetPocketPlanProvider)();
}

/// Shows when Android is blocking OmniTrex notifications (with a fix), and
/// a "send a test" button to check sound and delivery. Re-checks when the
/// user comes back from the phone's settings.
class _NotificationStatus extends ConsumerStatefulWidget {
  const _NotificationStatus();

  @override
  ConsumerState<_NotificationStatus> createState() => _NotificationStatusState();
}

class _NotificationStatusState extends ConsumerState<_NotificationStatus> with WidgetsBindingObserver {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final v = await ref.read(notificationServiceProvider).areEnabled();
    if (mounted) setState(() => _enabled = v);
  }

  Future<void> _turnOn() async {
    final ok = await ref.read(notificationServiceProvider).requestPermission();
    // Denied before: Android won't ask again, so open the app's settings.
    if (!ok) await openAppSettings();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(notificationServiceProvider);
    if (!service.isSupported) return const SizedBox.shrink();
    return Column(children: [
      if (_enabled == false)
        ListTile(
          leading: Icon(Icons.notifications_off_rounded, color: Colors.red.shade700),
          title: const Text('Notifications are blocked'),
          subtitle: const Text('Reminders and alerts can\'t reach you'),
          trailing: FilledButton.tonal(onPressed: _turnOn, child: const Text('Turn on')),
        ),
      ListTile(
        leading: const Icon(Icons.notifications_active_outlined),
        title: const Text('Send a test notification'),
        subtitle: const Text('Check the sound and that alerts arrive'),
        onTap: () async {
          await service.showTest();
          await _refresh();
        },
      ),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _AutoTrackingSection extends ConsumerStatefulWidget {
  const _AutoTrackingSection();

  @override
  ConsumerState<_AutoTrackingSection> createState() => _AutoTrackingSectionState();
}

class _AutoTrackingSectionState extends ConsumerState<_AutoTrackingSection>
    with WidgetsBindingObserver {
  bool _sms = false, _notif = false, _battery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Permission screens are outside the app; re-check on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final b = ref.read(autoTrackingBridgeProvider);
    final sms = await b.hasSmsPermission();
    final notif = await b.hasNotificationAccess();
    final battery = await b.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _sms = sms;
        _notif = notif;
        _battery = battery;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(autoTrackingBridgeProvider);
    final enabled = ref.watch(settingsProvider.select((s) => s.autoTrackingEnabled));
    final notifier = ref.read(settingsProvider.notifier);

    if (!bridge.isSupported) {
      return const ListTile(
        leading: Icon(Icons.phonelink_off),
        title: Text('Not available on this platform'),
        subtitle: Text('Bank SMS and UPI notifications can only be read on Android. '
            'Use manual entry, or try the parser on the Review tab.'),
      );
    }

    return Column(children: [
      SwitchListTile(
        secondary: const Icon(Icons.auto_awesome),
        title: const Text('Auto-track payments'),
        subtitle: const Text('Read bank SMS and GPay / PhonePe / Paytm notifications'),
        value: enabled,
        onChanged: (v) => notifier.update((s) => s.copyWith(autoTrackingEnabled: v)),
      ),
      if (enabled) ...[
        _PermTile(
          icon: Icons.sms_outlined,
          title: 'SMS access',
          granted: _sms,
          onFix: () async {
            final ok = await bridge.requestSmsPermission();
            if (!ok && context.mounted) {
              showSnack(context, 'SMS denied — UPI notifications and manual entry still work.');
            }
            _refresh();
          },
        ),
        _PermTile(
          icon: Icons.notifications_active_outlined,
          title: 'Notification access',
          granted: _notif,
          onFix: bridge.openNotificationAccessSettings,
        ),
        _PermTile(
          icon: Icons.battery_saver_outlined,
          title: 'Battery optimization exemption',
          subtitle: 'Keeps tracking reliable in the background',
          granted: _battery,
          onFix: bridge.requestIgnoreBatteryOptimizations,
        ),
      ],
    ]);
  }
}

class _PermTile extends StatelessWidget {
  const _PermTile(
      {required this.icon, required this.title, required this.granted, required this.onFix, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool granted;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.only(left: 32, right: 16),
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: granted
            ? const Icon(Icons.check_circle, color: Colors.green)
            : FilledButton.tonal(onPressed: onFix, child: const Text('Allow')),
      );
}
