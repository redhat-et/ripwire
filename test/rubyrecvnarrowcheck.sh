#!/usr/bin/env bash
# rubyrecvnarrowcheck.sh — gate for Ruby CONSTANT-RECEIVER call narrowing: `Calc.add(1,2)`,
# `Outer::Engine.run(3)`, `::Top.ping`, `Util.format(5)` resolve to the method defined under THAT
# constant, instead of splitting across every same-named method in the corpus.
#
# What was wrong, and where. resolve.h's Rule 2c (docs/EVALS.md "Phase 4b") already says "the receiver
# token IS the type": a `Cls.m(…)` call whose receiver names a class-like definition resolves against
# that class. It never fired for Ruby, because ingest_binds.h::classifyReceiver accepted a receiver node
# of kind (identifier) only. Ruby's class/module receiver is its OWN node kind — (constant) for `Calc`,
# (scope_resolution) for `Outer::Engine` and `::Top` — so every such call classified RecvKind::None,
# receiverOf then stamped it FieldOfVar with an empty recvVar ("a member access, receiver undecidable"),
# and the resolver fell through to the §2a name spray. Measured before the fix on the four Ruby corpora:
# activerecord 8.1.3 lib = 9,116 edges with ambiguous=1,496 and declined=4,576; a 4,683-file Rails app
# = 23,784 edges with declined=12,485. Constant-receiver call SITES in that same text: 3,176 and 9,499.
#
# The rule, stated so it can be disagreed with:
#   * The receiver's FINAL constant segment is the type name — `Outer::Engine` → `Engine`, `::Top` → `Top`.
#     That is the same final-segment convention Rule 2's type bindings already use (`ns::Foo` → `Foo`),
#     and it meets Symbol::scope, which is the IMMEDIATE enclosing name by design (ingest_sidecap.h).
#   * A (scope_resolution) whose `name:` child is not a (constant) is not a constant receiver at all.
#     `Outer::run(1)` is not that shape — tree-sitter-ruby parses it as an ordinary (call) with receiver
#     (constant) `Outer`, exactly like `Outer.run(1)`, and both narrow through the (constant) arm.
#   * A Ruby MODULE is a receiver of class methods as much as a class is (`Util.format`). `@definition.module`
#     maps to SymKind::Other (ingest_crawl.h::defKind) for every language, and in Ruby that kind is reached
#     by nothing else — queries/ruby/tags.scm emits class, module, method and constant, and the other three
#     have kinds of their own — so buildGraph's Rule 2c class-name set takes Ruby's SymKind::Other symbols.
#   * A receiver naming no in-repo definition (`Time.now`) mints no edge. One naming a class whose lookup does not
#     define the callee degraded to the name ladder through parser version 136; since 137 Ruby's lookup on the class
#     object decides it (test/rubyclassrecvcheck.sh): `Calc.report` reaches no Tally.report and is refused as
#     external. That arm below is kept, INVERTED.
#
# Stated floors, pinned below so each stays a decision rather than an accident:
#   (a) LIFTED at parser version 98 by test/rubyinheritcheck.sh (`class Child < Parent` now mints an
#       inherit ref, so chaUp holds Ruby and the base walk runs). The arm below is kept, INVERTED: it
#       now asserts `Child.build` pins to Parent::build, and it is the tripwire that fires if Ruby ever
#       loses its inheritance edges again.
#   (b) LIFTED at parser version 137 by test/rubyclassrecvcheck.sh: a call on a class reads the constant by its
#       fully-qualified name through the constant index, so `Left::Shared.go` reaches Left's Shared alone where two
#       classes of the last name `Shared` both define `go`. Through 136 that was an honest split; the arm below is kept,
#       INVERTED.
#   (c) A variable receiver (`c.scale`) is untouched by this round. A chained one (`Calc.new.scale`) was too, until
#       parser version 132 typed a receiver the code builds (test/rubytypedrecvcheck.sh); its arm below is kept,
#       INVERTED: it now asserts `Calc.new.scale` pins to Calc::scale alone.
#   (d) A constant receiver whose class defines BOTH `def self.x` and `def x` gets an honest two-way split that
#       includes the instance method (rails `Journey::Parser.parse`): a split, not a pin. Ruby's tags.scm gives
#       `method` and `singleton_method` one kind, so telling them apart is a later round.
#
# Usage:  test/rubyrecvnarrowcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyrecvnarrowcheck.sh
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
FIX="$DIR/fix"; mkdir -p "$FIX"   # the corpus — outputs live in $DIR, never here (the crawl census would count them)

