#pragma once
// naminglens.h — identifier-naming quality lens v1: the naming-* built-in --lint rules.
//
// Deterministic, dictionary-free, ML-free. Every rule is a
// LENS over facts the index already holds (symbol name / kind / lang / scope / spans) plus the raw
// signature and body bytes — never a verdict. The false-positive discipline is the whole game:
// a rule fires ONLY when its needed fact is KNOWN (an unresolvable return type keeps
// naming-predicate / naming-setter silent; an un-indexed loop local can never be flagged).
//
// WITHDRAWN — naming-body-mismatch (name↔body zero-vocabulary-overlap). Measured on ripwire's own
// src/ at the commit that shipped it, the rule produced 159 of the lens's 217 naming findings — 73% of
// the whole signal from the rule labelled weakest-confidence — and the flagged set was dominated by the
// BEST names in the tree (didYouMean, transitiveCallers, symbolAdjacency, contractGraph): a good
// abstraction name states INTENT while its body states MECHANISM, so zero overlap is the signature of
// successful abstraction, not of a bad name. The axis is non-monotonic with quality — near-0 holds
// great abstractions AND genuine lies — so no threshold on it has a defensible direction and it cannot
// be a lint rule at any cut. Do not re-add it. The substrate it needed (splitIdentifier, toLowerAscii,
// tokensAgree) is kept below; a corpus-IDF informativeness lens is the successor candidate, and it must
// clear a rename-history precision gate BEFORE it ships — this rule is the proof of why.
//
// The rules (each cites the empirical work it mechanizes; bracketed tags are the lineage):
//   naming-short         — 1–2 letter Function/Method/Var name (Var = module/global role; a
//                          function name is visible far beyond any 20-line scope) [Beniamini/Hofmeister]
//   naming-wordy         — more than 5 split tokens in one name [Butler; AlSuhaibani]
//   naming-series        — foo1/foo2/… digit-suffix siblings sharing a base in one scope [Butler]
//   naming-underscore    — internal consecutive underscores; C-family reserved __x / _X forms [Butler]
//   naming-case          — snake_case and camelCase mixed inside ONE name [Butler]
//   naming-predicate     — is/has/can/should/was name whose KNOWN return type is not bool-like [LAPD A2]
//   naming-setter        — set-prefixed name whose KNOWN return type is not void-like [LAPD A3]
//   naming-confusable    — co-visible pair: edit distance ≤2 (both ≥5 chars), same tokens reordered,
//                          or a bare/digit-suffixed twin [Namesake]
//
// Findings flow through the SAME lint tally/listing as every other built-in rule (AstMatch → runLint),
// under the same per-rule budget semantics: a rule that hits its budget — or a confusable scan too big
// to run in full — is reported saturated, so its count= is disclosed as a FLOOR (§P0.2).
//
// The splitter is a reimplementation of the conservative Spiral heuristic_split semantics (case
// transitions, digit boundaries, separators, ACRONYMWord handling) — from the paper's description,
// not the GPL source. It preserves case (lexical.h's subtokens() lowercases and drops 1-char tokens,
// which the casing rules here cannot afford).

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <initializer_list>
#include <string>
#include <string_view>
#include <vector>

#include "model.h"
#include "ingest.h"     // AstMatch — naming findings ride the shared lint finding shape

