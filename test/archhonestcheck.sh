#!/usr/bin/env bash
# archhonestcheck.sh — a module, file or repo whose language has no file edges in this index reads UNKNOWN, never zero.
#
# Go, Java, Kotlin, C#, PHP, Swift (imports captured, no sound string→file rule) and Dart, GDScript, Clojure (no import
# capture) draw no file→file edge, so --arch used to print Ca=Ce=0, I=0, D≈1 and zone="pain" for every typed module, purely
# from the missing data, and --deps afferent="0" instab="0.00", shape="horizontal". The fact is LangFacts::fileEdges
# (src/langfacts.h). Every fixture is built at runtime under mktemp. Arms:
#   (A) one fixture per no-edge language: unknown rows, no pain, no propagation_cost, root disclosure, well-formed XML
#   (B) mixed Go + Python: the Python modules keep their numbers byte for byte, the Go modules read unknown
#   (C) a C++ repo: nothing new appears, the legend does not ride
#   (D) NEAR MISS: a language WITH edges and a genuinely uncoupled typed module stays Ca=Ce=0 and keeps zone="pain"
#   (E) one directory with both kinds of file: edges observed keep the numbers plus the attribute; none observed reads unknown
#   (F) --deps: <f> rows and <health> over a no-edge language; twins with edges keep every number
#   (G) --report: never "none (acyclic)" over a no-edge language; a C++ tree still says it
#   (H) the fact matches the index: every Resolved language draws a real cross-directory edge, every Unmeasured one none
#   (I) the root's graph_partial= stays single when a TS unresolved import already set it (xmllint refuses a duplicate)
#   (J) every --arch exit path carries the root disclosure; the stderr floor line rides exactly when it fires
#   (K) a no-edge language that DOES have an observed edge (Go across roots through go.mod replace) keeps its numbers + attribute
#   (L) legends: compact defines the new attributes; the arch and deps comments carry the clause only when fired
#
# Usage: bash test/archhonestcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "archhonestcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
RULES="$TMP/rules.arch"
printf 'layer a = zzz_none_a\nlayer b = zzz_none_b\ndeny a -> b\n' > "$RULES"

