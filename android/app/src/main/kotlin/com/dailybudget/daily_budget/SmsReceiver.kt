package com.dailybudget.daily_budget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/** Queues incoming SMS; multipart messages are joined per sender. */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        parts.groupBy { it.originatingAddress }.forEach { (sender, msgs) ->
            val body = msgs.joinToString("") { it.messageBody ?: "" }
            // Cheap pre-filter: only messages that mention money reach the queue.
            if (MONEY.containsMatchIn(body)) {
                MessageQueue.enqueue(context, body, sender, "sms", msgs.first().timestampMillis)
            }
        }
    }

    companion object {
        val MONEY = Regex("(rs\\.?|inr|₹|debited|credited|spent|refund)", RegexOption.IGNORE_CASE)
    }
}
