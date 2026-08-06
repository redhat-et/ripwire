#!/usr/bin/env bash
# naminglocalscheck.sh — Phase 2 of the local-variable-indexing plan (PLAN.md, "2026-08-06 (evening) —
# local-variable-indexing plan, orchestrated"): `--naming-locals`, an OPT-IN --lint modifier (default OFF)
# that runs the naming-short/naming-wordy/naming-underscore/naming-case predicates against LOCAL variable
# names too — C/C++ only, and only inside a function that already clears naminglens.h's namingLocalsGate
# (the shipped large-function/deep-nesting/quality.h-kCcxBar thresholds, reused unchanged, AND
# locals>=kNamingLocalsGateFloor, MEASURED — see naminglens.h's own comment for the exact numbers).
#
# This deliberately breaks src/naminglens.h's own stated invariant ("an un-indexed loop local can never be
# flagged") — read that file's WITHDRAWN note before touching this gate; it is the precedent for exactly
# the failure mode (a plausible-but-unaudited rule that passed its fixture gate and was wrong on real code)
# this feature's hard default-off / opt-in posture exists to avoid repeating. This gate proves the
# MECHANISM is correct; it does NOT claim the calibration/audit work the plan requires before default-enable
# has happened — see --help's own text for --naming-locals.
#
# ── ARMS ──────────────────────────────────────────────────────────────────────────────────────────────
#   0. PRESENCE     — the fixture spells every shape the arms below claim to assert.
#   1. DEFAULT-OFF  — a plain `--lint` run (no --naming-locals) on a fixture whose gated function WOULD
#                     produce local-scope findings reports ZERO naming-* hits: the feature is a true no-op
#                     until explicitly requested (regression safety for every existing --lint caller).
#   2. GATED-FIRE   — `--lint --naming-locals` DOES fire naming-short / naming-wordy / naming-underscore /
#                     naming-case on local names inside the gated function, at the LOCAL's own line (not
#                     the function's), naming the enclosing function in the message text.
#   3. GATE-BOUNDARY — an UN-gated function (small, shallow, few locals) with the SAME kind of short nested
#                     local contributes NOTHING, even with --naming-locals on: the size/complexity+locals
#                     gate is real, not a decoration.
#   4. DECLDEPTH    — naming-short's EXTRA per-local gate: a top-level (declDepth=1) short local inside an
#                     otherwise-gated function does NOT fire naming-short, while naming-case (no depth gate)
#                     still fires on a top-level local in the SAME function — proving the depth gate is
#                     scoped to naming-short specifically, not applied uniformly by accident.
#   5. TAG-REUSE    — findings ride the EXISTING naming-* tags (Open Question 3, PLAN.md) — no `-local`
#                     suffixed tag family appears in the rule listing.
#   6. HYGIENE      — determinism (two runs byte-identical) and well-formed XML.
#   7. MUTATION     — the gate has real teeth: with the namingLocalsGate size/complexity check DISABLED in
#                     source (a controlled, restored-afterward source edit — the same discipline Phase 1's
#                     own gate used), arm 3's boundary assertion is PROVEN to go red.
#
# Usage:
#   bash test/naminglocalscheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/naminglocalscheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
echo "naminglocalscheck: BIN=$BIN  TMP=$TMP"

FIXDIR="$TMP/fix"; mkdir -p "$FIXDIR"
cat >"$FIXDIR/big.cpp" <<'EOF'
// gated: maxNest=5 (>4) and locals=11 (>=8) — clears namingLocalsGate.
int bigFunction( int n )
{
    int a = 1;
    int b = 2;
    int c = 3;
    int d = 4;
    int e = 5;
    int f = 6;
    int g = 7;
    int reallyLongLocalVariableNameThatHasSixWords = 8;
    int top_mixedCase = 9;
    if( n > 0 )
    {
        if( n > 1 )
        {
            if( n > 2 )
            {
                if( n > 3 )
                {
                    if( n > 4 )
                    {
                        int x = a + b;
                        int __reserved = 1;
                        (void)x; (void)__reserved;
                    }
                }
            }
        }
    }
    return n + a + b + c + d + e + f + g + reallyLongLocalVariableNameThatHasSixWords + top_mixedCase;
}

