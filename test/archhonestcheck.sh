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
#   (M) fix round 1, C2: a no-edge file with no observed edge is out of BOTH system denominators (dep_files=, propagation_cost), counted in masked_files=
#   (N) fix round 1, C3: --cochange, --impact (CLI, json, columnar, MCP) and --export=cc.json do not print a measured-looking zero for a no-edge file
#   (Q) fix round 2: F1 a zero-edge tree with one edgeless measured file has no verdict; F2 --cochange-groups says no_file_edges + unknown_pairs; F3 a touched no-edge file is masked too; m15 --impact full legend present-only
#   (P) fix round 1, C4: a module with an observed edge AND a no-edge file keeps ca/ce as floors and drops the verdict; the wording is true on go.mod replace
#
# Usage: bash test/archhonestcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "archhonestcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
# Well-formedness (a duplicate attribute, a double hyphen in a comment) is read by xmllint when it exists and by expat (python3) when it does
# not: both refuse the same documents, so a host without xmllint loses no arm. CR 5725024918: the gate used to exit 0 here before any arm,
# and test/regression.sh records that as a PASS.
if command -v xmllint >/dev/null 2>&1; then
    wf(){ xmllint --noout - 2>/dev/null; }
elif command -v python3 >/dev/null 2>&1; then
    echo "archhonestcheck: no xmllint, well-formedness is read by python3 expat"
    wf(){ python3 -I -c 'import sys,xml.etree.ElementTree as E; E.fromstring(sys.stdin.buffer.read())' 2>/dev/null; }
else
    echo "archhonestcheck: no xmllint and no python3: the well-formedness arms SKIP, every other arm runs"
    wf(){ return 0; }
fi
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
    objc)  put "$d/a/a.m" '#import "../b/b.h"\n\n@implementation A\n- (int)f { return 1; }\n@end\n'
           put "$d/b/b.h" '@interface B\n@end\n' ;;
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
EDGED="py ts js cpp c rs sh rb lua ex objc"

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
    printf '%s' "$o" | wf || no "(A) $l: not well-formed"
    [ "$fail" = 0 ] && ok "(A) $l: unknown, why named, no zone tally, no propagation_cost"
    [ "$f0" = 0 ] || fail=1
