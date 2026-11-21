package com.moongate.app.moongate

import android.content.Context
import android.text.format.DateUtils
import org.json.JSONObject

/**
 * The fleet snapshot the Dart side writes for the home-screen widget
 * (mobile/lib/models/widget_snapshot.dart is the schema; this is its reader).
 *
 * Dart produces every display string already localised to the app's language
 * - state words, remaining time, finish clock, layer line, the templates for
 * the text this side must build itself - so nothing here is translated and
 * the widget needs no Android string resources. Kotlin only parses and draws.
 */
data class WidgetPrinter(
    val id: String,
    val name: String,
    /** Raw state the colour and ranking key off: printing / paused / heating / error / offline / ... */
    val state: String,
    /** The localised state word (Printing / Paused / Ready / Offline ...). */
    val stateLabel: String,
    /** 0..1 while printing or paused, else 0. */
    val progress: Float,
    /** "~1h05m", or null when unknown. */
    val remainingLabel: String?,
    /** "13:20" / "1:20 PM", or null when unknown. */
    val finishClock: String?,
    /** The printing file, folder stripped; null when idle. */
    val filename: String?,
    /** "Layer 12 / 300" when the slicer reports layers; null otherwise. */
    val layerLabel: String?,
    val hotend: Float,
    val hotendTarget: Float,
    val bed: Float,
    val bedTarget: Float,
    /** 0 when the printer has no chamber sensor. */
    val chamber: Float,
) {
    val isActive: Boolean get() = state == "printing" || state == "paused"
    val percent: Int get() = (progress * 100).toInt().coerceIn(0, 100)

    companion object {
        fun from(j: JSONObject): WidgetPrinter = WidgetPrinter(
            id             = j.optString("id"),
            name           = j.optString("name"),
            state          = j.optString("state", "offline"),
            stateLabel     = j.optString("stateLabel"),
            progress       = j.optDouble("progress", 0.0).toFloat().coerceIn(0f, 1f),
            remainingLabel = j.optStringOrNull("remainingLabel"),
            finishClock    = j.optStringOrNull("finishClock"),
            filename       = j.optStringOrNull("filename"),
            layerLabel     = j.optStringOrNull("layerLabel"),
            hotend         = j.optDouble("hotend", 0.0).toFloat(),
            hotendTarget   = j.optDouble("hotendTarget", 0.0).toFloat(),
            bed            = j.optDouble("bed", 0.0).toFloat(),
            bedTarget      = j.optDouble("bedTarget", 0.0).toFloat(),
            chamber        = j.optDouble("chamber", 0.0).toFloat(),
        )
    }
}

data class WidgetSnapshot(
    /** Epoch millis of the poll that produced this. */
    val updatedAt: Long,
    /** True while the print-notification service is feeding the widget. */
    val monitoring: Boolean,
    /** Dashboard order; the fleet layout lists them as given. */
    val printers: List<WidgetPrinter>,
    /** Index of the printer the one-printer layouts show (Dart's pick by rank). */
    val featured: Int,
    /** Localised templates, see [WidgetStrings]. */
    val strings: Map<String, String>,
) {
    val featuredPrinter: WidgetPrinter?
        get() = printers.getOrNull(featured) ?: printers.firstOrNull()

    companion object {
        /** The newest schema this reader understands; newer snapshots are ignored. */
        const val SCHEMA = 1

        /** Null for an absent, unreadable or too-new snapshot. */
        fun parse(raw: String?): WidgetSnapshot? {
            if (raw.isNullOrEmpty()) return null
            return try {
                val j = JSONObject(raw)
                if (j.optInt("v", 0) > SCHEMA) return null
                val arr = j.optJSONArray("printers")
                val printers = ArrayList<WidgetPrinter>()
                if (arr != null) {
                    for (i in 0 until arr.length()) {
                        arr.optJSONObject(i)?.let { printers.add(WidgetPrinter.from(it)) }
                    }
                }
                WidgetSnapshot(
                    updatedAt  = j.optLong("updatedAt", 0L),
                    monitoring = j.optBoolean("monitoring", false),
                    printers   = printers,
                    featured   = j.optInt("featured", 0),
                    strings    = parseStrings(j.optJSONObject("strings")),
                )
            } catch (_: Exception) {
                null
            }
        }

        fun parseStrings(j: JSONObject?): Map<String, String> {
            if (j == null) return emptyMap()
            val out = HashMap<String, String>()
            val keys = j.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                j.optStringOrNull(k)?.let { out[k] = it }
            }
            return out
        }

        /** Sample fleet for the launcher's live preview (Android 15+). */
        fun sample(): WidgetSnapshot = WidgetSnapshot(
            updatedAt  = System.currentTimeMillis(),
            monitoring = true,
            featured   = 0,
            strings    = emptyMap(),
            printers   = listOf(
                WidgetPrinter(
                    id = "sample-1", name = "Voron 2.4", state = "printing",
                    stateLabel = "Printing", progress = 0.42f, remainingLabel = "~1h05m",
                    finishClock = "13:20", filename = "benchy.gcode", layerLabel = "Layer 84 / 200",
                    hotend = 245f, hotendTarget = 245f, bed = 105f, bedTarget = 105f, chamber = 48f,
                ),
                WidgetPrinter(
                    id = "sample-2", name = "Micron+", state = "standby",
                    stateLabel = "Ready", progress = 0f, remainingLabel = null,
                    finishClock = null, filename = null, layerLabel = null,
                    hotend = 24f, hotendTarget = 0f, bed = 23f, bedTarget = 0f, chamber = 0f,
                ),
            ),
        )
    }
}

/**
 * The localised templates the widget needs for text it builds itself (the
 * stale hint's time stamp, the empty states). The app writes them at start-up
 * under their own key, and every snapshot carries the same set, so the
 * freshest copy wins. English fallbacks guard a widget placed before the app
 * ever ran.
 */
class WidgetStrings(private val map: Map<String, String>) {
    val noData: String      get() = map["noData"]     ?: "Turn on print notifications in Moongate to feed this widget"
    val noPrinters: String  get() = map["noPrinters"] ?: "No printers paired yet"
    private val updatedTpl  get() = map["updatedAt"]  ?: "Updated {n}"

    /**
     * "Updated 14:05" (today) or "Updated 20 Nov, 14:05" for a snapshot written
     * at [updatedAt] (epoch ms UTC, shown in the phone's zone, 12/24 h as the
     * phone is set). An absolute time on purpose: a stale widget is only
     * redrawn when something pokes it, so a relative "N min ago" would freeze
     * at whatever it said when last drawn and quietly go wrong.
     */
    fun updatedAt(context: Context, updatedAt: Long): String {
        var flags = DateUtils.FORMAT_SHOW_TIME
        if (!DateUtils.isToday(updatedAt)) {
            flags = flags or DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_ABBREV_MONTH
        }
        return updatedTpl.replace("{n}", DateUtils.formatDateTime(context, updatedAt, flags))
    }

    companion object {
        /** Merge: the snapshot's own templates over the start-up copy. */
        fun resolve(standalone: String?, snapshot: WidgetSnapshot?): WidgetStrings {
            val base = try {
                WidgetSnapshot.parseStrings(standalone?.let { JSONObject(it) })
            } catch (_: Exception) {
                emptyMap()
            }
            return WidgetStrings(base + (snapshot?.strings ?: emptyMap()))
        }
    }
}

/** JSONObject.optString returns "" / "null" for missing values; we want null. */
private fun JSONObject.optStringOrNull(key: String): String? =
    if (has(key) && !isNull(key)) optString(key).takeIf { it.isNotEmpty() } else null
