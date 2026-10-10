#!/usr/bin/env bash
# rubyinheritcheck.sh — gate for Ruby INHERITANCE edges: `class Child < Parent` is an IS-A edge, so it
# reaches the lego (interface/implementor) view and the resolver's base walk.
#
# What was missing. ingest_relations.h::captureBases turns a class's base clause into inherit RawRefs
# (role Extends), which buildGraph reads into the CHA-lite name graph chaUp/chaDown — the table Rule 1's
# `super`/implicit-self walk and Rules 2b/2c's methodOnTypeOrBases probe after a type's OWN method set
# misses. Ruby reached none of it. The clause kind `superclass` was already in captureBases' table (Java
# spells its `extends` clause with the same node name), but isBaseTypeNode's list of base-TYPE node kinds
# had no entry Ruby uses: Ruby names a base with (constant) — `class Child < Parent` — or with
# (scope_resolution) — `class Derived < Space::Base`. So Ruby corpora carried no inheritance edges at
# all: `--lego` listed no implementors, and `Child.build` could not reach a `build` defined on Parent.
#
# That second half is what held the gem numbers down in the constant-receiver round
# (test/rubyrecvnarrowcheck.sh, floor (a)): a Rails gem reaches its class methods up an
# ActiveRecord::Base hierarchy, and without chaUp the receiver rule can only see a type's OWN methods.
#
# The rule: a Ruby base is the (constant) or (scope_resolution) child of the class's `superclass` clause,
# named by its FINAL segment (`Space::Base` → `Base`), which is how chaUp and byName key every other
# language's bases. Everything else about captureBases is unchanged.
#
# Stated floors, pinned below so each stays a decision:
#   (a) a COMPUTED superclass (`class Dynamic < Struct.new( :a )`) is a call, not a constant — no edge. Not
#       even to the call's RECEIVER: captureBases descends one wrapper level for every language (TS's
#       `extends_clause`, C#'s `base_list`), and in Ruby that descent landed on `Struct`, minting an edge that
#       only read as absent because the fixture defines no Struct. `class Built < Factory.fabricate( :x )` against
#       an in-tree `Factory` pins it.
#   (b) a MIXIN (`include Helper` / `extend` / `prepend`) is an ANCESTOR for the call graph since parser version
#       131 — the base walk, the CHA cone and a bare call's reach read it (ingest_relations.h captureRubyMixinBases,
#       test/rubyreachcheck.sh) — and since lane lego-transitive it is an IMPLEMENTOR edge too: graph.h's implementors
#       builder admits a Ruby module as a base (BuiltinMethodGate::isClassLike's Ruby-module rule), so --lego=Helper
#       lists Mixed. Floor (b) is CLOSED; the arm below is inverted and says so (rake: `include Rake::DSL`).
#   (c) the base WALK is keyed by NAME. A base is found by name (its final segment, as every language's is)
#       and then SCOPED: the superclass as written is looked up the way Ruby looks it up — Module.nesting
#       innermost first, then the top level, `::X` absolute — against every class/module the tree opens (the
#       #57 constant index, wrappers included), and only a definition with THAT fully-qualified constant gets
#       the implementor row. So `class Rec < ActiveRecord::Base` is no implementor of the fixture's `Space::Base`,
#       `class Inner < Base` inside `module Beta` lands on Beta::Base alone, and a base the tree never opens
#       (`ActiveRecord::Base`) adds nothing to the CHA name graph — Rec's walk no longer reaches Space::Base's
#       methods. What stays name-keyed is the walk's METHOD probe (canonByName is keyed `Scope::method` with the
#       IMMEDIATE scope), so two in-tree bases sharing a final name still share one probe — for a call to self. A call
#       on a CLASS walks fully-qualified constants since parser version 137 (test/rubyclassrecvcheck.sh): the
#       `UsesAlpha.beta_make` arm below is kept, INVERTED — UsesAlpha < Alpha::Base reaches no Beta::Base#beta_make.
#   (d) `Built = Class.new( Parent )` — with or without a block — makes Built < Parent at runtime, but it is a constant
#       ASSIGNMENT whose value is a call, not a `class` open: no class symbol, no superclass clause, no edge. The same
#       decision as (a): the tool reads a base off a class header, never off a computed value.
#
# A class REOPENED with its superclass repeated (`class Reop < Parent … end` twice, legal Ruby) is two symbols but one
# constant, so the lego view lists it ONCE: implementors are keyed by the derived class's constant, not by open.
#
# Usage:  test/rubyinheritcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyinheritcheck.sh
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
FIX="$DIR/fix"; mkdir -p "$FIX"

