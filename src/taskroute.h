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
#include "sarif.h"           // rootRelativeUri / rootPrefixOf — the ONE root-relative path rule the map emits with
#include "verify.h"          // parseClaim — the SHIPPED claim grammar; the router never re-implements it
#include "compactlegend.h"  // rw::legendCompactAppliesTo — ONE answer to "does --legend=compact apply here"
#include "commentcoherence.h" // rw::isCommentStopword — the general-English stoplist, reused rather than duplicated

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

// What the BUILD the recommendation will be handed to can actually parse. A router that composes a flag
// its own binary has no row for recommends a command that exits non-zero on the first paste — the same
// prerequisite violation as naming a plan file that is not there, arriving from the other direction. The
// caller fills this in from cli.h's own flag table (main.cpp), so a surface that lands one release later
// is composed by the build that ships it and by no earlier one.
struct RouterCaps
{
    bool dirScope = false;   // --in=DIR, the directory scope on the churn-decay window
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

// "is this word one of these?" — the shape four tables' predicates were each writing out by hand, which is
// how a five-line any_of becomes a duplication finding against its own neighbours.
inline bool isOneOf( std::string_view word, const std::string_view* table, std::size_t count ) noexcept
{
    return std::any_of( table, table + count, [word]( const std::string_view t ) { return t == word; } );
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

// HOW a cue is matched is the only thing the two spellings below differ in, so it is a parameter and not a
// second loop: a bare WORD matched as a substring is a different word — `here` occurs inside
// where/there/adhere, `file` inside profile, `code` inside codec, `moving` inside removing. Getting that
// wrong is not academic: with the substring spelling the recency route below recommended the churn window,
// at confidence="high", for a sentence about a supplier revising their terms (2026-09-13 review).
//
// A multi-word cue is SAFER, not safe, and the first round of that review overstated it as "a phrase
// carries its own boundaries". The space inside a phrase delimits its interior and nothing at its two
// ENDS: `how do` is found across `show documentation`, `how is` across `show issues`. So Substring is not
// a licence — it is for the phrases whose first and last words do not finish or begin ordinary words, and
// a caller that cannot say that of its own cues asks for WordBounded (kExplanatoryCues does).
enum class CueMatch : std::uint8_t { Substring, WordBounded };

inline int cueScore( std::string_view lower, CueMatch how,
                     std::initializer_list<std::pair<std::string_view, int>> cues ) noexcept
{
    int score = 0;
    for( const auto& [ cue, weight ] : cues )
    {
        const bool hit = how == CueMatch::WordBounded ? boundedFind( lower, cue ) != std::string_view::npos
                                                      : has( lower, cue );
        if( hit )
        {
            score += weight;
        }
    }
    return score;
}

inline int phraseScore( std::string_view lower, std::initializer_list<std::pair<std::string_view, int>> phrases ) noexcept
{
    return cueScore( lower, CueMatch::Substring, phrases );
}

inline int wordScore( std::string_view lower, std::initializer_list<std::pair<std::string_view, int>> words ) noexcept
{
    return cueScore( lower, CueMatch::WordBounded, words );
}

// Is `task` a harness/system event rather than something a user typed — a background-task wake-up or an
// injected reminder, delivered to UserPromptSubmit through the same channel as a real prompt (Claude Code
// routes both `<task-notification>…</task-notification>` completions and `<system-reminder>…</system-reminder>`
// blocks this way)? Both the Claude Code and Codex UserPromptSubmit router hooks (under hooks/, filenames
// ending "-route.sh") skip calling this classifier at all on such input — a bash-level guard mirroring the
// PreToolUse tool-call router's own pre-classification notification check (hooks/, filename ending
// "-toolroute.sh") — but --help-task is also callable directly: by a test, by an MCP client, by a future
// integration that does not go through either hook. So the same discipline lives here too, rather than
// only at the shell layer. A background-task report is mostly prose quoting machine output (a sanitizer
// excerpt, a diff, an XML `<result>` block): before this guard existed, that prose could mint a
// `--from-trace=-`/`--grep=`/`--connect=` recommendation out of text that named no task at all (the
// routing-noise round, docs/EVALS.md). Narrow and literal on purpose — this is a shape check on the
// harness's own wake-up markers, not a guess at what a user prompt looks like: only the FIRST non-
// whitespace bytes are tested, so a user prompt that happens to mention `<task-notification>` in the
// middle of a sentence ("what does <task-notification> mean in the hook?") is unaffected.
inline bool looksLikeSystemEvent( std::string_view task ) noexcept
{
    std::size_t i = 0;
    while( i < task.size() && ( task[i] == ' ' || task[i] == '\t' || task[i] == '\n' || task[i] == '\r' ) )
    {
        ++i;
    }
    const std::string_view rest = task.substr( i );
    return rest.starts_with( "<task-notification>" ) || rest.starts_with( "<system-reminder>" );
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
    if( !isOneOf( word, std::begin( kWeakSymbolCues ), std::size( kWeakSymbolCues ) ) )
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
    return !isOneOf( name, std::begin( kWeakSymbolStopWords ), std::size( kWeakSymbolStopWords ) );
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

// A NAME that carries at least one of {uppercase, '_', ':', '$'} is a STRONG-mention CANDIDATE — but the
// byte alone is not evidence, only the reason to look closer. Ripwire's own fixture corpora define
// single-word symbols literally named `A`, `E`, `Fix`, `Summary`, `Report`, `Lane`, `Split` and `WORK`
// (test fixtures written for unrelated rounds), and the old rule here — ANY uppercase/underscore/colon/
// dollar byte anywhere in the name — let a bare leading capital through on shape alone. A background-task
// report quoting prose like "Summary: A, Fix, Report" then satisfied it for four different names in one
// sentence, minting a spurious `--connect=` recommendation (>=3 "resolved symbols") out of text that never
// named a task at all — the routing-noise round (docs/EVALS.md). Genuine shape, checked in this order:
//   1. The occurrence itself is explicitly marked as code IN THE PROMPT — wrapped in backticks, or
//      immediately followed by "()" (a call). This overrides the name's own shape: a user who writes
//      `` `Report` `` or `Report()` has said, unambiguously, "this is code".
//   2. Otherwise the NAME must carry real identifier punctuation: an interior uppercase letter directly
//      after a lowercase one (a camel/Pascal SEAM — "CacheNode" qualifies, a bare leading capital like
//      "Report" does not), an underscore, a "::"/"." qualifier, or a "$". A SCREAMING word (uppercase
//      throughout, no lowercase — "WORK") never qualifies here: it has no seam to test, and a short
//      all-caps word is exactly the collision class step 1 exists to admit only when the prompt itself
//      marks it as code — single letters and all-caps short words never count unless backticked.
//   3. Failing both, the bare word still counts if it is at least 4 bytes, carries a lowercase letter (so
//      SCREAMING is excluded here too), and is not an ordinary English word — reusing commentcoherence.h's
//      isCommentStopword first (general reuse, mandatory before adding anything new), then a second,
//      narrowly-scoped list (kShapelessCollisionWords, below) for the ordinary NOUNS a function-word list
//      does not carry ("report", "summary", "split", "lane" — the routing-noise round's own noise text:
//      "Summary: A, Fix, Report" and "...Lane E WORK"). Kept separate from kWeakSymbolStopWords on
//      purpose: that list governs the ALL-LOWERCASE weak tier and has its own audited scope (2026-09-10),
//      and folding this round's words into it would let an unrelated future round's behavior drift.
inline bool identifierMentionShape( std::string_view task, std::size_t pos, std::string_view name ) noexcept
{
    // Precondition from the one call site: `name` was located AT `pos` by boundedFind( task, name )
    // immediately before this call, so [pos, pos+name.size()) is inside `task` by construction. This is
    // the caller's contract, not this function's own invariant, so EXPECTS rather than ASSUME.
    EXPECTS( pos + name.size() <= task.size(), "the caller resolved name at pos via boundedFind first" );
    const bool backticked = pos > 0 && pos + name.size() < task.size()
                          && task[pos - 1] == '`' && task[pos + name.size()] == '`';
    const bool calledForm = pos + name.size() + 1 < task.size()
                          && task[pos + name.size()] == '(' && task[pos + name.size() + 1] == ')';
    if( backticked || calledForm )
    {
        return true;
    }

    bool hasLower = false, hasUpper = false, camelSeam = false, hasUnderscore = false;
    for( std::size_t i = 0; i < name.size(); ++i )
    {
        const unsigned char c = (unsigned char)name[i];
        if( c == '_' ) { hasUnderscore = true; continue; }
        if( std::islower( c ) ) { hasLower = true; }
        if( std::isupper( c ) )
        {
            hasUpper = true;
            if( i > 0 && std::islower( (unsigned char)name[i - 1] ) ) { camelSeam = true; }
        }
    }
    const bool scoped = name.find( "::" ) != std::string_view::npos || name.find( '.' ) != std::string_view::npos;
    const bool dollar = name.find( '$' ) != std::string_view::npos;
    if( hasUnderscore || camelSeam || scoped || dollar )
    {
        return true;
    }
    if( !hasLower )
    {
        return false;   // SCREAMING or a lone capital letter — shape alone never counts (step 1 still can)
    }
    if( name.size() < 4 )
    {
        return false;
    }
    const std::string lowered = lowerAscii( name );
    if( isCommentStopword( lowered ) )
    {
        return false;
    }
    // See step 3 above: ordinary nouns a general-English function-word stoplist does not carry, but that
    // this round's own noise prompts used as report/notification prose. Extend here, narrowly, rather
    // than in kWeakSymbolStopWords (a different tier's already-audited list).
    static constexpr std::string_view kShapelessCollisionWords[] = { "lane", "report", "split", "summary" };
    return !isOneOf( lowered, std::begin( kShapelessCollisionWords ), std::size( kShapelessCollisionWords ) );
}

// Where, and how strongly, one indexed name is mentioned in the task. Identifier shape
// (camel/Pascal/snake/scoped, see identifierMentionShape) is a STRONG mention and counts wherever it
// appears. An all-lowercase name is no longer discarded outright — a word-bounded exact hit on the real
// symbol table beats casing as evidence — but it counts only from a symbol slot, and only as a WEAK
// mention.
struct SymbolMention
{
    bool        matched = false;
    bool        strong  = false;
    std::size_t pos     = 0;
};

inline SymbolMention symbolMention( std::string_view task, std::string_view lowerTask, std::string_view name )
{
    // lowerTask is always lowerAscii( task ) at every call site (resolveTaskSymbols builds it once, byte
    // for byte, ASCII-only): findInSymbolSlot's positions into lowerTask are handed straight back out as
    // positions into task, and that substitution is only sound when the two strings are the same length.
    ASSUME( lowerTask.size() == task.size(), "lowerTask is lowerAscii(task) — a position in one is a position in the other" );
    // '.' is here for the same reason ':' is: identifierMentionShape treats a "::" OR "." qualifier as a
    // scoped-name seam (see `scoped` there), so the gate that decides whether to even TRY that shape test
    // must recognize both scope spellings, not just one. Missing this let an all-lowercase dotted name —
    // a real indexed shape: TOML nested tables index as t="sec" symbols named literally "tool.poetry" —
    // fall through to the weak tier, where Section-kind symbols are never weak evidence (weakEvidenceKind),
    // so the name could not resolve even when explicitly backtick-marked in the task text (backticks are
    // step 1 of identifierMentionShape, itself unreachable without this).
    const bool hasMark = std::any_of( name.begin(), name.end(), []( const unsigned char c )
    {
        return std::isupper( c ) || c == '_' || c == ':' || c == '.' || c == '$';
    } );
    if( hasMark )
    {
        // A marked name that fails the shape test is never re-tried against the (all-lowercase) weak
        // path below: findInSymbolSlot searches lowerTask, and a name that still carries a capital can
        // never byte-match there, so falling through would only cost a wasted scan for an identical "no
        // match" answer. This early return states that outcome explicitly instead of arriving at it by
        // accident.
        const std::size_t pos = boundedFind( task, name );
        if( pos == std::string_view::npos || !identifierMentionShape( task, pos, name ) )
        {
            return {};
        }
        return { true, true, pos };
    }
    if( !weakSymbolCandidate( name ) )
    {
        return {};
    }
    const std::size_t pos = findInSymbolSlot( lowerTask, name );
    if( pos == std::string_view::npos )
    {
        return {};
    }
    return { true, false, pos };
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
    // A4 follow-up (review round, found-items 2026-09-17): .hxx added alongside .h/.hpp/.hh now that the
    // crawl itself admits it (src/ingest_crawl.h's kLangTable) — a task description naming a .hxx FILE:LINE
    // seed used to be recognized nowhere even though the file it names now indexes fine.
    ".cpp", ".cc", ".cxx", ".h", ".hpp", ".hh", ".hxx", ".c", ".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs",
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

// Cue phrases that place the word right after them in a VARIABLE slot — trace the flow OF budget, the
// data flowing INTO total_bytes. A local variable never appears in ing.symbols (extraction indexes
// definitions, not locals), so this is the router's only channel for naming one: purely lexical, mirroring
// the symbol-slot design above (a cue is the whole discriminator, not the word itself).
inline constexpr std::string_view kVariableSlotCues[] = {
    "the value of", "value of", "flowing into", "flows into", "feeds into", "feed into", "flow of", "into",
};

// Short function words the extractor hops over rather than accepting as the name itself — `flow of the
// budget` names budget, not the; `under our tools folder` names tools, not our. ONE table for every slot
// reader: the two that existed differed only by which three words each author happened to think of, which
// is the shape a duplicate takes when it is written twice instead of shared.
inline constexpr std::string_view kSlotFillers[] = {
    "the", "a", "an", "this", "that", "it", "its", "all", "our", "my", "data", "value", "code",
};

// THE slot walk, shared by every reader of "the thing named right after one of these cues".
//
// EARLIEST MATCH, across all cues: the cue occurrences are visited in POSITION order, not in the order the
// cue table happens to list them, so `what changed lately across src, but only in test` reads `across src`
// — the first slot in the sentence — rather than whichever cue sits earlier in an array. (The variable
// reader had this rule and the directory reader did not; they are one walk now, so they cannot disagree
// again.) At each occurrence the raw token is handed to `normalize` — a variable is an identifier run, a
// directory keeps its slashes and drops a trailing one — and then to `accept`. A slot the predicate turns
// down is not the end of the search: the walk moves to the next cue occurrence, because a sentence may
// name something that is not a directory before it names one that is.
template< std::size_t CueCount, typename Normalize, typename Accept >
inline std::string slotCandidate( std::string_view task, std::string_view lowerTask,
                                  const std::string_view ( &cues )[ CueCount ],
                                  Normalize normalize, Accept accept )
{
    constexpr std::string_view kSlotBreaks = " \t\n\r\"\'`(),;";
    std::vector<std::size_t> starts;            // where each cue occurrence's slot begins, position order
    for( std::size_t c = 0; c < CueCount; ++c )
    {
        for( std::size_t from = 0; ; )
        {
            const std::size_t p = boundedFind( lowerTask, cues[c], from );
            if( p == std::string_view::npos )
            {
                break;
            }
            starts.push_back( p + cues[c].size() );
            from = p + 1;
        }
    }
    std::sort( starts.begin(), starts.end() );
    for( const std::size_t slot : starts )
    {
        std::size_t begin = slot;
        for( int hop = 0; hop < 2; ++hop )
        {
            begin = task.find_first_not_of( kSlotBreaks, begin );
            if( begin == std::string_view::npos )
            {
                break;
            }
            std::size_t end = task.find_first_of( kSlotBreaks, begin );
            if( end == std::string_view::npos )
            {
                end = task.size();
            }
            const std::string_view token = normalize( task.substr( begin, end - begin ) );
            if( token.empty() )
            {
                break;
            }
            if( !isOneOf( lowerAscii( token ), std::begin( kSlotFillers ), std::size( kSlotFillers ) ) )
            {
                if( accept( token ) )
                {
                    return std::string( token );
                }
                break;   // this slot named something else — a LATER cue may still name what we want
            }
            begin = end;
        }
    }
    return {};
}

// a variable is the leading identifier run of the token (`budget,` is budget)
inline std::string_view identifierRunOf( std::string_view token ) noexcept
{
    std::size_t n = 0;
    while( n < token.size() && wordByte( token[n] ) ) { ++n; }
    return token.substr( 0, n );
}

inline std::string variableSlotCandidate( std::string_view task, std::string_view lowerTask )
{
    return slotCandidate( task, lowerTask, kVariableSlotCues,
                          []( const std::string_view t ) { return identifierRunOf( t ); },
                          []( const std::string_view ) { return true; } );
}

inline void addLexical( std::vector<RouteChoice>& choices, const char* id, const char* skill, const char* reason,
                        std::string command, int score, int floor, int priority )
{
    if( score >= floor )
    {
        choices.push_back( { id, skill, reason, std::move( command ), score, priority } );
    }
}

// THE token walk shared by every reader of "the tokens of this task, stripped of surrounding break
// characters and trailing sentence punctuation" — firstPathTokenWithSuffix (first token matching a
// suffix) and codeFileTokens (every code-extensioned token, position order) used to duplicate this walk
// byte-for-byte (measured: 263 duplicated tokens, --quality-delta round-1 L4 review). `visit` runs once
// per cleaned token in position order; returning true stops the walk early (the first-match reader uses
// this, the collect-all reader never does).
template< typename Visit >
inline void walkTaskTokens( std::string_view task, Visit visit )
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
        if( visit( token ) )
        {
            return;
        }
        i = end + 1;
    }
}

// A path the user actually WROTE, recognised by its extension. The router never invents one: --edit-plan
// and --plan-lint both refuse a file that is not there, and recommending a command the verb refuses is a
// prerequisite violation, not a suggestion. One extractor for every value-carrying path route, so the two
// cannot disagree about what counts as a written path.
inline std::string firstPathTokenWithSuffix( std::string_view task, std::initializer_list<std::string_view> suffixes )
{
    std::string found;
    walkTaskTokens( task, [&]( std::string_view token )
    {
        for( const std::string_view suffix : suffixes )
        {
            if( token.size() > suffix.size() && token.ends_with( suffix ) )
            {
                found = std::string( token );
                return true;
            }
        }
        return false;
    } );
    return found;
}

inline std::string firstJsonPathToken( std::string_view task )
{
    return firstPathTokenWithSuffix( task, { ".json", ".ndjson" } );
}

// ── file-grain readers shared by the coverage / impact / reach cards below ────────────────────────────
// Every source-extensioned token in the task, position order, literal duplicates collapsed — built on the
// SAME walkTaskTokens core firstPathTokenWithSuffix uses above (not a second copy of it): the two differ
// only in what a token is tested against (kCodeExtensions vs. an initializer_list of suffixes) and in
// whether the walk stops at the first hit or collects every one, both of which `visit`'s bool return and
// this lambda's own accumulator already express.
inline std::vector<std::string> codeFileTokens( std::string_view task )
{
    std::vector<std::string> out;
    walkTaskTokens( task, [&]( std::string_view token )
    {
        if( looksLikeFileToken( token ) )
        {
            const bool duplicate = std::any_of( out.begin(), out.end(), [&]( const std::string& s ) { return s == token; } );
            if( !duplicate )
            {
                out.push_back( std::string( token ) );
            }
        }
        return false;   // never stop early — this reader collects every match, not just the first
    } );
    return out;
}

// True when `file` is a path this build actually indexed, spelled root-relative the way the map spells
// p= (sarif's one root-relative rule — the same fact directoryInCorpus checks for a directory, one path
// component instead of a prefix). Structural, never inferred: --affected and --situ both read facts about
// a file this build indexed, and a file the task merely NAMES may not be one — recommending it anyway
// would be the same prerequisite violation --edit-plan/--plan-lint already refuse to commit.
inline bool fileInCorpus( std::string_view file, const std::string& root, const IngestResult& ing )
{
    if( file.empty() )
    {
        return false;
    }
    const std::string prefix = rw::sarif::rootPrefixOf( root );
    for( const std::string& f : ing.files )
    {
        if( rw::sarif::rootRelativeUri( f, prefix ) == file )
        {
            return true;
        }
    }
    return false;
}

// The FIRST code-extensioned token the task names that is also indexed — the one-file reader the
// coverage and impact cards share. A task can name a file this build never saw (a sibling repo, a
// rocksdb path pasted into a ripwire task); codeFileTokens finds the TEXT, fileInCorpus is what turns
// that into a file the recommended command can actually run against.
inline std::string firstIndexedCodeFile( std::string_view task, const std::string& root, const IngestResult& ing )
{
    for( const std::string& token : codeFileTokens( task ) )
    {
        if( fileInCorpus( token, root, ing ) )
        {
            return token;
        }
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
                                commandWithValue( root, "--grep=", quoted ) + " --handles --legend=compact", 100, 88 };
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
                            ripRoot + "--doctor --agent=codex --legend=compact", 100, 86 };
    }
    if( ( has( lower, "shell gate" ) || has( lower, "test gate" ) || has( lower, "test-gate" ) )
     && ( has( lower, "evidence" ) || has( lower, "why" ) || has( lower, "which" ) || has( lower, "picked" ) || has( lower, "chose" ) ) )
    {
        return RouteChoice{ "gate-evidence", "ripwire-change-check", "shell-gate selection asked for by its evidence",
                            ripRoot + "--test-gate --legend=compact", 100, 85 };
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
                            commandWithValue( root, "--slice=", "@" + fileLine ) + " --legend=compact", 100, 84 };
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
                            commandWithValue( root, "--uses=", symbols[0] ) + " --legend=compact", 100, 81 };
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
                                commandWithValue( root, "--slice=", symbols[0] + ":" + variable ) + " --slice-flow=back --legend=compact", 100, 83 };
        }
        return RouteChoice{ "data-flow", "ripwire-navigate",
                            "one exact indexed symbol plus data-flow wording (no variable named — lists its locals)",
                            commandWithValue( root, "--slice=", symbols[0] ) + " --legend=compact", 100, 83 };
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
                            ripRoot + "--handoff --legend=compact", 100, 79 };
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
                                commandWithValue( root, "--plan-lint=", planDoc ) + " --legend=compact", 100, 78 };
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
                            ripRoot + "--from-trace=- --legend=compact", 100, 77 };
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
                            ripRoot + "--scan-skills --legend=compact", 100, 76 }
             : RouteChoice{ "scan-skill", "ripwire-security-scan", "pre-install vetting wording plus a named file",
                            commandWithValue( root, "--scan-skill=", skillFile ) + " --legend=compact", 100, 76 };
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
                            ripRoot + "--deps --legend=compact", 100, 74 };
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
                            ripRoot + "--quality-delta --legend=compact", 100, 73 };
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
                            commandWithValue( root, "--around=", symbols[0] ) + " --legend=compact", 100, 72 };
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
                            commandWithValue( root, "--graph-query=", expr ) + " --legend=compact", 100, 71 };
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
                            ripRoot + "--hotspots --legend=compact", 100, 70 };
    }
    return std::nullopt;
}

