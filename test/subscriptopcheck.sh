#!/usr/bin/env bash
# subscriptopcheck.sh — gate for SUBSCRIPT = OPERATOR-METHOD CALL (Ruby `recv[ k ]` -> `[]` / `[]=`, Python `obj[ k ]` ->
# `__getitem__` / `__setitem__`) and for Ruby's MAIN OBJECT as a --lego implementor (`<impl t="object" n="main">`).
#
# Before this round an element access was no call at all: rake's Application#invoke_task does `t = self[ name ]`, which runs
# TaskManager#[] (Application includes TaskManager), and --callees=invoke_task listed only parse_task_string and invoke.
# And rake's dsl_definition.rb ends with `self.extend Rake::DSL` — the top level's self is the main object, which then
# answers DSL's methods — but --lego=DSL listed only classes.
#
# THE RULE (queries/{ruby,python}/tags.scm @reference.subscript; ingest_binds.h subscriptOperatorRef; graph.h
# subscriptOperatorProven; parser version 174):
#   * an element access names its receiver class's subscript operator method, by the language's table
#     (kSubscriptOperatorMethods): the write form as an assignment's whole target, the read form otherwise;
#   * it is a CALL only where a receiver rule PROVES the class: Ruby's lookup on self in a def (through include/extend
#     ancestry), a receiver the code builds (`r = Registry.new`, `Registry.new[ k ]`), a class constant's own
#     `def self.[]`; Python's receiver evidence (`self` in a class or its bases, a typed parameter, a constructed local,
#     a field the class assigns). Everything else — a Hash/Array/dict/list local, a literal, an untyped parameter — makes
#     NO edge and NO hedge: no definition named `[]` anywhere decides it by name;
#   * a Ruby file's top-level `include M` / `extend M` / `self.extend M` lists main as M's implementor in --lego=M.
# Stated floors, each pinned below: a compound assignment (`self[ k ] ||= v`, `o[ k ] += 1`) is recorded as the read form;
# a Ruby instance variable receiver is not typed (`@reg[ k ]`); a multiple-assignment target, `del o[ k ]` and an
# annotation record nothing; a Python class-object subscript (`Registry[ k ]`, `cls[ k ]`) runs the metaclass and binds
# nothing; a top-level directive inside `if`, `prepend`, and a mixin onto another object list no main row.
#
# Usage:  test/subscriptopcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/subscriptopcheck.sh
# Exits non-zero on any failure. Self-contained via mktemp.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "subscriptopcheck: BIN=$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
RB="$DIR/rb"; PY="$DIR/py"; mkdir -p "$RB" "$PY"   # the corpora — outputs live in $DIR, never inside them

cat > "$RB/registry.rb" <<'RUBY'
module Lookup
  def [](name)
    fetch_entry(name)
  end

  def []=(name, value)
    store_entry(name, value)
  end
end

class Registry
  include Lookup

  def fetch_entry(name)
    name
  end

  def store_entry(name, value)
    value
  end

  def find_self(name)
    self[name]
  end

  def put_self(name, value)
    self[name] = value
  end

  def or_assign(name)
    self[name] ||= 1
  end

  def self.[](name)
    new.find_self(name)
  end
end

class Plain
  def [](k)
    k
  end
end

class Catalog
  def initialize
    @reg = Registry.new
  end

  def get_built(name)
    r = Registry.new
    r[name]
  end

  def get_value(name)
    Registry.new[name]
  end

  def by_class(name)
    Registry[name]
  end

  def by_plain_class(name)
    Plain[name]
  end

  def via_ivar(name)
    @reg[name]
  end

  def hash_only(name)
    h = {}
    h[name] = 1
    h[name]
  end

  def array_only(i)
    a = [1, 2]
    a[i]
  end

  def untyped(thing, name)
    thing[name]
  end

  def literal
    { a: 1 }[:a]
  end
end

module Tasks
  def task(name)
    name
  end