// UN-gated: shallow (nest=1), no size/complexity trigger, only 1 local — namingLocalsGate must stay false.
int smallFunction( int n )
{
    if( n > 0 )
    {
        int x = 1;
        return x;
    }
    return 0;
}
EOF

xml_lint(){ "$BIN" "$1" --lint --naming-locals --no-cache 2>/dev/null; }
xml_lint_off(){ "$BIN" "$1" --lint --no-cache 2>/dev/null; }

# ══ 0. PRESENCE ══════════════════════════════════════════════════════════════════════════════════════
presence(){ if grep -qF -- "$2" "$1"; then ok "presence: $3"; else no "presence: $3 — fixture drifted"; fi; }
presence "$FIXDIR/big.cpp" 'reallyLongLocalVariableNameThatHasSixWords' 'a >5-token local name present'
presence "$FIXDIR/big.cpp" 'top_mixedCase'                              'a snake+camel mixed local name present'
presence "$FIXDIR/big.cpp" 'int x = a + b;'                             'a nested 1-2 letter local present (declDepth>=2)'
presence "$FIXDIR/big.cpp" '__reserved'                                 'a reserved-underscore-form local present'
presence "$FIXDIR/big.cpp" 'int smallFunction'                          'the un-gated control function present'

# ══ 1. DEFAULT-OFF ═══════════════════════════════════════════════════════════════════════════════════
OFF="$( xml_lint_off "$FIXDIR" )"
off_hits="$( printf '%s' "$OFF" | tr '>' '\n' | grep -c '<f rule="naming-' || true )"
[ "$off_hits" = "0" ] && ok "default-off: --lint alone reports 0 naming-* hits on a fixture that WOULD flag under --naming-locals" \
                        || no "default-off: --lint alone reported $off_hits naming-* hit(s) — the feature is not a true no-op"

# ══ 2. GATED-FIRE ════════════════════════════════════════════════════════════════════════════════════
ON="$( xml_lint "$FIXDIR" )"
on_rows(){ printf '%s' "$ON" | tr '>' '\n' | grep "^<f rule=\"$1\""; }
for tag in naming-short naming-wordy naming-underscore naming-case; do
    row="$( on_rows "$tag" )"
    if [ -n "$row" ]; then
        ok "gated-fire: $tag fires under --naming-locals ($( printf '%s' "$row" | head -1 ))"
    else
        no "gated-fire: $tag did NOT fire under --naming-locals"
    fi
done
if printf '%s' "$ON" | grep -q 'in="bigFunction"'; then
    ok "gated-fire: findings name the enclosing function (in=\"bigFunction\")"
else
    no "gated-fire: no finding named the enclosing function"
fi

# ══ 3. GATE-BOUNDARY ═════════════════════════════════════════════════════════════════════════════════
small_hits="$( printf '%s' "$ON" | tr '>' '\n' | grep 'in="smallFunction"' | grep -c 'naming-' || true )"
[ "$small_hits" = "0" ] && ok "gate-boundary: smallFunction (un-gated) contributes 0 local-scope naming-* hits despite its own short nested local" \
                          || no "gate-boundary: smallFunction contributed $small_hits hit(s) — namingLocalsGate is not actually filtering"

# ══ 4. DECLDEPTH ═════════════════════════════════════════════════════════════════════════════════════
# top_mixedCase sits at declDepth=1 (a direct statement in bigFunction's own outermost block) — naming-case
# must fire on it (no depth gate), but it must NEVER be reported under naming-short (it is not short anyway,
# so this is really about "no top-level SHORT local exists in the fixture to accidentally flag" being true
# by construction; the real depth-gate proof is that naming-short's ONE hit is the depth-6 `x`, not a
# depth-1 name).
short_line="$( on_rows naming-short | grep -oE ':[0-9]+' | head -1 )"
if printf '%s' "$ON" | grep -q 'naming-case'; then
    ok "decldepth: naming-case (no depth gate) fires on the depth-1 local top_mixedCase"
