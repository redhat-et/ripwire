import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


TIMEOUT = 25
SECRET = "DO_NOT_PRINT_CODEX_DOCTOR_SECRET"


def fail(message):
    print(f"  FAIL  {message}")
    return 1


def ok(message):
    print(f"  PASS  {message}")


def native_path(raw):
    text = str(raw).replace("\\", "/")
    match = re.match(r"^/([A-Za-z])/(.*)$", text)
    if match:
        return Path(f"{match.group(1).upper()}:/{match.group(2)}")
    return Path(text)


def forward(path):
    return str(path).replace("\\", "/")


def run(command, env, cwd=None, timeout=TIMEOUT):
    try:
        return subprocess.run(
            [str(part) for part in command],
            cwd=str(cwd) if cwd is not None else None,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"command timed out after {timeout}s: {Path(command[0]).name}")
    except OSError as exc:
        raise RuntimeError(f"could not start {Path(command[0]).name}: {exc}") from exc


def file_digest(path):
    return hashlib.sha256(path.read_bytes()).digest()


def snapshot(paths):
    result = []
    for path in paths:
        result.append((str(path), file_digest(path)))
    skills = paths[2].parent
    result.extend((str(path), None) for path in sorted(skills.iterdir(), key=lambda item: item.name))
    return result


def report(result):
    if SECRET.encode() in result.stdout or SECRET.encode() in result.stderr:
        raise RuntimeError("doctor leaked an unrelated config secret")
    try:
        root = ET.fromstring(result.stdout)
    except ET.ParseError as exc:
        raise RuntimeError(f"doctor output is not XML: {exc}") from exc
    rows = {node.attrib.get("n"): node.attrib for node in root.findall("c")}
    return root, rows


def doctor(binary, repo, env, agent=True):
    command = [binary, repo, "--doctor"]
    if agent:
        command.append("--agent=codex")
    command.append("--no-cache")
    result = run(command, env)
    root, rows = report(result)
    return result, root, rows


