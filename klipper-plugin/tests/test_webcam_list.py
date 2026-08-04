#!/usr/bin/env python3
"""v0.6.22: /status carries EVERY enabled Moonraker webcam (`webcams: [...]`),
not just the first - the app's dashboard tile shows a camera switcher when
more than one is present. The flat webcam_* fields stay the first enabled
camera, which is the whole back-compat story: pre-multicam apps keep reading
the flat fields, 0.9.59+ apps prefer the list.

Stdlib-only, same harness as test_lan_only_no_deps.py:

    python3 klipper-plugin/tests/test_webcam_list.py
"""

import asyncio
import importlib.util
import json
import sys
import tempfile
import types
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


class FakeServer:
    def register_endpoint(self, *a, **k):      pass
    def register_remote_method(self, *a, **k): pass
    def lookup_component(self, *a, **k):       raise KeyError("not in test")
    def get_host_info(self):                   return {"port": 80}
    def error(self, msg, code=500):            return RuntimeError(f"{code}: {msg}")


class FakeConfig:
    """Duck-typed stand-in for Moonraker's ConfigHelper ([moongate] section)."""
    def __init__(self, opts):
        self._opts   = opts
        self._server = FakeServer()

    def get_server(self):            return self._server
    def get(self, k, d=None):        return self._opts.get(k, d)
    def getboolean(self, k, d=None): return self._opts.get(k, d)
    def getint(self, k, d=None):     return self._opts.get(k, d)


class FakeResp:
    def __init__(self, code, body):
        self.code = code
        self.body = body


class FakeClient:
    """Stands in for tornado's AsyncHTTPClient: answers /server/webcams/list
    with a canned payload (or a canned error code)."""
    def __init__(self, webcams=None, code=200):
        self._webcams = webcams or []
        self._code    = code

    async def fetch(self, req, raise_error=False):
        body = json.dumps({"result": {"webcams": self._webcams}}).encode()
        return FakeResp(self._code, body)


def _stub_tornado():
    """_get_webcam_info lazily does `from tornado.httpclient import
    HTTPRequest`; a stdlib box has no tornado, so plant a minimal fake."""
    if "tornado.httpclient" in sys.modules:
        return
    httpclient = types.ModuleType("tornado.httpclient")

    class HTTPRequest:
        def __init__(self, url, **kw):
            self.url = url

    httpclient.HTTPRequest = HTTPRequest
    tornado = types.ModuleType("tornado")
    tornado.httpclient = httpclient
    sys.modules.setdefault("tornado", tornado)
    sys.modules["tornado.httpclient"] = httpclient


def test_entry_normalisation(mod):
    # Normal Pi-served camera: relative snapshot path rides through untouched.
    e = mod._webcam_entry({
        "name":         "Nozzle",
        "uid":          "ec20767d",
        "snapshot_url": "/webcam/?action=snapshot",
        "stream_url":   "/webcam/?action=stream",
        "target_fps":   30,
        "rotation":     180,
        "flip_horizontal": True,
    })
    assert e["name"] == "Nozzle" and e["uid"] == "ec20767d"
    assert e["snapshot_path"] == "/webcam/?action=snapshot"
    assert e["stream_external"] is None and e["snapshot_external"] is None
    assert e["target_fps"] == 30 and e["rotation"] == 180
    assert e["flip_horizontal"] is True and e["flip_vertical"] is False

    # localhost absolute URL is stripped to its path (Moonraker often stores
    # http://127.0.0.1/webcam2/... for the second Crowsnest cam).
    e = mod._webcam_entry({
        "name":         "Chamber",
        "snapshot_url": "http://127.0.0.1/webcam2/?action=snapshot",
    })
    assert e["snapshot_path"] == "/webcam2/?action=snapshot"
    assert e["snapshot_external"] is None

    # External phone-cam: absolute URL surfaces via *_external, and the
    # snapshot_path falls back to the default instead of leaking the URL.
    e = mod._webcam_entry({
        "name":       "Phone",
        "stream_url": "http://192.168.0.107:8080/video",
    })
    assert e["stream_external"] == "http://192.168.0.107:8080/video"
    assert e["snapshot_path"] == "/webcam/?action=snapshot"

    # Garbage fps / rotation never take the entry down.
    e = mod._webcam_entry({"target_fps": "abc", "rotation": "sideways"}, 1)
    assert e["target_fps"] == 15 and e["rotation"] == 0
    # Unnamed cam gets an indexed fallback label; missing uid stays None.
    assert e["name"] == "Camera 2" and e["uid"] is None
    e = mod._webcam_entry({"target_fps": 999})
    assert e["target_fps"] == 15


def test_entries_filter_and_cap(mod):
    cams = [
        {"name": "one"},
        {"name": "off", "enabled": False},
        "not-a-dict",
        {"name": "two"},
    ]
    entries = mod._webcam_entries(cams)
    assert [e["name"] for e in entries] == ["one", "two"]

    entries = mod._webcam_entries([{"name": f"c{i}"} for i in range(12)])
    assert len(entries) == mod._WEBCAM_LIST_CAP

    assert mod._webcam_entries(None) == []
    assert mod._webcam_entries({"name": "not-a-list"}) == []


def test_status_contract(mod):
    """The async fetch path: flat webcam_* fields mirror the first enabled
    entry, the full list rides alongside, and a Moonraker error still
    returns the defaults (with an empty list, never a missing key)."""
    _stub_tornado()
    with tempfile.TemporaryDirectory() as tmp:
        plugin = mod.MoongatePlugin(FakeConfig({
            "lan_only":  True,
            "data_path": tmp,
        }))

    info = asyncio.run(plugin._get_webcam_info(FakeClient([
        {"name": "off-first", "enabled": False,
         "snapshot_url": "/webcam9/?action=snapshot"},
        {"name": "Nozzle",  "uid": "aaa",
         "snapshot_url": "/webcam/?action=snapshot",  "target_fps": 30},
        {"name": "Chamber", "uid": "bbb",
         "snapshot_url": "http://127.0.0.1/webcam2/?action=snapshot"},
    ])))
    assert [e["name"] for e in info["webcams"]] == ["Nozzle", "Chamber"]
    assert info["snapshot_path"] == "/webcam/?action=snapshot"
    assert info["target_fps"] == 30
    assert info["webcams"][1]["snapshot_path"] == "/webcam2/?action=snapshot"

    info = asyncio.run(plugin._get_webcam_info(FakeClient(code=500)))
    assert info["webcams"] == [] and info["target_fps"] == 15

    info = asyncio.run(plugin._get_webcam_info(FakeClient([])))
    assert info["webcams"] == []
    assert info["snapshot_path"] == "/webcam/?action=snapshot"


if __name__ == "__main__":
    mod = _load("moongate_webcams")
    test_entry_normalisation(mod)
    print("PASS per-camera normalisation (paths, externals, fps, names)")
    test_entries_filter_and_cap(mod)
    print("PASS list building (enabled filter, junk tolerance, cap)")
    test_status_contract(mod)
    print("PASS /status contract (flat fields = first entry, list alongside)")
    print("All good.")
