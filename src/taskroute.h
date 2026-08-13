#pragma once

// taskroute.h — deterministic enhanced help: one task in, one safe Ripwire command (or abstention) out.
// This module recommends only. It never executes a command, calls a model, reads the network, or learns
// weights at runtime. Integer scores and stable tie-breaking keep the result byte-deterministic.

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "infra/jsonesc.h"   // shSingleQuote — the repository's canonical POSIX argv quoting
#include "model.h"           // IngestResult
#include "query.h"           // isKnownLayerWord — the layer vocabulary --verify enforces at evaluation
#include "verify.h"          // parseClaim — the SHIPPED claim grammar; the router never re-implements it

namespace rw::taskroute
{

enum class RouteStatus : std::uint8_t { Recommend, Ambiguous, Abstain };

struct RepoFacts
{
    bool                     git   = false;
    bool                     dirty = false;
    bool                     trace = false;
    std::vector<std::string> resolvedSymbols;
};

struct RouteChoice
{
    const char* id       = "";
    const char* skill    = "";
    const char* reason   = "";
    std::string command;
    int         score    = 0;
    int         priority = 0;
};

struct TaskRouteResult
{
    RouteStatus              status = RouteStatus::Abstain;
    RepoFacts                facts;
    std::vector<RouteChoice> choices;
    int                      score  = 0;
    int                      margin = 0;
};

inline std::string lowerAscii( std::string_view text )
{
    std::string out;
    out.reserve( text.size() );
    for( const unsigned char c : text )
    {
        out.push_back( char( std::tolower( c ) ) );
    }
    return out;
}

inline bool wordByte( char c ) noexcept
{
    const unsigned char u = static_cast<unsigned char>( c );
    return std::isalnum( u ) || c == '_';
}

inline std::size_t boundedFind( std::string_view haystack, std::string_view needle, std::size_t from = 0 ) noexcept
{
    for( std::size_t p = haystack.find( needle, from ); p != std::string_view::npos; p = haystack.find( needle, p + 1 ) )
    {
        const bool left  = p == 0 || !wordByte( haystack[p - 1] );
        const bool right = p + needle.size() == haystack.size() || !wordByte( haystack[p + needle.size()] );
        if( left && right )
        {
            return p;
        }
    }
    return std::string_view::npos;
}

inline bool has( std::string_view lower, std::string_view phrase ) noexcept
{
    return lower.find( phrase ) != std::string_view::npos;
}

inline int phraseScore( std::string_view lower, std::initializer_list<std::pair<std::string_view, int>> phrases ) noexcept
{
    int score = 0;
    for( const auto& [ phrase, weight ] : phrases )
    {
        if( has( lower, phrase ) )
        {
            score += weight;
        }
    }
    return score;
}

inline bool looksLikeTrace( std::string_view lower ) noexcept
{
    return has( lower, "addresssanitizer:" ) || has( lower, "threadsanitizer:" ) || has( lower, "undefinedbehaviorsanitizer:" )
        || has( lower, "stack trace" ) || has( lower, "traceback (most recent call last)" )
        || ( has( lower, "#0 ") && ( has( lower, " in ") || has( lower, " at ") ) );
}

// A task routes to --verify only if the SHIPPED parser accepts it byte-for-byte, plus the one
// constraint the verb defers to evaluation time: reaches' unquoted second argument must be a
// built-in layer word. Without that second check the router would recommend a command the verb
// itself refuses — a prerequisite-violating route, which the contract forbids outright.
inline bool looksLikeClosedClaim( std::string_view task )
{
    const verify::Claim claim = verify::parseClaim( task );
    if( !claim.ok )
    {
        return false;
    }
    if( claim.shape == verify::ClaimShape::Reaches && !claim.arg2Quoted && !query::isKnownLayerWord( claim.arg2 ) )
    {
        return false;
    }
    return true;
}

inline std::vector<std::string> resolveTaskSymbols( std::string_view task, const IngestResult& ing )
{
    struct At { std::size_t pos; std::string name; };
    std::vector<At> found;
    for( const Symbol& sym : ing.symbols )
    {
        if( sym.name.empty() )
        {
            continue;
        }
        // A lowercase dictionary word that happens to be a symbol is not strong enough evidence for an
        // automatic graph route. Require identifier shape (camel/Pascal/snake/scoped); simple names remain
        // reachable through --for, but cannot accidentally turn ordinary prose into a 3-symbol --connect.
        const bool identifierShape = std::any_of( sym.name.begin(), sym.name.end(), []( const unsigned char c )
        {
            return std::isupper( c ) || c == '_' || c == ':' || c == '$';
        } );
        if( !identifierShape )
        {
            continue;
        }
        const std::size_t pos = boundedFind( task, sym.name );
        if( pos == std::string_view::npos )
        {
            continue;
        }
        const bool duplicate = std::any_of( found.begin(), found.end(), [&]( const At& at ) { return at.name == sym.name; } );
        if( !duplicate )
        {
            found.push_back( { pos, sym.name } );
        }
    }
    std::sort( found.begin(), found.end(), []( const At& a, const At& b )
    {
        if( a.pos != b.pos ) { return a.pos < b.pos; }
        return a.name < b.name;
    } );
    std::vector<std::string> out;
    out.reserve( found.size() );
    for( At& at : found )
    {
        out.push_back( std::move( at.name ) );
    }
    return out;
}

inline std::string commandWithValue( const std::string& root, const char* flag, std::string_view value )
{
    return "ripwire " + shSingleQuote( root ) + " " + flag + shSingleQuote( std::string( value ) );
}

inline std::string commaSymbols( const std::vector<std::string>& symbols )
{
    std::string out;
    for( std::size_t i = 0; i < symbols.size(); ++i )
    {
        if( i != 0 ) { out += ','; }
        out += symbols[i];
    }
    return out;
}

inline void addLexical( std::vector<RouteChoice>& choices, const char* id, const char* skill, const char* reason,
                        std::string command, int score, int floor, int priority )
{
    if( score >= floor )
    {
        choices.push_back( { id, skill, reason, std::move( command ), score, priority } );
    }
}

inline TaskRouteResult classify( std::string_view task, const std::string& root, const IngestResult& ing, bool git, bool dirty )
{
    TaskRouteResult result;
    result.facts.git             = git;
    result.facts.dirty           = dirty;
    result.facts.trace           = looksLikeTrace( lowerAscii( task ) );
    result.facts.resolvedSymbols = resolveTaskSymbols( task, ing );
    const std::string lower      = lowerAscii( task );

    // Hard structured shapes are contracts, not suggestions. They outrank every lexical card.
    if( looksLikeClosedClaim( task ) )
    {
        result.status  = RouteStatus::Recommend;
        result.score   = 100;
        result.margin  = 100;
        result.choices.push_back( { "verify-claim", "ripwire-navigate", "closed claim grammar",
                                    commandWithValue( root, "--verify=", task ), 100, 100 } );
        return result;
    }
    if( result.facts.trace )
    {
        result.status = RouteStatus::Recommend;
        result.score  = result.margin = 100;
        result.choices.push_back( { "trace-debug", "ripwire-find-bug", "stack-trace shape; pass the trace on stdin",
                                    "ripwire " + shSingleQuote( root ) + " --from-trace=-", 100, 90 } );
        return result;
    }
    if( result.facts.resolvedSymbols.size() >= 3 )
    {
        result.status = RouteStatus::Recommend;
        result.score  = result.margin = 100;
        result.choices.push_back( { "connect-symbols", "ripwire-navigate", "three or more exact indexed symbols",
                                    commandWithValue( root, "--connect=", commaSymbols( result.facts.resolvedSymbols ) ), 100, 80 } );
        return result;
    }
    if( result.facts.resolvedSymbols.size() == 1 && ( has( lower, "understand" ) || has( lower, "implementation" ) || has( lower, "how does" ) ) )
    {
        result.status = RouteStatus::Recommend;
        result.score  = result.margin = 100;
        result.choices.push_back( { "understand-symbol", "ripwire-navigate", "one exact indexed symbol plus understand wording",
                                    commandWithValue( root, "--expand=", result.facts.resolvedSymbols[0] ), 100, 70 } );
        return result;
    }

    std::vector<RouteChoice> candidates;
    if( dirty )
    {
        const int score = phraseScore( lower, { { "before i push", 9 }, { "before pushing", 9 }, { "ready to push", 9 },
                                               { "safe to merge", 9 }, { "current changes", 6 }, { "my diff", 6 },
                                               { "review my", 4 }, { "which tests", 3 } } );
        addLexical( candidates, "review-diff", "ripwire-change-check", "dirty worktree plus review/pre-push wording",
                    "ripwire " + shSingleQuote( root ) + " --situ", score, 8, 60 );
    }
    const int planScore = phraseScore( lower, { { "plan", 5 }, { "implementation", 2 }, { "feature", 4 },
                                                { "scope", 4 }, { "multi-symbol", 4 }, { "before building", 4 }, { "new ", 1 } } );
    addLexical( candidates, "plan-feature", "ripwire-before-you-build", "prospective feature planning wording",
                commandWithValue( root, "--pack-task=", task ), planScore, 8, 50 );

    const int reuseScore = phraseScore( lower, { { "about to write", 8 }, { "one helper", 5 }, { "one function", 5 },
                                                 { "one class", 5 }, { "helper", 3 }, { "function", 2 }, { "class", 2 } } );
    addLexical( candidates, "reuse-one-symbol", "ripwire-reuse-first", "about-to-write one-symbol wording",
                commandWithValue( root, "--exemplar=", task ), reuseScore, 10, 40 );

    const int locateScore = phraseScore( lower, { { "find the code", 8 }, { "locate", 7 }, { "responsible", 4 },
                                                  { "bug", 3 }, { "wrong output", 4 }, { "crash", 4 }, { "symptom", 3 } } );
    addLexical( candidates, "locate-task", "ripwire-find-bug", "code-location or symptom wording",
                commandWithValue( root, "--for=", task ), locateScore, 8, 30 );

    if( candidates.empty() )
    {
        return result;
    }
    std::sort( candidates.begin(), candidates.end(), []( const RouteChoice& a, const RouteChoice& b )
    {
        if( a.score != b.score )       { return a.score > b.score; }
        if( a.priority != b.priority ) { return a.priority > b.priority; }
        return std::string_view( a.id ) < std::string_view( b.id );
    } );
    result.score  = candidates[0].score;
    result.margin = candidates.size() == 1 ? candidates[0].score : candidates[0].score - candidates[1].score;
    if( candidates.size() == 1 || result.margin >= 3 )
    {
        result.status = RouteStatus::Recommend;
        result.choices.push_back( std::move( candidates[0] ) );
    }
    else
    {
        result.status = RouteStatus::Ambiguous;
        result.choices.push_back( std::move( candidates[0] ) );
        result.choices.push_back( std::move( candidates[1] ) );
    }
    return result;
}

inline const char* statusName( RouteStatus status ) noexcept
{
    switch( status )
    {
        case RouteStatus::Recommend: return "recommend";
        case RouteStatus::Ambiguous: return "ambiguous";
        case RouteStatus::Abstain:   return "abstain";
    }
    return "abstain";
}

}   // namespace rw::taskroute
