#!/usr/bin/env python3
"""v0.6.27 temperature watches: the pure rules behind MOONGATE_TEMP_NOTIFY
and the app's "preheat and soak first" / "tell me when it's cool enough to
remove" - direction from the reading at arm time, warm-ups judged against the
live target (grace, heaters-off cancel), cool-downs "at or below", the soak
clock, the after-print gate, the alert text, and the macro block install.sh
writes matching the plugin's own copy (the one-tap update appends it).

Stdlib-only, same loader as the other tests:

    python3 klipper-plugin/tests/test_temp_watch.py
"""

import importlib.util
import sys
from pathlib import Path

PLUGIN_PATH  = Path(__file__).resolve().parents[1] / "moongate_standalone.py"
INSTALL_PATH = Path(__file__).resolve().parents[1] / "install.sh"


def _load(name):
    spec = importlib.util.spec_from_file_location(name, PLUGIN_PATH)
    mod  = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    try:
        spec.loader.exec_module(mod)
    except BaseException:
        del sys.modules[name]
        raise
    return mod


mod   = _load("moongate_temp_watch")
new   = mod.temp_watch_new
judge = mod.judge_temp_watch
text  = mod.temp_watch_message
parse = mod.parse_temp_notify_args
reads = mod.temp_watch_readings

PASS = 0
FAIL = 0


def check(label, got, want):
    global PASS, FAIL
    if got == want:
        PASS += 1
        print(f"  ok: {label}")
    else:
        FAIL += 1
        print(f"FAIL: {label}: got {got!r}, want {want!r}")


T0 = 1_700_000_000

# ── readings from a status block ─────────────────────────────────────────────
status = {
    "print_stats": {"state": "standby"},
    "heater_bed":  {"temperature": 24.3, "target": 0.0},
    "extruder":    {"temperature": 25.0, "target": 0.0},
    "extruder1":   {"temperature": 26.0, "target": 0.0},
    "temperature_sensor chamber": {"temperature": 23.1},
    "temperature_sensor mcu": {"temperature": 40.0},
}
r = reads(status, "temperature_sensor chamber")
check("readings: roles", sorted(r), ["bed", "chamber", "extruder", "extruder1"])
check("readings: passive chamber target 0", r["chamber"], (23.1, 0.0))
check("readings: no chamber key = no chamber role", "chamber" in reads(status, None), False)

# ── direction at arm time ────────────────────────────────────────────────────
cold = {"bed": (24.0, 0.0), "chamber": (23.0, 0.0), "extruder": (25.0, 0.0)}
hot  = {"bed": (105.0, 0.0), "chamber": (44.0, 0.0), "extruder": (200.0, 0.0)}
w = new("macro", {"bed": 110, "chamber": 45}, cold, now=T0)
check("arm: cold readings = warm up", w["dirs"], {"bed": "up", "chamber": "up"})
w = new("macro", {"bed": 35, "chamber": 30}, hot, now=T0)
check("arm: hot readings = cool down", w["dirs"], {"bed": "down", "chamber": "down"})
w = new("macro", {"bed": 60}, {}, now=T0)
check("arm: no reading = warm up", w["dirs"], {"bed": "up"})
w = new("app-cool", {"bed": 29, "chamber": 28}, cold, force_dir="down", now=T0)
check("arm: forced down beats cold readings", w["dirs"], {"bed": "down", "chamber": "down"})
w = new("x", {"bed": 0, "mcu": 50, "chamber": 45}, cold, now=T0)
check("arm: zero + unknown roles dropped", w["wait"], {"chamber": 45.0})
w = new("x", {"bed": 60}, cold, soak=99999, now=T0)
check("arm: soak capped", w["soak"], mod.TEMP_WATCH_MAX_SOAK)

# ── warm-up: wait / grace / cancel / fire ────────────────────────────────────
w = new("app-soak", {"bed": 110, "chamber": 45}, cold, force_dir="up", now=T0)
check("warm: SET not landed yet inside grace = wait",
      judge(w, {"bed": (24.0, 0.0), "chamber": (23.0, 0.0)}, "standby", T0 + 10), "wait")
check("warm: target still 0 after grace = cancel",
      judge(w, {"bed": (24.0, 0.0), "chamber": (23.0, 0.0)}, "standby", T0 + 200), "cancel")
w = new("app-soak", {"bed": 110, "chamber": 45}, cold, force_dir="up", now=T0)
check("warm: heating = wait",
      judge(w, {"bed": (80.0, 110.0), "chamber": (30.0, 0.0)}, "standby", T0 + 600), "wait")
check("warm: bed within margin, chamber short = wait",
      judge(w, {"bed": (107.5, 110.0), "chamber": (41.0, 0.0)}, "standby", T0 + 900), "wait")
