#!/usr/bin/env bash
# rubydescribedclasscheck.sh — gate for RSpec's `described_class` as a CONSTANT receiver: inside
# `RSpec.describe Calc do … end`, `described_class.m1( 1 )` is `Calc.m1( 1 )`, so it pins to Calc::m1 through the
# same Rule 2c arm a written `Calc.m1( 1 )` takes (#267), instead of declining.
#
# Why it matters: a spec's calls are the test→code edges tested=, --seams and --test-gate read. `described_class`
# is how RSpec spells the class under test (902 uses in one measured Rails app's spec/, 4216 in another), and it is
# a bare (identifier) receiver no binding names, so every such call declined and the spec reached nothing.
#
# The rule is RSpec's own (rspec-core 3.13, Metadata::ExampleGroupHash#described_class): a group's described class
# is its FIRST description argument unless that is nil or a String; otherwise it is the parent group's. So the
# INNERMOST enclosing example group whose first argument is a constant wins, and a string-described group passes
# its parent's through. An example group is a call of describe/context (and their x/f and feature spellings)
# with no receiver or the receiver `RSpec`, that carries a block.
#
# Stated floors, pinned below so each stays a decision:
#   (a) a CHAINED receiver (`described_class.new.m_chain`) was untouched — the same one-hop bound as #267's
#       `Calc.new.scale`: the receiver is a call, not a constant — until parser version 132 typed a receiver the code
#       builds (test/rubytypedrecvcheck.sh). Its arm below is kept, INVERTED: it now pins m_chain to Calc.
#   (b) a group with no constant (`RSpec.describe "no class"`, `RSpec.describe :sym`) names no class, so
#       `described_class` there is left exactly as it was.
#   (c) a `describe` call on any other receiver (`Docs.describe Calc do`) is not an RSpec example group.
#   (d) `subject` — the implicit `described_class.new` — is NOT modeled by this rule: an explicit `subject { … }`
#       can be anything. test/rubytypedrecvcheck.sh (parser version 132) types a group's subject, explicit or
#       implicit, as a call RECEIVER from what its block builds.
#   (e) a REDEFINED `described_class` declines: the redefinition names what it means, and this rule does not read
#       it, so it answers nothing rather than the group's constant. A METHOD of that name — any `:described_class`
#       symbol (`let( :described_class ) { … }`) or `def described_class` — declines every site in the file, since a
#       method reaches the whole group. A LOCAL of that name — an assignment (`=`, `||=`), a multiple-assignment
#       target, a block or method parameter — declines the sites Ruby reads as that local: after the binding in its
#       own scope and in the blocks nested inside it, never in a sibling block, and never across a `def`. The name
#       is matched as a whole word: `my_described_class = x` and `:described_class_name` redefine nothing.
#   (f) a QUALIFIED describe is named by its FINAL segment: `RSpec.describe Cask::Tab` reads as `Tab`, the same
#       final-segment rule #267 gives a written `Cask::Tab.m`. So where another `Tab` defines the method too, the
#       call splits between the two; where only the other `Tab` defines it (the described class inherits it), the
#       call pins to that one, unmarked. Carrying the full path to the resolver is its own round.
#
# A SHARED group (`shared_examples`, `shared_examples_for`, `shared_context`) stops the walk with no answer: its body
# runs inside whichever group includes it, so its lexical parent's described class is not its own.
#
# Usage:  test/rubydescribedclasscheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubydescribedclasscheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh. Self-contained via mktemp.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
FIX="$DIR/fix"; mkdir -p "$FIX/lib" "$FIX/spec"

# Every method name is defined on TWO classes, so an unpinned call is a split or a decline and a pinned one names
# exactly one class. Each case below uses its own name: a spec's calls all land in one <file-scope> owner.
cat > "$FIX/lib/calc.rb" <<'RUBY'
class Calc
  def self.m_top( a )
    a
  end

  def self.m_str( a )
    a
  end

  def self.m_ctx( a )
    a
  end

  def self.m_inner( a )
    a
  end

  def self.m_none( a )
    a
  end

  def self.m_sym( a )
    a
  end

  def self.m_docs( a )
    a
  end

  def self.m_nil( a )
    a
  end

  def self.m_let( a )
    a
  end

  def self.m_asgn( a )
    a
  end

  def self.r_bparam( a )
    a
  end

  def self.r_mparam( a )
    a
  end

  def self.r_masgn( a )
    a
  end

  def self.r_opasgn( a )
    a
  end

  def self.m_sib( a )
    a
  end

  def self.m_pre( a )
    a
  end

  def self.m_wb1( a )
    a
  end

  def self.m_wb2( a )
    a
  end

  def self.m_shared( a )
    a
  end

  def self.m_sctx( a )
    a
  end

  def self.r_self( a )
    a
  end

  def m_chain
    1
  end