// ── the recency window: which files the repository itself has been MOVING ─────────────────────────────
// The question a reader asks as `what moved here lately`, `who has been in this area`, `newest commits`.
// Until 2026-09-13 no route reached it at all: the verb that answers it (--rank-by=churn-decay, plus the
// directory scope below) had no entry in this file, so every phrasing abstained with score 0.
//
// One correction to the order that asked for this route, recorded where the next reader will look. The
// plan said the time word was a STOP WORD and that this was why the question could not route. Both halves
// of that need separating: kWeakSymbolStopWords governs SYMBOL RESOLUTION only — it is why --expand can
// never be handed one of those words out of prose — and it has never had any bearing on which INTENT a
// task reads as. Those words stay on that list (they must never name a definition) and become evidence
// HERE, which is exactly what its own comment already says they are: evidence about what the caller
// WANTS. Nothing was taken off the list.
//
// Conjunctive, like every catalog route: a TIME word AND a MOTION word. Either alone is ordinary English
// — a newest release, a modified header — and only the pair makes the question about history. Two guards
// keep the pair honest:
//   • an EXPLANATORY question is never this route, however many of both words it holds: a question about
//     how some cache with a time word in its NAME behaves is a question about that cache.
//   • the WORKING TREE is a different question — --situ answers what YOU have changed and not committed,
//     and its own route (review-diff, dirty worktrees only) keeps the wording this vocabulary avoids.
// Every phrase below is at most TWO words, deliberately: the fixture screen that keeps this corpus from
// quoting its own cards flags shared word-TRIGRAMS, and a card that never spells three consecutive words
// cannot contaminate a prompt no matter how it is phrased. The prose here obeys the same rule — an
// EXAMPLE is spelled in backticks, never in the double quotes that screen reads as a card.
inline constexpr std::string_view kDirScopeFlag = "--in=";

