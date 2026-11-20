#!/usr/bin/env bash
# repeateddecisioncheck.sh — QD-REPEATED-DECISION: the "name the decision once" facet (src/repeateddecision.h).
#
# WHY THIS GATE EXISTS. Two of #697's merged complexity slips had one tell no row named: defGroupsDropSilent tested
# `groups.untied[k] && !named[k]` twice (once to count, once to renumber), and chooseInWindow copied its pass loop a
# second time for the last-resort passes. The fix of each was to decide once. A complexity or tangle row on such a
# function now carries fix="name the decision once: <condition> is tested at lines A and B" or "name the loop once:
# the loop body at line A repeats at line B". It is a facet: it never makes a row and never changes a severity.
#
# WHAT THIS GATE PINS — one repo, every function new in the working tree with ccx over the bar, so each has its row:
#   (P1) C++: the defGroupsDropSilent shape (a ternary count and an if over the same 9-token condition) names the decision
#   (P2) Python: the chooseInWindow shape (two pass loops with one body) names the loop
#   (N1) a complex function with no repeat carries no fix=
#   (N2) a 3-token condition (`p == nullptr`) tested twice is not named — a single fact, cheap to re-test
#   (N3) Python: two comprehensions on one line are not a repeated loop (their `for` opens no statement)
#   (N4) Python: a conditional expression's `if` repeated is not a repeated decision
#   (S)  the row's severity and gating are what they are without the facet: every row here is origin="new-symbol"
#   (C)  PREMISE COUNT — all six rows found; a missing row FAILS
#   (L)  a document with the facet defines it (full legend); one without carries no such sentence
# Red-before: on a binary without the facet, P1 and P2 FAIL. Guard-off (no minimum condition length, no statement test):
# N2, N3 and N4 FAIL.
#
# Usage:  bash test/repeateddecisioncheck.sh [BIN]

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" TMPDIR="$TMP"; mkdir -p "$HOME"
fail=0; seen=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

R="$TMP/repo"; mkdir -p "$R/src"
( cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false ) || { echo "git setup failed"; exit 2; }
printf '#pragma once\ninline int keep() { return 0; }\n' >"$R/src/keep.h"
( cd "$R" && git add -A && git commit -qm base ) || { echo "git setup failed"; exit 2; }

cat >"$R/src/groups.h" <<'EOF'
#pragma once
#include <cstddef>
#include <vector>
// P1: the defGroupsDropSilent shape — "untied and no row names it" decided twice
inline int dropSilent( const std::vector<int>& untied, const std::vector<int>& named, int mode )
{
    int left = 0;
    for( std::size_t k = 0; k < untied.size(); ++k )
    {
        left += ( untied[k] && !named[k] ) ? 0 : 1;
    }
    if( left >= 2 )
    {
        return left;
    }
    int dropped = 0;
    for( std::size_t k = 0; k < untied.size(); ++k )
    {
        if( untied[k] && !named[k] )
        {
            ++dropped;
            continue;
        }
        if( mode > 1 )
        {
            if( mode > 2 )
            {
                if( mode > 3 )
                {
                    dropped += 3;
                }
            }
        }
    }
    return dropped;
}
// N1: as complex, nothing decided twice
inline int tally( const std::vector<int>& v, int mode )
{
    int total = 0;
    for( std::size_t k = 0; k < v.size(); ++k )
    {
        if( v[k] > mode && v[k] % 2 == 0 )
        {
            total += v[k];
        }
        else if( v[k] < 0 || mode == 7 )
        {
            if( mode > 2 )
            {
                if( mode > 3 )
                {
                    if( mode > 4 )
                    {
                        total -= 1;
                    }
                }
            }
        }
    }
    return total;
}
// N2: a 3-token guard tested twice
inline int guarded( const int* p, const std::vector<int>& v, int mode )
{
    int total = 0;
    if( p == nullptr )
    {
        total = 1;
    }
    for( std::size_t k = 0; k < v.size(); ++k )
    {
        if( v[k] > mode && v[k] % 3 == 0 )
        {
            if( mode > 2 )
            {
                if( mode > 3 )
                {
                    if( mode > 4 )
                    {
                        total -= 1;
                    }
                }
            }
        }
    }
    if( p == nullptr )
    {
        total += 2;
    }
    return total;
}
EOF
cat >"$R/src/window.py" <<'EOF'
def choose_window(passes, last, lo, hi, probe, first):
    """P2: the chooseInWindow shape — the pass loop written twice."""
    for lim, ok, why in passes:
        n = first(lo, hi, ok)
        if n is not None:
            print(f"window HEAD~{n} ({why(n)})")
            return n, lim
    rev = probe()
    if rev is not None and rev > lo:
        return rev, 1
    for lim, ok, why in last:
        n = first(lo, hi, ok)
        if n is not None:
            print(f"window HEAD~{n} ({why(n)})")
            return n, lim
    if lo > 0:
        if hi > lo:
            if probe:
                if first:
                    return None
    return None