end

class Tally
  def self.m_top( a )
    a
  end

  def self.m_str( a )
    a
  end

  def self.m_ctx( a )
    a
  end

  def self.m_inner( a )
    a
  end

  def self.m_none( a )
    a
  end

  def self.m_sym( a )
    a
  end

  def self.m_docs( a )
    a
  end

  def self.m_nil( a )
    a
  end

  def self.m_let( a )
    a
  end

  def self.m_asgn( a )
    a
  end

  def self.r_bparam( a )
    a
  end

  def self.r_mparam( a )
    a
  end

  def self.r_masgn( a )
    a
  end

  def self.r_opasgn( a )
    a
  end

  def self.m_sib( a )
    a
  end

  def self.m_pre( a )
    a
  end

  def self.m_wb1( a )
    a
  end

  def self.m_wb2( a )
    a
  end

  def self.m_shared( a )
    a
  end

  def self.m_sctx( a )
    a
  end

  def self.r_self( a )
    a
  end

  def m_chain
    2
  end
end

module Outer
  class Engine
    def self.e_run
      1
    end
  end
end

class Other
  def self.e_run
    2
  end
end

module Docs
  def self.describe( what )
    yield
  end
end
RUBY

# floor (f): two classes whose FINAL segment matches, each in its own file so FILE:SYM names one definition
cat > "$FIX/lib/cask_tab.rb" <<'RUBY'
module Cask
  class Tab
    def self.t_both( a )
      a
    end
  end
end
RUBY

cat > "$FIX/lib/tab.rb" <<'RUBY'
class Tab
  def self.t_both( a )
    a
  end

  def self.t_lone( a )
    a
  end
end
RUBY

cat > "$FIX/spec/calc_spec.rb" <<'RUBY'
RSpec.describe Calc do
  it "pins the top-level group's class" do
    described_class.m_top( 1 )
  end

  describe "a string group" do
    it "passes its parent's class through" do
      described_class.m_str( 1 )
    end
  end

  context "a context" do
    it "passes its parent's class through too" do
      described_class.m_ctx( 1 )
    end
  end

  describe nil do
    it "passes its parent's class through, as a string does" do
      described_class.m_nil( 1 )
    end
  end

  describe Tally do
    it "takes the innermost constant" do
      described_class.m_inner( 1 )
    end
  end

  it "leaves a chained receiver alone" do
    described_class.new.m_chain
  end
end
RUBY

cat > "$FIX/spec/engine_spec.rb" <<'RUBY'
describe Outer::Engine do
  it { described_class.e_run }
end
RUBY

cat > "$FIX/spec/noclass_spec.rb" <<'RUBY'
RSpec.describe "no class" do
  it { described_class.m_none( 1 ) }
end

RSpec.describe :sym do
  it { described_class.m_sym( 1 ) }
end
RUBY

cat > "$FIX/spec/docs_spec.rb" <<'RUBY'
Docs.describe Calc do
  described_class.m_docs( 1 )
end
RUBY

cat > "$FIX/spec/let_spec.rb" <<'RUBY'
RSpec.describe Calc do
  let( :described_class ) { Tally }
  it { described_class.m_let( 1 ) }
end
RUBY

cat > "$FIX/spec/asgn_spec.rb" <<'RUBY'
RSpec.describe Calc do
  it "calls through a local of the same name" do
    described_class = Tally
    described_class.m_asgn( 1 )
  end
end
RUBY

cat > "$FIX/spec/local_spec.rb" <<'RUBY'
RSpec.describe Calc do
  [Tally].each do |described_class|
    it { described_class.r_bparam( 1 ) }
  end

  def helper( described_class )
    described_class.r_mparam( 1 )
  end

  it { described_class, other = Tally, 1
       described_class.r_masgn( 1 ) }

  it do
    described_class ||= Tally
    described_class.r_opasgn( 1 )
  end

  it { described_class = described_class.r_self( 1 ) }
end
RUBY

cat > "$FIX/spec/scope_spec.rb" <<'RUBY'
RSpec.describe Calc do
  it "binds a local after one call" do
    described_class.m_pre( 1 )
    described_class = Tally
  end

  it "is a sibling of the example that binds it" do
    described_class.m_sib( 1 )
  end
end
RUBY

cat > "$FIX/spec/wordb1_spec.rb" <<'RUBY'
RSpec.describe Calc do
  it do
    my_described_class = Tally
    described_class.m_wb1( 1 )
  end
end
RUBY

cat > "$FIX/spec/wordb2_spec.rb" <<'RUBY'
RSpec.describe Calc do
  it do
    respond_to( :described_class_name )
    described_class.m_wb2( 1 )
  end
end
RUBY

