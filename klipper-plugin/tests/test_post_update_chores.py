#!/usr/bin/env python3
"""0.6.28: the post-update chores the plugin runs at component load because
Moonraker never executes an extension's install_script (it only scans it
for PKGLIST lines). Three pure functions, each pinned here on temp dirs:

  ensure_moonraker_git_exclude - Moonraker's .git/info/exclude gains the
      component's path once, so the Software Update panel stops reporting
      "Repo has untracked source files"; .git as a dir, as a worktree /
      submodule file, and no checkout at all.
  ensure_asvc_entry - moonraker.asvc lists moongate-tunnel once, only where
      the unit exists, and never glued onto a last line missing its newline.
  refresh_pair_page - the QR page lands in every web root that exists, only
      when missing or different.

Stdlib-only, same harness as test_lan_only_no_deps.py:

    python3 klipper-plugin/tests/test_post_update_chores.py
"""

import importlib.util
import sys
import tempfile
from pathlib import Path

PLUGIN_PATH = Path(__file__).resolve().parents[1] / "moongate_standalone.py"


def _load(name):
    spec = importlib.util.spec_from_file_location(name, PLUGIN_PATH)
    mod  = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    try:
        spec.loader.exec_module(mod)
    except BaseException:
        del sys.modules[name]
        raise
    return mod


MOD = _load("moongate_post_update_chores_test")
LINE = "/moonraker/components/moongate.py"


def _component(root: Path) -> Path:
    comp = root / "moonraker" / "components" / "moongate.py"
    comp.parent.mkdir(parents=True, exist_ok=True)
    comp.write_text("# stand-in for the symlink\n", encoding="utf-8")
    return comp


def test_exclude_git_dir():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "moonraker"
        (root / ".git").mkdir(parents=True)          # no info/ yet
        comp = _component(root)
        assert MOD.ensure_moonraker_git_exclude(comp) is True
        exclude = root / ".git" / "info" / "exclude"
        assert exclude.read_text(encoding="utf-8") == LINE + "\n"
        # Idempotent: a second load adds nothing.
        assert MOD.ensure_moonraker_git_exclude(comp) is False
        assert exclude.read_text(encoding="utf-8").count(LINE) == 1
        # A file that lacks its trailing newline is never corrupted.
        exclude.write_text("# keep me", encoding="utf-8")
        assert MOD.ensure_moonraker_git_exclude(comp) is True
        assert exclude.read_text(encoding="utf-8") == "# keep me\n" + LINE + "\n"
        # Whitespace around an existing entry still counts as present.
        exclude.write_text("  " + LINE + "  \n", encoding="utf-8")
        assert MOD.ensure_moonraker_git_exclude(comp) is False


def test_exclude_git_file():
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        # Submodule-style: .git is a file pointing at a relative gitdir.
        root = base / "moonraker"
        root.mkdir()
        (base / "real.git").mkdir()
        (root / ".git").write_text("gitdir: ../real.git\n", encoding="utf-8")
        comp = _component(root)
        assert MOD.ensure_moonraker_git_exclude(comp) is True
        assert (base / "real.git" / "info" / "exclude").read_text(
            encoding="utf-8") == LINE + "\n"
        # Worktree-style: git keeps info/exclude in the common dir.
        wt = base / "wt"
        wt.mkdir()
        common = base / "main" / ".git"
        (common / "worktrees" / "wt").mkdir(parents=True)
        (wt / ".git").write_text(
            f"gitdir: {common / 'worktrees' / 'wt'}\n", encoding="utf-8")
        comp2 = _component(wt)
        assert MOD.moonraker_git_exclude_file(comp2) == common / "info" / "exclude"
        assert MOD.ensure_moonraker_git_exclude(comp2) is True
        assert (common / "info" / "exclude").read_text(
            encoding="utf-8") == LINE + "\n"
        # A .git file that is not a gitdir pointer is left alone.
        odd = base / "odd"
        odd.mkdir()
        (odd / ".git").write_text("not a pointer\n", encoding="utf-8")
        assert MOD.ensure_moonraker_git_exclude(_component(odd)) is None


def test_exclude_nothing_to_do():
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        # Not a git checkout (package / vendor install): nothing written.
        root = base / "moonraker"
        comp = _component(root)
        assert MOD.ensure_moonraker_git_exclude(comp) is None
        assert not (root / ".git").exists()
        # Unexpected layout: never guess a repo root.
        loose = base / "moongate.py"
        loose.write_text("", encoding="utf-8")
        (base / ".git").mkdir()
        assert MOD.ensure_moonraker_git_exclude(loose) is None
        assert not (base / ".git" / "info").exists()


def test_asvc_entry():
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        asvc = base / "moonraker.asvc"
        unit = base / "moongate-tunnel.service"
        # LAN-only box: no unit, nothing touched (not even a file created).
        assert MOD.ensure_asvc_entry(asvc, unit) is None
        assert not asvc.exists()
        unit.write_text("[Unit]\n", encoding="utf-8")
        # The field case: another tool left the file without a newline.
        asvc.write_text("klipper_mcu\nmobileraker", encoding="utf-8")
        assert MOD.ensure_asvc_entry(asvc, unit) is True
        assert asvc.read_text(encoding="utf-8").splitlines() == [
            "klipper_mcu", "mobileraker", "moongate-tunnel"]
        assert MOD.ensure_asvc_entry(asvc, unit) is False
        # No asvc at all yet: created with just our entry.
        asvc.unlink()
        assert MOD.ensure_asvc_entry(asvc, unit) is True
        assert asvc.read_text(encoding="utf-8") == "moongate-tunnel\n"


def test_pair_page():
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        src = base / "moongate-pair.html"
        src.write_bytes(b"<html>v1</html>")
        mainsail = base / "mainsail"
        mainsail.mkdir()
        fluidd = base / "fluidd"                       # does not exist
        stale = base / "www"
        stale.mkdir()
        (stale / "moongate-pair.html").write_bytes(b"<html>old</html>")
        written = MOD.refresh_pair_page(src, [mainsail, fluidd, stale])
        assert written == [mainsail / "moongate-pair.html",
                           stale / "moongate-pair.html"]
        assert (mainsail / "moongate-pair.html").read_bytes() == b"<html>v1</html>"
        assert (stale / "moongate-pair.html").read_bytes() == b"<html>v1</html>"
        assert not fluidd.exists()
        # Unchanged copies are not rewritten.
        assert MOD.refresh_pair_page(src, [mainsail, fluidd, stale]) == []
        # A missing source (component copied, not symlinked) is a no-op.
        assert MOD.refresh_pair_page(base / "missing.html", [mainsail]) == []


if __name__ == "__main__":
    test_exclude_git_dir()
    print("PASS exclude: .git dir, once, newline guard, whitespace match")
    test_exclude_git_file()
    print("PASS exclude: gitdir file, worktree common dir, odd pointer")
    test_exclude_nothing_to_do()
    print("PASS exclude: no checkout / unexpected layout leave nothing behind")
    test_asvc_entry()
    print("PASS asvc: no unit, glued-line guard, once, created when absent")
    test_pair_page()
    print("PASS pair page: existing roots only, stale replaced, unchanged skipped")
    print("All good.")
