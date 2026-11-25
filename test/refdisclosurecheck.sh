#!/usr/bin/env bash
# refdisclosurecheck.sh — A FACT IS NEVER RELOCATED: every completeness, cut, floor and provenance attribute an answer
# carries is on its ROOT, in the prefix, under EVERY legend posture (src/legenddict.h).
#
# THE DEFECT THIS HOLDS SHUT. Until this gate, the legend="ref" posture (the CLI handshake --legend-have=DICTV, and the
# MCP stdio default from a session's second reducible answer onward) MOVED every root attribute but task=/changed=/
# from=/to= onto a trailing <about> element. The handshake's purpose is to stop re-sending DEFINITIONS; that move
# relocated FACTS. A reader that holds rows but cannot see `capped="1" has_more="1" counts_floor="1"` believes it holds
# the whole set, which is a wrong answer and not a short one. Measured on the unfixed binary (2026-11-17, five corpora,
# 110 handshake calls, 103 took the posture): <about> was not wholly inside the first 2 KB in 27 answers and not inside
# 4 KB in 16; of the 28 ref answers over 2 KB, 22 had a complete row in the prefix while an ACTIVE cut or floor sat
# beyond it. A live MCP session put route= root= confidence= at byte 16,502 of a 16,784 B `for` answer.
#
# THE INVARIANT. Under the default, --legend=full, the handshake and an MCP session answer alike:
#   - the root open tag carries every attribute the inline answer's root carries, same order, same values;
#   - <about legend="ref" [have=] dict= dictv=/> is a POINTER: it carries those attributes and nothing else;
#   - the root open tag ends before the first row. Under ref it ends inside the first 2,048 bytes of the answer; inline
#     it ends within 2,048 bytes of the end of the legend that precedes it (where an inline legend sits is --legend=last's
#     business, not this gate's);
#   - the map header comment (the legend calls it data: files= shown= unindexed=) stays where the inline answer has it.
# The byte cost is zero: the same bytes, in a different place. (F) asserts a ref answer is never longer than its twin.
#
# ARMS
#   (A) THE INVARIANT, every posture, on a fixture that this gate builds and whose answers really are cut.
#   (B) NON-VACUITY. The fixture has 64 callers of one function against a 40-row default window, one file no grammar
#       reads, and the arm counts the ref answers that carry capped="1", has_more="1", counts_floor="1", and that are
#       longer than the prefix. An arm that only ever saw uncapped answers would prove nothing.
#   (C) MUTATION CONTROLS, each of which must go RED. Delete a disclosure from a capped answer (the reader-protecting
#       direction: caught against the inline twin AND by the answer's own shown= < total=); relocate one to the trailer;
#       relocate them all (the pre-fix shape); push the root past the prefix; delete one from an INLINE answer.
#   (D) capped="1" WITH shown == total. Read over every element of every sampled answer. Two readings are in the
#       vocabulary (src/pageview.h rules 4 and 5): a floor marker beside it (the total itself is a floor) and a
#       byte-trimmed <sigs> ("rows shrunk, none dropped", defined in band by the answer). Anything else misstates a cut.
#   (E) DETERMINISM. Every CLI answer and the whole MCP session, twice, byte-identical.
#   (F) THE NON-REF POSTURES DID NOT MOVE. A handshake answer the dictionary cannot reduce is the default answer byte
#       for byte; a ref answer minus its legend and pointer is its inline twin minus its legend; no ref answer is longer
#       than its twin. With REFDISCLOSURE_BASE_BIN=<a pre-change binary> the default, --legend=full and --mcp-legend=inline
#       answers are compared across the two binaries byte for byte; without it that comparison is NOT RUN and says so.
#
#   bash test/refdisclosurecheck.sh "$PWD/build/ripwire"

set -u
# θ5 (src/forpages.h): this gate reads the FULL page-1 legend of a default --for answer (or pins its bytes/rows); the default's
# core legend is pinned by test/corelegendcheck.sh, so the full legend is switched back on here.
export RIPWIRE_NO_CORE_LEGEND=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BASE_BIN="${REFDISCLOSURE_BASE_BIN:-}"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "refdisclosurecheck: BIN=$BIN"
fail=0
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

