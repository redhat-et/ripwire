#!/usr/bin/env bash
# tailsymtermscheck.sh — TAIL-SYM-TERMS (depth lab G2, reports/depth-gc-lab-1114.md): a --for code tail row that prints sym= ADDS,
# in its own tsym= after sym=, up to kTailSymTermNames (2) more of its file's symbols whose names share a task word.
#
# WHY. The tail names a file's top three symbols by lens rank. When the symbol the question wants shares the task's words only
# through a stem (`restoration` / `restorer`), the lens never scores it, so the tail listed its file and stayed silent about it.
# The lab's G1 (re-pick the three names by task words) lost 12 credited lens names on 217 cells; G2 (append, never displace)
# lost none, so only the append ships. RIPWIRE_NO_TAIL_SYM_TERMS=1 is the pre-card tail (the ablation arm below).
#
# DISTINCTIVE EVIDENCE ONLY (TSYM-WRONG-DECOYS, 2026-11-16): a row adds names only when at most 3 of its file's symbols share a
# task word, and each name plus the file's path carries 2+ distinct task words (fortailterms.h kTailSymTermFileMatches/Evidence).
#
# Fixture: 60 strong widget/frobnicate files (they take the head and most of the tail), plus zz_scheduler_store.py, a weak file
# whose three lens-scored symbols (doc-comment hits) carry no task word in their names, and three unscored symbols that do, by the
# lab stem only (restorer_scheduling: 2 words; config_restorer, restorer_cache: 1 each, plus "scheduler" from the path).
# docs/restoration.md is a doc row. c000.py (a head file) also defines probe_schedulers, a <syms> by=name pick; zz_restorer_probe.py,
# another weak file, defines a namesake. zz_queue.py and zz_scheduler_pool.py are arm j's weak-evidence files.
#
# Arms (each counts its premise and FAILS on 0; an empty or crashed answer fails every arm):
#   a  named:        on the ablated tail restorer_scheduling is absent from the whole answer and zz_store.py's row is listed; on the
#                    default tail that row carries tsym="restorer_scheduling,restorer_cache": score 2 first, then the graph's PageRank
#                    (c050..c059 call restorer_cache; by index or by lens config_restorer, defined first, would take the slot)
#   b  no-displace:  every default tail row is its ablated twin's tag byte for byte, or that tag with one tsym= added before "/>"
#                    (same rows, same order, sym= untouched); counts the rows compared and the rows that gained tsym= (both > 0)
#   c  negative:     a task whose words no unprinted symbol of a tail file carries ("widget frobnicate helper") is byte-identical
#                    (stdout + stderr + rc) to the ablation; premise: zz_store.py is listed and holds an unprinted symbol
#   d  cap:          no tsym= holds more than 2 names; premise: zz_scheduler_store.py has 3 candidates and its tsym= holds 2
#   e  doc row:      the docs/restoration.md row (its title holds a comma and task words) is unchanged
#   f  legend:       the clause rides the full and the compact dialect exactly when a row gained a name, never on the ablation or
#                    the negative task
#   g  JSON + MCP:   the JSON "tsym" of zz_store.py (with "tsym_why") and the MCP `for` twin's tail row carry the same two names
#   h  warm==cold:   a cached rerun is byte-identical to the cold run (the names read the index only, never the cache state)
#   i  syms first:   <syms> keeps its priority: the default answer's <syms> block equals the ablated one, and a name it prints
#                    (probe_schedulers) is cut from every tsym= (the lane's first fire: names in the tail hid 21 of 206 answers'
#                    picks); premise: the ablated <syms> names probe_schedulers, and with no <syms> (RIPWIRE_NO_FILE_SYMS=1) zz_probe.py's
#                    row carries tsym="probe_schedulers", so the cut has a name to cut
#   j  decoy class:  (TSYM-WRONG-DECOYS: the lane's first cut printed 3 gold-WRONG names on fire321) zz_queue.py's restorer_queue
#                    holds one task word and its path none: no tsym=; zz_scheduler_pool.py's four restorer_* names each hold two
#                    words with the path, but four symbols of the file match (> 3): no tsym=; premise: both rows listed, the names
#                    unprinted on the ablation. Red on the pre-fix lane (8eda7e7bf: tsym="restorer_queue", "restorer_a,restorer_b").
#   k  path-only:    (CodeRabbit #678) a second fixture, fx2: head file c000.py's tail row has no sym= (the head shows its one scored
#                    name), and its unscored restorer_scheduling_plan carries two task words; the row stays `<t p="c000.py"/>`, the
#                    name nowhere in the answer; premise: the ablated row is path-only. Red on 546cc81f9 (tsym="restorer_scheduling_plan").
#   l  tie order:    (CodeRabbit #678: no float-equality tie) fx2's zz_scheduler_plan.py defines restorer_zeta before restorer_alpha,
#                    equal score and equal PageRank (neither called): tsym= keeps definition-line order, "restorer_zeta,restorer_alpha";
#                    and tailTermCands' comparator in src/forpage.h tests PageRank by strict > only (red on 546cc81f9: `a.pr != b.pr`).
#
# Usage: test/tailsymtermscheck.sh [BIN]   (default build/ripwire; RIPWIRE_BIN also honoured)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "tailsymtermscheck: BIN=$BIN"