check("warm: everything within margin, no soak = fire",
      judge(w, {"bed": (107.5, 110.0), "chamber": (42.5, 0.0)}, "standby", T0 + 1200), "fire")
w = new("macro", {"bed": 60}, cold, now=T0)
check("warm: live target wins (PRINT_START retargeted to 110, bed at 61 = still heating)",
      judge(w, {"bed": (61.0, 110.0)}, "printing", T0 + 300), "wait")
check("warm: missing reading = wait", judge(w, {}, "standby", T0 + 300), "wait")
check("warm: stale after 6 h = cancel",
      judge(w, {"bed": (30.0, 60.0)}, "standby", T0 + mod.TEMP_WATCH_STALE_S + 1), "cancel")

# ── soak clock ───────────────────────────────────────────────────────────────
w = new("app-soak", {"bed": 110, "chamber": 45}, cold, soak=20, force_dir="up", now=T0)
at_temp = {"bed": (109.0, 110.0), "chamber": (45.0, 0.0)}
check("soak: reached starts the clock (wait)", judge(w, at_temp, "standby", T0 + 1000), "wait")
check("soak: reached_ts recorded", w["reached_ts"], T0 + 1000)
sag = {"bed": (104.0, 110.0), "chamber": (40.0, 0.0)}
check("soak: a sag does not reset", judge(w, sag, "standby", T0 + 1600), "wait")
check("soak: reached_ts unchanged by the sag", w["reached_ts"], T0 + 1000)
check("soak: clock not up = wait", judge(w, at_temp, "standby", T0 + 1000 + 19 * 60), "wait")
check("soak: clock up = fire", judge(w, at_temp, "standby", T0 + 1000 + 20 * 60 + 5), "fire")
w2 = dict(w)
check("soak: heaters off mid-soak = cancel",
      judge(w2, {"bed": (90.0, 0.0), "chamber": (44.0, 0.0)}, "standby", T0 + 1500), "cancel")
w3 = dict(w)
check("soak: deadline noticed > 1 h late = cancel",
      judge(w3, at_temp, "standby", T0 + 1000 + 20 * 60 + mod.TEMP_WATCH_LATE_S + 1), "cancel")

# ── cool-down (macro from PRINT_END) ─────────────────────────────────────────
w = new("macro", {"bed": 35, "chamber": 30}, hot, now=T0)
check("cool: still hot = wait", judge(w, {"bed": (60.0, 0.0), "chamber": (35.0, 0.0)}, "complete", T0 + 60), "wait")
check("cool: bed there, chamber not = wait", judge(w, {"bed": (34.0, 0.0), "chamber": (31.0, 0.0)}, "complete", T0 + 1800), "wait")
check("cool: both at or below = fire", judge(w, {"bed": (34.0, 0.0), "chamber": (30.0, 0.0)}, "complete", T0 + 2400), "fire")
check("cool: heaters off is normal, never a cancel", judge(new("m", {"bed": 35}, hot, now=T0),
      {"bed": (50.0, 0.0)}, "standby", T0 + 200), "wait")

# ── after-print gate (the app's ready-to-remove watch) ───────────────────────
w = new("app-cool", {"bed": 29, "chamber": 28}, cold, force_dir="down", after_print=True, now=T0)
check("after: idle before the print starts = wait (cold readings ignored)",
      judge(w, {"bed": (24.0, 0.0), "chamber": (23.0, 0.0)}, "standby", T0 + 60), "wait")
check("after: printing = wait, print seen",
      (judge(w, {"bed": (110.0, 110.0), "chamber": (45.0, 0.0)}, "printing", T0 + 4000), w["seen_print"]),
      ("wait", True))
check("after: paused still counts as running",
      judge(w, {"bed": (110.0, 110.0), "chamber": (45.0, 0.0)}, "paused", T0 + 5000), "wait")
end = T0 + 40_000
check("after: print ended, still hot = wait", judge(w, {"bed": (100.0, 0.0), "chamber": (44.0, 0.0)}, "complete", end), "wait")
check("after: judging clock starts at the print end", w["active_ts"], end)
check("after: cooled = fire", judge(w, {"bed": (28.5, 0.0), "chamber": (27.9, 0.0)}, "complete", end + 47 * 60), "fire")
w = new("app-cool", {"bed": 29}, cold, force_dir="down", after_print=True, now=T0)
check("after: no print within 6 h = cancel",
      judge(w, {"bed": (24.0, 0.0)}, "standby", T0 + mod.TEMP_WATCH_STALE_S + 1), "cancel")
w = new("app-cool", {"bed": 29}, cold, force_dir="down", after_print=True, now=T0)
judge(w, {"bed": (110.0, 110.0)}, "printing", T0 + 100)
check("after: the 6 h stale clock does not run during a long print",
      judge(w, {"bed": (110.0, 110.0)}, "printing", T0 + 20 * 3600), "wait")
