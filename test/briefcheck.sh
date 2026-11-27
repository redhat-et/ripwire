#!/usr/bin/env bash
# test/briefcheck.sh — the `--brief="TASK"` subagent brief (lane BRIEF-VERB): budget per size class, quoted-never-guessed
# build commands, (skip) dirs, the drop order, determinism, refusals, and the MCP `brief` twin.
#
# WHY. --brief is pasted into a fresh subagent's prompt, so every byte is paid once per lane and a wrong line is acted on.
# The two promises a reader cannot check by eye are the ones gated here: the page stays under its size class's cap
# (3.5 / 5 / 7 KB by indexed files < 1K / < 10K / more; --brief-bytes overrides, 512..8192), and a build/test command is
# QUOTED from a file that exists (a manifest or a doc's fenced block), never guessed: a tree with neither says `none found`.
#
# ARMS (each counts what it saw and FAILs on zero)
#   (P)  premise: six fixtures built (four small, one medium, one large), each answering with a <brief> root.
#   (B)  budget: bytes= equals the page's byte length, budget= is the class cap, bytes <= budget; size_class matches the
#        fixture's file count; --brief-bytes=2048 holds a large page to 2048.
#   (M)  manifests: every build line names an existing file (path: or path:line); the no-manifest, no-docs fixture answers
#        `<build>none found` with build_source="none", and NO command head (make cmake npm pytest go cargo tox) appears in
#        its <build> — the negative arm.
#   (S)  skip: vendored and generated dirs are marked (skip) in the layout, ordinary code dirs are not.
#   (O)  drop order: under --brief-bytes=512 dropped= is a prefix of conventions,attrs,layout_depth,ranked,entry,edges,where_else,qs in
#        that order, the act and build sections are still there, and over="1" is set exactly when the fixed sections
#        alone outgrow the budget.
#   (D)  determinism: two runs are byte-identical; every page is well-formed XML (xmllint when present, else python).
#   (R)  refusals: --brief with --for, --brief-bytes without --brief, --brief-bytes=100 each exit non-zero with no brief;
#        an unwritable TMPDIR (no buffer for the --for page) exits non-zero with stdout EMPTY, no leaked --for page.
#   (C)  MCP: tools/list advertises `brief`; a call answers a <brief> root; bytes=100 is refused.
#   (G)  schema="ripwire.brief/v1" and a legend naming every attribute the page carries; --legend=full differs only in it.
#   (L)  the shared --brief= row: beside --plan-lanes, --brief=FILE is still the lane file (a lane plan with one lane per
#        line, no <brief> root); the subagent brief takes --brief= only without --plan-lanes.
#   (X)  round-2 detectors, one synthetic fixture each (autoconf-only C, a Go module, a Cargo workspace): the project's own
#        program leads the entries (named by AC_INIT, go.mod or the origin remote) ahead of a tool main, a bigger cmd and a
#        build script; the leading main names its delegate files, the most-called first; configure.ac without Makefile.am quotes `./configure &&
#        make` and the template makefile's targets; <r>registration: lists a registry dir, a metadata file and a build
#        config near the act; where-else lists the dir-named _test sibling, the testdata corpus and a task-word test file.
#   (A)  the exemplar anchor: "like the squash stage" resolved to ONE unit is disclosed as <like t=>FILE</like>, leads the edges
#        (its imports line first) and its dir's test mirror leads where-else; "like frob" with two definitions is disclosed as
#        ambiguous="2" with both candidates and changes none of the 6 other sections against the task without the phrase; a task
#        with no like-phrase draws no <like>.
#   (H)  BRIEF-COCHANGE, one synthetic git fixture with dated history: twenty-two sibling functions under src/functions/, each added in
#        a commit with the catalog (named nothing like a registry), a numbered test corpus, the docs page, the changelog and the unit's CMakeLists; a hot
#        file in many unrelated commits; a sweeping commit (a formatter pass over 60 files). <r>registration: leads with the
#        catalog, where-else lists the corpus dir, the docs page and the changelog, <build> names the unit's CMakeLists with
#        the line that lists the exemplar, history="1"; the hot file and the sweep-only file are absent. The same tree cut to
#        one commit (a shallow clone's shape) answers history="0" with no history slot; RIPWIRE_BRIEF_COCHANGE=0 and
#        RIPWIRE_BRIEF_UNITBUILD=0 each remove exactly their half.
#   (R)  BRIEF-R3: a "like X: path" task takes that path as the exemplar; <ranked> holds only indexed files no other slot names;
#        RIPWIRE_BRIEF_RANKED=0 removes it.
#   (Q)  BRIEF-R2, synthetic fixtures: a TS package whose pipe is re-exported through a barrel (pipes/index.ts) and the
#        package index.ts — both named in <entry> as `surface:`; a Python package whose __init__.py imports the unit; a Go module
#        whose root file imports the unit's package (named), while a root file that does not import it is not; a test file that
#        calls the exemplar leads where-else ahead of one that only imports it, the dir holding the siblings' tests is named, and
#        the same-tree file they import is the test support; a trampoline main (one delegate) names the delegate's own hand-off
#        `a -> b -> c`; a main that calls only a same-file helper names the file that helper calls; the attrs step sheds
#        `:line kind hops=` from <entry> before any entry is cut. Each OFF switch (SURFACE / SUBJECTTESTS / HANDOFF) removes its part.
# usage: test/briefcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "briefcheck: BIN=$BIN"

