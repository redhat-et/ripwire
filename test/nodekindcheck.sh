#!/usr/bin/env bash
# nodekindcheck.sh — gate for rw::kindIs (src/infra/nodekind.h), the inline node-kind compare that
# replaced 569 per-AST-node `std::strcmp` calls in the ingest walk (docs/OPTREMARKS.md §8b/F3).
#
# The claim being gated is narrow and total: `kindIs( t, "lit" )` is `std::strcmp( t, "lit" ) == 0`,
# for every t, with no read past t's NUL. A hand-rolled byte compare is the kind of code that is
# right on the strings you thought of and wrong on the ones you did not, so this gate does not test a
# sample — it enumerates.
#
#   A. DIFFERENTIAL, exhaustive. Every candidate string in a matrix built from the node-kind literals
#      the ingest walk sections ACTUALLY use — harvested from the tree at gate time, not from a frozen
#      list (§8's lesson: a list can be perfectly self-consistent about a tree that has moved) — is
#      compared against every literal, both ways, and `kindIs` must agree with `std::strcmp( … ) == 0`
#      on every pair. The matrix adds the cases a byte loop gets wrong: every proper prefix of every
#      literal, every literal with one byte appended, the empty string, single bytes, last-byte
#      substitutions, and high bytes 0x80..0xFF (which are `char`-signed on this platform, so a
#      compare written with the wrong type gets them backwards).
#   B. GUARD PAGE. The one hazard a byte loop invites is reading past the NUL — which `std::memcmp(
#      t, lit, N )` would do, and which no assertion on the RESULT can observe, because the extra byte
#      usually happens to be readable. So arm B makes it not readable: the candidate is copied so its
#      NUL is the last byte before an mprotect(PROT_NONE) page, and kindIs is called against literals
#      that are strict extensions of it. A read past the NUL is a SIGSEGV, not a wrong answer.
#   C. MUTATION. Arms A and B must be able to go red. A scratch copy of nodekind.h with the loop bound
#      weakened to `N - 1` (the classic prefix bug — "if" would equal "if_statement") must make arm A
#      fail; a second copy that reads one byte past must make arm B fail. An arm that has never been
#      observed failing is decoration.
#   D. POPULATION. The five ingest walk sections must still BE on kindIs: zero
#      `std::strcmp( x, "literal" )` sites left in them, and a non-trivial number of kindIs sites. This
#      is the coverage assertion — arms A-C prove the primitive is correct, and only this one keeps the
#      measured win from being quietly reverted a site at a time. A future site that genuinely needs
#      libc strcmp in one of these files should change this arm on purpose, not slip past it.
#      (D-mut) performs that revert on a scratch copy and requires arm D to report every section: a
#      mechanical 570-site conversion is exactly where an arm can be green in BOTH directions, and an
#      arm that cannot see the change being undone is not guarding it.
#
# Usage:  bash test/nodekindcheck.sh   [ CXX=clang++ ]
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"
. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

HDR="$ROOT/src/infra/nodekind.h"
# The per-AST-node dispatch population. These five are sections of ONE translation unit (src/ingest.cpp)
# and they are the files the profile named: cc_walk/isDecisionType, bindsVisitNode, the side-capture
# visitors, captureIncludes, and the name/qualifier walk.
WALK_FILES="src/ingest_metrics.h src/ingest_binds.h src/ingest_sidecap.h src/ingest_relations.h src/ingest_names.h"

