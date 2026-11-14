#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include "infra/platform.h" // infra::platform::{add,sub,mul}Overflow — the checked constant-expression arithmetic
#include <string_view>       // %.*s (precision, pointer) collapses to one view


// layout.h — `--layout=STRUCT`, the CPU/GPU CONTRACT verb.
// Evidence: dual-compile uniform structs (AudioUniforms 24 B, MusicPulseUniforms 192→208 B in one day)
// are edited WEEKLY, and every edit makes the author hand-collect the same three things — the field
// offsets, the `static_assert( sizeof(X)==N )` tripwires that pin them, and the stub/mirror copies of the
// struct that must be edited in lockstep. Miss the third and the CPU writes 208 bytes into a buffer the
// GPU reads as 192: no compiler error, no crash, just wrong pixels. One call should answer "does my struct
// still match its mirror, and did this edit silently change its size".
//
// Three answers, one report:
//   fields   — declaration order with COMPUTED offsets/sizes/padding (see the honesty contract below)
//   asserts  — every static_assert in the index that mentions the struct, with agree="0" when a
//              `sizeof(X)==N` tripwire disagrees with the computed size
//   mirrors  — EVERY same-name definition in the index, compared field by field. Two definitions whose
//              field lists differ is the bug this verb exists for, so it is a header attribute
//              (mirror="mismatch"), its own element, AND a non-zero exit — not a row to scroll past.
//
// ── the honesty contract (read this before believing a number) ────────────────────────────────────────
// The offsets are COMPUTED from the source text under STANDARD-LAYOUT assumptions on a 64-bit
// little-endian Apple/LP64 target: natural alignment per field, interior padding up to each field's own
// alignment, trailing padding up to the aggregate's alignment. THIS IS A MODEL, NOT THE ABI. It is the
// same arithmetic a reader does by hand — which is the point, since doing it by hand is the friction —
// but the real compiler has inputs this module cannot see. So every input that would invalidate the
// arithmetic is DETECTED and the definition is marked modeled="0" with a named caveat, instead of
// printing a confident wrong number: `#pragma pack` anywhere in the file, bitfields, virtual members,
// base classes, nested/anonymous aggregates, `#if`-conditional members, templates, pointer-to-member
// fields, and any field whose type this module cannot size. `alignas(N)` and `__attribute__((packed))`
// ARE modelled (local, unambiguous) and reported as attributes.
// A field with an unknown size does not just lose its own row: every field AFTER it loses its offset too,
// and the aggregate reports no size at all. Silence beats a plausible lie here — the entire value of the
// verb is that its numbers can be trusted against the tripwire.
//
// ── scope, deliberately ───────────────────────────────────────────────────────────────────────────────
// "Niche in general; weekly value in GPU repos" (the field note's own words), so this stays a lexical
// model over the INDEXED C-family files and does not grow a preprocessor. Three consequences worth
// stating rather than discovering: (a) only C/C++/ObjC files are considered — a TypeScript or Swift
// `class Cat {` opens a brace after the word `class` and would otherwise be modelled as a C++ struct and
// then compared as a "mirror" of an unrelated same-named one; (b) mirrors are found among files ripwire
// INDEXES — `.metal` is one of them (indexed under the C++ grammar, see kLangTable in src/ingest.cpp),
// so a Metal-side mirror of a struct joins automatically with no special-casing here; (c) macro type
// names and array extents resolve
// against the DEFINING FILE's own `#define`s and `constexpr`/`using`/`enum` declarations only. The
// dual-compile idiom that motivated this — one macro with two
// definitions behind `#ifdef __METAL_VERSION__` — is handled by resolving EVERY definition and accepting
// the answer only when they all agree on the size (`AAPL_HALF_SCALAR` is `half` on one side and `__fp16`
// on the other; both are 2 bytes, so the offset is knowable and is reported).
//
// Determinism: definitions sort by (path, line), asserts by (path, line), fields keep declaration order,
// the constant table is a sorted btree_map, and no wall clock is ever read.

#include "model.h"
#include "graph.h"              // splitQualifiedSpec — the ONE `file:name` disambiguation rule --around/--lego use
#include "graphlegend.h"   // R-E fix (2026-08-19): rw::rootRelPathsLegend — the ONE root= definition
#include "arch.h"               // fnv1a64
#include "infra/hashutil.h"     // fnv1aMultiply — the sanitizer-safe wrapping multiply (G1 runs -fsanitize=integer)
#include "infra/namesplit.h"    // afterLast — the ONE base-name cut (lastSegment's `::` segment)
#include "serialize.h"          // escapeXml
#include "darkflags.h"          // readWhole — the same 4 MB-capped whole-file read the sibling field-notes verb owns
#include "infra/Diagnostics.h"  // ASSUME / DISCLOSE

#include "btree.hpp"      // gtl::btree_map — sorted iteration (house rule: never std::map)

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <functional>
#include <limits>       // std::numeric_limits — IntEval::apply refuses the one quotient int64 cannot hold
#include <memory>       // std::unique_ptr / shared_ptr / weak_ptr — the std:: table's sizeof rows
#include <string>
#include <string_view>
#include <utility>
#include <vector>
#include <version>     // _LIBCPP_VERSION / __GLIBCXX__ — which standard library sizes the std:: table

namespace rw
{
namespace layout
{

// ── tuning constants ─────────────────────────────────────────────────────────────────────────────────

constexpr std::size_t   kMaxNestDepth   = 8;          // nested-aggregate resolution depth (a cycle stops here)
constexpr std::size_t   kMaxMacroDepth  = 4;          // object-like macro expansion depth for a type name
constexpr std::size_t   kMaxExtentParens = 64;        // `(` nesting DEPTH an extent expression may reach (IntEval recurses per level)
constexpr std::size_t   kMaxDefScan     = 1u << 20;   // bytes scanned forward from a def start looking for its body
constexpr std::size_t   kMaxAssertChars = 220;        // the displayed prefix of a static_assert's text
constexpr std::uint32_t kMaxArrayElems  = 1u << 24;   // refusal bound: past this the extent is a parse artefact
constexpr std::size_t   kMaxDefsShown   = 24;         // a name defined more often than this is a generic, not a mirror

// ── the primitive size/alignment table (declarative, per house style — not a switch chain) ───────────
// 64-bit little-endian Apple/LP64. The C integer-family spellings (`unsigned long int`, `signed short`…)
// are NOT enumerated here: they reduce arithmetically in intFamilySize() below, which is exhaustive where
// an enumeration would be leaky. What lives here is everything with no such rule — the fixed-width
// typedefs, the floating types, and the simd/Metal vector+matrix vocabulary this verb exists to serve (a
// dual-compile uniform block is mostly half4 / float4 / float4x4).
struct PrimType
{
    std::string_view spelling;
    std::uint32_t    size;
    std::uint32_t    align;
};

constexpr PrimType kPrimTable[] = {
    // fixed-width + boolean + character
    { "bool",           1,  1 },  { "int8_t",         1,  1 },  { "uint8_t",        1,  1 },
    { "int16_t",        2,  2 },  { "uint16_t",       2,  2 },  { "char16_t",       2,  2 },
    { "int32_t",        4,  4 },  { "uint32_t",       4,  4 },  { "char32_t",       4,  4 },
    { "int64_t",        8,  8 },  { "uint64_t",       8,  8 },  { "wchar_t",        4,  4 },
    { "intptr_t",       8,  8 },  { "uintptr_t",      8,  8 },  { "ptrdiff_t",      8,  8 },
    { "size_t",         8,  8 },  { "ssize_t",        8,  8 },  { "off_t",          8,  8 },
    // floating point. `long double` is deliberately ABSENT: 8 B on Apple arm64, 16 B on x86-64, and this
    // module refuses any number it cannot pin to one answer.
    { "__fp16",         2,  2 },  { "_Float16",       2,  2 },  { "half",           2,  2 },
    { "float",          4,  4 },  { "double",         8,  8 },
    // simd / Metal vectors — the dual-compile vocabulary
    { "vector_half2",   4,  4 },  { "half2",          4,  4 },  { "simd_half2",     4,  4 },
    { "vector_half3",   8,  8 },  { "half3",          8,  8 },  { "simd_half3",     8,  8 },
    { "vector_half4",   8,  8 },  { "half4",          8,  8 },  { "simd_half4",     8,  8 },
    { "vector_float2",  8,  8 },  { "float2",         8,  8 },  { "simd_float2",    8,  8 },
    { "vector_float3", 16, 16 },  { "float3",        16, 16 },  { "simd_float3",   16, 16 },
    { "vector_float4", 16, 16 },  { "float4",        16, 16 },  { "simd_float4",   16, 16 },
    { "vector_int2",    8,  8 },  { "int2",           8,  8 },  { "simd_int2",      8,  8 },
    { "vector_uint2",   8,  8 },  { "uint2",          8,  8 },  { "simd_uint2",     8,  8 },
    { "vector_int3",   16, 16 },  { "int3",          16, 16 },  { "simd_int3",     16, 16 },
    { "vector_uint3",  16, 16 },  { "uint3",         16, 16 },  { "simd_uint3",    16, 16 },
    { "vector_int4",   16, 16 },  { "int4",          16, 16 },  { "simd_int4",     16, 16 },
    { "vector_uint4",  16, 16 },  { "uint4",         16, 16 },  { "simd_uint4",    16, 16 },
    { "vector_short2",  4,  4 },  { "short2",         4,  4 },  { "vector_short4",  8,  8 },
    { "short4",         8,  8 },  { "vector_uchar4",  4,  4 },  { "uchar4",         4,  4 },
    { "simd_bool",      4,  4 },
    // simd / Metal matrices (column-major: N columns, each the column vector's own size and alignment)
    { "matrix_float2x2", 16,  8 }, { "simd_float2x2", 16,  8 }, { "float2x2", 16,  8 },
    { "matrix_float3x3", 48, 16 }, { "simd_float3x3", 48, 16 }, { "float3x3", 48, 16 },
    { "matrix_float4x4", 64, 16 }, { "simd_float4x4", 64, 16 }, { "float4x4", 64, 16 },
    // packed_* deliberately drop the vector alignment (that IS their purpose) but keep the byte count
    { "packed_float2",  8,  4 },  { "packed_float3", 12,  4 },  { "packed_float4", 16,  4 },
    { "packed_half2",   4,  2 },  { "packed_half3",   6,  2 },  { "packed_half4",   8,  2 },
    // Apple / ObjC scalar aliases that show up in dual-compile headers (64-bit runtime)
    { "NSInteger",      8,  8 },  { "NSUInteger",     8,  8 },  { "CGFloat",        8,  8 },
    { "BOOL",           1,  1 },
};

// ── lexical helpers ──────────────────────────────────────────────────────────────────────────────────

// The two byte-level predicates the sibling field-notes module already owns — reused rather than respelled
// (darkflags.h is included here anyway, for its capped whole-file read).
using darkflags::identByte;
using darkflags::trimView;

// The whole-word test (`Foo` never matches `FooBar` / `myFoo`) moved DOWN to darkflags.h beside identByte
// when flipimpact.h's value lane needed the same primitive — one definition, imported here exactly like
// identByte/trimView above rather than cloned per module.
using darkflags::wholeWordAt;
using darkflags::containsWord;

// Collapse every whitespace run to one space and drop the ends — an XML ATTRIBUTE may not carry a raw
// newline under G4, and a multi-line static_assert is the common case.
inline std::string flattenSpace( std::string_view s, std::size_t cap )
{
    std::string out;
    out.reserve( std::min( s.size(), cap ) + 1 );
    bool pendingSpace = false;
    for( char c : s )
    {
        if( out.size() >= cap )
        {
            break;
        }
        if( std::isspace( (unsigned char)c ) != 0 ) { pendingSpace = !out.empty(); continue; }
        if( pendingSpace ) { out.push_back( ' ' ); pendingSpace = false; }
        out.push_back( c );
    }
    return out;
}

inline std::uint32_t lineOf( std::string_view src, std::size_t at )
{
    std::uint32_t line = 1;
    for( std::size_t i = 0; i < at && i < src.size(); ++i )
    {
        if( src[i] == '\n' )
        {
            ++line;
        }
    }
    return line;
}

// Advance past the comment / string / character literal starting at src[i]; returns i unchanged when
// src[i] opens none of them. The ONE skip routine every scan below shares, so a `//` inside a string or a
// brace inside a comment can never desync a brace match.
inline std::size_t skipInert( std::string_view src, std::size_t i )
{
    const std::size_t n = src.size();
    if( i + 1 < n && src[i] == '/' && src[ i + 1 ] == '/' )
    {
        i += 2;
        while( i < n && src[i] != '\n' )
        {
            ++i;
        }
        return i;
    }
    if( i + 1 < n && src[i] == '/' && src[ i + 1 ] == '*' )
    {
        i += 2;
        while( i + 1 < n && !( src[i] == '*' && src[i + 1] == '/' ) )
        {
            ++i;
        }
        return std::min( n, i + 2 );
    }
    if( src[i] == '"' || src[i] == '\'' )
    {
        const char  q = src[i];
        std::size_t j = i + 1;
        while( j < n && src[j] != q )
        {
            if( src[j] == '\\' )
            {
                ++j;
            }
            ++j;
        }
        return std::min( n, j + 1 );
    }
    return i;
}

// `s` with every COMMENT replaced by one space and every string/char literal kept verbatim. The body walk
// below already steps OVER comments, but the statement text it slices out still contains them, and a
// trailing `// bytes used (<= CAP)` on the previous line turns the next field into something with a `(` in
// it — i.e. into a "member function" that silently vanishes from the layout. (Found by dogfooding, not by
// inspection: it ate FixedStr's `data[CAP]` and made its size read 16 instead of 32.)
inline std::string withoutComments( std::string_view s )
{
    std::string out;
    out.reserve( s.size() );
    for( std::size_t i = 0; i < s.size(); )
    {
        const std::size_t j = skipInert( s, i );
        if( j == i ) { out.push_back( s[i] ); ++i; continue; }
        if( s[i] == '"' || s[i] == '\'' )
        {
            out.append( s.substr( i, j - i ) ); // a literal is content
        }
        else
        {
            // A comment becomes one space plus its OWN newlines: the line structure has to survive, or a
            // block comment straddling two lines would splice a `#define` onto whatever followed it.
            out.push_back( ' ' );
            for( char c : s.substr( i, j - i ) )
            {
                if( c == '\n' )
                {
                    out.push_back( '\n' );
                }
            }
        }
        i = j;
    }
    return out;
}

// Index just past the `close` that balances the `open` at src[from] (from must BE the open). Returns npos
// when the bracket never closes inside the buffer — a truncated/garbled file degrades, never hangs.
inline std::size_t matchBracket( std::string_view src, std::size_t from, char open, char close )
{
    ASSUME( from < src.size() && src[ from ] == open );
    int depth = 0;
    for( std::size_t i = from; i < src.size(); )
    {
        const std::size_t skipped = skipInert( src, i );
        if( skipped != i ) { i = skipped; continue; }
        if( src[i] == open )
        {
            ++depth;
        }
        else if( src[i] == close )
        {
            --depth;
            if( depth == 0 )
            {
                return i + 1;
            }
        }
        ++i;
    }
    return std::string_view::npos;
}

// Invoke `onCall( at, close, inner )` for every WHOLE-WORD occurrence of `keyword` in `text` that is
// immediately followed by a balanced parenthesis group — passing the keyword's position, one past the
// closing paren, and the group's inner text. `alignas( 32 )` and `static_assert( sizeof(X) == N, "…" )`
// are the same shape, and the whitespace/nesting handling is worth getting right exactly once.
template<class OnCall>
inline void forEachKeywordCall( std::string_view text, std::string_view keyword, OnCall onCall )
{
    for( std::size_t at = text.find( keyword ); at != std::string_view::npos; at = text.find( keyword, at + 1 ) )
    {
        if( !wholeWordAt( text, at, keyword.size() ) )
        {
            continue;
        }
        std::size_t p = at + keyword.size();
        while( p < text.size() && std::isspace( (unsigned char)text[p] ) != 0 )
        {
            ++p;
        }
        if( p >= text.size() || text[p] != '(' )
        {
            continue;
        }
        const std::size_t close = matchBracket( text, p, '(', ')' );
        if( close == std::string_view::npos )
        {
            continue;
        }
        onCall( at, close, text.substr( p + 1, close - p - 2 ) );
    }
}

// The identifier starting at `i` (empty when src[i] does not open one), advancing `i` past it. `::` is
// absorbed so `std::uint8_t` stays ONE token — a qualified name split into three tokens would make the
// declarator rule "the last identifier is the field name" pick `uint8_t` as the name.
inline std::string_view takeQualifiedIdent( std::string_view src, std::size_t& i )
{
    while( i < src.size() && !identByte( (unsigned char)src[i] ) )
    {
        ++i;
    }
    const std::size_t start = i;
    while( i < src.size() )
    {
        if( identByte( (unsigned char)src[i] ) ) { ++i; continue; }
        if( src[i] == ':' && i + 2 < src.size() && src[ i + 1 ] == ':' && identByte( (unsigned char)src[ i + 2 ] ) )
        { i += 2; continue; }
        break;
    }
    return src.substr( start, i - start );
}

inline bool isCFamilyPath( std::string_view path )
{
    static constexpr std::string_view kExt[] = { ".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx",
                                                 ".inl", ".ipp", ".m", ".mm", ".metal", ".cu", ".cuh" };
    const std::size_t dot = path.rfind( '.' );
    if( dot == std::string_view::npos )
    {
        return false;
    }
    const std::string_view ext = path.substr( dot );
    for( std::string_view e : kExt )
    {
        if( ext == e )
        {
            return true;
        }
    }
    return false;
}

// ── the constant table (array extents + macro type names, harvested from the DEFINING FILE) ──────────
// One name may legitimately have SEVERAL definitions in one file — that is exactly the dual-compile
// `#ifdef __METAL_VERSION__ / #else / #endif` idiom — so this is a name → LIST, and the resolvers below
// accept an answer only when every definition agrees. Harvested patterns:
//   #define NAME replacement                      (object-like only)
//   [static] [inline] constexpr TYPE NAME = expr; (the in-class `static constexpr int CAP = 31;` idiom)
//   [static] const     TYPE NAME = expr;
//   NAME = <integer>,                             (a bare enumerator line, for array extents)
//   using NAME = SPELLING;  /  typedef SPELLING NAME;   (a TYPE alias — same table, same agreement rule:
//                                                        `NodeId` has to become `std::uint32_t` before it
//                                                        can be sized, and a house repo is full of them)
//   enum [class|struct] NAME : UNDERLYING          (the fixed underlying type IS the size)
//   enum class NAME {                              (a scoped enum with no fixed type is `int` by the
//                                                   standard — certain, unlike an unscoped one)
using ConstTable = gtl::btree_map<std::string, std::vector<std::string>>;

inline void addConst( ConstTable& table, std::string_view name, std::string_view value )
{
    const std::string_view v = trimView( value );
    if( name.empty() || v.empty() )
    {
        return;
    }
    std::vector<std::string>& slot = table[ std::string( name ) ];
    for( const std::string& existing : slot )
    {
        if( existing == v )
        {
            return; // the same spelling twice ⇒ one entry
        }
    }
    slot.emplace_back( v );
}

// `#define NAME replacement` — object-like only: a `(` straight after the name is a function macro, whose
// replacement is not a type or an integer this module can use.
inline void harvestObjectMacro( ConstTable& table, std::string_view line )
{
    const std::string_view d = trimView( line.substr( 1 ) );
    if( d.rfind( "define", 0 ) != 0 || d.size() <= 6 || identByte( (unsigned char)d[6] ) )
    {
        return;
    }
    std::size_t            k    = 6;
    const std::string_view name = takeQualifiedIdent( d, k );
    if( name.empty() || ( k < d.size() && d[k] == '(' ) )
    {
        return;
    }

    // The replacement stops at a trailing comment: `#define F 0  // dark` defines F as "0", not "0 // dark".
    std::string_view  rep = d.substr( std::min( k, d.size() ) );
    const std::size_t cmt = std::min( rep.find( "//" ), rep.find( "/*" ) );
    if( cmt != std::string_view::npos )
    {
        rep = rep.substr( 0, cmt );
    }
    addConst( table, name, rep );
}

// A `= value` declaration — `constexpr` / `const` / a bare enumerator. The NAME is the identifier
// immediately left of the `=`; the value runs to the terminating `;` or `,`.
inline void harvestValueConstant( ConstTable& table, std::string_view line )
{
    const std::size_t eq = line.find( '=' );
    if( eq == std::string_view::npos || eq == 0 )
    {
        return;
    }
    if( eq + 1 < line.size() && line[eq + 1] == '=' )
    {
        return;
    }
    static constexpr std::string_view kNotAssignment = "=!<>+-*/&|^%";             // ==, !=, <=, +=, … are comparisons/compounds
    if( kNotAssignment.find( line[eq - 1] ) != std::string_view::npos )
    {
        return;
    }

    const std::string_view lhs     = line.substr( 0, eq );
    const bool             isDecl  = containsWord( lhs, "constexpr" ) || containsWord( lhs, "const" );
    std::size_t            nameEnd = eq;
    while( nameEnd > 0 && std::isspace( (unsigned char)line[nameEnd - 1] ) != 0 )
    {
        --nameEnd;
    }
    std::size_t nameStart = nameEnd;
    while( nameStart > 0 && identByte( (unsigned char)line[nameStart - 1] ) )
    {
        --nameStart;
    }
    const bool isEnumerator = nameStart == 0 && !isDecl;               // a bare `NAME = 3,` line inside an enum
    if( nameStart == nameEnd || !( isDecl || isEnumerator ) )
    {
        return;
    }

    std::string_view  value = line.substr( eq + 1 );
    const std::size_t stop  = std::min( std::min( value.find( ';' ), value.find( ',' ) ),
                                        std::min( value.find( "//" ), value.find( "/*" ) ) );
    if( stop != std::string_view::npos )
    {
        value = value.substr( 0, stop );
    }
    addConst( table, line.substr( nameStart, nameEnd - nameStart ), value );
}

// `line` opens with the whole word `kw`.
inline bool leadsWith( std::string_view line, std::string_view kw )
{
    return line.rfind( kw, 0 ) == 0 && ( line.size() == kw.size() || !identByte( (unsigned char)line[ kw.size() ] ) );
}

// `enum [class|struct] NAME [: UNDERLYING] {` — the fixed underlying type IS the size, and a SCOPED enum
// without one is `int` by the standard. An UNSCOPED enum without one is implementation-defined, so it is
// deliberately NOT recorded (resolveFieldType's enum-assumed-4 lane names that guess out loud instead).
inline void harvestEnumUnderlying( ConstTable& table, std::string_view line )
{
    std::size_t      k      = 4;
    std::string_view word   = takeQualifiedIdent( line, k );
    const bool       scoped = ( word == "class" || word == "struct" );
    if( scoped )
    {
        word = takeQualifiedIdent( line, k );
    }
    if( word.empty() )
    {
        return;
    }

    const std::size_t colon = line.find( ':', k );
    const std::size_t brace = line.find( '{', k );
    if( colon == std::string_view::npos || ( brace != std::string_view::npos && brace < colon ) )
    {
        if( scoped )
        {
            addConst( table, word, "int" );
        }
        return;
    }
    std::string_view  underlying = line.substr( colon + 1 );
    const std::size_t stop       = std::min( underlying.find( '{' ), underlying.find( ';' ) );
    if( stop != std::string_view::npos )
    {
        underlying = underlying.substr( 0, stop );
    }
    addConst( table, word, underlying );
}

// `using NAME = SPELLING;` — never an alias TEMPLATE (its arguments are not knowable here) and never a
// using-DECLARATION (`using std::swap;`, which has no `=`).
inline void harvestUsingAlias( ConstTable& table, std::string_view line )
{
    const std::size_t eq = line.find( '=' );
    if( eq == std::string_view::npos )
    {
        return;
    }
    std::size_t            k    = 5;
    const std::string_view name = takeQualifiedIdent( line, k );
    if( name.empty() || k > eq )
    {
        return;
    }

    std::string_view  spelling = line.substr( eq + 1 );
    const std::size_t stop     = spelling.find( ';' );
    if( stop != std::string_view::npos )
    {
        spelling = spelling.substr( 0, stop );
    }
    if( trimView( spelling ) != name )
    {
        addConst( table, name, spelling );
    }
}

// `typedef SPELLING NAME;` — the simple one-line form only. A `{` means it is a typedef of an aggregate
// DEFINITION (`typedef struct X {…} X;`), which the aggregate index already owns.
inline void harvestTypedefAlias( ConstTable& table, std::string_view line )
{
    const std::size_t semi = line.find( ';' );
    if( semi == std::string_view::npos )
    {
        return;
    }
    if( line.find( '{' ) != std::string_view::npos || line.find( '(' ) != std::string_view::npos )
    {
        return;
    }

    const std::string_view body    = trimView( line.substr( 7, semi - 7 ) );
    std::size_t            nameEnd = body.size();
    while( nameEnd > 0 && !identByte( (unsigned char)body[nameEnd - 1] ) )
    {
        --nameEnd;
    }
    std::size_t nameStart = nameEnd;
    while( nameStart > 0 && identByte( (unsigned char)body[nameStart - 1] ) )
    {
        --nameStart;
    }
    if( nameStart == nameEnd || nameEnd != body.size() )
    {
        return;
    }

    const std::string_view name     = body.substr( nameStart, nameEnd - nameStart );
    const std::string_view spelling = trimView( body.substr( 0, nameStart ) );
    if( !spelling.empty() && spelling != name )
    {
        addConst( table, name, spelling );
    }
}

// The three TYPE-alias lanes, dispatched by leading keyword so harvestConstants stays one readable loop.
// Returns true when the line was an alias declaration, so the caller stops looking at it.
inline bool harvestTypeAlias( ConstTable& table, std::string_view line )
{
    if( leadsWith( line, "enum" ) )    { harvestEnumUnderlying( table, line ); return true; }
    if( leadsWith( line, "using" ) )   { harvestUsingAlias( table, line );     return true; }
    if( leadsWith( line, "typedef" ) ) { harvestTypedefAlias( table, line );   return true; }
    return false;
}

inline ConstTable harvestConstants( std::string_view src )
{
    ConstTable  table;
    std::size_t lineStart = 0;
    while( lineStart <= src.size() )
    {
        std::size_t e = src.find( '\n', lineStart );
        if( e == std::string_view::npos )
        {
            e = src.size();
        }
        const std::string_view line = trimView( src.substr( lineStart, e - lineStart ) );
        const bool             last = e >= src.size();
        lineStart = e + 1;
        if( line.empty() )
        {
            if( last ) { break; }
            else
            {
                continue;
            }
        }
        if( line[0] == '#' )
        {
            harvestObjectMacro( table, line );
        }
        else if( !harvestTypeAlias( table, line ) )
        {
            harvestValueConstant( table, line );
        }
        if( last )
        {
            break;
        }
    }
    return table;
}

// ── integer-expression evaluation (array extents) ────────────────────────────────────────────────────
// A tiny recursive-descent evaluator over `+ - * / ( )`, integer literals, and CONSTANT NAMES resolved
// through the table above. Deliberately small: an extent it cannot evaluate becomes an UNKNOWN extent
// (which un-sizes the field, which un-sizes the aggregate) rather than a guess.
struct IntEval
{
    const ConstTable& table;
    std::size_t       depth = 0;
    bool              ok    = true;
    std::size_t       parenDepth = 0;   // `(` levels OPEN at this point of the parse — kMaxExtentParens bounds the recursion

