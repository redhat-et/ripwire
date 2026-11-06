#pragma once
// subjectanchor.h — SUBJECT-ANCHOR: a symbol named exactly in a descriptive --for subject is the anchor; the ordinary words
// around it are not.
//
// WHY. lexical.h chooseForRanker treats every word that equals SOME symbol's name as a name. On a descriptive subject that turns
// plain words into anchors: "async_prepare_setup_platform new parameter" anchored new() and parameter() too, bodied three
// symbols and lost the one function's <callers>; "transformNodes new parameter" and "kube-proxy nftables syncProxyRules" were
// declined by the commonness of a word the task only used as a word. Index evidence cannot tell these apart (a one-definition
// parameter() passes every plausibility bound), so the rule reads WORD CLASS, with no word table: identifier syntax (camelCase,
// snake_case, a qualified spelling) is a name, and a plain word beside a proven name is a word.
//
// THE READING (subjectReading). It needs an EXACT symbol beside plain words: an identifier-syntax word that is a symbol of exactly
// that spelling, its qualifier placing it when it has one (scope, file stem or directory, the mention anchor's own test), in at most
// kSubjectMaxDefs definitions. A namesake flood proves nothing, so that route stays declined and says so. Graph forms (path from,
// callers of, call chain from), joins of named endpoints (+, ->, =>, =, |) and pasted traces or issue forms get no reading; their
// answers are byte-identical to before.
// WHAT A PLAIN WORD THAT REALLY IS A SYMBOL GETS. On a flip it is dropped like any other word, beside a proven name, and the route
// prints its count: "dropped: emit(102-defs) new(41-defs) argument". To ask about emit, the subject is `emit`, which routes as it always did.
//
// WHAT THE READING DOES. ONE change to the route, the flip, and only where it serves what it takes away:
//   * the flip: the subject spells ONE identifier, it places one exact symbol, and the whole route either anchored a plain word too
//     (name-exact) or was declined for one on a DESCRIPTIVE subject (no question lead, at most kSubjectMaxPlainWords plain content
//     words). The words are dropped and the route is the bare symbol's, but only on a surface that prints the body and the callers
//     (the CLI --for default bundle) and only where that answer has them: one function with a source definition, a real body that
//     fits the single-anchor allowance, a caller (flipServesBodyAndCallers). rankQuery carries the name; route= says dropped:.
//   * everything else, a refused flip included: the route is chooseForRanker's for the whole subject (CONFIDENCE-ANCHOR's note aside). A conceptual
//     route whose descriptive subject names a symbol gains <callers by="subject"> on top (verbs_for.h); nothing is taken. For that
//     block alone a sentence that asks what depends on the symbol (isDependentsCue) does not count its task frame as prose.

#include "filter.h"            // isTestSymbol, pathTierOf
#include "forcallerhop.h"      // forCallerHopTargets — the ONE-function test a flip needs (its callers are served)
#include "graph.h"
#include "infra/namesplit.h"   // hasIdentifierShape, isIdentChar
#include "langfacts.h"         // langFacts().notCode
#include "lexical.h"           // chooseForRanker, RouteChoice, parseGraphSubject, isRouteStopword, kMaxAnchorDefs
#include "mention.h"           // mention_detail::qualifierPlaces — the ONE "does this qualifier place this symbol" test
#include "model.h"
#include "queryshape.h"
#include "serialize.h"         // kForAnchorBodyBudgetBytes

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// More plain content words than this beside the names is prose with a name in it. Every descriptive tail seen in the corpora's
// subjects fits ("new parameter", "feature gate default", "gets a new argument"); "config setting and the startup banner" does not.
inline constexpr std::size_t kSubjectMaxPlainWords = 4;
// More definitions than this is a namesake flood. The route's plain-word bound (kMaxAnchorDefs, 3) is too tight for identifier syntax:
// one method per backend is 4-10 definitions (syncProxyRules 4, Machine_scan 10), and the floods start far above that (SCAN_INTERVAL 363).
inline constexpr std::size_t kSubjectMaxDefs = 12;

struct SubjectExactSymbol
{
    std::string         word;   // as the subject spells it, edges trimmed
    std::vector<NodeId> defs;   // the definitions it places, NodeId order; never empty, at most kSubjectMaxDefs
};

struct SubjectReading
{
    std::vector<SubjectExactSymbol> exact;      // subject word order
    std::string                     reduced;    // the subject with its plain words gone (exact + unproven identifier-syntax words)
    std::vector<std::string>        dropped;    // the plain content words, subject order
    std::size_t                     names       = 0;       // identifier-syntax words in the subject (the words `reduced` keeps)
    bool                            sourceDef   = false;   // one exact symbol has a source-class definition
    bool                            descriptive = false;   // no question lead, and few enough plain words: not prose
    bool                            framed      = false;   // descriptive, or asks what depends on it with few plain words beside the frame
};