# ─── fixtures ───────────────────────────────────────────────────────────────────────────────────────────────────────
mk_cmake() {   # small C + CMake + vendored + generated dirs + a CONTRIBUTING with headings
    local d="$TMP/cmake"; mkdir -p "$d/src" "$d/tests" "$d/third_party/zlib" "$d/vendor/lib" "$d/build"
    printf 'cmake_minimum_required(VERSION 3.20)\nproject(widget C)\nenable_testing()\nadd_executable(widget src/main.c src/retry.c)\nadd_test(NAME retry COMMAND test_retry)\n' > "$d/CMakeLists.txt"
    printf '#include "retry.h"\nint main( void )\n{\n    return retry_send( 3 );\n}\n' > "$d/src/main.c"
    printf '#pragma once\nint retry_send( int attempts );\n' > "$d/src/retry.h"
    printf '#include "retry.h"\nint retry_send( int attempts )\n{\n    return attempts > 0 ? 0 : 1;\n}\n' > "$d/src/retry.c"
    printf '#include "../src/retry.h"\nint test_retry( void )\n{\n    return retry_send( 1 );\n}\n' > "$d/tests/test_retry.c"
    printf 'int inflate_fast( int x )\n{\n    return x;\n}\n' > "$d/third_party/zlib/inflate.c"
    printf 'int vend( int x )\n{\n    return x;\n}\n' > "$d/vendor/lib/vend.c"
    printf 'int gen_out( int x )\n{\n    return x;\n}\n' > "$d/build/gen.c"
    printf '# Contributing\n\n## Style\n\nAllman braces.\n\n## Tests\n\nAdd a test per fix.\n' > "$d/CONTRIBUTING.md"
}
mk_python() {
    local d="$TMP/python"; mkdir -p "$d/pkg" "$d/tests"
    printf '[project]\nname = "pkg"\n[tool.pytest.ini_options]\ntestpaths = ["tests"]\n' > "$d/pyproject.toml"
    printf 'def fetch( url ):\n    return retry( url, 3 )\n\ndef retry( url, n ):\n    return url * n\n' > "$d/pkg/client.py"
    printf 'from pkg.client import fetch\n\ndef main():\n    return fetch( "x" )\n' > "$d/pkg/__main__.py"
    printf 'from pkg.client import retry\n\ndef test_retry():\n    assert retry( "a", 2 ) == "aa"\n' > "$d/tests/test_client.py"
}
mk_node() {
    local d="$TMP/node"; mkdir -p "$d/src" "$d/test" "$d/node_modules/left-pad"
    printf '{\n  "name": "http-thing",\n  "main": "src/index.js",\n  "scripts": {\n    "test": "mocha test",\n    "build": "tsc -p ."\n  }\n}\n' > "$d/package.json"
    printf 'function request( url ) { return retry( url ); }\nfunction retry( url ) { return url; }\nmodule.exports = { request, retry };\n' > "$d/src/index.js"
    printf 'const { retry } = require( "../src/index.js" );\ndescribe( "retry", () => { it( "works", () => retry( "a" ) ); } );\n' > "$d/test/retry.test.js"
    printf 'module.exports = function leftPad( s ) { return s; };\n' > "$d/node_modules/left-pad/index.js"
}
mk_bare() {    # no manifest, no docs: the negative arm's fuel
    local d="$TMP/bare"; mkdir -p "$d/lib"
    printf 'int retry_send( int attempts )\n{\n    return attempts;\n}\nint caller( void )\n{\n    return retry_send( 2 );\n}\n' > "$d/lib/net.c"
}
mk_many() {    # mk_many DIR N: N one-function C files under DIR/src/mNN/
    local d="$1" n="$2" i
    mkdir -p "$d"
    printf 'all:\n\tcc -o app src/*/*.c\ntest:\n\t./run_tests.sh\n' > "$d/Makefile"
    python3 - "$d" "$n" <<'PY'
import os, sys
d, n = sys.argv[1], int(sys.argv[2])
for i in range(n):
    sub = os.path.join(d, "src", "m%03d" % (i // 100)); os.makedirs(sub, exist_ok=True)
    nxt = "retry_send" if i == 0 else "f%d" % (i - 1)
    open(os.path.join(sub, "f%d.c" % i), "w").write("int %s( int x );\nint f%d( int x )\n{\n    return %s( x );\n}\n" % (nxt, i, nxt))
open(os.path.join(d, "src", "net.c"), "w").write("int retry_send( int attempts )\n{\n    return attempts;\n}\n")
PY
}
mk_cmake; mk_python; mk_node; mk_bare
mk_many "$TMP/medium" 1200
mk_many "$TMP/large" 10050

TASK="add retry to the http client send path (retry_send)"
brief() { ( cd "$1" && "$BIN" . --no-cache "--brief=$TASK" "${@:2}" 2>/dev/null ) || no "--brief exited $? in ${1##*/} ${*:2}"; }
attr() { python3 -c 'import re,sys; t=sys.stdin.read(); m=re.search(r"<brief [^>]*\b"+sys.argv[1]+r"=\"([^\"]*)\"", t); print(m.group(1) if m else "")' "$1"; }

classOf() { case "$1" in medium) echo medium ;; large) echo large ;; *) echo small ;; esac; }
# Each class cap is its content room (3584/5120/7168) plus the 379 B the legend's attribute definitions and schema= add over the
# 104-B notes comment (brief.h kLegendDefsBytes): a legend edit that moves this must re-pin it here, so the fit change is seen.
LEGEND_DEFS=379
capOf() { case "$1" in medium) echo $(( 5120 + LEGEND_DEFS )) ;; large) echo $(( 7168 + LEGEND_DEFS )) ;; *) echo $(( 3584 + LEGEND_DEFS )) ;; esac; }
pageLen() { python3 -c 'import sys; print(len(open(sys.argv[1], "rb").read().rstrip(b"\n")))' "$1"; }
built=0
for f in cmake python node bare medium large; do
    brief "$TMP/$f" > "$TMP/$f.out"   # status: brief() FAILs the gate on a nonzero exit
    grep -q '^<brief ' "$TMP/$f.out" && built=$(( built + 1 ))
done
if [ "$built" = 6 ]; then ok "(P) six fixtures answer a <brief> root"; else no "(P) only $built of 6 fixtures answered a <brief> root"; fi

# ─── (B) budget per class ───────────────────────────────────────────────────────────────────────────────────────────
nb=0
for f in cmake python node bare medium large; do
    [ -s "$TMP/$f.out" ] || continue
    len=$( pageLen "$TMP/$f.out" )
    b=$( attr bytes < "$TMP/$f.out" ); bud=$( attr budget < "$TMP/$f.out" ); cls=$( attr size_class < "$TMP/$f.out" )
    want=$( classOf "$f" ); cap=$( capOf "$want" )
    if [ "$cls" = "$want" ] && [ "$bud" = "$cap" ] && [ "$b" = "$len" ] && [ "$len" -le "$bud" ]; then
        nb=$(( nb + 1 ))
    else
        no "(B) $f: size_class=$cls (want $want) budget=$bud (want $cap) bytes=$b page=$len"
    fi
done
if [ "$nb" = 6 ]; then ok "(B) all 6 fixtures: size_class, class cap as budget=, bytes= = page length <= budget"; else no "(B) $nb of 6 fixtures held the class budget"; fi
brief "$TMP/large" --brief-bytes=2048 > "$TMP/l2048.out"   # status: brief() FAILs the gate on a nonzero exit
len=$( pageLen "$TMP/l2048.out" )
if [ "$( attr budget < "$TMP/l2048.out" )" = 2048 ] && [ "$len" -le 2048 ] && [ "$len" -gt 0 ]; then ok "(B) --brief-bytes=2048 holds a large page to $len <= 2048"; else no "(B) --brief-bytes=2048: budget=$( attr budget < "$TMP/l2048.out" ) page=$len"; fi

# ─── (M) quoted, never guessed ──────────────────────────────────────────────────────────────────────────────────────
python3 - "$TMP" <<'PY' > "$TMP/m.probe"
import os, re, sys
tmp = sys.argv[1]; quoted = 0; bad = []
for f in ("cmake", "python", "node", "medium", "large"):
    t = open(os.path.join(tmp, f + ".out")).read()
    m = re.search(r"<build>(.*?)</build>", t)
    for line in (m.group(1).split(" | ") if m else []):
        src = re.match(r"([^ :]+):", line)
        if line.startswith(("new test", "tests run by", "test support")):
            continue
        if not src or not os.path.exists(os.path.join(tmp, f, src.group(1))):
            bad.append(f + ": " + line)
        else:
            quoted += 1
print("QUOTED:%d" % quoted)
for b in bad: print("BAD:" + b)
PY
q=$( grep '^QUOTED:' "$TMP/m.probe" | cut -d: -f2 )
if [ "${q:-0}" -ge 4 ] && ! grep -q '^BAD:' "$TMP/m.probe"; then ok "(M) $q build lines, each naming an existing file"
else no "(M) quoted=$q; $( grep '^BAD:' "$TMP/m.probe" | head -3 | tr '\n' ';' )"; fi
bb=$( grep -o '<build>[^<]*</build>' "$TMP/bare.out" )
if [ "$bb" = "<build>none found</build>" ] && [ "$( attr build_source < "$TMP/bare.out" )" = none ]; then ok "(M) no manifest, no docs: <build>none found</build>, build_source=\"none\""
else no "(M) bare fixture build: '$bb' build_source=$( attr build_source < "$TMP/bare.out" )"; fi
heads=0
for h in make cmake npm pytest "go " cargo tox; do printf '%s' "$bb" | grep -qF "$h" && heads=$(( heads + 1 )); done
if [ "$heads" = 0 ]; then ok "(M) the bare fixture's build names no command head (7 checked)"; else no "(M) a GUESSED command in the bare fixture's build: $bb"; fi

