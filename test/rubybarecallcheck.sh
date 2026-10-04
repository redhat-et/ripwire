#!/usr/bin/env bash
# rubybarecallcheck.sh — gate for Ruby's BARE-WORD call: `full_name` / `render_profile` / `items.sum`, an identifier
# with no receiver, no arguments and no parentheses. tree-sitter-ruby parses it as a plain (identifier) — the same node
# as a local-variable read — so queries/ruby/tags.scm never captured it, and one Ruby call site in five minted no
# reference at all (measured with Prism's `variable_call?` on activerecord 7.2.3.2 lib: 4,157 of 28,584 call sites; on
# two Rails applications 50,893 of 250,320 and 56,897 of 295,879). The resolver already reads a receiver-less Ruby call
# as an implicit-self send (resolve.h Rule 1 and its base walk); it was never handed this one.
#
# The rule is Ruby's own, not a heuristic. The Ruby parser decides it LEXICALLY: an identifier is a local variable
# exactly when an assignment, a parameter or a pattern binds that name EARLIER in the same scope; every other bare
# identifier is a method call on self (Prism: CallNode#variable_call?). Scopes are Ruby's: a `def`, `class`, `module`
# and `class << x` body sees no outer local; a block or lambda sees the enclosing locals and keeps its own. So:
#   * a read AFTER `x = …` / `x ||= …` / `a, (x, b) = …` / `*x = …`, a method, block or lambda parameter, a block-local
#     (`|i; x|`), `rescue => x`, `for x in`, a pattern binding (`in [x]`, `in {x:}`, `=> x`, `in x`), a regex named
#     capture (`/(?<x>…)/ =~ s`) — and the right side of its own assignment (`x = x`) — is a LOCAL: no reference;
#   * the same name BEFORE its binding, in a SIBLING block, or across a `def` wall is a CALL;
#   * inside a block with no parameters, `it` and `_1`…`_9` are the block's implicit parameters (Ruby 3.4);
#   * a hash or keyword-argument shorthand (`{ payload: }`) reads `payload` — a call when no local has that name.
# RSpec: `let`/`let!`/`subject`/`subject!` (and test-prof's `let_it_be` family) define a METHOD on the example group,
# visible to the whole group — before the line that defines it, in nested groups and in a `def` inside the group — and
# every example group defines `subject` implicitly. Those names bind like locals over the group's block, so a spec's
# `user` never reaches an unrelated application `def user`. They are NOT minted as definitions: a let is reachable
# only from its group, and a definition the resolver can see from application code would turn unique application
# calls into declines (measured: 1,818 and 1,036 application call sites to a uniquely-defined method share a name with a
# let on the two Rails applications).
#
# Ruby has NO DECLARATIONS. Every class, module, def, attr accessor and constant it indexes is a definition — there is
# no prototype for a body to replace — so a body-less one (an `attr_reader` accessor, an empty `def on_event; end` hook)
# is the answer for a call that names it, not a declaration the decl/def collapse (graph.h collapseDeclarationsOfName)
# may evict in favour of a same-named bodied def anywhere in the tree. Measured as a lower bound on the bare calls this
# round adds: 367 of 2,952 on activerecord named an attr accessor of the caller's own file and landed in another file
# (activesupport 26 of 721; the two applications 402 of 12,033 and 288 of 8,339). The receiver forms `self.x` and `x()`
# were already misrouted the same way. Pinned below (model.h isDefinitionNotDeclaration, the Kotlin-type precedent).
# And a Ruby definition is no other language's body: a C prototype with no C definition (an extension's header) stays
# its C callers' best-available target whatever Ruby defines under that name (graph.h's collapse gives Ruby its own
# family, as it gives Kotlin one). Before, a Ruby `def` evicted it and the C call read unresolved.
#
# Stated floors, each pinned below:
#   (a) `defined?( name )` asks whether `name` exists; it calls nothing — no reference.
#   (b) a `let` that a SHARED context defines (`shared_context` … `include_context`) is not known in the including file:
#       there the name reads as Ruby reads it with no let in sight — a call.
#   (c) locals made at run time (`binding.local_variable_set`, `eval`) are invisible to a lexical rule.
#   (d) inside `instance_eval`/`class_eval`/`instance_exec` blocks self changes; a bare call there resolves against the
#       lexical class, exactly as a parenthesised `m()` there always has.
#   (e) the RSpec DSL call itself — `subject( :x ) { … }`, `let( :x ) { … }`, `it "…" do` — is a call with arguments,
#       captured before this round, and binds by name like any call when the tree defines that name; only the bare
#       READS of the names they define are this round's.
#
# Usage:  test/rubybarecallcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubybarecallcheck.sh
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
FIX="$DIR/fix"; mkdir -p "$FIX/lib/app" "$FIX/lib/base" "$FIX/lib/other" "$FIX/lib/decoys" "$FIX/spec"

