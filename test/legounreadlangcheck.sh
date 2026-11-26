#!/usr/bin/env bash
# legounreadlangcheck.sh — an interface whose language's implementor relation this build never reads must read
# UNREAD on --lego, never implementors="0".
#
# THE DEFECT. `--lego=TYPE` answers one interface's method contract plus every implementor, so an agent can read a
# real implementation as the template for a new one. The implementor relation comes from extends/implements CLAUSES
# (src/ingest_relations.h captureBases, plus the Rust impl pass and the Ruby mixin capture). Go has no such clause —
# conformance is structural — so captureBases reads nothing for it and `g.implementors` is empty for EVERY Go
# interface. The targeted verb printed that as `implementors="0"`, which under this project's own rule ("a zero means
# none found, never none exists"; a count that cannot be a total is labelled a floor) is a WRONG ANSWER: on nfpm,
# `--lego=Packager` said implementors="0" about an interface six packagers implement, i.e. it told the reader to write
# from scratch while the template sat in the tree. ObjC (`@interface D : Base`), C, GDScript and Clojure measured the
# same way, and ObjC is the worst of them: its method contract IS read, so the reader gets a full contract beside a
# confident false zero.
#
# THE FIX UNDER TEST. LangFacts::implementorEdges (src/langfacts.h) — the per-language fact, Unread by default, Read
# only for a language this gate proves draws an edge. Where it is Unread, packLego's targeted branch OMITS
# implementors= and emits `implementors_unread_for_lang="<langTag>"` instead: unknown, not zero. That is the
# `no_file_edges=`/`fileEdges::Unmeasured` convention (lane arch-honest, src/graphlegend.h), whose rule is the same —
# "A <f> row with no_file_edges= and no edge observed has no afferent=/instab=/transitive=: unknown, not zero" — and
# the reason reads `unread-for-lang`, beside the neighbouring `caveat="not-extracted-for-lang"` on the same row.
#
# Every fixture is built at runtime under mktemp. Arms:
#   (A) UNREAD: a Go interface with two real implementors carries the disclosure and NO implementors=
#   (B) NON-VACUITY, read off the fixture itself: the Go fixture really holds >=2 types implementing every method the
#       interface declares (derived from the fixture text, never hardcoded), and ripwire really INDEXED those types —
#       so the absent edge is "no edge drawn", not "nothing was there to draw it from"
#   (C) CONTROL: a language whose relation IS read keeps a real implementors= and never acquires the disclosure
#   (D) THE FACT MATCHES THE INDEX, both ways: every Read language draws an edge and discloses nothing; every Unread
#       language draws none and discloses, naming its OWN langTag. A row on the wrong side reds here.
#   (E) MIXED tree: Go beside C++ — the C++ row keeps its count, the Go row discloses (a tree-wide disclaimer reds)
#   (F) LEGEND: the compact dialect DEFINES the new attribute where it rides, and does not where it does not
#   (G) DETERMINISM: two runs byte-identical, on both an unread and a read answer
#   (H) WELL-FORMEDNESS: no duplicate attribute where the contract caveat and the disclosure ride the same row
#   (I) MCP `lego` parity: the two dialects cannot describe implementors= differently
#   (J) MUTATION CONTROL: a deliberately wrong assertion fails, so a PASS above is discrimination and not a tautology
#
# Usage: bash test/legounreadlangcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "legounreadlangcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# Well-formedness is read by xmllint when it exists and by expat (python3) when it does not: both refuse a duplicate
# attribute, so a host without xmllint loses no arm.
if command -v xmllint >/dev/null 2>&1; then
    wf(){ xmllint --noout - 2>/dev/null; }
elif command -v python3 >/dev/null 2>&1; then
    echo "legounreadlangcheck: no xmllint, well-formedness is read by python3 expat"
    wf(){ python3 -I -c 'import sys,xml.etree.ElementTree as E; E.fromstring(sys.stdin.buffer.read())' 2>/dev/null; }
else
    echo "legounreadlangcheck: no xmllint and no python3: the well-formedness arms SKIP, every other arm runs"
    wf(){ return 0; }
