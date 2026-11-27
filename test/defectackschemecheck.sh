#!/usr/bin/env bash
# defectackschemecheck.sh — CR712-ACK-KEY-MASK: a defect-shape ack written under the TWO-BIT site-value scheme (v0.6.9/v0.6.10:
# defectSiteValue masked `& ~3`) still suppresses its row after QD-UNCHECKED-STATUS widened the facet bits to three (`& ~7`).
# The widening moved every site value whose hash had bit 2 set, and with it the defectRowKey of the row holding it; about half
# of the released format-arity acks stopped matching, so the acked row gated again (exit 2) and the ack was listed stale.
# addDefectFacetSchemeAliases (src/quality.h) re-files such an ack through the SCHEME alias path (acks_rekeyed_by_scheme=).
#
# The fixture is GENERATED here: a one-commit repo whose working tree adds label1(), a format-arity defect (two arguments to a
# one-placeholder std::format). Its two-bit key was recorded from the released v0.6.9 binary (built_from b8c317899); set
# RIPWIRE_LEGACY_BIN to a pre-74dee2e9b binary and arm (r) re-derives it instead of trusting the constant.
#   (p)  PREMISE: an ack the binary under test writes for the same row has a DIFFERENT key (the site moved between schemes;
#        a fixture whose site did not move would pass every arm below vacuously).
#   (l)  LEGACY: the two-bit ack suppresses the row: exit 0, acked="1", stale="0", gating="0", acks_rekeyed_by_scheme="1".
#        Red before the lane (main 8861b0d4d): exit 2, acked="0", stale="1", the format-arity row gates.
#   (c)  CURRENT: the binary's own ack matches directly: exit 0, acked="1", no acks_rekeyed_by_scheme= (no alias needed).
#   (h)  HEAL: --quality-ack over the legacy ledger re-files the row at the current key (the (p) key, reason kept), and the
#        next run needs no alias.
#   (r)  optional, RIPWIRE_LEGACY_BIN: the legacy binary writes the recorded key.
# Usage: test/defectackschemecheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/cache"; mkdir -p "$TMPDIR"
export HOME="$TMP/home"; mkdir -p "$HOME"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "defectackschemecheck: BIN=$BIN"
G=( git -c user.name=t -c user.email=t@t -c commit.gpgsign=false )
LEGACY_KEY=69365bba7ebf69de
LEDGER=.ripwire_quality_acks

# fixture DIR — the one-commit repo plus the working-tree defect
fixture(){ mkdir -p "$1/src"; "${G[@]}" -C "$1" init -q
    printf '#include <format>\n#include <string>\nint drive() { return 1; }\n' >"$1/src/a.cpp"
    "${G[@]}" -C "$1" add -A && "${G[@]}" -C "$1" commit -qm a
    printf '#include <format>\n#include <string>\nstd::string label1( int a )\n{\n    return std::format( "{} 1", a, a );\n}\nint drive() { return 1; }\n' >"$1/src/a.cpp"; }
ackkey(){ grep -E '^ack defect-shape ' "$1/$LEDGER" | awk '{ print $3 }' | tr '\n' ' ' | sed 's/ $//'; }
root(){ grep -oE '<quality-delta [^>]*' "$1"; }
attr(){ root "$2" | grep -oE " $1=\"[0-9]+\"" | grep -oE '[0-9]+'; }
ack(){ ( cd "$1" && "$BIN" . --quality-delta --no-cache --ack-only=format-arity --quality-ack="$2" >/dev/null 2>&1 ); }
run(){ ( cd "$1" && "$BIN" . --quality-delta --no-cache >"$2" 2>/dev/null ); }

# (p) the binary's own key for this row
fixture "$TMP/cur"; ack "$TMP/cur" "current ack"; arc=$?
[ "$arc" = 0 ] || no "(p) --quality-ack on the fresh row exited $arc, want 0"
CUR="$( ackkey "$TMP/cur" )"
if [ -n "$CUR" ] && [ "$CUR" != "$LEGACY_KEY" ]; then ok "(p) the row's current key $CUR differs from its two-bit key $LEGACY_KEY"
else no "(p) want one current key different from $LEGACY_KEY; got '${CUR:-none}' — the fixture no longer exercises a moved site"; fi

