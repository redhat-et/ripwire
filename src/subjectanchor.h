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
#include "darkflags.h"         // readWhole / wholeWordAt — an outer qualifier read in the definition's file
#include "model.h"
#include "queryshape.h"
#include "serialize.h"         // kForAnchorBodyBudgetBytes

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
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
    std::vector<NodeId>             codeSubject;           // SENTENCE-SUBJECT: the ONE `backticked` symbol a sentence asks the dependents of
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

// A Go receiver spelling read as the name it qualifies: `(*pkg.T).M` and `(T).M` are pkg.T.M and T.M; "" when `w` is not one.
// Anything after the method name stays (a sentence word's closing backtick or `?`).
inline std::string goReceiverRead( std::string_view w )
{
    const std::size_t rp = w.find( ')' );
    if( !w.starts_with( '(' ) || rp == std::string_view::npos || rp + 1 >= w.size() || w[rp + 1] != '.' )
    {
        return {};
    }
    std::string_view recv = w.substr( 1, rp - 1 );
    recv.remove_prefix( recv.starts_with( '*' ) ? 1 : 0 );
    return std::string( recv ) + std::string( w.substr( rp + 1 ) );
}

// SENTENCE-SUBJECT. A sentence that marks its code (`backticks`) says which words are names, so the guards above that tell a name from
// prose (one identifier-syntax word, at most kSubjectMaxPlainWords plain words) have nothing left to guess: "If
// `kvserver.NewReplicaEvalContext` (pkg/...) gained a new required parameter, exactly which non-test functions call it directly ...;
// functions that merely receive the resulting EvalContext ... do not count" names ONE function, however long it is and whatever
// other identifier it mentions in passing. Each span spells one name: a call's argument list is dropped (`f(title)` is f), a Go
// receiver is unwrapped (`(*pkg.T).M` is pkg.T.M), a span with a space in it (`nu script.nu`) is a command, not a name.
inline std::vector<std::string> backtickSpellings( std::string_view task )
{
    std::vector<std::string> out;
    for( std::size_t open = task.find( '`' ); open != std::string_view::npos; )
    {
        const std::size_t close = task.find( '`', open + 1 );
        if( close == std::string_view::npos )
        {
            break;
        }
        std::string_view span = task.substr( open + 1, close - open - 1 );
        open                  = task.find( '`', close + 1 );
        std::string name = span.starts_with( '(' ) ? goReceiverRead( span ) : std::string( span );   // a Go receiver: `(*pkg.T).M`, `(T).M`
        if( name.empty() )
        {
            continue;
        }
        if( const std::size_t lp = name.find( '(' ); lp != std::string::npos )   // a call: `f(title)`, `f()`, `f(...)`
        {
            if( !name.ends_with( ')' ) )
            {
                continue;
            }
            name.resize( lp );
        }
        if( !name.empty() && parseSpelling( name ).valid && std::ranges::find( out, name ) == out.end() )
        {
            out.push_back( std::move( name ) );
        }
    }
    return out;
}

// The qualifiers a spelling names BEFORE the one parseSpelling keeps: `Missing::Model::save` is "Missing",
// `concurrent.futures.ThreadPoolExecutor` is "concurrent", a one- or two-segment spelling has none.
inline std::string_view outerQualifiers( std::string_view word, const subject_detail::Spelling& sp ) noexcept
{
    if( sp.qualifier.empty() || sp.qualifier.data() < word.data() || sp.qualifier.data() > word.data() + word.size() )
    {
        return {};
    }
    std::string_view outer = word.substr( 0, std::size_t( sp.qualifier.data() - word.data() ) );
    while( !outer.empty() && ( outer.back() == ':' || outer.back() == '.' ) )
    {
        outer.remove_suffix( 1 );
    }
    return outer;
}