    std::int64_t parse( std::string_view s )
    {
        std::size_t        i = 0;
        const std::int64_t v = level( s, i, 0 );
        skipWs( s, i );
        if( i != s.size() )
        {
            ok = false;
        }
        return v;
    }

private:
    // Precedence-climbing: ONE binary level parameterized by rank, rather than a sum()/product() pair whose
    // bodies would be the same eleven lines twice (the clone the quality gate would — correctly — flag).
    // Rank 0 is `+ -`, rank 1 is `* /`, rank 2 falls through to atom().
    static constexpr std::string_view kOpsAtRank[] = { "+-", "*/" };

    static void skipWs( std::string_view s, std::size_t& i )
    {
        while( i < s.size() && std::isspace( (unsigned char)s[i] ) != 0 )
        {
            ++i;
        }
    }

    // Every operator is checked: an extent is source text, so `(0-1099511627776)*8388608` reaches INT64_MIN and a
    // following `/(0-1)` is the one quotient int64 cannot hold (SIGFPE on x86-64), and a plain `1<<40 * 1<<40`
    // product is signed overflow (an abort in the sanitizer build). An expression that leaves the range is not a
    // knowable extent, so it un-sizes the field exactly like any other expression this evaluator cannot read.
    std::int64_t apply( char op, std::int64_t a, std::int64_t b )
    {
        std::int64_t r = 0;
        bool         outOfRange = false;
        switch( op )
        {
            case '+': outOfRange = infra::platform::addOverflow( a, b, &r ); break;
            case '-': outOfRange = infra::platform::subOverflow( a, b, &r ); break;
            case '*': outOfRange = infra::platform::mulOverflow( a, b, &r ); break;
            default:
                outOfRange = b == 0 || ( b == -1 && a == std::numeric_limits<std::int64_t>::min() );   // never divide by zero under G1
                r          = outOfRange ? 0 : a / b;
                break;
        }
        if( outOfRange )
        {
            ok = false;
            return 0;
        }
        return r;
    }

    std::int64_t level( std::string_view s, std::size_t& i, std::size_t rank )
    {
        if( rank >= std::size( kOpsAtRank ) )
        {
            return atom( s, i );
        }
        const std::string_view ops = kOpsAtRank[ rank ];
        std::int64_t           v   = level( s, i, rank + 1 );
        for( skipWs( s, i ); ok && i < s.size() && ops.find( s[i] ) != std::string_view::npos; skipWs( s, i ) )
        {
            const char op = s[ i++ ];
            v = apply( op, v, level( s, i, rank + 1 ) );
        }
        return v;
    }

