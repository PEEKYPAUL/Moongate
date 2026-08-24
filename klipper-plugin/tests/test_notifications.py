#!/usr/bin/env python3
"""v0.6.25 regression tests: machine-error push + MOONGATE_NOTIFY text.

The field report behind the feature (2026-08-24, Discord): a printer errored
out, mobileraker notified, Moongate stayed silent. The old watcher only saw
print_stats transitions, and a real Klipper error/shutdown knocks out the
print_stats query itself - blind exactly when it matters. The fix watches
klippy_state (via /server/info, which keeps answering) alongside.

Three pure functions carry the behaviour and are pinned here:
  - PrintEventWatcher._klippy_event_for: the transition -> event matrix
  - _error_detail: shutdown reason -> one clean push line
  - _notify_text: MOONGATE_NOTIFY MSG -> sanitised, capped text

Stdlib-only on purpose, same loader as test_lan_only_no_deps.py:

    python3 klipper-plugin/tests/test_notifications.py
"""

import importlib.util
import sys
from pathlib import Path

PLUGIN_PATH = Path(__file__).resolve().parents[1] / "moongate_standalone.py"


def _load(name):
    spec = importlib.util.spec_from_file_location(name, PLUGIN_PATH)
    mod  = importlib.util.module_from_spec(spec)
    # Register before exec: @dataclass looks its module up in sys.modules.
    sys.modules[name] = mod
    try:
        spec.loader.exec_module(mod)
    except BaseException:
        del sys.modules[name]
        raise
    return mod


mod    = _load("moongate_notifications")
kevent = mod.PrintEventWatcher._klippy_event_for

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


# ── _klippy_event_for: the transition matrix ────────────────────────────────

# Baseline: never alert for the state the printer was already in at load -
# a plugin update on an already-dead printer must not fire a stale alert.
check("baseline into shutdown -> no event", kevent(None, "shutdown"), None)
check("baseline into ready -> no event",    kevent(None, "ready"),    None)

# Arrival in an error state fires, whatever healthy state preceded it.
check("ready -> shutdown fires",        kevent("ready", "shutdown"),        "error")
check("ready -> error fires",           kevent("ready", "error"),           "error")
check("printing -> shutdown fires",     kevent("printing", "shutdown"),     "error")
check("startup -> error fires",         kevent("startup", "error"),         "error")
check("disconnected -> shutdown fires", kevent("disconnected", "shutdown"), "error")

# Shuffles between the two error states never refire - one alert per disaster.
check("shutdown -> error silent", kevent("shutdown", "error"),    None)
check("error -> shutdown silent", kevent("error", "shutdown"),    None)

# Recovery and healthy churn are silent in v1.
check("shutdown -> ready silent",   kevent("shutdown", "ready"),   None)
check("ready -> startup silent",    kevent("ready", "startup"),    None)
check("startup -> ready silent",    kevent("startup", "ready"),    None)
check("ready -> disconnected silent", kevent("ready", "disconnected"), None)

# ── _error_detail: shutdown reason -> one push line ─────────────────────────

klipper_msg = ("Heater extruder not heating at expected rate\n"
               "See the 'verify_heater' section in docs/Config_Reference.md\n"
               "Once the underlying issue is corrected, use the\n"
               "FIRMWARE_RESTART command to reset the firmware...")
check("multi-line reason -> first line",
      mod._error_detail(klipper_msg),
      "Heater extruder not heating at expected rate")
check("leading blank lines skipped",
      mod._error_detail("\n\n  MCU 'mcu' shutdown: Timer too close\nrest"),
      "MCU 'mcu' shutdown: Timer too close")
check("empty reason -> empty", mod._error_detail(""),   "")
check("None reason -> empty",  mod._error_detail(None), "")
check("long first line capped at 180",
      len(mod._error_detail("x" * 500)), 180)
check("control chars scrubbed",
      mod._error_detail("bad\x07bell\x1b[31m line"),
      "bad bell [31m line")

# ── _notify_text: MOONGATE_NOTIFY MSG sanitiser ─────────────────────────────

check("plain text passes", mod._notify_text("Spool nearly empty"),
      "Spool nearly empty")
check("whitespace collapses",
      mod._notify_text("  filament   \n  swap\ttime  "),
      "filament swap time")
check("control chars stripped then collapsed",
      mod._notify_text("ding\x00\x01dong"), "ding dong")
check("empty stays empty",     mod._notify_text(""),   "")
check("None stays empty",      mod._notify_text(None), "")
check("capped at 200", len(mod._notify_text("y" * 300)), 200)
check("non-string input coerced", mod._notify_text(42), "42")

print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
