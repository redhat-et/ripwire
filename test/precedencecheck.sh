#!/usr/bin/env bash
# precedencecheck.sh — H12 gate: the verb-precedence NOTICE ("X takes precedence ... IGNORED this run: Y")
# must name the verb that ACTUALLY produced stdout, never a different one.
#
# The defect (capture-audit 2026-09-04, lens3-prose.md H1 / plan H12): `--stray-content=lane --abi` printed
# "ripwire: --stray-content takes precedence ... IGNORED this run: --abi" on stderr while stdout was the
# <abi ...> root the whole time. scanReportVerbPrecedence's slots[] table (src/main.cpp) disagreed with the
# real dispatch chain (src/verbs_change.h::runCrossRef), which treats --abi as a MODE of --stray-content
# (like --plan), never as an independently-dispatching verb — --abi alone already refuses ("composes with
# --stray-content's sweep — pass both"), exactly like --plan/--gateability/--detail/--partition, none of
# which own a row in the precedence table. --abi should not have owned one either.
#
# This gate does two things:
#   (1) the DIRECT regression check for the reported pair — stray-content vs abi, red-first.
#   (2) a FAMILY check over other pairs, deriving the expected winner from the SAME table the binary
#       actually compiles (parsed out of src/main.cpp at run time, not hand-copied here) rather than
#       trusting a second, hand-maintained copy of the order to stay in sync.
#
# Usage:  test/precedencecheck.sh   |   test/precedencecheck.sh asan/ripwire   |   RIPWIRE_BIN=... test/precedencecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "precedencecheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "precedencecheck: python3 is required"; exit 2; }

echo "precedencecheck: BIN=$BIN"

# firstTag OUTFILE — first real (non-comment) XML element name in OUTFILE.
firstTag()
{
    sed -e 's/<!--[^>]*-->//g' -e 's/<!--.*-->//g' "$1" | grep -o '<[a-zA-Z][a-zA-Z0-9-]*' | head -1 | tr -d '<'
}

# ── (1) the direct regression: --stray-content=lane --abi ──────────────────────────────────────────────
t1out="$( mktemp )"; t1err="$( mktemp )"
"$BIN" "$ROOT" --stray-content=lane --abi --no-cache >"$t1out" 2>"$t1err"
tag1="$( firstTag "$t1out" )"
if grep -q 'IGNORED this run' "$t1err"; then
    named="$( grep -oE 'IGNORED this run: [^.]+' "$t1err" | head -1 )"
    if [ "$tag1" = "abi" ]; then
        no "H12: --stray-content=lane --abi still prints a precedence notice ($named) while stdout is <abi> (the notice's implied winner disagrees with the real output)"
    else
        no "H12: --stray-content=lane --abi prints a precedence notice ($named) AND stdout is <$tag1>, neither of which is the expected <abi>"
    fi
else
    if [ "$tag1" = "abi" ]; then
        ok "H12: --stray-content=lane --abi emits <abi> with NO precedence notice (--abi is a mode of --stray-content, not a competing verb — nothing was 'ignored')"
    else
        no "H12: --stray-content=lane --abi printed no notice but stdout is <$tag1>, not <abi>"
    fi
fi

# Baseline: --stray-content alone (no --abi) must still win as itself — the fix must not have collaterally
# broken plain --stray-content dispatch or made it print a notice against nothing.
t2out="$( mktemp )"; t2err="$( mktemp )"
"$BIN" "$ROOT" --stray-content=lane --no-cache >"$t2out" 2>"$t2err"
tag2="$( firstTag "$t2out" )"
if [ "$tag2" = "stray-content" ] && ! grep -q 'IGNORED this run' "$t2err"; then
    ok "H12: bare --stray-content=lane still emits <stray-content> with no notice (unaffected by the --abi fix)"
else
    no "H12: bare --stray-content=lane regressed — tag=<$tag2>, notice-present=$( grep -c 'IGNORED this run' "$t2err" )"
fi

# ── (2) family check: derive the table's order from src/main.cpp itself, not a hand-copied list ─────────
orderFile="$( mktemp )"
python3 -c "
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'scanReportVerbPrecedence\( const rw::Config& c \)\s*\{.*?const ReportVerbSlot slots\[\] = \{(.*?)\};', text, re.S)
if not m:
    sys.exit('no table found')