// What a --for or MCP route uses: the route, and the query the ranker and the mention anchor read.
struct SubjectRoute
{
    RouteChoice         route;
    std::string         rankQuery;     // non-empty only when the words were dropped from the route
    std::vector<std::vector<NodeId>> callerCandidates;   // conceptual route: each exact symbol's definitions, for <callers by="subject">
    bool                anchorNoSource = false;   // CONFIDENCE-ANCHOR: name-exact, and no source-class definition backs the anchor
    RouteAnchorKeys anchorKeys; // FRAME-HIGH-CONFIDENCE: what counts as the anchor heading the ranked rows
};

namespace subject_detail
{
// the leaf and qualifier of a spelling: `a.b.C::d` is (d, C), `d` is (d, ""). Only identifier characters in each segment, or nothing.
struct Spelling
{
    std::string_view leaf;
    std::string_view qualifier;
    bool             valid = false;
};

inline Spelling parseSpelling( std::string_view w ) noexcept
{
    Spelling          s;
    const auto        identOnly = []( std::string_view t ) { return !t.empty() && std::ranges::all_of( t, namesplit::isIdentChar ); };
    const std::size_t colon = w.rfind( "::" );
    const std::size_t dot   = w.rfind( '.' );
    if( colon != std::string_view::npos && ( dot == std::string_view::npos || colon > dot ) )
    {
        s.leaf = w.substr( colon + 2 );
        w      = w.substr( 0, colon );
    }
    else if( dot != std::string_view::npos )
    {
        s.leaf = w.substr( dot + 1 );
        w      = w.substr( 0, dot );
    }
    else
    {
        s.leaf  = w;
        s.valid = identOnly( w );
        return s;
    }
    const std::size_t prevColon = w.rfind( "::" );
    const std::size_t prevDot   = w.rfind( '.' );
    const std::size_t cut       = prevColon != std::string_view::npos && ( prevDot == std::string_view::npos || prevColon > prevDot ) ? prevColon + 2
                                : prevDot != std::string_view::npos ? prevDot + 1 : 0;
    s.qualifier = w.substr( cut );
    s.valid     = identOnly( s.leaf ) && identOnly( s.qualifier );
    return s;
}

// identifier syntax: the shape the router already calls explicit (camelCase, snake_case), or a qualified spelling
inline bool hasNameSyntax( std::string_view w ) noexcept
{
    // `<file-scope>`, `<module>`: the angle-bracketed spelling of a synthetic owner (module-scope symbols) is a name, not a word
    if( w.size() > 2 && w.front() == '<' && w.back() == '>' )
    {
        return true;
    }
    return !w.empty() && w.front() != '-' && w.find( '/' ) == std::string_view::npos
        && ( namesplit::hasIdentifierShape( w ) || w.find( "::" ) != std::string_view::npos || w.find( '.' ) != std::string_view::npos );
}

// a question opens with one of these
inline bool isQuestionLead( std::string_view w )
{
    return detail::graphSubjectWordIs( w, { "which", "where", "how", "what", "why", "who", "when", "does", "do", "is", "are", "can", "should", "will" } );
}

// SUBJECT-CALLERS-NATURAL. A sentence can name ONE function and only frame a question about what depends on it: "I want to add a
// new parameter to f; what is affected?", "who calls f and would break if its signature changed?". Such a sentence asks exactly what
// "f new parameter" asks. Two closed word lists, no code names. A dependents cue asks who uses the function (change, add, affected,
// breaks, depends, calls, used, update, modify, invokes, references, rename, exercise), in its dependents sense only (asksDependents);
// without one a sentence is not asking for callers ("how does f reach g", "default x and y for buffers"), so it reads as before. The
// sentence names ONE function: with two, the block would guess which one the cue governs. Task frame words are the cues plus question leads, pronouns, helpers, conjunctions
// and prepositions ("I need to", "what would that", "into"); the plain-word bound counts the other words only. Only <callers by="subject"> reads
// this; the flip keeps `descriptive`, so a sentence never trades a map for a name-exact route.
// The two closed lists, one table: `cue` marks a dependents cue (also a frame word); the rest only frame the question.
struct TaskFrameWord
{
    std::string_view word;
    bool             cue;
};
inline constexpr TaskFrameWord kTaskFrameWords[] = {
    { "change", true }, { "changes", true }, { "changed", true }, { "changing", true }, { "add", true }, { "adds", true }, { "added", true },
    { "adding", true }, { "affect", true }, { "affects", true }, { "affected", true }, { "affecting", true }, { "break", true }, { "breaks", true },
    { "broke", true }, { "broken", true }, { "breaking", true }, { "depend", true }, { "depends", true }, { "depended", true }, { "depending", true },
    { "dependent", true }, { "dependents", true }, { "update", true }, { "updates", true }, { "updated", true }, { "updating", true }, { "modify", true },
    { "modifies", true }, { "modified", true }, { "modifying", true }, { "call", true }, { "calls", true }, { "called", true }, { "calling", true },
    { "caller", true }, { "callers", true }, { "used", true }, { "uses", true }, { "invoke", true }, { "invokes", true }, { "invoked", true },
    { "invoking", true }, { "references", true }, { "referenced", true }, { "referencing", true }, { "rename", true }, { "renames", true },
    { "renamed", true }, { "renaming", true }, { "exercise", true }, { "exercises", true }, { "exercised", true }, { "exercising", true },
    { "i", false }, { "we", false }, { "you", false }, { "me", false }, { "my", false }, { "our", false }, { "it", false }, { "its", false }, { "it's", false },
    { "they", false }, { "them", false }, { "their", false }, { "this", false }, { "that", false }, { "these", false }, { "those", false }, { "there", false },
    { "here", false }, { "am", false }, { "be", false }, { "been", false }, { "being", false }, { "was", false }, { "were", false }, { "has", false },
    { "have", false }, { "had", false }, { "did", false }, { "done", false }, { "would", false }, { "could", false }, { "might", false }, { "must", false },
    { "may", false }, { "shall", false }, { "need", false }, { "needs", false }, { "want", false }, { "wants", false }, { "wanted", false }, { "and", false },
    { "or", false }, { "if", false }, { "then", false }, { "so", false }, { "but", false }, { "else", false }, { "also", false }, { "whom", false },
    { "whose", false }, { "anything", false }, { "something", false }, { "everything", false }, { "define", false }, { "defines", false },
    { "defined", false }, { "use", false }, { "using", false }, { "work", false }, { "works", false }, { "worked", false }, { "working", false },
    { "from", false }, { "into", false }, { "onto", false }, { "between", false }, { "about", false }, { "by", false }, { "at", false }, { "as", false },
    { "through", false }, { "via", false }, { "within", false }, { "across", false }, { "after", false }, { "before", false }, { "during", false },
    { "up", false }, { "down", false }, { "out", false }, { "toward", false }, { "towards", false } };

// is the word (a subject word, already trimmed by graphSubjectTrimWord) in the table, and is it a cue?
enum class FrameClass : std::uint8_t
{
    None,
    Frame,
    Cue
};
inline FrameClass taskFrameClass( std::string_view w )
{
    const std::string lw = routeLower( w );
    const auto        at = std::ranges::find( kTaskFrameWords, std::string_view( lw ), &TaskFrameWord::word );
    return at == std::end( kTaskFrameWords ) ? FrameClass::None : at->cue ? FrameClass::Cue : FrameClass::Frame;
}

inline bool isDependentsCue( std::string_view w ) { return taskFrameClass( w ) == FrameClass::Cue; }

inline bool isTaskFrameWord( std::string_view w )
{
    return isQuestionLead( w ) || taskFrameClass( w ) != FrameClass::None;
}

// A cue word in a sentence names a dependent only in the dependents sense. Closed lists, read beside the cue (SCN-FIX1):
//   * a dependents NOUN (callers, dependents) always asks for them;
//   * the callee shape asks what the function itself does, so no verb cue counts: an auxiliary right before the name ("what does f
//     depend on / modify / use", "where does f make API calls") or the name as the subject of a verb cue ("f calls", "f uses");
//   * "used to <verb>" is a purpose; "API calls", "make calls" are a noun; a negated cue ("I changed nothing in f") asks nothing;
//   * "using" is a means ("build it using f") except after a form of be ("who is using f").
inline constexpr std::string_view kDependentsNouns[] = { "caller", "callers", "dependent", "dependents" };
inline constexpr std::string_view kCalleeAux[]       = { "does", "do", "did", "doesn't", "don't", "didn't" };
inline constexpr std::string_view kAgentCues[]       = { "calls", "uses", "depends", "modifies", "updates", "affects", "adds", "invokes", "references", "exercises", "renames" };
inline constexpr std::string_view kCallNounModifiers[] = { "api", "apis", "http", "https", "rpc", "grpc", "network", "remote", "external", "system", "database", "db",
                                                           "sql", "rest", "make", "makes", "made", "making" };
inline constexpr std::string_view kNegations[]  = { "not", "never", "no", "nothing", "none", "without", "didn't", "don't", "doesn't", "haven't", "hasn't", "won't" };
inline constexpr std::string_view kBeForms[]    = { "is", "are", "was", "were", "who's", "what's" };
// is the (trimmed) word, case-folded, in the closed list?
inline bool wordIn( std::string_view w, std::span<const std::string_view> list )
{
    const std::string lw = routeLower( w );
    return std::ranges::find( list, std::string_view( lw ) ) != list.end();
}

// "call chain from A to B" names the same two endpoints a path does (parseGraphSubject reads the code-spelled forms)
inline bool isGraphForm( std::string_view task, const std::vector<std::string_view>& words )
{
    if( parseGraphSubject( task ) )
    {
        return true;
    }
    for( std::size_t k = 0; k + 1 < words.size(); ++k )
    {
        const std::string a = routeLower( words[k] );
        const std::string b = routeLower( words[k + 1] );
        if( ( b == "from" && ( a == "path" || a == "chain" ) ) || ( b == "of" && ( a == "caller" || a == "callers" || a == "callees" ) ) )
        {
            return true;
        }
    }
    return false;
}

// A CI, tool or vendored copy: under a dot directory (.github, .circleci, .yarn), a vendoring directory, or the demo/generated tier. Such
// a file can define the subject's symbol, even first in path order (a bundled .github action defined Angular's UrlSerializer), and it
// is never what the subject means.
inline bool isToolOrVendoredPath( std::string_view p ) noexcept
{
    if( isDemoOrGeneratedPath( p ) )
    {
        return true;
    }
    for( std::size_t start = 0, slash = p.find( '/' ); slash != std::string_view::npos; start = slash + 1, slash = p.find( '/', start ) )
    {
        const std::string_view dir = p.substr( start, slash - start );
        const bool             vendoring = dir == "vendor" || dir == "third_party" || dir == "node_modules" || dir == "bower_components";
        if( vendoring || ( dir.size() > 1 && dir.front() == '.' && dir != ".." ) )
        {
            return true;
        }
    }
    return false;
}

inline bool sourceClassDef( const IngestResult& ing, NodeId id )
{
    const Symbol& s = ing.symbols[id];
    return s.kind != SymKind::Section && s.fileId < ing.files.size() && !langFacts( s.lang ).notCode
        && pathTierOf( rootRelPath( ing, s.fileId ) ) == PathTier::Source && !isToolOrVendoredPath( rootRelPath( ing, s.fileId ) ) && !isTestSymbol( ing, id );
}

// The definitions of each exact candidate: name equal byte for byte (an Elixir name/N also by its arity-less spelling), qualifier
// placing it when it has one. One pass over the symbols for all candidates.
inline std::vector<std::vector<NodeId>> placeCandidates( const IngestResult& ing, const std::vector<Spelling>& cands )
{
    std::vector<std::vector<NodeId>> out( cands.size() );
    for( NodeId id = 0; id < NodeId( ing.symbols.size() ); ++id )
    {
        const Symbol& s = ing.symbols[id];
        if( s.kind == SymKind::Section )
        {
            continue;
        }
        const std::string_view base = elixirBaseName( s.name );   // `name/N` to `name`; every other language's name is itself
        for( std::size_t k = 0; k < cands.size(); ++k )
        {
            if( base == cands[k].leaf && ( cands[k].qualifier.empty() || mention_detail::qualifierPlaces( ing, s, cands[k].qualifier ) ) )
            {
                out[k].push_back( id );
            }
        }
    }
    return out;
}
// One subject's words by class. False: a join word, so two named endpoints and no reading.
struct SubjectWords
{
    std::vector<std::string_view> named;     // identifier-syntax words with a clean spelling, trimmed
    std::vector<Spelling>         spelled;   // their spellings
    std::vector<std::string_view> kept;      // every identifier-syntax word, clean or not
};

inline bool sortSubjectWords( const std::vector<std::string_view>& words, SubjectWords& out, std::vector<std::string>& dropped )
{
    for( const std::string_view w : words )
    {
        if( detail::graphSubjectWordIs( w, { "+", "->", "=>", "=", "|", "<-", "&" } ) )   // two named endpoints: a connect question
        {
            return false;
        }
        const std::string_view t = detail::graphSubjectTrimWord( w ).text;
        if( isRouteStopword( routeLower( t ) ) )
        {
            continue;
        }
        if( !hasNameSyntax( t ) )
        {
            dropped.emplace_back( t );
            continue;
        }
        out.kept.push_back( t );
        if( const Spelling sp = parseSpelling( t ); sp.valid )
        {
            out.named.push_back( t );
            out.spelled.push_back( sp );
        }
    }
    return true;
}
// the cue at text[k] asks what depends on the sentence's function (the senses listed above kDependentsNouns)
inline bool cueInDependentsSense( const std::vector<std::string_view>& text, std::size_t k, bool callee )
{
    const std::string_view w    = text[k];
    const std::string_view prev = k > 0 ? text[k - 1] : std::string_view();
    const std::string_view next = k + 1 < text.size() ? text[k + 1] : std::string_view();
    if( wordIn( prev, kNegations ) || wordIn( next, kNegations ) )
    {
        return false;
    }
    if( wordIn( w, kDependentsNouns ) )
    {
        return true;
    }
    if( callee )
    {
        return false;
    }
    if( detail::graphSubjectWordIs( w, { "using" } ) )
    {
        return wordIn( prev, kBeForms );
    }
    const bool purpose = detail::graphSubjectWordIs( w, { "used" } ) && detail::graphSubjectWordIs( next, { "to" } );
    const bool noun    = detail::graphSubjectWordIs( w, { "call", "calls" } ) && wordIn( prev, kCallNounModifiers );
    return isDependentsCue( w ) && !purpose && !noun;
}
// a sentence that names ONE function (each mention the same spelling) and asks what depends on it, with few plain words beside the
// task frame. Two names fire for none: the block would have to guess which one the cue governs ("when f changes, who calls g?").
inline bool asksDependents( const std::vector<std::string_view>& words, const std::vector<std::string>& dropped )
{
    std::vector<std::string_view> text;   // trimmed words, sentence order
    std::string_view              name;
    bool                          callee = false;
    for( const std::string_view w : words )
    {
        text.push_back( detail::graphSubjectTrimWord( w ).text );
    }
    for( std::size_t k = 0; k < text.size(); ++k )
    {
        if( isRouteStopword( routeLower( text[k] ) ) || !hasNameSyntax( text[k] ) )
        {
            continue;
        }
        if( !name.empty() && name != text[k] )
        {
            return false;
        }
        name   = text[k];
        callee = callee || ( k > 0 && wordIn( text[k - 1], kCalleeAux ) ) || ( k + 1 < text.size() && wordIn( text[k + 1], kAgentCues ) );
    }
    bool cue = false;
    for( std::size_t k = 0; k < text.size() && !cue; ++k )
    {
        cue = cueInDependentsSense( text, k, callee );
    }
    const auto plain = []( const std::string& w ) { return !isTaskFrameWord( w ); };
    return cue && !name.empty() && std::size_t( std::ranges::count_if( dropped, plain ) ) <= kSubjectMaxPlainWords;
}
}   // namespace subject_detail

