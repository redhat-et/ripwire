#!/usr/bin/env bash
# assertedcheck.sh — asserted=1 beside tested=1: a test that REACHES a row is not a test that CHECKS anything (lane
# asserted-signal, research audit 2026-11-26 top-10 item 2).
#
# WHY. tested=1 means an indexed test reaches the row over call edges (#770 says "reached, not asserted"). Rahman et al.
# (arXiv 2610.33708, "Covered Is Not Checked") found 18% of covered branch outcomes could change with no test failing. The
# static half of that gap is visible in the index: a reaching test whose body makes no assertion call cannot fail on the row's
# result. asserted=1 marks a tested row that at least one ASSERTING test reaches. A test asserts when its own body, or a
# test-scoped helper it calls (over test symbols only, transitively), makes a call from its language's assertion vocabulary
# (langfacts.h assertionCalls). An assertion in PRODUCTION code on the path never counts: the check has to be the test's.
# Absence means none found, never none exists.
#
# ARMS. Per covered language (fixture below), --callers=<lang>_leaf lists the production rows that call the leaf:
#   (<L>a) the row a test reaches AND asserts on carries tested="1" asserted="1"            — RED on the base (no asserted=)
#   (<L>h) the row a test reaches through a test-scoped asserting helper: the same            — RED on the base
#   (<L>n) the row a test reaches with NO assertion carries tested="1" and no asserted=      — a prohibition: it passes on the
#          base too, so it only counts beside its language's (<L>a) arm, which proves the attribute is emitted at all
#   (Pp)   Python: an assert in the PRODUCTION row itself does not make it asserted (no test of it asserts) — paired the same way
# Surface arms: (S) a test row never carries asserted=; (I) --impact rows carry it on the same rows as --callers; (J) the JSON
# rows carry "asserted":true on the same rows; (M) the MCP impact twin carries it; (B) --callees carries it; (Co) the columnar
# form's present-only last <asserted> column, (Co0) absent when no row asserts.
# Covered languages (one control each, a NAMED test function): Python, C++, C, Go, Rust, TypeScript, JavaScript, Java, Kotlin,
# C#, Ruby, Elixir, Lua, GDScript, Clojure. Scoped out (langfacts.h assertionCalls says why): Bash, Dart, Swift, Objective-C, PHP.
# (Fg) the over-claim guard: an anonymous test callback's assertions are never counted (its calls belong to its file's scope).
# Legend arms: (L1) compact defines asserted= when a row carries it, (L2) --legend=full defines it, (L3) the reading says
# "none found", (L0) an answer with no asserted row carries no asserted= term (present-only; paired with L1).
#
# Usage: bash test/assertedcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "assertedcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0; passed=0; failed=0
ok(){ printf '  PASS  %s\n' "$*"; passed=$(( passed + 1 )); return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; failed=$(( failed + 1 )); }

COR="$TMP/c"
mk(){ mkdir -p "$( dirname "$COR/$1" )"; cat >"$COR/$1"; }

# ── Python: pytest's bare assert statement, unittest self.assert*, a test-scoped helper, and a production-side assert ─────────
mk src/pylib.py <<'E'
def py_leaf():
    return 1


def py_checked():
    return py_leaf()


def py_unchecked():
    assert py_leaf() == 1
    return py_leaf()


def py_helped():
    return py_leaf()


def py_unit():
    return py_leaf()
E
mk tests/test_pylib.py <<'E'
import unittest
from src.pylib import py_checked, py_unchecked, py_helped, py_unit


def _expect_one(value):
    assert value == 1


def test_checked():
    assert py_checked() == 1


def test_unchecked():
    py_unchecked()


def test_helped():
    _expect_one(py_helped())


class TestUnit(unittest.TestCase):
    def test_unit(self):
        self.assertEqual(py_unit(), 1)
