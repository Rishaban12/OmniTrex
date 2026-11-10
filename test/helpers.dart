import 'dart:convert';
import 'dart:io';

import 'package:daily_budget/data/db/app_database.dart';
import 'package:daily_budget/domain/entities/app_settings.dart';
import 'package:daily_budget/platform/auto_tracking_bridge.dart';
import 'package:daily_budget/platform/notification_service.dart';
import 'package:daily_budget/platform/home_widget_service.dart';
import 'package:daily_budget/presentation/providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phone-only features switched off so tests never hit platform channels.
class FakeBridge extends AutoTrackingBridge {
  @override
  bool get isSupported => false;
}

/// Records what would have been shown / scheduled instead of calling Android.
class FakeNotifications extends NotificationService {
  final overLimit = <String>[];
  /// Each call books a batch (the next few mornings).
  final morningBatches = <List<({DateTime at, String title, String body})>>[];
  int morningCancels = 0;
  int tests = 0;

  /// What Android reports for "notifications allowed".
  bool? enabled = true;

  /// The latest booked mornings, soonest first (empty if never booked).
  List<({DateTime at, String title, String body})> get morning =>
      morningBatches.isEmpty ? const [] : morningBatches.last;

  @override
  bool get isSupported => false;

  @override
  Future<void> showOverLimit(String body) async => overLimit.add(body);

  @override
  Future<bool?> areEnabled() async => enabled;

  @override
  Future<bool> requestPermission() async => enabled ?? false;

  @override
  Future<void> showTest() async => tests++;

  @override
  Future<void> scheduleMorningLimits(List<({DateTime at, String title, String body})> items) async =>
      morningBatches.add(items);

  @override
  Future<void> cancelMorningLimit() async => morningCancels++;

  final weekly = <({DateTime at, String title, String body})>[];
  int weeklyCancels = 0;

  @override
  Future<void> scheduleWeeklyInsight(DateTime at, String title, String body) async =>
      weekly.add((at: at, title: title, body: body));

  @override
  Future<void> cancelWeeklyInsight() async => weeklyCancels++;
}

/// Records what would be sent to the Android home-screen widget.
class FakeHomeWidget extends HomeWidgetService {
  FakeHomeWidget({this.supported = false, this.pinResult = true});
  final bool supported;
  final bool pinResult;
  final updates = <String>[];
  int pinRequests = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<void> update(String itemsJson) async => updates.add(itemsJson);

  /// Ticks "made on the widget", handed over once.
  Map<int, bool> toggles = {};

  @override
  Future<Map<int, bool>> takeToggles() async {
    final out = toggles;
    toggles = {};
    return out;
  }

  @override
  Future<bool> requestPin() async {
    pinRequests++;
    return pinResult;
  }
}

AppDatabase memoryDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Settings + DB + fakes, ready for a ProviderScope / ProviderContainer.
Future<List<Override>> testOverrides({
  required AppDatabase db,
  AppSettings settings = const AppSettings(),
  FakeHomeWidget? homeWidget,
  FakeNotifications? notifications,
}) async {
  SharedPreferences.setMockInitialValues({'app_settings_v1': jsonEncode(settings.toJson())});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPrefsProvider.overrideWithValue(prefs),
    databaseProvider.overrideWithValue(db),
    autoTrackingBridgeProvider.overrideWithValue(FakeBridge()),
    notificationServiceProvider.overrideWithValue(notifications ?? FakeNotifications()),
    homeWidgetServiceProvider.overrideWithValue(homeWidget ?? FakeHomeWidget()),
  ];
}

/// Real Roboto metrics, so overflow checks match a phone rather than the
/// square-glyph test font.
Future<void> loadRoboto() async {
  final dir = Directory(
      '${Platform.environment['FLUTTER_ROOT'] ?? r'C:\src\flutter'}/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/Roboto');
  if (!dir.existsSync()) return; // falls back to the test font
  final loader = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold', 'Black']) {
    final f = File('${dir.path}/Roboto-$w.ttf');
    if (f.existsSync()) loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await loader.load();
}

/// A configured, already-set-up PocketPlan user.
final setUpUser = AppSettings(
  onboardingSeen: true,
  setupDone: true,
  monthlyBudget: 30000,
  periodStart: DateTime(2026, 11, 1),
  periodEnd: DateTime(2026, 11, 30),
);