fi

put(){ mkdir -p "$( dirname "$1" )"; printf '%b' "$2" > "$1"; }
lego(){ perl -e 'alarm 120; exec @ARGV' "$BIN" "$1" --lego="${2:-Base}" --legend=compact --no-cache 2>/dev/null; }
iface(){ printf '%s' "$1" | sed 's/<!--[^>]*-->//g' | grep -o '<iface [^>]*>' | tail -1; }

# ── the fixtures: one interface named Base with TWO implementors, per language ────────────────────────────────────
# Every language is written in its OWN idiom for "D1 and D2 both implement Base". The split between READ and UNREAD
# below is the fact table's claim; arm (D) proves the index agrees with it in both directions.
mkfix(){   # $1 lang key, $2 dir
    local d="$2"
    case "$1" in
    cpp)    put "$d/a.cpp"   'class Base { public: virtual void f(); };\nclass D1 : public Base { public: void f(); };\nclass D2 : public Base { public: void f(); };\n' ;;
    python) put "$d/a.py"    'class Base:\n    def f(self): pass\nclass D1(Base):\n    def f(self): pass\nclass D2(Base):\n    def f(self): pass\n' ;;
    ts)     put "$d/a.ts"    'export interface Base { f(): void }\nexport class D1 implements Base { f(): void {} }\nexport class D2 implements Base { f(): void {} }\n' ;;
    js)     put "$d/a.js"    'export class Base { f() {} }\nexport class D1 extends Base { f() {} }\nexport class D2 extends Base { f() {} }\n' ;;
    java)   put "$d/A.java"  'interface Base { void f(); }\nclass D1 implements Base { public void f() {} }\nclass D2 implements Base { public void f() {} }\n' ;;
    rust)   put "$d/a.rs"    'pub trait Base { fn f(&self); }\npub struct D1;\nimpl Base for D1 { fn f(&self) {} }\npub struct D2;\nimpl Base for D2 { fn f(&self) {} }\n' ;;
    swift)  put "$d/a.swift" 'protocol Base { func f() }\nclass D1: Base { func f() {} }\nclass D2: Base { func f() {} }\n' ;;
    cs)     put "$d/A.cs"    'interface Base { void F(); }\nclass D1 : Base { public void F() {} }\nclass D2 : Base { public void F() {} }\n' ;;
    ruby)   put "$d/a.rb"    'class Base\n  def f; end\nend\nclass D1 < Base\n  def f; end\nend\nclass D2 < Base\n  def f; end\nend\n' ;;
    php)    put "$d/a.php"   '<?php\ninterface Base { public function f(); }\nclass D1 implements Base { public function f() {} }\nclass D2 implements Base { public function f() {} }\n' ;;
    kt)     put "$d/A.kt"    'interface Base { fun f() }\nclass D1 : Base { override fun f() {} }\nclass D2 : Base { override fun f() {} }\n' ;;
    dart)   put "$d/a.dart"  'abstract class Base { void f(); }\nclass D1 extends Base { void f() {} }\nclass D2 extends Base { void f() {} }\n' ;;
    ex)     put "$d/a.ex"    'defprotocol Base do\n  def f(x)\nend\ndefimpl Base, for: D1 do\n  def f(_x), do: :ok\nend\ndefimpl Base, for: D2 do\n  def f(_x), do: :ok\nend\n' ;;
    go)     put "$d/a.go"    'package p\n\ntype Base interface {\n\tF() error\n\tName() string\n}\n\ntype D1 struct{}\n\nfunc (d *D1) F() error { return nil }\n\nfunc (d *D1) Name() string { return "d1" }\n\ntype D2 struct{}\n\nfunc (d *D2) F() error { return nil }\n\nfunc (d *D2) Name() string { return "d2" }\n' ;;
    objc)   put "$d/a.h"     '#import <Foundation/Foundation.h>\n\n@interface Base : NSObject\n- (void)f;\n@end\n\n@interface D1 : Base\n- (void)f;\n@end\n\n@interface D2 : Base\n- (void)f;\n@end\n'
            put "$d/a.m"     '#import "a.h"\n\n@implementation Base\n- (void)f {}\n@end\n' ;;
    c)      put "$d/a.c"     'struct Base { void (*f)(void); };\nstruct D1 { struct Base base; };\nstruct D2 { struct Base base; };\n' ;;
    gd)     put "$d/base.gd" 'class_name Base\nextends Node\nfunc f():\n\tpass\n'
            put "$d/d1.gd"   'extends Base\nclass_name D1\nfunc f():\n\tpass\n'
            put "$d/d2.gd"   'extends Base\nclass_name D2\nfunc f():\n\tpass\n' ;;
    clj)    put "$d/a.clj"   '(defprotocol Base (f [this]))\n(defrecord D1 [] Base (f [this] nil))\n(defrecord D2 [] Base (f [this] nil))\n' ;;
    *)      echo "legounreadlangcheck: mkfix has no fixture for '$1'"; exit 2 ;;
    esac
}
# The fact table's two sides, as langTag spellings paired with the fixture key. A language with no type to target
# (Markdown, JSON, TOML, YAML, Bash, Proto, Lua's setmetatable tables) has no --lego answer to disclose on and is
# therefore not fixtured; it rides the Unread default, which is the honest answer for a language that says nothing.
READ="cpp python ts js java rust swift cs ruby php kt dart ex"
UNREAD="go objc c gd clj"
tagOf(){ case "$1" in cpp) echo cpp;; python) echo py;; ts) echo ts;; js) echo js;; java) echo java;; rust) echo rs;;
                      swift) echo swift;; cs) echo cs;; ruby) echo rb;; php) echo php;; kt) echo kt;; dart) echo dart;;
                      ex) echo ex;; go) echo go;; objc) echo objc;; c) echo c;; gd) echo gd;; clj) echo clj;;
                      *) echo "?";; esac; }

