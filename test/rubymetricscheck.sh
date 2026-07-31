#!/usr/bin/env bash
# rubymetricscheck.sh — gate for Ruby structural-metrics recognition (src/ingest.cpp predicate tables:
# cc_isParamList / isDecisionType / cc_isNestingControl). Ruby parses for symbols, but before the fix the
# cognitive-complexity / params / nesting node-type tables only knew C-family (+ a little Python) node
# kinds, so for Ruby source params/ccx/nest were SILENTLY ALWAYS ZERO. This asserts they are now non-zero
# for a branchy Ruby method, and that a branch-free method scores strictly LESS (guarding against a
# hardcoded constant). Ruby's tree-sitter node kinds are confirmed empirically (method_parameters /
# block_parameters / lambda_parameters for params; if/elsif/unless/while/until/for/when/rescue/conditional
# + the trailing modifier forms for decisions; if/unless/while/until/for/case/case_match/rescue/conditional
# for nesting).
# Usage:  test/rubymetricscheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rubymetricscheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh. Self-contained via mktemp.
set -u
BIN="${RIPWIRE_BIN:-./build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

DIR="$(mktemp -d)"; trap 'rm -rf "$DIR"' EXIT

# a Ruby method with: 3 params, nested if/while, boolean-operator branches, elsif, case/when, ternary,
# for, begin/rescue, until, and a trailing `unless` modifier — plus a branch-FREE method for the ordering
# assertion.
cat > "$DIR/probe.rb" <<'RUBY'
class Widget
  def branchy(a, b, c)
    if a > 0
      while b > 0
        if a && b || c
          b -= 1
        end
      end
    elsif c
      puts "c"
    end
    case a
    when 1 then 1
    when 2 then 2
    end
    x = a > 0 ? 1 : 2
    for i in 0..a
      puts i
    end
    begin
      puts "x"
    rescue => e
      puts e
    end
    until c
      c = true
    end
    puts "hi" unless a
    x
  end

  def flat(a, b)
    a + b
  end
end
RUBY

# grab an integer attribute (attr="123") from the <s ...> line of a named symbol.
metric(){ # $1=method name  $2=attr
  "$BIN" "$DIR" --metrics --no-cache 2>/dev/null \
    | grep -oE "n=\"$1\"[^>]*" | grep -oE "$2=\"[0-9]+\"" | grep -oE '[0-9]+' | head -1
}

bp="$(metric branchy params)"; bx="$(metric branchy ccx)"; bn="$(metric branchy nest)"; bc="$(metric branchy cx)"
fx="$(metric flat ccx)"; fp="$(metric flat params)"

# defaults if a metric is absent (would otherwise blank-compare)
bp="${bp:-0}"; bx="${bx:-0}"; bn="${bn:-0}"; bc="${bc:-0}"; fx="${fx:-0}"; fp="${fp:-0}"

[ "$bp" -gt 0 ] && ok "Ruby method params counted (branchy params=$bp)" \
                || no "Ruby method params should be > 0 (got $bp) — cc_isParamList missing method_parameters?"

[ "$bx" -gt 0 ] && ok "Ruby cognitive complexity counted (branchy ccx=$bx)" \
                || no "Ruby ccx should be > 0 (got $bx) — isDecisionType/cc_isNestingControl missing Ruby nodes?"

[ "$bn" -gt 0 ] && ok "Ruby control nesting counted (branchy nest=$bn)" \
                || no "Ruby nest should be > 0 (got $bn) — cc_isNestingControl missing Ruby nodes?"

# not a hardcoded constant: the branch-FREE method must score strictly less than the branchy one.
if [ "$fx" -lt "$bx" ]; then
  ok "branch-free method scores strictly less (flat ccx=$fx < branchy ccx=$bx)"
else
  no "branch-free flat ccx ($fx) should be < branchy ccx ($bx) — metric may be a constant"
fi
[ "$fx" -eq 0 ] && ok "branch-free method ccx == 0 (flat)" || no "branch-free flat ccx should be 0 (got $fx)"
[ "$fp" -gt 0 ] && ok "branch-free method still counts its params (flat params=$fp)" \
                || no "branch-free flat params should be > 0 (got $fp)"

# determinism: two full runs byte-identical.
r1="$("$BIN" "$DIR" --metrics --no-cache 2>/dev/null)"
r2="$("$BIN" "$DIR" --metrics --no-cache 2>/dev/null)"
[ "$r1" = "$r2" ] && ok "Ruby --metrics deterministic run-to-run" || no "Ruby --metrics not deterministic"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
