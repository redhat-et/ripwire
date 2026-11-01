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
// WHAT A PLAIN WORD THAT REALLY IS A SYMBOL GETS. It is dropped like any other word, beside a proven name, and the route prints its
// count: "dropped: emit(102-defs) new(41-defs) argument". To ask about emit, the subject is `emit`, which routes as it always did.
//
// WHAT THE READING DOES, by what chooseForRanker made of the whole subject:
//   * name-exact, with a plain word among its anchors: the words are dropped. Always; that anchor was never true, on a question too,
//     and with a test-only symbol too (CONFIDENCE-ANCHOR reads that answer low).
//   * declined for a word: the route is the one the names alone get, when the subject is DESCRIPTIVE (no question lead, at most
//     kSubjectMaxPlainWords plain content words) and names ONE exact symbol with a source-class definition. rankQuery carries the names, so
//     the answer is the bare symbol's plus the dropped: clause.
//   * any other route, same two conditions: the conceptual answer stands, every byte, and <callers by="subject"> rides on top
//     (verbs_for.h). The prose words there are real retrieval terms and the ranked map may hold the answer, so nothing is taken.

#include "filter.h"            // isTestSymbol, pathTierOf
#include "infra/namesplit.h"   // hasIdentifierShape, isIdentChar
#include "langfacts.h"         // langFacts().notCode
#include "lexical.h"           // chooseForRanker, RouteChoice, parseGraphSubject, isRouteStopword, kMaxAnchorDefs
#include "mention.h"           // mention_detail::qualifierPlaces — the ONE "does this qualifier place this symbol" test
#include "model.h"
#include "queryshape.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
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
    bool                            sourceDef   = false;   // one exact symbol has a source-class definition
    bool                            descriptive = false;   // no question lead, and few enough plain words: not prose
};

// What a --for or MCP route uses: the route, and the query the ranker and the mention anchor read.
struct SubjectRoute
{
    RouteChoice         route;
    std::string         rankQuery;     // non-empty only when the words were dropped from the route
    std::vector<std::vector<NodeId>> callerCandidates;   // conceptual route: each exact symbol's definitions, for <callers by="subject">
    bool                anchorNoSource = false;   // CONFIDENCE-ANCHOR: name-exact, and no source-class definition backs the anchor
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
    return !w.empty() && w.front() != '-' && w.find( '/' ) == std::string_view::npos
        && ( namesplit::hasIdentifierShape( w ) || w.find( "::" ) != std::string_view::npos || w.find( '.' ) != std::string_view::npos );
}

// a question opens with one of these
inline bool isQuestionLead( std::string_view w )
{
    return detail::graphSubjectWordIs( w, { "which", "where", "how", "what", "why", "who", "when", "does", "do", "is", "are", "can", "should", "will" } );
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
    r.descriptive = !isQuestionLead( words.front() ) && r.dropped.size() <= kSubjectMaxPlainWords;
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
    std::vector<std::string> leaves;
    for( const std::string_view w : splitRouteWords( rankQuery ) )
    {
        const std::string_view t = detail::graphSubjectTrimWord( w ).text;
        if( const Spelling sp = parseSpelling( t ); sp.valid )
        {
            leaves.push_back( routeLower( sp.leaf ) );
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
    const auto named = [ & ]( const Symbol& s )
    {
        if( rc.anchorDefs.empty() )
        {
            return std::ranges::any_of( leaves, [ & ]( const std::string& l ) { return l.size() == s.name.size() && l == routeLower( s.name ); } );
        }
        return std::ranges::any_of( rc.anchorDefs, [ & ]( const RouteAnchorDef& a )
                                    { return a.fileId == s.fileId && a.lowerName.size() == s.name.size() && a.lowerName == routeLower( s.name ); } );
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

// The route the subject reading picks, before the CONFIDENCE-ANCHOR check.
inline SubjectRoute chooseSubjectRouteUnchecked( const IngestResult& ing, std::string_view task )
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
    // Two exact symbols on a declined route ("add a UrlSerializer parameter to createSegmentGroupFromRoute") name no ONE anchor, and
    // name-exact would serve neither's callers: the conceptual answer stands with the first function's callers on top.
    if( subjectAnchoredPlainWord( ing, out.route, reading ) || ( declined && lift && reading.exact.size() == 1 ) )
    {
        RouteChoice bare = chooseForRanker( ing, reading.reduced );
        // A flip from a declined route gives up the conceptual map, so the definition the anchor would SERVE must be source-class, not
        // merely some definition of the name: the anchor binds the first body-carrying one in path order, and that can be a CI or
        // vendored copy. A name-exact route had no map to lose, and CONFIDENCE-ANCHOR reads that answer low.
        if( bare.which == LexMode::NameExact && ( !declined || routeAnchorHasSourceDef( ing, bare, reading.reduced ) ) )
        {
            bare.reason += subjectDroppedClause( ing, reading.dropped );
            out.route     = std::move( bare );
            out.rankQuery = std::move( reading.reduced );
            return out;
        }
    }
    if( lift && out.route.which != LexMode::NameExact )
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
inline SubjectRoute chooseSubjectRoute( const IngestResult& ing, std::string_view task )
{
    SubjectRoute out = chooseSubjectRouteUnchecked( ing, task );
    out.anchorNoSource = !routeAnchorHasSourceDef( ing, out.route, out.rankQuery.empty() ? task : std::string_view( out.rankQuery ) );
    if( out.anchorNoSource )
    {
        out.route.reason += "; anchor has no source definition (test, doc, data, CI or vendored only, or not indexed)";
    }
    return out;
}

} // namespace rw
