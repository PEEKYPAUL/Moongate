#!/usr/bin/env python3
"""v0.6.24 regression test: the one-tap update must only be advertised where
Moonraker's update manager actually manages a "moongate" client.

0.6.16 hardcoded plugin_can_self_update = True, so a manual install
(docs/third-party-printers.md - no [update_manager moongate] section, and on
COSMOS no update_manager component at all) showed the app an "Update now"
button whose background POST died quietly on the printer and whose badge
never cleared (field report: an Elegoo Centauri Carbon, 2026-08-14).

The decision now lives in the pure module-level _self_update_decision(),
fed by a real /machine/update/status answer; each branch of its matrix is
what this suite pins. True/False are definitive and cached for the process
lifetime; None means "Moonraker wasn't ready, probe again later" - so the
startup races must map to None, never to a cached wrong answer.

Stdlib-only on purpose, same loader as test_lan_only_no_deps.py:

    python3 klipper-plugin/tests/test_self_update_gate.py
"""

import importlib.util
import json
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


mod    = _load("moongate_self_update_gate")
decide = mod._self_update_decision

PASS = 0
FAIL = 0


def check(label, got, want):
    global PASS, FAIL
    if got is want:
        PASS += 1
        print(f"  ok: {label}")
    else:
        FAIL += 1
        print(f"FAIL: {label}: got {got!r}, want {want!r}")


def body(version_info):
    return json.dumps({"result": {"version_info": version_info}})


# ── Definitive answers (cacheable) ──────────────────────────────────────────

# The installer-written world: update_manager manages moongate alongside the
# usual system/moonraker/klipper entries.
check("managed install -> True",
      decide(200, body({"system": {}, "moonraker": {}, "klipper": {},
                        "moongate": {"version": "v0.6.23"}})),
      True)

# update_manager runs but nobody registered moongate (manual copy on a
# normal Pi, or the section was removed).
check("update_manager without moongate -> False",
      decide(200, body({"system": {}, "moonraker": {}, "klipper": {}})),
      False)

# No update_manager component at all (COSMOS): Moonraker 404s the route.
check("no update_manager component (404) -> False",
      decide(404, b"Not Found"),
      False)

# ── Indeterminate answers (must NOT cache a guess) ──────────────────────────

# Moonraker still starting: 503 from our own startup guard, or tornado's
# transport-error pseudo-status.
check("startup 503 -> None",          decide(503, b""),        None)
check("transport error (599) -> None", decide(599, b""),       None)
check("no status at all -> None",      decide(None, b""),      None)

# The COSMOS startup race: a file-serving Moonraker answers 200 with the web
# UI's HTML for a moment before the API routes register.
check("200 with HTML body -> None",
      decide(200, b"<!DOCTYPE html><html>...</html>"),
      None)

# 200 with JSON that isn't update-manager shaped.
check("200 with JSON list -> None",    decide(200, b"[1, 2]"), None)
check("200 without version_info -> None",
      decide(200, json.dumps({"result": {"busy": False}})),
      None)
check("200 with non-dict version_info -> None",
      decide(200, json.dumps({"result": {"version_info": None}})),
      None)

print(f"\n{PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
