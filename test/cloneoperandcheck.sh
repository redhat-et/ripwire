#!/usr/bin/env bash
# cloneoperandcheck.sh — QD-IDIOM-ELEMTYPE: the operand path of the clone demotion (src/cloneidiom.h).
#
# WHY THIS GATE EXISTS. A port of a 700-line shell matcher (QD-VA-FORMS, 2026-11-19) needed 13 reasoned acks for
# short clone rows that matched unrelated code by SHAPE: an svLess binary search over a runtime vector<string>
# beside one over a constexpr span of string_view tables, a quote strip beside a whitespace squeeze, two parsers'
# bounded peeks. Each pair operates on DIFFERENT DATA, and that is what the operand path reads: a group under the
# 80-token idiom ceiling, in distinct contexts, whose every pair has no literal in common (0 and 1 left out) or the
# same number of concrete parameters with a different type at some position, is reported minor with why= naming it.
#
# WHAT THIS GATE PINS — through --quality-delta (one member committed, its twin in the working tree, so the row is
# preexisting-worse and would gate):
#   (P1) types: an svLess search over vector<string> beside the same body over span<const string_view> is minor,
#        why="different parameter types"
#   (P2) literals: a quote strip beside a whitespace squeeze (one copy-filter loop) is minor, why="different literals"
#   (P3) literals, one side empty: a bounded peek returning '\0' beside one returning a member is minor
#   (N1) a copy that kept a literal (a tag-parameterised hex writer beside its "tangle " instance) GATES
#   (N2) a copy over the same literals (two reverse find-by-key loops, 0 and 1 only) GATES
#   (N3) the P2 pair in one file and one namespace GATES
#   (N4) a GENERIC member (a template over the range) beside the concrete P1 member GATES
#   (N5) the P2 shape grown past the 80-token ceiling, literal sets still disjoint, GATES
#   (N6) a pair sharing one literal (Python's \w beside an identifier class with '$') GATES
#   (C)  PREMISE COUNT — every arm above found its row; an arm with no row FAILS (a missing row would pass a "does
#        not gate" arm vacuously, and a negative that never forms its group proves nothing)
#   (L)  the document with a why= clone row defines it (full legend); one without carries no such sentence
#   (V)  the --clones verb does not read the verdict: the P2 group prints there without demoted="1"
#   (J)  determinism — two runs byte-identical
# Red-before: on a binary without the operand path, P1-P3 gate (FAIL). Guard-off (the disjointness, the concrete-type,
# the context and the ceiling tests removed): N1-N6 FAIL. See docs/EVALS.md "Clone operand path".
#
# Usage:  bash test/cloneoperandcheck.sh [BIN]

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" TMPDIR="$TMP"; mkdir -p "$HOME"
fail=0; seen=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

# The fixtures are WRITTEN HERE, never committed: they copy real bodies on purpose, and a committed copy would sit in
# this repo as a new clone of src/ code that its own quality-delta reports beside every change.
F="$TMP/fix"
mkfix(){ mkdir -p "$F/$1"; cat >"$F/$1/$2"; }

