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
 *     (Paul's sketch): a LARGE progress ring with the percent, spanning the
 *     block's height on the left; beside it the name over "Status: Printing"
 *     over "~20m · 🏁10:04 PM"; then one tall column per temperature sensor
 *     (the sensor's icon over a large value: a nozzle for the hotend, a
 *     radiator for the bed, a boxed fan for the chamber, the chamber only when
 *     the printer reports one; nozzle and radiator turn red while that heater
 *     is hot). No bar (the ring already shows the percent). The printing
 *     rows take all the height the idle rows leave, so the ring is the
 *     dominant element;
 *     every other printer carries the same heading, "Name |
 *     Status: Ready", with its temperatures on the right while it is on and
 *     nothing more once it is powered off. The rows share the tile's full height (so four
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
        private val TYPE_SMALL  = Type(heading = 15.sp, name = 13.sp, body = 11.sp, fine = 10.sp, gap = 4.dp,  rowMin = 46.dp)
        private val TYPE_MEDIUM = Type(heading = 19.sp, name = 16.sp, body = 13.sp, fine = 12.sp, gap = 8.dp,  rowMin = 68.dp)
        private val TYPE_LARGE  = Type(heading = 23.sp, name = 19.sp, body = 15.sp, fine = 13.sp, gap = 10.dp, rowMin = 84.dp)

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
            FleetLayout(snapshot.printers, stale, hint, strings, size)
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
                if (p.showsTemps) {
                    Spacer(GlanceModifier.height(4.dp))
                    TempsInline(p, 10.sp, GlanceTheme.colors.onSurfaceVariant)
                }
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
        /** The printer name in every row's heading - larger than [name], which sizes the temperatures. */
        val heading: TextUnit,
        val name: TextUnit,
        val body: TextUnit,
        val fine: TextUnit,
        val gap: Dp,
        val rowMin: Dp,
    )

    private fun typeFor(size: DpSize): Type = when {
        size.height >= 300.dp -> TYPE_LARGE
        size.height >= 180.dp -> TYPE_MEDIUM
        else                  -> TYPE_SMALL
    }

    /** The buckets from the tile's own down to the smallest, for sizing rows down. */
    private fun typesFrom(t: Type): List<Type> = when (t) {
        TYPE_LARGE  -> listOf(TYPE_LARGE, TYPE_MEDIUM, TYPE_SMALL)
        TYPE_MEDIUM -> listOf(TYPE_MEDIUM, TYPE_SMALL)
        else        -> listOf(TYPE_SMALL)
    }

    @Composable
    private fun FleetLayout(printers: List<WidgetPrinter>, stale: Boolean, hint: String?, strings: WidgetStrings, size: DpSize) {
        val context = LocalContext.current
        val detail  = size.width >= DETAIL_MIN_WIDTH
        // EVERY paired printer gets a row. First try the tile's own type
        // bucket; if the rows (a printing block needs more height than a
        // compact row) do not all fit, step the type down a bucket, then
        // another, so four printers on a 4x3 still sit on one screen. When
        // they all fit, the rows take the whole height between them (see
        // [rowHeights]: the printing rows get the slack, so their rings grow)
        // and the tile is filled. Only when even the smallest type cannot
        // seat them all does the list scroll (swipe for more) - never drop a
        // printer.
        val headerDp = if (hint != null) 22f else 0f
        val avail    = size.height.value - headerDp - 20f
        val fitting  = typesFrom(typeFor(size)).firstOrNull { t ->
            printers.sumOf { rowMin(it, t).toDouble() } <= avail
        }
        val t        = fitting ?: TYPE_SMALL
        val heights  = if (fitting != null) rowHeights(printers, t, avail) else emptyList()
        Column(modifier = GlanceModifier.fillMaxSize()) {
            if (hint != null) {
                // Above the list, clear of the refresh glyph in the corner.
                Row(modifier = GlanceModifier.fillMaxWidth().padding(bottom = 2.dp)) {
                    Text(hint, style = secondary(t.fine), maxLines = 1)
                    Spacer(GlanceModifier.width(22.dp))
                }
            }
            if (fitting != null) {
                printers.forEachIndexed { i, p ->
                    if (i > 0) Divider()
                    PrinterRow(p, stale, detail, t, strings, heights[i], size.width.value, openDashboard(context),
                        GlanceModifier.fillMaxWidth().height(heights[i].dp))
                }
            } else {
                // Rows carry the dashboard click themselves - the list view
                // takes the touches, so the card's own clickable never sees them.
                LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
                    items(printers) { p ->
                        Column(modifier = GlanceModifier.fillMaxWidth()) {
                            PrinterRow(p, stale, detail, t, strings, rowMin(p, t), size.width.value, openDashboard(context),
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
        if (p.isActive) t.rowMin.value + 24f else t.rowMin.value

    /**
     * The rows' heights when the fleet fits in [avail] dp (the dividers
     * between them taken off first). Idle rows keep their minimum and the
     * printing rows share everything else, so a running print's ring grows
     * with the tile instead of every row getting an equal strip; with no
     * print running the rows share alike and still fill the tile.
     */
    private fun rowHeights(printers: List<WidgetPrinter>, t: Type, avail: Float): List<Float> {
        val usable = avail - (printers.size - 1)
        val active = printers.count { it.isActive }
        if (active == 0) return List(printers.size) { usable / printers.size }
        val idle      = printers.filter { !it.isActive }.sumOf { rowMin(it, t).toDouble() }.toFloat()
        val perActive = ((usable - idle) / active).coerceAtLeast(t.rowMin.value + 24f)
        return printers.map { if (it.isActive) perActive else rowMin(it, t) }
    }

    /** A hairline between fleet rows, so the spacing reads as deliberate. */
    @Composable
    private fun Divider() {
        Box(modifier = GlanceModifier.fillMaxWidth().height(1.dp).background(ColorProvider(TRACK))) {}
    }

    /**
     * One fleet row. [rowDp] is the height the row has (shared height when the
     * fleet fits, else the row minimum) and sizes the printing block's ring;
     * [widthDp] is the tile's width, which budgets the name.
     */
    @Composable
    private fun PrinterRow(p: WidgetPrinter, stale: Boolean, detail: Boolean, t: Type, strings: WidgetStrings, rowDp: Float, widthDp: Float, onClick: Action, modifier: GlanceModifier) {
        if (p.isActive) {
            PrintingBlock(p, stale, t, strings, rowDp, widthDp, onClick, modifier)
            return
        }
        // Not printing: the shared heading, "<name> | Status: Ready", on the
        // left. A powered-on printer keeps its temperatures on the right of
        // the same line (under it, right-aligned, on a tile too narrow for
        // both); a powered-off one shows the heading alone - its 0° / 0°
        // would say nothing. The content is centred in the row's band rather
        // than pinned to its top.
        val sameLine = p.showsTemps && detail
        val reserved = if (sameLine) inlineDp(p, t.name.value) + 12f else 0f
        Box(
            modifier = modifier.padding(vertical = t.gap).clickable(onClick),
            contentAlignment = Alignment.CenterStart,
        ) {
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Heading(p, stale, t, strings, nameChars(p, t, strings, widthDp, reserved))
                    if (sameLine) {
                        Spacer(GlanceModifier.defaultWeight())
                        TempsInline(p, t.name, GlanceTheme.colors.onSurface)
                    }
                }
                if (p.showsTemps && !sameLine) {
                    Spacer(GlanceModifier.height(2.dp))
                    Row(modifier = GlanceModifier.fillMaxWidth()) {
                        Spacer(GlanceModifier.defaultWeight())
                        TempsInline(p, t.name, GlanceTheme.colors.onSurface)
                    }
                }
            }
        }
    }

    /**
     * The temperatures on one line, each sensor's icon before its value
     * (the same drawables and red-when-hot tint as the printing block's
     * columns): "[nozzle] 25°  [radiator] 26°  [fan] 25°", chamber only when
     * sensed. [size] sizes the values; the icons follow it.
     */
    @Composable
    private fun TempsInline(p: WidgetPrinter, size: TextUnit, color: ColorProvider) {
        val iconDp = (size.value * 1.15f).dp
        Row(verticalAlignment = Alignment.CenterVertically) {
            tempColumns(p).forEachIndexed { i, c ->
                if (i > 0) Spacer(GlanceModifier.width(8.dp))
                Image(
                    provider           = ImageProvider(c.icon),
                    contentDescription = null,
                    colorFilter        = ColorFilter.tint(if (c.hot) ColorProvider(RED) else color),
                    modifier           = GlanceModifier.size(iconDp),
                )
                Spacer(GlanceModifier.width(2.dp))
                Text(c.value, style = TextStyle(color = color, fontSize = size, fontWeight = FontWeight.Medium), maxLines = 1)
            }
        }
    }

    /** The width (dp) [TempsInline] takes at [sp]: icons, gaps and values. */
    private fun inlineDp(p: WidgetPrinter, sp: Float): Float {
        var w = 0f
        tempColumns(p).forEachIndexed { i, c ->
            if (i > 0) w += 8f
            w += sp * 1.15f + 2f + estWidth(c.value, sp)
        }
        return w
    }

    /**
     * The heading every row shares, whatever the state: "<name> | Status:
     * <state word>" - the name bold at the heading size, then the localised
     * "Status" label and the state word in its colour at the body size.
     * Glance cannot ellipsize, so the name is cut to [maxChars] with an
     * ellipsis when it would push the rest off the line.
     */
    @Composable
    private fun Heading(p: WidgetPrinter, stale: Boolean, t: Type, strings: WidgetStrings, maxChars: Int) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(fitName(p.name, maxChars), style = title(t.heading), maxLines = 1)
            Text(statusLabel(strings), style = secondary(t.body), maxLines = 1)
            Text(p.stateLabel, style = stateStyle(p, stale, t.body), maxLines = 1)
        }
    }

    private fun statusLabel(strings: WidgetStrings): String = " | ${strings.status}: "

    /**
     * How many characters of the name fit on the heading line: the tile's
     * width less the card padding, the status label and state word, and
     * [reservedDp] (the temperatures when they share the line), at the
     * heading type's average glyph width. Never fewer than four.
     */
    private fun nameChars(p: WidgetPrinter, t: Type, strings: WidgetStrings, widthDp: Float, reservedDp: Float): Int {
        val fixed = estWidth(statusLabel(strings) + p.stateLabel, t.body.value) + reservedDp
        val room  = widthDp - 24f - fixed
        return (room / (t.heading.value * 0.6f)).toInt().coerceAtLeast(4)
    }

    /**
     * A rough text width in dp, by glyph class: emoji and symbols wide,
     * capitals and digits a little over half an em, spaces narrow, the rest
     * about half. Deliberately close rather than generous - it only guards the
     * name against gross overflow, so an ordinary name must never be cut.
     */
    private fun estWidth(text: String, sp: Float): Float {
        var w = 0f
        var i = 0
        while (i < text.length) {
            val cp = text.codePointAt(i)
            w += sp * when {
                cp > 0x2000                 -> 1.15f
                cp == ' '.code              -> 0.28f
                Character.isDigit(cp)       -> 0.56f
                Character.isUpperCase(cp)   -> 0.65f
                else                        -> 0.5f
            }
            i += Character.charCount(cp)
        }
        return w
    }

    /** [name] whole when it fits in [max] characters, else cut with an ellipsis. */
    private fun fitName(name: String, max: Int): String =
        if (name.length <= max) name else name.take((max - 1).coerceAtLeast(1)) + "\u2026"

    /**
     * Paul's printing block, as he approved it: one band, left to right.
     * LEFT, the progress ring - the dominant element, LARGE, the percent
     * centred inside, spanning the block's height. MIDDLE (taking the slack),
     * three short lines vertically centred against the ring: the printer name
     * on a line of its own (bold, so an ordinary name never clips), "<Status>:
     * <state word>" under it, then "~20m · 🏁10:04 PM" (time left and finish
     * clock). RIGHT, one tall column per temperature sensor, each the sensor's
     * icon (nozzle, radiator, boxed fan; the nozzle and radiator red while
     * that heater is hot, Dart's call) over a LARGE value (sized with the
     * ring's percent): hotend, bed, and chamber only when the printer reports
     * one, a hairline between them. On
     * a tile too narrow for them all the chamber column goes first, then the
     * bed, the hotend always stays - never an overflow. No progress bar (the
     * ring already shows the percent) and no file line. The ring takes the
     * row's whole inner height (the fleet layout hands printing rows the idle
     * rows' slack for exactly this), capped by a third of the width so the
     * name keeps room. Paused prints use the same block in the paused colour;
     * a print still heating shows the ring at 0 % with "Heating" as its state.
     */
    @Composable
    private fun PrintingBlock(p: WidgetPrinter, stale: Boolean, t: Type, strings: WidgetStrings, rowDp: Float, widthDp: Float, onClick: Action, modifier: GlanceModifier) {
        val inner    = rowDp - 2f * t.gap.value
        // The ring spans the band: the whole inner height, up to 150 dp and
        // never more than a third of the width.
        val ringDp   = inner.coerceIn(40f, 150f).coerceAtMost(widthDp * 0.36f)
        val ringFont = (ringDp / 3.2f).coerceIn(12f, 38f)
        val showEnd  = widthDp >= DETAIL_MIN_WIDTH.value
        // The temperature value, a touch under the ring's percent, never
        // below the name size.
        val valueSp  = (ringFont * 0.78f).coerceIn(t.name.value, 30f)
        // Which columns fit: all that apply, the chamber dropped first, then
        // the bed, so the name keeps about eight characters of its line.
        val all      = tempColumns(p)
        val fixed    = 24f + ringDp + 12f + 8f * t.heading.value * 0.55f
        var columns  = all
        while (columns.size > 1 && fixed + columnsDp(columns, valueSp, t) > widthDp) {
            columns = columns.dropLast(1)
        }
        val room     = widthDp - fixed - columnsDp(columns, valueSp, t) + 8f * t.heading.value * 0.55f
        val maxChars = (room / (t.heading.value * 0.55f)).toInt().coerceAtLeast(4)
        Row(
            modifier = modifier.padding(vertical = t.gap).clickable(onClick),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Ring(p, stale, ringDp.dp, (ringDp / 10f).dp, ringFont.sp)
            Spacer(GlanceModifier.width(12.dp))
            Column(modifier = GlanceModifier.defaultWeight(), verticalAlignment = Alignment.CenterVertically) {
                Text(fitName(p.name, maxChars), style = title(t.heading), maxLines = 1)
                Spacer(GlanceModifier.height(2.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("${strings.status}: ", style = secondary(t.body), maxLines = 1)
                    Text(p.stateLabel, style = stateStyle(p, stale, t.body), maxLines = 1)
                }
                val time = timeLine(p, showEnd)
                if (time != null) {
                    Spacer(GlanceModifier.height(2.dp))
                    Text(time, style = secondary(t.body), maxLines = 1)
                }
            }
            columns.forEachIndexed { i, c ->
                if (i == 0) {
                    Spacer(GlanceModifier.width(10.dp))
                } else {
                    Spacer(GlanceModifier.width(8.dp))
                    VerticalRule((ringDp * 0.55f).dp)
                    Spacer(GlanceModifier.width(8.dp))
                }
                TempColumn(c, t, valueSp.sp)
            }
        }
    }

    /** One temperature column: the sensor's icon, its value, and whether the icon reads red. */
    private data class TempCol(val icon: Int, val value: String, val hot: Boolean)

    /** The sensors a printing block shows, in drop order reversed: hotend, bed, then chamber only when sensed. */
    private fun tempColumns(p: WidgetPrinter): List<TempCol> {
        val cols = mutableListOf(
            TempCol(R.drawable.ic_widget_nozzle,   "${p.hotend.toInt()}°", p.hotendHot),
            TempCol(R.drawable.ic_widget_radiator, "${p.bed.toInt()}°",    p.bedHot),
        )
        // The chamber is never coloured by heat.
        if (p.chamber > 0f) cols.add(TempCol(R.drawable.ic_widget_chamber_fan, "${p.chamber.toInt()}°", false))
        return cols
    }

    /** The width (dp) the temperature columns take, gaps and rules included. */
    private fun columnsDp(columns: List<TempCol>, valueSp: Float, t: Type): Float {
        var w = 10f
        columns.forEachIndexed { i, c ->
            if (i > 0) w += 17f
            w += maxOf(estWidth(c.value, valueSp), t.name.value * 1.3f)
        }
        return w
    }

    /**
     * One temperature: the sensor's icon over its value, large, centred
     * against the ring. The icon is a tinted vector: red while the heater is
     * hot, the text colour otherwise (and always for the chamber).
     */
    @Composable
    private fun TempColumn(c: TempCol, t: Type, valueSize: TextUnit) {
        val tint   = if (c.hot) ColorProvider(RED) else GlanceTheme.colors.onSurface
        val iconDp = (t.name.value * 1.3f).dp
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalAlignment   = Alignment.CenterVertically,
        ) {
            Image(
                provider           = ImageProvider(c.icon),
                contentDescription = null,
                colorFilter        = ColorFilter.tint(tint),
                modifier           = GlanceModifier.size(iconDp),
            )
            Spacer(GlanceModifier.height(2.dp))
            Text(c.value, style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = valueSize, fontWeight = FontWeight.Bold), maxLines = 1)
        }
    }

    /** A hairline between the temperature columns. */
    @Composable
    private fun VerticalRule(height: Dp) {
        Box(modifier = GlanceModifier.width(1.dp).height(height).background(ColorProvider(TRACK))) {}
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