// Cue words that put a DIRECTORY in the slot after them. Same discriminator the symbol slot uses: a bare
// noun that happens to match a directory name is not a scope, and the same noun after `in` is.
inline constexpr std::string_view kDirectorySlotCues[] = { "in", "inside", "under", "within", "across" };

// True when `dir` is a directory of the CORPUS — some indexed file sits under it, with the path spelled
// the way the map spells p= (sarif's one root-relative rule, which is also what the scope flag matches
// against). Structural, never inferred: the flag refuses a directory that is not under the root, so a
// router that guessed one would be recommending a refusal.
inline bool directoryInCorpus( std::string_view dir, const std::string& root, const IngestResult& ing )
{
    if( dir.empty() )
    {
        return false;
    }
    const std::string prefix = rw::sarif::rootPrefixOf( root );
    for( const std::string& file : ing.files )
    {
        const std::string_view rel = rw::sarif::rootRelativeUri( file, prefix );
        if( rel.size() > dir.size() && rel.substr( 0, dir.size() ) == dir && rel[ dir.size() ] == '/' )
        {
            return true;
        }
    }
    return false;
}

// One token of the task, with the spellings people type stripped off it: a trailing '/' or sentence
// punctuation, and a leading "./" that says the same path twice.
inline std::string_view cleanedDirectoryToken( std::string_view token ) noexcept
{
    while( !token.empty() && ( token.back() == '.' || token.back() == '?' || token.back() == '!'
                            || token.back() == ':' || token.back() == '/' ) )
    {
        token.remove_suffix( 1 );
    }
    if( token.starts_with( "./" ) )
    {
        token.remove_prefix( 2 );
    }
    return token;
}

