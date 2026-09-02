#pragma once

// fielduses.h — the ONE `--uses=Owner.field` emitter (the member-variable round, card A3), printed verbatim by
// the CLI --uses arm (verbs_navigate.h runUses) and the MCP `uses` verb (mcpverbs.h usesText). One renderer,
// two surfaces — the §B4 rule: a legend clause or a root attribute added on one arm and not the other is the
// drift class floormarkcheck/mcpclidiffcheck exist to catch, so there is nothing here for an arm to copy.
//
// WHAT IT EMITS. `<uses of= defs="1" external="0" count= member= pinned= amb_sites= owners_of_name= [root=]
// [page…] counts_floor="1">` and one `<u role= p= [in_id=] [amb=K]/>` per site — the SAME row shape the
// name-matched --uses answer prints, plus amb=K on a site the resolver could not pin to one owner. The site
// set and the per-site candidate count come from graph.h collectFieldUseSites; this file only orders (tier,
// then path, then line, then role, then enclosing id — the LB-G order every use-site list shares), pages
// (pageview.h's vocabulary, the --uses default site cap) and words the answer. Deterministic by construction:
// a total order on rows and no HashMap reaches the output.

#include "model.h"
#include "graph.h"        // collectFieldUseSites / FieldUseAnswer
#include "resolve.h"      // canonicalIdForEmit — the root-relative in_id= both surfaces print
#include "graphlegend.h"  // kUsesLegendOpen / kUsesFieldLegend / graphCountDisclosure / kGraphCountFloorAttrXml / rootRelPathsLegend / capLegendClause
#include "pageview.h"     // pageWindow / pageDisclosure / computePageDisclosure / effectiveRowCap / kUseSiteRowCap
#include "filter.h"       // pathTierIndexOver / compareTierThenPath — the shared tier-then-path row order
#include "sarif.h"        // rootPrefixOf / rootRelativeUri — root-relative p=
#include "serialize.h"    // escapeXml

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

struct FieldUsesArgs
{
    std::string_view selectorEcho;   // of= echoes the selector AS TYPED (Owner.field, Owner::field, the id, or a bare name that resolved to one field)
    bool             singleRoot;     // the same single-root condition every other verb's root= uses
    std::string_view root;           // the root spelling (p= and in_id= are made relative to it when singleRoot; ignored otherwise)
    int              pageLimit;      // --limit / MCP limit (0 = the verb's default cap)
    int              pageOffset;     // --offset / MCP offset
};

// The one selector shape the member form serves: a resolution to exactly ONE symbol that is a field. kNoNode
// otherwise — two fields (the owner refusal), a field beside a same-named function (the historic union), or
// nothing at all (the not-found path) all fall through to the name-matched arm.
inline NodeId singleFieldOf( const IngestResult& ing, std::span<const NodeId> defs ) noexcept
{
    const bool one = defs.size() == 1 && defs[ 0 ] < ing.symbols.size() && ing.symbols[ defs[ 0 ] ].kind == SymKind::Field;
    return one ? defs[ 0 ] : kNoNode;
}

