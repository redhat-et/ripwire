#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_docs.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_docs.h — the markdown section tier, moved VERBATIM from ingest.cpp in the 2026-08-29
// split: the mdtier namespace (heading cleanup, slugs, the block-grammar tree walk with its quote
// and depth guards) and extractMarkdown, which turns a doc's headings into section symbols with a
// file-level fallback node. A heading is to a doc what a function is to a file. Small but sealed:
// nothing else in the pipeline shares these helpers. Same contract as every ingest_*.h: reopens
// `namespace rw` and the unnamed namespace inside it — one TU, one unnamed namespace, internal
// linkage unchanged, zero new API surface — under the RIPWIRE_INGEST_TU guard.

namespace rw
{

namespace
{

// ── THE MARKDOWN SECTION TIER (collapse-queue G2/G3, gate: test/mdsectioncheck.sh) ──────────────────────
// A heading is to a doc what a function is to a file. Parsed with the vendored tree-sitter-markdown BLOCK
// grammar (custom tree walk, no tags.scm — section spans and heading hierarchy need the tree, not a
// capture list). We extract:
//   (1) a FILE-LEVEL node spanning the whole file (named by the filename stem) so heading-less docs stay
//       visible + rankable AND so cross-file [[wikilinks]]/[x](other.md) links have a target;
//   (2) every ATX (# .. ######) AND setext (===/---) heading as a Section def whose SPAN runs from the
//       heading to the next same-or-higher heading — bodyByte = the heading construct's end, so the
//       signature is the heading line and [bodyByte, endByte) is the section body --expand serves. The
//       span rule runs over the MERGED ATX+setext heading list because the grammar nests `section` nodes
//       on ATX only (probed 2026-08-12: a setext H1 does NOT open a section node) — the level rule is the
//       ratified design, the grammar's section nesting is not. scope = the nearest shallower heading
//       (parent), so the canonical id is path::Parent::Child — identity stays path-qualified;
//   (3) NOTHING inside fenced/indented code, html blocks, front-matter (minus/plus_metadata) or
//       blockquotes becomes structure: headings are read only off heading AST nodes outside block_quote,
//       and the inline line scan below skips OPAQUE byte ranges collected from the same walk (fenced code
//       is also never handed to the language grammar that owns it — no double-index);
//   (4) inline-code `identifiers` → doc→code mentions (isDocLink, resolved in buildGraph, OUT of the call
//       graph) — unchanged semantics, now attributed to their enclosing SECTION by the span containment
//       scan;
//   (5) links → edges: [[slug]] (the agent-memory/Obsidian convention) and [text](other.md) /
//       [label]: other.md → a ref named by the target's stem (the resolve ladder's same-dir preference
//       lands it on the file node); [text](#anchor) → a ref named by the matching heading in THIS file
//       (GitHub slugify; same-file preference wins) — a doc-section→doc-section edge. Dangling links drop.
// Determinism: the walk is a preorder over the AST (byte order); pending anchors resolve in byte order.
// Names are XML-escaped downstream; CR bytes never enter a name, embedded newlines flatten to spaces.
namespace mdtier
{

struct MdHeading
{
    std::uint32_t level     = 0;   // 1..6
    std::uint32_t startByte = 0;   // heading construct start (== the section's defStart)
    std::uint32_t sigEnd    = 0;   // heading construct end (ATX line / setext underline incl. newline)
    std::uint32_t nameByte  = 0;   // heading-text start (dedup identity)
    std::uint32_t endByte   = 0;   // section span end — filled by the post-pass
    std::uint32_t line      = 0;   // 1-based
    std::string   name;            // heading text: closing #s stripped, \r dropped, \n flattened
};

struct MdWalkOut
{
    std::vector<MdHeading>                                 headings;
    std::vector<std::pair<std::uint32_t, std::uint32_t>>   opaque;    // byte ranges the line scan must skip
    std::vector<std::pair<std::uint32_t, std::uint32_t>>   refDefs;   // link_reference_definition DESTINATION spans
};

inline std::string mdCleanHeadingText( std::string_view raw )
{
    std::string name;
    name.reserve( raw.size() );
    for( const char c : raw )
    {
        if( c == '\r' ) { continue; }
        name += ( c == '\n' ) ? ' ' : c;
    }
    while( !name.empty() && ( name.back() == ' ' || name.back() == '\t' ) ) { name.pop_back(); }
    while( !name.empty() && name.back() == '#' ) { name.pop_back(); }        // ATX closing sequence — the
    while( !name.empty() && ( name.back() == ' ' || name.back() == '\t' ) ) { name.pop_back(); }   // grammar keeps it (probed)
    return name;
}

// GitHub anchor slug of a heading name: alnum lowered, spaces→'-', '-'/'_' kept, everything else
// dropped. First match wins on collision (GitHub's -1/-2 suffixes are not modelled; a collided anchor
// resolves to the first heading — disclosed here rather than guessed).
inline std::string mdSlugOf( std::string_view name )
{
    std::string slug;
    slug.reserve( name.size() );
    for( const char c : name )
    {
        if( ( c >= 'a' && c <= 'z' ) || ( c >= '0' && c <= '9' ) || c == '_' || c == '-' ) { slug += c; }
        else if( c >= 'A' && c <= 'Z' ) { slug += char( c - 'A' + 'a' ); }
        else if( c == ' ' || c == '\t' ) { slug += '-'; }
    }
    return slug;
}

inline void mdWalk( TSNode node, std::string_view src, bool inQuote, std::uint32_t depth, MdWalkOut& out )
{
    if( depth > 512u )
    {
        return;   // the depth prescan (mdNestsTooDeep) bounds real trees far below this; belt only
    }
    const char*         type = ts_node_type( node );
    const std::uint32_t a    = ts_node_start_byte( node );
    const std::uint32_t b    = ts_node_end_byte( node );
    if( std::strcmp( type, "fenced_code_block" ) == 0 || std::strcmp( type, "indented_code_block" ) == 0
        || std::strcmp( type, "html_block" ) == 0 || std::strcmp( type, "minus_metadata" ) == 0
        || std::strcmp( type, "plus_metadata" ) == 0 )
    {
        out.opaque.emplace_back( a, b );
        return;   // nothing inside is structure, mention or link
    }
    if( std::strcmp( type, "link_reference_definition" ) == 0 )
    {
        out.opaque.emplace_back( a, b );   // not mention-scanned …
        const std::uint32_t n = ts_node_named_child_count( node );
        for( std::uint32_t i = 0; i < n; ++i )
        {
            TSNode ch = ts_node_named_child( node, i );
            if( std::strcmp( ts_node_type( ch ), "link_destination" ) == 0 )
            {
                out.refDefs.emplace_back( ts_node_start_byte( ch ), ts_node_end_byte( ch ) );   // … but its destination IS a link
            }
        }
        return;
    }
    if( !inQuote && std::strcmp( type, "atx_heading" ) == 0 )
    {
        MdHeading           h;
        const std::uint32_t n = ts_node_named_child_count( node );
        for( std::uint32_t i = 0; i < n; ++i )
        {
            TSNode      ch = ts_node_named_child( node, i );
            const char* ct = ts_node_type( ch );
            if( std::strncmp( ct, "atx_h", 5 ) == 0 && ct[ 5 ] >= '1' && ct[ 5 ] <= '6' )
            {
                h.level = std::uint32_t( ct[ 5 ] - '0' );
            }
            else if( std::strcmp( ct, "inline" ) == 0 )
            {
                const std::uint32_t ia = ts_node_start_byte( ch );
                h.name     = mdCleanHeadingText( src.substr( ia, ts_node_end_byte( ch ) - ia ) );
                h.nameByte = ia;
                h.line     = ts_node_start_point( ch ).row + 1;
            }
        }
        if( h.level >= 1 && !h.name.empty() )
        {
            h.startByte = a;
            h.sigEnd    = b;
            out.headings.push_back( std::move( h ) );
        }
        return;
    }
    if( !inQuote && std::strcmp( type, "setext_heading" ) == 0 )
    {
        MdHeading           h;
        const std::uint32_t n = ts_node_named_child_count( node );
        for( std::uint32_t i = 0; i < n; ++i )
        {
            TSNode      ch = ts_node_named_child( node, i );
            const char* ct = ts_node_type( ch );
            if( std::strcmp( ct, "setext_h1_underline" ) == 0 ) { h.level = 1; }
            else if( std::strcmp( ct, "setext_h2_underline" ) == 0 ) { h.level = 2; }
            else if( std::strcmp( ct, "paragraph" ) == 0 )
            {
                const std::uint32_t pn = ts_node_named_child_count( ch );
                for( std::uint32_t j = 0; j < pn; ++j )
                {
                    TSNode in = ts_node_named_child( ch, j );
                    if( std::strcmp( ts_node_type( in ), "inline" ) == 0 )
                    {
                        const std::uint32_t ia = ts_node_start_byte( in );
                        h.name     = mdCleanHeadingText( src.substr( ia, ts_node_end_byte( in ) - ia ) );
                        h.nameByte = ia;
                        h.line     = ts_node_start_point( in ).row + 1;
                    }
                }
            }
        }
        if( h.level >= 1 && !h.name.empty() )
        {
            h.startByte = a;
            h.sigEnd    = b;
            out.headings.push_back( std::move( h ) );
        }
        return;
    }
    const bool          quoteHere = inQuote || std::strcmp( type, "block_quote" ) == 0;   // a quoted heading is
    const std::uint32_t n         = ts_node_named_child_count( node );                    // quoted content, not structure
    for( std::uint32_t i = 0; i < n; ++i )
    {
        mdWalk( ts_node_named_child( node, i ), src, quoteHere, depth + 1, out );
    }
}

} // namespace mdtier

void extractMarkdown( std::uint32_t fileId, std::string_view src, std::string_view stem, TSNode root,
                      std::vector<RawDef>& defs, std::vector<RawRef>& refs )
{
    using mdtier::MdHeading;

    // (1) file-level node — span [0,size) ⇒ the lexical scorer indexes the whole fact body; cross-file
    // links land here. bodyByte stays 0 (no signature/body split — this node IS the whole doc).
    // nameByte = src.size() (EOF), NOT 0: (fileId, nameByte) is the global dedup identity, and a SETEXT
    // heading whose paragraph opens the file puts its name at byte 0 — with nameByte 0 the file node and
    // that heading TIED on every sort key (same kind, same startByte, and an equal endByte whenever the
    // first heading's span runs to EOF), so std::sort's instability let the unique() survivor flip with
    // worker arrival order (caught 2026-08-12: bench scoreboards flapping in --merge-scout's changed set).
    // No identifier can START at EOF, so this identity is collision-free by construction.
    {
        RawDef d;
        d.fileId = fileId; d.line = 1; d.startByte = 0; d.endByte = std::uint32_t( src.size() );
        d.nameByte = std::uint32_t( src.size() ); d.bodyByte = 0; d.kind = SymKind::Section; d.lang = Lang::Markdown;
        d.name.assign( stem );
        defs.push_back( std::move( d ) );
    }

    mdtier::MdWalkOut walk;
    mdtier::mdWalk( root, src, false, 0, walk );

    // The walk is preorder ⇒ headings and opaque ranges arrive in byte order; VERIFY rather than re-sort
    // (a re-sort would hide a walk-order bug behind deterministic-looking output).
    for( std::size_t i = 1; i < walk.headings.size(); ++i )
    {
        VERIFY( walk.headings[ i - 1 ].startByte <= walk.headings[ i ].startByte );
    }

    // (2) section spans + hierarchy over the MERGED heading list: endByte = next same-or-higher heading's
    // start (else EOF); scope = nearest earlier heading with a strictly shallower level.
    for( std::size_t i = 0; i < walk.headings.size(); ++i )
    {
        MdHeading&    h       = walk.headings[ i ];
        std::uint32_t spanEnd = std::uint32_t( src.size() );
        for( std::size_t j = i + 1; j < walk.headings.size(); ++j )
        {
            if( walk.headings[ j ].level <= h.level )
            {
                spanEnd = walk.headings[ j ].startByte;
                break;
            }
        }
        h.endByte = spanEnd;

        std::string scope;
        for( std::size_t p = i; p > 0; --p )   // p-- in the condition wraps at 0 under -fsanitize=integer (G1)
        {
            if( walk.headings[ p - 1 ].level < h.level )
            {
                scope = walk.headings[ p - 1 ].name;
                break;
            }
        }

        RawDef d;
        d.fileId    = fileId;
        d.line      = h.line;
        d.startByte = h.startByte;
        d.endByte   = spanEnd;
        d.nameByte  = h.nameByte;
        d.bodyByte  = h.sigEnd;    // signature = the heading construct; [bodyByte, endByte) = the section body
        d.kind      = SymKind::Section;
        d.lang      = Lang::Markdown;
        d.name      = h.name;
        d.scope     = std::move( scope );
        defs.push_back( std::move( d ) );
    }

    // opaque-range membership for the line scan below. Ranges arrive in byte order and never nest (every
    // opaque node type is a leaf block for the walk), so a linear cursor suffices.
    const auto& opaque       = walk.opaque;
    std::size_t opaqueCursor = 0;
    const auto  inOpaque     = [ & ]( std::uint32_t pos ) noexcept
    {
        while( opaqueCursor < opaque.size() && opaque[ opaqueCursor ].second <= pos ) { ++opaqueCursor; }
        return opaqueCursor < opaque.size() && opaque[ opaqueCursor ].first <= pos;
    };

    // link-target handling shared by inline links, reference definitions and (via slug) anchors.
    // Cross-file: [x](other.md) / [x](../a/other.md#frag) → ref named by the target's STEM (the resolve
    // ladder's same-dir preference lands it on other.md's file node, exactly like [[other]]). Anchors:
    // [x](#slug) → pending, resolved against THIS file's headings once they are all known.
    std::vector<std::pair<std::uint32_t, std::string>> pendingAnchors;   // (refByte, slug)
    const auto emitLinkTarget = [ & ]( std::string_view target, std::uint32_t refByte )
    {
        if( target.size() >= 2 && target.front() == '<' && target.back() == '>' )
        {
            target = target.substr( 1, target.size() - 2 );
        }
        if( const std::size_t sp = target.find_first_of( " \t" ); sp != std::string_view::npos )
        {
            target = target.substr( 0, sp );   // a following "title" is not part of the destination
        }
        if( target.empty() )
        {
            return;
        }
        if( target.front() == '#' )
        {
            std::string slug;
            for( const char c : target.substr( 1 ) ) { slug += ( c >= 'A' && c <= 'Z' ) ? char( c - 'A' + 'a' ) : c; }
            pendingAnchors.emplace_back( refByte, std::move( slug ) );
            return;
        }
        if( const std::size_t frag = target.find( '#' ); frag != std::string_view::npos )
        {
            target = target.substr( 0, frag );   // cross-file anchor part deferred (stem edge only, disclosed)
        }
        const bool isMd = target.size() > 3 && ( target.ends_with( ".md" ) || target.ends_with( ".markdown" ) );
        if( !isMd )
        {
            return;   // http/image/other targets are not doc→doc edges
        }
        const std::size_t slash = target.find_last_of( '/' );
        std::string_view  base  = ( slash == std::string_view::npos ) ? target : target.substr( slash + 1 );
        base = base.substr( 0, base.rfind( '.' ) );
        if( !base.empty() )
        {
            RawRef r;
            r.fileId = fileId; r.startByte = refByte; r.lang = Lang::Markdown; r.isInherit = false;
            r.name.assign( base );
            refs.push_back( std::move( r ) );
        }
    };

    // (4)+(5) the inline line scan: `backtick` mentions and [text](target) links — outside every opaque
    // range. Line-based exactly as before the grammar landed; the AST replaces only the hand-rolled fence
    // toggle (which knew ```/~~~ but not html blocks, front-matter or indented code).
    for( std::size_t i = 0; i < src.size(); )
    {
        const std::size_t lineStart = i;
        std::size_t       j         = i;
        while( j < src.size() && src[ j ] != '\n' )
        {
            ++j; // [lineStart, j) = this line, no newline
        }
        if( inOpaque( std::uint32_t( lineStart ) ) )
        {
            i = ( j < src.size() ) ? j + 1 : j;
            continue;
        }
        std::string_view line = src.substr( lineStart, j - lineStart );
        if( !line.empty() && line.back() == '\r' )
        {
            line.remove_suffix( 1 ); // CRLF: drop the trailing CR — LF/CRLF byte-identity
        }

        // inline-code `identifiers` → doc→code mentions; resolved to real code symbols in buildGraph
        // (stored in g.mentions, OUT of the call graph). Accepts only clean idents (len≥3).
        for( std::size_t b = 0; b + 1 < line.size(); )
        {
            if( line[ b ] != '`' ) { ++b; continue; }
            std::size_t e = b + 1;
            while( e < line.size() && line[ e ] != '`' )
            {
                ++e;
            }
            if( e >= line.size() )
            {
                break; // unclosed backtick on this line
            }
            std::string_view span = line.substr( b + 1, e - b - 1 );
            if( const std::size_t p = span.find( '(' ); p != std::string_view::npos )
            {
                span = span.substr( 0, p ); // `foo()` → foo
            }
            if( const std::size_t c = span.rfind( "::" ); c != std::string_view::npos )
            {
                span = span.substr( c + 2 ); // `A::b` → b
            }
            bool ok = span.size() >= 3 && ( ( span.front() >= 'A' && span.front() <= 'Z' ) || ( span.front() >= 'a' && span.front() <= 'z' ) || span.front() == '_' );
            for( std::size_t k = 0; ok && k < span.size(); ++k )
            { const char ch = span[ k ]; ok = ( ch >= 'A' && ch <= 'Z' ) || ( ch >= 'a' && ch <= 'z' ) || ( ch >= '0' && ch <= '9' ) || ch == '_'; }
            if( ok )
            {
                RawRef rr;
                rr.fileId = fileId;  rr.startByte = std::uint32_t( lineStart + b );  rr.lang = Lang::Markdown;
                rr.isInherit = false;  rr.isDocLink = true;  rr.name.assign( span );
                refs.push_back( std::move( rr ) );
            }
            b = e + 1;
        }

        // [text](target) links (images ride along; non-.md targets drop in emitLinkTarget). [[wikilinks]]
        // are NOT handled here — their own scan below keeps its historical shape.
        for( std::size_t b = 0; b + 1 < line.size(); ++b )
        {
            if( line[ b ] != '[' )
            {
                continue;
            }
            if( line[ b + 1 ] == '[' )
            {
                ++b;   // a [[wikilink]] — skip both brackets so its inner text is not read as a link
                continue;
            }
            const std::size_t close = line.find( ']', b + 1 );
            if( close == std::string_view::npos )
            {
                break;
            }
            if( close + 1 < line.size() && line[ close + 1 ] == '(' )
            {
                const std::size_t rp = line.find( ')', close + 2 );
                if( rp != std::string_view::npos )
                {
                    emitLinkTarget( line.substr( close + 2, rp - close - 2 ), std::uint32_t( lineStart + b ) );
                    b = rp;
                    continue;
                }
            }
            b = close;
        }

        if( j < src.size() )
        {
            i = j + 1;
        }
        else
        {
            i = j;
        }
    }

    // reference-style definitions ([label]: target) — destinations straight off the AST.
    for( const auto& [ da, db ] : walk.refDefs )
    {
        emitLinkTarget( src.substr( da, db - da ), da );
    }

    // (5b) [[wikilink]] edges: [[slug]] / [[slug|text]] / [[slug#sec]] → a ref from this file's node to
    // the node named `slug`. The resolver makes it a same-dir file→file edge; dangling links drop.
    // Opaque-aware now: a [[link]] inside a fence/html block/front-matter is quoted text, not an edge.
    {
        std::size_t wikiCursor = 0;   // the shared inOpaque cursor is already past EOF — use a fresh one
        const auto  wikiOpaque = [ & ]( std::uint32_t pos ) noexcept
        {
            while( wikiCursor < opaque.size() && opaque[ wikiCursor ].second <= pos ) { ++wikiCursor; }
            return wikiCursor < opaque.size() && opaque[ wikiCursor ].first <= pos;
        };
        for( std::size_t i = 0; i + 1 < src.size(); ++i )
        {
            if( src[ i ] != '[' || src[ i + 1 ] != '[' || wikiOpaque( std::uint32_t( i ) ) )
            {
                continue;
            }
            const std::size_t open = i + 2;
            std::size_t       e    = open;
            while( e + 1 < src.size() && src[ e ] != '\n' && !( src[ e ] == ']' && src[ e + 1 ] == ']' ) )
            {
                ++e;
            }
            if( e + 1 >= src.size() || src[ e ] != ']' || src[ e + 1 ] != ']' ) { i = e; continue; }   // no closing ]] on this line
            std::string_view slug = src.substr( open, e - open );
            for( std::size_t k = 0; k < slug.size(); ++k )
            {
                if( slug[ k ] == '|' || slug[ k ] == '#' )
                {
                    slug = slug.substr( 0, k );
                    break;
                }
            }
            while( !slug.empty() && slug.front() == ' ' )
            {
                slug.remove_prefix( 1 );
            }
            while( !slug.empty() && slug.back() == ' ' )
            {
                slug.remove_suffix( 1 );
            }
            if( !slug.empty() )
            {
                RawRef r;
                r.fileId = fileId; r.startByte = std::uint32_t( i ); r.lang = Lang::Markdown; r.isInherit = false;
                r.name.assign( slug );
                refs.push_back( std::move( r ) );
            }
            i = e + 1;   // past the closing ]]
        }
    }

    // (5c) anchors: [x](#slug) → the heading whose GitHub slug matches, in THIS file (first match wins on
    // a collision — GitHub's -1/-2 suffixes are not modelled). Dangling anchors drop, like wikilinks.
    for( const auto& [ refByte, slug ] : pendingAnchors )
    {
        for( const MdHeading& h : walk.headings )
        {
            if( mdtier::mdSlugOf( h.name ) == slug )
            {
                RawRef r;
                r.fileId = fileId; r.startByte = refByte; r.lang = Lang::Markdown; r.isInherit = false;
                r.name = h.name;
                refs.push_back( std::move( r ) );
                break;
            }
        }
    }
}
}   // namespace — ingest_docs.h section of ingest.cpp

}   // namespace rw