// Calendar words that turn a bare `since` into a WINDOW. git's own vocabulary (--since=REV|DATE): a day, a
// month or a date after it is a time bound, while `since the rewrite` is not one this router can hand over.
inline constexpr std::string_view kCalendarWords[] = {
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "yesterday",
    "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
    "november", "december", "midnight", "noon",
};

// The EXPLANATORY reading, which is never the history route however many of its three conjuncts hold.
// WORD-BOUNDED, and the boundary is the whole point: a multi-word cue is NOT self-delimiting, which the
// first review round's comment on CueMatch assumed it was. The space INSIDE a phrase delimits nothing at
// its two ENDS — the first word can finish another word and the last can begin one. `show documentation`
// contains `how do` and `show issues` contains `how is`, so both of those questions ABOUT this repository's
// history lost the route that answers them (2026-09-13, second review round).
inline constexpr std::string_view kExplanatoryCues[] = {
    "how does", "how do", "how is", "how are", "what does", "implementation of",
};

// `since Monday`, `since 2026-09-01` — structural, because a date has no paraphrase (the same reasoning
// firstFileLineToken is built on). Word-bounded, so `sincerely` is not a window.
inline bool saysSinceWhen( std::string_view lowerTask ) noexcept
{
    for( std::size_t from = 0; ; )
    {
        const std::size_t p = boundedFind( lowerTask, "since", from );
        if( p == std::string_view::npos )
        {
            return false;
        }
        from = p + 1;
        std::size_t begin = p + 5;
        while( begin < lowerTask.size() && lowerTask[begin] == ' ' ) { ++begin; }
        std::size_t end = begin;
        while( end < lowerTask.size() && wordByte( lowerTask[end] ) ) { ++end; }
        const std::string_view word = lowerTask.substr( begin, end - begin );
        if( word.empty() )
        {
            continue;
        }
        if( std::isdigit( static_cast<unsigned char>( word.front() ) ) != 0
         || isOneOf( word, std::begin( kCalendarWords ), std::size( kCalendarWords ) ) )
        {
            return true;
        }
    }
}

