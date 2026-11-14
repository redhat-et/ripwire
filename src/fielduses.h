#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings
#include <string_view>       // %.*s (precision, pointer) collapses to one view


// fielduses.h — the ONE `--uses=Owner.field` emitter (the member-variable round, card A3), printed verbatim by
// the CLI --uses arm (verbs_navigate.h runUses) and the MCP `uses` verb (mcpverbs.h usesText). One renderer,
// two surfaces — the §B4 rule: a legend clause or a root attribute added on one arm and not the other is the
// drift class floormarkcheck/mcpclidiffcheck exist to catch, so there is nothing here for an arm to copy.
//
// WHAT IT EMITS. `<uses of= defs="1" external="0" count= member= pinned= amb_sites= owners_of_name= [root=]
// [page…] counts_floor="1">` and one `<u role= p= [in_id=] [owner_candidates=K]/>` per site — the SAME row shape the
// name-matched --uses answer prints, plus owner_candidates=K on a site the resolver could not pin to one owner. The site
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
#include "degradedscan.h" // readWhole / wholeWordAt / crossref's comment tests — the shared lexical helpers (unservedMemberDeclRefusal)
#include "lexindex.h"     // forEachLexSubtoken / lexSubtokenHash — the per-definition token prefilter

#include <algorithm>
#include <cctype>
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
    const Graph&     graph;          // M15: the gauge pair on the root (graphCountFloorAttrXml) reads ambOut/unresolvedOut
};

inline std::string renderFieldUses( const IngestResult& ing, FieldId fieldId, const FieldUsesArgs& args )
{
    ASSUME( fieldId < ing.fields.size() );
    const Symbol&        field  = ing.fields[ fieldId ];
    const FieldUseAnswer answer = collectFieldUseSites( ing, fieldId );

    struct Row { std::uint32_t fileId; std::uint32_t line; RefRole role; std::uint32_t candidateCount; std::string in; NodeId from; };   // from: rankUseSites' weight
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
        rows.push_back( { r.fileId, r.line, r.role, site.candidateCount, std::move( in ), r.fromSymbol } );
    }
    const std::vector<std::uint8_t> tierOfFile = pathTierIndexOver( ing, rows, [ ]( const Row& u ) { return u.fileId; } );
    std::sort( rows.begin(), rows.end(), [ & ]( const Row& a, const Row& b )
               {
                   if( const int c = compareTierThenPath( ing, tierOfFile, a.fileId, b.fileId ); c != 0 ) { return c < 0; }
                   if( a.line != b.line ) { return a.line < b.line; }
                   if( a.role != b.role ) { return std::uint8_t( a.role ) < std::uint8_t( b.role ); }
                   return a.in < b.in;
               } );
    rankUseSites( ing, args.graph, rows );   // cut-fix C: the --uses order, shared — the cap drops the lightest sites

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
    out += graphCountDisclosure( rw::graphGaugeClauses( args.graph ) );
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
    out += graphCountFloorAttrXml( args.graph );   // M15: gauge + marker
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
            // M15 (capture-audit 2026-09-04): owner_candidates=, not amb= — amb= is the map's "K ambiguous CALLS of this
            // symbol" (g.ambOut); this is "how many owners this ONE site could belong to", a different fact.
            out += " owner_candidates=\"" + std::to_string( u.candidateCount ) + "\"";
        }
        out += "/>";
    }
    out += "</uses>";
    return out;
}

// The CLI --uses arm, behind ONE branch in runUses, entered ONLY when the selector named no symbol (`defs`
// empty — a name that IS a symbol keeps the historic name-matched answer, union included): the member answer
// (exit 0), the several-owners refusal (exit 1), the unserved-language refusal (exit 1), or nullopt when the
// selector names no field either and the not-found path proceeds. `root` is roots[0].
// ── USES-FIELD-EXTERNAL (B31) ────────────────────────────────────────────────────────────────────────────────────
// A BARE member name in a language with no field capture resolved to nothing, so the CLI answered found="0" near="Route"
// (a type) and MCP external="1" — "no definition in the indexed tree under any spelling" — for hono's `routes`, a class
// field at src/hono-base.ts:125. The qualified form (`Hono.routes`) already refuses with the right sentence; this finds
// the owner LEXICALLY so the bare form says the same: the first class-like definition of an unserved language (graph.h
// fieldsUnservedOwner, symbol id order = path, line) whose body holds a line shaped like a member declaration of `name`,
// outside every function or method body of that file.

