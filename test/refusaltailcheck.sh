#!/usr/bin/env bash
# refusaltailcheck.sh — the LOW tail of the 2026-09-04 capture audit's refusal lens (lens 6 F10/F13/F14/F15,
# F20's log-leak half). Four small properties, each a one-line lie in a refusal an agent reads.
#
#   A  AN EMPTY LIST ITEM IS REFUSED, NEVER DROPPED, AND NEVER SUGGESTED FROM.
#      `--path=rankGraphTeleport,` answered "endpoint not found:  (did you mean 'A'?)" — the second endpoint
#      is the EMPTY STRING, and the edit-distance suggester, asked for the nearest name to "", returned the
#      shortest symbol in the corpus. Its siblings dropped the empty item in silence instead:
#      `--connect=A,B,` ran as a 2-terminal connect at exit 0, so a trailing comma (or a shell variable that
#      expanded to nothing) quietly changed the question. Both halves are the same defect — an empty item is
#      not a selector, and neither answering about it nor deleting it is honest.
#
#   B  A REFUSAL CARRIES NO "[math degraded]" LINE. That log means "this run CONTINUED in a reduced mode";
#      ahead of a refusal it says the opposite of what happened. namedfileinputcheck.sh owns the FILE-input
#      members; this arm covers the REF-shaped ones (--pr-context) that leak the same way.
#
#   C  AN ENUM REFUSAL NAMES THE WHOLE SUPPORTED SET. `--edit-plan`'s op vocabulary was listed nowhere — not
#      in --help, not in the refusal ("unknown edit-plan op 'replace'"), while every other enum in the tool
#      prints "(supported: …)". A closed set the caller cannot enumerate is a guessing game.
#
#   D  A STRUCT SELECTOR SUGGESTS FROM THE STRUCT SET. `--layout=Grap` and `--field-affinity=Grap` said only
#      "try --grep=Grap" with `Graph` one edit away in an index of 494 structs they had already loaded —
#      while every SYMBOL selector one keystroke away offers the name. The candidate set was right there.
#
# RED-FIRST (base binary ec5e3c3): every arm below.
#
# Usage:  bash test/refusaltailcheck.sh [BIN]
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "refusaltailcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R"
cat > "$R/one.cpp" <<'EOF'
struct Graphite { int wide; int tall; };
int leafy( int x ) { return x + 1; }
int middy( int x ) { return leafy( x ); }
int toppy( int x ) { return middy( x ); }
int spanA( const Graphite& g ) { return g.wide + g.tall; }
int spanB( const Graphite& g ) { return g.tall * g.wide; }
EOF

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== A: an EMPTY item in a comma list refuses, and no suggestion is computed from it ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
empty_item(){ # $1 = the whole flag=value token
    local token="$1" out rc
    out="$( "$BIN" "$R" "$token" --no-cache 2>&1 1>/dev/null )"; rc=$?
    if [ "$rc" -ne 0 ]; then ok "A $token → exit $rc (the empty item is not silently dropped)"; else no "A $token → exit 0: an empty item was dropped and the question silently changed"; fi
    if printf '%s' "$out" | grep -q "did you mean"; then
        no "A $token: a did-you-mean was computed from the empty string: $out"
    else
        ok "A $token: no suggestion invented for an empty selector"
    fi
    if printf '%s' "$out" | grep -qi "empty"; then
        ok "A $token: the refusal says the item is empty"
    else
        no "A $token: the refusal does not say WHAT is wrong: $out"
    fi
}
empty_item "--path=middy,"
empty_item "--path=,middy"
empty_item "--connect=middy,leafy,"

# the negative: a well-formed list of the same shape still answers
"$BIN" "$R" --path=toppy,leafy --no-cache >/dev/null 2>&1 \
  && ok "A --path=toppy,leafy (no empty item) still answers" || no "A a well-formed --path was refused"
"$BIN" "$R" --connect=toppy,leafy --no-cache >/dev/null 2>&1 \
  && ok "A --connect=toppy,leafy (no empty item) still answers" || no "A a well-formed --connect was refused"

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== B: a refusal carries no internal degrade log ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
( cd "$R" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
for token in "--pr-context=nosuchref-zz"; do
    out="$( "$BIN" "$R" "$token" --no-cache 2>&1 1>/dev/null )"
    printf '%s' "$out" | grep -qF '[math degraded]' \
      && no "B $token: an internal degrade log precedes the refusal: $out" \
      || ok "B $token: no internal degrade log in a refusal"
done

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== C: --edit-plan's op vocabulary is printed, in the refusal and in --help ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
printf 'body\n' > "$R/pay.txt"
cat > "$R/plan.json" <<'EOF'
{"version":1,"edits":[{"op":"replace","target":"middy","payload":"pay.txt"}]}
EOF
OUT="$( "$BIN" "$R" --edit-plan="$R/plan.json" --dry-run --no-cache 2>&1 1>/dev/null )"
printf '%s' "$OUT" | grep -qF 'replace_symbol_body' \
  && ok "C the unknown-op refusal names the supported ops" \
  || no "C the unknown-op refusal names no supported set: $OUT"
HELPF="$TMP/help.txt"; "$BIN" --help >"$HELPF" 2>/dev/null
grep -qF 'replace_symbol_body' "$HELPF" \
  && ok "C --help lists the edit-plan op vocabulary" \
  || no "C --help still documents {op,target,file?,payload} without naming the op values"

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== D: a STRUCT selector suggests from the struct set ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
for flag in --layout --field-affinity; do
    OUT="$( "$BIN" "$R" "$flag=Graphit" --no-cache 2>&1 1>/dev/null )"
    printf '%s' "$OUT" | grep -qF "Graphite" \
      && ok "D $flag=Graphit names the near-miss Graphite" \
      || no "D $flag=Graphit offers no candidate from the struct set it had already loaded: $OUT"
done
# and a name with nothing close still gets no invented candidate
OUT="$( "$BIN" "$R" --layout=zzzznosuchstruct --no-cache 2>&1 1>/dev/null )"
printf '%s' "$OUT" | grep -q "did you mean" \
  && no "D --layout=zzzznosuchstruct invented a candidate: $OUT" \
  || ok "D --layout=<nothing close> invents no candidate"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