check("after: a failed print still counts as ended",
      judge(w, {"bed": (100.0, 0.0)}, "error", T0 + 20 * 3600 + 30), "wait")
check("after: ... and cools to a fire", judge(w, {"bed": (28.0, 0.0)}, "error", T0 + 21 * 3600), "fire")

# ── alert text ───────────────────────────────────────────────────────────────
w = new("macro", {"bed": 110, "chamber": 45, "extruder": 250}, cold, now=T0)
check("text: default at-temperature line",
      text(w, {"extruder": (248.0, 250.0), "bed": (109.0, 110.0), "chamber": (45.0, 0.0)}, T0 + 100),
      "At temperature: Hotend 248° · Bed 109° · Chamber 45°")
w = new("macro", {"bed": 110, "chamber": 45}, cold, soak=20, now=T0)
check("text: default soak line",
      text(w, {"bed": (110.0, 110.0), "chamber": (46.0, 0.0)}, T0 + 100),
      "Heat-soak complete: Bed 110° · Chamber 46° · soaked 20 min")
w = new("macro", {"bed": 35, "chamber": 30}, hot, now=T0)
check("text: default cool-down line",
      text(w, {"bed": (34.0, 0.0), "chamber": (30.0, 0.0)}, T0 + 47 * 60 + 10),
      "Cooled down: Bed 34° · Chamber 30° · after 47 min")
w = new("macro", {"bed": 35}, hot, msg="Print cooled - safe to remove", now=T0)
check("text: the macro's own MSG verbatim", text(w, {"bed": (34.0, 0.0)}, T0 + 60), "Print cooled - safe to remove")
w = new("app-soak", {"bed": 110}, cold, msg="Heat-soak complete: Bed {bed} · soaked 20 min", then_start="abs/benchy.gcode", now=T0)
check("text: app placeholders + started outcome appended",
      text(w, {"bed": (110.0, 110.0)}, T0 + 60, started=True),
      "Heat-soak complete: Bed 110° · soaked 20 min · printing benchy.gcode")
check("text: busy printer outcome",
      text(w, {"bed": (110.0, 110.0)}, T0 + 60, started=False),
      "Heat-soak complete: Bed 110° · soaked 20 min · not started, printer busy")
w = new("app-soak", {"bed": 110}, cold, msg="Soak done, {started}", then_start="a.gcode", now=T0)
check("text: {started} placed by the message", text(w, {"bed": (110.0, 110.0)}, T0, started=True), "Soak done, printing a.gcode")
w = new("app-cool", {"bed": 29, "chamber": 28}, cold, msg="Ready to remove: Bed {bed} · Chamber {chamber} · {file} cooled in {mins} min",
        then_start="", force_dir="down", after_print=True, now=T0)
w["active_ts"] = T0 + 1000
check("text: cool-down placeholders incl. mins since the print ended",
      text(w, {"bed": (28.0, 0.0), "chamber": (27.0, 0.0)}, T0 + 1000 + 47 * 60),
      "Ready to remove: Bed 28° · Chamber 27° · cooled in 47 min")

# ── snapshot ─────────────────────────────────────────────────────────────────
w = new("app-soak", {"bed": 110}, cold, soak=20, now=T0)
check("snapshot: no due before reached", mod.temp_watch_snapshot(w)["due_ts"], 0)
w["reached_ts"] = T0 + 500
check("snapshot: due = reached + soak", mod.temp_watch_snapshot(w)["due_ts"], T0 + 500 + 1200)

# ── macro params ─────────────────────────────────────────────────────────────
p = parse("35", "", "30", "15", "Print cooled", "")
check("params: numbers parsed", (p["wait"], p["soak"], p["msg"], p["cancel"]),
      ({"bed": 35.0, "chamber": 30.0}, 15, "Print cooled", False))
p = parse("abc", "-5", "500", "x", "", "1")
check("params: junk ignored, cancel seen", (p["wait"], p["soak"], p["cancel"]), ({}, 0, True))
check("params: CANCEL=0 is not a cancel", parse(cancel="0")["cancel"], False)
check("params: empty = nothing to wait for", parse()["wait"], {})

# ── install.sh carries the plugin's macro text ───────────────────────────────
install = INSTALL_PATH.read_text(encoding="utf-8")
check("install.sh has the MOONGATE_TEMP_NOTIFY block", mod.TEMP_NOTIFY_MACRO_CFG.strip() in install, True)
check("install.sh has the MOONGATE_NOTIFY block", mod.NOTIFY_MACRO_CFG.strip() in install, True)
check("install.sh has the MOONGATE_STATUS block", mod.STATUS_MACRO_CFG.strip() in install, True)

print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
