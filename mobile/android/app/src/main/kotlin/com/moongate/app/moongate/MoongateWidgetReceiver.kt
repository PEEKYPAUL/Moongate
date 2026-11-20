package com.moongate.app.moongate

import android.content.Context
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/**
 * The AppWidgetProvider behind Moongate's home-screen widget, declared in the
 * manifest and the target of Dart's `HomeWidget.updateWidget(...)`. home_widget's
 * base class copies its SharedPreferences bridge into the Glance state on every
 * update, so [MoongateWidget] reads the Dart-written snapshot straight from
 * `currentState<HomeWidgetGlanceState>().preferences`.
 */
class MoongateWidgetReceiver : HomeWidgetGlanceWidgetReceiver<MoongateWidget>() {
    override val glanceAppWidget: MoongateWidget = MoongateWidget()

    /**
     * The Android 15+ picker preview is static sample data, so it never has to
     * be re-registered once accepted (a constant fingerprint).
     */
    override fun previewFingerprint(context: Context): String = "moongate-widget-preview-1"
}