inline SubjectReading subjectReading( const IngestResult& ing, std::string_view task )
{
    using namespace subject_detail;
    SubjectReading                      r;
    const std::vector<std::string_view> words = splitRouteWords( task );
    if( words.size() < 2 || queryshape::classify( task ).fires() || isGraphForm( task, words ) )
    {
        return r;
    }
    SubjectWords sw;
    if( !sortSubjectWords( words, sw, r.dropped ) )
    {
        return r;
    }
    const std::vector<std::string_view>& named   = sw.named;
    const std::vector<Spelling>&         spelled = sw.spelled;
    const std::vector<std::string_view>& keptRaw = sw.kept;
    if( spelled.empty() || r.dropped.empty() )
    {
        return r;
    }
    std::vector<std::vector<NodeId>> placed = placeCandidates( ing, spelled );
    for( std::size_t k = 0; k < placed.size(); ++k )
    {
        if( placed[k].empty() || placed[k].size() > kSubjectMaxDefs )
        {
            continue;
        }
        for( const NodeId id : placed[k] )
        {
            r.sourceDef = r.sourceDef || sourceClassDef( ing, id );
        }
        r.exact.push_back( SubjectExactSymbol{ std::string( named[k] ), std::move( placed[k] ) } );
    }
    if( r.exact.empty() )
    {
        return r;
    }
    for( const std::string_view t : keptRaw )
    {
        r.reduced += r.reduced.empty() ? "" : " ";
        r.reduced += t;
    }
    r.names       = keptRaw.size();
    r.descriptive = !isQuestionLead( words.front() ) && r.dropped.size() <= kSubjectMaxPlainWords;
    r.framed      = r.descriptive || subject_detail::asksDependents( words, r.dropped );
    return r;
}

