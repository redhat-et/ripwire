#!/usr/bin/env bash
# preproccondcheck.sh — an `#include` / `#import` / `using` that sits inside a PREPROCESSOR CONDITIONAL
# is a physical dependency and must reach the include graph.
#
# ── THE DEFECT ────────────────────────────────────────────────────────────────────────────────────────
# src/ingest.cpp::captureIncludes scanned the ROOT node's DIRECT children only. tree-sitter does not
# flatten the preprocessor: `#if` / `#ifdef` / `#ifndef` / `#else` / `#elif` / `#elifdef` each parse as a
# CONTAINER node (preproc_if / preproc_ifdef / preproc_else / preproc_elif / preproc_elifdef) that owns
# the directives written between it and its `#endif`. So every guarded include was invisible — not
# mis-resolved, never seen. Minimal repro (pre-fix): a file whose only `#include` sits under
# `#if defined(FOO)` produced NO `<f>` row at all under `--deps`.
#
# The same top-level-only scan hit C#, whose grammar spells its conditional nodes with the same public
# type names, so a `using` inside `#if` was dropped too. `#region` is NOT a container in that grammar and
# was never affected — it is this gate's negative control for over-descent.
#
# ── WHY IT MATTERS BEYOND A MISSING ROW (the reason this is a gate, not a tidy-up) ────────────────────
# `--cochange`'s `surprising="1"` means "these two files change together and NO static dependency, even
# transitive, explains it". Its predicate (src/gitmine.h::StaticIncludeCoupling, §P9.1) is built from the
# captured include list. A file that wraps its whole body in one feature guard therefore hands that
# predicate an empty include list and gets flagged as hidden architectural coupling against its OWN
# header — a confident false positive on the rows the flag exists to make actionable. Measured on a
# private C++ tree: levelEdit2/LevelEditor.cpp wraps its body in `#if LEVELEDIT`, ripwire captured 1 of
# its ~29 includes, and the pair (LevelEditor.cpp, LevelEditor.h) shipped `surprising="1"` even though
# LevelEditor.cpp contains BOTH `#import "LevelEditor.h"` and `#include "LevelEditor.h"`. That is the
# same defect CLASS as §P9.1 with a different root cause, and arm 3 below reproduces it end-to-end on a
# throwaway git repo built in this gate (recipe borrowed from test/cochangesurprisecheck.sh, so it
# asserts identically on a fresh clone and a shallow CI checkout as on the author's machine).
#
# ── ARMS ──────────────────────────────────────────────────────────────────────────────────────────────
#   0.  PRESENCE   — the fixture really spells each guarded form (green-while-inert guard: if a fixture
#                    edit drops an arm, this gate must go red rather than pass on a corpus that no longer
#                    contains what it claims to assert).
#   1.  CAPTURE    — every guarded target appears in `--deps`, one named assertion per grammar node kind:
#                    preproc_if / else / ifdef / elif / ifndef / elifdef / nested / #import-as-preproc_call
#                    / ObjC-grammar #import / C# preproc_if / C# preproc_else.
#   1b. CONTROL    — the top-level includes that already worked still work, and `#region` (a flat
#                    directive) is unchanged: the descent must not have been bought by rewriting the
#                    top-level scan.
#   1c. NO SPRAY   — exact per-file include COUNTS. A descent that walked into function bodies, or that
#                    visited a node twice, shows up here and nowhere else.
#   2.  USE-SITES  — the import-role RawRef rides along, so `--uses` sees the guarded import site with
#                    the right LINE (the ref's line comes from the directive node, not the container).
#   3.  COCHANGE   — the end-to-end consequence: a `#if`-wrapped .cpp co-changing with its own header
#                    must NOT be reported `surprising="1"`. Positive control in the same repo: a
#                    genuinely uncoupled dependency-capable pair must STILL be flagged, so arm 3 cannot
#                    pass by suppressing the signal wholesale.
#   4.  DEGRADE    — a pathologically nested guard stack does not crash, hang, or emit malformed XML.
#   5.  HYGIENE    — determinism (two cold runs byte-identical), warm == cold (the extraction change is
#                    behind kParserVer, so a stale blob must not survive), well-formed XML.
#   6.  MONOTONIC  — on a real tree (this repo's own src/, held constant), against a binary built from
#                    git HEAD: no include the pre-change extractor captured may be lost, and
#                    `surprising="1"` may only ever be SUPPRESSED. Both follow from the descent being
#                    purely additive, and both would catch a future refactor of captureIncludes that
#                    bought the guarded case by dropping something else.
#
# Usage:
#   bash test/preproccondcheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/preproccondcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/preproccondcheck.sh
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/preproccondfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){   printf '  PASS  %s\n' "$*"; }
no(){   printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }
echo "preproccondcheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