F="$TMP/fx"; mkdir -p "$F/docs" "$TMP/home"
i=0
while [ $i -lt 60 ]; do
    n=$( printf '%03d' $i )
    if [ $i -ge 50 ]; then   # arm a's tie-break: ten callers lift restorer_cache's PageRank over the other one-word names
        printf 'from zz_scheduler_store import restorer_cache\n\n\ndef widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    return restorer_cache()\n' "$n" > "$F/c$n.py"
    else
        printf 'def widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    return 1\n' "$n" > "$F/c$n.py"
    fi
    i=$(( i + 1 ))
done
cat > "$F/zz_scheduler_store.py" <<'EOF'
def alpha_one():
    """widget"""
    return 1


def alpha_two():
    """widget"""
    return 2


def alpha_three():
    """widget"""
    return 3


def config_restorer():
    return 0


def restorer_cache():
    return 0


def restorer_scheduling():
    return 0
EOF
printf 'def probe_schedulers():\n    return 0\n' >> "$F/c000.py"
printf 'def alpha_probe():\n    """widget"""\n    return 1\n\n\ndef probe_schedulers():\n    return 0\n' > "$F/zz_restorer_probe.py"
# arm j (TSYM-WRONG-DECOYS): two more weak files whose names share a task word only WEAKLY. zz_queue.py: restorer_queue holds one
# task word and the path none (one generic word, no co-evidence). zz_scheduler_pool.py: four names each hold "restorer" and the path
# "scheduler" (two words each), but four of the file's symbols match (the word is the file's topic, so a pick is a guess).
printf 'def alpha_queue():\n    """widget"""\n    return 1\n\n\ndef restorer_queue():\n    return 0\n' > "$F/zz_queue.py"
printf 'def alpha_pool():\n    """widget"""\n    return 1\n' > "$F/zz_scheduler_pool.py"
for w in a b c d; do printf '\n\ndef restorer_%s():\n    return 0\n' "$w" >> "$F/zz_scheduler_pool.py"; done
printf '# Restorer scheduling, widget frobnicate notes\n\nThe widget restoration scheduler notes.\n' > "$F/docs/restoration.md"
# fx2 (arms k, l): 60 strong files, head file c000.py with one unscored two-word name, and a weak file with two tied names
F2="$TMP/fx2"; mkdir -p "$F2"
i=0
while [ $i -lt 60 ]; do
    n=$( printf '%03d' $i )
    printf 'def widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    return 1\n' "$n" > "$F2/c$n.py"
    i=$(( i + 1 ))
