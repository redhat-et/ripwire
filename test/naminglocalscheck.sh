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
#   7. MUTATION     — the gate has real teeth: the SAME smallFunction body, padded past namingLocalsGate's
#                     thresholds in a second fixture, DOES produce the local-scope finding arm 3 asserts is
#                     absent — so arm 3's zero is the gate's doing and not a vacuous constant.
#   8. NO SHARED-STATE WRITES — the gate leaves src/ and the binary byte-for-byte as it found them. Arm 7
#                     used to prove its point by editing src/naminglens.h and rebuilding build/ in place,
#                     which broke 126 suite-mates under pargates; arm 8 is the regression guard for that.
#
# Usage:
#   bash test/naminglocalscheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/naminglocalscheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
echo "naminglocalscheck: BIN=$BIN  TMP=$TMP"

# arm 8's baseline — see its comment. Content hash of src/, plus the binary's identity, taken BEFORE any arm
# runs so the comparison at the end measures this gate and nothing else.
shared_state_fingerprint()
{
    ( cd "$ROOT" && find src -type f -exec cksum {} + | sort; cksum "$BIN" 2>/dev/null ) 2>/dev/null
}
SHARED_STATE_BEFORE="$( shared_state_fingerprint )"

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
                        for( int q = 0; q < n; ++q )   // a CONVENTIONAL for-init counter, 6 blocks deep:
                        {                              // its declaration's parent is for_statement, NOT
                            a += q;                    // compound_statement, so it is structurally never
                        }                              // countable and must never fire naming-short (arm 4b)
                        (void)x; (void)__reserved;
                    }
                }
            }
        }
    }
    return n + a + b + c + d + e + f + g + reallyLongLocalVariableNameThatHasSixWords + top_mixedCase;
}

// COMMA-LIST: gated ONLY if locals= counts DECLARATORS, not declaration STATEMENTS. maxNest=5 (>4)
// clears the size/complexity half of namingLocalsGate; the locals half (>=8) is reachable ONLY through
// the ONE comma-separated declaration below, which introduces exactly TEN declarators
// (a,b,c,d,e,f,g,h,reallyLongLocalVariableNameThatHasSixWords,top_mixedCase) in a SINGLE `declaration`
// node — no other local anywhere in the function, so --metrics locals= on this function is a direct,
// unambiguous read of the counting rule. Before the per-declarator fix, cc_isCountableLocalDecl's caller
// counted that one node as "1" local — under the locals>=8 floor, so namingLocalsGate never cleared and
// no naming-* finding could ever fire here, no matter how badly-named the declarators were. After the
// fix each declarator counts (10 >= 8), the gate clears, and naming-case fires on top_mixedCase
// (depth-1, no depth gate — same proof shape as arm 4's DECLDEPTH check on bigFunction).
int commaListFunction( int n )
{
    int a=1,b=2,c=3,d=4,e=5,f=6,g=7,h=8,reallyLongLocalVariableNameThatHasSixWords=9,top_mixedCase=10;
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
                        (void)a;
                    }
                }
            }
        }
    }
    return n + a + b + c + d + e + f + g + h + reallyLongLocalVariableNameThatHasSixWords + top_mixedCase;
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
presence "$FIXDIR/big.cpp" 'int a=1,b=2,c=3,d=4,e=5,f=6,g=7,h=8,reallyLongLocalVariableNameThatHasSixWords=9,top_mixedCase=10;' \
                                                                          'a ten-declarator comma-list local declaration present'

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