for l in $READ $UNREAD; do mkfix "$l" "$TMP/f_$l"; done

# ── (A) UNREAD: the Go answer discloses and prints no implementors= ──────────────────────────────────────────────
GO="$( lego "$TMP/f_go" )"
GOR="$( iface "$GO" )"
if [ -z "$GOR" ]; then
    no "(A) no <iface> row for the Go Base at all — the premise of every arm below is gone: $( printf '%s' "$GO" | cut -c1-400 )"
else
    if printf '%s' "$GOR" | grep -q ' implementors="'; then
        no "(A) the Go row still states an implementors count, so a zero there is still a claim: $GOR"
    else
        ok "(A) Go: implementors= is absent, never a zero"
    fi
    if printf '%s' "$GOR" | grep -q 'implementors_unread_for_lang="go"'; then
        ok "(A) Go: the row discloses implementors_unread_for_lang=\"go\""
    else
        no "(A) Go: no unread-for-lang disclosure on the row: $GOR"
    fi
fi

# ── (B) NON-VACUITY, tracked to the fixture ──────────────────────────────────────────────────────────────────────
# B1 reads the Go fixture's OWN text: the methods `type Base interface` declares, then the receiver types that define
# every one of them. If the fixture ever drifts (a method dropped from the interface, an implementor's method
# renamed) this arm goes red instead of letting (A) pass for the wrong reason.
if command -v python3 >/dev/null 2>&1; then
    implCount="$( python3 -I - "$TMP/f_go/a.go" <<'PY'
import re, sys
src = open( sys.argv[1], encoding="utf-8" ).read()
m = re.search( r"type\s+Base\s+interface\s*\{(.*?)\}", src, re.S )
if not m:
    print( "NO-INTERFACE" ); raise SystemExit
want = { n for n in re.findall( r"^\s*([A-Z]\w*)\s*\(", m.group( 1 ), re.M ) }
if not want:
    print( "NO-METHODS" ); raise SystemExit
have = {}
for recv, name in re.findall( r"^func\s*\(\s*\w+\s+\*?(\w+)\s*\)\s*(\w+)\s*\(", src, re.M ):
    have.setdefault( recv, set() ).add( name )