def comprehensions(rows, lo, hi, mode):
    """N3: two comprehensions on one line; N4: one conditional expression twice."""
    a, b = [r for r in rows if r > lo], [r for r in rows if r > lo]
    x = hi if mode is not None and mode > lo else lo
    y = hi if mode is not None and mode > lo else lo
    for r in rows:
        if r > hi and mode:
            if r > lo:
                if r > x:
                    if r > y:
                        if a and b:
                            return r
    return None
EOF

QD="$( "$BIN" "$R" --quality-delta --no-cache 2>/dev/null )"   # status: exits 0 or 2 by design; the rows are the verdict
crow(){ printf '%s' "$QD" | tr '<' '\n' | grep '^r kind="complexity"' | grep -- "sym=\"$1\"" | head -1; }
need(){ [ -n "$2" ] || { no "$1: no complexity row at all — the arm is vacuous"; return 1; }; seen=$(( seen + 1 )); return 0; }

echo "── positives"
P1="$( crow dropSilent )"
if need "(P1)" "$P1"; then
    case "$P1" in *'fix="name the decision once: untied[k] &amp;&amp; !named[k] is tested at lines 10 and 19"'*) ok "(P1) names the condition and both lines";;
                  *) no "(P1) no decision fix= (row: $P1)";; esac
fi
P2="$( crow choose_window )"
if need "(P2)" "$P2"; then
    case "$P2" in *'fix="name the loop once: the loop body at line 4 repeats at line 12"'*) ok "(P2) names the loop and both lines";;
                  *) no "(P2) no loop fix= (row: $P2)";; esac
fi

echo "── negatives"
N1="$( crow tally )"
if need "(N1)" "$N1"; then
    case "$N1" in *'fix='*) no "(N1) a function with no repeat carries fix= (row: $N1)";; *) ok "(N1) no fix=";; esac
fi
N2="$( crow guarded )"
if need "(N2)" "$N2"; then
    case "$N2" in *'name the decision once'*) no "(N2) a 3-token guard was named (row: $N2)";; *) ok "(N2) a 3-token guard is not named";; esac
fi
N34="$( crow comprehensions )"
if need "(N3/N4)" "$N34"; then
    seen=$(( seen + 1 ))
    case "$N34" in *'name the loop once'*) no "(N3) comprehensions read as a repeated loop (row: $N34)";; *) ok "(N3) two comprehensions are not a repeated loop";; esac
    case "$N34" in *'name the decision once'*) no "(N4) a conditional expression read as a repeated decision (row: $N34)";; *) ok "(N4) a conditional expression is not a decision";; esac
fi

echo "── (S) severity unchanged"
for r in "$P1" "$P2"; do
    case "$r" in *'origin="new-symbol"'*) ok "(S) the facet row keeps origin=\"new-symbol\"";; *) no "(S) the facet row lost its origin (row: $r)";; esac
    case "$r" in *'gating="1"'*) no "(S) the facet row gates (row: $r)";; *) ok "(S) the facet row does not gate";; esac
done

echo "── (C) premise count"
if [ "$seen" -eq 6 ]; then ok "(C) all six rows found"; else no "(C) $seen of 6 rows found"; fi

echo "── (L) legend"
FULL="$( "$BIN" "$R" --quality-delta --no-cache --legend=full 2>/dev/null )"
case "$FULL" in *'deciding it once is the cheapest fix'*) ok "(L) a document with the facet defines it";; *) no "(L) a document with the facet never defines it";; esac
mv "$R/src/groups.h" "$R/src/window.py" "$TMP/"
printf '#pragma once\ninline int keep() { return 1; }\ninline int more( int a ) { return a + 1; }\n' >"$R/src/keep.h"
FULL0="$( "$BIN" "$R" --quality-delta --no-cache --legend=full 2>/dev/null )"
case "$FULL0" in *'deciding it once is the cheapest fix'*) no "(L) a document without the facet pays for its sentence";; *) ok "(L) a document without the facet carries no such sentence";; esac

echo
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES"; exit 1
