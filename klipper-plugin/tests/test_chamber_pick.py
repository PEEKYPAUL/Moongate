#!/usr/bin/env python3
"""v0.6.30: which sensor is "the chamber". pick_chamber_key() is the default
rule (the object named exactly "chamber" wins, else the first temperature
object whose name contains "chamber"), the same rule the app applies, so LAN
and tunnel agree. The app can override it per printer through
/status?chamber=<object>; _apply_chamber_choice() only accepts an object the
printer really lists and "auto" clears it.

Stdlib-only, same harness as test_filaments.py:

    python3 klipper-plugin/tests/test_chamber_pick.py
"""

import importlib.util
import sys
from pathlib import Path

PLUGIN_PATH = Path(__file__).resolve().parents[1] / "moongate_standalone.py"


def _load(name="moongate_chamber_under_test"):
    spec = importlib.util.spec_from_file_location(name, PLUGIN_PATH)
    mod  = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    try:
        spec.loader.exec_module(mod)
    except BaseException:
        del sys.modules[name]
        raise
    return mod


# The VT.2197 report (issue raised on Discord, 26/10/2026): four chamber
# sensors, Chamber_Toolhead first in config order, Chamber the one Mainsail's
# panel and the user mean.
VT2197 = [
    "gcode", "toolhead", "extruder", "heater_bed",
    "temperature_fan Bed_Fans",
    "temperature_fan RPi",
    "temperature_sensor Chamber_Toolhead",
    "temperature_sensor BoxTurtle",
    "temperature_sensor Chamber",
    "temperature_sensor Chamber_Low",
    "temperature_sensor Chamber_Mid",
    "temperature_sensor Leviathan",
    "temperature_sensor Nh_Temp",
    "temperature_sensor NightOwl-ERB",
    "mmu",
]


def test_exact_name_wins(mod):
    assert mod.pick_chamber_key(VT2197) == "temperature_sensor Chamber"


def test_exact_name_any_case(mod):
    objs = ["temperature_sensor chamber_rear", "heater_generic CHAMBER"]
    assert mod.pick_chamber_key(objs) == "heater_generic CHAMBER"


def test_first_partial_when_no_exact(mod):
    objs = ["temperature_sensor Chamber_Top", "temperature_sensor Chamber_Low"]
    assert mod.pick_chamber_key(objs) == "temperature_sensor Chamber_Top"


def test_combined_counts(mod):
    objs = ["temperature_sensor Chamber_A", "temperature_combined Chamber"]
    assert mod.pick_chamber_key(objs) == "temperature_combined Chamber"


def test_none_without_chamber(mod):
    objs = ["temperature_sensor Enclosure", "heater_bed", "extruder"]
    assert mod.pick_chamber_key(objs) is None
    assert mod.pick_chamber_key([]) is None


def test_temperature_objects_keeps_order(mod):
    assert mod.temperature_objects(VT2197)[:3] == [
        "temperature_fan Bed_Fans",
        "temperature_fan RPi",
        "temperature_sensor Chamber_Toolhead",
    ]
    assert "mmu" not in mod.temperature_objects(VT2197)
    assert mod.temperature_objects([None, 3, "extruder"]) == []


class _Host:
    """Just the three attributes _apply_chamber_choice touches."""
    def __init__(self, mod, objects):
        self._temp_objects = mod.temperature_objects(objects)
        self._chamber_auto = mod.pick_chamber_key(objects)
        self._chamber_pick = None


def test_choice_accepted_and_cleared(mod):
    h = _Host(mod, VT2197)
    apply = mod.MoongatePlugin._apply_chamber_choice
    key   = mod.MoongatePlugin._chamber_key
    apply(h, "temperature_sensor Chamber_Mid")
    assert h._chamber_pick == "temperature_sensor Chamber_Mid"
    assert key.fget(h) == "temperature_sensor Chamber_Mid"
    apply(h, "auto")
    assert h._chamber_pick is None
    assert key.fget(h) == "temperature_sensor Chamber"


def test_choice_rejects_unknown(mod):
    h = _Host(mod, VT2197)
    apply = mod.MoongatePlugin._apply_chamber_choice
    apply(h, "temperature_sensor Nope")
    apply(h, "heater_bed")          # a real object, but not a temperature one
    apply(h, "extruder&evil=1")
    assert h._chamber_pick is None
    apply(h, None)                  # an app older than v0.9.77 sends nothing
    assert h._chamber_pick is None


def test_choice_survives_other_sensor_not_the_default(mod):
    # Nothing named chamber at all: the picker is the only way to a reading.
    objs = ["temperature_sensor Enclosure", "extruder"]
    h = _Host(mod, objs)
    assert mod.MoongatePlugin._chamber_key.fget(h) is None
    mod.MoongatePlugin._apply_chamber_choice(h, "temperature_sensor Enclosure")
    assert mod.MoongatePlugin._chamber_key.fget(h) == "temperature_sensor Enclosure"


def main() -> int:
    mod = _load()
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t(mod)
            print(f"ok   {t.__name__}")
        except Exception as exc:  # noqa: BLE001 - report every failure
            failed += 1
            print(f"FAIL {t.__name__}: {exc!r}")
    print(f"{len(tests) - failed}/{len(tests)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
