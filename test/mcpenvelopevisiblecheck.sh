#!/usr/bin/env bash
# mcpenvelopevisiblecheck.sh — every MCP envelope disclosure is also said INSIDE content[], the only part the model receives.
#
#   test/mcpenvelopevisiblecheck.sh [BIN]     # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# THE DEFECT (research audit 2026-11-26, item 1). A tools/call result carries its disclosures as siblings of `content`:
# `_assumed_root` (no path= was given, the launch directory answered), `_memory_stop` (the memory guard cut the index that
# answered), `_memory_peak` (the run went over its memory limit), `_history_cut` (a git history walk this request read was
# cut), and `_fresh:"reindexed"` with `_stale_files`/`_changed_files` (the tree moved and the index was rebuilt first).
# An MCP host hands the model `content` only: the audit sampled 102 Claude Code results and found 0 carrying `_index` or
# `_fresh`. So "every truncation is disclosed" held for the JSON-RPC client and failed for the agent.
#
# THE RULE. When a result carries any of those keys, `content` carries a second text block that says the same sentence,
# key by key, one "<key>: <sentence>" line each (never opening with '[' or '{': no reader may take it for a JSON payload).
# `_memory_peak` is the one exception, and the gate pins it: the answer it rides is whole, its number differs run to run,
# and the CLI says it on stderr only — so it stays machine-only, and a deterministic answer stays byte-identical. The verb's own payload (the first block) is untouched, so a JSON payload stays parseable. A result that carries
# none of them is byte-identical to before: one content block.
#
# Arms ([P] RED on the parent 5f4b50415; [C] holds on every binary):
#   (V1..V5) [C] the envelope key is forced and present — without this each [P] arm below would judge nothing.
#   (V1) [P] _assumed_root      bare --mcp launched in the fixture, path= omitted
#   (V2) [P] _memory_stop       RIPWIRE_TEST_MEMGUARD=crawl:30 under --max-memory=64M (memguardcheck's B6 recipe)
#   (V3) [C] _memory_peak       RIPWIRE_TEST_MEMGUARD=peak:1 under --max-memory=64M: in the envelope, NOT in content[]
#   (V4) [P] _history_cut       RIPWIRE_GIT_WALK_COMMITS=100 over a 130-commit history (historywalkcheck's M1 recipe)
#   (V5) [P] _fresh:"reindexed" a file edited between two calls; the block names both counts with the envelope's values
#   (V6) [C] a result with no disclosure has exactly one content block, and the first block of a disclosing result still
#            parses as the verb's JSON (the payload was not touched)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "mcpenvelopevisiblecheck: python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "mcpenvelopevisiblecheck: git required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "mcpenvelopevisiblecheck: BIN=$BIN"

BIN="$BIN" TMP="$TMP" python3 -I - <<'PY'
import json, os, subprocess, sys
BIN, TMP = os.environ["BIN"], os.environ["TMP"]
bad = 0


def say(okay, msg):
    global bad
    print("  %s  %s" % ("PASS" if okay else "FAIL", msg))
    bad += 0 if okay else 1


def write(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(s)


def mcp(calls, cwd=TMP, extra=(), env=None, between=None):
    """calls: [(tool, args)]; between: {index: fn} run after that call's response is read (a live session)."""
    e = dict(os.environ)
    e.update(env or {})
    p = subprocess.Popen([BIN, "--mcp", "--no-cache"] + list(extra), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, errors="replace", cwd=cwd, env=e)
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}) + "\n")
    p.stdin.flush()
    p.stdout.readline()
    out = []
    for i, (tool, args) in enumerate(calls):
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": i + 2, "method": "tools/call", "params": {"name": tool, "arguments": args}}) + "\n")
        p.stdin.flush()
        line = p.stdout.readline()
        try:
            out.append(json.loads(line))
        except ValueError:
            out.append({})
        if between and i in between:
            between[i]()
    p.stdin.close()
    p.wait(timeout=300)
    return out


def blocks(m):
    return [c.get("text", "") for c in m.get("result", {}).get("content", [])]


def visible(m, key, sentence):
    """The envelope's sentence for `key`, said in a content block other than the payload."""
    return any(sentence in b and key in b for b in blocks(m)[1:])


# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────────────────────
small = os.path.join(TMP, "small")
write(os.path.join(small, "a.c"), "int perimeter(int w, int h) { return 2 * (w + h); }\nint area(int w, int h) { return w * h; }\n")
many = os.path.join(TMP, "many")
for d in "abcd":
    for k in range(18):
        write(os.path.join(many, d, "f%02d.c" % k), "int %s_%02d(int x) { return x + %d; }\n" % (d, k, k))
hist = os.path.join(TMP, "hist")
write(os.path.join(hist, "m1.c"), "int f1(int x) { return x; }\n")
write(os.path.join(hist, "m2.c"), "int f2(int x) { return x; }\n")
genv = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
subprocess.run(["git", "-C", hist, "init", "-q"], check=True, env=genv)
fi = "".join("commit refs/heads/main\nmark :%d\ncommitter t <t@t> %d +0000\ndata 2\nc\n%sM 100644 inline m1.c\ndata %d\n%s\n"
             "M 100644 inline m2.c\ndata %d\n%s\n" % (i + 1, 1700000000 + i, ("from :%d\n" % i) if i else "",
                                                     len("int f1(int x) { return x + %d; }\n" % i), "int f1(int x) { return x + %d; }\n" % i,
                                                     len("int f2(int x) { return x - %d; }\n" % i), "int f2(int x) { return x - %d; }\n" % i)
             for i in range(130))
