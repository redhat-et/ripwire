#pragma once
// forfilesyms.h — K-WRONGSYM (cause K "right file, wrong symbol"): a --for answer that shows the right FILE often shows the wrong
// SYMBOL of it — the head row is a neighbour that ranked on body or doc text, while the function the task needs sits a few lines
// away, unnamed. <syms> names a few of those unshown symbols, one row each (Scope.name and file:line, no body), after the
// ordinary answer. (CLI src/verbs_for.h appendForFileSyms, MCP `for` src/mcpverbs.h forTaskText — one renderer.)
//
// WHICH FILES. The answer's own shown files: the distinct p= of its <d>, <b> and <t> rows in answer order, the first
// kForFileSymsFiles. A candidate is an indexed definition of one of them (no doc heading or data key, no module scope, no field;
// a function-local def counts: TypeScript's checker.ts holds its API inside one function) whose NAME is not already a word anywhere in the answer (it is shown, called in a shown body, or echoed).
// TWO RULES, each row says which picked it (by=):
//   by="name"   its name's subtokens share a word with the task (identifier split, light stem, stopwords out); most shared first.
//   by="callee" a definition NAMED like a head row (the first kForFileSymsHeadRows <d> rows, any file) calls, in the index's graph,
//               a definition NAMED like it: the shown row or a namesake, since the row's name is what the answer gave (Stage 0: NullInjector.get is shown, the
//               R3Injector.get beside it is the one that calls augmentRuntimeError). Most head names first. The hedge reuses the call
//               rows' spellings (graphlegend.h): plain only when the shown row itself calls this very definition over an evidence-bound
//               edge; prov="split" when that call is one arm of a split; via="name" otherwise (a namesake's call, a call to a namesake
//               of it, or one bound by name alone).
// Ties: fan-in (graph callers) desc, then shown-file order, then name. kForFileSymsRowsPerRule rows per rule (a runaway cap: name= /
// callee= count the rows shown; name_capped="1" name_total= / callee_capped="1" callee_total= when the cap cut them). A name both rules pick prints
// once, as by="name".
// PRESENT-ONLY: no candidate scores, no block. A token budget holds it (held="budget", next= the same --for call without the
// budget). The block is outside est_tokens, after every byte of the ordinary answer: no auto-served body pays for it.
#include "infra/namesplit.h" // namesplit::isIdentChar — the one identifier-byte test
#include "graph.h" // Graph::outOff / outTargets / outNameOnly / outProv / inEdges, edgeKindByte, kEdgeName
#include "lexical.h" // subtokens — the one identifier splitter
#include "memberowner.h" // MemberOwners, qualifiedMemberName — the Scope.name spelling every row kind shares
#include "model.h"
#include "nextverb.h" // nextFlag / nextAttrXml
#include "serialize.h" // escapeXml

#include <algorithm>
#include <array>
#include <bit>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <format>
#include <string>
#include <string_view>
#include <tuple>
#include <vector>