namespace rw
{
namespace naminglens
{

// char classes — ASCII only; a name holding any non-ASCII byte is skipped entirely (conservative).
inline bool ncUpper( char c ) noexcept { return c >= 'A' && c <= 'Z'; }
inline bool ncLower( char c ) noexcept { return c >= 'a' && c <= 'z'; }
inline bool ncDigit( char c ) noexcept { return c >= '0' && c <= '9'; }
inline bool ncAlpha( char c ) noexcept { return ncUpper( c ) || ncLower( c ); }
inline bool ncAlnum( char c ) noexcept { return ncAlpha( c ) || ncDigit( c ); }
inline bool ncIdent( char c ) noexcept { return ncAlnum( c ) || c == '_'; }

// the one set-membership primitive this unit uses — the bool-type names, the C-family non-type keywords
// and the width suffixes are all "is this token one of a fixed list", and each spelling it out separately
// was three copies of the same loop.
inline bool ncAnyOf( std::string_view token, std::initializer_list<std::string_view> set ) noexcept
{
    return std::find( set.begin(), set.end(), token ) != set.end();
}

inline bool ncAllAscii( std::string_view name ) noexcept
{
    for( const char ch : name )
    {
        if( static_cast<unsigned char>( ch ) >= 0x80 )
        {
            return false;
        }
    }
    return true;
}

// conservative case-preserving split: separators, digit↔alpha boundaries, lower→Upper transitions,
// and the ACRONYMWord rule (the LAST upper of an ≥2-upper run starts the next word: "HTTPServer" →
// [HTTP, Server]). Keeps 1-char tokens and original case — both load-bearing for the rules here.
inline void splitIdentifier( std::string_view identifier, std::vector<std::string>& out )
{
    out.clear();
    std::string cur;
    const auto flush = [ & ] { if( !cur.empty() ) { out.push_back( cur ); } cur.clear(); };
    for( const char c : identifier )
    {
        if( !ncAlnum( c ) )
        {
            flush();    // separator (underscore or any other non-alnum)
            continue;
        }
        if( !cur.empty() )
        {
            const char prev = cur.back();
            if( ncDigit( prev ) != ncDigit( c ) )
            {
                flush();    // digit↔alpha boundary
            }
            else if( ncLower( prev ) && ncUpper( c ) )
            {
                flush();    // camelCase boundary
            }
            else if( ncUpper( prev ) && ncLower( c ) && cur.size() >= 2 && ncUpper( cur[ cur.size() - 2 ] ) )
            {
                const char lastUpper = cur.back();      // ACRONYMWord: the run's last upper opens the next word
                cur.pop_back();
                flush();
                cur.push_back( lastUpper );
            }
        }
        cur.push_back( c );
    }
    flush();
}

inline std::string toLowerAscii( std::string_view token )
{
    std::string lowered;
    lowered.reserve( token.size() );
    for( const char c : token )
    {
        lowered.push_back( ncUpper( c ) ? char( c - 'A' + 'a' ) : c );
    }
    return lowered;
}

// Levenshtein distance capped at `cap` — returns cap+1 as soon as the distance provably exceeds it.
inline std::size_t editDistanceCapped( std::string_view a, std::string_view b, std::size_t cap )
{
    const std::size_t lenA = a.size(), lenB = b.size();
    const std::size_t over = cap + 1;
    if( lenA > lenB )
    {
        return editDistanceCapped( b, a, cap );
    }
    if( lenB - lenA > cap )
    {
        return over;
    }
    std::vector<std::size_t> row( lenA + 1 );
    for( std::size_t i = 0; i <= lenA; ++i )
    {
        row[i] = i;
    }
    for( std::size_t j = 1; j <= lenB; ++j )
    {
        std::size_t diag    = row[0];
        std::size_t rowBest = over;
        row[0]              = j;
        for( std::size_t i = 1; i <= lenA; ++i )
        {
            const std::size_t sub  = diag + ( a[ i - 1 ] == b[ j - 1 ] ? 0 : 1 );
            const std::size_t next = std::min( { sub, row[i] + 1, row[ i - 1 ] + 1 } );
            diag                   = row[i];
            row[i]                 = next;
            rowBest                = std::min( rowBest, next );
        }
        if( rowBest > cap )
        {
            return over;    // the whole row exceeds the cap — no path back under it
        }
    }
    return std::min( row[lenA], over );
}

// name minus a trailing digit run. hasDigits ⇔ a non-empty digit suffix was stripped AND an
// alphabetic base remains ("foo2" → base "foo"; "2" / "v2x" untouched).
inline std::string_view digitSuffixBase( std::string_view name, bool& hasDigits )
{
    std::size_t end = name.size();
    while( end > 0 && ncDigit( name[ end - 1 ] ) )
    {
        --end;
    }
    hasDigits = end < name.size() && end > 0;
    return name.substr( 0, end );
}

// register/integer WIDTH suffixes (u8/u32/u64, hsum32/hsum64, utf8/utf16…) are semantic variants, not
// an arbitrary enumeration — the number-series rule must not paint them foo1/foo2 (found by running the
// lens on ripwire's own src, not by inspection).
inline bool ncWidthSuffix( std::string_view name ) noexcept
{
    bool                   hasDigits = false;
    const std::string_view base      = digitSuffixBase( name, hasDigits );
    if( !hasDigits )
    {
        return false;
    }
    return ncAnyOf( name.substr( base.size() ), { "8", "16", "32", "64", "128", "256", "512" } );
}

// ---- return-type recovery from the SIGNATURE bytes (the index stores a symbol's signature span but
// no parsed return type). Per language family; anything not confidently parseable stays UNKNOWN, and an
// unknown fact keeps naming-predicate / naming-setter silent. ----
struct ReturnTypeFact
{
    bool known    = false;
    bool boolLike = false;
    bool voidLike = false;
};

inline bool ncBoolTypeName( std::string_view token ) noexcept
{
    return ncAnyOf( token, { "bool", "_Bool", "Bool", "BOOL", "boolean", "Boolean", "jboolean" } );
}

// a bare identifier token, or empty view if the text is anything more structured (generics,
// attributes, tuples, quoted annotations…) — structured means NOT confidently known here.
inline std::string_view bareIdentifierOnly( std::string_view text ) noexcept
{
    while( !text.empty() && ( text.front() == ' ' || text.front() == '\t' || text.front() == '\n' || text.front() == '\r' ) )
    {
        text.remove_prefix( 1 );
    }
    while( !text.empty() && ( text.back() == ' ' || text.back() == '\t' || text.back() == '\n' || text.back() == '\r' ) )
    {
        text.remove_suffix( 1 );
    }
    if( text.empty() || !( ncAlpha( text.front() ) || text.front() == '_' ) )
    {
        return {};
    }
    for( const char c : text )
    {
        if( !ncIdent( c ) )
        {
            return {};
        }
    }
    return text;
}

// tokens that mean "the token before the name is NOT a usable return type" in C-family signatures.
inline bool ncCFamilyNonType( std::string_view token ) noexcept
{
    return ncAnyOf( token, { "auto", "decltype", "const", "constexpr", "consteval", "constinit", "static", "inline", "virtual",
                             "extern", "friend", "explicit", "typename", "mutable", "register", "volatile", "thread_local",
                             "signed", "unsigned", "long", "short", "operator", "template", "typedef", "using", "struct",
                             "class", "enum", "union", "public", "private", "protected", "final", "abstract", "synchronized",
                             "native", "strictfp", "default", "new", "delete", "return", "override" } );
}

inline ReturnTypeFact returnTypeFromSignature( const Symbol& s, std::string_view sig )
{
    ReturnTypeFact fact;
    const Lang lang = s.lang;

    // arrow annotation family: Python `-> int:` / Rust `-> i32` / Swift `-> Bool`. No arrow = unknown
    // (an unannotated Python def genuinely tells us nothing — never guess).
    if( lang == Lang::Python || lang == Lang::Rust || lang == Lang::Swift )
    {
        const std::size_t arrowPos = sig.rfind( "->" );
        if( arrowPos == std::string_view::npos )
        {
            return fact;
        }
        std::string_view annotation = sig.substr( arrowPos + 2 );
        while( !annotation.empty() && ( annotation.back() == ':' || annotation.back() == '{' || annotation.back() == ' ' || annotation.back() == '\t'
                                        || annotation.back() == '\n' || annotation.back() == '\r' ) )
        {
            annotation.remove_suffix( 1 );
        }
        const std::string_view token = bareIdentifierOnly( annotation );
        if( token.empty() )
        {
            return fact;    // Optional[bool], tuples, quoted annotations … — structured ⇒ unknown
        }
        fact.known    = true;
        fact.boolLike = token == "bool" || token == "Bool";
        fact.voidLike = token == "None" || token == "Void";
        return fact;
    }

    // TypeScript `): type` (JavaScript stays silent — it has no annotations to know).
    if( lang == Lang::TypeScript )
    {
        const std::size_t parenPos = sig.rfind( ')' );
        if( parenPos == std::string_view::npos )
        {
            return fact;
        }
        std::string_view after = sig.substr( parenPos + 1 );
        while( !after.empty() && ( after.front() == ' ' || after.front() == '\t' ) )
        {
            after.remove_prefix( 1 );
        }
        if( after.empty() || after.front() != ':' )
        {
            return fact;
        }
        after.remove_prefix( 1 );
        while( !after.empty() && ( after.back() == '{' || after.back() == ' ' || after.back() == '\t' || after.back() == '\n' || after.back() == '\r' ) )
        {
            after.remove_suffix( 1 );
        }
        const std::string_view token = bareIdentifierOnly( after );
        if( token.empty() )
        {
            return fact;
        }
        fact.known    = true;
        fact.boolLike = token == "boolean";
        fact.voidLike = token == "void";
        return fact;
    }

    // C-family / Java / C#: the type token immediately precedes the name. Find `name (`-shaped
    // occurrence, scan back one token (skipping * & and whitespace, keeping :: qualifications).
    if( lang == Lang::Cpp || lang == Lang::C || lang == Lang::ObjC || lang == Lang::Java || lang == Lang::CSharp )
    {
        std::size_t namePos = std::string_view::npos;
        for( std::size_t from = 0; from < sig.size(); )
        {
            const std::size_t candidate = sig.find( s.name, from );
            if( candidate == std::string_view::npos )
            {
                break;
            }
            from = candidate + 1;
            if( candidate > 0 && ncIdent( sig[ candidate - 1 ] ) )
            {
                continue;   // substring of a longer identifier
            }
            std::size_t after = candidate + s.name.size();
            while( after < sig.size() && ( sig[after] == ' ' || sig[after] == '\t' || sig[after] == '\n' || sig[after] == '\r' ) )
            {
                ++after;
            }
            if( after < sig.size() && sig[after] == '(' )
            {
                namePos = candidate;
                break;
            }
        }
        if( namePos == std::string_view::npos || namePos == 0 )
        {
            return fact;
        }
        std::size_t cursor = namePos;
        while( cursor > 0 && ( sig[ cursor - 1 ] == ' ' || sig[ cursor - 1 ] == '\t' || sig[ cursor - 1 ] == '\n' || sig[ cursor - 1 ] == '\r'
                               || sig[ cursor - 1 ] == '*' || sig[ cursor - 1 ] == '&' ) )
        {
            --cursor;
        }
        std::size_t tokenEnd = cursor;
        while( cursor > 0 && ( ncIdent( sig[ cursor - 1 ] ) || sig[ cursor - 1 ] == ':' ) )
        {
            --cursor;
        }
        std::string_view token = sig.substr( cursor, tokenEnd - cursor );
        while( !token.empty() && token.front() == ':' )
        {
            token.remove_prefix( 1 );   // `::Type` — keep the qualified spelling but not a dangling lead
        }
        if( token.empty() || !( ncAlpha( token.front() ) || token.front() == '_' ) )
        {
            return fact;    // `>` of a template, `)` of a macro, nothing at all … — unknown
        }
        // the UNQUALIFIED tail decides bool/void-ness for a qualified spelling like std::string.
        std::string_view tail = token;
        const std::size_t lastColon = token.rfind( ':' );
        if( lastColon != std::string_view::npos )
        {
            tail = token.substr( lastColon + 1 );
        }
        if( tail.empty() || ncCFamilyNonType( token ) || token == s.name )
        {
            return fact;    // qualifier keyword or a constructor — not a return type we know
        }
        fact.known    = true;
        fact.boolLike = ncBoolTypeName( tail );
        fact.voidLike = tail == "void";
        return fact;
    }

    return fact;    // Go/Ruby/Bash/… — no extraction implemented ⇒ unknown ⇒ silent (never guess)
}

// prefix + boundary: `is`+`Valid` / `is`+`_valid` / `set`+`Limit` — but never `island` or `setup`.
inline bool prefixedWithBoundary( std::string_view name, std::string_view prefix ) noexcept
{
    if( name.size() <= prefix.size() || name.substr( 0, prefix.size() ) != prefix )
    {
        return false;
    }
    const char boundary = name[ prefix.size() ];
    return boundary == '_' || ncUpper( boundary ) || ncDigit( boundary );
}

inline bool predicatePrefixed( std::string_view name ) noexcept
{
    return prefixedWithBoundary( name, "is" ) || prefixedWithBoundary( name, "has" ) || prefixedWithBoundary( name, "can" )
           || prefixedWithBoundary( name, "should" ) || prefixedWithBoundary( name, "was" );
}

// ---- the lens itself ----
struct NamingLensResult
{
    std::vector<AstMatch>    hits;
    std::vector<std::string> saturatedRules;    // rule names whose count= is a FLOOR (budget spent, or a scan too big to run in full)
};

inline constexpr std::size_t kConfusableGroupMax = 512;   // beyond this many co-visible names the O(n²) pair scan
inline constexpr std::size_t kConfusableWindow   = 24;    //   degrades to a sorted-neighbor window — disclosed as a floor

namespace detail
{

// shared per-rule budget bookkeeping: an AstMatch sink that never exceeds maxHitsPerRule per tag and
// remembers which rules it had to stop counting for (§P0.2 floor semantics, same as astQuery's budget).
struct RuleSink
{
    struct Tally
    {
        const char* tag;
        std::size_t count     = 0;
        bool        saturated = false;
    };
    std::vector<AstMatch> hits;
    std::size_t           maxHitsPerRule = 0;
    Tally                 tallies[8]     = { { "naming-short" }, { "naming-wordy" }, { "naming-series" }, { "naming-underscore" }, { "naming-case" },
                                             { "naming-predicate" }, { "naming-setter" }, { "naming-confusable" } };

