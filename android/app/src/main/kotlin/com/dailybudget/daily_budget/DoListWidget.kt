package com.dailybudget.daily_budget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * DoList home-screen widget: a movable, resizable box on top of the user's
 * own wallpaper. Heading "DoList", then one small pastel box per to-do that is
 * active today, each ending with its start and end date/time.
 *
 * The app sends every to-do that hasn't ended (with start/end); the widget
 * picks today's ones itself, so it rolls over to a new day without the app.
 */
class DoListWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateOne(context, manager, it) }
        manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            val id = intent.getLongExtra(EXTRA_ID, -1L)
            if (id >= 0) toggle(context, id)
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        const val PREFS = "dolist_widget"
        const val KEY_ITEMS = "items"
        /** {todoId: done} ticks made on the widget, not yet saved by the app. */
        const val KEY_PENDING = "pending"
        const val ACTION_TOGGLE = "com.dailybudget.daily_budget.DOLIST_TOGGLE"
        const val EXTRA_ID = "todo_id"

        private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        private fun parseArray(raw: String?) = try { JSONArray(raw ?: "[]") } catch (_: Exception) { JSONArray() }
        private fun parseObject(raw: String?) = try { JSONObject(raw ?: "{}") } catch (_: Exception) { JSONObject() }

        /** Widget tap: strike / un-strike right away and remember it for the app. */
        fun toggle(context: Context, id: Long) {
            val p = prefs(context)
            val items = parseArray(p.getString(KEY_ITEMS, "[]"))
            var newDone: Boolean? = null
            for (i in 0 until items.length()) {
                val o = items.getJSONObject(i)
                if (o.optLong("id", -1L) == id) {
                    newDone = !o.optBoolean("done")
                    o.put("done", newDone)
                }
            }
            if (newDone == null) return
            val pending = parseObject(p.getString(KEY_PENDING, "{}")).put(id.toString(), newDone)
            p.edit().putString(KEY_ITEMS, items.toString()).putString(KEY_PENDING, pending.toString()).apply()
            updateAll(context)
        }

        /** List from the app; ticks the app hasn't picked up yet stay applied. */
        fun saveFromApp(context: Context, itemsJson: String) {
            val p = prefs(context)
            val pending = parseObject(p.getString(KEY_PENDING, "{}"))
            val items = parseArray(itemsJson)
            for (i in 0 until items.length()) {
                val o = items.getJSONObject(i)
                val key = o.optLong("id", -1L).toString()
                if (pending.has(key)) o.put("done", pending.getBoolean(key))
            }
            p.edit().putString(KEY_ITEMS, items.toString()).apply()
            updateAll(context)
        }

        /** Hands widget ticks to the app (which saves them) and clears them. */
        fun takePending(context: Context): String {
            val p = prefs(context)
            val raw = p.getString(KEY_PENDING, "{}") ?: "{}"
            p.edit().remove(KEY_PENDING).apply()
            return raw
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, DoListWidgetProvider::class.java))
            if (ids.isEmpty()) return
            ids.forEach { updateOne(context, manager, it) }
            manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
        }

        private fun updateOne(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_dolist)
            val adapter = Intent(context, DoListWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME)) // unique per widget
            }
            @Suppress("DEPRECATION")
            views.setRemoteAdapter(R.id.widget_list, adapter)
            views.setEmptyView(R.id.widget_list, R.id.widget_empty)

            // Tapping the box (outside a note) opens OmniTrex.
            val open = PendingIntent.getActivity(
                context, 0, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.widget_root, open)
            // Tapping a note strikes / un-strikes it (each note fills in its id,
            // so the template must be mutable).
            val mutable = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S)
                PendingIntent.FLAG_MUTABLE else 0
            val toggle = PendingIntent.getBroadcast(
                context, 1,
                Intent(context, DoListWidgetProvider::class.java).setAction(ACTION_TOGGLE),
                mutable or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setPendingIntentTemplate(R.id.widget_list, toggle)
            manager.updateAppWidget(id, views)
        }

        /** Items whose start…end touches today (local time). */
        fun todaysItems(context: Context): List<JSONObject> {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_ITEMS, "[]")
            val all = try { JSONArray(raw) } catch (_: Exception) { JSONArray() }
            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            val dayStart = cal.timeInMillis
            cal.add(Calendar.DAY_OF_MONTH, 1)
            val dayEnd = cal.timeInMillis
            return (0 until all.length()).map { all.getJSONObject(it) }.filter {
                it.optLong("startMs") < dayEnd && it.optLong("endMs") >= dayStart
            }
        }

        private val noteBackgrounds = intArrayOf(
            R.drawable.widget_note_0, R.drawable.widget_note_1, R.drawable.widget_note_2,
            R.drawable.widget_note_3, R.drawable.widget_note_4,
        )

        fun noteBackground(colorIndex: Int) = noteBackgrounds[Math.floorMod(colorIndex, noteBackgrounds.size)]
    }
}

class DoListWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Factory(applicationContext)

    private class Factory(private val context: Context) : RemoteViewsFactory {
        private var items: List<JSONObject> = emptyList()

        override fun onCreate() {}
        override fun onDataSetChanged() { items = DoListWidgetProvider.todaysItems(context) }
        override fun onDestroy() {}
        override fun getCount() = items.size
        override fun getLoadingView(): RemoteViews? = null
        override fun getViewTypeCount() = 1
        override fun getItemId(position: Int) = position.toLong()
        override fun hasStableIds() = false

        override fun getViewAt(position: Int): RemoteViews {
            val item = items[position]
            val done = item.optBoolean("done")
            val title = item.optString("title")
            val views = RemoteViews(context.packageName, R.layout.widget_dolist_item)
            views.setTextViewText(R.id.item_check, if (done) "✓" else "○")
            views.setTextViewText(
                R.id.item_title,
                if (done) SpannableString(title).apply {
                    setSpan(StrikethroughSpan(), 0, title.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                } else title,
            )
            views.setTextViewText(R.id.item_when, item.optString("when"))
            views.setInt(R.id.item_root, "setBackgroundResource", DoListWidgetProvider.noteBackground(item.optInt("color")))
            views.setOnClickFillInIntent(R.id.item_root, Intent().putExtra(DoListWidgetProvider.EXTRA_ID, item.optLong("id", -1L)))
            return views
        }
    }
}