subprocess.run(["git", "-C", hist, "fast-import", "--quiet"], input=fi, text=True, check=True, env=genv)
subprocess.run(["git", "-C", hist, "checkout", "-q", "-f", "main"], check=True, env=genv)

# ── (V1) _assumed_root ───────────────────────────────────────────────────────────────────────────────────────────────
(r,) = mcp([("find_symbol", {"symbol": "perimeter"})], cwd=small)
note = r.get("result", {}).get("_assumed_root", "")
say(bool(note), "(V1) [C] an omitted path= is disclosed in the envelope (_assumed_root present)")
say(bool(note) and visible(r, "_assumed_root", note), "(V1) [P] ...and the same sentence is in content[] (blocks: %d)" % len(blocks(r)))

# ── (V2) _memory_stop ────────────────────────────────────────────────────────────────────────────────────────────────
(r,) = mcp([("grep", {"path": many, "pattern": "a_01"})], extra=["--max-memory=64M"], env={"RIPWIRE_TEST_MEMGUARD": "crawl:30"})
note = r.get("result", {}).get("_memory_stop", "")
say(bool(note), "(V2) [C] the memory guard's crawl stop is disclosed in the envelope (_memory_stop present)")
say(bool(note) and visible(r, "_memory_stop", note), "(V2) [P] ...and the same sentence is in content[] (blocks: %d)" % len(blocks(r)))
try:
    json.loads(blocks(r)[0])
    payload_ok = True
except (ValueError, IndexError):
    payload_ok = False

# ── (V3) _memory_peak ────────────────────────────────────────────────────────────────────────────────────────────────
(r,) = mcp([("grep", {"path": small, "pattern": "perimeter"})], extra=["--max-memory=64M"], env={"RIPWIRE_TEST_MEMGUARD": "peak:1"})
note = r.get("result", {}).get("_memory_peak", "")
say(bool(note), "(V3) [C] a run over its memory limit is disclosed in the envelope (_memory_peak present)")
say(bool(note) and len(blocks(r)) == 1, "(V3) [C] ...and it stays machine-only: one content block, no run-dependent peak in the answer (blocks: %d)" % len(blocks(r)))

# ── (V4) _history_cut ────────────────────────────────────────────────────────────────────────────────────────────────
(r,) = mcp([("cochange", {"path": hist, "file": "m1.c"})], cwd=hist, env={"RIPWIRE_GIT_WALK_COMMITS": "100"})
note = r.get("result", {}).get("_history_cut", "")
say(bool(note), "(V4) [C] a cut git history walk is disclosed in the envelope (_history_cut present)")
say(bool(note) and visible(r, "_history_cut", note), "(V4) [P] ...and the same sentence is in content[] (blocks: %d)" % len(blocks(r)))

# ── (V5) _fresh:"reindexed" ──────────────────────────────────────────────────────────────────────────────────────────
edit = lambda: write(os.path.join(small, "a.c"), "int perimeter(int w, int h) { return 2 * (w + h); }\nint area(int w, int h) { return w * h; }\n"
                                                  "int volume(int w, int h, int d) { return area(w, h) * d; }\n")
r1, r2 = mcp([("grep", {"path": small, "pattern": "area"}), ("grep", {"path": small, "pattern": "area"})], between={0: edit})
env2 = r2.get("result", {})
say(env2.get("_fresh") == "reindexed", "(V5) [C] the edit between two calls is disclosed in the envelope (_fresh=%s)" % env2.get("_fresh"))
want = ["reindexed", "_stale_files=%s" % env2.get("_stale_files"), "_changed_files=%s" % env2.get("_changed_files")]
say(env2.get("_fresh") == "reindexed" and any(all(w in b for w in want) and "_fresh" in b for b in blocks(r2)[1:]),
    "(V5) [P] ...and content[] says reindexed with both counts (%s)" % " ".join(want))

# ── (V6) controls ────────────────────────────────────────────────────────────────────────────────────────────────────
say(env2.get("_fresh") != "reindexed" or len(blocks(r1)) == 1,
    "(V6) [C] a result with no disclosure (_fresh=%s) has exactly one content block (%d)" % (r1.get("result", {}).get("_fresh"), len(blocks(r1))))
say(payload_ok, "(V6) [C] the first block of a disclosing result is still the verb's own JSON payload")
notes = [b for m in (r2,) for b in blocks(m)[1:]]
say(bool(notes) and all(not ln.lstrip()[:1] in ("[", "{") for b in notes for ln in b.split("\n")),
    "(V6) [C] no visible-notes line opens with '[' or '{' (a JSON-sniffing reader must not take it for a payload)")
print("mcpenvelopevisiblecheck: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
sys.exit(1 if bad else 0)
PY