    std::int64_t atom( std::string_view s, std::size_t& i )
    {
        skipWs( s, i );
        if( i >= s.size() || !ok ) { ok = false; return 0; }
        if( s[i] == '(' )
        {
            // A bounded recursion: `#define N ((((…1))))` 200,000 levels deep overflowed the stack (SIGSEGV, exit 139).
            // The bound is the DEPTH of open parentheses, restored when this level closes: `(A)+(B)+…` with sixty-six
            // sibling terms nests one level, and must size exactly as it did before the bound existed.
            if( parenDepth >= kMaxExtentParens ) { ok = false; return 0; }
            ++parenDepth;
            ++i;
            const std::int64_t v = level( s, i, 0 );
            --parenDepth;
            skipWs( s, i );
            if( i < s.size() && s[i] == ')' ) { ++i; }
            else
            {
                ok = false;
            }
            return v;
        }
        if( std::isdigit( (unsigned char)s[i] ) != 0 )
        {
            std::int64_t v = 0;
            while( i < s.size() && std::isdigit( (unsigned char)s[i] ) != 0 )
            {
                if( v > ( 1ll << 40 ) ) { ok = false; return 0; }      // absurd literal — refuse, never wrap
                v = v * 10 + ( s[ i++ ] - '0' );
            }
            while( i < s.size() && ( s[i] == 'u' || s[i] == 'U' || s[i] == 'l' || s[i] == 'L' ) )
            {
                ++i;
            }
            return v;
        }
        if( !identByte( (unsigned char)s[i] ) ) { ok = false; return 0; }

        const std::string_view name = takeQualifiedIdent( s, i );
        if( name.empty() || depth >= kMaxMacroDepth ) { ok = false; return 0; }   // bounded: an A→B→A cycle stops here
        const auto it = table.find( std::string( name ) );
        if( it == table.end() || it->second.empty() ) { ok = false; return 0; }

        // Every definition of the name must agree, or the extent is not knowable (the dual-compile rule).
        std::int64_t first = 0;
        for( std::size_t k = 0; k < it->second.size(); ++k )
        {
            IntEval            inner{ table, depth + 1, true };
            const std::int64_t v = inner.parse( it->second[k] );
            if( !inner.ok ) { ok = false; return 0; }
            if( k == 0 )
            {
                first = v;
            }
            else if( v != first )
            {
                ok = false;
                return 0;
            }
        }
        return first;
    }
};

inline bool evalExtent( const ConstTable& table, std::string_view expr, std::uint32_t& out )
{
    IntEval            ev{ table, 0, true };
    const std::int64_t v = ev.parse( expr );
    if( !ev.ok || v <= 0 || v > std::int64_t( kMaxArrayElems ) )
    {
        return false;
    }
    out = std::uint32_t( v );
    return true;
}

// ── type sizing ──────────────────────────────────────────────────────────────────────────────────────

struct TypeSize
{
    std::uint32_t size    = 0;
    std::uint32_t align   = 1;
    bool          known   = false;
    std::uint32_t tailPad = 0;       // an aggregate's trailing pad (a base with one is refused: ABIs differ on reusing it)
    bool          empty   = false;   // an aggregate with no members (an empty base takes no bytes)
};

// The C integer family reduced arithmetically instead of enumerated: any word set drawn only from
// {signed, unsigned, char, short, int, long} has exactly one size, and the `long` count decides the rest.
inline bool intFamilySize( const std::vector<std::string_view>& words, TypeSize& out )
{
    bool hasChar = false, hasShort = false, hasInt = false, hasSign = false;
    int  longCount = 0;
    for( std::string_view w : words )
    {
        if( w == "char" )
        {
            hasChar = true;
        }
        else if( w == "short" )
        {
            hasShort = true;
        }
        else if( w == "int" )
        {
            hasInt = true;
        }
        else if( w == "long" )
        {
            ++longCount;
        }
        else if( w == "signed" || w == "unsigned" )
        {
            hasSign = true;
        }
        else
        {
            return false; // a word outside the family
        }
    }
    if( !hasChar && !hasShort && !hasInt && longCount == 0 && !hasSign )
    {
        return false;
    }
    if( hasChar )
    {
        out = TypeSize { 1, 1, true };
    }
    else if( hasShort )
    {
        out = TypeSize { 2, 2, true };
    }
    else if( longCount > 0 )
    {
        out = TypeSize { 8, 8, true };
    }
    else
    {
        out = TypeSize { 4, 4, true };
    }
    return true;
}

// Split a type spelling into significant words, dropping the qualifiers and elaborated-type keywords that
// never change a size, and stripping a leading `std::` / `::`.
inline std::vector<std::string_view> typeWords( std::string_view spec, bool& sawEnumKeyword )
{
    static constexpr std::string_view kNoise[] = { "const", "volatile", "mutable", "constexpr", "typename",
                                                   "struct", "class", "union", "restrict", "__restrict", "inline" };
    std::vector<std::string_view> out;
    sawEnumKeyword = false;
    for( std::size_t i = 0; i < spec.size(); )
    {
        if( !identByte( (unsigned char)spec[i] ) ) { ++i; continue; }
        std::string_view w = takeQualifiedIdent( spec, i );
        if( w.empty() )
        {
            break;
        }
        if( w == "enum" ) { sawEnumKeyword = true; continue; }
        bool noise = false;
        for( std::string_view k : kNoise )
        {
            if( w == k )
            {
                noise = true;
                break;
            }
        }
        if( noise )
        {
            continue;
        }
        if( w.rfind( "std::", 0 ) == 0 )
        {
            w = w.substr( 5 );
        }
        while( w.rfind( "::", 0 ) == 0 )
        {
            w = w.substr( 2 );
        }
        if( !w.empty() )
        {
            out.push_back( w );
        }
    }
    return out;
}

// A namespace-qualified primitive still names the same primitive: `simd::float3` is `float3`, and the
// simd/Metal headers spell it both ways in the same tree. The LAST segment is what the table keys on.
inline std::string_view lastSegment( std::string_view s )
{
    return rw::namesplit::afterLast( s, "::" );
}

inline bool primLookup( std::string_view spelling, TypeSize& out )
{
    for( std::string_view probe : { spelling, lastSegment( spelling ) } )
    {
        for( const PrimType& p : kPrimTable )
        {
            if( p.spelling == probe ) { out = TypeSize{ p.size, p.align, true }; return true; }
        }
    }
    return false;
}

// ── the std:: member table (LAYOUT-SIZED, 2026-11-11 memory audit) ───────────────────────────────────
// `--layout` on ripwire's own Reference/Binding/Symbol said sized="0" for every std::string member — or, worse, sized a
// `std::string` as an unrelated in-repo `class string {}` stub at 1 B and printed a confident size="28" for a 96 B Binding.
// The standard library's own types now have a table. Their sizes are a property of the LIBRARY, not of the C++ language:
// std::string is 24 B in libc++ and 32 B in libstdc++. The table is the library THIS binary was compiled against
// (std_abi= on the answer names it), so a Linux build answers libstdc++ and a macOS build libc++, each matching the
// compiler beside it (test/layoutcheck.sh compiles a probe and compares). Anything else in std:: is never guessed and
// never resolved to a same-named in-repo type: it stays unsized with why="std-unlisted". MSVC's STL changes its
// container sizes with _ITERATOR_DEBUG_LEVEL, so a Windows build carries no table rather than a number that depends on a
// build setting the source cannot show.
// Every number below is sizeof/alignof of the REAL type in this binary's library (CodeRabbit 4544554325): a build setting that
// moves a size (_GLIBCXX_USE_CXX11_ABI=0's 8 B std::string, _GLIBCXX_DEBUG's vector, a libc++ ABI option) moves it here too.
#if defined( _LIBCPP_VERSION ) && defined( __LP64__ )
inline constexpr std::string_view kStdAbi = "libc++";
#elif defined( __GLIBCXX__ ) && defined( __LP64__ )
inline constexpr std::string_view kStdAbi = "libstdc++";
#else
inline constexpr std::string_view kStdAbi = {};
#endif
inline constexpr std::uint32_t kStdStringSize  = std::uint32_t( sizeof( std::string ) );
inline constexpr std::uint32_t kStdStringAlign = std::uint32_t( alignof( std::string ) );

// The arg-independent rows: `args` is how many template arguments the DEFAULT form takes (a second one — a custom
// allocator or deleter — can change the size, so it is refused rather than assumed stateless).
struct StdFixedType
{
    std::string_view name;
    std::uint32_t    args;
    std::uint32_t    size;
    std::uint32_t    align;
};

template<class T>
inline constexpr StdFixedType stdFixedRow( std::string_view name, std::uint32_t args )
{
    return StdFixedType{ name, args, std::uint32_t( sizeof( T ) ), std::uint32_t( alignof( T ) ) };
}
// The default-allocator / default-deleter forms: their size does not depend on the element type.
inline constexpr StdFixedType kStdFixedTable[] = {
    stdFixedRow<std::string_view>( "string_view", 0 ), stdFixedRow<std::vector<int>>( "vector", 1 ),
    stdFixedRow<std::unique_ptr<int>>( "unique_ptr", 1 ), stdFixedRow<std::shared_ptr<int>>( "shared_ptr", 1 ),
    stdFixedRow<std::weak_ptr<int>>( "weak_ptr", 1 ),
};

// ── the result model ─────────────────────────────────────────────────────────────────────────────────

struct FieldRow
{
    std::string   name;
    std::string   type;                  // the type as WRITTEN (pre-expansion) — what the reader edits
    std::string   resolved;              // what a macro expanded to; "" when the spelling was already final
    std::uint32_t offset    = 0;
    std::uint32_t size      = 0;         // total bytes INCLUDING the array extent
    std::uint32_t align     = 1;
    std::uint32_t elems     = 1;         // array extent product; 1 = not an array
    std::uint32_t padBefore = 0;         // padding the model inserted in front of this field
    bool          sized     = false;     // the type's size/align are known
    bool          placed    = false;     // …and so is the offset (false once an earlier field went unknown)
    std::string   why;                   // !sized: the reason kind (why= on the row; same vocabulary as a caveat k=)
    std::uint32_t bitWidth  = 0;         // a bitfield's width in bits; 0 = not a bitfield (its byte is `offset`)
    std::uint32_t bitOffset = 0;         // the bitfield's first bit within that byte
};

struct Caveat
{
    std::string   kind;                    // bitfield / virtual / base-class / pragma-pack / unknown-type / …
    std::string   detail;                  // the FIRST field/site this kind fired on (see addCaveat)
    std::uint32_t count = 1;               // §P6.12: how many times this KIND fired — the dedup below keeps
                                            // one row per kind ("a report, not a log"), which used to make a
                                            // second unmodelable field of the SAME kind (e.g. two std::string
                                            // fields, both "unknown-type") vanish with no count telling the
                                            // reader a second one existed. count reconciles caveat rows against
                                            // the actual number of sites that hit each kind.
};

struct LayoutDef
{
    std::string   path;                  // the labeled (display) path, exactly as ing.files spells it
    std::uint32_t line          = 0;
    const char*   aggregate     = "struct";   // struct | class | union
    std::uint32_t size          = 0;
    std::uint32_t align         = 1;
    std::uint32_t tailPad       = 0;
    std::uint32_t declaredAlign = 0;     // alignas(N) written on the aggregate; 0 = none
    bool          packedAttr    = false; // __attribute__((packed)) — modelled as align 1 throughout
    bool          modeled       = true;  // false ⇒ size/align/offsets are NOT reported (see the caveats)
    std::string   baseSpec;              // the ONE base class as written (`RefColdFields`); "" = none
    std::uint32_t baseSize      = 0;     // bytes the base subobject occupies at offset 0 (0 for an empty base)
    bool          baseSized     = false;
    std::vector<FieldRow> fields;
    std::vector<Caveat>   caveats;
    // Two mirror keys, because two definitions can differ in two very different ways. `byteShape` is the
    // BYTE contract (field names + computed offsets/sizes/extents + the aggregate's own size/align) and is
    // the only one that can break a CPU/GPU buffer. `spellShape` also folds in the type SPELLINGS, which
    // legitimately differ between the two arms of one `#ifdef __METAL_VERSION__` block (`simd::float4` on
    // the host, `float4` in the shader) — a difference worth SHOWING and never worth failing a build over.
    std::uint64_t byteShape     = 0;
    std::uint64_t spellShape    = 0;
    // A THIRD key, name-blind: `spellShape` with every field NAME folded out, so two definitions whose
    // positional slot sequence (offset/size/align/extent) AND type spellings agree hash the same even when
    // the fields are called something else. It is the only way to tell a pure source-level RENAME from a
    // repack — `x,y` -> `a,b` keeps every byte where it was, while `half,half` -> `unsigned int` at the same
    // offset does not, and both read as "same size, different fields" without it. Consumed by abicheck.h
    // (cross-BRANCH, where a rename is a source change over time); deliberately NOT consumed by --layout's
    // own mirror verdict, where a CPU/GPU pair disagreeing on a field's NAME is itself the bug.
    std::uint64_t slotShape     = 0;
};

struct AssertRow
{
    std::string   path;
    std::uint32_t line    = 0;
    std::string   text;                  // whitespace-flattened, truncated
    const char*   kind    = "mention";   // sizeof | alignof | mention
    std::uint32_t want    = 0;
    std::uint32_t got     = 0;
    bool          hasWant = false;
    bool          compared = false;      // a modelled number existed to compare against
    bool          agree   = true;
};

struct FieldDiff
{
    std::string name;
    std::string inA;                     // "float@4" / "Slot x4@0" / "absent"
    std::string inB;
};

struct MirrorDiff
{
    std::string            a, b;         // "path:line" of each side
    std::vector<FieldDiff> fields;
    bool                   sizeDiffers = false;
    std::uint32_t          sizeA = 0, sizeB = 0;
    // Why the two sides differ, which decides whether it is a BREAK or just worth seeing:
    //   drift    — the byte contract itself differs. This is the bug the verb exists for; exit 2.
    //   stub     — one side is an EMPTY placeholder aggregate (`struct AudioUniforms {};` in a test's
    //              stub_includes tree). A real repo is full of them; failing on every one would make the
    //              verdict worthless where it matters.
    //   spelling — identical bytes, different type NAMES: the two arms of one `#ifdef __METAL_VERSION__`
    //              block (`simd::float4` host-side, `float4` in the shader). That is the dual-compile
    //              idiom working correctly, not drift.
    // All three are REPORTED — the reader asked for every same-name definition — but only drift breaks.
    const char*            kind = "drift";
    bool                   stubOnly = false;
};

struct LayoutResult
{
    std::string             sym;
    bool                    found = false;
    std::vector<LayoutDef>  defs;
    std::vector<AssertRow>  asserts;
    std::vector<MirrorDiff> mirrors;     // populated ONLY when two definitions disagree
    std::uint32_t           assertConflicts = 0;
    std::size_t             filesScanned = 0;
    std::size_t             defsFound    = 0;   // before the display cap
    // Symbols that carry the name but have NO C-family aggregate body — a Python/Java/Go/Rust/Swift class,
    // or a forward declaration. Tracked separately so the refusal can say "indexed, but this verb models
    // C/C++/ObjC byte layout" instead of the flatly wrong "no such struct".
    std::size_t             bodilessCandidates = 0;
    // Symbols that resolved to an `enum`/`enum class`/`enum struct` body (§P6.11) — tracked separately so
    // the refusal can say "this is an enum, --layout models structs" instead of silently degrading to a
    // confident modeled="1" zero-field struct, or falling through to the generic bodiless-candidate message.
    std::size_t             enumCandidates = 0;
    // Definitions whose FILE could not be read when the verb ran (removed, or unreadable since it was indexed). They
    // are absent from defs=/mirror=, so the root says so with unreadable="N" — a mirror="single" beside it is one
    // definition READ, not one definition that exists. This struct is the DISCLOSE sink for that degrade.
    std::size_t             unreadableDefs = 0;
    bool                    stdTableUsed   = false;   // a std:: row of the table sized something: std_abi= on the root
    enum class DisclosureWhy : std::uint8_t
    {
        UnreadableFile,
    };
    void disclose( DisclosureWhy ) noexcept   // every reason records the same fact
    {
        ++unreadableDefs;
    }
};

// The verb's own verdict. A definition that could NOT be modelled is not a break — there is no number to
// disagree with — and neither is an empty stub. Only a real disagreement (mirror DRIFT between two
// populated definitions, or a tripwire the computed size contradicts) is.
inline bool layoutContractBroken( const LayoutResult& r ) noexcept
{
    for( const MirrorDiff& m : r.mirrors )
    {
        if( std::string_view( m.kind ) == "drift" )
        {
            return true;
        }
    }
    return r.assertConflicts > 0;
}

// ── locating a definition's body in its file ─────────────────────────────────────────────────────────

struct DefSite
{
    std::uint32_t fileId     = 0;
    std::size_t   headStart  = 0;        // first byte of the declaration (the `typedef` / `struct` keyword)
    std::size_t   braceStart = 0;        // the `{`
    std::size_t   braceEnd   = 0;        // one past the matching `}`
    bool          isEnum     = false;    // set on a FALSE return: the candidate body belongs to an enum, not
                                          // an aggregate (§P6.11) — `enum class X {`/`enum struct X {` heads
                                          // contain the word "class"/"struct" too, so this must be checked
                                          // before the struct/class/union acceptance test below, not after.
};

// Find `name`'s body starting from its indexed def byte. Returns false when the symbol is NOT a definition
// with a body — the common and load-bearing case: `typedef struct X {…} X;` yields TWO indexed symbols
// named X (the aggregate and the typedef alias), and this rejects whichever one hits a `;` before a `{`.
// Survivors are deduped by (fileId, braceStart) at the call site, so the two never become two "mirrors".
inline bool findDefBody( std::string_view src, std::string_view name, std::size_t from, DefSite& out )
{
    if( from >= src.size() )
    {
        return false;
    }
    const std::size_t limit = std::min( src.size(), from + kMaxDefScan );

    std::size_t i = from;
    while( i < limit )
    {
        const std::size_t skipped = skipInert( src, i );
        if( skipped != i ) { i = skipped; continue; }
        if( src[i] == '{' )
        {
            break;
        }
        if( src[i] == ';' )
        {
            return false; // a declaration / typedef alias, not a body
        }
        ++i;
    }
    if( i >= limit || src[i] != '{' )
    {
        return false;
    }

    const std::size_t end = matchBracket( src, i, '{', '}' );
    if( end == std::string_view::npos )
    {
        return false;
    }

    const std::string_view head = src.substr( from, i - from );

    // §P6.11: an `enum class X {`/`enum struct X {` head contains the word "class"/"struct" too — checked
    // BEFORE the aggregate acceptance test below, or a scoped enum is silently accepted as a zero-field
    // struct/class and degrades to a confident modeled="1" size="1" instead of refusing. A bare `enum X {`
    // head already fails the test below (no struct/class/union word at all); flagged here too so the
    // caller gets the specific "this is an enum" refusal instead of the generic "no aggregate body" one.
    if( containsWord( head, "enum" ) ) { out.isEnum = true; return false; }

    if( !containsWord( head, "struct" ) && !containsWord( head, "class" ) && !containsWord( head, "union" ) )
    {
        return false;
    }
    if( !containsWord( head, name ) )
    {
        // The ANONYMOUS-with-typedef idiom `typedef struct { … } PointLight;` — the name is not in the head
        // at all, it is on the far side of the closing brace. Common in GPU headers, so it is accepted
        // when (and only when) the head really is a bare `typedef struct` and the trailing declarator
        // before the `;` really is this name. Anything else means the brace belongs to something else.
        if( !containsWord( head, "typedef" ) )
        {
            return false;
        }
        const std::size_t      semi = src.find( ';', end );
        if( semi == std::string_view::npos )
        {
            return false;
        }
        const std::string_view tail = src.substr( end, semi - end );
        if( !containsWord( tail, name ) )
        {
            return false;
        }
    }

    out.headStart  = from;
    out.braceStart = i;
    out.braceEnd   = end;
    return true;
}

// ── declaration parsing ──────────────────────────────────────────────────────────────────────────────

// Split `stmt` on TOP-LEVEL commas (outside (), [], <> and any inert run): `float a, b;` is two fields,
// `Map<int, float> m;` is one.
inline std::vector<std::string_view> splitDeclarators( std::string_view stmt )
{
    std::vector<std::string_view> out;
    int         paren = 0, square = 0, angle = 0;
    std::size_t start = 0;
    for( std::size_t i = 0; i < stmt.size(); )
    {
        const std::size_t skipped = skipInert( stmt, i );
        if( skipped != i ) { i = skipped; continue; }
        const char c = stmt[i];
        if( c == '(' )
        {
            ++paren;
        }
        else if( c == ')' )
        {
            --paren;
        }
        else if( c == '[' )
        {
            ++square;
        }
        else if( c == ']' )
        {
            --square;
        }
        else if( c == '<' )
        {
            ++angle;
        }
        else if( c == '>' && angle > 0 )
        {
            --angle;
        }
        else if( c == ',' && paren == 0 && square == 0 && angle == 0 )
        {
            out.push_back( stmt.substr( start, i - start ) );
            start = i + 1;
        }
        ++i;
    }
    out.push_back( stmt.substr( start ) );
    return out;
}

// The parsed shape of ONE declarator, before any type resolution.
struct Declarator
{
    std::string_view              typeSpec;        // everything left of the name, AS WRITTEN (`char *`, `char*`, `int *const`)
    std::string_view              baseSpec;        // typeSpec up to its first top-level `*`/`&` (`char`); empty on a
                                                   // follow-on declarator, which inherits the first one's base
    std::string_view              declPart;        // typeSpec from that `*`/`&` on (`*`, `**`, `*const`); "" for a plain one
    std::string_view              name;
    std::vector<std::string_view> extents;         // one entry per `[…]`, left to right
    std::vector<std::string_view> attrGroups;      // A3: peeled `__attribute__((…))` inner text, source order
    bool                          isPointer  = false;
    bool                          isRef      = false;
    bool                          isBitfield = false;
    std::string_view              bitWidth;        // a bitfield's width expression (`1`, `WIDTH`), initializer cut off
    bool                          ok         = false;
};

// Cut `s` at the first TOP-LEVEL occurrence of any byte in `stops` (never inside a comment/literal, and
// never at a `::`), reporting whether a cut happened. The two declarator prefixes — a bitfield's `:` width
// and a default member initializer's `=`/`{` — are the same scan with a different stop set.
inline bool cutAtTopLevel( std::string_view& s, std::string_view stops )
{
    for( std::size_t i = 0; i < s.size(); ++i )
    {
        const std::size_t skipped = skipInert( s, i );
        if( skipped != i ) { i = ( skipped > 0 ) ? skipped - 1 : 0; continue; }
        if( stops.find( s[i] ) == std::string_view::npos )
        {
            continue;
        }
        if( s[i] == ':' && ( ( i + 1 < s.size() && s[ i + 1 ] == ':' ) || ( i > 0 && s[ i - 1 ] == ':' ) ) ) { ++i; continue; }
        s = trimView( s.substr( 0, i ) );
        return true;
    }
    return false;
}

// `s` with the CONTENTS of every string literal, character literal and comment blanked to spaces — same length, the
// delimiters kept. The attribute scans below read this mask and slice the ORIGINAL at the same offsets, so an argument
// such as `deprecated( ")" )` cannot unbalance a group and `deprecated( "packed" )` cannot spell a layout keyword
// (CodeRabbit on #281, test/layoutcheck.sh AttributeString*Case). An unterminated literal blanks to the end.
inline std::string lexicalMask( std::string_view s )
{
    std::string mask( s );
    for( std::size_t i = 0; i < mask.size(); ++i )
    {
        const char c = mask[i];
        if( c == '"' || c == '\'' )
        {
            for( ++i; i < mask.size() && mask[i] != c; ++i )
            {
                if( mask[i] == '\\' && i + 1 < mask.size() )
                {
                    mask[i++] = ' ';   // the escape and the byte it escapes are both content
                }
                mask[i] = ' ';
            }
        }
        else if( c == '/' && i + 1 < mask.size() && ( mask[ i + 1 ] == '/' || mask[ i + 1 ] == '*' ) )
        {
            const bool line = mask[ i + 1 ] == '/';
            for( i += 2; i < mask.size() && !( line ? mask[i] == '\n' : ( mask[i] == '*' && i + 1 < mask.size() && mask[ i + 1 ] == '/' ) ); ++i )
            {
                mask[i] = ' ';
            }
            i += line ? 0 : 1;   // leave a block comment's `*/` in place
        }
    }
    return mask;
}

// A3 (found-items 2026-09-17): peel trailing `__attribute__((…))` groups off the RIGHT of `s` — GNU/GCC
// postfix attribute syntax, placed after the declarator name or (per the standard grammar) after its array
// extents. `int x __attribute__((aligned(8)))` used to reach parseDeclarator's last-identifier scan with the
// attribute still attached: the scan took "8" (the last identifier-looking token before the attribute's own
// closing parens) as the field NAME and left `)))` as unparsed trailing junk, so `d.ok` came back false and
// the whole declaration was refused as "unparsed-member" with no `<f n="x">` row at all — candidateParen
// already keeps `__attribute__(( … ))` from being misread as a member-function's parameter list (see its own
// comment above), but nothing removed the group before the name/type split ran. Mirrors peelExtents: balanced
// parens, returns the peeled groups' INNER text (the attribute-list bytes between the doubled parens, e.g.
// "aligned(8)") in source order, so the caller can tell an attribute that changes layout (aligned/packed)
// from one that is purely a hint (deprecated/unused/…) and does not need to touch modeled= at all.
inline std::vector<std::string_view> peelAttributeGroups( std::string_view& s )
{
    static constexpr std::string_view kAttr = "__attribute__";
    std::vector<std::string_view>     reversed;
    for( ;; )
    {
        s = trimView( s );
        const std::string mask = lexicalMask( s );   // parens and the keyword are read here; slices come from `s`
        if( mask.empty() || mask.back() != ')' )
        {
            break;
        }
        int         depth = 0;
        std::size_t open  = std::string_view::npos;
        // Cursor counts down to 1, index = cursor - 1: the `i-- > 0` idiom wraps the unsigned to SIZE_MAX when no
        // `(` balances the trailing `)` (`int b );`), which G1's -fsanitize=integer aborts on (abicheck arm 11).
        for( std::size_t cursor = mask.size(); cursor > 0; --cursor )
        {
            const std::size_t i = cursor - 1;
            if( mask[i] == ')' )      { ++depth; }
            else if( mask[i] == '(' ) { --depth; if( depth == 0 ) { open = i; break; } }
        }
        if( open == std::string_view::npos )
        {
            break; // unbalanced — degrade rather than misclassify (same rule matchBracket's callers use)
        }
        const std::string_view before = trimView( s.substr( 0, open ) );
        if( !trimView( std::string_view( mask ).substr( 0, open ) ).ends_with( kAttr ) )
        {
            break; // the trailing (...) group is not an attribute specifier — leave it for the caller
        }
        std::string_view inner = trimView( s.substr( open + 1, s.size() - open - 2 ) );
        if( inner.size() >= 2 && inner.front() == '(' && inner.back() == ')' )
        {
            inner = trimView( inner.substr( 1, inner.size() - 2 ) ); // the doubled-paren wrapper `((…))`
        }
        reversed.push_back( inner );
        s = trimView( before.substr( 0, before.size() - kAttr.size() ) );
    }
    return { reversed.rbegin(), reversed.rend() };
}

// A3 (review round, found-items 2026-09-17): a GNU attribute keyword may be spelled bare (`aligned`) OR
// wrapped in the reserved-namespace double underscore (`__aligned__` — what system headers reach for so
// the name cannot collide with a macro of the same bare word); the two spell the SAME attribute, but
// `containsWord` alone cannot see it: `_` counts as an identifier byte, so the underscores that correctly
// wall "aligned" off from a longer word are exactly what makes `__aligned__` fail to match at all. Checked
// as two containsWord calls (the bare spelling, then the wrapped one) rather than a hand-rolled tokenizer:
// a fresh identifier-scanning loop here duplicated gitoracle.h::forEachIdentifier closely enough that
// quality-delta gated on it (found-items 2026-09-17 review round) — two bounded word checks reuse the
// primitive layout.h already leans on everywhere else (static/virtual/operator, above) instead of
// re-deriving a general tokenizer for a two-keyword, fixed-alphabet job.
inline bool attrHasKeyword( std::string_view attr, std::string_view bare ) noexcept
{
    const std::string code = lexicalMask( attr );   // a keyword spelled inside a string argument is not the keyword
    if( containsWord( code, bare ) )
    {
        return true;
    }
    std::string wrapped;
    wrapped.reserve( bare.size() + 4 );
    wrapped += "__";
    wrapped += bare;
    wrapped += "__";
    return containsWord( code, wrapped );
}

// Peel trailing array extents off the RIGHT of `s`: `slots[ 4 ][ 2 ]` → {"4","2"}, leaving `Slot slots`.
inline std::vector<std::string_view> peelExtents( std::string_view& s )
{
    std::vector<std::string_view> reversed;
    for( ;; )
    {
        s = trimView( s );
        if( s.empty() || s.back() != ']' )
        {
            break;
        }
        int         depth = 0;
        std::size_t open  = std::string_view::npos;
        for( std::size_t cursor = s.size(); cursor > 0; --cursor )   // cursors, not `i-- > 0`: an unbalanced `]` wrapped it
        {
            const std::size_t i = cursor - 1;
            if( s[i] == ']' )
            {
                ++depth;
            }
            else if( s[i] == '[' )
            {
                --depth;
                if( depth == 0 )
                {
                    open = i;
                    break;
                }
            }
        }
        if( open == std::string_view::npos )
        {
            break;
        }
        reversed.push_back( trimView( s.substr( open + 1, s.size() - open - 2 ) ) );
        s = s.substr( 0, open );
    }
    return { reversed.rbegin(), reversed.rend() };
}

// The first `*` or `&` of `spec` outside any `<…>` / `(…)` / `[…]`, or spec.size() when there is none.
inline std::size_t topLevelDeclaratorMark( std::string_view spec )
{
    int depth = 0;
    for( std::size_t i = 0; i < spec.size(); ++i )
    {
        const char c = spec[i];
        if( c == '<' || c == '(' || c == '[' )
        {
            ++depth;
        }
        else if( ( c == '>' || c == ')' || c == ']' ) && depth > 0 )
        {
            --depth;
        }
        else if( depth == 0 && ( c == '*' || c == '&' ) )
        {
            return i;
        }
    }
    return spec.size();
}

inline Declarator parseDeclarator( std::string_view text )
{
    Declarator       d;
    std::string_view s = trimView( text );
    if( s.empty() )
    {
        return d;
    }

    const std::string_view whole = s;
    std::string_view       beforeInit = s;
    cutAtTopLevel( beforeInit, "={" );             // a `:` is a bitfield width only BEFORE the first top-level `=`/`{`: in
    std::string_view declPart = beforeInit;        // `std::uint8_t c = f ? 2 : 1;` it is a ternary's (CodeRabbit 4544554334)
    d.isBitfield = cutAtTopLevel( declPart, ":" ); // a bitfield WIDTH — `s` keeps the declarator, the width is kept aside
    if( d.isBitfield )
    {
        s = declPart;
        const std::size_t colon = whole.find( ':', s.size() );
        std::string_view  width = ( colon == std::string_view::npos ) ? std::string_view() : whole.substr( colon + 1 );
        cutAtTopLevel( width, "={" );              // C++20 `std::uint8_t a : 1 = 0;`
        d.bitWidth = trimView( width );
    }
    cutAtTopLevel( s, "={" );                      // a default member initializer (`= 0`, `= {}`, `{0}`)
    if( s.empty() )
    {
        return d;
    }

    // A3: peel a trailing `__attribute__((…))` BEFORE the array extents — the standard grammar (and this
    // fixture's own `int x[4] __attribute__((packed));` shape) places the attribute AFTER any array bounds,
    // so it must come off first for peelExtents below to still find `]` at the end of `s`.
    d.attrGroups = peelAttributeGroups( s );
    if( s.empty() )
    {
        return d;
    }

    d.extents = peelExtents( s );
    s = trimView( s );
    if( s.empty() )
    {
        return d;
    }

    // The name is the LAST identifier; everything to its left is the type spec, and any `*` / `&` between
    // the two makes THIS declarator a pointer/reference whatever the shared base type is.
    std::size_t nameEnd = s.size();
    while( nameEnd > 0 && !identByte( (unsigned char)s[nameEnd - 1] ) )
    {
        --nameEnd;
    }
    std::size_t nameStart = nameEnd;
    while( nameStart > 0 && identByte( (unsigned char)s[nameStart - 1] ) )
    {
        --nameStart;
    }
    if( nameStart == nameEnd )
    {
        return d;
    }

    const std::string_view tail = trimView( s.substr( nameEnd ) );
    if( !tail.empty() && tail != "*" && tail != "&" )
    {
        return d; // trailing junk ⇒ not a plain field
    }

    d.name     = s.substr( nameStart, nameEnd - nameStart );
    d.typeSpec = trimView( s.substr( 0, nameStart ) );
    // Only a TOP-LEVEL `*`/`&` makes this declarator a pointer/reference: the one in `std::vector<int*> v` or
    // `Fn<void(int&)> f` belongs to a template argument. The first such byte splits the written type into the
    // shared BASE (`char` in `char *a, b;`) and this declarator's own part (`*`), so a follow-on `b` is a plain
    // `char` and the label never repeats a `*` the source wrote once (LAYOUT-PTR-STAR, 2026-11-11).
    const std::size_t declAt = topLevelDeclaratorMark( d.typeSpec );
    d.baseSpec = trimView( d.typeSpec.substr( 0, declAt ) );
    d.declPart = ( declAt < d.typeSpec.size() ) ? trimView( d.typeSpec.substr( declAt ) ) : std::string_view();
    for( char c : d.declPart )
    {
        if( c == '*' )
        {
            d.isPointer = true;
        }
        if( c == '&' )
        {
            d.isRef = true;
        }
    }
    if( tail == "*" )
    {
        d.isPointer = true;
    }
    if( tail == "&" )
    {
        d.isRef = true;
    }
    // An EMPTY typeSpec is fine here and only here: a follow-on declarator in `uint16_t x, y, z, w;`
    // inherits the first one's type. modelStatement is what rejects an empty type on declarator 0.
    d.ok = true;
    return d;
}

// `spec` without its leading/trailing cv-qualifiers and `typename`: what names the TYPE.
inline std::string_view withoutCv( std::string_view spec )
{
    static constexpr std::string_view kLead[] = { "const", "volatile", "mutable", "typename", "constexpr" };
    for( bool again = true; again; )
    {
        again = false;
        spec  = trimView( spec );
        for( std::string_view w : kLead )
        {
            if( spec.starts_with( w ) && spec.size() > w.size() && !identByte( (unsigned char)spec[ w.size() ] ) )
            {
                spec  = spec.substr( w.size() );
                again = true;
            }
            if( spec.ends_with( w ) && spec.size() > w.size() && !identByte( (unsigned char)spec[ spec.size() - w.size() - 1 ] ) )
            {
                spec  = spec.substr( 0, spec.size() - w.size() );
                again = true;
            }
        }
    }
    return spec;
}

// `name<a, b>` → name and its top-level arguments (none for a plain name). False when anything follows the closing `>`
// or the brackets do not balance: that is not one template-id.
struct TemplateId
{
    std::string_view              name;
    std::vector<std::string_view> args;
    bool                          hasArgs = false;
};

inline bool splitTemplateId( std::string_view spec, TemplateId& out )
{
    spec                   = trimView( spec );
    const std::size_t open = spec.find( '<' );
    if( open == std::string_view::npos )
    {
        out.name = spec;
        return !spec.empty();
    }
    const std::size_t close = matchBracket( spec, open, '<', '>' );
    if( close == std::string_view::npos || !trimView( spec.substr( close ) ).empty() )
    {
        return false;
    }
    out.name    = trimView( spec.substr( 0, open ) );
    out.hasArgs = true;
    for( std::string_view a : splitDeclarators( spec.substr( open + 1, close - open - 2 ) ) )
    {
        out.args.push_back( trimView( a ) );
    }
    return !out.name.empty();
}

// ── the modeller ─────────────────────────────────────────────────────────────────────────────────────

// One index-wide lookup: name → the indexed Struct/Class/Interface symbols carrying it. Built once per
// --layout run (one linear pass over ing.symbols) and reused by the nested-type resolver, which would
// otherwise rescan every symbol per field.
using AggIndex = gtl::btree_map<std::string, std::vector<NodeId>>;

inline AggIndex buildAggIndex( const IngestResult& ing )
{
    AggIndex byName;
    for( const Symbol& s : ing.symbols )
    {
        if( isStructOrNamedType( s.kind ) || s.kind == SymKind::Class || s.kind == SymKind::Interface )
        {
            byName[ s.name ].push_back( s.id );
        }
    }
    return byName;
}

// Everything the modeller needs that it does not own. `bytes` / `consts` are indexed DIRECTLY by fileId
// (never a node-based map): the modeller holds a `const std::string&` into this cache across recursion,
// and a btree_map promises no reference stability across the inserts that recursion performs.
struct ModelCtx
{
    const IngestResult&      ing;
    const AggIndex&          byName;
    std::vector<std::string> bytes;         // fileId → file text ("" = absent/unreadable/oversized)
    std::vector<std::string> stripped;      // fileId → the same text with comments blanked
    std::vector<ConstTable>  consts;        // fileId → its constant/alias table (built from `stripped`)
    std::vector<char>        bytesLoaded;   // one flag for all three — ensureFileLoaded fills them together
    std::vector<std::string> inProgress;    // cycle guard: the aggregate names currently being sized
    std::size_t              depth = 0;
    // A type alias defined in ANOTHER file (`using InternedText = InternedTextOf<RefNames>;` in refnames.h, used in
    // model.h): name → the C-family files whose index holds an alias symbol of that name. Built on first use.
    gtl::btree_map<std::string, std::vector<std::uint32_t>> aliasFiles;
    bool                     aliasFilesBuilt   = false;
    std::vector<std::string> templateParams;    // while sizing an in-repo class template: its parameter names (never sized)
    bool                     allowTemplateHead = false;   // …and its `template <…>` head is not a refusal
    bool                     stdTableUsed      = false;   // a std:: table row sized something (std_abi= on the answer)
    // LAYOUT-EBO-NESTED: an in-repo aggregate's name → the type names of the subobjects at its offset 0 (its base, its first
    // member, and theirs, recursively). Filled as sizeNestedAggregate models a definition; read by the empty-base rule.
    gtl::btree_map<std::string, std::vector<std::string>> zeroOffsetTypes;

