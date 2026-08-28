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

// Words the router itself reads as INTENT. A bare lowercase occurrence of one of these is evidence about
// what the user WANTS, never evidence that they named a symbol — resolving them would let the router argue
// with itself ("did I change its contract?" would resolve `contract` and then fail the one-symbol
// precondition of the very route that phrase exists to trigger). Open-class content words (`check`,
// `render`, `config`) are deliberately absent: they are legitimate symbol names, and the slot rule below
// is what keeps them from hijacking prose. A floor on what must never resolve, not a completeness claim.
inline constexpr std::string_view kWeakSymbolStopWords[] = {
    "before", "building", "change", "changed", "changes", "class", "classes", "contract", "contracts",
    "crash", "crashes", "current", "edited", "every", "feature", "features", "function", "functions",
    "helper", "helpers", "implementation", "literal", "locate", "merge", "multi", "occurrence",
    "occurrences", "output", "pushing", "ready", "recent", "responsible", "review", "scope", "search",
    "signature", "signatures", "stack", "symbol", "symbols", "symptom", "symptoms", "tests", "trace",
    "traceback", "understand", "which", "write", "wrong",
};

// Cue words that place the word AFTER them in a symbol slot. This is the whole discriminator: "how does
// classify work" and "I just edited classify" name a symbol, while "how does the license affect what we
// ship" and "did I change the report" do not — and the only difference is the word in front. Casing was
// the old proxy for this and it was the wrong one; it discarded `classify` to protect against `report`,
// when the position in the sentence separates them exactly.
inline constexpr std::string_view kWeakSymbolCues[] = {
    "called", "class", "does", "edit", "edited", "editing", "function", "helper", "method", "modified",
    "modifying", "named", "of", "symbol", "understand", "understanding",
};

inline constexpr std::size_t kMinWeakSymbolLen = 5;

// True when the word immediately before `pos` is a symbol-slot cue. `lowerTask` is the lowercased task,
// so the comparison is a plain equality. Opening quotes and backticks between the cue and the name are
// stepped over — they are themselves symbol evidence, never separators.
inline bool precededBySymbolCue( std::string_view lowerTask, std::size_t pos ) noexcept
{
    std::size_t end = pos;
    while( end > 0 && ( lowerTask[end - 1] == ' ' || lowerTask[end - 1] == '`'
                     || lowerTask[end - 1] == '\'' || lowerTask[end - 1] == '"' ) )
    {
        --end;
    }
    std::size_t begin = end;
    while( begin > 0 && wordByte( lowerTask[begin - 1] ) )
    {
        --begin;
    }
    const std::string_view word = lowerTask.substr( begin, end - begin );
    return std::any_of( std::begin( kWeakSymbolCues ), std::end( kWeakSymbolCues ),
                        [word]( const std::string_view cue ) { return cue == word; } );
}

// A name with no identifier punctuation and no capital is a WEAK match: it might be a symbol mention, or
// it might just be a word. Length plus the stop list above is what separates the two cheaply.
inline bool weakSymbolCandidate( std::string_view name ) noexcept
{
    if( name.size() < kMinWeakSymbolLen )
    {
        return false;
    }
    return std::none_of( std::begin( kWeakSymbolStopWords ), std::end( kWeakSymbolStopWords ),
                         [name]( const std::string_view stop ) { return stop == name; } );
}

// The first word-bounded occurrence of an all-lowercase `name` that sits in a symbol slot, or npos when
// no occurrence does. A later mention can be the one in a slot ("classify is slow — how does classify
// work?"), so every occurrence is tried, not just the first.
inline std::size_t findInSymbolSlot( std::string_view lowerTask, std::string_view name ) noexcept
{
    std::size_t pos = boundedFind( lowerTask, name );
    while( pos != std::string_view::npos && !precededBySymbolCue( lowerTask, pos ) )
    {
        pos = boundedFind( lowerTask, name, pos + 1 );
    }
    return pos;
}

// Where, and how strongly, one indexed name is mentioned in the task. Identifier shape
// (camel/Pascal/snake/scoped) is a STRONG mention and counts wherever it appears. An all-lowercase name is
// no longer discarded outright — a word-bounded exact hit on the real symbol table beats casing as
// evidence — but it counts only from a symbol slot, and only as a WEAK mention.
struct SymbolMention
{
    bool        matched = false;
    bool        strong  = false;
    std::size_t pos     = 0;
};