inline std::optional<RouteChoice> recencyTaskChoice( std::string_view task, std::string_view lower, const std::string& root,
                                                     const IngestResult& ing, bool git, const RouterCaps& caps )
{
    if( !git )
    {
        return std::nullopt;   // the window IS the commit history; without one there is nothing to rank
    }
    // SINGLE words are word-bounded, multi-word phrases are not: a phrase carries its own boundaries, and a
    // bare word matched as a substring is a different word. `here` inside where/there/adhere, `source`
    // inside outsource, `file` inside profile, `code` inside codec, `moving` inside removing, `changed`
    // inside unchanged — each of those was a live false positive of the substring spelling (the
    // counter-example in the paragraph below routed with confidence="high" until this was fixed).
    const int timeScore = wordScore( lower, { { "recently", 8 }, { "lately", 8 }, { "yesterday", 8 },
                                              { "newest", 5 }, { "latest", 5 }, { "recent", 5 } } )
                        + phraseScore( lower, { { "last week", 8 }, { "past week", 8 }, { "last month", 8 },
                                                { "past month", 8 }, { "last night", 8 }, { "last few", 8 },
                                                { "this week", 7 }, { "these days", 6 } } )
                        + ( saysSinceWhen( lower ) ? 8 : 0 );
    const int motionScore = wordScore( lower, { { "churn", 9 }, { "changed", 7 }, { "changes", 7 },
                                                { "commits", 7 }, { "touched", 7 }, { "touching", 7 },
                                                { "modified", 7 }, { "rewritten", 7 }, { "rewrote", 7 },
                                                { "edited", 6 }, { "editing", 6 }, { "edits", 6 },
                                                { "commit", 6 }, { "landed", 6 }, { "merged", 6 },
                                                { "moving", 6 }, { "activity", 6 }, { "updated", 6 },
                                                { "updates", 6 } } )
                          + phraseScore( lower, { { "git history", 8 }, { "git log", 7 } } );
    // `what is new in DIR` is this question with NEITHER word spelled: `new` carries the time sense and the
    // change sense at once, and giving it a weight in both tables would have every `new feature` sentence
    // read as history. Recognised as the phrase it is, and only in the question forms that mean it.
    const bool newInPhrase = has( lower, "what is new in" ) || has( lower, "what's new in" )
                          || has( lower, "whats new in" ) || has( lower, "anything new in" );
    const bool explanatory = std::any_of( std::begin( kExplanatoryCues ), std::end( kExplanatoryCues ),
                                          [lower]( const std::string_view cue ) { return boundedFind( lower, cue ) != std::string_view::npos; } );
    if( ( ( timeScore < 5 || motionScore < 6 ) && !newInPhrase ) || explanatory )
    {
        return std::nullopt;
    }
    // …and the pair is still not enough on its own, because the world outside the checkout also has a
    // history: `our supplier changed their terms recently, where is that noted?` carries a time word and a
    // motion word and is not a question about this repository at all. The third conjunct is what the
    // question is ABOUT — a word naming the corpus, or a directory of it the task actually named. Nothing
    // here is a completeness claim: a history question that names neither abstains, which is the cheap side
    // to be wrong on (the caller asks again with the word in it; a wrong recommendation costs a call).
    // the EARLIEST directory of this corpus the task names in a locating slot, or "" when it names none
    const std::string dir = slotCandidate( task, lower, kDirectorySlotCues,
                                           []( const std::string_view t ) { return cleanedDirectoryToken( t ); },
                                           [&]( const std::string_view t ) { return directoryInCorpus( t, root, ing ); } );
    const int corpusScore = wordScore( lower, { { "file", 1 }, { "files", 1 }, { "code", 1 }, { "codebase", 1 },
                                                { "repo", 1 }, { "repository", 1 }, { "tree", 1 }, { "branch", 1 },
                                                { "commit", 1 }, { "commits", 1 }, { "module", 1 }, { "directory", 1 },
                                                { "folder", 1 }, { "checkout", 1 }, { "worktree", 1 }, { "source", 1 },
                                                { "function", 1 }, { "header", 1 }, { "symbol", 1 }, { "here", 1 } } );
    if( corpusScore == 0 && dir.empty() )
    {
        return std::nullopt;
    }
    std::string command = "ripwire " + shSingleQuote( root ) + " --rank-by=churn-decay";
    if( dir.empty() )
    {
        return RouteChoice{ "recency-window", "ripwire-fresh-eyes",
                            "history wording: a time word plus a motion word, about commits rather than the working tree",
                            std::move( command ), 100, 69 };
    }
    if( caps.dirScope )
    {
        command += " " + std::string( kDirScopeFlag ) + shSingleQuote( dir );
        return RouteChoice{ "recency-window", "ripwire-fresh-eyes",
                            "history wording plus a directory the corpus holds, scoped to it",
                            std::move( command ), 100, 69 };
    }
    // The task NAMED a directory and this build has no flag to scope with. Dropping it silently would hand
    // back a whole-repository answer to a question about one directory with nothing saying so; the reason
    // is where that is said, since it is the only prose a caller of this verb reads.
    return RouteChoice{ "recency-window", "ripwire-fresh-eyes",
                        "history wording plus a directory this build cannot scope to; the whole repository is shown instead",
                        std::move( command ), 100, 69 };
}

