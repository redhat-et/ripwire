"""Native-Windows qsnapprefetch gate.

The shell gate uses POSIX FIFOs.  Windows has no equivalent named pipe that can be
opened with the same blocking semantics by a native process, so this companion
keeps the protocol on anonymous subprocess pipes and leaves all behavioural
assertions in Python.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import queue
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "test" / "fixture"


class GateError(RuntimeError):
    pass


class Server:
    def __init__(self, binary: Path, env: dict[str, str]):
        self.process = subprocess.Popen(
            [str(binary), "--mcp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            cwd=str(ROOT),
        )
        self.responses: queue.Queue[dict] = queue.Queue()
        self.stderr_lines: list[str] = []
        self._stderr_lock = threading.Lock()
        self._stdout_thread = threading.Thread(target=self._read_stdout, daemon=True)
        self._stderr_thread = threading.Thread(target=self._read_stderr, daemon=True)
        self._stdout_thread.start()
        self._stderr_thread.start()

    def _read_stdout(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            try:
                value = json.loads(line)
            except json.JSONDecodeError as exc:
                self.responses.put({"__invalid__": repr(line), "error": str(exc)})
                continue
            if isinstance(value, dict) and "id" in value:
                self.responses.put(value)

    def _read_stderr(self) -> None:
        assert self.process.stderr is not None
        for line in self.process.stderr:
            decoded = line.decode("utf-8", errors="replace").rstrip("\r\n")
            with self._stderr_lock:
                self.stderr_lines.append(decoded)

    def call(self, request_id: int, method: str, params: dict | None = None, timeout: float = 60.0) -> dict:
        request = {"jsonrpc": "2.0", "id": request_id, "method": method}
        if params is not None:
            request["params"] = params
        assert self.process.stdin is not None
        try:
            self.process.stdin.write(json.dumps(request, separators=(",", ":")).encode("utf-8") + b"\n")
            self.process.stdin.flush()
        except OSError as exc:
            raise GateError(f"server stdin failed for id={request_id}: {exc}") from exc

        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise GateError(f"server did not answer id={request_id} within {timeout:.0f}s")
            try:
                response = self.responses.get(timeout=remaining)
            except queue.Empty as exc:
                raise GateError(f"server did not answer id={request_id} within {timeout:.0f}s") from exc
            if "__invalid__" in response:
                raise GateError(f"server returned invalid JSON: {response}")
            if response.get("id") == request_id:
                return response

    def close(self) -> None:
        if self.process.stdin is not None:
            try:
                self.process.stdin.close()
            except OSError:
                pass
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=10)
        self._stdout_thread.join(timeout=2)
        self._stderr_thread.join(timeout=2)


class Gate:
    def __init__(self, binary: Path):
        self.binary = binary
        self.failures = 0
        self.temp = Path(tempfile.mkdtemp(prefix="ripwire-qsnapprefetch-"))

    def ok(self, message: str) -> None:
        print(f"  PASS  {message}")

    def no(self, message: str) -> None:
        self.failures += 1
        print(f"  FAIL  {message}")

    def git(self, work: Path, *args: str) -> None:
        env = os.environ.copy()
        env["GIT_TERMINAL_PROMPT"] = "0"
        result = subprocess.run(
            ["git", "-C", str(work), *args],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        if result.returncode != 0:
            raise GateError(f"git {' '.join(args)} failed ({result.returncode}): {result.stderr.decode(errors='replace')}")

    def new_repo(self) -> tuple[Path, Path]:
        work = Path(tempfile.mkdtemp(prefix="work.", dir=self.temp))
        cache = Path(tempfile.mkdtemp(prefix="cache.", dir=self.temp))
        shutil.copytree(FIXTURE, work, dirs_exist_ok=True)
        self.git(work, "init", "-q")
        self.git(work, "config", "user.email", "pf@x.com")
        self.git(work, "config", "user.name", "PF")
        self.git(work, "add", "-A")
        self.git(work, "commit", "-q", "-m", "init")
        return work, cache

    @staticmethod
    def env(cache: Path, threshold: int | None = None) -> dict[str, str]:
        env = os.environ.copy()
        cache_text = str(cache)
        env["TMPDIR"] = cache_text
        env["TEMP"] = cache_text
        env["TMP"] = cache_text
        env["XDG_CACHE_HOME"] = cache_text
        env.setdefault("RIPWIRE_BASH", r"C:\Program Files\Git\usr\bin\bash.exe")
        env["RIPWIRE_MCP_TIMINGS"] = "1"

        if threshold is not None:
            env["RIPWIRE_QSNAP_PREFETCH_MIN_FILES"] = str(threshold)
        return env

    @staticmethod
    def qsnap_files(cache: Path) -> list[Path]:
        return sorted(cache.rglob("ripwire-qsnap-*.bin"), key=lambda path: str(path).lower())

    @staticmethod
    def validate_qsnap(path: Path) -> str:
        try:
            data = path.read_bytes()
        except OSError:
            return "ABSENT"
        if not data:
            return "EMPTY"
        if len(data) < 4 + 4 + 8 + 8 or data[:4] != b"QSNP":
            return "INVALID"
        expected = struct.unpack("<Q", data[-8:])[0]
        digest = hashlib.blake2b(digest_size=8)
        # The production format uses FNV-1a, kept explicit below; blake2b is not used as the verdict.
        del digest
        value = 14695981039346656037
        for byte in data[:-8]:
            value = ((value ^ byte) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
        return "VALID" if value == expected else "INVALID"

    @staticmethod
    def remove_qsnaps(cache: Path) -> None:
        for path in Gate.qsnap_files(cache):
            try:
                path.unlink()
            except FileNotFoundError:
                pass

    @staticmethod
    def response_text(response: dict) -> str:
        if "error" in response:
            return "__ERROR__:" + str(response["error"].get("message", ""))
        try:
            return str(response["result"]["content"][0]["text"])
        except (KeyError, IndexError, TypeError) as exc:
            raise GateError(f"malformed MCP response: {response}") from exc

    @staticmethod
    def find(server: Server, request_id: int, work: Path, symbol: str) -> dict:
        return server.call(
            request_id,
            "tools/call",
            {
                "name": "find_symbol",
                "arguments": {"path": str(work), "symbol": symbol},
            },
        )

    @staticmethod
    def quality_delta(server: Server, request_id: int, work: Path) -> str:
        response = server.call(
            request_id,
            "tools/call",
            {"name": "quality_delta", "arguments": {"path": str(work)}},
            timeout=120,
        )
        return Gate.response_text(response)

    @staticmethod
    def identity(path: Path) -> tuple[int, int] | None:
        try:
            info = path.stat()
        except OSError:
            return None
        return info.st_ino, info.st_mtime_ns

    def run_cli_delta(self, work: Path, cache: Path, stderr_path: Path) -> None:
        with stderr_path.open("ab") as stderr:
            subprocess.run(
                [str(self.binary), str(work), "--quality-delta"],
                env=self.env(cache),
                stdout=subprocess.DEVNULL,
                stderr=stderr,
                timeout=120,
                check=False,
            )

    def scenario_a(self) -> None:
        work, cache = self.new_repo()
        stderr_path = work / "err.txt"
        bad = []
        stop = threading.Event()

        def sample() -> None:
            for _ in range(400):
                for path in self.qsnap_files(cache):
                    try:
                        if path.read_bytes() and self.validate_qsnap(path) != "VALID":
                            bad.append(str(path))
                            stop.set()
                            return
                    except OSError:
                        pass
                if stop.is_set():
                    return
            stop.set()

        sampler = threading.Thread(target=sample, daemon=True)
        sampler.start()
        for _ in range(12):
            self.remove_qsnaps(cache)
            self.run_cli_delta(work, cache, stderr_path)
        stop.set()
        sampler.join(timeout=10)
        if bad:
            self.no("(a) sampler caught a non-empty INVALID qsnap (torn read)")
        else:
            self.ok("(a) qsnap never observed half-written across 12 rewrites (atomic rename)")
        files = self.qsnap_files(cache)
        if files and self.validate_qsnap(files[0]) == "VALID":
            self.ok("(a) final qsnap blob is checksum-valid")
        else:
            self.no("(a) final qsnap blob missing/invalid")
        residues = list(cache.rglob("*.tmp.*"))
        if residues:
            self.no("(a) stale *.tmp.* residue left behind (rename did not consume it)")
        else:
            self.ok("(a) no *.tmp.* residue after writes (rename consumed the tmp)")
        self.ok("no ThreadSanitizer warning in server stderr (a)") if b"ThreadSanitizer" not in stderr_path.read_bytes() else self.no("TSan WARNING in server stderr (a)")

    def scenario_b(self) -> None:
        work, cache = self.new_repo()
        geo = work / "geometry.cpp"
        server = Server(self.binary, self.env(cache, 1))
        try:
            server.call(1, "initialize")
            self.find(server, 2, work, "perimeter")
            if self.qsnap_files(cache):
                self.no("(b) unexpected qsnap present before commit")
            else:
                self.ok("(b) no qsnap before any commit (clean warm-up)")
            with geo.open("ab") as handle:
                handle.write(b"\n// prefetch-trigger edit\n")
            self.git(work, "commit", "-q", "-am", "edit that moves HEAD")
            self.find(server, 3, work, "perimeter")
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline and not self.qsnap_files(cache):
                time.sleep(0.05)
            files = self.qsnap_files(cache)
            if files:
                self.ok("(b) qsnap for the NEW sha appeared WITHOUT any quality_delta (prefetch fired — non-vacuous)")
            else:
                self.no("(b) qsnap never appeared after the commit — prefetch did NOT fire")
                print("        server stderr: " + " | ".join(server.stderr_lines[-12:]))
            if any("ripwire-prefetch spawn" in line for line in server.stderr_lines):
                self.ok("(b) server logged a prefetch spawn")
            else:
                self.no("(b) no prefetch spawn logged")
            before = self.identity(files[0]) if files else None
            text = self.quality_delta(server, 4, work)
            if "baseline" in text:
                self.ok("(b) quality_delta returned a well-formed result")
            else:
                self.no(f"(b) quality_delta did not return a baseline result: {text[:120]}")
            after = self.identity(files[0]) if files else None
            if before is not None and before == after:
                self.ok("(b) quality_delta served the prewarmed qsnap un-rewritten (WARM path: inode/mtime unchanged)")
            else:
                self.no(f"(b) qsnap was rewritten by quality_delta (COLD path): {before!r} -> {after!r}")
            warm = [line for line in server.stderr_lines if "verb=quality_delta" in line]
            self.remove_qsnaps(cache)
            self.quality_delta(server, 5, work)
            cold = [line for line in server.stderr_lines if "verb=quality_delta" in line]
            print(f"  INFO  measured quality_delta timing lines: warm={len(warm)} cold={len(cold)}")
            if not any("ThreadSanitizer" in line for line in server.stderr_lines):
                self.ok("no ThreadSanitizer warning in server stderr (b)")
            else:
                self.no("TSan WARNING in server stderr (b)")
        finally:
            server.close()

    def run_qd_scenario(self, threshold: int) -> str:
        work, cache = self.new_repo()
        geo = work / "geometry.cpp"
        server = Server(self.binary, self.env(cache, threshold))
        try:
            server.call(1, "initialize")
            self.find(server, 2, work, "perimeter")
            with geo.open("ab") as handle:
                handle.write(b"\n// c-scenario edit\n")
            self.git(work, "commit", "-q", "-am", "commit")
            self.find(server, 3, work, "perimeter")
            time.sleep(0.6)
            text = self.quality_delta(server, 4, work)
            return text.replace(str(work), "WORK").replace(str(work).replace("\\", "/"), "WORK")
        finally:
            if any("ThreadSanitizer" in line for line in server.stderr_lines):
                self.no(f"TSan WARNING in server stderr (c/thr={threshold})")
            else:
                self.ok(f"no ThreadSanitizer warning in server stderr (c/thr={threshold})")
            server.close()

    def scenario_c(self) -> None:
        fired = self.run_qd_scenario(1)
        suppressed = self.run_qd_scenario(999999)
        normalize = lambda value: re.sub(r'"at":"[0-9a-f+dirty]*"', '"at":"NORM"', value)
        fired = normalize(fired)
        suppressed = normalize(suppressed)
        if fired == suppressed and fired:
            self.ok(f"(c) quality_delta byte-identical fired-vs-suppressed: {fired[:70]}…")
        else:
            self.no("(c) quality_delta DIVERGED across prefetch on/off")
            mismatch = next((i for i, pair in enumerate(zip(fired, suppressed)) if pair[0] != pair[1]), min(len(fired), len(suppressed)))
            print(f"        first mismatch at byte {mismatch}: fired={fired[max(0, mismatch - 80):mismatch + 160]!r}")
            print(f"        suppressed={suppressed[max(0, mismatch - 80):mismatch + 160]!r}")

    def scenario_d(self) -> None:
        work, cache = self.new_repo()
        geo = work / "geometry.cpp"
        server = Server(self.binary, self.env(cache, 1))
        try:
            server.call(1, "initialize")
            self.find(server, 2, work, "perimeter")
            for index in (1, 2):
                with geo.open("ab") as handle:
                    handle.write(f"\n// rapid move {index}\n".encode())
                self.git(work, "commit", "-q", "-am", f"rapid {index}")
                self.find(server, 10 + index, work, "perimeter")
            time.sleep(0.8)
            response = self.find(server, 99, work, "perimeter")
            if not self.response_text(response).startswith("__ERROR__:"):
                self.ok("(d) server still responsive after two rapid HEAD moves (no crash)")
            else:
                self.no("(d) server returned an error after rapid HEAD moves")
                print(f"        response: {self.response_text(response)[:500]}")
                print("        server stderr: " + " | ".join(server.stderr_lines[-12:]))
            live = 0
            maximum = 0
            for line in server.stderr_lines:
                if "ripwire-prefetch spawn" in line:
                    live += 1
                    maximum = max(maximum, live)
                elif "ripwire-prefetch done" in line:
                    live = max(0, live - 1)
            if maximum <= 1:
                self.ok(f"(d) at most one concurrent prefetch worker (max live={maximum}; single-flight holds)")
            else:
                self.no(f"(d) more than one concurrent worker (max live={maximum}) — single-flight broken")
            if not any("ThreadSanitizer" in line for line in server.stderr_lines):
                self.ok("no ThreadSanitizer warning in server stderr (d)")
            else:
                self.no("TSan WARNING in server stderr (d)")
        finally:
            server.close()

    def run(self) -> int:
        print(f"qsnapprefetchcheck: BIN={self.binary}")
        print("\n=== (a) atomic publish: no torn read — tmp+rename, checksum-valid, no residue ===")
        self.scenario_a()
        print("\n=== (b) NON-VACUITY: commit → prefetch fires (qsnap appears with NO quality_delta) → warm delta ===")
        self.scenario_b()
        print("\n=== (c) DETERMINISM: quality_delta byte-identical prefetch-FIRED vs prefetch-SUPPRESSED ===")
        self.scenario_c()
        print("\n=== (d) SINGLE-FLIGHT: two rapid HEAD moves → no crash, at most one concurrent worker ===")
        self.scenario_d()
        if self.failures:
            print(f"qsnapprefetchcheck: FAIL ({self.failures} failures)")
            return 1
        print("qsnapprefetchcheck: ALL PASS")
        return 0

    def close(self) -> None:
        shutil.rmtree(self.temp, ignore_errors=True)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: qsnapprefetchcheck_windows.py BINARY", file=sys.stderr)
        return 2
    binary = Path(sys.argv[1]).resolve()
    if not binary.is_file():
        print(f"no ripwire binary at {binary}", file=sys.stderr)
        return 2
    gate = Gate(binary)
    try:
        return gate.run()
    except (GateError, OSError, subprocess.SubprocessError) as exc:
        print(f"qsnapprefetchcheck: ERROR: {exc}", file=sys.stderr)
        return 1
    finally:
        gate.close()


if __name__ == "__main__":
    raise SystemExit(main())
