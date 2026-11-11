#pragma once
// forreadercallers.h — READER-CALLERS: who drives the code that reads a literal (ORCH reports/ideas-opus-1111.md C1 READER-CALLERS and
// reports/ideas-fable-1111.md LIT-READER-UP; C8 THROW-SITE folded in).
//
// WHY. A --for task naming a bare setting, env var, flag or message gets a <lit> block (forliteral.h) whose <ls> rows name the function
// that reads it: `get_plugins` for PYDANTIC_DISABLE_PLUGINS, `Reader::ReadSource` for FZF_DEFAULT_COMMAND, `tty_keys_next` for tmux's
// escape-time. The question ("which validators does it affect", "under what conditions is it used", "what does it change at runtime")
// is answered one or two calls UP from that reader, and nothing printed it: measured on mf2-pydantic-05, mf1-fzf-05 and mf1-tmux-04,
// `--callers` of the printed reader is exactly the missing item (ORCH tmp/reader-callers/RULE.md).
//
// WHAT. Inside <lit>, after its bodies: <lc d= of= n= t= p=> rows, the proven callers of the element's readers.
//   * readers: the distinct callable (fn/method) owners of the shown <ls> rows, in row order, at most kReaderCallerReaders;
//   * a caller is a call-graph in-neighbour (Graph::inEdges) that is callable (never a file or module scope), in a source path (not a
//     test, bench or doc path), not the node itself, not a reader and not a row already printed, on a plain call edge (never a markdown
//     link). An edge bound by NAME ALONE is kept only when the node's name has exactly one callable definition in the index (the name
//     binds nowhere else); its row says via="name". Order: path, line, id;
//   * d="1" the callers of each reader; d="2" the callers of a d=1 caller when its reader has exactly one caller (a funnel), or when the
//     d=1 caller is a constructor (THROW-SITE: a message built in an exception's constructor is raised where the class is constructed);
//   * a constructor (forctorhop.h ctor_detail::isCtorName on its owner class) hops to its class: the class node's callers (the `new`
//     sites) and its own; its row says ctor="1";
//   * fan-in gate: a node with more than kReaderCallerFanIn kept callers lists none, one <lcn of= n= next="--callers=…"/> says how many;
//     a constructor's n= counts its class's construction sites too, which its own --callers does not list: class_next="--callers=Class"
//   * at most kReaderCallerRows <lc> rows per element; past it one <lcn more=/> counts the rest; readers past kReaderCallerReaders that
//     have a kept caller are counted by readers_more= on that same closing <lcn/>.
// Nothing enters the ranked rows; the rows sit inside <lit>, so its bytes= counts them. RIPWIRE_NO_READER_CALLERS (any value) turns it off.

#include "forctorhop.h"        // ctor_detail::isCtorName — the language's constructor spelling
#include "filter.h"            // pathTierOf
#include "graph.h"
#include "hopbody.h"           // fold_detail::spanInside
#include "model.h"
#include "nextverb.h"          // nextFlag / nextAttrXml
#include "receiverevidence.h"  // ReceiverEvidence::callableKind / classLike
#include "serialize.h"         // escapeXml

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <vector>

