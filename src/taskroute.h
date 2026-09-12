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

// A cue occurrence that is ALSO the word satisfying an intent gate is not evidence of a symbol slot.
// Without this the understand-symbol route confirms itself out of thin air: its gate is
// `understand | implementation | how does`, and `does`/`understand` were both symbol-slot cues, so every
// English question of the form `how does <indexed-word> …?` minted the very symbol the gate then required
// — the same two words playing both parts (a question about version bumping on a team recommended
// --expand='version', 13 of 25 adversarial prose prompts, 2026-09-10 audit F-R1-01). An intent word is
// evidence about what the user WANTS; it may never double as the positional evidence that they NAMED
// something. Only occurrences are disqualified, never words: a LATER cue in the same task still resolves
// the name (a how-does question that later asks for the body OF the same name routes on that `of`), which is what
// keeps the rule about self-confirmation rather than about the weak tier as a whole. Kept next to the cue
// table, and complete with respect to that gate's three phrases — `implementation` is not a cue at all.
inline bool cueOccurrenceIsIntentGate( std::string_view lowerTask, std::size_t begin, std::string_view cue ) noexcept
{
    if( cue == "understand" || cue == "understanding" )
    {
        return true;   // the gate reads `has( lower, "understand" )`, which this occurrence already satisfies
    }
    if( cue != "does" )
    {
        return false;
    }
    std::size_t end = begin;
    while( end > 0 && lowerTask[end - 1] == ' ' )
    {
        --end;
    }
    std::size_t from = end;
    while( from > 0 && wordByte( lowerTask[from - 1] ) )
    {
        --from;
    }
    return lowerTask.substr( from, end - from ) == "how";   // "how does" IS the gate
}

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
    if( std::none_of( std::begin( kWeakSymbolCues ), std::end( kWeakSymbolCues ),
                      [word]( const std::string_view cue ) { return cue == word; } ) )
    {
        return false;
    }
    return !cueOccurrenceIsIntentGate( lowerTask, begin, word );
}

