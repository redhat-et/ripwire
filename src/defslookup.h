#pragma once
// defslookup.h — THE one definition lookup every verb shares (lane D2 DEFS-LOOKUP, PLAN_DEFS_LOOKUP 2026-10-27).
//
// "Which definitions does this name bind?" had three partial answers: the resolver's count (from_defs=7 on --path), the shared
// refusal's file list (selectorrefuse.h, failure only) and MCP find_symbol's def table. lookupDefs answers it once: the shared
// resolver (resolveAllByNameQualified — every spelling a SYM verb accepts), folded into definition groups by defattrib.h's ONE
// grouping rule (a C-family prototype joins the definition it declares; a TS overload joins its implementation), each group
// with the spelling that picks it ALONE (sel=, proven by re-resolving it), its class (the --path test-twin rule) and its
// in-graph caller count (a floor). Consumers: the --defs verb (verbs_navigate.h runDefs) and --path's inline alternatives
// (defAltsXml), which print the other definitions of an endpoint whose pick is not provably unique.
//
// WHAT IT DOES NOT MEAN (checklist 3): a definition the parser does not model (an assignment `x.f = …`, define_method,
// setattr) is no row and is not counted — defs= counts parsed definitions; a JSON/YAML key is never one. in= counts distinct
// graph callers, a floor (declined and unbound calls are not edges). sel_proven="0" says no spelling this lookup tried picks
// that group alone; the sel= it prints then names the group's file and owner and may bind more than it.

#include "defattrib.h"     // DefGroups, defGroupsOf — the ONE definition-group rule
#include "filter.h"        // isTestSymbol, pathTierOf (via pathDefInTests)
#include "graph.h"         // resolveAllByNameQualified — the shared resolver
#include "mapinventory.h"  // isInventoryCodeSymbol — a data Section (doc heading, JSON/YAML key) is no code definition
#include "memberowner.h"   // MemberOwners, qualifiedMemberName — n= as every row spells it
#include "model.h"
#include "nextverb.h"      // nextFlag / nextAttrXml
#include "pathpairs.h"     // pathDefInTests — the one test-path rule --path's twins use
#include "serialize.h"     // escapeXml / jsonStr / symTag

#include <algorithm>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// The house cap for definition groups (defattrib.h kDefTableCap): a page of rows, never a cut — past it the answer pages (next=).
inline constexpr std::size_t kDefRowsCap = kDefTableCap;
// --defs takes at most this many names in one call (one index load).
inline constexpr std::size_t kDefsNamesMax = 16;

struct DefRow
{
    std::uint32_t group     = 0;       // the DefGroups index
    NodeId        rep       = kNoNode; // the group's bodied member (else its first match)
    std::string   sel;                 // the spelling that picks this group alone (when selProven); filled for the printed window only
    bool          selProven = false;   // re-resolving sel binds this group's members and nothing else
    bool          test      = false;   // pathDefInTests: a test/bench file or a test symbol
    std::size_t   callers   = 0;       // distinct in-graph callers over the group's members (a floor)
};

struct DefLookup
{
    std::string_view    spec;
    std::vector<NodeId> matches;          // the resolver's answer, in its order
    DefGroups           groups;
    std::vector<DefRow> rows;             // one per group: source before test, then callers (desc), then path
    std::size_t         unprovenDefs = 0; // the resolver's decl→def residue (graph.h H1), as --path counts it
    std::size_t         dataDefs     = 0; // matches that are data Sections (a doc heading, a JSON/YAML key): not rows, counted

    std::size_t defs() const noexcept { return rows.size(); }
};

namespace defslookup_detail
{
// distinct non-prose callers of `n` in the graph's in-edges (markdown links excluded: a doc naming it is no caller)
inline void collectCallers( const IngestResult& ing, const Graph& g, NodeId n, std::vector<NodeId>& into )
{
    if( n >= g.inEdges.rows() )
    {
        return;
    }
    const auto* ro = g.inEdges.rowOffsets();
    const auto* ci = g.inEdges.colIndices();
    for( auto k = ro[n]; k < ro[ n + 1 ]; ++k )
    {
        const NodeId c = NodeId( ci[k] );
        if( c < ing.symbols.size() && pathTierOf( rootRelPath( ing, ing.symbols[c].fileId ) ) != PathTier::Doc )
        {
            into.push_back( c );
        }
    }
}
// does `spell` resolve to members of group `k` and nothing else?
inline bool picksAlone( const IngestResult& ing, std::string_view spell, const std::vector<NodeId>& members )
{
    const std::vector<NodeId> got = resolveAllByNameQualified( ing, spell );
    return !got.empty() && std::all_of( got.begin(), got.end(), [ & ]( NodeId n ) { return std::find( members.begin(), members.end(), n ) != members.end(); } );
}
}   // namespace defslookup_detail