namespace rw
{
inline constexpr std::size_t kReaderCallerReaders = 3;    // reader owners walked, in row order (the lit's own body cap)
inline constexpr std::size_t kReaderCallerFanIn   = 6;    // a node with more kept callers lists none (a hub: <lcn n=>)
inline constexpr std::size_t kReaderCallerRows    = 12;   // <lc> rows per <lit>
static_assert( kReaderCallerReaders == 3 && kReaderCallerFanIn == 6 && kReaderCallerRows == 12, "kReaderCallersLegend states the three caps: move the sentence with the constants" );

inline bool readerCallersOn()
{
    return std::getenv( "RIPWIRE_NO_READER_CALLERS" ) == nullptr;
}

inline constexpr std::string_view kReaderCallersLegend =
    "<!-- ripwire for lit callers: lc d=1 a call-graph caller of= a reader above (an ls row's in=), d=2 its caller when that reader has one caller or "
    "of= is a constructor (ctor=1: its hop is the class's construction sites); n= t= p=file:line the caller, source paths only; via=name bound by "
    "name alone, the name has one definition. lcn n= a node with more than 6 callers (none listed, next=; a constructor's n= counts its class's "
    "construction sites, class_next= lists them), more= rows past the 12-row cap, readers_more= readers past the first 3 with callers, not walked. -->";
static_assert( kReaderCallersLegend.find( "--", 4 ) == kReaderCallersLegend.size() - 3, "the only double hyphen in a legend comment is its closing" );

struct ReaderCallers
{
    std::string xml;    // the <lc>/<lcn> rows ("" when none)
    std::size_t rows = 0;
};

namespace readercallers_detail
{
// the innermost class/struct of `id`'s file whose span holds it (kNoNode: none); `named` non-empty: only a class of that name
inline NodeId ownerClassOf( const IngestResult& ing, NodeId id, std::string_view named = {} )
{
    const Symbol& s    = ing.symbols[id];
    NodeId        best = kNoNode;
    for( NodeId c = 0; c < NodeId( ing.symbols.size() ); ++c )
    {
        const Symbol& cs = ing.symbols[c];
        if( cs.fileId == s.fileId && ReceiverEvidence::classLike( cs.kind ) && ( named.empty() || cs.name == named ) && fold_detail::spanInside( ing, id, c )
            && ( best == kNoNode || fold_detail::spanInside( ing, c, best ) ) )
        {
            best = c;
        }
    }
    return best;
}

// `id` is a constructor: its owner class node (same file, the innermost class holding it; named as its scope says when it has one), else kNoNode
inline NodeId ctorClassOf( const IngestResult& ing, NodeId id )
{
    const Symbol&          s     = ing.symbols[id];
    const std::string_view scope = scopeLastSegment( s.scope );
    if( !ReceiverEvidence::callableKind( s.kind ) )
    {
        return kNoNode;
    }
    const NodeId cls = ownerClassOf( ing, id, scope );   // a TS/JS member carries no scope: the class holding it names it
    return cls != kNoNode && ctor_detail::isCtorName( s.lang, s.name, ing.symbols[cls].name ) ? cls : kNoNode;
}

// the number of callable definitions named `name` (stops counting at 2: only "one" matters)
inline std::size_t callableDefsNamed( const IngestResult& ing, std::string_view name )
{
    std::size_t n = 0;
    for( const Symbol& s : ing.symbols )
    {
        if( s.name == name && ReceiverEvidence::callableKind( s.kind ) && ++n > 1 )
        {
            break;
        }
    }
    return n;
}

struct Walk
{
    const IngestResult& ing;
    const Graph&        g;
    std::vector<NodeId> printed;   // readers and rows: never a row again

    // the kept callers of `target` (an in-edge from a callable source-path symbol), deduped, in (path, line, id) order
    void keptCallersInto( NodeId target, NodeId named, std::vector<std::pair<NodeId, bool>>& out ) const
    {
        if( std::size_t( target ) >= g.inEdges.rows() )
        {
            return;
        }
        const auto* ro = g.inEdges.rowOffsets();
        const auto* ci = g.inEdges.colIndices();
        int uniqueName = -1;   // lazily: does `named`'s name have one callable definition
        for( std::uint32_t e = ro[target]; e < ro[target + 1]; ++e )
        {
            const NodeId c = ci[e];
            if( std::size_t( c ) >= ing.symbols.size() || c == target || c == named || std::ranges::contains( printed, c ) )
            {
                continue;
            }
            const Symbol& cs = ing.symbols[c];
            if( !ReceiverEvidence::callableKind( cs.kind ) || pathTierOf( rootRelPath( ing, cs.fileId ) ) != PathTier::Source
                || edgeNameOnlyInCsr( g.outOff, g.outTargets, g.outNameOnly, c, target, kEdgeLink ) )
            {
                continue;
            }
            const bool byName = edgeNameOnlyInCsr( g.outOff, g.outTargets, g.outNameOnly, c, target, kEdgeName );
            if( byName )
            {
                if( uniqueName < 0 )
                {
                    uniqueName = callableDefsNamed( ing, ing.symbols[target].name ) == 1 ? 1 : 0;
                }
                if( uniqueName == 0 )
                {
                    continue;   // a name-only edge to a name with several definitions: unproven, never a row
                }
            }
            const auto it = std::find_if( out.begin(), out.end(), [ & ]( const auto& p ) { return p.first == c; } );
            if( it == out.end() )
            {
                out.emplace_back( c, byName );
            }
            else
            {
                it->second = it->second && byName;   // one plain edge proves the pair
            }
        }
    }