mkfix tables tables.h <<'EOF'
#pragma once
#include <algorithm>
#include <span>
#include <string_view>
namespace tables
{
inline bool svLess( std::string_view a, std::string_view b ) noexcept { return a < b; }
// the lookup of a strictly sorted constexpr table, taken as a span so a new table reuses it
inline bool inSortedTable( std::span<const std::string_view> table, std::string_view name ) noexcept
{
    return std::binary_search( table.begin(), table.end(), name, tables::svLess );
}
}
EOF
mkfix names names.h <<'EOF'
#pragma once
#include <algorithm>
#include <string>
#include <string_view>
#include <vector>
#include "tables.h"
namespace shellnames
{
// a runtime vector of names, sorted once
inline bool hasName( const std::vector<std::string>& sorted, std::string_view n )
{
    return std::binary_search( sorted.begin(), sorted.end(), n, tables::svLess );
}
}
EOF
mkfix generic names.h <<'EOF'
#pragma once
#include <algorithm>
#include <string_view>
#include "tables.h"
namespace shellnames
{
template <class Range>
inline bool hasName( const Range& sorted, std::string_view n )
{
    return std::binary_search( sorted.begin(), sorted.end(), n, tables::svLess );
}
}
EOF
mkfix squeeze layout.h <<'EOF'
#pragma once
#include <cctype>
#include <string>
#include <string_view>
namespace layout
{
inline std::string squeeze( std::string_view s )
{
    std::string out;
    out.reserve( s.size() );
    for( char c : s )
    {
        if( std::isspace( (unsigned char)c ) == 0 )
        {
            out.push_back( c );
        }
    }
    return out;
}
}
EOF
mkfix unq words.h <<'EOF'
#pragma once
#include <string>
#include <string_view>
namespace words
{
// every quote character removed
inline std::string unq( std::string_view s )
{
    std::string out;
    out.reserve( s.size() );
    for( char c : s )
    {
        if( c != '"' && c != '\'' )
        {
            out.push_back( c );
        }
    }
    return out;
}
}
EOF
mkfix samescope_base text.h <<'EOF'
#pragma once
#include <cctype>
#include <string>
#include <string_view>
namespace text
{
inline std::string squeeze( std::string_view s )
{
    std::string out;
    out.reserve( s.size() );
    for( char c : s )
    {
        if( std::isspace( (unsigned char)c ) == 0 )
        {
            out.push_back( c );
        }
    }
    return out;
}
}
EOF
mkfix samescope_head text.h <<'EOF'
#pragma once
#include <cctype>
#include <string>
#include <string_view>
namespace text
{
inline std::string squeeze( std::string_view s )
{
    std::string out;
    out.reserve( s.size() );
    for( char c : s )
    {
        if( std::isspace( (unsigned char)c ) == 0 )
        {
            out.push_back( c );
        }
    }
    return out;
}
inline std::string unq( std::string_view s )
{
    std::string out;
    out.reserve( s.size() );
    for( char c : s )
    {
        if( c != '"' && c != '\'' )
        {
            out.push_back( c );
        }
    }
    return out;
}
}
EOF
mkfix bigsqueeze layout.h <<'EOF'
#pragma once
#include <cstddef>
#include <string>
#include <string_view>
namespace layout
{
inline std::string squeezeMarked( std::string_view s, std::size_t& dropped )
{
    std::string out;
    out.reserve( s.size() + 2 );
    for( char c : s )
    {
        if( c != ' ' && c != '\t' )
        {
            out.push_back( c );
        }
        else
        {
            ++dropped;
        }
    }
    if( dropped > 4 )
    {
        out.insert( out.begin(), '#' );
        out.push_back( '#' );
    }
    if( out.size() > 64 )
    {
        out.resize( 64 );
    }
    return out;
}
}
EOF
mkfix bigunq words.h <<'EOF'
#pragma once
#include <cstddef>
#include <string>
#include <string_view>
namespace words
{
inline std::string unquoteMarked( std::string_view s, std::size_t& dropped )
{
    std::string out;
    out.reserve( s.size() + 2 );
    for( char c : s )
    {
        if( c != '"' && c != '\'' )
        {
            out.push_back( c );
        }
        else
        {
            ++dropped;
        }
    }
    if( dropped > 8 )
    {
        out.insert( out.begin(), '@' );
        out.push_back( '@' );
    }
    if( out.size() > 128 )
    {
        out.resize( 128 );
    }
    return out;
}
}
EOF
mkfix peekq query.h <<'EOF'
#pragma once
#include <cstddef>
#include <string_view>
namespace query
{
struct Eval
{
    std::string_view src;
    std::size_t      pos = 0;
    void skipWs() noexcept
    {
        while( pos < src.size() && src[pos] == ' ' )
        {
            ++pos;
        }
    }
    char peek() noexcept
    {
        skipWs();
        return pos < src.size() ? src[pos] : '\0';
    }
};
}
EOF
mkfix peeks parser.h <<'EOF'
#pragma once
#include <cstddef>
#include <vector>
namespace shparse
{
struct Tok { int kind = 0; };
struct Parser
{
    std::vector<Tok> t_;
    std::size_t      i_ = 0;
    Tok              eof_{};
    const Tok& peek() const noexcept
    {
        return i_ < t_.size() ? t_[i_] : eof_;
    }
};
}
EOF
mkfix hexpair sidecar.h <<'EOF'
#pragma once
#include <ostream>
#include <string_view>
namespace sidecar
{
// a key -> hash record family: "<tag> <key> <hash>", both hex, one per record
template <class HexMap>
inline void writeHexPairLines( std::ostream& f, std::string_view tag, const HexMap& m )
{
    for( const auto& [h, v] : m )
    {
        f << tag << ' ' << std::hex << h << ' ' << v << std::dec << '\n';
    }
}
}
EOF
mkfix tangle tangle.h <<'EOF'
#pragma once
#include <cstdint>
#include <ostream>
#include <utility>
#include <vector>
namespace tanglefile
{
struct Snap
{
    bool                                               known = false;
    std::vector<std::pair<std::uint64_t, std::uint32_t>> bySym;
};
inline void writeTangleLines( std::ostream& f, const Snap& s )
{
    if( s.known )
    {
        f << "tangleon 1\n";
    }
    for( const auto& [h, v] : s.bySym )
    {
        f << "tangle " << std::hex << h << ' ' << v << std::dec << '\n';
    }
}
}
EOF
mkfix jsonget json.h <<'EOF'
#pragma once
#include <string>
#include <string_view>
#include <vector>
namespace tsimport
{
struct JsonNode
{
    std::vector<std::string> keys;
    std::vector<JsonNode>    vals;
    // a later duplicate wins at lookup, as in JSON.parse
    const JsonNode* get( std::string_view key ) const noexcept
    {
        for( std::size_t cursor = keys.size(); cursor > 0; --cursor )
        {
            if( keys[cursor - 1] == key )
            {
                return &vals[cursor - 1];
            }
        }
        return nullptr;
    }
};
}
EOF
mkfix steerfind steer.h <<'EOF'
#pragma once
#include <cstdint>
#include <string_view>
#include <vector>
namespace steer
{
struct Slot { std::string_view name; std::uint32_t scopeEnd = 0; };
struct Acc  { std::vector<Slot> slots; };
inline Slot* steer_find( Acc& acc, std::string_view name, std::uint32_t at ) noexcept
{
    for( std::size_t i = acc.slots.size(); i > 0; --i )
    {
        if( acc.slots[ i - 1 ].name == name && at < acc.slots[ i - 1 ].scopeEnd )
        {
            return &acc.slots[ i - 1 ];
        }
    }
    return nullptr;
}
}
EOF
mkfix identchar ident.h <<'EOF'
#pragma once
namespace unusedfile
{
inline bool isIdentChar( char c ) noexcept { return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_'; }
inline bool isIdent( char c ) noexcept { return isIdentChar( c ) || c == '$' || static_cast<unsigned char>( c ) >= 0x80; }
}
EOF
mkfix wordchar word.h <<'EOF'
#pragma once
#include "ident.h"
namespace shword
{
inline bool isWordChar( char c ) noexcept   // Python's \w on str: ASCII word characters, and any non-ASCII byte
{
    return unusedfile::isIdentChar( c ) || static_cast<unsigned char>( c ) >= 0x80;
}
}
EOF

# mkrepo <name> "<committed fixture dirs>" "<working-tree fixture dirs>": each dir's files land in src/.
mkrepo()
{
    local R="$TMP/$1" d
    mkdir -p "$R/src"
    ( cd "$R" && git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false ) || return 1
    for d in $2; do cp "$F/$d/"* "$R/src/"; done
    ( cd "$R" && git add -A && git commit -qm base ) || return 1
    for d in $3; do cp "$F/$d/"* "$R/src/"; done
    return 0
}
qd(){ "$BIN" "$TMP/$1" --quality-delta --no-cache 2>/dev/null; }   # status: exits 0 or 2 (gating) by design; the row is the verdict
# row <repo> <member substring>: the duplication row naming it, one line, or empty
row(){ qd "$1" | tr '<' '\n' | grep '^r kind="duplication"' | grep -- "$2" | head -1; }   # status: qd exits 0 or 2 by design; an empty row FAILs the arm that reads it

# demotes <label> <row> <why>: the row exists, is minor, does not gate, and names the difference
demotes()
{
    local label="$1" r="$2" why="$3"
    [ -n "$r" ] || { no "$label: no duplication row at all — the arm is vacuous"; return; }
    seen=$(( seen + 1 ))
    case "$r" in *'sev="minor"'*) ok "$label: minor";; *) no "$label: not minor (row: $r)";; esac
    case "$r" in *'gating="1"'*) no "$label: still gates (row: $r)";; *) ok "$label: does not gate";; esac
    case "$r" in *"why=\"$why\""*) ok "$label: why=\"$why\"";; *) no "$label: no why=\"$why\" (row: $r)";; esac
}
# gates <label> <row>: the row exists and gates, with no operand why=
gates()
{
    local label="$1" r="$2"
    [ -n "$r" ] || { no "$label: no duplication row at all — the negative proves nothing"; return; }
    seen=$(( seen + 1 ))
    case "$r" in *'gating="1"'*) ok "$label: gates";; *) no "$label: stopped gating (row: $r)";; esac
    case "$r" in *'why="different'*) no "$label: carries an operand why= (row: $r)";; *) ok "$label: no operand why=";; esac
}