namespace rw
{
// Runaway guards and reading scope (knob census ADDENDUM 2026-11-05, lane k-wrongsym); each is said on the block or in its legend.
inline constexpr std::size_t kForFileSymsFiles = 6; // shown files whose symbols are candidates (files= on the block)
inline constexpr std::size_t kForFileSymsHeadRows = 8; // head <d> rows whose callees by="callee" reads (head= on the block)
inline constexpr std::size_t kForFileSymsRowsPerRule = 3; // rows per rule (name= / callee=, *_total= when cut)

inline bool forFileSymsOn()
{
    return std::getenv( "RIPWIRE_NO_FILE_SYMS" ) == nullptr;
}

inline constexpr std::string_view kForFileSymsLegend =
    "<!-- ripwire for syms: symbols of the answer's first files= shown files that it does not name, one <y> row each (p=file:line, n= the owner-qualified name; no body, the expand verb serves one): "
    "by=\"name\" its name shares a task word, by=\"callee\" a definition named like one of the first head= <d> rows calls one named like it (via=\"name\": "
    "no evidence-bound call from the shown row to this definition, only a namesake's call, a call to a namesake or one bound by name alone; prov=\"split\": one arm of a split call); name= callee= rows shown, *_capped=\"1\" *_total= the candidates (files_total= the shown files) when a cap cut them; "
    "not in est_tokens -->";
inline constexpr std::string_view kForFileSymsLegendCompact =
    "<!-- syms: unnamed symbols of the first files= shown files, y p=file:line n=Owner.name; by=name task word, by=callee a head= <d> row or its namesake calls it or its namesake (via=name: "
    "by name alone); *_capped=1 *_total= when cut; not in est_tokens -->";

namespace filesyms_detail
{
// The measured stopword list (reports/k-wrongsym.md Stage 0, tmp angles.py): English glue a task carries that no name means.
inline constexpr std::array<std::string_view, 60> kStop {
    "the", "and", "for", "with", "from", "that", "this", "what", "which", "where", "when", "how", "does", "are", "was",
    "were", "into", "its", "their", "then", "than", "there", "here", "who", "why", "can", "not", "but", "all", "any",
    "has", "have", "had", "will", "would", "should", "could", "get", "set", "use", "used", "uses", "using", "via",
    "per", "new", "add", "make", "made", "like", "each", "also", "only", "just", "your", "you", "our", "out", "it's", "itself"
};

// A light suffix stem (ing, ies→y, es, ed, s) so `failed` meets `fail` and `integrations` meets `integration`.
inline std::string lightStem( std::string w )
{
    static constexpr std::array<std::string_view, 5> kSuf { "ing", "ies", "es", "ed", "s" };
    for( const std::string_view suf : kSuf )
    {
        if( w.size() > suf.size() + 2 && std::string_view( w ).ends_with( suf ) )
        {
            w.resize( w.size() - suf.size() );
            if( suf == "ies" )
            {
                w += 'y';
            }
            return w;
        }
    }
    return w;
}

// The words of `text` that can match a name: identifier subtokens of 3+ bytes, stopwords out, stemmed; sorted unique.
inline std::vector<std::string> matchWords( std::string_view text )
{
    std::vector<std::string> raw;
    subtokens( text, raw );
    std::vector<std::string> out;
    for( std::string& w : raw )
    {
        if( w.size() >= 3 && !std::ranges::contains( kStop, std::string_view( w ) ) )
        {
            out.push_back( lightStem( std::move( w ) ) );
        }
    }
    std::ranges::sort( out );
    out.erase( std::unique( out.begin(), out.end() ), out.end() );
    return out;
}

inline std::size_t sharedWords( const std::vector<std::string>& a, const std::vector<std::string>& b )
{
    std::size_t n = 0;
    for( auto i = a.begin(), j = b.begin(); i != a.end() && j != b.end(); )
    {
        const int c = i->compare( *j );
        n += c == 0 ? 1 : 0;
        i += c <= 0 ? 1 : 0;
        j += c >= 0 ? 1 : 0;
    }
    return n;
}


// Every whole word of the answer (markup, legend, bodies and all), sorted unique: a candidate whose name is one is already named.
inline std::vector<std::string_view> answerWords( std::string_view text )
{
    std::vector<std::string_view> out;
    for( std::size_t i = 0; i < text.size(); )
    {
        if( !namesplit::isIdentChar( text[i] ) )
        {
            ++i;
            continue;
        }
        std::size_t j = i;
        while( j < text.size() && namesplit::isIdentChar( text[j] ) )
        {
            ++j;
        }
        out.push_back( text.substr( i, j - i ) );
        i = j;
    }
    std::ranges::sort( out );
    out.erase( std::unique( out.begin(), out.end() ), out.end() );
    return out;
}

// The five XML entities the answer escapes, decoded (a name like `operator<` or a path with `&`).
inline std::string unescapeXmlAttr( std::string_view v )
{
    static constexpr std::array<std::pair<std::string_view, char>, 5> kEnt {
        { { "&lt;", '<' }, { "&gt;", '>' }, { "&amp;", '&' }, { "&quot;", '"' }, { "&apos;", '\'' } }
    };
    std::string out;
    out.reserve( v.size() );
    for( std::size_t i = 0; i < v.size(); )
    {
        const auto ent = v[i] == '&' ? std::ranges::find_if( kEnt, [&]( const auto& e )
                                                             { return v.substr( i ).starts_with( e.first ); } )
                                     : kEnt.end();
        if( ent != kEnt.end() )
        {
            out += ent->second;
            i += ent->first.size();
            continue;
        }
        out += v[i++];
    }
    return out;
}

// The value of ` name="…"` inside one tag's attribute text, or "" (the answer's own markup: no attribute holds a raw quote).
inline std::string_view attrOf( std::string_view tag, std::string_view name )
{
    for( std::size_t at = tag.find( name ); at != std::string_view::npos; at = tag.find( name, at + 1 ) )
    {
        const std::size_t eq = at + name.size();
        if( at > 0 && tag[at - 1] == ' ' && eq + 1 < tag.size() && tag[eq] == '=' && tag[eq + 1] == '"' )
        {
            const std::size_t close = tag.find( '"', eq + 2 );
            return close == std::string_view::npos ? std::string_view() : tag.substr( eq + 2, close - eq - 2 );
        }
    }
    return {};
}

struct ShownRow
{
    char kind = 0; // 'd', 'b' or 't'
    std::string path;
    std::string name;
    std::uint32_t line = 0;
};

// The <d>, <b> and <t> row tags of the answer in order, outside comments and CDATA (a served body's own `<b>` is code, not a row).
inline std::vector<ShownRow> shownRows( std::string_view text )
{
    std::vector<ShownRow> rows;
    for( std::size_t i = text.find( '<' ); i != std::string_view::npos && i + 2 < text.size(); i = text.find( '<', i + 1 ) )
    {
        const std::string_view rest = text.substr( i );
        const std::string_view skipTo = rest.starts_with( "<!--" ) ? "-->" : rest.starts_with( "<![CDATA[" ) ? "]]>"
                                                                                                             : "";
        if( !skipTo.empty() )
        {
            const std::size_t end = text.find( skipTo, i );
            if( end == std::string_view::npos )
            {
                break;
            }
            i = end;
            continue;
        }
        const char k = text[i + 1];
        if( ( k != 'd' && k != 'b' && k != 't' ) || text[i + 2] != ' ' )
        {
            continue;
        }
        const std::size_t close = text.find( '>', i );
        if( close == std::string_view::npos )
        {
            break;
        }
        const std::string_view tag = text.substr( i + 2, close - i - 2 );
        ShownRow r { .kind = k, .path = unescapeXmlAttr( attrOf( tag, "p" ) ), .name = unescapeXmlAttr( attrOf( tag, "n" ) ) };
        const std::string_view l = attrOf( tag, "l" );
        std::from_chars( l.data(), l.data() + l.size(), r.line );
        if( const std::size_t colon = r.path.rfind( ':' ); r.line == 0 && colon != std::string::npos ) // a p="file:line" row
        {
            const std::string_view tail = std::string_view( r.path ).substr( colon + 1 );
            if( !tail.empty() && std::ranges::all_of( tail, []( char c )
                                                      { return c >= '0' && c <= '9'; } ) )
            {
                std::from_chars( tail.data(), tail.data() + tail.size(), r.line );
                r.path.resize( colon );
            }
        }
        if( !r.path.empty() )
        {
            rows.push_back( std::move( r ) );
        }
        i = close;
    }
    return rows;
}

// The file id a row's p= names: the index path itself, else the one file it is a whole-segment suffix of (or that is one of it).
inline std::uint32_t fileOfPath( const IngestResult& ing, std::string_view p )
{
    std::uint32_t hit = UINT32_MAX, suffixHits = 0;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        const std::string_view q = rootRelPath( ing, f );
        if( q == p )
        {
            return f;
        }
        const bool suffix = ( q.size() > p.size() && q.ends_with( p ) && q[q.size() - p.size() - 1] == '/' ) || ( p.size() > q.size() && p.ends_with( q ) && p[p.size() - q.size() - 1] == '/' );
        if( suffix )
        {
            hit = f;
            ++suffixHits;
        }
    }
    return suffixHits == 1 ? hit : UINT32_MAX;
}

inline std::string_view leafName( std::string_view n )
{
    return n.substr( n.find_last_of( ".:#" ) + 1 ); // npos + 1 is 0: no separator, the whole spelling
}

inline std::uint32_t fanIn( const Graph& g, NodeId id )
{
    const std::uint32_t* ro = g.inEdges.rowOffsets();
    const std::uint32_t* ci = g.inEdges.colIndices();
    if( ro == nullptr || ci == nullptr || std::size_t( id ) >= g.inEdges.rows() )
    {
        return 0;
    }
    std::uint32_t n = 0;
    for( std::uint32_t k = ro[id]; k < ro[id + 1]; ++k )
    {
        n += ci[k] != id ? 1u : 0u;
    }
    return n;
}

struct Cand
{
    NodeId id = kNoNode;
    std::size_t fileRank = 0; // position among the shown files
    std::size_t byName = 0; // task words its name shares
    std::size_t byCallee = 0; // head names whose definitions call it (popcount of headMask)
    std::uint8_t headMask = 0; // bit i: a definition named Head::names[i] calls it
    std::uint32_t fanIn = 0;
    bool anyPlain = false; // a shown head row itself calls it over an evidence-bound edge (not name-only, not split)
    bool anySplit = false;
};

// The first kForFileSymsHeadRows <d> rows: their distinct leaf names (by="callee" reads every definition so named) and the rows
// themselves as index ids (the definition in the row's file at its line by that name; kNoNode when the row maps to none).
struct Head
{
    std::vector<std::string> names; // distinct, at most kForFileSymsHeadRows (a bit each in Cand::headMask)
    std::vector<NodeId> ids;
    std::size_t rows = 0;
};
inline Head headOf( const IngestResult& ing, const std::vector<ShownRow>& rows, const std::vector<std::uint32_t>& rowFile )
{
    static_assert( kForFileSymsHeadRows <= 8, "Cand::headMask holds one bit per head name" );
    Head out;
    for( std::size_t i = 0; i < rows.size() && out.rows < kForFileSymsHeadRows; ++i )
    {
        if( rows[i].kind != 'd' || rows[i].name.empty() )
        {
            continue;
        }
        ++out.rows;
        const std::string_view leaf = leafName( rows[i].name );
        if( !std::ranges::contains( out.names, leaf ) )
        {
            out.names.emplace_back( leaf );
        }
        if( rowFile[i] == UINT32_MAX )
        {
            continue;
        }
        for( const Symbol& s : ing.symbols ) // one row's lookup; the head is 8 rows
        {
            if( s.fileId == rowFile[i] && s.line == rows[i].line && s.name == leaf )
            {
                out.ids.push_back( s.id );
                break;
            }
        }
    }
    return out;
}

inline constexpr std::array<SymKind, 3> kNotCandidate { SymKind::Section, SymKind::ModuleScope, SymKind::Field }; // a heading or data key, a file's scope, a field
inline bool candidateKind( const Symbol& s ) noexcept
{
    return !s.name.empty() && !std::ranges::contains( kNotCandidate, s.kind );
}
} // namespace filesyms_detail

