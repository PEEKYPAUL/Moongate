#!/usr/bin/env python3
"""v0.6.32: which web interfaces the Pi serves (Mainsail on 80, Fluidd on 81
is the KIAUH two-UI layout). classify_frontend() names a root page,
nginx_listen_ports() reads the ports nginx is told to serve,
frontend_probe_ports() orders one probe round, pick_frontends() shapes the
/status `frontends` list, and frontend_upstream() is the auth proxy's routing
rule for the app's `mg_ui` cookie (a type the probe listed, never a port).

Stdlib-only, same harness as test_chamber_pick.py:

    python3 klipper-plugin/tests/test_frontends.py
"""

import importlib.util
import json
import sys
import tempfile
from pathlib import Path

PLUGIN_PATH = Path(__file__).resolve().parents[1] / "moongate_standalone.py"


def _load(name="moongate_frontends_under_test"):
    spec = importlib.util.spec_from_file_location(name, PLUGIN_PATH)
    mod  = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    try:
        spec.loader.exec_module(mod)
    except BaseException:
        del sys.modules[name]
        raise
    return mod


MAINSAIL_INDEX = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<title>Mainsail</title><link rel="icon" href="/img/icon.svg"></head>
<body><noscript>Mainsail needs JavaScript. See the Fluidd docs for a
comparison.</noscript><div id="app"></div></body></html>"""

FLUIDD_INDEX = """<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>fluidd</title></head><body><div id="app"></div>
<script type="module" src="/assets/index-abc123.js"></script></body></html>"""

OCTOPRINT_INDEX = """<html><head><title>OctoPrint Login</title></head><body>
<div id="loginform">OctoPrint</div></body></html>"""

CAMERA_INDEX = """<html><head><title>go2rtc</title></head><body>
<a href="stream.html?src=camera">camera</a></body></html>"""


# ── classify_frontend ────────────────────────────────────────────────────────

def test_classify_by_title(mod):
    assert mod.classify_frontend(MAINSAIL_INDEX) == "mainsail"
    assert mod.classify_frontend(FLUIDD_INDEX) == "fluidd"
    assert mod.classify_frontend(OCTOPRINT_INDEX) == "octoprint"


def test_classify_title_wins_over_body_mentions(mod):
    # The Mainsail page above mentions Fluidd in its body; the title decides.
    assert mod.classify_frontend(MAINSAIL_INDEX) == "mainsail"


def test_classify_falls_back_to_body(mod):
    assert mod.classify_frontend("<div class='fluidd-app'></div>") == "fluidd"


def test_classify_unknown_pages_are_none(mod):
    assert mod.classify_frontend(CAMERA_INDEX) is None
    assert mod.classify_frontend('{"error": {"code": 404}}') is None
    assert mod.classify_frontend("") is None
    assert mod.classify_frontend(None) is None


# ── nginx_listen_ports ───────────────────────────────────────────────────────

def test_nginx_listen_ports_reads_every_form(mod):
    with tempfile.TemporaryDirectory() as d:
        site = Path(d)
        (site / "mainsail").write_text(
            "server {\n    listen 80 default_server;\n"
            "    listen [::]:80 default_server;\n    root /home/pi/mainsail;\n}\n")
        (site / "fluidd").write_text(
            "server {\n\tlisten 0.0.0.0:81;\n\tlisten [::]:81;\n}\n")
        (site / "odd").write_text(
            "server {\n listen 127.0.0.1:4409 ssl http2;\n # listen 9999;\n}\n")
        (site / "notes.txt").write_text("listen to this: not a directive\n")
        # File order is nginx's own (alphabetical); the probe orders ports.
        assert sorted(mod.nginx_listen_ports([d])) == [80, 81, 4409]


def test_nginx_listen_ports_tolerates_missing_dirs(mod):
    assert mod.nginx_listen_ports(["/nonexistent/sites-enabled"]) == []


# ── frontend_probe_ports ─────────────────────────────────────────────────────

def test_probe_ports_order_and_dedupe(mod):
    ports = mod.frontend_probe_ports(80, 7125, [80, 81])
    assert ports[0] == 80                      # the advertised UI first
    assert ports[1] == 81                      # then nginx's extra
    assert 7125 not in ports                   # Moonraker never serves a UI
    assert len(ports) == len(set(ports))
    for p in mod.FRONTEND_CANDIDATE_PORTS:
        assert p in ports


def test_probe_ports_skips_moonraker_even_as_http_port(mod):
    # Embedded hosts bind Moonraker itself to :80.
    assert 80 not in mod.frontend_probe_ports(80, 80, [])


def test_probe_ports_ignores_junk(mod):
    assert mod.frontend_probe_ports("x", 7125, [None, "81", 0, 70000]) == \
        [81, *[p for p in mod.FRONTEND_CANDIDATE_PORTS if p != 81]]


# ── pick_frontends ───────────────────────────────────────────────────────────

def test_pick_frontends_shape_sorted_by_port(mod):
    found = [(4409, "fluidd"), (80, "mainsail"), (8080, None), (5000, None)]
    assert mod.pick_frontends(found) == [
        {"type": "mainsail", "port": 80},
        {"type": "fluidd",   "port": 4409},
    ]


def test_pick_frontends_same_ui_twice_keeps_lowest_port(mod):
    found = [(80, "mainsail"), (4408, "mainsail")]
    assert mod.pick_frontends(found) == [{"type": "mainsail", "port": 80}]


def test_pick_frontends_empty_and_junk(mod):
    assert mod.pick_frontends([]) == []
    assert mod.pick_frontends(None) == []
    assert mod.pick_frontends([("x", "fluidd"), (81, ""), (81, 3), "junk"]) == []


# ── frontends.json + frontend_upstream (the proxy's side) ────────────────────

def test_load_frontends_file_roundtrip(mod):
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "frontends.json"
        f.write_text(json.dumps({"frontends": [
            {"type": "mainsail", "port": 80},
            {"type": "fluidd",   "port": 81},
            {"type": "bad",      "port": "81"},
            {"type": "",         "port": 82},
            "junk",
        ], "updated": 1}))
        assert mod.load_frontends_file(f) == {"mainsail": 80, "fluidd": 81}


def test_load_frontends_file_missing_or_broken(mod):
    with tempfile.TemporaryDirectory() as d:
        assert mod.load_frontends_file(Path(d) / "none.json") == {}
        f = Path(d) / "broken.json"
        f.write_text("{not json")
        assert mod.load_frontends_file(f) == {}
        f.write_text("[1, 2]")
        assert mod.load_frontends_file(f) == {}


def test_upstream_routes_only_listed_types(mod):
    fe = {"mainsail": 80, "fluidd": 81}
    default = "http://127.0.0.1:80"
    assert mod.frontend_upstream("fluidd", fe, default) == "http://127.0.0.1:81"
    assert mod.frontend_upstream("mainsail", fe, default) == default
    # Unknown, empty, missing: the default, exactly as before 0.6.32.
    assert mod.frontend_upstream("octoprint", fe, default) == default
    assert mod.frontend_upstream("", fe, default) == default
    assert mod.frontend_upstream(None, fe, default) == default
    assert mod.frontend_upstream("fluidd", {}, default) == default
    assert mod.frontend_upstream("fluidd", None, default) == default


def test_upstream_cookie_never_names_a_port(mod):
    # A cookie value is a TYPE; anything port-shaped routes nowhere new.
    fe = {"mainsail": 80}
    default = "http://127.0.0.1:80"
    assert mod.frontend_upstream("81", fe, default) == default
    assert mod.frontend_upstream("127.0.0.1:22", fe, default) == default


def main() -> int:
    mod = _load()
    tests = [(n, f) for n, f in sorted(globals().items())
             if n.startswith("test_") and callable(f)]
    failed = 0
    for name, fn in tests:
        try:
            fn(mod)
            print(f"ok   {name}")
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"FAIL {name}: {exc!r}")
    print(f"{len(tests) - failed}/{len(tests)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
