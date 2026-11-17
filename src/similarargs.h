#pragma once

// similarargs.h — the scanner behind --quality-delta's similar-argument-list signal (QD-SWAP-1117, a PROTOTYPE).
//
// The shape: a run of adjacent parameters with ONE written type and different names — f( task, answer ),
// g( at, nameAt, nameEnd, fileId, line ). A call that swaps two of them compiles and runs wrong. clang-tidy names it
// bugprone-easily-swappable-parameters; this is the part of that check a signature's own bytes decide.
//
// OFF BY DEFAULT. The rows print only when RIPWIRE_QD_SIMILAR_ARGS is set in the environment (similarArgsOn), and they
// never gate: the owner decides whether the signal becomes a default. With the variable unset no answer changes.
//
// What is read: the signature text of one C or C++ function or method definition (quality.h hands in
// [sigStartByte, sigEndByte)), as defectshape.h's C++ tokens (comments dropped). The parameter list opens at the `(`
// after the definition's own name and closes at its match; it is split at commas outside ( ) [ ] { } < >; a default
// (`= …`) is dropped; the last identifier is the name and the tokens before it, joined, are the written type.
//
// PRECISION BEFORE RECALL. Each of these answers "no run", a stated miss and never a finding:
//   - a parameter with no name, a function-pointer parameter, a pack (`Args&&... args`), a C variadic `...`;
//   - a type that is bool or ends in an iterator spelling (clang-tidy's own defaults: flags and iterator pairs);
//   - a run of exactly two whose names are a range or a symmetric pair (kPairedNames: begin/end, from/to, a/b, …);
//   - two parameters whose types are one type under an alias (NodeId beside std::uint32_t): written types are compared;
//   - a signature whose name is not followed by `(` in the text (an operator, a macro-built definition).
// It does not read the body, so it cannot tell that two parameters are used together (a comparator's ( a, b ) is
// caught by the name list only).

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>

#include "defectshape.h"   // the C++ lexer (lexCpp, Tok, joinTokens): one tokenizer for every signature-text rule

namespace rw::similarargs
{

// The prototype's switch: the rows exist only when the variable is set (any value).
inline bool similarArgsOn() noexcept
{
    return std::getenv( "RIPWIRE_QD_SIMILAR_ARGS" ) != nullptr;
}

// A run shorter than this is not a list of similar arguments.
inline constexpr std::uint32_t kSimilarRunMin = 2;

// Name pairs that say "a range" or "the two sides of one symmetric test": a run of exactly these two is not reported.
struct PairedNames
{
    std::string_view first;
    std::string_view second;
};
inline constexpr std::array<PairedNames, 15> kPairedNames = { {
    { "begin", "end" }, { "first", "last" }, { "from", "to" }, { "lo", "hi" }, { "start", "stop" }, { "start", "end" }, { "open", "close" },
    { "lhs", "rhs" },   { "a", "b" },        { "x", "y" },     { "i", "j" },   { "l", "r" },        { "left", "right" }, { "min", "max" },
    { "u", "v" },
} };

// A word that can end a parameter without being its name: the parameter is unnamed (`const int`, `unsigned`).
inline constexpr std::array<std::string_view, 16> kTypeWords = { "const", "volatile", "int",    "char",  "bool", "auto",     "unsigned", "signed",
                                                                 "long",  "short",    "double", "float", "void", "restrict", "size_t",   "noexcept" };

// One definition's signature bytes and its own name (two string_views, named at the call: this file's own shape).
struct SignatureText
{
    std::string_view text;
    std::string_view name;
};

namespace detail
{
using defectshape::detail::Tok;
using defectshape::detail::TokKind;
using defectshape::detail::tokIs;
using defectshape::detail::tokText;

// A signature and its tokens: what every step below reads.
struct Lexed
{
    std::string_view src;
    std::vector<Tok> toks;