# ══ 0. PRESENCE GUARD — the fixture spells what the arms below claim to assert ════════════════════════
# Without this, deleting an `#elif` arm from the fixture would turn arm 1 green-while-inert instead of red.
presence(){ # presence <file> <literal> <label>
    if grep -qF -- "$2" "$FIX/$1"; then ok "presence: $3"; else no "presence: $3 — fixture drifted, arms below cannot assert"; fi
}
presence guarded.cpp '#if defined( RIPWIRE_COND_A )' '#if defined(...) arm present'
presence guarded.cpp '#else'                         '#else arm present'
presence guarded.cpp '#ifdef RIPWIRE_COND_B'         '#ifdef arm present'
presence guarded.cpp '#elif defined( RIPWIRE_COND_C )' '#elif arm present'
presence guarded.cpp '#ifndef RIPWIRE_COND_D'        '#ifndef arm present'
presence guarded.cpp '#elifdef RIPWIRE_COND_H'       '#elifdef arm present'
presence guarded.cpp '#        include "cond_nested.h"' 'nested #if-inside-#if arm present'
presence guarded.cpp '#import "cond_import.h"'       '#import-inside-#if arm present (C/C++ grammar → preproc_call)'
presence whole.cpp   '#if RIPWIRE_WHOLE_ENABLED'     'whole-file guard arm present (the LevelEditor.cpp shape)'
presence guard.m     '#import "objc_guarded.h"'      'ObjC-grammar #import-inside-#if arm present'
presence Cond.cs     'using IfArm.Ns;'               'C# using-inside-#if arm present'
presence Cond.cs     'using ElseArm.Ns;'             'C# using-inside-#else arm present'
presence Cond.cs     '#region grouped'               'C# #region negative control present'

# ══ 1. CAPTURE — one named assertion per grammar node kind the extractor must descend through ════════
"$BIN" "$FIX" --deps --no-cache >"$TMP/deps" 2>"$TMP/deps.err"
rc=$?
[ "$rc" -eq 0 ] && ok "--deps exits 0" || { no "--deps exits $rc"; head -3 "$TMP/deps.err"; }
[ -s "$TMP/deps" ] || { echo "preproccondcheck: empty --deps output, cannot proceed"; exit 2; }

inc(){ # inc <target> <label>
    if grep -qF "<inc t=\"$1\"" "$TMP/deps"; then ok "captured: $2"; else no "DROPPED: $2 (no <inc t=\"$1\"> in --deps)"; fi
}
inc cond_if.h      '#include under preproc_if'
inc cond_else.h    '#include under preproc_else'
inc cond_ifdef.h   '#include under preproc_ifdef (#ifdef)'
inc cond_elif.h    '#include under preproc_elif'
inc cond_ifndef.h  '#include under preproc_ifdef (#ifndef)'
inc cond_elifdef.h '#include under preproc_elifdef'
inc cond_nested.h  '#include under a NESTED #if-inside-#if (descent is not depth-1)'
inc cond_import.h  '#import under preproc_if (C/C++ grammar → preproc_call, not preproc_include)'
inc whole.h        '#import of the file OWN header, visible only inside a whole-file guard'
inc whole_dep.h    '#include inside a whole-file guard'
inc objc_guarded.h '#import under preproc_if in the ObjC grammar (→ preproc_include)'
inc IfArm.Ns       'C# using under preproc_if'
inc ElseArm.Ns     'C# using under preproc_else'