    // the callers of `id` (a constructor: of its class too), in (path, line, id) order
    std::vector<std::pair<NodeId, bool>> callersOf( NodeId id ) const
    {
        std::vector<std::pair<NodeId, bool>> out;
        keptCallersInto( id, id, out );
        const NodeId cls = ctorClassOf( ing, id );
        if( cls != kNoNode )
        {
            keptCallersInto( cls, cls, out );
        }
        std::sort( out.begin(), out.end(), [ & ]( const auto& a, const auto& b )
                   {
                       const Symbol& x = ing.symbols[a.first];
                       const Symbol& y = ing.symbols[b.first];
                       return std::tuple( rootRelPath( ing, x.fileId ), x.line, a.first ) < std::tuple( rootRelPath( ing, y.fileId ), y.line, b.first );
                   } );
        return out;
    }
};

// the <ls in=> spelling (search.h grepEnrich: scope::name); a member with no scope (TS/JS) is named by the class holding it
inline std::string chainOf( const IngestResult& ing, NodeId id )
{
    const Symbol& s = ing.symbols[id];
    if( !s.scope.empty() )
    {
        return s.scope + "::" + s.name;
    }
    const NodeId cls = s.kind == SymKind::Method ? ownerClassOf( ing, id ) : kNoNode;
    return cls == kNoNode ? s.name : ing.symbols[cls].name + "::" + s.name;
}
}   // namespace readercallers_detail

// THE ROWS. `readers` = the callable owners of the shown <ls> rows, in row order; `relPath` the lit's p= spelling.
template <class RelPath>
inline ReaderCallers renderReaderCallers( const IngestResult& ing, const Graph* g, std::span<const NodeId> readers, const RelPath& relPath, std::vector<char>& esc )
{
    using namespace readercallers_detail;
    ReaderCallers out;
    if( g == nullptr || readers.empty() || !readerCallersOn() )
    {
        return out;
    }
    Walk        walk{ ing, *g, std::vector<NodeId>( readers.begin(), readers.end() ) };
    std::size_t more = 0;
    const auto  row  = [ & ]( int d, NodeId of, NodeId c, bool byName )
    {
        walk.printed.push_back( c );
        if( out.rows >= kReaderCallerRows )
        {
            ++more;
            return;
        }
        const Symbol& s = ing.symbols[c];
        out.xml += "<lc d=\"" + std::to_string( d ) + "\" of=\"";
        out.xml += escapeXml( chainOf( ing, of ), esc );
        out.xml += "\" n=\"";
        out.xml += escapeXml( chainOf( ing, c ), esc );
        out.xml += "\" t=\"";
        out.xml += symTag( s.kind );
        out.xml += "\" p=\"";
        out.xml += escapeXml( relPath( s.fileId ), esc );
        out.xml += ":" + std::to_string( s.line ) + "\"";
        out.xml += ctorClassOf( ing, c ) != kNoNode ? " ctor=\"1\"" : "";
        out.xml += byName ? " via=\"name\"" : "";
        out.xml += "/>";
        ++out.rows;
    };
    const auto hub = [ & ]( NodeId of, std::size_t n )
    {
        out.xml += "<lcn of=\"";
        out.xml += escapeXml( chainOf( ing, of ), esc );
        out.xml += "\" n=\"" + std::to_string( n ) + "\"";
        const Symbol& s     = ing.symbols[of];
        const NodeId  cls   = s.scope.empty() && s.kind == SymKind::Method ? ownerClassOf( ing, of ) : kNoNode;
        const std::string_view owner = cls != kNoNode ? std::string_view( ing.symbols[cls].name ) : scopeLastSegment( s.scope );
        out.xml += nextAttrXml( nextFlag( "--callers=", owner.empty() ? s.name : std::string( owner ) + "." + s.name ) );   // the selector spelling Owner.name
        const NodeId ctorCls = ctorClassOf( ing, of );
        if( ctorCls != kNoNode )
        {
            out.xml += nextAttrXml( nextFlag( "--callers=", ing.symbols[ctorCls].name ), "class_next" );   // n= counted the class's in-edges too
        }
        out.xml += "/>";
    };
    for( std::size_t r = 0; r < readers.size() && r < kReaderCallerReaders; ++r )
    {
        const NodeId reader = readers[r];
        if( std::size_t( reader ) >= ing.symbols.size() )
        {
            continue;
        }
        const std::vector<std::pair<NodeId, bool>> d1 = walk.callersOf( reader );
        if( d1.size() > kReaderCallerFanIn )
        {
            hub( reader, d1.size() );
            continue;
        }
        for( const auto& [c, byName] : d1 )
        {
            row( 1, reader, c, byName );
        }
        for( const auto& [c, byName] : d1 )
        {
            if( d1.size() != 1 && ctorClassOf( ing, c ) == kNoNode )
            {
                continue;   // d=2 only above a funnel (the reader's one caller) or a constructor
            }
            const std::vector<std::pair<NodeId, bool>> d2 = walk.callersOf( c );
            if( d2.size() > kReaderCallerFanIn )
            {
                hub( c, d2.size() );
                continue;
            }
            for( const auto& [c2, byName2] : d2 )
            {
                row( 2, c, c2, byName2 );
            }
        }
    }
    std::size_t readersMore = 0;   // readers past kReaderCallerReaders with a caller not printed above: not walked, counted (CR 4540061421)
    for( std::size_t r = kReaderCallerReaders; r < readers.size(); ++r )
    {
        readersMore += std::size_t( readers[r] ) < ing.symbols.size() && !walk.callersOf( readers[r] ).empty() ? 1 : 0;
    }
    if( more > 0 || readersMore > 0 )
    {
        out.xml += "<lcn";
        out.xml += more > 0 ? " more=\"" + std::to_string( more ) + "\"" : std::string();
        out.xml += readersMore > 0 ? " readers_more=\"" + std::to_string( readersMore ) + "\"" : std::string();
        out.xml += "/>";
    }
    return out;
}
}   // namespace rw