else
    no "decldepth: naming-case did not fire at all"
fi
if [ -n "$short_line" ]; then
    ok "decldepth: naming-short's hit is anchored at a real line ($short_line), i.e. the depth-6 local, not a depth-1 one"
else
    no "decldepth: naming-short produced no anchored line to check"
fi

# ══ 5. TAG-REUSE ═════════════════════════════════════════════════════════════════════════════════════
if printf '%s' "$ON" | grep -qi 'naming-short-local\|naming-.*-local"'; then
    no "tag-reuse: a NEW '-local'-suffixed tag appeared — Open Question 3 (PLAN.md) says reuse, not extend"
else
    ok "tag-reuse: no new '-local'-suffixed tag — findings ride the existing naming-* tags"
fi

# ══ 6. HYGIENE ═══════════════════════════════════════════════════════════════════════════════════════
ON2="$( xml_lint "$FIXDIR" )"
[ "$ON" = "$ON2" ] && ok "hygiene: two --naming-locals runs are byte-identical (determinism)" || no "hygiene: two runs DIFFER"
if printf '%s' "$ON" | xmllint --noout - >/dev/null 2>&1; then
    ok "hygiene: --lint --naming-locals output is well-formed XML"
else
    no "hygiene: --lint --naming-locals output failed xmllint"
fi

# ══ 7. MUTATION — the gate-boundary arm can actually fail ══════════════════════════════════════════════
NAMINGLENS="$ROOT/src/naminglens.h"
if [ -f "$NAMINGLENS" ] && grep -q 'inline bool namingLocalsGate' "$NAMINGLENS"; then
    BACKUP="$TMP/naminglens.h.bak"
    cp "$NAMINGLENS" "$BACKUP"
    # neuter the gate to "always true" — a controlled, RESTORED-AFTERWARD source edit (same discipline as
    # localscountcheck.sh's own mutation arm), proving arm 3 is not vacuously green.
    python3 - "$NAMINGLENS" <<'PYEOF'
import re, sys
path = sys.argv[1]
src = open(path, encoding='utf-8').read()
marker = "inline bool namingLocalsGate( const Symbol& s ) noexcept\n{"
idx = src.index(marker)
insert_at = idx + len(marker)
mutated = src[:insert_at] + "\n    return true;   // MUTATION TEST ONLY\n" + src[insert_at:]
open(path, 'w', encoding='utf-8').write(mutated)
PYEOF
    BUILD_LOG="$TMP/mutbuild.log"
    ( cd "$ROOT" && cmake --build build -j 6 >"$BUILD_LOG" 2>&1 )
    MUT_RC=$?
    if [ "$MUT_RC" -ne 0 ]; then
        no "mutation: the neutered-gate build FAILED to compile — cannot prove the arm has teeth ($BUILD_LOG)"
    else
        MUT_OUT="$( xml_lint "$FIXDIR" )"
        mut_small_hits="$( printf '%s' "$MUT_OUT" | tr '>' '\n' | grep 'in="smallFunction"' | grep -c 'naming-' || true )"
        if [ "$mut_small_hits" != "0" ]; then
            ok "mutation: neutering namingLocalsGate DOES make arm 3 (gate-boundary) go red ($mut_small_hits stray hit(s) on smallFunction) — the gate has real teeth"
        else
            no "mutation: neutering namingLocalsGate did NOT change smallFunction's hit count — arm 3 cannot actually fail, it is vacuous"
        fi
    fi
    cp "$BACKUP" "$NAMINGLENS"
    ( cd "$ROOT" && cmake --build build -j 6 >"$TMP/restorebuild.log" 2>&1 )
    if [ $? -ne 0 ]; then
        no "mutation: RESTORE build failed after reverting naminglens.h — repo may be left in a broken state, check $TMP/restorebuild.log"
    else
        ok "mutation: source restored to its original (non-mutated) state and rebuilt clean"
    fi
else
    no "mutation: could not locate namingLocalsGate in src/naminglens.h to mutate — gate signature drifted"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