E
# ── C++: GoogleTest macros, a test-scoped helper ────────────────────────────────────────────────────────────────────────────
mk src/cclib.cpp <<'E'
int cc_leaf() { return 1; }
int cc_checked() { return cc_leaf(); }
int cc_unchecked() { return cc_leaf(); }
int cc_helped() { return cc_leaf(); }
E
mk tests/cclib_test.cpp <<'E'
int cc_checked();
int cc_unchecked();
int cc_helped();
static void expectOne( int v ) { ASSERT_EQ( v, 1 ); }
TEST( CcLib, Checked ) { EXPECT_EQ( cc_checked(), 1 ); }
TEST( CcLib, Unchecked ) { cc_unchecked(); }
TEST( CcLib, Helped ) { expectOne( cc_helped() ); }
E
# ── Go: testing.T's Errorf/Fatalf, testify, a test-scoped helper ─────────────────────────────────────────────────────────────
mk golib/lib.go <<'E'
package golib

func GoLeaf() int      { return 1 }
func GoChecked() int   { return GoLeaf() }
func GoUnchecked() int { return GoLeaf() }
func GoHelped() int    { return GoLeaf() }
func GoTestify() int   { return GoLeaf() }
E
mk golib/lib_test.go <<'E'
package golib

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func expectOne(t *testing.T, v int) {
	if v != 1 {
		t.Fatalf("got %d", v)
	}
}

func TestChecked(t *testing.T) {
	if GoChecked() != 1 {
		t.Errorf("bad")
	}
}

func TestUnchecked(t *testing.T) { GoUnchecked() }

func TestHelped(t *testing.T) { expectOne(t, GoHelped()) }

func TestTestify(t *testing.T) { assert.Equal(t, 1, GoTestify()) }
E
# ── Rust: assert_eq! inside #[cfg(test)] ────────────────────────────────────────────────────────────────────────────────────
mk src/rslib.rs <<'E'
pub fn rs_leaf() -> i32 { 1 }
pub fn rs_checked() -> i32 { rs_leaf() }
pub fn rs_unchecked() -> i32 { rs_leaf() }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn checked() { assert_eq!(rs_checked(), 1); }
    #[test]
    fn unchecked() { rs_unchecked(); }
}
E
# ── TypeScript: Jest/Vitest expect in a NAMED test function (the control); an anonymous callback's assertion is never counted ─
mk src/tslib.ts <<'E'
export function tsLeaf(): number { return 1; }
export function tsChecked(): number { return tsLeaf(); }
export function tsUnchecked(): number { return tsLeaf(); }
export function tsAnon(): number { return tsLeaf(); }
E
mk tests/checked.test.ts <<'E'
import { tsChecked } from "../src/tslib";
function checksTsChecked() { expect(tsChecked()).toBe(1); }
test("checked", checksTsChecked);
E
mk tests/anon.test.ts <<'E'
import { tsAnon } from "../src/tslib";
test("anon", () => { expect(tsAnon()).toBe(1); });
E
mk tests/unchecked.test.ts <<'E'
import { tsUnchecked } from "../src/tslib";
test("unchecked", () => { tsUnchecked(); });
E
# ── Java: JUnit assertEquals ────────────────────────────────────────────────────────────────────────────────────────────────
mk src/main/java/JLib.java <<'E'
public class JLib {
    public static int jLeaf() { return 1; }
    public static int jChecked() { return jLeaf(); }
    public static int jUnchecked() { return jLeaf(); }
}
E
mk src/test/java/JLibTest.java <<'E'
import static org.junit.jupiter.api.Assertions.assertEquals;
public class JLibTest {
    @Test public void checked() { assertEquals(1, JLib.jChecked()); }
    @Test public void unchecked() { JLib.jUnchecked(); }
}
E
# ── C#: xUnit Assert.Equal (a member of the Assert class) ───────────────────────────────────────────────────────────────────
mk src/CsLib.cs <<'E'
public class CsLib
{
    public static int CsLeaf() { return 1; }
    public static int CsChecked() { return CsLeaf(); }
    public static int CsUnchecked() { return CsLeaf(); }
}
E
mk tests/CsLibTests.cs <<'E'
public class CsLibTests
{
    [Fact] public void Checked() { Assert.Equal(1, CsLib.CsChecked()); }
    [Fact] public void Unchecked() { CsLib.CsUnchecked(); }
}
E
# ── Ruby: minitest assert_equal ─────────────────────────────────────────────────────────────────────────────────────────────
mk lib/rblib.rb <<'E'
module RbLib
  def self.rb_leaf
    1
  end

  def self.rb_checked
    rb_leaf
  end

  def self.rb_unchecked
    rb_leaf
  end
