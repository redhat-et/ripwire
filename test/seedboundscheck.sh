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
echo "=== a BOUNDED traversal discloses the bound that BIT, not only the bound that was SET ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
# THE SECOND DEFECT, one round on from the first (harvest B card C2, 2026-09-05). M20 above made the BOUND
# readable: --around's root now carries depth= and fanout=. It did not make the BITE readable. The gate's own
# framing above says the reader "could not tell 'X is not in this neighbourhood' from 'X was outside the
# fanout'" — with the bound echoed but no bite flag that sentence is STILL true, because a reader handed
# fanout="32" cannot tell whether 32 was a ceiling that never bound or a knife that cut.
#
# MEASURED on db6a416d, this repo:  --around=buildGraph                     → 31 <s> rows
#                                   --around=buildGraph --around-fanout=200 → 72 <s> rows
# 41 direct neighbours dropped, and nothing in the answer says so. The verb's own legend claims "a row's
# absence means outside them, not nonexistent" — true, but unactionable: it cannot tell the agent whether
# raising the bound would return anything, which is the whole "can I ask for more?" question.
#
# THE FAMILY is every traversal with a settable bound, and the property is stated in both directions: the
# attribute appears when the bound cut, and is ABSENT when it did not (an always-present flag carries no
# information). --slice-flow (flow_truncated="1") and --connect (truncated="paths", <unconnected radius=>)
# already comply and are asserted here because the property belongs to the family, not to --around.
#
# RED-FIRST (base binary db6a416d): both --around arms; the --slice-flow and --connect arms pass on it.
R2="$TMP/hub"; mkdir -p "$R2"
cat > "$R2/hub.cpp" <<'EOF'
int n1( int x ) { return x + 1; }
int n2( int x ) { return x + 2; }
int n3( int x ) { return x + 3; }
int n4( int x ) { return x + 4; }
int n5( int x ) { return x + 5; }
int n6( int x ) { return x + 6; }
int hub( int x ) { return n1( x ) + n2( x ) + n3( x ) + n4( x ) + n5( x ) + n6( x ); }
int mid2( int x ) { return hub( x ); }
int top2( int x ) { return mid2( x ); }
EOF
ROOT2(){ "$BIN" "$R2" "$@" --no-cache 2>/dev/null | sed 's/<!--[^>]*-->//g' | grep -o '<r [^>]*>' | head -1; }

# Three runs over ONE fixture isolate the two bounds from each other, which is the property that makes each
# attribute worth reading: a single "something was cut" flag would not tell the agent WHICH knob to turn.
#
#  1) fanout alone.  --around=hub --around-fanout=2 --around-depth=9: hub has 7 undirected neighbours
#     (6 callees + mid2) so the cap cuts 5, and hub is their ONLY route, so no later hop re-admits them —
#     fanout_cut="5", exactly. The depth is deliberately generous: the walk exhausts what the cap left it,
#     so depth_truncated must be ABSENT even though 5 symbols are missing. Wrong attribution is a failure.
EL="$( ROOT2 --around=hub --around-depth=9 --around-fanout=2 )"
printf '%s' "$EL" | grep -qF 'fanout_cut="5"' \
  && ok '--around fanout=2 on a 7-neighbour hub: root discloses fanout_cut="5" (exact, not a floor)' \
  || no "--around: the fanout cap cut 5 symbols and the answer does not say so — 'X is absent' is unreadable: $EL"
printf '%s' "$EL" | grep -q 'depth_truncated=' \
  && no "--around: a FANOUT cut is reported as a DEPTH truncation — the agent would raise the wrong knob: $EL" \
  || ok "--around depth=9 fanout=2: no depth_truncated= (the walk exhausted what the cap left it)"

#  2) depth alone.  --around=n1 --around-depth=1 --around-fanout=50: n1's one neighbour is hub, whose other
#     seven neighbours sit one hop further out. Nothing is capped; the depth bound alone ends the walk.
EL="$( ROOT2 --around=n1 --around-depth=1 --around-fanout=50 )"
printf '%s' "$EL" | grep -qF 'depth_truncated="1"' \
  && ok '--around depth=1 with symbols one hop further out: root discloses depth_truncated="1"' \
  || no "--around: the depth bound left reachable symbols out and the answer does not say so: $EL"
