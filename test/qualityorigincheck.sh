#!/usr/bin/env bash
# qualityorigincheck.sh — gate for the --quality-delta ORIGIN SPLIT (r26): every finding is classified
# `preexisting-worse` (the symbol EXISTED at the baseline and got worse) vs `new-symbol` (the finding exists
# only because the code is NEW), the header carries both counters plus the gating= count, and the EXIT CODE
# is gated on preexisting-worse MAJOR findings only. New-symbol rows stay fully VISIBLE — they are still
# information — they just never gate.
#
# What this pins (each an independently-failing assertion):
#   A. a doctored regression on a symbol that EXISTED at the baseline still exits 2, and its <r> carries no
#      origin= attribute (absent = preexisting-worse);
#   B. a change that adds ONLY new symbols exits 0 while its findings remain PRESENT and carry
#      origin="new-symbol" — including a MAJOR one (proves the split is origin-driven, not a sev= rename);
#   C. on a fixture with a KNOWN MIX, the two header counters are exactly right: new-symbol= equals the
#      number of origin="new-symbol" rows, preexisting-worse= equals the rest, and the two sum to
#      regressions=; gating= equals the rows that are BOTH preexisting and major;
#   D. byte-identical output across two runs on a fixed repo state (the determinism law);
#   E. COMPOSITION with the two pre-existing axes: the ack ratchet still suppresses first (acked="N", and the
#      suppressed finding leaves both origin counters), and the sev="minor" materiality tier still governs
#      among preexisting findings (a minor-only preexisting run exits 0);
#   F. JSON parity — --json carries the same three counters and the same per-row origin.
#
# Everything runs in git-backed temp repos (the auto-baseline-vs-HEAD path), never the real repo.
# Usage:  RIPWIRE_BIN=build/ripwire bash test/qualityorigincheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qualityorigincheck (git required for the HEAD-baseline fixtures)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "qualityorigincheck: BIN=$BIN  (temp git corpora)"