done
printf '\n\ndef restorer_scheduling_plan():\n    return 0\n' >> "$F2/c000.py"
printf 'def alpha_plan():\n    """widget"""\n    return 1\n\n\ndef restorer_zeta():\n    return 0\n\n\ndef restorer_alpha():\n    return 0\n' > "$F2/zz_scheduler_plan.py"
Q="widget frobnicate restoration scheduler"
QN="widget frobnicate helper"

run() {   # run OUTFILE ARGS... -> rc file beside the output; HOME/TMPDIR private, cwd = the fixture
    local o="$1"; shift
    ( cd "$F" || exit 9; HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" "$F" "$@" ) > "$o" 2> "$o.err"   # status: recorded on the next line
    echo $? > "$o.rc"                                                                              # and read by ok() (a non-0 run fails)
}
run "$TMP/d.xml"   --no-cache "--for=$Q"
run "$TMP/d.full"  --no-cache "--for=$Q" --legend=full
run "$TMP/d.cmp"   --no-cache "--for=$Q" --legend=compact
run "$TMP/d.json"  --no-cache "--for=$Q" --json
run "$TMP/n.xml"   --no-cache "--for=$QN"
run "$TMP/w1.xml"  "--for=$Q"
run "$TMP/w2.xml"  "--for=$Q"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"for\",\"arguments\":{\"task\":\"$Q\"}}}" > "$TMP/mcp.in"
( cd "$F" || exit 9; HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" "$F" --mcp --no-cache < "$TMP/mcp.in" ) > "$TMP/d.mcp" 2> "$TMP/d.mcp.err"   # status: the server's rc is not the verdict; arm (g MCP) reads the tools/call reply
( cd "$F2" || exit 9; HOME="$TMP/home" TMPDIR="$TMP/" "$BIN" "$F2" --no-cache "--for=$Q" ) > "$TMP/k.xml" 2> "$TMP/k.xml.err"; echo $? > "$TMP/k.xml.rc"
( cd "$F2" || exit 9; HOME="$TMP/home" TMPDIR="$TMP/" RIPWIRE_NO_TAIL_SYM_TERMS=1 "$BIN" "$F2" --no-cache "--for=$Q" ) > "$TMP/ka.xml" 2> "$TMP/ka.xml.err"; echo $? > "$TMP/ka.xml.rc"
RIPWIRE_NO_FILE_SYMS=1 run "$TMP/ns.xml" --no-cache "--for=$Q"   # arm i's premise: with no <syms> block, nothing is cut from tsym=
export RIPWIRE_NO_TAIL_SYM_TERMS=1
run "$TMP/a.xml"   --no-cache "--for=$Q"
run "$TMP/a.full"  --no-cache "--for=$Q" --legend=full
run "$TMP/a.json"  --no-cache "--for=$Q" --json
run "$TMP/an.xml"  --no-cache "--for=$QN"
unset RIPWIRE_NO_TAIL_SYM_TERMS

python3 - "$TMP" "$ROOT" <<'PY'
import html, json, re, sys
T, ROOT = sys.argv[1], sys.argv[2]
fails = []
def rd(n):
    return open(f"{T}/{n}", encoding="utf8", errors="replace").read()
def ok(n):
    return rd(n + ".rc").strip() == "0" and len(rd(n)) > 0
def arm(name, cond, why):
    print(("PASS " if cond else "FAIL ") + name + ": " + why)
    if not cond:
        fails.append(name)
def tail_tags(t):
    i, j = t.find("<tail"), t.find("</tail>")
    return re.findall(r'<t [^>]*/>', t[i:j]) if i >= 0 else []
def attr(tag, a):
    m = re.search(r' ' + a + r'="([^"]*)"', tag)
    return [x for x in html.unescape(m.group(1)).split(",") if x] if m else []
def tail_rows(t):   # (path, sym names, tsym names)
    return [(html.unescape(re.search(r' p="([^"]*)"', g).group(1)), attr(g, "sym"), attr(g, "tsym")) for g in tail_tags(t)]
for n in ("k.xml", "ka.xml", "ns.xml", "d.xml", "d.full", "d.cmp", "d.json", "n.xml", "w1.xml", "w2.xml", "a.xml", "a.full", "a.json", "an.xml"):
    if not ok(n):
        arm("run " + n, False, "rc=" + rd(n + ".rc").strip() + " bytes=" + str(len(rd(n))))
D, A = tail_rows(rd("d.xml")), tail_rows(rd("a.xml"))
dz = [(s, ts) for p, s, ts in D if p.endswith("zz_scheduler_store.py")]
az = [(s, ts) for p, s, ts in A if p.endswith("zz_scheduler_store.py")]
# a — named
arm("a premise", len(az) == 1 and "restorer_scheduling" not in rd("a.xml"),
    f"ablated: zz_scheduler_store.py rows={len(az)}, restorer_scheduling in answer={'restorer_scheduling' in rd('a.xml')}")
arm("a named", len(dz) == 1 and len(az) == 1 and dz[0] == (az[0][0], ["restorer_scheduling", "restorer_cache"]) and az[0][1] == [],
    f"default zz_scheduler_store.py (sym, tsym)={dz} ablated={az}")
# b — no displacement: each default tag is the ablated tag, or it with one tsym= inserted before "/>"
DT, AT = tail_tags(rd("d.xml")), tail_tags(rd("a.xml"))
kept = sum(1 for dt, at in zip(DT, AT) if re.sub(r' tsym="[^"]*"(?=/>$)', "", dt) == at)
gained = sum(1 for dt in DT if ' tsym="' in dt)
arm("b no-displace", len(DT) == len(AT) and len(DT) > 0 and kept == len(DT) and gained > 0,
    f"rows default={len(DT)} ablated={len(AT)} same-but-tsym={kept} gained={gained}")
# c — negative
n_rows = [s for p, s, _ in tail_rows(rd("an.xml")) if p.endswith("zz_scheduler_store.py")]
arm("c premise", len(n_rows) == 1 and "config_restorer" not in rd("an.xml"), f"zz_scheduler_store.py rows={len(n_rows)} unprinted symbol listed nowhere")
arm("c negative", rd("n.xml") == rd("an.xml") and rd("n.xml.err") == rd("an.xml.err") and rd("n.xml.rc") == rd("an.xml.rc"),
    "a task no unprinted name matches: stdout, stderr and rc equal the ablation")
# d — cap
over = [(p, len(ts)) for p, s, ts in D if len(ts) > 2]
arm("d cap", len(dz) == 1 and len(dz[0][1]) == 2 and not over, f"zz_scheduler_store.py tsym={dz[0][1] if dz else None} (3 candidates); rows over 2: {over}")
# e — doc row
dd = [(s, ts) for p, s, ts in D if p.endswith("restoration.md")]
ad = [(s, ts) for p, s, ts in A if p.endswith("restoration.md")]
arm("e doc row", len(dd) == 1 and dd == ad, f"docs/restoration.md default={dd} ablated={ad}")
# f — legend
FULL = "; tail tsym= up to 2 more of that file"
CMP = "; t tsym= up to 2 more file symbols"
arm("f legend", FULL in rd("d.full") and CMP in rd("d.cmp") and FULL not in rd("a.full") and FULL not in rd("n.xml") and CMP not in rd("n.xml"),
    "clause in default full/compact, absent on ablation and the negative task")
# g — JSON + MCP
try:
    j = json.loads(rd("d.json"))["tail"]
    js = [s for f, s in zip(j["files"], j["tsym"]) if f.endswith("zz_scheduler_store.py")] + (["why"] if j.get("tsym_why") else [])
except Exception as e:
    js = [f"parse error {e}"]
mcp = rd("d.mcp")
mrow = re.search(r'<t p=\\"[^"\\]*zz_scheduler_store\.py\\" sym=\\"[^"\\]*\\" tsym=\\"([^"\\]*)\\"', mcp)
want = ",".join(dz[0][1]) if dz else None
arm("g JSON", js == [want, "why"], f"JSON tsym={js} want {want} + tsym_why")
arm("g MCP", mrow is not None and mrow.group(1) == want and FULL in mcp, f"MCP row sym={mrow.group(1) if mrow else None}")
# h — warm == cold
arm("h warm==cold", rd("w1.xml") == rd("w2.xml") and rd("w1.xml") == rd("d.xml"), "cached rerun equals the cold run")
# i — <syms> priority
def syms(t):
    m = re.search(r"<syms[ >].*?</syms>", t)
    return m.group(0) if m else ""
pz = [ts for p, s, ts in D if p.endswith("zz_restorer_probe.py")]
pn = [ts for p, s, ts in tail_rows(rd("ns.xml")) if p.endswith("zz_restorer_probe.py")]
probe_picked = 'n="probe_schedulers"' in syms(rd("a.xml"))   # computed before the f-string: no backslash in its expression (Python < 3.12)
arm("i premise", probe_picked and len(pz) == 1 and pn == [["probe_schedulers"]],
    f"ablated <syms> names probe_schedulers={probe_picked}; zz_restorer_probe.py tsym with no <syms>={pn}")
arm("i syms first", syms(rd("d.xml")) == syms(rd("a.xml")) and not any("probe_schedulers" in ts for p, s, ts in D),
    "default <syms> equals the ablated block; no tsym= repeats a name it prints")
# j — decoy class (TSYM-WRONG-DECOYS): no name on one generic word, none from a file whose topic the word is
jq = [(s, ts) for p, s, ts in D if p.endswith("zz_queue.py")]
jp = [(s, ts) for p, s, ts in D if p.endswith("zz_scheduler_pool.py")]
arm("j premise", len(jq) == 1 and len(jp) == 1 and "restorer_queue" not in rd("a.xml") and "restorer_a" not in rd("a.xml"),
    f"zz_queue.py rows={len(jq)} zz_scheduler_pool.py rows={len(jp)}; their matching names unprinted on the ablation")
arm("j one word", len(jq) == 1 and jq[0][1] == [], f"zz_queue.py tsym={jq[0][1] if jq else None} (restorer_queue: one task word, path none)")
arm("j file topic", len(jp) == 1 and jp[0][1] == [], f"zz_scheduler_pool.py tsym={jp[0][1] if jp else None} (4 matching symbols > 3)")
# k — a row with no sym= stays path-only
K, KA = tail_tags(rd("k.xml")), tail_tags(rd("ka.xml"))
kc = [g for g in K if ' p="c000.py"' in g]
kac = [g for g in KA if ' p="c000.py"' in g]
arm("k premise", kac == ['<t p="c000.py"/>'] and "restorer_scheduling_plan" not in rd("ka.xml"),
    f"fx2 ablated c000.py row={kac}; restorer_scheduling_plan unprinted={'restorer_scheduling_plan' not in rd('ka.xml')}")
arm("k path-only", kc == ['<t p="c000.py"/>'] and "restorer_scheduling_plan" not in rd("k.xml"), f"fx2 default c000.py row={kc}")
# l — an exact PageRank tie breaks on the definition line, and the comparator never tests PageRank for equality
lp = [attr(g, "tsym") for g in K if ' p="zz_scheduler_plan.py"' in g]
arm("l tie order", lp == [["restorer_zeta", "restorer_alpha"]], f"fx2 zz_scheduler_plan.py tsym={lp} (want definition-line order)")
src = open(ROOT + "/src/forpage.h", encoding="utf8").read()
cmp_at = src.find("inline TailTermCands tailTermCands(")
cmp_src = src[cmp_at:src.find("\n}\n", cmp_at)] if cmp_at >= 0 else ""
arm("l no float ==", bool(cmp_src) and "a.pr > b.pr || b.pr > a.pr" in cmp_src and not re.search(r"\bpr\s*[!=]=", cmp_src),
    f"tailTermCands found={bool(cmp_src)}; PageRank compared by strict > only")
print("tailsymtermscheck: " + ("FAIL " + ",".join(fails) if fails else "PASS"))
sys.exit(1 if fails else 0)
PY