end

module Inner
  def inner_m
    1
  end
end

module Prepended
  def pre_m
    1
  end
end

module Other
  def other_m
    1
  end
end

self.extend Tasks
include Lookup
extend ::Tasks
if true
  include Inner
end
prepend Prepended
Object.new.extend Other
include Comparable
RUBY

cat > "$PY/registry.py" <<'PY'
class Registry:
    def __init__(self):
        self.items = {}

    def __getitem__(self, key):
        return self.items[key]

    def __setitem__(self, key, value):
        self.items[key] = value

    def lookup_self(self, key):
        return self[key]

    def store_self(self, key, value):
        self[key] = value

    @classmethod
    def by_cls(cls, key):
        return cls[key]


class Sub(Registry):
    def first(self):
        return self["first"]


class Holder:
    def __init__(self):
        self.reg = Registry()

    def via_field(self, k):
        return self.reg[k]


def use_typed(reg: Registry):
    return reg["x"]


def use_built():
    r = Registry()
    return r["y"]


def use_dict():
    d = {}
    d["k"] = 1
    return d["k"]


def use_untyped(thing):
    return thing["z"]


def use_literal():
    return {"a": 1}["a"]


def use_list(xs):
    return xs[0]


def remove(reg: Registry):
    del reg["x"]


def class_side():
    return Registry["x"]


def multi(other: Registry):
    other["a"], other["b"] = 1, 2


def aug(other: Registry):
    other["n"] += 1


def annotated(x: "dict[str, int]") -> None:
    y: dict[str, int] = {}
    return y
PY

# langfacts-fold (train 29): two more files, so the lines above stay where the arms read them
cat > "$RB/scoped.rb" <<'RUBY'
module Outer
  class Cache
    def self.[](key)
      key
    end
  end
end

class Cache
  def self.[](key)
    key
  end
end

class ScopedUser
  def pick(name)
    Outer::Cache[name]
  end

  def pick_top(name)
    ::Cache[name]
  end

  def pick_bare(name)
    Cache[name]
  end

  def pick_call(name)
    build_cache[name]
  end

  def build_cache
    Cache.new
  end
end
RUBY
cat > "$PY/callres.py" <<'PY'
class Reg:
    def __getitem__(self, key):
        return key


def make():
    return Reg()


def use_callres():
    return make()["z"]


def use_attr(reg: Reg):
    return reg.items["k"]
PY

line_of(){ grep -n -- "$2" "$1" | head -1 | cut -d: -f1; }
RGET=$( line_of "$RB/registry.rb" 'def \[\](name)' )
RSET=$( line_of "$RB/registry.rb" 'def \[\]=(name, value)' )
RCLS=$( line_of "$RB/registry.rb" 'def self.\[\](name)' )
PGET=$( line_of "$PY/registry.py" 'def __getitem__' )
PSET=$( line_of "$PY/registry.py" 'def __setitem__' )
for v in RGET RSET RCLS PGET PSET; do
    case "${!v}" in ''|*[!0-9]*) echo "  FAIL  fixture line for $v is not numeric: '${!v}'"; exit 1 ;; esac
done

# one callees answer's <s> rows; the answer must have exited 0 and carried its <callees> root
callees(){ # dir name tag
    local out="$DIR/$3.xml"
    "$BIN" "$1" --callees="$2" --no-cache > "$out" 2> "$DIR/$3.err"
    local rc=$?
    if [ $rc -ne 0 ] || ! grep -q '<callees ' "$out"; then
        no "$3: --callees=$2 did not answer (rc=$rc): $( head -c 300 "$DIR/$3.err" )"
        return 1
    fi
    grep -o '<s t="[^"]*" n="[^"]*" p="[^"]*"[^>]*>' "$out" > "$DIR/$3.rows"
    return 0
}
has_row(){ grep -qF -- "n=\"$2\" p=\"$3\"" "$DIR/$1.rows"; }
# QUALNAME-1: a member row prints Owner.name / Owner#name, so the negative rejects the bare AND any Owner-qualified spelling
no_op_row(){ ! grep -qE -- 'n="([^"]*[.#:])?(\[\]|\[\]=|__getitem__|__setitem__)"' "$DIR/$1.rows"; }