[ -f "$HDR" ] || { echo "missing $HDR — nothing to check"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "nodekindcheck: CXX=$CXX  header=src/infra/nodekind.h"

# ── harvest the literal set FROM THE TREE ────────────────────────────────────────────────────────────
# Second argument of every kindIs( x, "lit" ) call in the walk sections. Escapes are refused rather than
# mishandled: none of the grammar strings contain one today, and a backslash would need the emitter
# below to think about C escaping, which is exactly the kind of silent mis-encoding this gate exists to
# rule out.
LITS="$TMP/lits.txt"
( cd "$ROOT" && grep -ohE 'kindIs\( [^,]+, "[^"]*" \)' $WALK_FILES 2>/dev/null ) \
    | sed -E 's/.*, "(.*)" \)$/\1/' | sort -u > "$LITS"
NLITS="$( wc -l < "$LITS" | tr -d ' ' )"
if [ "$NLITS" -lt 100 ]; then
    no "harvested only $NLITS node-kind literals from the walk sections — the probe found nothing, so every arm below would be vacuous"
    echo; echo "SOME CHECKS FAILED"; exit 1
fi
if grep -q '\\' "$LITS"; then
    no "a harvested literal contains a backslash escape — this gate's emitter does not handle C escaping"
fi
ok "harvested $NLITS distinct node-kind literals from the tree ($( echo $WALK_FILES | wc -w | tr -d ' ' ) walk sections)"

# ── the harness generator: shared by the real header and by the mutation copies ──────────────────────
# $1 = include dir holding the nodekind.h under test, $2 = output binary, $3 = log
gen_and_build(){
    local incdir="$1" out="$2" log="$3"
    python3 - "$LITS" > "$TMP/harness.cpp" <<'PYEOF'
import sys
lits = [l.rstrip("\n") for l in open(sys.argv[1]) if l.rstrip("\n") != ""]
def c(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
print('#include "nodekind.h"')
print("""
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <sys/mman.h>
#include <unistd.h>

static int failures = 0;

// arm A: kindIs must agree with strcmp on EVERY (candidate, literal) pair.
template< std::size_t N >
static void pair( const std::string& t, const char ( &lit )[N] )
{
    const bool want = std::strcmp( t.c_str(), lit ) == 0;
    const bool got  = rw::kindIs( t.c_str(), lit );
    if( want != got )
    {
        if( ++failures <= 10 )
        {
            std::printf( "MISMATCH t=\\"%s\\" lit=\\"%s\\" strcmp==0 -> %d  kindIs -> %d\\n", t.c_str(), lit, int( want ), int( got ) );
        }
    }
}

// arm B: the candidate's NUL is the last readable byte before a PROT_NONE page. Any read past it is a
// SIGSEGV, so the process either completes (no over-read) or dies (over-read) — the result is not the
// evidence here, surviving is.
static const char* atGuardEdge( const std::string& s )
{
    const long pg = ::sysconf( _SC_PAGESIZE );
    char* base = static_cast< char* >( ::mmap( nullptr, std::size_t( pg ) * 2, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0 ) );
    if( base == MAP_FAILED ) { std::printf( "GUARD_MMAP_FAILED\\n" ); std::exit( 2 ); }
    if( ::mprotect( base + pg, std::size_t( pg ), PROT_NONE ) != 0 ) { std::printf( "GUARD_MPROTECT_FAILED\\n" ); std::exit( 2 ); }
    char* p = base + pg - ( s.size() + 1 );     // the NUL lands on the last readable byte
    std::memcpy( p, s.c_str(), s.size() + 1 );
    return p;
}
""")
print("int main()\n{")
print("    std::vector<std::string> cands;")
print("    const char* const kLits[] = {")
for l in lits:
    print("        %s," % c(l))
print("    };")
print("""
    // the literals themselves, plus every proper prefix, plus every one-byte extension
    for( const char* l : kLits )
    {
        const std::string s( l );
        cands.push_back( s );
        for( std::size_t k = 0; k < s.size(); ++k ) { cands.push_back( s.substr( 0, k ) ); }
        cands.push_back( s + "x" );
        cands.push_back( s + "_" );
        if( !s.empty() )
        {
            std::string alt = s; alt.back() = char( alt.back() ^ 0x01 );   // last-byte substitution
            cands.push_back( alt );
            std::string hi = s; hi.back() = char( 0xE9 );                  // a high byte where a match is expected
            cands.push_back( hi );
        }
    }
    // single bytes across the whole 1..255 range: `char` is signed here, so 0x80..0xFF are the values a
    // compare written against the wrong type gets backwards.
    for( int b = 1; b < 256; ++b ) { cands.push_back( std::string( 1, char( b ) ) ); }
    cands.push_back( std::string() );
""")
print("    for( const std::string& t : cands )\n    {")
for l in lits:
    print("        pair( t, %s );" % c(l))
print("    }")
print("""
    std::printf( "ARM_A pairs=%zu\\n", cands.size() * ( sizeof( kLits ) / sizeof( kLits[0] ) ) );

    // ── arm B: over-read detection ───────────────────────────────────────────────────────────────
    // Candidates chosen so the compare must run to (and past) the candidate's NUL: the literal is a
    // strict EXTENSION of the candidate, so every byte the candidate has matches and the decision is
    // made exactly at the NUL.
    for( const char* l : kLits )
    {
        const std::string full( l );
        for( std::size_t k = 0; k <= full.size(); ++k )
        {
            const char* edge = atGuardEdge( full.substr( 0, k ) );
            volatile bool got = rw::kindIs( edge, "" );
            (void) got;
        }
    }
""")
# arm B, the shape that matters: candidate is a proper prefix of the literal, so the loop reaches the NUL
print("    for( const std::string& base : cands )\n    {")
print("        if( base.size() > 64 ) { continue; }")
print("        const char* edge = atGuardEdge( base );")
for l in lits:
    print("        { volatile bool g = rw::kindIs( edge, %s ); (void) g; }" % c(l))
print("    }")
print("""
    std::printf( "ARM_B survived\\n" );
    if( failures != 0 ) { std::printf( "FAILURES %d\\n", failures ); return 1; }
    std::printf( "UNIT_OK\\n" );
    return 0;
}
""")
PYEOF
    "$CXX" "$CXXSTD" -O2 -Wall -Wextra -I "$incdir" "$TMP/harness.cpp" -o "$out" 2>"$log"
}

# ── A + B against the real header ────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/real" && cp "$HDR" "$TMP/real/nodekind.h"
if ! gen_and_build "$TMP/real" "$TMP/real.bin" "$TMP/real.cc.log"; then
    no "harness does not compile against the real nodekind.h"
    sed 's/^/    /' "$TMP/real.cc.log" | head -20
else
    if "$TMP/real.bin" > "$TMP/real.out" 2>&1; then
        grep -q UNIT_OK "$TMP/real.out" && ok "A: kindIs == (strcmp == 0) on every pair — $( grep -o 'pairs=[0-9]*' "$TMP/real.out" )" \
                                        || no "A: harness exited 0 without UNIT_OK"
        grep -q 'ARM_B survived' "$TMP/real.out" && ok "B: no read past the candidate's NUL (mprotect(PROT_NONE) guard page)" \
                                                 || no "B: guard-page arm did not report"
    else
        no "A/B: harness failed — $( head -12 "$TMP/real.out" | tr '\n' ' ' )"
    fi
fi

# ── C. the mutation arms — each must FAIL the arm it targets ─────────────────────────────────────────
# C1: drop the NUL from the comparison (`i < N` -> `i < N - 1`). kindIs becomes a PREFIX test, so
#     "if" now equals "if_statement" and arm A must catch it.
mkdir -p "$TMP/mut1"
sed 's/for( std::size_t i = 0; i < N; ++i )/for( std::size_t i = 0; i + 1 < N; ++i )/' "$HDR" > "$TMP/mut1/nodekind.h"
if ! grep -q 'i + 1 < N' "$TMP/mut1/nodekind.h"; then
    no "C1: could not apply the prefix mutation — the loop bound moved, so this arm proves nothing"
elif ! gen_and_build "$TMP/mut1" "$TMP/mut1.bin" "$TMP/mut1.cc.log"; then
    no "C1: mutated header does not compile — the mutation must produce a WRONG build, not a broken one"
elif "$TMP/mut1.bin" > "$TMP/mut1.out" 2>&1; then
    no "C1: arm A stayed GREEN against a kindIs that is a prefix test — arm A cannot fail"
else
    ok "C1: arm A goes red when the NUL is dropped from the compare ($( sed -n 's/^FAILURES //p' "$TMP/mut1.out" ) disagreements with strcmp)"
fi

# C2: read one byte past the literal (`i < N` -> `i <= N`). The answer is usually unchanged — the extra
#     byte is normally readable and normally differs on strings that already differ — so ONLY the guard
#     page can see it. This is the arm that proves arm B is not decoration.
mkdir -p "$TMP/mut2"
sed 's/for( std::size_t i = 0; i < N; ++i )/for( std::size_t i = 0; i <= N; ++i )/' "$HDR" > "$TMP/mut2/nodekind.h"
if ! grep -q 'i <= N' "$TMP/mut2/nodekind.h"; then
    no "C2: could not apply the over-read mutation — the loop bound moved, so this arm proves nothing"
elif ! gen_and_build "$TMP/mut2" "$TMP/mut2.bin" "$TMP/mut2.cc.log"; then
    no "C2: mutated header does not compile"
else
    # The over-read is a FAULT, not a wrong answer, so the shell that reaps it prints its own
    # "Bus error" line about a subprocess this gate killed ON PURPOSE. That line goes to the reaping
    # shell's stderr, not the child's, so it has to be reaped by a shell we can silence — hence the
    # nested `bash -c` rather than a redirect on the binary.
    bash -c '"$1" > "$2" 2>&1' _ "$TMP/mut2.bin" "$TMP/mut2.out" 2>/dev/null
    rc=$?
    if [ "$rc" -eq 0 ]; then
        no "C2: the guard-page arm survived a kindIs that reads one byte past the NUL — arm B cannot fail"
    else
        ok "C2: arm B goes red (exit $rc — a fault on the guard page) when kindIs reads one byte past the NUL"
    fi
fi

# ── D. population: the walk sections are on kindIs, and have no literal strcmp left ──────────────────
# This is the COVERAGE arm. A-C prove the primitive is correct; only this one stops the measured win
# from being reverted a site at a time, so it has to be able to see a revert — which is why the
# mutation control below performs one. Sites that compare against a `const char*` VARIABLE rather than
# a literal (ev_childText's caller-supplied list, isTypeDeclarationSite's parent table) legitimately
# keep std::strcmp: kindIs takes `const char (&)[N]` and does not bind to them at all.
#
# The check is a FUNCTION OVER A DIRECTORY, not a straight-line grep of $ROOT, for one reason: the
# mutation control has to run it against a reverted copy of the tree, and a gate that can only look at
# its own checkout cannot be shown to fail. Never mutate $ROOT itself to prove this — a gate that edits
# tracked source leaves the repo dirty if it dies, and an extra file in the tree perturbs anything that
# crawls it.
checkPopulation(){                   # $1 = tree root to inspect; prints one line per violation, empty = clean
    local root="$1" f n k
    for f in $WALK_FILES; do
        [ -f "$root/$f" ] || { printf '%s: MISSING\n' "$f"; continue; }
        n="$( grep -cE 'std::strcmp\([^"]*"[^"]*"[[:space:]]*\)[[:space:]]*[!=]=[[:space:]]*0' "$root/$f" 2>/dev/null || true )"
        k="$( grep -c 'kindIs(' "$root/$f" 2>/dev/null || true )"
        [ "${n:-0}" -ne 0 ] && printf '%s: %s literal std::strcmp site(s) on a per-AST-node path\n' "$f" "$n"
        [ "${k:-0}" -lt 10 ] && printf '%s: only %s kindIs site(s) — not on the inline compare\n' "$f" "${k:-0}"
    done
    return 0
}