// ANCHOR-QUALIFIER-OWNERSHIP (CodeRabbit #630): does `bytes` OPEN a scope named `seg` outside a comment — `namespace X` (or
// `namespace a::X`), `mod X`, `package X` (or `package a.X`), `module X`, `class X`, `struct X`, `impl X`? A bare whole word (a
// comment, an unrelated identifier) placed a wrong qualifier before; `using namespace X;` names a scope, it opens none.
inline bool opensScopeNamed( std::string_view bytes, std::string_view seg )
{
    static constexpr std::string_view kOpeners[] = { "namespace", "mod", "package", "module", "class", "struct", "impl" };
    const auto identAt = [ & ]( std::size_t i ) { return namesplit::isIdentChar( bytes[ i ] ); };
    // the identifier ending at `end` after whitespace, line breaks included (`namespace\nrw {`, CodeRabbit 4570578087), as [start, end)
    const auto wordBefore = [ & ]( std::size_t end )
    {
        std::size_t e = end;
        while( e > 0 && ( bytes[ e - 1 ] == ' ' || bytes[ e - 1 ] == '\t' || bytes[ e - 1 ] == '\n' || bytes[ e - 1 ] == '\r' ) )
        {
            --e;
        }
        std::size_t b = e;
        while( b > 0 && identAt( b - 1 ) )
        {
            --b;
        }
        return std::pair{ b, e };
    };
    darkflags::BlockCommentState comments( bytes );
    for( std::size_t at = bytes.find( seg ); at != std::string_view::npos; at = bytes.find( seg, at + 1 ) )
    {
        if( !darkflags::wholeWordAt( bytes, at, seg.size() ) )
        {
            continue;
        }
        std::size_t b = at;   // back over a qualified prefix (`a::b::X`, `a.b.X`)
        for( ;; )
        {
            const std::size_t sep = b >= 2 && bytes.substr( b - 2, 2 ) == "::" ? 2 : ( b >= 1 && bytes[ b - 1 ] == '.' ? 1 : 0 );
            if( sep == 0 || b - sep == 0 || !identAt( b - sep - 1 ) )
            {
                break;
            }
            b -= sep;
            while( b > 0 && identAt( b - 1 ) )
            {
                --b;
            }
        }
        const auto [ kb, ke ] = wordBefore( b );
        if( ke == b || std::ranges::find( kOpeners, bytes.substr( kb, ke - kb ) ) == std::end( kOpeners ) )
        {
            continue;
        }
        if( const auto [ ub, ue ] = wordBefore( kb ); bytes.substr( ub, ue - ub ) == "using" )
        {
            continue;
        }
        const std::size_t      nl   = kb == 0 ? std::string_view::npos : bytes.rfind( '\n', kb - 1 );
        const std::string_view lead = bytes.substr( nl == std::string_view::npos ? 0 : nl + 1, kb - ( nl == std::string_view::npos ? 0 : nl + 1 ) );
        if( lead.find( "//" ) != std::string_view::npos || lead.find( '#' ) != std::string_view::npos || comments.insideAt( kb ) )
        {
            continue;   // a line comment (`//`, `#`) or a block comment: it opens nothing
        }
        return true;
    }
    return false;
}

