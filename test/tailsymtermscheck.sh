#!/usr/bin/env bash
# tailsymtermscheck.sh — TAIL-SYM-TERMS (depth lab G2, reports/depth-gc-lab-1114.md): a --for code tail row that prints sym= ADDS,
# in its own tsym= after sym=, up to kTailSymTermNames (2) more of its file's symbols whose names share a task word.
#
# WHY. The tail names a file's top three symbols by lens rank. When the symbol the question wants shares the task's words only
# through a stem (`restoration` / `restorer`), the lens never scores it, so the tail listed its file and stayed silent about it.
# The lab's G1 (re-pick the three names by task words) lost 12 credited lens names on 217 cells; G2 (append, never displace)
# lost none, so only the append ships. RIPWIRE_NO_TAIL_SYM_TERMS=1 is the pre-card tail (the ablation arm below).
#
# Fixture: 60 strong widget/frobnicate files (they take the head and most of the tail), plus zz_store.py, a weak file whose three
# lens-scored symbols (doc-comment hits) carry no task word in their names, and four unscored symbols that do, by the lab stem
# only (restorer_scheduling: 2 words; config_restorer, queue_scheduling, restorer_cache: 1 each). docs/restoration.md is a doc row.
# c000.py (a head file) also defines probe_schedulers, a <syms> by=name pick; zz_probe.py, another weak file, defines a namesake.
#
# Arms (each counts its premise and FAILS on 0; an empty or crashed answer fails every arm):
#   a  named:        on the ablated tail restorer_scheduling is absent from the whole answer and zz_store.py's row is listed; on the
#                    default tail that row carries tsym="restorer_scheduling,restorer_cache": score 2 first, then the graph's PageRank
#                    (c050..c059 call restorer_cache; by index or by lens config_restorer, defined first, would take the slot)
#   b  no-displace:  every default tail row is its ablated twin's tag byte for byte, or that tag with one tsym= added before "/>"
#                    (same rows, same order, sym= untouched); counts the rows compared and the rows that gained tsym= (both > 0)
#   c  negative:     a task whose words no unprinted symbol of a tail file carries ("widget frobnicate helper") is byte-identical
#                    (stdout + stderr + rc) to the ablation; premise: zz_store.py is listed and holds an unprinted symbol
#   d  cap:          no tsym= holds more than 2 names; premise: zz_store.py has 4 candidates and its tsym= holds 2
#   e  doc row:      the docs/restoration.md row (its title holds a comma and task words) is unchanged
#   f  legend:       the clause rides the full and the compact dialect exactly when a row gained a name, never on the ablation or
#                    the negative task
#   g  JSON + MCP:   the JSON "tsym" of zz_store.py (with "tsym_why") and the MCP `for` twin's tail row carry the same two names
#   h  warm==cold:   a cached rerun is byte-identical to the cold run (the names read the index only, never the cache state)
#   i  syms first:   <syms> keeps its priority: the default answer's <syms> block equals the ablated one, and a name it prints
#                    (probe_schedulers) is cut from every tsym= (the lane's first fire: names in the tail hid 21 of 206 answers'
#                    picks); premise: the ablated <syms> names probe_schedulers, and with no <syms> (RIPWIRE_NO_FILE_SYMS=1) zz_probe.py's
#                    row carries tsym="probe_schedulers", so the cut has a name to cut
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
        printf 'from zz_store import restorer_cache\n\n\ndef widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    return restorer_cache()\n' "$n" > "$F/c$n.py"
    else
        printf 'def widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    return 1\n' "$n" > "$F/c$n.py"
    fi
    i=$(( i + 1 ))
done
cat > "$F/zz_store.py" <<'EOF'
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


def queue_scheduling():
    return 0


def restorer_cache():
    return 0


def restorer_scheduling():
    return 0
EOF
printf 'def probe_schedulers():\n    return 0\n' >> "$F/c000.py"
printf 'def alpha_probe():\n    """widget"""\n    return 1\n\n\ndef probe_schedulers():\n    return 0\n' > "$F/zz_probe.py"
printf '# Restorer scheduling, widget frobnicate notes\n\nThe widget restoration scheduler notes.\n' > "$F/docs/restoration.md"
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
RIPWIRE_NO_FILE_SYMS=1 run "$TMP/ns.xml" --no-cache "--for=$Q"   # arm i's premise: with no <syms> block, nothing is cut from tsym=
export RIPWIRE_NO_TAIL_SYM_TERMS=1
run "$TMP/a.xml"   --no-cache "--for=$Q"
run "$TMP/a.full"  --no-cache "--for=$Q" --legend=full
run "$TMP/a.json"  --no-cache "--for=$Q" --json
run "$TMP/an.xml"  --no-cache "--for=$QN"
unset RIPWIRE_NO_TAIL_SYM_TERMS

