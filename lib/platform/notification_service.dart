import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local notifications only (daily reminder, over-limit alert). No-op on web.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _channel = AndroidNotificationDetails(
    'budget_alerts', 'Budget alerts',
    channelDescription: 'Daily reminders and over-limit alerts',
    importance: Importance.high,
    priority: Priority.high,
    // Phone's default notification sound + vibration.
    playSound: true,
    enableVibration: true,
  );

  Future<void> init() async {
    if (!isSupported || _ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  }

  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    await init();
    return await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission() ??
        false;
  }

  Future<void> showOverLimit(String body) async {
    if (!isSupported) return;
    await init();
    await _plugin.show(1, 'Daily limit exceeded', body,
        const NotificationDetails(android: _channel));
  }

  /// Removes the old repeating evening "Log today's spending" reminder (id 2)
  /// on phones that had it switched on before it was retired.
  Future<void> cancelLegacyEveningReminder() async {
    if (isSupported) await _plugin.cancel(2);
  }

  /// Whether Android lets the app show notifications (null when unknown /
  /// not on Android).
  Future<bool?> areEnabled() async {
    if (!isSupported) return null;
    await init();
    return _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();
  }

  /// Settings → "Send a test notification".
  Future<void> showTest() async {
    if (!isSupported) return;
    await init();
    await _plugin.show(9, 'OmniTrex notifications work', 'You\'ll hear this sound for budget alerts.',
        const NotificationDetails(android: _channel));
  }

  /// Old single-slot id (before the reminder was booked days ahead).
  static const _legacyMorningId = 3;

  /// Ids 30…36: one per booked morning.
  static int _morningSlot(int i) => 30 + i;

  /// Books the "Today's limit" reminders, one per morning in [items] (the
  /// next few days). Replaces whatever was booked before, so the numbers
  /// stay current every time spending changes.
  Future<void> scheduleMorningLimits(List<({DateTime at, String title, String body})> items) async {
    if (!isSupported) return;
    await init();
    await cancelMorningLimit();
    for (final (i, n) in items.indexed) {
      await _plugin.zonedSchedule(
        _morningSlot(i),
        n.title,
        n.body,
        tz.TZDateTime.from(n.at, tz.UTC),
        const NotificationDetails(android: _channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> cancelMorningLimit() async {
    if (!isSupported) return;
    await _plugin.cancel(_legacyMorningId);
    for (var i = 0; i < 10; i++) {
      await _plugin.cancel(_morningSlot(i));
    }
  }

  static const _weeklyId = 4;

  /// One-shot Sunday-evening "Travel is high this week" check; re-scheduled
  /// by the app whenever spending changes.
  Future<void> scheduleWeeklyInsight(DateTime at, String title, String body) async {
    if (!isSupported) return;
    await init();
    await _plugin.cancel(_weeklyId);
    await _plugin.zonedSchedule(
      _weeklyId,
      title,
      body,
      tz.TZDateTime.from(at, tz.UTC),
      const NotificationDetails(android: _channel),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelWeeklyInsight() async {
    if (isSupported) await _plugin.cancel(_weeklyId);
  }
}
