#!/usr/bin/env bash
# mcpwhereiscausecheck.sh — MCP `whereis` / `stray_content` answer on a git tree, and an empty answer names a cause it MEASURED.
#
#   test/mcpwhereiscausecheck.sh [BIN]     # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# THE DEFECT (research audit 2026-11-26, item 4). On this project's own main checkout, MCP `whereis` answered
#   "not a git repository (or no HEAD commit) — no refs to search"
# while the CLI `--whereis` on the same tree answered normally. Measured cause: the MCP freshness watcher (mcpindex.h FsWatcher)
# holds one open descriptor per watched directory, with no cap. That checkout has 45,547 directories, so the watcher held
# 45,547 descriptors, and every descriptor the server opened after it was numbered past 32,767. macOS stdio keeps a FILE's
# descriptor in a `short`, so fdopen() of a larger one fails with EMFILE: every popen() the server made after the index was
# built returned NULL. The git probe behind whereis read that NULL as "no HEAD", and the fallback named that cause for every
# empty return without checking it. The CLI has no watcher, so it never saw the limit.
#
# Arms (each RED on the parent 5f4b50415, GREEN on the fix):
#   (W1) a git fixture with 33,000 directories and the symbol on HEAD: MCP `whereis` answers with on-head="1" (a hit on HEAD).
#   (W2) the same server, the same tree: `stray_content` answers too (the same popen path), not "not a git repository".
#   (W4) the same server, the same tree: MCP `grep` finds the symbol. On the parent it answered files=0 total=0 — a FALSE ZERO
#        with no disclosure (its file reads go through stdio too), found while measuring W1 on the project checkout.
#   (W3) the fallback names what it measured: a directory that is not a git repository says "not a git repository", and a
#        repository with no commit says "no HEAD commit" — never the two-cause "(or no HEAD commit)" guess.
# Control:
#   (C1) a small git fixture answers on every binary (the arms above are not a broken fixture).
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "mcpwhereiscausecheck: python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "mcpwhereiscausecheck: git required"; exit 2; }
. "$ROOT/test/lib/clean-env.sh" 2>/dev/null || true
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "mcpwhereiscausecheck: BIN=$BIN"

BIN="$BIN" TMP="$TMP" python3 -I - <<'PY'
import json, os, subprocess, sys
BIN, TMP = os.environ["BIN"], os.environ["TMP"]
bad = 0


def say(okay, msg):
    global bad
    print("  %s  %s" % ("PASS" if okay else "FAIL", msg))
    bad += 0 if okay else 1


def git(cwd, *args):
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t",
               GIT_AUTHOR_DATE="2026-01-01T00:00:00Z", GIT_COMMITTER_DATE="2026-01-01T00:00:00Z")
    subprocess.run(["git", "-C", cwd] + list(args), check=True, capture_output=True, env=env)


def fixture(name, dirs):
    root = os.path.join(TMP, name)
    os.makedirs(os.path.join(root, "src"))
    with open(os.path.join(root, "src", "a.c"), "w") as f:
        f.write("int where_target(int x) { return x + 1; }\nint caller(int y) { return where_target(y); }\n")
    for i in range(dirs):   # empty directories: the watcher watches every directory, a file in each is not needed
        os.makedirs(os.path.join(root, "tree", "d%03d" % (i // 1000), "e%04d" % i))
    git(root, "init", "-q")
    git(root, "add", "src")
    git(root, "commit", "-q", "-m", "one")
    return root


def mcp(cwd, calls):
    lines = [json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})]
    for i, (tool, args) in enumerate(calls):
        lines.append(json.dumps({"jsonrpc": "2.0", "id": i + 2, "method": "tools/call", "params": {"name": tool, "arguments": args}}))
    r = subprocess.run([BIN, "--mcp", "--no-cache"], input="\n".join(lines) + "\n", capture_output=True, text=True, errors="replace",
                       cwd=cwd, timeout=600)
    out = {}
    for ln in r.stdout.splitlines():
        try:
            m = json.loads(ln)
        except ValueError:
            continue
        out[m.get("id")] = m
    return [out.get(i + 2, {}) for i in range(len(calls))]


def text_of(m):
    if "error" in m:
        return "ERROR " + m["error"].get("message", "")
    return "".join(c.get("text", "") for c in m.get("result", {}).get("content", []))


small = fixture("small", 0)
(w,) = mcp(TMP, [("whereis", {"path": small, "symbol": "where_target"})])
say('on-head="1"' in text_of(w), "(C1) control: MCP whereis on a small git fixture answers with the symbol on HEAD")

big = fixture("big", 33000)
w, s, g = mcp(TMP, [("whereis", {"path": big, "symbol": "where_target"}), ("stray_content", {"path": big}),
                    ("grep", {"path": big, "pattern": "where_target"})])
say('on-head="1"' in text_of(w), "(W1) MCP whereis on a 33,000-directory git fixture answers with the symbol on HEAD (got: %s)" % text_of(w)[:160])
say("ripwire stray-content" in text_of(s) and "not a git repository" not in text_of(s),
    "(W2) MCP stray_content on the same server answers too (got: %s)" % text_of(s)[:160])

gj = {}
try:
    gj = json.loads(text_of(g))
except ValueError:
    pass
say(gj.get("total", 0) >= 2, "(W4) MCP grep on the same server finds the symbol's 2 lines, not a false zero (total=%s)" % gj.get("total"))

plain = os.path.join(TMP, "plain")
os.makedirs(plain)
with open(os.path.join(plain, "a.c"), "w") as f:
    f.write("int where_target(int x) { return x; }\n")
nohead = os.path.join(TMP, "nohead")
os.makedirs(nohead)
with open(os.path.join(nohead, "a.c"), "w") as f:
    f.write("int where_target(int x) { return x; }\n")
git(nohead, "init", "-q")
p, n = mcp(TMP, [("whereis", {"path": plain, "symbol": "where_target"}), ("whereis", {"path": nohead, "symbol": "where_target"})])
pt, nt = text_of(p), text_of(n)
say("not a git repository" in pt and "or no HEAD" not in pt, "(W3a) a non-git directory: the refusal names the measured cause (got: %s)" % pt[:200])
say("no HEAD commit" in nt and "not a git repository" not in nt, "(W3b) a repository with no commit: the refusal says no HEAD commit (got: %s)" % nt[:200])
print("mcpwhereiscausecheck: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
sys.exit(1 if bad else 0)
PY