    Tally& tallyFor( std::string_view tag )
    {
        for( Tally& tally : tallies )
        {
            if( tag == tally.tag )
            {
                return tally;
            }
        }
        return tallies[0];  // unreachable by construction (every caller passes a table name)
    }

    void add( const char* tag, const Symbol& s, std::uint32_t anchorLine, std::string text )
    {
        Tally& tally = tallyFor( tag );
        if( tally.count >= maxHitsPerRule )
        {
            tally.saturated = true;
            return;
        }
        ++tally.count;
        hits.push_back( { s.fileId, s.sigStartByte, s.endByte, anchorLine, tag, std::move( text ) } );
    }
};

// eligibility: the kinds the spec names (functions/methods/vars — params and locals are not indexed,
// which is exactly what keeps the idiom allow-list roles silent), data/doc languages excluded,
// prototypes excluded (the definition owns the name), operators/destructors/non-ASCII skipped.
inline bool eligibleSymbol( const Symbol& s )
{
    if( s.kind != SymKind::Function && s.kind != SymKind::Method && s.kind != SymKind::Var )
    {
        return false;
    }
    if( s.lang == Lang::Json || s.lang == Lang::Markdown || s.lang == Lang::Unknown )
    {
        return false;
    }
    if( s.name.empty() || !ncAllAscii( s.name ) )
    {
        return false;
    }
    if( s.name[0] == '~' || s.name.rfind( "operator", 0 ) == 0 )
    {
        return false;
    }
    if( ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && s.endByte <= s.sigEndByte )
    {
        return false;   // prototype / abstract — the definition carries the findings
    }
    return true;
}

inline bool isPythonDunder( std::string_view name ) noexcept
{
    return name.size() > 4 && name.substr( 0, 2 ) == "__" && name.substr( name.size() - 2 ) == "__";
}

// N1 + N2 + N4: facts derivable from the name alone (plus kind/lang for role and idiom gating).
inline void checkNameShape( const Symbol& s, const std::vector<std::string>& toks, RuleSink& sink )
{
    // naming-short — strip decorating underscores; a 1–2 letter alphabetic core in a non-local role.
    {
        std::string_view core = s.name;
        while( !core.empty() && core.front() == '_' )
        {
            core.remove_prefix( 1 );
        }
        while( !core.empty() && core.back() == '_' )
        {
            core.remove_suffix( 1 );
        }
        bool allAlpha = !core.empty();
        for( const char c : core )
        {
            allAlpha = allAlpha && ncAlpha( c );
        }
        if( allAlpha && core.size() <= 2 )
        {
            sink.add( "naming-short", s, s.line,
                      s.kind == SymKind::Var ? s.name + " (1-2 letter name for a module/global variable)"
                                             : s.name + " (1-2 letter function name; visible far beyond a 20-line scope)" );
        }
    }

    // naming-wordy — more than 5 split tokens.
    if( toks.size() > 5 )
    {
        sink.add( "naming-wordy", s, s.line, s.name + " (" + std::to_string( toks.size() ) + " words in one name)" );
    }

    // naming-underscore — internal consecutive underscores anywhere; C-family reserved forms
    // (leading __ or _Capital). Python dunders and single leading/trailing underscores are idiomatic.
    {
        const std::string_view name = s.name;
        bool internalDouble = false;
        bool sawAlnumBefore = false;
        for( std::size_t i = 0; i + 1 < name.size(); ++i )
        {
            sawAlnumBefore = sawAlnumBefore || ncAlnum( name[i] );
            if( name[i] == '_' && name[ i + 1 ] == '_' && sawAlnumBefore )
            {
                bool alnumAfter = false;
                for( std::size_t j = i + 2; j < name.size(); ++j )
                {
                    alnumAfter = alnumAfter || ncAlnum( name[j] );
                }
                internalDouble = internalDouble || alnumAfter;
            }
        }
        // the reserved-identifier forms are a C-family rule only (C/C++/ObjC reserve leading _Capital and __).
        const bool cFamily  = s.lang == Lang::Cpp || s.lang == Lang::C || s.lang == Lang::ObjC;
        const bool reserved = cFamily && name.size() >= 2 && name[0] == '_' && ( name[1] == '_' || ncUpper( name[1] ) );
        if( ( internalDouble && !isPythonDunder( name ) ) || reserved )
        {
            sink.add( "naming-underscore", s, s.line,
                      reserved ? s.name + " (reserved identifier form: leading underscore + capital or double underscore)"
                               : s.name + " (consecutive underscores inside a name)" );
        }
    }

    // naming-case — one name mixing a snake separator AND an in-word camel transition.
    {
        const std::string_view name = s.name;
        bool sawSeparator  = false;
        bool sawTransition = false;
        for( std::size_t i = 0; i + 1 < name.size(); ++i )
        {
            if( name[i] == '_' && i > 0 && ncAlnum( name[ i - 1 ] ) && ncAlnum( name[ i + 1 ] ) )
            {
                sawSeparator = true;
            }
            if( ncLower( name[i] ) && ncUpper( name[ i + 1 ] ) )
            {
                sawTransition = true;
            }
        }
        if( sawSeparator && sawTransition )
        {
            sink.add( "naming-case", s, s.line, s.name + " (snake_case and camelCase mixed in one name)" );
        }
    }
}

// N5 + N6: role-vs-known-return-type checks. `sig` = the raw signature bytes; an empty view or an
// unparseable type keeps both rules silent.
inline void checkRoleReturnTypes( const Symbol& s, std::string_view sig, RuleSink& sink )
{
    if( ( s.kind != SymKind::Function && s.kind != SymKind::Method ) || sig.empty() )
    {
        return;
    }
    const bool isPredicate = predicatePrefixed( s.name );
    const bool isSetter    = prefixedWithBoundary( s.name, "set" );
    if( !isPredicate && !isSetter )
    {
        return;
    }
    const ReturnTypeFact fact = returnTypeFromSignature( s, sig );
    if( !fact.known )
    {
        return;     // the needed fact is unknown — stay silent, never guess
    }
    if( isPredicate && !fact.boolLike )
    {
        sink.add( "naming-predicate", s, s.line, s.name + " (predicate-named but the declared return type is not bool-like)" );
    }
    if( isSetter && !fact.voidLike )
    {
        sink.add( "naming-setter", s, s.line, s.name + " (set-prefixed but declares a non-void return type)" );
    }
}

// two lowercased tokens "agree" when equal, or when one is a ≥4-char prefix of the other — the
// deterministic, dictionary-free stand-in for plural/inflection morphology ("candidates" agrees with
// candidate, "building" with build).
//
// KEPT ON PURPOSE, with no caller today: this is the token-agreement half of the substrate the withdrawn
// naming-body-mismatch rule was built on (splitIdentifier, its other half, is still live under
// checkScopeGroups). What was measured wrong was the RULE's direction, not this predicate — and comparing
// two spellings of one concept is exactly what the corpus-CONSISTENCY work (synonym / abbreviation
// unification) needs, so it is the part of that rule worth keeping. See the WITHDRAWN note at the top.
inline bool tokensAgree( std::string_view a, std::string_view b ) noexcept
{
    if( a == b )
    {
        return true;
    }
    if( a.size() < 4 || b.size() < 4 )
    {
        return false;
    }
    return a.size() < b.size() ? b.substr( 0, a.size() ) == a : a.substr( 0, b.size() ) == b;
}

// N3 + N7: the pair rules over names co-visible in one (file, scope) group.
inline void checkScopeGroups( const IngestResult& ing, RuleSink& sink )
{
    // eligible symbols, ordered by (fileId, scope, name, sigStartByte) — fileId order IS the sorted
    // crawl-path order, so the walk (and therefore the output) is deterministic.
    std::vector<const Symbol*> pool;
    pool.reserve( ing.symbols.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( eligibleSymbol( s ) )
        {
            pool.push_back( &s );
        }
    }
    std::sort( pool.begin(), pool.end(), []( const Symbol* a, const Symbol* b )
               {
        if( a->fileId != b->fileId ) { return a->fileId < b->fileId;
}
        if( a->scope != b->scope ) { return a->scope < b->scope;
}
        if( a->name != b->name ) { return a->name < b->name;
}
        return a->sigStartByte < b->sigStartByte; } );

    std::vector<std::vector<std::string>> uniqToks;     // lowercased sorted tokens per unique name, computed once per group
    for( std::size_t groupBegin = 0; groupBegin < pool.size(); )
    {
        std::size_t groupEnd = groupBegin;
        while( groupEnd < pool.size() && pool[groupEnd]->fileId == pool[groupBegin]->fileId && pool[groupEnd]->scope == pool[groupBegin]->scope )
        {
            ++groupEnd;
        }

        // unique names in the group (overloads collapse to their first declaration).
        std::vector<const Symbol*> uniq;
        for( std::size_t poolIndex = groupBegin; poolIndex < groupEnd; ++poolIndex )
        {
            if( uniq.empty() || uniq.back()->name != pool[poolIndex]->name )
            {
                uniq.push_back( pool[poolIndex] );
            }
        }

        // naming-series: ≥2 distinct digit-suffixed names sharing (kind, base). Sorted-by-name means
        // every same-base sibling is adjacent (they share the base as a literal prefix).
        for( std::size_t nameIndex = 0; nameIndex < uniq.size(); )
        {
            bool                   headHasDigits = false;
            const std::string_view headBase      = digitSuffixBase( uniq[nameIndex]->name, headHasDigits );
            if( !headHasDigits )
            {
                ++nameIndex;
                continue;
            }
            std::size_t runEnd = nameIndex + 1;
            while( runEnd < uniq.size() )
            {
                bool                   nextHasDigits = false;
                const std::string_view nextBase      = digitSuffixBase( uniq[runEnd]->name, nextHasDigits );
                if( !nextHasDigits || nextBase != headBase || uniq[runEnd]->kind != uniq[nameIndex]->kind )
                {
                    break;
                }
                ++runEnd;
            }
            bool allWidthSuffixes = true;   // width families (hsum32/hsum64) and 1-char bases (u8/u32) are semantic, not a series
            for( std::size_t memberIndex = nameIndex; memberIndex < runEnd; ++memberIndex )
            {
                allWidthSuffixes = allWidthSuffixes && ncWidthSuffix( uniq[memberIndex]->name );
            }
            if( runEnd - nameIndex >= 2 && headBase.size() >= 2 && !allWidthSuffixes )
            {
                for( std::size_t memberIndex = nameIndex; memberIndex < runEnd; ++memberIndex )
                {
                    const Symbol& member = *uniq[memberIndex];
                    sink.add( "naming-series", member, member.line,
                              member.name + " (number-series name; " + std::to_string( runEnd - nameIndex ) + " siblings share the base '"
                                  + std::string( headBase ) + "')" );
                }
            }
            nameIndex = runEnd;
        }

        // naming-confusable: pairwise over unique names. A group too big for the O(n²) scan degrades
        // to a sorted-neighbor window and the rule is reported saturated (its count= becomes a floor).
        const bool windowed = uniq.size() > kConfusableGroupMax;
        if( windowed )
        {
            sink.tallyFor( "naming-confusable" ).saturated = true;
        }
        uniqToks.assign( uniq.size(), {} );
        std::vector<std::string> splitScratch;
        for( std::size_t nameIndex = 0; nameIndex < uniq.size(); ++nameIndex )
        {
            splitIdentifier( uniq[nameIndex]->name, splitScratch );
            for( const std::string& tok : splitScratch )
            {
                uniqToks[nameIndex].push_back( toLowerAscii( tok ) );
            }
            std::sort( uniqToks[nameIndex].begin(), uniqToks[nameIndex].end() );
        }
        for( std::size_t firstIndex = 0; firstIndex < uniq.size(); ++firstIndex )
        {
            const std::size_t secondEnd = windowed ? std::min( uniq.size(), firstIndex + 1 + kConfusableWindow ) : uniq.size();
            for( std::size_t secondIndex = firstIndex + 1; secondIndex < secondEnd; ++secondIndex )
            {
                const Symbol& first  = *uniq[firstIndex];
                const Symbol& second = *uniq[secondIndex];
                bool                   firstHasDigits = false, secondHasDigits = false;
                const std::string_view firstBase  = digitSuffixBase( first.name, firstHasDigits );
                const std::string_view secondBase = digitSuffixBase( second.name, secondHasDigits );
                if( firstHasDigits && secondHasDigits && firstBase == secondBase )
                {
                    continue;   // a number series — naming-series owns that family
                }
                const char* reason = nullptr;
                if( ( firstHasDigits != secondHasDigits )
                    && ( ( firstHasDigits && firstBase == second.name ) || ( secondHasDigits && secondBase == first.name ) )
                    && ( firstHasDigits ? firstBase : secondBase ).size() >= 2 )
                {
                    reason = "differ only by a digit suffix";
                }
                else if( first.name.size() >= 5 && second.name.size() >= 5 && editDistanceCapped( first.name, second.name, 2 ) <= 2 )
                {
                    reason = "edit distance <=2";
                }
                else if( uniqToks[firstIndex].size() >= 2 && uniqToks[firstIndex] == uniqToks[secondIndex] )
                {
                    reason = "same words in a different order";
                }
                if( reason == nullptr )
                {
                    continue;
                }
                const Symbol& earlier = first.sigStartByte <= second.sigStartByte ? first : second;
                const Symbol& later   = first.sigStartByte <= second.sigStartByte ? second : first;
                sink.add( "naming-confusable", later, later.line, earlier.name + " ~ " + later.name + " (" + reason + ")" );
            }
        }

        groupBegin = groupEnd;
    }
}

}   // namespace detail

// The lens entry point runLint merges: every finding is an AstMatch with a naming-* tag, flowing
// through the same sort/dedupe/tally/paging as the other built-ins. maxHitsPerRule is the caller's
// per-rule lint budget (kLintMaxPerRule) — same floor semantics as the query-based rules.
inline NamingLensResult namingLensChecks( const IngestResult& ing, std::size_t maxHitsPerRule );

// The shape runLint actually calls, matching the house pattern of the other symbol-level checks
// (`for( AstMatch& h : lintSymbolLevelChecks( ing ) )`): findings are APPENDED to `out`, and the
// return value is the rule names whose count= must be disclosed as a floor.
inline std::vector<std::string> appendNamingFindings( const IngestResult& ing, std::size_t maxHitsPerRule, std::vector<AstMatch>& out )
{
    NamingLensResult res = namingLensChecks( ing, maxHitsPerRule );
    out.insert( out.end(), std::make_move_iterator( res.hits.begin() ), std::make_move_iterator( res.hits.end() ) );
    return std::move( res.saturatedRules );
}

inline NamingLensResult namingLensChecks( const IngestResult& ing, std::size_t maxHitsPerRule )
{
    detail::RuleSink sink;
    sink.maxHitsPerRule = maxHitsPerRule;

    // memoized whole-file reads (same shape as lintSymbolLevelChecks) — an unreadable file yields an
    // empty view, and every rule needing bytes goes silent for it (degrade, not failure).
    std::vector<std::string> fileBytes( ing.files.size() );
    std::vector<char>        fileRead( ing.files.size(), 0 );
    const auto getBytes = [ & ]( std::uint32_t fileId ) -> const std::string&
    {
        if( !fileRead[fileId] )
        {
            std::FILE* fp = std::fopen( diskPath( ing, fileId ).c_str(), "rb" );
            if( fp )
            {
                std::fseek( fp, 0, SEEK_END );
                const long fileSize = std::ftell( fp );
                std::fseek( fp, 0, SEEK_SET );
                if( fileSize > 0 )
                {
                    fileBytes[fileId].resize( std::size_t( fileSize ) );
                    const std::size_t readCount = std::fread( fileBytes[fileId].data(), 1, std::size_t( fileSize ), fp );
                    fileBytes[fileId].resize( readCount );
                }
                std::fclose( fp );
            }
            fileRead[fileId] = 1;
        }
        return fileBytes[fileId];
    };

    std::vector<std::string> toks;
    for( const Symbol& s : ing.symbols )    // symbols are already in deterministic (file, line, name) order
    {
        if( !detail::eligibleSymbol( s ) )
        {
            continue;
        }
        splitIdentifier( s.name, toks );
        detail::checkNameShape( s, toks, sink );
        if( s.kind == SymKind::Function || s.kind == SymKind::Method )
        {
            const std::string& bytes = getBytes( s.fileId );
            const std::uint32_t sigA = std::min( s.sigStartByte, std::uint32_t( bytes.size() ) );
            const std::uint32_t sigB = std::min( s.sigEndByte,   std::uint32_t( bytes.size() ) );
            detail::checkRoleReturnTypes( s, std::string_view( bytes ).substr( sigA, sigB - sigA ), sink );
        }
    }
    detail::checkScopeGroups( ing, sink );

    NamingLensResult res;
    res.hits = std::move( sink.hits );
    for( const detail::RuleSink::Tally& tally : sink.tallies )
    {
        if( tally.saturated )
        {
            res.saturatedRules.push_back( tally.tag );
        }
    }
    // runLint re-sorts the combined set; sorting here as well keeps this unit independently deterministic.
    std::sort( res.hits.begin(), res.hits.end(), [ & ]( const AstMatch& x, const AstMatch& y )
               {
        if( ing.files[x.fileId] != ing.files[y.fileId] ) { return ing.files[x.fileId] < ing.files[y.fileId];
}
        if( x.startByte != y.startByte ) { return x.startByte < y.startByte;
}
        return x.tag < y.tag; } );
    return res;
}

}   // namespace naminglens
}   // namespace rw