// ── first-verb cards for the four question shapes the router used to abstain on (round-1 L4) ────────────
// The mining finding (--help-task over the round's 60-question corpus): the router recommended nothing
// on ALL 48 instances of `which tests cover F`, `if I change F what else has to change`, `how does A
// reach B` and `where is X implemented`, and correctly named only S5 (the recency window above). Each
// card below is FILE-STRUCTURAL wherever the target verb needs a file (test-coverage, change-impact) —
// the same fileInCorpus discipline directoryInCorpus already uses for --in=DIR — so a task that merely
// NAMES a file this build never indexed abstains rather than recommending a command that verb refuses
// (measured: --affected on an unindexed path exits 1). reach-flow is structural on FILE COUNT (two
// distinct indexed files) rather than on wording, for the same reason: the file-grain --path surface
// does not exist (round 2), so --for=task is the only verb, and the two-file count is what keeps an
// ordinary `how does X work` sentence (0 or 1 file) out of this gate regardless of score.

// The read-only view every round-1 L4 card (and directTaskChoice itself) needs: the task in both
// spellings, the root, the resolved symbols, and the ingest facts a file-structural card checks a name
// against. One struct instead of a five-parameter argument list at every call site — added in review
// (--quality-delta flagged directTaskChoice's own param count growing 4->5 as a gating api-surface
// regression; bundling collapses it back to one). Reference members only — this is a non-owning view
// built fresh at each classifyRoutes call, never stored.
struct RouteContext
{
    std::string_view                task;
    std::string_view                lower;
    const std::string&              root;
    const std::vector<std::string>& symbols;
    const IngestResult&             ing;
};

// `which tests cover F` / `test(s) for F` / `test files exercise F` — one indexed file plus
// coverage/exercise wording routes to --affected=F, the transitive test list for that file.
inline std::optional<RouteChoice> testCoverageTaskChoice( const RouteContext& ctx )
{
    const int coverScore = phraseScore( ctx.lower, { { "which tests cover", 9 }, { "tests cover", 7 },
                                                     { "test for", 6 }, { "tests for", 6 }, { "tests exist for", 7 },
                                                     { "test(s) for", 7 }, { "test files exercise", 8 }, { "files exercise", 5 },
                                                     { "unit tests should i run", 8 }, { "covered by any test", 8 },
                                                     { "test coverage", 6 } } );
    if( coverScore < 6 )
    {
        return std::nullopt;
    }
    const std::string file = firstIndexedCodeFile( ctx.task, ctx.root, ctx.ing );
    if( file.empty() )
    {
        return std::nullopt;
    }
    return RouteChoice{ "test-coverage", "ripwire-change-check", "test-coverage wording plus one indexed file",
                        commandWithValue( ctx.root, "--affected=", file ) + " --legend=compact", 100, 64 };
}

// `if I change F, what else has to change (with it)` / `what breaks if I edit F` / `blast radius of F` /
// `what depends on F` — one indexed file plus change-impact wording routes to --situ=F. --situ is a PROSE
// verb (legendCompactAppliesTo refuses it the compact flag, measured: exit 1), so unlike every card
// above this one the command is never suffixed with --legend=compact.
inline std::optional<RouteChoice> changeImpactTaskChoice( const RouteContext& ctx )
{
    const int impactScore = phraseScore( ctx.lower, { { "what else has to change", 9 }, { "what breaks if", 9 },
                                                      { "blast radius", 7 }, { "what depends on", 7 },
                                                      { "need to update alongside", 8 }, { "update alongside", 6 },
                                                      { "if i change", 4 }, { "if i edit", 4 }, { "if i modify", 4 } } );
    if( impactScore < 7 )
    {
        return std::nullopt;
    }
    const std::string file = firstIndexedCodeFile( ctx.task, ctx.root, ctx.ing );
    if( file.empty() )
    {
        return std::nullopt;
    }
    return RouteChoice{ "change-impact", "ripwire-change-check", "change-impact wording plus one indexed file",
                        commandWithValue( ctx.root, "--situ=", file ), 100, 63 };
}

// `how does A reach B` / `call chain from A into B` / `how is A used by B` — two files the task itself
// names, both indexed, plus reach/call-chain wording. --for=task is the only shipped surface for a
// file-grain path question (no file-grain --path exists; round 2 backlog), so this widens the same
// --for bundle locate-task and locate-implementation already use rather than inventing a new verb.
inline std::optional<RouteChoice> reachTaskChoice( const RouteContext& ctx )
{
    const int reachScore = phraseScore( ctx.lower, { { "call chain from", 9 }, { "call chain", 6 }, { "reaches", 5 },
                                                     { "reach", 5 }, { "used by", 5 }, { "how does", 2 }, { "how is", 2 } } );
    if( reachScore < 7 )
    {
        return std::nullopt;
    }
    std::vector<std::string> files;
    for( const std::string& token : codeFileTokens( ctx.task ) )
    {
        if( fileInCorpus( token, ctx.root, ctx.ing ) )
        {
            files.push_back( token );
            if( files.size() == 2 )
            {
                break;
            }
        }
    }
    if( files.size() != 2 )
    {
        return std::nullopt;
    }
    // codeFileTokens collapses literal duplicates before this loop ever sees them, so two collected
    // entries are always two different paths — never the same file named twice.
    ASSUME( files[0] != files[1], "codeFileTokens de-duplicates; two collected tokens are distinct paths" );
    return RouteChoice{ "reach-flow", "ripwire-navigate",
                        "two indexed file paths plus reach/call-chain wording (no file-grain --path surface)",
                        commandWithValue( ctx.root, "--for=", ctx.task ), 100, 61 };
}

