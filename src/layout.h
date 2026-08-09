#pragma once

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
#include "graph.h"        // splitQualifiedSpec — the ONE `file:name` disambiguation rule --around/--lego use
#include "arch.h"         // fnv1a64
#include "infra/hashutil.h"     // fnv1aMultiply — the sanitizer-safe wrapping multiply (G1 runs -fsanitize=integer)
#include "serialize.h"    // escapeXml
#include "darkflags.h"    // readWhole — the same 4 MB-capped whole-file read the sibling field-notes verb owns
#include "Diagnostics.h"  // VERIFY / DEGRADED_PATH_ALERT

#include "btree.hpp"      // gtl::btree_map — sorted iteration (house rule: never std::map)

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <functional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{
namespace layout
{

// ── tuning constants ─────────────────────────────────────────────────────────────────────────────────

constexpr std::size_t   kMaxNestDepth   = 8;          // nested-aggregate resolution depth (a cycle stops here)
constexpr std::size_t   kMaxMacroDepth  = 4;          // object-like macro expansion depth for a type name
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
    VERIFY( from < src.size() && src[ from ] == open );
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

    std::int64_t apply( char op, std::int64_t a, std::int64_t b )
    {
        if( ( op == '/' ) && b == 0 ) { ok = false; return 0; }        // never divide by zero under G1
        switch( op )
        {
            case '+': return a + b;
            case '-': return a - b;
            case '*': return a * b;
            default:  return a / b;
        }
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
            ++i;
            const std::int64_t v = level( s, i, 0 );
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
    std::uint32_t size  = 0;
    std::uint32_t align = 1;
    bool          known = false;
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
    const std::size_t at = s.rfind( "::" );
    return ( at == std::string_view::npos ) ? s : s.substr( at + 2 );
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
    std::string_view              typeSpec;        // empty on a follow-on declarator (inherits the first's)
    std::string_view              name;
    std::vector<std::string_view> extents;         // one entry per `[…]`, left to right
    bool                          isPointer  = false;
    bool                          isRef      = false;
    bool                          isBitfield = false;
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
        for( std::size_t i = s.size(); i-- > 0; )
        {
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

inline Declarator parseDeclarator( std::string_view text )
{
    Declarator       d;
    std::string_view s = trimView( text );
    if( s.empty() )
    {
        return d;
    }

    d.isBitfield = cutAtTopLevel( s, ":" );        // a bitfield WIDTH — refused later, but recognised here
    cutAtTopLevel( s, "={" );                      // a default member initializer (`= 0`, `= {}`, `{0}`)
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
    for( char c : s.substr( 0, nameStart ) )
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
        if( s.kind == SymKind::Struct || s.kind == SymKind::Class || s.kind == SymKind::Interface )
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

    explicit ModelCtx( const IngestResult& i, const AggIndex& n )
        : ing( i ), byName( n ), bytes( i.files.size() ), stripped( i.files.size() ),
          consts( i.files.size() ), bytesLoaded( i.files.size(), 0 ) {}
};

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
        if( !darkflags::readWhole( diskPath( ctx.ing, fileId ), ctx.bytes[fileId] ) )
        {
            ctx.bytes[fileId].clear();
        }
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
inline TypeSize sizeNestedAggregate( ModelCtx& ctx, std::string_view typeName, std::uint32_t preferFileId, std::string& note )
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

        const LayoutDef d = modelDef( ctx, s.fileId, site, typeName );
        if( !d.modeled ) { note = "nested-unmodelled"; out = TypeSize{}; break; }
        const TypeSize here{ d.size, d.align, true };
        if( first ) { out = here; first = false; }
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

inline ResolvedType resolveFieldType( const TypeScope& scope, std::string_view spec, bool isPointer, bool isRef,
                                      std::size_t macroDepth )
{
    ResolvedType out;
    if( isPointer || isRef ) { out.size = TypeSize{ 8, 8, true }; return out; }   // LP64 data pointer / reference

    bool                          sawEnum = false;
    std::vector<std::string_view> words   = typeWords( spec, sawEnum );
    if( words.empty() )
    {
        return out;
    }
    if( intFamilySize( words, out.size ) )
    {
        return out;
    }

    if( words.size() != 1 )                                { out.note = "compound-type"; return out; }
    if( spec.find( '<' ) != std::string_view::npos )       { out.note = "template-type"; return out; }

    const std::string_view single = words.front();
    if( primLookup( single, out.size ) )
    {
        return out;
    }
    if( resolveThroughAlias( scope, single, macroDepth, out ) )
    {
        return out;
    }
    out.size = TypeSize{};                                             // a failed alias lane leaves no number

    TypeSize nested = sizeNestedAggregate( scope.ctx, single, scope.fileId, out.note );
    if( !nested.known && single != lastSegment( single ) )
    {
        nested = sizeNestedAggregate( scope.ctx, lastSegment( single ), scope.fileId, out.note );
    }
    if( nested.known ) { out.size = nested; return out; }

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

// Read the attributes the aggregate's HEAD text carries (everything from the def start to its `{`).
inline void readHeadAttributes( LayoutDef& def, std::string_view head, std::string_view name )
{
    if( containsWord( head, "union" ) )
    {
        def.aggregate = "union";
    }
    else if( containsWord( head, "class" ) )
    {
        def.aggregate = "class";
    }
    if( containsWord( head, "template" ) )
    {
        def.modeled = false;
        addCaveat( def, "template", "a template's layout depends on its arguments" );
    }

    readDeclaredAlign( def, head );

    if( head.find( "packed" ) != std::string_view::npos && head.find( "__attribute__" ) != std::string_view::npos )
    {
        def.packedAttr = true;
    }

    // A base-class list: a top-level `:` after the name that is not part of a `::`. The base subobject's
    // size and placement are not in this declaration, so the arithmetic has no starting offset.
    const std::size_t nameAt = head.find( name );
    if( nameAt == std::string_view::npos )
    {
        return;
    }
    for( std::size_t i = nameAt + name.size(); i < head.size(); ++i )
    {
        if( head[i] != ':' )
        {
            continue;
        }
        if( ( i + 1 < head.size() && head[ i + 1 ] == ':' ) || ( i > 0 && head[ i - 1 ] == ':' ) ) { ++i; continue; }
        def.modeled = false;
        addCaveat( def, "base-class", "a base subobject's size and placement are not in this declaration" );
        break;
    }
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

    void refuse( std::string kind, std::string detail )
    {
        def.modeled = false;
        placeable   = false;
        addCaveat( def, std::move( kind ), std::move( detail ) );
    }
};

// Fold ONE parsed declarator into the def's field list, advancing the offset cursor when it still can.
inline void appendField( BodyWalk& w, const Declarator& d, std::string_view typeSpec )
{
    // Every string here reaches an XML ATTRIBUTE, which may not carry a raw newline under G4 — a member
    // declaration wrapped over two lines would otherwise emit one.
    FieldRow f;
    f.name = std::string( d.name );
    f.type = flattenSpace( typeSpec, 160 );
    if( d.isPointer )
    {
        f.type += "*";
    }
    if( d.isRef )
    {
        f.type += "&";
    }

    const TypeScope    scope{ w.ctx, w.consts, w.fileId };
    const ResolvedType r = resolveFieldType( scope, typeSpec, d.isPointer, d.isRef );
    TypeSize           t = r.size;
    f.resolved = flattenSpace( r.resolved, 160 );
    if( !r.note.empty() )
    {
        addCaveat( w.def, r.note, f.name + ": " + f.type );
    }
    if( d.isRef )
    {
        addCaveat( w.def, "reference-member", f.name + ": a reference member's storage is unspecified" );
    }

    for( std::string_view e : d.extents )
    {
        std::uint32_t n = 0;
        if( !evalExtent( w.consts, e, n ) || f.elems > kMaxArrayElems / n )
        {
            addCaveat( w.def, "unknown-extent", f.name + "[" + flattenSpace( e, 80 ) + "]" );
            t.known = false;
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

// The statement forms that contribute NO storage and are simply skipped, plus the ones that withdraw the
// numbers. Returns true when the statement was consumed here and holds no field declarators.
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
    const std::size_t paren = s.find( '(' );
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

// Handle one top-level statement inside the aggregate body.
inline void modelStatement( BodyWalk& w, std::string_view stmt )
{
    const std::string_view s = trimView( stmt );
    if( s.empty() || modelNonFieldStatement( w, s ) )
    {
        return;
    }

    const std::vector<std::string_view> parts = splitDeclarators( s );
    std::string_view                    baseType;
    for( std::size_t i = 0; i < parts.size(); ++i )
    {
        const Declarator d = parseDeclarator( parts[i] );
        if( d.isBitfield )
        { w.refuse( "bitfield", "the bit allocation unit and packing order are implementation-defined" ); return; }
        if( !d.ok || ( i == 0 && d.typeSpec.empty() ) )
        { w.refuse( "unparsed-member", flattenSpace( parts[i], 160 ) ); return; }

        if( i == 0 )
        {
            baseType = d.typeSpec;
        }
        appendField( w, d, ( i == 0 ) ? d.typeSpec : baseType );
    }
}

// A `#` that opens a preprocessor DIRECTIVE (only whitespace between it and the line start).
inline bool atDirectiveStart( std::string_view body, std::size_t at )
{
    for( std::size_t i = at; i-- > 0; )
    {
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

// One preprocessor directive line inside the body. An `#if`-family conditional can add or remove fields
// depending on build flags, so it withdraws the numbers; every other directive is merely skipped.
inline std::size_t walkDirective( BodyWalk& w, std::size_t at )
{
    static constexpr std::string_view kConditional[] = { "if", "ifdef", "ifndef", "else", "elif", "endif" };

    std::size_t end = at;
    while( end < w.body.size() && w.body[end] != '\n' )
    {
        ++end;
    }
    const std::string_view d = trimView( w.body.substr( at + 1, end - at - 1 ) );
    for( std::string_view c : kConditional )
    {
        if( d.rfind( c, 0 ) == 0 && ( d.size() == c.size() || !identByte( (unsigned char)d[ c.size() ] ) ) )
        {
            w.refuse( "conditional-members", "a preprocessor conditional inside the body can add or remove fields" );
            break;
        }
    }

    const std::size_t next = std::min( end + 1, w.body.size() );
    if( trimView( w.body.substr( w.stmtStart, ( next > w.stmtStart ) ? next - w.stmtStart : 0 ) ).empty() )
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
    const std::string_view pending    = trimView( pendingRaw );

    if( containsWord( pending, "struct" ) || containsWord( pending, "class" )
        || containsWord( pending, "union" ) || containsWord( pending, "enum" ) )
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

    const bool isInitializer = !pending.empty() && ( pending.back() == '=' || pending.back() == ']'
                                                     || identByte( (unsigned char)pending.back() ) );
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

    for( std::uint64_t part : { std::uint64_t( def.size ), std::uint64_t( def.align ), std::uint64_t( def.modeled ? 1 : 0 ) } )
    {
        foldAll( part );
    }
    for( const FieldRow& f : def.fields )
    {
        fold( byteHash, fnv1a64( f.name ) );
        fold( spellHash, fnv1a64( f.name ) );                       // slotHash deliberately skips the name

        for( std::uint64_t part : { std::uint64_t( f.elems ), std::uint64_t( f.sized ? f.size : 0u ),
                                    std::uint64_t( f.align ), std::uint64_t( f.placed ? f.offset + 1u : 0u ) } )
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

    VERIFY( site.braceStart < site.braceEnd && site.braceEnd <= src.size() );
    const std::string_view whole    = src;
    const std::string      headText = withoutComments( whole.substr( site.headStart, site.braceStart - site.headStart ) );
    readHeadAttributes( def, headText, name );

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
    std::string            bytes;
    for( std::uint32_t fileId = 0; fileId < ing.files.size(); ++fileId )
    {
        if( !isCFamilyPath( ing.files[fileId] ) )
        {
            continue;
        }
        if( !darkflags::readWhole( diskPath( ing, fileId ), bytes ) )
        {
            continue;
        }
        ++filesScanned;
        if( bytes.find( name ) == std::string::npos )
        {
            continue; // cheap reject before the keyword walk
        }
        scanFileForAsserts( bytes, ing.files[ fileId ], name, rows );
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
                DEGRADED_PATH_ALERT( "layout: cannot read a definition's file — that definition is omitted" );
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

inline void writeLayoutDef( std::FILE* out, const LayoutDef& def, const XmlEscaper& ex )
{
    std::fprintf( out, "<def p=\"%s\" l=\"%u\" agg=\"%s\" modeled=\"%d\" fields=\"%zu\"",
                  ex( def.path ).c_str(), def.line, def.aggregate, def.modeled ? 1 : 0, def.fields.size() );
    if( def.modeled )
    {
        std::fprintf( out, " size=\"%u\" align=\"%u\" tail_pad=\"%u\"", def.size, def.align, def.tailPad );
    }
    if( def.declaredAlign )
    {
        std::fprintf( out, " alignas=\"%u\"", def.declaredAlign );
    }
    if( def.packedAttr )
    {
        std::fprintf( out, " packed=\"1\"" );
    }
    std::fprintf( out, ">" );

    for( const FieldRow& f : def.fields )
    {
        if( f.padBefore )
        {
            std::fprintf( out, "<pad bytes=\"%u\"/>", f.padBefore );
        }
        std::fprintf( out, "<f n=\"%s\" ty=\"%s\"", ex( f.name ).c_str(), ex( f.type ).c_str() );
        if( !f.resolved.empty() )
        {
            std::fprintf( out, " as=\"%s\"", ex( f.resolved ).c_str() );
        }
        if( f.elems != 1 )
        {
            std::fprintf( out, " x=\"%u\"", f.elems );
        }
        if( f.sized )
        {
            std::fprintf( out, " sz=\"%u\" al=\"%u\"", f.size, f.align );
        }
        else
        {
            std::fprintf( out, " sized=\"0\"" );
        }
        if( f.placed )
        {
            std::fprintf( out, " off=\"%u\"", f.offset );
        }
        std::fprintf( out, "/>" );
    }
    if( def.modeled && def.tailPad )
    {
        std::fprintf( out, "<pad tail=\"%u\"/>", def.tailPad );
    }
    for( const Caveat& c : def.caveats )
    {
        std::fprintf( out, "<caveat k=\"%s\" d=\"%s\"", ex( c.kind ).c_str(), ex( c.detail ).c_str() );
        if( c.count > 1 )
        {
            std::fprintf( out, " count=\"%u\"", c.count ); // §P6.12: how many sites this ONE row stands for
        }
        std::fprintf( out, "/>" );
    }
    std::fprintf( out, "</def>" );
}

inline void writeLayout( std::FILE* out, const LayoutResult& res )
{
    std::vector<char> esc;
    const XmlEscaper  ex = [ & ]( std::string_view s ) { return std::string( escapeXml( s, esc ) ); };

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
    std::fprintf( out, "<!-- ripwire layout: field offsets COMPUTED from the source text under standard-layout "
                       "assumptions on a 64-bit Apple/LP64 target (natural alignment, interior padding, trailing pad to "
                       "the aggregate's own alignment). NOT the ABI: pragma pack, bitfields, virtuals, base classes, "
                       "nested aggregates, preprocessor-conditional members and unsized field types are DETECTED and set "
                       "modeled=\"0\" with a caveat rather than numbered. Every same-name definition is compared: "
                       "kind=\"drift\" means the BYTE contract differs (the bug this verb exists for, and the only one that "
                       "exits non-zero); kind=\"stub\" is an empty placeholder aggregate and kind=\"spelling\" is the two "
                       "arms of one ifdef block naming the same bytes differently (simd::float4 vs float4) — both reported, "
                       "neither a break. agree=\"0\" on an assert row means a sizeof tripwire contradicts the computed size. "
                       "Definitions and asserts come from the INDEXED files. -->" );
    std::fprintf( out, "<layout sym=\"%s\" found=\"%d\" defs=\"%zu\" mirror=\"%s\" asserts=\"%zu\" conflicts=\"%u\" scanned=\"%zu\">",
                  ex( res.sym ).c_str(), res.found ? 1 : 0, res.defsFound, mirror, res.asserts.size(),
                  res.assertConflicts, res.filesScanned );

    for( const LayoutDef& d : res.defs )
    {
        writeLayoutDef( out, d, ex );
    }
    if( res.defsFound > res.defs.size() )
    {
        std::fprintf( out, "<more defs=\"%zu\"/>", res.defsFound - res.defs.size() );
    }

    for( const MirrorDiff& m : res.mirrors )
    {
        std::fprintf( out, "<mismatch kind=\"%s\" a=\"%s\" b=\"%s\" size_a=\"%u\" size_b=\"%u\" size_differs=\"%d\" diffs=\"%zu\">",
                      m.kind, ex( m.a ).c_str(), ex( m.b ).c_str(),
                      m.sizeA, m.sizeB, m.sizeDiffers ? 1 : 0, m.fields.size() );
        for( const FieldDiff& f : m.fields )
        {
            std::fprintf( out, "<d n=\"%s\" a=\"%s\" b=\"%s\"/>", ex( f.name ).c_str(), ex( f.inA ).c_str(), ex( f.inB ).c_str() );
        }
        std::fprintf( out, "</mismatch>" );
    }

    for( const AssertRow& a : res.asserts )
    {
        std::fprintf( out, "<assert p=\"%s\" l=\"%u\" kind=\"%s\"", ex( a.path ).c_str(), a.line, a.kind );
        if( a.hasWant )
        {
            std::fprintf( out, " want=\"%u\"", a.want );
        }
        if( a.compared )
        {
            std::fprintf( out, " got=\"%u\" agree=\"%d\"", a.got, a.agree ? 1 : 0 );
        }
        std::fprintf( out, " t=\"%s\"/>", ex( a.text ).c_str() );
    }
    std::fprintf( out, "</layout>" );
}

}}   // namespace rw::layout