// "; dropped: emit(102-defs) new(41-defs) argument" — the words the route did not read, each with the definitions it would have
// named, so an agent that did mean the symbol can see it and ask for it alone.
inline std::string subjectDroppedClause( const IngestResult& ing, const std::vector<std::string>& dropped )
{
    const HashMap<std::string, NameAnchor> names = buildLowerNameIndex( ing );
    std::string                            out   = "; dropped: ";
    bool                                   first = true;
    for( const std::string& w : dropped )
    {
        out += first ? "" : " ";
        first = false;
        out += w;
        const auto at = names.find( routeLower( w ) );
        if( at != names.end() && at->second.wholeName )
        {
            out += "(" + std::to_string( at->second.extraDefs + 1u ) + "-defs)";
        }
    }
    return out;
}

// CONFIDENCE-ANCHOR: does the name-exact route's anchor have a source-class definition? A resolved anchor is judged at the file its
// answer is served from (RouteAnchorDef, the same pick the auto bodies read), an identifier-syntax anchor with no whole-name symbol by
// its leaf anywhere. Every other route answers true: confidence= there says nothing about a name.
inline bool routeAnchorHasSourceDef( const IngestResult& ing, const RouteChoice& rc, std::string_view rankQuery )
{
    using namespace subject_detail;
    if( rc.which != LexMode::NameExact )
    {
        return true;
    }
    std::vector<std::string> leaves;     // every word that spells a symbol
    std::vector<std::string> idLeaves;   // the identifier-syntax ones: a subject that SPELLS a name is about that name
    for( const std::string_view w : splitRouteWords( rankQuery ) )
    {
        const std::string_view t = detail::graphSubjectTrimWord( w ).text;
        if( const Spelling sp = parseSpelling( t ); sp.valid )
        {
            leaves.push_back( routeLower( sp.leaf ) );
            if( hasNameSyntax( t ) )
            {
                idLeaves.push_back( routeLower( sp.leaf ) );
            }
        }
    }
    // a subject that is a FILE ("DynamicScreen.c", "src/x.cc") anchors that file, not a symbol: a source file is a source anchor
    if( rc.anchorDefs.empty() )
    {
        for( const std::string_view w : splitRouteWords( rankQuery ) )
        {
            const std::string_view t = detail::graphSubjectTrimWord( w ).text;
            for( std::uint32_t f = 0; f < ing.files.size(); ++f )
            {
                const std::string_view path = rootRelPath( ing, f );
                if( path.ends_with( t ) && ( path.size() == t.size() || path[ path.size() - t.size() - 1 ] == '/' ) && pathTierOf( path ) == PathTier::Source && !isToolOrVendoredPath( path ) )
                {
                    return true;
                }
            }
        }
    }
    // A plain word never vouches for a subject that spells a name: `max_concurrent_queries read` is about the key, whose only home is
    // a data file, and `read` has a source definition anywhere. With no identifier-syntax word, the plain words ARE the anchor.
    const std::vector<std::string>& judge = idLeaves.empty() ? leaves : idLeaves;
    const auto inJudge = [ & ]( const std::string& lower ) { return std::ranges::find( judge, lower ) != judge.end(); };
    const auto named = [ & ]( const Symbol& s )
    {
        const std::string lower = routeLower( s.name );
        if( rc.anchorDefs.empty() )
        {
            return inJudge( lower );
        }
        return inJudge( lower ) && std::ranges::any_of( rc.anchorDefs, [ & ]( const RouteAnchorDef& a ) { return a.fileId == s.fileId && a.lowerName == lower; } );
    };
    for( NodeId id = 0; id < NodeId( ing.symbols.size() ); ++id )
    {
        if( named( ing.symbols[id] ) && sourceClassDef( ing, id ) )
        {
            return true;
        }
    }
    return false;
}