namespace filesyms_detail
{
// The answer's first kForFileSymsFiles distinct shown paths as file ids (UINT32_MAX: a path the index does not hold), in answer
// order, and each row's file id (a head <d> row past the window still maps, for its callees).
struct ShownFiles
{
    std::vector<std::uint32_t> files;
    std::vector<std::uint32_t> rowFile;
    std::size_t pathsShown = 0; // distinct shown paths, the window's total
};
inline ShownFiles shownFiles( const IngestResult& ing, const std::vector<ShownRow>& rows )
{
    ShownFiles out;
    std::vector<std::string_view> paths; // parallel to out.files
    out.rowFile.assign( rows.size(), UINT32_MAX );
    for( std::size_t i = 0; i < rows.size(); ++i )
    {
        const std::string_view p = rows[i].path;
        const auto at = std::ranges::find( paths, p );
        if( at != paths.end() )
        {
            out.rowFile[i] = out.files[std::size_t( at - paths.begin() )];
            continue;
        }
        ++out.pathsShown;
        if( paths.size() < kForFileSymsFiles )
        {
            paths.push_back( p );
            out.files.push_back( fileOfPath( ing, p ) );
            out.rowFile[i] = out.files.back();
        }
        else if( rows[i].kind == 'd' )
        {
            out.rowFile[i] = fileOfPath( ing, p );
        }
    }
    return out;
}

// The candidates in id order: definitions of the shown files whose name is no word of the answer, each with its task-word score.
inline std::vector<Cand> collectCands( const IngestResult& ing, const std::vector<std::uint32_t>& files, std::string_view answer, std::string_view task )
{
    const std::vector<std::string_view> words = answerWords( answer );
    const std::vector<std::string> taskWords = matchWords( task );
    std::vector<Cand> cands;
    for( const Symbol& s : ing.symbols )
    {
        const auto at = std::ranges::find( files, s.fileId );
        if( at == files.end() || !candidateKind( s ) || std::ranges::binary_search( words, std::string_view( s.name ) ) )
        {
            continue;
        }
        cands.push_back( Cand { .id = s.id, .fileRank = std::size_t( at - files.begin() ), .byName = sharedWords( taskWords, matchWords( s.name ) ) } );
    }
    return cands;
}

// by="callee", name-resolved at both ends (Stage 0's rule): every definition NAMED like a head row (the shown row and its namesakes,
// since a row's name is what the answer gave) and every call it makes (calls only; a markdown link is no call), crediting each
// candidate NAMED like the callee. A row is plain only when the shown row itself calls that very candidate over an evidence-bound edge.
inline void creditCallees( const IngestResult& ing, const Graph& g, const Head& head, std::vector<Cand>& cands )
{
    std::vector<std::pair<std::string_view, std::size_t>> candByName; // (name, index into cands), sorted: the callee's namesakes
    candByName.reserve( cands.size() );
    for( std::size_t i = 0; i < cands.size(); ++i )
    {
        candByName.emplace_back( ing.symbols[cands[i].id].name, i );
    }
    std::ranges::sort( candByName );
    for( const Symbol& caller : ing.symbols )
    {
        const auto named = std::ranges::find( head.names, caller.name );
        if( named == head.names.end() || std::size_t( caller.id ) + 1 >= g.outOff.size() )
        {
            continue;
        }
        const std::uint8_t bit = std::uint8_t( 1u << std::size_t( named - head.names.begin() ) );
        const bool shown = std::ranges::contains( head.ids, caller.id );
        for( std::uint32_t e = g.outOff[caller.id]; e < g.outOff[caller.id + 1]; ++e )
        {
            const NodeId to = g.outTargets[e];
            const std::uint8_t kind = e < g.outNameOnly.size() ? edgeKindByte( g.outNameOnly[e] ) : 0;
            if( to == caller.id || to >= ing.symbols.size() || kind == kEdgeLink )
            {
                continue;
            }
            const bool split = e < g.outProv.size() && g.outProv[e] == 3u;
            const auto [lo, hi] = std::ranges::equal_range( candByName, std::string_view( ing.symbols[to].name ), {}, &std::pair<std::string_view, std::size_t>::first );
            for( auto it = lo; it != hi; ++it )
            {
                Cand& c = cands[it->second];
                const bool self = shown && c.id == to; // the shown row's own edge to this very definition
                c.headMask = std::uint8_t( c.headMask | bit );
                c.anySplit = c.anySplit || ( self && split && kind != kEdgeName );
                c.anyPlain = c.anyPlain || ( self && kind != kEdgeName && !split );
            }
        }
    }
}

// One row per (file, scope, name): an overload set, a member's in-class declaration and its out-of-line definition, or a re-opened
// definition name one place to look. The kept row is the one with the most head callers (head bits OR-ed: one head calling both
// spellings is one caller), else the lowest id.
inline void dedupeCands( const IngestResult& ing, std::vector<Cand>& cands )
{
    for( Cand& c : cands )
    {
        c.byCallee = std::size_t( std::popcount( c.headMask ) );
    }
    const auto key = [&]( const Cand& c )
    {
        const Symbol& s = ing.symbols[c.id];
        return std::tuple( s.fileId, std::string_view( s.scope ), std::string_view( s.name ) );
    };
    std::ranges::sort( cands, [&]( const Cand& a, const Cand& b )
                       { return std::tuple( key( a ), b.byCallee, a.id ) < std::tuple( key( b ), a.byCallee, b.id ); } );
    std::vector<Cand> kept;
    for( const Cand& c : cands )
    {
        if( kept.empty() || key( kept.back() ) != key( c ) )
        {
            kept.push_back( c );
            continue;
        }
        Cand& k = kept.back();
        k.headMask = std::uint8_t( k.headMask | c.headMask );
        k.byCallee = std::size_t( std::popcount( k.headMask ) );
        k.anyPlain = k.anyPlain || c.anyPlain;
        k.anySplit = k.anySplit || c.anySplit;
    }
    cands = std::move( kept );
}

struct Picks
{
    std::vector<const Cand*> byName, byCallee; // capped at kForFileSymsRowsPerRule each
    std::size_t nameTotal = 0, calleeTotal = 0;
};
// Each rule's rows: score desc, then fan-in desc, shown-file order, name, id (a total order), cut after the sort. A name both rules
// pick prints once, as by="name".
inline Picks pickRows( const IngestResult& ing, const Graph& g, std::vector<Cand>& cands )
{
    Picks out;
    for( Cand& c : cands )
    {
        c.fanIn = ( c.byName > 0 || c.byCallee > 0 ) ? fanIn( g, c.id ) : 0;
    }
    const auto tail = [&]( const Cand* a, const Cand* b )
    {
        return std::tuple( b->fanIn, a->fileRank, std::string_view( ing.symbols[a->id].name ), a->id ) < std::tuple( a->fanIn, b->fileRank, std::string_view( ing.symbols[b->id].name ), b->id );
    };
    const auto cut = [&]( std::vector<const Cand*>& rule, std::size_t& total, auto&& before )
    {
        std::ranges::sort( rule, [&]( const Cand* a, const Cand* b )
                           { return before( a, b ) || ( !before( b, a ) && tail( a, b ) ); } );
        total = rule.size();
        rule.resize( std::min( rule.size(), kForFileSymsRowsPerRule ) );
    };
    for( const Cand& c : cands )
    {
        if( c.byName > 0 )
        {
            out.byName.push_back( &c );
        }
    }
    cut( out.byName, out.nameTotal, []( const Cand* a, const Cand* b )
         { return a->byName > b->byName; } );
    for( const Cand& c : cands )
    {
        if( c.byCallee > 0 && !std::ranges::contains( out.byName, &c ) )
        {
            out.byCallee.push_back( &c );
        }
    }
    cut( out.byCallee, out.calleeTotal, []( const Cand* a, const Cand* b )
         { return std::pair( a->byCallee, a->byName ) > std::pair( b->byCallee, b->byName ); } );
    return out;
}

inline std::string blockXml( const IngestResult& ing, const ShownFiles& sf, const Head& head, const Picks& picks, bool compactLegend )
{
    const MemberOwners owners( ing );
    std::vector<char> esc;
    std::string out( compactLegend ? kForFileSymsLegendCompact : kForFileSymsLegend );
    const auto count = [&]( std::string_view attr, std::size_t shown, std::size_t total )
    {
        out += shown == 0 ? std::string() : std::format( " {}=\"{}\"", attr, shown );
        out += total > shown ? std::format( " {}_capped=\"1\" {}_total=\"{}\"", attr, attr, total ) : std::string();
    };
    out += "<syms";
    count( "files", sf.files.size(), sf.pathsShown );
    count( "head", head.rows, 0 );
    count( "name", picks.byName.size(), picks.nameTotal );
    count( "callee", picks.byCallee.size(), picks.calleeTotal );
    out += ">";
    const auto row = [&]( const Cand& c, bool callee )
    {
        const Symbol& s = ing.symbols[c.id];
        out += "<y p=\"";
        out += escapeXml( rootRelPath( ing, s.fileId ), esc );
        out += std::format( ":{}\" n=\"", s.line );
        out += escapeXml( qualifiedMemberName( owners, s ), esc );
        out += callee ? "\" by=\"callee\"" : "\" by=\"name\"";
        out += !callee || c.anyPlain ? "" : c.anySplit ? " prov=\"split\""
                                                       : " via=\"name\"";
        out += "/>";
    };
    for( const Cand* c : picks.byName )
    {
        row( *c, false );
    }
    for( const Cand* c : picks.byCallee )
    {
        row( *c, true );
    }
    return out + "</syms>";
}
} // namespace filesyms_detail