# ── shared fixture helpers ─────────────────────────────────────────────────────────────────────────────
# ifs N: an N-branch if-chain — the standard ccx dial the other quality gates use (ccx ≈ N+1).
ifs(){ n=$1; s=''; i=1; while [ "$i" -le "$n" ]; do s="$s if(a>$i){ s++; }"; i=$(( i + 1 )); done; printf '%s' "$s"; }
newrepo(){ mkdir -p "$1/src"; ( cd "$1" && git init -q && git config user.email t@t && git config user.name t ); }
commitall(){ ( cd "$1" && git add -A >/dev/null 2>&1 && git commit -qm "$2" >/dev/null 2>&1 ); }
dq(){  ( cd "$1" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
ecq(){ ( cd "$1" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }
# hattr OUT NAME → the header's NAME="…" value (header counters are numeric, so the [0-9] class cannot
# collide with a row's origin="new-symbol"/surface="new-symbol" facet value).
hattr(){ printf '%s' "$1" | grep -o "$2=\"[0-9]*\"" | head -1 | cut -d'"' -f2; }
count(){ printf '%s' "$1" | grep -o "$2" | wc -l | tr -d ' '; }
# ROW counters must look at <r/> elements ONLY — the leading XML comment documents the contract and so
# literally contains the string origin="new-symbol"; a whole-output grep would count the documentation.
rowsplit(){ printf '%s' "$1" | tr '>' '\n' | grep '<r '; }
rowcount(){ rowsplit "$1" | wc -l | tr -d ' '; }
newrowcount(){ rowsplit "$1" | grep -c 'origin="new-symbol"' | tr -d ' '; }

# ═══ A) PREEXISTING-WORSE STILL GATES ═══════════════════════════════════════════════════════════════════
#   f() is committed at a modest complexity, then the working tree rewrites it far over the ccx bar. The
#   symbol existed at the baseline, so this is the finding class --quality-delta exists for: it must gate.
P="$WORK/pre"; newrepo "$P"
printf 'int f( int a ){ int s=0;%s return s; }\nint usef(){ return f(1); }\n' "$( ifs 5 )"  > "$P/src/c.cpp"
commitall "$P" init
printf 'int f( int a ){ int s=0;%s return s; }\nint usef(){ return f(1); }\n' "$( ifs 30 )" > "$P/src/c.cpp"
OP="$( dq "$P" )"; EP="$( ecq "$P" )"

[ "$EP" = 2 ] && ok "A: preexisting-worse regression still exits 2" \
    || { no "A: preexisting regression should exit 2 (got $EP)"; printf '%s\n' "$OP" | tr '>' '\n' | grep '<r '; }
rowsplit "$OP" | grep '<r kind="complexity" sym="f"' | grep -q 'origin=' \
    && no "A: a preexisting symbol's row wrongly carries origin= (absent must mean preexisting-worse)" \
    || ok "A: preexisting row carries NO origin= (absent = preexisting-worse)"
[ "$( hattr "$OP" 'preexisting-worse' )" -ge 1 ] 2>/dev/null \
    && ok "A: header preexisting-worse >= 1" || { no "A: header preexisting-worse missing/zero"; printf '%s\n' "$OP" | head -c 400; }
[ "$( hattr "$OP" 'gating' )" -ge 1 ] 2>/dev/null \
    && ok "A: header gating >= 1 (the exit-2 predicate is visible in the header)" || no "A: header gating missing/zero"

# ═══ B) NEW-SYMBOL-ONLY CHANGE IS VISIBLE BUT NON-FATAL ═════════════════════════════════════════════════
#   The working tree adds a brand-new file: a big complex function, its (uncalled) driver, and a new public
#   header decl. Nothing that existed at the baseline got worse — so exit 0 — but every finding must still
#   be PRINTED, classified origin="new-symbol". At least one of them is MAJOR (no sev="minor"): that is the
#   whole point of the split — majorness alone no longer gates, origin does.
N="$WORK/new"; newrepo "$N"
printf 'int keep(){ return 1; }\nint usek(){ return keep(); }\n' > "$N/src/base.cpp"
commitall "$N" init
printf 'int newbig( int a ){ int s=0;%s return s; }\nint drivenew(){ return newbig(1); }\n' "$( ifs 30 )" > "$N/src/new.cpp"
printf 'int brand_new_api( int a );\n' > "$N/src/napi.h"
ON="$( dq "$N" )"; EN="$( ecq "$N" )"

NROWS="$( rowcount "$ON" )"; NNEW="$( newrowcount "$ON" )"
[ "$NROWS" -ge 2 ] && ok "B: new-symbol-only change still REPORTS its findings ($NROWS rows, still visible)" \
    || { no "B: expected the new-code findings to remain visible (got $NROWS rows)"; printf '%s\n' "$ON" | head -c 500; }
[ "$NNEW" = "$NROWS" ] && ok "B: every row classified origin=\"new-symbol\" ($NNEW/$NROWS)" \
    || { no "B: $(( NROWS - NNEW )) row(s) not classified new-symbol"; printf '%s\n' "$ON" | tr '>' '\n' | grep '<r '; }
[ "$EN" = 0 ] && ok "B: new-symbol-only change exits 0 (non-fatal)" \
    || { no "B: new-symbol-only change should exit 0 (got $EN)"; printf '%s\n' "$ON" | tr '>' '\n' | grep '<r '; }
rowsplit "$ON" | grep 'origin="new-symbol"' | grep -qv 'sev="minor"' \
    && ok "B: a MAJOR new-symbol row exists yet the run exits 0 (origin gates, not sev)" \
    || no "B: no major new-symbol row — the fixture no longer proves origin-not-sev gating"
[ "$( hattr "$ON" 'preexisting-worse' )" = 0 ] && ok "B: header preexisting-worse=\"0\"" || no "B: header preexisting-worse should be 0"
[ "$( hattr "$ON" 'gating' )" = 0 ]            && ok "B: header gating=\"0\"" || no "B: header gating should be 0"

# ═══ C) COUNTERS EXACT ON A KNOWN MIX ═══════════════════════════════════════════════════════════════════
#   One repo, both halves at once: f() (committed) is pushed over the ccx bar AND a whole new file lands.
M="$WORK/mix"; newrepo "$M"
printf 'int f( int a ){ int s=0;%s return s; }\nint usef(){ return f(1); }\n' "$( ifs 5 )"  > "$M/src/c.cpp"
commitall "$M" init
printf 'int f( int a ){ int s=0;%s return s; }\nint usef(){ return f(1); }\n' "$( ifs 30 )" > "$M/src/c.cpp"
printf 'int newbig( int a ){ int s=0;%s return s; }\nint drivenew(){ return newbig(1); }\n' "$( ifs 30 )" > "$M/src/new.cpp"
printf 'int brand_new_api( int a );\n' > "$M/src/napi.h"
OM="$( dq "$M" )"; EM="$( ecq "$M" )"

MROWS="$( rowcount "$OM" )"; MNEW="$( newrowcount "$OM" )"
MREG="$( hattr "$OM" 'regressions' )"; MPRE="$( hattr "$OM" 'preexisting-worse' )"; MNEWH="$( hattr "$OM" 'new-symbol' )"
MGATE="$( hattr "$OM" 'gating' )"
# rows that are BOTH preexisting (no origin=) and major (no sev="minor") — the exit-2 predicate, derived.
MGATEROWS="$( rowsplit "$OM" | grep -v 'origin="new-symbol"' | grep -cv 'sev="minor"' | tr -d ' ' )"

[ "$MPRE" -ge 1 ] 2>/dev/null && [ "$MNEWH" -ge 1 ] 2>/dev/null \
    && ok "C: mixed fixture really is mixed (preexisting-worse=$MPRE, new-symbol=$MNEWH)" \
    || { no "C: fixture is not a mix (preexisting-worse=$MPRE new-symbol=$MNEWH)"; printf '%s\n' "$OM" | tr '>' '\n' | grep '<r '; }
[ "$MNEWH" = "$MNEW" ] && ok "C: header new-symbol=\"$MNEWH\" == the origin=\"new-symbol\" row count" \
    || no "C: header new-symbol=$MNEWH but $MNEW rows carry origin=\"new-symbol\""
[ "$MPRE" = "$(( MROWS - MNEW ))" ] && ok "C: header preexisting-worse=\"$MPRE\" == the unclassified-row count" \
    || no "C: header preexisting-worse=$MPRE but $(( MROWS - MNEW )) rows lack origin="
[ "$MREG" = "$(( MPRE + MNEWH ))" ] && [ "$MREG" = "$MROWS" ] \
    && ok "C: preexisting-worse + new-symbol == regressions == printed rows ($MREG)" \
    || no "C: counter sum broken (regressions=$MREG pre=$MPRE new=$MNEWH rows=$MROWS)"
[ "$MGATE" = "$MGATEROWS" ] && ok "C: header gating=\"$MGATE\" == the preexisting-AND-major row count" \
    || no "C: header gating=$MGATE but $MGATEROWS rows are preexisting+major"
[ "$EM" = 2 ] && ok "C: a mix containing a preexisting major finding exits 2" || no "C: mixed run should exit 2 (got $EM)"

# ═══ D) DETERMINISM + WELL-FORMEDNESS ═══════════════════════════════════════════════════════════════════
[ "$OM" = "$( dq "$M" )" ] && ok "D: byte-identical across two runs on a fixed repo state" || no "D: non-deterministic delta"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OM" | xmllint --noout - 2>/dev/null && printf '%s' "$ON" | xmllint --noout - 2>/dev/null \
        && ok "D: xml well-formed with the new attributes (G4)" || no "D: xml malformed"
else
    printf '  SKIP  D: xml well-formed (no xmllint)\n'
fi

# ═══ E) COMPOSITION WITH THE ACK RATCHET AND THE sev= TIER ══════════════════════════════════════════════
#   E1 — the ack ratchet runs FIRST: acking corpus A's preexisting finding removes it from the report
#        entirely, so BOTH origin counters drop to 0 and the gate opens (exit 0, acked="1").
( cd "$P" && "$BIN" . --quality-ack='gate fixture: deliberately accepted' --no-cache >/dev/null 2>&1 )
OPA="$( dq "$P" )"; EPA="$( ecq "$P" )"
{ printf '%s' "$OPA" | grep -q 'acked="1"' && [ "$( hattr "$OPA" 'preexisting-worse' )" = 0 ] && [ "$EPA" = 0 ]; } \
    && ok "E1: ack ratchet still applies BEFORE the origin split (acked=\"1\", preexisting-worse=\"0\", exit 0)" \
    || { no "E1: ack composition broken (exit $EPA)"; printf '%s\n' "$OPA" | head -c 400; }

#   E2 — the sev= materiality tier still governs AMONG preexisting findings: a +1-ccx edit to an
#        already-over-the-bar function is preexisting-worse (counted!) but minor, so it does not gate.
T="$WORK/tier"; newrepo "$T"
printf 'int g( int a ){ int s=0;%s return s; }\nint useg(){ return g(1); }\n' "$( ifs 16 )" > "$T/src/m.cpp"
commitall "$T" init
printf 'int g( int a ){ int s=0;%s return s; }\nint useg(){ return g(1); }\n' "$( ifs 17 )" > "$T/src/m.cpp"
OT="$( dq "$T" )"; ET="$( ecq "$T" )"
{ printf '%s' "$OT" | tr '>' '\n' | grep -q '<r kind="complexity" sym="g".*sev="minor"' \
    && [ "$( hattr "$OT" 'preexisting-worse' )" -ge 1 ] && [ "$( hattr "$OT" 'gating' )" = 0 ] && [ "$ET" = 0 ]; } 2>/dev/null \
    && ok "E2: a MINOR preexisting finding counts as preexisting-worse but does NOT gate (sev tier intact)" \
    || { no "E2: sev/origin composition broken (exit $ET)"; printf '%s\n' "$OT" | tr '>' '\n' | grep '<r \|quality-delta '; }

# ═══ F) JSON PARITY ═════════════════════════════════════════════════════════════════════════════════════
JM="$( cd "$M" && "$BIN" . --quality-delta --json --no-cache 2>/dev/null )"
JPRE="$( printf '%s' "$JM" | grep -o '"preexisting-worse":[0-9]*' | head -1 | cut -d: -f2 )"
JNEW="$( printf '%s' "$JM" | grep -o '"new-symbol":[0-9]*'        | head -1 | cut -d: -f2 )"
JGATE="$( printf '%s' "$JM" | grep -o '"gating":[0-9]*'           | head -1 | cut -d: -f2 )"
JROWNEW="$( count "$JM" '"origin":"new-symbol"' )"
{ [ "$JPRE" = "$MPRE" ] && [ "$JNEW" = "$MNEWH" ] && [ "$JGATE" = "$MGATE" ] && [ "$JROWNEW" = "$MNEW" ]; } \
    && ok "F: --json mirrors the counters + per-row origin (pre=$JPRE new=$JNEW gating=$JGATE rows=$JROWNEW)" \
    || no "F: json parity broken (xml pre=$MPRE new=$MNEWH gating=$MGATE rows=$MNEW | json pre=$JPRE new=$JNEW gating=$JGATE rows=$JROWNEW)"
JEC="$( cd "$M" && "$BIN" . --quality-delta --json --no-cache >/dev/null 2>&1; echo $? )"
[ "$JEC" = "$EM" ] && ok "F: --json exit code matches the XML path ($JEC)" || no "F: json exit $JEC != xml exit $EM"

# ═══ G) MUTATION SELF-TEST — the classifier is not a constant ═══════════════════════════════════════════
#   The SAME shaped finding (a complexity regression far over the bar, major, unacked) gates in corpus A and
#   does not in corpus B; the only difference is whether the symbol existed at HEAD. If a future change made
#   origin constant in either direction, exactly one of these two halves would flip.
{ [ "$EP" = 2 ] && [ "$EN" = 0 ]; } \
    && ok "G: identical finding shape gates when preexisting (exit 2) and not when new (exit 0) — classifier is live" \
    || no "G: the origin classifier looks constant (preexisting exit $EP, new exit $EN)"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
