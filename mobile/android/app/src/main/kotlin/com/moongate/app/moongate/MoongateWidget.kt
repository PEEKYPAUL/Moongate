package com.moongate.app.moongate

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionSendBroadcast
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.material3.ColorProviders
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition

/**
 * Moongate's home-screen widget (v0.9.79, Android): live printer status, fed by
 * the print-notification service through home_widget - no poller of its own.
 *
 * One Glance widget behind SEVEN app-widget providers (see
 * MoongateWidgetReceivers.kt), one per preset size, so the launcher's picker
 * lists "Moongate 2x2" ... "Moongate 4x4" and the user picks the size when
 * adding. Every provider renders the same snapshot; the layout follows the
 * size actually granted ([SizeMode.Exact]):
 *   • narrower than three cells (2x2, 2x4): the printer that matters most -
 *     name, progress ring, state, time left + finish clock, and on the tall
 *     2x4 also the file / layer line and the temperatures;
 *   • three cells or wider (3x2, 3x4, 4x2, 4x3, 4x4): the WHOLE fleet, one
 *     row per printer. A printing / paused printer gets the "printing block"
 *     (Paul's mock-up): a progress ring with the percent on the far left and,
 *     stacked to its right, the name, "time left · 🏁 finish", a progress bar
 *     and the truncated file; an idle printer keeps a compact row (name,
 *     state, temperatures). The rows share the tile's full height (so four
 *     printers fill a 4x4, not a block at the top), type and ring scale with
 *     the room per row ([Type]), and only when more printers are paired than
 *     the tile can show does the list scroll (swipe for more).
 * "Matters most" is Dart's call, by the dashboard ranking (error, then
 * printing / paused / heating, then ready, idle, offline) - see
 * WidgetSnapshot.featured.
 *
 * Every word comes pre-rendered and localised from Dart ([WidgetSnapshot]);
 * this file lays out, colours and draws. While the service is off the last
 * snapshot is shown greyed with an "updated N min ago" hint and a refresh
 * glyph that runs a one-shot Dart poll in the background.
 *
 * Tap: anywhere on the widget, any size, opens the dashboard
 * (`moongate://dashboard`, a plain VIEW intent on the scheme the pairing
 * links already use, so DeepLinkService handles it). There are no per-printer
 * links: the path of a launching VIEW intent is also fed to go_router as the
 * initial route, and `moongate://dashboard` has none.
 */
class MoongateWidget : GlanceAppWidget() {