# A premise that fails is a FAIL: an absent row must be read off a command that ran and produced its root.
arch(){ ( cd "$1" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$1" --arch="$RULES" --no-cache "${@:2}" 2>"$TMP/stderr" ); }
deps(){ ( cd "$1" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$1" --deps --no-cache "${@:2}" 2>/dev/null ); }
report(){ ( cd "$1" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$1" --report --no-cache 2>/dev/null ); }
row(){ printf '%s' "$1" | grep -o '<m [^>]*/>' | grep "path=\"$2\""; }
metrics(){ printf '%s' "$1" | grep -o '<metrics [^>]*>' | sed 's/ note=.*//'; }
root(){ printf '%s' "$1" | grep -o "<$2 [^>]*>" | head -1; }
command -v xmllint >/dev/null 2>&1 || { echo "archhonestcheck: SKIP (no xmllint: the duplicate-attribute arms need it)"; exit 0; }
put(){ mkdir -p "$( dirname "$1" )"; printf '%b' "$2" > "$1"; }

# a typed file per language, importing the other directory's file in that language's own spelling
mkfix(){ # lang dir
    local l="$1" d="$2"
    case "$l" in
    go)    put "$d/go.mod" 'module example.com/m\n\ngo 1.21\n'
           put "$d/a/a.go" 'package a\n\nimport "example.com/m/b"\n\ntype A struct{}\n\nfunc F() int { return b.G() }\n'
           put "$d/b/b.go" 'package b\n\ntype B struct{}\n\nfunc G() int { return 1 }\n' ;;
    java)  put "$d/a/A.java" 'package a;\n\nimport b.B;\n\npublic class A { int f() { return new B().g(); } }\n'
           put "$d/b/B.java" 'package b;\n\npublic class B { public int g() { return 1; } }\n' ;;
    kt)    put "$d/a/A.kt" 'package a\n\nimport b.B\n\nclass A { fun f(): Int = B().g() }\n'
           put "$d/b/B.kt" 'package b\n\nclass B { fun g(): Int = 1 }\n' ;;
    cs)    put "$d/a/A.cs" 'using B;\n\nnamespace A { public class CA { int F() { return new CB().G(); } } }\n'
           put "$d/b/B.cs" 'namespace B { public class CB { public int G() { return 1; } } }\n' ;;
    php)   put "$d/a/A.php" '<?php\nnamespace A;\nuse B\\CB;\nclass CA { function f() { return (new CB())->g(); } }\n'
           put "$d/b/B.php" '<?php\nnamespace B;\nclass CB { function g() { return 1; } }\n' ;;
    swift) put "$d/a/A.swift" 'import b\n\nclass CA { func f() -> Int { return CB().g() } }\n'
           put "$d/b/B.swift" 'class CB { func g() -> Int { return 1 } }\n' ;;
    dart)  put "$d/a/a.dart" "import '../b/b.dart';\n\nclass CA { int f() => CB().g(); }\n"
           put "$d/b/b.dart" 'class CB { int g() => 1; }\n' ;;
    gd)    put "$d/a/a.gd" 'class_name CA\nvar B = preload("res://b/b.gd")\nfunc f():\n\treturn B.new().g()\n'
           put "$d/b/b.gd" 'class_name CB\nfunc g():\n\treturn 1\n' ;;
    clj)   put "$d/a/a.clj" '(ns a (:require [b]))\n(defn f [] (b/g))\n'
           put "$d/b/b.clj" '(ns b)\n(defn g [] 1)\n' ;;
    py)    put "$d/a/a.py" 'from b.b import B\n\nclass A:\n    def f(self):\n        return B().g()\n'
           put "$d/b/b.py" 'class B:\n    def g(self):\n        return 1\n'
           put "$d/a/__init__.py" ''; put "$d/b/__init__.py" '' ;;
    ts)    put "$d/a/a.ts" "import { B } from '../b/b';\n\nexport class A { f() { return new B().g(); } }\n"
           put "$d/b/b.ts" 'export class B { g() { return 1; } }\n' ;;
    js)    put "$d/a/a.js" "import { B } from '../b/b.js';\n\nexport class A { f() { return new B().g(); } }\n"
           put "$d/b/b.js" 'export class B { g() { return 1; } }\n' ;;
    cpp)   put "$d/a/a.cpp" '#include "../b/b.h"\n\nstruct A { int f() { return B().g(); } };\n'
           put "$d/b/b.h" 'struct B { int g() { return 1; } };\n' ;;
    c)     put "$d/a/a.c" '#include "../b/b.h"\n\nint f( void ) { return g(); }\n'
           put "$d/b/b.h" 'int g( void );\n' ;;
    rs)    put "$d/src/main.rs" 'mod net;\n\nfn main() { net::conn::g(); }\n'
           put "$d/src/net/mod.rs" 'pub mod conn;\n'
           put "$d/src/net/conn.rs" 'pub fn g() {}\n' ;;
    sh)    put "$d/a/a.sh" '#!/bin/sh\n. ../b/b.sh\ng\n'
           put "$d/b/b.sh" '#!/bin/sh\ng() { :; }\n' ;;
    rb)    put "$d/a/a.rb" "require_relative '../b/b'\n\nclass A; def f; B.new.g; end; end\n"
           put "$d/b/b.rb" 'class B; def g; 1; end; end\n' ;;
    lua)   put "$d/a/a.lua" 'local b = require("b.b")\nreturn b.g()\n'
           put "$d/b/b.lua" 'local M = {}\nfunction M.g() return 1 end\nreturn M\n' ;;
    ex)    put "$d/a/a.ex" 'defmodule A do\n  alias B.Thing\n  def f, do: Thing.g()\nend\n'
           put "$d/b/b.ex" 'defmodule B.Thing do\n  def g, do: 1\nend\n' ;;
    *) no "mkfix: unknown language $l" ;;
    esac
}

NOEDGE="go java kt cs php swift dart gd clj"
EDGED="py ts js cpp c rs sh rb lua ex"