violations="$( checkPopulation "$ROOT" )"
if [ -n "$violations" ]; then
    printf '%s\n' "$violations" | while IFS= read -r v; do no "D: $v"; done
    fail=1
else
    ok "D: all $( echo $WALK_FILES | wc -w | tr -d ' ' ) walk sections are on kindIs, with no literal std::strcmp left"
fi

# ── D-mut. the revert control: arm D must SEE a revert of the whole change ───────────────────────────
# The failure this rules out is the one a mechanical 570-site conversion invites — an arm that is green
# in both directions, and therefore green forever. A scratch copy of the five sections is transformed
# back to `std::strcmp( x, "lit" ) == 0` / `!= 0` (the exact inverse of the rewrite), and arm D's own
# function must report every one of them. Anything less than all five means the arm has a blind file.
mkdir -p "$TMP/reverted/src"
revertedFiles=0
for f in $WALK_FILES; do
    if python3 - "$ROOT/$f" "$TMP/reverted/$f" <<'PYREVERT'
import re, sys
src = open( sys.argv[1] ).read()
# !kindIs( A, "L" ) -> std::strcmp( A, "L" ) != 0   ·   kindIs( A, "L" ) -> std::strcmp( A, "L" ) == 0
out, n = re.subn( r'(!?)kindIs\( (.*?), ("(?:[^"\\]|\\.)*") \)',
                  lambda m: 'std::strcmp( %s, %s ) %s 0' % ( m.group(2), m.group(3), '!=' if m.group(1) else '==' ),
                  src )
open( sys.argv[2], 'w' ).write( out )
sys.exit( 0 if n > 0 else 1 )
PYREVERT
    then revertedFiles=$(( revertedFiles + 1 )); fi
done
if [ "$revertedFiles" -ne "$( echo $WALK_FILES | wc -w | tr -d ' ' )" ]; then
    no "D-mut: could only build a reverted copy of $revertedFiles walk section(s) — the control cannot prove arm D fires"
else
    mutViolations="$( checkPopulation "$TMP/reverted" )"
    mutFiles="$( printf '%s\n' "$mutViolations" | grep -c 'literal std::strcmp' || true )"
    if [ "${mutFiles:-0}" -eq "$( echo $WALK_FILES | wc -w | tr -d ' ' )" ]; then
        ok "D-mut: arm D goes red on a full revert of the change — all $mutFiles section(s) reported (it is not green in both directions)"
    else
        no "D-mut: a full revert left arm D green on $(( $( echo $WALK_FILES | wc -w | tr -d ' ' ) - ${mutFiles:-0} )) of $( echo $WALK_FILES | wc -w | tr -d ' ' ) section(s) — the arm has a blind file"
    fi
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