# ─── (S) skip marks ────────────────────────────────────────────────────────────────────────────────────────────────
lay=$( grep -o '<layout>[^<]*</layout>' "$TMP/cmake.out" )
ns=0
for d in "third_party/ vendored(skip)" "vendor/ vendored(skip)" "build/ generated(skip)"; do printf '%s' "$lay" | grep -qF "$d" && ns=$(( ns + 1 )); done
if [ "$ns" = 3 ]; then ok "(S) third_party/, vendor/ and build/ marked (skip)"; else no "(S) $ns of 3 skip marks: $lay"; fi
if printf '%s' "$lay" | grep -q 'src/ [a-z]*(skip)'; then no "(S) src/ marked skip: $lay"; else ok "(S) src/ is not marked skip"; fi
if grep -o '<layout>[^<]*</layout>' "$TMP/node.out" | grep -qF 'node_modules/ vendored(skip)'; then ok "(S) node_modules/ marked vendored(skip)"; else no "(S) node_modules/ not marked: $( grep -o '<layout>[^<]*</layout>' "$TMP/node.out" )"; fi

# ─── (O) drop order ────────────────────────────────────────────────────────────────────────────────────────────────
brief "$TMP/cmake" --brief-bytes=512 > "$TMP/o.out"   # status: brief() FAILs the gate on a nonzero exit
dr=$( attr dropped < "$TMP/o.out" )
python3 - "$dr" <<'PY' > "$TMP/o.probe"
import sys
order = "conventions,attrs,layout_depth,ranked,entry,edges,where_else,qs".split(",")
got = [x for x in sys.argv[1].split(",") if x]
print("OK" if got and got == order[:len(got)] else "BAD")
PY
if [ "$( cat "$TMP/o.probe" )" = OK ]; then ok "(O) --brief-bytes=512 dropped=\"$dr\" is a prefix of the drop order"; else no "(O) dropped=\"$dr\" breaks the order"; fi
if grep -q '<act read="' "$TMP/o.out" && grep -q '<build>' "$TMP/o.out"; then ok "(O) act and build survive the 512-byte cut"; else no "(O) act or build dropped at 512 B"; fi
# the fixed sections (root, legend, act, build, the three-moment block) can outgrow a tiny budget: that is disclosed, never hidden
olen=$( pageLen "$TMP/o.out" ); over=$( attr over < "$TMP/o.out" )
if { [ "$olen" -gt 512 ] && [ "$over" = 1 ]; } || { [ "$olen" -le 512 ] && [ -z "$over" ]; }; then ok "(O) over=\"$over\" matches the 512-byte page's $olen B"
else no "(O) page $olen B vs budget 512 but over=\"$over\""; fi

# ─── (D) determinism + well-formedness ─────────────────────────────────────────────────────────────────────────────
brief "$TMP/cmake" > "$TMP/cmake.2"; brief "$TMP/large" > "$TMP/large.2"   # status: brief() FAILs the gate on a nonzero exit
if cmp -s "$TMP/cmake.out" "$TMP/cmake.2" && cmp -s "$TMP/large.out" "$TMP/large.2"; then ok "(D) two runs byte-identical (small + large)"; else no "(D) two runs differ"; fi
nw=0
for f in cmake python node bare medium large; do
    if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$TMP/$f.out" 2>/dev/null && nw=$(( nw + 1 ))
    else python3 -c 'import sys,xml.dom.minidom as m; m.parse(sys.argv[1])' "$TMP/$f.out" 2>/dev/null && nw=$(( nw + 1 )); fi
done
if [ "$nw" = 6 ]; then ok "(D) all 6 pages well-formed XML"; else no "(D) $nw of 6 pages well-formed"; fi

# ─── (R) refusals ──────────────────────────────────────────────────────────────────────────────────────────────────
nr=0
for args in "--brief=x --for=y" "--brief-bytes=2048" "--brief=x --brief-bytes=100"; do
    # shellcheck disable=SC2086
    out=$( cd "$TMP/bare" && "$BIN" . $args 2>/dev/null ); rc=$?
    [ "$rc" != 0 ] && ! printf '%s' "$out" | grep -q '<brief' && nr=$(( nr + 1 )) || no "(R) '$args' rc=$rc"
done
if [ "$nr" = 3 ]; then ok "(R) 3 misuse forms refused, no brief printed"; else no "(R) $nr of 3 misuse forms refused"; fi
# an unwritable TMPDIR leaves no buffer for the --for page: refused before --for runs, so stdout stays EMPTY (no leaked --for page).
# Darwin's std::tmpfile honours TMPDIR, so the refusal is reachable there. glibc's std::tmpfile ignores TMPDIR (it opens under
# P_tmpdir, /tmp), so on Linux the buffer still opens: there the arm asserts the other half of the contract, that stdout carries
# exactly one brief page and no leaked --for page.
out=$( cd "$TMP/cmake" && TMPDIR="$TMP/no-such-dir" "$BIN" . --no-cache --brief="add a retry" 2>/dev/null ); rc=$?
nb=$( printf '%s' "$out" | wc -c | tr -d ' ' )
if [ "$( uname -s )" = Darwin ]; then
    if [ "$rc" != 0 ] && [ -z "$out" ]; then ok "(R) no temp buffer: refused, stdout empty"; else no "(R) no temp buffer: rc=$rc, $nb B on stdout"; fi
else
    nbrief=$( printf '%s\n' "$out" | grep -c '<brief[ >]' ); nfor=$( printf '%s\n' "$out" | grep -c '<ctx[ >]' )
    if [ "$rc" = 0 ] && [ "$nbrief" = 1 ] && [ "$nfor" = 0 ]; then ok "(R) no temp buffer (glibc tmpfile ignores TMPDIR): one brief page, no leaked --for page ($nb B)"
    else no "(R) no temp buffer (glibc): rc=$rc, $nb B, <brief> x$nbrief, <ctx> (--for root) x$nfor (want rc=0, 1, 0)"; fi
fi

# ─── (G) schema and legend: the page explains itself in both dialects ──────────────────────────────────────────────────────
# The default (compact) page carries schema="ripwire.brief/v1" and a legend that names every attribute the page carries
# (present-only: an absent attribute's term is not printed); --legend=full is the same page with the worded legend.
brief "$TMP/cmake" > "$TMP/s.def"; brief "$TMP/cmake" --legend=full > "$TMP/s.full"; brief "$TMP/cmake" --brief-bytes=512 > "$TMP/s.cut"   # status: brief() FAILs the gate on a nonzero exit
sres=$( python3 - "$TMP/s.def" "$TMP/s.full" "$TMP/s.cut" <<'PY'
import re, sys
CORE = { "p", "n", "t", "id", "l", "k", "c" }
def parts( path ):
    d = open( path, encoding = "utf-8" ).read()
    leg = " ".join( re.findall( r"<!--(.*?)-->", d, re.S ) )
    body = re.sub( r"<!--.*?-->", "", re.sub( r"<!\[CDATA\[.*?\]\]>", "", d, flags = re.S ), flags = re.S )
    attrs = { a for a in re.findall( r"\s([\w:.-]+)=\"", body ) if a not in CORE }
    return d, leg, body, attrs
bad = []; seen = 0
for path in sys.argv[ 1: ]:
    d, leg, body, attrs = parts( path )
    seen += len( attrs )
    if 'schema="ripwire.brief/v1"' not in d: bad.append( path + ": no schema=" )
    miss = sorted( a for a in attrs if not re.search( r"(?<![\w:.-])" + re.escape( a ) + r"\s*=", leg ) )
    if miss: bad.append( path + ": undefined " + ",".join( miss ) )
dd, dl, db, da = parts( sys.argv[ 1 ] ); fd, fl, fb, fa = parts( sys.argv[ 2 ] ); cd, cl, cb, ca = parts( sys.argv[ 3 ] )
if db != fb:
    k = next( ( i for i in range( min( len( db ), len( fb ) ) ) if db[ i ] != fb[ i ] ), min( len( db ), len( fb ) ) )
    bad.append( "full and compact differ outside the legend at %d: [%s] vs [%s]" % ( k, db[ max( 0, k - 40 ):k + 60 ], fb[ max( 0, k - 40 ):k + 60 ] ) )
if not len( dl ) < len( fl ): bad.append( "compact legend not shorter than full" )
if "dropped" in ca and "dropped=" not in cl: bad.append( "cut page: dropped= undefined" )
if "dropped" not in da and "dropped=" in dl: bad.append( "uncut page names dropped= (present-only)" )
if "dropped" not in ca: bad.append( "premise: the 512-B page dropped nothing" )
print( "OK %d" % seen if not bad and seen > 0 else "BAD " + "; ".join( bad ) + " (attrs seen %d)" % seen )
PY
)
case "$sres" in OK*) ok "(G) schema= and a legend naming every attribute (${sres#OK } seen), present-only dropped=, full = compact outside the legend" ;; *) no "(G) $sres" ;; esac

