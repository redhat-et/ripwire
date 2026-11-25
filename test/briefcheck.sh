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
#   (X)  round-2 detectors, one synthetic fixture each (autoconf-only C, a Go module, a Cargo workspace): the project's own
#        program leads the entries (named by AC_INIT, go.mod or the origin remote) ahead of a tool main, a bigger cmd and a
#        build script; the leading main names its delegate files, the most-called first; configure.ac without Makefile.am quotes `./configure &&
#        make` and the template makefile's targets; <r>registration: lists a registry dir, a metadata file and a build
#        config near the act; where-else lists the dir-named _test sibling, the testdata corpus and a task-word test file.
#   (A)  the exemplar anchor: "like the squash stage" resolved to ONE unit is disclosed as <like t=>FILE</like>, leads the edges
#        (its imports line first) and its dir's test mirror leads where-else; "like frob" with two definitions is disclosed as
#        ambiguous="2" with both candidates and changes none of the 6 other sections against the task without the phrase; a task
#        with no like-phrase draws no <like>.
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
brief "$TMP/large" --brief-bytes=2048 > "$TMP/l2048.out"
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
brief "$TMP/cmake" --brief-bytes=512 > "$TMP/o.out"
dr=$( attr dropped < "$TMP/o.out" )
python3 - "$dr" <<'PY' > "$TMP/o.probe"
import sys
order = "conventions,layout_depth,entry,edges,where_else,qs".split(",")
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
brief "$TMP/cmake" > "$TMP/cmake.2"; brief "$TMP/large" > "$TMP/large.2"
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
# an unwritable TMPDIR leaves no buffer for the --for page: refused before --for runs, so stdout stays EMPTY (no leaked --for page)
out=$( cd "$TMP/cmake" && TMPDIR="$TMP/no-such-dir" "$BIN" . --no-cache --brief="add a retry" 2>/dev/null ); rc=$?
if [ "$rc" != 0 ] && [ -z "$out" ]; then ok "(R) no temp buffer: refused, stdout empty"; else no "(R) no temp buffer: rc=$rc, $( printf '%s' "$out" | wc -c | tr -d ' ' ) B on stdout"; fi

# ─── (L) --plan-lanes --brief=FILE keeps its meaning ───────────────────────────────────────────────────────────────
printf 'add a retry to the client\nrename the parser entry\n' > "$TMP/lanes.txt"
lp=$( cd "$TMP/cmake" && "$BIN" . --plan-lanes --brief="$TMP/lanes.txt" 2>/dev/null ); rc=$?
nl=$( printf '%s' "$lp" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("lanes",[])))' 2>/dev/null || echo 0 )
if [ "$rc" = 0 ] && [ "$nl" = 2 ] && ! printf '%s' "$lp" | grep -q '<brief'; then ok "(L) --plan-lanes --brief=FILE answers a 2-lane plan, no <brief> root"; else no "(L) --plan-lanes --brief=FILE rc=$rc lanes=$nl"; fi

# ─── (C) the MCP twin ──────────────────────────────────────────────────────────────────────────────────────────────
mcp_call() { printf '%s\n' "$@" | ( cd "$TMP/cmake" && "$BIN" --mcp 2>/dev/null ); }
LIST=$( mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | tail -1 )
if printf '%s' "$LIST" | python3 -c 'import sys,json; print(int(any(t["name"]=="brief" for t in json.load(sys.stdin)["result"]["tools"])))' 2>/dev/null | grep -q 1; then ok "(C) tools/list advertises brief"; else no "(C) brief missing from tools/list"; fi
call() {
    mcp_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"brief\",\"arguments\":$1}}" | tail -1 | python3 -c '
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
xbrief() { local d="$1" t="$2"; ( cd "$TMP/$d" && "$BIN" . --no-cache --brief-bytes=8192 "--brief=$t" 2>/dev/null ); }
xbrief ac "add a new spin operation for widgets next to widget_frobnicate" > "$TMP/ac.out"
xbrief goreg "add a new widget variant next to HandleWidget" > "$TMP/goreg.out"
xbrief cargo "add a new spin mode to spin_loop" > "$TMP/cargo.out"
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
abrief() { ( cd "$TMP/stages" && "$BIN" . --no-cache --brief-bytes=8192 "--brief=$1" 2>/dev/null ); }
abrief "add a new stage (like the squash stage) to run_pipeline" > "$TMP/a1.out"
abrief "add a new helper like frob to run_pipeline" > "$TMP/a2.out"
abrief "add a new helper to run_pipeline" > "$TMP/a3.out"
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

[ "$fail" = 0 ] && echo "briefcheck: PASS" || echo "briefcheck: FAIL"
exit "$fail"