    companion object {
        /** home_widget SharedPreferences keys - WidgetFeed.snapshotKey / stringsKey in Dart. */
        const val KEY_SNAPSHOT = "fleet_snapshot"
        const val KEY_STRINGS  = "widget_strings"

        /** The whole-tile tap target - DeepLinkService routes it to the dashboard. */
        const val DASHBOARD_URI = "moongate://dashboard"

        /** The refresh glyph's background URI - WidgetFeed.refreshUri in Dart. */
        const val REFRESH_URI = "moongate://widget/refresh"

        /** home_widget's background action (HomeWidgetBackgroundIntent keeps it private). */
        private const val HOME_WIDGET_BACKGROUND_ACTION = "es.antonborri.home_widget.action.BACKGROUND"

        // Launcher cells are about 70 dp each minus 30 dp of gutter: two cells
        // never reach 180 dp, three cells always do. Below this width the tile
        // is a one-printer view; from it on, the fleet list.
        private val FLEET_MIN_WIDTH = 180.dp
        // From here on a row has room for the temperature line too.
        private val DETAIL_MIN_WIDTH = 240.dp
        // A one-printer tile this tall (2x4) gains the file and temperature lines.
        private val TALL_MIN_HEIGHT = 180.dp
        // Fleet type buckets by tile height: two cells (under 180 dp), three
        // (under 300 dp), four and up. The row minimum is what a row needs at
        // that type before the list has to scroll instead of sharing the height.
        private val TYPE_SMALL  = Type(name = 13.sp, body = 11.sp, fine = 10.sp, bar = 5.dp,  gap = 4.dp,  rowMin = 46.dp, fileChars = 28)
        private val TYPE_MEDIUM = Type(name = 16.sp, body = 13.sp, fine = 12.sp, bar = 7.dp,  gap = 8.dp,  rowMin = 68.dp, fileChars = 30)
        private val TYPE_LARGE  = Type(name = 19.sp, body = 15.sp, fine = 13.sp, bar = 8.dp,  gap = 10.dp, rowMin = 84.dp, fileChars = 34)

        // State colours as the dashboard tiles use them: printing = the theme's
        // primary (dynamic colour), paused / heating = orange, error = red,
        // finished = teal, everything idle-ish = blue-grey.
        private val ORANGE   = Color(0xFFFF9800)
        private val RED      = Color(0xFFF44336)
        private val TEAL     = Color(0xFF009688)
        private val BLUEGREY = Color(0xFF607D8B)
        private val GREY     = Color(0xFF9E9E9E)
        private val TRACK    = Color(0x33808080)
    }

    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    /** The granted size decides the layout, so render for the exact size. */
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val prefs    = currentState<HomeWidgetGlanceState>().preferences
            val snapshot = WidgetSnapshot.parse(prefs.getString(KEY_SNAPSHOT, null))
            val strings  = WidgetStrings.resolve(prefs.getString(KEY_STRINGS, null), snapshot)
            Root(snapshot, strings)
        }
    }

    /** Android 15+ live picker preview: sample data through the real layouts. */
    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        provideContent {
            Root(WidgetSnapshot.sample(), WidgetStrings(emptyMap()))
        }
    }

    // ── Root ─────────────────────────────────────────────────────────────────

    @Composable
    private fun Root(snapshot: WidgetSnapshot?, strings: WidgetStrings) {
        val context = LocalContext.current
        // Material You on Android 12+ (Glance's dynamic providers); below that
        // a Material 3 scheme seeded like the app's default theme.
        val colors = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            GlanceTheme.colors
        } else {
            ColorProviders(
                light = lightColorScheme(primary = Color(0xFF5A54D6)),
                dark  = darkColorScheme(primary = Color(0xFFC5C0FF)),
            )
        }
        GlanceTheme(colors = colors) {
            var card = GlanceModifier
                .fillMaxSize()
                .appWidgetBackground()
                .background(GlanceTheme.colors.widgetBackground)
                .clickable(openDashboard(context))
            card = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                card.cornerRadius(android.R.dimen.system_app_widget_background_radius)
            } else {
                card.cornerRadius(16.dp)
            }
            Box(modifier = card.padding(horizontal = 12.dp, vertical = 10.dp)) {
                when {
                    snapshot == null            -> Message(strings.noData)
                    snapshot.printers.isEmpty() -> Message(strings.noPrinters)
                    else                        -> Content(snapshot, strings)
                }
                if (snapshot != null && !snapshot.monitoring) {
                    Box(
                        modifier = GlanceModifier.fillMaxSize(),
                        contentAlignment = Alignment.TopEnd,
                    ) {
                        RefreshGlyph(context)
                    }
                }
            }
        }
    }

    @Composable
    private fun Content(snapshot: WidgetSnapshot, strings: WidgetStrings) {
        val size  = LocalSize.current
        val stale = !snapshot.monitoring
        val hint  = if (stale) strings.updatedAt(LocalContext.current, snapshot.updatedAt) else null
        if (size.width < FLEET_MIN_WIDTH) {
            val one = snapshot.featuredPrinter ?: return
            FeaturedLayout(one, stale, hint, tall = size.height >= TALL_MIN_HEIGHT)
        } else {
            FleetLayout(snapshot.printers, stale, hint, size)
        }
    }

    @Composable
    private fun Message(text: String) {
        Box(modifier = GlanceModifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                text  = text,
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 12.sp),
                maxLines = 3,
            )
        }
    }

    // ── Two cells wide: the one printer that matters most ────────────────────

    @Composable
    private fun FeaturedLayout(p: WidgetPrinter, stale: Boolean, hint: String?, tall: Boolean) {
        Column(
            modifier = GlanceModifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalAlignment   = Alignment.CenterVertically,
        ) {
            Text(p.name, style = title(12.sp), maxLines = 1)
            Spacer(GlanceModifier.height(4.dp))
            Ring(p, stale, 54.dp, 6.dp, 14.sp)
            Spacer(GlanceModifier.height(4.dp))
            Text(p.stateLabel, style = stateStyle(p, stale, 11.sp), maxLines = 1)
            val eta = etaLine(p)
            if (eta != null) Text(eta, style = secondary(10.sp), maxLines = 1)
            if (tall) {
                val detail = detailLine(p)
                if (detail != null) {
                    Spacer(GlanceModifier.height(6.dp))
                    Text(detail, style = secondary(10.sp), maxLines = 2)
                }
                Spacer(GlanceModifier.height(4.dp))
                Text(tempsLine(p), style = secondary(10.sp), maxLines = 1)
            }
            if (hint != null) {
                Spacer(GlanceModifier.height(4.dp))
                Text(hint, style = secondary(10.sp), maxLines = 1)
            }
        }
    }

    // ── Three cells or wider: the whole fleet, one row per printer ───────────

    /** Type and spacing for one tile-size bucket (see TYPE_SMALL / MEDIUM / LARGE). */
    private data class Type(
        val name: TextUnit,
        val body: TextUnit,
        val fine: TextUnit,
        val bar: Dp,
        val gap: Dp,
        val rowMin: Dp,
        /** Characters of file name a row shows before "…" (no ellipsize in Glance). */
        val fileChars: Int,
    )

    private fun typeFor(size: DpSize): Type = when {
        size.height >= 300.dp -> TYPE_LARGE
        size.height >= 180.dp -> TYPE_MEDIUM
        else                  -> TYPE_SMALL
    }

    @Composable
    private fun FleetLayout(printers: List<WidgetPrinter>, stale: Boolean, hint: String?, size: DpSize) {
        val context = LocalContext.current
        val t       = typeFor(size)
        val detail  = size.width >= DETAIL_MIN_WIDTH
        // Does every printer get a row at this type without scrolling? A
        // printing block needs more height than a compact row. If they all fit,
        // the rows share the whole height (weights) so the tile is filled;
        // otherwise a scrolling list at the minimum row height, swipe for more.
        val headerDp = if (hint != null) 22f else 0f
        val avail    = size.height.value - headerDp - 20f
        val needed   = printers.sumOf { rowMin(it, t).toDouble() }.toFloat()
        val fits     = needed <= avail
        val rowDp    = if (fits) avail / printers.size else 0f
        Column(modifier = GlanceModifier.fillMaxSize()) {
            if (hint != null) {
                // Above the list, clear of the refresh glyph in the corner.
                Row(modifier = GlanceModifier.fillMaxWidth().padding(bottom = 2.dp)) {
                    Text(hint, style = secondary(t.fine), maxLines = 1)
                    Spacer(GlanceModifier.width(22.dp))
                }
            }
            if (fits) {
                printers.forEachIndexed { i, p ->
                    if (i > 0) Divider()
                    PrinterRow(p, stale, detail, t, rowDp, openDashboard(context),
                        GlanceModifier.fillMaxWidth().defaultWeight())
                }
            } else {
                // Rows carry the dashboard click themselves - the list view
                // takes the touches, so the card's own clickable never sees them.
                LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
                    items(printers, itemId = { it.id.hashCode().toLong() }) { p ->
                        Column(modifier = GlanceModifier.fillMaxWidth()) {
                            PrinterRow(p, stale, detail, t, rowMin(p, t), openDashboard(context),
                                GlanceModifier.fillMaxWidth())
                            Divider()
                        }
                    }
                }
            }
        }
    }

    /** The height (dp) a printer's row needs at this type: more for a printing block. */
    private fun rowMin(p: WidgetPrinter, t: Type): Float =
        if (p.isActive) t.rowMin.value + 18f else t.rowMin.value

    /** A hairline between fleet rows, so the spacing reads as deliberate. */
    @Composable
    private fun Divider() {
        Box(modifier = GlanceModifier.fillMaxWidth().height(1.dp).background(ColorProvider(TRACK))) {}
    }

    /**
     * One fleet row. [rowDp] is the height the row has (shared height when the
     * fleet fits, else the row minimum) and sizes the printing block's ring.
     */
    @Composable
    private fun PrinterRow(p: WidgetPrinter, stale: Boolean, detail: Boolean, t: Type, rowDp: Float, onClick: Action, modifier: GlanceModifier) {
        if (p.isActive) {
            PrintingBlock(p, stale, detail, t, rowDp, onClick, modifier)
            return
        }
        // Compact row for a printer that is not printing: dot, name, state
        // word, and the temperatures right-aligned where the width allows.
        Column(
            modifier = modifier.padding(vertical = t.gap).clickable(onClick),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Dot(p, stale, t.body)
                Spacer(GlanceModifier.width(6.dp))
                Text(p.name, style = title(t.name), maxLines = 1, modifier = GlanceModifier.defaultWeight())
                Spacer(GlanceModifier.width(8.dp))
                Text(p.stateLabel, style = stateStyle(p, stale, t.body), maxLines = 1)
            }
            if (detail) {
                Spacer(GlanceModifier.height(3.dp))
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Spacer(GlanceModifier.defaultWeight())
                    Text(tempsLine(p), style = secondary(t.body), maxLines = 1)
                }
            }
        }
    }

    /**
     * Paul's printing block: the progress ring with the percent on the far
     * left, sized to the row, and to its right the name (state word at the
     * end), "~46m · 🏁 2:52 PM" (temperatures right-aligned when there is
     * width), the progress bar, and the file cut to the row's budget. On a
     * tight row the file goes first, then the finish clock; the ring, percent
     * and bar always stay. Paused prints use the same block in the paused
     * colour; a print still heating shows the ring at 0 % with the
     * temperatures where the time line would be.
     */
    @Composable
    private fun PrintingBlock(p: WidgetPrinter, stale: Boolean, detail: Boolean, t: Type, rowDp: Float, onClick: Action, modifier: GlanceModifier) {
        val inner    = rowDp - 2f * t.gap.value
        val ringDp   = (inner - 6f).coerceIn(34f, 84f)
        val ringFont = (ringDp / 3.6f).coerceIn(11f, 22f)
        val showFile = inner >= 58f
        val showEnd  = inner >= 46f
        Row(
            modifier = modifier.padding(vertical = t.gap).clickable(onClick),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Ring(p, stale, ringDp.dp, (ringDp / 9f).dp, ringFont.sp)
            Spacer(GlanceModifier.width(10.dp))
            Column(modifier = GlanceModifier.defaultWeight(), verticalAlignment = Alignment.CenterVertically) {
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(p.name, style = title(t.name), maxLines = 1, modifier = GlanceModifier.defaultWeight())
                    Spacer(GlanceModifier.width(8.dp))
                    Text(p.stateLabel, style = stateStyle(p, stale, t.body), maxLines = 1)
                }
                Spacer(GlanceModifier.height(2.dp))
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(timeLine(p, showEnd) ?: tempsLine(p), style = secondary(t.body), maxLines = 1, modifier = GlanceModifier.defaultWeight())
                    if (detail && timeLine(p, showEnd) != null) {
                        Spacer(GlanceModifier.width(8.dp))
                        Text(tempsLine(p), style = secondary(t.fine), maxLines = 1)
                    }
                }
                Spacer(GlanceModifier.height(4.dp))
                Bar(p, stale, GlanceModifier.fillMaxWidth().height(t.bar))
                if (showFile) {
                    val file = fileLine(p, t.fileChars)
                    if (file != null) {
                        Spacer(GlanceModifier.height(3.dp))
                        Text(file, style = secondary(t.fine), maxLines = 1)
                    }
                }
            }
        }
    }

    // ── Pieces ───────────────────────────────────────────────────────────────

    /** Progress ring with the percent inside; the track alone when idle. */
    @Composable
    private fun Ring(p: WidgetPrinter, stale: Boolean, size: Dp, stroke: Dp, fontSize: TextUnit) {
        val context = LocalContext.current
        val color   = stateColor(p, stale).getColor(context).toArgb()
        val bitmap  = ringBitmap(context, if (p.isActive) p.progress else 0f, color, TRACK.toArgb(), size.value, stroke.value)
        Box(modifier = GlanceModifier.size(size), contentAlignment = Alignment.Center) {
            Image(provider = ImageProvider(bitmap), contentDescription = null, modifier = GlanceModifier.size(size))
            if (p.isActive) {
                Text("${p.percent}%", style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = fontSize, fontWeight = FontWeight.Bold), maxLines = 1)
            }
        }
    }

    @Composable
    private fun Bar(p: WidgetPrinter, stale: Boolean, modifier: GlanceModifier) {
        LinearProgressIndicator(
            progress        = p.progress,
            modifier        = modifier,
            color           = stateColor(p, stale),
            backgroundColor = ColorProvider(TRACK),
        )
    }

    /** A coloured status dot: the tile's state colour, grey when stale. */
    @Composable
    private fun Dot(p: WidgetPrinter, stale: Boolean, size: TextUnit = 11.sp) {
        Text("●", style = TextStyle(color = stateColor(p, stale), fontSize = size), maxLines = 1)
    }

    @Composable
    private fun RefreshGlyph(context: Context) {
        val intent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
            action = HOME_WIDGET_BACKGROUND_ACTION
            data   = Uri.parse(REFRESH_URI)
        }
        Image(
            provider           = ImageProvider(R.drawable.ic_widget_refresh),
            contentDescription = null,
            colorFilter        = ColorFilter.tint(GlanceTheme.colors.onSurfaceVariant),
            modifier           = GlanceModifier.size(18.dp).clickable(actionSendBroadcast(intent)),
        )
    }

    @Composable
    private fun title(size: TextUnit) =
        TextStyle(color = GlanceTheme.colors.onSurface, fontSize = size, fontWeight = FontWeight.Bold)

    @Composable
    private fun secondary(size: TextUnit) =
        TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = size)

    @Composable
    private fun stateStyle(p: WidgetPrinter, stale: Boolean, size: TextUnit) =
        TextStyle(color = stateColor(p, stale), fontSize = size, fontWeight = FontWeight.Medium)

    /** The tile's state colour; a flat grey once the snapshot is stale. */
    @Composable
    private fun stateColor(p: WidgetPrinter, stale: Boolean): ColorProvider {
        if (stale) return ColorProvider(GREY)
        return when (p.state) {
            "printing"           -> GlanceTheme.colors.primary
            "paused", "heating"  -> ColorProvider(ORANGE)
            "error"              -> ColorProvider(RED)
            "complete"           -> ColorProvider(TEAL)
            else                 -> ColorProvider(BLUEGREY)
        }
    }

    /** "42% · ~1h05m" for a running print; "42%" when no estimate yet. */
    private fun progressLine(p: WidgetPrinter): String =
        listOfNotNull("${p.percent}%", p.remainingLabel).joinToString(" · ")

    /** "~1h05m · 13:20", or null when there is nothing to project. */
    private fun etaLine(p: WidgetPrinter): String? {
        val parts = listOfNotNull(p.remainingLabel, p.finishClock)
        return if (parts.isEmpty()) null else parts.joinToString(" · ")
    }

    /** "benchy.gcode · Layer 84 / 200", or null when idle (the featured tile). */
    private fun detailLine(p: WidgetPrinter): String? {
        val parts = listOfNotNull(p.filename, p.layerLabel)
        return if (parts.isEmpty()) null else parts.joinToString(" · ")
    }

    /**
     * "~46m · 🏁 2:52 PM" for a running print (the percent lives in the ring);
     * without the finish clock when [withEnd] is false; null when there is no
     * estimate yet (then the caller shows the temperatures instead).
     */
    private fun timeLine(p: WidgetPrinter, withEnd: Boolean): String? {
        val parts = listOfNotNull(
            p.remainingLabel,
            if (withEnd) p.finishClock?.let { "🏁$it" } else null,
        )
        return if (parts.isEmpty()) null else parts.joinToString(" · ")
    }

    /**
     * The file for a fleet row: slicer suffix dropped, cut to [budget]
     * characters with an ellipsis, then the layer line if there is one.
     */
    private fun fileLine(p: WidgetPrinter, budget: Int): String? {
        var name = p.filename ?: return p.layerLabel
        name = name.removeSuffix(".gcode").removeSuffix(".gco").removeSuffix(".g")
        if (name.length > budget) name = name.take((budget - 1).coerceAtLeast(1)).trimEnd() + "…"
        return listOfNotNull(name, p.layerLabel).joinToString(" · ")
    }

    /** Hotend / bed / chamber, the notification's own markers, chamber only when sensed. */
    private fun tempsLine(p: WidgetPrinter): String {
        val parts = mutableListOf("🔥${p.hotend.toInt()}°", "🟧${p.bed.toInt()}°")
        if (p.chamber > 0f) parts.add("🏠${p.chamber.toInt()}°")
        return parts.joinToString("  ")
    }

    /** The whole-tile tap: an explicit VIEW intent into MainActivity. */
    private fun openDashboard(context: Context): Action =
        actionStartActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(DASHBOARD_URI), context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )

    /** Draw the ring: a full track plus the progress arc from 12 o'clock. */
    private fun ringBitmap(context: Context, progress: Float, color: Int, track: Int, sizeDp: Float, strokeDp: Float): Bitmap {
        val density = context.resources.displayMetrics.density
        val px      = (sizeDp * density).toInt().coerceAtLeast(8)
        val stroke  = strokeDp * density
        val bmp     = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val canvas  = Canvas(bmp)
        val paint   = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style       = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap   = Paint.Cap.ROUND
        }
        val inset = stroke / 2f
        val rect  = RectF(inset, inset, px - inset, px - inset)
        paint.color = track
        canvas.drawArc(rect, 0f, 360f, false, paint)
        if (progress > 0f) {
            paint.color = color
            canvas.drawArc(rect, -90f, 360f * progress.coerceIn(0f, 1f), false, paint)
        }
        return bmp
    }
}