def git_path():
    candidates = []
    found = shutil.which("git.exe") or shutil.which("git")
    if found:
        candidates.append(Path(found))
    candidates.extend(
        [
            Path("C:/Program Files/Git/cmd/git.exe"),
            Path("C:/Program Files/Git/bin/git.exe"),
        ]
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise RuntimeError("git.exe is not available")


def bash_path():
    candidates = []
    configured = os.environ.get("RIPWIRE_BASH")
    if configured:
        candidates.append(native_path(configured))
    candidates.extend(
        [
            Path("C:/Program Files/Git/usr/bin/bash.exe"),
            Path("C:/Program Files/Git/bin/bash.exe"),
        ]
    )
    for candidate in candidates:
        if candidate.is_file() and "system32/bash.exe" not in str(candidate).lower():
            return candidate
    raise RuntimeError("Git Bash is not available")


def run_git(git, args, env, repo):
    result = run([git, "-C", repo, *args], env, timeout=15)
    if result.returncode != 0:
        raise RuntimeError(f"git {args[0]} failed with rc={result.returncode}")


def write_surface(codex, hooks, installed):
    nudge = forward(hooks / "ripwire-codex-nudge.sh")
    route = forward(hooks / "ripwire-codex-route.sh")
    config_command = forward(installed)
    hooks_json = {
        "hooks": {
            "PreToolUse": [{"hooks": [{"type": "command", "command": nudge}]}],
            "SessionStart": [{"hooks": [{"type": "command", "command": f"{nudge} --session-start"}]}],
            "UserPromptSubmit": [{"hooks": [{"type": "command", "command": route}]}],
        },
        "unrelated_secret": SECRET,
    }
    (codex / "hooks.json").write_text(json.dumps(hooks_json), encoding="utf-8", newline="\n")
    (codex / "config.toml").write_text(
        "\n".join(
            [
                "[mcp_servers.ripwire]",
                f'command = "{config_command}"',
                'args = ["--mcp"]',
                'enabled_tools = ["analyze", "quality_delta", "flags", "doc_drift"]',
                'default_tools_approval_mode = "approve"',
                f'token = "{SECRET}"',
                "",
            ]
        ),
        encoding="utf-8",
        newline="\n",
    )


def deny_execute(path, env):
    icacls = Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32" / "icacls.exe"
    if not icacls.is_file():
        raise RuntimeError("icacls.exe is unavailable for the execute-denial fixture")
    result = run([icacls, path, "/deny", "*S-1-1-0:(X)"], env, timeout=15)
    if result.returncode != 0:
        raise RuntimeError(f"icacls could not deny FILE_EXECUTE (rc={result.returncode})")
    return icacls


def restore_execute(icacls, path, env):
    result = run([icacls, path, "/remove:d", "*S-1-1-0"], env, timeout=15)
    if result.returncode != 0:
        raise RuntimeError(f"icacls could not restore FILE_EXECUTE (rc={result.returncode})")


def main():
    if len(sys.argv) != 2:
        print("usage: codexdoctorcheck_windows.py BINARY", file=sys.stderr)
        return 2

    source = native_path(sys.argv[1]).resolve()
    if not source.is_file():
        print(f"missing binary: {source}", file=sys.stderr)
        return 2

    try:
        git = git_path()
        bash = bash_path()
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix="ripwire-codexdoctor-") as temp_name:
            temp = Path(temp_name)
            home = temp / "home"
            codex = temp / "codex"
            agents = temp / "agents"
            bindir = temp / "bin"
            repo = temp / "repo"
            cache = temp / "cache"
            hooks = temp / "hooks"
            for directory in (home, codex, agents, bindir, repo, cache, hooks):
                directory.mkdir(parents=True)

            installed = bindir / "ripwire.exe"
            shutil.copy2(source, installed)
            (repo / "f.cpp").write_text("int f(){return 0;}\n", encoding="utf-8", newline="\n")

            env = os.environ.copy()
            for name in list(env):
                if name.casefold() == "path":
                    del env[name]
            path_parts = [bindir, git.parent, bash.parent, Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32"]
            env.update(
                {
                    "HOME": forward(home),
                    "CODEX_HOME": forward(codex),
                    "AGENTS_HOME": forward(agents),
                    "TMPDIR": forward(cache),
                    "TEMP": forward(cache),
                    "TMP": forward(cache),
                    "RW_MSYS_TMP": forward(temp),
                    "RIPWIRE_BASH": forward(bash),
                    "MSYS_NO_PATHCONV": "1",
                    "OS": "Windows_NT",
                    "PATH": ";".join(forward(part) for part in path_parts),
                    "GIT_CONFIG_NOSYSTEM": "1",
                    "XDG_CONFIG_HOME": forward(home / "config"),
                }
            )
            (home / "config").mkdir()

            run_git(git, ["init", "-q"], env, repo)
            run_git(git, ["config", "user.email", "t@t"], env, repo)
            run_git(git, ["config", "user.name", "Dev"], env, repo)
            run_git(git, ["add", "-A"], env, repo)
            run_git(git, ["commit", "-qm", "init"], env, repo)

            install = run([bash, root / "skills" / "install.sh", "--codex"], env, cwd=root, timeout=30)
            if install.returncode != 0:
                raise RuntimeError(f"Codex skill install failed with rc={install.returncode}")
            manifest = agents / "skills" / ".ripwire-manifest-v1"
            if not manifest.is_file():
                raise RuntimeError("Codex install omitted .ripwire-manifest-v1")
            ok("Codex install emits the versioned skills manifest")

            for name in ("ripwire-codex-nudge.sh", "ripwire-codex-route.sh"):
                hook = hooks / name
                hook.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8", newline="\n")
                hook.chmod(0o755)
            write_surface(codex, hooks, installed)
            tracked_surface = [codex / "hooks.json", codex / "config.toml", manifest]

            result, report_root, rows = doctor(installed, repo, env)
            if result.returncode != 0 or report_root.attrib.get("agent") != "codex" or not rows or not all(row.get("ok") == "1" for row in rows.values()):
                failed = sorted((name, row.get("ok", "missing")) for name, row in rows.items() if row.get("ok") != "1")
                detail = result.stderr.decode("utf-8", "replace").strip()
                raise RuntimeError(f"healthy Codex doctor did not pass all rows: rc={result.returncode}, failed={failed}, stderr={detail}")
            ok("fully wired fake Codex surface exits 0")

            _, base_root, base_rows = doctor(installed, repo, env, agent=False)
            if len(rows) != len(base_rows) + 4 or report_root.attrib.get("passed") != report_root.attrib.get("checks"):
                raise RuntimeError("Codex selection did not add four passing checks")
            ok(f"Codex selection adds four checks (base {len(base_rows)} -> {len(rows)}), all passed, and labels the report")
            for name in ("codex-binary", "codex-skills", "codex-hooks", "codex-mcp"):
                if rows.get(name, {}).get("ok") != "1":
                    raise RuntimeError(f"healthy row missing or failing: {name}")
                ok(f"healthy row present: {name}")
            ok("Codex doctor output is well-formed XML")
            ok("Codex doctor does not print config secrets")

            before = snapshot(tracked_surface)
            result, _, _ = doctor(installed, repo, env)
            if result.returncode != 0 or before != snapshot(tracked_surface):
                raise RuntimeError("Codex doctor mutated the active surface")
            ok("Codex doctor is read-only")

            declared = next(line[6:] for line in manifest.read_text(encoding="utf-8").splitlines() if line.startswith("skill="))
            skill_dir = agents / "skills" / declared
            hidden_skill = temp / declared
            skill_dir.rename(hidden_skill)
            try:
                result, _, missing_rows = doctor(installed, repo, env)
                if result.returncode != 1 or missing_rows.get("codex-skills", {}).get("ok") != "0":
                    raise RuntimeError("missing manifest-declared skill did not fail parity")
                if "skills/install.sh --codex" not in result.stdout.decode("utf-8", "replace"):
                    raise RuntimeError("skill failure omitted the exact repair command")
            finally:
                hidden_skill.rename(skill_dir)
            ok("missing manifest-declared skill fails parity")
            ok("skill failure names the exact repair command")

            undocumented = agents / "skills" / "ripwire-undocumented"
            undocumented.mkdir()
            try:
                _, _, undocumented_rows = doctor(installed, repo, env)
                if undocumented_rows.get("codex-skills", {}).get("ok") != "0":
                    raise RuntimeError("undeclared live skill did not fail parity")
            finally:
                undocumented.rmdir()
            ok("undeclared live skill fails parity")

            route = hooks / "ripwire-codex-route.sh"
            icacls = deny_execute(route, env)
            try:
                result, _, hook_rows = doctor(installed, repo, env)
                if result.returncode != 1 or hook_rows.get("codex-hooks", {}).get("ok") != "0":
                    raise RuntimeError("FILE_EXECUTE-denied Codex hook did not fail")
                if "skills/install.sh --codex --hook" not in result.stdout.decode("utf-8", "replace"):
                    raise RuntimeError("hook failure omitted the exact repair command")
            finally:
                restore_execute(icacls, route, env)
            ok("non-executable Codex hook fails")
            ok("hook failure names the exact repair command")

            config = codex / "config.toml"
            original_config = config.read_text(encoding="utf-8")
            config.write_text(original_config.replace(forward(installed), forward(temp / "missing-ripwire")), encoding="utf-8", newline="\n")
            try:
                result, _, mcp_rows = doctor(installed, repo, env)
                if result.returncode != 1 or mcp_rows.get("codex-mcp", {}).get("ok") != "0":
                    raise RuntimeError("non-executable MCP command did not fail")
                if "ripwire wrap codex" not in result.stdout.decode("utf-8", "replace"):
                    raise RuntimeError("MCP failure omitted the precise recipe command")
            finally:
                config.write_text(original_config, encoding="utf-8", newline="\n")
            ok("non-executable MCP command fails")
            ok("MCP failure names the precise recipe command")
            ok("failing Codex doctor still redacts config secrets")

            bad = run([source, repo, "--doctor", "--agent=notanagent", "--no-cache"], env)
            bad_text = bad.stdout + bad.stderr
            if bad.returncode != 1 or b"supported: codex" not in bad_text:
                raise RuntimeError("unknown --agent value did not refuse with the supported set")
            ok("unknown --agent value refuses with the supported set")

            alone = run([source, repo, "--agent=codex", "--no-cache"], env)
            if alone.returncode != 1 or b"--agent=codex modifies --doctor" not in alone.stdout + alone.stderr:
                raise RuntimeError("--agent=codex alone silently no-opped")
            ok("--agent=codex alone refuses as an inert modifier")

        print("ALL PASS")
        return 0
    except (RuntimeError, StopIteration) as exc:
        return fail(str(exc))


if __name__ == "__main__":
    raise SystemExit(main())