// A WEAK reading needs the name to be backed by a CODE definition. A t="sec" row is a markdown heading or
// a JSON/TOML/YAML config key — doc structure and data, isolated in the call graph — and an ordinary
// English word collides with those far more often than with a function: six of the thirteen names the
// weak tier falsely resolved on adversarial prose existed ONLY as t="sec" (`version`, `summary`,
// `license`, `agent`, `author`, `notes` — 2026-09-10 audit F-R1-02), so --expand='version' answered with
// `"version": "1.2.3"` out of a package.json at exit 0. The filter is scoped to the weak tier: an
// identifier-shaped (camel/snake/scoped) mention still resolves whatever kind it names, because there the
// SHAPE is the evidence. Rank is deliberately not part of this test — k is 0.0000 for nearly every row in
// any large corpus, so gating on it would make resolution depend on corpus size.
inline bool weakEvidenceKind( SymKind kind ) noexcept
{
    return kind != SymKind::Section;
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
        if( !at.strong && !weakEvidenceKind( sym.kind ) )
        {
            continue;   // this definition is a heading or a config key — no weak evidence (see weakEvidenceKind)
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

// Code-file extensions the FILE half of a FILE:LINE seed is allowed to end in. Deliberately narrow (the
// languages --slice/--at actually serve, per their own legend) rather than "any dotted token" — a prose
// sentence is full of dotted tokens (URLs, "e.g.", version numbers) that are not a source file.
inline constexpr std::string_view kCodeExtensions[] = {
    ".cpp", ".cc", ".cxx", ".h", ".hpp", ".hh", ".c", ".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs",
    ".java", ".rb", ".swift", ".cs", ".m", ".mm", ".cu", ".cuh", ".metal", ".kt",
};

inline bool looksLikeFileToken( std::string_view token ) noexcept
{
    for( const std::string_view ext : kCodeExtensions )
    {
        if( token.size() > ext.size() && token.ends_with( ext ) )
        {
            return true;
        }
    }
    return false;
}

// The FILE:LINE half of the --at/--slice=@FILE:LINE seed grammar, read out of a task in either spelling
// the user might type it: a literal "src/main.cpp:120" token pasted verbatim (a compiler error, a diff
// hunk, a stack frame — the moment --at itself documents), or the same fact said in words ("line 40 in
// budget.cpp" / "line 40 of src/main.cpp"). Structural extraction only — no phrase scoring — because a
// FILE:LINE pair is either present or it is not; there is no paraphrase of a line number.
inline std::string firstFileLineToken( std::string_view task )
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
        std::string_view token = task.substr( begin, end - begin );
        while( !token.empty() && ( token.back() == '.' || token.back() == ':' || token.back() == '?' || token.back() == '!' ) )
        {
            token.remove_suffix( 1 );
        }
        const std::size_t colon = token.rfind( ':' );
        if( colon != std::string_view::npos && colon + 1 < token.size() )
        {
            const std::string_view lineDigits = token.substr( colon + 1 );
            const std::string_view fileGuess  = token.substr( 0, colon );
            const bool allDigits = !lineDigits.empty() && std::all_of( lineDigits.begin(), lineDigits.end(),
                                   []( const unsigned char c ) { return std::isdigit( c ) != 0; } );
            if( allDigits && looksLikeFileToken( fileGuess ) )
            {
                return std::string( fileGuess ) + ":" + std::string( lineDigits );
            }
        }
        i = end + 1;
    }
    // Fallback: "line N" and a code-extensioned path said as two separate words in the same task — both
    // halves of the same seed spoken in prose rather than pasted as one token. Either half alone is too
    // weak to mint a location the --at/--slice seed grammar would accept, so both are required.
    const std::string  lower   = lowerAscii( task );
    const std::size_t  linePos = boundedFind( lower, "line" );
    if( linePos == std::string_view::npos )
    {
        return {};
    }
    std::size_t p = linePos + 4;
    while( p < task.size() && task[p] == ' ' ) { ++p; }
    const std::size_t digitsBegin = p;
    while( p < task.size() && std::isdigit( static_cast<unsigned char>( task[p] ) ) ) { ++p; }
    if( p == digitsBegin )
    {
        return {};
    }
    const std::string_view lineNum = task.substr( digitsBegin, p - digitsBegin );
    for( std::size_t i2 = 0; i2 < task.size(); )
    {
        const std::size_t begin2 = task.find_first_not_of( kBreaks, i2 );
        if( begin2 == std::string_view::npos )
        {
            break;
        }
        std::size_t end2 = task.find_first_of( kBreaks, begin2 );
        if( end2 == std::string_view::npos )
        {
            end2 = task.size();
        }
        std::string_view token2 = task.substr( begin2, end2 - begin2 );
        while( !token2.empty() && ( token2.back() == '.' || token2.back() == ',' || token2.back() == '?' || token2.back() == '!' ) )
        {
            token2.remove_suffix( 1 );
        }
        if( looksLikeFileToken( token2 ) )
        {
            return std::string( token2 ) + ":" + std::string( lineNum );
        }
        i2 = end2 + 1;
    }
    return {};
}

// Cue phrases that place the word right after them in a VARIABLE slot — "trace the flow of budget",
// "the data flowing into total_bytes". A local variable never appears in ing.symbols (extraction indexes
// definitions, not locals), so this is the router's only channel for naming one: purely lexical, mirroring
// the symbol-slot design above (a cue is the whole discriminator, not the word itself). Longer/more
// specific phrases are listed first only for readability; every one is tried and the EARLIEST match in the
// task wins, so overlapping cues ("into" inside "flows into") cannot pick a later, weaker anchor.
inline constexpr std::string_view kVariableSlotCues[] = {
    "the value of", "value of", "flowing into", "flows into", "feeds into", "feed into", "flow of", "into",
};

// A short function-word the extractor should hop over once ("the", "a data flow value of..." style
// filler) rather than accept as the variable itself — "flow of the budget" should name budget, not the.
inline constexpr std::string_view kVariableSlotFillers[] = {
    "the", "a", "an", "this", "that", "it", "its", "data", "value", "code",
};