// THE lookup. `g` supplies the caller counts; sel= is proven for the sorted rows [selBegin, selBegin + selCount) only.
inline DefLookup lookupDefs( const IngestResult& ing, const Graph& g, std::string_view spec, std::size_t selBegin = 0, std::size_t selCount = kDefRowsCap + 1 )
{
    DefLookup out;
    out.spec    = spec;
    out.matches = resolveAllByNameQualified( ing, spec, &out.unprovenDefs );
    const auto data = std::remove_if( out.matches.begin(), out.matches.end(), [ & ]( NodeId n ) { return !isInventoryCodeSymbol( ing.symbols[n] ); } );
    out.dataDefs    = std::size_t( out.matches.end() - data );
    out.matches.erase( data, out.matches.end() );
    if( out.matches.empty() )
    {
        return out;
    }
    out.groups = defGroupsOf( ing, out.matches );
    const MemberOwners owners( ing );
    std::vector<std::vector<NodeId>> members( out.groups.size() );
    for( std::size_t i = 0; i < out.matches.size(); ++i )
    {
        members[ out.groups.ofMatch[i] ].push_back( out.matches[i] );
    }
    out.rows.resize( out.groups.size() );
    std::vector<NodeId> callers;
    for( std::uint32_t k = 0; k < out.groups.size(); ++k )
    {
        DefRow& r = out.rows[k];
        r.group   = k;
        r.rep     = out.groups.rep[k];
        r.test    = pathDefInTests( ing, r.rep );
        callers.clear();
        for( const NodeId m : members[k] )
        {
            defslookup_detail::collectCallers( ing, g, m, callers );
        }
        std::sort( callers.begin(), callers.end() );
        callers.erase( std::unique( callers.begin(), callers.end() ), callers.end() );
        // a member calling itself (recursion) is no outside caller
        r.callers = std::size_t( std::count_if( callers.begin(), callers.end(), [ & ]( NodeId c )
                                                { return std::find( members[k].begin(), members[k].end(), c ) == members[k].end(); } ) );
    }
    std::stable_sort( out.rows.begin(), out.rows.end(), [ & ]( const DefRow& a, const DefRow& b )
    {
        if( a.test != b.test )
        {
            return !a.test;
        }
        if( a.callers != b.callers )
        {
            return a.callers > b.callers;
        }
        const Symbol& sa = ing.symbols[ a.rep ];
        const Symbol& sb = ing.symbols[ b.rep ];
        const std::string_view pa = rootRelPath( ing, sa.fileId ), pb = rootRelPath( ing, sb.fileId );
        return pa != pb ? pa < pb : sa.line < sb.line;
    } );
    // sel= only for the rows a page prints (the window [selBegin, selBegin + selCount) of the sorted rows): each try re-resolves a
    // spelling, and dispose binds 2619 groups on vscode: proving every one measured 69-81 s warm (the callers verb: 30 s) for a 16-row page
    const std::size_t selEnd = std::min( out.rows.size(), selBegin + selCount );
    for( std::size_t i = std::min( selBegin, selEnd ); i < selEnd; ++i )
    {
        // sel=: the shortest spelling the resolver binds to this group alone — the name as given (one group), file:name,
        // file:Owner.name, then the @file:line seed (one definition starting on that line)
        DefRow&                  r     = out.rows[i];
        const Symbol&            s     = ing.symbols[ r.rep ];
        const std::string        file( rootRelPath( ing, s.fileId ) );
        const std::string        owned = qualifiedMemberName( owners, s );
        std::vector<std::string> tries;
        if( out.groups.size() == 1 )
        {
            tries.emplace_back( spec );
        }
        tries.push_back( file + ":" + s.name );
        if( owned != s.name )
        {
            tries.push_back( file + ":" + owned );
        }
        tries.push_back( "@" + file + ":" + std::to_string( s.line ) );
        for( const std::string& t : tries )
        {
            if( defslookup_detail::picksAlone( ing, t, members[ r.group ] ) )
            {
                r.sel       = t;
                r.selProven = true;
                break;
            }
        }
        if( !r.selProven )
        {
            r.sel = file + ":" + owned;
        }
    }
    return out;
}