cat > "$FIX/spec/shared_spec.rb" <<'RUBY'
RSpec.describe Calc do
  shared_examples "a shared group" do
    it { described_class.m_shared( 1 ) }
  end

  shared_context "a shared context" do
    it { described_class.m_sctx( 1 ) }
  end
end
RUBY

cat > "$FIX/spec/qual_spec.rb" <<'RUBY'
RSpec.describe Cask::Tab do
  it { described_class.t_both( 1 ) }
  it { described_class.t_lone( 1 ) }
end
RUBY

MAP="$DIR/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
if [ $? -eq 0 ]; then ok "default map exits 0"; else no "default map exited non-zero: $( cat "$DIR/map.err" )"; fi
[ -s "$DIR/map.err" ] && no "unexpected stderr: $( head -3 "$DIR/map.err" )" || ok "clean stderr"
command -v xmllint >/dev/null 2>&1 && { if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi; }

# calls ROOT SYM SPEC — 0 when --callers=SYM lists SPEC's <file-scope> as a caller, 1 when it does not, and a FAIL (2)
# when the run itself failed: an absence arm must never read a crashed run as "not a caller".
calls(){
    if ! "$BIN" "$1" --no-cache --callers="$2" >"$DIR/c.out" 2>"$DIR/c.err"
    then
        no "--callers=$2 exited non-zero: $( head -3 "$DIR/c.err" )"
        return 2
    fi
    sed 's/></>\n</g' "$DIR/c.out" | grep -q "p=\"spec/$3:"
}
# pins SPEC METHOD CLASS OTHER WHY — SPEC's call reaches CLASS::METHOD and not OTHER::METHOD
pins(){
    local hit=1 miss=1
    calls "$FIX" "$3::$2" "$1"; hit=$?
    calls "$FIX" "$4::$2" "$1"; miss=$?
    if [ "$hit" -eq 2 ] || [ "$miss" -eq 2 ]
    then
        return
    fi
    if [ "$hit" -eq 0 ] && [ "$miss" -eq 1 ]
    then
        ok "$1: described_class.$2 → $3::$2 alone ($5)"
    else
        no "$1: described_class.$2 — $3::$2 caller=$( [ "$hit" -eq 0 ] && echo yes || echo no ), $4::$2 caller=$( [ "$miss" -eq 0 ] && echo yes || echo no ) — want $3 alone ($5)"
    fi
}
# untouched SPEC METHOD WHY — SPEC's call is NOT pinned to Calc alone: Calc and Tally answer the same
untouched(){
    local a=1 b=1
    calls "$FIX" "Calc::$2" "$1"; a=$?
    calls "$FIX" "Tally::$2" "$1"; b=$?
    if [ "$a" -eq 2 ] || [ "$b" -eq 2 ]
    then
        return
    fi
    [ "$a" -eq "$b" ] && ok "$1: described_class.$2 is not pinned to one class ($3)" \
        || no "$1: described_class.$2 reaches Calc=$( [ "$a" -eq 0 ] && echo yes || echo no ) Tally=$( [ "$b" -eq 0 ] && echo yes || echo no ) — $3"
}

echo "=== described_class is the innermost constant-described group's class ==="
pins calc_spec.rb   m_top   Calc   Tally "RSpec.describe Calc do"
pins calc_spec.rb   m_str   Calc   Tally "a string-described group passes its parent's class through"
pins calc_spec.rb   m_ctx   Calc   Tally "so does a string-described context"
pins calc_spec.rb   m_inner Tally  Calc  "a nested describe Tally is the innermost constant — RSpec's own rule"
pins engine_spec.rb e_run   Engine Other "a bare describe, and a scope_resolution constant named by its final segment"
pins calc_spec.rb   m_nil   Calc   Tally "describe nil passes its parent's class through — RSpec reads nil like a String"

echo "=== floor (a) lifted: described_class.new is a typed receiver (parser version 132) ==="
pins calc_spec.rb   m_chain Calc   Tally "described_class.new.m_chain — the receiver the code builds is a Calc (test/rubytypedrecvcheck.sh)"

echo "=== floors (b) no constant, (c) not RSpec, (e) redefined — each left exactly as it was ==="
untouched noclass_spec.rb m_none  "RSpec.describe \"no class\" names no class (floor (b), stated)"
untouched noclass_spec.rb m_sym   "RSpec.describe :sym names no class (floor (b), stated)"
untouched docs_spec.rb    m_docs  "Docs.describe Calc is not an RSpec example group (floor (c), stated)"
untouched let_spec.rb     m_let   "let( :described_class ) redefines it: the file declines (floor (e), stated)"
untouched asgn_spec.rb    m_asgn   "a local described_class = Tally redefines it: the site after it declines (floor (e), stated)"
untouched local_spec.rb   r_bparam "a block parameter |described_class| redefines it inside that block (floor (e), stated)"
untouched local_spec.rb   r_mparam "a method parameter def helper( described_class ) redefines it inside that def (floor (e), stated)"
untouched local_spec.rb   r_masgn  "a multiple-assignment target described_class, other = … redefines it (floor (e), stated)"
untouched local_spec.rb   r_opasgn "described_class ||= Tally binds a local too (floor (e), stated)"
untouched local_spec.rb   r_self   "described_class = described_class.r_self — the right side already reads the local (floor (e), stated)"