done
# the abstractness half does not depend on an edge: types=/abstract=/A= stay.
o="$( arch "$TMP/a_go" )"; r="$( row "$o" '[^"]*/a' )"
if printf '%s' "$r" | grep -qE 'types="1" abstract="0" A="0\.00"'; then ok "(A) types=/abstract=/A= stay (no edge behind them)"; else no "(A) types half lost: $r"; fi
m="$( metrics "$o" )"
if printf '%s' "$m" | grep -q 'typed_modules="2"'; then ok "(A) typed_modules= still counts modules with types"; else no "(A) typed_modules wrong: $m"; fi
n="$( printf '%s' "$o" | grep -o '<metrics [^>]*note="[^"]*"' )"
if printf '%s' "$n" | grep -q 'zone_unknown'; then ok "(A) note= defines zone_unknown in the partition"; else no "(A) note= silent on zone_unknown"; fi
# CR 5725024918 (thread 4433389591): the printed sum names every term of the partition when zone_unknown= rides
if printf '%s' "$n" | grep -q 'zone_pain+zone_useless+zone_ok+zone_na+zone_unknown = modules'; then ok "(A) note= states the partition sum with zone_unknown"; else no "(A) note= sum omits zone_unknown: $( printf '%s' "$n" | grep -o 'zone_pain+[^;]*' )"; fi

# a typeless Go module is unknown too, and typed_modules= counts types, not "not n/a"
d="$TMP/a_typeless"; mkfix go "$d"; put "$d/c/c.go" 'package c\n\nfunc H() {}\n'; put "$d/docs/x.md" '# doc\n'
o="$( arch "$d" )"; m="$( metrics "$o" )"
if printf '%s' "$m" | grep -q 'typed_modules="2"' && printf '%s' "$( row "$o" "$d/c" )" | grep -q 'zone="unknown"'; then ok "(A) typeless Go module unknown; typed_modules=2 of its modules"; else no "(A) typeless: $m / $( row "$o" "$d/c" )"; fi
# NotApplicable: a docs directory draws no edge by decision and keeps its row beside them
if printf '%s' "$( row "$o" "$d/docs" )" | grep -q ' ca="0" ce="0" types="0" .*zone="n/a"' && ! printf '%s' "$( row "$o" "$d/docs" )" | grep -q no_file_edges; then ok "(A) a docs directory keeps its row"; else no "(A) docs row: $( row "$o" "$d/docs" )"; fi
if python3 - "$ROOT/src/lintrules.h" "$ROOT/src/langfacts.h" <<'PY'; then ok "(A) fileEdges agrees with dependencyCapable: capable is never NotApplicable, not capable is never Resolved"; else no "(A) fileEdges contradicts dependencyCapable"; fi
import re,sys
lint=open(sys.argv[1]).read(); facts=open(sys.argv[2]).read()
body=lint[lint.index('inline bool dependencyCapable( Lang lang )'):]
head=body[:body.index('return true;')]; capable=set(re.findall(r'Lang::(\w+)',head))
table=facts[facts.index('kLangFacts = { {'):]
rows=re.findall(r'\{ \.lang = Lang::(\w+)(.*?) \},\n',table,re.S)
assert len(rows)==25 and len(capable)==17,(len(rows),len(capable))
for lang,rest in rows:
    m=re.search(r'\.fileEdges = FileEdges::(\w+)',rest); v=m[1] if m else 'Unmeasured'
    assert not (lang in capable and v=='NotApplicable'),lang
    assert not (lang not in capable and v=='Resolved'),lang
PY

# ── (B) mixed Go + Python ─────────────────────────────────────────────────────────────────────────────────
d="$TMP/b_py"; mkfix py "$d"; pyonly="$( arch "$d" )"
d="$TMP/b_mix"; mkfix py "$d"; mkfix go "$d/gomod"
o="$( arch "$d" )"
sq(){ sed -E 's#path="[^"]*/(a|b)"#path="\1"#' ; }
ra="$( row "$o" "$d/a" | sq )"; rb="$( row "$o" "$d/b" | sq )"
pa="$( row "$pyonly" "$TMP/b_py/a" | sq )"; pb="$( row "$pyonly" "$TMP/b_py/b" | sq )"
if [ -n "$ra" ] && [ "$ra" = "$pa" ] && [ "$rb" = "$pb" ]; then ok "(B) Python rows byte-identical to a Python-only tree"; else no "(B) Python row moved: [$ra] vs [$pa], [$rb] vs [$pb]"; fi
if printf '%s' "$ra" | grep -q 'ce="1"'; then ok "(B) Python module a/ keeps Ce=1"; else no "(B) Python a/ lost its edge: $ra"; fi
rg="$( row "$o" "$d/gomod/a" )"
if printf '%s' "$rg" | grep -q 'zone="unknown"' && printf '%s' "$rg" | grep -q 'no_file_edges="go"'; then ok "(B) Go module unknown in the same tree"; else no "(B) Go module: $rg"; fi
m="$( metrics "$o" )"
if printf '%s' "$m" | grep -q 'propagation_cost='; then ok "(B) propagation_cost stays where edges exist"; else no "(B) propagation_cost lost: $m"; fi
if root "$o" arch | grep -q 'no_file_edges="go" unmeasured_files="2" graph_partial="1"'; then ok "(B) root: no_file_edges= names Go, 2 files"; else no "(B) root: $( root "$o" arch )"; fi
printf '%s' "$o" | wf || no "(B) not well-formed"

# ── (C) a C++ repo: nothing new ───────────────────────────────────────────────────────────────────────────
d="$TMP/c_cpp"; mkfix cpp "$d"; o="$( arch "$d" )"; dd="$( deps "$d" )"
[ -n "$( root "$o" arch )" ] || no "(C) no <arch> root"
if printf '%s%s' "$o" "$dd" | grep -qE 'no_file_edges|unmeasured_files|masked_files|zone_unknown|zone="unknown"'; then no "(C) a C++ tree carries the new vocabulary"; else ok "(C) C++ tree: no new attribute, no legend clause"; fi
if printf '%s' "$( row "$o" "$d/a" )" | grep -q ' ca="0" ce="1" '; then ok "(C) C++ numbers stand"; else no "(C) C++ row: $( row "$o" "$d/a" )"; fi

# ── (D) NEAR MISS: a language with edges and a genuinely uncoupled typed module ───────────────────────────
d="$TMP/d_near"; mkfix py "$d"; put "$d/lone/lone.py" 'class Lone:\n    def z(self):\n        return 1\n'
o="$( arch "$d" )"; r="$( row "$o" "$d/lone" )"
if printf '%s' "$r" | grep -q ' ca="0" ce="0" types="1"' && printf '%s' "$r" | grep -q 'zone="pain"' && printf '%s' "$r" | grep -q 'isolated="1"'; then ok "(D) uncoupled Python module stays Ca=Ce=0, zone=pain, isolated=1"; else no "(D) near miss moved: $r"; fi
printf '%s' "$r" | grep -q 'no_file_edges' && no "(D) near miss carries no_file_edges: $r"

# ── (E) one directory holding both kinds of file ─────────────────────────────────────────────────────────
d="$TMP/e_dir"; mkfix py "$d"; put "$d/a/stray.go" 'package a\n\ntype S struct{}\n'
put "$d/lone2/lone.py" 'class L2:\n    pass\n'; put "$d/lone2/x.go" 'package lone2\n\ntype X struct{}\n'
put "$d/shgo/run.sh" '#!/bin/sh\necho hi\n'; put "$d/shgo/main.go" 'package main\n\ntype Y struct{}\n\nfunc main() {}\n'
o="$( arch "$d" )"
r="$( row "$o" "$d/a" )"
if printf '%s' "$r" | grep -q ' ce="1" ' && printf '%s' "$r" | grep -q 'no_file_edges="go"'; then ok "(E) edges observed: ca/ce stay as floors, no_file_edges= says they cover part of the module"; else no "(E) mixed dir with edges: $r"; fi
for sub in lone2 shgo; do
    r="$( row "$o" "$d/$sub" )"
    if printf '%s' "$r" | grep -q 'zone="unknown"' && ! printf '%s' "$r" | grep -q ' ca='; then ok "(E) $sub: no edge observed with a no-edge file in it: unknown"; else no "(E) $sub: $r"; fi
done

# ── (F) --deps ───────────────────────────────────────────────────────────────────────────────────────────
dd="$( deps "$TMP/a_go" )"
f="$( printf '%s' "$dd" | sed 's/<!--.*-->//' | grep -o '<f p="a/a.go[^>]*>' )"
[ -n "$f" ] || no "(F) no <f> row for a/a.go"
printf '%s' "$f" | grep -qE 'afferent=|instab=|transitive=' && no "(F) Go row still states a number: $f"
if printf '%s' "$f" | grep -q 'no_file_edges="go"' && printf '%s' "$f" | grep -q 'includes="1"'; then ok "(F) Go <f>: includes= stays, afferent/instab/transitive unknown"; else no "(F) Go row: $f"; fi
h="$( printf '%s' "$dd" | grep -o '<health [^>]*>' )"
if printf '%s' "$h" | grep -qE ' (ccd|acd|nccd|shape)='; then no "(F) Go <health> states a verdict: $h"; else ok "(F) Go <health>: no ccd/acd/nccd/shape"; fi
printf '%s' "$h" | grep -q 'files="[0-9]*" dep_files="[0-9]*"' && printf '%s' "$h" | grep -q 'dep_langs=' || no "(F) <health> lost its denominators: $h"
if root "$dd" deps | grep -q 'no_file_edges="go" unmeasured_files="2" graph_partial="1"'; then ok "(F) Go <deps> root discloses"; else no "(F) <deps> root: $( root "$dd" deps )"; fi
printf '%s' "$dd" | wf || no "(F) Go deps not well-formed"
dd="$( deps "$TMP/b_mix" )"
if printf '%s' "$dd" | sed 's/<!--.*-->//' | grep -o '<f p="a/a.py[^>]*>' | grep -q 'afferent="0" instab="1.00" transitive="2"'; then ok "(F) mixed: Python <f> keeps its numbers"; else no "(F) mixed Python row: $( printf '%s' "$dd" | grep -o '<f p="a/a.py[^>]*>' )"; fi
printf '%s' "$dd" | grep -o '<f p="gomod/a/a.go[^>]*>' | grep -q 'afferent=' && no "(F) mixed Go row states a number"
if printf '%s' "$dd" | grep -o '<health [^>]*>' | grep -q ' shape='; then ok "(F) mixed: <health> keeps its verdict over the resolved edges"; else no "(F) mixed health lost shape"; fi

# ── (G) --report ─────────────────────────────────────────────────────────────────────────────────────────
ro="$( report "$TMP/a_go" )"
printf '%s' "$ro" | grep -q '## Dependency cycles' || no "(G) no cycles section in the Go report"
if printf '%s' "$ro" | grep -q 'none (acyclic)'; then no "(G) a Go tree reads acyclic"; else ok "(G) Go report does not say acyclic"; fi
if printf '%s' "$ro" | grep -q 'imports almost never resolved to files' && printf '%s' "$ro" | grep -q 'none found over the resolved edges'; then ok "(G) Go report names the gap"; else no "(G) Go report: $( printf '%s' "$ro" | grep -A1 'Dependency cycles' )"; fi
ro="$( report "$TMP/c_cpp" )"
if printf '%s' "$ro" | grep -q 'none (acyclic)' && ! printf '%s' "$ro" | grep -q 'no file edges'; then ok "(G) C++ report unchanged"; else no "(G) C++ report moved"; fi

# ── (H) the fact matches the index ───────────────────────────────────────────────────────────────────────
for l in $EDGED; do
    d="$TMP/h_$l"; mkfix "$l" "$d"; dd="$( deps "$d" )"
if printf '%s' "$dd" | sed 's/<!--.*-->//' | grep -qE 'afferent="[1-9]' && ! printf '%s' "$dd" | grep -q 'no_file_edges'; then ok "(H) $l: fileEdges=Resolved draws a real edge"; else no "(H) $l: Resolved in the facts but no edge: $( printf '%s' "$dd" | sed 's/<!--.*-->//' | cut -c1-300 )"; fi
done
for l in $NOEDGE; do
    dd="$( deps "$TMP/a_$l" )"
    [ -n "$( root "$dd" deps )" ] || { no "(H) $l: no <deps> root"; continue; }
    if printf '%s' "$dd" | sed 's/<!--.*-->//' | grep -qE 'afferent="[1-9]'; then no "(H) $l: Unmeasured in the facts but the index drew an edge: move its row"; else ok "(H) $l: fileEdges=Unmeasured, and no edge"; fi
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
    if [ "$c" = 1 ] && printf '%s' "$v" | wf; then ok "(I) $n: one graph_partial=, well-formed"; else no "(I) $n: graph_partial x$c: $( root "$v" "$n" )"; fi
done

# ── (J) every --arch exit path; the stderr floor line ────────────────────────────────────────────────────
d="$TMP/j_go"; mkfix go "$d"
o="$( arch "$d" )"
if grep -q 'almost none of their imports' "$TMP/stderr" && grep -q 'violations= is a floor' "$TMP/stderr" && ! grep -q 'have no file edges' "$TMP/stderr"; then ok "(J) stderr: violations= is a floor, and says almost none (go.mod replace resolves some)"; else no "(J) no stderr floor line: $( cat "$TMP/stderr" )"; fi
cp "$RULES" "$TMP/j.arch"
for mode in --baseline --baseline-update; do
    o="$( cd "$d" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$d" --arch="$TMP/j.arch" "$mode" --no-cache 2>/dev/null )"
    if root "$o" arch | grep -q 'no_file_edges="go"' && printf '%s' "$o" | grep -q 'zone="unknown"'; then ok "(J) $mode carries it"; else no "(J) $mode: $( root "$o" arch )"; fi
