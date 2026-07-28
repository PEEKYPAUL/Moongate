#!/usr/bin/env python3
"""v0.6.19 regression test: an OPEN pairing session must keep the heartbeat
awake. The 0.6.15 orphan dormancy had a race: MOONGATE_PAIR's poke lands
before the user has redeemed the new GATE code, the server still answers with
the reset-owner tombstone (410 printer_released), and the loop went dormant
for 6 h right as the freshly-claimed row appeared - so the row never got a
tunnel URL and the app showed the printer offline (field report 2026-07-28).

Stdlib-only on purpose, same loader as test_lan_only_no_deps.py:

    python3 klipper-plugin/tests/test_heartbeat_pair_window.py
"""

import importlib.util
import sys
import time
from pathlib import Path

PLUGIN_PATH = Path(__file__).resolve().parents[1] / "moongate_standalone.py"
BLOCKED     = ("jwt", "cryptography")


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


def _load_blocked(name):
    """Load the plugin with the cloud deps blocked, like an embedded host.
    HeartbeatLoop itself never touches them, so the tests stay deterministic
    whether or not this machine has PyJWT/cryptography installed."""
    for dep in BLOCKED:
        assert dep not in sys.modules or sys.modules[dep] is None, (
            f"{dep} already imported - run this test in its own process")
        sys.modules[dep] = None
    try:
        mod = _load(name)
    finally:
        for dep in BLOCKED:
            del sys.modules[dep]
    # The loop reads the tunnel URL from a module-level helper; give it one so
    # _send_one() always reaches the fake Supabase client below.
    mod._get_tunnel_url = lambda: "https://test.trycloudflare.com"
    return mod


class FakeDevice:
    public_key_b64 = "cGtfdGVzdA=="

    @staticmethod
    def sign_b64(data):
        return "c2lnX3Rlc3Q="


class FakeSb:
    """Duck-typed SupabaseClient: one canned heartbeat answer at a time."""
    def __init__(self):
        self.reply = (204, {})
        self.calls = 0

    def heartbeat(self, pk_b64, tunnel, ts, sig_b64):
        self.calls += 1
        return self.reply


def _make_loop(mod, pending):
    sb    = FakeSb()
    state = {"pending": pending}
    hb    = mod.HeartbeatLoop(
        FakeDevice(), sb, 300,
        pending_pair_cb=lambda: state["pending"],
    )
    return hb, sb, state


def test_410_during_open_pair_stays_awake(mod):
    hb, sb, state = _make_loop(mod, pending=True)
    sb.reply = (410, {"error": "printer_released"})
    hb._send_one()
    assert hb.dormant is False, "410 mid-pair must not dorm"
    assert hb._fast_deadline > time.time(), "fast cadence must stay armed"
    # Code redeemed -> the new live row answers 200 and the loop settles.
    state["pending"] = False
    sb.reply = (204, {})
    hb._send_one()
    assert hb.dormant is False
    assert hb._fast_deadline == 0.0, "accepted heartbeat must end the window"


def test_410_with_no_open_pair_dorms(mod):
    hb, sb, _ = _make_loop(mod, pending=False)
    sb.reply = (410, {"error": "printer_released"})
    hb._send_one()
    assert hb.dormant is True, "410 with no pairing session must still dorm"


def test_410_after_code_expiry_dorms(mod):
    hb, sb, state = _make_loop(mod, pending=True)
    sb.reply = (410, {"error": "printer_released"})
    hb._send_one()
    assert hb.dormant is False
    state["pending"] = False   # the 10-min TTL lapsed, code never redeemed
    hb._send_one()
    assert hb.dormant is True, "expiry must restore the dormancy answer"


def test_404_during_open_pair_rearms_fast(mod):
    hb, sb, _ = _make_loop(mod, pending=True)
    hb._fast_deadline = 0.0    # bootstrap window already lapsed
    sb.reply = (404, {"error": "not_found"})
    hb._send_one()
    assert hb._fast_deadline > time.time(), (
        "404 mid-pair must re-arm the fast window even on a never-healthy Pi")


def test_no_callback_keeps_old_behaviour(mod):
    hb = mod.HeartbeatLoop(FakeDevice(), FakeSb(), 300)
    assert hb._pair_in_flight() is False
    hb2, sb2, _ = _make_loop(mod, pending=False)
    sb2.reply = (410, {"error": "printer_released"})
    hb2._send_one()
    assert hb2.dormant is True


if __name__ == "__main__":
    mod = _load_blocked("moongate_hb_test")
    test_410_during_open_pair_stays_awake(mod)
    print("PASS 410 during an open pairing session stays awake")
    test_410_with_no_open_pair_dorms(mod)
    print("PASS 410 with no pairing session dorms")
    test_410_after_code_expiry_dorms(mod)
    print("PASS 410 after code expiry dorms")
    test_404_during_open_pair_rearms_fast(mod)
    print("PASS 404 during an open pairing session re-arms the fast window")
    test_no_callback_keeps_old_behaviour(mod)
    print("PASS no callback keeps the old behaviour")
    print("All good.")