    std::string_view text( std::size_t k ) const noexcept { return tokText( src, toks[k] ); }
};

// One parameter as written: its type (the tokens joined by single spaces) and its name. `named` false = it ends a run.
struct Param
{
    std::string      type;
    std::string_view name;
    bool             named = false;
};

// A parameter's tokens: [first, past).
struct TokSpan
{
    std::size_t first = 0;
    std::size_t past  = 0;
};

// How a token moves the bracket depth: `>>` closes two template brackets, `->` (one token) none.
inline int depthStep( std::string_view t ) noexcept
{
    constexpr std::string_view kOpeners = "([{<";
    constexpr std::string_view kClosers = ")]}>";
    if( t.size() != 1 )
    {
        return t == ">>" ? -2 : 0;
    }
    return kOpeners.contains( t.front() ) ? 1 : kClosers.contains( t.front() ) ? -1 : 0;
}

// The token after the `(` that opens the parameter list of the definition named `name`, or the token count: the first
// place the name is followed by `(`.
inline std::size_t parameterListOpen( const Lexed& sig, std::string_view name ) noexcept
{
    for( std::size_t k = 0; k + 1 < sig.toks.size(); ++k )
    {
        if( sig.toks[k].kind == TokKind::Ident && sig.text( k ) == name && sig.text( k + 1 ) == "(" )
        {
            return k + 2;
        }
    }
    return sig.toks.size();
}

// The parameters of the list whose first token is `open`, split at depth-0 commas. Empty when the list never closes.
inline std::vector<TokSpan> splitParameters( const Lexed& sig, std::size_t open )
{
    std::vector<TokSpan> parts;
    int                  depth = 0;
    std::size_t          first = open;
    for( std::size_t k = open; k < sig.toks.size(); ++k )
    {
        const std::string_view t = sig.text( k );
        if( depth == 0 && ( t == ")" || t == "," ) )
        {
            parts.push_back( { first, k } );
            if( t == ")" )
            {
                return parts;
            }
            first = k + 1;
            continue;
        }
        depth = std::max( 0, depth + depthStep( t ) );
    }
    return {};
}

// The span without its default (cut at the first depth-0 `=`) and without a trailing array bound (`counts[4]`).
inline TokSpan declaratorSpan( const Lexed& sig, TokSpan p ) noexcept
{
    int depth = 0;
    for( std::size_t k = p.first; k < p.past; ++k )
    {
        if( depth == 0 && sig.text( k ) == "=" )
        {
            p.past = k;
            break;
        }
        depth = std::max( 0, depth + depthStep( sig.text( k ) ) );
    }
    if( p.past > p.first && sig.text( p.past - 1 ) == "]" )
    {
        while( p.past > p.first && sig.text( p.past - 1 ) != "[" )
        {
            --p.past;
        }
        p.past -= p.past > p.first ? 1 : 0;
    }
    return p;
}

inline Param parseParameter( const Lexed& sig, TokSpan whole )
{
    const TokSpan p = declaratorSpan( sig, whole );
    Param         out;
    if( p.past < p.first + 2 || sig.toks[ p.past - 1 ].kind != TokKind::Ident )
    {
        return out;   // one token (an unnamed type), or it ends in punctuation (a function pointer, a reference with no name)
    }
    out.name = sig.text( p.past - 1 );
    out.type = defectshape::detail::joinTokens( sig.src, sig.toks, p.first, p.past - 2 );
    const bool hasPack = out.type.find( "..." ) != std::string::npos;
    out.named          = !std::ranges::contains( kTypeWords, out.name ) && !out.type.ends_with( "::" ) && !hasPack;
    return out;
}

// clang-tidy's default exclusions: a flag pair and an iterator pair are their own conventions.
inline bool isExcludedType( std::string_view type ) noexcept
{
    while( type.ends_with( " &" ) || type.ends_with( " *" ) )
    {
        type.remove_suffix( 2 );
    }
    return type == "bool" || type == "const bool" || type.ends_with( "It" ) || type.ends_with( "terator" );
}

inline bool isPairedNames( std::string_view a, std::string_view b )
{
    const auto lower = []( std::string_view w )
    {
        std::string out( w );
        std::ranges::transform( out, out.begin(), []( char c ) { return c >= 'A' && c <= 'Z' ? char( c - 'A' + 'a' ) : c; } );
        return out;
    };
    const std::string la = lower( a );
    const std::string lb = lower( b );
    return std::ranges::any_of( kPairedNames, [ & ]( const PairedNames& pair )
                                { return ( la == pair.first && lb == pair.second ) || ( la == pair.second && lb == pair.first ); } );
}

// Is the run params[first, past) one this file reports: named, one type, every name different, not an excluded type or pair?
inline bool isReportedRun( const std::vector<Param>& params, TokSpan run )
{
    const std::size_t count = run.past - run.first;
    if( count < kSimilarRunMin || isExcludedType( params[ run.first ].type ) )
    {
        return false;
    }
    for( std::size_t a = run.first; a < run.past; ++a )
    {
        for( std::size_t b = a + 1; b < run.past; ++b )
        {
            if( params[a].name == params[b].name )
            {
                return false;
            }
        }
    }
    return !( count == 2 && isPairedNames( params[ run.first ].name, params[ run.first + 1 ].name ) );
}
} // namespace detail

// The longest run of adjacent parameters with one written type and different names in the definition's signature
// text; 0 when there is none of kSimilarRunMin or more (see the misses in this file's header).
inline std::uint32_t longestSimilarRun( SignatureText of )
{
    const detail::Lexed        sig{ of.text, defectshape::detail::lexCpp( of.text ) };
    std::vector<detail::Param> params;
    for( const detail::TokSpan span : detail::splitParameters( sig, detail::parameterListOpen( sig, of.name ) ) )
    {
        params.push_back( detail::parseParameter( sig, span ) );
    }
    std::uint32_t best = 0;
    for( std::size_t k = 0; k < params.size(); )
    {
        std::size_t past = k + 1;
        while( params[k].named && past < params.size() && params[past].named && params[past].type == params[k].type )
        {
            ++past;
        }
        if( detail::isReportedRun( params, { k, past } ) )
        {
            best = std::max( best, std::uint32_t( past - k ) );
        }
        k = past;
    }
    return best;
}

} // namespace rw::similarargs