# ─── (L) --plan-lanes --brief=FILE keeps its meaning ───────────────────────────────────────────────────────────────
printf 'add a retry to the client\nrename the parser entry\n' > "$TMP/lanes.txt"
lp=$( cd "$TMP/cmake" && "$BIN" . --plan-lanes --brief="$TMP/lanes.txt" 2>/dev/null ); rc=$?
nl=$( printf '%s' "$lp" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("lanes",[])))' 2>/dev/null || echo 0 )
if [ "$rc" = 0 ] && [ "$nl" = 2 ] && ! printf '%s' "$lp" | grep -q '<brief'; then ok "(L) --plan-lanes --brief=FILE answers a 2-lane plan, no <brief> root"; else no "(L) --plan-lanes --brief=FILE rc=$rc lanes=$nl"; fi

# ─── (C) the MCP twin ──────────────────────────────────────────────────────────────────────────────────────────────
mcp_call() { printf '%s\n' "$@" | ( cd "$TMP/cmake" && "$BIN" --mcp 2>/dev/null ); }
LIST=$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )   # status: the server's JSON reply is parsed below; no reply (an exited server) fails that arm
if printf '%s' "$LIST" | python3 -c 'import sys,json; print(int(any(t["name"]=="brief" for t in json.load(sys.stdin)["result"]["tools"])))' 2>/dev/null | grep -q 1; then ok "(C) tools/list advertises brief"; else no "(C) brief missing from tools/list"; fi
call() {
    local req="{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"brief\",\"arguments\":$1}}" reply
    reply=$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$req" | tail -1 )   # status: the reply is parsed below; no reply (an exited server) prints a traceback, never a page, and the arm FAILs
    printf '%s' "$reply" | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__" if "error" in r or r.get("result", {}).get("isError") else r["result"]["content"][0]["text"])'
}
call "{\"path\":\".\",\"task\":\"$TASK\"}" > "$TMP/c.out"
if grep -q '^<brief ' "$TMP/c.out" && grep -q '<act read="' "$TMP/c.out"; then ok "(C) tools/call brief answers a <brief> root with its act"; else no "(C) MCP brief: $( head -c 200 "$TMP/c.out" )"; fi
if call "{\"path\":\".\",\"task\":\"$TASK\",\"bytes\":100}" | grep -q '__ERROR__'; then ok "(C) bytes=100 refused"; else no "(C) bytes=100 not refused"; fi