// Does every segment of `outer` place `s`? A segment places it when it is a segment of its scope, a directory or the stem on its
// file's path, a Rust path keyword, or a scope its file opens (a C++ `namespace rw {`, a Rust `mod net {`; opensScopeNamed): `Missing.Model.save`
// names nothing of pkg/models/base.py's Model.save, `concurrent.futures.ThreadPoolExecutor` names Lib/concurrent/. Read only on
// a word with outer qualifiers, and the file only when the cheap tests fail.
// ANCHOR-READ-DISCLOSE (CodeRabbit #630): a definition file the read cannot open (unreadable, or over darkflags::readWhole's
// 4 MiB) is not placed, and `*unread` says so, so the route reason discloses it instead of reading the qualifier as absent.
inline bool outerQualifiersPlace( const IngestResult& ing, const Symbol& s, std::string_view outer, bool* unread = nullptr )
{
    const std::string_view path = rootRelPath( ing, s.fileId );
    const auto namesSegment = []( std::string_view text, std::string_view seps, std::string_view seg )
    {
        for( std::size_t i = 0; i <= text.size(); )
        {
            const std::size_t e = std::min( text.find_first_of( seps, i ), text.size() );
            if( text.substr( i, e - i ) == seg )
            {
                return true;
            }
            i = e + 1;
        }
        return false;
    };
    std::optional<std::string> bytes;
    bool                       read = false;
    for( std::size_t i = 0; i < outer.size(); )
    {
        const std::size_t      e   = std::min( outer.find_first_of( ".:", i ), outer.size() );
        const std::string_view seg = outer.substr( i, e - i );
        i                          = e + 1;
        if( seg.empty() || seg == "crate" || seg == "self" || seg == "super" || namesSegment( s.scope, ".:", seg )
            || namesSegment( path.substr( 0, path.size() - mention_detail::baseNameOf( path ).size() ), "/", seg ) || mention_detail::pathStem( path ) == seg )
        {
            continue;
        }
        if( !read )
        {
            bytes = darkflags::readWhole( diskPath( ing, s.fileId ) );
            read  = true;
        }
        if( !bytes && unread != nullptr )
        {
            *unread = true;
        }
        if( !bytes || !opensScopeNamed( *bytes, seg ) )
        {
            return false;
        }
    }
    return true;
}
// The names a sentence spells as code, sentence order, each with the definitions it places (1 to kSubjectMaxDefs): its `backtick` spans
// when it has any, else its identifier-syntax words. A spelling that places nothing (a file, a command, a field) is no name here.
struct CodeName
{
    std::string         spelling;
    std::vector<NodeId> defs;
};
inline std::vector<CodeName> sentenceCodeNames( const IngestResult& ing, std::string_view task, const std::vector<std::string_view>& words )
{
    std::vector<std::string> spellings = backtickSpellings( task );
    if( spellings.empty() )
    {
        for( const std::string_view w : words )
        {
            const std::string_view t = detail::graphSubjectTrimWord( w ).text;
            if( hasNameSyntax( t ) && parseSpelling( t ).valid && !isRouteStopword( routeLower( t ) ) && std::ranges::find( spellings, t ) == spellings.end() )
            {
                spellings.emplace_back( t );
            }
        }
    }
    std::vector<Spelling> parsed;
    for( const std::string& sp : spellings )
    {
        parsed.push_back( parseSpelling( sp ) );
    }
    std::vector<std::vector<NodeId>> placed = placeCandidates( ing, parsed );
    std::vector<CodeName>            out;
    for( std::size_t k = 0; k < spellings.size(); ++k )
    {
        // the placement read only the leaf and the last qualifier: `Missing::Model::save` must not place `Model::save` (as
        // sourceSyntaxAnchors filters it; CodeRabbit on #646)
        const std::string_view outer = outerQualifiers( spellings[k], parsed[k] );
        std::erase_if( placed[k], [ & ]( NodeId id ) { return !outerQualifiersPlace( ing, ing.symbols[id], outer ); } );
        // two spellings of one function (`ConfigWrapper.core_config(title)` and later `core_config`) are one name
        const bool same = std::ranges::any_of( out, [ & ]( const CodeName& c ) { return c.defs == placed[k]; } );
        if( !placed[k].empty() && placed[k].size() <= kSubjectMaxDefs && !same )
        {
            out.push_back( CodeName{ spellings[k], std::move( placed[k] ) } );
        }
    }
    return out;
}

// The sentence's words as the name tests compare them: trimmed, and a Go receiver word read as backtickSpellings reads it
// (`(*kv.Replica).NewEvalContext` is kv.Replica.NewEvalContext). `text` views `goRead`'s strings or the words themselves.
struct SentenceWordText
{
    std::vector<std::string_view> text;
    std::vector<std::string>      goRead;
};
inline SentenceWordText sentenceWordText( const std::vector<std::string_view>& words )
{
    SentenceWordText r;
    r.goRead.reserve( words.size() );   // no reallocation: `text` views these strings (a move of `r` keeps the buffer)
    for( std::string_view w : words )
    {
        w.remove_prefix( w.starts_with( '`' ) ? 1 : 0 );
        r.goRead.push_back( goReceiverRead( w ) );
        r.text.push_back( r.goRead.back().empty() ? detail::graphSubjectTrimWord( w ).text : std::string_view( r.goRead.back() ) );
    }
    return r;
}