// FRAME-HIGH-CONFIDENCE: the keys a ranked head row is matched against (routeAnchorHeadsRows). Name-exact routes only.
inline RouteAnchorKeys routeAnchorKeys( const IngestResult& ing, const RouteChoice& rc, std::string_view rankQuery )
{
    using namespace subject_detail;
    RouteAnchorKeys out;
    if( rc.which != LexMode::NameExact )
    {
        return out;
    }
    const auto addName = [&]( std::string lower )
    {
        if( !lower.empty() && std::ranges::find( out.lowerNames, lower ) == out.lowerNames.end() )
        {
            out.lowerNames.push_back( std::move( lower ) );
        }
    };
    const auto addFile = [&]( std::uint32_t f )
    {
        if( std::ranges::find( out.fileIds, f ) == out.fileIds.end() )
        {
            out.fileIds.push_back( f );
        }
    };
    for( const RouteAnchorDef& a : rc.anchorDefs )
    {
        addName( a.lowerName );
        addFile( a.fileId );
    }
    // The words' leaves, judged as routeAnchorHasSourceDef judges them: a subject that spells a name is about that name, so its plain
    // words (`where`, `defined`) are not the anchor; with no identifier-syntax word, the plain words are.
    std::vector<std::string> leaves;
    std::vector<std::string> idLeaves;
    for( const std::string_view w : splitRouteWords( rankQuery ) )
    {
        const std::string_view t = detail::graphSubjectTrimWord( w ).text;
        if( const Spelling sp = parseSpelling( t ); sp.valid )
        {
            leaves.push_back( routeLower( sp.leaf ) );
            if( hasNameSyntax( t ) )
            {
                idLeaves.push_back( routeLower( sp.leaf ) );
            }
        }
        // a FILE subject ("DynamicScreen.c", "src/x.cc") anchors that file: any row in it is the anchor's
        if( t.find( '.' ) != std::string_view::npos || t.find( '/' ) != std::string_view::npos )
        {
            for( std::uint32_t f = 0; f < ing.files.size(); ++f )
            {
                const std::string_view path = rootRelPath( ing, f );
                if( path.ends_with( t ) && ( path.size() == t.size() || path[path.size() - t.size() - 1] == '/' ) )
                {
                    addFile( f );
                }
            }
        }
    }
    for( std::string& l : idLeaves.empty() ? leaves : idLeaves )
    {
        addName( std::move( l ) );
    }
    return out;
}