# ─── (X) round-2 detectors: each on its own synthetic fixture, each arm counts what it saw and FAILs on zero ────────
# Run with --brief-bytes=8192 so no drop step hides what a detector found; every name below is the fixture's own.
mk_autoconf() {   # autoconf without automake: configure.ac + a committed configure + a template makefile; a project program
    local d="$TMP/ac"; mkdir -p "$d/Programs" "$d/Modules" "$d/Objects" "$d/Tools/scan" "$d/Lib/test"
    printf 'AC_INIT([gizmo],[1.0])\nAC_OUTPUT\n' > "$d/configure.ac"
    printf '#!/bin/sh\necho configured\n' > "$d/configure"; chmod +x "$d/configure"
    printf 'all:\n\tcc -o gizmo Programs/gizmo.c Modules/runmain.c Objects/widget.c\ntest:\n\t./gizmo --selftest\n' > "$d/Makefile.pre.in"
    # main calls one function in Modules/aaa_log.c and two in Modules/runmain.c: the file it calls into most is named first
    printf 'void log_init( void );\nvoid gizmo_setup( void );\nint gizmo_run_main( int argc, char** argv );\nint main( int argc, char** argv )\n{\n    log_init();\n    gizmo_setup();\n    return gizmo_run_main( argc, argv );\n}\n' > "$d/Programs/gizmo.c"
    printf 'int widget_frobnicate( int x );\nvoid gizmo_setup( void )\n{\n}\nint gizmo_run_main( int argc, char** argv )\n{\n    (void)argv;\n    return widget_frobnicate( argc );\n}\n' > "$d/Modules/runmain.c"
    printf 'void log_init( void )\n{\n}\n' > "$d/Modules/aaa_log.c"
    printf 'int widget_frobnicate( int x )\n{\n    return x * 2;\n}\n' > "$d/Objects/widget.c"
    printf 'int widget_frobnicate( int x );\nint main( void )\n{\n    return widget_frobnicate( 1 );\n}\n' > "$d/Tools/scan/scan.c"
    printf 'import unittest\nunittest.main()\n' > "$d/Lib/test/test_spin.py"    # no symbol: only its name says spin
    printf 'def test_other():\n    assert True\n' > "$d/Lib/test/test_other.py"
}
mk_goreg() {      # a Go module: a project-named cmd beside a bigger one; registry/metadata/build config near the act; tests
    local d="$TMP/goreg" i; mkdir -p "$d/cmd/toolbox" "$d/cmd/zbig" "$d/pkg/feature/impl" "$d/pkg/feature/registry" "$d/pkg/feature/sub/testdata/cases" "$d/pkg/feature/sub/testdata/small"
    printf 'module example.com/acme/toolbox\n\ngo 1.21\n' > "$d/go.mod"
    printf 'package main\n\nfunc main() {\n}\n' > "$d/cmd/toolbox/main.go"
    printf 'package main\n\nfunc main() {\n}\n' > "$d/cmd/zbig/main.go"
    for i in 1 2 3 4 5 6; do printf 'package main\n\nfunc helper%s() int {\n\treturn %s\n}\n' "$i" "$i" > "$d/cmd/zbig/h$i.go"; done
    printf 'package impl\n\n// HandleWidget serves one widget.\nfunc HandleWidget(n int) int {\n\treturn n + 1\n}\n' > "$d/pkg/feature/impl/handler.go"
    printf 'package impl\n\nimport "testing"\n\nfunc TestOne(t *testing.T) {}\n' > "$d/pkg/feature/impl/impl_test.go"
    printf 'package registry\n\nfunc Register(name string) {}\n' > "$d/pkg/feature/registry/registry.go"
    printf 'features:\n  - widget\n' > "$d/pkg/feature/feature_metadata.yaml"
    printf 'FEATURES = []\n' > "$d/pkg/feature/all_features.bzl"
    for i in $( seq 1 25 ); do printf 'case %s\n' "$i" > "$d/pkg/feature/sub/testdata/cases/c$i.txt"; done
    printf 'x\n' > "$d/pkg/feature/sub/testdata/small/a.txt"
}
mk_cargo() {      # a Cargo workspace (no package name): the project comes from the origin remote; a build script; a bigger tool
    local d="$TMP/cargo" i; mkdir -p "$d/crates/spinner/src" "$d/crates/aaa_tool/src"
    printf '[workspace]\nmembers = ["crates/*"]\n' > "$d/Cargo.toml"
    printf '[package]\nname = "spinner"\n\n[[bin]]\nname = "spinner"\npath = "src/main.rs"\n' > "$d/crates/spinner/Cargo.toml"
    printf 'fn main() {\n}\n' > "$d/crates/spinner/src/main.rs"
    printf 'pub fn spin_loop(n: u32) -> u32 {\n    n + 1\n}\n' > "$d/crates/spinner/src/lib.rs"
    printf 'fn main() {\n}\n' > "$d/crates/spinner/build.rs"
    printf '[package]\nname = "aaa_tool"\n' > "$d/crates/aaa_tool/Cargo.toml"
    printf 'fn main() {\n}\n' > "$d/crates/aaa_tool/src/main.rs"
    for i in 1 2 3 4 5 6; do printf 'pub fn part%s() -> u32 {\n    %s\n}\n' "$i" "$i" > "$d/crates/aaa_tool/src/p$i.rs"; done
    ( cd "$d" && git init -q && git remote add origin https://example.com/acme/spinner.git ) >/dev/null 2>&1
}
mk_autoconf; mk_goreg; mk_cargo
xbrief() { local d="$1" t="$2"; ( cd "$TMP/$d" && "$BIN" . --no-cache --brief-bytes=8192 "--brief=$t" 2>/dev/null ) || no "--brief exited $? in $d"; }
xbrief ac "add a new spin operation for widgets next to widget_frobnicate" > "$TMP/ac.out"   # status: xbrief() FAILs the gate on a nonzero exit
xbrief goreg "add a new widget variant next to HandleWidget" > "$TMP/goreg.out"   # status: xbrief() FAILs the gate on a nonzero exit
xbrief cargo "add a new spin mode to spin_loop" > "$TMP/cargo.out"   # status: xbrief() FAILs the gate on a nonzero exit
sect() { python3 -c 'import re,sys; t=open(sys.argv[1]).read(); m=re.search(r"<"+sys.argv[2]+r"[^>]*>(.*?)</"+sys.argv[2]+">", t, re.S); print(m.group(1) if m else "")' "$1" "$2"; }
firstEntry() { sect "$1" entry | sed 's/ · .*//' | cut -d: -f1; }
# X1/X5/X9 the project's own program leads (Programs/<p>.c, cmd/<p>/, crates/<p>/src/main.rs) — a tool main, a bigger cmd and a
# build script would lead without it
n=0
for pair in "ac Programs/gizmo.c" "goreg cmd/toolbox/main.go" "cargo crates/spinner/src/main.rs"; do
    set -- $pair
    if [ "$( firstEntry "$TMP/$1.out" )" = "$2" ]; then n=$(( n + 1 )); else no "(X) $1: first entry is '$( firstEntry "$TMP/$1.out" )', not the project program $2"; fi
done
if [ "$n" = 3 ]; then ok "(X) the project's own program leads the entries on 3 of 3 fixtures"; else no "(X) project program led on $n of 3 fixtures"; fi
nb=$( sect "$TMP/cargo.out" entry | tr '·' '\n' | grep -c 'build.rs' )
pos=$( sect "$TMP/cargo.out" entry | tr '·' '\n' | grep -n 'crates/spinner/src/main.rs' | cut -d: -f1 )
if [ "${pos:-0}" = 1 ] && [ "$( sect "$TMP/cargo.out" entry | tr '·' '\n' | head -1 | grep -c 'build.rs' )" = 0 ]; then ok "(X) a cargo build script never leads ($nb build.rs rows, after the program)"; else no "(X) build.rs placement: program at ${pos:-none}"; fi
# X2 the delegate: the leading main's cross-file callee file
nd=$( sect "$TMP/ac.out" entry | grep -c 'Programs/gizmo.c:[0-9]* main[^·]* -> Modules/runmain.c, Modules/aaa_log.c' )
if [ "$nd" -ge 1 ]; then ok "(X) the leading main names the files it hands off to, most-called first ($nd: -> Modules/runmain.c, Modules/aaa_log.c)"; else no "(X) delegates on the leading main: $( sect "$TMP/ac.out" entry )"; fi
# X3 autoconf without automake: the configure line and the template makefile's targets
nbld=0
sect "$TMP/ac.out" build | grep -qF 'configure.ac: ./configure &amp;&amp; make' && nbld=$(( nbld + 1 ))
sect "$TMP/ac.out" build | grep -qF 'Makefile.pre.in: make all · make test' && nbld=$(( nbld + 1 ))
if [ "$nbld" = 2 ]; then ok "(X) autoconf without automake: configure.ac and Makefile.pre.in quoted (2 of 2)"; else no "(X) autoconf build lines $nbld of 2: $( sect "$TMP/ac.out" build )"; fi
# X6 registration near the act: a registry dir, a metadata yaml and a build config two dirs up from the act file
nreg=0
for r in pkg/feature/registry/ pkg/feature/feature_metadata.yaml pkg/feature/all_features.bzl; do
    sect "$TMP/goreg.out" edges | grep -o '<r>[^<]*</r>' | grep -qE "[: ]$r( |<)" && nreg=$(( nreg + 1 ))
done
if [ "$nreg" = 3 ]; then ok "(X) registration lists the registry dir, the metadata file and the build config (3 of 3)"; else no "(X) registration $nreg of 3: $( sect "$TMP/goreg.out" edges )"; fi
# X7/X8/X4 tests: the dir-named _test sibling, the subsystem's testdata corpus (its fullest subdir), a task-word test file
nt=0
sect "$TMP/goreg.out" where-else | grep -qF 'test pkg/feature/impl/impl_test.go' && nt=$(( nt + 1 ))
sect "$TMP/goreg.out" where-else | grep -qF 'test pkg/feature/sub/testdata/cases/' && nt=$(( nt + 1 ))
sect "$TMP/ac.out" where-else | grep -qF 'test Lib/test/test_spin.py' && nt=$(( nt + 1 ))
if [ "$nt" = 3 ]; then ok "(X) tests: dir-named _test sibling, testdata corpus and task-word test file (3 of 3)"; else no "(X) test detectors $nt of 3: $( sect "$TMP/goreg.out" where-else ) | $( sect "$TMP/ac.out" where-else )"; fi

# ─── (A) the exemplar anchor: "like X" resolved to ONE unit leads the named files; ambiguous discloses and adds nothing ──
mk_stages() {     # a pipeline of stages: the exemplar is a class two words long; an ambiguous helper is defined twice
    local d="$TMP/stages"; mkdir -p "$d/src/ext/stages/squash" "$d/src/ext/stages/merge" "$d/tests/ext/stages/squash" "$d/tools" "$d/lib"
    printf 'class SquashStage:\n    def run(self, rows):\n        return rows[:1]\n' > "$d/src/ext/stages/squash/squash_stage.py"
    printf 'class MergeStage:\n    def run(self, rows):\n        return rows + rows\n' > "$d/src/ext/stages/merge/merge_stage.py"
    printf 'from src.ext.stages.squash.squash_stage import SquashStage\nfrom src.ext.stages.merge.merge_stage import MergeStage\n\ndef build_pipeline():\n    return [SquashStage(), MergeStage()]\n\ndef run_pipeline(rows):\n    for s in build_pipeline():\n        rows = s.run(rows)\n    return rows\n' > "$d/pipeline.py"
    printf 'def test_squash():\n    assert True\n' > "$d/tests/ext/stages/squash/test_squash.py"   # the test mirror of the exemplar dir
    printf 'def frob(x):\n    return x\n' > "$d/tools/frobber.py"
    printf 'def frob(x):\n    return x + 1\n' > "$d/lib/frobs.py"
}
mk_stages
abrief() { ( cd "$TMP/stages" && "$BIN" . --no-cache --brief-bytes=8192 "--brief=$1" 2>/dev/null ) || no "--brief exited $? in stages: $1"; }
abrief "add a new stage (like the squash stage) to run_pipeline" > "$TMP/a1.out"   # status: abrief() FAILs the gate on a nonzero exit
abrief "add a new helper like frob to run_pipeline" > "$TMP/a2.out"   # status: abrief() FAILs the gate on a nonzero exit
abrief "add a new helper to run_pipeline" > "$TMP/a3.out"   # status: abrief() FAILs the gate on a nonzero exit
na=0
if grep -qF '<like t="squash stage">src/ext/stages/squash/squash_stage.py</like>' "$TMP/a1.out"; then na=$(( na + 1 )); else no "(A) unique exemplar not anchored: $( grep -o '<task.*</task>' "$TMP/a1.out" | head -c 300 )"; fi
if sect "$TMP/a1.out" edges | grep -q '^<i f="src/ext/stages/squash/squash_stage.py">'; then na=$(( na + 1 )); else no "(A) the anchored file does not lead the edges (its imports line first): $( sect "$TMP/a1.out" edges )"; fi
if grep -qF '<like t="frob" ambiguous="2">lib/frobs.py · tools/frobber.py</like>' "$TMP/a2.out"; then na=$(( na + 1 )); else no "(A) ambiguous exemplar not disclosed: $( grep -o '<task.*</task>' "$TMP/a2.out" | head -c 300 )"; fi
same=0
for s in layout build entry edges where-else conventions; do
    [ "$( sect "$TMP/a2.out" "$s" )" = "$( sect "$TMP/a3.out" "$s" )" ] && same=$(( same + 1 ))
done
if [ "$same" = 6 ]; then na=$(( na + 1 )); else no "(A) an ambiguous exemplar changed $(( 6 - same )) of 6 sections against the task without it"; fi
if sect "$TMP/a1.out" where-else | grep -q '^test tests/ext/stages/squash/'; then na=$(( na + 1 )); else no "(A) the exemplar's test mirror does not lead where-else: $( sect "$TMP/a1.out" where-else )"; fi
if ! grep -q '<like' "$TMP/a3.out" && ! grep -q '<like' "$TMP/cmake.out"; then na=$(( na + 1 )); else no "(A) a task with no like-phrase drew a <like> element"; fi
if [ "$na" = 6 ]; then ok "(A) exemplar anchor: unique accepted, leads the edges and its test mirror leads where-else, ambiguous disclosed with 6 of 6 sections unchanged, no phrase no element (6 of 6)"; else no "(A) exemplar anchor $na of 6"; fi

# ─── (H) co-change roles + the unit's build file (BRIEF-COCHANGE) ─────────────────────────────────────────────────────
mk_hist() {       # a C project whose functions are added the same way each time: catalog + corpus test + docs + changelog + unit build
    local d="$TMP/hist" i n=0
    mkdir -p "$d/src/functions" "$d/tests/queries/stateless" "$d/docs" "$d/src/core"
    printf 'cmake_minimum_required(VERSION 3.10)\nproject(hist C)\nadd_subdirectory(src/functions)\n' > "$d/CMakeLists.txt"
    printf 'int core_main(void) { return 0; }\n' > "$d/src/core/main.c"
    printf 'int hot(void) { return 0; }\n' > "$d/src/core/hot.c"
    git -C "$d" init -q && git -C "$d" config user.email t@example.invalid && git -C "$d" config user.name t
    commit() { n=$(( n + 1 )); local at; at="$( python3 -c "import datetime,sys; print((datetime.datetime(2026,1,1,10)+datetime.timedelta(days=int(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$n" )"; git -C "$d" add -A && GIT_AUTHOR_DATE="$at" GIT_COMMITTER_DATE="$at" git -C "$d" commit -qm "$1"; }
    commit "base"
    for i in $( seq 1 22 ); do
        printf 'int fn_%s(int x) { return x + %s; }\n' "$i" "$i" > "$d/src/functions/fn_$i.c"
        printf 'void add_fn_%s(void);\n' "$i" >> "$d/src/catalog.c"
        printf 'SELECT fn_%s(1);\n' "$i" > "$d/tests/queries/stateless/000${i}_fn_$i.sql"
        printf '## fn_%s\n' "$i" >> "$d/docs/functions.md"
        printf -- '- add fn_%s\n' "$i" >> "$d/CHANGELOG.md"
        printf 'add_library(fn_%s fn_%s.c)\n' "$i" "$i" >> "$d/src/functions/CMakeLists.txt"
        commit "add fn_$i"
        printf '// %s\n' "$i" >> "$d/src/core/hot.c"; commit "tweak hot $i a"
        printf '// %s b\n' "$i" >> "$d/src/core/hot.c"; commit "tweak hot $i b"
    done
    for i in $( seq 1 60 ); do printf 'int w_%s;\n' "$i" > "$d/src/core/wide_$i.c"; done
    for i in $( seq 1 22 ); do printf '\n' >> "$d/src/functions/fn_$i.c"; done
    printf '\n' >> "$d/src/core/main.c"; commit "format everything"
}
mk_hist
hbrief() { ( cd "$1" && env "${@:2}" "$BIN" . --no-cache --brief-bytes=8192 "--brief=add a new function (like fn_3) to the catalog" 2>/dev/null ); }
hbrief "$TMP/hist" > "$TMP/h1.out"
hbrief "$TMP/hist" RIPWIRE_BRIEF_COCHANGE=0 > "$TMP/h2.out"
hbrief "$TMP/hist" RIPWIRE_BRIEF_UNITBUILD=0 > "$TMP/h3.out"
git clone -q --depth 1 "file://$TMP/hist" "$TMP/hist1" 2>/dev/null
mkdir -p "$TMP/h4cache"; hbrief "$TMP/hist1" TMPDIR="$TMP/h4cache" > "$TMP/h4.out"   # its own cache: the full clone's walk is keyed to the same HEAD
nh=0
[ "$( attr history < "$TMP/h1.out" )" = 1 ] && grep -qF '<like t="fn_3">src/functions/fn_3.c</like>' "$TMP/h1.out" && nh=$(( nh + 1 )) || no "(H) premise: history=\"1\" with the exemplar fn_3 anchored: $( head -c 400 "$TMP/h1.out" )"
sect "$TMP/h1.out" edges | grep -qF '<r>registration: src/catalog.c' && nh=$(( nh + 1 )) || no "(H) the catalog does not lead registration: $( sect "$TMP/h1.out" edges | head -c 300 )"
we="$( sect "$TMP/h1.out" where-else )"
for want in 'test tests/queries/stateless/' 'doc docs/functions.md' 'log CHANGELOG.md'; do
    case "$we" in *"$want"*) nh=$(( nh + 1 )) ;; *) no "(H) where-else lacks '$want': $we" ;; esac
done
sect "$TMP/h1.out" build | grep -qE 'unit build: src/functions/CMakeLists.txt:3( |$|<| ·)' && nh=$(( nh + 1 )) || no "(H) <build> does not name the unit's CMakeLists at the fn_3 line: $( sect "$TMP/h1.out" build )"
grep -qE 'src/core/hot\.c|src/core/wide_|src/core/main\.c' "$TMP/h1.out" && no "(H) the hot file or a sweep-only file reached the brief" || nh=$(( nh + 1 ))
[ "$( attr history < "$TMP/h4.out" )" = 0 ] && ! sect "$TMP/h4.out" edges | grep -qF '<r>registration: src/catalog.c' && nh=$(( nh + 1 )) || no "(H) the 1-commit clone is not history=\"0\" without the history slots"
grep -qF 'unit build: src/functions/CMakeLists.txt' "$TMP/h4.out" && nh=$(( nh + 1 )) || no "(H) the history-free half is missing on the 1-commit clone: $( sect "$TMP/h4.out" build )"
[ "$( attr history < "$TMP/h2.out" )" = 0 ] && ! sect "$TMP/h2.out" edges | grep -qF '<r>registration: src/catalog.c' && grep -qF 'unit build: src/functions/CMakeLists.txt' "$TMP/h2.out" && nh=$(( nh + 1 )) || no "(H) RIPWIRE_BRIEF_COCHANGE=0 did not remove exactly the history half"
! grep -qF 'unit build: src/functions/CMakeLists.txt:3' "$TMP/h3.out" && sect "$TMP/h3.out" edges | grep -qF 'src/catalog.c' && nh=$(( nh + 1 )) || no "(H) RIPWIRE_BRIEF_UNITBUILD=0 did not remove exactly the nearest-manifest half: $( sect "$TMP/h3.out" build )"
if [ "$nh" = 11 ]; then ok "(H) co-change roles: catalog, corpus dir, docs, changelog, the unit's CMakeLists at the exemplar's line; hot and sweep-only files absent; 1-commit clone history=0; both OFF switches (11 of 11)"; else no "(H) co-change roles $nh of 11"; fi

# ─── (I) the brief quotes file text: secrets redacted on CLI and MCP (--no-redact leaves them), and a FIFO convention doc never blocks it ───
mkdir -p "$TMP/sec/src"
printf 'cmake_minimum_required(VERSION 3.10)\nproject(sec C)\nadd_executable(sec src/a.c)\n' > "$TMP/sec/CMakeLists.txt"
printf 'int a(void){return 1;}\nint b(void){return a();}\n' > "$TMP/sec/src/a.c"
cp "$ROOT/test/redactfix/brief_agents.md" "$TMP/sec/AGENTS.md"   # the sanctioned credential-shaped fixture dir (ripwirepubliccheck arm 4)
sec_cli() { ( cd "$TMP/sec" && "$BIN" . --no-cache "$@" "--brief=change a" 2>/dev/null ) || no "--brief exited $? in sec $*"; }
sec_mcp() { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"brief","arguments":{"path":".","task":"change a"}}}' | ( cd "$TMP/sec" && "$BIN" --mcp "$@" 2>/dev/null ) | tail -1; }   # status: its JSON reply is parsed by the (I) arms; no reply fails them
SECRET="$( grep -o 'ghp_[A-Za-z0-9]*' "$ROOT/test/redactfix/brief_agents.md" )"
ni=0
sec_cli > "$TMP/i1.out"; sec_cli --no-redact > "$TMP/i2.out"; sec_mcp > "$TMP/i3.out"; sec_mcp --no-redact > "$TMP/i4.out"   # status: sec_cli() FAILs the gate on a nonzero exit; sec_mcp output is parsed by the arms below
grep -qF 'make test' "$TMP/i2.out" && grep -qF "$SECRET" "$TMP/i2.out" && ni=$(( ni + 1 )) || no "(I) premise: --no-redact CLI brief must quote the doc command raw: $( head -c 300 "$TMP/i2.out" )"
grep -qF 'make test' "$TMP/i1.out" && ! grep -qF "$SECRET" "$TMP/i1.out" && ni=$(( ni + 1 )) || no "(I) the CLI brief leaks the doc fence's secret"
grep -qF "$SECRET" "$TMP/i4.out" && ni=$(( ni + 1 )) || no "(I) premise: --no-redact MCP brief must quote the doc command raw"
grep -qF 'make test' "$TMP/i3.out" && ! grep -qF "$SECRET" "$TMP/i3.out" && ni=$(( ni + 1 )) || no "(I) the MCP brief leaks the doc fence's secret"
rm -f "$TMP/sec/AGENTS.md"; mkfifo "$TMP/sec/AGENTS.md"
( sec_cli > "$TMP/i5.out" 2>/dev/null & bp=$!; for _ in 1 2 3 4 5 6 7 8 9 10; do sleep 1; kill -0 "$bp" 2>/dev/null || exit 0; done; kill -9 "$bp" 2>/dev/null; exit 1 ) && grep -q '^<brief ' "$TMP/i5.out" && ni=$(( ni + 1 )) || no "(I) a FIFO AGENTS.md blocked the brief or it printed nothing"   # status: run in a timed subshell; the grep on i5.out is the check (an exit or hang prints no page)
if [ "$ni" = 5 ]; then ok "(I) file-derived text redacted on CLI and MCP (raw under --no-redact), FIFO convention doc skipped (5 of 5)"; else no "(I) quoted-text safety $ni of 5"; fi
# ─── (Q) package surface, subject tests, main hand-off, attrs-first byte order (BRIEF-R2) ─────────────────────────────
mk_r2() {
    local t="$TMP/r2ts" p="$TMP/r2py" g="$TMP/r2go" m="$TMP/r2main"
    mkdir -p "$t/packages/common/pipes" "$t/packages/common/test/pipes" "$t/packages/common/test/helpers"
    printf '{\n  "name": "@x/common",\n  "main": "index.js"\n}\n' > "$t/packages/common/package.json"
    printf 'export * from "./pipes/index.js";\n' > "$t/packages/common/index.ts"
    printf '// the pipes\nexport * from "./parse-int.pipe.js";\nexport * from "./parse-uuid.pipe.js";\n' > "$t/packages/common/pipes/index.ts"
    printf 'export class ParseIntPipe {\n  transform(v: string) { return parseInt(v); }\n}\n' > "$t/packages/common/pipes/parse-int.pipe.ts"
    printf 'export class ParseUuidPipe {\n  transform(v: string) { return v; }\n}\n' > "$t/packages/common/pipes/parse-uuid.pipe.ts"
    printf 'export function makeArg(s: string) { return s; }\n' > "$t/packages/common/test/helpers/args.ts"
    for n in a b; do
        printf 'import { ParseIntPipe } from "../../pipes/parse-int.pipe";\nimport { makeArg } from "../helpers/args";\ndescribe("p%s", () => { it("t", () => { new ParseIntPipe().transform(makeArg("1")); }); });\n' "$n" > "$t/packages/common/test/pipes/parse-int-$n.spec.ts"
    done
    printf 'import { ParseUuidPipe } from "../../pipes/parse-uuid.pipe";\nimport { makeArg } from "../helpers/args";\ndescribe("u", () => { it("t", () => { new ParseUuidPipe().transform(makeArg("1")); }); });\n' > "$t/packages/common/test/pipes/parse-uuid.spec.ts"
    mkdir -p "$p/pkg/types" "$p/tests"
    printf '[project]\nname = "pkg"\n' > "$p/pyproject.toml"
    printf 'from pkg.types.sizes import ByteSize\n' > "$p/pkg/types/__init__.py"
    printf 'from pkg.types import ByteSize\n' > "$p/pkg/__init__.py"
    printf 'class ByteSize:\n    def human(self):\n        return "1B"\n' > "$p/pkg/types/sizes.py"
    printf 'from pkg.types.sizes import ByteSize\n\ndef test_human():\n    assert ByteSize().human() == "1B"\n' > "$p/tests/test_sizes.py"
    mkdir -p "$g/render"
    printf 'module example.com/web\n\ngo 1.22\n' > "$g/go.mod"
    printf 'package render\n\ntype TOML struct{}\n\nfunc (r TOML) Render() error { return nil }\n' > "$g/render/toml.go"
    printf 'package render\n\ntype JSON struct{}\n\nfunc (r JSON) Render() error { return nil }\n' > "$g/render/json.go"
    printf 'package web\n\nimport (\n\t"example.com/web/render"\n)\n\nfunc Serve() error { return render.TOML{}.Render() }\n' > "$g/engine.go"
    printf 'package web\n\nfunc Unrelated() int { return 1 }\n' > "$g/zzz_unrelated.go"
    mkdir -p "$m/Programs" "$m/Modules" "$m/Python" "$m/cmd"
    printf 'all:\n\tcc -o app Programs/app.c Modules/main.c Python/lifecycle.c\n' > "$m/Makefile"
    printf 'int app_main( int argc );\nint main( int argc, char** argv )\n{\n    return app_main( argc );\n}\n' > "$m/Programs/app.c"
    printf 'int lifecycle_init( int n );\nstatic int run( int n )\n{\n    return lifecycle_init( n );\n}\nint app_main( int argc )\n{\n    return run( argc );\n}\n' > "$m/Modules/main.c"
    printf 'int lifecycle_init( int n )\n{\n    return n;\n}\n' > "$m/Python/lifecycle.c"
}
mk_r2
qbrief() { ( cd "$1" && env "${@:3}" "$BIN" . --no-cache --brief-bytes=8192 "--brief=$2" 2>/dev/null ); }
TS_TASK="add a new pipe (like ParseIntPipe) exported from the package"
qbrief "$TMP/r2ts" "$TS_TASK" > "$TMP/q1.out"
qbrief "$TMP/r2ts" "$TS_TASK" RIPWIRE_BRIEF_SURFACE=0 > "$TMP/q1s.out"
qbrief "$TMP/r2ts" "$TS_TASK" RIPWIRE_BRIEF_SUBJECTTESTS=0 > "$TMP/q1t.out"
qbrief "$TMP/r2py" "add a new type (like ByteSize) exported from pkg" > "$TMP/q2.out"
qbrief "$TMP/r2go" "add a new render format (like TOML)" > "$TMP/q3.out"
qbrief "$TMP/r2main" "change how the app starts up (lifecycle_init)" > "$TMP/q4.out"
qbrief "$TMP/r2main" "change how the app starts up (lifecycle_init)" RIPWIRE_BRIEF_HANDOFF=0 > "$TMP/q4h.out"
nq=0
en="$( sect "$TMP/q1.out" entry )"
case "$en" in "surface: packages/common/pipes/index.ts · packages/common/index.ts"*) nq=$(( nq + 1 )) ;; *) no "(Q) TS barrel + package index are not the surface: $en" ;; esac
sect "$TMP/q1s.out" entry | grep -q 'surface:' && no "(Q) RIPWIRE_BRIEF_SURFACE=0 kept the surface" || nq=$(( nq + 1 ))
we="$( sect "$TMP/q1.out" where-else )"
case "$we" in *"test packages/common/test/pipes/parse-int-a.spec.ts"*"test packages/common/test/pipes/"*) nq=$(( nq + 1 )) ;; *) no "(Q) the exemplar's spec files and the tests' dir do not lead where-else: $we" ;; esac
sect "$TMP/q1.out" build | grep -qF 'helpers packages/common/test/helpers/args.ts' && nq=$(( nq + 1 )) || no "(Q) the same-tree helper the tests import is not test support: $( sect "$TMP/q1.out" build )"
case "$( sect "$TMP/q1t.out" where-else )" in *"parse-int-a.spec.ts"*"parse-int-b.spec.ts"*"packages/common/test/pipes/"*) no "(Q) RIPWIRE_BRIEF_SUBJECTTESTS=0 kept the subject tests: $( sect "$TMP/q1t.out" where-else )" ;; *) nq=$(( nq + 1 )) ;; esac
sect "$TMP/q2.out" entry | grep -qF 'surface: pkg/types/__init__.py · pkg/__init__.py' && nq=$(( nq + 1 )) || no "(Q) the Python package roots are not the surface: $( sect "$TMP/q2.out" entry )"
en3="$( sect "$TMP/q3.out" entry )"
case "$en3" in *"surface: engine.go"*) nq=$(( nq + 1 )) ;; *) no "(Q) the Go root file importing render/ is not the surface: $en3" ;; esac
case "$en3" in *zzz_unrelated.go*) no "(Q) a Go root file that does not import render/ reached the surface: $en3" ;; *) nq=$(( nq + 1 )) ;; esac
sect "$TMP/q4.out" entry | grep -qE 'Programs/app.c:2 main( hops=[0-9]+)? -> Modules/main.c -> Python/lifecycle.c' && nq=$(( nq + 1 )) || no "(Q) the trampoline main does not chain through Modules/main.c: $( sect "$TMP/q4.out" entry )"
sect "$TMP/q4h.out" entry | grep -qF 'Python/lifecycle.c' && no "(Q) RIPWIRE_BRIEF_HANDOFF=0 kept the chain: $( sect "$TMP/q4h.out" entry )" || nq=$(( nq + 1 ))
# attrs before any path cut: at a budget that needs the attrs step, entry rows lose :line/kind/hops but no row
( cd "$TMP/r2main" && "$BIN" . --no-cache --brief-bytes=1024 "--brief=change how the app starts up (lifecycle_init)" 2>/dev/null ) > "$TMP/q5.out"
dq=$( attr dropped < "$TMP/q5.out" )
case ",$dq," in *,attrs,*) case "$( sect "$TMP/q5.out" entry )" in *"Programs/app.c -> Modules/main.c"*) nq=$(( nq + 1 )) ;; *) no "(Q) attrs did not shed the entry's line/kind: $( sect "$TMP/q5.out" entry )" ;; esac ;; *) no "(Q) premise: 1024 B did not reach the attrs step (dropped=\"$dq\")" ;; esac
if [ "$nq" = 11 ]; then ok "(Q) round 2: TS barrel + index and Python roots as surface, Go importer named and a non-importer not, subject tests + dir + same-tree helper, trampoline chain, attrs shed first, three OFF switches (11 of 11)"; else no "(Q) round 2 $nq of 11"; fi

