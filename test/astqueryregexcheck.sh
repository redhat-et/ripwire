#!/usr/bin/env bash
# astqueryregexcheck.sh — gate for the #match? / #not-match? predicate regex in passesPredicates
# (src/ingest_astquery.h): its COMPILATION was hoisted out of the per-match path into a table built once
# per compiled TSQuery, and none of its SEMANTICS may move with it.
#
# WHY THIS EXISTS. `std::regex_search( lhs, std::regex( rhs ) )` ran once per query MATCH, per file, and
# `rhs` is a constant owned by the TSQuery — so the most expensive constructor in the standard library was
# being run to answer a question whose answer never changes. A 1 ms `sample` of `--lint` over the go
# corpus (44,376 busy leaf samples) put the `std::basic_regex` subtree at 13.52% of busy CPU, 100% of it
# owned by passesPredicates, and regex CONSTRUCTION (not matching) at ~46.7% of every malloc leaf in the
# run. Hoisting it is worth doing and is exactly the kind of change that silently alters a filter.
#
# WHAT IS AT RISK, and therefore what is gated. Five things a "compile it once" change can quietly move:
#   * the FLAGS. std::regex's default is ECMAScript, case-SENSITIVE. A build that added icase would still
#     look right on most patterns.
#   * search vs match. regex_search finds a substring; regex_match requires the whole string.
#   * the REFUSAL. A malformed pattern threw out of the constructor, was caught, and left `ok = true` —
#     i.e. it filtered NOTHING. Precompiling moves that throw from the match to the build, so the arm has
#     to be preserved deliberately; getting it wrong turns a broken rule into a rule that drops every row.
#   * the CAPTURE-typed argument. `(#match? @a @b)` has no constant to precompile — it must stay dynamic.
#   * THREAD SAFETY. The compiled regex is now SHARED across the query pool's workers instead of being
#     built per match. Concurrent const use of a standard library object is data-race-free by
#     [res.on.data.races], so this is legal — arm F is the empirical half of that claim.
#
# ARMS
#   A  GOLDEN. `--lint` and six `--match` probes over a fixture this script materialises (deterministic
#      text, written here, so the corpus cannot drift out from under the golden) must be byte-identical to
#      test/astqueryregex_golden.txt, which was RECORDED FROM THE PRE-CHANGE BINARY. That is the whole
#      "the hoist changed nothing" claim, in the only form that can be checked later by someone who was
#      not there. UPDATE_GOLDEN=1 re-records it — review the diff first.
#   B  NON-VACUITY. The golden must contain the rows the predicates actually decide (a #match?-only lint
#      rule with a non-zero count), or arm A would be a golden of an empty filter.
#   C  CAN GO RED WITHOUT A REBUILD. Four differential probes whose ANSWERS pin the semantics above, so a
#      build that moved any of them fails arm A AND is diagnosed by name here:
#        C1 case sensitivity  — "^Foo" and "^foo" must select DIFFERENT single functions (an icase build
#           makes both select two, which is the mutation the round actually ran; see the note below).
#        C2 search, not match — a bare substring "oo" must select both of them.
#        C3 complement       — #not-match? on a pattern must select exactly the rows #match? does not.
#        C4 refusal          — a malformed pattern "(" must filter NOTHING, i.e. return the same rows as
#           the same query with no predicate at all.
#   D  CAPTURE-TYPED ARGUMENT. `(#match? @a @b)` still evaluates per match (its pattern is not a constant),
#      and the probe's answer is pinned in the golden with the rest.
#   E  MUTATION CONTROL for arm C. Each of C1-C4 is re-run with its expectation INVERTED and must fail —
#      an arm that cannot be observed failing is decoration.
#   F  DETERMINISM UNDER THE POOL. `--lint` is run five times over a multi-file fixture; all five must be
#      byte-identical. The regex is shared read-only across the worker threads that evaluate predicates,
#      and this is the arm that would catch a shared-mutable-state regression in the cheapest place.
#
# THE REBUILD MUTATION, run once by hand rather than in this gate. The round that landed the hoist built a
# scratch binary with `std::regex::icase` added to the precompiled construction and confirmed arm C1 goes
# red (both probes return 2 hits instead of 1 each) and arm A fails. It is NOT run here: a gate that builds
# the whole binary is super-linear in CI contention (see the round notes on crossdirincludecheck), and
# C1's differential answer is the same evidence at a thousandth of the cost.
#
# Usage:  bash test/astqueryregexcheck.sh            [ RIPWIRE_BIN=build/ripwire ]  [ UPDATE_GOLDEN=1 ]
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
case "$BIN" in /*) ;; *) BIN="$ROOT/$BIN";; esac
GOLD="$ROOT/test/astqueryregex_golden.txt"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "astqueryregexcheck: BIN=$BIN"

# ── the fixture, written HERE so the corpus can never drift out from under the golden ────────────────
FIX="$TMP/fix"
mkdir -p "$FIX"
cat > "$FIX/a.cpp" <<'FIXA'
#include <cstring>
void Foo( char* dst, const char* srcText )
{
    strcpy( dst, srcText );
    sprintf( dst, "%s", srcText );
}
void foo2( char* d ) { strcat( d, "x" ); }
unsigned MD5( const char* p );
unsigned sha1sum( const char* p );
void useHash( const char* p ) { MD5( p ); sha1sum( p ); }
int strcp( int x ) { return x; }
FIXA
cat > "$FIX/b.cpp" <<'FIXB'
#include <cstring>
namespace second
{
void Barrier( char* d, const char* s ) { strcpy( d, s ); }
void barrier2( char* d ) { sprintf( d, "%d", 1 ); }
unsigned md4( const char* p );
void useMd4( const char* p ) { md4( p ); }
}
FIXB
cat > "$FIX/c.c" <<'FIXC'
#include <string.h>
void plainC( char* d, const char* s ) { strcat( d, s ); }
void alsoPlain( char* d ) { gets( d ); }
FIXC

# Every probe, run through ONE helper so the golden and the differential arms cannot disagree about how a
# run is spelled. The corpus root is an absolute temp path, so it is normalised out; nothing else in these
# outputs is machine-dependent (paths inside the map are already root-relative).
FN_DEF='(function_definition declarator: (function_declarator declarator: (identifier) @n)'
probe(){                                      # $1 = label, rest = argv after the corpus
    local label="$1"; shift
    printf '===== %s\n' "$label"
    "$BIN" "$FIX" --no-cache "$@" 2>/dev/null | sed "s#$FIX#<ROOT>#g"
    # An EXPLICIT terminator, not a blank line: the map output carries no trailing newline (G4), so a
    # blank-line delimiter would not exist and every per-section `sed` range below would silently run to
    # end of file — which is exactly the shape of a differential arm that compares two identical
    # whole-file reads and reports "different" forever.
    printf '\n----- end %s\n' "$label"
}
emit_all(){
    probe "lint"            --lint
    probe "match-anchor-Foo"  "--match=$FN_DEF (#match? @n \"^Foo\"))"
    probe "match-anchor-foo"  "--match=$FN_DEF (#match? @n \"^foo\"))"
    probe "match-substring"   "--match=$FN_DEF (#match? @n \"oo\"))"
    probe "match-not-anchor"  "--match=$FN_DEF (#not-match? @n \"^Foo\"))"
    probe "match-malformed"   "--match=$FN_DEF (#match? @n \"(\"))"
    probe "match-no-predicate" "--match=$FN_DEF)"
    probe "match-capture-arg" "--match=(call_expression function: (identifier) @f arguments: (argument_list (identifier) @a) (#match? @f @a))"
}

emit_all > "$TMP/now.txt"

# ── A. the golden ────────────────────────────────────────────────────────────────────────────────────
if [ "${UPDATE_GOLDEN:-0}" = "1" ]; then
    cp "$TMP/now.txt" "$GOLD"
    ok "A: UPDATE_GOLDEN=1 — re-recorded $( wc -c < "$GOLD" | tr -d ' ' ) B into test/astqueryregex_golden.txt (review the diff)"
elif [ ! -f "$GOLD" ]; then
    no "A: no golden at test/astqueryregex_golden.txt — record it with UPDATE_GOLDEN=1 against the PRE-change binary"
elif cmp -s "$TMP/now.txt" "$GOLD"; then
    ok "A: --lint + 7 --match probes byte-identical to the recorded golden ($( wc -c < "$GOLD" | tr -d ' ' ) B)"
else
    no "A: output differs from test/astqueryregex_golden.txt"
    diff "$GOLD" "$TMP/now.txt" | head -20 | sed 's/^/    /'
fi

# ── B. non-vacuity: the predicates must actually be deciding something ───────────────────────────────
UNSAFE="$( sed -n 's/.*rule name="unsafe-c-fn" count="\([0-9]*\)".*/\1/p' "$TMP/now.txt" | head -1 )"
WEAK="$(   sed -n 's/.*rule name="weak-crypto" count="\([0-9]*\)".*/\1/p' "$TMP/now.txt" | head -1 )"
if [ "${UNSAFE:-0}" -lt 3 ] || [ "${WEAK:-0}" -lt 1 ]; then
    no "B: the two #match?-only lint rules found ${UNSAFE:-0} / ${WEAK:-0} — the golden would be a golden of an empty filter"