end
E
mk test/rblib_test.rb <<'E'
class RbLibTest < Minitest::Test
  def test_checked
    assert_equal 1, RbLib.rb_checked
  end

  def test_unchecked
    RbLib.rb_unchecked
  end
end
E

# ── Kotlin, Elixir, GDScript, C (Unity): a named test function asserts or does not ──────────────────────────────────────────
mk src/klib.kt <<'E'
fun kLeaf(): Int = 1
fun kChecked(): Int = kLeaf()
fun kUnchecked(): Int = kLeaf()
E
mk src/test/kotlin/KLibTest.kt <<'E'
class KLibTest {
    @Test fun checked() { assertEquals(1, kChecked()) }
    @Test fun unchecked() { kUnchecked() }
}
E
mk lib/elib.ex <<'E'
defmodule ELib do
  def e_leaf, do: 1
  def e_checked, do: e_leaf()
  def e_unchecked, do: e_leaf()
end
E
mk test/elib_test.exs <<'E'
defmodule ELibTest do
  use ExUnit.Case
  test "checked" do
    assert ELib.e_checked() == 1
  end
  test "unchecked" do
    ELib.e_unchecked()
  end
end
E
mk src/glib.gd <<'E'
func g_leaf():
	return 1
func g_checked():
	return g_leaf()
func g_unchecked():
	return g_leaf()
E
mk test/test_glib.gd <<'E'
extends GutTest
func test_checked():
	assert_eq(g_checked(), 1)
func test_unchecked():
	g_unchecked()
E
mk csrc/clibc.c <<'E'
int c_leaf(void) { return 1; }
int c_checked(void) { return c_leaf(); }
int c_unchecked(void) { return c_leaf(); }
E
mk tests/test_clibc.c <<'E'
int c_checked(void);
int c_unchecked(void);
void test_checked(void) { TEST_ASSERT_EQUAL(1, c_checked()); }
void test_unchecked(void) { c_unchecked(); }
E
# ── callback-style frameworks: the control is a NAMED test function; an anonymous callback's own assertion is never counted ──
mk src/jslib.js <<'E'
function jsLeaf() { return 1; }
function jsChecked() { return jsLeaf(); }
function jsUnchecked() { return jsLeaf(); }
function jsNode() { return jsLeaf(); }
module.exports = { jsChecked, jsUnchecked, jsNode };
E
mk test/checked.test.js <<'E'
const { jsChecked } = require("../src/jslib");
function checksJsChecked() { expect(jsChecked()).toBe(1); }
test("c", checksJsChecked);
E
mk test/node.test.js <<'E'
const assert = require("node:assert");
const { jsNode } = require("../src/jslib");
function checksJsNode() { assert.strictEqual(jsNode(), 1); }
test("n", checksJsNode);
E
mk test/unchecked.test.js <<'E'
const { jsUnchecked } = require("../src/jslib");
test("u", () => { jsUnchecked(); });
E
# Dart is scoped out (langfacts.h): package:test callbacks live inside the NAMED function main, so no Dart row reads asserted.
mk lib/dlib.dart <<'E'
int dLeaf() => 1;
int dChecked() => dLeaf();
E
mk test/dchecked_test.dart <<'E'
void main() { test('c', () { expect(dChecked(), 1); }); }
E
mk src/llib.lua <<'E'
function l_leaf() return 1 end
function l_checked() return l_leaf() end
function l_unchecked() return l_leaf() end
E
mk spec/lchecked_spec.lua <<'E'
function checks_l_checked() assert(l_checked() == 1) end
describe("l", function() it("c", checks_l_checked) end)
E
mk spec/lunchecked_spec.lua <<'E'
describe("l", function() it("u", function() l_unchecked() end) end)
E
mk src/cljlib.clj <<'E'
(ns cljlib)
(defn clj-leaf [] 1)
(defn clj-checked [] (clj-leaf))
(defn clj-unchecked [] (clj-leaf))
E
mk test/cljlib_checked_test.clj <<'E'
(ns cljlib-checked-test (:require [clojure.test :refer :all] [cljlib :refer :all]))
(defn checks-clj-checked [] (is (= 1 (clj-checked))))
(deftest checked (checks-clj-checked))
E
mk test/cljlib_unchecked_test.clj <<'E'
(ns cljlib-unchecked-test (:require [clojure.test :refer :all] [cljlib :refer :all]))
(deftest unchecked (clj-unchecked))
E
# ── the over-claim guard: ONE RSpec file whose first example asserts must NOT mark the row only its second example reaches ────
mk lib/rsgran.rb <<'E'
module RsGran
  def self.gran_leaf; 1; end
  def self.gran_checked; gran_leaf; end
  def self.gran_unchecked; gran_leaf; end
