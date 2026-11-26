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
# THE RULE. When a result carries any of those keys, the answer itself says the same sentence, key by key, in its own
# form: XML gains a final <notes><n k="KEY">…</n></notes> child (still ONE well-formed document — CI #774 showed a second
# plain-text block breaking every client and gate that joins the blocks), JSON gains a "_notes" member, plain text gains
# trailing "KEY: sentence" lines. content[] stays ONE block.
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
#   (V6) [C] a result with no disclosure has exactly one content block, and a disclosing JSON payload still parses
#   (V7) [P] an XML answer that discloses (impact with path= omitted) is ONE well-formed document, <notes> inside the root
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "mcpenvelopevisiblecheck: python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "mcpenvelopevisiblecheck: git required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "mcpenvelopevisiblecheck: xmllint required"; exit 2; }
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


def said(text, key):
    """What the answer itself says for `key`, in its own form (XML <n k=>, JSON _notes, or a trailing text line)."""
    import html, re
    try:
        j = json.loads(text)
        return j.get("_notes", {}).get(key, "") if isinstance(j, dict) else ""
    except ValueError:
        pass
    m = re.search(r'<n k="%s">(.*?)</n>' % re.escape(key), text, re.S)
    if m:
        return html.unescape(m.group(1))
    m = re.search(r"^%s: (.*)$" % re.escape(key), text, re.M)
    return m.group(1) if m else ""


def visible(m, key, sentence):
    """The envelope's sentence for `key`, said inside the one content block."""
    b = blocks(m)
    return len(b) == 1 and said(b[0], key) == sentence


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
say(bool(note) and len(blocks(r)) == 1 and "_memory_peak" not in blocks(r)[0],
    "(V3) [C] ...and it stays machine-only: no run-dependent peak in the answer (blocks: %d)" % len(blocks(r)))

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
say(env2.get("_fresh") == "reindexed" and len(blocks(r2)) == 1 and all(w in said(blocks(r2)[0], "_fresh") for w in want),
    "(V5) [P] ...and content[] says reindexed with both counts (%s)" % " ".join(want))

# ── (V6) controls ────────────────────────────────────────────────────────────────────────────────────────────────────
say(env2.get("_fresh") != "reindexed" or len(blocks(r1)) == 1,
    "(V6) [C] a result with no disclosure (_fresh=%s) has exactly one content block (%d)" % (r1.get("result", {}).get("_fresh"), len(blocks(r1))))
say(payload_ok, "(V6) [C] the first block of a disclosing result is still the verb's own JSON payload")
# (V7) an XML answer that discloses stays ONE well-formed document, with the notes a child of its root
(rx,) = mcp([("impact", {"symbol": "perimeter"})], cwd=small)
tx = blocks(rx)[0] if blocks(rx) else ""
wf = subprocess.run(["xmllint", "--noout", "-"], input=tx.encode(), capture_output=True).returncode == 0 if tx else False
say(bool(rx.get("result", {}).get("_assumed_root")) and said(tx, "_assumed_root") == rx["result"]["_assumed_root"] and wf
    and tx.rstrip().endswith("</impact>"),
    "(V7) [P] an XML answer carries its note as a <notes> child and is still one well-formed document (xmllint %s)" % ("ok" if wf else "FAILS"))
print("mcpenvelopevisiblecheck: %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
sys.exit(1 if bad else 0)
PY