cat > "$FIX/h.rb" <<'RUBY'
class Parent
  def self.build
    1
  end

  def shared_helper( n )
    n
  end

  def bare_helper
    2
  end
end

class Child < Parent
  def use_inherited
    shared_helper( 1 )
  end

  def use_bare
    bare_helper
  end
end

class GrandChild < Child
end

module Space
  class Base
    def self.make
      3
    end
  end
end

class Derived < Space::Base
end

class Rec < ActiveRecord::Base
end

class Dynamic < Struct.new( :a )
end

class Factory
  def self.fabricate( x )
    x
  end
end

class Built < Factory.fabricate( :x )
end

module Helper
  def helped
    4
  end
end

class Mixed
  include Helper
end

class Unrelated
  def self.build
    9
  end

  def self.make
    9
  end

  def shared_helper( n )
    n
  end

  def bare_helper
    9
  end
end
RUBY

cat > "$FIX/caller.rb" <<'RUBY'
class Caller
  def call_inherited
    Child.build
  end

  def call_two_levels
    GrandChild.build
  end

  def call_scoped_base
    Derived.make
  end

  def call_mixin
    Mixed.new.helped
  end

  def call_out_of_tree_base
    Rec.make
  end
end
RUBY

# floor (c)'s fixture: two MORE in-tree `Base`s, each in its own file so `--lego=FILE:Base` names one definition.
cat > "$FIX/alpha.rb" <<'RUBY'
module Alpha
  class Base
    def self.alpha_make
      5
    end
  end
end
RUBY

cat > "$FIX/beta.rb" <<'RUBY'
module Beta
  class Base
    def self.beta_make
      6
    end
  end

  class Inner < Base
  end
end
RUBY

# A BODY-LESS base beside a same-named class WITH a body (Space::Base has `def self.make`). The C-family decl/def
# collapse reads `class Base < StandardError; end` as a forward declaration and drops it from byName whenever a bodied
# `Base` exists — activerecord's Encryption::Errors::Base lost its six subclasses to rails/generators' Base that way.
cat > "$FIX/errs.rb" <<'RUBY'
module Errs
  class Base < StandardError; end
  class Oops < Base; end
end
RUBY

cat > "$FIX/scoped.rb" <<'RUBY'
class UsesAlpha < Alpha::Base
end

class Abs < ::Parent
end

class Outer
  class Nested
  end
end

class FromWrapper < Outer
end

class ScopedCaller
  def call_alpha
    UsesAlpha.alpha_make
  end

  def call_beta_through_alpha
    UsesAlpha.beta_make
  end
end
RUBY

# A class reopened with its superclass repeated — two opens, one constant — and the Class.new form of floor (d).
cat > "$FIX/reopen.rb" <<'RUBY'
class Reop < Parent
  def first_half
    1
  end
end

class Reop < Parent
  def second_half
    2
  end
end

Built2 = Class.new( Parent )

Blocky = Class.new( Parent ) do
  def blocky
    3
  end
end
RUBY

MAP="$DIR/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
if [ $? -eq 0 ]; then ok "default map exits 0"; else no "default map exited non-zero: $( cat "$DIR/map.err" )"; fi
[ -s "$DIR/map.err" ] && no "unexpected stderr: $( head -3 "$DIR/map.err" )" || ok "clean stderr"
command -v xmllint >/dev/null 2>&1 && { if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi; }