# 1b. CONTROLS — what already worked must still work (the descent is purely additive).
inc top.h            'CONTROL: plain top-level #include'
inc objc_top.h       'CONTROL: plain top-level #import (ObjC grammar)'
inc whole_pre.h      'CONTROL: the one include ABOVE a whole-file guard'
inc RegionUsing.Ns   'CONTROL: C# using inside #region (a FLAT directive — never affected)'
inc TopLevel.Ns      'CONTROL: plain top-level C# using'

# 1c. NO SPRAY — exact counts. Double-visiting a node, or descending into function bodies, lands here.
#     Numbers are read off the fixture BY HAND, not off the tool:
#       guarded.cpp  top + if + else + ifdef + elif + ifndef + elifdef + nested + import      = 9
#       whole.cpp    whole_pre + whole(#import) + whole_dep                                   = 3
#       guard.m      objc_top + objc_guarded                                                  = 2
#       Cond.cs      IfArm + ElseArm + RegionUsing + TopLevel                                 = 4
count(){ # count <file> <expected> <label>
    # --deps echoes the corpus path as GIVEN (absolute here), so match on the trailing path segment and
    # require the row to carry includes= — the `<godfiles>` block repeats bare `<f p=…>` rows without it.
    local got
    # RE-PINNED 2026-08-19 (R-E CORRECTION): p= is root-relative — see nestedimportcheck.sh's twin comment.
    got="$( tr '>' '\n' <"$TMP/deps" | grep -E "<f p=\"([^\"]*/)?$1\" .*includes=" | grep -oE 'includes="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
    if [ "${got:-}" = "$2" ]; then ok "count: $3 (includes=$2)"; else no "count: $3 — expected includes=$2, got includes=${got:-<no row>}"; fi
}
count guarded.cpp 9 'guarded.cpp captures every arm exactly once'
count whole.cpp   3 'whole.cpp captures both guarded includes plus the one above the guard'
count guard.m     2 'guard.m captures the guarded #import exactly once'
count Cond.cs     4 'Cond.cs captures both #if arms plus both controls'

# The <inc> listing serialize.h emits is capped at 40 children per file (the rest disclosed as `+more`),
# and every `inc`/`noinc` assertion above reads that listing. Assert the cap was not reached, or those
# arms could go red for a truncation rather than for a lost capture.
if grep -q '+more' "$TMP/deps"; then
    no "fixture outgrew the 40-per-file <inc> display cap (+more present) — the capture arms above are unsound"
else
    ok "no fixture file reaches the 40-per-file <inc> display cap (the capture arms read a COMPLETE listing)"
fi

# ══ 2. USE-SITES — the import-role RawRef rides along, attributed to the DIRECTIVE line ═══════════════
# The ref's line must come from the include directive itself, not from the enclosing preproc_if: the
# container starts on the `#if` line, so a descent that attributed to the container would report a line
# that is off by one or more and silently mislocate every guarded import site.
# NOTE the nested arm is written `#        include "cond_nested.h"` (indented continuation form), so this
# must not anchor on `#include` — an empty IMPLINE would make the line assertion below match anything.
IMPLINE="$( grep -nF 'include "cond_nested.h"' "$FIX/guarded.cpp" | cut -d: -f1 )"
GUARDLINE="$( grep -nF '#if defined( RIPWIRE_COND_E )' "$FIX/guarded.cpp" | cut -d: -f1 )"
if [ -n "$IMPLINE" ] && [ -n "$GUARDLINE" ] && [ "$IMPLINE" != "$GUARDLINE" ]; then
    ok "presence: the directive line ($IMPLINE) differs from its enclosing #if line ($GUARDLINE) — the line arm can discriminate"
else
    no "presence: could not locate distinct directive/#if lines in guarded.cpp — the line arm below is inert"
fi
"$BIN" "$FIX" --uses=cond_nested --no-cache >"$TMP/uses" 2>/dev/null
if grep -q 'guarded.cpp' "$TMP/uses"; then
    ok "--uses reports the guarded import site (cond_nested.h)"
    if grep -qE "guarded\.cpp:$IMPLINE\b" "$TMP/uses"; then
        ok "--uses line = the DIRECTIVE line $IMPLINE (not the enclosing #if line)"
    else
        no "--uses line is not the directive line $IMPLINE"; grep -o 'guarded\.cpp:[0-9]*' "$TMP/uses" | head -3
    fi
