package com.dailybudget.daily_budget

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject

/**
 * On-device queue of raw payment messages. Receivers append here even when
 * the Flutter engine isn't running; Dart drains and parses on next resume.
 * Nothing is sent off the device.
 */
object MessageQueue {
    private const val PREFS = "auto_tracking_queue"
    private const val KEY = "pending"
    private const val MAX = 500

    /** Set by MainActivity while the Flutter engine is alive. */
    @Volatile var onEnqueued: (() -> Unit)? = null

    @Synchronized
    fun enqueue(context: Context, body: String, sender: String?, source: String, timestamp: Long) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        arr.put(JSONObject().apply {
            put("body", body)
            put("sender", sender ?: JSONObject.NULL)
            put("source", source)
            put("timestamp", timestamp)
        })
        val trimmed = if (arr.length() > MAX) {
            JSONArray().also { out -> for (i in arr.length() - MAX until arr.length()) out.put(arr.get(i)) }
        } else arr
        prefs.edit().putString(KEY, trimmed.toString()).apply()
        onEnqueued?.let { cb -> Handler(Looper.getMainLooper()).post { cb() } }
    }

    @Synchronized
    fun drain(context: Context): List<Map<String, Any?>> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        prefs.edit().putString(KEY, "[]").apply()
        return (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            mapOf(
                "body" to o.getString("body"),
                "sender" to if (o.isNull("sender")) null else o.getString("sender"),
                "source" to o.getString("source"),
                "timestamp" to o.getLong("timestamp"),
            )
        }
    }
}