// Words that may precede a member's name on its declaration line (TS/JS, Rust, Go, Swift, Kotlin, Java, C#, Dart).
inline constexpr std::string_view kMemberDeclModifiers[] = {
    "pub", "pub(crate)", "pub(super)", "pub(self)", "private", "public", "protected", "internal", "readonly", "static", "declare",
    "override", "abstract", "final", "transient", "volatile", "val", "var", "let", "const", "mut", "lateinit", "open", "export",
    "required", "weak", "lazy", "late",
};

// Is `line` a member declaration of the name at `at`? NAME-FIRST: only modifiers (or a TS `#`) before it, then `:`, `?:`,
// `!:`, `=`, `;` — or, in Go, the field's type. TYPE-FIRST (Java, C#, Dart): `Type name;`, `Type name =`, `Type name {`.
// Comments, string literals and anything followed by `(` (a method) are never declarations.
inline bool memberDeclShaped( std::string_view line, std::size_t at, std::size_t nameLen, Lang lang )
{
    if( crossref::lineOpensComment( line ) || crossref::insideCommentOrString( line, at ) )
    {
        return false;
    }
    std::size_t after = at + nameLen;
    while( after < line.size() && ( line[ after ] == ' ' || line[ after ] == '\t' ) )
    {
        ++after;
    }
    if( after < line.size() && ( line[ after ] == '?' || line[ after ] == '!' ) )
    {
        ++after;
    }
    const char next  = after < line.size() ? line[ after ] : '\0';
    const char next2 = after + 1 < line.size() ? line[ after + 1 ] : '\0';
    const bool binds = ( next == ':' && next2 != ':' ) || ( next == '=' && next2 != '=' && next2 != '>' ) || next == ';';

    bool              modifiersOnly = true;
    std::size_t       words         = 0;
    std::string_view  prefix        = line.substr( 0, at );
    if( const std::size_t opener = prefix.find_last_of( "{};" ); opener != std::string_view::npos )
    {
        prefix.remove_prefix( opener + 1 );   // `class Options { limit = 1; }`: the declaration starts after the owner's opener
    }
    for( std::size_t i = prefix.find_first_not_of( " \t" ); i != std::string_view::npos; i = prefix.find_first_not_of( " \t", i ) )
    {
        std::size_t end = prefix.find_first_of( " \t", i );
        end             = end == std::string_view::npos ? prefix.size() : end;
        const std::string_view word = prefix.substr( i, end - i );
        ++words;
        if( word != "#" && std::find( std::begin( kMemberDeclModifiers ), std::end( kMemberDeclModifiers ), word ) == std::end( kMemberDeclModifiers ) )
        {
            modifiersOnly = false;
        }
        i = end;
    }
    if( !prefix.empty() && prefix.back() == '#' )
    {
        modifiersOnly = modifiersOnly || prefix.find_first_not_of( " \t" ) == prefix.size() - 1;   // `#path: string` (TS private)
    }
    if( modifiersOnly )
    {
        const bool goType = langFacts( lang ).memberDecl == MemberDecl::NameThenType && ( std::isalpha( (unsigned char)next ) || next == '*' || next == '[' || next == '_' );
        return binds || goType;
    }
    // TYPE-FIRST: the name sits in the declarator slot right after a type — never inside an initializer (`int seed = valueToken;`
    // reads valueToken, CodeRabbit 4553235686) or after a member access (`this.x =`). The prefix holds no `=`/`(` and ends on a
    // type's last byte (a word, `>`, `]`, `?`, `*`) or a declarator list's `,`.
    const bool             typeFirstLang  = langFacts( lang ).memberDecl == MemberDecl::TypeFirst;
    const std::size_t      lastByte       = prefix.find_last_not_of( " \t" );
    const char             typeEnd        = lastByte == std::string_view::npos ? '\0' : prefix[ lastByte ];
    const bool             declaratorSlot = std::isalnum( (unsigned char)typeEnd ) || std::string_view( "_$>]?*," ).find( typeEnd ) != std::string_view::npos;
    return typeFirstLang && words >= 1 && prefix.find_first_of( "=(" ) == std::string_view::npos && declaratorSlot
        && ( ( next == '=' && next2 != '=' ) || next == ';' || next == '{' );
}

