#!/usr/bin/env bash
# communitydrillcheck.sh — gate for --community=ID.
#
# THE GAP: --communities and --zoom PRINT module ids (id="2006" size="274") and NO verb accepted one. A
# 274-member module showed five members and there was no next call — the §P8 selector-chain gap at module
# granularity, on the two verbs whose whole output is module ids. --community=ID closes it: given an id
# from that output, the module's ranked members (paged) and its bridge edges to other modules.
#
# The gate's spine is the PARENT/CHILD AGREEMENT: the drill-down's member count must equal the size= the
# parent claimed for that id. If the two ever disagree, one of them is lying about the partition, and a
# reader has no way to tell which — the failure mode a "just print the members" implementation invites,
# because it is invisible in either output read alone.
#
# Run against test/zoomfix (the fixture communitylabelcheck/zoomcheck already use — a corpus with enough
# structure to produce several multi-member modules and real bridges) plus this repo for scale.
#
# Usage:  bash test/communitydrillcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash test/communitydrillcheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/zoomfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "communitydrillcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

run(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$CORPUS" "$@" --no-cache 2>/dev/null; }
attr(){ printf '%s' "$2" | grep -oE " $1=\"[^\"]*\"" | head -1 | sed "s/ $1=\"//;s/\"//"; }

C="$( run --communities )"

# ── 0) the drill-down is DISCOVERABLE from the output that emits the ids ──────────────────────────────
# A verb nothing points at is a verb nobody calls. The parent's own header names the child.
case "$C" in *'--community=ID'*) ok "--communities header names --community=ID (the drill-down is discoverable)" ;;
             *) no "--communities header does not name --community=ID" ;; esac

# take the FIRST (largest) module the parent listed, with its claimed size
ID="$(   printf '%s' "$C" | grep -oE '<community id="[0-9]+" size="[0-9]+"' | head -1 | grep -oE 'id="[0-9]+"'   | grep -oE '[0-9]+' )"
SIZE="$( printf '%s' "$C" | grep -oE '<community id="[0-9]+" size="[0-9]+"' | head -1 | grep -oE 'size="[0-9]+"' | grep -oE '[0-9]+' )"
[ -n "$ID" ] && [ -n "$SIZE" ] && [ "$SIZE" -ge 2 ] \
    && ok "--communities offered a drillable id ($ID, size=$SIZE)" \
    || { no "could not read an id/size pair out of --communities"; echo "FAILURES ABOVE"; exit 1; }

D="$( run --community="$ID" --limit=1000 )"

# ── 1) PARENT/CHILD AGREEMENT — the member count IS the size= the parent claimed ──────────────────────
rows="$( printf '%s' "$D" | grep -o '<member ' | wc -l | tr -d ' ' )"
{ [ "$( attr size "$D" )" = "$SIZE" ] && [ "$rows" = "$SIZE" ]; } \
    && ok "--community=$ID: size=$SIZE and exactly $SIZE <member> rows — the parent's claim, kept" \
    || no "parent/child disagreement: parent size=$SIZE, child size=$( attr size "$D" ), rows=$rows"

# ── 1b) the parent's dir=/label= for that id are the same facts, not a second derivation ──────────────
PL="$( printf '%s' "$C" | grep -oE "<community id=\"$ID\" size=\"[0-9]+\" dir=\"[^\"]*\" label=\"[^\"]*\"" | head -1 )"
{ [ "$( attr dir "$D" )" = "$( attr dir "$PL" )" ] && [ "$( attr label "$D" )" = "$( attr label "$PL" )" ]; } \
    && ok "--community=$ID: dir=/label= match --communities' row for the same id" \
    || no "dir/label drift (child dir=$( attr dir "$D" ) label=$( attr label "$D" ) vs parent $PL)"

