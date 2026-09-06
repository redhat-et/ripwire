#!/usr/bin/env bash
# printffmtparitycheck.sh — the byte-parity fence for any printf-family -> std::format/std::print
# conversion (harvest-B lane R8, PLAN_HARVEST_B_2026-09-05.md §2/§8 item H).
#
# THE PROPERTY THIS GATE PROVES, AND WHY IT IS THE WHOLE SAFETY STORY FOR THAT MIGRATION: the codebase
# is printf-family by deliberate choice (0 std::cout, 1529 fprintf/printf/snprintf/sprintf call sites
# across ~60 files) and every one of those bytes feeds G4 (minified XML), the determinism contract,
# docs/EVALS.md's recorded numbers, and showcasecapturecheck's/docscommandscheck's stored captures.
# A conversion to std::format is safe ONLY if it changes NOTHING about stdout/stderr bytes for any verb —
# std::format's default float formatting (shortest-roundtrip) is NOT the same as printf's (`%g` = 6
# significant digits: 0.1+0.2 prints "0.3" under %g, "0.30000000000000004" under std::format's `{}`),
# so a naive per-specifier swap is a silent, gate-invisible byte change unless something asserts
# byte-identity directly. This script is that assertion: it is the reviewer, not the model doing the
# conversion — a cheap model can be trusted with the mechanical rule set in the lane report PRECISELY
# BECAUSE this gate reverts any file whose conversion moves one byte.
#
# WHAT IT DOES: runs a fixed corpus of verb invocations (chosen to touch several of the densest
# printf-family files — verbs_lint.h, verbs_navigate.h, cli.h, verbs_report.h's --hotspots/--clones
# paths, main.cpp's dispatch) against the binary under test, hashes stdout and stderr separately per
# verb (SHA-256, so a 176 KB --help capture costs one line, not a checked-in blob), and compares against
# the committed manifest test/printf_parity.manifest. Any mismatch — hash OR exit code — is a FAIL naming
# exactly which verb and which stream changed.
#
# Deliberately EXCLUDED from the corpus: --doctor (self_mtime/self_size/cache blobs= are documented
# VOLATILE fields — doctor's own legend says a determinism comparison must strip them, so a naive
# byte-hash here would false-positive on every rebuild regardless of any printf change); --quality-delta
# (a state-writing verb per the lane brief's rule 9 — out of scope for a read-only parity fence); and
# --version (embeds `built_from=<sha>[+dirty]` — the dirty suffix flips the moment ANY file in the tree
# is edited, which is true of every commit in a printf-family conversion BEFORE it lands, so this verb
# false-positives on the gate's own normal use and would falsely blame the conversion for a byte change
# that is really "you have uncommitted changes"; confirmed live during the R8 pilot conversion).
#
# Usage:
#   bash test/printffmtparitycheck.sh                    # compare against the committed manifest
#   RIPWIRE_BIN=asan/ripwire bash test/printffmtparitycheck.sh
#   UPDATE_GOLDEN=1 bash test/printffmtparitycheck.sh     # regenerate the manifest (review the diff!)
#
# Exits non-zero on any mismatch; prints PASS/FAIL per verb/stream; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/fixture"
MANIFEST="$ROOT/test/printf_parity.manifest"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

hashfile(){
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
    else sha256sum "$1" | cut -d' ' -f1
    fi
}

# ── the verb corpus ──────────────────────────────────────────────────────────────────────────────────
# label -> (needsCorpus 0|1, argv...). needsCorpus=1 verbs get "$CORPUS --no-cache" prepended; 0 verbs
# (--version/--help) are global and take no positional path at all.
LABELS="flagless lint lint_sarif lint_select lint_naming lint_catalog match pattern for_verb callers impact hotspots clones owners help"

argsFor(){
    case "$1" in
        flagless)    echo "1|";;
        lint)        echo "1|--lint";;
        lint_sarif)  echo "1|--lint --sarif";;
        lint_select) echo "1|--lint --lint-select=cache";;
        lint_naming) echo "1|--lint --naming-locals";;
        lint_catalog) echo "1|--lint-catalog";;
        match)       echo "1|--match=(function_definition) @m";;
        pattern)     echo "1|--pattern=distance(\$A, \$B)";;
        for_verb)    echo "1|--for=distance";;
        callers)     echo "1|--callers=distance";;
        impact)      echo "1|--impact=perimeter";;
        hotspots)    echo "1|--hotspots";;
        clones)      echo "1|--clones";;
        owners)      echo "1|--owners";;
        help)        echo "0|--help";;
    esac
}

runVerb(){
    # $1 = label, writes stdout to $TMP/out, stderr to $TMP/err, returns the process rc via $?
    local spec needsCorpus argLine
    spec="$( argsFor "$1" )"
    needsCorpus="${spec%%|*}"
    argLine="${spec#*|}"
    # word-split argLine deliberately (each verb's args are simple flags/values, none containing IFS
    # whitespace inside a single token except --match=/--pattern= which quote-embed a literal space in
    # the query text — handled by the explicit array below for those two labels only).
    if [ "$1" = "match" ]; then
        set -- "--match=(function_definition) @m"
    elif [ "$1" = "pattern" ]; then
        set -- "--pattern=distance(\$A, \$B)"
    else
        # shellcheck disable=SC2206
        set -- $argLine
    fi
    if [ "$needsCorpus" = "1" ]; then
        "$BIN" "$CORPUS" --no-cache "$@" >"$TMP/out" 2>"$TMP/err"
    else
        "$BIN" "$@" >"$TMP/out" 2>"$TMP/err"
    fi
    return $?
}

if [ "${UPDATE_GOLDEN:-0}" = "1" ]; then
    : >"$MANIFEST"
    for label in $LABELS; do
        runVerb "$label"; rc=$?
        printf '%s %s %s %s\n' "$label" "$rc" "$( hashfile "$TMP/out" )" "$( hashfile "$TMP/err" )" >>"$MANIFEST"
    done
    echo "UPDATE_GOLDEN: wrote $MANIFEST ($( wc -l <"$MANIFEST" | tr -d ' ' ) verbs) — review the diff before committing"
    exit 0
fi

[ -f "$MANIFEST" ] || { echo "printffmtparitycheck: no manifest at $MANIFEST — run with UPDATE_GOLDEN=1 first"; exit 2; }

while read -r label wantRc wantOutHash wantErrHash; do
    [ -n "$label" ] || continue
    runVerb "$label"; rc=$?
    gotOutHash="$( hashfile "$TMP/out" )"
    gotErrHash="$( hashfile "$TMP/err" )"
    if [ "$rc" != "$wantRc" ]; then
        no "$label: exit code changed ($wantRc -> $rc)"
    elif [ "$gotOutHash" != "$wantOutHash" ]; then
        no "$label: STDOUT bytes changed (sha256 $wantOutHash -> $gotOutHash) — a printf-family conversion altered output"
    elif [ "$gotErrHash" != "$wantErrHash" ]; then
        no "$label: STDERR bytes changed (sha256 $wantErrHash -> $gotErrHash) — a printf-family conversion altered a refusal/diagnostic message"
    else
        ok "$label (rc=$rc, out=$gotOutHash, err=$gotErrHash)"
    fi
done <"$MANIFEST"

if [ "$fail" = 0 ]; then
    echo "ALL PASS — printf-family byte parity holds over $( wc -l <"$MANIFEST" | tr -d ' ' ) verbs"
else
    echo "printffmtparitycheck: FAIL — see above. Any file whose conversion moved these bytes must be reverted."
fi
exit $fail
