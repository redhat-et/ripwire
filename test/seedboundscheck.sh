#!/usr/bin/env bash
# seedboundscheck.sh — M20 (capture-audit 2026-09-04, lens 6 F12, lens 2 L8): a SEEDED verb echoes its seed
# and the bounds that decide what could appear in the answer.
#
# THE DEFECT. `--around=SYM` renders through the shared map serializer, so it came out under the PLAIN map
# root: `<r root="." est_tokens="10788">`. Three things were missing from it and every one of them changes
# how the 189 rows below should be read —
#   of=      the seed. Recoverable only by spotting the k="1.0000" row, and only if you knew to look.
#   depth=   how many call hops out the walk went (default 2, and --help named no default at all).
#   fanout=  how many neighbours per hop it kept (default 32).
# A reader handed the rows could not tell a 1-hop answer from a 3-hop one, and therefore could not tell
# "X is not in this neighbourhood" from "X was outside the fanout". The bounds ARE the claim's scope.
#
# And the fourth: defs=. resolveFocus resolves a bare name to the LOWEST-ID definition, so `--around=size`
# (6 definitions) walked one of them silently. --callers/--uses/--impact/--mentions/--safe-delete/--path/
# --verify all print defs= for exactly this reason; the ego graph and the Steiner subgraph (--connect's
# <t/> terminal rows) did not.
#
# THE FAMILY, and why each member is asserted the way it is: a verb is SEEDED when the caller names the
# symbol(s) the answer is centred on. --around (one seed, two bounds), --connect (2..16 terminals, radius
# bound), --path (two endpoints), --slice (one seed). The last two already complied — from_defs=/to_defs= on
# --path, sym= on --slice — and are here because the property belongs to the family, not to --around.
#
# RED-FIRST (base binary ec5e3c3): every --around arm and the --connect defs= arm.
#
# Usage:  bash test/seedboundscheck.sh [BIN]
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "seedboundscheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R"
# `dup` is defined twice (one per translation unit) — the ambiguous seed. `leaf`/`mid`/`top` give the walk
# something to bound, so depth= and fanout= are not vacuous here.
cat > "$R/one.cpp" <<'EOF'
int leaf( int x ) { return x + 1; }
int dup( int x ) { return leaf( x ); }
int mid( int x ) { return dup( x ) + leaf( x ); }
int top( int x ) { return mid( x ); }
EOF
cat > "$R/two.cpp" <<'EOF'
int dup( double x ) { return int( x ); }
int other( double x ) { return dup( x ); }
EOF

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== --around: the root echoes of= and BOTH bounds, always ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
ROOTEL(){ "$BIN" "$R" "$@" --no-cache 2>/dev/null | sed 's/<!--[^>]*-->//g' | grep -o '<r [^>]*>' | head -1; }

EL="$( ROOTEL --around=mid )"
# RE-PINNED 2026-09-05 (capture-audit P4, lane L7): the default depth is 1 (cli.h aroundDepth; --around-depth=2 restores).
for attr in 'of="mid"' 'depth="1"' 'fanout="32"'; do
    printf '%s' "$EL" | grep -qF "$attr" \
      && ok "--around=mid root carries $attr" \
      || no "--around=mid root has no $attr — the answer's scope is unreadable: $EL"
done

EL="$( ROOTEL --around=mid --around-depth=1 --around-fanout=4 )"
printf '%s' "$EL" | grep -qF 'depth="1"' && printf '%s' "$EL" | grep -qF 'fanout="4"' \
  && ok "--around --around-depth=1 --around-fanout=4: the root echoes the values ACTUALLY used" \
  || no "--around root echoes stale/default bounds: $EL"

# defs= is a single-pick disclosure: present when the seed name has several definitions, absent when it has one.
EL="$( ROOTEL --around=dup )"
printf '%s' "$EL" | grep -qF 'defs="2"' \
  && ok '--around=dup (2 definitions): root carries defs="2"' \
  || no "--around=dup: no defs= — the walk ran from one of two definitions silently: $EL"
EL="$( ROOTEL --around=mid )"
printf '%s' "$EL" | grep -q 'defs=' \
  && no "--around=mid (one definition): defs= emitted where there is no ambiguity: $EL" \
  || ok "--around=mid (one definition): no defs= (absent means unambiguous)"

# the legend defines what it emits (the house rule, and legendcoveragecheck's subject)
# everything BEFORE the <r …> root element is legend (a map legend comment legally contains '>', e.g.
# "absent=>p=is-the-raw-ingest-path", so a `<!--[^>]*-->` extraction silently truncates at the first one).
LEG="$( "$BIN" "$R" --around=dup --no-cache 2>/dev/null | sed 's/<r .*//' )"
for word in 'of=' 'depth=' 'fanout=' 'defs='; do
    printf '%s' "$LEG" | grep -qF "$word" \
      && ok "--around legend defines $word" \
      || no "--around emits $word with no legend clause"
done

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== --connect: a TERMINAL row discloses a multi-definition seed; a Steiner row never does ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
OUT="$( "$BIN" "$R" --connect=dup,top --no-cache 2>/dev/null | sed 's/<!--[^>]*-->//g' )"
printf '%s' "$OUT" | grep -o '<t [^>]*>' | grep -qE 'n="dup"[^>]*defs="2"' \
  && ok '--connect=dup,top: the dup terminal carries defs="2"' \
  || no "--connect: no defs= on an ambiguous terminal: $( printf '%s' "$OUT" | grep -o '<t [^>]*>' | tr '\n' ' ' )"
printf '%s' "$OUT" | grep -o '<t [^>]*>' | grep -qE 'n="top"[^>]*defs=' \
  && no "--connect: defs= emitted on an unambiguous terminal" \
  || ok "--connect: no defs= on the unambiguous terminal (absent means unambiguous)"
printf '%s' "$OUT" | grep -o '<s [^>]*>' | grep -q 'defs=' \
  && no "--connect: a Steiner row carries defs= — nobody selected it, the search found it" \
  || ok "--connect: Steiner rows carry no defs="

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== the two seeded verbs that already complied (the property is the family's) ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
"$BIN" "$R" --path=dup,leaf --no-cache 2>/dev/null | grep -q 'from_defs="2"' \
  && ok '--path=dup,leaf discloses from_defs="2"' \
  || no "--path: no from_defs= for an ambiguous endpoint"
# --slice echoes its resolved seed as sym= (the M1 family attribute), not seed=.
"$BIN" "$R" --slice=mid --no-cache 2>/dev/null | grep -q 'sym="mid"' \
  && ok '--slice=mid echoes its resolved seed as sym="mid"' \
  || no "--slice: the root does not echo the seed"

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== --help names the defaults the root now echoes ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
HELP="$TMP/help.txt"
"$BIN" --help >"$HELP" 2>/dev/null
grep -qF -- '--around-depth=N, default 1' "$HELP" \
  && ok "--help names --around-depth's default" || no "--help still gives no default for --around-depth"
grep -qF -- '--around-fanout=K, default 32' "$HELP" \
  && ok "--help names --around-fanout's default" || no "--help still gives no default for --around-fanout"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