cat > "$FIX/r.rb" <<'RUBY'
class Calc
  def self.add( a, b )
    a + b
  end

  def scale( n )
    n * 2
  end
end

class Tally
  def self.add( a, b )
    a - b
  end

  def self.report
    0
  end

  def scale( n )
    n
  end
end

module Outer
  class Engine
    def self.run( x )
      x
    end
  end
end

module Other
  class Motor
    def self.run( x )
      x
    end
  end
end

class Top
  def self.ping
    1
  end
end

class Radar
  def self.ping
    2
  end
end

module Util
  def self.format( x )
    x
  end
end

class Printer
  def self.format( x )
    x
  end
end

module Left
  class Shared
    def self.go
      1
    end
  end
end

module Right
  class Shared
    def self.go
      2
    end
  end
end

class Parent
  def self.build
    1
  end
end

class Child < Parent
end

class Unrelated
  def self.build
    2
  end
end
RUBY

cat > "$FIX/caller.rb" <<'RUBY'
class Caller
  def qualified_call
    Calc.add( 1, 2 )
  end

  def scoped_call
    Outer::Engine.run( 3 )
  end

  def absolute_call
    ::Top.ping
  end

  def module_call
    Util.format( 5 )
  end

  def colon_call
    Util::format( 6 )
  end

  def external_call
    Time.now
  end

  def inherited_call
    Child.build
  end

  def missing_method_call
    Calc.report
  end

  def same_segment_call
    Left::Shared.go
  end

  def instance_call( c )
    c.scale( 7 )
  end

  def chain_call
    Calc.new.scale( 8 )
  end
end
RUBY

MAP="$DIR/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
if [ $? -eq 0 ]; then ok "default map exits 0"; else no "default map exited non-zero: $( cat "$DIR/map.err" )"; fi
[ -s "$DIR/map.err" ] && no "unexpected stderr: $( head -3 "$DIR/map.err" )" || ok "clean stderr"
command -v xmllint >/dev/null 2>&1 && { if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi; }

SPLIT="$DIR/split"; sed 's/></>\n</g' "$MAP" >"$SPLIT"
rowOf(){ awk -v pat="$1" '$0 ~ pat{f=1;print;next} /^<s /{f=0} f' "$SPLIT"; }   # an <s> row + its <c> children
edgesTo(){ echo "$1" | grep -c "<c n=\"$2\""; }                                  # how many <c> rows of that name
# An ABSENCE arm on a --callers answer: read only off a run that succeeded and produced its <callers> root. A crash or a
# refusal leaves the capture empty, and a bare `grep -q ROW && no || ok` reads that as a PASS (checklist 14).
#   callersLacks DIR SYMBOL ROW-PATTERN FAIL-MESSAGE PASS-MESSAGE
callersLacks(){
    local out
    if ! out="$( "$BIN" "$1" --no-cache --callers="$2" 2>"$DIR/absent.err" )"; then
        no "--callers=$2 exited non-zero, so its absence arm proves nothing: $( head -3 "$DIR/absent.err" )"; return
    fi
    case "$out" in
        *'<callers'*) ;;
        *) no "--callers=$2 produced no <callers> root, so its absence arm proves nothing"; return ;;
    esac
    if echo "$out" | grep -q "$3"; then no "$4"; else ok "$5"; fi
}
# how many <c> edges of that name; FE-B: a merged via="name" row <c … x="N"/> stands for N edges (serialize.h writeMapCalleeRows)
edgesTo(){ echo "$1" | grep -o "<c n=\"$2\"[^>]*>" | awk '{ n = 1; if ( match( $0, / x="[0-9]+"/ ) ) n = substr( $0, RSTART + 4, RLENGTH - 5 ) + 0; s += n } END { print s + 0 }'; }