# (l) the legacy ledger row, verbatim as v0.6.9 wrote it
fixture "$TMP/leg"
printf 'ack defect-shape %s 1 now=1 was=0 facet=format-arity p=src/a.cpp:3 legacy ack\n' "$LEGACY_KEY" >"$TMP/leg/$LEDGER"
run "$TMP/leg" "$TMP/leg.xml"; rc=$?
a="$( attr acked "$TMP/leg.xml" )"; s="$( attr stale "$TMP/leg.xml" )"; g="$( attr gating "$TMP/leg.xml" )"; k="$( attr acks_rekeyed_by_scheme "$TMP/leg.xml" )"
if [ "$rc" = 0 ] && [ "$a" = 1 ] && [ "$s" = 0 ] && [ "$g" = 0 ] && [ "$k" = 1 ]; then ok "(l) the two-bit ack suppresses its row: rc=0 acked=1 stale=0 gating=0 acks_rekeyed_by_scheme=1"
else no "(l) want rc=0 acked=1 stale=0 gating=0 acks_rekeyed_by_scheme=1; got rc=$rc acked=${a:-?} stale=${s:-?} gating=${g:-?} acks_rekeyed_by_scheme=${k:-absent}"; fi

# (c) the binary's own ack
run "$TMP/cur" "$TMP/cur.xml"; rc=$?
a="$( attr acked "$TMP/cur.xml" )"; k="$( attr acks_rekeyed_by_scheme "$TMP/cur.xml" )"
if [ "$rc" = 0 ] && [ "$a" = 1 ] && [ -z "$k" ]; then ok "(c) the current-key ack matches directly: rc=0 acked=1, no acks_rekeyed_by_scheme="
else no "(c) want rc=0 acked=1 and no acks_rekeyed_by_scheme=; got rc=$rc acked=${a:-?} acks_rekeyed_by_scheme=${k:-absent}"; fi

# (h) re-ack heals the legacy row forward
ack "$TMP/leg" "re-ack"   # status: exits 1 by design (the row is already acked through the alias: nothing new to accept); (h) judges the ledger it re-serialised
HK="$( ackkey "$TMP/leg" )"; reason="$( grep -cE '^ack defect-shape .* legacy ack$' "$TMP/leg/$LEDGER" )"
run "$TMP/leg" "$TMP/heal.xml"; rc=$?; k="$( attr acks_rekeyed_by_scheme "$TMP/heal.xml" )"
if [ "$HK" = "$CUR" ] && [ "$reason" = 1 ] && [ "$rc" = 0 ] && [ -z "$k" ]; then ok "(h) --quality-ack re-filed the row at $HK with its reason; the next run needs no alias"
else no "(h) want the ledger at $CUR with the legacy reason and a later run without acks_rekeyed_by_scheme=; got key='${HK:-none}' reason-rows=$reason rc=$rc acks_rekeyed_by_scheme=${k:-absent}"; fi

# (r) optional: re-derive the recorded key with a two-bit binary
if [ -n "${RIPWIRE_LEGACY_BIN:-}" ]; then
    fixture "$TMP/rec"; ( cd "$TMP/rec" && "$RIPWIRE_LEGACY_BIN" . --quality-delta --no-cache --ack-only=format-arity --quality-ack="legacy ack" >/dev/null 2>&1 )   # status: (r) judges the key the legacy binary wrote, not its exit
    RK="$( ackkey "$TMP/rec" )"
    if [ "$RK" = "$LEGACY_KEY" ]; then ok "(r) $RIPWIRE_LEGACY_BIN writes the recorded two-bit key $RK"; else no "(r) $RIPWIRE_LEGACY_BIN wrote '${RK:-none}', the recorded key is $LEGACY_KEY"; fi
fi

[ "$fail" = 0 ] && echo "defectackschemecheck: PASS" || echo "defectackschemecheck: FAIL"
exit "$fail"
