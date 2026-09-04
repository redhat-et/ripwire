#!/usr/bin/env bash
# accessshapecheck.sh — gate for src/accessshape.h (Phase A of the access-shape / chase-pointer
# colocation design, docs/FIELDAFFINITY.md §9), exercised through --field-affinity (Phase A
# ships no CLI flag of its own — see fieldaffinity.h's file-header addendum for why).
#
# Fixture test/accessshapefix/ pins the FOUR discriminating traps the design's correctness review named
# as required, plus one demo per DISCLOSED refusal cause (ambiguous / zero-owner / non-pointer sole
# owner — each with its own counter, so no refusal is ever tallied under another's cause label):
#   indexWalk    for(LinkedNode* p=first; p!=first+n; ++p) p->payload=0;        -> index  (arrow in the
#                BODY must NOT leak into the classification — the advance is pointer arithmetic on p)
#   chaseWalk    for(LinkedNode* p=head; p; p=p->next) p->payload=0;            -> chase  (next IS the
#                enclosing struct's own type -> shape_conf="self-ref")
#   iteratorWalk for(auto it=v; it!=v+n; ++it) it->payload=0;                   -> unknown (auto has no
#                pointer_declarator -> fails closed, docs/FIELDAFFINITY.md §9.6 (2)'s stated default)
#   mixedWalk    for(LinkedNode* p=head,*idx=first; p; p=p->next,++idx) …       -> mixed  (ONE loop, BOTH
#                signals, via a comma-expression update clause)
#   stepperWalk  for(; s; s=s->step) s->val=0;  (StepperA::step, but StepperB ALSO declares `step`)      ->
#                a real chase advance whose FIELD must still be REFUSED (as_stem_ambiguous, no <f n="step">
#                chase attribute anywhere) — "refuse rather than guess", the same convention amb_skipped=
#                already enforces for fieldaffinity.h's own member-access attribution.
#   hopWalk      for(Opaque* p=h; p; p=p->hop) …  (Opaque only ever forward-declared)                    ->
#                chase through a type with NO modeled owner: as_stem_unowned, never mislabeled ambiguous.
#   ledgerWalk   for(Opaque* p=h; p; p=p->link) … (`link` solely owned by Ledger — as a plain int)       ->
#                chase refused because the sole owner's type cannot point: as_stem_nonptr, and
#                Ledger::link must never carry chase="1" (the pre-fix silent-misattribution bug).
#
# Also pins the REPORT-ONLY contract: sepcost= must be IDENTICAL whether or not Phase A/B code exists at
# all (kChaseSepCostBoostApplied is a locked 1.0 no-op) — checked by hand-deriving LinkedNode's sepcost
# from Chilimbi's own formula, not by trusting the binary's own number.
#
# Usage:  bash test/accessshapecheck.sh [BIN]  |  RIPWIRE_BIN=build/ripwire bash test/accessshapecheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/accessshapefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/accessshapefix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "accessshapecheck: BIN=$BIN  CORPUS=test/accessshapefix"

"$BIN" "$FIX" --field-affinity --no-cache >"$TMP/out.xml" 2>"$TMP/err.txt"; rc=$?
[ "$rc" = 0 ] || { echo "  FAIL  --field-affinity exited $rc"; cat "$TMP/err.txt"; exit 1; }
OUT="$( cat "$TMP/out.xml" )"

sect(){ printf '%s' "$OUT" | tr '<' '\n' | awk -v want="$1" '
    /^s n="/ { inside = ( $0 ~ ("^s n=\"" want "\"") ) }
    inside   { print }
'; }
has(){ printf '%s' "$1" | grep -q -- "$2"; }
header(){ printf '%s' "$OUT" | grep -o '<fieldaffinity [^>]*>'; }

# ── 1) the header's loop-shape counters, hand-counted from walks.cpp's seven loop functions ────────────
H="$( header )"
if has "$H" 'as_loops="7"' && has "$H" 'as_index="1"' && has "$H" 'as_chase="4"' \
   && has "$H" 'as_mixed="1"' && has "$H" 'as_unknown="1"'
then ok 'as_loops=7 splits 1 index / 4 chase / 1 mixed / 1 unknown, matching the seven loop functions by hand'
else no 'access-shape loop counters wrong'; printf '%s\n' "$H"
fi