echo "=== the fixture parsed the way this gate assumes ==="
for want in 'n="add" sc="Calc"' 'n="add" sc="Tally"' 'n="run" sc="Engine"' 'n="run" sc="Motor"' \
            'n="ping" sc="Top"' 'n="ping" sc="Radar"' 'n="format" sc="Util"' 'n="format" sc="Printer"' \
            'n="go" sc="Shared"' 'n="build" sc="Parent"' 'n="build" sc="Unrelated"'; do
    grep -q "$want" "$SPLIT" && ok "indexed: $want" \
        || no "the fixture did not index $want — this gate's arms below are meaningless until it does"
done
grep -q 'n="go" sc="Shared" overloads="2"' "$SPLIT" \
    && ok "Left::Shared::go and Right::Shared::go both carry sc=\"Shared\" and merge into one overloads=\"2\" row (the final-segment collision floor (b) is real)" \
    || no "expected one n=\"go\" sc=\"Shared\" overloads=\"2\" row: $( grep 'n="go"' "$SPLIT" | head -2 | tr '\n' ' ' )"

echo "=== a CONSTANT receiver pins the call to that constant's method ==="
Q="$( rowOf 'n="qualified_call" ' )"
[ "$( edgesTo "$Q" add )" -eq 1 ] && ok "Calc.add( 1, 2 ) → exactly one edge named add" \
    || no "Calc.add( 1, 2 ) produced $( edgesTo "$Q" add ) add edges — the constant receiver did not narrow: $Q"
echo "$Q" | grep -q 'prov="split"' && no "qualified_call still carries prov=\"split\" — the receiver was not read" || ok "…with no prov=\"split\" on it"
echo "$Q" | grep -q 'amb=' && no "qualified_call still carries amb= — the call stayed ambiguous" || ok "…and no amb= on the row"

CL="$( "$BIN" "$FIX" --no-cache --callers=Calc::add 2>/dev/null )"
echo "$CL" | grep -q 'n="qualified_call"' && ok "--callers=Calc::add lists qualified_call" \
    || no "--callers=Calc::add does not list qualified_call: $( echo "$CL" | grep -o '<callers[^>]*' )"
CT="$( "$BIN" "$FIX" --no-cache --callers=Tally::add 2>/dev/null )"
callersLacks "$FIX" Tally::add 'n="qualified_call"' "--callers=Tally::add STILL lists qualified_call — the wrong half of the split survived" "--callers=Tally::add does not list qualified_call"
echo "$CT" | grep -q 'count="0"' && ok "…and reports count=\"0\" (Tally::add has no caller in this tree)" \
    || no "--callers=Tally::add did not report count=0: $( echo "$CT" | grep -o '<callers[^>]*' )"

echo "=== a SCOPE_RESOLUTION receiver pins by its FINAL segment ==="
S="$( rowOf 'n="scoped_call" ' )"
[ "$( edgesTo "$S" run )" -eq 1 ] && ok "Outer::Engine.run( 3 ) → exactly one edge named run" \
    || no "Outer::Engine.run( 3 ) produced $( edgesTo "$S" run ) run edges: $S"
CE="$( "$BIN" "$FIX" --no-cache --callers=Engine::run 2>/dev/null )"
echo "$CE" | grep -q 'n="scoped_call"' && ok "--callers=Engine::run lists scoped_call" \
    || no "--callers=Engine::run does not list scoped_call"
callersLacks "$FIX" Motor::run 'n="scoped_call"' "--callers=Motor::run lists scoped_call — Outer::Engine reached Other::Motor" "--callers=Motor::run does not list scoped_call"

A="$( rowOf 'n="absolute_call" ' )"
[ "$( edgesTo "$A" ping )" -eq 1 ] && ok "::Top.ping → exactly one edge named ping (the absolute spelling has no scope: child)" \
    || no "::Top.ping produced $( edgesTo "$A" ping ) ping edges: $A"
CP="$( "$BIN" "$FIX" --no-cache --callers=Top::ping 2>/dev/null )"
echo "$CP" | grep -q 'n="absolute_call"' && ok "--callers=Top::ping lists absolute_call" \
    || no "--callers=Top::ping does not list absolute_call"
callersLacks "$FIX" Radar::ping 'n="absolute_call"' "--callers=Radar::ping lists absolute_call — ::Top reached Radar" "--callers=Radar::ping does not list absolute_call"