end
E
mk spec/rsgran_spec.rb <<'E'
describe RsGran do
  it "checks" do
    expect(RsGran.gran_checked).to eq 1
  end
  it "only calls" do
    RsGran.gran_unchecked
  end
end
E

answer(){ local out="$1"; shift; ( cd "$COR" && perl -e 'alarm 60; exec @ARGV' "$BIN" . "$@" --no-cache >"$out" 2>/dev/null </dev/null ); }
# row FILE NAME — the payload <s> row named NAME (legend comments stripped), or empty
row(){ perl -0pe 's/<!--.*?-->//gs' "$1" | grep -o "<s [^>]*n=\"$2\"[^>]*>" | head -1; }
# arm LABEL FILE NAME WANT — WANT is both (tested+asserted), tested (tested, no asserted)
arm(){
    local label="$1" file="$2" name="$3" want="$4" r
    r="$( row "$file" "$name" )"
    if [ -z "$r" ]; then no "$label: no <s n=\"$name\"> row (premise)"; return; fi
    case "$want" in
        both)   case "$r" in *'tested="1"'*'asserted="1"'*) ok "$label: $name carries tested=\"1\" asserted=\"1\"" ;;
                             *) no "$label: $name should carry tested=\"1\" asserted=\"1\": $r" ;; esac ;;
        tested) case "$r" in *'asserted='*) no "$label: $name carries asserted= with no asserting test: $r" ;;
                             *'tested="1"'*) ok "$label: $name carries tested=\"1\" and no asserted=" ;;
                             *) no "$label: $name lost tested=\"1\": $r" ;; esac ;;
    esac
}