# ── 2) each refusal cause carries ITS OWN counter — no cause is ever tallied under another's label ──────
if has "$H" 'as_stem_ambiguous="1"'
then ok 'as_stem_ambiguous=1 — StepperA/StepperB both declaring `step` is caught'
else no 'as_stem_ambiguous missing/wrong — the ambiguous chase field was not refused'; printf '%s\n' "$H"
fi
if printf '%s' "$OUT" | grep -q 'n="step"[^/]*chase='
then no 'a <f n="step"> row carries a chase attribute — an ambiguous field name must NEVER be flagged'
else ok 'no <f n="step"> row carries chase="1" — the refusal held'
fi
if has "$H" 'as_stem_unowned="1"'
then ok 'as_stem_unowned=1 — hopWalk chasing a forward-declared type is refused under its OWN cause, not "ambiguous"'
else no 'as_stem_unowned missing/wrong — the zero-owner chase field was mislabeled or dropped'; printf '%s\n' "$H"
fi
if has "$H" 'as_stem_nonptr="1"'
then ok 'as_stem_nonptr=1 — Ledger (sole owner of `link`, as an int) is refused: its type cannot point'
else no 'as_stem_nonptr missing/wrong — the non-pointer sole owner was not refused'; printf '%s\n' "$H"
fi
if printf '%s' "$OUT" | grep -q 'n="link"[^/]*chase='
then no 'Ledger::link (a plain int) carries a chase attribute — the silent-misattribution bug is back'
else ok 'no <f n="link"> row carries chase="1" — a loop over an unmodeled type cannot decorate an int field'
fi

# ── 3) LinkedNode::next is the CONFIRMED self-ref chase target, loops=2 (chaseWalk + mixedWalk) ─────────
L="$( sect LinkedNode )"
if has "$L" 'n="next" acc="2" fns="2" sz="8" off="8" ln="0" chase="1" loops="2" shape_conf="self-ref"'
then ok 'LinkedNode::next is chase="1" loops="2" shape_conf="self-ref" (the type IS the enclosing struct)'
else no 'LinkedNode::next chase disclosure wrong'; printf '%s\n' "$L" | grep '^f '
fi
if printf '%s' "$L" | grep '^f n="payload"' | grep -q 'chase='
then no 'payload (never a chase-advance field) incorrectly carries a chase attribute'
else ok 'payload carries no chase attribute — only the actual advance field is flagged'
fi

# ── 4) REPORT-ONLY: sepcost is the plain Chilimbi number, unmodified by any chase boost ─────────────────
# dist(payload,next) = 8, wt = (64-8)/64 = 0.875 -> displayed 0.88; fns=2 (chaseWalk + mixedWalk both
# touch payload AND next) -> sepCost = fns * (1 - wt) = 2 * 0.125 = 0.25 EXACTLY, boost=1.0 either way.
if has "$L" 'sepcost="0.25"' && has "$L" 'dist="8" wt="0.88"'
then ok 'sepcost=0.25 is the UNBOOSTED Chilimbi number (kChaseSepCostBoostApplied is a locked 1.0 no-op)'
else no 'sepcost/wt arithmetic wrong — Phase B may have silently started affecting ranking'; printf '%s\n' "$L" | grep '^pair\|^s n'
fi

# ── 5) no CLI surface: Phase A ships no new flag (docs/FIELDAFFINITY.md §9.1's "extend, don't ship a new flag") ────────────
if "$BIN" --help 2>&1 | grep -qi -- '--access-shape'
then no '--access-shape appeared in --help — the plan calls for extending --field-affinity, not a new flag'
else ok 'no --access-shape flag exists — Phase A is --field-affinity-only, per the plan'
fi

# ── 6) MUTATION self-tests: the two most plausible bugs MUST trip their assertions ─────────────────────
# (a) swapped index/chase counts: the exact-attribute check in (1) must FAIL on the swapped header.
MUT_SWAP="$( printf '%s' "$H" | sed 's/as_index="1" as_chase="2"/as_index="2" as_chase="1"/' )"
if printf '%s' "$MUT_SWAP" | grep -q 'as_index="1" as_chase="2"'
then no 'mutation self-test (swap): swapped index/chase header still passes the (1) grep — assertion is decoration'
else ok 'mutation self-test (swap): swapped index/chase header correctly FAILS the (1) assertion'
fi
# (b) dropped shape_conf: strip it from LinkedNode::next; the (3) exact-attribute check must FAIL on it.
MUT_CONF="$( printf '%s' "$L" | sed 's/ shape_conf="self-ref"//' )"
if printf '%s' "$MUT_CONF" | grep -q 'n="next" acc="2" fns="2" sz="8" off="8" ln="0" chase="1" loops="2" shape_conf="self-ref"'
then no 'mutation self-test (shape_conf): stripped attribute still passes the (3) grep — assertion is decoration'
else ok 'mutation self-test (shape_conf): stripped shape_conf correctly FAILS the (3) assertion'
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