print( len( [ t for t, names in have.items() if want <= names ] ) )
PY
)"
    case "$implCount" in
    ''|NO-*|0|1) no "(B1) the Go fixture does not hold the shape under test (two types implementing every method of Base): $implCount" ;;
    *)           ok "(B1) the Go fixture really holds $implCount types implementing every method Base declares" ;;
    esac
else
    echo "legounreadlangcheck: no python3, (B1) SKIPS; (B2) still proves the types were indexed"
fi
# B2: the implementor TYPES are in the index. Without this, an empty implementor list could mean "the crawl saw
# nothing" rather than "the extractor draws no such edge", and the disclosure would be describing the wrong gap.
MAP="$( perl -e 'alarm 120; exec @ARGV' "$BIN" "$TMP/f_go" --legend=compact --no-cache 2>/dev/null )"
if printf '%s' "$MAP" | grep -q 'n="D1"' && printf '%s' "$MAP" | grep -q 'n="D2"'; then
    ok "(B2) ripwire indexed D1 and D2 — the absent edge is no edge drawn, not nothing to draw from"
else
    no "(B2) D1/D2 are not in the Go map, so the absent implementor list says nothing about the extractor"
fi

# ── (C) CONTROL: a read language keeps a real count and never acquires the disclosure ────────────────────────────
CPP="$( lego "$TMP/f_cpp" )"
CPPR="$( iface "$CPP" )"
if printf '%s' "$CPPR" | grep -q 'implementors="2"' && ! printf '%s' "$CPPR" | grep -q 'implementors_unread_for_lang'; then
    ok "(C) C++: implementors=\"2\" stands, no disclosure"
else
    no "(C) C++ control moved — a fix that disclaims everywhere is worse than the defect: $CPPR"
fi
if printf '%s' "$CPP" | grep -q '<impl n="D1"' && printf '%s' "$CPP" | grep -q '<impl n="D2"'; then
    ok "(C) C++: both <impl> rows still render"
else
    no "(C) C++ lost its <impl> rows: $( printf '%s' "$CPP" | cut -c1-400 )"
fi

# ── (D) the fact matches the index, both ways ────────────────────────────────────────────────────────────────────
for l in $READ; do
    r="$( iface "$( lego "$TMP/f_$l" )" )"
    [ -n "$r" ] || { no "(D) $l: no <iface> row — the arm would be vacuous"; continue; }
    if printf '%s' "$r" | grep -qE ' implementors="[1-9]' && ! printf '%s' "$r" | grep -q 'implementors_unread_for_lang'; then
        ok "(D) $l: implementorEdges=Read, and the index drew an edge"
    else
        no "(D) $l: Read in the facts but no counted implementor (or it disclosed anyway) — move its row: $r"
    fi
done
for l in $UNREAD; do
    r="$( iface "$( lego "$TMP/f_$l" )" )"
    [ -n "$r" ] || { no "(D) $l: no <iface> row — the arm would be vacuous"; continue; }
    if printf '%s' "$r" | grep -q ' implementors="'; then
        no "(D) $l: Unread in the facts but the row states a count — move its row: $r"
    elif printf '%s' "$r" | grep -q "implementors_unread_for_lang=\"$( tagOf "$l" )\""; then
        ok "(D) $l: implementorEdges=Unread, disclosed as $( tagOf "$l" )"
    else
        no "(D) $l: Unread in the facts and the row neither counts nor discloses: $r"
    fi
done

# ── (E) MIXED tree: one tree, both kinds of language ────────────────────────────────────────────────────────────
mkfix cpp "$TMP/mix"; put "$TMP/mix/go/a.go" 'package p\n\ntype GoBase interface {\n\tF() error\n}\n\ntype G1 struct{}\n\nfunc (g *G1) F() error { return nil }\n\ntype G2 struct{}\n\nfunc (g *G2) F() error { return nil }\n'
MC="$( iface "$( lego "$TMP/mix" Base )" )"
MG="$( iface "$( lego "$TMP/mix" GoBase )" )"
if printf '%s' "$MC" | grep -q 'implementors="2"' && ! printf '%s' "$MC" | grep -q 'implementors_unread_for_lang'; then
    ok "(E) mixed: the C++ row keeps its count beside Go files"