SPLIT="$DIR/split"; sed 's/></>\n</g' "$MAP" >"$SPLIT"
rowOf(){ awk -v pat="$1" '$0 ~ pat{f=1;print;next} /^<s /{f=0} f' "$SPLIT"; }
edgesTo(){ echo "$1" | grep -c "<c n=\"$2\""; }
lego(){ "$BIN" "$FIX" --no-cache --lego="$1" 2>/dev/null | sed 's/></>\n</g'; }
# refuses TYPE — --lego=TYPE must exit non-zero with its own "type not found": the tree indexes no such type, so no
# implementor row can exist under it. Any other failure is a FAIL, not a pass.
refuses(){
    if "$BIN" "$FIX" --no-cache --lego="$1" >"$DIR/ref.out" 2>"$DIR/ref.err"
    then
        return 1
    fi
    grep -q -- "--lego type not found: $1" "$DIR/ref.err"
}
# runq VAR ARGS… — run the binary into VAR in THIS shell and FAIL a non-zero exit on its own line. An absence arm reads
# a crashed run's empty stdout exactly like "no edge", so it runs only when this returns 0.
runq(){
    local var="$1"; shift
    if ! "$BIN" "$@" >"$DIR/runq.out" 2>"$DIR/runq.err"
    then
        no "ripwire ${*#"$DIR/"} exited non-zero: $( head -3 "$DIR/runq.err" )"
        printf -v "$var" '%s' ''
        return 1
    fi
    printf -v "$var" '%s' "$( cat "$DIR/runq.out" )"
}

echo "=== the fixture parsed the way this gate assumes ==="
for want in 'n="Parent"' 'n="Child"' 'n="GrandChild"' 'n="Base" sc="Space"' 'n="Derived"' 'n="Unrelated"'; do
    grep -q "$want" "$SPLIT" && ok "indexed: $want" \
        || no "the fixture did not index $want"
done

echo "=== a Ruby subclass is an IMPLEMENTOR in the lego view ==="
LP="$( lego Parent )"
echo "$LP" | grep -q '<impl n="Child"' && ok "--lego=Parent lists Child" \
    || no "--lego=Parent lists no Child: $( echo "$LP" | grep -E '^<(iface|impl)' | tr '\n' ' ' )"
LC="$( lego Child )"
echo "$LC" | grep -q '<impl n="GrandChild"' && ok "--lego=Child lists GrandChild (a second level is its own direct edge)" \
    || no "--lego=Child lists no GrandChild: $( echo "$LC" | grep -E '^<(iface|impl)' | tr '\n' ' ' )"
LB="$( lego h.rb:Base )"
echo "$LB" | grep -q '<impl n="Derived"' && ok "--lego=h.rb:Base lists Derived (a scope_resolution base, found by its final segment and scoped to Space::Base)" \
    || no "--lego=h.rb:Base lists no Derived: $( echo "$LB" | grep -E '^<(iface|impl)' | tr '\n' ' ' )"

echo "=== the base walk reaches a method the receiver's own class does not define ==="
CI="$( rowOf 'n="call_inherited" ' )"
[ "$( edgesTo "$CI" build )" -eq 1 ] && ok "Child.build → exactly one edge named build (Parent::build through the base walk)" \
    || no "Child.build produced $( edgesTo "$CI" build ) build edges: $CI"
CLP="$( "$BIN" "$FIX" --no-cache --callers=Parent::build 2>/dev/null )"
echo "$CLP" | grep -q 'n="call_inherited"' && ok "--callers=Parent::build lists call_inherited" \
    || no "--callers=Parent::build does not list call_inherited"
if runq CLU "$FIX" --no-cache --callers=Unrelated::build
then
    echo "$CLU" | grep -q 'n="call_inherited"' && no "--callers=Unrelated::build lists call_inherited — the walk took an unrelated same-named def" \
        || ok "--callers=Unrelated::build does not list call_inherited"
fi

CT="$( rowOf 'n="call_two_levels" ' )"
[ "$( edgesTo "$CT" build )" -eq 1 ] && ok "GrandChild.build → exactly one edge (the walk crosses TWO levels)" \
    || no "GrandChild.build produced $( edgesTo "$CT" build ) build edges: $CT"