echo "== Ruby: an element access is a call of the receiver class's []/[]= where a rule proves the class"
pos_rb(){ # name tag op line what
    if callees "$RB" "$1" "$2"; then
        if has_row "$2" "$3" "registry.rb:$4" && ! grep -q 'via=' "$DIR/$2.rows"; then ok "R $5: $1 -> $3 registry.rb:$4 (proven, no via=)"
        else no "R $5: $1 should call $3 at registry.rb:$4 with no via=: $( tr '\n' ' ' < "$DIR/$2.rows" )"; fi
    fi
}
pos_rb find_self  r1 'Lookup#[]'  "$RGET" "self[ k ] through an included module"
pos_rb put_self   r2 'Lookup#[]=' "$RSET" "self[ k ] = v names the writer"
pos_rb get_built  r3 'Lookup#[]'  "$RGET" "a local the code builds (r = Registry.new)"
pos_rb get_value  r4 'Lookup#[]'  "$RGET" "a value receiver (Registry.new[ k ])"
pos_rb by_class   r5 'Registry#[]'  "$RCLS" "a class constant reaches its def self.[]"
pos_rb or_assign  r6 'Lookup#[]'  "$RGET" "floor: self[ k ] ||= v is recorded as the read form"
if [ -s "$DIR/r5.rows" ] && ! has_row r5 'Lookup#[]' "registry.rb:$RGET"; then ok "R class side: Registry[ k ] does not reach the instances' []"
else no "R class side: Registry[ k ] must not reach Lookup#[]: $( tr '\n' ' ' < "$DIR/r5.rows" 2>/dev/null )"; fi

neg_rb(){ # name tag what
    if callees "$RB" "$1" "$2"; then
        if no_op_row "$2"; then ok "R negative $3: $1 has no []/[]= row"
        else no "R negative $3: $1 must make no edge: $( tr '\n' ' ' < "$DIR/$2.rows" )"; fi
    fi
}
neg_rb hash_only      n1 "a Hash local (h = {})"
neg_rb array_only     n2 "an Array local"
neg_rb untyped        n3 "an untyped parameter, with in-tree [] namesakes (no hedge either)"
neg_rb literal        n4 "a literal receiver"
neg_rb via_ivar       n5 "floor: an instance variable receiver is not typed"
neg_rb by_plain_class n6 "a class constant whose class defines only an instance []"