struct FileSymsArgs
{
    std::string_view task; // the --for task
    std::string_view answer; // the ordinary answer's text, before </ctx>
    bool held = false; // a token budget: the tag names the call, no rows
    bool compactLegend = false;
};
// The block for one answer: "" when no candidate scores.
inline std::string renderForFileSyms( const IngestResult& ing, const Graph& g, const FileSymsArgs& a )
{
    namespace fd = filesyms_detail;
    if( !forFileSymsOn() || a.task.empty() || a.answer.empty() )
    {
        return {};
    }
    const std::vector<fd::ShownRow> rows = fd::shownRows( a.answer );
    const fd::ShownFiles sf = fd::shownFiles( ing, rows );
    if( sf.files.empty() )
    {
        return {};
    }
    const fd::Head head = fd::headOf( ing, rows, sf.rowFile );
    std::vector<fd::Cand> cands = fd::collectCands( ing, sf.files, a.answer, a.task );
    fd::creditCallees( ing, g, head, cands );
    fd::dedupeCands( ing, cands );
    const fd::Picks picks = fd::pickRows( ing, g, cands );
    if( picks.byName.empty() && picks.byCallee.empty() )
    {
        return {};
    }
    if( a.held )
    {
        return "<syms held=\"budget\"" + nextAttrXml( nextFlag( "--for=", a.task ) ) + "/>";
    }
    return fd::blockXml( ing, sf, head, picks, a.compactLegend );
}
} // namespace rw
