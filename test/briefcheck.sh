#!/usr/bin/env bash
# test/briefcheck.sh — the `--brief="TASK"` subagent brief (lane BRIEF-VERB): budget per size class, quoted-never-guessed
# build commands, (skip) dirs, the drop order, determinism, refusals, and the MCP `brief` twin.
#
# WHY. --brief is pasted into a fresh subagent's prompt, so every byte is paid once per lane and a wrong line is acted on.
# The two promises a reader cannot check by eye are the ones gated here: the page stays under its size class's cap
# (2.5 / 4 / 6 KB by indexed files < 1K / < 10K / more; --brief-bytes overrides, 512..8192), and a build/test command is
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
#   (O)  drop order: under --brief-bytes=512 dropped= is a prefix of conventions,layout_depth,entry,edges,where_else,qs in
#        that order, the act and build sections are still there, and over="1" is set exactly when the fixed sections
#        alone outgrow the budget.
#   (D)  determinism: two runs are byte-identical; every page is well-formed XML (xmllint when present, else python).
#   (R)  refusals: --brief with --for, --brief-bytes without --brief, --brief-bytes=100 each exit non-zero with no brief;
#        an unwritable TMPDIR (no buffer for the --for page) exits non-zero with stdout EMPTY, no leaked --for page.
#   (C)  MCP: tools/list advertises `brief`; a call answers a <brief> root; bytes=100 is refused.
#   (L)  the shared --brief= row: beside --plan-lanes, --brief=FILE is still the lane file (a lane plan with one lane per
#        line, no <brief> root); the subagent brief takes --brief= only without --plan-lanes.
# usage: test/briefcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-$ROOT/build/ripwire}"
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
brief() { ( cd "$1" && "$BIN" . --no-cache "--brief=$TASK" "${@:2}" 2>/dev/null ); }
attr() { python3 -c 'import re,sys; t=sys.stdin.read(); m=re.search(r"<brief [^>]*\b"+sys.argv[1]+r"=\"([^\"]*)\"", t); print(m.group(1) if m else "")' "$1"; }

classOf() { case "$1" in medium) echo medium ;; large) echo large ;; *) echo small ;; esac; }
capOf() { case "$1" in medium) echo 4096 ;; large) echo 6144 ;; *) echo 2560 ;; esac; }
pageLen() { python3 -c 'import sys; print(len(open(sys.argv[1], "rb").read().rstrip(b"\n")))' "$1"; }
built=0
for f in cmake python node bare medium large; do
    brief "$TMP/$f" > "$TMP/$f.out"
    grep -q '^<brief ' "$TMP/$f.out" && built=$(( built + 1 ))
done
[ "$built" = 6 ] && ok "(P) six fixtures answer a <brief> root" || no "(P) only $built of 6 fixtures answered a <brief> root"

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
[ "$nb" = 6 ] && ok "(B) all 6 fixtures: size_class, class cap as budget=, bytes= = page length <= budget" || no "(B) $nb of 6 fixtures held the class budget"
brief "$TMP/large" --brief-bytes=2048 > "$TMP/l2048.out"
len=$( pageLen "$TMP/l2048.out" )
[ "$( attr budget < "$TMP/l2048.out" )" = 2048 ] && [ "$len" -le 2048 ] && [ "$len" -gt 0 ] \
    && ok "(B) --brief-bytes=2048 holds a large page to $len <= 2048" || no "(B) --brief-bytes=2048: budget=$( attr budget < "$TMP/l2048.out" ) page=$len"

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
[ "$heads" = 0 ] && ok "(M) the bare fixture's build names no command head (7 checked)" || no "(M) a GUESSED command in the bare fixture's build: $bb"

# ─── (S) skip marks ────────────────────────────────────────────────────────────────────────────────────────────────
lay=$( grep -o '<layout>[^<]*</layout>' "$TMP/cmake.out" )
ns=0
for d in "third_party/ vendored(skip)" "vendor/ vendored(skip)" "build/ generated(skip)"; do printf '%s' "$lay" | grep -qF "$d" && ns=$(( ns + 1 )); done
[ "$ns" = 3 ] && ok "(S) third_party/, vendor/ and build/ marked (skip)" || no "(S) $ns of 3 skip marks: $lay"
printf '%s' "$lay" | grep -q 'src/ [a-z]*(skip)' && no "(S) src/ marked skip: $lay" || ok "(S) src/ is not marked skip"
grep -o '<layout>[^<]*</layout>' "$TMP/node.out" | grep -qF 'node_modules/ vendored(skip)' \
    && ok "(S) node_modules/ marked vendored(skip)" || no "(S) node_modules/ not marked: $( grep -o '<layout>[^<]*</layout>' "$TMP/node.out" )"