// FRAME-HIGH-CONFIDENCE: does the anchor head the ranked rows? confidence= measures the score drop below the head, so it vouches for the
// anchor only when the head IS the anchor: a symbol of the anchor's name (an Elixir `name/N` by its base), or a row in a file the anchor
// is defined in. No keys (no name-exact route, or nothing to match): true, the check says nothing.
inline bool routeAnchorHeadsRows( const IngestResult& ing, const RouteAnchorKeys& keys, NodeId head )
{
    if( keys.lowerNames.empty() && keys.fileIds.empty() )
    {
        return true;
    }
    const Symbol& s = ing.symbols[head];
    if( std::ranges::find( keys.fileIds, s.fileId ) != keys.fileIds.end() )
    {
        return true;
    }
    const std::string lower = routeLower( s.name );
    const std::string base = routeLower( elixirBaseName( s.name ) );
    return std::ranges::any_of( keys.lowerNames, [&]( const std::string& n )
                                { return n == lower || n == base; } );
}

// The route= clause a head that is not the anchor appends, beside the confidence it lowers: the reader sees which row heads instead.
inline std::string routeAnchorNotHeadClause( const IngestResult& ing, NodeId head )
{
    const Symbol& s = ing.symbols[head];
    return "; anchor is not the ranked head (r=1 is " + s.name + " in " + std::string( rootRelPath( ing, s.fileId ) ) + ")";
}