    explicit ModelCtx( const IngestResult& i, const AggIndex& n )
        : ing( i ), byName( n ), bytes( i.files.size() ), stripped( i.files.size() ),
          consts( i.files.size() ), bytesLoaded( i.files.size(), 0 ) {}
};

// Does `expr` (an array extent, a bitfield width, a std::array bound) name a parameter of the class template being sized? Its
// value is the template ARGUMENT's, which the model never reads, so a same-named file constant must not stand in for it
// (CodeRabbit 4544554342: `template <std::size_t N> struct Buf { char data[N]; };` beside `constexpr std::size_t N = 16;`).
inline bool namesTemplateParam( const ModelCtx& ctx, std::string_view expr )
{
    const auto& params = ctx.templateParams;
    for( std::size_t i = 0; i < expr.size() && !params.empty(); )
    {
        if( !identByte( (unsigned char)expr[i] ) )
        {
            ++i;
            continue;
        }
        std::size_t e = i;
        while( e < expr.size() && identByte( (unsigned char)expr[e] ) )
        {
            ++e;
        }
        if( std::find( params.begin(), params.end(), expr.substr( i, e - i ) ) != params.end() )
        {
            return true;
        }
        i = e;
    }
    return false;
}

// ONE lazy load per file, feeding all three views: the raw bytes, the comment-blanked text, and the
// constant/alias table harvested from it. The three accessors below are pure lookups so none of them
// carries a second copy of the load-once dance.
inline bool ensureFileLoaded( ModelCtx& ctx, std::uint32_t fileId )
{
    if( fileId >= ctx.bytes.size() )
    {
        return false;
    }
    if( !ctx.bytesLoaded[ fileId ] )
    {
        ctx.bytesLoaded[ fileId ] = 1;
        ctx.bytes[fileId] = darkflags::readWhole( diskPath( ctx.ing, fileId ) ).value_or( std::string() );
        ctx.stripped[ fileId ] = withoutComments( ctx.bytes[ fileId ] );
        ctx.consts[ fileId ]   = harvestConstants( ctx.stripped[ fileId ] );
    }
    return true;
}

inline const std::string& fileBytes( ModelCtx& ctx, std::uint32_t fileId )
{
    static const std::string kEmpty;
    return ensureFileLoaded( ctx, fileId ) ? ctx.bytes[ fileId ] : kEmpty;
}

// The file with every comment blanked. Both the constant harvest and the `#pragma pack` probe read THIS,
// never the raw bytes: a header whose prose merely MENTIONS `#pragma pack` (this module's own fixture does)
// must not be treated as containing the directive.
inline const std::string& fileStripped( ModelCtx& ctx, std::uint32_t fileId )
{
    static const std::string kEmpty;
    return ensureFileLoaded( ctx, fileId ) ? ctx.stripped[ fileId ] : kEmpty;
}

inline const ConstTable& fileConsts( ModelCtx& ctx, std::uint32_t fileId )
{
    static const ConstTable kEmpty;
    return ensureFileLoaded( ctx, fileId ) ? ctx.consts[ fileId ] : kEmpty;
}

inline LayoutDef modelDef( ModelCtx& ctx, std::uint32_t fileId, const DefSite& site, std::string_view name );

// Size a nested user-defined aggregate BY NAME: model its definition(s) and accept the answer only when
// every definition in the index agrees. A type whose own mirrors disagree cannot size the field that
// holds it — that IS the bug, and a number here would hide it one level down.
// The parameter names of the `template <…>` that introduces the definition at site.headStart — read from the head itself
// or from just before it (the index's def byte may sit on either the `template` or the `class` keyword).
inline std::vector<std::string> templateParamsAt( std::string_view src, const DefSite& site )
{
    std::vector<std::string> out;
    std::string_view         head = src.substr( site.headStart, site.braceStart - site.headStart );
    std::size_t              open = std::string_view::npos;
    std::string_view         text;
    const std::size_t        kw   = head.find( "template" );
    if( kw != std::string_view::npos )
    {
        open = head.find( '<', kw );
        text = head;
    }
    else
    {
        std::size_t back = site.headStart;
        while( back > 0 && std::isspace( (unsigned char)src[back - 1] ) != 0 )
        {
            --back;
        }
        if( back == 0 || src[back - 1] != '>' )
        {
            return out;
        }
        int depth = 0;
        for( std::size_t cursor = back; cursor > 0; --cursor )   // cursors, not `i-- > 0` (the sanitizer rule above)
        {
            const char c = src[cursor - 1];
            depth += ( c == '>' ) ? 1 : ( c == '<' ) ? -1 : 0;
            if( depth == 0 )
            {
                open = cursor - 1;
                break;
            }
        }
        if( open == std::string_view::npos || !trimView( src.substr( 0, open ) ).ends_with( "template" ) )
        {
            return out;
        }
        text = src;
    }
    if( open == std::string_view::npos )
    {
        return out;
    }
    const std::size_t close = matchBracket( text, open, '<', '>' );
    if( close == std::string_view::npos )
    {
        return out;
    }
    for( std::string_view param : splitDeclarators( text.substr( open + 1, close - open - 2 ) ) )
    {
        cutAtTopLevel( param, "=" );                                   // a default argument
        param = trimView( param );
        std::size_t e = param.size();
        while( e > 0 && !identByte( (unsigned char)param[e - 1] ) ) { --e; }
        std::size_t b = e;
        while( b > 0 && identByte( (unsigned char)param[b - 1] ) ) { --b; }
        if( b < e )
        {
            out.emplace_back( param.substr( b, e - b ) );
        }
    }
    return out;
}

// Model a nested definition. A class template is sized only when no member depends on its parameters
// (InternedTextOf<Domain> is a 4 B id whatever Domain is): the parameter names are fenced off for the body walk, and its
// `template` head is allowed. A non-template sees an empty fence, never its enclosing template's.
inline LayoutDef modelNestedDef( ModelCtx& ctx, std::uint32_t fileId, const DefSite& site, std::string_view typeName, bool templateId )
{
    std::vector<std::string> params = templateId ? templateParamsAt( fileBytes( ctx, fileId ), site ) : std::vector<std::string>();
    std::swap( ctx.templateParams, params );
    const bool allowWas   = ctx.allowTemplateHead;
    ctx.allowTemplateHead = templateId;
    LayoutDef d           = modelDef( ctx, fileId, site, typeName );
    ctx.allowTemplateHead = allowWas;
    std::swap( ctx.templateParams, params );
    return d;
}

// The subobject types at offset 0 of a modelled definition (LAYOUT-EBO-NESTED, CodeRabbit #630): its base (always at 0) and, when
// placed at 0 by value, its first member — each with the types already recorded for it, so the chain is transitive.
inline void recordZeroOffsetTypes( ModelCtx& ctx, std::string_view typeName, const LayoutDef& d )
{
    std::vector<std::string> at0;
    const auto add = [ & ]( std::string_view spec )
    {
        const std::string name( lastSegment( withoutCv( spec ) ) );
        at0.push_back( name );
        if( const auto it = ctx.zeroOffsetTypes.find( name ); it != ctx.zeroOffsetTypes.end() )
        {
            at0.insert( at0.end(), it->second.begin(), it->second.end() );
        }
    };
    if( !d.baseSpec.empty() )
    {
        add( d.baseSpec );
    }
    if( !d.fields.empty() && d.fields.front().placed && d.fields.front().offset == 0
        && d.fields.front().type.find_first_of( "*&" ) == std::string::npos )
    {
        add( d.fields.front().type );
    }
    if( !at0.empty() )
    {
        ctx.zeroOffsetTypes.emplace( std::string( typeName ), std::move( at0 ) );
    }
}

inline TypeSize sizeNestedAggregate( ModelCtx& ctx, std::string_view typeName, std::uint32_t preferFileId, std::string& note,
                                     bool templateId = false )
{
    TypeSize out;
    if( ctx.depth >= kMaxNestDepth ) { note = "nest-depth"; return out; }
    for( const std::string& active : ctx.inProgress )
    {
        if( active == typeName ) { note = "recursive-type"; return out; }
    }

    const auto it = ctx.byName.find( std::string( typeName ) );
    if( it == ctx.byName.end() )
    {
        return out;
    }

    // Prefer a definition in the SAME file (the dual-compile header's own slot type), so a same-file
    // reader and this model compute the same number.
    std::vector<NodeId> order = it->second;
    std::stable_sort( order.begin(), order.end(), [ & ]( NodeId a, NodeId b )
    {
        const bool sa = ctx.ing.symbols[a].fileId == preferFileId, sb = ctx.ing.symbols[b].fileId == preferFileId;
        return ( sa != sb ) ? sa : ( a < b );
    } );

    ctx.inProgress.emplace_back( typeName );
    ++ctx.depth;
    bool                                first = true;
    gtl::btree_map<std::uint64_t, bool> seenSite;                      // dedupe the typedef-alias twin
    for( NodeId id : order )
    {
        const Symbol& s = ctx.ing.symbols[ id ];
        if( !isCFamilyPath( ctx.ing.files[s.fileId] ) )
        {
            continue; // only a C-family aggregate has a byte layout
        }
        DefSite       site;
        {
            const std::string& src = fileBytes( ctx, s.fileId );
            if( src.empty() || !findDefBody( src, typeName, s.sigStartByte, site ) )
            {
                continue;
            }
        }
        site.fileId = s.fileId;
        const std::uint64_t key = ( std::uint64_t( s.fileId ) << 32 ) | std::uint64_t( site.braceStart & 0xFFFFFFFFull );
        if( seenSite.find( key ) != seenSite.end() )
        {
            continue;
        }
        seenSite.emplace( key, true );

        const LayoutDef d = modelNestedDef( ctx, s.fileId, site, typeName, templateId );
        if( !d.modeled ) { note = "nested-unmodelled"; out = TypeSize{}; break; }
        // empty: no member, and no base or one the model placed at 0 B (`struct M : E {};`, CodeRabbit 4544554347)
        const bool     emptyAgg = d.fields.empty() && ( d.baseSpec.empty() || ( d.baseSized && d.baseSize == 0 ) );
        const TypeSize here{ d.size, d.align, true, d.tailPad, emptyAgg };
        if( first ) { recordZeroOffsetTypes( ctx, typeName, d ); out = here; first = false; }
        else if( here.size != out.size || here.align != out.align ) { note = "nested-mirrors-disagree"; out = TypeSize{}; break; }
    }
    --ctx.depth;
    ctx.inProgress.pop_back();
    return out;
}

// Where a type spelling is being resolved: the corpus, the DEFINING FILE's constant/alias table, and that
// file's id (the "prefer a same-file nested definition" tiebreak). One parameter instead of three.
struct TypeScope
{
    ModelCtx&         ctx;
    const ConstTable& consts;
    std::uint32_t     fileId;
};

// What resolution produced: the numbers, the expansion (when a macro/alias changed the spelling, so the
// report can show `AAPL_HALF_SCALAR -> __fp16` rather than leaving the reader to grep), and the caveat kind
// to record. A structured return, per the house rule, instead of two out-params.
struct ResolvedType
{
    TypeSize    size;
    std::string resolved;
    std::string note;
};

// The object-like-macro / type-alias lane: every definition of the name must resolve to the SAME size, or
// the field is honestly unknown. This is the dual-compile idiom (`half` on one side, `__fp16` on the other).
inline ResolvedType resolveFieldType( const TypeScope& scope, std::string_view spec, bool isPointer, bool isRef,
                                      std::size_t macroDepth = 0 );

inline bool resolveThroughAlias( const TypeScope& scope, std::string_view single, std::size_t macroDepth, ResolvedType& out )
{
    if( macroDepth >= kMaxMacroDepth )
    {
        return false;
    }
    const auto m = scope.consts.find( std::string( single ) );
    if( m == scope.consts.end() || m->second.empty() )
    {
        return false;
    }

    bool        first = true;
    TypeSize    agreed;
    std::string firstSpelling;
    for( const std::string& replacement : m->second )
    {
        const ResolvedType inner = resolveFieldType( scope, replacement, false, false, macroDepth + 1 );
        if( !inner.size.known )
        {
            return false;
        }
        if( first ) { agreed = inner.size; firstSpelling = replacement; first = false; }
        else if( inner.size.size != agreed.size || inner.size.align != agreed.align )
        { out.note = "macro-type-ambiguous"; return false; }
    }
    out.size     = agreed;
    out.resolved = firstSpelling;
    return agreed.known;
}

// One template ARGUMENT as a type: a top-level `*`/`&` makes it a pointer (`std::vector<int*>`'s element), anything else
// resolves like a member type one level deeper (the depth bound is shared with alias expansion).
inline ResolvedType resolveTypeArg( const TypeScope& scope, std::string_view arg, std::size_t depth )
{
    ResolvedType out;
    if( depth + 1 >= kMaxMacroDepth )
    {
        out.note = "nest-depth";
        return out;
    }
    if( topLevelDeclaratorMark( arg ) < arg.size() )
    {
        out.size = TypeSize{ 8, 8, true };
        return out;
    }
    return resolveFieldType( scope, arg, false, false, depth + 1 );
}

inline std::uint32_t roundUpTo( std::uint32_t v, std::uint32_t align ) noexcept
{
    return ( align == 0 ) ? v : ( v + align - 1 ) / align * align;
}

// An argument that did not size hands its reason up; a bare failure is an unknown type.
inline void failFromArg( ResolvedType& out, const ResolvedType& arg )
{
    out.size = TypeSize{};
    out.note = arg.note.empty() ? std::string( "unknown-type" ) : arg.note;
}

// The std:: lane. `rest` is the spelling after `std::`. Returns false for a plain std scalar (`std::uint32_t`, `std::size_t`)
// so the generic primitive path takes it; true when this lane decided, sized or refused (a note says which).
inline bool resolveStdType( const TypeScope& scope, std::string_view rest, std::size_t depth, ResolvedType& out )
{
    TemplateId id;
    if( !splitTemplateId( rest, id ) )
    {
        out.note = "compound-type";
        return true;
    }
    if( kStdAbi.empty() )
    {
        if( id.hasArgs || id.name == "string" || id.name == "string_view" )
        {
            out.note = "std-unlisted";
            return true;
        }
        return false;
    }
    const auto sized = [ & ]( std::uint32_t size, std::uint32_t align )
    {
        out.size                = TypeSize{ size, align, true };
        scope.ctx.stdTableUsed = true;
        return true;
    };
    if( !id.hasArgs && id.name == "string" )
    {
        return sized( kStdStringSize, kStdStringAlign );
    }
    for( const StdFixedType& row : kStdFixedTable )
    {
        if( row.name != id.name )
        {
            continue;
        }
        // LAYOUT-DEPENDENT-NAMES (CodeRabbit #630): vector<T> of a template parameter may be vector<bool> (40 B on libstdc++)
        if( id.name == "vector" && !id.args.empty() && namesTemplateParam( scope.ctx, id.args.front() ) )
        {
            out.note = "template-param";
            return true;
        }
        const bool boolVector = id.name == "vector" && !id.args.empty() && withoutCv( id.args.front() ) == "bool";
        if( row.args != id.args.size() || boolVector )
        {
            out.note = "std-unlisted";   // a custom allocator/deleter, or vector<bool>'s own specialisation
            return true;
        }
        return sized( row.size, row.align );
    }
    if( !id.hasArgs )
    {
        return false;                    // std::uint32_t, std::size_t, … — the primitive table's
    }
    if( id.name == "optional" && id.args.size() == 1 )
    {
        const ResolvedType t = resolveTypeArg( scope, id.args[0], depth );
        if( !t.size.known ) { failFromArg( out, t ); return true; }
        return sized( roundUpTo( t.size.size + 1, t.size.align ), t.size.align );   // the value, then the engaged flag
    }
    if( id.name == "array" && id.args.size() == 2 )
    {
        const ResolvedType t = resolveTypeArg( scope, id.args[0], depth );
        if( !t.size.known ) { failFromArg( out, t ); return true; }
        std::uint32_t n = 0;
        if( namesTemplateParam( scope.ctx, id.args[1] ) )
        {
            out.note = "template-param";   // the bound is the template argument's
            return true;
        }
        if( !evalExtent( scope.consts, id.args[1], n ) || n == 0 || n > kMaxArrayElems / std::max( t.size.size, 1u ) )
        {
            out.note = "unknown-extent";
            return true;
        }
        return sized( t.size.size * n, t.size.align );
    }
    if( id.name == "span" && ( id.args.size() == 1 || id.args.size() == 2 ) )
    {
        if( id.args.size() == 1 || id.args[1] == "dynamic_extent" || id.args[1] == "std::dynamic_extent" )
        {
            return sized( 16, 8 );       // pointer + size
        }
        if( namesTemplateParam( scope.ctx, id.args[1] ) )
        {
            out.note = "template-param";   // the bound is the template argument's, not a same-named file constant (CodeRabbit #630)
            return true;
        }
        std::uint32_t n = 0;
        if( !evalExtent( scope.consts, id.args[1], n ) )
        {
            out.note = "unknown-extent";
            return true;
        }
        return sized( 8, 8 );            // a static extent keeps only the pointer
    }
    if( id.name == "pair" && id.args.size() == 2 )
    {
        const ResolvedType a = resolveTypeArg( scope, id.args[0], depth );
        const ResolvedType b = resolveTypeArg( scope, id.args[1], depth );
        if( !a.size.known ) { failFromArg( out, a ); return true; }
        if( !b.size.known ) { failFromArg( out, b ); return true; }
        const std::uint32_t align = std::max( a.size.align, b.size.align );
        return sized( roundUpTo( roundUpTo( a.size.size, b.size.align ) + b.size.size, align ), align );   // { first; second; }
    }
    out.note = "std-unlisted";
    return true;
}

// The C-family files holding an indexed type alias named `name` (built once per run, on first use).
inline const std::vector<std::uint32_t>* aliasFilesFor( ModelCtx& ctx, std::string_view name )
{
    if( !ctx.aliasFilesBuilt )
    {
        ctx.aliasFilesBuilt = true;
        for( const Symbol& sym : ctx.ing.symbols )
        {
            if( sym.kind != SymKind::Alias || sym.fileId >= ctx.ing.files.size() || !isCFamilyPath( ctx.ing.files[ sym.fileId ] ) )
            {
                continue;
            }
            std::vector<std::uint32_t>& files = ctx.aliasFiles[ std::string( sym.name ) ];
            if( std::find( files.begin(), files.end(), sym.fileId ) == files.end() )
            {
                files.push_back( sym.fileId );
            }
        }
    }
    const auto it = ctx.aliasFiles.find( std::string( name ) );
    return ( it == ctx.aliasFiles.end() ) ? nullptr : &it->second;
}

// An alias defined in ANOTHER indexed file: resolved in THAT file's scope (its own constants and aliases), and accepted
// only when every file defining the name agrees on the size — the same rule the same-file alias lane applies.
inline bool resolveCrossFileAlias( const TypeScope& scope, std::string_view single, std::size_t depth, ResolvedType& out )
{
    for( std::string_view probe : { single, lastSegment( single ) } )
    {
        const std::vector<std::uint32_t>* files = aliasFilesFor( scope.ctx, probe );
        if( files == nullptr )
        {
            continue;
        }
        bool         first = true;
        ResolvedType agreed;
        for( std::uint32_t fileId : *files )
        {
            if( fileId == scope.fileId )
            {
                continue;                // the same-file alias lane already had its chance
            }
            const TypeScope there{ scope.ctx, fileConsts( scope.ctx, fileId ), fileId };
            ResolvedType    here;
            if( !resolveThroughAlias( there, probe, depth, here ) )
            {
                if( !here.note.empty() ) { out.note = here.note; }
                return false;
            }
            if( first ) { agreed = here; first = false; }
            else if( here.size.size != agreed.size.size || here.size.align != agreed.size.align )
            {
                out.note = "macro-type-ambiguous";
                return false;
            }
        }
        if( !first )
        {
            out = agreed;
            return true;
        }
    }
    return false;
}

// The spelling that names the TYPE: cv-qualifiers, `typename` and a leading global `::` dropped.
inline std::string_view typeCore( std::string_view spec )
{
    std::string_view core = withoutCv( spec );
    while( core.starts_with( "::" ) )
    {
        core = core.substr( 2 );
    }
    return core;
}

// Size an in-repo aggregate by name, trying the qualified spelling and then its last segment (`rw::Foo`, then `Foo`).
inline TypeSize sizeNestedByName( ModelCtx& ctx, std::string_view name, std::uint32_t fileId, std::string& note, bool templateId )
{
    TypeSize nested = sizeNestedAggregate( ctx, name, fileId, note, templateId );
    if( !nested.known && name != lastSegment( name ) )
    {
        nested = sizeNestedAggregate( ctx, lastSegment( name ), fileId, note, templateId );
    }
    return nested;
}

// An in-repo class template (`InternedTextOf<RefNames>`): sized from its own definition when no member depends on its
// parameters. A std:: template the table did not take, or one with no in-repo definition, is a template-type refusal.
inline ResolvedType resolveTemplateIdType( const TypeScope& scope, std::string_view core, bool stdName )
{
    ResolvedType out;
    TemplateId   id;
    if( !stdName && splitTemplateId( core, id ) )
    {
        out.size = sizeNestedByName( scope.ctx, id.name, scope.fileId, out.note, true );
        if( out.size.known )
        {
            return out;
        }
    }
    if( out.note.empty() )
    {
        out.note = "template-type";
    }
    return out;
}

// One plain type name: a primitive, a template parameter (never sized), a std:: name outside the table, a same-file
// alias, an in-repo aggregate, or an alias defined in another file — in that order. False leaves `out` unsized.
inline bool resolveSingleName( const TypeScope& scope, std::string_view single, bool stdName, std::size_t depth, ResolvedType& out )
{
    if( primLookup( single, out.size ) )
    {
        return true;
    }
    const auto& params = scope.ctx.templateParams;
    if( std::find( params.begin(), params.end(), single ) != params.end() )
    {
        out.note = "template-param";                                   // depends on the template's argument
        return false;
    }
    if( stdName )
    {
        out.note = "std-unlisted";
        return false;
    }
    if( resolveThroughAlias( scope, single, depth, out ) )
    {
        return true;
    }
    out.size = sizeNestedByName( scope.ctx, single, scope.fileId, out.note, false );   // a failed alias lane leaves no number
    return out.size.known || ( out.note.empty() && resolveCrossFileAlias( scope, single, depth, out ) );
}

inline ResolvedType resolveFieldType( const TypeScope& scope, std::string_view spec, bool isPointer, bool isRef,
                                      std::size_t macroDepth )
{
    ResolvedType out;
    if( isPointer || isRef ) { out.size = TypeSize{ 8, 8, true }; return out; }   // LP64 data pointer / reference

    // A std:: name is the standard library's, never a same-named type in the repo (an in-repo `class string {}` stub once
    // sized every std::string at 1 B). The std lane sizes it or says why not; only a plain scalar falls through.
    const std::string_view core    = typeCore( spec );
    const bool             stdName = core.starts_with( "std::" );
    if( stdName && resolveStdType( scope, core.substr( 5 ), macroDepth, out ) )
    {
        return out;
    }

    bool                          sawEnum = false;
    std::vector<std::string_view> words   = typeWords( spec, sawEnum );
    if( words.empty() || intFamilySize( words, out.size ) )
    {
        return out;
    }
    if( spec.find( '<' ) != std::string_view::npos )
    {
        return resolveTemplateIdType( scope, core, stdName );
    }
    if( words.size() != 1 )                                { out.note = "compound-type"; return out; }
    if( resolveSingleName( scope, words.front(), stdName, macroDepth, out ) )
    {
        return out;
    }

    // A written `enum X` keyword is the one place a 4-byte assumption beats silence: the field is reported
    // WITH the assumption named, so a reader with a fixed-underlying-type enum can overrule it.
    if( sawEnum ) { out.note = "enum-assumed-4"; out.size = TypeSize{ 4, 4, true }; }
    return out;
}


inline void addCaveat( LayoutDef& def, std::string kind, std::string detail )
{
    for( Caveat& c : def.caveats )
    {
        if( c.kind == kind ) { ++c.count; return; }   // one ROW per kind (still a report, not a log) — but
    }
                                                        // count now discloses how many sites hit it, instead
                                                        // of silently dropping every site after the first
    def.caveats.push_back( Caveat{ std::move( kind ), std::move( detail ), 1 } );
}

// `alignas( N )` / `__attribute__(( aligned( N ) ))` — modelled, because it is local, unambiguous, and the
// whole reason a 24-byte-looking struct can be 32 bytes. An argument that is not a plain power-of-two
// literal (`alignas( alignof( T ) )`) is NOT guessed at: it withdraws the numbers instead.
inline void readDeclaredAlign( LayoutDef& def, std::string_view head )
{
    static constexpr std::string_view kKeywords[] = { "alignas", "aligned" };
    const ConstTable                  noConsts;                        // a literal only — no file constants here
    for( std::string_view kw : kKeywords )
    {
        forEachKeywordCall( head, kw, [ & ]( std::size_t, std::size_t, std::string_view inner )
        {
            const std::string_view arg = trimView( inner );
            std::uint32_t          n   = 0;
            if( evalExtent( noConsts, arg, n ) && ( n & ( n - 1 ) ) == 0 )
            {
                def.declaredAlign = std::max( def.declaredAlign, n );
            }
            else
            {
                def.modeled = false;
                addCaveat( def, "unparsed-alignas", flattenSpace( arg, 80 ) );
            }
        } );
    }
}

// The text of a base-class list: after the first top-level `:` past the name that is not part of a `::`; "" = none.
inline std::string_view baseClauseOf( std::string_view head, std::string_view name )
{
    const std::size_t nameAt = head.find( name );
    if( nameAt == std::string_view::npos )
    {
        return {};
    }
    for( std::size_t i = nameAt + name.size(); i < head.size(); ++i )
    {
        if( head[i] != ':' )
        {
            continue;
        }
        if( ( i + 1 < head.size() && head[ i + 1 ] == ':' ) || ( i > 0 && head[ i - 1 ] == ':' ) ) { ++i; continue; }
        return head.substr( i + 1 );
    }
    return {};
}

// ONE non-virtual base is kept for placeBase (the Reference : RefColdFields shape); several bases, or a virtual one,
// put subobjects where the source text cannot say, so they withdraw the numbers.
inline void readBaseClause( LayoutDef& def, std::string_view head, std::string_view name )
{
    const std::string_view clause = baseClauseOf( head, name );
    if( clause.empty() )
    {
        return;
    }
    const std::vector<std::string_view> bases = splitDeclarators( clause );
    std::string_view                    one   = ( bases.size() == 1 ) ? trimView( bases.front() ) : std::string_view();
    for( std::string_view access : { "public", "protected", "private" } )
    {
        if( one.starts_with( access ) && one.size() > access.size() && !identByte( (unsigned char)one[ access.size() ] ) )
        {
            one = trimView( one.substr( access.size() ) );
        }
    }
    if( !one.empty() && !containsWord( one, "virtual" ) )
    {
        def.baseSpec = std::string( one );
        return;
    }
    def.modeled = false;
    addCaveat( def, "base-class", bases.size() > 1 ? "several base subobjects: their order and padding are not in this declaration"
                                                   : "a virtual base's placement is not in this declaration" );
}

// Read the attributes the aggregate's HEAD text carries (everything from the def start to its `{`).
inline void readHeadAttributes( LayoutDef& def, std::string_view head, std::string_view name, bool allowTemplate = false )
{
    if( containsWord( head, "union" ) )
    {
        def.aggregate = "union";
    }
    else if( containsWord( head, "class" ) )
    {
        def.aggregate = "class";
    }
    if( containsWord( head, "template" ) && !allowTemplate )
    {
        def.modeled = false;
        addCaveat( def, "template", "a template's layout depends on its arguments" );
    }

    readDeclaredAlign( def, head );

    if( head.find( "packed" ) != std::string_view::npos && head.find( "__attribute__" ) != std::string_view::npos )
    {
        def.packedAttr = true;
    }

    readBaseClause( def, head, name );
}

// The mutable state of ONE aggregate-body walk, bundled so each phase below takes a single parameter
// instead of eight — and so `placeable` is unmistakably shared across them rather than copied. It goes
// false permanently the moment an offset can no longer be computed.
struct BodyWalk
{
    ModelCtx&         ctx;
    const ConstTable& consts;
    LayoutDef&        def;
    std::uint32_t     fileId;
    std::string_view  body;
    std::uint32_t     cursor    = 0;
    std::uint32_t     maxAlign  = 1;
    bool              placeable = true;
    std::size_t       stmtStart = 0;
    std::uint32_t     bitByte   = 0;     // the byte the open bitfield run is filling…
    std::uint32_t     bitUsed   = 0;     // …and how many of its bits are taken (0 = no run open)