done
o="$( cd "$d" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$d" --arch="$TMP/j.arch" --no-cache 2>/dev/null )"
if root "$o" arch | grep -q 'no_file_edges="go"'; then ok "(J) a baselined run carries it"; else no "(J) baselined: $( root "$o" arch )"; fi
if arch "$TMP/c_cpp" >/dev/null; grep -q 'almost none of their imports' "$TMP/stderr"; then no "(J) C++ stderr has the line"; else ok "(J) C++ stderr: no line"; fi

# ── (K) an observed edge in a no-edge language keeps its numbers ─────────────────────────────────────────
d="$TMP/k"; mkdir -p "$d"
put "$d/app/go.mod" 'module example.com/app\n\ngo 1.21\n\nrequire example.com/lib v0.0.0\n\nreplace example.com/lib => ../lib\n'
put "$d/app/main.go" 'package main\n\nimport "example.com/lib"\n\ntype T struct{}\n\nfunc main() { lib.G() }\n'
put "$d/lib/go.mod" 'module example.com/lib\n\ngo 1.21\n'
put "$d/lib/lib.go" 'package lib\n\ntype L struct{}\n\nfunc G() {}\n'
o="$( cd "$d" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$d/app" "$d/lib" --arch="$RULES" --no-cache 2>/dev/null )"
r="$( row "$o" '[^"]*app' )"
if printf '%s' "$r" | grep -q ' ce="1" '; then
    if printf '%s' "$r" | grep -q 'no_file_edges="go"'; then ok "(K) Go across roots: observed edge keeps its numbers, attribute says the rest is unseen"; else no "(K) $r"; fi
    if printf '%s' "$o" | grep -o '<metrics [^>]*>' | grep -q 'propagation_cost='; then no "(K) propagation_cost over two Go files whose other imports are unseen"; else ok "(K) fix round 2, F3: propagation_cost is absent while only Go files carry the edge (a cone over them is a floor)"; fi