// Is a plain word among a name-exact route's anchors?
inline bool subjectAnchoredPlainWord( const IngestResult& ing, const RouteChoice& whole, const SubjectReading& r )
{
    if( whole.which != LexMode::NameExact )
    {
        return false;
    }
    const HashMap<std::string, NameAnchor> names = buildLowerNameIndex( ing );
    for( const std::string& w : r.dropped )
    {
        const auto at = names.find( routeLower( w ) );
        if( at != names.end() && at->second.wholeName )
        {
            return true;
        }
    }
    return false;
}

// Would the bare symbol's route SERVE what a flip takes away? A declined or conceptual route is a ranked map; the name-exact route that
// replaces it is one definition's body plus its callers, and nothing else. That trade is worth it only when both really print:
//   * the anchor resolved to a definition (rc.anchorDefs): the single-anchor body allowance (kForAnchorBodyBudgetBytes) funds ITS body.
//     A spelling the route could only read by shape ("ProcessList::insert(syntax)") binds nothing, so the body is omitted: no flip;
//   * a definition carries a body (a declaration-only symbol never flips) and the span(s) fit the allowance that really funds them: one
//     candidate gets kForAnchorBodyBudgetBytes, a declaration beside its definition shares the six-candidate pool;
//   * the name is ONE function over the whole index, by the callers verb's own resolution (forCallerHopTargets): its callers are
//     served and no namesake, in any directory, is a second candidate for the body. This is the class, not a path list: a copy under
//     devtools/, ci/, examples/, deps/ or anywhere else makes the name two functions and the map stays;
//   * at least one caller prints, and every match falls in ONE definition group (a declaration in another namespace is not this body's).
inline bool flipServesBodyAndCallers( const IngestResult& ing, const Graph& g, const RouteChoice& bare )
{
    if( bare.anchorDefs.empty() )
    {
        return false;
    }
    std::vector<NodeId> defs;
    for( NodeId id = 0; id < NodeId( ing.symbols.size() ); ++id )
    {
        const Symbol& s = ing.symbols[id];
        if( s.kind == SymKind::Section )
        {
            continue;
        }
        const std::string lower = routeLower( s.name );
        for( const RouteAnchorDef& a : bare.anchorDefs )
        {
            if( a.fileId == s.fileId && a.lowerName == lower )
            {
                defs.push_back( id );
                break;
            }
        }
    }
    // M2: a symbol with no definition that carries a body (a prototype, an interface method, a `declare function`) has no body to
    // print, so the flip would trade the map for a signature and nothing else.
    const bool anyBody = std::ranges::any_of( defs, [ & ]( NodeId id ) { return isDefinitionNotDeclaration( ing.symbols[id] ); } );
    if( !anyBody )
    {
        return false;
    }
    // M1: the budget that really funds the body. ONE candidate raises to kForAnchorBodyBudgetBytes; two or more (a declaration beside
    // its definition in one file is two) share the six-candidate pool (kForAutoBodyBudgetBytes, buildForAutoBodies), so their whole
    // spans must fit that. A byte count, not a promise about which one prints: an over-budget case keeps the map.
    const std::size_t allowance = defs.size() == 1 ? kForAnchorBodyBudgetBytes : kForAutoBodyBudgetBytes;
    std::size_t       spanBytes = 0;
    for( const NodeId id : defs )
    {
        const Symbol& s = ing.symbols[id];
        spanBytes += s.endByte > s.sigStartByte ? std::size_t( s.endByte - s.sigStartByte ) : 0;
    }
    if( spanBytes > allowance )
    {
        return false;
    }
    const std::vector<NodeId> targets = forCallerHopTargets( ing, g, defs );
    if( targets.empty() )
    {
        return false;
    }
    // M5: callers total >= 1, so the <callers> a flip promises exists.
    const std::vector<NodeId> rows = oneHopCallerRows( ing, g, targets );
    if( rows.empty() )
    {
        return false;
    }
    // M4 (cross-namespace tie): the hop resolves the SCOPED selector (`b::SoloThing`), so a bodyless declaration of the same bare name in
    // another namespace or owner (`namespace a { int SoloThing(int); }`) is outside `targets`, yet the callers verb unions it with the
    // definition: the body is b's and the caller row is a's. A bodyless namesake in any other scope declines the flip.
    {
        std::size_t unproven = 0;
        for( const NodeId id : resolveAllByNameQualified( ing, ing.symbols[ targets.front() ].name, &unproven ) )
        {
            if( ReceiverEvidence::callableKind( ing.symbols[id].kind ) && !isDefinitionNotDeclaration( ing.symbols[id] )
                && std::ranges::find( targets, id ) == targets.end() )
            {
                return false;
            }
        }
    }
    // M4: ONE definition group. A declaration in `a` and a definition in `b` are two groups the callers verb unions (the hop tolerates
    // an untied bodyless group); the body and callers a flip would print belong to one of them. Declined: the map stays.
    return attributeOneHopAnswer( ing, g, targets, rows, /*towardMatches=*/true ).groups.size() == 1;
}

