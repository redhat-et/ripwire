#!/usr/bin/env bash
# stdqualcheck.sh — gate for the std::-QUALIFIED C++ call scope guard (graph.h keepStdQualifiedCandidates).
#
# WHAT WAS BROKEN. A C++ call written `std::X( … )` looks up the canonical key `std::X` first. When no in-repo
# def is keyed that way — the normal case, because the def lives in the standard library — the site fell to the
# bare-name spray, and a LONE in-repo definition named X took it: any class's `move()`, `swap()`, `fill()`, at
# full confidence, with no amb= and no prov="split". Nothing splits a lone candidate, so nothing disclosed it.
# Found by a read-only probe of a large C++20 database engine: one header-only string wrapper declares a
# `move()` member, and ~2,100 caller functions' std::move sites bound to it, making that one-line accessor the
# top-ranked symbol of the whole tree. A 6-line reproduction gave --callers count=3.
#
# THE RULE. A call whose written qualifier is `std` — `std::X`, `::std::X`, or a standard library's inline ABI
# namespace spelling such as `std::__1::X` — may bind only a definition that is itself inside namespace std: a
# def scoped `std`, a member of a class written `std::…`, or a def in one of those inline namespaces. When none
# survives the site is refused and counted in the header's `external=`. It is std-ONLY, on purpose: any other
# qualifier can legitimately miss its def's scope (a namespace alias, a using-declaration, a derived-class
# qualifier), and §8's alias arm is the true edge a general rule would delete.
#
# THE CORPUS is test/stdqualfix/; each file's header maps its call spellings to the arm below. EVERY expected
# number is a LITERAL read off those files by hand, never derived the way the resolver derives it.
#
# RED-FIRST (recorded 2026-09-11, plain build of origin/main 3511c93b, before graph.h changed): 19 of the 35
# checks FAIL. The pre-fix readings, each the literal the matching arm now refuses:
#   header           edges=15 ambiguous=1 unresolved=0 external=2           (now edges=6 ambiguous=0 external=12)
#   --callers        Buf::move 4, Slot::swap 3, Cursor::unreachable 2      (now 1 / 1 / 1)
#   --callees        takeTwice takeRooted takeInline flipTwice flipRooted stopHere rotate clearHost = 1 each
#                    (now 0 each); launderIt 2, amb="1", one arm on arena.h's decoy (now 1, polyfill.h, no amb=)
#   census           takeTwice 2x 'unique' -> Buf::move, rotate 'receiver-rule' -> Token::exchange (now 'external');
#                    C external rows 2 (bareMove, bridgeMove)               (now 12)
# The 16 that pass on BOTH binaries are, by construction, the controls: the true member calls (useBuf, useSlot,
# clearGrid), the alias call, the unqualified veto, the ObjC++ floor, the specialization zero and its vacuity
# guard, the Rule-3 eligibility guard, the name-based --uses counts and the hygiene arms. They are what proves the
# guard took ONLY what it should.
#
# THE GUARD IS LOAD-BEARING, PART BY PART (manual mutations, each a scratch build of graph.h, measured 2026-09-11;
# 35/35 PASS on the unmutated binary):
#   M1  guard never applies (cppFamilyRef forced false)            19 FAIL — byte-for-byte the RED readings above
#   M2  call site passes `alreadyPinned` instead of `canonical`,     4 FAIL — --callees=rotate 1, rotate's census row
#       i.e. a Rule-3-narrowed site is exempt (the Rust shape)       'receiver-rule', header edges=7 external=11, census 11
#   M3  inline ABI namespaces ignored (only a literal `std` counts)   4 FAIL — --callers=Buf::move 2 (std::__1::move binds
#                                                                    again), --callees=takeInline 1, launderIt 0 (the def
#                                                                    inside std::__1 is refused)
# M3 leaves the header at edges=6 external=12 — one edge swaps for one refusal — so only the per-function arms
# catch it. Keep them; the totals alone cannot.
#
# §11 (added 2026-09-11, FIXED 2026-09-23 by #150) covers nested std namespaces and declaration-only std defs,
# on a corpus this gate writes into $TMP; its own RED-FIRST evidence is recorded next to §11 itself, below. The
# 35-check counts above are #134's and do not include §11. §12 (added 2026-09-23) extends #150's coverage to
# the additional written shapes the fix's own design has to get right (`::std::`, an inline ABI namespace above
# a nested one, the C++17 `namespace std::ranges { … }` spelling, a namespace literally named `std` nested
# inside another, and `using namespace std::chrono;` — RED-FIRST evidence at §12 itself) plus `--callers`,
# `--impact` and `--dead-code` over the SAME §11 fixture, so the fix's effect on every verb `--quality-delta`
# and the other navigation verbs read is pinned, not just `--callees`.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/stdqualcheck.sh   |   bash test/stdqualcheck.sh asan/ripwire
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"      # BOTH seams: positional arg and RIPWIRE_BIN=
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # absolute BEFORE we cd away
# RELATIVE corpus path (we cd to $ROOT below): every p= is relative to the crawl root, so rows read
# `p="buffers.h:21"` and the literals below stay writable.
FIX="test/stdqualfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$ROOT/$FIX" ] || { echo "no test/stdqualfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "stdqualcheck: BIN=$BIN  CORPUS=$FIX"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
run(){ perl -e 'alarm 30; exec @ARGV' "$BIN" "$@" 2>/dev/null; }
cnt(){ printf '%s' "$1" | grep -oE 'count="[0-9]+"' | head -1 | tr -dc 0-9; }
el(){ printf '%s' "$1" | grep -oE '<(callers|callees) .*' | head -1; }   # the answer element, without the legend comment

expect(){   # $1 verb  $2 sym  $3 want  $4 prose
    local out; out="$( run "$FIX" "--$1=$2" --no-cache )"
    local got; got="$( cnt "$out" )"
    [ "${got:-REFUSED}" = "$3" ] && ok "--$1=$2 count=$3 — $4" \
        || no "--$1=$2 expected count=$3, got '${got:-REFUSED}' — $4"
}

# the census C rows for one caller: "<mech>\t<targets>" per site, in site order
crows(){ awk -F'\t' -v c="$1" '$1=="C" && index($6, c"#") > 0 {print $2 "\t" $8}' "$TMP/c.tsv"; }

run "$FIX" --pin-census="$TMP/c.tsv" --no-cache >"$TMP/map.xml"
MAP="$( cat "$TMP/map.xml" )"
[ -s "$TMP/c.tsv" ] || no "the census run wrote nothing — every census arm below would be vacuous"

# ── §1 THE FALSE EDGES ARE GONE — every std:: spelling, against a LONE same-named member ──────────────────────
BUFC="$( run "$FIX" --callers=Buf::move --no-cache )"
[ "$( cnt "$BUFC" )" = 1 ] \
    && ok "--callers=Buf::move count=1 — only the true member call remains (was 4: three std::move callers)" \
    || no "--callers=Buf::move expected 1, got '$( cnt "$BUFC" )': $( el "$BUFC" )"
printf '%s' "$BUFC" | grep -qE 'n="(takeTwice|takeRooted|takeInline)"' \
    && no "a std::move caller still binds Buf::move: $( el "$BUFC" )" \
    || ok "no std::move / ::std::move / std::__1::move caller is listed under Buf::move"
expect callers Slot::swap          1 "only useSlot's a.swap( b ) remains (was 3)"
expect callees takeTwice           0 "std::move x2 binds nothing in-repo (was Buf::move)"
expect callees takeRooted          0 "::std::move — the leading-:: spelling arrives as qualifier std"
expect callees takeInline          0 "std::__1::move — the libc++ inline-namespace spelling arrives as __1"
expect callees flipTwice           0 "std::swap x2 binds nothing in-repo (was Slot::swap)"
expect callees flipRooted          0 "::std::swap binds nothing in-repo"
expect callees stopHere            0 "std::unreachable() in a .cpp binds nothing in-repo (was Cursor::unreachable)"
# NON-VACUITY: the sites still EXTRACT. --uses is name-based by contract (it answers "where is this name written",
# the call graph answers "what resolves to this def"), so the refused sites stay listed — a count of 0 above is the
# resolver refusing, not the reference disappearing. 7 = takeTwice 2 + takeRooted + takeInline + useBuf + bareMove
# + bridgeMove; 4 = flipTwice 2 + flipRooted + useSlot.
expect uses    move                7 "every move site is still a use-site (unchanged by the guard)"
expect uses    swap                4 "every swap site is still a use-site (unchanged by the guard)"
[ "$( crows takeTwice | grep -c '^external' )" = 2 ] \
    && ok "census: takeTwice has 2 'external' rows — one per std::move SITE, refused rather than dropped silently" \
    || no "census: takeTwice expected 2 external rows, got: $( crows takeTwice | tr '\n' ' ' )"

# ── §2 THE TRUE MEMBER CALLS ARE KEPT ────────────────────────────────────────────────────────────────────────
USEBUF="$( run "$FIX" --callees=useBuf --no-cache )"
{ [ "$( cnt "$USEBUF" )" = 1 ] && printf '%s' "$USEBUF" | grep -q 'n="Buf::move" p="buffers.h:21"'; } \
    && ok "--callees=useBuf count=1 -> Buf::move (buffers.h:21) — buf.move() still binds" \
    || no "useBuf lost its true edge to Buf::move: $( el "$USEBUF" )"
USESLOT="$( run "$FIX" --callees=useSlot --no-cache )"
{ [ "$( cnt "$USESLOT" )" = 1 ] && printf '%s' "$USESLOT" | grep -q 'n="Slot::swap" p="buffers.h:29"'; } \
    && ok "--callees=useSlot count=1 -> Slot::swap (buffers.h:29) — a.swap( b ) still binds" \
    || no "useSlot lost its true edge to Slot::swap: $( el "$USESLOT" )"

# ── §3 A DEF INSIDE namespace std STILL BINDS — the survivor path, and the specialization reading ──────────────
# polyfill.h puts `launder` in `namespace std { inline namespace __1 { … } }`, so its scope is "__1" and the
# canonical key std::launder misses; arena.h holds a same-directory decoy. The guard must keep the def inside std.
LAUNDER="$( run "$FIX" --callees=launderIt --no-cache )"
{ [ "$( cnt "$LAUNDER" )" = 1 ] && printf '%s' "$LAUNDER" | grep -q 'n="launder" p="polyfill.h:15"'; } \
    && ok "--callees=launderIt count=1 -> the std::__1::launder def (polyfill.h:15) — the def inside std survives" \
    || no "launderIt did not bind exactly the inline-namespace def (was 2, split onto arena.h): $( el "$LAUNDER" )"
printf '%s' "$LAUNDER" | grep -q 'p="arena.h' \
    && no "launderIt still reaches the Arena::launder decoy: $( el "$LAUNDER" )" \
    || ok "no edge from std::launder to the Arena::launder decoy"
printf '%s' "$MAP" | grep -qE 'n="launderIt"[^>]*amb=' \
    && no "launderIt carries amb= — the guard left a split where one def is inside std" \
    || ok "PRECISE: launderIt carries no amb= (was amb=\"1\")"
# stdspec.cpp: `namespace std { template<> struct hash<Mine> { operator() } }` used as `std::hash<Mine>{}( m )`.
# Measured on the pre-fix binary: zero callees — the brace-initialised temporary names no call reference that
# reaches operator(). Pinned at that literal so the guard is seen to invent nothing; the vacuity guard asserts
# the specialization's operator() really is indexed (so the zero is about resolution, not a missing file).
printf '%s' "$MAP" | grep -qE '<s t="method" n="operator\(\)" sc="hash&lt;Mine&gt;"' \
    && ok "the std::hash<Mine> specialization's operator() IS indexed (scope hash<Mine>)" \
    || no "the specialization's operator() is missing from the map — the arm below is vacuous"
expect callees hashMine            0 "std::hash<Mine>{}( m ) — no edge today, none after: pinned, not invented"

# ── §4 A RULE-3-NARROWED SITE IS STILL GUARDED ──────────────────────────────────────────────────────────────
# `exchange` has two defs (token.h, sub/ledger.h) and exchange_user.cpp includes only token.h, so Rule 3 pins
# `std::exchange` to Token::exchange — census mech "receiver-rule", no amb=. An #include is evidence about FILES,
# never about namespace std, so only the canonical tier may exempt a site from the guard.
[ "$( run "$FIX" --uses=exchange --no-cache | grep -oE '<uses [^>]*>' | grep -oE 'defs="[0-9]+"' )" = 'defs="2"' ] \
    && ok "exchange has 2 defs, so Rule 3 is eligible (the arm below tests a narrowed site, not a lone one)" \
    || no "exchange no longer has exactly 2 defs — the Rule-3 arm is vacuous"
expect callees rotate              0 "std::exchange narrowed by Rule 3 to Token::exchange is refused (was 1)"
[ "$( crows rotate )" = "$( printf 'external\t' )" ] \
    && ok "census: rotate's one site is 'external' (was 'receiver-rule' -> token.h::Token::exchange)" \
    || no "census: rotate expected one external row, got: $( crows rotate | tr '\n' ' ' )"

# ── §5 THE CUDA GRAMMAR PATH ─────────────────────────────────────────────────────────────────────────────────
expect callees clearHost           0 "kernels.cu std::fill binds nothing in-repo (was Grid::fill)"
CGRID="$( run "$FIX" --callees=clearGrid --no-cache )"
{ [ "$( cnt "$CGRID" )" = 1 ] && printf '%s' "$CGRID" | grep -q 'n="Grid::fill" p="kernels.cu:7"'; } \
    && ok "--callees=clearGrid count=1 -> Grid::fill (kernels.cu:7) — the CUDA member call still binds" \
    || no "clearGrid lost its true edge to Grid::fill: $( el "$CGRID" )"

# ── §6 THE UNQUALIFIED CONTROL IS UNCHANGED ─────────────────────────────────────────────────────────────────
# `move( x )` under `using namespace std;` has no qualifier; the Phase-5 veto refuses it (table name, no free move),
# before the fix and after. Asserted from the census so the zero cannot be a missing site.
expect callees bareMove            0 "unqualified move( x ) binds nothing — the Phase-5 veto, as before"
[ "$( crows bareMove )" = "$( printf 'external\t' )" ] \
    && ok "census: bareMove's site is refused by the Phase-5 veto ('external', no target) — unchanged" \
    || no "census: bareMove expected one external row, got: $( crows bareMove | tr '\n' ' ' )"

# ── §7 ObjC++ — the qualifier is lost at EXTRACTION, so the guard cannot see it (a STATED FLOOR) ────────────────
# tree-sitter-objc parses `std::move( x )` as an ERROR node `std::` beside a bare call. bridgeMove is refused by
# the Phase-5 veto on both binaries; bridgeStop's std::unreachable is not a table name and still binds the lone
# Cursor::unreachable. Pinned so that closing the floor (a parser change) is a visible decision, not drift.
# KNOWN GAP (help wanted, the optional part of prompts/help-wanted/cpp-nested-std-namespaces.md): recovering the ObjC++
# qualifier flips the FLOOR arm below — rewrite it to count=0 in the same commit.
expect callees bridgeMove          0 "bridge.mm std::move — refused by the Phase-5 veto, not by this guard"
BSTOP="$( run "$FIX" --callees=bridgeStop --no-cache )"
{ [ "$( cnt "$BSTOP" )" = 1 ] && printf '%s' "$BSTOP" | grep -q 'n="Cursor::unreachable" p="buffers.h:38"'; } \
    && ok "FLOOR: bridge.mm std::unreachable() still binds Cursor::unreachable — ObjC++ carries no qualifier" \
    || no "the ObjC++ floor moved (bridgeStop no longer binds Cursor::unreachable) — update this arm and the fixture: $( el "$BSTOP" )"
expect callers Cursor::unreachable 1 "only the ObjC++ floor remains under Cursor::unreachable (was 2: stopHere too)"

# ── §8 A NON-std QUALIFIER IS UNCHANGED — the alias control ──────────────────────────────────────────────────
PROBE="$( run "$FIX" --callees=probePath --no-cache )"
{ [ "$( cnt "$PROBE" )" = 1 ] && printf '%s' "$PROBE" | grep -q 'n="exists" p="alias.cpp:10"'; } \
    && ok "--callees=probePath count=1 -> vendor::fsimpl::exists via the fs:: alias — a non-std qualifier keeps its edge" \
    || no "the fs:: alias call lost its true edge (the guard generalised past std): $( el "$PROBE" )"

# ── §9 THE HEADER DISCLOSURE MOVES THE RIGHT WAY ─────────────────────────────────────────────────────────────
# edges 15 -> 6: the eight std-qualified false edges go, and launderIt's split collapses to one arm.
# ambiguous 1 -> 0: that split was the corpus's only guess. external 2 -> 12: the ten refused std-qualified SITES
# (takeTwice 2, takeRooted, takeInline, flipTwice 2, flipRooted, stopHere, rotate, clearHost) join the two
# Phase-5 refusals (bareMove, bridgeMove). unresolved stays 0: that gauge means "defined in-repo but lang-filtered".
printf '%s' "$MAP" | grep -qE 'files=13 symbols=35 edges=6 shown=35 est_tokens=[0-9]+ ambiguous=0 unresolved=0 external=12 ' \
    && ok "fixture header: edges=6 ambiguous=0 unresolved=0 external=12 (was edges=15 ambiguous=1 external=2)" \
    || no "fixture header wrong: $( printf '%s' "$MAP" | grep -oE 'files=13 [^-]*' | head -1 )"
[ "$( grep -c $'^C\texternal\t' "$TMP/c.tsv" )" = 12 ] \
    && ok "census: exactly 12 'C external' rows — one per refusal, agreeing with the header's external=12" \
    || no "census: expected 12 external rows, got $( grep -c $'^C\texternal\t' "$TMP/c.tsv" )"

# ── §10 hygiene: determinism, warm == cold, well-formed XML ──────────────────────────────────────────────────
run "$FIX" --pin-census="$TMP/c2.tsv" --no-cache >"$TMP/map2.xml"
cmp -s "$TMP/map.xml" "$TMP/map2.xml" && cmp -s "$TMP/c.tsv" "$TMP/c2.tsv" \
    && ok "deterministic: map + census byte-identical across two --no-cache runs" \
    || no "non-deterministic: map or census differs between two runs"
run "$FIX" --cache="$TMP/c.bin" >"$TMP/cold.xml"; run "$FIX" --cache="$TMP/c.bin" >"$TMP/warm.xml"
cmp -s "$TMP/cold.xml" "$TMP/warm.xml" \
    && ok "warm == cold (the guard reads only facts that survive the cache round-trip)" \
    || no "warm != cold"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/map.xml" 2>/dev/null && printf '%s' "$BUFC" | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed (fixture map + --callers)" || no "xml malformed"
else
    no "cannot verify G4: xmllint is NOT INSTALLED — this check did not run (install libxml2)"
fi

# ── §11 NESTED std NAMESPACES (#150, fixed) ──────────────────────────────────────────────────────────────────────
# Was a KNOWN GAP section for prompts/help-wanted/cpp-nested-std-namespaces.md, pinning three wrong answers
# (K1-K3 below) that PASSED on every pre-#150 binary. #150 widened keepStdQualifiedCandidates (graph.h) to read
# the FULL written qualifier chain (Reference::qualifierRootsStd / Symbol::scopeRootsStd, computed at extraction
# by ingest_names.h cppQualifiedChainRootsStd/cppEnclosingChainRootsStd/cppDefinitionRootsStd), not just the
# immediate segment #134 read — the arms below now assert the CORRECTED literals (count=0, one 'external' census
# row each) and the RED evidence (the pre-#150 wrong answers) is recorded in this section's own history comment
# below. The CONTROL arms hold on both binaries; they are what proves the fix took only what it should.
#
# WHY THIS FIXTURE IS WRITTEN AT RUN TIME into $TMP instead of committed beside test/stdqualfix. ripwire's own
# tracked sources call these names, so a committed decoy is not inert. Measured 2026-09-11 with a temporary,
# uncommitted copy of these four files under test/: --callers=duration_cast on the whole repo counted 7, among them
# ripwire's own now_ticks (src/infra/profileScope.h) and wallClockNs (src/ingest_crawl.h), whose
# std::chrono::duration_cast calls bound to the decoy by exactly gap K2 below. The decoy move and the
# declaration-only std::terminate took no caller outside the fixture in that run. A committed copy would plant K2's
# false edges in ripwire's own map and move every live-tree capture that reads them. A heredoc is as literal as a
# committed file, and invisible to the self-crawl.
#
# THE THREE GAPS — RED-FIRST EVIDENCE, measured 2026-09-11 on a plain build of main 766913d0, and reconfirmed
# 2026-09-23 on origin/main 60b65f02 (pre-#150) before this fix (census mech in quotes):
#   K1  std::ranges::move( from, to.begin() ) in shiftRange. The call arrives with qualifier "ranges", the IMMEDIATE
#       segment, which cannot be told from a user namespace; the guard never applies and the bare-name spray hands
#       the site to the LONE in-repo move, Pool::move ('unique'). #134 left exactly this shape as the one false
#       caller of the large engine's SafeString::move.
#   K2  std::chrono::duration_cast<…>( s ) in toMillis. Worse than K1: the canonical key chrono::duration_cast HITS a
#       user namespace that mirrors std's layout (vendorlib::chrono; Boost.Chrono's boost::chrono::duration_cast is
#       the real-world twin), and a canonical hit is exempt from the guard by design ('qualified', no amb=).
#   K3  std::terminate() in bail, against compat.h's DECLARATION-ONLY `namespace std { void terminate() noexcept; }`.
#       The guard keeps the candidate because its scope is std; nothing in the corpus defines it ('unique').
# On the #150 FIX (this binary): K1/K2/K3 all refuse (count=0, one 'external' census row each, header
# edges=3 external=3 — was edges=6, no external=). CONTROLS, held on BOTH binaries — proof the fix took only
# what it should: drain's pool.move() -> Pool::move (a true member call); sampleTicks' vendorlib::chrono::
# duration_cast -> the SAME def K2 wrongly took, kept because the chain root is "vendorlib", not "std" (a fix
# must read the WHOLE chain, not refuse every chrono::); hasAnswer's std::ranges::contains -> a def INSIDE
# std::ranges (a polyfill), which the std-rooted rule keeps because ITS OWN chain is std-rooted too.
NEST="$TMP/nested"
mkdir -p "$NEST"
cat >"$NEST/decoys.h" <<'EOF'
#pragma once

struct Pool
{
    int move() { return size; }
    int size = 0;
};

namespace vendorlib
{
namespace chrono
{
inline long duration_cast( long ticks ) { return ticks / 1000; }
}
}
EOF
cat >"$NEST/compat.h" <<'EOF'
#pragma once

namespace std
{
[[noreturn]] void terminate() noexcept;
}
EOF
cat >"$NEST/polyfill.h" <<'EOF'
#pragma once

#include <vector>

namespace std
{
namespace ranges
{
inline bool contains( const std::vector<int>& r, int v )
{
    for( int x : r )
    {
        if( x == v )
        {
            return true;
        }
    }
    return false;
}
}
}
EOF
cat >"$NEST/callers.cpp" <<'EOF'
#include "compat.h"
#include "decoys.h"
#include "polyfill.h"

#include <algorithm>
#include <chrono>
#include <vector>

void shiftRange( std::vector<int>& from, std::vector<int>& to )
{
    std::ranges::move( from, to.begin() );
}

long toMillis( std::chrono::seconds s )
{
    return std::chrono::duration_cast<std::chrono::milliseconds>( s ).count();
}

void bail()
{
    std::terminate();
}

int drain( Pool& pool )
{
    return pool.move();
}

long sampleTicks( long ticks )
{
    return vendorlib::chrono::duration_cast( ticks );
}

bool hasAnswer( const std::vector<int>& v )
{
    return std::ranges::contains( v, 42 );
}
EOF
nrun(){ run "$NEST" "$@" --no-cache; }
# census "<mech>\t<targets>" per site for one caller, node ids stripped (a fix that changes extraction may renumber)
ncrows(){ awk -F'\t' -v c="$1" '$1=="C" && index($6, c"#") > 0 {print $2 "\t" $8}' "$TMP/n.tsv" | sed 's/#[0-9]*//g'; }
nedge(){   # $1 caller  $2 want count  $3 fixed-string callee row  $4 PASS prose  $5 FAIL prose
    local out; out="$( nrun "--callees=$1" )"
    if [ "$( cnt "$out" )" = "$2" ] && printf '%s' "$out" | grep -qF "$3"; then ok "$4"; else no "$5: $( el "$out" )"; fi
}

nrun --pin-census="$TMP/n.tsv" >"$TMP/nmap.xml"
NMAP="$( cat "$TMP/nmap.xml" )"
[ -s "$TMP/n.tsv" ] || no "§11: the nested-fixture census run wrote nothing — every census arm below would be vacuous"
nmissing=""
for want in 'n="move" sc="Pool"' 'n="duration_cast" sc="chrono"' 'n="terminate" sc="std"' \
            'n="contains" sc="ranges"' 'n="shiftRange"' 'n="toMillis"' 'n="bail"' 'n="drain"' 'n="sampleTicks"' 'n="hasAnswer"'; do
    printf '%s' "$NMAP" | grep -qF "$want" || nmissing="$nmissing $want"
done
[ -z "$nmissing" ] \
    && ok "§11 presence: the four targets and six callers are indexed, so every count below is about resolution, not a lost file" \
    || no "§11 presence: not indexed —$nmissing (the arms below would be vacuous)"

nexpect(){   # $1 sym  $2 want  $3 PASS prose  $4 FAIL prose
    local out; out="$( nrun "--callees=$1" )"
    local got; got="$( cnt "$out" )"
    if [ "${got:-REFUSED}" = "$2" ]; then
        ok "$3"
    else
        no "$4 — got '${got:-REFUSED}': $( el "$out" )"
    fi
}
nexpect shiftRange 0 \
    "#150 FIXED K1: --callees=shiftRange count=0 — std::ranges::move no longer binds the lone in-repo Pool::move (was count=1)" \
    "#150 K1 REGRESSED: std::ranges::move must not bind Pool::move"
[ "$( ncrows shiftRange )" = "$( printf 'external\t' )" ] \
    && ok "#150 FIXED K1 census: shiftRange's one site is now 'external' (was 'unique' -> decoys.h::Pool::move)" \
    || no "#150 K1 census REGRESSED: '$( ncrows shiftRange | tr '\t\n' '  ' )' — expected one 'external' row, no target"
nexpect toMillis 0 \
    "#150 FIXED K2: --callees=toMillis count=0 — std::chrono::duration_cast no longer binds vendorlib::chrono::duration_cast at the canonical tier (was count=1)" \
    "#150 K2 REGRESSED: std::chrono::duration_cast must not bind a user chrono:: at the canonical tier"
[ "$( ncrows toMillis )" = "$( printf 'external\t' )" ] \
    && ok "#150 FIXED K2 census: toMillis's one site is now 'external' (was 'qualified' -> decoys.h::chrono::duration_cast)" \
    || no "#150 K2 census REGRESSED: '$( ncrows toMillis | tr '\t\n' '  ' )' — expected one 'external' row, no target"
nexpect bail 0 \
    "#150 FIXED K3: --callees=bail count=0 — std::terminate no longer binds the DECLARATION-ONLY compat.h stand-in (was count=1)" \
    "#150 K3 REGRESSED: a std-rooted call must not bind a bodyless std declaration with no rival definition"
[ "$( ncrows bail )" = "$( printf 'external\t' )" ] \
    && ok "#150 FIXED K3 census: bail's one site is now 'external' (was 'unique' -> compat.h::std::terminate)" \
    || no "#150 K3 census REGRESSED: '$( ncrows bail | tr '\t\n' '  ' )' — expected one 'external' row, no target"
printf '%s' "$NMAP" | grep -qE 'files=4 symbols=11 edges=3 shown=11 est_tokens=[0-9]+ ambiguous=0 unresolved=0 external=3 order=' \
    && ok "#150 FIXED header: files=4 symbols=11 edges=3 ambiguous=0 unresolved=0 external=3 (was edges=6, no external=)" \
    || no "#150 header REGRESSED: $( printf '%s' "$NMAP" | grep -oE 'files=4 [^-]*' | head -1 ) — expected edges=3 external=3"

nedge drain 1 'n="Pool::move" p="decoys.h:5"' \
    "CONTROL: --callees=drain count=1 -> Pool::move (decoys.h:5): a true member call keeps its edge" \
    "CONTROL LOST: drain no longer binds Pool::move — the change took a true member call"
nedge sampleTicks 1 'n="duration_cast" p="decoys.h:13"' \
    "CONTROL: --callees=sampleTicks count=1 -> vendorlib::chrono::duration_cast: a true nested user-namespace call keeps its canonical edge" \
    "CONTROL LOST: sampleTicks lost vendorlib::chrono::duration_cast — a fix must read the whole chain, not refuse every chrono::"
nedge hasAnswer 1 'n="contains" p="polyfill.h:9"' \
    "CONTROL: --callees=hasAnswer count=1 -> std::ranges::contains (polyfill.h:9): a def INSIDE a nested std namespace survives" \
    "CONTROL LOST: hasAnswer lost the def inside std::ranges — a std-rooted rule must keep a def whose own chain is rooted in std"
# NON-VACUITY: --uses is name-based by contract, so every site above is still a use whatever the resolver decides.
[ "$( cnt "$( nrun --uses=move )" )" = 2 ] && [ "$( cnt "$( nrun --uses=duration_cast )" )" = 2 ] && [ "$( cnt "$( nrun --uses=terminate )" )" = 1 ] \
    && ok "§11 non-vacuity: --uses move=2 duration_cast=2 terminate=1 — every call site extracts (a refusal would be the resolver, not a lost reference)" \
    || no "§11 non-vacuity: --uses counts moved (move/duration_cast/terminate expected 2/2/1)"

nrun --pin-census="$TMP/n2.tsv" >"$TMP/nmap2.xml"
cmp -s "$TMP/nmap.xml" "$TMP/nmap2.xml" && cmp -s "$TMP/n.tsv" "$TMP/n2.tsv" \
    && ok "§11 deterministic: nested map + census byte-identical across two --no-cache runs" \
    || no "§11 non-deterministic: nested map or census differs between two runs"
run "$NEST" --cache="$TMP/n.bin" >"$TMP/ncold.xml"; run "$NEST" --cache="$TMP/n.bin" >"$TMP/nwarm.xml"
cmp -s "$TMP/ncold.xml" "$TMP/nwarm.xml" \
    && ok "§11 warm == cold on the nested fixture (a new per-reference field must survive the cache round-trip)" \
    || no "§11 warm != cold on the nested fixture"
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/nmap.xml" 2>/dev/null; then ok "§11 xml well-formed (nested fixture map)"; else no "§11 nested fixture map is malformed XML"; fi
else
    no "§11 cannot verify G4: xmllint is NOT INSTALLED — this check did not run (install libxml2)"
fi

# ── §12 (#150) — the WRITTEN SHAPES the fix's own design has to get right, beyond §11's three gaps ─────────────
# §11 pins the three broken RESOLUTIONS; §12 pins the SPELLINGS a std-rooted call/def can take. Two are
# RED-FIRST (measured once against base main 60b65f02: `globalMs` binds a decoy, count=1; `callInline` is
# AMBIGUOUS, count=2 — this gate does not re-run a base binary); two are CONTROLS proving the widening did not
# over-trigger. `sortedCopy` DUPLICATES the name on purpose (a decoy AND the real std def) so `callInline`
# actually discriminates between them — §11's `hasAnswer`/`contains` has no such decoy, so it could not.
SHAPES="$TMP/shapes"
mkdir -p "$SHAPES"
cat >"$SHAPES/shapes.h" <<'EOF'
#pragma once

struct Ring
{
    int reset() { return 0; }
};

inline long duration_cast( long ticks ) { return ticks; }   // NOT std — shares std::chrono::duration_cast's name
inline int  sortedCopy( int x ) { return x + 1; }            // NOT std — shares std::ranges::sortedCopy's name

namespace mylib
{
namespace std
{
inline int wake() { return 1; }   // a namespace literally named `std`, nested inside `mylib` — NOT std-rooted:
                                  // the language permits reopening the real ::std only at file scope
}
}

// the C++17 nested-namespace spelling — §11's polyfill.h covers the OLDER `namespace std { namespace
// ranges { … } }` two-node form for `contains`; this covers the single-node form for the SAME question.
namespace std::ranges
{
inline int sortedCopy( int x ) { return x; }
}
EOF
cat >"$SHAPES/shapecallers.cpp" <<'EOF'
#include "shapes.h"

#include <chrono>

long globalMs( std::chrono::seconds s )
{
    return ::std::chrono::duration_cast<std::chrono::milliseconds>( s ).count();   // leading `::` spelling
}

int callInline( int x )
{
    return std::__1::ranges::sortedCopy( x );   // an inline ABI namespace written ABOVE a nested one
}

int callMylibStd()
{
    return mylib::std::wake();   // NOT std-rooted — must resolve exactly as it did before #150
}

int useDirective( std::chrono::seconds s )
{
    using namespace std::chrono;
    return duration_cast<std::chrono::milliseconds>( s ).count();   // unqualified — a DIFFERENT round (aliases/
                                                                    // using-directives), stays on today's ladder
}
EOF
srun(){ run "$SHAPES" "$@" --no-cache; }
sexpect(){   # $1 sym  $2 want  $3 PASS prose  $4 FAIL prose
    local out; out="$( srun "--callees=$1" )"
    local got; got="$( cnt "$out" )"
    if [ "${got:-REFUSED}" = "$2" ]; then
        ok "$3"
    else
        no "$4 — got '${got:-REFUSED}': $( el "$out" )"
    fi
}
sexpect globalMs 0 \
    "#150 §12: --callees=globalMs count=0 — ::std::chrono::duration_cast (leading ::) refuses the non-std decoy (was count=1 -> the decoy)" \
    "#150 §12 REGRESSED: the leading-:: spelling must refuse the non-std duration_cast decoy"
sexpect callInline 1 \
    "#150 §12: --callees=callInline count=1 -> the REAL std::ranges::sortedCopy (std::__1::ranges::, inline ABI above a nested namespace) — the non-std decoy is refused (was count=2, ambiguous)" \
    "#150 §12 REGRESSED: std::__1::ranges::sortedCopy must resolve to the one std-rooted candidate, not stay ambiguous with the decoy"
srun --callees=callInline | grep -qF 'p="shapes.h:24"' \
    && ok "#150 §12: callInline's surviving target is the NESTED-namespace-syntax def (shapes.h:24), not the decoy (shapes.h:9)" \
    || no "#150 §12 REGRESSED: callInline's surviving target moved off the nested std::ranges def"
sexpect callMylibStd 1 \
    "CONTROL §12: --callees=callMylibStd count=1 -> mylib::std::wake — a namespace literally named std, nested inside another, is NOT std-rooted and resolves unchanged" \
    "CONTROL LOST §12: callMylibStd's resolution changed — a nested-but-not-real std namespace must not be treated as std-rooted"
sexpect useDirective 1 \
    "CONTROL §12: --callees=useDirective count=1 -> the duration_cast decoy — an unqualified call after 'using namespace std::chrono;' is a DIFFERENT round (see the guard's stated floor) and stays on today's ladder" \
    "CONTROL LOST §12: an unqualified call after a using-directive changed resolution — that is out of #150's stated scope"
srun --pin-census="$TMP/shapes.tsv" >"$TMP/shapes1.xml"
srun --pin-census="$TMP/shapes2.tsv" >"$TMP/shapes2.xml"
cmp -s "$TMP/shapes1.xml" "$TMP/shapes2.xml" && cmp -s "$TMP/shapes.tsv" "$TMP/shapes2.tsv" \
    && ok "§12 deterministic: shapes map + census byte-identical across two --no-cache runs" \
    || no "§12 non-deterministic: shapes map or census differs between two runs"
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/shapes1.xml" 2>/dev/null; then ok "§12 xml well-formed (shapes fixture map)"; else no "§12 shapes fixture map is malformed XML"; fi
else
    no "§12 cannot verify G4: xmllint is NOT INSTALLED — this check did not run (install libxml2)"
fi

# ── §13 (#150) — --callers / --impact / --dead-code over the SAME false-edge shape, not just --callees ────────
# The orchestrator brief's own requirement: a now-unbound in-repo function must not turn into a false
# dead-code row. `Cache::fetch` is INTERNAL LINKAGE on purpose (an anonymous namespace) — §11/§12's decoys are
# all external-linkage struct/namespace members, which --dead-code never considers a candidate at all, so a
# dead-code check against them would be vacuously "not a false row" rather than a real one. `useCache` is
# `fetch`'s one TRUE caller; `touchViaStd` is a std-rooted call that (pre-#150) bound it falsely too — RED-FIRST
# on base main 60b65f02: --callees=touchViaStd count=1, --callers=fetch count=2, --impact=fetch reaches=2.
DEADFIX="$TMP/deadfix"
mkdir -p "$DEADFIX"
cat >"$DEADFIX/deadfix.h" <<'EOF'
#pragma once

namespace
{
struct Cache
{
    int fetch( int k ) { return k; }   // internal linkage — a REAL --dead-code candidate, unlike Pool (§11) or
                                       // Ring/sortedCopy (§12), which all have external linkage
};
}
EOF
cat >"$DEADFIX/deadcallers.cpp" <<'EOF'
#include "deadfix.h"

int useCache( Cache& c, int k )
{
    return c.fetch( k );          // the ONE true caller — fetch must never read as dead, before or after #150
}

int touchViaStd( Cache& c, int k )
{
    return std::ranges::fetch( c, k );   // #150: pre-fix, this std-rooted call falsely bound Cache::fetch too
}
EOF
drun(){ run "$DEADFIX" "$@" --no-cache; }
[ "$( cnt "$( drun --callees=touchViaStd )" )" = 0 ] \
    && ok "#150 §13: --callees=touchViaStd count=0 — a std-rooted call no longer binds the internal-linkage Cache::fetch (was count=1)" \
    || no "#150 §13 REGRESSED: touchViaStd must not bind Cache::fetch — got '$( cnt "$( drun --callees=touchViaStd )" )'"
[ "$( cnt "$( drun --callers=fetch )" )" = 1 ] && drun --callers=fetch | grep -qF 'n="useCache"' \
    && ok "#150 §13: --callers=fetch count=1 -> useCache ONLY — the false std-rooted caller is gone, the true one remains (was count=2)" \
    || no "#150 §13 REGRESSED: --callers=fetch expected count=1 -> useCache, got: $( drun --callers=fetch | grep -oE '<s[^/]*/>' | tr '\n' ' ' )"
[ "$( drun --impact=fetch | grep -oE 'reaches="[0-9]+"' )" = 'reaches="1"' ] \
    && ok "#150 §13: --impact=fetch reaches=1 — the false blast radius through touchViaStd is gone (was reaches=2)" \
    || no "#150 §13 REGRESSED: --impact=fetch expected reaches=1, got $( drun --impact=fetch | grep -oE 'reaches="[0-9]+"' )"
[ "$( cnt "$( drun --dead-code )" )" = 0 ] \
    && ok "#150 §13 (the orchestrator's own dead-code requirement): --dead-code count=0 — Cache::fetch's true caller (useCache) keeps it live whether or not the false std edge exists" \
    || no "#150 §13 REGRESSED (FALSE DEAD-CODE ROW): --dead-code count moved off 0 for a function with a real caller — got '$( cnt "$( drun --dead-code )" )'"
dcold="$( run "$DEADFIX" --dead-code --cache="$TMP/dead.bin" )"; dwarm="$( run "$DEADFIX" --dead-code --cache="$TMP/dead.bin" )"
[ "$dcold" = "$dwarm" ] \
    && ok "§13 warm == cold on the dead-code fixture (a new per-def field must survive the cache round-trip)" \
    || no "§13 warm != cold on the dead-code fixture"
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$dcold" | xmllint --noout - 2>/dev/null; then
        ok "§13 xml well-formed (dead-code fixture map)"
    else
        no "§13 dead-code fixture map is malformed XML"
    fi
else
    no "§13 cannot verify G4: xmllint is NOT INSTALLED — this check did not run (install libxml2)"
fi

# ── §14 (F1/F2, adversarial review of #150, 2026-09-23) — OUT-OF-LINE std DEFINITIONS, 3+ SEGMENTS ─────────
# The review that found this: cppDefinitionRootsStd (ingest_names.h) trusted `ts_node_parent(nameNode)` to
# always be the OUTERMOST qualified_identifier of a definition's written chain, the way it genuinely is for a
# CALL. It is not, for a 3+-segment OUT-OF-LINE DEFINITION: ingest.cpp re-seats a definition's @name to the
# INNERMOST link (queries/cpp/tags.scm's own comment: "ingest.cpp descends it to the innermost name:"), so
# `std::detail::f`'s nameNode there is `f`, whose immediate parent is only the inner `detail::f` node — its
# root reads as "detail", not "std", and a real std-rooted definition loses every true caller (RED on lane
# head 70dfdf09, BEFORE this fix: `test/stdqualcheck.sh` itself passed ALL PASS at that commit, because §11's
# fixture has no 3+-segment out-of-line std definition — these three shapes are what a probe build had to
# add to find it). A second, narrower bug shared the same root cause: a PARTIALLY-qualified out-of-line def
# written inside `namespace std { … }` (`namespace std { int detail::innerHelper(int){} }`) never reached the
# enclosing-namespace fallback at all, qualified or not. §14 also covers F2: the K3 "must have a body" filter
# (graph.h) applied to every candidate kind, including a std-rooted VARIABLE (a niebloid), which has no
# separate body by construction and was wrongly refused as if it were a bodyless declaration.
F1FIX="$TMP/f1fix"
mkdir -p "$F1FIX"
cat >"$F1FIX/f1shapes.h" <<'EOF'
#pragma once

struct Foo { int v; };

namespace std
{
template<class T> struct hash;
template<> struct hash<Foo>
{
    unsigned long operator()( const Foo& f ) const { return f.v; }
    static unsigned long mix( unsigned long x );          // out-of-line def below: 3 segments, a template-id middle link
};
namespace detail { int polyfillHelper( int x ); }          // out-of-line def below: 3 plain segments
namespace ranges
{
struct sort_fn { int operator()( int x ) const { return x; } };
inline constexpr sort_fn niebloid{};                        // F2: a std-rooted VARIABLE, no body by construction
}
}
EOF
cat >"$F1FIX/f1shapes.cpp" <<'EOF'
#include "f1shapes.h"

unsigned long std::hash<Foo>::mix( unsigned long x ) { return x ^ 0x9e3779b9UL; }   // 3-seg, template-id middle
int std::detail::polyfillHelper( int x ) { return x + 1; }                          // 3-seg, plain

namespace std
{
namespace detail { int innerHelper( int x ); }
int detail::innerHelper( int x ) { return x; }   // PARTIAL qualifier ("detail::innerHelper") inside namespace std {}
}

unsigned long callMix( unsigned long x ) { return std::hash<Foo>::mix( x ); }
int callPolyfill( int x ) { return std::detail::polyfillHelper( x ); }
int callInner( int x ) { return std::detail::innerHelper( x ); }
int callNiebloid( int x ) { return std::ranges::niebloid( x ); }
EOF
frun(){ run "$F1FIX" "$@" --no-cache; }
fexpect(){   # $1 sym  $2 want  $3 PASS prose  $4 FAIL prose
    local out; out="$( frun "--callees=$1" )"
    local got; got="$( cnt "$out" )"
    if [ "${got:-REFUSED}" = "$2" ]; then
        ok "$3"
    else
        no "$4 — got '${got:-REFUSED}': $( el "$out" )"
    fi
}
fexpect callMix 1 \
    "#150 §14 F1: --callees=callMix count=1 -> std::hash<Foo>::mix, a 3-segment out-of-line def with a template-id middle link (was count=0 on 70dfdf09: the innermost-link bug read the root as 'hash<Foo>')" \
    "#150 §14 F1 REGRESSED: std::hash<Foo>::mix must resolve — an out-of-line std definition with a template-id in its chain lost its true edge"
fexpect callPolyfill 1 \
    "#150 §14 F1: --callees=callPolyfill count=1 -> std::detail::polyfillHelper, a 3-segment out-of-line def (was count=0 on 70dfdf09)" \
    "#150 §14 F1 REGRESSED: std::detail::polyfillHelper must resolve — a 3+-segment out-of-line std definition lost its true edge"
fexpect callInner 1 \
    "#150 §14 F1: --callees=callInner count=1 -> detail::innerHelper, a PARTIALLY-qualified out-of-line def inside namespace std {} (was count=0 on 70dfdf09: the dispatcher never fell back to the enclosing-namespace walk)" \
    "#150 §14 F1 REGRESSED: a partially-qualified out-of-line def inside namespace std {} must still resolve via the enclosing-namespace walk"
fexpect callNiebloid 1 \
    "#150 §14 F2: --callees=callNiebloid count=1 -> the std::ranges niebloid VARIABLE (was count=0 on 70dfdf09: the body test applied to every kind, not just functions/methods)" \
    "#150 §14 F2 REGRESSED: a std-rooted variable (a niebloid) must not be refused for having no function body"
[ "$( cnt "$( frun --callers=polyfillHelper )" )" = 1 ] && frun --callers=polyfillHelper | grep -qF 'n="callPolyfill"' \
    && ok "#150 §14 F1: --callers=polyfillHelper count=1 -> callPolyfill (the verb the review named alongside --callees/--impact)" \
    || no "#150 §14 F1 REGRESSED: --callers=polyfillHelper must show callPolyfill as a true caller"
[ "$( frun --impact=polyfillHelper | grep -oE 'reaches="[0-9]+"' )" = 'reaches="1"' ] \
    && ok "#150 §14 F1: --impact=polyfillHelper reaches=1 -> callPolyfill (the blast radius is not silently empty)" \
    || no "#150 §14 F1 REGRESSED: --impact=polyfillHelper expected reaches=1, got $( frun --impact=polyfillHelper | grep -oE 'reaches="[0-9]+"' )"
frun --pin-census="$TMP/f1a.tsv" >"$TMP/f1a.xml"
frun --pin-census="$TMP/f1b.tsv" >"$TMP/f1b.xml"
cmp -s "$TMP/f1a.xml" "$TMP/f1b.xml" && cmp -s "$TMP/f1a.tsv" "$TMP/f1b.tsv" \
    && ok "§14 deterministic: f1shapes map + census byte-identical across two --no-cache runs" \
    || no "§14 non-deterministic: f1shapes map or census differs between two runs"
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/f1a.xml" 2>/dev/null; then ok "§14 xml well-formed (f1shapes fixture map)"; else no "§14 f1shapes fixture map is malformed XML"; fi
else
    no "§14 cannot verify G4: xmllint is NOT INSTALLED — this check did not run (install libxml2)"
fi

# ── §15 (CodeRabbit on #331, 2026-09-24) — a WRITTEN `std::` def qualifier inside a NAMED namespace ─────────────
# A qualified definition names an entity of a namespace that ENCLOSES it ([namespace.memdef]), so `int
# std::ranges::vshift(int)` written inside `namespace vendor { … }` defines vendor::std::ranges::vshift. The
# real ::std can only be re-opened out of line at file scope. cppDefinitionRootsStd used to mark that def
# std-rooted from its written chain alone, and keepStdQualifiedCandidates then kept it as the target of a call
# to the real ::std::ranges::vshift, which has no in-repo definition: RED on 9936ba4e, count=1 for both calls
# below (a false edge). §14's file-scope out-of-line std defs above are the control: they must still resolve.
# Known limit, the SAFE direction #150 already chose: a call written `std::ranges::vshift` INSIDE namespace
# vendor (which C++ would bind to vendor::std) is not bound either, since the call side cannot tell vendor::std
# from ::std without cross-file lookup; an unbound call is disclosed, a false edge is not.
VSTD="$TMP/vstd"
mkdir -p "$VSTD"
cat >"$VSTD/vendor.h" <<'EOF'
#pragma once
namespace vendor
{
namespace std { namespace ranges { int vshift( int x ); } }
}
EOF
cat >"$VSTD/vendor.cpp" <<'EOF'
#include "vendor.h"
namespace vendor
{
int std::ranges::vshift( int x ) { return x << 1; }   // defines vendor::std::ranges::vshift, NOT ::std's
}
int callGlobal( int x ) { return ::std::ranges::vshift( x ); }   // names the REAL ::std: no in-repo def
int callWritten( int x ) { return std::ranges::vshift( x ); }    // at file scope, std is ::std as well
EOF
for vsym in callGlobal callWritten; do
    vout="$( run "$VSTD" "--callees=$vsym" --no-cache )"
    vgot="$( cnt "$vout" )"
    if [ "${vgot:-REFUSED}" = 0 ]; then
        ok "#331 §15: --callees=$vsym count=0 — a ::std call does not bind vendor::std::ranges::vshift, a same-spelled def inside namespace vendor (was count=1 on 9936ba4e)"
    else
        no "#331 §15 REGRESSED: --callees=$vsym must not bind the def written inside namespace vendor — got '${vgot:-REFUSED}': $( el "$vout" )"
    fi
done

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