inline std::string variableSlotCandidate( std::string_view task, std::string_view lowerTask ) noexcept
{
    std::size_t bestPos = std::string_view::npos;
    std::size_t bestEnd = 0;
    for( const std::string_view cue : kVariableSlotCues )
    {
        for( std::size_t from = 0; ; )
        {
            const std::size_t p = boundedFind( lowerTask, cue, from );
            if( p == std::string_view::npos )
            {
                break;
            }
            if( bestPos == std::string_view::npos || p < bestPos )
            {
                bestPos = p;
                bestEnd = p + cue.size();
            }
            from = p + 1;
        }
    }
    if( bestPos == std::string_view::npos )
    {
        return {};
    }
    std::size_t begin = bestEnd;
    for( int hop = 0; hop < 2; ++hop )
    {
        while( begin < task.size() && task[begin] == ' ' ) { ++begin; }
        std::size_t end = begin;
        while( end < task.size() && wordByte( task[end] ) ) { ++end; }
        if( end == begin )
        {
            return {};
        }
        const std::string_view word   = task.substr( begin, end - begin );
        const std::string      lowered = lowerAscii( word );
        bool filler = false;
        for( std::size_t f = 0; f < std::size( kVariableSlotFillers ) && !filler; ++f )
        {
            filler = kVariableSlotFillers[f] == lowered;
        }
        if( !filler )
        {
            return std::string( word );
        }
        begin = end;
    }
    return {};
}

inline void addLexical( std::vector<RouteChoice>& choices, const char* id, const char* skill, const char* reason,
                        std::string command, int score, int floor, int priority )
{
    if( score >= floor )
    {
        choices.push_back( { id, skill, reason, std::move( command ), score, priority } );
    }
}

// A path the user actually WROTE, recognised by its extension. The router never invents one: --edit-plan
// and --plan-lint both refuse a file that is not there, and recommending a command the verb refuses is a
// prerequisite violation, not a suggestion. One extractor for every value-carrying path route, so the two
// cannot disagree about what counts as a written path.
inline std::string firstPathTokenWithSuffix( std::string_view task, std::initializer_list<std::string_view> suffixes )
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
        std::string_view token = task.substr( begin, end - begin );
        while( !token.empty() && ( token.back() == '.' || token.back() == '?' || token.back() == '!' ) )
        {
            token.remove_suffix( 1 );
        }
        for( const std::string_view suffix : suffixes )
        {
            if( token.size() > suffix.size() && token.ends_with( suffix ) )
            {
                return std::string( token );
            }
        }
        i = end + 1;
    }
    return {};
}

