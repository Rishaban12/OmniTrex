import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'presentation/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  final notifications = container.read(notificationServiceProvider);
  await notifications.init();
  await notifications.cancelLegacyEveningReminder();
  runApp(UncontrolledProviderScope(container: container, child: const DailyBudgetApp()));

  // Android 13+ blocks notifications until the user allows them: ask once
  // (over-limit alert + 6 AM limit). No-op on web.
  const asked = 'notification_permission_asked';
  if (notifications.isSupported && !(prefs.getBool(asked) ?? false)) {
    await prefs.setBool(asked, true);
    await notifications.requestPermission();
  }
}
