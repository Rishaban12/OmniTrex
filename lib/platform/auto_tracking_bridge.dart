import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/services/sms_parser.dart';

/// Talks to the Android SmsReceiver / NotificationListenerService.
/// Native code queues raw messages on-device; Flutter drains and parses them.
/// On web and other platforms everything reports "unsupported" and the app
/// runs in manual-only mode.
class AutoTrackingBridge {
  AutoTrackingBridge() {
    if (isSupported) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onMessagesAvailable') _onMessages?.call();
      });
    }
  }

  static const _channel = MethodChannel('daily_budget/auto_tracking');
  VoidCallback? _onMessages;

  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  set onMessagesAvailable(VoidCallback? cb) => _onMessages = cb;

  Future<List<RawMessage>> drainPending() async {
    if (!isSupported) return const [];
    final list = await _channel.invokeListMethod<Map>('drainPending') ?? const [];
    return [
      for (final m in list)
        RawMessage(
          body: m['body'] as String? ?? '',
          sender: m['sender'] as String?,
          source: m['source'] == 'notification'
              ? MessageSource.notification
              : MessageSource.sms,
          receivedAt: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
        ),
    ];
  }

  Future<bool> hasSmsPermission() async =>
      isSupported && await Permission.sms.isGranted;

  Future<bool> requestSmsPermission() async =>
      isSupported && (await Permission.sms.request()).isGranted;

  Future<bool> hasNotificationAccess() async => isSupported &&
      (await _channel.invokeMethod<bool>('hasNotificationAccess') ?? false);

  Future<void> openNotificationAccessSettings() async {
    if (isSupported) await _channel.invokeMethod('openNotificationAccessSettings');
  }

  Future<bool> isIgnoringBatteryOptimizations() async => isSupported &&
      (await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false);

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (isSupported) await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
  }

  /// "quick_add" when launched from the launcher shortcut.
  Future<String?> takeLaunchAction() async =>
      isSupported ? _channel.invokeMethod<String>('takeLaunchAction') : null;
}