# ── (A) one fixture per no-edge language ──────────────────────────────────────────────────────────────────
for l in $NOEDGE; do
    d="$TMP/a_$l"; mkfix "$l" "$d"; f0=$fail; fail=0
    o="$( arch "$d" )"; rc=$?
    [ "$rc" = 0 ] && [ -n "$( root "$o" arch )" ] || { no "(A) $l: --arch rc=$rc or no <arch> root"; [ "$f0" = 0 ] || fail=1; continue; }
    m="$( metrics "$o" )"
    r="$( row "$o" '[^"]*/a' )"
    [ -n "$r" ] || { no "(A) $l: no <m> row for a/"; [ "$f0" = 0 ] || fail=1; continue; }
    printf '%s' "$r" | grep -q 'zone="unknown"' || no "(A) $l: a/ zone is not unknown: $r"
    printf '%s' "$r" | grep -q "no_file_edges=\"$l\"" || no "(A) $l: a/ does not name why: $r"
    printf '%s' "$r" | grep -qE ' (ca|ce|I|D|reachable|isolated|leaf)=' && no "(A) $l: a/ still states a coupling number: $r"
    printf '%s' "$m" | grep -q 'zone_pain="0" zone_useless="0" zone_ok="0"' || no "(A) $l: a zone tally survived: $m"
    printf '%s' "$m" | grep -qE 'zone_unknown="[1-9]' || no "(A) $l: no zone_unknown=: $m"
    printf '%s' "$m" | grep -q 'propagation_cost=' && no "(A) $l: propagation_cost printed over no edges: $m"
    root "$o" arch | grep -q "no_file_edges=\"$l\" unmeasured_files=\"[0-9]*\" graph_partial=\"1\"" || no "(A) $l: root disclosure missing: $( root "$o" arch )"
    printf '%s' "$o" | xmllint --noout - 2>/dev/null || no "(A) $l: not well-formed"
    [ "$fail" = 0 ] && ok "(A) $l: unknown, why named, no zone tally, no propagation_cost"
    [ "$f0" = 0 ] || fail=1