echo "── positives"
mkrepo p1 "tables" "names" || { echo "git fixture setup failed"; exit 2; }
demotes "(P1) svLess search, vector<string> vs span<const string_view>" "$( row p1 hasName )" "different parameter types"
mkrepo p2 "squeeze" "unq" || { echo "git fixture setup failed"; exit 2; }
demotes "(P2) quote strip vs whitespace squeeze" "$( row p2 unq )" "different literals"
mkrepo p3 "peekq" "peeks" || { echo "git fixture setup failed"; exit 2; }
demotes "(P3) bounded peek, '\\0' vs a member" "$( row p3 Parser::peek )" "different literals"

echo "── negatives"
mkrepo n1 "hexpair" "tangle" || { echo "git fixture setup failed"; exit 2; }
gates "(N1) a tag-parameterised writer and its \"tangle \" instance share ' ' and '\\n'" "$( row n1 writeTangleLines )"
mkrepo n2 "jsonget" "steerfind" || { echo "git fixture setup failed"; exit 2; }
gates "(N2) two reverse find-by-key loops over the same literals" "$( row n2 steer_find )"
mkrepo n3 "samescope_base" "samescope_head" || { echo "git fixture setup failed"; exit 2; }
gates "(N3) the P2 pair in one namespace" "$( row n3 unq )"
mkrepo n4 "tables" "generic" || { echo "git fixture setup failed"; exit 2; }
gates "(N4) a generic member beside a concrete one" "$( row n4 hasName )"
mkrepo n5 "bigsqueeze" "bigunq" || { echo "git fixture setup failed"; exit 2; }
N5="$( row n5 unquoteMarked )"
gates "(N5) the P2 shape past the 80-token ceiling" "$N5"
case "$N5" in *'tokens="'[0-9][0-9][0-9]'"'*|*'tokens="'[89][0-9]'"'*) ok "(N5) premise: the group is 80 tokens or more";; *) no "(N5) premise: the group is under 80 tokens (row: ${N5:-<none>})";; esac
mkrepo n6 "identchar" "wordchar" || { echo "git fixture setup failed"; exit 2; }
gates "(N6) identifier classes sharing the literal 0x80" "$( row n6 isWordChar )"

