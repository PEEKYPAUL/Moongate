#!/usr/bin/env python3
"""v0.6.29: /status carries `filaments`, one entry per TOOL with the filament
the printer says is loaded for it, so the app's G-code viewer can repaint a
multi-material file in what is really in the gates (its Colour view's
Sliced / Loaded switch). Two sources, folded by build_filaments():

  * Happy Hare: the `mmu` object's per-gate lists, tool -> gate via ttg_map.
  * AFC: one "AFC_lane <name>" object per lane, tool from its `map` ("T1").

Stdlib-only, same harness as test_lan_only_no_deps.py:

    python3 klipper-plugin/tests/test_filaments.py
"""

import importlib.util
import sys
from pathlib import Path

PLUGIN_PATH = Path(__file__).resolve().parents[1] / "moongate_standalone.py"


def _load(name="moongate_filaments_under_test"):
    spec = importlib.util.spec_from_file_location(name, PLUGIN_PATH)
    mod  = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    try:
        spec.loader.exec_module(mod)
    except BaseException:
        del sys.modules[name]
        raise
    return mod


def test_happy_hare(mod):
    # A 4-gate ERCF: T0 -> gate 0, T1 -> gate 1, T2 -> gate 3 (remapped),
    # T3 -> gate 2 which is EMPTY; gate 3 has an unknown status (-1) and a
    # colour given as a hex name because the user typed one.
    status = {
        "mmu": {
            "ttg_map":        [0, 1, 3, 2],
            "gate_color_rgb": [(0.62, 0.79, 0.88), (0.84, 0.15, 0.16), (0.0, 0.0, 0.0), []],
            "gate_color":     ["lightblue", "red", "", "00FF00"],
            "gate_material":  ["PLA+", "PETG", "", "PLA"],
            "gate_name":      ["Esun PLA+", "Red PETG", "", "Green"],
            "gate_status":    [1, 2, 0, -1],
            "tool": 0,
        },
        "print_stats": {"state": "standby"},
    }
    f = mod.build_filaments(status)
    assert [e["tool"] for e in f] == [0, 1, 2, 3], f
    assert f[0] == {"tool": 0, "slot": "gate 0", "color": "#9EC9E0", "material": "PLA+",
                    "name": "Esun PLA+", "loaded": True}, f[0]
    assert f[1]["color"] == "#D62629" and f[1]["loaded"] is True
    # T2 -> gate 3: no rgb entry, falls back to the hex in gate_color; -1 = present.
    assert f[2] == {"tool": 2, "slot": "gate 3", "color": "#00FF00", "material": "PLA",
                    "name": "Green", "loaded": True}, f[2]
    # T3 -> gate 2: empty gate, empty strings become None.
    assert f[3] == {"tool": 3, "slot": "gate 2", "color": "#000000", "material": None,
                    "name": None, "loaded": False}, f[3]


def test_afc(mod):
    status = {
        "AFC": {"lanes": ["lane1", "lane2", "lane3"], "current_load": "lane2"},
        "AFC_lane lane1": {"map": "T0", "color": "#FF0000", "material": "PLA",
                           "filament_name": "Polymaker Red", "prep": True, "load": True,
                           "tool_loaded": False, "spool_id": 12},
        "AFC_lane lane2": {"map": "T1", "color": "ffffff", "material": "ABS",
                           "filament_name": "", "prep": True, "load": True, "tool_loaded": True},
        "AFC_lane lane3": {"map": "T2", "color": "", "material": "", "filament_name": "",
                           "prep": False, "load": False, "tool_loaded": False},
        "AFC_stepper lane9": {"map": "T5", "color": "#123456", "material": "PETG",
                              "prep": True, "load": False, "tool_loaded": False},
        "AFC_lane odd": {"map": "custom", "color": "#000000"},  # not a Tn map: skipped
        "heater_bed": {"temperature": 25.0},
    }
    f = mod.build_filaments(status)
    assert [e["tool"] for e in f] == [0, 1, 2, 5], f
    assert f[0] == {"tool": 0, "slot": "lane1", "color": "#FF0000", "material": "PLA",
                    "name": "Polymaker Red", "loaded": True}, f[0]
    assert f[1]["color"] == "#FFFFFF" and f[1]["name"] is None and f[1]["loaded"] is True
    assert f[2] == {"tool": 2, "slot": "lane3", "color": None, "material": None,
                    "name": None, "loaded": False}, f[2]
    assert f[3]["slot"] == "lane9" and f[3]["loaded"] is True  # prep alone counts


def test_neither_and_garbage(mod):
    assert mod.build_filaments({}) == []
    assert mod.build_filaments({"print_stats": {}, "extruder": {}}) == []
    assert mod.build_filaments({"mmu": "not a dict"}) == []
    assert mod.build_filaments({"mmu": {"ttg_map": "nope"}}) == []
    assert mod.build_filaments({"mmu": {"ttg_map": [0, "x", -1]}}) == [
        {"tool": 0, "slot": "gate 0", "color": None, "material": None, "name": None,
         "loaded": True}]
    assert mod.build_filaments("garbage") == []


def test_colour_helpers(mod):
    assert mod._colour_hex("#ff8800") == "#FF8800"
    assert mod._colour_hex("ff8800ff") == "#FF8800"
    assert mod._colour_hex("red") is None
    assert mod._colour_hex("") is None
    assert mod._colour_hex(None) is None
    assert mod._rgb_hex((1.0, 0.5, 0.0)) == "#FF8000"
    assert mod._rgb_hex([0, 0, 0]) == "#000000"
    assert mod._rgb_hex((2.0, -1.0, 0.5)) == "#FF0080"
    assert mod._rgb_hex("nope") is None and mod._rgb_hex((1.0,)) is None


if __name__ == "__main__":
    m = _load()
    test_happy_hare(m)
    test_afc(m)
    test_neither_and_garbage(m)
    test_colour_helpers(m)
    print("test_filaments: all passed")