# ─── (R) round 3: --for's ranked files the rest does not name, and a "like X: path" exemplar (BRIEF-R3) ─────────────────
mk_r3() {
    local p="$TMP/r3py"
    mkdir -p "$p/enc" "$p/tests"
    printf '[project]\nname = "enc"\n' > "$p/pyproject.toml"
    printf 'class Codec:\n    def encode(self, s):\n        raise NotImplementedError\n' > "$p/enc/base.py"
    for n in alpha beta gamma delta epsilon zeta eta theta iota kappa; do
        printf 'from enc.base import Codec\nfrom enc.registry import register\n\n@register\nclass %sCodec(Codec):\n    def encode(self, s):\n        return s\n' "$n" > "$p/enc/$n.py"
    done
    printf 'REGISTRY = []\n\ndef register(cls):\n    REGISTRY.append(cls)\n    return cls\n' > "$p/enc/registry.py"
    printf 'from enc.alpha import alphaCodec\n\ndef test_alpha():\n    assert alphaCodec().encode("x") == "x"\n' > "$p/tests/test_alpha.py"
}
mk_r3
R3_TASK="add one more (like alphaCodec: enc/alpha.py)"   # words no sibling holds, so the question sites do not already list the family
qbrief "$TMP/r3py" "$R3_TASK" > "$TMP/r1.out"
qbrief "$TMP/r3py" "$R3_TASK" RIPWIRE_BRIEF_RANKED=0 > "$TMP/r1r.out"
nr=0
sect "$TMP/r1.out" like | grep -qx 'enc/alpha.py' && nr=$(( nr + 1 )) || no "(R) the \"like X: path\" exemplar is not that path: $( grep -o '<like[^/]*/like>' "$TMP/r1.out" )"
rk="$( sect "$TMP/r1.out" ranked )"
[ -n "$rk" ] && nr=$(( nr + 1 )) || no "(R) premise: no <ranked> slot on a family of 10 sibling codecs"
python3 - "$TMP/r1.out" "$TMP/r3py" <<'PY' && nr=$(( nr + 1 )) || no "(R) a ranked path is not an indexed file, or another slot already names it"
import os, re, sys
t = open(sys.argv[1]).read(); m = re.search(r"<ranked>(.*?)</ranked>", t)
paths = m.group(1).split(" · ") if m else []
rest = t[:m.start()] + t[m.end():] if m else t
ok = paths and all(os.path.isfile(os.path.join(sys.argv[2], p)) and p not in rest for p in paths)
sys.exit(0 if ok else 1)
PY
grep -q '<ranked>' "$TMP/r1r.out" && no "(R) RIPWIRE_BRIEF_RANKED=0 kept <ranked>" || nr=$(( nr + 1 ))
if [ "$nr" = 4 ]; then ok "(R) round 3: like X: path is the exemplar, ranked files are indexed and named nowhere else, OFF switch (4 of 4)"; else no "(R) round 3 $nr of 4"; fi

[ "$fail" = 0 ] && echo "briefcheck: PASS" || echo "briefcheck: FAIL"
exit "$fail"