python3 - "$TMP" <<'PY'
import html, json, re, sys
T = sys.argv[1]
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
for n in ("ns.xml", "d.xml", "d.full", "d.cmp", "d.json", "n.xml", "w1.xml", "w2.xml", "a.xml", "a.full", "a.json", "an.xml"):
    if not ok(n):
        arm("run " + n, False, "rc=" + rd(n + ".rc").strip() + " bytes=" + str(len(rd(n))))
D, A = tail_rows(rd("d.xml")), tail_rows(rd("a.xml"))
dz = [(s, ts) for p, s, ts in D if p.endswith("zz_store.py")]
az = [(s, ts) for p, s, ts in A if p.endswith("zz_store.py")]
# a — named
arm("a premise", len(az) == 1 and "restorer_scheduling" not in rd("a.xml"),
    f"ablated: zz_store.py rows={len(az)}, restorer_scheduling in answer={'restorer_scheduling' in rd('a.xml')}")
arm("a named", len(dz) == 1 and len(az) == 1 and dz[0] == (az[0][0], ["restorer_scheduling", "restorer_cache"]) and az[0][1] == [],
    f"default zz_store.py (sym, tsym)={dz} ablated={az}")
# b — no displacement: each default tag is the ablated tag, or it with one tsym= inserted before "/>"
DT, AT = tail_tags(rd("d.xml")), tail_tags(rd("a.xml"))
kept = sum(1 for dt, at in zip(DT, AT) if re.sub(r' tsym="[^"]*"(?=/>$)', "", dt) == at)
gained = sum(1 for dt in DT if ' tsym="' in dt)
arm("b no-displace", len(DT) == len(AT) and len(DT) > 0 and kept == len(DT) and gained > 0,
    f"rows default={len(DT)} ablated={len(AT)} same-but-tsym={kept} gained={gained}")
# c — negative
n_rows = [s for p, s, _ in tail_rows(rd("an.xml")) if p.endswith("zz_store.py")]
arm("c premise", len(n_rows) == 1 and "config_restorer" not in rd("an.xml"), f"zz_store.py rows={len(n_rows)} unprinted symbol listed nowhere")
arm("c negative", rd("n.xml") == rd("an.xml") and rd("n.xml.err") == rd("an.xml.err") and rd("n.xml.rc") == rd("an.xml.rc"),
    "a task no unprinted name matches: stdout, stderr and rc equal the ablation")
# d — cap
over = [(p, len(ts)) for p, s, ts in D if len(ts) > 2]
arm("d cap", len(dz) == 1 and len(dz[0][1]) == 2 and not over, f"zz_store.py tsym={dz[0][1] if dz else None} (4 candidates); rows over 2: {over}")
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
    js = [s for f, s in zip(j["files"], j["tsym"]) if f.endswith("zz_store.py")] + (["why"] if j.get("tsym_why") else [])
except Exception as e:
    js = [f"parse error {e}"]
mcp = rd("d.mcp")
mrow = re.search(r'<t p=\\"[^"\\]*zz_store\.py\\" sym=\\"[^"\\]*\\" tsym=\\"([^"\\]*)\\"', mcp)
want = ",".join(dz[0][1]) if dz else None
arm("g JSON", js == [want, "why"], f"JSON tsym={js} want {want} + tsym_why")
arm("g MCP", mrow is not None and mrow.group(1) == want and FULL in mcp, f"MCP row sym={mrow.group(1) if mrow else None}")
# h — warm == cold
arm("h warm==cold", rd("w1.xml") == rd("w2.xml") and rd("w1.xml") == rd("d.xml"), "cached rerun equals the cold run")
# i — <syms> priority
def syms(t):
    m = re.search(r"<syms[ >].*?</syms>", t)
    return m.group(0) if m else ""
pz = [ts for p, s, ts in D if p.endswith("zz_probe.py")]
pn = [ts for p, s, ts in tail_rows(rd("ns.xml")) if p.endswith("zz_probe.py")]
arm("i premise", 'n="probe_schedulers"' in syms(rd("a.xml")) and len(pz) == 1 and pn == [["probe_schedulers"]],
    f"ablated <syms> names probe_schedulers={'n=\"probe_schedulers\"' in syms(rd('a.xml'))}; zz_probe.py tsym with no <syms>={pn}")
arm("i syms first", syms(rd("d.xml")) == syms(rd("a.xml")) and not any("probe_schedulers" in ts for p, s, ts in D),
    "default <syms> equals the ablated block; no tsym= repeats a name it prints")
print("tailsymtermscheck: " + ("FAIL " + ",".join(fails) if fails else "PASS"))
sys.exit(1 if fails else 0)
PY