    void refuse( std::string kind, std::string detail )
    {
        def.modeled = false;
        placeable   = false;
        addCaveat( def, std::move( kind ), std::move( detail ) );
    }
};

// The ONE non-virtual base (readHeadAttributes kept its spelling): its subobject sits at offset 0 and the members start
// after it. Two shapes are refused rather than numbered: a base that cannot be sized, and a base with tail padding —
// Itanium may put a derived member inside that padding (when the base is not POD), MSVC never does. An empty base takes
// no bytes (the empty-base optimisation every ABI applies to a single base).
inline void placeBase( BodyWalk& w )
{
    LayoutDef& def = w.def;
    if( def.baseSpec.empty() )
    {
        return;
    }
    const TypeScope    scope{ w.ctx, w.consts, w.fileId };
    const ResolvedType r = resolveFieldType( scope, def.baseSpec, false, false );
    if( !r.size.known )
    {
        w.refuse( "base-class", flattenSpace( def.baseSpec, 120 ) + ": the base cannot be sized (" + ( r.note.empty() ? "unknown-type" : r.note ) + ")" );
        return;
    }
    if( r.size.tailPad != 0 && !r.size.empty )
    {
        w.refuse( "base-class", flattenSpace( def.baseSpec, 120 ) + ": " + std::to_string( r.size.tailPad )
                                  + " B of tail padding, which Itanium may fill with derived members and MSVC never does" );
        return;
    }
    def.baseSized = true;
    def.baseSize  = r.size.empty ? 0u : r.size.size;
    w.cursor      = def.baseSize;
    w.maxAlign    = std::max( w.maxAlign, r.size.align );
}

// A bitfield whose type is ONE byte wide (bool, char, std::uint8_t, an enum over one): every ABI packs those the same way —
// fill the current byte, open the next when the width does not fit. Wider types (Itanium straddles alignment units, MSVC
// opens a unit per type change), zero widths and union members return false and the caller refuses the aggregate.
inline bool placeByteBitfield( BodyWalk& w, const Declarator& d, std::string_view written )
{
    if( std::string_view( w.def.aggregate ) == "union" )
    {
        return false;
    }
    const TypeScope    scope{ w.ctx, w.consts, w.fileId };
    const ResolvedType r     = resolveFieldType( scope, d.baseSpec, false, false );
    std::uint32_t      width = 0;
    if( !r.size.known || r.size.size != 1 || !evalExtent( w.consts, d.bitWidth, width ) || width == 0 || width > 8 )
    {
        return false;
    }
    FieldRow f;
    f.name     = std::string( d.name );
    f.type     = flattenSpace( written, 160 );
    f.resolved = flattenSpace( r.resolved, 160 );
    f.size     = 1;
    f.align    = 1;
    f.sized    = true;
    f.bitWidth = width;
    w.maxAlign = std::max( w.maxAlign, 1u );
    if( w.placeable )
    {
        if( w.bitUsed == 0 || w.bitUsed + width > 8 )
        {
            w.bitByte = w.cursor;
            w.cursor += 1;
            w.bitUsed = 0;
        }
        f.offset    = w.bitByte;
        f.bitOffset = w.bitUsed;
        f.placed    = true;
    }
    w.bitUsed += width;
    w.def.fields.push_back( std::move( f ) );
    return true;
}

// Fold ONE parsed declarator into the def's field list, advancing the offset cursor when it still can.
// `written` is the label (the type as the source spells it for THIS declarator); d.baseSpec is what is sized.
inline void appendField( BodyWalk& w, const Declarator& d, std::string_view written )
{
    // Every string here reaches an XML ATTRIBUTE, which may not carry a raw newline under G4 — a member
    // declaration wrapped over two lines would otherwise emit one.
    FieldRow f;
    f.name = std::string( d.name );
    f.type = flattenSpace( written, 160 );

    const TypeScope    scope{ w.ctx, w.consts, w.fileId };
    const ResolvedType r = resolveFieldType( scope, d.baseSpec, d.isPointer, d.isRef );
    TypeSize           t = r.size;
    f.resolved = flattenSpace( r.resolved, 160 );
    f.why      = t.known ? std::string() : ( r.note.empty() ? std::string( "unknown-type" ) : r.note );
    w.bitUsed  = 0;                                                    // an ordinary member closes any bitfield byte
    if( !r.note.empty() )
    {
        addCaveat( w.def, r.note, f.name + ": " + f.type );
    }
    if( d.isRef )
    {
        addCaveat( w.def, "reference-member", f.name + ": a reference member's storage is unspecified" );
    }

    // A3: a PER-FIELD `__attribute__((aligned(N)))` / `((packed))` (bare OR the GNU reserved-namespace
    // `__aligned__` / `__packed__` spelling — attrHasKeyword normalises both to one classification, review
    // round 2026-09-17) changes this field's own placement, and the model has no argument evaluator for
    // it — degrade to unknown-type exactly like resolveFieldType's own refusal for `alignas(N) int x`
    // (AlignasFieldCase), an unknown size/align rather than a confidently wrong one. Every OTHER attribute
    // (deprecated/unused/…) is a pure hint that changes no byte of the layout, so peelAttributeGroups
    // already dropped it from typeSpec above with no caveat at all — this is the one place that distinction
    // is made, deliberately narrow to keep a silent attribute silent.
    for( std::string_view attr : d.attrGroups )
    {
        if( attrHasKeyword( attr, "aligned" ) || attrHasKeyword( attr, "packed" ) )
        {
            t.known = false;
            f.why   = "attribute-aligned";
            break;
        }
    }

    for( std::string_view e : d.extents )
    {
        std::uint32_t n = 0;
        if( namesTemplateParam( w.ctx, e ) )
        {
            addCaveat( w.def, "template-param", f.name + "[" + flattenSpace( e, 80 ) + "]: the extent is the template argument's" );
            t.known = false;
            f.why   = "template-param";
            break;
        }
        if( !evalExtent( w.consts, e, n ) || f.elems > kMaxArrayElems / n )
        {
            addCaveat( w.def, "unknown-extent", f.name + "[" + flattenSpace( e, 80 ) + "]" );
            t.known = false;
            f.why   = "unknown-extent";
            break;
        }
        f.elems *= n;
    }

    if( w.def.packedAttr && t.known )
    {
        t.align = 1;
    }

    f.sized = t.known;
    if( !t.known )
    {
        w.refuse( "unknown-type", f.name + ": " + f.type );
        w.def.fields.push_back( std::move( f ) );
        return;
    }

    f.size     = t.size * f.elems;
    f.align    = t.align;
    w.maxAlign = std::max( w.maxAlign, t.align );

    if( w.placeable )
    {
        if( std::string_view( w.def.aggregate ) == "union" ) { f.padBefore = 0; f.offset = 0; }
        else
        {
            const std::uint32_t rem = ( t.align > 0 ) ? ( w.cursor % t.align ) : 0u;
            f.padBefore = ( rem == 0 ) ? 0u : ( t.align - rem );
            w.cursor += f.padBefore;
            f.offset  = w.cursor;
            w.cursor += f.size;
        }
        f.placed = true;
    }
    w.def.fields.push_back( std::move( f ) );
}

// Peel leading access specifiers (`private:`, `public:` …) off a statement. The body walk cuts statements at `;`, so a
// specifier rides at the FRONT of the next member: `private: std::uint32_t id_ = 0;` reached the walker as one statement,
// led with the skip word `private`, and the field vanished while the class still said modeled="1" (InternedTextOf<D>,
// 4 B, printed size="1" fields="0"). `record` = false peels without the caveat, for a statement that is not a member.
inline std::string_view peelAccessSpecifiers( BodyWalk& w, std::string_view s, bool record = true )
{
    for( bool again = true; again; )
    {
        again = false;
        for( std::string_view access : { "public", "protected", "private" } )
        {
            if( !s.starts_with( access ) )
            {
                continue;
            }
            const std::string_view rest = trimView( s.substr( access.size() ) );
            const bool longerWord = s.size() > access.size() && identByte( (unsigned char)s[ access.size() ] );   // `privateData`
            if( longerWord || rest.empty() || rest.front() != ':' || rest.starts_with( "::" ) )
            {
                continue;
            }
            if( record && access != "public" )
            {
                addCaveat( w.def, "mixed-access", "non-public members make this non-standard-layout" );
            }
            s     = trimView( rest.substr( 1 ) );
            again = true;
        }
    }
    return s;
}

// `template <…> rest` → rest; anything else unchanged.
inline std::string_view withoutTemplateHead( std::string_view s )
{
    if( !s.starts_with( "template" ) )
    {
        return s;
    }
    const std::size_t open = s.find( '<' );
    if( open == std::string_view::npos || !trimView( s.substr( 8, open - 8 ) ).empty() )
    {
        return s;
    }
    const std::size_t close = matchBracket( s, open, '<', '>' );
    return ( close == std::string_view::npos ) ? s : trimView( s.substr( close ) );
}

// True when the word immediately before `s[at]` — the `(` at `at` — spells `alignas` / `__attribute__` /
// `decltype`: that `(` opens the specifier's own argument list, not a member's parameter list.
inline bool opensAttrSpecifier( std::string_view s, std::size_t at )
{
    static constexpr std::string_view kAttrKeywords[] = { "alignas", "__attribute__", "decltype" };
    std::size_t wordEnd = at;
    while( wordEnd > 0 && std::isspace( (unsigned char)s[wordEnd - 1] ) != 0 ) { --wordEnd; }
    std::size_t wordStart = wordEnd;
    while( wordStart > 0 && identByte( (unsigned char)s[wordStart - 1] ) ) { --wordStart; }
    const std::string_view word = s.substr( wordStart, wordEnd - wordStart );
    for( std::string_view kw : kAttrKeywords )
    {
        if( word == kw ) { return true; }
    }
    return false;
}

// The statement forms that contribute NO storage and are simply skipped, plus the ones that withdraw the
// numbers. Returns true when the statement was consumed here and holds no field declarators.
// The first `(` that is a CANDIDATE for a member declaration's parameter list: skip one that instead
// belongs to an `alignas( … )` / `__attribute__( ( … ) )` / `decltype( … )` specifier, or that sits inside a
// template argument list's `<…>` (`std::function< void(int) >`). None of those opens a parameter list, and
// counting one anyway silently dropped the field it decorates while the aggregate still reported
// modeled="1": `alignas(8) int x`, `int x __attribute__((aligned(8)))`, `decltype(1) x` and
// `std::function<void(int)> cb` each lost their field this way. Returns npos when no candidate remains.
inline std::size_t candidateParen( std::string_view s )
{
    int angle = 0;
    for( std::size_t i = 0; i < s.size(); )
    {
        const char c = s[i];
        if( c == '<' ) { ++angle; ++i; continue; }
        if( c == '>' && angle > 0 ) { --angle; ++i; continue; }
        if( c != '(' ) { ++i; continue; }
        if( angle > 0 ) { ++i; continue; }   // a template argument's own parens — not a parameter list
        if( !opensAttrSpecifier( s, i ) )
        {
            return i;
        }
        const std::size_t close = matchBracket( s, i, '(', ')' );
        if( close == std::string_view::npos )
        {
            return std::string_view::npos;   // unbalanced — degrade rather than misclassify
        }
        i = close;
    }
    return std::string_view::npos;
}

// Where a member declaration's parameter list opens, or npos when it has none. Only a `(` that comes BEFORE the first
// `[`, `=`, `{` or bitfield `:` can open one: `char a[(4)];`, `int x = (3);` and `int x{ (3) };` are data members whose
// parenthesis sits in an extent or an initializer. Reading those as member functions dropped the field from the layout
// while the struct still reported modeled="1" and a size four bytes short. `operator=`, `operator[]` and `operator()`
// are functions whose own name holds one of those characters, so an `operator` word decides first.
inline std::size_t parameterListParen( std::string_view s )
{
    if( containsWord( s, "operator" ) )
    {
        return s.find( '(' );
    }
    const std::size_t paren = candidateParen( s );
    if( paren == std::string_view::npos )
    {
        return paren;
    }
    for( std::size_t i = 0; i < paren; ++i )
    {
        const char c = s[i];
        const bool scopeColon = c == ':' && ( ( i + 1 < s.size() && s[i + 1] == ':' ) || ( i > 0 && s[i - 1] == ':' ) );
        if( c == '[' || c == '=' || c == '{' || ( c == ':' && !scopeColon ) )
        {
            return std::string_view::npos;
        }
    }
    return paren;
}

inline bool modelNonFieldStatement( BodyWalk& w, std::string_view s )
{
    // Access specifiers change nothing this model computes, but MIXED access makes the class non-standard-
    // layout, which is worth naming even though Clang/GCC still place members in declaration order.
    if( s == "public:" || s == "private:" || s == "protected:" )
    {
        if( s != "public:" )
        {
            addCaveat( w.def, "mixed-access", "non-public members make this non-standard-layout" );
        }
        return true;
    }

    static constexpr std::string_view kSkipLeaders[] = { "typedef", "using", "friend", "template", "static_assert",
                                                         "_Static_assert", "public", "private", "protected", "return" };
    std::size_t            k     = 0;
    const std::string_view first = takeQualifiedIdent( s, k );
    for( std::string_view lead : kSkipLeaders )
    {
        if( first == lead )
        {
            return true;
        }
    }

    if( containsWord( s, "static" ) )
    {
        return true; // a static data member has no layout slot
    }
    if( containsWord( s, "virtual" ) )
    {
        // A vtable pointer sits at offset 0, so it invalidates the fields ALREADY placed above it too —
        // the one refusal that has to reach backwards. (Every other one only affects what follows it.)
        for( FieldRow& f : w.def.fields ) { f.placed = false; f.offset = 0; }
        w.refuse( "virtual", "a virtual member adds a vtable pointer at offset 0 that the source text never spells" );
        return true;
    }

    // A member FUNCTION declaration (a `(` that is not the `(*fn)` function-pointer shape) contributes no
    // storage, so it is simply skipped. A function POINTER member does contribute — but a pointer to a
    // MEMBER function is 16 bytes, not 8, and the two are not reliably distinguishable here, so the
    // aggregate withdraws its numbers rather than pick.
    const std::size_t paren = parameterListParen( s );
    if( paren == std::string_view::npos )
    {
        return false;
    }
    const std::string_view afterParen = trimView( s.substr( paren + 1 ) );
    if( afterParen.empty() || ( afterParen[0] != '*' && afterParen[0] != '&' ) )
    {
        return true;
    }
    w.refuse( "function-pointer", flattenSpace( s, 160 ) );
    return true;
}

// The empty-base rule one level down: a first member whose own offset 0 holds the empty base's type (`struct A : E { int x; };
// struct D : E { A a; };` puts a at 4, not 0) — LAYOUT-EBO-NESTED, CodeRabbit #630. Read after appendField sized the member, which
// recorded its offset-0 chain. Refuses on `w` and returns true when the rule applies.
inline bool refuseNestedEmptyBase( BodyWalk& w, const Declarator& d )
{
    if( w.def.fields.size() != 1 || !w.def.baseSized || w.def.baseSize != 0 || d.isPointer || d.isRef )
    {
        return false;
    }
    const std::string_view base = lastSegment( withoutCv( w.def.baseSpec ) );
    const auto             it   = w.ctx.zeroOffsetTypes.find( std::string( lastSegment( withoutCv( d.baseSpec ) ) ) );
    if( it == w.ctx.zeroOffsetTypes.end() || std::ranges::find( it->second, base ) == it->second.end() )
    {
        return false;
    }
    w.refuse( "base-class", flattenSpace( w.def.baseSpec, 120 ) + ": the first member " + std::string( d.name ) + " holds a "
                              + std::string( base ) + " at its own offset 0, so the empty base cannot share its address" );
    return true;
}

// Handle one top-level statement inside the aggregate body.
// Fold ONE declarator of a member statement. `baseType` is the statement's shared base, set from declarator 0: a
// follow-on declarator shares only that (`char *a, b;` makes b a `char`, `int *p, *q;` makes q an `int *`). False when
// the statement was refused and the rest of it must not be read.
inline bool modelDeclarator( BodyWalk& w, std::string_view part, bool first, std::string_view& baseType )
{
    Declarator d = parseDeclarator( part );
    if( first && d.ok )
    {
        baseType = d.baseSpec;
    }
    d.baseSpec = baseType;
    const std::string written = first ? std::string( d.typeSpec )
                              : d.declPart.empty() ? std::string( baseType ) : std::string( baseType ) + " " + std::string( d.declPart );
    if( d.isBitfield )
    {
        if( namesTemplateParam( w.ctx, d.bitWidth ) )
        {
            w.refuse( "template-param", std::string( d.name ) + " : " + flattenSpace( d.bitWidth, 80 ) + ": the width is the template argument's" );
            return false;
        }
        const bool placed = d.ok && !baseType.empty() && placeByteBitfield( w, d, written );
        if( !placed )
        {
            w.refuse( "bitfield", "the bit allocation unit and packing order are implementation-defined" );
        }
        return placed;
    }
    if( !d.ok || baseType.empty() )
    {
        w.refuse( "unparsed-member", flattenSpace( part, 160 ) );
        return false;
    }
    // The empty-base optimisation is barred when the first member has the base's own type: two subobjects of one type may
    // not share an address, so `struct D : E { E e; int x; }` puts e at 1, not 0 (CodeRabbit 4544554347). Refused, not placed.
    if( w.def.fields.empty() && w.def.baseSized && w.def.baseSize == 0 && !d.isPointer && !d.isRef
        && lastSegment( withoutCv( d.baseSpec ) ) == lastSegment( withoutCv( w.def.baseSpec ) ) )
    {
        w.refuse( "base-class", flattenSpace( w.def.baseSpec, 120 ) + ": the first member " + std::string( d.name )
                                  + " has the empty base's own type, so the base cannot share its address" );
        return false;
    }
    appendField( w, d, written );
    return !refuseNestedEmptyBase( w, d );
}

inline void modelStatement( BodyWalk& w, std::string_view stmt )
{
    const std::string_view s = peelAccessSpecifiers( w, trimView( stmt ) );
    if( s.empty() || modelNonFieldStatement( w, s ) )
    {
        return;
    }

    const std::vector<std::string_view> parts = splitDeclarators( s );
    std::string_view                    baseType;
    for( std::size_t i = 0; i < parts.size(); ++i )
    {
        if( !modelDeclarator( w, parts[i], i == 0, baseType ) )
        {
            return;
        }
    }
}

// A `#` that opens a preprocessor DIRECTIVE (only whitespace between it and the line start).
inline bool atDirectiveStart( std::string_view body, std::size_t at )
{
    for( std::size_t cursor = at; cursor > 0; --cursor )   // cursors, not `i-- > 0`: a `#` with no newline before it wrapped it
    {
        const std::size_t i = cursor - 1;
        if( body[i] == '\n' )
        {
            return true;
        }
        if( std::isspace( (unsigned char)body[i] ) == 0 )
        {
            return false;
        }
    }
    return true;
}

// One past a directive's last byte: the first newline NOT escaped by a trailing backslash (`#define W ( A \` goes on).
inline std::size_t directiveEnd( std::string_view body, std::size_t at )
{
    for( std::size_t i = at; i < body.size(); ++i )
    {
        if( body[i] != '\n' )
        {
            continue;
        }
        std::size_t back = i;
        if( back > at && body[back - 1] == '\r' )
        {
            --back;
        }
        if( back == at || body[back - 1] != '\\' )
        {
            return i;
        }
    }
    return body.size();
}

// One preprocessor directive line inside the body. An `#if`-family conditional can add or remove fields
// depending on build flags, so it withdraws the numbers; every other directive is merely skipped.
inline std::size_t walkDirective( BodyWalk& w, std::size_t at )
{
    static constexpr std::string_view kConditional[] = { "if", "ifdef", "ifndef", "else", "elif", "endif" };

    const std::size_t      end = directiveEnd( w.body, at );
    const std::string_view d   = trimView( w.body.substr( at + 1, end - at - 1 ) );
    for( std::string_view c : kConditional )
    {
        if( d.rfind( c, 0 ) == 0 && ( d.size() == c.size() || !identByte( (unsigned char)d[ c.size() ] ) ) )
        {
            w.refuse( "conditional-members", "a preprocessor conditional inside the body can add or remove fields" );
            break;
        }
    }

    // A directive BETWEEN two members belongs to neither: the next statement starts after it. The test is the text
    // BEFORE the `#` — testing through `next` included the directive itself, so it never passed, and every #define
    // between two fields was glued onto the next field's type (tmux window_pane.sync_dirty, 2026-11-11 audit).
    const std::size_t next   = std::min( end + 1, w.body.size() );
    const std::string before = withoutComments( w.body.substr( w.stmtStart, ( at > w.stmtStart ) ? at - w.stmtStart : 0 ) );
    if( trimView( before ).empty() )   // a `// flags` line above the directive is not a member either (CodeRabbit 4544554368)
    {
        w.stmtStart = next;
    }
    return next;
}

// One `{` inside the body, classified by what precedes it: a nested aggregate (refuse), a member-function
// body (skip, statement over), or a brace INITIALIZER (skip, statement continues — `char d[CAP] = {};`
// still declares a field).
inline std::size_t walkBrace( BodyWalk& w, std::size_t at )
{
    const std::size_t      close      = matchBracket( w.body, at, '{', '}' );
    const std::size_t      after      = ( close == std::string_view::npos ) ? w.body.size() : close;
    const std::string      pendingRaw = withoutComments( w.body.substr( w.stmtStart, at - w.stmtStart ) );
    const std::string_view pending    = peelAccessSpecifiers( w, trimView( pendingRaw ), false );
    // `template <class T> void set( T&& v ) { … }` is a member function: the `class` is its parameter's, not an aggregate's.
    const std::string_view declared   = withoutTemplateHead( pending );

    if( containsWord( declared, "struct" ) || containsWord( declared, "class" )
        || containsWord( declared, "union" ) || containsWord( declared, "enum" ) )
    {
        w.refuse( "nested-aggregate", "a nested or anonymous aggregate member is not modelled" );
        std::size_t i = after;
        while( i < w.body.size() && w.body[i] != ';' )
        {
            ++i;
        }
        if( i < w.body.size() )
        {
            ++i;
        }
        w.stmtStart = i;
        return i;
    }

    // A brace INITIALIZER follows a declarator (`= {`, `] {`, `name {`). A member function whose signature ends in a word
    // (`id() const noexcept {`) is not one: its parameter list says so. Reading it as an initializer ran the statement on
    // to the next `;`, and a `private:` field behind it vanished (TextIdOf<D>, ColdBase: fields="0" size="1").
    const bool isInitializer = !pending.empty() && ( pending.back() == '=' || pending.back() == ']'
                                                     || identByte( (unsigned char)pending.back() ) )
                               && parameterListParen( declared ) == std::string_view::npos;
    if( isInitializer )
    {
        return after;
    }

    std::size_t i = after;
    if( i < w.body.size() && w.body[i] == ';' )
    {
        ++i;
    }
    w.stmtStart = i;
    return i;
}

// The body walk itself: comments/strings skipped, bracket groups stepped over whole, statements cut at
// top-level `;`.
inline void walkAggregateBody( BodyWalk& w )
{
    for( std::size_t i = 0; i < w.body.size(); )
    {
        const std::size_t skipped = skipInert( w.body, i );
        if( skipped != i )                                        { i = skipped;              continue; }
        if( w.body[i] == '#' && atDirectiveStart( w.body, i ) )   { i = walkDirective( w, i ); continue; }
        if( w.body[i] == '{' )                                    { i = walkBrace( w, i );     continue; }
        if( w.body[i] == '(' || w.body[i] == '[' )
        {
            const std::size_t close = matchBracket( w.body, i, w.body[i], ( w.body[i] == '(' ) ? ')' : ']' );
            i = ( close == std::string_view::npos ) ? w.body.size() : close;
            continue;
        }
        if( w.body[i] == ';' )
        {
            modelStatement( w, withoutComments( w.body.substr( w.stmtStart, i - w.stmtStart ) ) );
            w.stmtStart = i + 1;
        }
        ++i;
    }
}

// Turn the finished walk into the aggregate's own size/alignment/trailing pad. A union's members all sit at
// offset 0, so its extent is the widest member rather than the running cursor.
inline void finalizeLayout( BodyWalk& w )
{
    LayoutDef&    def     = w.def;
    std::uint32_t natural = w.cursor;
    if( std::string_view( def.aggregate ) == "union" )
    {
        natural = 0;
        for( const FieldRow& f : def.fields )
        {
            natural = std::max( natural, f.size );
        }
    }

    def.align = std::max( def.packedAttr ? 1u : w.maxAlign, def.declaredAlign );
    if( def.align == 0 )
    {
        def.align = 1;
    }
    if( !w.placeable || !def.modeled ) { def.modeled = false; return; }

    natural = std::max( natural, 1u );                                 // an empty aggregate still occupies 1 byte
    const std::uint32_t rem = natural % def.align;
    def.size    = ( rem == 0 ) ? natural : ( natural + def.align - rem );
    def.tailPad = def.size - natural;
}

// The three mirror keys (see the LayoutDef comment). All start from the aggregate's own numbers, so a pure
// alignas change is drift even when every field matches. An UNSIZED field contributes its SPELLING to the
// byte key too — with no number to compare, the spelling is the only evidence left. `slotShape` is
// `spellShape` minus the field NAMES: same positional slots, same types, whatever they are called.
inline void computeShapes( LayoutDef& def )
{
    std::uint64_t byteHash = 14695981039346656037ull, spellHash = byteHash, slotHash = byteHash;   // FNV-1a 64 offset basis
    const auto    fold = []( std::uint64_t& h, std::uint64_t part )
    {
        h ^= part;
        h  = hashutil::fnv1aMultiply( h );
    };
    const auto foldAll = [ & ]( std::uint64_t part ) { fold( byteHash, part ); fold( spellHash, part ); fold( slotHash, part ); };

    for( std::uint64_t part : { std::uint64_t( def.size ), std::uint64_t( def.align ), std::uint64_t( def.modeled ? 1 : 0 ),
                                std::uint64_t( def.baseSize ), std::uint64_t( def.baseSized ? 1 : 0 ) } )
    {
        foldAll( part );
    }
    // The base's SPELLING is a spelling, like a field type's: `simd::Base` on the host and `Base` in the shader take the same
    // bytes and must read kind="spelling", not drift (CodeRabbit 4553235766). An UNSIZED base keeps it in the byte key too.
    const std::uint64_t baseSpelling = fnv1a64( def.baseSpec );
    if( !def.baseSized )
    {
        fold( byteHash, baseSpelling );
    }
    fold( spellHash, baseSpelling );
    fold( slotHash, baseSpelling );
    for( const FieldRow& f : def.fields )
    {
        fold( byteHash, fnv1a64( f.name ) );
        fold( spellHash, fnv1a64( f.name ) );                       // slotHash deliberately skips the name

        for( std::uint64_t part : { std::uint64_t( f.elems ), std::uint64_t( f.sized ? f.size : 0u ),
                                    std::uint64_t( f.align ), std::uint64_t( f.placed ? f.offset + 1u : 0u ),
                                    ( std::uint64_t( f.bitWidth ) << 8 ) | f.bitOffset } )
        {
            foldAll( part );
        }

        const std::uint64_t spelling = fnv1a64( f.resolved.empty() ? f.type : f.resolved );
        if( !f.sized )
        {
            fold( byteHash, spelling );
        }
        fold( spellHash, spelling );
        fold( slotHash,  spelling );                                // a retype at a fixed offset is NOT a rename
    }
    def.byteShape  = byteHash;
    def.spellShape = spellHash;
    def.slotShape  = slotHash;
}

// Model ONE definition site given its OWN source/consts rather than pulling them from ctx's disk-file
// cache — the hook a cross-branch caller (abicheck.h) needs to run this EXACT arithmetic over a git ref's
// blob, which was never ingested and never touched disk. `fileId` still supplies the def's PATH LABEL and
// the nested-aggregate "prefer this file" tiebreak; the bytes modelled do not have to be that file's own
// disk content, which is precisely what lets a ref's blob borrow HEAD's fileId for both.
inline LayoutDef modelDefFromSource( ModelCtx& ctx, std::string_view src, std::string_view stripped, const ConstTable& consts,
                                     std::uint32_t fileId, const DefSite& site, std::string_view name )
{
    LayoutDef def;
    def.path = ( fileId < ctx.ing.files.size() ) ? ctx.ing.files[ fileId ] : std::string();
    def.line = lineOf( src, site.headStart );

    ASSUME( site.braceStart < site.braceEnd && site.braceEnd <= src.size() );
    const std::string_view whole    = src;
    const std::string      headText = withoutComments( whole.substr( site.headStart, site.braceStart - site.headStart ) );
    readHeadAttributes( def, headText, name, ctx.allowTemplateHead );

    // `#pragma pack` anywhere in the file silently rewrites every alignment below it. Tracking its
    // push/pop regions lexically is exactly the half-right preprocessing this module refuses to do, so the
    // presence of the directive is enough to withdraw the numbers. Probed on the COMMENT-STRIPPED text — a
    // header whose prose merely mentions the pragma is not a header that contains it.
    if( stripped.find( "#pragma pack" ) != std::string_view::npos )
    {
        def.modeled = false;
        addCaveat( def, "pragma-pack", "this file contains a pragma pack directive — alignment is not modelled" );
    }

    BodyWalk walk{ ctx, consts, def, fileId,
                   whole.substr( site.braceStart + 1, site.braceEnd - site.braceStart - 2 ),
                   0, 1, def.modeled, 0 };
    placeBase( walk );
    walkAggregateBody( walk );
    finalizeLayout( walk );
    computeShapes( def );
    return def;
}

// Model ONE definition site from the disk-cached file it lives in — every existing caller's path
// (computeLayout, sizeNestedAggregate) reading the working tree. Thin wrapper over the buffer-taking core
// above so the two never drift apart.
inline LayoutDef modelDef( ModelCtx& ctx, std::uint32_t fileId, const DefSite& site, std::string_view name )
{
    return modelDefFromSource( ctx, fileBytes( ctx, fileId ), fileStripped( ctx, fileId ), fileConsts( ctx, fileId ),
                               fileId, site, name );
}

// Locate the FIRST top-level aggregate definition named `name` in a buffer that was never indexed — the
// lexical stand-in for "look up sigStartByte in ing.symbols" a cross-branch caller needs (a git ref's blob
// has no index; that is the whole reason this exists rather than reusing computeLayout's symbol walk).
// Walks the buffer once, splitting it at top-level `;` and matched `{...}` groups with the SAME primitives
// findDefBody's own forward scan uses (skipInert, no special-casing of `(`/`[`), so the two scans always
// agree on which `{` is "next" — then hands each candidate span's START to findDefBody() exactly as an
// index's sigStartByte would. A `{` that opens a `namespace` block is DESCENDED into rather than skipped
// (the common case a dual-compile header nests structs inside); anything else that fails is skipped whole
// via matchBracket. LIMIT: a struct nested inside a class body or an `extern "C"` block is not found —
// documented at the call site, never silently reported as unchanged.
inline bool findTopLevelDef( std::string_view src, std::string_view name, DefSite& out )
{
    std::size_t stmtStart = 0;
    for( std::size_t i = 0; i < src.size(); )
    {
        const std::size_t skipped = skipInert( src, i );
        if( skipped != i ) { i = skipped; continue; }
        if( src[i] == '{' )
        {
            if( findDefBody( src, name, stmtStart, out ) )
            {
                return true;
            }
            if( containsWord( src.substr( stmtStart, i - stmtStart ), "namespace" ) ) { stmtStart = i + 1; ++i; continue; }
            const std::size_t close = matchBracket( src, i, '{', '}' );
            i         = ( close == std::string_view::npos ) ? src.size() : close;
            stmtStart = i;
            continue;
        }
        if( src[i] == ';' ) { stmtStart = i + 1; ++i; continue; }
        ++i;
    }
    return false;
}

// ── static_assert harvesting ─────────────────────────────────────────────────────────────────────────
// The house style pins every hot struct with `static_assert( sizeof(X) == N )`, and that assert is the
// SECOND thing the field note says gets hand-collected on every edit. One streaming pass over the indexed
// C-family files (read, probe, discard — peak memory is one file) collects them all.

// `s` with every whitespace byte removed. Compacting an assert's argument is what turns the `sizeof(X)==N`
// match below into two string searches instead of a tokenizer — the house spells it
// `static_assert( sizeof( X ) == N, "…" )`, other repos spell it `static_assert(sizeof(X)==N)`, and after
// this they are the same bytes.
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

// The unsigned decimal literal at `compact[from]`, but ONLY when it ends the comparison (`==24,` / `==24)`).
// `==24+8` is an expression this module does not evaluate, and half-reading it would manufacture a phantom
// conflict — so an unterminated literal is a refusal, not a partial answer.
inline bool wholeIntLiteral( std::string_view compact, std::size_t from, std::size_t stop, std::uint32_t& out )
{
    if( from >= stop || std::isdigit( (unsigned char)compact[from] ) == 0 )
    {
        return false;
    }
    std::uint64_t v = 0;
    std::size_t   j = from;
    while( j < stop && std::isdigit( (unsigned char)compact[j] ) != 0 )
    {
        v = v * 10 + std::uint64_t( compact[ j++ ] - '0' );
        if( v > 0xFFFFFFFFull )
        {
            return false;
        }
    }
    if( j != stop )
    {
        return false;
    }
    out = std::uint32_t( v );
    return true;
}

// Pull the integer out of `<fn>(NAME)==<int>` or `<int>==<fn>(NAME)` in a squeezed assert argument, with the
// elaborated `struct`/`class` spellings of NAME accepted too.
inline bool extractSizeAssert( std::string_view compact, std::string_view fn, std::string_view name, std::uint32_t& out )
{
    const std::string bare  = std::string( fn ) + "(" + std::string( name ) + ")";
    const std::string elabS = std::string( fn ) + "(struct" + std::string( name ) + ")";
    const std::string elabC = std::string( fn ) + "(class"  + std::string( name ) + ")";
    for( const std::string& probe : { bare, elabS, elabC } )
    {
        const std::size_t at = compact.find( probe );
        if( at == std::string_view::npos )
        {
            continue;
        }

        // `sizeof(X)==N` — the literal runs to the next `,` or `)`, or to the end of the argument.
        const std::size_t after = at + probe.size();
        if( compact.compare( after, 2, "==" ) == 0 )
        {
            const std::size_t stop = std::min( std::min( compact.find( ',', after ), compact.find( ')', after ) ), compact.size() );
            if( wholeIntLiteral( compact, after + 2, stop, out ) )
            {
                return true;
            }
        }

        // `N==sizeof(X)` — the same comparison written the other way round.
        if( at >= 3 && compact.compare( at - 2, 2, "==" ) == 0 )
        {
            std::size_t start = at - 2;
            while( start > 0 && std::isdigit( (unsigned char)compact[start - 1] ) != 0 )
            {
                --start;
            }
            if( wholeIntLiteral( compact, start, at - 2, out ) )
            {
                return true;
            }
        }
    }
    return false;
}

// Every `static_assert` / `_Static_assert` in ONE file whose argument mentions `name`, appended to `rows`.
inline void scanFileForAsserts( std::string_view src, const std::string& path, std::string_view name,
                                std::vector<AssertRow>& rows )
{
    static constexpr std::string_view kKeywords[] = { "static_assert", "_Static_assert" };
    for( std::string_view kw : kKeywords )
    {
        forEachKeywordCall( src, kw, [ & ]( std::size_t at, std::size_t close, std::string_view inner )
                            {
            if( !containsWord( inner, name ) ) { return;
}

            AssertRow row;
            row.path = path;
            row.line = lineOf( src, at );
            row.text = flattenSpace( src.substr( at, close - at ), kMaxAssertChars );

            const std::string compact = squeeze( inner );
            if     ( extractSizeAssert( compact, "sizeof",  name, row.want ) ) { row.kind = "sizeof";  row.hasWant = true; }
            else if( extractSizeAssert( compact, "alignof", name, row.want ) ) { row.kind = "alignof"; row.hasWant = true; }
            rows.push_back( std::move( row ) ); } );
    }
}

inline std::vector<AssertRow> collectAsserts( const IngestResult& ing, std::string_view name, std::size_t& filesScanned )
{
    std::vector<AssertRow> rows;
    for( std::uint32_t fileId = 0; fileId < ing.files.size(); ++fileId )
    {
        if( !isCFamilyPath( ing.files[fileId] ) )
        {
            continue;
        }
        const std::optional<std::string> bytes = darkflags::readWhole( diskPath( ing, fileId ) );
        if( !bytes )
        {
            continue;
        }
        ++filesScanned;
        if( bytes->find( name ) == std::string::npos )
        {
            continue; // cheap reject before the keyword walk
        }
        scanFileForAsserts( *bytes, ing.files[ fileId ], name, rows );
    }

    std::sort( rows.begin(), rows.end(), []( const AssertRow& a, const AssertRow& b )
               { return ( a.path != b.path ) ? ( a.path < b.path ) : ( a.line < b.line ); } );
    return rows;
}

// ── the mirror comparison ────────────────────────────────────────────────────────────────────────────

inline std::string fieldSpell( const FieldRow& f )
{
    std::string s = f.resolved.empty() ? f.type : f.resolved;
    if( f.elems != 1 )
    {
        s += " x" + std::to_string( f.elems );
    }
    if( f.placed )
    {
        s += "@" + std::to_string( f.offset );
    }
    if( f.bitWidth != 0 )
    {
        s += ":" + std::to_string( f.bitOffset ) + "+" + std::to_string( f.bitWidth );
    }
    return s;
}

inline std::string siteSpell( const LayoutDef& d ) { return d.path + ":" + std::to_string( d.line ); }

// Field-by-field diff of two definitions, keyed by NAME (an added/removed/retyped/moved field is what a
// reader needs to see; a pure reorder shows up as two moved offsets, which is exactly right).
inline MirrorDiff diffDefs( const LayoutDef& a, const LayoutDef& b )
{
    MirrorDiff diff;
    diff.a           = siteSpell( a );
    diff.b           = siteSpell( b );
    diff.sizeA       = a.size;
    diff.sizeB       = b.size;
    diff.sizeDiffers = a.modeled && b.modeled && a.size != b.size;
    diff.stubOnly    = a.fields.empty() != b.fields.empty();
    diff.kind        = diff.stubOnly                  ? "stub"
                     : ( a.byteShape == b.byteShape ) ? "spelling"
                                                      : "drift";

    gtl::btree_map<std::string, const FieldRow*> byNameB;
    for( const FieldRow& f : b.fields )
    {
        byNameB.emplace( f.name, &f );
    }

    gtl::btree_map<std::string, bool> seen;
    for( const FieldRow& fa : a.fields )
    {
        seen.emplace( fa.name, true );
        const auto it = byNameB.find( fa.name );
        if( it == byNameB.end() ) { diff.fields.push_back( FieldDiff{ fa.name, fieldSpell( fa ), "absent" } ); continue; }
        const std::string sa = fieldSpell( fa ), sb = fieldSpell( *it->second );
        if( sa != sb )
        {
            diff.fields.push_back( FieldDiff { fa.name, sa, sb } );
        }
    }
    for( const FieldRow& fb : b.fields )
    {
        if( seen.find( fb.name ) == seen.end() )
        {
            diff.fields.push_back( FieldDiff{ fb.name, "absent", fieldSpell( fb ) } );
        }
    }
    return diff;
}

// ── the whole computation ────────────────────────────────────────────────────────────────────────────

// The modelled definition a `sizeof(X)==N` tripwire should be compared against. The assert's OWN FILE wins
// — a mirror pair legitimately has two different sizes and two different asserts. The single agreed size
// is a fallback ONLY when the assert's file defines the type nowhere: a same-file definition that could not
// be modelled must not be scored against a DIFFERENT file's copy, which on the motivating repo turned an
// unsized `simd::float3` field into a phantom "sizeof(X)==48 but the computed size is 1", quoting a stub
// header the assert had never seen. Returns nullptr when there is nothing sound to compare with.
inline const LayoutDef* defForAssert( const LayoutResult& result, const AssertRow& row )
{
    bool sameFile = false;
    for( const LayoutDef& d : result.defs )
    {
        if( d.path != row.path )
        {
            continue;
        }
        sameFile = true;
        if( d.modeled )
        {
            return &d;
        }
    }
    if( sameFile )
    {
        return nullptr;
    }

    const LayoutDef* only = nullptr;
    for( const LayoutDef& d : result.defs )
    {
        if( !d.modeled )
        {
            continue;
        }
        if( only == nullptr )
        {
            only = &d;
        }
        else if( only->size != d.size || only->align != d.align )
        {
            return nullptr; // no single answer
        }
    }
    return only;
}

inline void scoreAsserts( LayoutResult& result )
{
    for( AssertRow& row : result.asserts )
    {
        if( !row.hasWant )
        {
            continue;
        }
        const LayoutDef* pick = defForAssert( result, row );
        if( pick == nullptr )
        {
            continue;
        }

        row.got      = ( std::string_view( row.kind ) == "alignof" ) ? pick->align : pick->size;
        row.compared = true;
        row.agree    = row.got == row.want;
        if( !row.agree )
        {
            ++result.assertConflicts;
        }
    }
}

inline LayoutResult computeLayout( const IngestResult& ing, std::string_view spec )
{
    LayoutResult     result;
    std::string_view fileFilter, name;
    splitQualifiedSpec( spec, fileFilter, name );
    result.sym = std::string( name );
    if( name.empty() )
    {
        return result;
    }

    const AggIndex byName = buildAggIndex( ing );
    const auto     hit    = byName.find( std::string( name ) );
    if( hit == byName.end() )
    {
        return result;
    }

    ModelCtx                            ctx( ing, byName );
    gtl::btree_map<std::uint64_t, bool> seenSite;                      // (fileId, braceStart) — the typedef twin
    for( NodeId id : hit->second )
    {
        const Symbol& s = ing.symbols[ id ];
        if( !fileFilter.empty() && ing.files[s.fileId].find( fileFilter ) == std::string::npos )
        {
            continue;
        }

        // Only a C-family aggregate HAS a byte layout. A TypeScript / Swift / Java `class Cat {` opens a
        // brace after the word `class` and would otherwise be modelled as a C++ struct — and then compared
        // as a "mirror" of an unrelated C++ struct of the same name. Counted as bodiless so the refusal
        // says "this verb models C/C++/ObjC byte layout only" rather than "no such struct".
        if( !isCFamilyPath( ing.files[ s.fileId ] ) ) { ++result.bodilessCandidates; continue; }

        DefSite site;
        {
            const std::string& src = fileBytes( ctx, s.fileId );
            if( src.empty() )
            {
                DISCLOSE( result, LayoutResult::DisclosureWhy::UnreadableFile, "layout: cannot read a definition's file — that definition is omitted" );
                continue;
            }
            if( !findDefBody( src, name, s.sigStartByte, site ) )
            {
                if( site.isEnum ) { ++result.enumCandidates; }
                else
                {
                    ++result.bodilessCandidates;
                }
                continue;
            }
        }
        site.fileId = s.fileId;
        const std::uint64_t key = ( std::uint64_t( s.fileId ) << 32 ) | std::uint64_t( site.braceStart & 0xFFFFFFFFull );
        if( seenSite.find( key ) != seenSite.end() )
        {
            continue;
        }
        seenSite.emplace( key, true );

        result.found = true;
        ++result.defsFound;
        if( result.defs.size() < kMaxDefsShown )
        {
            result.defs.push_back( modelDef( ctx, s.fileId, site, name ) );
        }
    }
    result.stdTableUsed = ctx.stdTableUsed;
    if( !result.found )
    {
        return result;
    }

    std::sort( result.defs.begin(), result.defs.end(), []( const LayoutDef& a, const LayoutDef& b )
               { return ( a.path != b.path ) ? ( a.path < b.path ) : ( a.line < b.line ); } );

    // Mirrors: every later definition against the first. Identical spellings AND identical bytes are the
    // normal, quiet case and emit nothing.
    for( std::size_t i = 1; i < result.defs.size(); ++i )
    {
        const LayoutDef& a = result.defs.front();
        const LayoutDef& b = result.defs[i];
        if( a.spellShape == b.spellShape )
        {
            continue;
        }
        result.mirrors.push_back( diffDefs( a, b ) );
    }

    result.asserts = collectAsserts( ing, name, result.filesScanned );
    scoreAsserts( result );
    return result;
}

// ── XML emission (G4: minified, xmllint-clean; no `\n` outside CDATA, no double hyphen in a comment) ──

using XmlEscaper = std::function<std::string( std::string_view )>;

// One <f> row: name, type as written, expansion, extent, bitfield position, size (or why it has none), offset.
inline void writeFieldRow( std::FILE* out, const FieldRow& f, const XmlEscaper& ex )
{
    rw::emitTo( out, "<f n=\"{}\" ty=\"{}\"", ex( f.name ).c_str(), ex( f.type ).c_str() );
    if( !f.resolved.empty() )
    {
        rw::emitTo( out, " as=\"{}\"", ex( f.resolved ).c_str() );
    }
    if( f.elems != 1 )
    {
        rw::emitTo( out, " x=\"{}\"", f.elems );
    }
    if( f.bitWidth != 0 )
    {
        rw::emitTo( out, " bits=\"{}\" bit=\"{}\"", f.bitWidth, f.bitOffset );
    }
    if( f.sized )
    {
        rw::emitTo( out, " sz=\"{}\" al=\"{}\"", f.size, f.align );
    }
    else
    {
        rw::emitTo( out, " sized=\"0\" why=\"{}\"", ex( f.why.empty() ? std::string_view( "unknown-type" ) : std::string_view( f.why ) ).c_str() );
    }
    if( f.placed )
    {
        rw::emitTo( out, " off=\"{}\"", f.offset );
    }
    rw::emitRaw( out, "/>" );
}

// `rootPrefix` empty ⇒ p= keeps def.path unchanged (multi-root, or no single root to strip) — R-E
// (2026-08-17 harvest): def.path is an already-materialized copy of ing.files[fileId], relativized here at
// print time exactly like every other lens's pathRel.
inline void writeLayoutDef( std::FILE* out, const LayoutDef& def, const XmlEscaper& ex, std::string_view rootPrefix = {} )
{
    const std::string_view rp = rootPrefix.empty() ? std::string_view( def.path ) : rw::sarif::rootRelativeUri( def.path, rootPrefix );
    rw::emitTo( out, "<def p=\"{}\" l=\"{}\" agg=\"{}\" modeled=\"{}\" fields=\"{}\"",
                  ex( rp ).c_str(), def.line, def.aggregate, def.modeled ? 1 : 0, def.fields.size() );
    if( def.modeled )
    {
        rw::emitTo( out, " size=\"{}\" align=\"{}\" tail_pad=\"{}\"", def.size, def.align, def.tailPad );
    }
    if( def.declaredAlign )
    {
        rw::emitTo( out, " alignas=\"{}\"", def.declaredAlign );
    }
    if( def.packedAttr )
    {
        rw::emitRaw( out, " packed=\"1\"" );
    }
    if( !def.baseSpec.empty() )
    {
        rw::emitTo( out, " base=\"{}\"", ex( flattenSpace( def.baseSpec, 160 ) ).c_str() );
        if( def.baseSized )
        {
            rw::emitTo( out, " base_sz=\"{}\"", def.baseSize );
        }
    }
    rw::emitRaw( out, ">" );

    for( const FieldRow& f : def.fields )
    {
        if( f.padBefore )
        {
            rw::emitTo( out, "<pad bytes=\"{}\"/>", f.padBefore );
        }
        writeFieldRow( out, f, ex );
    }
    if( def.modeled && def.tailPad )
    {
        rw::emitTo( out, "<pad tail=\"{}\"/>", def.tailPad );
    }
    for( const Caveat& c : def.caveats )
    {
        rw::emitTo( out, "<caveat k=\"{}\" d=\"{}\"", ex( c.kind ).c_str(), ex( c.detail ).c_str() );
        if( c.count > 1 )
        {
            rw::emitTo( out, " count=\"{}\"", c.count ); // §P6.12: how many sites this ONE row stands for
        }
        rw::emitRaw( out, "/>" );
    }
    rw::emitRaw( out, "</def>" );
}

// `rootArg` — R-E (2026-08-17 harvest), same single-root-only root argument serialize() takes.
inline void writeLayout( std::FILE* out, const LayoutResult& res, std::string_view rootArg = {} )
{
    std::vector<char> esc;
    const XmlEscaper  ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };
    const std::string rootPrefix = rootArg.empty() ? std::string() : rw::sarif::rootPrefixOf( rootArg );
    // MirrorDiff::a/b are pre-formatted "path:line" strings (built where the two mirror sides are joined) —
    // relativize the path portion only, splitting at the LAST ':' so a Windows-drive-letter-free path with
    // no colon of its own (every indexed path here) is unambiguous.
    const auto relPathLine = [ & ]( const std::string& pathLine ) -> std::string
    {
        if( rootPrefix.empty() ) { return pathLine; }
        const std::size_t colon = pathLine.rfind( ':' );
        if( colon == std::string::npos ) { return pathLine; }
        return std::string( rw::sarif::rootRelativeUri( std::string_view( pathLine ).substr( 0, colon ), rootPrefix ) )
             + std::string( std::string_view( pathLine ).substr( colon ) );
    };