# ── 1c) §A8.6: modules= AGREES between parent and child (SAME predicate, size>=2), and the child's
# partition= is the FULL label space — the number the refusal's "valid ids are 0..N-1" already uses.
# Pre-fix, the child's `modules=` meant the FULL partition count (K), a different quantity from the
# parent's `modules=` (non-isolated only) under the identical attribute name.
PARENT_MODULES="$( attr modules "$C" )"
CHILD_MODULES="$(  attr modules "$D" )"
CHILD_PARTITION="$( attr partition "$D" )"
REFUSAL_N="$( "$BIN" "$CORPUS" --community=999999 --no-cache 2>&1 >/dev/null | grep -oE '0\.\.[0-9]+' | sed -E 's/^0\.\.//' )"
[ -n "$CHILD_PARTITION" ] \
    && ok "--community=$ID: carries partition= ($CHILD_PARTITION, the full label space)" \
    || no "--community=$ID: missing partition="
{ [ -n "$PARENT_MODULES" ] && [ -n "$CHILD_MODULES" ] && [ "$PARENT_MODULES" = "$CHILD_MODULES" ]; } \
    && ok "--community=$ID: modules=$CHILD_MODULES agrees with --communities' modules=$PARENT_MODULES" \
    || no "modules= disagreement: parent=$PARENT_MODULES child=$CHILD_MODULES"
{ [ -n "$CHILD_PARTITION" ] && [ -n "$REFUSAL_N" ] && [ "$(( CHILD_PARTITION - 1 ))" = "$REFUSAL_N" ]; } \
    && ok "--community=$ID: partition-1=$(( CHILD_PARTITION - 1 )) == the refusal's max valid id ($REFUSAL_N)" \
    || no "partition= disagrees with the refusal's valid range (partition=$CHILD_PARTITION refusal max=$REFUSAL_N)"

# ── 2) the members are RANK-ORDERED, and the parent's top-5 preview is this listing's head ────────────
# The preview and the drill-down must be one ordering, or the "top members" a reader saw are not the top.
PREV="$( printf '%s' "$C" | sed 's/<community /\n<community /g' | grep "id=\"$ID\"" | grep -oE '<member [^>]*n="[^"]*"' | grep -oE 'n="[^"]*"' | head -5 | tr '\n' ',' )"
HEAD5="$( printf '%s' "$D" | grep -oE '<member [^>]*n="[^"]*"' | grep -oE 'n="[^"]*"' | head -5 | tr '\n' ',' )"
[ -n "$PREV" ] && [ "$PREV" = "$HEAD5" ] \
    && ok "--community=$ID: the first 5 members ARE --communities' preview (one ordering, not two)" \
    || no "member ordering diverges from the parent preview (parent='$PREV' child='$HEAD5')"

# ── 3) BRIDGES: the module's edges to OTHER modules are present and never self-referential ────────────
BR="$( printf '%s' "$D" | grep -o '<bridge ' | wc -l | tr -d ' ' )"
[ "$BR" -ge 1 ] \
    && ok "--community=$ID: $BR bridge row(s) to other modules" \
    || no "--community=$ID emitted no bridges (the fixture has cross-module edges)"
case "$D" in *"<bridge to=\"$ID\""*) no "a bridge points at the module itself" ;;
             *) ok "no self-bridge (a module never bridges to itself)" ;; esac

# ── 4) PAGING (pageview.h's one vocabulary), on the member listing ────────────────────────────────────
P1="$( run --community="$ID" --limit=2 )"
p1rows="$( printf '%s' "$P1" | grep -o '<member ' | wc -l | tr -d ' ' )"
{ [ "$p1rows" = 2 ] && [ "$( attr shown "$P1" )" = 2 ] && [ "$( attr capped "$P1" )" = 1 ] \
  && [ "$( attr total "$P1" )" = "$SIZE" ] && [ "$( attr has_more "$P1" )" = 1 ] && [ "$( attr next_offset "$P1" )" = 2 ]; } \
    && ok "--community --limit=2: 2 rows + the full six-attribute paging disclosure" \
    || no "--community paging wrong (rows=$p1rows shown=$( attr shown "$P1" ) capped=$( attr capped "$P1" ) total=$( attr total "$P1" ) has_more=$( attr has_more "$P1" ) next_offset=$( attr next_offset "$P1" ))"