inline std::string renderFieldUses( const IngestResult& ing, NodeId fieldSym, const FieldUsesArgs& args )
{
    VERIFY( fieldSym < ing.symbols.size() );
    const Symbol&        field  = ing.symbols[ fieldSym ];
    const FieldUseAnswer answer = collectFieldUseSites( ing, fieldSym );

    struct Row { std::uint32_t fileId; std::uint32_t line; RefRole role; std::uint32_t candidateCount; std::string in; };
    std::vector<Row> rows;
    rows.reserve( answer.sites.size() );
    const std::string_view rootForId = args.singleRoot ? args.root : std::string_view{};
    for( const FieldUseSite& site : answer.sites )
    {
        const Reference& r = ing.references[ site.refIndex ];
        std::string      in;
        if( r.fromSymbol != kNoNode && r.fromSymbol < ing.symbols.size() )
        {
            in = canonicalIdForEmit( ing, ing.symbols[ r.fromSymbol ], rootForId );
        }
        rows.push_back( { r.fileId, r.line, r.role, site.candidateCount, std::move( in ) } );
    }
    const std::vector<std::uint8_t> tierOfFile = pathTierIndexOver( ing, rows, [ ]( const Row& u ) { return u.fileId; } );
    std::sort( rows.begin(), rows.end(), [ & ]( const Row& a, const Row& b )
               {
                   if( const int c = compareTierThenPath( ing, tierOfFile, a.fileId, b.fileId ); c != 0 ) { return c < 0; }
                   if( a.line != b.line ) { return a.line < b.line; }
                   if( a.role != b.role ) { return std::uint8_t( a.role ) < std::uint8_t( b.role ); }
                   return a.in < b.in;
               } );

    const PageWindow  window      = pageWindow( rows.size(), effectiveRowCap( args.pageLimit, kUseSiteRowCap ), args.pageOffset );
    const std::size_t pageRows    = window.end - window.begin;
    const bool        discloseCap = pageRows < rows.size();
    char              pageBuf[ kPageDisclosureCap ];
    const char* const pageAttrs   = pageDisclosure( pageBuf, sizeof( pageBuf ), pageRows, rows.size(), window.end, args.pageLimit, args.pageOffset, discloseCap );

    std::vector<char> esc;
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };

    std::string out;
    out.reserve( 4096 + rows.size() * 96 );
    out += kUsesLegendOpen;
    out += kUsesFieldLegend;
    out += capLegendClause( computePageDisclosure( pageRows, rows.size(), window.end, args.pageLimit, args.pageOffset, discloseCap ).active );
    out += graphCountDisclosure();
    out += "-->";
    out += rootRelPathsLegend( args.singleRoot );

    const std::string rootPrefix = args.singleRoot ? sarif::rootPrefixOf( args.root ) : std::string();
    out += "<uses of=\"" + ex( args.selectorEcho ) + "\" defs=\"1\" external=\"0\" count=\"" + std::to_string( rows.size() )
         + "\" member=\"" + ex( field.scope + "." + field.name ) + "\" pinned=\"" + std::to_string( answer.pinnedCount )
         + "\" amb_sites=\"" + std::to_string( answer.ambCount ) + "\" owners_of_name=\"" + std::to_string( answer.ownersOfName ) + "\"";
    if( args.singleRoot )
    {
        out += " root=\"" + ex( args.root ) + "\"";
    }
    out += pageAttrs;
    out += kGraphCountFloorAttrXml;
    out += ">";
    for( std::size_t rowIndex = window.begin; rowIndex < window.end; ++rowIndex )
    {
        const Row&             u  = rows[ rowIndex ];
        const std::string_view rp = args.singleRoot ? sarif::rootRelativeUri( ing.files[ u.fileId ], rootPrefix ) : std::string_view( ing.files[ u.fileId ] );
        out += "<u role=\"";
        out += refRoleTag( u.role );
        out += "\" p=\"" + ex( rp ) + ":" + std::to_string( u.line ) + "\"";
        if( !u.in.empty() )
        {
            out += " in_id=\"" + ex( u.in ) + "\"";
        }
        if( u.candidateCount > 1 )
        {
            out += " amb=\"" + std::to_string( u.candidateCount ) + "\"";
        }
        out += "/>";
    }
    out += "</uses>";
    return out;
}

// The CLI --uses arm, behind ONE branch in runUses: the member answer (exit 0), the several-owners refusal
// (exit 1), the unserved-language refusal (exit 1), or nullopt when the selector is not a member shape at all
// and the name-matched arm proceeds. `defs` is what resolveAllByNameQualified returned; `root` is roots[0].
inline std::optional<int> memberUsesArm( const IngestResult& ing, std::span<const NodeId> defs, std::string_view sym,
                                         bool singleRoot, std::string_view root, int pageLimit, int pageOffset )
{
    if( const NodeId field = singleFieldOf( ing, defs ); field != kNoNode )
    {
        std::fputs( renderFieldUses( ing, field, FieldUsesArgs{ sym, singleRoot, root, pageLimit, pageOffset } ).c_str(), stdout );
        return 0;
    }
    if( const std::string refusal = memberOwnerRefusal( ing, defs, sym, "--uses=" ); !refusal.empty() )
    {
        std::fprintf( stderr, "ripwire: --uses=%s refused: %s\n", std::string( sym ).c_str(), refusal.c_str() );
        return 1;
    }
    // `Owner.field` on a type whose language extracts no fields refuses BY LANGUAGE NAME — the generic
    // not-found would read as a typo, and an empty answer as "no uses". Only when nothing resolved at all.
    if( const std::string unserved = defs.empty() ? memberSelectorUnservedRefusal( ing, sym ) : std::string{}; !unserved.empty() )
    {
        std::fprintf( stderr, "ripwire: --uses %s\n", unserved.c_str() );
        return 1;
    }
    return std::nullopt;
}

}   // namespace rw
