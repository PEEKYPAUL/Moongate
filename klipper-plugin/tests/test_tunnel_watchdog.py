#!/usr/bin/env python3
"""v0.6.23: the tunnel watchdog. After a SUCCESSFUL heartbeat (the internet
anchor) the plugin probes its own public tunnel URL - the authproxy's 401 is
the healthy answer - and restarts moongate-tunnel when the tunnel alone is
provably dead: transport failures or Cloudflare's tunnel-down 530, never a
delivered response like a 502 (that proves the tunnel works and indicts the
authproxy, which a tunnel restart cannot fix).

These tests pin the pure decision pieces (the probe classifier and the
strike/budget state machine) plus the heartbeat-loop hook, with no network
and no Moonraker.

Stdlib-only, same harness as test_lan_only_no_deps.py:

    python3 klipper-plugin/tests/test_tunnel_watchdog.py
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


MOD = _load("moongate_watchdog_test")


def test_classifier():
    classify = MOD.classify_probe
    # The healthy gate and everything else that was DELIVERED = alive.
    assert classify(401, None) == "alive"   # the expected authproxy answer
    assert classify(502, None) == "alive"   # authproxy down - not our fix
    assert classify(503, None) == "alive"
    assert classify(404, None) == "alive"
    assert classify(200, None) == "alive"
    # Nothing delivered = dead.
    assert classify(530, None)        == "dead"   # Cloudflare error 1033
    assert classify(None, "timeout")  == "dead"
    assert classify(None, "[Errno 111] refused") == "dead"


def test_strikes_to_heal():
    wd  = MOD.TunnelWatchdog()
    now = 1_000_000.0
    gap = wd.PROBE_GAP_SECONDS
    assert wd.note_probe("dead", now)           is None
    assert wd.note_probe("dead", now + gap)     is None
    assert wd.note_probe("dead", now + 2 * gap) == "heal"
    assert wd.heal_count == 1
    assert wd.last_heal  == int(now + 2 * gap)
    assert wd.snapshot() == {
        "heals": 1, "last_heal": int(now + 2 * gap), "state": "ok"}
    # Strikes were consumed by the heal - the next round starts from zero.
    assert wd.note_probe("dead", now + 3 * gap) is None
    assert wd.note_probe("dead", now + 4 * gap) is None
    assert wd.note_probe("dead", now + 5 * gap) == "heal"
    assert wd.heal_count == 2


def test_alive_resets_strikes():
    wd  = MOD.TunnelWatchdog()
    now = 1_000_000.0
    assert wd.note_probe("dead",  now + 0) is None
    assert wd.note_probe("dead",  now + 1) is None
    assert wd.note_probe("alive", now + 2) is None
    # The two strikes are gone - three fresh ones needed again.
    assert wd.note_probe("dead", now + 3) is None
    assert wd.note_probe("dead", now + 4) is None
    assert wd.note_probe("dead", now + 5) == "heal"


def test_probe_gap():
    wd  = MOD.TunnelWatchdog()
    now = 1_000_000.0
    assert wd.should_probe(now)
    wd.note_probe("alive", now)
    assert not wd.should_probe(now + 1)
    assert not wd.should_probe(now + wd.PROBE_GAP_SECONDS - 1)
    assert wd.should_probe(now + wd.PROBE_GAP_SECONDS)


def test_heal_budget_throttles_then_recovers():
    wd  = MOD.TunnelWatchdog()
    now = 1_000_000.0
    t   = now

    def three_strikes():
        nonlocal t
        results = []
        for _ in range(3):
            results.append(wd.note_probe("dead", t))
            t += 60
        return results[-1]

    # Budget's worth of heals...
    for i in range(wd.HEAL_BUDGET):
        assert three_strikes() == "heal", f"heal {i + 1} within budget"
    # ...then the transition to throttled fires exactly once...
    assert three_strikes() == "throttle"
    assert wd.snapshot()["state"] == "throttled"
    # ...and stays quiet (no heal, no repeated throttle) while still dead.
    assert three_strikes() is None
    assert wd.heal_count == wd.HEAL_BUDGET
    # A single alive probe clears the stand-down.
    wd.note_probe("alive", t)
    assert wd.snapshot()["state"] == "ok"
    # Once the rolling window has passed, healing is allowed again.
    t = now + wd.BUDGET_WINDOW_SECONDS + wd.PROBE_GAP_SECONDS * 10
    assert three_strikes() == "heal"
    assert wd.heal_count == wd.HEAL_BUDGET + 1


def test_heartbeat_hook_restarts_once():
    """Three dead probes through the real _check_tunnel_health = exactly one
    restart callback, and a disabled watchdog probes nothing at all."""
    calls  = []
    probes = []

    def fake_probe(url, timeout=6.0):
        probes.append(url)
        return None, "connection timed out"

    original = MOD._probe_tunnel
    MOD._probe_tunnel = fake_probe
    try:
        wd = MOD.TunnelWatchdog()
        wd.PROBE_GAP_SECONDS = 0     # instance override - no waiting in tests
        loop = MOD.HeartbeatLoop(
            device=None, sb=None, interval=300,
            watchdog=wd, restart_tunnel_cb=lambda: calls.append(1))
        for _ in range(3):
            loop._check_tunnel_health("https://x.trycloudflare.com")
        assert len(probes) == 3
        assert len(calls)  == 1, "exactly one restart on the third strike"

        # Watchdog off (None): the hook is a no-op, no probe fired.
        probes.clear()
        loop_off = MOD.HeartbeatLoop(
            device=None, sb=None, interval=300,
            watchdog=None, restart_tunnel_cb=lambda: calls.append(1))
        loop_off._check_tunnel_health("https://x.trycloudflare.com")
        assert probes == []
    finally:
        MOD._probe_tunnel = original


if __name__ == "__main__":
    test_classifier()
    print("PASS classifier: delivered answers alive, transport/530 dead")
    test_strikes_to_heal()
    print("PASS three strikes heal, counters advance, strikes consumed")
    test_alive_resets_strikes()
    print("PASS an alive probe resets the strike count")
    test_probe_gap()
    print("PASS probe gap holds during fast heartbeat cadences")
    test_heal_budget_throttles_then_recovers()
    print("PASS heal budget throttles loudly once, recovers after the window")
    test_heartbeat_hook_restarts_once()
    print("PASS heartbeat hook probes, heals once, and honours the off switch")
    print("All good.")