legend(){ perl -0ne 'print join( " ", /<!--(.*?)-->/gs )' "$1"; }
echo "=== per-language arms (--callers=<lang>_leaf) ==="
lang(){   # lang TAG LEAF CHECKED UNCHECKED [HELPED]
    local tag="$1" leaf="$2" f="$TMP/$1.callers"
    answer "$f" --callers="$leaf" --legend=compact
    arm "($tag a)" "$f" "$3" both
    arm "($tag n)" "$f" "$4" tested
    [ -n "${5:-}" ] && arm "($tag h)" "$f" "$5" both
    return 0
}
lang Py py_leaf py_checked py_unchecked py_helped
arm "(Py u) unittest self.assertEqual" "$TMP/Py.callers" py_unit both
arm "(Pp) a production-side assert is not the test's" "$TMP/Py.callers" py_unchecked tested
lang Cc cc_leaf cc_checked cc_unchecked cc_helped
lang Go GoLeaf GoChecked GoUnchecked GoHelped
arm "(Go t) testify assert.Equal" "$TMP/Go.callers" GoTestify both
lang Rs rs_leaf rs_checked rs_unchecked
lang Ts tsLeaf tsChecked tsUnchecked
lang Java jLeaf jChecked jUnchecked
lang Cs CsLeaf CsChecked CsUnchecked
lang Rb rb_leaf 'RbLib#rb_checked' 'RbLib#rb_unchecked'
lang Kt kLeaf kChecked kUnchecked
lang Ex e_leaf 'ELib.e_checked/0' 'ELib.e_unchecked/0'
lang Gd g_leaf g_checked g_unchecked
lang C c_leaf c_checked c_unchecked
lang Js jsLeaf jsChecked jsUnchecked
arm "(Js t) node:assert assert.strictEqual" "$TMP/Js.callers" jsNode both
lang Lua l_leaf l_checked l_unchecked
lang Clj clj-leaf clj-checked clj-unchecked
# (Fg) the over-claim guard. An anonymous callback's calls belong to its file's module scope, which stands in for every example in
# the file, so its assertions are never counted. Prohibitions: each passes on the base too, so each is paired with a red
# positive arm of the same language's NAMED test (Rb a, Ts a, Js a, Lua a, Clj a) that proves asserted= is emitted at all.
answer "$TMP/gran.callers" --callers=gran_leaf --legend=compact
arm "(Fg) RSpec: the example that only CALLS gets no asserted from its asserting sibling" "$TMP/gran.callers" 'RsGran#gran_unchecked' tested
arm "(Fg) RSpec: the asserting anonymous example itself is not counted (the stated floor)" "$TMP/gran.callers" 'RsGran#gran_checked' tested
arm "(Fg) Jest: an anonymous callback's expect() is not counted" "$TMP/Ts.callers" tsAnon tested
answer "$TMP/dart.callers" --callers=dLeaf --legend=compact
arm "(Fg) Dart (scoped out): package:test's callback in main() is not counted" "$TMP/dart.callers" dChecked tested
answer "$TMP/py.leaf.compact" --callers=py_leaf --legend=compact
case "$( legend "$TMP/py.leaf.compact" )" in *'not counted for an anonymous test callback'*) ok "(Fg) the compact reading says anonymous test callbacks are not counted" ;;
                                             *) no "(Fg) the compact reading does not say anonymous test callbacks are not counted" ;; esac

echo "=== surface arms ==="
answer "$TMP/py.callers.test" --callers=py_checked --legend=compact
t="$( row "$TMP/py.callers.test" test_checked )"
case "$t" in *'test="1"'*) case "$t" in *asserted=*) no "(S) a test row carries asserted=: $t" ;; *) ok "(S) the test row test_checked is test=\"1\" with no asserted=" ;; esac ;;
             *) no "(S) premise: --callers=py_checked has no test=\"1\" row test_checked: $t" ;; esac
answer "$TMP/py.impact" --impact=py_leaf --legend=compact
arm "(I) --impact asserted row" "$TMP/py.impact" py_checked both
arm "(I) --impact unasserted row" "$TMP/py.impact" py_unchecked tested
answer "$TMP/py.callees" --callees=test_checked --legend=compact
arm "(B) --callees asserted row" "$TMP/py.callees" py_checked both
answer "$TMP/py.json" --callers=py_leaf --json
jrow(){ grep -o "{\"t\":\"[a-z]*\",\"n\":\"$1\"[^}]*}" "$TMP/py.json" | head -1; }
case "$( jrow py_checked )" in *'"tested":true'*'"asserted":true'*) ok "(J) JSON py_checked carries \"tested\":true,\"asserted\":true" ;;
                               *) no "(J) JSON py_checked lacks \"asserted\":true: $( jrow py_checked )" ;; esac
case "$( jrow py_unchecked )" in *'"asserted"'*) no "(J) JSON py_unchecked carries asserted: $( jrow py_unchecked )" ;;
                                 *'"tested":true'*) ok "(J) JSON py_unchecked carries \"tested\":true and no asserted" ;;
                                 *) no "(J) premise: JSON py_unchecked row missing: $( jrow py_unchecked )" ;; esac
