package com.moongate.app.moongate

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.glance.ExperimentalGlanceApi
import androidx.glance.appwidget.AppWidgetId
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.compose
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * The prompt redraw path for the home-screen widget.
 *
 * Glance's own [androidx.glance.appwidget.GlanceAppWidget.update] does not
 * draw: it hands the work to a WorkManager session (a plain, non-expedited
 * OneTimeWorkRequest), and Android schedules that when it sees fit - on a
 * device test the placed widget repainted minutes apart while the
 * notification refreshed every poll. Glance 1.1+ also offers
 * [androidx.glance.appwidget.compose], which runs the composition right here
 * and returns the RemoteViews; handing those to [AppWidgetManager.updateAppWidget]
 * repaints the launcher at once, with no job in between.
 *
 * [refreshAll] walks the seven providers, finds the instances that are
 * actually placed (usually one) and composes each directly, so a publish
 * costs one broadcast and one composition instead of seven broadcasts and a
 * WorkManager job each. The Dart side (WidgetFeed) pokes
 * [MoongateWidgetRefreshReceiver] once per poll.
 */
object MoongateWidgetRefresh {
    private const val TAG = "MoongateWidget"

    /** Every size's provider (MoongateWidgetReceivers.kt). */
    val providers: List<Class<out MoongateWidgetReceiver>> = listOf(
        MoongateWidgetReceiver2x2::class.java,
        MoongateWidgetReceiver2x4::class.java,
        MoongateWidgetReceiver3x2::class.java,
        MoongateWidgetReceiver3x4::class.java,
        MoongateWidgetReceiver4x2::class.java,
        MoongateWidgetReceiver4x3::class.java,
        MoongateWidgetReceiver4x4::class.java,
    )

    /** Compose and push every placed instance. Returns how many were drawn. */
    suspend fun refreshAll(context: Context): Int {
        val manager = AppWidgetManager.getInstance(context)
        val widget  = MoongateWidget()
        var state: Any? = null
        var drawn = 0
        for (cls in providers) {
            val ids = manager.getAppWidgetIds(ComponentName(context, cls))
            for (id in ids) {
                if (state == null) state = loadState(context)
                refresh(context, manager, widget, id, state)
                drawn++
            }
        }
        return drawn
    }

    /** The widget's state as the Glance composition reads it: home_widget's SharedPreferences bridge. */
    suspend fun loadState(context: Context): Any =
        HomeWidgetGlanceStateDefinition().getDataStore(context, "").data.first()

    /**
     * Compose one placed instance for its current size options and hand the
     * views straight to the launcher. Should the direct composition fail,
     * fall back to Glance's own (deferred) update rather than leave the
     * widget stale.
     */
    @OptIn(ExperimentalGlanceApi::class)
    suspend fun refresh(context: Context, manager: AppWidgetManager, widget: MoongateWidget, appWidgetId: Int, state: Any?) {
        try {
            val views = widget.compose(
                context = context,
                id      = AppWidgetId(appWidgetId),
                options = manager.getAppWidgetOptions(appWidgetId),
                state   = state,
            )
            manager.updateAppWidget(appWidgetId, views)
        } catch (e: Exception) {
            Log.w(TAG, "direct compose failed for widget $appWidgetId, falling back to a Glance session", e)
            widget.update(context, GlanceAppWidgetManager(context).getGlanceIdBy(appWidgetId))
        }
    }
}

/**
 * The one receiver Dart pokes per poll (home_widget's updateWidget sends it
 * an explicit APPWIDGET_UPDATE intent): redraws every placed widget directly,
 * see [MoongateWidgetRefresh]. Not exported - same-app intents only.
 */
class MoongateWidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                MoongateWidgetRefresh.refreshAll(context)
            } catch (e: Exception) {
                Log.w("MoongateWidget", "widget refresh failed", e)
            } finally {
                pending.finish()
            }
        }
    }
}