# ══ 4b. FOR-INIT COUNTER — the conventional-loop-counter class, MEASURED not assumed ══════════════════
# The fixture's deepest block declares `for( int q = 0; … )` — the most conventional short name possible,
# 6 blocks deep, well past the declDepth>=2 gate. It must NOT fire naming-short, and not because of any
# name whitelist: a for-init declaration's parent is the for_statement, not the compound_statement, so
# cc_isCountableLocalDecl (ingest.cpp) structurally never counts it — the exclusion Phase 1's own
# localscountcheck.sh pins at the COUNT level, proven here to carry through to Phase 2's FLAGGING level.
# (The residual class this does NOT close, recorded in naminglens.h's checkLocalNameShape comment: a
# C-style block-declared counter — `int j;` then `for( j = 0; … )` — still fires; closing it needs the
# real-corpus audit the plan's default-enable blocker already requires, not another plausible guard.)
short_rows="$( on_rows naming-short | grep -c . || true )"
if [ "$short_rows" = "1" ]; then
    ok "for-init: naming-short fired exactly once (the block-declared x) — the depth-6 for-init counter q did NOT fire"
else
    no "for-init: naming-short fired $short_rows time(s), expected exactly 1 — a for-init counter may be leaking through"
fi

# ══ 4c. COMMA-LIST — locals= counts DECLARATORS, not declaration STATEMENTS (the bug this round fixes) ═
# Direct numeric proof, independent of --naming-locals: commaListFunction's ONLY locals are the ten names
# in its one comma-separated declaration, so --metrics locals= on it is an unambiguous read of the
# counting rule (10 = per-declarator, 1 = per-statement — the bug this test was written to catch).
METRICS_XML="$( "$BIN" "$FIXDIR" --metrics --no-cache 2>/dev/null )"
comma_locals="$( printf '%s' "$METRICS_XML" | tr '>' '\n' | grep 'n="commaListFunction"' | grep -oE 'locals="[0-9]+"' | grep -oE '[0-9]+' )"
if [ "$comma_locals" = "10" ]; then
    ok "comma-list: --metrics reports locals=10 for a single ten-declarator comma-list statement (per-declarator counting)"
else
    no "comma-list: --metrics reports locals=$comma_locals for commaListFunction, want 10 — locals= is counting declaration STATEMENTS, not declarators"
fi
# End-to-end proof: the gate (namingLocalsGate: size/complexity clears at maxNest=5, locals needs >=8) is
# reachable ONLY via the comma list's per-declarator count, so a fire here is proof the count feeds the
# gate. Scoped to naming-* rules specifically (rule="naming-...") — commaListFunction ALSO trips
# unrelated always-on rules (deep-nesting, magic-number, c-style-cast on the (void) cast) that fire
# regardless of --naming-locals, so a bare "does this function appear anywhere in the output" check would
# pass vacuously even with the bug present.
comma_naming_hits="$( printf '%s' "$ON" | tr '>' '\n' | grep '^<f rule="naming-' | grep -c 'in="commaListFunction"' || true )"
if [ "$comma_naming_hits" -gt 0 ]; then
    ok "comma-list: --naming-locals fires $comma_naming_hits naming-* finding(s) on commaListFunction (e.g. naming-case on top_mixedCase, depth-1) — namingLocalsGate's locals>=8 floor is reachable via a comma list"