else
    no "(K) premise: go.mod replace drew no edge across roots: [$r]"
fi
dd="$( cd "$d" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$d/app" "$d/lib" --deps --no-cache 2>/dev/null | sed 's/<!--.*-->//' )"
if printf '%s' "$dd" | grep -o '<f p="[^"]*main.go[^>]*>' | grep -q 'afferent="0" instab="1.00"'; then ok "(K) --deps: a Go file with an observed edge keeps its numbers"; else no "(K) deps main.go: $( printf '%s' "$dd" | grep -o '<f p="[^"]*main.go[^>]*>' )"; fi
if printf '%s' "$dd" | grep -o '<health [^>]*>' | grep -q ' shape='; then no "(K) --deps: <health> gives a verdict over two Go files whose other imports are unseen"; else ok "(K) fix round 2, F3: --deps <health> has no verdict while only Go files carry the edge"; fi

# ── (L) legends ──────────────────────────────────────────────────────────────────────────────────────────
o="$( arch "$TMP/a_go" --legend=full )"; lg="$( printf '%s' "$o" | grep -o '<!--.*-->' | head -1 )"
if printf '%s' "$lg" | grep -q 'no_file_edges='; then ok "(L) arch full legend defines it when fired"; else no "(L) arch full legend silent"; fi
if o="$( arch "$TMP/c_cpp" --legend=full )"; printf '%s' "$o" | grep -q 'no_file_edges'; then no "(L) arch legend rides without the attribute"; else ok "(L) arch legend present-only"; fi
if dd="$( deps "$TMP/a_go" --legend=full )"; printf '%s' "$dd" | grep -o '<!--.*-->' | grep -q 'no_file_edges='; then ok "(L) deps full legend defines it when fired"; else no "(L) deps full legend silent"; fi
for v in arch deps; do   # present-only: a C++ tree's full legend defines neither the root clause nor masked_files
    if [ "$v" = arch ]; then o="$( arch "$TMP/c_cpp" --legend=full )"; else o="$( deps "$TMP/c_cpp" --legend=full )"; fi
    if printf '%s' "$o" | grep -qE 'masked_files|no_file_edges'; then no "(L) near miss: the $v full legend of a C++ tree defines the no-edge vocabulary"; else ok "(L) near miss: the $v full legend of a C++ tree is silent on masked_files/no_file_edges"; fi
done
if printf '%s' "$dd" | wf; then ok "(L) the clause holds no double hyphen (well-formed comment)"; else no "(L) deps legend not well-formed"; fi
for v in arch deps; do
    if [ "$v" = arch ]; then c="$( arch "$TMP/a_go" --legend=compact )"; else c="$( deps "$TMP/a_go" --legend=compact )"; fi
    lc="$( printf '%s' "$c" | grep -o '<!--.*-->' | head -1 )"
    if printf '%s' "$lc" | grep -q 'no_file_edges=LANGS:' && printf '%s' "$lc" | grep -q 'unmeasured_files=N:'; then ok "(L) $v compact legend defines both"; else no "(L) $v compact legend: $( printf '%s' "$lc" | cut -c1-300 )"; fi
done

# ── (M) C2: a no-edge file with no observed edge is out of BOTH system denominators ───────────────────────
# 9 Go packages + 2 more Go files that import nothing the index can see, plus 2 Ruby files with ONE require_relative: the one edge used to
# bring back <health shape="horizontal"> and a 0.083 propagation_cost, both over a denominator of 13 whose 11 members could not have an edge.
mkm(){ # lang dir : eleven single-file units in lang, plus a Ruby pair with one edge
    local l="$1" d="$2" i
    for i in 1 2 3 4 5 6 7 8 9; do
        if [ "$l" = go ]; then put "$d/p$i/p.go" "package p$i\n\nimport \"example.com/m/b\"\n\ntype P$i struct{}\n"
        else put "$d/p$i/p$i.py" "class P$i:\n    pass\n"; fi
    done
    if [ "$l" = go ]; then put "$d/go.mod" 'module example.com/m\n\ngo 1.21\n'; put "$d/a/a.go" 'package a\n\ntype A struct{}\n'; put "$d/b/b.go" 'package b\n\ntype B struct{}\n'
    else put "$d/a/a.py" 'class A:\n    pass\n'; put "$d/b/b.py" 'class B:\n    pass\n'; fi
    put "$d/t/t.rb" "require_relative 'lib/h'\nclass T; end\n"; put "$d/t/lib/h.rb" 'class H; end\n'
}
d="$TMP/m_go"; mkm go "$d"; dd="$( deps "$d" )"; o="$( arch "$d" )"
h="$( printf '%s' "$dd" | grep -o '<health [^>]*>' )"
if printf '%s' "$h" | grep -q 'dep_files="2"' && printf '%s' "$h" | grep -q 'masked_files="11"'; then ok "(M) --deps: dep_files= is the 2 measured files, masked_files=11 says how many were left out"; else no "(M) --deps health: $h"; fi
if printf '%s' "$h" | grep -q 'nccd="1.09" shape="vertical"'; then ok "(M) --deps: nccd/shape are over the measured files (1.09 vertical, not 0.35 horizontal)"; else no "(M) --deps verdict: $h"; fi
m="$( metrics "$o" )"
if printf '%s' "$m" | grep -q 'propagation_cost="0.750"' && printf '%s' "$m" | grep -q 'masked_files="11"'; then ok "(M) --arch: propagation_cost is over the 2 measured files (0.750), masked_files=11"; else no "(M) --arch metrics: $m"; fi
# NEAR MISS: eleven edgeless PYTHON files draw no mask, and the numbers are the ones a Python tree always had
d="$TMP/m_py"; mkm py "$d"; dd="$( deps "$d" )"; o="$( arch "$d" )"
h="$( printf '%s' "$dd" | grep -o '<health [^>]*>' )"; m="$( metrics "$o" )"
if printf '%s' "$h$m" | grep -q 'masked_files'; then no "(M) near miss: edgeless Python files were masked: $h $m"; else ok "(M) near miss: edgeless Python files are not masked"; fi
if printf '%s' "$h" | grep -q 'dep_files="13"' && printf '%s' "$h" | grep -q 'shape="horizontal"'; then ok "(M) near miss: Python tree keeps dep_files=13 and its verdict"; else no "(M) near miss health: $h"; fi
# fix round 2, F3 (retires the round-1 near miss that pinned the opposite): a Go file WITH an observed edge (go.mod replace) is masked too, its cone
# is only a floor (its other imports are unseen), so the two Go files of fixture k leave the denominator and nothing measured is left
dd="$( cd "$TMP/k" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$TMP/k/app" "$TMP/k/lib" --deps --no-cache 2>/dev/null )"
h="$( printf '%s' "$dd" | grep -o '<health [^>]*>' )"
if printf '%s' "$h" | grep -q 'masked_files="2"' && ! printf '%s' "$h" | grep -qE ' (ccd|nccd|shape)='; then ok "(M) F3: Go files with an observed edge are masked (masked_files=2) and leave no verdict"; else no "(M) F3: touched Go files stayed in the denominator: $h"; fi
# zero-edge trees keep the rule they had: nothing left to measure, so no verdict, and the count is said
dd="$( deps "$TMP/a_go" )"; h="$( printf '%s' "$dd" | grep -o '<health [^>]*>' )"
if printf '%s' "$h" | grep -q 'masked_files="2"' && ! printf '%s' "$h" | grep -qE ' (ccd|nccd|shape)='; then ok "(M) a tree of only masked files has no verdict and says masked_files=2"; else no "(M) all-masked health: $h"; fi
# legends define it where it fires
for v in arch deps; do
    if [ "$v" = arch ]; then c="$( arch "$TMP/m_go" --legend=compact )"; f="$( arch "$TMP/m_go" --legend=full )"; else c="$( deps "$TMP/m_go" --legend=compact )"; f="$( deps "$TMP/m_go" --legend=full )"; fi
    if printf '%s' "$c" | grep -o '<!--.*-->' | head -1 | grep -q 'masked_files=N:' && printf '%s' "$f" | grep -o '<!--.*-->' | head -1 | grep -q 'masked_files'; then ok "(M) $v: compact and full legends define masked_files="; else no "(M) $v legends silent on masked_files="; fi