# Bare calls inside one class: Rule 1 (the caller's own class) answers each of them.
cat > "$FIX/lib/app/person.rb" <<'RUBY'
class Person
  attr_reader :title

  def full_name
    first_name + " " + last_name
  end

  def first_name
    "a"
  end

  def last_name
    "b"
  end

  def show
    render_profile
  end

  def render_profile
    "#{greeting}!"
  end

  def greeting
    "hi"
  end

  def total
    items.sum
  end

  def items
    [1]
  end

  def logs
    log( message )
  end

  def log( m )
    m
  end

  def message
    "m"
  end

  def shorthand
    { payload: }
  end

  def payload
    1
  end

  def endless = endless_target

  def endless_target
    2
  end

  def each_item
    items.each { |i| process_one }
  end

  def process_one
    3
  end

  def label
    title
  end

  def helper
    1
  end

  def run
    helper
  end
end
RUBY

# Same-named methods elsewhere: a bare call must pin to the caller's own class or its superclass, never split.
cat > "$FIX/lib/other/robot.rb" <<'RUBY'
class Robot
  def helper
    2
  end

  def inherited_helper
    2
  end
end
RUBY

cat > "$FIX/lib/base/parent.rb" <<'RUBY'
class Parent
  def inherited_helper
    1
  end
end
RUBY

cat > "$FIX/lib/app/child.rb" <<'RUBY'
class Child < Parent
  def go
    inherited_helper
  end
end
RUBY

cat > "$FIX/lib/app/boot.rb" <<'RUBY'
def boot_now
  1
end

boot_now
RUBY

# Every name a local or an RSpec let binds is ALSO a method of module Decoy, in another directory, which the calling
# classes (Locals, Scoping) include — so a binding misread as a call would reach Decoy through the base walk (and, from a
# spec's example group, which is in no class, as the unique global) and show as a caller of it. A module, not a class:
# an unrelated class's method is out of a bare call's reach (test/rubyreachcheck.sh), so it could show nothing.
cat > "$FIX/lib/decoys/decoy.rb" <<'RUBY'
module Decoy
  def x_asg; end
  def x_op; end
  def x_m2; end
  def x_rest; end
  def x_req; end
  def x_opt; end
  def x_dflt; end
  def x_splat; end
  def x_kw; end
  def x_kwopt; end
  def x_dsplat; end
  def x_blk; end
  def x_bp; end
  def x_dp; end
  def x_bl; end
  def x_lam; end
  def x_err; end
  def x_for; end
  def x_ap; end
  def x_fp; end
  def x_hp; end
  def x_as; end
  def x_in; end
  def x_rw; end
  def x_tp; end
  def x_rx; end
  def x_self; end
  def x_mod; end
  def x_outer; end
  def x_defined; end
  def it; end
  def pre_bound; end
  def sib_local; end
  def wall_x; end
  def other_param; end
  def spec_user; end
  def named_subj; end
  def subject; end
  def later_let; end
  def spec_helper_q; end
end
RUBY

