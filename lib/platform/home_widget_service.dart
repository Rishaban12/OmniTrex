import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Talks to the Android DoList home-screen widget (a movable, resizable box
/// on top of the user's own wallpaper). No-op on web / other platforms.
class HomeWidgetService {
  static const _channel = MethodChannel('omnitrex/widget');

  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Sends the to-do list (JSON) to the widget and redraws it.
  Future<void> update(String itemsJson) async {
    if (!isSupported) return;
    await _channel.invokeMethod('update', {'items': itemsJson});
  }

  /// To-dos ticked / unticked on the widget since the last call ({id: done}).
  /// The widget forgets them once handed over.
  Future<Map<int, bool>> takeToggles() async {
    if (!isSupported) return const {};
    final raw = await _channel.invokeMethod<String>('takePending') ?? '{}';
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return {for (final e in map.entries) int.parse(e.key): e.value as bool};
  }

  /// Asks the launcher to place the widget (Android 8+). Returns false when
  /// the launcher can't do that, so the app can explain the manual steps.
  Future<bool> requestPin() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('requestPin') ?? false;
  }}