done
# the abstractness half does not depend on an edge: types=/abstract=/A= stay.
o="$( arch "$TMP/a_go" )"; r="$( row "$o" '[^"]*/a' )"
printf '%s' "$r" | grep -qE 'types="1" abstract="0" A="0\.00"' && ok "(A) types=/abstract=/A= stay (no edge behind them)" || no "(A) types half lost: $r"
m="$( metrics "$o" )"
printf '%s' "$m" | grep -q 'typed_modules="2"' && ok "(A) typed_modules= still counts modules with types" || no "(A) typed_modules wrong: $m"
n="$( printf '%s' "$o" | grep -o '<metrics [^>]*note="[^"]*"' )"
printf '%s' "$n" | grep -q 'zone_unknown' && ok "(A) note= defines zone_unknown in the partition" || no "(A) note= silent on zone_unknown"

# ── (B) mixed Go + Python ─────────────────────────────────────────────────────────────────────────────────
d="$TMP/b_py"; mkfix py "$d"; pyonly="$( arch "$d" )"
d="$TMP/b_mix"; mkfix py "$d"; mkfix go "$d/gomod"
o="$( arch "$d" )"
sq(){ sed -E 's#path="[^"]*/(a|b)"#path="\1"#' ; }
ra="$( row "$o" "$d/a" | sq )"; rb="$( row "$o" "$d/b" | sq )"
pa="$( row "$pyonly" "$TMP/b_py/a" | sq )"; pb="$( row "$pyonly" "$TMP/b_py/b" | sq )"
[ -n "$ra" ] && [ "$ra" = "$pa" ] && [ "$rb" = "$pb" ] && ok "(B) Python rows byte-identical to a Python-only tree" || no "(B) Python row moved: [$ra] vs [$pa], [$rb] vs [$pb]"
printf '%s' "$ra" | grep -q 'ce="1"' && ok "(B) Python module a/ keeps Ce=1" || no "(B) Python a/ lost its edge: $ra"
rg="$( row "$o" "$d/gomod/a" )"
printf '%s' "$rg" | grep -q 'zone="unknown"' && printf '%s' "$rg" | grep -q 'no_file_edges="go"' && ok "(B) Go module unknown in the same tree" || no "(B) Go module: $rg"
m="$( metrics "$o" )"
printf '%s' "$m" | grep -q 'propagation_cost=' && ok "(B) propagation_cost stays where edges exist" || no "(B) propagation_cost lost: $m"
root "$o" arch | grep -q 'no_file_edges="go" unmeasured_files="2" graph_partial="1"' && ok "(B) root: no_file_edges= names Go, 2 files" || no "(B) root: $( root "$o" arch )"
printf '%s' "$o" | xmllint --noout - 2>/dev/null || no "(B) not well-formed"

# ── (C) a C++ repo: nothing new ───────────────────────────────────────────────────────────────────────────
d="$TMP/c_cpp"; mkfix cpp "$d"; o="$( arch "$d" )"; dd="$( deps "$d" )"
[ -n "$( root "$o" arch )" ] || no "(C) no <arch> root"
printf '%s%s' "$o" "$dd" | grep -qE 'no_file_edges|unmeasured_files|zone_unknown|zone="unknown"' && no "(C) a C++ tree carries the new vocabulary" || ok "(C) C++ tree: no new attribute, no legend clause"
printf '%s' "$( row "$o" "$d/a" )" | grep -q ' ca="0" ce="1" ' && ok "(C) C++ numbers stand" || no "(C) C++ row: $( row "$o" "$d/a" )"

# ── (D) NEAR MISS: a language with edges and a genuinely uncoupled typed module ───────────────────────────
d="$TMP/d_near"; mkfix py "$d"; put "$d/lone/lone.py" 'class Lone:\n    def z(self):\n        return 1\n'
o="$( arch "$d" )"; r="$( row "$o" "$d/lone" )"
printf '%s' "$r" | grep -q ' ca="0" ce="0" types="1"' && printf '%s' "$r" | grep -q 'zone="pain"' && printf '%s' "$r" | grep -q 'isolated="1"' \
    && ok "(D) uncoupled Python module stays Ca=Ce=0, zone=pain, isolated=1" || no "(D) near miss moved: $r"
printf '%s' "$r" | grep -q 'no_file_edges' && no "(D) near miss carries no_file_edges: $r"

# ── (E) one directory holding both kinds of file ─────────────────────────────────────────────────────────
d="$TMP/e_dir"; mkfix py "$d"; put "$d/a/stray.go" 'package a\n\ntype S struct{}\n'
put "$d/lone2/lone.py" 'class L2:\n    pass\n'; put "$d/lone2/x.go" 'package lone2\n\ntype X struct{}\n'
put "$d/shgo/run.sh" '#!/bin/sh\necho hi\n'; put "$d/shgo/main.go" 'package main\n\ntype Y struct{}\n\nfunc main() {}\n'
o="$( arch "$d" )"
r="$( row "$o" "$d/a" )"
printf '%s' "$r" | grep -q ' ce="1" ' && printf '%s' "$r" | grep -q 'no_file_edges="go"' && ok "(E) edges observed: numbers stay, no_file_edges= says they cover part of the module" || no "(E) mixed dir with edges: $r"
for sub in lone2 shgo; do
    r="$( row "$o" "$d/$sub" )"
    printf '%s' "$r" | grep -q 'zone="unknown"' && ! printf '%s' "$r" | grep -q ' ca=' && ok "(E) $sub: no edge observed with a no-edge file in it: unknown" || no "(E) $sub: $r"
done

# ── (F) --deps ───────────────────────────────────────────────────────────────────────────────────────────
dd="$( deps "$TMP/a_go" )"
f="$( printf '%s' "$dd" | sed 's/<!--.*-->//' | grep -o '<f p="a/a.go[^>]*>' )"
[ -n "$f" ] || no "(F) no <f> row for a/a.go"
printf '%s' "$f" | grep -qE 'afferent=|instab=|transitive=' && no "(F) Go row still states a number: $f"
printf '%s' "$f" | grep -q 'no_file_edges="go"' && printf '%s' "$f" | grep -q 'includes="1"' && ok "(F) Go <f>: includes= stays, afferent/instab/transitive unknown" || no "(F) Go row: $f"
h="$( printf '%s' "$dd" | grep -o '<health [^>]*>' )"
printf '%s' "$h" | grep -qE ' (ccd|acd|nccd|shape)=' && no "(F) Go <health> states a verdict: $h" || ok "(F) Go <health>: no ccd/acd/nccd/shape"
printf '%s' "$h" | grep -q 'files="[0-9]*" dep_files="[0-9]*"' && printf '%s' "$h" | grep -q 'dep_langs=' || no "(F) <health> lost its denominators: $h"
root "$dd" deps | grep -q 'no_file_edges="go" unmeasured_files="2" graph_partial="1"' && ok "(F) Go <deps> root discloses" || no "(F) <deps> root: $( root "$dd" deps )"
printf '%s' "$dd" | xmllint --noout - 2>/dev/null || no "(F) Go deps not well-formed"
dd="$( deps "$TMP/b_mix" )"
printf '%s' "$dd" | sed 's/<!--.*-->//' | grep -o '<f p="a/a.py[^>]*>' | grep -q 'afferent="0" instab="1.00" transitive="2"' && ok "(F) mixed: Python <f> keeps its numbers" || no "(F) mixed Python row: $( printf '%s' "$dd" | grep -o '<f p="a/a.py[^>]*>' )"
printf '%s' "$dd" | grep -o '<f p="gomod/a/a.go[^>]*>' | grep -q 'afferent=' && no "(F) mixed Go row states a number"
printf '%s' "$dd" | grep -o '<health [^>]*>' | grep -q ' shape=' && ok "(F) mixed: <health> keeps its verdict over the resolved edges" || no "(F) mixed health lost shape"

# ── (G) --report ─────────────────────────────────────────────────────────────────────────────────────────
ro="$( report "$TMP/a_go" )"
printf '%s' "$ro" | grep -q '## Dependency cycles' || no "(G) no cycles section in the Go report"
printf '%s' "$ro" | grep -q 'none (acyclic)' && no "(G) a Go tree reads acyclic" || ok "(G) Go report does not say acyclic"
printf '%s' "$ro" | grep -q 'have no file edges' && printf '%s' "$ro" | grep -q 'none found over the resolved edges' && ok "(G) Go report names the gap" || no "(G) Go report: $( printf '%s' "$ro" | grep -A1 'Dependency cycles' )"
ro="$( report "$TMP/c_cpp" )"
printf '%s' "$ro" | grep -q 'none (acyclic)' && ! printf '%s' "$ro" | grep -q 'no file edges' && ok "(G) C++ report unchanged" || no "(G) C++ report moved"

# ── (H) the fact matches the index ───────────────────────────────────────────────────────────────────────
for l in $EDGED; do
    d="$TMP/h_$l"; mkfix "$l" "$d"; dd="$( deps "$d" )"
    printf '%s' "$dd" | sed 's/<!--.*-->//' | grep -qE 'afferent="[1-9]' && ! printf '%s' "$dd" | grep -q 'no_file_edges' \
        && ok "(H) $l: fileEdges=Resolved draws a real edge" || no "(H) $l: Resolved in the facts but no edge: $( printf '%s' "$dd" | sed 's/<!--.*-->//' | cut -c1-300 )"
done
for l in $NOEDGE; do
    dd="$( deps "$TMP/a_$l" )"
    [ -n "$( root "$dd" deps )" ] || { no "(H) $l: no <deps> root"; continue; }
    printf '%s' "$dd" | sed 's/<!--.*-->//' | grep -qE 'afferent="[1-9]' && no "(H) $l: Unmeasured in the facts but the index drew an edge: move its row" || ok "(H) $l: fileEdges=Unmeasured, and no edge"
done

# ── (I) graph_partial stays single beside a TS unresolved import ─────────────────────────────────────────
d="$TMP/i_ts"; mkfix go "$d"
put "$d/tsconfig.json" '{"compilerOptions":{"baseUrl":".","paths":{"@/*":["web/*"]}}}\n'
put "$d/web/x.ts" "import { nope } from '@/missing';\nexport const y = nope;\n"
o="$( arch "$d" )"; dd="$( deps "$d" )"
for pair in "arch:$o" "deps:$dd"; do
    n="${pair%%:*}"; v="${pair#*:}"
    root "$v" "$n" | grep -q 'imports_unresolved=' || no "(I) $n: premise: no imports_unresolved= ($( root "$v" "$n" ))"
    c="$( root "$v" "$n" | grep -o 'graph_partial=' | wc -l | tr -d ' ' )"
    [ "$c" = 1 ] && printf '%s' "$v" | xmllint --noout - 2>/dev/null && ok "(I) $n: one graph_partial=, well-formed" || no "(I) $n: graph_partial x$c: $( root "$v" "$n" )"
done

# ── (J) every --arch exit path; the stderr floor line ────────────────────────────────────────────────────
d="$TMP/j_go"; mkfix go "$d"
o="$( arch "$d" )"
grep -q 'have no file edges' "$TMP/stderr" && grep -q 'violations= is a floor' "$TMP/stderr" && ok "(J) stderr: violations= is a floor" || no "(J) no stderr floor line: $( cat "$TMP/stderr" )"
cp "$RULES" "$TMP/j.arch"
for mode in --baseline --baseline-update; do
    o="$( cd "$d" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$d" --arch="$TMP/j.arch" "$mode" --no-cache 2>/dev/null )"
    root "$o" arch | grep -q 'no_file_edges="go"' && printf '%s' "$o" | grep -q 'zone="unknown"' && ok "(J) $mode carries it" || no "(J) $mode: $( root "$o" arch )"