    bool drift = false, stub = false, spelling = false;
    for( const MirrorDiff& m : res.mirrors )
    {
        const std::string_view k = m.kind;
        if( k == "drift" )
        {
            drift = true;
        }
        else if( k == "stub" )
        {
            stub = true;
        }
        else
        {
            spelling = true;
        }
    }
    const char* mirror = drift    ? "mismatch"
                       : stub     ? "stub"
                       : spelling ? "spelling"
                       : ( res.defsFound > 1 ? "match" : "single" );

    // G4: an XML comment may not contain a double hyphen, so this text names flags WITHOUT their leading
    // dashes. Keep it that way when editing.
    rw::emitTo( out, "<!-- ripwire layout: field offsets COMPUTED from the source text under standard-layout "
                       "assumptions on a 64-bit Apple/LP64 target (natural alignment, interior padding, trailing pad to "
                       "the aggregate's own alignment). NOT the ABI: pragma pack, bitfields wider than a byte, virtuals, "
                       "several or virtual bases, nested aggregates, preprocessor-conditional members and unsized field types "
                       "are DETECTED and set modeled=\"0\" with a caveat rather than numbered, and each unsized member says "
                       "why=; one base class sits at offset 0 (base= base_sz=); 1-byte bitfields carry bits= bit=; std:: "
                       "members are sized from the standard library named by std_abi=; a caveat row's count=\"N\" means that ONE row stands "
                       "for N member sites of the same kind (absent = one). Every same-name definition is compared: "
                       "kind=\"drift\" means the BYTE contract differs (the bug this verb exists for, and the only one that "
                       "exits non-zero); kind=\"stub\" is an empty placeholder aggregate and kind=\"spelling\" is the two "
                       "arms of one ifdef block naming the same bytes differently (simd::float4 vs float4) — both reported, "
                       "neither a break. agree=\"0\" on an assert row means a sizeof tripwire contradicts the computed size. "
                       "Definitions and asserts come from the INDEXED files.{} -->{}",
                 res.unreadableDefs != 0 ? " unreadable=\"N\": N same-name definitions whose file could not be read when this ran —"
                                           " absent from defs= and from the mirror comparison, so mirror= compares only what was read (exit 3: not verified)." : "",
                 rw::rootRelPathsLegend( !rootArg.empty() )  );   // R-E fix (2026-08-19): defines root= (graphlegend.h)
    const std::string layoutRootAttr = rootArg.empty() ? std::string() : ( " root=\"" + ex( rootArg ) + "\"" );
    const std::string unreadableAttr = res.unreadableDefs != 0 ? ( " unreadable=\"" + std::to_string( res.unreadableDefs ) + "\"" ) : std::string();
    const std::string stdAbiAttr = res.stdTableUsed ? ( " std_abi=\"" + std::string( kStdAbi ) + "\"" ) : std::string();
    rw::emitTo( out, "<layout sym=\"{}\" found=\"{}\" defs=\"{}\" mirror=\"{}\" asserts=\"{}\" conflicts=\"{}\" scanned=\"{}\"{}{}{}>",
                  ex( res.sym ).c_str(), res.found ? 1 : 0, res.defsFound, mirror, res.asserts.size(),
                  res.assertConflicts, res.filesScanned, unreadableAttr.c_str(), stdAbiAttr.c_str(), layoutRootAttr.c_str() );

