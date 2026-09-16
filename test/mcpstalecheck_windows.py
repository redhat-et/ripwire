import json
import os
import subprocess
import sys


def fail(message):
    print(f"  FAIL  {message}")
    raise SystemExit(1)


def ok(message):
    print(f"  PASS  {message}")


class Server:
    def __init__(self, binary):
        self.process = subprocess.Popen(
            [binary, "--mcp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        self.next_id = 0

    def call(self, method, arguments=None):
        self.next_id += 1
        request = {
            "jsonrpc": "2.0",
            "id": self.next_id,
            "method": method,
        }
        if arguments is not None:
            request["params"] = arguments
        self.process.stdin.write(json.dumps(request, separators=(",", ":")).encode() + b"\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline()
        if not line:
            fail(f"server exited before answering id={self.next_id} (rc={self.process.poll()})")
        try:
            return json.loads(line)
        except json.JSONDecodeError as exc:
            fail(f"server returned invalid JSON for id={self.next_id}: {line!r} ({exc})")

    def close(self):
        try:
            self.process.stdin.close()
            self.process.wait(timeout=20)
        except Exception:
            self.process.kill()
            self.process.wait(timeout=20)


def tool(server, path, symbol):
    return server.call(
        "tools/call",
        {
            "name": "find_symbol",
            "arguments": {"path": path, "symbol": symbol},
        },
    )


def content(response):
    if "error" in response:
        error = response["error"]
        return "__ERROR__:" + str(error.get("message", ""))
    return response["result"]["content"][0]["text"]


def stamp(response):
    return response.get("result", {}).get("_index", "")


def main():
    if len(sys.argv) != 3:
        print("usage: mcpstalecheck_windows.py BINARY WORK", file=sys.stderr)
        return 2
    binary = os.path.abspath(sys.argv[1])
    work = os.path.abspath(sys.argv[2])
    geo = os.path.join(work, "geometry.cpp")
    if not os.path.isfile(binary) or not os.path.isfile(geo):
        print(f"missing binary or fixture: {binary} {geo}", file=sys.stderr)
        return 2

    original = open(geo, "rb").read()
    original_stat = os.stat(geo)
    parent = os.stat(work)
    server = Server(binary)
    try:
        server.call("initialize")
        before = tool(server, work, "distanceXY")
        stamp_before_response = tool(server, work, "perimeter")
        before_text = content(before)
        before_stamp = stamp(stamp_before_response)
        if not before_text.startswith("__ERROR__:"):
            fail("warm-up: distanceXY unexpectedly resolves pre-edit")
        ok("warm-up: find_symbol('distanceXY') MISSES pre-edit")

        original = open(geo, "rb").read()
        original_stat = os.stat(geo)
        parent = os.stat(work)
        edited = original.replace(b"distance", b"distanceXY")
        if edited == original or len(edited) == len(original):
            fail("edit did not change content length")
        with open(geo, "wb") as handle:
            handle.write(edited)
        os.utime(geo, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))
        os.utime(work, ns=(parent.st_atime_ns, parent.st_mtime_ns))
        if os.stat(geo).st_mtime_ns != original_stat.st_mtime_ns:
            fail("file mtime was not restored")
        ok("edit's MTIME was restored (size remains the discriminator)")

        after = tool(server, work, "distanceXY")
        stamp_after_response = tool(server, work, "perimeter")
        after_text = content(after)
        after_stamp = stamp(stamp_after_response)
        if after_text.startswith("__ERROR__:"):
            fail("post-edit: distanceXY still misses; index stayed stale")
        ok("post-edit: find_symbol('distanceXY') resolves after the size-preserving mtime attack")
        if before_text == after_text:
            fail("post-edit: find_symbol response stayed byte-identical")
        ok("post-edit: find_symbol response changed")
        if not before_stamp or before_stamp == after_stamp:
            fail(f"_index stamp did not change (before={before_stamp!r} after={after_stamp!r})")
        ok("_index stamp changed after the content edit")
    finally:
        server.close()
        with open(geo, "wb") as handle:
            handle.write(original)
        os.utime(geo, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))
        os.utime(work, ns=(parent.st_atime_ns, parent.st_mtime_ns))
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