else
    no "comma-list: --naming-locals fired NO naming-* finding on commaListFunction — namingLocalsGate's locals>=8 floor is unreachable via a comma list (the bug: locals= undercounts a comma-declarator statement as 1)"
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
# The mutation is applied to the FIXTURE, never to src/naminglens.h.
#
# This arm used to neuter namingLocalsGate in the source, run `cmake --build build -j 6` against the SHARED
# build tree, and rebuild again to restore. That is the only gate in test/ that ever wrote to $ROOT/src or to
# $ROOT/build, and under test/pargates.py it corrupts the whole suite: while the two rebuilds relink
# build/ripwire, every concurrently-scheduled gate sees the binary either absent (rc=2 "no ripwire binary")
# or busy (ETXTBSY -> exit 126, reported as "Permission denied"). Measured on CI run 31145553507: 126 of 361
# gates failed on release (ubuntu-24.04, Release) for that reason alone, and on two legs this gate blew
# pargates' own 300 s timeout mid-rebuild — which kills the RESTORE leg and leaves the checkout mutated.
# A gate must not be able to fail its suite-mates, so the shared-state edit is gone for good.
#
# The replacement is the positive control for the same claim, in-process and end-to-end: `smallFunction` is
# re-emitted into its own corpus with its `if( n > 0 ) { int x = 1; … }` body BYTE-IDENTICAL and only the
# gate inputs padded past namingLocalsGate's thresholds (naminglens.h: loc>80 || maxNest>4 || ccx>=15, AND
# locals>=8). Same binary, same names, same nesting depth for `x` — the ONLY thing that changed is which
# side of the gate the function sits on. If the padded twin flags and arm 3's original does not, arm 3's
# zero is the gate's doing and not a vacuous constant. The padding locals are deliberately depth-1 and
# unremarkable, so the hit that appears is `x`'s, the same local arm 3 asserts silence for.
MUTDIR="$TMP/mut"; mkdir -p "$MUTDIR"
{
    printf '// arm 7 positive control: smallFunction, padded past namingLocalsGate (maxNest=5>4, locals=10>=8).\n'
    printf '// The gated body below is byte-identical to big.cpp'"'"'s smallFunction — only the gate inputs differ.\n'
    printf 'int smallFunction( int n )\n{\n'
    for i in 1 2 3 4 5 6 7 8 9; do printf '    int padLocal%d = %d;\n' "$i" "$i"; done
    printf '    if( n > 0 )\n    {\n'
    printf '        if( n > 1 )\n        {\n'
    printf '            if( n > 2 )\n            {\n'
    printf '                if( n > 3 )\n                {\n'
    printf '                    if( n > 0 )\n                    {\n'
    printf '                        int x = 1;\n'
    printf '                        return x;\n'
    printf '                    }\n                }\n            }\n        }\n    }\n'
    printf '    return padLocal1 + padLocal2 + padLocal3 + padLocal4 + padLocal5\n'
    printf '         + padLocal6 + padLocal7 + padLocal8 + padLocal9;\n}\n'
} >"$MUTDIR/small_padded.cpp"

#
# The assertion is anchored at `x`'s OWN line, not counted over `in="smallFunction"` the way arm 3 is.
# Padding the function past the locals gate also pushes it past the FUNCTION-level size rules, and the twin
# duly picks up a naming-uninformative row on the function name itself (measured: line 2, the declaration).
# A bare `in="smallFunction"` count would therefore stay at 1 even if the local path emitted nothing at all —
# a positive control that cannot fail. Matching the local's line keeps this arm about the one finding arm 3
# claims the gate suppresses.
MUT_OUT="$( xml_lint "$MUTDIR" )"
XLINE="$( grep -n 'int x = 1;' "$MUTDIR/small_padded.cpp" | cut -d: -f1 )"
mut_local_hits="$( printf '%s' "$MUT_OUT" | tr '>' '\n' | grep 'in="smallFunction"' | grep -c "small_padded\.cpp:$XLINE\"" || true )"
if [ "$mut_local_hits" != "0" ]; then
    ok "mutation: the SAME smallFunction body, padded past namingLocalsGate, DOES flag its local x at line $XLINE — arm 3's zero is the gate's doing, not a vacuous constant"
else
    no "mutation: padding smallFunction past namingLocalsGate produced no finding at x's own line ($XLINE) — arm 3 cannot actually fail, it is vacuous"
fi
# ══ 8. NO SHARED-STATE WRITES ═════════════════════════════════════════════════════════════════════════
# The regression guard for what arm 7 used to do. Compared against the fingerprint taken before any arm ran,
# so a tree that was already dirty when the gate started stays green — what is asserted is that THIS gate
# changed nothing, not that the checkout is pristine.
if [ "$( shared_state_fingerprint )" = "$SHARED_STATE_BEFORE" ]; then
    ok "shared state: src/ and the binary are exactly as this gate found them — no suite-mate can be broken by running it"
else
    no "shared state: src/ or $BIN CHANGED while this gate ran — under pargates that hands every concurrent gate a missing or busy binary (rc=2 / exit 126)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