else
    no "--uses does not report the guarded import site"; head -c 400 "$TMP/uses"; echo
fi

# ══ 3. COCHANGE — the end-to-end false positive this defect ships ════════════════════════════════════
# A throwaway git repo (self-contained: needs no history but its own, so it behaves the same on a fresh
# clone and under `actions/checkout` as on a full local tree). One co-change wave touches every file, so
# every pair has identical together=/deg= support and the ONLY variable between the two arms is whether
# the #include predicate can see the guarded include.
#
#   src/wrapped.cpp   whole body inside `#if FEATURE`, `#include "wrapped.h"` INSIDE the guard
#       → (wrapped.cpp, wrapped.h)  must NOT be surprising="1"          ← the defect
#   src/lone.cpp / src/other.h  — both dependency-capable, no include path either way
#       → must STILL be surprising="1"                                  ← the positive control
CO="$TMP/cofix"
mkCoFixture(){
    mkdir -p "$CO/src" || return 1
    printf '#pragma once\nint wrappedValue();\n'                                              >"$CO/src/wrapped.h"
    printf '#if FEATURE_ON\n#include "wrapped.h"\nint wrappedValue(){ return 1; }\n#endif\n'  >"$CO/src/wrapped.cpp"
    printf '#pragma once\nint otherValue();\n'                                                >"$CO/src/other.h"
    printf 'int lone(){ return 7; }\n'                                                        >"$CO/src/lone.cpp"
    (
        cd "$CO" || exit 1
        git init -q . || exit 1
        git config user.email preproccond@example.invalid || exit 1
        git config user.name  'preproccond gate'          || exit 1
        git config commit.gpgsign false                   || exit 1
        # several waves: co-change support has to clear the tool's minimum-together threshold.
        for i in 1 2 3 4 5; do
            printf '// wave %s\n' "$i" >>src/wrapped.cpp
            printf '// wave %s\n' "$i" >>src/wrapped.h
            printf '// wave %s\n' "$i" >>src/lone.cpp
            printf '// wave %s\n' "$i" >>src/other.h
            git add -A                                       || exit 1
            git commit -q -m "wave $i" --date="2024-01-0$i 12:00:00" || exit 1
        done
    )
}
if ! command -v git >/dev/null 2>&1; then
    skip "cochange arm: git not on PATH"
elif ! mkCoFixture >"$TMP/cofix.log" 2>&1; then
    skip "cochange arm: fixture repo could not be built ($( head -1 "$TMP/cofix.log" ))"
else
    "$BIN" "$CO" --cochange --pack-top-n=1000 >"$TMP/co" 2>/dev/null
    # one row per pair; grab the row naming both members, whatever the attribute order.
    row(){ tr '>' '\n' <"$TMP/co" | grep -F "$1" | grep -F "$2" | head -1; }
    RW="$( row 'wrapped.cpp' 'wrapped.h' )"
    LO="$( row 'lone.cpp'    'other.h'   )"
    if [ -z "$RW" ]; then
        no "cochange: the (wrapped.cpp, wrapped.h) pair is absent — fixture history did not register"
    elif printf '%s' "$RW" | grep -q 'surprising="1"'; then
        no "cochange: (wrapped.cpp, wrapped.h) still surprising=\"1\" — the guarded #include is invisible to StaticIncludeCoupling"
        printf '        %s\n' "$RW"
    else
        ok "cochange: a #if-wrapped .cpp is NOT surprising against its own header (the false positive is gone)"
    fi
    if [ -z "$LO" ]; then
        skip "cochange positive control: the (lone.cpp, other.h) pair is absent from the emitted rows"
    elif printf '%s' "$LO" | grep -q 'surprising="1"'; then
        ok "cochange positive control: a genuinely uncoupled dep-capable pair is STILL surprising=\"1\""
    else
        no "cochange positive control LOST: (lone.cpp, other.h) no longer surprising=\"1\" — the fix suppressed the signal wholesale"
        printf '        %s\n' "$LO"
    fi
fi

