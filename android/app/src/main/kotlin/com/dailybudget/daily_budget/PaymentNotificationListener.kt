package com.dailybudget.daily_budget

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/** Captures payment notifications from GPay, PhonePe and Paytm only. */
class PaymentNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in PACKAGES) return
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        val body = listOf(title, text).filter { it.isNotBlank() }.joinToString("\n")
        if (body.isBlank() || !SmsReceiver.MONEY.containsMatchIn(body)) return
        // Group summaries and progress updates repeat content; skip them.
        if (sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        MessageQueue.enqueue(this, body, sbn.packageName, "notification", sbn.postTime)
    }

    companion object {
        val PACKAGES = setOf(
            "com.google.android.apps.nbu.paisa.user",
            "com.phonepe.app",
            "net.one97.paytm",
        )
    }
}