cat > "$FIX/lib/app/locals.rb" <<'RUBY'
class Locals
  include Decoy
  def assign
    x_asg = 1
    x_asg
  end

  def op_assign
    x_op ||= 1
    x_op
  end

  def multi
    x_m1, ( x_m2, x_m3 ) = 1, [ 2, 3 ]
    x_m2
  end

  def rest
    a, *x_rest = 1, 2
    x_rest
  end

  def params( x_req, x_opt = 1, x_dflt = x_req, *x_splat, x_kw:, x_kwopt: 2, **x_dsplat, &x_blk )
    [ x_req, x_opt, x_dflt, x_splat, x_kw, x_kwopt, x_dsplat, x_blk ]
  end

  def block_params
    [ 1 ].each { |x_bp| x_bp }
    { a: 1 }.each { |( x_dp, v ), w| x_dp }
    [ 1 ].each { |i; x_bl| x_bl = i; x_bl }
  end

  def implicit_params
    [ 1 ].map { it }
    [ 1 ].map { _1 }
  end

  def lambdas
    l = ->( x_lam ) { x_lam }
    l
  end

  def rescues
    begin
      1
    rescue => x_err
      x_err
    end
  end

  def fors
    for x_for in [ 1 ]
      x_for
    end
  end

  def patterns( v )
    case v
    in [ x_ap, *rest ] then x_ap
    in [ *, x_fp, * ] then x_fp
    in { x_hp: } then x_hp
    in Integer => x_as then x_as
    in x_in then x_in
    end
  end

  def rightward( h, v )
    h => { x_rw: }
    x_rw
    v in Integer => x_tp
    x_tp
  end

  def named_captures( s )
    /(?<x_rx>\d+)/ =~ s
    x_rx
  end

  def self_read
    x_self = x_self
  end

  def modifier
    x_mod = 1 if x_mod
  end

  def nested
    x_outer = 1
    [ 1 ].each { x_outer }
  end

  def defined_check
    defined?( x_defined )
  end
end
RUBY

# Ruby's scoping where the SAME spelling is a call: before the binding, in a sibling block, across a def wall.
cat > "$FIX/lib/app/scoping.rb" <<'RUBY'
class Scoping
  include Decoy
  wall_x = 1

  def before_bind
    pre_bound
    pre_bound = 1
    pre_bound
  end

  def sibling
    [ 1 ].each { sib_local = 1 }
    sib_local
  end

  def through_wall
    wall_x
  end

  def param_elsewhere( other_param )
    other_param
  end

  def no_param_here
    other_param
  end
end
RUBY

cat > "$FIX/spec/person_spec.rb" <<'RUBY'
RSpec.describe Person do
  let( :spec_user ) { Person.new }
  subject( :named_subj ) { Person.new }

  it "reads its group's lets" do
    spec_user.full_name
    named_subj.full_name
    subject.full_name
    later_let
    spec_helper_q
  end

  def group_helper
    spec_user
  end

  def spec_helper_q
    1
  end

  context "nested" do
    it { spec_user }
  end

  let!( :later_let ) { 1 }
end
RUBY

# No declarations: the caller's own private attr_reader, and an inherited empty hook, against bodied defs elsewhere.
cat > "$FIX/lib/app/tracker.rb" <<'RUBY'
class Tracker
  def t_bare
    aliases
  end

  def t_self
    self.aliases
  end

  def t_paren
    aliases()
  end

  private
    attr_reader :aliases
end
RUBY

cat > "$FIX/lib/other/join.rb" <<'RUBY'
class Join
  def aliases
    1
  end

  def on_event
    2
  end
end
RUBY

cat > "$FIX/lib/base/hooks.rb" <<'RUBY'
class Hooks
  def on_event; end
end
RUBY

cat > "$FIX/lib/app/hooked.rb" <<'RUBY'
class Hooked < Hooks
  def fire
    on_event
  end
end
RUBY

# A mixed tree: a C extension's header declares widget_count/widget_total with no C body; Ruby defines both names.
mkdir -p "$FIX/ext"
cat > "$FIX/ext/widget.h" <<'C'
int widget_count( void );
int widget_total( void );
C
cat > "$FIX/ext/widget.c" <<'C'
#include "widget.h"
int widget_report( void ) { return widget_count() + widget_total(); }
C
cat > "$FIX/lib/app/widget.rb" <<'RUBY'
class Widget
  attr_reader :widget_total

  def widget_count
    1
  end
