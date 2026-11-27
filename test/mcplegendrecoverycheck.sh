#!/usr/bin/env bash
# mcplegendrecoverycheck.sh — every MCP answer in the legend="ref" posture names, INSIDE the answer, where its definitions are.
#
#   test/mcplegendrecoverycheck.sh [BIN]     # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# THE DEFECT (research audit 2026-11-26, item 6). Over MCP the session's first answer defines its attributes inline and later
# answers end with <about legend="ref" …/>, assuming the reader still holds that first answer. A client can remove it: Claude
# Code compaction, or the API's context editing (`clear_tool_uses` keeps the last 3 tool results by default). The only text
# naming the recovery was the `initialize` instructions; the answer itself said dict="ripwire --legend-dict", a CLI command
# an MCP-only agent may have no way to run. The server cannot observe a clear, so the answer has to carry the way back.
#
# THE RULE. Over MCP, the <about legend="ref"> pointer's dict= names the resource ripwire://legend-dict/full, and that
# resource reads back the definitions. No new attribute: the existing dict= says it, so no verb dialect gains a word.
#
# Arms (RED on the parent 5f4b50415 where marked [P]):
#   (R0) [C] the session reaches the ref posture at least 3 times (standalone verbs and a batch sub-answer) — without this the
#        prohibition below would pass on a session that never took the posture.
#   (R1) [P] every answer text carrying legend="ref" names dict="ripwire://legend-dict/full".
#   (R2) [P] no MCP answer names the CLI pointer dict="ripwire --legend-dict".
#   (R3) [C] resources/read of the named URI answers the dictionary text (the pointer resolves on this server).
#   (R4) [C] the CLI handshake's ref posture (--legend-have=) is unchanged: it still points at `ripwire --legend-dict`.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "mcplegendrecoverycheck: python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "mcplegendrecoverycheck: BIN=$BIN"

BIN="$BIN" TMP="$TMP" python3 -I - <<'PY'
import json, os, subprocess, sys
BIN, TMP = os.environ["BIN"], os.environ["TMP"]
bad = 0
URI = "ripwire://legend-dict/full"


def say(okay, msg):
    global bad
    print("  %s  %s" % ("PASS" if okay else "FAIL", msg))
    bad += 0 if okay else 1


fx = os.path.join(TMP, "fx")
os.makedirs(os.path.join(fx, "src"))
# 12 files x 10 functions, each calling the one before it and leaf(): answers large enough that the ref posture pays
for m in range(12):
    with open(os.path.join(fx, "src", "m%02d.c" % m), "w") as f:
        f.write("int leaf(int x);\nint mid(int x);\nint top(int x);\n")
        for k in range(10):
            prev = "leaf" if k == 0 else "f%02d_%d" % (m, k - 1)
            f.write("int f%02d_%d(int x) { return %s(x) + leaf(x) + mid(x); }\n" % (m, k, prev))
with open(os.path.join(fx, "src", "a.c"), "w") as f:
    f.write("int leaf(int x) { return x * 2; }\nint mid(int x) { return leaf(x) + 1; }\nint top(int x) { return mid(x) + leaf(x); }\n"
            "int other(int y) { return top(y) - mid(y); }\n")

calls = [("impact", {"path": fx, "symbol": "leaf"}), ("impact", {"path": fx, "symbol": "mid"}),
         ("uses", {"path": fx, "symbol": "leaf"}), ("uses", {"path": fx, "symbol": "mid"}),
         ("impact", {"path": fx, "symbol": "top"}),
         ("batch", {"path": fx, "queries": [{"verb": "impact", "symbol": "other"}, {"verb": "uses", "symbol": "top"}]})]
lines = [json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})]
for i, (tool, args) in enumerate(calls):
    lines.append(json.dumps({"jsonrpc": "2.0", "id": i + 2, "method": "tools/call", "params": {"name": tool, "arguments": args}}))
lines.append(json.dumps({"jsonrpc": "2.0", "id": 99, "method": "resources/read", "params": {"uri": URI}}))
r = subprocess.run([BIN, "--mcp", "--no-cache"], input="\n".join(lines) + "\n", capture_output=True, text=True, errors="replace", timeout=300)
msgs = {}
for ln in r.stdout.splitlines():
    try:
        m = json.loads(ln)
    except ValueError:
        continue
    msgs[m.get("id")] = m
texts = ["".join(c.get("text", "") for c in msgs.get(i + 2, {}).get("result", {}).get("content", [])) for i in range(len(calls))]
import re
POINTER = re.compile(r'<about legend="ref"[^>]*/>')
pointers = [(calls[i][0], p) for i, t in enumerate(texts) for p in POINTER.findall(t)]
say(len(pointers) >= 3, "(R0) the session took the ref posture %d times (>= 3: the prohibition below has answers to judge)" % len(pointers))
missing = sorted({v for v, p in pointers if ('dict="%s"' % URI) not in p})
say(len(pointers) >= 3 and not missing, "(R1) every <about legend=\"ref\"> pointer names dict=\"%s\" (verbs whose do not: %s)" % (URI, missing or "none"))
cli = sorted({calls[i][0] for i, t in enumerate(texts) if 'dict="ripwire --legend-dict"' in t})
say(not cli, "(R2) no MCP answer points at the CLI command dict=\"ripwire --legend-dict\" (verbs that do: %s)" % (cli or "none"))
res = msgs.get(99, {}).get("result", {}).get("contents", [])
body = "".join(c.get("text", "") for c in res)
say(len(body) > 1000 and "legend=\"ref\"" in body, "(R3) resources/read %s answers the dictionary (%d chars)" % (URI, len(body)))
have = subprocess.run([BIN, "--legend-dict=core"], capture_output=True, text=True, errors="replace").stdout.split("\n", 1)[0]
m = re.search(r"have=([0-9a-f]+)", have)
c = subprocess.run([BIN, fx, "--impact=leaf", "--legend-have=" + (m.group(1) if m else "x"), "--no-cache"], capture_output=True, text=True, errors="replace")
say('<about legend="ref" have="core" dict="ripwire --legend-dict"' in c.stdout,
    "(R4) the CLI handshake's ref pointer is unchanged (dict=\"ripwire --legend-dict\": a CLI reader runs that command)")
print("mcplegendrecoverycheck: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
sys.exit(1 if bad else 0)
PY
