#!/usr/bin/env bash
# rubyscopecheck.sh — gate for Ruby definition SCOPE (the enclosing class/module recorded on every Ruby def).
#
# Before the fix, src/ingest_sidecap.h set d.scope only for C++, Python and Rust. A Ruby def therefore never
# carried a scope, which had three visible consequences, all asserted here from the OUTSIDE:
#   1. no Ruby row ever carried an id= (canonical path::scope::name), so `Scope::name` selectors could not
#      address a Ruby method — `--expand=B::initialize` matched nothing;
#   2. same-named methods in DIFFERENT classes of one file folded into one row with overloads=N (on
#      ActiveSupport 7.2: as_json overloads="26", initialize overloads="13" — unrelated methods, not overloads);
#   3. editcheck.h's editCheckImplicitReceiver claimed Ruby records the enclosing class and keyed on it — the
#      branch was dead, so a Ruby method's implicit receiver was never recognised.
#
# Shapes pinned (each read off a real parse of the fixture, not predicted from the grammar):
#   - `def m` inside `class A`            → scope "A"        (method → body_statement → class)
#   - `def self.m` inside a class         → scope "Widget"   (singleton_method → body_statement → class)
#   - `def m` inside `class << self`      → scope "Widget"   (singleton_class has no name field: walk THROUGH it)
#   - `class Widget` inside `module Outer`→ scope "Outer"    (the class's OWN node is skipped — a def's scope is
#                                                             what ENCLOSES it, never itself)
#   - `class Foo::Bar` then `def deep`    → scope "Bar"      (scope_resolution: the IMMEDIATE scope is the last
#                                                             segment, matching C++'s qualifierOf contract)
#   - top-level `def toplevel`            → NO scope, NO id= (unchanged: the file is not a scope)
#   - Python control: `t.py::B::__init__` keeps its id (the Python arm is untouched)
#
# Usage:  test/rubyscopecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubyscopecheck.sh
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

cat > "$FIX/t.rb" <<'RUBY'
def toplevel
  1
end

class A
  def initialize(x)
    @x = x
  end

  def run
    go(1)
  end
end

class B
  def initialize(x, y)
    @x = x
  end

  def go(n)
    n
  end
end

module Outer
  class Widget
    def self.build(n)
      new(n)
    end

    class << self
      def registry
        []
      end
    end
  end
end

class Foo::Bar
  def deep
    2
  end
end
RUBY

cat > "$FIX/t.py" <<'PY'
class B:
    def __init__(self, x, y):
        self.x = x
PY

MAP="$DIR/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
if [ $? -eq 0 ]; then ok "default map exits 0"; else no "default map exited non-zero: $( cat "$DIR/map.err" )"; fi
[ -s "$DIR/map.err" ] && no "unexpected stderr: $( head -3 "$DIR/map.err" )" || ok "clean stderr"
command -v xmllint >/dev/null 2>&1 && { if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi; }

ROWS="$DIR/rows"
sed 's/></>\n</g' "$MAP" | grep '^<s ' >"$ROWS"

hasId(){ # $1=id $2=label
  if grep -q "id=\"$1\"" "$ROWS"; then ok "$2 → id=\"$1\""; else no "$2 → id=\"$1\" MISSING: $( grep -o "n=\"${1##*::}\"[^>]*" "$ROWS" | head -2 | tr '\n' ' ' )"; fi
}

echo "=== ids: every Ruby def inside a class/module carries path::scope::name ==="
hasId "t.rb::A::initialize"  "def initialize inside class A"
hasId "t.rb::B::initialize"  "def initialize inside class B"
hasId "t.rb::B::go"          "def go inside class B"
hasId "t.rb::Widget::build"  "def self.build inside class Widget (singleton_method)"
hasId "t.rb::Widget::registry" "def registry inside class << self (walks through singleton_class)"
hasId "t.rb::Outer::Widget"  "class Widget inside module Outer (a class's scope is what ENCLOSES it)"
hasId "t.rb::Bar::deep"      "def deep inside class Foo::Bar (immediate scope = last segment)"
hasId "t.py::B::__init__"    "Python control: __init__ inside class B (unchanged)"