end
RUBY

cat > "$FIX/spec/implicit_spec.rb" <<'RUBY'
RSpec.describe Person do
  it { subject.full_name }
end
RUBY

MAP="$DIR/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP" 2>"$DIR/map.err"
if [ $? -eq 0 ]; then ok "default map exits 0"; else no "default map exited non-zero: $( cat "$DIR/map.err" )"; fi
[ -s "$DIR/map.err" ] && no "unexpected stderr: $( head -3 "$DIR/map.err" )" || ok "clean stderr"
command -v xmllint >/dev/null 2>&1 && { if xmllint --noout "$MAP"; then ok "xmllint --noout"; else no "xmllint failed"; fi; }

# callers ROOT SYM — writes the --callers=SYM caller rows (one per line) to $DIR/c.rows; returns 2 when the run failed,
# so an absence arm can never read a crashed run as "no caller".
callers(){
    if ! "$BIN" "$1" --no-cache --callers="$2" >"$DIR/c.out" 2>"$DIR/c.err"
    then
        no "--callers=$2 exited non-zero: $( head -3 "$DIR/c.err" )"
        return 2
    fi
    sed 's/></>\n</g' "$DIR/c.out" | grep '^<s t="' >"$DIR/c.rows"
    return 0
}
# reaches SYM CALLER WHY — CALLER (a symbol name) is a caller of SYM
reaches(){
    callers "$FIX" "$1" || return
    grep -q " n=\"$2\"" "$DIR/c.rows" && ok "$2 → $1 ($3)" \
        || no "$2 does not reach $1 ($3); callers: $( tr '\n' ' ' <"$DIR/c.rows" )"
}
# misses SYM CALLER WHY — CALLER is NOT a caller of SYM
misses(){
    callers "$FIX" "$1" || return
    grep -q " n=\"$2\"" "$DIR/c.rows" && no "$2 reaches $1 — $3" || ok "$2 does not reach $1 ($3)"
}
# missesFrom SYM FILE WHY — no caller of SYM sits in FILE
missesFrom(){
    callers "$FIX" "$1" || return
    grep -q " p=\"$2:" "$DIR/c.rows" && no "$2 reaches $1 — $3" || ok "$2 does not reach $1 ($3)"
}
# uncalled SYM WHY — SYM has no caller at all
uncalled(){
    callers "$FIX" "$1" || return
    [ -s "$DIR/c.rows" ] && no "$1 has callers — $2: $( tr '\n' ' ' <"$DIR/c.rows" )" || ok "$1 has no caller ($2)"
}

echo "=== a bare word is a call: each shape reaches the method it names ==="
reaches Person::first_name     full_name      "an operand of +"
reaches Person::last_name      full_name      "the other operand"
reaches Person::render_profile show           "a statement on its own"
reaches Person::greeting       render_profile "inside string interpolation"
reaches Person::items          total          "the receiver of another call"
reaches Person::message        logs           "an argument"
reaches Person::payload        shorthand      "a hash shorthand { payload: } reads payload"
reaches Person::endless_target endless        "an endless def's body"
reaches Person::process_one    each_item      "inside a block — i is the block's parameter, process_one is not"
reaches Person::title          label          "an attr_reader's accessor"
reaches boot_now               "&lt;file-scope&gt;" "a top-level bare call is owned by the file"

echo "=== implicit self: the caller's own class, then its superclass — never a split ==="
reaches Person::helper           run "Rule 1: the enclosing class defines helper"
misses  Robot::helper            run "Robot::helper is another class's method"
reaches Parent::inherited_helper go  "the base walk: Child < Parent"
misses  Robot::inherited_helper  go  "Robot is not an ancestor of Child"