flags = re.findall(r'\{\s*\"(--[a-zA-Z0-9=_-]+)\"', m.group(1))
print('\n'.join(flags))
" "$ROOT/src/main.cpp" > "$orderFile"

if [ ! -s "$orderFile" ]; then
    no "could not parse scanReportVerbPrecedence's slots[] table out of src/main.cpp — family check skipped"
else
    ok "parsed $( wc -l <"$orderFile" | tr -d ' ' ) rows out of scanReportVerbPrecedence's table (src/main.cpp)"
fi

# --abi must NOT be a row any more (it is a --stray-content MODE, like --plan/--gateability/--detail).
if grep -qx -- '--abi' "$orderFile"; then
    no "H12: --abi is STILL a row in scanReportVerbPrecedence's table — it never independently dispatches (see src/verbs_change.h::runCrossRef), so it should not own a precedence-table row"
else
    ok "H12: --abi is no longer a row in scanReportVerbPrecedence's table"
fi

orderIndex()
{
    grep -nx -- "$1" "$orderFile" | head -1 | cut -d: -f1
}

# curated, read-only report verbs this repo can answer meaningfully; args + expected root tag are the only
# hand-supplied facts (a shell script cannot invent either), but WHICH one wins each pair is derived from
# the table above, not hardcoded.
argsFor()
{
    case "$1" in
        --hotspots)     echo "--hotspots" ;;
        --clones)       echo "--clones" ;;
        --cochange)     echo "--cochange" ;;
        --owners)       echo "--owners" ;;
        --dead-code)    echo "--dead-code" ;;
        --communities)  echo "--communities" ;;
        --zoom)         echo "--zoom" ;;
        --seams)        echo "--seams" ;;
        --tree)         echo "--tree" ;;
        --lint)         echo "--lint" ;;
        *)              echo "" ;;
    esac
}
tagFor()
{
    case "$1" in
        --hotspots)     echo "hotspots" ;;
        --clones)       echo "clones" ;;
        --cochange)     echo "cochange" ;;
        --owners)       echo "owners" ;;
        --dead-code)    echo "dead-code" ;;
        --communities)  echo "communities" ;;
        --zoom)         echo "zoom" ;;
        --seams)        echo "seams" ;;
        --tree)         echo "tree" ;;
        --lint)         echo "lint" ;;
        *)              echo "" ;;
    esac
}

assertTablePair()
{
    local a="$1" b="$2"
    local ia ib
    ia="$( orderIndex "$a" )"; ib="$( orderIndex "$b" )"
    if [ -z "$ia" ] || [ -z "$ib" ]; then
        no "precedence family: '$a' or '$b' is not in the parsed table — cannot derive an expected winner"
        return
    fi
    local winner loser
    if [ "$ia" -lt "$ib" ]; then winner="$a"; loser="$b"; else winner="$b"; loser="$a"; fi
    local wantTag; wantTag="$( tagFor "$winner" )"
    local out err
    out="$( mktemp )"; err="$( mktemp )"
    # shellcheck disable=SC2046
    "$BIN" "$ROOT" $( argsFor "$a" ) $( argsFor "$b" ) --no-cache >"$out" 2>"$err"
    local got; got="$( firstTag "$out" )"
    if [ "$got" = "$wantTag" ]; then
        ok "precedence family: $winner (table row $ia) beats $loser (row $ib) — stdout is <$got>"
    else
        no "precedence family: table says $winner (row $ia) should beat $loser (row $ib), stdout is <$got> not <$wantTag>"
    fi
    if grep -q 'IGNORED this run' "$err"; then
        grep -qF -- "$winner" "$err" && grep -qF -- "$loser" "$err" \
            && ok "precedence family: $winner/$loser notice names the real winner ($winner) and the real loser ($loser)" \
            || no "precedence family: $winner/$loser notice does not name both flags correctly: $( grep 'IGNORED this run' "$err" )"
    else
        no "precedence family: $winner/$loser printed no notice even though two report verbs were given"
    fi
}

assertTablePair "--hotspots"    "--clones"
assertTablePair "--clones"      "--cochange"
assertTablePair "--owners"      "--dead-code"
assertTablePair "--dead-code"   "--communities"
assertTablePair "--communities" "--zoom"
assertTablePair "--zoom"        "--seams"
assertTablePair "--seams"       "--tree"
assertTablePair "--tree"        "--lint"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "SOME CHECKS FAILED"
fi
exit "$fail"
