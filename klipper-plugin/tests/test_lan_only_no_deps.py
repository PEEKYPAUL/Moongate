#!/usr/bin/env python3
"""v0.6.17 regression test: the plugin must load and run LAN-only WITHOUT
PyJWT/cryptography installed (embedded hosts - see docs/third-party-printers.md
- have no pip and no prebuilt wheels for them).

v0.6.20 tightened the contract: the pair imports lazily, only when CLOUD mode
constructs. LAN-only must never import them EVEN WHEN INSTALLED - a
present-but-unused cryptography costs ~6.5 MB of RSS inside Moonraker
(measured on a 32-bit Pi), real money on ~112 MB embedded hosts.

Stdlib-only on purpose so it runs anywhere Python 3.9+ does:

    python3 klipper-plugin/tests/test_lan_only_no_deps.py

Covers:
  1. import with jwt + cryptography BLOCKED  -> module loads, no probe yet
  2. MoongatePlugin construction in lan_only -> no cloud objects, no keygen,
     and the cloud deps are never probed/imported
  3. CLOUD-mode construction with deps BLOCKED -> fail-loud-but-running
     (plugin_error says what to install, no cloud objects)
  4. import with real deps (when installed)  -> lan_only still never
     imports them
"""

import importlib.util
import sys
import tempfile
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


class _BlockDeps:
    """Context manager: `import jwt` / `import cryptography` raise ImportError
    inside the with-block (None in sys.modules makes the import fail)."""
    def __enter__(self):
        for name in BLOCKED:
            assert name not in sys.modules or sys.modules[name] is None, (
                f"{name} already imported - run this test in its own process")
            sys.modules[name] = None

    def __exit__(self, *exc):
        for name in BLOCKED:
            del sys.modules[name]
        return False


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


def test_import_without_deps():
    with _BlockDeps():
        mod = _load("moongate_nodeps")
    # Lazy since v0.6.20: a bare import must neither probe nor fail.
    assert mod._CLOUD_DEPS_ERROR is None, "import must not probe cloud deps"
    assert mod._CLOUD_DEPS_PROBED is False
    # Class definitions must survive the missing imports (only calls need them)
    for cls in ("MoongatePlugin", "DeviceKey", "JwksCache",
                "AccessTokenVerifier", "HeartbeatLoop", "PrintEventWatcher"):
        assert hasattr(mod, cls), f"{cls} missing from module"
    return mod


def test_lan_only_construction(mod):
    with tempfile.TemporaryDirectory() as tmp:
        plugin = mod.MoongatePlugin(FakeConfig({
            "lan_only":  True,
            "data_path": tmp,
        }))
        assert plugin.lan_only is True
        assert plugin._plugin_error is None, "lan_only must not report an error"
        for attr in ("device", "jwks", "verifier", "sb", "heartbeat", "watcher"):
            assert getattr(plugin, attr) is None, f"{attr} built in lan_only"
        assert plugin._moonraker_port == 80, "get_host_info port not used"
        assert not (Path(tmp) / "device_ed25519").exists(), \
            "lan_only must not generate a device key"
        # moonraker.conf's lan_only wins over config.json's default (False)
        assert plugin._lan_only_override is True
        # The v0.6.20 guarantee: lan_only never even probes the cloud deps.
        assert mod._CLOUD_DEPS_PROBED is False, \
            "lan_only construction must not import/probe PyJWT+cryptography"


def test_cloud_construction_without_deps():
    with _BlockDeps():
        mod = _load("moongate_nodeps_cloud")
        with tempfile.TemporaryDirectory() as tmp:
            plugin = mod.MoongatePlugin(FakeConfig({"data_path": tmp}))
    assert plugin.lan_only is False
    assert plugin._plugin_error is not None, "cloud mode must surface the gap"
    assert "PyJWT" in plugin._plugin_error
    assert mod._CLOUD_DEPS_ERROR == plugin._plugin_error
    for attr in ("device", "jwks", "verifier", "sb", "heartbeat", "watcher"):
        assert getattr(plugin, attr) is None, f"{attr} built without deps"


def test_lan_only_with_real_deps_does_not_import_them():
    mod = _load("moongate_withdeps")
    assert mod._CLOUD_DEPS_ERROR is None, mod._CLOUD_DEPS_ERROR
    with tempfile.TemporaryDirectory() as tmp:
        mod.MoongatePlugin(FakeConfig({
            "lan_only":  True,
            "data_path": tmp,
        }))
    assert mod._CLOUD_DEPS_PROBED is False
    # Whether or not this machine has the packages, a lan_only construction
    # must not be the thing that pulls them into the process.
    assert "jwt" not in sys.modules, \
        "lan_only construction imported PyJWT as a side effect"


AUTHPROXY_PATH = Path(__file__).resolve().parents[1] / "moongate_authproxy.py"


def test_authproxy_startup_contract():
    """v0.6.21 regression (the 0.6.20 field failure): the auth proxy is a
    SEPARATE process that imports JwksCache/AccessTokenVerifier from this
    module and never constructs MoongatePlugin - the only place the lazy
    cloud-deps probe ran. Without its own probe, pyjwt stays None and every
    tunnel request raises AttributeError -> aiohttp's stock 500 page, while
    LAN (which bypasses the proxy) and heartbeats (the component's process,
    where the probe DID run) look healthy. Two guards:
      a) the proxy source probes + exits loud at startup;
      b) after a successful probe, verify() on garbage tokens returns None
         (the constant-401 path) instead of raising.

    NOTE this test must stay LAST: on a deps-present box it really imports
    PyJWT into the process, which would trip test_lan_only_with_real_deps's
    "jwt not in sys.modules" assert if it ran before it."""
    src = AUTHPROXY_PATH.read_text(encoding="utf-8")
    assert "_import_cloud_deps" in src, \
        "auth proxy no longer probes the lazy cloud deps at startup"

    mod = _load("moongate_authproxy_pattern")
    err = mod._import_cloud_deps()
    if err is not None:
        print("  (PyJWT/cryptography absent on this box - probe reported the "
              "gap; the verify half needs a deps-present run)")
        return
    with tempfile.TemporaryDirectory() as tmp:
        jwks     = mod.JwksCache("https://unused.invalid", "anon-key",
                                 Path(tmp) / "jwks.json", 3600)
        verifier = mod.AccessTokenVerifier(jwks)
        # Garbage tokens fail the header parse long before any JWKS/network
        # touch - the contract is they 401 (None), never raise.
        assert verifier.verify("not-a-jwt", None) is None
        assert verifier.verify("aaaa.bbbb.cccc", None) is None


if __name__ == "__main__":
    mod = test_import_without_deps()
    print("PASS import with jwt/cryptography blocked (no probe, no error)")
    test_lan_only_construction(mod)
    print("PASS lan_only construction without deps (no cloud objects, no keygen, no probe)")
    test_cloud_construction_without_deps()
    print("PASS cloud construction without deps fails loud but keeps running")
    test_lan_only_with_real_deps_does_not_import_them()
    print("PASS lan_only never imports the cloud deps even when installed")
    test_authproxy_startup_contract()
    print("PASS auth proxy probes the lazy deps; verify never raises on garbage")
    print("All good.")