CS="$( rowOf 'n="call_scoped_base" ' )"
[ "$( edgesTo "$CS" make )" -eq 1 ] && ok "Derived.make → exactly one edge (base written as Space::Base)" \
    || no "Derived.make produced $( edgesTo "$CS" make ) make edges: $CS"
CLM="$( "$BIN" "$FIX" --no-cache --callers=Base::make 2>/dev/null )"
echo "$CLM" | grep -q 'n="call_scoped_base"' && ok "--callers=Base::make lists call_scoped_base" \
    || no "--callers=Base::make does not list call_scoped_base"

echo "=== an implicit-self call inside a subclass reaches the superclass method (Rule 1's bare arm) ==="
UI="$( rowOf 'n="use_inherited" ' )"
[ "$( edgesTo "$UI" shared_helper )" -eq 1 ] && ok "a bare shared_helper inside Child → exactly one edge (Parent#shared_helper)" \
    || no "a bare shared_helper inside Child produced $( edgesTo "$UI" shared_helper ) edges: $UI"
CLS="$( "$BIN" "$FIX" --no-cache --callers=Parent::shared_helper 2>/dev/null )"
echo "$CLS" | grep -q 'n="use_inherited"' && ok "--callers=Parent::shared_helper lists use_inherited" \
    || no "--callers=Parent::shared_helper does not list use_inherited"

# Parser version 130 (test/rubybarecallcheck.sh) mints the bare, parenthesis-less call this arm once pinned as minting
# nothing; it now takes the same base walk as the parenthesised shared_helper( 1 ) above.
UB="$( rowOf 'n="use_bare" ' )"
[ "$( edgesTo "$UB" bare_helper )" -eq 1 ] && ok "a bare, parenthesis-less bare_helper inside Child → exactly one edge (Parent#bare_helper, the base walk)" \
    || no "a bare, parenthesis-less bare_helper inside Child produced $( edgesTo "$UB" bare_helper ) edges, want 1 (Parent#bare_helper): $UB"

echo "=== floors (a) computed base, (b) mixins ==="
refuses Struct && ok "a computed superclass mints no edge: the tree indexes no Struct, so --lego=Struct refuses (floor (a), stated)" \
    || no "--lego=Struct did not refuse with type-not-found — something now indexes a Struct, so this arm must look for <impl n=\"Dynamic\"> instead: $( head -3 "$DIR/ref.err" )"
if runq LF "$FIX" --no-cache --lego=Factory
then
    echo "$LF" | grep -q '<impl n="Built"' \
        && no "class Built < Factory.fabricate( :x ) lists Built as a Factory implementor — a computed superclass's RECEIVER is not its base (floor (a))" \
        || ok "a computed superclass mints no edge to its receiver either: --lego=Factory lists no Built (floor (a))"
fi
if runq LH "$FIX" --no-cache --lego=Helper
then
    # INVERTED (lane lego-transitive): the decision this arm demanded be stated was taken — captureRubyMixinBases' header,
    # graph.h's implementors builder and CHANGELOG.md say so. A mixin is now an implementor row as well as an ancestor.
    if echo "$LH" | grep -q '<impl n="Mixed"'; then ok "include Helper lists Mixed as a --lego implementor (floor (b) closed)"; else no "include Helper lists no Mixed under --lego=Helper — the module implementor row is gone: $( echo "$LH" | grep -oE '<(iface|impl) [^>]*>' | tr '\n' ' ' )"; fi
fi
CM="$( rowOf 'n="call_mixin" ' )"
echo "$CM" | grep -q '<c n="helped"' && ok "…and Mixed.new.helped still edges the one helped def through the name ladder (a floor deletes nothing)" \
    || no "Mixed.new.helped lost its edge: $CM"
refuses ActiveRecord::Base && ok "--lego=ActiveRecord::Base finds no type: the tree never opens ActiveRecord::Base, so there is no row to list under" \
    || no "--lego=ActiveRecord::Base did not refuse with type-not-found: $( head -3 "$DIR/ref.err" )"