inline std::string firstJsonPathToken( std::string_view task )
{
    return firstPathTokenWithSuffix( task, { ".json", ".ndjson" } );
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
        return RouteChoice{ "compact-legend", "ripwire-orient", "compact-legend wording; the posture applies to --for and --grep",
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
// The three "where did this value come from" surfaces — --slice=@FILE:LINE (a named location),
// --uses=SYM (writer-attribution wording), --slice=SYM[:VAR] (data-flow wording) — extracted out of
// directTaskChoice the same way instrumentedTaskChoice is above it, so the central ladder stays readable
// as intents grow.
inline std::optional<RouteChoice> flowTaskChoice( std::string_view task, std::string_view lower,
                                                  const std::string& root, const std::vector<std::string>& symbols )
{
    // at-line: a FILE:LINE seed the task NAMES, in either spelling the --at/--slice=@FILE:LINE grammar
    // documents — a location IS the seed, so this is a structural check, not a phrase-scored one.
    const std::string fileLine = firstFileLineToken( task );
    if( !fileLine.empty() )
    {
        return RouteChoice{ "at-line", "ripwire-navigate", "a file:line location named in the task",
                            commandWithValue( root, "--slice=", "@" + fileLine ), 100, 84 };
    }
    // who-writes: "who writes/sets/modifies/assigns SYM" needs exactly one resolved symbol, the same
    // discipline edit-contract uses. --uses=SYM is the closest shipped surface (every resolvable
    // read/write/import/call/extends site, not writes alone); a write-only filter is future work. The
    // dotted Owner.field phrasing ("who writes Symbol.name") is NOT specially parsed here — the field
    // half is lane E's, kept deliberately uncoupled — so today the router resolves only the OWNER symbol
    // ("Symbol" out of "Symbol.name", via the existing word-bounded symbol match) and routes to it.
    const int whoWritesScore = phraseScore( lower, { { "who writes", 9 }, { "who sets", 8 }, { "who modifies", 8 },
                                                     { "who assigns", 8 }, { "who mutates", 7 },
                                                     { "writes the field", 8 }, { "sets the field", 7 },
                                                     { "writes to", 5 } } );
    if( symbols.size() == 1 && whoWritesScore >= 7 )
    {
        return RouteChoice{ "who-writes", "ripwire-navigate",
                            "one exact indexed symbol plus writer-attribution wording (Owner.field coupling deferred)",
                            commandWithValue( root, "--uses=", symbols[0] ), 100, 81 };
    }
    // data-flow: "where does this value come from" / "which statements feed X" / "trace the flow of X"
    // needs exactly one resolved symbol too — --slice needs a SYM to pick the one definition to slice.
    // A variable named through a slot cue ("value of X", "into X", "flow of X") upgrades the command to
    // the transitive --slice-flow=back walk; without one, bare --slice=SYM lists the sliceable locals —
    // a real, runnable command (the verb's own documented bare-SYM form), never a placeholder the verb
    // would refuse.
    const int dataFlowScore = phraseScore( lower, { { "data flow", 9 }, { "which statements feed", 9 },
                                                    { "statements feed", 8 }, { "trace the flow", 8 },
                                                    { "trace the data", 7 }, { "flow of the value", 8 },
                                                    { "where does this value come from", 9 },
                                                    { "where does the value", 7 }, { "flows into", 6 },
                                                    { "feeds into", 6 }, { "value flow", 6 } } );
    if( symbols.size() == 1 && dataFlowScore >= 7 )
    {
        const std::string variable = variableSlotCandidate( task, lower );
        if( !variable.empty() && variable != symbols[0] )
        {
            return RouteChoice{ "data-flow", "ripwire-navigate",
                                "one exact indexed symbol plus data-flow wording plus a variable-slot mention",
                                commandWithValue( root, "--slice=", symbols[0] + ":" + variable ) + " --slice-flow=back", 100, 83 };
        }
        return RouteChoice{ "data-flow", "ripwire-navigate",
                            "one exact indexed symbol plus data-flow wording (no variable named — lists its locals)",
                            commandWithValue( root, "--slice=", symbols[0] ), 100, 83 };
    }
    return std::nullopt;
}

// ── the catalog tier: verbs and skills the router could not name at all ───────────────────────────────
// The 2026-09-10 audit measured `--help-task` at 3 recommends over 39 phrasings of the 13 surfaces added
// since 2026-08-28 (F-R1-08), and found the router able to name 8 of the 16 shipped skills (F-R1-09) —
// `--help-task` and the skill catalog were two routers with two vocabularies. These routes close both
// gaps for the surfaces that are VERBS rather than shaping flags. They sit LAST in directTaskChoice on
// purpose: every route above them is older, more specific, and keeps its rows unchanged.
//
// Each requires conjunctive evidence in the same shape instrumentedTaskChoice uses — the surface asked
// for close to its own vocabulary, plus a second word that says it is being asked FOR — and the two that
// carry a user-supplied value fire only when the task supplies it. What is deliberately NOT here, and
// why: `--scope`, `--slice-depth`, `--slice-flow`, `--allow-dirty`, `--no-ignore`, `--no-post-check` are
// SHAPING flags on other verbs, not commands a one-command router can recommend on their own.
inline std::optional<RouteChoice> catalogTaskChoice( std::string_view task, std::string_view lower,
                                                     const std::string& root, const std::vector<std::string>& symbols )
{
    const std::string ripRoot = "ripwire " + shSingleQuote( root ) + " ";
    // handoff: brief SOMEONE ELSE. The discriminator against orient is the second party — a successor, a
    // teammate, the next session — never the speaker's own understanding.
    const int handoffScore = phraseScore( lower, { { "hand off", 9 }, { "hand this off", 9 }, { "handing off", 9 },
                                                   { "hand-off", 8 }, { "handover", 8 }, { "hand over", 8 },
                                                   { "takes it over", 8 }, { "taking over", 7 }, { "take it over", 7 },
                                                   { "next session", 7 }, { "successor", 7 }, { "picks this up", 7 },
                                                   { "whoever", 6 }, { "going on leave", 7 }, { "brief the next", 8 },
                                                   { "brief someone", 8 }, { "for the next agent", 8 },
                                                   { "onboard", 5 }, { "teammate", 5 } } );
    if( handoffScore >= 7 )
    {
        return RouteChoice{ "handoff-brief", "ripwire-handoff", "briefing a SECOND party (successor/teammate/next session)",
                            ripRoot + "--handoff", 100, 79 };
    }
    // plan-lint: a PLAN/DESIGN file's structure. Value-carrying — the verb refuses a file that is not
    // there, so the route fires only when the task names one.
    const std::string planDoc  = firstPathTokenWithSuffix( task, { ".md", ".markdown" } );
    const std::string planDocL = lowerAscii( planDoc );
    // The file may name ITSELF as the plan (docs/cache-plan.md, docs/design-notes.md) — that is surface evidence
    // the task's prose does not have to repeat.
    if( ( has( lower, "plan" ) || has( lower, "design doc" ) || has( lower, "design document" )
       || has( planDocL, "plan" ) || has( planDocL, "design" ) )
     && ( has( lower, "lint" ) || has( lower, "structure" ) || has( lower, "well-formed" ) || has( lower, "sections" )
       || has( lower, "shape" ) || has( lower, "check" ) ) )
    {
        if( !planDoc.empty() )
        {
            return RouteChoice{ "plan-lint", "ripwire-before-you-build", "plan/design structure wording plus a named markdown file",
                                commandWithValue( root, "--plan-lint=", planDoc ), 100, 78 };
        }
    }
    // trace-prose: the user SAYS they are holding a trace instead of pasting one. looksLikeTrace matches a
    // pasted artifact (`AddressSanitizer:`, `#0 … in`), and a sanitizer REPORT described in words contains
    // none of those literals, so the #108 name-ladder work was unreachable from prose (F-R1-08 §1.2).
    const bool holdsTrace = has( lower, "sanitizer report" ) || has( lower, "asan report" ) || has( lower, "crash log" )
                         || has( lower, "compiler error" ) || has( lower, "backtrace" ) || has( lower, "core dump" )
                         || has( lower, "build error" ) || has( lower, "panic message" );
    if( holdsTrace
     && ( has( lower, "map" ) || has( lower, "onto" ) || has( lower, "which symbol" ) || has( lower, "indexed" )
       || has( lower, "translate" ) || has( lower, "i have" ) || has( lower, "here is" ) || has( lower, "frames" ) ) )
    {
        return RouteChoice{ "trace-prose", "ripwire-find-bug", "a trace/report described rather than pasted; pass it on stdin",
                            ripRoot + "--from-trace=-", 100, 77 };
    }
    // security-scan: vetting something UNTRUSTED before installing it. --scan-skills defaults its directory,
    // so the valueless form is a real command; a named file upgrades it to --scan-skill=FILE.
    const int scanScore = phraseScore( lower, { { "before installing", 9 }, { "before i install", 9 },
                                                { "prompt injection", 9 }, { "exfiltration", 9 }, { "untrusted", 7 },
                                                { "vet", 6 }, { "audit", 4 }, { "safe to install", 9 },
                                                { "skill file", 6 }, { "mcp.json", 6 }, { "skill", 3 } } );
    if( scanScore >= 9 && ( has( lower, "skill" ) || has( lower, "mcp" ) || has( lower, "install" ) ) )
    {
        const std::string skillFile = firstPathTokenWithSuffix( task, { ".md", ".markdown", ".json", ".sh" } );
        return skillFile.empty()
             ? RouteChoice{ "scan-skills", "ripwire-security-scan", "pre-install vetting wording; --scan-skills defaults its directory",
                            ripRoot + "--scan-skills", 100, 76 }
             : RouteChoice{ "scan-skill", "ripwire-security-scan", "pre-install vetting wording plus a named file",
                            commandWithValue( root, "--scan-skill=", skillFile ), 100, 76 };
    }
    // opt-remarks: clang optimization remarks while building ripwire itself. The ONLY skill with no verb of
    // its own — the ranked lens is what finds the symbol a remark names, and the reason says exactly that
    // rather than implying a dedicated surface exists.
    if( has( lower, "not vectorized" ) || has( lower, "will not be inlined" ) || has( lower, "-rpass" )
     || has( lower, "opt-record" ) || has( lower, "optimization remark" ) || has( lower, "optimisation remark" ) )
    {
        return RouteChoice{ "opt-remark", "ripwire-opt-remarks", "a clang optimization remark; the ranked lens locates the symbol it names",
                            commandWithValue( root, "--for=", task ), 100, 75 };
    }
    // architecture-health: cycles, god files, propagation. --arch=FILE is the GATING form and needs a rules
    // file the task names; without one, --deps is the real, runnable overview the same skill leads with.
    const int layersScore = phraseScore( lower, { { "layering", 9 }, { "layer violation", 9 }, { "dependency mess", 9 },
                                                  { "module boundaries", 9 }, { "circular dependenc", 9 },
                                                  { "dependency cycle", 9 }, { "god file", 8 }, { "godfile", 8 },
                                                  { "propagation cost", 9 }, { "architecture health", 9 },
                                                  { "reaches into the database", 9 }, { "cycles", 5 } } );
    if( layersScore >= 8 )
    {
        return RouteChoice{ "architecture-health", "ripwire-layers", "architecture-health wording (--arch=FILE is the gating form and needs a rules file)",
                            ripRoot + "--deps", 100, 74 };
    }
    // quality-bar: what YOU just wrote, before you call it done. Deliberately narrow so it cannot steal the
    // dirty-worktree review route below, whose wording is about a DIFF and a push rather than about debt.
    // "before i commit" is a TIMING word, not a quality word — on its own it also fits linting a plan or
    // running a gate, and at the old weight it stole "lint the plan file layout before I commit it" from
    // the plan-lint abstention above. Weighted below the floor so it can only ever CONFIRM a quality word.
    const int qualityScore = phraseScore( lower, { { "call it done", 9 }, { "before i commit", 6 },
                                                   { "new debt", 9 }, { "made anything worse", 9 },
                                                   { "made it worse", 8 }, { "got worse", 8 },
                                                   { "code i just wrote", 9 }, { "quality of what i", 9 },
                                                   { "verify the cleanup", 9 }, { "quality bar", 8 } } );
    if( qualityScore >= 9 )
    {
        return RouteChoice{ "quality-check", "ripwire-quality-bar", "own-code quality wording (what got WORSE), not merge safety",
                            ripRoot + "--quality-delta", 100, 73 };
    }
    // perf-target: a MEASURED profile that NAMES a symbol. Static metrics are not runtime heat, so this
    // needs the profile wording AND the one symbol the profile named — never the wording alone.
    const int perfScore = phraseScore( lower, { { "profiler", 9 }, { "flame graph", 9 }, { "flamegraph", 9 },
                                                { "perf sample", 9 }, { "perf record", 9 }, { "hot symbol", 8 },
                                                { "hot path", 7 }, { "hottest", 8 }, { "benchmark says", 8 },
                                                { "cpu time", 7 }, { "profile names", 8 } } );
    if( symbols.size() == 1 && perfScore >= 7 )
    {
        return RouteChoice{ "perf-symbol", "ripwire-perf-target", "a measured profile plus the one symbol it names",
                            commandWithValue( root, "--around=", symbols[0] ), 100, 72 };
    }
    // graph-query: a closure question the fixed verbs cannot phrase. The EXPRESSION is built only out of
    // what the task supplied — the symbol it named and the direction it asked for — and the depth is a
    // stated default the reason names, the same way --grep-context=2 and --slice-flow=back are.
    const int closureScore = phraseScore( lower, { { "can reach", 8 }, { "that reach", 8 }, { "everything that reaches", 9 },
                                                   { "transitively", 7 }, { "within one hop", 8 }, { "within two hops", 8 },
                                                   { "graph query", 9 }, { "call graph question", 9 }, { "fan-in", 7 } } );
    if( symbols.size() == 1 && closureScore >= 7 )
    {
        const bool outward = has( lower, "reachable from" ) || has( lower, "everything it calls" ) || has( lower, "downstream of" );
        const std::string expr = std::string( outward ? "callees(name(\"" : "callers(name(\"" ) + symbols[0] + "\"),3)";
        return RouteChoice{ "graph-query", "ripwire-graph-query", "a bounded-closure question plus one named symbol (depth 3 is the default; raise it)",
                            commandWithValue( root, "--graph-query=", expr ), 100, 71 };
    }
    // fresh-eyes: maintenance risk in code the speaker did NOT write. LAST of the catalog tier because its
    // vocabulary is the broadest, so every more specific reading above gets first refusal.
    const int riskScore = phraseScore( lower, { { "gnarly", 9 }, { "where is the rot", 9 }, { "the rot", 8 },
                                                { "safe to touch", 9 }, { "god object", 9 }, { "maintenance risk", 9 },
                                                { "did not write", 8 }, { "didn't write", 8 }, { "i inherited", 8 },
                                                { "inherited", 6 }, { "where maintenance hurts", 9 }, { "bus factor", 9 } } );
    if( riskScore >= 8 )
    {
        return RouteChoice{ "maintenance-risk", "ripwire-fresh-eyes", "maintenance-risk wording about code the speaker did not write",
                            ripRoot + "--hotspots", 100, 70 };
    }
    return std::nullopt;
}

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
    // Both of these were fixed OR-chains of four or five literal phrases, which meant they recognised the
    // wording they were written against and nothing else: "did X's contract change after my patch" is not
    // "did i change", and "just finished editing X" is not "just edited". They now use the same weighted
    // phraseScore + floor the four generic categories use, so paraphrases accumulate evidence instead of
    // having to match one blessed spelling. Neither floor is the whole gate: exact-grep still needs a
    // literal the user actually quoted, and edit-contract still needs exactly one resolved symbol, so the
    // widened vocabulary can only choose BETWEEN routes, never invent one out of prose.
    const int exactScore = phraseScore( lower, { { "exact occurrence", 9 }, { "exact literal", 9 },
                                                 { "every occurrence", 8 }, { "occurrences of", 8 }, { "verbatim", 8 },
                                                 { "find every", 7 }, { "every place", 7 }, { "search for", 7 },
                                                 { "look for", 6 }, { "grep", 6 }, { "the string", 5 },
                                                 { "where does", 5 }, { "exactly", 4 }, { "literal", 4 },
                                                 { "show up", 4 }, { "across the repo", 4 }, { "in the codebase", 3 } } );
    const std::string quoted = exactScore >= 6 ? firstQuotedLiteral( task ) : std::string();
    if( !quoted.empty() )
    {
        return RouteChoice{ "exact-grep", "ripwire-navigate", "quoted literal plus exact-search wording",
                            commandWithValue( root, "--grep=", quoted ) + " --grep-context=2 --limit=40", 100, 85 };
    }
    const int postEditScore = phraseScore( lower, { { "just edited", 9 }, { "just finished editing", 9 },
                                                    { "my edit to", 9 }, { "changed its signature", 9 },
                                                    { "changed its contract", 9 }, { "compatible with callers", 8 },
                                                    { "break its callers", 8 }, { "break any caller", 8 },
                                                    { "did i change", 8 }, { "i edited", 8 }, { "i modified", 8 },
                                                    { "i just changed", 8 }, { "after my patch", 7 },
                                                    { "after my change", 7 }, { "since my edit", 7 },
                                                    { "contract change", 7 }, { "still compatible", 7 },
                                                    { "break anyone", 7 } } );
    if( symbols.size() == 1 && postEditScore >= 7 )
    {
        return RouteChoice{ "edit-contract", "ripwire-change-check",
                            "one exact indexed symbol plus post-edit contract wording",
                            commandWithValue( root, "--edit-check=", symbols[0] ), 100, 82 };
    }
    // at-line / who-writes / data-flow: structural or phrase-scored the same way the categories above
    // are, just extracted into their own function (see flowTaskChoice's own comment) to keep this ladder
    // from growing without bound as more "where did this value come from" surfaces are added.
    if( std::optional<RouteChoice> flow = flowTaskChoice( task, lower, root, symbols ) )
    {
        return flow;
    }
    // catalog tier LAST: the verbs and skills the router could not name at all before 2026-09-10. Every
    // route above this line is older and more specific and keeps its rows unchanged (measured: all 189
    // corpus rows byte-identical on status/intent across this addition).
    if( std::optional<RouteChoice> catalog = catalogTaskChoice( task, lower, root, symbols ) )
    {
        return catalog;
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

    const int writeTestsScore = phraseScore( lower, { { "missing coverage", 8 }, { "no tests", 6 }, { "untested", 5 },
                                                      { "regression gate", 4 }, { "add", 3 }, { "write", 3 },
                                                      { "find", 2 }, { "cover", 2 } } );
    addLexical( candidates, "write-tests", "ripwire-write-tests", "test-gap wording plus a test-writing action",
                "ripwire " + shSingleQuote( root ) + " --seams", writeTestsScore, 8, 35 );

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