echo "=== negative controls ==="
TOP="$( grep 'n="toplevel"' "$ROWS" )"
if [ -n "$TOP" ]; then ok "top-level def toplevel indexed"; else no "top-level def toplevel missing"; fi
echo "$TOP" | grep -q ' id="' && no "top-level def carries an id= (the file is not a scope): $TOP" || ok "top-level def carries NO id= (no scope)"
grep -q 'n="Outer" id=' "$ROWS" && no "top-level module Outer carries an id= (nothing encloses it)" || ok "top-level module Outer carries NO id="

echo "=== overload folding: same name in DIFFERENT classes must stay separate rows ==="
N_INIT="$( grep -c 'n="initialize"' "$ROWS" )"
if [ "$N_INIT" -eq 2 ]; then ok "two initialize rows (one per class)"; else no "expected 2 initialize rows, got $N_INIT"; fi
grep 'n="initialize"' "$ROWS" | grep -q 'overloads=' && no "initialize rows folded as overloads across classes" || ok "no overloads= on initialize (different scopes are different symbols)"

echo "=== Scope::name selector addresses ONE Ruby method ==="
EXP="$( "$BIN" "$FIX" --no-cache --top-k=0 --expand=B::initialize 2>/dev/null | sed 's/></>\n</g' )"
NB="$( echo "$EXP" | grep -c '^<b ' )"
if [ "$NB" -eq 1 ]; then ok "--expand=B::initialize returns exactly one body"; else no "--expand=B::initialize returned $NB bodies"; fi
if echo "$EXP" | grep -q '^<b [^>]*l="16"'; then ok "…and it is B's initialize (line 16), not A's (line 6)"; else no "expanded body is not B's initialize: $( echo "$EXP" | grep '^<b ' )"; fi

echo "=== resolution: scope must never LOSE an edge the bare-name spray used to find ==="
# Delegation under the caller's own name — `def publish_event; notifier.publish_event(e); end` — is how Ruby
# spells a facade, and a core_ext file defines the same method on class after class (ActiveSupport 7.2's
# core_ext/object/json.rb: 26 `as_json`). Before scope those same-file defs FOLDED into one node, so the call
# was a self-loop and produced nothing. With scope they are separate candidates in the same-file tier — and
# the S6-C locality tie-break then scored the caller's OWN def as a full match against itself, kept it alone,
# and emission dropped it as a self-loop: still nothing, now for a different reason (measured RED on this
# fixture: edges=0). The caller must never be its own tie-break winner; with it scored zero the two real
# targets tie, survive, and the site is an honest 2-way split.
DEL="$DIR/deleg"; mkdir -p "$DEL"
cat > "$DEL/n.rb" <<'RUBY'
class Facade
  def publish_event(event)
    notifier.publish_event(event)
  end
end

class Fanout
  def publish_event(event)
    1
  end
end

class Subscriber
  def publish_event(event)
    2
  end
end
RUBY
DMAP="$( "$BIN" "$DEL" --no-cache 2>/dev/null | sed 's/></>\n</g' )"
DEDGES="$( echo "$DMAP" | grep -o '<!-- files=[^>]*edges=[0-9]*' | grep -o 'edges=[0-9]*' | cut -d= -f2 )"
if [ "${DEDGES:-0}" -eq 2 ]; then ok "facade delegation keeps both real targets (edges=2)"; else no "facade delegation: expected edges=2, got ${DEDGES:-0} — the caller won its own locality tie-break?"; fi
FAC="$( echo "$DMAP" | awk '/id="n.rb::Facade::publish_event"/{f=1;print;next} /^<s /{f=0} f' )"
if [ "$( echo "$FAC" | grep -c '<c n="publish_event"' )" -eq 2 ]; then ok "Facade::publish_event → two publish_event callee rows (Fanout, Subscriber)"; else no "Facade::publish_event callee rows: $( echo "$FAC" | grep -c '<c n="publish_event"' )"; fi
if echo "$FAC" | grep -q 'amb="1"'; then ok "…disclosed as an honest split (amb=\"1\"), not a locality guess"; else no "Facade::publish_event is not marked amb=\"1\": $( echo "$FAC" | head -1 )"; fi
echo "$FAC" | grep -q 'lpin=' && no "Facade::publish_event carries lpin= — the tie-break picked ONE target from a two-way tie" || ok "…and no lpin= (a two-way tie is left a tie)"