echo "== Ruby: a top-level include/extend lists the main object in --lego"
lego(){ # type tag
    "$BIN" "$RB" --lego="$1" --no-cache > "$DIR/$2.xml" 2> "$DIR/$2.err"
    local rc=$?
    if [ $rc -ne 0 ] || ! grep -q '<iface ' "$DIR/$2.xml"; then no "$2: --lego=$1 did not answer (rc=$rc)"; return 1; fi
    return 0
}
EXT1=$( line_of "$RB/registry.rb" '^self.extend Tasks' )
EXT2=$( line_of "$RB/registry.rb" '^extend ::Tasks' )
INC1=$( line_of "$RB/registry.rb" '^include Lookup' )
if lego Tasks l1; then
    m=$( grep -o '<impl t="object" n="main" p="[^"]*"/>' "$DIR/l1.xml" | tr '\n' ' ' )
    if [ "$m" = "<impl t=\"object\" n=\"main\" p=\"registry.rb:$EXT1\"/> <impl t=\"object\" n=\"main\" p=\"registry.rb:$EXT2\"/> " ]; then
        ok "L1 self.extend Tasks and extend ::Tasks: two main rows at their constants"
    else no "L1 --lego=Tasks main rows: got '$m'"; fi
    # train 28 (the lane review's carried item; by design, rule 4): the two directives are two ROWS of ONE implementor — both mix
    # into the same main object — so implementors= counts it once. Was implementors="2" (one per directive). The two rows stay
    # asserted above; L2 below keeps a class beside main at 2.
    if grep -q '<iface n="Tasks"[^>]* implementors="1"' "$DIR/l1.xml"; then ok "L1 implementors= counts the main object once (two directives, two rows)"
    else no "L1 implementors= should be 1 (one main object): $( grep -o '<iface [^>]*>' "$DIR/l1.xml" )"; fi
    if grep -q '<!-- impl t="object" n="main":' "$DIR/l1.xml"; then ok "L1 the main-row legend clause rides with the row"
    else no "L1 no main-row legend clause"; fi
    if command -v xmllint > /dev/null 2>&1; then
        if xmllint --noout "$DIR/l1.xml" 2> "$DIR/l1.lint"; then ok "L1 the answer (clause included) is well-formed XML"
        else no "L1 xmllint: $( head -c 300 "$DIR/l1.lint" )"; fi
    else
        echo "  SKIP  L1 xmllint: not installed"
    fi
fi
if lego Lookup l2; then
    if grep -q '<impl n="Registry"' "$DIR/l2.xml" && grep -q "<impl t=\"object\" n=\"main\" p=\"registry.rb:$INC1\"/>" "$DIR/l2.xml" \
       && grep -q '<iface n="Lookup"[^>]* implementors="2"' "$DIR/l2.xml"; then
        ok "L2 a top-level include lists main beside the class that includes the module"
    else no "L2 --lego=Lookup: $( grep -o '<iface [^>]*>\|<impl [^>]*>' "$DIR/l2.xml" | tr '\n' ' ' )"; fi