// does the sentence ask what depends on `spelling`? A dependents cue in that sense anywhere (no plain-word bound: the code is marked)
// whose object is the name: the name, or a pronoun for it, within kCueObjectWords words after the cue ("which functions call it
// directly", "who invokes `f`", "callers does `f` have"). A cue about something else ("how does rake invoke the task ... `multitask`
// prerequisites") asks nothing about the name.
inline constexpr std::size_t      kCueObjectWords = 3;
inline constexpr std::string_view kCuePronouns[]  = { "it", "them", "its" };
inline bool asksDependentsOf( const std::vector<std::string_view>& words, std::string_view spelling )
{
    const SentenceWordText        read = sentenceWordText( words );
    const std::vector<std::string_view>& text = read.text;
    bool callee = false;
    for( std::size_t k = 0; k < text.size(); ++k )
    {
        if( text[k].find( spelling ) != std::string_view::npos )
        {
            callee = callee || ( k > 0 && wordIn( text[k - 1], kCalleeAux ) ) || ( k + 1 < text.size() && wordIn( text[k + 1], kAgentCues ) );
        }
    }
    const auto objectAfter = [ & ]( std::size_t k )
    {
        for( std::size_t j = k + 1; j < text.size() && j <= k + kCueObjectWords; ++j )
        {
            if( text[j].find( spelling ) != std::string_view::npos || wordIn( text[j], kCuePronouns ) )
            {
                return true;
            }
        }
        return false;
    };
    for( std::size_t k = 0; k < text.size(); ++k )
    {
        if( cueInDependentsSense( text, k, callee ) && objectAfter( k ) )
        {
            return true;
        }
    }
    return false;
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
    if( !backtickSpellings( task ).empty() )   // SENTENCE-SUBJECT: a code-marked sentence naming ONE symbol and asking what depends on it
    {
        std::vector<CodeName> code = sentenceCodeNames( ing, task, words );
        if( code.size() == 1 && asksDependentsOf( words, code.front().spelling ) )
        {
            r.codeSubject = std::move( code.front().defs );
        }
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
        // every qualifier, not only the last: `Missing.setup.prepare_setup_platform` places nothing (as sentenceCodeNames)
        const std::string_view outer = outerQualifiers( named[k], spelled[k] );
        std::erase_if( placed[k], [ & ]( NodeId id ) { return !outerQualifiersPlace( ing, ing.symbols[id], outer ); } );
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

// A FILE subject ("DynamicScreen.c", "src/x.cc") anchors that file: the files whose path ends with the word at a path-segment boundary,
// so any row in them is the anchor's. None when the word spells a symbol the index holds (`FooBar.py` as the method `py` of FooBar): it
// names that symbol, and a file of the same spelling is a namesake, not the anchor.
inline std::vector<std::uint32_t> fileSubjectFiles( const IngestResult& ing, std::string_view t, const subject_detail::Spelling& sp )
{
    std::vector<std::uint32_t> named;
    if( t.find( '.' ) == std::string_view::npos && t.find( '/' ) == std::string_view::npos )
    {
        return named;
    }
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view path = rootRelPath( ing, f );
        if( path.ends_with( t ) && ( path.size() == t.size() || path[path.size() - t.size() - 1] == '/' ) )
        {
            named.push_back( f );
        }
    }
    if( !named.empty() && sp.valid && !subject_detail::placeCandidates( ing, std::vector<subject_detail::Spelling>{ sp } )[0].empty() )
    {
        named.clear();
    }
    return named;
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
        const Spelling sp = parseSpelling( t );
        if( sp.valid )
        {
            leaves.push_back( routeLower( sp.leaf ) );
            if( hasNameSyntax( t ) )
            {
                idLeaves.push_back( routeLower( sp.leaf ) );
            }
        }
        for( const std::uint32_t f : fileSubjectFiles( ing, t, sp ) )
        {
            addFile( f );
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

// The row the answer prints as r=1. confidence= and the route= clause read the score head, but code above docs (serialize.h
// reorderDocsAfterCode) moves the Markdown rows of the shown set below its code rows, so when that reorder applies the first row printed is
// the first non-Markdown one of the surface. Same predicate on the CLI and MCP twins (their `docsAfterCode` verdicts).
inline NodeId routeEmittedHead( const IngestResult& ing, std::span<const NodeId> surface, bool docsAfterCode )
{
    if( docsAfterCode )
    {
        const auto code = std::ranges::find_if( surface, [&]( NodeId id ) { return !isDocsAfterCodeRow( ing, id ); } );
        if( code != surface.end() )
        {
            return *code;
        }
    }
    return surface.front();
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

// The <callers by="subject"> candidates of a conceptual route, from the source-class definitions only (a CI or vendored copy of the
// name is not a second function to split the callers over):
//   * SUBJECT-CALLERS-NATURAL: a descriptive or framed subject's exact symbols ("who calls f", "I need to change f; what depends on it?");
//   * SENTENCE-SUBJECT: else the ONE symbol a code-marked sentence asks the dependents of.
inline std::vector<std::vector<NodeId>> subjectCallerCandidates( const IngestResult& ing, SubjectReading reading )
{
    std::vector<std::vector<NodeId>> out;
    const auto addSource = [ & ]( std::vector<NodeId> defs )
    {
        std::erase_if( defs, [ & ]( NodeId id ) { return !subject_detail::sourceClassDef( ing, id ); } );
        if( !defs.empty() )
        {
            out.push_back( std::move( defs ) );
        }
    };
    if( reading.framed && reading.sourceDef )
    {
        for( SubjectExactSymbol& e : reading.exact )
        {
            addSource( std::move( e.defs ) );
        }
    }
    if( out.empty() )
    {
        addSource( std::move( reading.codeSubject ) );
    }
    return out;
}

// The route the subject reading picks, before the CONFIDENCE-ANCHOR check. `servesBodiesAndCallers`: the surface prints the anchor's
// body and <callers> (the CLI --for does; the MCP `for` verb serves signatures only), so it may trade a ranked map for them.
inline SubjectRoute chooseSubjectRouteUnchecked( const IngestResult& ing, const Graph& g, std::string_view task, bool servesBodiesAndCallers )
{
    SubjectRoute out;
    out.route = chooseForRanker( ing, task );
    SubjectReading reading = subjectReading( ing, task );
    if( reading.exact.empty() && reading.codeSubject.empty() )
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
    if( out.route.which != LexMode::NameExact )   // a conceptual route only gains <callers by="subject"> on top
    {
        out.callerCandidates = subjectCallerCandidates( ing, std::move( reading ) );
    }
    return out;
}

// RE-ASK (SENTENCE-SUBJECT card 2). A sentence that spells code and asks a graph question the answer did not carry a block for (no
// <callers by="subject">, no <graph_verb>): the bare form of the same question, the one call that does answer it. The shape is read
// from the sentence's own words, as the blocks read it: ONE code name and a dependents cue is `--callers=X`; two or more code names and
// a graph cue (path, chain, reach, calls both, common caller) is `--path=A,B` (`--connect=A,B` for both / common), the first two names
// in sentence order unless a `from`/`to` marker states the direction. A sentence is a question mark, a `backticked` name or a question lead; a stored key ("X gains a parameter") is not
// one. Anything else is "" (nothing to suggest).
inline std::string sentenceReaskInvocation( const IngestResult& ing, std::string_view task )
{
    using namespace subject_detail;
    const std::vector<std::string_view> words = splitRouteWords( task );
    if( words.size() < 3 || queryshape::classify( task ).fires() )
    {
        return {};
    }
    const bool sentence = task.find( '?' ) != std::string_view::npos || task.find( '`' ) != std::string_view::npos || isQuestionLead( words.front() );
    if( !sentence )
    {
        return {};
    }
    const std::vector<CodeName> names = sentenceCodeNames( ing, task, words );
    bool graphCue = false;
    bool common   = false;
    // the cue words as the sentence spells them, punctuation trimmed ("the path, if any, between ...")
    const auto is = [ & ]( std::size_t k, std::initializer_list<std::string_view> any )
    { return k < words.size() && std::ranges::find( any, std::string_view( routeLower( detail::graphSubjectTrimWord( words[k] ).text ) ) ) != any.end(); };
    for( std::size_t k = 0; k < words.size(); ++k )
    {
        const bool both         = is( k, { "call", "calls" } ) && is( k + 1, { "both" } );
        const bool commonCaller = is( k, { "common" } ) && is( k + 1, { "caller", "callers" } );
        common   = common || both || commonCaller;
        graphCue = graphCue || both || commonCaller || is( k, { "path", "chain", "reach", "reaches" } );
    }
    if( graphCue && names.size() >= 2 && common )
    {
        return "--connect=" + names[0].spelling + "," + names[1].spelling;
    }
    if( graphCue && names.size() >= 2 )
    {
        // the direction as the sentence states it: `from X` is the source and `to X` the destination, so "the path to B from A" is
        // --path=A,B; no marker keeps sentence order, as `A reaches B` reads; two sources or two destinations suggest nothing
        const SentenceWordText read = sentenceWordText( words );
        const auto role = [ & ]( std::string_view spelling )
        {
            for( std::size_t k = 0; k < read.text.size(); ++k )
            {
                if( read.text[k].find( spelling ) != std::string_view::npos )
                {
                    return k > 0 && is( k - 1, { "from" } ) ? -1 : k > 0 && is( k - 1, { "to", "into" } ) ? 1 : 0;
                }
            }
            return 0;
        };
        const int from0 = role( names[0].spelling ), from1 = role( names[1].spelling );
        if( from0 == from1 && from0 != 0 )
        {
            return {};
        }
        const bool swap = from0 == 1 || from1 == -1;
        return "--path=" + names[ swap ? 1 : 0 ].spelling + "," + names[ swap ? 0 : 1 ].spelling;
    }
    if( names.size() == 1 && asksDependentsOf( words, names.front().spelling ) )
    {
        return "--callers=" + names.front().spelling;
    }
    return {};
}

// ANCHOR-TEST-ONLY: does a name-exact route with no source-backed anchor stay committed to it? It does when the anchors name ONE
// definition in all (a test helper, a data key, a CI script that is the only thing by that name: the subject can only mean it) or none
// (an env var or literal the index stores no definition of: the <shortkey> ladder and the <lit> block serve that route). With two or
// more definitions none of which is source, the route picked one non-source copy among several (gtest_threading.cpp's max_threads of
// three, a .github action before the real one): the words' ranking is the honest answer, and the anchors ride on as a hint.
inline bool routeAnchorUncommitted( const RouteChoice& rc )
{
    if( rc.which != LexMode::NameExact || rc.anchorDefs.empty() )
    {
        return false;
    }
    // each distinct anchor name once: a repeated word (`lonely_helper ... lonely_helper`) resolves the same definitions again
    std::size_t defs = 0;
    for( std::size_t i = 0; i < rc.anchorDefs.size(); ++i )
    {
        const RouteAnchorDef& a = rc.anchorDefs[i];
        const auto earlier = rc.anchorDefs.begin() + std::ptrdiff_t( i );
        if( std::find_if( rc.anchorDefs.begin(), earlier, [ & ]( const RouteAnchorDef& b ) { return b.lowerName == a.lowerName; } ) == earlier )
        {
            defs += 1u + a.extraDefs;
        }
    }
    return defs >= 2;
}

// The ranker an uncommitted anchor falls through to: the conceptual one, coded as chooseForRanker codes it for the same word count.
inline RouteChoice routeAnchorFallThrough( std::string_view query, const RouteChoice& anchored )
{
    std::size_t nWords = 0;
    for( const std::string_view w : splitRouteWords( query ) )
    {
        nWords += isRouteStopword( routeLower( w ) ) ? 0 : 1;
    }
    RouteChoice rc;
    rc.which  = LexMode::SubtokenBody;
    rc.reason = nWords >= 3 ? "subtoken+body" : "subtoken+body:broad";
    // the hint: the anchors: evidence as the anchored route printed it (word(defining file+N) per anchor). Not the name-exact(X) code:
    // route= starts with the ranker that ran, and no reader may find a second ranker code in it.
    const std::size_t at = anchored.reason.find( "; anchors: " );
    rc.reason += "; anchor has no source definition (test, doc, data, CI or vendored only, or not indexed), not committed: ranked as words";
    if( at != std::string::npos )
    {
        rc.reason += "; hint " + anchored.reason.substr( at + 2 );
    }
    return rc;
}

// ANCHOR-HONESTY: the identifier-syntax words of a query that place a SOURCE-class definition (Injector.loadProvider, Model.save,
// concurrent.futures.ThreadPoolExecutor), each with those definitions in NodeId order. Asked on name-exact routes only: one placement
// pass for all the words, plus one selector resolution per identifier-syntax word (a short query holds one or two).
struct SourceSyntaxAnchor
{
    std::string_view    word;   // trimmed, as the query spells it
    std::vector<NodeId> defs;   // its source-class placed definitions, never empty
};

// Drop the definitions the outer qualifiers do not place; `*unreadDefs` (optional) counts the ones dropped because their file
// could not be read, so the caller discloses them instead of reading the qualifier as absent (ANCHOR-READ-DISCLOSE).
inline void dropOuterUnplaced( const IngestResult& ing, std::vector<NodeId>& defs, std::string_view outer, std::size_t* unreadDefs )
{
    std::erase_if( defs, [ & ]( NodeId id )
    {
        bool       unread = false;
        const bool drop   = !subject_detail::outerQualifiersPlace( ing, ing.symbols[id], outer, &unread );
        if( drop && unread && unreadDefs != nullptr )
        {
            ++*unreadDefs;
        }
        return drop;
    } );
}

// `*unreadDefs` (optional) counts the placed definitions dropped because their file could not be read (outerQualifiersPlace).
inline std::vector<SourceSyntaxAnchor> sourceSyntaxAnchors( const IngestResult& ing, std::string_view query, std::size_t* unreadDefs = nullptr )
{
    using namespace subject_detail;
    std::vector<std::string_view> words;
    std::vector<Spelling>         spelled;
    for( const std::string_view w : splitRouteWords( query ) )
    {
        const std::string_view t = detail::graphSubjectTrimWord( w ).text;
        if( !hasNameSyntax( t ) )
        {
            continue;
        }
        if( const Spelling sp = parseSpelling( t ); sp.valid )
        {
            words.push_back( t );
            spelled.push_back( sp );
        }
    }
    std::vector<SourceSyntaxAnchor> out;
    if( spelled.empty() )
    {
        return out;
    }
    // the subject reading's placement (leaf + scope or file stem), and the selector verbs' own resolver for the spellings it misses (a
    // TypeScript method carries no scope: `Injector.loadProvider` resolves through its dotted-scope tier)
    std::vector<std::vector<NodeId>> placed = placeCandidates( ing, spelled );
    for( std::size_t k = 0; k < placed.size(); ++k )
    {
        // the placement read only the leaf and the last qualifier: `Missing::Model::save` placed the indexed `Model::save`, so the
        // qualifiers before that one must place the definition too (CodeRabbit 4545021751)
        const std::string_view outer = outerQualifiers( words[k], spelled[k] );
        dropOuterUnplaced( ing, placed[k], outer, unreadDefs );
        for( const NodeId id : resolveAllByNameQualified( ing, words[k] ) )
        {
            if( std::ranges::find( placed[k], id ) == placed[k].end() )
            {
                placed[k].push_back( id );
            }
        }
        std::ranges::sort( placed[k] );
        std::erase_if( placed[k], [ & ]( NodeId id ) { return !sourceClassDef( ing, id ); } );
        if( !placed[k].empty() )
        {
            out.push_back( SourceSyntaxAnchor{ words[k], std::move( placed[k] ) } );
        }
    }
    return out;
}

// The query without the words `drop` selects (sentence order kept), the dropped words that are not route stopwords (the ones a reader
// needs named), and whether any word went at all.
struct QueryWithout
{
    std::string              kept;
    std::vector<std::string> named;
    bool                     anyDropped = false;
};
inline QueryWithout queryWithout( std::string_view query, bool ( *drop )( std::string_view ) )
{
    QueryWithout out;
    for( const std::string_view w : splitRouteWords( query ) )
    {
        const std::string_view t = detail::graphSubjectTrimWord( w ).text;
        if( drop( t ) )
        {
            out.anyDropped = true;
            if( !isRouteStopword( routeLower( t ) ) )
            {
                out.named.emplace_back( t );
            }
            continue;
        }
        out.kept += out.kept.empty() ? "" : " ";
        out.kept += w;
    }
    return out;
}

// ANCHOR-HONESTY: the words a short "what does X call" question frames X with: the call-frame verbs and the question leads. Beside a
// source syntax anchor they are the question, not a second subject: a test-only `call` must not veto X, and a source `invoke` elsewhere
// must not anchor the answer.
inline bool isFrameOrQuestionWord( std::string_view w )
{
    return detail::graphSubjectWordIs( w, { "call", "calls", "invoke", "invokes" } ) || subject_detail::isQuestionLead( w );
}
inline bool isQuestionLeadWord( std::string_view w ) { return subject_detail::isQuestionLead( w ); }

// ANCHOR-HONESTY R1b: a docs-file tie never beats a source definition. An anchor whose word is a source syntax anchor but whose
// resolved definition is not source-class (the reST `.. method:: Model.save` section the whole-name index files first) is re-bound to
// the word's first source-class definition, and the anchors: clause names that file.
inline void preferSourceAnchorDefs( const IngestResult& ing, RouteChoice& rc, const std::vector<SourceSyntaxAnchor>& src )
{
    for( RouteAnchorDef& a : rc.anchorDefs )
    {
        const auto at = std::ranges::find_if( src, [ & ]( const SourceSyntaxAnchor& s ) { return routeLower( s.word ) == a.lowerName; } );
        if( at == src.end() )
        {
            continue;
        }
        bool sourceBound = false;
        for( NodeId id = 0; id < NodeId( ing.symbols.size() ) && !sourceBound; ++id )
        {
            const Symbol& s = ing.symbols[id];
            sourceBound = s.fileId == a.fileId && routeLower( s.name ) == a.lowerName && subject_detail::sourceClassDef( ing, id );
        }
        if( sourceBound )
        {
            continue;
        }
        const Symbol& def = ing.symbols[at->defs.front()];
        const std::string oldEvidence = routeAnchorPath( rootRelPath( ing, a.fileId ) ) + ( a.extraDefs != 0 ? "+" + std::to_string( a.extraDefs ) : "" );
        a = RouteAnchorDef{ routeLower( def.name ), def.fileId, std::uint32_t( at->defs.size() - 1 ) };
        const std::string newEvidence = routeAnchorPath( rootRelPath( ing, a.fileId ) ) + ( a.extraDefs != 0 ? "+" + std::to_string( a.extraDefs ) : "" );
        const std::string from = std::string( at->word ) + "(" + oldEvidence + ")";
        if( const std::size_t pos = rc.reason.find( from ); pos != std::string::npos )
        {
            rc.reason.replace( pos, from.size(), std::string( at->word ) + "(" + newEvidence + ")" );
        }
    }
}

// ANCHOR-HONESTY + WH-WORD-GUARD on a name-exact route whose query holds a source syntax anchor (the rules: tmp B27 RULE.md):
//   R1a the call-frame verbs and question leads leave the ROUTE: the reduced query is routed again and, if still name-exact, replaces
//       it, its reason naming the dropped words;
//   R1b a non-source anchor definition of a source syntax anchor is re-bound to the source one;
//   R2  WH-WORD-GUARD: the question leads leave the RANK query too (a `where` or `what` namesake no longer scores).
// Returns the source syntax anchors it judged by (empty: nothing changed).
inline std::vector<SourceSyntaxAnchor> applyAnchorHonesty( const IngestResult& ing, std::string_view task, SubjectRoute& out )
{
    if( out.route.which != LexMode::NameExact )
    {
        return {};
    }
    const std::string_view          query      = out.rankQuery.empty() ? task : std::string_view( out.rankQuery );
    std::size_t                     unreadDefs = 0;
    std::vector<SourceSyntaxAnchor> src        = sourceSyntaxAnchors( ing, query, &unreadDefs );
    // appended once the route is final, so a name-exact route that replaces it below keeps the disclosure (CodeRabbit 4570578098)
    const auto discloseUnread = [ & ]
    {
        if( unreadDefs != 0 )
        {
            out.route.reason += "; " + std::to_string( unreadDefs ) + " definition(s) not placed: the file is unreadable or over 4 MiB, so "
                                "its outer qualifier was not checked";
        }
    };
    if( src.empty() )
    {
        discloseUnread();
        return src;
    }
    if( out.rankQuery.empty() )
    {
        QueryWithout reduced = queryWithout( query, &isFrameOrQuestionWord );
        if( reduced.anyDropped && !reduced.kept.empty() )
        {
            RouteChoice bare = chooseForRanker( ing, reduced.kept );
            if( bare.which == LexMode::NameExact )
            {
                if( !reduced.named.empty() )
                {
                    bare.reason += subjectDroppedClause( ing, reduced.named );
                }
                out.route     = std::move( bare );
                out.rankQuery = std::move( reduced.kept );   // R2: the question leads rank no longer either
            }
        }
    }
    // R2 WH-WORD-GUARD where R1a left the route alone (no frame word, a flip, or a reduced query that is no longer name-exact)
    {
        const std::string rq    = out.rankQuery.empty() ? std::string( task ) : out.rankQuery;
        QueryWithout      asked = queryWithout( rq, &isQuestionLeadWord );
        if( asked.anyDropped && !asked.kept.empty() )
        {
            out.rankQuery = std::move( asked.kept );
        }
    }
    preferSourceAnchorDefs( ing, out.route, src );
    discloseUnread();
    return src;
}

// THE entry point both the CLI lens and the MCP verbs call in place of chooseForRanker. No reading and a source-backed anchor: exactly
// chooseForRanker. confidence= reads low on anchorNoSource, and route= says why, so the answer explains itself in every legend dialect.
inline SubjectRoute chooseSubjectRoute( const IngestResult& ing, const Graph& g, std::string_view task, bool servesBodiesAndCallers )
{
    SubjectRoute out = chooseSubjectRouteUnchecked( ing, g, task, servesBodiesAndCallers );
    // R1c: a source syntax anchor vouches for the route by itself, whatever plain word resolved beside it
    const bool sourceSyntax = !applyAnchorHonesty( ing, task, out ).empty();
    const std::string_view rankQuery = out.rankQuery.empty() ? task : std::string_view( out.rankQuery );
    out.anchorNoSource = !sourceSyntax && !routeAnchorHasSourceDef( ing, out.route, rankQuery );
    if( out.anchorNoSource && routeAnchorUncommitted( out.route ) )
    {
        out.route = routeAnchorFallThrough( rankQuery, out.route );   // the words rank; no anchorDefs restrict the bodies
    }
    else if( out.anchorNoSource )
    {
        out.route.reason += "; anchor has no source definition (test, doc, data, CI or vendored only, or not indexed)";
    }
    out.anchorKeys = routeAnchorKeys( ing, out.route, rankQuery );
    return out;
}

} // namespace rw