done

# ── (N) C3: the other surfaces that printed a measured-looking zero ────────────────────────────────────────
# a git tree, four co-change waves, so a pair reaches the support floor of 3
mkco(){ # lang dir
    local l="$1" d="$2"; mkfix "$l" "$d"
    case "$l" in py) put "$d/c/c.py" 'class C:\n    pass\n'; put "$d/e/e.py" 'class E:\n    pass\n' ;; esac
    ( cd "$d" && git init -q . && git config user.email t@example.invalid && git config user.name t && git config commit.gpgsign false \
        && git add -A && git commit -qm base && for i in 1 2 3 4; do
            for f in $( git ls-files | grep -E '\.(go|py)$' ); do printf '\n# pad %s\n' "$i" >> "$f"; done
            git add -A && git commit -qm "wave $i"
          done ) >/dev/null 2>&1
}
co(){ ( cd "$1" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$1" "${@:2}" --no-cache 2>/dev/null ); }
mcp(){ # dir tool args-json
    printf '%s\n%s\n%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
        '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"'"$2"'","arguments":'"$3"'}}' \
        | ( cd "$1" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$1" --mcp --no-cache 2>/dev/null | tail -1 ); }
d="$TMP/n_go"; mkco go "$d"; dp="$TMP/n_py"; mkco py "$dp"
pair="$( co "$d" --cochange | grep -o '<pair [^>]*/>' )"
[ -n "$pair" ] || no "(N) premise: no Go co-change pair: $( co "$d" --cochange | cut -c1-200 )"
if printf '%s' "$pair" | grep -q 'surprising="1"'; then no "(N) --cochange: a Go pair with an unseen import reads surprising=1: $pair"
elif printf '%s' "$pair" | grep -q 'no_file_edges="go"'; then ok "(N) --cochange: a Go pair says no_file_edges=go instead of a hidden-coupling claim"; else no "(N) --cochange: neither claim nor disclosure: $pair"; fi
f="$( co "$d" --cochange=a/a.go | grep -o '<f [^>]*/>' )"
if ! printf '%s' "$f" | grep -q 'surprising="1"' && printf '%s' "$f" | grep -q 'no_file_edges="go"'; then ok "(N) --cochange=FILE: the same"; else no "(N) --cochange=FILE: $f"; fi
j="$( mcp "$d" cochange '{"path":"'"$d"'","file":"a/a.go"}' )"
if printf '%s' "$j" | grep -q 'surprising\\":false' && printf '%s' "$j" | grep -q 'no_file_edges\\":\\"go'; then ok "(N) MCP cochange: surprising false and no_file_edges=go"; else no "(N) MCP cochange: $( printf '%s' "$j" | cut -c1-400 )"; fi
# NEAR MISSES: an uncoupled Python pair still says surprising=1; a coupled one says nothing; no Python row names no_file_edges
pp="$( co "$dp" --cochange --pack-top-n=1000 | grep -o '<pair [^>]*/>' )"
if printf '%s' "$pp" | grep 'c/c.py' | grep 'e/e.py' | grep -q 'surprising="1"'; then ok "(N) near miss: an uncoupled Python pair is still surprising=1"; else no "(N) positive control lost: $pp"; fi
if printf '%s' "$pp" | grep 'a/a.py' | grep 'b/b.py' | grep -qE 'surprising|no_file_edges'; then no "(N) near miss: a coupled Python pair carries a claim: $pp"; else ok "(N) near miss: a coupled Python pair carries neither attribute"; fi
if printf '%s' "$pp" | grep -q 'no_file_edges'; then no "(N) near miss: Python rows carry no_file_edges"; else ok "(N) near miss: no Python row carries no_file_edges"; fi
# --impact: CLI xml, json, columnar, MCP
imp="$( co "$d" --impact=G )"; impp="$( co "$dp" --impact=g )"
if printf '%s' "$imp" | grep -o '<impact [^>]*>' | grep -q 'no_file_edges="go"'; then ok "(N) --impact: a Go def's root says no_file_edges=go (importers= is a floor)"; else no "(N) --impact root: $( printf '%s' "$imp" | grep -o '<impact [^>]*>' )"; fi
if printf '%s' "$impp" | grep -q 'no_file_edges'; then no "(N) near miss: a Python def's --impact carries no_file_edges"; else ok "(N) near miss: a Python def's --impact carries none"; fi
if co "$d" --impact=G --json | grep -q '"no_file_edges":"go"'; then ok "(N) --impact --json carries no_file_edges"; else no "(N) --impact --json silent"; fi
if co "$d" --impact=G --format=columnar | grep -q 'no_file_edges="go"'; then ok "(N) --impact --format=columnar carries no_file_edges"; else no "(N) --impact columnar silent"; fi
j="$( mcp "$d" impact '{"path":"'"$d"'","symbol":"G"}' )"
if printf '%s' "$j" | grep -q 'no_file_edges=\\"go\\"'; then ok "(N) MCP impact carries no_file_edges"; else no "(N) MCP impact silent: $( printf '%s' "$j" | cut -c1-200 )"; fi
if printf '%s' "$imp" | grep -o '<!--.*-->' | head -1 | grep -q 'no_file_edges='; then ok "(N) --impact legend defines it when fired"; else no "(N) --impact legend silent"; fi
if co "$dp" --impact=g | grep -o '<!--.*-->' | head -1 | grep -q 'no_file_edges'; then no "(N) near miss: --impact legend rides without the attribute"; else ok "(N) --impact legend present-only"; fi
if co "$dp" --impact=g --legend=full | grep -o '<!--.*-->' | head -1 | grep -q 'no_file_edges'; then no "(N) near miss: --impact full legend rides without the attribute"; else ok "(N) --impact full legend present-only"; fi
# cc.json
cc="$( co "$d" --export=cc.json )"; ccp="$( co "$dp" --export=cc.json )"
if printf '%s' "$cc" | grep -o '"name":"a.go"[^}]*}' | grep -qE 'fan_in|fan_out'; then no "(N) cc.json: a.go prints fan_in/fan_out over no edge"; else ok "(N) cc.json: a no-edge file prints neither fan_in nor fan_out"; fi
if printf '%s' "$cc" | grep -o '"name":"a.go"[^}]*}' | grep -q '"churn":'; then ok "(N) cc.json: its other metrics stay"; else no "(N) cc.json lost the file's other metrics"; fi
if printf '%s' "$ccp" | grep -o '"name":"a.py"[^}]*}' | grep -q '"fan_out":1' && ! printf '%s' "$ccp" | grep -q 'unknown'; then ok "(N) near miss: Python cc.json keeps fan_out and its descriptors"; else no "(N) Python cc.json moved"; fi
if printf '%s' "$cc" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then ok "(N) cc.json stays valid JSON"; else no "(N) cc.json not JSON"; fi
if printf '%s' "$cc" | grep -o '"fan_in":{[^}]*}' | grep -q 'unknown'; then ok "(N) cc.json descriptor says an absent value is unknown (only when fired)"; else no "(N) cc.json descriptor silent"; fi
# NEAR MISS: a Go file WITH an observed edge (go.mod replace across two roots) keeps its fan_in/fan_out
ccw="$( cd "$TMP/k" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$TMP/k/app" "$TMP/k/lib" --export=cc.json --no-cache 2>/dev/null )"
if printf '%s' "$ccw" | grep -o '"name":"main.go"[^}]*}' | grep -q '"fan_out":1' && printf '%s' "$ccw" | grep -o '"name":"lib.go"[^}]*}' | grep -q '"fan_in":1'; then ok "(N) near miss: Go files with an observed edge keep fan_in/fan_out in cc.json"; else no "(N) cc.json dropped a measured Go edge: $( printf '%s' "$ccw" | grep -o '"name":"[a-z]*.go"[^}]*}' )"; fi
# CR 5725024918 (thread 4433389558): an observed edge in ONE direction does not make the other direction a measured zero. A zero side is omitted,
# a nonzero side is a floor the descriptors say so; the Python near miss above is unchanged
if printf '%s' "$ccw" | grep -o '"name":"main.go"[^}]*}' | grep -q '"fan_in"'; then no "(N) cc.json: main.go prints fan_in:0 for a no-edge language"; else ok "(N) cc.json: main.go (an observed fan_out) prints no fan_in"; fi
if printf '%s' "$ccw" | grep -o '"name":"lib.go"[^}]*}' | grep -q '"fan_out"'; then no "(N) cc.json: lib.go prints fan_out:0 for a no-edge language"; else ok "(N) cc.json: lib.go (an observed fan_in) prints no fan_out"; fi
if printf '%s' "$ccw" | grep -o '"fan_in":{[^}]*}' | grep -q 'floor'; then ok "(N) cc.json: the descriptors call a no-edge language's value a floor"; else no "(N) cc.json: descriptors do not call a partial value a floor"; fi
if printf '%s' "$ccw" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then ok "(N) cc.json with a partial file stays valid JSON"; else no "(N) partial cc.json not JSON"; fi
# the cochange legends define it where it fires, and only there
for lg in full compact; do
    if co "$d" --cochange --legend=$lg | grep -o '<!--.*-->' | head -1 | grep -q 'no_file_edges'; then ok "(N) --cochange $lg legend defines no_file_edges"; else no "(N) --cochange $lg legend silent"; fi
    if co "$dp" --cochange --legend=$lg | grep -q 'no_file_edges'; then no "(N) near miss: the Python --cochange $lg answer mentions no_file_edges"; else ok "(N) near miss: the Python --cochange $lg answer is silent on no_file_edges"; fi
done

# ── (P) C4: a module with an observed edge AND a no-edge file keeps floors, not a verdict ──────────────────
o="$( cd "$TMP/k" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$TMP/k/app" "$TMP/k/lib" --arch="$RULES" --no-cache 2>"$TMP/stderr" )"
for sub in app lib; do
    r="$( row "$o" "[^\"]*$sub" )"
    if printf '%s' "$r" | grep -q 'zone="unknown"' && printf '%s' "$r" | grep -q 'no_file_edges="go"' && printf '%s' "$r" | grep -qE ' (ca|ce)="[0-9]+"' \
        && ! printf '%s' "$r" | grep -qE ' (I|D|reachable|isolated|leaf)='; then ok "(P) go.mod replace: $sub keeps ca/ce as floors and states no I/D/leaf/zone verdict"; else no "(P) $sub: $r"; fi
done
if printf '%s' "$o" | grep -o '<metrics [^>]*>' | grep -q 'zone_unknown="2"'; then ok "(P) both modules are in zone_unknown"; else no "(P) zone_unknown: $( metrics "$o" )"; fi
d="$TMP/e_dir"; o="$( arch "$d" )"; r="$( row "$o" "$d/a" )"
if printf '%s' "$r" | grep -q 'zone="unknown"' && ! printf '%s' "$r" | grep -qE ' (I|D|reachable|isolated|leaf)=' && printf '%s' "$r" | grep -q ' ce="1" '; then ok "(P) a Python module with a stray .go and a real edge: floors, no verdict"; else no "(P) stray-go module: $r"; fi
# NEAR MISS: the same Python module without the stray file keeps every number and its verdict
d="$TMP/p_clean"; mkfix py "$d"; o="$( arch "$d" )"; r="$( row "$o" "$d/a" )"
if printf '%s' "$r" | grep -q ' I="' && printf '%s' "$r" | grep -q ' D="' && printf '%s' "$r" | grep -q ' reachable="' && ! printf '%s' "$r" | grep -qE 'zone="unknown"|no_file_edges'; then ok "(P) near miss: a clean Python module keeps I/D/reachable/zone"; else no "(P) near miss moved: $r"; fi
# the wording is true on the same fixture: it HAS a resolved Go edge
cs="$( cd "$TMP/k" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$TMP/k/app" "$TMP/k/lib" --arch="$RULES" --legend=compact --no-cache 2>/dev/null | grep -o '<!--.*-->' | head -1 )"
if printf '%s' "$cs" | grep -q 'no import in these languages resolves to a file' || printf '%s' "$cs" | grep -q 'no edge to or from them is in any count'; then no "(P) compact legend still says none resolves, on a tree where one does"; else ok "(P) compact legend makes no claim the go.mod replace fixture refutes"; fi
if grep -q 'have no file edges' "$TMP/stderr"; then no "(P) stderr still says no file edges, on a tree that has one"; else ok "(P) stderr makes no claim the fixture refutes"; fi

# ── (Q) fix round 2 ───────────────────────────────────────────────────────────────────────────────────────
# F1: two Go files (no go.mod, so the import draws no edge) and ONE edgeless shell file. The shell file is measured, so it survives the
# mask, but there is no edge anywhere: a verdict or a propagation_cost over it would read "every file reaches every file" on a tree with none.
d="$TMP/q_g3"; put "$d/a/a.go" 'package a\n\nimport "example.com/m/b"\n\ntype A struct{}\n\nfunc F() int { return b.G() }\n'
put "$d/b/b.go" 'package b\n\ntype B struct{}\n\nfunc G() int { return 1 }\n'; put "$d/run.sh" '#!/bin/sh\necho hi\n'
dd="$( deps "$d" )"; h="$( printf '%s' "$dd" | grep -o '<health [^>]*>' )"; m="$( metrics "$( arch "$d" )" )"
if printf '%s' "$h" | grep -q 'masked_files="2"' && ! printf '%s' "$h" | grep -qE ' (ccd|acd|nccd|shape)='; then ok "(Q) F1: --deps has no verdict on a tree with no edge, one edgeless sh file left"; else no "(Q) F1 health: $h"; fi
if printf '%s' "$m" | grep -q 'masked_files="2"' && ! printf '%s' "$m" | grep -q 'propagation_cost='; then ok "(Q) F1: --arch prints no propagation_cost there, masked_files=2"; else no "(Q) F1 metrics: $m"; fi
# NEAR MISS: a tree of only edgeless sh files has no no-edge file, so it keeps the verdict it always had
d="$TMP/q_sh"; put "$d/a.sh" '#!/bin/sh\necho a\n'; put "$d/b.sh" '#!/bin/sh\necho b\n'
h="$( deps "$d" | grep -o '<health [^>]*>' )"
if printf '%s' "$h" | grep -q ' nccd=' && ! printf '%s' "$h" | grep -q 'masked_files'; then ok "(Q) F1 near miss: a pure edgeless sh tree keeps its verdict"; else no "(Q) F1 near miss: $h"; fi
# NEAR MISS: an edge between two Resolved-language files keeps the verdict beside masked Go files (fixture m_go: 11 masked, a Ruby pair with one edge)
h="$( deps "$TMP/m_go" | grep -o '<health [^>]*>' )"
if printf '%s' "$h" | grep -q ' nccd=' && printf '%s' "$h" | grep -q 'masked_files="11"'; then ok "(Q) F1 near miss: one real edge among Resolved files keeps the verdict"; else no "(Q) F1 near miss, Ruby edge: $h"; fi

# F3: fixture k (two Go files, one observed edge) plus 20 Go packages whose imports never resolve: the 2 touched files stay masked with the 21 others
d="$TMP/q_k2"; mkdir -p "$d"; cp -R "$TMP/k/app" "$TMP/k/lib" "$d/"
for i in $( seq 1 20 ); do put "$d/app/p$i/p.go" "package p$i\n\nimport \"example.com/nowhere/b\"\n\ntype P$i struct{}\n"; done
dd="$( cd "$d" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$d/app" "$d/lib" --deps --no-cache 2>/dev/null )"; h="$( printf '%s' "$dd" | grep -o '<health [^>]*>' )"
o="$( cd "$d" && perl -e 'alarm 60; exec @ARGV' "$BIN" "$d/app" "$d/lib" --arch="$RULES" --no-cache 2>/dev/null )"; m="$( metrics "$o" )"
if printf '%s' "$h" | grep -q 'masked_files="22"' && ! printf '%s' "$h" | grep -qE ' (ccd|nccd|shape)='; then ok "(Q) F3: 22 Go files masked, none measured: no verdict"; else no "(Q) F3 health: $h"; fi
if printf '%s' "$m" | grep -q 'masked_files="22"' && ! printf '%s' "$m" | grep -q 'propagation_cost='; then ok "(Q) F3: --arch prints no propagation_cost"; else no "(Q) F3 metrics: $m"; fi
# NEAR MISS: Ruby pair beside masked Go files (m_go) still measures its edge
m="$( metrics "$( arch "$TMP/m_go" )" )"
if printf '%s' "$m" | grep -q 'propagation_cost="0.750"'; then ok "(Q) F3 near miss: a Resolved-language edge keeps propagation_cost beside masked Go files"; else no "(Q) F3 near miss: $m"; fi