echo "=== Ruby has no declarations: a body-less accessor or hook is the definition a call names ==="
reaches Tracker::aliases t_bare  "the caller's own private attr_reader"
misses  Join::aliases    t_bare  "Join::aliases is another class's method"
reaches Tracker::aliases t_self  "self.aliases — the receiver form, misrouted before this round too"
misses  Join::aliases    t_self  "self.aliases never reaches Join"
reaches Tracker::aliases t_paren "aliases() — the parenthesised form"
misses  Join::aliases    t_paren "aliases() never reaches Join"
reaches Hooks::on_event  fire    "an inherited EMPTY hook is a definition: the base walk finds it"
misses  Join::on_event   fire    "Join is not an ancestor of Hooked"

# calleeIn FN NAME FILE WHY — FN's callees include NAME defined in FILE
calleeIn(){
    if ! "$BIN" "$FIX" --no-cache --callees="$1" >"$DIR/ce.out" 2>"$DIR/ce.err"
    then
        no "--callees=$1 exited non-zero: $( head -3 "$DIR/ce.err" )"
        return
    fi
    sed 's/></>\n</g' "$DIR/ce.out" | grep '^<s t="' | grep " n=\"$2\"" | grep -q " p=\"$3:" && ok "$1 → $2 in $3 ($4)" \
        || no "$1 does not reach $2 in $3 ($4): $( sed 's/></>\n</g' "$DIR/ce.out" | grep '^<s t="' | tr '\n' ' ' )"
}
calleeIn widget_report widget_count ext/widget.h "a Ruby def is no C prototype's body: the C declaration stays the target"
calleeIn widget_report widget_total ext/widget.h "nor is a Ruby attr accessor"

echo "=== a local is not a call: every binding form Ruby has ==="
for x in x_asg x_op x_m2 x_rest x_req x_opt x_dflt x_splat x_kw x_kwopt x_dsplat x_blk x_bp x_dp x_bl x_lam x_err x_for \
         x_ap x_fp x_hp x_as x_in x_rw x_tp x_rx x_self x_mod x_outer
do
    uncalled "Decoy::$x" "a local of that name is read in lib/app/locals.rb"
done
misses Decoy::it implicit_params "it inside a parameterless block is the block's implicit parameter"
uncalled Decoy::x_defined "floor (a): defined?( x ) calls nothing (stated)"

echo "=== the same spelling IS a call where Ruby says so ==="
reaches Decoy::pre_bound   before_bind     "a read BEFORE the assignment is a call"
reaches Decoy::sib_local   sibling         "a local of a sibling block does not leak out of it"
reaches Decoy::wall_x      through_wall    "a class-body local does not cross the def wall"
reaches Decoy::other_param no_param_here   "another method's parameter is not in scope here"
misses  Decoy::other_param param_elsewhere "the parameter itself is a local where it is declared"

echo "=== RSpec: a group's lets, subject and named subject bind over the whole group ==="
for x in spec_user named_subj later_let
do
    uncalled "Decoy::$x" "spec/person_spec.rb's group defines $x"
done
missesFrom Decoy::subject spec/implicit_spec.rb "every example group defines subject implicitly"
reaches spec/person_spec.rb:spec_helper_q "&lt;file-scope&gt;" "a def inside the group is a method the example calls"
misses  Decoy::spec_helper_q "&lt;file-scope&gt;" "the spec's own def wins (same file)"

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

echo "=== mutation: rename the binding → the read becomes a call ==="
MUT="$DIR/mut"; cp -R "$FIX" "$MUT"
sed 's/^    x_asg = 1$/    y_asg = 1/' "$FIX/lib/app/locals.rb" >"$MUT/lib/app/locals.rb"
grep -q '^    y_asg = 1$' "$MUT/lib/app/locals.rb" || no "mutation did not apply"
if callers "$MUT" "Decoy::x_asg"
then
    grep -q ' n="assign"' "$DIR/c.rows" && ok "mutation: with the binding renamed, assign → Decoy::x_asg (the included module's method)" \
        || no "mutation: renamed binding, but assign still does not call Decoy::x_asg"
fi

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
