#!/usr/bin/env python3
"""Run installer gates with inherited agent homes outside their temporary fixtures."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def snapshot(root):
    return {
        str(path.relative_to(root)): (
            ("link", os.readlink(path)) if path.is_symlink()
            else ("directory",) if path.is_dir()
            else ("file", path.read_bytes())
        )
        for path in root.rglob("*")
    }


root = Path(__file__).resolve().parent.parent
binary = Path(sys.argv[1])
if not binary.is_absolute():
    binary = root / binary
binary = binary.resolve()
if not binary.is_file() or not os.access(binary, os.X_OK):
    sys.exit(f"missing executable ripwire binary: {binary}")
with tempfile.TemporaryDirectory(prefix="ripwire-installer-sentinels-") as temporary:
    outside = Path(temporary)
    environment = os.environ.copy()
    for variable in ("HOME", "CODEX_HOME", "AGENTS_HOME", "HERMES_HOME"):
        home = outside / variable
        home.mkdir()
        (home / "sentinel").write_text("leave unchanged\n")
        environment[variable] = str(home)
    claude = outside / "HOME" / ".claude"
    claude.mkdir()
    (claude / "settings.json").write_text('{"sentinel": true}\n')
    (outside / "CODEX_HOME" / "hooks.json").write_text('{"sentinel": true}\n')
    before = snapshot(outside)
    failed = False
    for gate, argument in (("skillinstallcheck.sh", str(binary)),
                           ("releaseinstallcheck.sh", "--isolation-child")):
        result = subprocess.run(
            ["bash", str(root / "test" / gate), argument],
            cwd=root, env=environment, capture_output=True, text=True,
        )
        if result.returncode:
            print(result.stdout)
            print(result.stderr, file=sys.stderr)
            print(f"  FAIL  {gate} with inherited agent homes")
            failed = True
        if snapshot(outside) != before:
            print(f"  FAIL  {gate} changed an outside sentinel home")
            failed = True
        else:
            print(f"  PASS  {gate} left outside sentinel homes unchanged")
    sys.exit(1 if failed else 0)