printf '%s' "$EL" | grep -q 'fanout_cut=' \
  && no "--around: fanout_cut= reported where fanout=50 could not bind on a 1-neighbour seed: $EL" \
  || ok "--around depth=1 fanout=50: no fanout_cut= (the cap never bound)"

#  3) neither.  Bounds wide enough to bind nothing emit NEITHER attribute — presence has to mean something,
#     and an unclipped neighbourhood must stay byte-identical to the pre-C2 output.
EL="$( ROOT2 --around=hub --around-depth=9 --around-fanout=50 )"
printf '%s' "$EL" | grep -q 'fanout_cut=' \
  && no "--around: fanout_cut= emitted where the cap never bound — the flag is noise: $EL" \
  || ok "--around fanout=50: no fanout_cut= (absent means the cap never bound)"
printf '%s' "$EL" | grep -q 'depth_truncated=' \
  && no "--around: depth_truncated= emitted where the walk exhausted the component: $EL" \
  || ok "--around depth=9: no depth_truncated= (absent means the walk reached the end)"

# the legend defines what it emits (the house rule, legendcoveragecheck's subject)
LEG="$( "$BIN" "$R2" --around=hub --around-depth=1 --around-fanout=2 --no-cache 2>/dev/null | sed 's/<r .*//' )"
for word in 'depth_truncated=' 'fanout_cut='; do
    # charged where the attribute is (the at= rule): the clause must be ABSENT from an unclipped run too,
    # asserted just below — a legend the default map pays for is the defect this house rule exists to stop.
    printf '%s' "$LEG" | grep -qF "$word" \
      && ok "--around legend defines $word" \
      || no "--around emits $word with no legend clause"
done
LEG="$( "$BIN" "$R2" --around=hub --around-depth=9 --around-fanout=50 --no-cache 2>/dev/null | sed 's/<r .*//' )"
printf '%s' "$LEG" | grep -qE 'depth_truncated=|fanout_cut=' \
  && no "--around: an unclipped walk still pays for the bite legend — charge the clause where the attributes are" \
  || ok "--around: an unclipped walk carries no bite clause (zero bytes when neither bound bit)"

# --- the family members that already comply -------------------------------------------------------------
# --slice-flow: depth= is the bound, flow_truncated="1" is the bite. Both halves, on the same symbol.
SL(){ "$BIN" "$ROOT" --slice=connectSubgraph:res --slice-flow=both "$@" --no-cache 2>/dev/null | grep -o '<slice [^>]*>' | head -1; }
printf '%s' "$( SL --slice-depth=1 )" | grep -qF 'flow_truncated="1"' \
  && ok '--slice-flow --slice-depth=1: discloses flow_truncated="1"' \
  || no "--slice-flow: a depth-1 flow slice does not disclose its truncation"
printf '%s' "$( SL --slice-depth=32 )" | grep -q 'flow_truncated=' \
  && no "--slice-flow --slice-depth=32: flow_truncated= emitted where the bound never bound" \
  || ok "--slice-flow --slice-depth=32: no flow_truncated= (absent means the flow closed)"

# --connect: radius= rides the root AND every <unconnected> block, so an empty join names the bound in force.
# hub—mid2—top2 is two undirected hops, so radius 1 cannot join them: the emptiness IS radius-scoped.
UNC="$( "$BIN" "$R2" --connect=hub,top2 --connect-radius=1 --no-cache 2>/dev/null | sed 's/<!--[^>]*-->//g' )"
printf '%s' "$UNC" | grep -qE '<connect [^>]*radius="1"' \
  && ok '--connect: the root echoes the radius actually searched' \
  || no "--connect: the root does not echo radius=: $( printf '%s' "$UNC" | grep -o '<connect [^>]*>' )"
printf '%s' "$UNC" | grep -qE '<unconnected [^>]*radius="1"' \
  && ok '--connect: an <unconnected> block names the radius its emptiness is scoped to' \
  || no "--connect: <unconnected> does not name the bound — 'no join' reads as 'no join exists'"

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