echo "=== a MODULE is a receiver too (Util.format, and the :: spelling of the same call) ==="
M="$( rowOf 'n="module_call" ' )"
[ "$( edgesTo "$M" format )" -eq 1 ] && ok "Util.format( 5 ) → exactly one edge named format" \
    || no "Util.format( 5 ) produced $( edgesTo "$M" format ) format edges — a module receiver did not narrow: $M"
C="$( rowOf 'n="colon_call" ' )"
[ "$( edgesTo "$C" format )" -eq 1 ] && ok "Util::format( 6 ) → exactly one edge named format (parsed as an ordinary (call) with a (constant) receiver)" \
    || no "Util::format( 6 ) produced $( edgesTo "$C" format ) format edges: $C"
CU="$( "$BIN" "$FIX" --no-cache --callers=Util::format 2>/dev/null )"
echo "$CU" | grep -q 'count="2"' && ok "--callers=Util::format reports count=\"2\" (module_call and colon_call)" \
    || no "--callers=Util::format did not report count=2: $( echo "$CU" | grep -o '<callers[^>]*' )"
CPR="$( "$BIN" "$FIX" --no-cache --callers=Printer::format 2>/dev/null )"
echo "$CPR" | grep -q 'count="0"' && ok "--callers=Printer::format reports count=\"0\"" \
    || no "--callers=Printer::format did not report count=0: $( echo "$CPR" | grep -o '<callers[^>]*' )"

echo "=== a MISS invents no edge ==="
E="$( rowOf 'n="external_call" ' )"
echo "$E" | grep -q '<c ' && no "Time.now minted an edge — neither Time nor now is defined in this tree: $E" || ok "Time.now → no edge (out-of-tree receiver, unchanged)"
MM="$( rowOf 'n="missing_method_call" ' )"
# An absence arm must fail on a missing row: an empty rowOf counts zero edges, which alone would read as a PASS.
if [ -z "$MM" ]
then
    no "the missing_method_call row is missing from the map — the zero-edge check below would pass on nothing"
elif [ "$( edgesTo "$MM" report )" -eq 0 ]
then
    ok "Calc.report → no edge: Calc's lookup defines no report, and Tally's class method is no method of Calc (parser version 137)"
else
    no "Calc.report bound to a namesake its class's lookup cannot reach: $MM"
fi

echo "=== the base walk: a method on the SUPERCLASS narrows too (floor (a), lifted at parser version 98) ==="
I="$( rowOf 'n="inherited_call" ' )"
[ "$( edgesTo "$I" build )" -eq 1 ] && ok "Child.build → exactly one edge (Parent::build, through the inheritance edge captureBases now mints for Ruby)" \
    || no "Child.build produced $( edgesTo "$I" build ) build edges — if Ruby LOST its inheritance edges, that is the regression: see ingest_relations.h::isBaseTypeNode's Ruby arm and test/rubyinheritcheck.sh: $I"
CB="$( "$BIN" "$FIX" --no-cache --callers=Parent::build 2>/dev/null )"
echo "$CB" | grep -q 'n="inherited_call"' && ok "--callers=Parent::build lists inherited_call" \
    || no "--callers=Parent::build does not list inherited_call"
# An absence arm must fail on a broken run: a crash or refusal leaves CBU empty, which the grep alone reads as a PASS.
if CBU="$( "$BIN" "$FIX" --no-cache --callers=Unrelated::build 2>"$DIR/cbu.err" )"; then
    if echo "$CBU" | grep -q 'n="inherited_call"'; then no "--callers=Unrelated::build lists inherited_call — the walk took an unrelated same-named def"
    else ok "--callers=Unrelated::build does not list inherited_call"; fi
else
    no "--callers=Unrelated::build exited non-zero: $( head -3 "$DIR/cbu.err" )"
fi