echo "=== floor (c): a base is SCOPED — the superclass as written, looked up the way Ruby looks it up ==="
# implOf SELECTOR NAME — 0 when `--lego=SELECTOR` lists NAME as an implementor, 1 when it does not, and a FAIL (2) when
# the run itself failed: an absence arm must never read a crashed run as "not listed".
implOf(){
    if ! "$BIN" "$FIX" --no-cache --lego="$1" >"$DIR/impl.out" 2>"$DIR/impl.err"
    then
        no "--lego=$1 exited non-zero: $( head -3 "$DIR/impl.err" )"
        return 2
    fi
    sed 's/></>\n</g' "$DIR/impl.out" | grep -q "<impl n=\"$2\""
}
# lists SELECTOR NAME WHY / notLists SELECTOR NAME WHY
lists(){    implOf "$1" "$2"; case $? in 0) ok "--lego=$1 lists $2 ($3)";; 1) no "--lego=$1 does not list $2 ($3)";; esac; }
notLists(){ implOf "$1" "$2"; case $? in 1) ok "--lego=$1 does not list $2 ($3)";; 0) no "--lego=$1 lists $2 — $3";; esac; }

notLists h.rb:Base     Rec       "class Rec < ActiveRecord::Base names a constant the tree never opens; the final-segment collision with Space::Base is gone"
notLists alpha.rb:Base Rec       "the out-of-tree base lands on no in-tree Base at all"
notLists beta.rb:Base  Rec       "the out-of-tree base lands on no in-tree Base at all"
lists    alpha.rb:Base UsesAlpha "class UsesAlpha < Alpha::Base lands on Alpha::Base"
notLists h.rb:Base     UsesAlpha "Alpha::Base is not Space::Base"
notLists beta.rb:Base  UsesAlpha "Alpha::Base is not Beta::Base"
lists    beta.rb:Base  Inner     "class Inner < Base inside module Beta is Beta::Base — Module.nesting first"
notLists h.rb:Base     Inner     "the lexical Beta::Base shadows every other Base"
notLists alpha.rb:Base Inner     "the lexical Beta::Base shadows every other Base"
notLists alpha.rb:Base Derived   "class Derived < Space::Base names Space::Base alone"
notLists beta.rb:Base  Derived   "class Derived < Space::Base names Space::Base alone"
lists    Parent        Abs       "class Abs < ::Parent — an absolute constant skips the nesting"
lists    errs.rb:Base  Oops      "class Oops < Base inside module Errs is the body-less Errs::Base — found by constant, not through byName's decl/def collapse"
notLists h.rb:Base     Oops      "Errs::Base is not Space::Base, though only Space::Base has a body"
lists    Outer         FromWrapper "class Outer holds only a nested class: a namespace WRAPPER is no definer in the #57 index, but it is still a class a base can name"

echo "=== a reopened class is ONE implementor; Class.new( Parent ) is floor (d) ==="
if runq LRP "$FIX" --no-cache --lego=Parent
then
    LRS="$( echo "$LRP" | sed 's/></>\n</g' )"
    NR="$( echo "$LRS" | grep -c '<impl n="Reop"' )"
    [ "$NR" -eq 1 ] && ok "--lego=Parent lists Reop once, though reopen.rb opens it twice with the superclass repeated" \
        || no "--lego=Parent lists Reop $NR times — two opens of ONE constant are one implementor"
    # lane lego-transitive: --lego now also lists the classes BELOW a direct one (GrandChild < Child < Parent) as rows that carry
    # via=/depth=, counted by transitive=, not implementors=. The invariant this arm pins is unchanged — implementors= counts
    # the DISTINCT DIRECT classes — so the direct rows are the ones counted; the deeper rows are checked against transitive=.
    NI="$( echo "$LRS" | grep '^<impl n=' | grep -v ' via="' | grep -o '^<impl n="[^"]*"' | sort -u | grep -c . )"
    NT="$( echo "$LRS" | grep '^<impl n=' | grep ' via="' | grep -o '^<impl n="[^"]*"' | sort -u | grep -c . )"
    AT="$( echo "$LRS" | grep -o 'transitive="[0-9]*"' | head -1 | tr -dc '0-9' )"
    if [ "$NT" = "${AT:-0}" ]; then ok "--lego=Parent's transitive=\"${AT:-0}\" counts its $NT distinct deeper classes"; else no "--lego=Parent says transitive=\"${AT:-absent}\" for $NT distinct deeper classes"; fi
    NA="$( echo "$LRS" | grep -o 'implementors="[0-9]*"' | head -1 | tr -dc '0-9' )"
    [ "$NI" = "$NA" ] && ok "--lego=Parent's implementors=\"$NA\" counts its $NI distinct classes" \
        || no "--lego=Parent says implementors=\"$NA\" for $NI distinct classes"