echo "=== resolution: an explicit self receiver / a bare paren call inside a class pins to THAT class (Rule 1) ==="
R1="$DIR/rule1"; mkdir -p "$R1"
cat > "$R1/r.rb" <<'RUBY'
class A
  def go
    self.helper(1)
  end

  def go_bare
    helper(2)
  end

  def helper(n)
    n
  end
end

class B
  def helper(n)
    n * 2
  end
end
RUBY
RMAP="$( "$BIN" "$R1" --no-cache 2>/dev/null | sed 's/></>\n</g' )"
GO="$( echo "$RMAP" | awk '/id="r.rb::A::go"/{f=1;print;next} /^<s /{f=0} f' )"
echo "$GO" | grep -q 'amb=' && no "self.helper(1) inside A stayed ambiguous: $( echo "$GO" | head -1 )" || ok "self.helper(1) inside A is not ambiguous (Rule 1: ThisObj receiver)"
if [ "$( echo "$GO" | grep -c '<c n="helper"' )" -eq 1 ]; then ok "…and resolves to exactly one helper"; else no "self.helper resolved to $( echo "$GO" | grep -c '<c n="helper"' ) helpers"; fi
echo "$GO" | grep -q 'lpin=' && no "self.helper(1) was pinned by the LOCALITY prior (lpin=), not by Rule 1 — a disclosed guess where a fact exists" || ok "…pinned as a fact (no lpin=), not by the locality prior"
GB="$( echo "$RMAP" | awk '/id="r.rb::A::go_bare"/{f=1;print;next} /^<s /{f=0} f' )"
echo "$GB" | grep -q 'amb=' && no "bare helper(2) inside A stayed ambiguous: $( echo "$GB" | head -1 )" || ok "bare helper(2) inside A is not ambiguous (Rule 1: implicit self)"
if [ "$( echo "$GB" | grep -c '<c n="helper"' )" -eq 1 ]; then ok "…and resolves to exactly one helper"; else no "bare helper(2) resolved to $( echo "$GB" | grep -c '<c n="helper"' ) helpers"; fi
echo "$GB" | grep -q 'lpin=' && no "bare helper(2) was pinned by the LOCALITY prior (lpin=), not by Rule 1" || ok "…pinned as a fact (no lpin=), not by the locality prior"
if "$BIN" "$R1" --no-cache --callers=A::helper 2>/dev/null | grep -q 'count="2"'; then ok "--callers=A::helper counts go + go_bare (count=2)"; else no "--callers=A::helper did not report count=2: $( "$BIN" "$R1" --no-cache --callers=A::helper 2>/dev/null | grep -o '<callers[^>]*' )"; fi
if "$BIN" "$R1" --no-cache --callers=B::helper 2>/dev/null | grep -q 'count="0"'; then ok "--callers=B::helper is empty (nothing in A reaches B)"; else no "--callers=B::helper is not empty: $( "$BIN" "$R1" --no-cache --callers=B::helper 2>/dev/null | grep -o '<callers[^>]*' )"; fi

echo "=== determinism ==="
"$BIN" "$FIX" --no-cache >"$DIR/b.xml" 2>/dev/null
if cmp -s "$MAP" "$DIR/b.xml"; then ok "byte-identical across two runs"; else no "output differs across runs"; fi

echo "=== mutation: hoist B's initialize to top level → its id must vanish (non-tautological) ==="
MUT="$DIR/mut"; mkdir -p "$MUT"
python3 - "$FIX/t.rb" "$MUT/t.rb" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()
body = "  def initialize(x, y)\n    @x = x\n  end\n\n"
assert body in src
src = src.replace(body, "")
src += "\ndef initialize(x, y)\n  @x = x\nend\n"
open(sys.argv[2], "w").write(src)
PYEOF
"$BIN" "$MUT" --no-cache 2>/dev/null | sed 's/></>\n</g' | grep -q 'id="t.rb::B::initialize"' \
  && no "mutation: B::initialize id survived hoisting the def out of class B" \
  || ok "mutation: hoisted def lost its B:: id"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