answer "$TMP/py.col" --callers=py_leaf --format=columnar --legend=compact
CF="$( grep -o '<cols [^>]*fields="[^"]*"' "$TMP/py.col" | sed 's/.*fields="//; s/"$//' )"
CA="$( grep -o '<asserted>[^<]*</asserted>' "$TMP/py.col" | sed 's/<[^>]*>//g' )"
CN="$( grep -o '<name>[^<]*</name>' "$TMP/py.col" | sed 's/<[^>]*>//g' )"
python3 - "$CF" "$CA" "$CN" <<'PYC' && ok "(Co) columnar: fields= lists asserted last and <asserted> is 1 exactly on py_checked/py_helped/py_unit" || no "(Co) columnar asserted column wrong: fields=$CF asserted=$CA names=$CN"
import sys
f, a, n = sys.argv[1].split( "," ), sys.argv[2].split( "," ), sys.argv[3].split( "," )
want = { "py_checked", "py_helped", "py_unit" }
sys.exit( 0 if f and f[-1] == "asserted" and len( a ) == len( n ) and { x for x, v in zip( n, a ) if v == "1" } == want else 1 )
PYC
case "$( legend "$TMP/py.col" )" in *'<asserted> column:'*'none found'*) ok "(Co) compact defines the <asserted> column" ;; *) no "(Co) compact leaves the <asserted> column undefined" ;; esac
answer "$TMP/none.col" --callers=cc_unchecked --format=columnar --legend=compact
grep -Eq '<asserted>|fields="[^"]*asserted|<asserted> column' "$TMP/none.col" && no "(Co0) a columnar answer with no asserted row carries an asserted column or term" \
    || ok "(Co0) a columnar answer with no asserted row carries no asserted column (present-only)"
MCP="$( printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"impact","arguments":{"path":"'"$COR"'","symbol":"py_leaf"}}}' \
    | perl -e 'alarm 30; exec @ARGV' "$BIN" "$COR" --mcp --no-cache 2>/dev/null | tail -1 )"
mrow(){ printf '%s' "$MCP" | grep -o "<s [^>]*n=\\\\\"$1\\\\\"[^>]*>" | head -1; }
case "$( mrow py_checked )" in *'asserted=\"1\"'*) ok "(M) the MCP impact twin carries asserted=\"1\" on py_checked" ;;
                               *) no "(M) the MCP impact twin lacks asserted on py_checked: $( mrow py_checked ) $( printf '%s' "$MCP" | cut -c1-200 )" ;; esac
case "$( mrow py_unchecked )" in *asserted*) no "(M) the MCP impact twin carries asserted on py_unchecked" ;;
                                 *'tested=\"1\"'*) ok "(M) the MCP impact twin: py_unchecked tested, no asserted" ;;
                                 *) no "(M) premise: MCP py_unchecked row missing" ;; esac

echo "=== legend arms ==="
L="$( legend "$TMP/Py.callers" )"
case "$L" in *'asserted=1'*) ok "(L1) compact --callers defines asserted= beside its row" ;; *) no "(L1) compact --callers emits asserted= undefined" ;; esac
case "$L" in *'asserted=1'*'none found'*) ok "(L3) the compact reading says none found" ;; *) no "(L3) the compact asserted reading does not say none found" ;; esac
answer "$TMP/Py.full" --callers=py_leaf --legend=full
case "$( legend "$TMP/Py.full" )" in *'asserted="1"'*) ok "(L2) --legend=full defines asserted=" ;; *) no "(L2) --legend=full emits asserted= undefined" ;; esac
answer "$TMP/none.callers" --callers=cc_unchecked --legend=compact
grep -q 'asserted=' "$TMP/none.callers" && no "(L0) an answer with no asserted row carries an asserted= term" \
    || ok "(L0) an answer with no asserted row carries no asserted= term (present-only)"

echo "assertedcheck: $passed passed, $failed failed"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILURES"; exit 1; }