# ══ 4. DEGRADE — a pathological guard stack must not crash, hang, or emit malformed XML ═══════════════
# The descent is bounded; the contract is that exceeding the bound DEGRADES (fewer includes) rather than
# failing. 600 nested `#if`s is past any plausible bound, and the plain (non-Release) build is the one
# that can observe the alert — see CONTRIBUTING.md §5.
DEEP="$TMP/deep"; mkdir -p "$DEEP"
{
    for i in $( seq 1 600 ); do printf '#if defined( D%s )\n' "$i"; done
    printf '#include "deep.h"\n'
    for i in $( seq 1 600 ); do printf '#endif\n'; done
    printf 'int deepFn(){ return 0; }\n'
} >"$DEEP/deep.cpp"
printf '#pragma once\nint deepValue();\n' >"$DEEP/deep.h"
if "$BIN" "$DEEP" --deps --no-cache >"$TMP/deep.out" 2>"$TMP/deep.err"; then
    ok "600-deep guard stack: exits 0 (degrades, does not fail)"
else
    no "600-deep guard stack: non-zero exit"; head -3 "$TMP/deep.err"
fi
# …and the degrade is ANNOUNCED, not silent. DEGRADED_PATH_ALERT is compiled out under NDEBUG, so first
# establish whether alerts are observable in THIS binary at all (probe an unrelated, always-degrading
# path); a Release leg then SKIPs instead of failing, and the plain leg — which CI runs as a second job
# for exactly this reason, CONTRIBUTING.md §5 — is what actually proves the alert fires.
"$BIN" "$ROOT" --rank-by=churn --since=notadate >/dev/null 2>"$TMP/probe.err"
if grep -q 'math degraded' "$TMP/probe.err"; then
    if grep -q 'import-container nesting past the depth bound' "$TMP/deep.err"; then
        ok "600-deep guard stack: the depth bound announces itself via DEGRADED_PATH_ALERT"
    else
        no "600-deep guard stack: depth bound hit SILENTLY — no DEGRADED_PATH_ALERT on stderr"
    fi
else
    skip "600-deep guard stack: DEGRADED_PATH_ALERT compiled out of this binary (NDEBUG); the plain-flavour leg proves it"
fi
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/deep.out" 2>/dev/null && ok "600-deep guard stack: XML well-formed" || no "600-deep guard stack: XML malformed"
else
    skip "600-deep guard stack: xmllint absent"
fi

# ══ 5. HYGIENE — determinism, warm == cold, well-formed XML ═══════════════════════════════════════════
"$BIN" "$FIX" --deps --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --deps --no-cache >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" && ok "deterministic (two --no-cache runs identical)" || no "non-deterministic"

"$BIN" "$FIX" --deps --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --deps --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
cmp -s "$TMP/cold" "$TMP/warm" && ok "warm == cold (guarded includes survive the extraction cache)" || { no "warm != cold"; diff "$TMP/cold" "$TMP/warm" | head -4; }
cmp -s "$TMP/cold" "$TMP/d1"   && ok "cached run == --no-cache run" || no "cached run differs from --no-cache run"

if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"
else
    skip "xml well-formedness (xmllint absent)"
fi

