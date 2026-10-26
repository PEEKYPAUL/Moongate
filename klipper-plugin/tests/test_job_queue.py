#!/usr/bin/env python3
"""v0.6.31: /status carries `job_queue`, Moonraker's print queue folded into
the one authenticated call so the app's tile and status card can show "Up
next" without a second request over the tunnel. build_job_queue() shapes
Moonraker's /server/job_queue/status answer plus the [job_queue]
automatic_transition flag; it never raises on a bad answer.

Stdlib-only, same harness as test_filaments.py:

    python3 klipper-plugin/tests/test_job_queue.py
"""

import importlib.util
import sys
from pathlib import Path

PLUGIN_PATH = Path(__file__).resolve().parents[1] / "moongate_standalone.py"


def _load(name="moongate_job_queue_under_test"):
    spec = importlib.util.spec_from_file_location(name, PLUGIN_PATH)
    mod  = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    try:
        spec.loader.exec_module(mod)
    except BaseException:
        del sys.modules[name]
        raise
    return mod


MOONRAKER = {
    "queued_jobs": [
        {"filename": "Cable_clip_x6.gcode", "job_id": "000001",
         "time_added": 1761480000.5, "time_in_queue": 120.25},
        {"filename": "sub/Spool_holder.gcode", "job_id": "000002",
         "time_added": 1761480100.0, "time_in_queue": 20.0},
    ],
    "queue_state": "paused",
}


def test_shape(mod):
    out = mod.build_job_queue(MOONRAKER, automatic=False)
    assert out == {
        "state": "paused",
        "automatic_transition": False,
        "count": 2,
        "jobs": [
            {"job_id": "000001", "filename": "Cable_clip_x6.gcode",
             "time_added": 1761480000.5},
            {"job_id": "000002", "filename": "sub/Spool_holder.gcode",
             "time_added": 1761480100.0},
        ],
    }


def test_empty_and_ready(mod):
    out = mod.build_job_queue({"queued_jobs": [], "queue_state": "ready"},
                              automatic=True)
    assert out["state"] == "ready" and out["jobs"] == [] and out["count"] == 0
    assert out["automatic_transition"] is True


def test_caps_the_list_but_keeps_the_count(mod):
    jobs = [{"filename": f"f{i}.gcode", "job_id": f"{i:06d}", "time_added": i}
            for i in range(25)]
    out = mod.build_job_queue({"queued_jobs": jobs, "queue_state": "ready"},
                              automatic=False)
    assert out["count"] == 25
    assert len(out["jobs"]) == mod.JOB_QUEUE_FOLD_LIMIT
    assert out["jobs"][0]["job_id"] == "000000"


def test_garbage_is_none(mod):
    assert mod.build_job_queue(None, automatic=False) is None
    assert mod.build_job_queue("nope", automatic=False) is None
    assert mod.build_job_queue({}, automatic=False) is None
    # Half-broken entries are skipped, not fatal.
    out = mod.build_job_queue(
        {"queued_jobs": [{"filename": "a.gcode"}, "x", {"job_id": "1"},
                         {"filename": "b.gcode", "job_id": "2"}],
         "queue_state": "loading"}, automatic=None)
    assert [j["job_id"] for j in out["jobs"]] == ["2"]
    assert out["count"] == 1 and out["state"] == "loading"
    assert out["automatic_transition"] is None


if __name__ == "__main__":
    m = _load()
    test_shape(m)
    test_empty_and_ready(m)
    test_caps_the_list_but_keeps_the_count(m)
    test_garbage_is_none(m)
    print("test_job_queue: all passed")