fi
notLists Parent Built2 "Built2 = Class.new( Parent ) is a constant assignment whose value is a call — no class open, no edge (floor (d), stated)"
notLists Parent Blocky "Blocky = Class.new( Parent ) do … end is the same assignment with a block (floor (d), stated)"

echo "=== floor (c): the base WALK — an out-of-tree base walks nowhere; a call on a class walks fully-qualified constants ==="
CO="$( rowOf 'n="call_out_of_tree_base" ' )"
# since parser version 137 a call on a class reads the class object's lookup (test/rubyclassrecvcheck.sh): Rec's leaves the
# tree at ActiveRecord::Base, so the call is refused as external — once an honest split over Space::Base.make and Unrelated.make
# An absence arm must fail on a missing row: an empty rowOf counts zero edges, which alone would read as a PASS.
if [ -z "$CO" ]
then
    no "the call_out_of_tree_base row is missing from the map — the zero-edge check below would pass on nothing"
elif [ "$( edgesTo "$CO" make )" -eq 0 ]
then
    ok "Rec.make has no edge: ActiveRecord::Base is not Space::Base, so the walk no longer pins it, and the lookup leaves the tree"
else
    no "Rec.make produced $( edgesTo "$CO" make ) make edges (want 0 — the out-of-tree base must not walk into Space::Base, nor the call reach a namesake): $CO"
fi
CA="$( rowOf 'n="call_alpha" ' )"
[ "$( edgesTo "$CA" alpha_make )" -eq 1 ] && ok "UsesAlpha.alpha_make → exactly one edge (the walk reaches Alpha::Base)" \
    || no "UsesAlpha.alpha_make produced $( edgesTo "$CA" alpha_make ) edges: $CA"
CB="$( rowOf 'n="call_beta_through_alpha" ' )"
if [ -z "$CB" ]
then
    no "the call_beta_through_alpha row is missing from the map — the zero-edge check below would pass on nothing"
elif [ "$( edgesTo "$CB" beta_make )" -eq 0 ]
then
    ok "UsesAlpha.beta_make has no edge — a call on a class walks fully-qualified constants (parser version 137), and Alpha::Base defines no beta_make"
else
    no "UsesAlpha.beta_make produced $( edgesTo "$CB" beta_make ) edges: Beta::Base#beta_make is no method of UsesAlpha < Alpha::Base"
fi

echo "=== determinism, warm == cold, and --deps is untouched ==="
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

echo "=== mutation: drop the base clause → the inherited pin must vanish ==="
MUT="$DIR/mut"; mkdir -p "$MUT"; cp "$FIX/caller.rb" "$MUT/caller.rb"
sed 's/^class Child < Parent$/class Child/' "$FIX/h.rb" >"$MUT/h.rb"
grep -q '^class Child$' "$MUT/h.rb" || no "mutation did not apply"
if runq MLP "$MUT" --no-cache --lego=Parent
then
    echo "$MLP" | grep -q '<impl n="Child"' && no "mutation: --lego=Parent still lists Child after the base clause was removed" \
        || ok "mutation: Child is no longer an implementor of Parent"
fi
MQ="$( "$BIN" "$MUT" --no-cache 2>/dev/null | sed 's/></>\n</g' | awk '/n="call_inherited" /{f=1;print;next} /^<s /{f=0} f' )"
# with no base clause Child's lookup defines no build, so the call on the class is refused as external (parser version 137,
# test/rubyclassrecvcheck.sh) — the pin was the inheritance edge and nothing else
if [ "$( echo "$MQ" | grep -c '<c n="build"' )" -eq 0 ]
then
    ok "mutation: Child.build has no edge — the pin was the inheritance edge and nothing else"