// `where is X implemented` / `which file implements X` — X is often a commit subject or a feature
// description this build never indexed verbatim (unlike the file-keyed cards above), so --for=task — a
// ranked bundle over the whole question — is the only surface this can name. Kept separate from the
// weighted-tier locate-task (`find the code`, `bug`, `crash`, `symptom`): that card answers what is
// RESPONSIBLE for a symptom, this one answers where something LIVES, and the two floors would otherwise
// have to serve two different confidence levels under one number. Narrow on purpose — `where is` ALONE is
// ordinary English (where is the config, where is the binary) and only the co-occurrence with
// `implemented` makes it this question. No bare `implementation of` cue here (kExplanatoryCues already
// carries that bigram for the recency route, and the screened corpus quotes `the implementation of`
// verbatim in unrelated review prose — a third word attached to it would be a new card trigram this round
// does not need: `which file implements` and the where-is/implemented pair already cover every registered
// template and 2 of 3 S1 paraphrases without it). Takes task/lower/root directly rather than a
// RouteContext: it is the one round-1 L4 card that reads neither ing nor symbols, and directTaskChoice
// calls it standalone (after the whole catalog tier), not through roundOneL4Choice below.
inline std::optional<RouteChoice> locateImplementationTaskChoice( std::string_view task, std::string_view lower, const std::string& root )
{
    const bool whereIsImplemented = boundedFind( lower, "where is" ) != std::string_view::npos
                                  && boundedFind( lower, "implemented" ) != std::string_view::npos;
    const int implementsScore = phraseScore( lower, { { "which file implements", 9 }, { "which files implement", 9 },
                                                      { "find the file that implements", 9 } } );
    if( !whereIsImplemented && implementsScore < 8 )
    {
        return std::nullopt;
    }
    return RouteChoice{ "locate-implementation", "ripwire-orient",
                        "an implementation-location question (where is X implemented / which file implements X)",
                        commandWithValue( root, "--for=", task ), 100, 60 };
}

// The three FILE-keyed round-1 L4 cards, bundled into one dispatcher the same way flowTaskChoice and
// catalogTaskChoice already bundle their own tiers — so directTaskChoice gains one call here, not three,
// as this round's card count grows (added in review: the un-bundled form was what pushed
// directTaskChoice's own body past its verbosity bar). A declarative table walked in a loop, not three
// sequential if-returns (CONTRIBUTING.md SS3 "declarative constexpr tables over scattered switch/if") —
// also added in review, after --quality-delta flagged the sequential-if form as a structural clone of
// screenRegexPattern's unrelated three-step chain (regexguard.h) at 71 duplicated tokens; two functions
// implementing the same idiom with different names still clone-match on shape. locate-implementation is
// NOT in this table: it runs after the whole catalog tier (see its own comment), so it stays a separate
// call in directTaskChoice.
inline std::optional<RouteChoice> roundOneL4Choice( const RouteContext& ctx )
{
    using Card = std::optional<RouteChoice> ( * )( const RouteContext& );
    static constexpr Card kCards[] = { testCoverageTaskChoice, changeImpactTaskChoice, reachTaskChoice };
    for( const Card card : kCards )
    {
        if( std::optional<RouteChoice> choice = card( ctx ) )
        {
            return choice;
        }
    }
    return std::nullopt;
}

// The intents whose command IS a --for bundle over the task text, and which a file-grain page therefore
// WIDENS. Keyed by INTENT and never by searching the command for the flag: a task that quotes the flag
// itself (`plan the new feature: replace the for= flag scoring`) puts that string inside another verb's
// quoted argument, and a continuation built from it pastes a page width onto a verb that refuses it
// (measured: exit 1). The page's own spelling and its byte ceiling belong to forpage.h; this list is only
// the answer to "does this recommendation have one".
inline constexpr std::string_view kForShapedIntents[] = { "compact-legend", "locate-task", "opt-remark",
                                                           "reach-flow", "locate-implementation" };

inline std::optional<RouteChoice> directTaskChoice( const RouteContext& ctx )
{
    // The instrumented surfaces are asked for BY NAME, so they outrank the generic literal/post-edit
    // shapes: "find every occurrence of 'X' and give me safe-edit handles" is a handles request that
    // happens to contain a grep, not the other way round.
    if( std::optional<RouteChoice> named = instrumentedTaskChoice( ctx.task, ctx.lower, ctx.root ) )
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
    const int exactScore = phraseScore( ctx.lower, { { "exact occurrence", 9 }, { "exact literal", 9 },
                                                     { "every occurrence", 8 }, { "occurrences of", 8 }, { "verbatim", 8 },
                                                     { "find every", 7 }, { "every place", 7 }, { "search for", 7 },
                                                     { "look for", 6 }, { "grep", 6 }, { "the string", 5 },
                                                     { "where does", 5 }, { "exactly", 4 }, { "literal", 4 },
                                                     { "show up", 4 }, { "across the repo", 4 }, { "in the codebase", 3 } } );
    const std::string quoted = exactScore >= 6 ? firstQuotedLiteral( ctx.task ) : std::string();
    if( !quoted.empty() )
    {
        return RouteChoice{ "exact-grep", "ripwire-navigate", "quoted literal plus exact-search wording",
                            commandWithValue( ctx.root, "--grep=", quoted ) + " --grep-context=2 --limit=40 --legend=compact", 100, 85 };
    }
    const int postEditScore = phraseScore( ctx.lower, { { "just edited", 9 }, { "just finished editing", 9 },
                                                        { "my edit to", 9 }, { "changed its signature", 9 },
                                                        { "changed its contract", 9 }, { "compatible with callers", 8 },
                                                        { "break its callers", 8 }, { "break any caller", 8 },
                                                        { "did i change", 8 }, { "i edited", 8 }, { "i modified", 8 },
                                                        { "i just changed", 8 }, { "after my patch", 7 },
                                                        { "after my change", 7 }, { "since my edit", 7 },
                                                        { "contract change", 7 }, { "still compatible", 7 },
                                                        { "break anyone", 7 } } );
    if( ctx.symbols.size() == 1 && postEditScore >= 7 )
    {
        return RouteChoice{ "edit-contract", "ripwire-change-check",
                            "one exact indexed symbol plus post-edit contract wording",
                            commandWithValue( ctx.root, "--edit-check=", ctx.symbols[0] ) + " --legend=compact", 100, 82 };
    }
    // at-line / who-writes / data-flow: structural or phrase-scored the same way the categories above
    // are, just extracted into their own function (see flowTaskChoice's own comment) to keep this ladder
    // from growing without bound as more "where did this value come from" surfaces are added.
    if( std::optional<RouteChoice> flow = flowTaskChoice( ctx.task, ctx.lower, ctx.root, ctx.symbols ) )
    {
        return flow;
    }
    // round-1 L4: test-coverage, change-impact, reach-flow — bundled in roundOneL4Choice (see its own
    // comment) so this ladder gains one call, not three, sitting ahead of the phrase-only catalog tier the
    // same way flowTaskChoice's structural cards do.
    if( std::optional<RouteChoice> l4 = roundOneL4Choice( ctx ) )
    {
        return l4;
    }
    // catalog tier LAST: the verbs and skills the router could not name at all before 2026-09-10. Every
    // route above this line is older and more specific and keeps its rows unchanged (measured: all 189
    // corpus rows byte-identical on status/intent across this addition).
    if( std::optional<RouteChoice> catalog = catalogTaskChoice( ctx.task, ctx.lower, ctx.root, ctx.symbols ) )
    {
        return catalog;
    }
    // locate-implementation is the BROADEST of round-1 L4's four cards (`where is X implemented` alone,
    // no file, no symbol), so it runs last of all — every older and more specific reading above it,
    // including the whole catalog tier, keeps first refusal.
    if( std::optional<RouteChoice> impl = locateImplementationTaskChoice( ctx.task, ctx.lower, ctx.root ) )
    {
        return impl;
    }
    return std::nullopt;
}