echo "=== floor (e) is Ruby's local scoping, and matches the name as a whole word ==="
pins scope_spec.rb  m_pre   Calc   Tally "a site BEFORE the local's assignment still reads RSpec's method"
pins scope_spec.rb  m_sib   Calc   Tally "a local bound in a sibling example does not reach this one"
pins wordb1_spec.rb m_wb1   Calc   Tally "my_described_class = Tally is another name — nothing is redefined"
pins wordb2_spec.rb m_wb2   Calc   Tally ":described_class_name is another symbol — nothing is redefined"

echo "=== a shared group stops the walk: its body runs in whichever group includes it ==="
untouched shared_spec.rb  m_shared "shared_examples inside RSpec.describe Calc is not described by Calc"
untouched shared_spec.rb  m_sctx   "nor is shared_context"

echo "=== floor (f): a qualified describe is named by its final segment (stated, pinned both ways) ==="
calls "$FIX" lib/cask_tab.rb:t_both qual_spec.rb; qa=$?
calls "$FIX" lib/tab.rb:t_both      qual_spec.rb; qb=$?
if [ "$qa" -ne 2 ] && [ "$qb" -ne 2 ]
then
    [ "$qa" -eq 0 ] && [ "$qb" -eq 0 ] && ok "qual_spec.rb: describe Cask::Tab reads as Tab — described_class.t_both splits over Cask::Tab and ::Tab (floor (f), stated)" \
        || no "qual_spec.rb: described_class.t_both — Cask::Tab caller=$( [ "$qa" -eq 0 ] && echo yes || echo no ), ::Tab caller=$( [ "$qb" -eq 0 ] && echo yes || echo no ) — floor (f) says both"
fi
calls "$FIX" lib/tab.rb:t_lone qual_spec.rb; ql=$?
if [ "$ql" -ne 2 ]
then
    [ "$ql" -eq 0 ] && ok "qual_spec.rb: described_class.t_lone pins to ::Tab, the only Tab defining it — the unmarked pin floor (f) states" \
        || no "qual_spec.rb: described_class.t_lone no longer reaches ::Tab::t_lone — floor (f) moved; restate it"
fi

echo "=== determinism and warm == cold ==="
"$BIN" "$FIX" --no-cache >"$DIR/b.xml" 2>/dev/null
cmp -s "$MAP" "$DIR/b.xml" && ok "byte-identical across two --no-cache runs" \
    || no "output differs across runs"
if ! "$BIN" "$FIX" --cache="$DIR/c.bin" >"$DIR/cold.xml" 2>"$DIR/cold.err"
then
    no "the cold cache run exited non-zero: $( head -3 "$DIR/cold.err" )"
fi
if ! "$BIN" "$FIX" --cache="$DIR/c.bin" >"$DIR/warm.xml" 2>"$DIR/warm.err"
then
    no "the warm cache run exited non-zero: $( head -3 "$DIR/warm.err" )"
fi
cmp -s "$DIR/cold.xml" "$DIR/warm.xml" && ok "warm run == cold run" \
    || no "the warm cache disagrees with the cold run"

echo "=== mutation: describe Tally instead of Calc → the pin must follow the group's constant ==="
MUT="$DIR/mut"; mkdir -p "$MUT/lib" "$MUT/spec"; cp "$FIX/lib/calc.rb" "$MUT/lib/calc.rb"
sed 's/^RSpec.describe Calc do$/RSpec.describe Tally do/' "$FIX/spec/calc_spec.rb" >"$MUT/spec/calc_spec.rb"
grep -q '^RSpec.describe Tally do$' "$MUT/spec/calc_spec.rb" || no "mutation did not apply"
calls "$MUT" "Tally::m_top" calc_spec.rb; mt=$?
calls "$MUT" "Calc::m_top" calc_spec.rb; mc=$?
if [ "$mt" -ne 2 ] && [ "$mc" -ne 2 ]
then
    [ "$mt" -eq 0 ] && [ "$mc" -eq 1 ] && ok "mutation: described_class.m_top follows the group to Tally::m_top" \
        || no "mutation: with RSpec.describe Tally, Tally caller=$( [ "$mt" -eq 0 ] && echo yes || echo no ), Calc caller=$( [ "$mc" -eq 0 ] && echo yes || echo no )"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
