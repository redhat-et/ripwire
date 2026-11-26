#!/usr/bin/env bash
# leidencheck.sh — every community answer is CONNECTED, and says so (Traag, Waltman & van Eck, Sci Rep 2019,
# "From Louvain to Leiden": Louvain's local moving can pull a bridge node out of a community and leave the rest of
# it in two pieces; their measurements found up to 16% of Louvain communities disconnected).
#
#   test/leidencheck.sh [BIN]
#
# The corpus is test/leidenfix/graph.c: fifteen functions whose undirected call graph is a 15-node, 23-edge graph
# that a randomized search of ripwire's own local-moving rule found and then minimized. On it, plain local moving
# ends with the community {lf00, lf01, lf04, lf05}, whose pieces lf00-lf01 and lf04-lf05 shared no edge.
#
# Arms:
#   (a) --communities, --zoom and --pack-task --partition each carry disconnected= on their root;
#   (b) each says disconnected="0";
#   (c) INDEPENDENT of the attribute: this script recomputes, from the fixture's own call lists, the connectivity of
#       every module --communities prints and of every module at EVERY level --zoom prints, and fails on any
#       module whose members are not one connected piece (the attribute could be wrong; the members cannot lie);
#   (d) lf00/lf01 and lf04/lf05 are no longer one module (the split actually happened, not just a relabelled 0);
#   (e) every answer is byte-identical across two runs, and well-formed XML.
# On a binary with no connectivity step, (a) fails on all three verbs, and with only the disclosure, (b) reads
# disconnected="1" on --communities and (c)/(d) name the split module.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/leidenfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "leidencheck: python3 unavailable — skipping"; exit 0; }

fail=0
run_twice()
{
    local name="$1"; shift
    "$BIN" "$FIX" "$@" --no-cache >"$TMP/$name.a" 2>"$TMP/$name.err"
    "$BIN" "$FIX" "$@" --no-cache >"$TMP/$name.b" 2>/dev/null
    if [ ! -s "$TMP/$name.a" ]; then
        echo "  FAIL  (e) $name printed nothing: $( head -c 300 "$TMP/$name.err" )"; fail=1
    elif diff -q "$TMP/$name.a" "$TMP/$name.b" >/dev/null; then
        echo "  PASS  (e) $name is byte-identical across two runs"
    else
        echo "  FAIL  (e) $name differs between two runs"; fail=1
    fi
}

run_twice communities --communities
run_twice zoom --zoom=4 --zoom-levels=0
run_twice partition --pack-task="lf00 lf04 lf08 lf12" --partition=2

python3 - "$FIX/graph.c" "$TMP" <<'PY' || fail=1
import re
import sys
import xml.etree.ElementTree as ET

src_path, tmp = sys.argv[1:]
src = open(src_path, encoding="utf-8").read()

# the fixture's undirected call graph, read from its own bodies (a definition is "void lfNN( void )\n{")
adj = {}
for m in re.finditer(r"void (lf\d\d)\( void \)\n\{\n(.*?)\}\n", src, re.S):
    caller = m.group(1)
    adj.setdefault(caller, set())
    for callee in re.findall(r"(lf\d\d)\(\);", m.group(2)):
        adj[caller].add(callee)
        adj.setdefault(callee, set()).add(caller)
if len(adj) != 15:
    sys.exit(f"  FAIL  fixture parse: expected 15 functions, read {len(adj)}")

def connected(members):
    members = set(members)
    start = next(iter(members))
    seen, stack = {start}, [start]
    while stack:
        u = stack.pop()
        for v in adj[u] & members:
            if v not in seen:
                seen.add(v)
                stack.append(v)
    return seen == members

bad = 0
def check(cond, msg):
    global bad
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    if not cond:
        bad = 1

roots = {}
for name, tag in (("communities", "communities"), ("zoom", "zoom"), ("partition", "ctx-partitions")):
    try:
        root = ET.parse(f"{tmp}/{name}.a").getroot()
    except ET.ParseError as e:
        check(False, f"(e) {name} is well-formed XML ({e})")
        continue
    check(root.tag == tag, f"(e) {name} root is <{tag}>")
    roots[name] = root
    value = root.get("disconnected")
    check(value is not None, f"(a) {name} root carries disconnected=")
    check(value == "0", f"(b) {name} root says disconnected=\"0\" (got {value!r})")

# (c)/(d) --communities: every listed module of 2+ symbols, members read from the rows (each is <= 5, so whole)
if "communities" in roots:
    modules = []
    for c in roots["communities"].iter("community"):
        names = [m.get("n") for m in c.iter("member")]
        check(c.get("capped") == "0", f"(c) communities module id={c.get('id')} lists every member")
        modules.append(names)
    for names in modules:
        check(connected(names), f"(c) communities module {sorted(names)} is connected in the fixture's call graph")
    joined = [names for names in modules if {"lf00", "lf04"} <= set(names) or {"lf01", "lf05"} <= set(names)]
    check(not joined, "(d) communities: lf00/lf01 and lf04/lf05 are no longer one module")
    listed = sorted(n for names in modules for n in names)
    check(listed == sorted(adj), f"(c) communities: the modules cover all 15 functions ({len(listed)} listed)")

# (c) --zoom: every module at every level; a level-0 module lists its members, a higher one is the union below it
if "zoom" in roots:
    def members_of(mod):
        names = [m.get("n") for m in mod.findall("member")]
        for child in mod.findall("module"):
            names += members_of(child)
        return names
    count = 0
    for mod in roots["zoom"].iter("module"):
        if mod.get("children") is not None:
            check(False, f"(c) zoom module level={mod.get('level')} id={mod.get('id')} is printed whole (zoom-levels=0)")
            continue
        if mod.get("level") == "0":
            check(mod.get("capped") == "0", f"(c) zoom level-0 module id={mod.get('id')} lists every member")
        names = members_of(mod)
        count += 1
        check(connected(names), f"(c) zoom level={mod.get('level')} module {sorted(names)} is connected")
    check(count > 0, f"(c) zoom printed {count} module(s) to check")

sys.exit(bad)
PY

if [ "$fail" -ne 0 ]; then
    echo "leidencheck: FAIL"
    exit 1
fi
echo "leidencheck: PASS"