// ONE PLACE APPLIES THE COMPACT-LEGEND POSTURE (PR #215 review item 5). A1-2 put --legend=compact on 26 route
// commands by editing 26 strings, which is 26 chances to miss one and no rule for the 27th. classifyRoutes below
// is the whole router; classify() is the one exit, and it applies the posture to every choice it returns — which
// is what makes the 27th free: #218's recency intent (merged here) spells its commands without the flag and
// gets it anyway, without knowing the rule exists.
//
// WHAT DECIDES: rw::legendCompactAppliesTo (compactlegend.h), the SAME list of non-XML surfaces cli.h REFUSES the flag
// on, asked of a command string instead of a parsed Config. So the router cannot generate a command its own
// binary rejects — which it did: `--zoom --legend=compact --mermaid` shipped in a skill, and a hand-listed gate
// enforced it. --for is exempt by policy, not by refusal, and legendCompactAppliesTo says so in one place.
// Idempotent: a command that already carries --legend= is left alone, so the hand-applied ones are untouched and
// this is a no-op on them. Gate: test/taskroutecheck.sh runs every generated command against the binary.
//
// caps rides through untouched (#218): classify() decides nothing about routing, it only applies the posture to
// what classifyRoutes returned, so every routing input is forwarded verbatim.
inline TaskRouteResult classifyRoutes( std::string_view task, const std::string& root, const IngestResult& ing, bool git, bool dirty,
                                       const RouterCaps& caps );

inline TaskRouteResult classify( std::string_view task, const std::string& root, const IngestResult& ing, bool git, bool dirty,
                                 const RouterCaps& caps = {} )
{
    TaskRouteResult result = classifyRoutes( task, root, ing, git, dirty, caps );
    for( RouteChoice& choice : result.choices )
    {
        if( rw::legendCompactAppliesTo( choice.command ) )
        {
            choice.command += " --legend=compact";
        }
    }
    return result;
}

inline TaskRouteResult classifyRoutes( std::string_view task, const std::string& root, const IngestResult& ing, bool git, bool dirty,
                                       const RouterCaps& caps )
{
    TaskRouteResult result;
    result.facts.git = git;
    result.facts.dirty = dirty;
    // A harness/system event outranks every other read — never worth resolving symbols or trace shape out
    // of a background-task report at all (see looksLikeSystemEvent). Facts stay at their defaults
    // (trace=0, resolved_symbols=0): nothing below was evaluated, which is itself honest disclosure.
    if( looksLikeSystemEvent( task ) )
    {
        return result;
    }
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
                                    commandWithValue( root, "--verify=", task ) + " --legend=compact", 100, 100 } );
        return result;
    }
    if( result.facts.trace )
    {
        result.status = RouteStatus::Recommend;
        result.score  = result.margin = 100;
        result.choices.push_back( { "trace-debug", "ripwire-find-bug", "stack-trace shape; pass the trace on stdin",
                                    "ripwire " + shSingleQuote( root ) + " --from-trace=- --legend=compact", 100, 90 } );
        return result;
    }
    if( std::optional<RouteChoice> direct = directTaskChoice( RouteContext{ task, lower, root, result.facts.resolvedSymbols, ing } ) )
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
                                    commandWithValue( root, "--connect=", commaSymbols( result.facts.resolvedSymbols ) ) + " --legend=compact", 100, 80 } );
        return result;
    }
    if( result.facts.resolvedSymbols.size() == 1 && ( has( lower, "understand" ) || has( lower, "implementation" ) || has( lower, "how does" ) ) )
    {
        result.status = RouteStatus::Recommend;
        result.score  = result.margin = 100;
        result.choices.push_back( { "understand-symbol", "ripwire-navigate", "one exact indexed symbol plus understand wording",
                                    commandWithValue( root, "--expand=", result.facts.resolvedSymbols[0] ) + " --legend=compact", 100, 70 } );
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
                commandWithValue( root, "--pack-task=", task ) + " --legend=compact", planScore, 8, 50 );

    const int reuseScore = phraseScore( lower, { { "about to write", 8 }, { "one helper", 5 }, { "one function", 5 },
                                                 { "one class", 5 }, { "helper", 3 }, { "function", 2 }, { "class", 2 } } );
    addLexical( candidates, "reuse-one-symbol", "ripwire-reuse-first", "about-to-write one-symbol wording",
                commandWithValue( root, "--exemplar=", task ) + " --legend=compact", reuseScore, 10, 40 );

    const int writeTestsScore = phraseScore( lower, { { "missing coverage", 8 }, { "no tests", 6 }, { "untested", 5 },
                                                      { "regression gate", 4 }, { "add", 3 }, { "write", 3 },
                                                      { "find", 2 }, { "cover", 2 } } );
    addLexical( candidates, "write-tests", "ripwire-write-tests", "test-gap wording plus a test-writing action",
                "ripwire " + shSingleQuote( root ) + " --seams --legend=compact", writeTestsScore, 8, 35 );

    const int locateScore = phraseScore( lower, { { "find the code", 8 }, { "locate", 7 }, { "responsible", 4 },
                                                  { "bug", 3 }, { "wrong output", 4 }, { "crash", 4 }, { "symptom", 3 } } );
    addLexical( candidates, "locate-task", "ripwire-find-bug", "code-location or symptom wording",
                commandWithValue( root, "--for=", task ), locateScore, 8, 30 );

    // The recency window runs LAST, and only when the weighted tier named nothing at all. That placement is
    // the whole argument that it costs the older routes nothing — and it is also how it reads `dirty`,
    // which it must: on a dirty worktree `is my diff safe to merge, i changed these files recently` carries
    // a time word, a motion word and a corpus word, and it is still the review-diff question. review-diff
    // is a candidate there (dirty-only, by its own wording), so it wins before this route is reached, and
    // on a CLEAN tree the same sentence has no diff to review and the history reading is the honest one.
    if( candidates.empty() )
    {
        if( std::optional<RouteChoice> recency = recencyTaskChoice( task, lower, root, ing, git, caps ) )
        {
            result.status = RouteStatus::Recommend;
            result.score  = result.margin = 100;
            result.choices.push_back( std::move( *recency ) );
        }
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