cat >"$TMP/arms.py" <<'PY'
import json, re, subprocess, sys
BIN, FX, BASE = sys.argv[1], sys.argv[2], sys.argv[3]
PREFIX = 2048
POINTER = ["legend", "have", "dict", "dictv"]   # have= (lane dict-core-packs): the tiers a CLI caller named — which definitions were left out, not a fact about the rows
fails = []
def ok(m):  print(f"  PASS  {m}")
def no(m):  print(f"  FAIL  {m}"); fails.append(m)
def check(c, m): (ok if c else no)(m)

def cli(binary, *flags):
    r = subprocess.run([binary, FX, *flags], capture_output=True, cwd=FX)
    return r.stdout.decode(errors="replace")
def session(binary, calls, server=()):
    reqs = [{"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}}]
    for i, (name, args) in enumerate(calls, 1):
        reqs.append({"jsonrpc": "2.0", "id": i, "method": "tools/call", "params": {"name": name, "arguments": dict(args, path=FX)}})
    p = subprocess.run([binary, "--mcp", *server], input="".join(json.dumps(r) + "\n" for r in reqs).encode(), capture_output=True, cwd=FX)
    out = {}
    for line in p.stdout.decode(errors="replace").splitlines():
        if not line.strip(): continue
        j = json.loads(line); r = j.get("result") or {}
        if "content" in r: out[j["id"]] = r["content"][0]["text"]
    return [out.get(i, "") for i in range(1, len(calls) + 1)]

ATTR  = re.compile(r'\s([\w:.-]+)="([^"]*)"')
HEAD  = re.compile(r'\s*(?:<\?xml[^>]*\?>\s*)?((?:<!--.*?-->\s*)*)<([A-Za-z_][\w.-]*)((?:\s+[\w:.-]+="[^"]*")*)\s*(/?)>', re.S)
ABOUT = re.compile(r'<about((?:\s+[\w:.-]+="[^"]*")*)\s*/>')
MAPHDR = re.compile(r'<!-- files=\d+ symbols=\d+ [^>]*?-->')
def no_cdata(t):    return re.sub(r'<!\[CDATA\[.*?\]\]>', '', t, flags=re.S)
def no_comments(t): return re.sub(r'<!--.*?-->', '', no_cdata(t), flags=re.S)
def is_ref(t):      return any(' legend="ref"' in m.group(0) for m in ABOUT.finditer(no_comments(t)))
def is_xml(t):      return HEAD.match(t) is not None
def root_of(t):
    """(tag, [(name, value)], byte offset where the root open tag ends, bytes of legend before it)"""
    m = HEAD.match(t)
    return (m.group(2), ATTR.findall(m.group(3)), len(t[:m.end()].encode()), len(t[:m.start(2) - 1].encode()))
def strip_price(av): return [(k, "" if k == "est_tokens" else v) for k, v in av]
def skeleton(t):
    """The answer with its legend, its pointer and its delivered price taken out: what must not differ between postures."""
    s = re.sub(r'<!--.*?-->', '', t, flags=re.S)
    s = ABOUT.sub(lambda m: "" if ' legend="ref"' in m.group(0) else m.group(0), s)
    return re.sub(r' est_tokens="\d+"', ' est_tokens=""', s).strip()

def violations(t, twin, ref):
    """Every way answer `t` breaks the invariant. `twin` is the same call's inline answer (None: no twin to read)."""
    v = []
    if not is_xml(t):
        return ["shape: not an XML answer"]
    tag, av, root_end, legend_bytes = root_of(t)
    body = no_comments(t)
    for m in ABOUT.finditer(body):
        names = [k for k, _ in ATTR.findall(m.group(1))]
        if "legend" in names and not ref:
            v.append("pointer: an inline answer carries <about legend=>")
        extra = [k for k in names if k not in POINTER] if "legend" in names else []
        if extra:
            v.append("trailer: <about> carries facts, not only the legend pointer: " + ",".join(extra[:8]))
    if ref and not is_ref(t):
        v.append("pointer: a ref answer has no <about legend=\"ref\">")
    if (root_end > PREFIX) if ref else (root_end - legend_bytes > PREFIX):
        v.append(f"prefix: the root open tag ends at byte {root_end} ({legend_bytes} B of legend before it), past the {PREFIX} B prefix")
    d = dict(av)
    if "shown" in d and "total" in d and d["shown"].isdigit() and d["total"].isdigit():
        if int(d["shown"]) < int(d["total"]) and d.get("capped") != "1":
            v.append(f"self: the root says shown={d['shown']} of total={d['total']} and does not say capped=\"1\"")
    if d.get("capped") == "1" and "total" in d and ("has_more" not in d or "next_offset" not in d):
        v.append("self: the root says capped=\"1\" and cannot be paged (has_more= / next_offset= missing)")
    if twin is not None and is_xml(twin):
        _, tav, _, _ = root_of(twin)
        if strip_price(av) != strip_price(tav):
            gone = [k for k, _ in tav if k not in d]
            v.append("twin: the root differs from the inline answer's root" + (" — missing " + ",".join(gone[:8]) if gone else " (order or value)"))
        if "<g " not in twin and skeleton(t) != skeleton(twin):
            v.append("twin: the answer minus legend and pointer is not the inline answer minus legend")
        tw_hdr, my_hdr = MAPHDR.search(twin), MAPHDR.search(t)
        if tw_hdr and twin.find(tw_hdr.group(0)) < twin.find("</") and not (my_hdr and t.find(my_hdr.group(0)) <= root_end + len(my_hdr.group(0)) + PREFIX and len(t[:t.find(my_hdr.group(0))].encode()) <= PREFIX):
            v.append("header: the map header comment (data) left the prefix")
    return v

DICT_HEAD = subprocess.run([BIN, "--legend-dict"], capture_output=True, text=True).stdout.splitlines()
DV = (re.search(r'dictv=([0-9a-f]{16})', DICT_HEAD[0]) if DICT_HEAD else None)
if DV is None:
    no("(setup) --legend-dict prints no dictv= — the handshake has no version to name"); sys.exit(1)
DV = DV.group(1)

VERBS = [["--impact=helper"], ["--callers=helper"], ["--uses=helper"], ["--callees=top"], ["--grep=helper"], ["--whereis=helper"],
         ["--dead-code"], ["--hotspots"], ["--impact=helper", "--limit=5"], ["--callees=top", "--limit=7", "--offset=3"], [],
         ["--for=which caller adds the helper"], ["--pack-task=add one more caller of the helper"], ["--impact=helper", "--json"]]
CALLS = [("impact", {"symbol": "helper"}), ("impact", {"symbol": "top"}), ("uses", {"symbol": "helper"}),
         ("for", {"task": "which caller adds the helper"}), ("analyze", {}), ("explore", {"task": "add one more caller of the helper"}),
         ("impact", {"symbol": "helper"}), ("impact", {"symbol": "top"}), ("uses", {"symbol": "helper"}),
         ("for", {"task": "which caller adds the helper"}), ("analyze", {}), ("explore", {"task": "add one more caller of the helper"}),
         ("batch", {"queries": [{"verb": "impact", "symbol": "helper"}, {"verb": "uses", "symbol": "helper"}]})]
name = lambda f: " ".join(f) or "(map)"

default = {name(f): cli(BIN, *f) for f in VERBS}
full    = {name(f): cli(BIN, *f, "--legend=full") for f in VERBS}
have    = {name(f): cli(BIN, *f, "--legend-have=" + DV) for f in VERBS}
mcp     = session(BIN, CALLS)
mcp_in  = session(BIN, CALLS, server=["--mcp-legend=inline"])

# ── (A) the invariant, every posture ────────────────────────────────────────────────────────────────────────────────
print("=== (A) every disclosure is on the root, in the prefix, under every posture ===")
subjects = []      # (posture, label, text, twin, ref)
for k, t in default.items():
    if is_xml(t): subjects.append(("default", k, t, None, False))
for k, t in full.items():
    if is_xml(t): subjects.append(("--legend=full", k, t, None, False))
for k, t in have.items():
    if is_xml(t): subjects.append(("handshake", k, t, default[k], is_ref(t)))
for i, t in enumerate(mcp):
    if is_xml(t): subjects.append(("mcp", f"#{i + 1} {CALLS[i][0]}", t, mcp_in[i], is_ref(t)))
for posture in ("default", "--legend=full", "handshake", "mcp"):
    mine = [s for s in subjects if s[0] == posture]
    bad = [(label, violations(t, twin, ref)) for _, label, t, twin, ref in mine]
    bad = [(l, v) for l, v in bad if v]
    nref = sum(1 for s in mine if s[4])
    check(mine and not bad, f"(A) {posture}: {len(mine)} XML answers ({nref} ref), every one holds the invariant"
          + ("" if not bad else f" — {len(bad)} do not; first: {bad[0][0]}: {bad[0][1][0]}"))
refs = [s for s in subjects if s[4]]
ends = sorted(root_of(t)[2] for _, _, t, _, _ in refs)
check(refs and ends[-1] <= PREFIX, f"(A) over {len(refs)} ref answers the root open tag ends at byte {ends[0] if ends else '-'}..{ends[-1] if ends else '-'} (prefix {PREFIX})")
# a batch answer's sub-answers took the posture one by one, inside CDATA: the pointer rule holds there too
subs = [m for t in mcp for m in ABOUT.finditer(t) if ' legend="ref"' in m.group(0)]
subbad = [m.group(0)[:80] for m in subs if [k for k, _ in ATTR.findall(m.group(1)) if k not in POINTER]]
check(subs and not subbad, f"(A) all {len(subs)} <about legend=\"ref\"> elements the MCP session sent (batch sub-answers included) are pointers only ({subbad[:1]})")

# ── (B) non-vacuity ─────────────────────────────────────────────────────────────────────────────────────────────────
print("=== (B) the sampled answers really are cut, floored, and longer than the prefix ===")
callers = len(re.findall(r'^int caller_\d+\(', open(FX + "/src/core.c").read(), flags=re.M))
check(callers == 64, f"(B) the fixture holds the {callers} callers this arm counts on (64 against a 40-row default window)")
def all_attrs(t):
    """Root and trailer together: where a disclosure may sit on EITHER side of the fix, so this arm reads the subject, not the verdict."""
    av = list(root_of(t)[1])
    for m in ABOUT.finditer(no_comments(t)): av += ATTR.findall(m.group(1))
    return dict(av)
def count(pred): return sum(1 for _, _, t, _, _ in refs if pred(all_attrs(t), t))
ncap   = count(lambda d, t: d.get("capped") == "1" and d.get("shown", "0").isdigit() and d.get("total", "0").isdigit() and int(d["shown"]) < int(d["total"]))
nmore  = count(lambda d, t: d.get("has_more") == "1" and d.get("next_offset", "").isdigit())
nfloor = count(lambda d, t: d.get("counts_floor") == "1")
nbig   = count(lambda d, t: len(t.encode()) > PREFIX)
ncut_big = count(lambda d, t: len(t.encode()) > PREFIX and (d.get("capped") == "1" or d.get("counts_floor") == "1"))
check(ncap >= 2,   f"(B) {ncap} ref answers carry an ACTIVE row cut (capped=\"1\", shown < total) — need 2")
check(nmore >= 2,  f"(B) {nmore} ref answers carry has_more=\"1\" with a next_offset= — need 2")
check(nfloor >= 3, f"(B) {nfloor} ref answers carry counts_floor=\"1\" — need 3")
check(ncut_big >= 3, f"(B) {ncut_big} of the {nbig} ref answers longer than {PREFIX} B carry an active cut or floor — the case a relocated disclosure hides; need 3")
mcpref = [s for s in refs if s[0] == "mcp"]
check(len(mcpref) >= 4 and any(all_attrs(s[2]).get("capped") == "1" for s in mcpref),
      f"(B) the MCP session itself reached the ref posture ({len(mcpref)} answers) and one of them is cut")

# ── (C) mutation controls ───────────────────────────────────────────────────────────────────────────────────────────
print("=== (C) mutation controls: each must go RED ===")
def subject(posture, want_ref):
    for p, label, t, twin, ref in subjects:
        d = dict(root_of(t)[1])
        if p == posture and ref == want_ref and d.get("capped") == "1" and d.get("has_more") == "1" and d.get("counts_floor") == "1" and not violations(t, twin, ref):
            return label, t, twin
    return None
def root_edit(t, fn):
    m = HEAD.match(t); return t[:m.start(3)] + fn(m.group(3)) + t[m.end(3):]
def to_trailer(t, picked):
    m = HEAD.match(t); moved = "".join(f' {k}="{v}"' for k, v in ATTR.findall(m.group(3)) if picked(k))
    kept = "".join(f' {k}="{v}"' for k, v in ATTR.findall(m.group(3)) if not picked(k))
    out = t[:m.start(3)] + kept + t[m.end(3):]
    return out.replace('<about legend="ref"', '<about' + moved + ' legend="ref"', 1)
def must_red(label, mutated, twin, ref, *wanted):
    v = violations(mutated, twin, ref)
    missing = [w for w in wanted if not any(x.startswith(w + ":") for x in v)]
    check(v and not missing, f"(C) {label} -> RED ({'; '.join(x.split(' — ')[0][:70] for x in v[:3]) or 'NOT CAUGHT'})" + (f" — arm(s) silent: {missing}" if missing else ""))
for posture in ("handshake", "mcp"):
    s = subject(posture, True)
    if s is None:
        no(f"(C) {posture}: no capped, floored ref answer holds the invariant, so there is nothing to mutate — every control below is unproven")
        continue
    label, t, twin = s
    must_red(f"{posture} [{label}] delete capped=\"1\" from the root (the reader would hold rows and believe them complete)",
             root_edit(t, lambda a: a.replace(' capped="1"', '')), twin, True, "twin", "self")
    must_red(f"{posture} [{label}] the same deletion with NO inline twin to compare against",
             root_edit(t, lambda a: a.replace(' capped="1"', '')), None, True, "self")
    must_red(f"{posture} [{label}] delete counts_floor=\"1\" from the root", root_edit(t, lambda a: a.replace(' counts_floor="1"', '')), twin, True, "twin")
    must_red(f"{posture} [{label}] delete has_more= and next_offset= from the root",
             root_edit(t, lambda a: re.sub(r' (has_more|next_offset)="[^"]*"', '', a)), twin, True, "twin", "self")
    must_red(f"{posture} [{label}] relocate capped= to the trailer", to_trailer(t, lambda k: k == "capped"), twin, True, "trailer", "twin")
    must_red(f"{posture} [{label}] relocate every root attribute but task= to the trailer (the pre-fix shape)",
             to_trailer(t, lambda k: k not in ("task", "changed", "from", "to")), twin, True, "trailer", "twin")
    must_red(f"{posture} [{label}] turn capped=\"1\" into capped=\"0\" on the root", root_edit(t, lambda a: a.replace(' capped="1"', ' capped="0"')), twin, True, "twin", "self")
    pad = "<!-- " + "x" * PREFIX + " -->"
    must_red(f"{posture} [{label}] push the root past the prefix", pad + t, twin, True, "prefix")
s = subject("default", False)
if s is None:
    no("(C) default: no capped, floored inline answer holds the invariant — the inline control is unproven")
else:
    must_red(f"default [{s[0]}] delete capped=\"1\" from an INLINE root", root_edit(s[1], lambda a: a.replace(' capped="1"', '')), None, False, "self")
    must_red(f"default [{s[0]}] an inline answer that grows an <about legend=> trailer", 
             re.sub(r'(</[\w.-]+>\s*)$', r'<about shown="1" legend="ref"/>\1', s[1]), None, False, "pointer", "trailer")

# ── (D) capped="1" with shown == total ──────────────────────────────────────────────────────────────────────────────
print("=== (D) capped=\"1\" never rides beside shown == total without one of its two defined readings ===")
EL = re.compile(r'<([A-Za-z_][\w.-]*)((?:\s+[\w:.-]+="[^"]*")*)\s*/?>')
seen = {"cut": 0, "floor": 0, "sigs": 0}; wrong = []
for posture, label, t, _, _ in subjects:
    for m in EL.finditer(no_comments(t)):
        a = dict(ATTR.findall(m.group(2)))
        if a.get("capped") != "1" or "shown" not in a or "total" not in a: continue
        if a["shown"] != a["total"]:                                                       seen["cut"] += 1
        elif a.get("counts_floor") == "1" or any(k.endswith("_capped") and v == "1" for k, v in a.items()): seen["floor"] += 1
        elif m.group(1) == "sigs":                                                         seen["sigs"] += 1
        else: wrong.append(f"{posture} {label} <{m.group(1)} shown={a['shown']} total={a['total']}>")
check(seen["cut"] >= 4 and not wrong, f"(D) {seen['cut']} cut elements read shown != total; {seen['floor']} are a floored total, {seen['sigs']} a byte-trimmed <sigs>; "
      f"{len(wrong)} misstate a cut ({wrong[:2]})")
D_OK  = '<x shown="40" total="40" capped="1" counts_floor="1"/>'
D_BAD = '<x shown="40" total="40" capped="1"/>'
def misstates(t):
    return [1 for m in EL.finditer(t) for a in [dict(ATTR.findall(m.group(2)))]
            if a.get("capped") == "1" and a.get("shown") == a.get("total") and a.get("counts_floor") != "1" and m.group(1) != "sigs"]
check(misstates(D_BAD) and not misstates(D_OK), "(D) control: a bare capped=\"1\" beside shown == total is caught, the floored one is not")

# ── (E) determinism ─────────────────────────────────────────────────────────────────────────────────────────────────
print("=== (E) determinism ===")
again = {name(f): cli(BIN, *f, "--legend-have=" + DV) for f in VERBS}
check(again == have, f"(E) {len(have)} handshake answers, run twice, are byte-identical")
check(session(BIN, CALLS) == mcp and all(mcp), f"(E) the {len(CALLS)}-call MCP session, run twice, is byte-identical and answered every call")

# ── (F) the non-ref postures did not move ───────────────────────────────────────────────────────────────────────────
print("=== (F) the non-ref postures did not move; a ref answer costs no byte ===")
kept = [k for k, t in have.items() if not is_ref(t)]
moved = [k for k in kept if have[k] != default[k]]
check(kept and not moved, f"(F) the {len(kept)} handshake answers the dictionary could not reduce are the default answers byte for byte ({moved})")
longer = [f"{l} {len(t.encode())}>{len(tw.encode())}" for _, l, t, tw, ref in subjects if ref and len(t.encode()) > len(tw.encode())]
check(refs and not longer, f"(F) no ref answer is longer than its inline twin, over {len(refs)} ({longer[:3]})")
if BASE:
    diffs  = [f"default {name(f)}" for f in VERBS if cli(BASE, *f) != default[name(f)]]
    diffs += [f"full {name(f)}" for f in VERBS if cli(BASE, *f, "--legend=full") != full[name(f)]]
    diffs += [f"mcp-inline #{i + 1}" for i, (a, b) in enumerate(zip(session(BASE, CALLS, server=["--mcp-legend=inline"]), mcp_in)) if a != b]
    base_ref = {name(f): cli(BASE, *f, "--legend-have=" + re.search(r'dictv=([0-9a-f]{16})', subprocess.run([BASE, "--legend-dict"], capture_output=True, text=True).stdout).group(1)) for f in VERBS}
    resized = [f"{k} {len(base_ref[k].encode())}->{len(have[k].encode())}" for k in have if is_ref(have[k]) and is_ref(base_ref[k]) and len(base_ref[k].encode()) != len(have[k].encode())]
    check(not diffs, f"(F) against {BASE}: {2 * len(VERBS)} CLI answers (default, --legend=full) and {len(CALLS)} --mcp-legend=inline answers are byte-identical ({diffs[:4]})")
    check(not resized, f"(F) against {BASE}: every handshake ref answer has the SAME byte length — the fix moves bytes, it adds none ({resized[:4]})")
else:
    print("  NOTE  (F) cross-binary byte-identity NOT RUN: set REFDISCLOSURE_BASE_BIN to a pre-change binary. Not run is not a pass.")

print(f"refdisclosurecheck: {'FAIL' if fails else 'PASS'} ({len(fails)} failing)")
sys.exit(1 if fails else 0)
PY

# ── the fixture: 64 callers of one function (the default window is 40 rows), a namesake pair, three tests, and one file
#    no grammar reads (so the graph gauges and counts_floor= fire) ──────────────────────────────────────────────────
FX="$TMP/fx"
mkdir -p "$FX/src" "$FX/tests"
{
    echo '/* helper adds one */'
    echo 'int helper(int x) { return x + 1; }'
    echo 'int external_thing(int);'
    for i in $( seq 1 64 ); do printf 'int caller_%02d(int v) { return helper(v) + external_thing(%d); }\n' "$i" "$i"; done
    echo 'int top(void) { int acc = 0;'
    for i in $( seq 1 64 ); do printf '  acc += caller_%02d(acc);\n' "$i"; done
    echo '  return acc; }'
} >"$FX/src/core.c"
printf 'int dup(int a) { return a; }\nint use_a(void) { return dup(1); }\n' >"$FX/src/a.c"
printf 'int dup(int a) { return a + 2; }\nint use_b(void) { return dup(2); }\n' >"$FX/src/b.c"
for n in one two three; do
    printf 'int top(void);\nint test_%s(void) { return top() == 4; }\n' "$n" >"$FX/tests/test_$n.c"
done
printf 'opaque\n' >"$FX/data.result"
( cd "$FX" && git init -q . && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm init ) \
    || no "could not build the git fixture"

if [ "$fail" -eq 0 ]; then
    python3 "$TMP/arms.py" "$BIN" "$FX" "$BASE_BIN" || fail=1
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "refdisclosurecheck: FAILURES ABOVE"
exit "$fail"