done
o="$( cd "$d" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$d" --arch="$TMP/j.arch" --no-cache 2>/dev/null )"
root "$o" arch | grep -q 'no_file_edges="go"' && ok "(J) a baselined run carries it" || no "(J) baselined: $( root "$o" arch )"
arch "$TMP/c_cpp" >/dev/null; grep -q 'no file edges' "$TMP/stderr" && no "(J) C++ stderr has the line" || ok "(J) C++ stderr: no line"

# ── (K) an observed edge in a no-edge language keeps its numbers ─────────────────────────────────────────
d="$TMP/k"; mkdir -p "$d"
put "$d/app/go.mod" 'module example.com/app\n\ngo 1.21\n\nrequire example.com/lib v0.0.0\n\nreplace example.com/lib => ../lib\n'
put "$d/app/main.go" 'package main\n\nimport "example.com/lib"\n\ntype T struct{}\n\nfunc main() { lib.G() }\n'
put "$d/lib/go.mod" 'module example.com/lib\n\ngo 1.21\n'
put "$d/lib/lib.go" 'package lib\n\ntype L struct{}\n\nfunc G() {}\n'
o="$( cd "$d" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$d/app" "$d/lib" --arch="$RULES" --no-cache 2>/dev/null )"
r="$( row "$o" '[^"]*app' )"
if printf '%s' "$r" | grep -q ' ce="1" '; then
    printf '%s' "$r" | grep -q 'no_file_edges="go"' && ok "(K) Go across roots: observed edge keeps its numbers, attribute says the rest is unseen" || no "(K) $r"
    printf '%s' "$o" | grep -o '<metrics [^>]*>' | grep -q 'propagation_cost=' && ok "(K) propagation_cost stays once an edge exists" || no "(K) propagation_cost lost"