# F2: --cochange-groups over a Go pair with an unseen import. groups="0" read as "no modularity violation"; it must say what it could not judge.
d="$TMP/n_go"; dp="$TMP/n_py"
g="$( co "$d" --cochange --cochange-groups )"; gr="$( printf '%s' "$g" | grep -o '<cochange [^>]*>' | head -1 )"
if printf '%s' "$gr" | grep -q 'no_file_edges="go"' && printf '%s' "$gr" | grep -qE 'unknown_pairs="[1-9]'; then ok "(Q) F2: --cochange-groups on Go carries no_file_edges=go and unknown_pairs=N on the root"; else no "(Q) F2 root: $gr"; fi
if co "$d" --cochange --cochange-groups --legend=full | grep -o '<!--.*-->' | head -1 | grep -q 'unknown_pairs'; then ok "(Q) F2: its full legend defines unknown_pairs"; else no "(Q) F2 full legend silent"; fi
gp="$( co "$dp" --cochange --cochange-groups )"
if printf '%s' "$gp" | grep -q 'no_file_edges\|unknown_pairs'; then no "(Q) F2 near miss: the Python groups answer mentions the disclosure"; else ok "(Q) F2 near miss: the Python groups answer is silent on it"; fi
if co "$dp" --cochange --cochange-groups --legend=full | grep -q 'no_file_edges\|unknown_pairs'; then no "(Q) F2 near miss: the Python full legend rides without the attribute"; else ok "(Q) F2 near miss: the Python full legend is present-only"; fi
if printf '%s' "$gp" | grep -q '<group '; then ok "(Q) F2 near miss: the Python groups answer still has its group"; else no "(Q) F2 near miss: Python groups lost: $( printf '%s' "$gp" | cut -c1-300 )"; fi
gc="$( co "$d" --cochange --cochange-groups --legend=compact | grep -o '<!--.*-->' | head -1 )"
if printf '%s' "$gc" | grep -q 'unknown_pairs'; then ok "(Q) F2: the compact legend defines unknown_pairs"; else no "(Q) F2 compact legend silent: $( printf '%s' "$gc" | cut -c1-200 )"; fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
