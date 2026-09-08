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
  - _next_notify + MoongatePlugin._klipper_notify (v0.6.26): the
    /status `last_notify` record the Android app polls for

Stdlib-only on purpose, same loader as test_lan_only_no_deps.py:

    python3 klipper-plugin/tests/test_notifications.py
"""

import asyncio
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
pevent = mod.PrintEventWatcher._event_for

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

# ── _event_for: the paused addition (v0.6.25) ───────────────────────────────

# A pause wants eyes on it whether a filament-runout macro or a human caused
# it; a resume is not a fresh start; cancelled stays deliberately silent.
check("printing -> paused fires",   pevent("printing", "paused"),    "paused")
check("paused -> printing silent (resume)", pevent("paused", "printing"), None)
check("baseline into paused silent", pevent(None, "paused"),         None)
check("printing -> cancelled silent", pevent("printing", "cancelled"), None)
check("paused -> complete still completes", pevent("paused", "complete"), "completed")
check("standby -> printing still starts", pevent("standby", "printing"), "started")

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

# ── v0.6.26: /status `last_notify` - the Android pickup ─────────────────────
#
# Android has no push path, so the app's foreground notification service
# polls /status and alerts on a seq INCREASE while it watches. The plugin
# records every accepted message there BEFORE trying the push, in every mode.

nxt = mod._next_notify

first = nxt(None, "Spool nearly empty", 1_700_000_000)
check("first record starts at seq 1", first,
      {"seq": 1, "ts": 1_700_000_000, "text": "Spool nearly empty"})
check("seq climbs by one", nxt(first, "next", 1_700_000_005)["seq"], 2)
check("seq continues from any prior",
      nxt({"seq": 7, "ts": 0, "text": "x"}, "y", 1)["seq"], 8)


class _FakeKlippy:
    def __init__(self):
        self.lines = []

    async def run_gcode(self, script):
        self.lines.append(script)


class _FakeServer:
    def __init__(self, klippy):
        self._klippy = klippy

    def lookup_component(self, name):
        assert name == "klippy_apis"
        return self._klippy


class _FakeWatcher:
    def __init__(self, ok):
        self.ok    = ok
        self.sends = []

    def _send_event(self, event, detail):
        self.sends.append((event, detail))
        return self.ok


class _Stub:
    """Just the attributes _klipper_notify touches - the method is called
    unbound with this object as self, so no Moonraker is needed."""
    def __init__(self, watcher, lan_only=False):
        self.klippy       = _FakeKlippy()
        self.server       = _FakeServer(self.klippy)
        self.watcher      = watcher
        self.lan_only     = lan_only
        self._notify_last = None
        self._last_notify = None


def _notify(stub, msg):
    asyncio.run(mod.MoongatePlugin._klipper_notify(stub, msg))
    return stub.klippy.lines[-1] if stub.klippy.lines else ""


# Cloud mode, push accepted: recorded AND pushed, console says sent.
cloud = _Stub(_FakeWatcher(ok=True))
ack = _notify(cloud, "Print 1 of 3 done")
check("cloud: recorded seq 1", cloud._last_notify["seq"], 1)
check("cloud: recorded text",  cloud._last_notify["text"], "Print 1 of 3 done")
check("cloud: pushed as custom", cloud.watcher.sends, [("custom", "Print 1 of 3 done")])
check("cloud: ack says sent", "notification sent" in ack, True)

# Rate limit: a second message inside 10 s is dropped everywhere - no new
# record (the app would otherwise buzz for a message the push never carried).
ack = _notify(cloud, "again")
check("rate-limited: ack says skipped", "skipped" in ack, True)
check("rate-limited: record unchanged", cloud._last_notify["seq"], 1)
check("rate-limited: nothing pushed", len(cloud.watcher.sends), 1)

# Limit window over: seq climbs.
cloud._notify_last = None
_notify(cloud, "third")
check("after the window: seq 2", cloud._last_notify["seq"], 2)
check("after the window: text follows", cloud._last_notify["text"], "third")

# Empty MSG: nothing recorded, nothing pushed, the usage hint instead.
empty = _Stub(_FakeWatcher(ok=True))
ack = _notify(empty, "   ")
check("empty: not recorded", empty._last_notify, None)
check("empty: not pushed",   empty.watcher.sends, [])
check("empty: usage hint",   'MSG="your text"' in ack, True)

# Push refused server-side: the record still lands (Android pickup) and the
# console says so instead of a bare failure.
refused = _Stub(_FakeWatcher(ok=False))
ack = _notify(refused, "hello")
check("push failed: still recorded", refused._last_notify["seq"], 1)
check("push failed: ack honest",     "NOT sent" in ack and "Android" in ack, True)

# Cloud machinery missing (deps), not LAN-only: recorded for the app, no push.
nocloud = _Stub(None, lan_only=False)
ack = _notify(nocloud, "hello")
check("no cloud: recorded",     nocloud._last_notify["seq"], 1)
check("no cloud: ack names the Android pickup", "Android" in ack, True)

# LAN-only (Direct mode): recorded in /status, but the ack must NOT promise an
# alert - the app's Android service skips lanOnly printers today.
lan = _Stub(None, lan_only=True)
ack = _notify(lan, "hello")
check("lan-only: recorded",       lan._last_notify["seq"], 1)
check("lan-only: ack says LAN-only", "LAN-only" in ack, True)
check("lan-only: no Android promise", "Android" in ack, False)

print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