// Every subtoken of `name` occurs in definition `id`'s body (the B0.2 per-definition token row): the cheap test that
// keeps the byte read off every class that cannot hold the member. True when the index carries no token rows.
inline bool lexRowMayHold( const IngestResult& ing, NodeId id, std::string_view name )
{
    if( !ing.hasLexStats || std::size_t( id ) + 1 >= ing.lexTokenRowOffsets.size() )
    {
        return true;
    }
    const auto rowBegin = ing.lexTokenHashes.begin() + std::ptrdiff_t( ing.lexTokenRowOffsets[ id ] );
    const auto rowEnd   = ing.lexTokenHashes.begin() + std::ptrdiff_t( ing.lexTokenRowOffsets[ id + 1 ] );
    bool       all      = true;
    forEachLexSubtoken( name, [ & ]( std::size_t b, std::size_t e )
    {
        if( e - b >= 2 && !std::binary_search( rowBegin, rowEnd, lexSubtokenHash( name.data() + b, e - b ) ) )
        {
            all = false;
        }
    } );
    return all;
}

// Is byte `at` of file `fileId` inside a function or method body? Symbols are sorted by (file, line): the file's are one run.
inline bool insideFunctionOfFile( const IngestResult& ing, std::uint32_t fileId, std::size_t at, NodeId from )
{
    for( std::size_t k = from; k < ing.symbols.size() && ing.symbols[ k ].fileId == fileId; ++k )
    {
        const Symbol& f = ing.symbols[ k ];
        if( ( f.kind == SymKind::Function || f.kind == SymKind::Method ) && f.sigStartByte <= at && at < f.endByte )
        {
            return true;
        }
    }
    return false;
}

// Brace depth inside an owner's span, walked forward once: `{`/`}` outside `//` and `/* */` comments, "…" and `…` strings,
// '…' strings (LangFacts::singleQuoteStrings) and char literals (CodeRabbit 4553235701: `label = '{'` opened a phantom depth). A direct
// member sits at depth 1; an object-literal property, a method's local or a nested type's member sits deeper. A skip may
// carry `pos` past the byte asked for: that byte sits inside the comment or string (memberDeclLine reads that as no member).
struct OwnerBraceWalk
{
    std::size_t pos          = 0;
    std::size_t depth        = 0;
    bool        opened       = false;   // the owner's body brace was seen (GDScript's indented classes never open one)
    bool        quoteStrings = false;   // LangFacts::singleQuoteStrings of the owner's language

    // The byte after the literal that opens at `pos` with `quote`, or npos when none closes it (`'a` lifetime, apostrophe).
    static std::size_t literalEnd( std::string_view bytes, std::size_t open, char quote, bool multiLine ) noexcept
    {
        std::size_t k = open + 1;
        while( k < bytes.size() && bytes[ k ] != quote && ( multiLine || bytes[ k ] != '\n' ) )
        {
            k += bytes[ k ] == '\\' ? 2 : 1;
        }
        return k < bytes.size() && bytes[ k ] == quote ? k + 1 : std::string_view::npos;
    }