else
    ok "B: the #match?-only lint rules are live on this fixture (unsafe-c-fn=$UNSAFE, weak-crypto=$WEAK)"
fi

# ── C. differential arms — each one pins a semantic the hoist could have moved ───────────────────────
section(){ sed -n "/^===== $1\$/,/^----- end $1\$/p" "$TMP/now.txt"; }
hits(){ section "$1" | sed -n 's/.*<match hits="\([0-9]*\)".*/\1/p' | head -1; }
names(){ section "$1" | grep -o 'in="[A-Za-z0-9_]*"' | sort -u; }

# The four expectations, as a table, so arm E can invert each one mechanically.
#   name | left probe | right probe | relation | why
expect(){                                  # $1 = arm, $2 = actual, $3 = expected, $4 = prose
    if [ "$2" = "$3" ]; then ok "$1: $4 (got $2)"; else no "$1: $4 — expected $3, got $2"; fi
}
C1L="$( hits 'match-anchor-Foo' )"; C1R="$( hits 'match-anchor-foo' )"
expect "C1" "$C1L/$C1R" "1/1" "case-SENSITIVE ECMAScript: \"^Foo\" and \"^foo\" each select exactly one function"
if [ "$( names 'match-anchor-Foo' )" = "$( names 'match-anchor-foo' )" ]; then
    no "C1: \"^Foo\" and \"^foo\" selected the SAME function — the regex is case-insensitive"