# ─── (O) drop order ────────────────────────────────────────────────────────────────────────────────────────────────
brief "$TMP/cmake" --brief-bytes=512 > "$TMP/o.out"
dr=$( attr dropped < "$TMP/o.out" )
python3 - "$dr" <<'PY' > "$TMP/o.probe"
import sys
order = "conventions,layout_depth,entry,edges,where_else,qs".split(",")
got = [x for x in sys.argv[1].split(",") if x]
print("OK" if got and got == order[:len(got)] else "BAD")
PY
[ "$( cat "$TMP/o.probe" )" = OK ] && ok "(O) --brief-bytes=512 dropped=\"$dr\" is a prefix of the drop order" || no "(O) dropped=\"$dr\" breaks the order"
grep -q '<act read="' "$TMP/o.out" && grep -q '<build>' "$TMP/o.out" && ok "(O) act and build survive the 512-byte cut" || no "(O) act or build dropped at 512 B"
# the fixed sections (root, legend, act, build, the three-moment block) can outgrow a tiny budget: that is disclosed, never hidden
olen=$( pageLen "$TMP/o.out" ); over=$( attr over < "$TMP/o.out" )
if { [ "$olen" -gt 512 ] && [ "$over" = 1 ]; } || { [ "$olen" -le 512 ] && [ -z "$over" ]; }; then ok "(O) over=\"$over\" matches the 512-byte page's $olen B"
else no "(O) page $olen B vs budget 512 but over=\"$over\""; fi

# ─── (D) determinism + well-formedness ─────────────────────────────────────────────────────────────────────────────
brief "$TMP/cmake" > "$TMP/cmake.2"; brief "$TMP/large" > "$TMP/large.2"
cmp -s "$TMP/cmake.out" "$TMP/cmake.2" && cmp -s "$TMP/large.out" "$TMP/large.2" && ok "(D) two runs byte-identical (small + large)" || no "(D) two runs differ"
nw=0
for f in cmake python node bare medium large; do
    if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$TMP/$f.out" 2>/dev/null && nw=$(( nw + 1 ))
    else python3 -c 'import sys,xml.dom.minidom as m; m.parse(sys.argv[1])' "$TMP/$f.out" 2>/dev/null && nw=$(( nw + 1 )); fi
done
[ "$nw" = 6 ] && ok "(D) all 6 pages well-formed XML" || no "(D) $nw of 6 pages well-formed"

# ─── (R) refusals ──────────────────────────────────────────────────────────────────────────────────────────────────
nr=0
for args in "--brief=x --for=y" "--brief-bytes=2048" "--brief=x --brief-bytes=100"; do
    # shellcheck disable=SC2086
    out=$( cd "$TMP/bare" && "$BIN" . $args 2>/dev/null ); rc=$?
    [ "$rc" != 0 ] && ! printf '%s' "$out" | grep -q '<brief' && nr=$(( nr + 1 )) || no "(R) '$args' rc=$rc"
done
[ "$nr" = 3 ] && ok "(R) 3 misuse forms refused, no brief printed" || no "(R) $nr of 3 misuse forms refused"
# an unwritable TMPDIR leaves no buffer for the --for page: refused before --for runs, so stdout stays EMPTY (no leaked --for page)
out=$( cd "$TMP/cmake" && TMPDIR="$TMP/no-such-dir" "$BIN" . --no-cache --brief="add a retry" 2>/dev/null ); rc=$?
[ "$rc" != 0 ] && [ -z "$out" ] && ok "(R) no temp buffer: refused, stdout empty" || no "(R) no temp buffer: rc=$rc, $( printf '%s' "$out" | wc -c | tr -d ' ' ) B on stdout"

# ─── (L) --plan-lanes --brief=FILE keeps its meaning ───────────────────────────────────────────────────────────────
printf 'add a retry to the client\nrename the parser entry\n' > "$TMP/lanes.txt"
lp=$( cd "$TMP/cmake" && "$BIN" . --plan-lanes --brief="$TMP/lanes.txt" 2>/dev/null ); rc=$?
nl=$( printf '%s' "$lp" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("lanes",[])))' 2>/dev/null || echo 0 )
[ "$rc" = 0 ] && [ "$nl" = 2 ] && ! printf '%s' "$lp" | grep -q '<brief' && ok "(L) --plan-lanes --brief=FILE answers a 2-lane plan, no <brief> root" \
    || no "(L) --plan-lanes --brief=FILE rc=$rc lanes=$nl"

# ─── (C) the MCP twin ──────────────────────────────────────────────────────────────────────────────────────────────
mcp_call() { printf '%s\n' "$@" | ( cd "$TMP/cmake" && "$BIN" --mcp 2>/dev/null ); }
LIST=$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )
printf '%s' "$LIST" | python3 -c 'import sys,json; print(int(any(t["name"]=="brief" for t in json.load(sys.stdin)["result"]["tools"])))' 2>/dev/null | grep -q 1 \
    && ok "(C) tools/list advertises brief" || no "(C) brief missing from tools/list"
call() {
    mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"brief\",\"arguments\":$1}}" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__" if "error" in r or r.get("result", {}).get("isError") else r["result"]["content"][0]["text"])'
}
call "{\"path\":\".\",\"task\":\"$TASK\"}" > "$TMP/c.out"
grep -q '^<brief ' "$TMP/c.out" && grep -q '<act read="' "$TMP/c.out" && ok "(C) tools/call brief answers a <brief> root with its act" || no "(C) MCP brief: $( head -c 200 "$TMP/c.out" )"
call "{\"path\":\".\",\"task\":\"$TASK\",\"bytes\":100}" | grep -q '__ERROR__' && ok "(C) bytes=100 refused" || no "(C) bytes=100 not refused"

[ "$fail" = 0 ] && echo "briefcheck: PASS" || echo "briefcheck: FAIL"
exit "$fail"