fi
for pair in "Inner:l3:a directive inside a top-level if" "Prepended:l4:prepend (main has none)" "Other:l5:a mixin onto another object"; do
    t=${pair%%:*}; rest=${pair#*:}; tag=${rest%%:*}; what=${rest#*:}
    if lego "$t" "$tag"; then
        if ! grep -q 'n="main"' "$DIR/$tag.xml" && grep -q "<iface n=\"$t\"[^>]* implementors=\"0\"" "$DIR/$tag.xml"; then ok "L negative ($what): --lego=$t lists no main row"
        else no "L negative ($what): --lego=$t: $( grep -o '<iface [^>]*>\|<impl [^>]*>' "$DIR/$tag.xml" | tr '\n' ' ' )"; fi
    fi
done
if lego Tasks l6 && "$BIN" "$RB" --for="tasks module" --no-cache > "$DIR/l6for.xml" 2>/dev/null && ! grep -q 'n="main"' "$DIR/l6for.xml"; then
    ok "L the ranked --for lego section keeps its shape (main rows ride the targeted --lego only)"
else no "L --for carries a main row or did not answer"; fi

echo "== Python: obj[ k ] calls __getitem__ / __setitem__ where receiver evidence proves the class"
pos_py(){ # name tag op line what
    if callees "$PY" "$1" "$2"; then
        if has_row "$2" "$3" "registry.py:$4" && ! grep -q 'via=' "$DIR/$2.rows"; then ok "P $5: $1 -> $3 registry.py:$4 (proven, no via=)"
        else no "P $5: $1 should call $3 at registry.py:$4 with no via=: $( tr '\n' ' ' < "$DIR/$2.rows" )"; fi
    fi
}
pos_py lookup_self p1 Registry.__getitem__ "$PGET" "self[ k ] in the class"
pos_py store_self  p2 Registry.__setitem__ "$PSET" "self[ k ] = v names __setitem__"
pos_py first       p3 Registry.__getitem__ "$PGET" "self[ k ] in a subclass reaches the base's"
pos_py use_typed   p4 Registry.__getitem__ "$PGET" "a typed parameter"
pos_py use_built   p5 Registry.__getitem__ "$PGET" "a constructed local"
pos_py via_field   p6 Registry.__getitem__ "$PGET" "a field the class assigns (self.reg = Registry())"
pos_py aug         p7 Registry.__getitem__ "$PGET" "floor: o[ k ] += 1 is recorded as the read form"
neg_py(){ # name tag what
    if callees "$PY" "$1" "$2"; then
        if no_op_row "$2"; then ok "P negative $3: $1 has no subscript row"
        else no "P negative $3: $1 must make no edge: $( tr '\n' ' ' < "$DIR/$2.rows" )"; fi
    fi
}
neg_py use_dict    q1 "a dict local"
neg_py use_untyped q2 "an untyped parameter, with an in-tree __getitem__ namesake (no hedge either)"
neg_py use_literal q3 "a dict literal"
neg_py use_list    q4 "a list parameter"
neg_py remove      q5 "floor: del o[ k ] (__delitem__ is not read)"
neg_py class_side  q6 "a class-object subscript runs the metaclass"
neg_py by_cls      q7 "cls[ k ] in a classmethod is the class object too"
neg_py multi       q8 "floor: a multiple-assignment target records nothing"
neg_py annotated   q9 "an annotation is a type, not a value"

echo "== langfacts-fold pins: the subscript record's two Ruby-only rules (src/ingest_binds.h subscriptOperatorRef), as they answer today"
# A Ruby receiver the shape rules cannot classify stays a FieldOfVar site (the typing walk may still type it); a Python one
# (a call result) records nothing. A Ruby constant receiver keeps its path as written, so a scoped constant reaches its own
# class's def self.[] and a bare or top-level one the top-level class's.
rows_are(){ [ "$( grep -c 'n="[^"]*#\[\]"' "$DIR/$1.rows" )" = 1 ] && [ "$( grep -c 'n="\[\]"' "$DIR/$1.rows" )" = 0 ] && has_row "$1" 'Cache#[]' "$2" && ! grep -q 'prov=\|via=' "$DIR/$1.rows"; }
for trip in pick:lf1:3:"Outer::Cache[ k ] reaches Outer::Cache.[]" pick_top:lf2:10:"::Cache[ k ] reaches the top-level Cache.[]" pick_bare:lf3:10:"Cache[ k ] reaches the top-level Cache.[]"; do
    IFS=: read -r nm tg ln what <<<"$trip"
    if callees "$RB" "$nm" "$tg"; then
        if rows_are "$tg" "scoped.rb:$ln"; then ok "LF R $what (scoped.rb:$ln, one row, proven)"
        else no "LF R $what: $( tr '\n' ' ' < "$DIR/$tg.rows" )"; fi
    fi
done
if callees "$RB" pick_call lf4; then
    if no_op_row lf4; then ok "LF R build_cache[ k ]: a call-result receiver makes no []-edge (the call to build_cache is the only row)"
    else no "LF R build_cache[ k ]: $( tr '\n' ' ' < "$DIR/lf4.rows" )"; fi
fi
neg_py use_callres lf5 "a call result (make()[ k ]) in Python: the receiver cannot be shaped, so nothing is recorded (Ruby keeps such a site)"
neg_py use_attr    lf6 "a field of a typed parameter (reg.items[ k ]): no edge"

echo "== the site is a use only as the call it is (--uses lists no subscript rows)"
"$BIN" "$PY" --uses=__getitem__ --no-cache > "$DIR/u.xml" 2>/dev/null; urc=$?
if [ $urc -eq 0 ] && grep -q '<uses' "$DIR/u.xml" && ! grep -q 'role="subscript"' "$DIR/u.xml"; then ok "U --uses=__getitem__ carries no role=\"subscript\" row"
else no "U --uses=__getitem__ (rc=$urc) leaked a subscript row or did not answer"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
