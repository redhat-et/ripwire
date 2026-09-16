#!/usr/bin/env python3
"""Run installer gates with inherited agent homes outside their temporary fixtures."""
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile


def snapshot(root):
    return {
        str(path.relative_to(root)): (stat.S_IMODE(path.lstat().st_mode), (
            ("link", os.readlink(path)) if path.is_symlink()
            else ("directory",) if path.is_dir()
            else ("file", path.read_bytes())
        ))
        for path in root.rglob("*")
    }


def shell_path(value):
    text = os.fspath(value).replace("\\", "/")
    if os.name == "nt" and len(text) >= 3 and text[1] == ":" and text[2] == "/":
        return "/" + text[0].lower() + text[2:]
    return text


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
    native_tmp = str(outside / "msys-tmp").replace("\\", "/")
    (outside / "msys-tmp").mkdir()
    # Git Bash creates POSIX-looking /tmp paths by default, while native jq and Python resolve
    # those paths independently. Give every child the same native temporary root used by pargates.py.
    environment.update({
        "RW_MSYS_TMP": native_tmp,
        "TMPDIR": native_tmp,
        "TEMP": native_tmp,
        "TMP": native_tmp,
    })

    claude = outside / "HOME" / ".claude"
    claude.mkdir()
    (claude / "settings.json").write_text('{"sentinel": true}\n')
    (outside / "CODEX_HOME" / "hooks.json").write_text('{"sentinel": true}\n')
    before = snapshot(outside)
    sentinel = outside / "CODEX_HOME" / "hooks.json"
    mode = stat.S_IMODE(sentinel.lstat().st_mode)
    permission_bit = stat.S_IWRITE if os.name == "nt" else stat.S_IXUSR
    sentinel.chmod(mode ^ permission_bit)
    if snapshot(outside) == before:
        sys.exit("  FAIL  snapshot missed a permission-only sentinel change")
    sentinel.chmod(mode)
    if snapshot(outside) != before:
        sys.exit("  FAIL  sentinel permissions were not restored")
    print("  PASS  snapshot detects permission-only changes")
    failed = False
    shell = os.environ.get("RIPWIRE_BASH", "bash")
    if os.name == "nt" and shell == "bash":
        shell = r"C:\Program Files\Git\usr\bin\bash.exe"
    for gate, argument in (("skillinstallcheck.sh", shell_path(binary)),
                           ("releaseinstallcheck.sh", "--isolation-child")):
        child_environment = environment.copy()
        child_environment.pop("MSYS_NO_PATHCONV", None)
        child_environment.pop("MSYS2_ARG_CONV_EXCL", None)
        if gate == "releaseinstallcheck.sh":
            # Exercise the release gate's unset of inherited overrides without changing the
            # skill gate's own activation contract (E1-E6 require activation by default).
            child_environment["RIPWIRE_NO_ACTIVATE"] = "1"
        result = subprocess.run(
            [shell, shell_path(root / "test" / gate), argument],
            cwd=root, env=child_environment, capture_output=True, text=True,
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