inline SymbolMention symbolMention( std::string_view task, std::string_view lowerTask, std::string_view name )
{
    const bool strong = std::any_of( name.begin(), name.end(), []( const unsigned char c )
    {
        return std::isupper( c ) || c == '_' || c == ':' || c == '$';
    } );
    if( !strong && !weakSymbolCandidate( name ) )
    {
        return {};
    }
    const std::size_t pos = strong ? boundedFind( task, name ) : findInSymbolSlot( lowerTask, name );
    if( pos == std::string_view::npos )
    {
        return {};
    }
    return { true, strong, pos };
}

inline std::vector<std::string> resolveTaskSymbols( std::string_view task, const IngestResult& ing )
{
    struct At { std::size_t pos; std::string name; };
    std::vector<At>   found;
    std::vector<At>   weak;
    const std::string lowerTask = lowerAscii( task );
    for( const Symbol& sym : ing.symbols )
    {
        const SymbolMention at = symbolMention( task, lowerTask, sym.name );
        if( !at.matched )
        {
            continue;
        }
        std::vector<At>& bucket = at.strong ? found : weak;
        const bool duplicate = std::any_of( bucket.begin(), bucket.end(), [&]( const At& s ) { return s.name == sym.name; } );
        if( !duplicate )
        {
            bucket.push_back( { at.pos, sym.name } );
        }
    }
    // The weak tier is consulted only when it is the ONLY reading available: no strong mention anywhere in
    // the task, and exactly one distinct weak name. The original ambiguity worry then holds STRUCTURALLY
    // rather than by heuristic — a single resolved symbol can never satisfy the three-symbol --connect
    // precondition, so ordinary prose still cannot mint a graph route out of dictionary words.
    if( found.empty() && weak.size() == 1 )
    {
        found = std::move( weak );
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

// A literal-search route needs a literal the user actually supplied, never one inferred from prose.
// Accept the first balanced single-, double- or backtick-quoted span; an unmatched/empty quote abstains.
// A single quote counts only at a word boundary on BOTH ends — a prose apostrophe ("the user's config
// and the team's settings") sits inside identifier characters and must never mint a grep literal.
inline std::string firstQuotedLiteral( std::string_view task )
{
    const auto isWordByte = []( char c ) noexcept
    { return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_'; };
    for( std::size_t i = 0; i < task.size(); ++i )
    {
        const char quote = task[i];
        if( quote != '\'' && quote != '"' && quote != '`' )
        {
            continue;
        }
        if( quote == '\'' && i > 0 && isWordByte( task[i - 1] ) )
        {
            continue;   // word-internal apostrophe (possessive/contraction), not an opening quote
        }
        const std::size_t end = task.find( quote, i + 1 );
        if( end == std::string_view::npos || end == i + 1 )
        {
            continue;
        }
        if( quote == '\'' && end + 1 < task.size() && isWordByte( task[end + 1] ) )
        {
            continue;   // the closing candidate is itself word-internal — same apostrophe class
        }
        return std::string( task.substr( i + 1, end - i - 1 ) );
    }
    return {};
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

// A plan path the user actually WROTE. The router never invents one: --edit-plan refuses a file that is
// not there, and recommending a command the verb refuses is a prerequisite violation, not a suggestion.
inline std::string firstJsonPathToken( std::string_view task )
{
    constexpr std::string_view kBreaks = " \t\n\r\"'`(),;";
    for( std::size_t i = 0; i < task.size(); )
    {
        const std::size_t begin = task.find_first_not_of( kBreaks, i );
        if( begin == std::string_view::npos )
        {
            break;
        }
        std::size_t end = task.find_first_of( kBreaks, begin );
        if( end == std::string_view::npos )
        {
            end = task.size();
        }
        const std::string_view token = task.substr( begin, end - begin );
        if( token.ends_with( ".json" ) || token.ends_with( ".ndjson" ) )
        {
            return std::string( token );
        }
        i = end + 1;
    }
    return {};
}

// Routes for surfaces whose trigger is a NAME rather than a phrase-scoring shape: the flag is asked for by
// something close to its own vocabulary, so a weighted score would only add noise. Each requires
// conjunctive evidence — the surface word AND an intent word — so a passing mention never routes. The two
// that carry a user-supplied value (a plan path, a grep literal) fire only when the task supplies it;
// substituting a placeholder would emit a command the verb refuses, which the contract forbids outright.
inline std::optional<RouteChoice> instrumentedTaskChoice( std::string_view task, std::string_view lower, const std::string& root )
{
    const std::string ripRoot = "ripwire " + shSingleQuote( root ) + " ";
    if( ( has( lower, "edit plan" ) || has( lower, "edit-plan" ) || has( lower, "multi-edit" ) || has( lower, "multi edit" ) )
     && ( has( lower, "apply" ) || has( lower, "transaction" ) || has( lower, "preflight" ) || has( lower, "dry run" ) || has( lower, "dry-run" ) ) )
    {
        const std::string plan = firstJsonPathToken( task );
        if( !plan.empty() )
        {
            return RouteChoice{ "apply-edit-plan", "ripwire-mcp", "multi-edit transaction wording plus a named plan file",
                                commandWithValue( root, "--edit-plan=", plan ) + " --dry-run", 100, 89 };
        }
    }
    // "handle" must be word-bounded: an existing fixture asks to search "the user's config handling", and
    // a substring match there would steal a plain exact-grep away from its own route.
    if( ( boundedFind( lower, "handle" ) != std::string_view::npos || boundedFind( lower, "handles" ) != std::string_view::npos )
     && ( has( lower, "edit" ) || has( lower, "grep" ) || has( lower, "search" ) || has( lower, "occurrence" ) ) )
    {
        const std::string quoted = firstQuotedLiteral( task );
        if( !quoted.empty() )
        {
            return RouteChoice{ "grep-handles", "ripwire-mcp", "safe-edit handle wording plus a quoted literal to anchor them",
                                commandWithValue( root, "--grep=", quoted ) + " --handles", 100, 88 };
        }
    }
    if( has( lower, "compact legend" ) || ( has( lower, "legend" ) && has( lower, "compact" ) ) )
    {
        return RouteChoice{ "compact-legend", "ripwire-efficient", "compact-legend wording; the posture applies to --for and --grep",
                            commandWithValue( root, "--for=", task ) + " --legend=compact", 100, 87 };
    }
    if( has( lower, "codex" )
     && ( has( lower, "doctor" ) || has( lower, "integration" ) || has( lower, "wired" ) || has( lower, "set up" ) || has( lower, "setup" ) ) )
    {
        return RouteChoice{ "codex-doctor", "ripwire-mcp", "codex plus integration/health wording",
                            ripRoot + "--doctor --agent=codex", 100, 86 };
    }
    if( ( has( lower, "shell gate" ) || has( lower, "test gate" ) || has( lower, "test-gate" ) )
     && ( has( lower, "evidence" ) || has( lower, "why" ) || has( lower, "which" ) || has( lower, "picked" ) || has( lower, "chose" ) ) )
    {
        return RouteChoice{ "gate-evidence", "ripwire-change-check", "shell-gate selection asked for by its evidence",
                            ripRoot + "--test-gate", 100, 85 };
    }
    return std::nullopt;
}

// High-confidence additions that need more than the generic phrase scorer, kept out of classify so the
// central routing ladder stays readable as instrumented intents grow.
inline std::optional<RouteChoice> directTaskChoice( std::string_view task, std::string_view lower,
                                                    const std::string& root, const std::vector<std::string>& symbols )
{
    // The instrumented surfaces are asked for BY NAME, so they outrank the generic literal/post-edit
    // shapes: "find every occurrence of 'X' and give me safe-edit handles" is a handles request that
    // happens to contain a grep, not the other way round.
    if( std::optional<RouteChoice> named = instrumentedTaskChoice( task, lower, root ) )
    {
        return named;
    }
    const bool exactSearch = has( lower, "exact occurrence" ) || has( lower, "exact literal" )
                          || has( lower, "find every" ) || has( lower, "search for" );
    const std::string quoted = exactSearch ? firstQuotedLiteral( task ) : std::string();
    if( !quoted.empty() )
    {
        return RouteChoice{ "exact-grep", "ripwire-navigate", "quoted literal plus exact-search wording",
                            commandWithValue( root, "--grep=", quoted ) + " --grep-context=2 --limit=40", 100, 85 };
    }
    const bool postEdit = has( lower, "just edited" ) || has( lower, "my edit to" )
                       || has( lower, "changed its signature" ) || has( lower, "changed its contract" )
                       || has( lower, "did i change" );
    if( symbols.size() == 1 && postEdit )
    {
        return RouteChoice{ "edit-contract", "ripwire-change-check",
                            "one exact indexed symbol plus post-edit contract wording",
                            commandWithValue( root, "--edit-check=", symbols[0] ), 100, 82 };
    }
    return std::nullopt;
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
    if( std::optional<RouteChoice> direct = directTaskChoice( task, lower, root, result.facts.resolvedSymbols ) )
    {
        result.status = RouteStatus::Recommend;
        result.score  = result.margin = 100;
        result.choices.push_back( std::move( *direct ) );
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