// One definition row: <d n= t= p= sel= [sel_proven="0"] lang= class= in= [bodyless="1"]/>. `compact` (the --path alternatives)
// keeps only what the next step needs: sel=, p=, class=, decl_only=.
inline void defRowXml( std::string& out, const IngestResult& ing, const DefLookup& L, const DefRow& r, const MemberOwners& owners, bool compact )
{
    std::vector<char> esc;
    const Symbol&     s = ing.symbols[ r.rep ];
    out += "<d";
    if( !compact )
    {
        out += " n=\"" + std::string( escapeXml( qualifiedMemberName( owners, s ), esc ) ) + "\" t=\"" + symTag( s.kind ) + "\"";
    }
    out += " p=\"" + std::string( escapeXml( rootRelPath( ing, s.fileId ), esc ) ) + ":" + std::to_string( s.line ) + "\"";
    out += " sel=\"" + std::string( escapeXml( r.sel, esc ) ) + "\"";
    if( !r.selProven )
    {
        out += " sel_proven=\"0\"";
    }
    if( !compact )
    {
        out += std::string( " lang=\"" ) + langTag( s.lang ) + "\"";
    }
    out += r.test ? " class=\"test\"" : " class=\"source\"";
    if( !compact )
    {
        out += " in=\"" + std::to_string( r.callers ) + "\"";
    }
    if( L.groups.bodyless[ r.group ] )
    {
        out += " decl_only=\"1\"";   // compact too: a header declaration of the bound definition is no second definition
    }
    out += "/>";
}

inline void defRowJson( std::string& out, const IngestResult& ing, const DefLookup& L, const DefRow& r, const MemberOwners& owners )
{
    const Symbol& s = ing.symbols[ r.rep ];
    out += "{\"n\":\"" + jsonStr( qualifiedMemberName( owners, s ) ) + "\",\"t\":\"" + symTag( s.kind ) + "\",\"p\":\""
         + jsonStr( rootRelPath( ing, s.fileId ) ) + ":" + std::to_string( s.line ) + "\",\"sel\":\"" + jsonStr( r.sel ) + "\"";
    if( !r.selProven )
    {
        out += ",\"sel_proven\":0";
    }
    out += std::string( ",\"lang\":\"" ) + langTag( s.lang ) + "\",\"class\":\"" + ( r.test ? "test" : "source" ) + "\",\"in\":"
         + std::to_string( r.callers );
    if( L.groups.bodyless[ r.group ] )
    {
        out += ",\"decl_only\":1";
    }
    out += "}";
}

// Is the pick a verb made among these definitions provably unique? Only when one candidate group is left: the groups less the
// untied C-family prototypes (defattrib.h candidateGroupCount — the rule --path's own endpointDefinitionCount uses, so the
// answer never calls an endpoint bound and unique while <alts> lists a prototype as another definition). Several candidates: the
// resolver's binding is a choice, not a proof (attrib-multidef).
inline bool defPickProvablyUnique( const DefLookup& L ) noexcept { return candidateGroupCount( L.groups ) <= 1; }

// The definitions a --path answer already prints, as the --path answer's own rows name them: the root's from_p=/to_p= are the
// first pair's, and every printed <pair>/<alt> row carries its own (pathpairs.h emitPathPairs). Listing one again under <alts>
// tells the agent nothing new. (The body elements' definitions join in pathAltsOf.)
inline std::vector<NodeId> pathPrintedEnds( const PathPairs& pp )
{
    std::vector<NodeId> ends;
    if( pp.active() )
    {
        const std::size_t printed = std::min( pp.pairs.size(), kPathPairChains + kPathPairAltRows );
        for( std::size_t i = 0; i < printed; ++i )
        {
            if( !pp.pairs[i].chain.empty() )
            {
                ends.push_back( pp.pairs[i].chain.front() );
                ends.push_back( pp.pairs[i].chain.back() );
            }
        }
    }
    return ends;
}

struct PathAlts
{
    std::string xml;
    bool        declOnly = false;   // some printed row is decl_only=1 (its legend reading rides)
    bool        unproven = false;   // some printed row is sel_proven="0": its sel= may bind more than that row (the legend says so)
    bool        any() const noexcept { return !xml.empty(); }
};