echo "── (C) premise count"
if [ "$seen" -eq 9 ]; then ok "(C) all 9 arms found their row"; else no "(C) $seen of 9 arms found their row"; fi

echo "── (L) legend"
FULL="$( "$BIN" "$TMP/p2" --quality-delta --no-cache --legend=full 2>/dev/null )"   # status: exits 0 or 2 by design; the legend text is the verdict
case "$FULL" in *'operate on DIFFERENT DATA'*) ok "(L) a why= clone row's document defines it";; *) no "(L) a why= clone row's document never defines it";; esac
FULL1="$( "$BIN" "$TMP/n1" --quality-delta --no-cache --legend=full 2>/dev/null )"   # status: exits 0 or 2 by design; the legend text is the verdict
case "$FULL1" in *'operate on DIFFERENT DATA'*) no "(L) a document without a why= clone row pays for the sentence";; *) ok "(L) a document without a why= clone row carries no operand sentence";; esac

echo "── (V) the clones verb"
CL="$( "$BIN" "$TMP/p2" --clones --no-cache 2>/dev/null | grep -oE '<group [^>]*>(<f [^>]*/>)*</group>' | grep -E 'unq' | head -3 )"   # status: a failed --clones prints no group, and an empty CL FAILs (V) below; the whole group is read because its tag carries demoted=
case "$CL" in
    '')              no "(V) --clones shows no unq group — the arm is vacuous";;
    *'demoted="1"'*) no "(V) --clones reads the operand verdict: demoted=1 on the P2 group";;
    *)               ok "(V) --clones prints the P2 group without demoted=1";;
esac

echo "── (J) determinism"
qd p1 >"$TMP/a"; qd p1 >"$TMP/b"   # status: exits 0 or 2 by design; the byte compare below is the verdict
if cmp -s "$TMP/a" "$TMP/b"; then ok "(J) two runs byte-identical"; else no "(J) two runs differ"; fi

echo
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES"; exit 1
