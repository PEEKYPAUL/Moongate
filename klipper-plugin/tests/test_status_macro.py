#!/usr/bin/env python3
"""v0.6.23: the MOONGATE_STATUS console macro. Its two live checks (a real
signed heartbeat for the database half, the watchdog's own probe for the
tunnel half) are turned into console wording by two pure functions - this
suite pins that wording matrix, because each branch IS a support answer:
the orphaned row, the released printer, the wrong Pi clock, the dead
tunnel, the dead authproxy behind a working tunnel.

Stdlib-only, same harness as test_lan_only_no_deps.py:

    python3 klipper-plugin/tests/test_status_macro.py
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


MOD = _load("moongate_status_macro_test")


def _joined(lines):
    return " ".join(lines)


def test_db_wording():
    db = MOD.describe_db_check
    # Healthy, with the clock offset surfaced.
    ok = _joined(db(204, {}, 0.3, paired=True))
    assert "OK" in ok and "+0s" in ok
    # 404 splits by local pairing state: gone row vs never paired.
    gone = _joined(db(404, {"error": "not_found"}, 0.1, paired=True))
    assert "GONE" in gone and "MOONGATE_PAIR" in gone
    fresh = _joined(db(404, {"error": "not_found"}, 0.1, paired=False))
    assert "not registered" in fresh and "GONE" not in fresh
    # 410 = the owner's explicit release.
    released = _joined(db(410, {"error": "printer_released"}, None, True))
    assert "released" in released
    # 401 with a big skew = the clock diagnosis, with the fix named.
    skewed = _joined(db(401, {}, 310.0, paired=True))
    assert "clock" in skewed and "+310s" in skewed and "htpdate" in skewed
    # 401 without meaningful skew stays a signature answer.
    refused = _joined(db(401, {}, 2.0, paired=True))
    assert "REFUSED" in refused and "htpdate" not in refused
    # Transport failure quotes the error.
    down = _joined(db(0, {"error": "timed out"}, None, True))
    assert "UNREACHABLE" in down and "timed out" in down
    # Anything else (a 502 platform blip) suggests a retry.
    blip = _joined(db(502, {}, None, True))
    assert "502" in blip and "again" in blip


def test_tunnel_wording():
    tn  = MOD.describe_tunnel_check
    url = "https://x.trycloudflare.com"
    now = 1_000_000.0
    # No URL published at all.
    off = _joined(tn(None, None, None, None, now))
    assert "NOT RUNNING" in off and "systemctl status moongate-tunnel" in off
    # The healthy gate.
    active = _joined(tn(url, 401, None, {"heals": 0, "state": "ok"}, now))
    assert "ACTIVE" in active and url in active
    # Dead by transport, watchdog on: promise the self-heal.
    dead = _joined(tn(url, None, "timed out",
                      {"heals": 0, "last_heal": None, "state": "ok"}, now))
    assert "BROKEN" in dead and "timed out" in dead and "15 min" in dead
    # Dead by Cloudflare's tunnel-down answer.
    cf = _joined(tn(url, 530, None,
                    {"heals": 0, "last_heal": None, "state": "ok"}, now))
    assert "BROKEN" in cf and "530" in cf
    # Dead with the watchdog disabled: say so instead of promising a heal.
    no_wd = _joined(tn(url, None, "refused", None, now))
    assert "OFF" in no_wd and "15 min" not in no_wd
    # Dead and the watchdog already stood down: point at the journal.
    throttled = _joined(tn(url, None, "refused",
                           {"heals": 3, "last_heal": now - 600,
                            "state": "throttled"}, now))
    assert "STOOD DOWN" in throttled and "journalctl -u moongate-tunnel" in throttled
    # Tunnel delivers but the authproxy is down: not the tunnel's fault.
    proxy = _joined(tn(url, 502, None, {"heals": 0, "state": "ok"}, now))
    assert "auth layer" in proxy and "moongate-authproxy" in proxy
    # Heal history rides along whenever heals happened.
    healed = _joined(tn(url, 401, None,
                        {"heals": 2, "last_heal": now - 720,
                         "state": "ok"}, now))
    assert "2 self-heal(s)" in healed and "12 min ago" in healed


if __name__ == "__main__":
    test_db_wording()
    print("PASS database wording: ok/gone/unpaired/released/clock/refused/down")
    test_tunnel_wording()
    print("PASS tunnel wording: off/active/broken/530/no-watchdog/throttled/authproxy/heals")
    print("All good.")
