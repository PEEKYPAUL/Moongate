package com.moongate.app.moongate

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Bundle
import android.util.Log
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * The AppWidgetProviders behind Moongate's home-screen widget: SEVEN of them,
 * one per preset size, so the launcher's picker lists "Moongate 2x2" ...
 * "Moongate 4x4" and the user picks the size when adding (a single provider
 * only ever offers its one default size). They differ ONLY in the
 * appwidget-provider XML they point at (res/xml/moongate_widget_<w>x<h>.xml:
 * default and minimum size, still resizable); all render the same
 * [MoongateWidget] from the same Dart-written snapshot.
 *
 * Sizes are WIDTH x HEIGHT in launcher cells. The widget reads the snapshot
 * from home_widget's SharedPreferences bridge (`currentState<HomeWidgetGlanceState>()`).
 *
 * Redraws are DIRECT, not Glance sessions: the per-poll redraw comes through
 * [MoongateWidgetRefreshReceiver], and the system's own update and resize
 * callbacks here compose the instance on the spot too
 * ([MoongateWidgetRefresh.refresh]), because Glance's update() defers the
 * drawing to WorkManager, which Android may hold for minutes.
 */
abstract class MoongateWidgetReceiver : HomeWidgetGlanceWidgetReceiver<MoongateWidget>() {
    override val glanceAppWidget: MoongateWidget = MoongateWidget()

    /**
     * The Android 15+ picker preview is static sample data, so it never has to
     * be re-registered once accepted (a constant fingerprint).
     */
    override fun previewFingerprint(context: Context): String = "moongate-widget-preview-2"

    /** Placement and the system's periodic update: draw now, not via WorkManager. */
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        drawNow(context, appWidgetManager, appWidgetIds)
    }

    /** A resize: draw for the new size options now. */
    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        drawNow(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    private fun drawNow(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                val state = MoongateWidgetRefresh.loadState(context)
                for (id in appWidgetIds) {
                    MoongateWidgetRefresh.refresh(context, appWidgetManager, glanceAppWidget, id, state)
                }
            } catch (e: Exception) {
                Log.w("MoongateWidget", "widget draw failed", e)
            } finally {
                pending.finish()
            }
        }
    }
}

class MoongateWidgetReceiver2x2 : MoongateWidgetReceiver()
class MoongateWidgetReceiver2x4 : MoongateWidgetReceiver()
class MoongateWidgetReceiver3x2 : MoongateWidgetReceiver()
class MoongateWidgetReceiver3x4 : MoongateWidgetReceiver()
class MoongateWidgetReceiver4x2 : MoongateWidgetReceiver()
class MoongateWidgetReceiver4x3 : MoongateWidgetReceiver()
class MoongateWidgetReceiver4x4 : MoongateWidgetReceiver()