echo "=== floor (b), lifted at parser version 137: Left::Shared.go names Left's Shared alone ==="
SS="$( rowOf 'n="same_segment_call" ' )"
# which Shared: the same shape in a fixture of its own, one class per file, read off the census (a constant index needs one
# Ruby superclass in the tree, so it carries one)
SEG="$DIR/segment"; mkdir -p "$SEG"
printf 'module Left\n  class Shared\n    def self.go\n      1\n    end\n  end\nend\n' > "$SEG/left.rb"
printf 'module Right\n  class Shared\n    def self.go\n      2\n    end\n  end\nend\n' > "$SEG/right.rb"
printf 'class Base\nend\n\nclass Caller < Base\n  def run\n    Left::Shared.go\n  end\nend\n' > "$SEG/call.rb"
"$BIN" "$SEG" --no-cache --pin-census="$DIR/segment.tsv" >/dev/null 2>&1
SEGT="$( awk -F'\t' '$1 == "C" && $7 == "go" { print $8 }' "$DIR/segment.tsv" )"
if [ "$( edgesTo "$SS" go )" -eq 1 ] && printf '%s' "$SEGT" | grep -qF "left.rb::Shared::go#" && ! printf '%s' "$SEGT" | grep -qF "right.rb::"
then
    ok "Left::Shared.go → Left's Shared::go alone (one edge here; left.rb's def, not right.rb's, on the one-class-per-file fixture)"
else
    no "Left::Shared.go is not Left's Shared::go alone ($( edgesTo "$SS" go ) go edges here; census on the per-file fixture: $SEGT)"
fi

echo "=== floor (c): a variable receiver is untouched by this round; a chained Calc.new is typed (parser version 132) ==="
IC="$( rowOf 'n="instance_call" ' )"
[ "$( edgesTo "$IC" scale )" -eq 2 ] && ok "c.scale( 7 ) → unchanged 2-way split (a variable receiver has no type in Ruby; floor, stated)" \
    || no "c.scale( 7 ) produced $( edgesTo "$IC" scale ) scale edges — this round must not move a variable receiver: $IC"
CC="$( rowOf 'n="chain_call" ' )"
CCL="$( "$BIN" "$FIX" --no-cache --callers=Calc::scale 2>/dev/null )"; CCL_RC=$?
CTL="$( "$BIN" "$FIX" --no-cache --callers=Tally::scale 2>/dev/null )"; CTL_RC=$?
# The Tally half is an absence: a crash or refusal leaves CTL empty, which `! grep` alone reads as a PASS.
if [ "$CCL_RC" -ne 0 ] || [ "$CTL_RC" -ne 0 ]
then
    no "--callers=Calc::scale / --callers=Tally::scale exited $CCL_RC / $CTL_RC — the absence half cannot be read off a failed run"
elif echo "$CCL" | grep -q 'n="chain_call"' && ! echo "$CTL" | grep -q 'n="chain_call"'
then
    ok "Calc.new.scale( 8 ) → Calc::scale alone (floor (c) lifted: the receiver the code builds is a Calc — test/rubytypedrecvcheck.sh)"
else
    no "Calc.new.scale( 8 ) does not pin to Calc::scale alone: $CC"
fi
echo "$CC" | grep -q '<c n="new"' && no "Calc.new minted an edge to a new this tree never defines" || ok "…and Calc.new mints no edge (no def named new exists here)"

echo "=== determinism, and the warm cache agrees with the cold one ==="
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
    || no "the warm cache disagrees with the cold run — the parser version did not move with the extraction change"

echo "=== mutation: the edge follows the RECEIVER, not the caller's file or its order ==="
MUT="$DIR/mut"; mkdir -p "$MUT"; cp "$FIX/r.rb" "$MUT/r.rb"
sed 's/    Calc\.add( 1, 2 )/    Tally.add( 1, 2 )/' "$FIX/caller.rb" >"$MUT/caller.rb"
grep -q 'Tally.add( 1, 2 )' "$MUT/caller.rb" || no "mutation did not apply"
MQ="$( "$BIN" "$MUT" --no-cache 2>/dev/null | sed 's/></>\n</g' | awk '/n="qualified_call" /{f=1;print;next} /^<s /{f=0} f' )"
MCL="$( "$BIN" "$MUT" --no-cache --callers=Tally::add 2>/dev/null )"
echo "$MCL" | grep -q 'n="qualified_call"' && ok "mutation: Tally.add → --callers=Tally::add now lists qualified_call" \
    || no "mutation: the edge did not follow the receiver: $MQ"
callersLacks "$MUT" Calc::add 'n="qualified_call"' "mutation: --callers=Calc::add still lists qualified_call — the pin is not reading the receiver" "mutation: Calc::add no longer lists it"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