else
    ok "C1: \"^Foo\" and \"^foo\" select DIFFERENT functions"
fi
expect "C2" "$( hits 'match-substring' )" "2" "regex_SEARCH, not regex_match: the bare substring \"oo\" selects both"
C3N="$( hits 'match-not-anchor' )"; C3A="$( hits 'match-no-predicate' )"
expect "C3" "$C3N" "$(( ${C3A:-0} - ${C1L:-0} ))" "#not-match? is the exact complement of #match? over the same rows"
expect "C4" "$( hits 'match-malformed' )" "$C3A" "a MALFORMED pattern filters NOTHING (the constructor's throw leaves ok = true)"

# ── D. capture-typed argument: no constant to precompile, so it must still be evaluated ──────────────
# NON-VACUITY, not just presence (CodeRabbit #127 / 3985249714 asked for it; the review's premise — that
# no fixture call satisfies the relation — is wrong, see below, but `grep -q '<match '` WAS too weak: a
# root with hits="0" would have passed it, and that is the shape a dead dynamic-predicate path produces).
# The fixture's `strcpy( d, s )` / `strcat( d, s )` satisfy `(#match? @f @a)` — regex_search("strcpy", "s")
# is TRUE — so the probe emits 4 captures, and the golden has pinned all 4 since it was recorded.
D_HITS="$( hits 'match-capture-arg' )"
if [ -z "$D_HITS" ]; then
    no "D: the Capture-typed #match? probe emitted no match root at all"
elif [ "$D_HITS" -lt 1 ]; then
    no "D: the Capture-typed #match? probe emitted hits=\"$D_HITS\" — the dynamic predicate matched nothing,"
    no "   so arm A would be pinning a golden of a predicate that never fires"
else
    ok "D: a Capture-typed #match? argument still runs and MATCHES (hits=$D_HITS; per-match text, never precompiled)"
fi

# ── E. mutation control for arm C: each expectation, inverted, must FAIL ─────────────────────────────
# Without this, arms C1-C4 could be comparing a number against itself. `expect` is re-run against a value
# it must NOT equal; the arm is healthy when every inverted check reports a failure.
inverted=0
check_inverts(){ [ "$1" != "$2" ] && inverted=$(( inverted + 1 )); }
check_inverts "$C1L/$C1R"                 "2/2"                              # what an icase build returns
check_inverts "$( hits 'match-substring' )" "0"                              # what regex_match would return
check_inverts "$C3N"                      "$C3A"                             # a #not-match? that filtered nothing
check_inverts "$( hits 'match-malformed' )" "0"                              # a refusal that dropped every row
if [ "$inverted" -eq 4 ]; then
    ok "E: all 4 inverted expectations are FALSE — arms C1-C4 are comparing real, distinguishable answers"
else
    no "E: only $inverted of 4 inverted expectations are false — an arm in C is comparing a value with itself"
fi

# ── F. determinism under the query pool (the regex is shared read-only across workers) ───────────────
same=1
"$BIN" "$FIX" --no-cache --lint 2>/dev/null > "$TMP/det0"
for i in 1 2 3 4; do
    "$BIN" "$FIX" --no-cache --lint 2>/dev/null > "$TMP/det$i"
    cmp -s "$TMP/det0" "$TMP/det$i" || same=0
done
if [ ! -s "$TMP/det0" ]; then
    no "F: --lint produced 0 B — an empty output compares identical to itself, which proves nothing"
elif [ "$same" -eq 1 ]; then
    ok "F: 5 --lint runs over the 3-file fixture byte-identical ($( wc -c < "$TMP/det0" | tr -d ' ' ) B) — the shared compiled regex is read-only across the pool"
else
    no "F: --lint is not deterministic across runs"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