P2="$( run --community="$ID" --limit=2 --offset=2 )"
A1="$( printf '%s' "$P1" | grep -oE '<member [^>]*p="[^"]*"' | tr '\n' ',' )"
A2="$( printf '%s' "$P2" | grep -oE '<member [^>]*p="[^"]*"' | tr '\n' ',' )"
[ -n "$A2" ] && [ "$A1" != "$A2" ] \
    && ok "--community --offset=2 is the continuation, not a re-served page 0" \
    || no "--community offset seam broken (page0='$A1' page1='$A2')"

# ── 5) an UNKNOWN id REFUSES, naming the valid range and the nearest id ───────────────────────────────
# §P0: a module id that does not exist is a typo, not an empty module. The message has to be actionable —
# the caller holds a number and needs to know which numbers are legal.
perl -e 'alarm 30; exec @ARGV' "$BIN" "$CORPUS" --community=999999 --no-cache >/dev/null 2>"$TMP/err.txt"; XEC=$?
E="$( cat "$TMP/err.txt" )"
[ "$XEC" = 1 ] && ok "--community=999999 exits 1 (refusal, not an empty module)" || no "--community unknown id exit=$XEC (want 1)"
case "$E" in *0..*) RE=1 ;; *) RE=0 ;; esac
case "$E" in *neares*) NE=1 ;; *) NE=0 ;; esac
{ [ "$RE" = 1 ] && [ "$NE" = 1 ]; } \
    && ok "--community unknown-id refusal names the valid range AND the nearest id: $E" \
    || no "--community unknown-id refusal incomplete: $E"

# a NON-NUMERIC id is the other typo shape and must not be read as 0
perl -e 'alarm 30; exec @ARGV' "$BIN" "$CORPUS" --community=abc --no-cache >/dev/null 2>"$TMP/err2.txt"; XEC2=$?
[ "$XEC2" = 1 ] \
    && ok "--community=abc exits 1 (a non-numeric id is not silently read as module 0): $( cat "$TMP/err2.txt" )" \
    || no "--community=abc exit=$XEC2 (want 1)"

# a bare --community (no value) refuses loudly rather than falling through to the default map
perl -e 'alarm 30; exec @ARGV' "$BIN" "$CORPUS" --community --no-cache >/dev/null 2>"$TMP/err3.txt"; XEC3=$?
{ [ "$XEC3" = 1 ] && [ -s "$TMP/err3.txt" ]; } \
    && ok "bare --community refuses loudly: $( cat "$TMP/err3.txt" )" \
    || no "bare --community exit=$XEC3 err='$( cat "$TMP/err3.txt" )'"

# ── 6) --community and --communities are DIFFERENT flags (no prefix collision in the parser) ──────────
[ "$( run --communities )" = "$C" ] \
    && ok "--communities still means --communities (the new flag did not shadow it)" \
    || no "--communities output changed shape — prefix collision with --community="

# ── 7) determinism + G4 ──────────────────────────────────────────────────────────────────────────────
[ "$( run --community="$ID" --limit=1000 )" = "$D" ] \
    && ok "--community deterministic (byte-identical run-to-run)" || no "--community non-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$D" | xmllint --noout - 2>/dev/null && ok "--community xml well-formed" || no "--community xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── 8) the same agreement at REPO scale, where the largest module has hundreds of members ─────────────
RC="$( perl -e 'alarm 120; exec @ARGV' "$BIN" "$ROOT" --communities 2>/dev/null )"
RID="$(  printf '%s' "$RC" | grep -oE '<community id="[0-9]+" size="[0-9]+"' | head -1 | grep -oE 'id="[0-9]+"'   | grep -oE '[0-9]+' )"
RSIZE="$( printf '%s' "$RC" | grep -oE '<community id="[0-9]+" size="[0-9]+"' | head -1 | grep -oE 'size="[0-9]+"' | grep -oE '[0-9]+' )"
RD="$( perl -e 'alarm 120; exec @ARGV' "$BIN" "$ROOT" --community="$RID" --limit=100000 2>/dev/null )"
rrows="$( printf '%s' "$RD" | grep -o '<member ' | wc -l | tr -d ' ' )"
{ [ "$rrows" = "$RSIZE" ] && [ "$( attr size "$RD" )" = "$RSIZE" ]; } \
    && ok "repo: --community=$RID emits exactly the $RSIZE members --communities claimed" \
    || no "repo parent/child disagreement (claimed $RSIZE, got $rrows rows, size=$( attr size "$RD" ))"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
