package com.dailybudget.daily_budget

import android.annotation.SuppressLint
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var launchAction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchAction = actionFrom(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "daily_budget/auto_tracking").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "drainPending" -> result.success(MessageQueue.drain(applicationContext))
                    "hasNotificationAccess" -> result.success(hasNotificationAccess())
                    "openNotificationAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestBatteryExemption()
                        result.success(null)
                    }
                    "takeLaunchAction" -> {
                        result.success(launchAction)
                        launchAction = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MessageQueue.onEnqueued = { channel?.invokeMethod("onMessagesAvailable", null) }

        // DoList home-screen widget: store the to-do list and redraw it, or ask
        // the launcher to place the widget.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "omnitrex/widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        val items = call.argument<String>("items") ?: "[]"
                        DoListWidgetProvider.saveFromApp(applicationContext, items)
                        result.success(null)
                    }
                    "takePending" -> result.success(DoListWidgetProvider.takePending(applicationContext))
                    "requestPin" -> {
                        val mgr = AppWidgetManager.getInstance(this)
                        val ok = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            mgr.isRequestPinAppWidgetSupported &&
                            mgr.requestPinAppWidget(ComponentName(this, DoListWidgetProvider::class.java), null, null)
                        result.success(ok)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (actionFrom(intent) == "quick_add") launchAction = "quick_add"
    }

    override fun onDestroy() {
        MessageQueue.onEnqueued = null
        channel?.setMethodCallHandler(null)
        super.onDestroy()
    }

    private fun actionFrom(intent: Intent?) =
        if (intent?.action == "com.dailybudget.QUICK_ADD") "quick_add" else null

    private fun hasNotificationAccess(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, PaymentNotificationListener::class.java)
        return enabled.split(":").any { ComponentName.unflattenFromString(it) == me }
    }

    @SuppressLint("BatteryLife")
    private fun requestBatteryExemption() {
        try {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:$packageName")))
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }
}