    for( const LayoutDef& d : res.defs )
    {
        writeLayoutDef( out, d, ex, rootPrefix );
    }
    if( res.defsFound > res.defs.size() )
    {
        rw::emitTo( out, "<more defs=\"{}\"/>", res.defsFound - res.defs.size() );
    }

    for( const MirrorDiff& m : res.mirrors )
    {
        rw::emitTo( out, "<mismatch kind=\"{}\" a=\"{}\" b=\"{}\" size_a=\"{}\" size_b=\"{}\" size_differs=\"{}\" diffs=\"{}\">",
                      m.kind, ex( relPathLine( m.a ) ).c_str(), ex( relPathLine( m.b ) ).c_str(),
                      m.sizeA, m.sizeB, m.sizeDiffers ? 1 : 0, m.fields.size() );
        for( const FieldDiff& f : m.fields )
        {
            rw::emitTo( out, "<d n=\"{}\" a=\"{}\" b=\"{}\"/>", ex( f.name ).c_str(), ex( f.inA ).c_str(), ex( f.inB ).c_str() );
        }
        rw::emitRaw( out, "</mismatch>" );
    }

    for( const AssertRow& a : res.asserts )
    {
        const std::string_view arp = rootPrefix.empty() ? std::string_view( a.path ) : rw::sarif::rootRelativeUri( a.path, rootPrefix );
        rw::emitTo( out, "<assert p=\"{}\" l=\"{}\" kind=\"{}\"", ex( arp ).c_str(), a.line, a.kind );
        if( a.hasWant )
        {
            rw::emitTo( out, " want=\"{}\"", a.want );
        }
        if( a.compared )
        {
            rw::emitTo( out, " got=\"{}\" agree=\"{}\"", a.got, a.agree ? 1 : 0 );
        }
        rw::emitTo( out, " t=\"{}\"/>", ex( a.text ).c_str() );
    }
    rw::emitRaw( out, "</layout>" );
}

}}   // namespace rw::layout