# ══ 6. MONOTONICITY on a real corpus — the descent is PURELY ADDITIVE ════════════════════════════════
# The fixture's CONTROL arms prove no top-level include was traded away in this change; this arm proves
# it over a whole real tree, and keeps proving it for future edits to captureIncludes. Two invariants,
# both structural rather than pinned to a number (a pinned count would just re-break on every corpus edit):
#   (a) every include the PRE-CHANGE binary captured is still captured — descending into a container can
#       only ADD directive positions, never remove one;
#   (b) `surprising="1"` is only ever SUPPRESSED — StaticIncludeCoupling is monotone in the include set,
#       so a longer include list can only make more pairs statically coupled. A NEW surprising row after
#       an include-capture change means the capture LOST an edge somewhere.
# Both binaries run over the SAME input (HEAD's src/), so the only variable is the extractor.
monotonicity_check()
{
    command -v git   >/dev/null 2>&1 || { skip "monotonicity: git absent";   return; }
    command -v cmake >/dev/null 2>&1 || { skip "monotonicity: cmake absent"; return; }
    ( cd "$ROOT" && git rev-parse --verify HEAD >/dev/null 2>&1 ) || { skip "monotonicity: not a git repo"; return; }
    . "$ROOT/test/lib/headbinlib.sh"                   # sha-keyed cache — shared with the other monotonicity gates

    local WT="$TMP/head"
    ( cd "$ROOT" && git worktree add -q --detach "$WT" HEAD ) 2>"$TMP/wt.err" \
        || { skip "monotonicity: cannot create HEAD worktree ($( head -1 "$TMP/wt.err" ))"; return; }
    trap '( cd "$ROOT" && git worktree remove --force "'"$WT"'" >/dev/null 2>&1 ); rm -rf "$TMP"' EXIT

    local OLDBIN
    OLDBIN="$( ripwire_head_binary "$ROOT" "$TMP" )" || { skip "monotonicity: pre-change build failed"; return; }

    local IN="$WT/src"
    # (a) captured includes — compare the PER-FILE COUNT, never the emitted <inc> rows. serialize.h caps
    #     a file's <inc> children at 40 and discloses the rest as `+more`, so a file that GAINS imports
    #     pushes later ones out of the listing: an <inc>-row diff would read that display truncation as a
    #     lost capture and this arm would red on a correct change. `includes=` in the <f> header is the raw
    #     uncapped statement count (serialize.h says so explicitly), which is the number that must not drop.
    inccounts(){ "$1" "$IN" --deps --no-cache --limit=5000 2>/dev/null | tr '>' '\n' \
                     | grep -oE '<f p="[^"]*" includes="[0-9]+"' | sed -E 's/<f p="([^"]*)" includes="([0-9]+)"/\1 \2/' | sort; }
    inccounts "$OLDBIN" >"$TMP/inc.old"
    inccounts "$BIN"    >"$TMP/inc.new"
    if [ ! -s "$TMP/inc.old" ]; then
        skip "monotonicity(a): pre-change binary captured no includes on $IN — cannot compare"
    else
        local dropped
        dropped="$( join "$TMP/inc.old" "$TMP/inc.new" | awk '$3 < $2 { print $1 " was=" $2 " now=" $3 }' )"
        # a file that had includes before and has NO row at all now is also a loss
        local vanished
        vanished="$( join -v1 "$TMP/inc.old" "$TMP/inc.new" | awk '$2 > 0 { print $1 " was=" $2 " now=<no row>" }' )"
        if [ -z "$dropped" ] && [ -z "$vanished" ]; then
            ok "monotonicity(a): no file's include COUNT dropped on src/ (descent is purely additive)"
        else
            no "monotonicity(a): includes LOST on src/ — the descent traded away earlier captures"
            printf '%s\n%s\n' "$dropped" "$vanished" | grep -v '^$' | head -5
        fi
    fi

    # (b) surprising="1" — the NEW set must be a SUBSET of the OLD set.
    surpset(){ "$1" "$IN" --cochange --pack-top-n=5000 --no-cache 2>/dev/null | tr '>' '\n' | grep 'surprising="1"' | grep -oE 'a="[^"]*" b="[^"]*"' | sort; }
    surpset "$OLDBIN" >"$TMP/surp.old"
    surpset "$BIN"    >"$TMP/surp.new"
    if [ ! -s "$TMP/surp.old" ] && [ ! -s "$TMP/surp.new" ]; then
        skip "monotonicity(b): no surprising= rows on $IN in either binary (needs git history — shallow clone?)"
    elif [ "$( comm -13 "$TMP/surp.old" "$TMP/surp.new" | wc -l | tr -d ' ' )" = "0" ]; then
        ok "monotonicity(b): surprising=\"1\" only ever SUPPRESSED, never added ($( comm -23 "$TMP/surp.old" "$TMP/surp.new" | wc -l | tr -d ' ' ) false positive(s) retired on src/)"
    else
        no "monotonicity(b): NEW surprising=\"1\" rows appeared — an include edge was LOST"
        comm -13 "$TMP/surp.old" "$TMP/surp.new" | head -5
    fi
}
monotonicity_check

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