else
    no "mutation: Child.build produced $( echo "$MQ" | grep -c '<c n="build"' ) build edges with no base clause: $MQ"
fi
MCU="$( "$BIN" "$MUT" --no-cache --callers=Unrelated::build 2>/dev/null )"
if echo "$MCU" | grep -q 'n="call_inherited"'
then
    no "mutation: Unrelated::build lists call_inherited — a class whose lookup leaves the tree bound to a namesake"
else
    ok "mutation: …and Unrelated::build is not among its callers either"
fi

echo "=== #325 disclosure: a base left on the final-segment rule is counted as ruby_bases_unscoped= ==="
# resolve.h's fallback — an inherit reference with no superclass directive at its class open keeps the byName rule —
# is defensive: no well-formed input is known to reach it (every class open with a superclass records its directive at
# that open). The test seam RIPWIRE_TEST_RUBY_BASE_UNSCOPED=1 (resolve.h rubyBaseUnscopedTestSeam) drops every
# directive from the join, so every Ruby inherit reference in the fixture takes the fallback and is counted.
if runq PLAIN "$FIX" --no-cache --lego=Parent
then
    echo "$PLAIN" | grep -q 'ruby_bases_unscoped' \
        && no "absence: --lego=Parent carries ruby_bases_unscoped= on a tree where every Ruby base was scoped" \
        || ok "absence: no ruby_bases_unscoped= on --lego=Parent when every Ruby base was scoped (absent at zero)"
fi
# The expected count: every `class X < Const` in the fixture (a computed superclass mints no inherit reference) and,
# since parser version 131, every constant of a class-body `include`/`extend`/`prepend` — a mixin is an ancestor too
# (ingest_relations.h captureRubyMixinBases), so the seam drops its directive from the join as well.
SUPERS="$( cat "$FIX"/*.rb | grep -cE '^[[:space:]]*class [A-Z][A-Za-z0-9_:]* < (::)?[A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)*[[:space:]]*(;|#|$)' )"
MIXINS="$( cat "$FIX"/*.rb | grep -E '^[[:space:]]+(include|extend|prepend) ' | grep -oE '(::)?[A-Z][A-Za-z0-9_]*(::[A-Z][A-Za-z0-9_]*)*' | grep -c . )"
WANT=$(( SUPERS + MIXINS ))
if RIPWIRE_TEST_RUBY_BASE_UNSCOPED=1 runq SEAMED "$FIX" --no-cache --lego=Parent --legend=full
then
    echo "$SEAMED" | grep -q " ruby_bases_unscoped=\"$WANT\"" \
        && ok "seam: --lego=Parent carries ruby_bases_unscoped=\"$WANT\" (one per Ruby inherit reference in the fixture)" \
        || no "seam: --lego=Parent lacks ruby_bases_unscoped=\"$WANT\": $( echo "$SEAMED" | grep -o '<lego [^>]*' )"
    echo "$SEAMED" | grep -q 'ruby_bases_unscoped=N (absent when zero' \
        && ok "seam: the full lego legend (--legend=full) defines ruby_bases_unscoped=" \
        || no "seam: the attribute rides --lego with no definition in its legend"
    echo "$SEAMED" | sed 's/></>\n</g' | grep -q '<impl n="Child"' \
        && ok "seam: the fallback keeps the byName answer (Child is still an implementor of Parent)" \
        || no "seam: the byName fallback lost Child"
fi
if RIPWIRE_TEST_RUBY_BASE_UNSCOPED=1 runq SEAMC "$FIX" --no-cache --lego=Parent --legend=compact
then
    echo "$SEAMC" | grep -q 'ruby_bases_unscoped=N:' \
        && ok "seam: the compact legend defines ruby_bases_unscoped=" \
        || no "seam: --legend=compact carries ruby_bases_unscoped= with no row defining it"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