// --path's inline alternatives for one endpoint (part 5): every definition the answer does NOT already show, up to the cap,
// compact rows, then alts_shown=K defs=N next=--defs=NAME --offset=M when more exist (M: the first row not yet shown). Empty when the pick is provably unique or
// nothing is left to tell (0 bytes added). Not alternatives: the bound definition, a definition the answer prints as a pair
// endpoint (`printed`), an untied C-family prototype (not a second candidate, as endpointDefinitionCount counts it).
// `bound`: the definition the answer bound (kNoNode when it bound none: every candidate group is then an alternative).
inline void defAltsXml( PathAlts& acc, const IngestResult& ing, const DefLookup& L, NodeId bound, std::string_view side, std::span<const NodeId> printed )
{
    if( defPickProvablyUnique( L ) )
    {
        return;
    }
    std::vector<char> skip( L.groups.size(), 0 );
    for( std::size_t i = 0; i < L.matches.size(); ++i )
    {
        if( L.matches[i] == bound || std::find( printed.begin(), printed.end(), L.matches[i] ) != printed.end() )
        {
            skip[ L.groups.ofMatch[i] ] = 1;
        }
    }
    const MemberOwners owners( ing );
    std::string        rows;
    std::size_t        shown = 0, total = 0, nextOffset = 0;
    for( std::size_t i = 0; i < L.rows.size(); ++i )
    {
        const DefRow& r = L.rows[i];
        if( skip[ r.group ] || L.groups.untied[ r.group ] )
        {
            continue;
        }
        ++total;
        // sel= is computed for the first kDefRowsCap + 1 sorted rows only (lookupDefs selCount): with two or more rows skipped above, the
        // 16th alternative can sit past that window and carry no sel= at all; it pages via next= instead (nextOffset follows the printed rows)
        if( shown < kDefRowsCap && !r.sel.empty() )
        {
            defRowXml( rows, ing, L, r, owners, /*compact=*/true );
            acc.declOnly = acc.declOnly || L.groups.bodyless[ r.group ];
            acc.unproven = acc.unproven || !r.selProven;
            ++shown;
            nextOffset = i + 1;   // --defs lists the same sorted rows: the ones not shown yet start right after the last one shown
        }
    }
    if( total == 0 )
    {
        return;
    }
    std::vector<char> esc;
    std::string out = "<alts side=\"" + std::string( side ) + "\" of=\"" + std::string( escapeXml( L.spec, esc ) ) + "\"";
    if( shown < total )
    {
        out += " alts_shown=\"" + std::to_string( shown ) + "\" defs=\"" + std::to_string( L.defs() ) + "\""
             + nextAttrXml( nextFlag( "--defs=", L.spec ) + " --offset=" + std::to_string( nextOffset ) );   // past page 1, never a replay of it
    }
    acc.xml += out + ">" + rows + "</alts>";
}

// Both --path transports (verbs_navigate.h runPathServed, mcpverbs.h pathText): the two endpoints' <alts>, from= first. A glob endpoint
// stands for every fitting definition by design (from_glob=), so it lists none. `bodyIds`: the definitions the answer's <bodies of=hops>
// / <bodies of=route> elements rendered (RouteBodiesXml::ids), so an alternative is never listed beside its own printed body.
inline PathAlts pathAltsOf( const IngestResult& ing, const Graph& g, std::string_view srcN, std::string_view dstN, bool srcGlob, bool dstGlob,
                            NodeId srcBound, NodeId dstBound, const PathPairs& pairs, std::span<const NodeId> bodyIds )
{
    PathAlts            out;
    std::vector<NodeId> printed = pathPrintedEnds( pairs );
    printed.insert( printed.end(), bodyIds.begin(), bodyIds.end() );   // a <bodies of=hops|route> body is a definition the answer prints too
    if( !srcGlob )
    {
        defAltsXml( out, ing, lookupDefs( ing, g, srcN ), srcBound, "from", printed );
    }
    if( !dstGlob )
    {
        defAltsXml( out, ing, lookupDefs( ing, g, dstN ), dstBound, "to", printed );
    }
    return out;
}

// The legend clause for <alts> — present only when an answer carries one.
inline std::string defAltsLegend( const PathAlts& alts )
{
    if( !alts.any() )
    {
        return {};
    }
    return std::string( "<alts side= of=> lists further definitions the endpoint's name binds, not printed above (the pick is "
                        "not provably unique): sel= pastes as that endpoint to bind one alone" )
         + ( alts.unproven ? ", except on a sel_proven=0 row: no spelling tried binds that one alone, its sel= names the file and owner and may bind more" : "" )
         + ", p= where it is, class=source|test; alts_shown=K defs=N: K of the other rows shown, next= pages the rest. "
         + ( alts.declOnly ? "decl_only=1: no body (a header declaration or interface contract), not a second definition. " : "" );
}

}   // namespace rw