else
    no "(E) mixed: the C++ row moved: $MC"
fi
if printf '%s' "$MG" | grep -q 'implementors_unread_for_lang="go"' && ! printf '%s' "$MG" | grep -q ' implementors="'; then
    ok "(E) mixed: the Go row discloses beside C++ files"
else
    no "(E) mixed: the Go row: $MG"
fi

# ── (F) LEGEND registration, present-only ───────────────────────────────────────────────────────────────────────
# An emitted attribute with no row in the compact DICTIONARY ships undocumented and silently, so the definition is
# asserted on an answer that CARRIES the attribute — and asserted ABSENT on one that does not.
if printf '%s' "$GO" | grep -q 'implementors_unread_for_lang=LANG'; then
    ok "(F) the compact legend defines implementors_unread_for_lang on the answer that carries it"
else
    no "(F) implementors_unread_for_lang is emitted with no definition in the compact legend: $( printf '%s' "$GO" | grep -o '<!--[^>]*-->' | head -1 | cut -c1-600 )"
fi
if printf '%s' "$CPP" | grep -q 'implementors_unread_for_lang=LANG'; then
    no "(F) the C++ answer defines an attribute it does not carry — the row is not present-only"
else
    ok "(F) the definition does not ride an answer without the attribute"
fi
for v in full compact; do
    L="$( perl -e 'alarm 120; exec @ARGV' "$BIN" "$TMP/f_go" --lego=Base --legend="$v" --no-cache 2>/dev/null )"
    if printf '%s' "$L" | grep -q 'unread-for-lang'; then
        ok "(F) --legend=$v names the unread-for-lang reading"
    else
        no "(F) --legend=$v does not name unread-for-lang: $( printf '%s' "$L" | grep -o '<!--[^>]*-->' | head -1 | cut -c1-600 )"
    fi
done

# ── (G) DETERMINISM ─────────────────────────────────────────────────────────────────────────────────────────────
for l in go cpp; do
    lego "$TMP/f_$l" > "$TMP/det1_$l"; lego "$TMP/f_$l" > "$TMP/det2_$l"
    if cmp -s "$TMP/det1_$l" "$TMP/det2_$l"; then ok "(G) $l: two runs byte-identical"; else no "(G) $l: runs differ"; fi
done

# ── (H) WELL-FORMEDNESS: the contract caveat and the disclosure share the row ───────────────────────────────────
for l in $READ $UNREAD; do
    printf '%s' "$( lego "$TMP/f_$l" )" | wf || no "(H) $l: --lego output is not well-formed (a duplicate attribute?)"
done
ok "(H) every fixture's --lego answer is well-formed"

# ── (I) MCP `lego` parity ───────────────────────────────────────────────────────────────────────────────────────
REQ='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"lego","arguments":{"path":"'"$TMP/f_go"'","type":"Base"}}}'
printf '%s\n' "$REQ" | "$BIN" --mcp 2>/dev/null > "$TMP/mcp_go" || true
if grep -q 'implementors_unread_for_lang=\\"go\\"' "$TMP/mcp_go" && ! grep -q 'implementors=\\"0\\"' "$TMP/mcp_go"; then
    ok "(I) MCP lego says the same thing as --lego"
else
    no "(I) MCP lego disagrees with --lego (see $TMP/mcp_go): $( cut -c1-500 "$TMP/mcp_go" )"
fi

# ── (J) MUTATION CONTROL ────────────────────────────────────────────────────────────────────────────────────────
# The same greps, pointed at the answer they must NOT match. A green run above with a green run here would mean the
# patterns match anything.
if printf '%s' "$CPPR" | grep -q 'implementors_unread_for_lang'; then
    no "(J) mutation control: the disclosure pattern matched the C++ row — the arms are tautologies"
else
    ok "(J) mutation control: the disclosure pattern does not match a read language's row"
fi
if printf '%s' "$GOR" | grep -q 'implementors="2"'; then
    no "(J) mutation control: the count pattern matched the Go row — the arms are tautologies"
else
    ok "(J) mutation control: the count pattern does not match the unread language's row"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