    void advanceTo( std::string_view bytes, std::size_t to )
    {
        while( pos < to )
        {
            const char c    = bytes[ pos ];
            const char next = pos + 1 < bytes.size() ? bytes[ pos + 1 ] : '\0';
            if( c == '/' && next == '/' )
            {
                pos = std::min( bytes.find( '\n', pos ), bytes.size() );   // may pass `to`: the next walk resumes outside the comment
            }
            else if( c == '/' && next == '*' )
            {
                const std::size_t close = bytes.find( "*/", pos + 2 );
                pos                     = close == std::string_view::npos ? bytes.size() : close + 2;
            }
            else if( c == '"' )
            {
                std::size_t k = pos + 1;
                while( k < bytes.size() && bytes[ k ] != '"' && bytes[ k ] != '\n' )
                {
                    k += bytes[ k ] == '\\' ? 2 : 1;
                }
                pos = std::min( k + 1, bytes.size() );
            }
            else if( c == '`' )
            {
                const std::size_t end = literalEnd( bytes, pos, '`', true );   // a template literal / Go raw string spans lines
                pos                   = end == std::string_view::npos ? bytes.size() : end;
            }
            else if( c == '\'' )
            {
                const std::size_t end     = literalEnd( bytes, pos, '\'', false );
                const bool        charLit = end != std::string_view::npos && ( end == pos + 3 || ( end <= pos + 8 && next == '\\' ) );
                pos                       = end != std::string_view::npos && ( quoteStrings || charLit ) ? end : pos + 1;
            }
            else
            {
                if( c == '{' )
                {
                    ++depth;
                    opened = true;
                }
                else if( c == '}' && depth > 0 )
                {
                    --depth;
                }
                ++pos;
            }
        }
    }
};

// The first line of `owner`'s body that declares member `name`; 0 when none.
inline std::uint32_t memberDeclLine( const IngestResult& ing, const Symbol& owner, std::string_view bytes, std::string_view name, NodeId fileFirst )
{
    const std::size_t begin = std::min<std::size_t>( owner.sigStartByte, bytes.size() );   // a Go struct's signature spans its fields
    const std::size_t end   = std::min<std::size_t>( owner.endByte, bytes.size() );
    OwnerBraceWalk    walk{ .pos = begin, .quoteStrings = langFacts( owner.lang ).singleQuoteStrings };
    for( std::size_t at = bytes.find( name, begin ); at != std::string_view::npos && at + name.size() <= end; at = bytes.find( name, at + 1 ) )
    {
        if( !darkflags::wholeWordAt( bytes, at, name.size() ) )
        {
            continue;
        }
        walk.advanceTo( bytes, at );
        if( walk.pos > at )
        {
            continue;   // the walk skipped over it: inside a `/* … */` spanning lines or a string (CodeRabbit 4553235721)
        }
        if( walk.opened && walk.depth != 1 )
        {
            continue;   // inside a nested literal, body or type: not a member of THIS owner
        }
        const std::size_t nl        = bytes.rfind( '\n', at );
        const std::size_t lineStart = nl == std::string_view::npos ? 0 : nl + 1;
        std::size_t       lineEnd   = bytes.find( '\n', at );
        lineEnd                     = lineEnd == std::string_view::npos ? bytes.size() : lineEnd;
        if( memberDeclShaped( bytes.substr( lineStart, lineEnd - lineStart ), at - lineStart, name.size(), owner.lang )
            && !insideFunctionOfFile( ing, owner.fileId, at, fileFirst ) )
        {
            return std::uint32_t( 1 + std::count( bytes.begin(), bytes.begin() + std::ptrdiff_t( at ), '\n' ) );
        }
    }
    return 0;
}

