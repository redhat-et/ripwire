#!/usr/bin/env bash
# paginationcheck.sh — T2 gate: --limit/--offset on the high-cardinality verbs (--deps/--callers/
# --callees/--hotspots/--tree). The contract:
#   (a) DEFAULT (no --limit) is byte-IDENTICAL to a pre-T2 run — existing callers/gates unaffected.
#   (b) --limit=N bounds the response to N items; the container's count=/ranked=/files= stays the TRUE total.
#   (c) SEAMS are continuous + deterministic: because results are already sorted, page (--offset=k,--limit=N)
#       is the exact continuation of the previous page — concatenating pages == the full list, no item
#       dropped or duplicated across a seam.
#   (d) offset past the end → an empty page, exit 0, no crash.
#
# §P8 UPDATE (2026-07-28) — this gate's contract is UNCHANGED and still pins these five verbs; what moved is
# the company they keep. --limit/--offset used to be honored ONLY here (plus --lint), and were accepted and
# SILENTLY IGNORED by --cochange/--owners/--clones/--doc-drift/--communities/--whereis/--grep, where a paging
# loop therefore never terminated. Those seven now page too — see test/pagingsweepcheck.sh, which owns their
# half of the contract, including the has_more=/next_offset= termination signal this gate predates.
# Two things to know when reading check (b)'s `offset="0" limit="3"` grep against --hotspots: those two
# attributes are still emitted, still last, still contiguous — but --hotspots now reaches them through the
# shared pageDisclosure() (src/pageview.h) rather than the older pageAttr(), so its paginated opening tag
# carries shown=/capped=/total=/has_more=/next_offset= AHEAD of them. Match on the pair, not on the whole
# tag. --hotspots also now discloses shown=/capped= with NO --limit at all (it was printing 40 of ranked=185
# and saying nothing), which is the one deliberate break in its un-paginated byte shape.
#
# Runs on src/ (a large, real, DETERMINISTIC tree) + test/queryfix. Mutation-tested: a deliberately wrong
# seam (drop/dup one item) MUST make check #3 fail — see the SELF-MUTATION note at the bottom.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/paginationcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
cd "$ROOT"

echo "paginationcheck: BIN=$BIN"

run(){ "$BIN" "$@" --no-cache 2>/dev/null; }

# item extractor per verb (an item = one emitted result row of the PAGINATED list):
#   callers/callees : <s ... />
#   tree            : <file p="..."   (one per file)
#   hotspots        : <f p="..." churn="...
#   deps            : <f p="..." includes="...   (the per-file body — NOT the godfiles/cycles preamble)
items(){ # $1=verb-kind ; reads stdin
    case "$1" in
        sym)      grep -oE '<s [^>]*/>' ;;
        tree)     grep -oE '<file p="[^"]*"' ;;
        hotspots) grep -oE '<f p="[^"]*" churn="[0-9]+"' ;;
        deps)     grep -oE '<f p="[^"]*" includes="[0-9]+"' ;;
    esac
}

# ── generic seam+bound+default checker. $1=label $2=item-kind $3.. = verb args (WITHOUT --limit/--offset) ──
check_verb(){
    local label="$1" kind="$2"; shift 2
    local full p1 p2 p3
    full="$( run "$@" )"

    # (a) default byte-identity is corpus/source-dependent; we assert the STRUCTURAL invariant instead:
    #     the default run carries NO page attrs (offset=/limit= only appear when pagination is active).
    if printf '%s' "$full" | grep -qE 'offset="[0-9]+" limit="[0-9]+"'; then
        no "$label: default (un-paginated) run leaked page attrs (should be byte-identical to pre-T2)"
    else
        ok "$label: default run carries no pagination attrs (byte-neutral posture)"
    fi

    # (b) --limit=3 emits at most 3 items and the container total is unchanged.
    p1="$( run "$@" --limit=3 --offset=0 )"
    local n1; n1="$( printf '%s' "$p1" | items "$kind" | wc -l | tr -d ' ' )"
    [ "$n1" -le 3 ] && ok "$label: --limit=3 emits <=3 items ($n1)" || no "$label: --limit=3 emitted $n1 items"
    printf '%s' "$p1" | grep -qE 'offset="0" limit="3"' && ok "$label: page attrs present when paginated" || no "$label: missing page attrs under --limit"

    # (c) SEAM: pages [0:3)+[3:6)+[6:9) concatenated == full[0:9], in order, no dup/drop.
    p2="$( run "$@" --limit=3 --offset=3 )"
    p3="$( run "$@" --limit=3 --offset=6 )"
    { printf '%s' "$p1" | items "$kind"; printf '%s' "$p2" | items "$kind"; printf '%s' "$p3" | items "$kind"; } > "$TMP/pages"
    printf '%s' "$full" | items "$kind" | head -9 > "$TMP/full9"
    if diff -q "$TMP/pages" "$TMP/full9" >/dev/null; then
        ok "$label: seam continuous — page[0:3]+[3:6]+[6:9] == full[0:9], no dup/drop"
    else
        no "$label: SEAM BROKEN (dropped/duplicated item across a page boundary)"; diff "$TMP/pages" "$TMP/full9" | head -6
    fi

    # (d) offset past the end → empty page, exit 0.
    run "$@" --limit=5 --offset=999999 >/dev/null 2>&1
    local ec=$?
    local nend; nend="$( run "$@" --limit=5 --offset=999999 | items "$kind" | wc -l | tr -d ' ' )"
    { [ "$ec" = 0 ] && [ "$nend" = 0 ]; } && ok "$label: offset past end → empty page, exit 0" \
        || no "$label: offset-past-end mishandled (exit=$ec items=$nend)"

    # (e) determinism: a paginated page is byte-identical run-to-run.
    local d1 d2; d1="$( run "$@" --limit=4 --offset=2 )"; d2="$( run "$@" --limit=4 --offset=2 )"
    [ "$d1" = "$d2" ] && ok "$label: paginated page deterministic" || no "$label: non-deterministic paginated page"

    # (f) xml well-formed under pagination.
    if command -v xmllint >/dev/null 2>&1; then
        printf '%s' "$p2" | xmllint --noout - 2>/dev/null && ok "$label: xml well-formed under pagination" || no "$label: xml malformed under pagination"
    fi
}

check_verb "callers"  sym      src --callers=size
check_verb "callees"  sym      src --callees=serialize
check_verb "tree"     tree     src --tree
check_verb "deps"     deps     src --deps
check_verb "hotspots" hotspots .   --hotspots

# ── SELF-MUTATION sanity: prove the seam check has teeth. A wrong page (offset off by one → a DROPPED
#    item) must fail the diff. We simulate the mutant by intentionally mis-paging and asserting the diff
#    DISAGREES with the correct full[0:9] (i.e. the check would catch a real off-by-one seam bug). ──────
MUT_P1="$( run src --callers=size --limit=3 --offset=0 | items sym )"
MUT_P2="$( run src --callers=size --limit=3 --offset=4 | items sym )"   # offset=4 (should be 3) → drops item #4
{ printf '%s' "$MUT_P1"; printf '%s' "$MUT_P2"; } > "$TMP/mut"
run src --callers=size | items sym | head -6 > "$TMP/mutfull"
if diff -q "$TMP/mut" "$TMP/mutfull" >/dev/null; then
    no "self-mutation: a WRONG seam (offset=4 instead of 3) still passed — the seam check lacks teeth"
else
    ok "self-mutation: an off-by-one seam (offset=4) IS caught by the diff — the seam check has teeth"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