// The route the subject reading picks, before the CONFIDENCE-ANCHOR check. `servesBodiesAndCallers`: the surface prints the anchor's
// body and <callers> (the CLI --for does; the MCP `for` verb serves signatures only), so it may trade a ranked map for them.
inline SubjectRoute chooseSubjectRouteUnchecked( const IngestResult& ing, const Graph& g, std::string_view task, bool servesBodiesAndCallers )
{
    SubjectRoute out;
    out.route = chooseForRanker( ing, task );
    SubjectReading reading = subjectReading( ing, task );
    if( reading.exact.empty() )
    {
        return out;
    }
    const bool lift     = reading.descriptive && reading.sourceDef;
    const bool declined = out.route.reason.starts_with( "subtoken+body:declined(" );
    const bool plainAnchored = subjectAnchoredPlainWord( ing, out.route, reading );
    // A flip is the ONE change to the route. It needs a surface that prints the body and the callers, and ONE name: the subject spells
    // one identifier and it places one exact symbol. Several names ("add a UrlSerializer parameter to createSegmentGroupFromRoute",
    // `first_caller second_caller new`) name no ONE anchor whose body and callers a name-exact answer would serve: the route stands.
    // Every refusal below leaves `out.route` exactly what chooseForRanker made of the whole subject (the answer is the one it always
    // was); a conceptual route then only gains <callers by="subject"> on top.
    if( servesBodiesAndCallers && reading.exact.size() == 1 && reading.names == 1 && ( plainAnchored || ( declined && lift ) ) )
    {
        RouteChoice bare = chooseForRanker( ing, reading.reduced );
        // The words go only for a route that is still name-exact on the symbol, whose anchor has a SOURCE definition (a test, doc or
        // data-file anchor leaves the route as it was; CONFIDENCE-ANCHOR reads it low), and whose answer prints the body AND the
        // callers (flipServesBodyAndCallers: one function, a real body that fits, a caller). This holds when a dropped word is itself
        // a symbol too ("how does X work": `work` is a definition in every large repo).
        if( bare.which == LexMode::NameExact && routeAnchorHasSourceDef( ing, bare, reading.reduced ) && flipServesBodyAndCallers( ing, g, bare ) )
        {
            bare.reason += subjectDroppedClause( ing, reading.dropped );
            out.route     = std::move( bare );
            out.rankQuery = std::move( reading.reduced );
            return out;
        }
    }
    // SUBJECT-CALLERS-NATURAL: the callers ride on a framed sentence too ("who calls f", "I need to change f; what depends on it?")
    if( reading.framed && reading.sourceDef && out.route.which != LexMode::NameExact )
    {
        // the source-class definitions only: a CI or vendored copy of the name is not a second function to split the callers over
        for( SubjectExactSymbol& e : reading.exact )
        {
            std::erase_if( e.defs, [ & ]( NodeId id ) { return !subject_detail::sourceClassDef( ing, id ); } );
            if( !e.defs.empty() )
            {
                out.callerCandidates.push_back( std::move( e.defs ) );
            }
        }
    }
    return out;
}

// THE entry point both the CLI lens and the MCP verbs call in place of chooseForRanker. No reading and a source-backed anchor: exactly
// chooseForRanker. confidence= reads low on anchorNoSource, and route= says why, so the answer explains itself in every legend dialect.
inline SubjectRoute chooseSubjectRoute( const IngestResult& ing, const Graph& g, std::string_view task, bool servesBodiesAndCallers )
{
    SubjectRoute out = chooseSubjectRouteUnchecked( ing, g, task, servesBodiesAndCallers );
    const std::string_view rankQuery = out.rankQuery.empty() ? task : std::string_view( out.rankQuery );
    out.anchorNoSource = !routeAnchorHasSourceDef( ing, out.route, rankQuery );
    out.anchorKeys = routeAnchorKeys( ing, out.route, rankQuery );
    if( out.anchorNoSource )
    {
        out.route.reason += "; anchor has no source definition (test, doc, data, CI or vendored only, or not indexed)";
    }
    return out;
}

} // namespace rw
