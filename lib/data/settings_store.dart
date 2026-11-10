import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/app_settings.dart';

class SettingsStore {
  SettingsStore(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'app_settings_v1';

  AppSettings load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) => _prefs.setString(_key, jsonEncode(s.toJson()));

  /// Day key (yyyy-mm-dd) of the last over-limit alert: set when it fires,
  /// cleared when spending drops back under the limit (so the next crossing
  /// alerts again, but reopening the app while still over does not).
  String? get lastOverLimitAlert => _prefs.getString('last_over_limit_alert');
  Future<void> setLastOverLimitAlert(String day) =>
      _prefs.setString('last_over_limit_alert', day);
  Future<void> clearLastOverLimitAlert() => _prefs.remove('last_over_limit_alert');
}
