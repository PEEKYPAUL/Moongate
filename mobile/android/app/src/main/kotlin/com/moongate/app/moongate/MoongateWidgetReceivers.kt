package com.moongate.app.moongate

import android.content.Context
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/**
 * The AppWidgetProviders behind Moongate's home-screen widget: SEVEN of them,
 * one per preset size, so the launcher's picker lists "Moongate 2x2" ...
 * "Moongate 4x4" and the user picks the size when adding (a single provider
 * only ever offers its one default size). They differ ONLY in the
 * appwidget-provider XML they point at (res/xml/moongate_widget_<w>x<h>.xml:
 * default and minimum size, still resizable); all render the same
 * [MoongateWidget] from the same Dart-written snapshot, and Dart's
 * `WidgetFeed.receivers` lists every class here so one publish redraws all.
 *
 * Sizes are WIDTH x HEIGHT in launcher cells. home_widget's base class copies
 * its SharedPreferences bridge into the Glance state on every update, so the
 * widget reads the snapshot from `currentState<HomeWidgetGlanceState>()`.
 */
abstract class MoongateWidgetReceiver : HomeWidgetGlanceWidgetReceiver<MoongateWidget>() {
    override val glanceAppWidget: MoongateWidget = MoongateWidget()

    /**
     * The Android 15+ picker preview is static sample data, so it never has to
     * be re-registered once accepted (a constant fingerprint).
     */
    override fun previewFingerprint(context: Context): String = "moongate-widget-preview-2"
}

class MoongateWidgetReceiver2x2 : MoongateWidgetReceiver()
class MoongateWidgetReceiver2x4 : MoongateWidgetReceiver()
class MoongateWidgetReceiver3x2 : MoongateWidgetReceiver()
class MoongateWidgetReceiver3x4 : MoongateWidgetReceiver()
class MoongateWidgetReceiver4x2 : MoongateWidgetReceiver()
class MoongateWidgetReceiver4x3 : MoongateWidgetReceiver()
class MoongateWidgetReceiver4x4 : MoongateWidgetReceiver()