else
    no "(K) premise: go.mod replace drew no edge across roots: [$r]"
fi

# ── (L) legends ──────────────────────────────────────────────────────────────────────────────────────────
o="$( arch "$TMP/a_go" --legend=full )"; lg="$( printf '%s' "$o" | grep -o '<!--.*-->' | head -1 )"
printf '%s' "$lg" | grep -q 'no_file_edges=' && ok "(L) arch full legend defines it when fired" || no "(L) arch full legend silent"
o="$( arch "$TMP/c_cpp" --legend=full )"; printf '%s' "$o" | grep -q 'no_file_edges' && no "(L) arch legend rides without the attribute" || ok "(L) arch legend present-only"
dd="$( deps "$TMP/a_go" --legend=full )"; printf '%s' "$dd" | grep -o '<!--.*-->' | grep -q 'no_file_edges=' && ok "(L) deps full legend defines it when fired" || no "(L) deps full legend silent"
printf '%s' "$dd" | xmllint --noout - 2>/dev/null && ok "(L) the clause holds no double hyphen (well-formed comment)" || no "(L) deps legend not well-formed"
for v in arch deps; do
    if [ "$v" = arch ]; then c="$( arch "$TMP/a_go" --legend=compact )"; else c="$( deps "$TMP/a_go" --legend=compact )"; fi
    lc="$( printf '%s' "$c" | grep -o '<!--.*-->' | head -1 )"
    printf '%s' "$lc" | grep -q 'no_file_edges=' && printf '%s' "$lc" | grep -q 'unmeasured_files=' && ok "(L) $v compact legend defines both" || no "(L) $v compact legend: $( printf '%s' "$lc" | cut -c1-300 )"
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