// The bare-name scan: `refusal` is "" unless `name` (no qualifier) is declared as a member of an unserved owner; `capped` says
// the scan stopped at its 16 MiB budget before finding one (USES-DECL-SCAN-CAPPED, CodeRabbit #630): the served answer then
// carries decl_scan="capped" (memberDeclScanAttrXml), because its external="1" was never checked against the unread files.
struct MemberDeclScan
{
    std::string refusal;
    bool        capped = false;
};
inline MemberDeclScan memberDeclScan( const IngestResult& ing, std::string_view name )
{
    if( name.empty() || name.size() > 256 || name.find_first_of( ".:@ " ) != std::string_view::npos )
    {
        return {};
    }
    std::size_t                scannedBytes = 0;
    std::uint32_t              loadedFile   = UINT32_MAX;
    NodeId                     fileFirst    = 0;
    std::optional<std::string> bytes;
    for( NodeId id = 0; id < ing.symbols.size(); ++id )
    {
        const Symbol& s = ing.symbols[ id ];
        if( id == 0 || ing.symbols[ id - 1 ].fileId != s.fileId )
        {
            fileFirst = id;
        }
        if( !fieldsUnservedOwner( s ) || langFacts( s.lang ).memberDecl == MemberDecl::None || s.endByte <= s.sigStartByte || !lexRowMayHold( ing, id, name ) )
        {
            continue;
        }
        if( s.fileId != loadedFile )
        {
            loadedFile = s.fileId;
            bytes      = darkflags::readWhole( diskPath( ing, s.fileId ) );
            if( bytes && ( scannedBytes += bytes->size() ) > kLexicalDefScanBytes )
            {
                return MemberDeclScan{ {}, true };   // budget: no refusal, and the served answer says the scan stopped
            }
        }
        if( !bytes )
        {
            continue;
        }
        if( const std::uint32_t line = memberDeclLine( ing, s, *bytes, name, fileFirst ); line != 0 )
        {
            return MemberDeclScan{ "'" + std::string( name ) + "' is declared as a member of '" + s.name + "' at " + ing.files[ s.fileId ] + ":"
                                       + std::to_string( line ) + " and has no other indexed definition — "
                                       + memberUnservedSentence( ing, s.name + "." + std::string( name ), s ),
                                   false };
        }
    }
    return {};
}
inline std::string unservedMemberDeclRefusal( const IngestResult& ing, std::string_view name )
{
    return memberDeclScan( ing, name ).refusal;
}

// decl_scan="capped" on a served external="1" answer: the bare-name member-declaration scan stopped at its budget, so a
// lexical member declaration past it was not ruled out. Asked only for an external answer (no indexed definition) of a
// name with no field: the scan runs again there (a cold path, at most the 16 MiB budget).
inline bool memberDeclScanCapped( const IngestResult& ing, std::string_view name, bool external )
{
    return external && resolveFieldSelector( ing, name ).empty() && memberDeclScan( ing, name ).capped;
}
inline const char* memberDeclScanAttrXml( bool capped ) noexcept
{
    return capped ? " decl_scan=\"capped\"" : "";
}
inline const char* memberDeclScanLegend( bool capped ) noexcept
{
    return capped ? "decl_scan=\"capped\": the scan for a lexical member declaration of SYM (a field of a type whose language the index "
                    "extracts no fields for) stopped at its 16 MiB budget, so external=\"1\" is unchecked past it; the grep verb finds the "
                    "declaration. "
                  : "";
}

inline std::optional<int> memberUsesArm( const IngestResult& ing, const Graph& g, std::span<const NodeId> defs, std::string_view sym,
                                         bool singleRoot, std::string_view root, int pageLimit, int pageOffset )
{
    if( !defs.empty() )
    {
        return std::nullopt;
    }
    const std::vector<FieldId> fields = resolveFieldSelector( ing, sym );
    if( fields.size() == 1 )
    {
        std::fputs( renderFieldUses( ing, fields[ 0 ], FieldUsesArgs{ sym, singleRoot, root, pageLimit, pageOffset, g } ).c_str(), stdout );
        return 0;
    }
    if( const std::string refusal = memberOwnerRefusal( ing, fields, sym, "--uses=" ); !refusal.empty() )
    {
        rw::emitTo( stderr, "ripwire: --uses={} refused: {}\n", std::string( sym ).c_str(), refusal.c_str() );
        return 1;
    }
    // `Owner.field` on a type whose language extracts no fields refuses BY LANGUAGE NAME — the generic
    // not-found would read as a typo, and an empty answer as "no uses".
    if( const std::string unserved = memberSelectorUnservedRefusal( ing, sym ); !unserved.empty() )
    {
        rw::emitTo( stderr, "ripwire: --uses {}\n", unserved.c_str() );
        return 1;
    }
    // B31 USES-FIELD-EXTERNAL: the bare name of such a member refuses with the same sentence, never found="0" near=<a type>.
    if( fields.empty() )
    {
        if( const std::string declared = unservedMemberDeclRefusal( ing, sym ); !declared.empty() )
        {
            rw::emitTo( stderr, "ripwire: --uses {}\n", declared.c_str() );
            return 1;
        }
    }
    return std::nullopt;
}

}   // namespace rw
