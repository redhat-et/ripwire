// ingest.cpp — Phase 2 INGEST. Deterministic crawl + tree-sitter tags-query extraction.
//
// Pipeline:
//   crawl -> skip-filter -> SORT paths (byte order) -> per-file parse + ONE tags query ->
//   collect raw defs/refs -> assign Symbol ids in (file,line,name) order ->
//   attribute each Reference to its enclosing definition by byte-span containment.
//
// Single-threaded (v1). Never throws: every recoverable problem degrades + DEGRADED_PATH_ALERT.

#include "ingest.h"
#include "docparse.h"          // P1-B: non-code document ingest (notebooks/html/csv + markitdown bridge)
#include "arch.h"              // T5: relForHash — root-relative path key, reused for cache portability
#include "quality.h"           // A5: cacheDirLadder + sweepStaleCacheBlobsOnce — the cache-dir hygiene hook (saveCache)
#include "embedded_queries.h"  // configure-generated constexpr tags.scm table; no runtime source-tree dependency
#include "infra/hashutil.h"    // sanitizer-clean modulo-2^64 FNV multiplication
#include "infra/namesplit.h"   // H4: stripTemplateArgs for the C++ qualified-call re-split (shared with tracelocus.h)
#include "infra/fixedStr.h"    // rw::findByte — the NEON/SSE2 byte scan buildNewlineOffsets rides
#include "lexindex.h"          // B0.1/B0.2: shared subtoken state machine + per-def lexical statistics builder
#include "didyoumean.h"        // octocode F3: boundedEditDistance/nearestNameByEditDistance — the ONE near-miss
                                // primitive, reused for a --match query's node-kind tokens (see nearestNodeKindHint)
#include "pattern.h"           // R2: the pattern surface's compiler + matcher — AstWalk::Pattern rides the shared file walk

#include "infra/Diagnostics.h"
#include "infra/profileScope.h"  // PROFILE_SCOPE self-profiling — gated by PROFILE_ENABLED (off unless -DRIPWIRE_PROFILE=ON)

#include <tree_sitter/api.h>

#include <algorithm>
#include <array>
#include <bit>                 // std::bit_floor — the cold-path reserve rounds to a power of two
#include <cctype>
#include <chrono>              // A4-P7: wall-clock cache-write timestamp for the racy-git rule
#include <cstdio>
#include <cstdlib>             // std::getenv — RIPWIRE_CACHE_STATS drift observable
#include <cstring>
#include <sys/stat.h>          // A4-P7: stat() for the (size,mtime) warm-run shortcut
#include <unistd.h>            // getpid — unique per-process cache temp name
#include <filesystem>
#include <fstream>
#include <limits>
#include <condition_variable>
#include <mutex>
#include <numeric>
#include <string>
#include <span>
#include <string_view>
#include <atomic>
#include <regex>
#include <thread>
#include <type_traits>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

#ifdef RIPWIRE_FUSE_PROBE
// ── Side-capture walk probe (compile-time opt-in; absent from every shipped build) ────────────────────
// The instrument behind the walk fusion in captureSideFacts. It separates the two things that "one more
// pass" can mean, because only one of them is what the fusion removes:
//   * STREAM POPS  — frames popped off a walk stack. One per node PER WALK, so N back-to-back walks over
//                    the same tree cost N x. This is the tree-streaming cost the fusion attacks.
//   * VISITOR CALLS — per-node matching work for one pass. Fusion does NOT reduce these; a pass still
//                    inspects every node it used to. If these move, a fact was dropped or double-counted.
// Compiled out entirely unless -DRIPWIRE_FUSE_PROBE is on the command line, so the plain/asan/profile
// builds are unaffected. Everything lands on STDERR — stdout is the XML map under a byte-identity gate.
//
//    cmake -S . -B build_probe -DCMAKE_CXX_FLAGS=-DRIPWIRE_FUSE_PROBE && cmake --build build_probe -j
//    TMPDIR=$(mktemp -d) ./build_probe/ripwire <corpus> >/dev/null      # TMPDIR forces a cold parse
namespace fuseprobe
{
enum PassId : int { kInc = 0, kFfi = 1, kRoutes = 2, kRustImpls = 3, kBinds = 4, kUses = 5, kPassCount = 6 };
inline const char* const kPassName[ kPassCount ] = { "captureIncludes", "captureFfi", "captureRoutes", "captureRustImpls", "captureBindings", "captureUses" };

inline thread_local std::uint64_t tlNodes[ kPassCount ] = {};   // visitor calls, this thread, cumulative
inline std::atomic<std::uint64_t> gNodes[ kPassCount ];         // visitor calls per pass, corpus-wide
inline std::atomic<std::uint64_t> gFiles[ kPassCount ];         // files on which the pass saw >=1 node
inline std::atomic<std::uint64_t> gHist[ kPassCount + 1 ];      // files by count of passes that saw a node
inline std::atomic<std::uint64_t> gFilesTotal { 0 };
inline std::atomic<std::uint64_t> gNodesMaxPass { 0 };          // sum of the per-file LARGEST pass = AST-size proxy
inline std::atomic<std::uint64_t> gStreamPops { 0 };            // THE fusion metric: frames popped, all walks

inline void bump( int pass ) noexcept { ++tlNodes[ pass ]; }
inline void pop() noexcept { gStreamPops.fetch_add( 1, std::memory_order_relaxed ); }

struct Dump
{
    ~Dump()
    {
        const std::uint64_t files = gFilesTotal.load();
        std::uint64_t       calls = 0;
        for( int p = 0; p < kPassCount; ++p )
        {
            calls += gNodes[ p ].load();
        }
        std::fprintf( stderr, "\n[fuseprobe] files_with_a_parsed_tree=%llu\n", (unsigned long long) files );
        std::fprintf( stderr, "[fuseprobe] %-18s %13s %10s %8s\n", "pass", "visitor_calls", "files", "%files" );
        for( int p = 0; p < kPassCount; ++p )
        {
            const std::uint64_t f = gFiles[ p ].load();
            std::fprintf( stderr, "[fuseprobe] %-18s %13llu %10llu %7.1f%%\n", kPassName[ p ], (unsigned long long) gNodes[ p ].load(),
                          (unsigned long long) f, files ? 100.0 * double( f ) / double( files ) : 0.0 );
        }
        const std::uint64_t astProxy = gNodesMaxPass.load();
        const std::uint64_t pops     = gStreamPops.load();
        std::fprintf( stderr, "[fuseprobe] visitor_calls=%llu  ast_size_proxy(sum of per-file max pass)=%llu\n",
                      (unsigned long long) calls, (unsigned long long) astProxy );
        std::fprintf( stderr, "[fuseprobe] STREAM_POPS=%llu  streams_per_node=%.2fx  <-- the number fusion moves\n",
                      (unsigned long long) pops, astProxy ? double( pops ) / double( astProxy ) : 0.0 );
        std::fprintf( stderr, "[fuseprobe] files by number of passes that SAW a node:\n" );
        for( int k = 0; k <= kPassCount; ++k )
        {
            const std::uint64_t f = gHist[ k ].load();
            if( f != 0 )
            {
                std::fprintf( stderr, "[fuseprobe]   %d pass%s : %10llu files (%5.1f%%)\n", k, k == 1 ? " " : "es", (unsigned long long) f,
                              files ? 100.0 * double( f ) / double( files ) : 0.0 );
            }
        }
        std::fflush( stderr );
    }
};
inline Dump gDump;
}   // namespace fuseprobe
    #define FUSEPROBE_BUMP( p ) ::fuseprobe::bump( ::fuseprobe::p )
    #define FUSEPROBE_POP()     ::fuseprobe::pop()
#else
    #define FUSEPROBE_BUMP( p ) ( (void) 0 )
    #define FUSEPROBE_POP()     ( (void) 0 )
#endif

// ---- tree-sitter grammar entry points (each grammar's OBJECT lib exports one) ----
extern "C"
{
    const TSLanguage* tree_sitter_cpp( void );
    const TSLanguage* tree_sitter_python( void );
    const TSLanguage* tree_sitter_go( void );
    const TSLanguage* tree_sitter_rust( void );
    const TSLanguage* tree_sitter_typescript( void );
    const TSLanguage* tree_sitter_tsx( void );
    const TSLanguage* tree_sitter_swift( void );
    const TSLanguage* tree_sitter_objc( void );
    const TSLanguage* tree_sitter_javascript( void );
    const TSLanguage* tree_sitter_bash( void );
    const TSLanguage* tree_sitter_java( void );
    const TSLanguage* tree_sitter_ruby( void );
    const TSLanguage* tree_sitter_json( void );
    const TSLanguage* tree_sitter_toml( void );
    const TSLanguage* tree_sitter_yaml( void );
    const TSLanguage* tree_sitter_c_sharp( void );
    const TSLanguage* tree_sitter_c( void );
    const TSLanguage* tree_sitter_cuda( void );
    const TSLanguage* tree_sitter_markdown( void );
    const TSLanguage* tree_sitter_php( void );
    const TSLanguage* tree_sitter_lua( void );
}

// ── the ingest-family sections (2026-08-29 split) ────────────────────────────────────────────────────
// Each ingest_*.h below is a SECTION of this translation unit, not a library header: it reopens
// `namespace rw` AND the unnamed namespace inside it (one TU, one unnamed namespace), sees every
// #include and grammar entry point above, and is included exactly once, right here — the same
// mechanism as main.cpp's verb-family split, with RIPWIRE_INGEST_TU as the enforcement: any other
// includer is a compile error. Order matters — a later section may call an earlier one (the
// side-capture section calls the metrics section's complexityOf; everything may call the crawl
// section's language table). The --match/--lint tail (ingest_astquery.h) is rw-level rather than
// unnamed and is included at the very END of this file, exactly where its content sat before the
// split.
#define RIPWIRE_INGEST_TU 1
#include "ingest_crawl.h"
#include "ingest_cache.h"
#include "ingest_metrics.h"
#include "ingest_relations.h"


namespace rw
{

namespace
{

// One parser, reused across files (single-threaded). Language set per file.
struct ParserGuard
{
    TSParser* p = ts_parser_new();
    ~ParserGuard()
    {
        if( p )
        {
            ts_parser_delete( p );
        }
    }
};

// Verify the grammar's ABI is in range for the linked core. v0.26.9 renamed the
// accessor to ts_language_abi_version; the [MIN_COMPATIBLE, LANGUAGE_VERSION] band is unchanged.
bool grammarAbiOk( const TSLanguage* lang ) noexcept
{
    const uint32_t v = ts_language_abi_version( lang );
    return v >= TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION && v <= TREE_SITTER_LANGUAGE_VERSION;
}

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

// E#4 canonical-resolution helpers (C++; node-type names are tree-sitter-cpp's). For a call `A::b()` the
// @name node `b` sits in a qualified_identifier whose `scope` is `A` → qualifierOf returns the IMMEDIATE
// scope component ("A", or "B" from `A::B::b`). enclosingScopeOf walks ancestors to the nearest
// class/struct/namespace and returns its name (for in-class method DEFS). Both "" when absent → caller
// falls back to bare-name resolution (so non-C++ langs and unqualified calls are unaffected).
inline std::string immediateScope( std::string_view full )
{
    const std::size_t cc = full.rfind( "::" );
    return std::string( cc == std::string_view::npos ? full : full.substr( cc + 2 ) );
}

// ── H4 qualified-call re-split helpers ───────────────────────────────────────────────────────────────────
// The widened C++ call pattern (`qualified_identifier name: (_)`) binds the INNER node at every depth, so
// the captured text of a 3+-segment call still carries scope (`inner::targetFn`,
// `numeric_limits<std::size_t>::max`). These two helpers turn that text back into the (name, immediate
// qualifier) pair the canonical resolution tier keys on — the plain finalSegment() path cannot, because it
// truncates at the FIRST '<' and would name the second example `numeric_limits`.

// The four C++ cast keywords. tree-sitter-cpp parses `static_cast<T>( x )` as
// `call_expression function: (template_function name: (identifier))` — structurally identical to a real
// explicit-template-argument call — so the template_function reference pattern matches every cast in the
// tree (171 sites in this repo's src/ alone). A cast is not a call and must not mint a reference: it is
// VALID INPUT, not a corrupt invariant, so the capture loop simply skips it (never VERIFY, never
// DEGRADED_PATH_ALERT — nothing degraded). Query predicates cannot do this: passesPredicates is wired into
// --match/--lint only, not the tags pass (measured — a `#not-eq?` left --uses=static_cast at 165).
inline bool isCppCastKeyword( std::string_view name ) noexcept
{
    return name == "static_cast" || name == "reinterpret_cast" || name == "const_cast" || name == "dynamic_cast";
}

// First DIRECT child of `n` whose node type is `type`, or a null node when none exists — the one
// child-scan shape shared by the using-declaration keyword guard below and the phantom-`::` probe
// (hasPhantomScopeSeparator), so the two cannot drift into near-clones of each other.
inline TSNode firstChildOfType( TSNode n, const char* type ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t i = 0; i < childCount; ++i )
    {
        const TSNode child = ts_node_child( n, i );
        if( std::strcmp( ts_node_type( child ), type ) == 0 )
        {
            return child;
        }
    }
    return TSNode {};
}

// using-declaration re-exports (r9 loss bucket 1): TRUE when a C++ `using_declaration` node is a grammar
// KEYWORD form rather than a single-symbol re-export — `using namespace ns;` (its qualified spelling
// `using namespace lib::nested;` carries a qualified_identifier and so matches the tags pattern) or
// `using enum E;` (C++20; re-exports the ENUMERATORS, not the named type, so an import row for the type
// would over-claim). Both are VALID INPUT, skipped at capture time exactly like the cast keywords above:
// the grammar puts the keyword in an anonymous child with no field name, which a tags-query pattern
// cannot negate (passesPredicates is wired into --match/--lint only, never the tags pass).
inline bool usingDeclarationIsDirective( TSNode n ) noexcept
{
    return !ts_node_is_null( firstChildOfType( n, "namespace" ) ) || !ts_node_is_null( firstChildOfType( n, "enum" ) );
}

// Start index of `text`'s trailing C++ OPERATOR NAME (`operator>`, `operator<<`, `operator()`, `operator bool`),
// or npos when the name is a plain identifier. This must be consulted BEFORE any angle-depth scanning.
//
// WHY (found by the adversarial verifier, not by construction): an operator name is the one place a NAME
// legitimately carries `<`/`>` punctuation that is not a template-argument delimiter. Scanning
// `inner::operator>` right-to-left, the trailing `>` opens a group that never closes, so
// lastTopLevelScopeSep finds NO separator, the re-split is skipped, and the qualifier falls back to
// qualifierOf()'s OUTERMOST scope — measured binding `outer::inner::operator>( x, y )` to a decoy
// `outer::operator>` with ambiguous=0 and no disclosure at all. `operator>`, `operator>>`, `operator>=` and
// `operator->` are all poisoned that way; `operator<<` merely survived by luck (depth is clamped at zero, so
// its `<`s are ignored rather than balanced). Detecting the operator tail up front cures the whole family.
//
// The first two guards mirror finalSegment()'s own operator exemption (see it above) so the two cannot
// drift: the keyword must start a SEGMENT (index 0, or right after a `::`/`.`), and the character after it
// must not continue an identifier — so `operatorId` stays a plain name and takes the ordinary path.
//
// The third guard is what makes the name TRAILING, as the contract says (V3-L-2: `rfind` alone accepted
// `op::operator>::go` and split it into name `operator>::go` / qualifier `op` — unreachable from valid C++,
// since an operator cannot name a scope, but the function promised npos for anything that is not a trailing
// operator name and did not deliver it). A SYMBOLIC operator's name is the keyword plus a run of operator
// punctuation, and it must reach the END of the text; anything after that run means a further segment
// follows, so this is not the trailing name. A SPACE after the keyword instead marks the
// `operator <type>` family (conversion operators, `operator new`/`operator delete`), whose type half may
// itself contain `::` (`operator ns::Type`) — that IS the trailing name, so the punctuation run is not
// applied to it.
inline std::size_t operatorNameStart( std::string_view text ) noexcept
{
    constexpr std::string_view kOperator      = "operator";
    constexpr std::string_view kOperatorPunct = "+-*/%^&|~!=<>()[],";   // every char a C++ operator name may use

    const std::size_t op = text.rfind( kOperator );
    if( op == std::string_view::npos )
    {
        return std::string_view::npos;
    }

    const bool atSegmentStart = ( op == 0 ) || ( text[ op - 1 ] == ':' ) || ( text[ op - 1 ] == '.' );
    if( !atSegmentStart )
    {
        return std::string_view::npos;
    }

    // `operator` must be a whole token: `operatorId` is a plain identifier that merely starts with it.
    const std::size_t after = op + kOperator.size();                    // one-past `operator`
    if( after >= text.size() )
    {
        return op; // the bare keyword ends the text
    }
    if( std::isalnum( static_cast<unsigned char>( text[ after ] ) ) || text[ after ] == '_' )
    {
        return std::string_view::npos;
    }

    // `operator <type>` — the type half owns the rest of the text, `::` and all.
    if( std::isspace( static_cast<unsigned char>( text[after] ) ) )
    {
        return op;
    }

    // symbolic: the punctuation run IS the name, and it must run to the end or this is not the tail.
    std::size_t punctEnd = after;
    while( punctEnd < text.size() && kOperatorPunct.find( text[punctEnd] ) != std::string_view::npos )
    {
        ++punctEnd;
    }
    return punctEnd == text.size() ? op : std::string_view::npos;
}

// Index of the last `::` in `text` that sits at TEMPLATE-ARGUMENT DEPTH ZERO, or npos when there is none.
// Scanned in reverse (the LAST top-level separator is the one that splits name from scope), tracking `<`/`>`
// nesting so a `::` inside template arguments never splits: `tmplFn<a::B>` has NO top-level separator, while
// `numeric_limits<std::size_t>::max` has exactly one — at the `::` before `max`.
// PRECONDITION: `text` carries no trailing operator name. Depth is clamped at zero, which makes an
// operator spelling merely IGNORED rather than balanced — that is enough for `operator<<` and NOT enough for
// the `>` family, whose unmatched `>` would leave the depth pinned above zero and hide every separator. The
// caller checks operatorNameStart() first; do not weaken that ordering.
// The loop counts a 1-based CURSOR down to zero rather than the classic `for( i = n; i-- > 0; )`: that idiom
// wraps `i` to SIZE_MAX on its final test, which `-fsanitize=integer` reports as an unsigned-integer
// overflow (observed on this very function before this shape — the G1 build caught it on the fixture).
inline std::size_t lastTopLevelScopeSep( std::string_view text ) noexcept
{
    std::size_t angleDepth = 0;
    for( std::size_t cursor = text.size(); cursor > 0; --cursor )
    {
        const std::size_t charIndex = cursor - 1;
        const char        c         = text[ charIndex ];
        if( c == '>' )
        {
            ++angleDepth;
        }
        else if( c == '<' && angleDepth > 0 )
        {
            --angleDepth;
        }
        else if( c == ':' && angleDepth == 0 && charIndex > 0 && text[ charIndex - 1 ] == ':' )
        {
            return charIndex - 1;                                 // index of the FIRST ':' of the pair
        }
    }
    return std::string_view::npos;
}
// True when a qualified_identifier's `::` separator is a MISSING node — a zero-width token tree-sitter
// INSERTED during error recovery, not one that is written in the source. Recovery reaches for this shape
// whenever two identifiers sit adjacent where the grammar expected one, so `<ReturnType> name(...)` after
// an unknown leading keyword parses as `ReturnType::name` with a phantom `::`. That is exactly what MSL's
// `vertex GalleryVertexOut gallery_vertexSphere( … )` does under the C++ grammar (L4) — and the invented
// "scope" is the RETURN TYPE, so honouring it would publish `Out::f` for a free function and try to
// resolve calls against a class that never had that member. Valid C++ never produces a MISSING `::`, so
// this guard is inert on every well-formed parse.
inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept
{
    const TSNode sep = firstChildOfType( qualified, "::" );
    return !ts_node_is_null( sep ) && ts_node_is_missing( sep );   // no separator child at all → pre-existing behaviour untouched (false)
}
// The innermost `name:` link of a C++ qualified_identifier chain (C1 — the DEFINITION half of the §H4
// recursion). tree-sitter-cpp nests qualified_identifier RIGHT-recursively, so the tags pattern for an
// out-of-line definition at 2+ segments binds an INNER qualified_identifier rather than the identifier
// itself: for `void nsD::OuterD::InnerD::deep3()` the capture spans `OuterD::InnerD::deep3`. Descending to
// the last link hands back exactly the node the depth-1 pattern binds directly, which is what makes the
// widened capture need no special case anywhere downstream — three properties are restored at once:
//   * TEXT is the bare final name, so defNameFromCapture()/finalSegment() need no text re-split (the one
//     the REFERENCE side needs, because its capture may carry template arguments a '<'-truncation would
//     mangle — see lastTopLevelScopeSep). A def's captured chain is a declarator, and its final link is an
//     identifier or an operator_name, never a template_function.
//   * START BYTE is the identifier's own, so `nameByte`/`nameRow` keep pointing at the name a selector
//     (--expand=file:line, --grep attribution, the flipimpact line index) matches on.
//   * PARENT is the IMMEDIATE scope's qualified_identifier, which is the node qualifierOf() reads — so
//     `deep3` keys as `InnerD::deep3` rather than the outermost `nsD::deep3`, and the phantom-`::`
//     error-recovery guard is applied to the separator that actually qualifies the name.
// Returns `n` unchanged for every node that is not a qualified_identifier — i.e. for every capture that
// existed before this fix — so it is inert by construction on the depth-1 path.
// The hop cap is defensive only: each step moves strictly down a finite tree, so it cannot spin. A chain
// deeper than the cap would return a still-qualified node, which finalSegment() still names correctly (it
// splits on the last `::`); only the immediate-scope precision would degrade, so there is nothing here a
// DEGRADED_PATH_ALERT could truthfully claim.
inline TSNode innermostQualifiedName( TSNode n ) noexcept
{
    constexpr int kMaxQualifierHops = 32;   // `a::b::c::…` past 32 segments is not written C++
    for( int hop = 0; hop < kMaxQualifierHops; ++hop )
    {
        if( ts_node_is_null( n ) || std::strcmp( ts_node_type( n ), "qualified_identifier" ) != 0 )
        {
            break;
        }
        const TSNode inner = ts_node_child_by_field_name( n, "name", 4 );
        if( ts_node_is_null( inner ) )
        {
            break;
        }
        n = inner;
    }
    return n;
}

// The four name facts captureTagsFacts carries per match: the @name node itself, its text, its start byte
// and its 0-based row. Named as a struct so the re-seat below can hand back all four at once and be
// consumed by a structured binding.
struct DefNameFacts
{
    TSNode           node;
    std::string_view text;
    std::uint32_t    byte;
    std::uint32_t    row;
};

// C1 (memgraph F1): the re-seat a C++ out-of-line DEFINITION needs when the tags pattern bound an INNER
// qualified_identifier — i.e. when the definition was written with two or more qualifier segments. Returns
// the innermost link's four facts, or a NULL node meaning "nothing to re-seat", which is the answer for
// every capture that existed before this fix (a bare identifier/operator_name is not a qualified_identifier,
// so innermostQualifiedName hands it straight back).
//
// `applies` carries the caller's whole precondition (this is a DEFINITION capture, in a C++ file) rather
// than being tested at the call site: captureTagsFacts is the file's largest function and every branch
// point spent there is measured — see the note at the bottom of this comment.
//
// The descent has to happen before ANY consumer reads the facts — the gated-capture drop, the RawDef built
// from them, and qualifierOf()'s parent lookup must all see exactly what the depth-1 pattern hands over.
//
// DEFS ONLY, deliberately. The REFERENCE path's capture may carry template arguments (`numeric_limits<
// std::size_t>::max`) that its own text re-split (operatorNameStart + lastTopLevelScopeSep) is written to
// survive; descending there would change resolved edges, which §H4's arms pin and this fix has no business
// moving. A definition's chain is a declarator, whose final link is an identifier or an operator_name.
//
// This lives OUTSIDE captureTagsFacts for the reason defNameFromCapture states above: that function is
// already the file's largest and well over the complexity bar, and a branch buried in it is both invisible
// and a measured --quality-delta regression (this one scored +11 cx / +27 LOC inline before it moved here).
inline DefNameFacts cppDefNameReseat( bool applies, TSNode nameNode, std::string_view src ) noexcept
{
    constexpr DefNameFacts kNoReseat { TSNode {}, {}, 0u, 0u };
    if( !applies || ts_node_is_null( nameNode ) )
    {
        return kNoReseat;
    }
    const TSNode inner = innermostQualifiedName( nameNode );
    if( ts_node_eq( inner, nameNode ) )
    {
        return kNoReseat;
    }
    const std::uint32_t a = ts_node_start_byte( inner );
    const std::uint32_t b = ts_node_end_byte( inner );
    if( a > b || b > src.size() )
    {
        return kNoReseat;   // out-of-range span — keep the capture's own facts, exactly as the caller did
    }
    return { inner, src.substr( a, b - a ), a, ts_node_start_point( inner ).row };
}
inline std::string qualifierOf( TSNode nameNode, std::string_view src )
{
    const TSNode parent = ts_node_parent( nameNode );
    if( ts_node_is_null( parent ) || std::strcmp( ts_node_type( parent ), "qualified_identifier" ) != 0 )
    {
        return {};
    }
    if( hasPhantomScopeSeparator( parent ) )
    {
        return {}; // error-recovery artefact, not a written qualification
    }
    const TSNode scope = ts_node_child_by_field_name( parent, "scope", 5 );
    if( ts_node_is_null( scope ) )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( scope ), b = ts_node_end_byte( scope );
    return ( a <= b && b <= src.size() ) ? immediateScope( src.substr( a, b - a ) ) : std::string{};
}
// ── H4 RUST qualified-call helpers (W1-MEASURE verdict) ─────────────────────────────────────────────────
// W1 measured that the Rust PATTERN ALONE under-delivers: Rust defs carried scope="" (canonByName was fed
// only by the C++/Python arms) and Rust refs carried qualifier="", so every widened `Widget::new()` fell to
// the BARE-NAME spray — and two types defining `new` in DIFFERENT directories then hit the tier-3
// unique-or-DROP rule, killing BOTH edges with no `amb=` and no `unresolved=` movement. So the pattern ships
// WITH a qualifier (ref side) and a scope (def side); together they key the canonical `qualifier::name` tier
// that C++ already uses, and idiomatic Rust resolves PRECISELY instead of silently vanishing.


// True when `s` is spelled as a plain Rust identifier. The qualifier is a canonByName KEY half, so a segment
// that is not an identifier (`<T as Trait>`, a stray `>` from an unbalanced spelling) can only ever produce a
// key that matches nothing — returning "" instead routes the ref to the bare-name ladder, which is the honest
// fallback. Cheap, and it keeps garbage out of a lookup table.
inline bool isRustIdentifier( std::string_view s ) noexcept
{
    if( s.empty() || ( s[0] >= '0' && s[0] <= '9' ) )
    {
        return false;
    }
    for( const char c : s )
    {
        if( !( ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_' ) )
        {
            return false;
        }
    }
    return true;
}

// The LAST segment of a Rust path spelling — the qualifier a `path::name` call keys on.
//   `Widget`                          → "Widget"        (2-segment `Widget::new()`)
//   `util::deep`                      → "deep"          (3-segment `util::deep::deepfn()`; immediate scope, as C++)
//   `Vec::<u32>`                      → "Vec"           (TURBOFISH, decided below)
//   `std::collections::HashMap::<K,V>` → "HashMap"
//   `<T as Trait>`                    → ""              (not an identifier → bare-name ladder)
// TURBOFISH DECISION (the round owes this one explicitly): Rust spells type arguments in expression position
// as `Vec::<u32>`, i.e. the `::` SURVIVES stripping the `<…>` group, where C++'s `Vec<u32>` does not. So the
// order is: strip the trailing balanced group FIRST (namesplit::stripTemplateArgs — never rfind, which would
// split inside `Foo<a::B>`), THEN drop the separator the turbofish left behind, THEN take the last TOP-LEVEL
// `::` segment. `Vec::<u32>` → `Vec::` → `Vec` → qualifier "Vec", which is the type the call actually names.
inline std::string rustPathSegment( std::string_view pathText ) noexcept
{
    std::string_view text = namesplit::stripTemplateArgs( pathText );          // `Vec::<u32>` → `Vec::`
    if( text.size() >= 2 && text.substr( text.size() - 2 ) == "::" )
    { // the turbofish `::<` separator
        text.remove_suffix( 2 );
    }
    const std::size_t sep = lastTopLevelScopeSep( text );
    const std::string_view seg = ( sep == std::string_view::npos ) ? text : text.substr( sep + 2 );
    return isRustIdentifier( seg ) ? std::string( seg ) : std::string{};
}

// The nearest enclosing Rust scope owner's NAME, walking ancestors from `node`.
//   `impl Widget { … }` / `impl Trait for Widget { … }` → the `type:` field ("Widget") — the IMPLEMENTOR in
//        both spellings, which is exactly what a caller writes before `::`. `impl<T> Foo<T>` → "Foo".
//   `trait Shape { fn area(&self) { … } }` → "Shape"  (a defaulted trait method is called `Shape::area`)
//   `mod util { … }`                      → "util"    (only when `includeModules`)
// `includeModules=false` is the `Self::` resolution mode: `Self` is only meaningful inside an impl/trait, so a
// module must NOT be allowed to answer for it. Node kinds are Rust-unique, which is why this stays a separate
// function from enclosingScopeOf rather than three more arms in its shared list.
inline std::string rustEnclosingScopeOf( TSNode node, std::string_view src, bool includeModules )
{
    for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        const bool  isImpl  = std::strcmp( t, "impl_item" )  == 0;
        const bool  isTrait = std::strcmp( t, "trait_item" ) == 0;
        const bool  isMod   = includeModules && std::strcmp( t, "mod_item" ) == 0;
        if( !isImpl && !isTrait && !isMod )
        {
            continue;
        }

        // impl carries the implementor under `type:`; trait/mod carry their own `name:`. Anonymous/ill-formed
        // (empty text) yields "" — no usable scope — which is the same degrade as "no owner above".
        const TSNode owner = isImpl ? ts_node_child_by_field_name( p, "type", 4 ) : ts_node_child_by_field_name( p, "name", 4 );
        // V3 L-1: a container is not its OWN scope. `mod util { … }`'s definition node IS that `name:` child, so
        // the first ancestor found is the module itself and `util` would be published as `util::util` (likewise
        // `Shape::Shape`) — a self-scope in the canonical-id space, which is what ids are keyed on. Keep walking
        // to the NEXT owner instead, so a nested `mod deep` inside `mod util` still scopes to "util".
        if( !ts_node_is_null( owner ) && ts_node_eq( owner, node ) )
        {
            continue;
        }
        return rustPathSegment( nodeTextOf( owner, src ) );                      // `Foo<T>` → "Foo"; `a::B` → "B"
    }
    return {};
}

// Qualifier of a Rust CALL reference whose @name is the final segment of a `scoped_identifier`:
// `Widget::new()` → "Widget", `util::deep::deepfn()` → "deep", `Vec::<u32>::new()` → "Vec".
// Returns "" for every other shape (bare `free()`, `w.bump()`, `generic::<u32>()`, and the crate-root `::f()`
// spelling, which has no `path:` child) → those keep the pre-existing bare-name resolution untouched.
// This is a CALL ref (isInherit=false). graph.h's Rust `impl Trait for T` CHA path reads `qualifier` too, but
// only behind `if( !ir.isInherit ) continue;`, so the two uses of the field cannot collide — gated by
// test/rustqualcheck.sh §8.
inline std::string rustQualifierOf( TSNode nameNode, std::string_view src )
{
    const TSNode parent = ts_node_parent( nameNode );
    if( ts_node_is_null( parent ) || std::strcmp( ts_node_type( parent ), "scoped_identifier" ) != 0 )
    {
        return {};
    }

    std::string qualifier = rustPathSegment( nodeTextOf( ts_node_child_by_field_name( parent, "path", 4 ), src ) );
    // `Self::helper()` — resolve `Self` to the ENCLOSING impl/trait type at EXTRACTION time, so the ref keys
    // the same canonical entry the def side wrote (`Widget::helper`). Precedent: captureRustImpls already
    // reads an impl header's `type:` for inherit refs. Falls back to bare-name when there is no impl above.
    if( qualifier == "Self" )
    {
        qualifier = rustEnclosingScopeOf( nameNode, src, /*includeModules=*/false );
    }
    return qualifier;
}

inline std::string enclosingScopeOf( TSNode node, std::string_view src )
{
    for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        // class/struct/namespace owners across grammars (names don't collide between grammars):
        //   C++: class_specifier/struct_specifier/namespace_definition · Python: class_definition.
        // Each exposes a `name` field; the nearest one is the enclosing scope used for canonical resolution
        // and P2-D Rule-1 narrowing (a `self.m()`/`this->m()`/bare member call resolves to scope::m).
        const bool scopeOwner =    std::strcmp( t, "class_specifier" )     == 0 || std::strcmp( t, "struct_specifier" )    == 0
                                || std::strcmp( t, "namespace_definition" ) == 0 || std::strcmp( t, "class_definition" )    == 0;
        if( scopeOwner )
        {
            const TSNode nm = ts_node_child_by_field_name( p, "name", 4 );
            if( ts_node_is_null( nm ) )
            {
                return {}; // anonymous → no usable scope
            }
            const std::uint32_t a = ts_node_start_byte( nm ), b = ts_node_end_byte( nm );
            return ( a <= b && b <= src.size() ) ? std::string( src.substr( a, b - a ) ) : std::string{};
        }
    }
    return {};
}

// F5: a Swift LOCAL binding — `let a = f()` / `var b = ...` inside a function/closure body — parses to the
// same `property_declaration` node as a real stored/computed MEMBER property, so the @definition.var pattern
// captures it as a spurious top-level `var` symbol AND (being the nearest enclosing symbol above the body's
// call sites) STEALS the enclosing function's call edges. The discriminant: a `statements` node is the body of
// an executable block (function_body / lambda_literal / if/for/while/… ) and NEVER wraps a member property
// directly — a stored member is a child of class_body/enum_class_body/source_file, and a computed member's
// `statements` live inside its `computed_property` CHILD, below (not above) the property_declaration. So a
// `statements` ANCESTOR uniquely marks a local binding. Walk up from the property node; a `statements` before
// any type-body/file scope ⇒ local. Swift-only (gated by the caller); no other grammar reaches here.
inline bool isSwiftLocalBinding( TSNode declNode ) noexcept
{
    for( TSNode p = ts_node_parent( declNode ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        if( std::strcmp( t, "statements" ) == 0 )
        {
            return true;                                             // inside an executable block → local binding
        }
        // a member property's wrappers — reaching one first means it is NOT a local.
        if( std::strcmp( t, "class_body" ) == 0 || std::strcmp( t, "enum_class_body" ) == 0 || std::strcmp( t, "protocol_body" ) == 0 || std::strcmp( t, "source_file" ) == 0 )
        {
            return false;
        }
    }
    return false;
}

// ── L8: IN-FILE TEST SCOPE ───────────────────────────────────────────────────────────────────────────
// filter.h::isTestPath answers "is this a test?" from the PATH alone. Four mainstream conventions put
// test code INSIDE a production source file, where no path signal exists:
//
//   Rust    `#[cfg(test)] mod tests { … }` / `#[test] fn …` inside src/*.rs — the language's OWN
//           documented convention, so essentially every crate is affected.
//   Python  `class TestFoo:` / a module-level `def test_bar():` beside production defs.
//   JS/TS   helpers declared inside a `describe(…)` / `it(…)` / `test(…)` block.
//   C#      a `[Fact]` / `[Test]` / `[TestMethod]` member beside a production class.
//
// Measured on astral-sh/ruff (5945 files) before this existed: the #1-ranked symbol of the entire map
// was `CursorTest::builder`, a `#[cfg(test)]` helper inside `crates/ty_ide/src/lib.rs`, and
// `--ignore-tests` dropped 15,811 path-classified symbols WITHOUT changing the top-5 — the top-5 were
// all in-file tests the path filter cannot see.
//
// The bit is SYNTACTIC and PRECISION-FIRST. A mis-marked production symbol vanishes from
// --ignore-tests output and is de-prioritized in retrieval, which is strictly worse than a missed
// test — so every rule below keys on a convention that is unambiguous in its own language, and
// nothing is inferred from a name that merely looks test-ish. The negative controls that pin this
// live in test/testscopecheck.sh: a non-test `mod utils`, a Python `class Testament`, a JS function
// named `describe_thing`, and an unattributed C# class next to an attributed method. What each rule
// deliberately does NOT cover is recorded at the rule itself — a documented gap, never a guess.
//
// Consumed by Symbol::testScope, which filter.h::isTestSymbol ORs with the path signal; it rides the
// per-file cache record, so kParserVer gates it like every other extraction fact.

// `a` equals `b` after every ASCII space/tab/CR/LF in `a` is removed. Attribute spellings vary
// (`cfg(test)` and `cfg( test )` are the same attribute), and the whitespace is the only variation a
// syntactic comparison must absorb — `b` is always a caller-supplied literal with none.
inline bool equalsIgnoringAsciiSpace( std::string_view a, std::string_view b ) noexcept
{
    std::size_t matched = 0;
    for( char c : a )
    {
        if( c == ' ' || c == '\t' || c == '\n' || c == '\r' )
        {
            continue;
        }
        if( matched >= b.size() || b[matched] != c )
        {
            return false;
        }
        ++matched;
    }
    return matched == b.size();
}

// One Rust attribute's inner text (the `cfg(test)` of `#[cfg(test)]`), judged as a test marker.
// MATCHES: `cfg(test)`, `test`, and any path attribute whose FINAL segment is `test` (`tokio::test`,
// `async_std::test`, `actix_rt::test` — every async runtime spells its harness that way).
// DELIBERATELY NOT MATCHED: the compound `cfg(all(test, …))` / `cfg(any(test, …))` forms. Deciding
// that such a module is test-only means reasoning about which arm a build selects, which depends on
// feature flags ripwire never sees — the same "never quietly guess" rule that keeps ppalt a
// disclosure instead of a branch choice.
inline bool rustAttrIsTestMarker( std::string_view attr ) noexcept
{
    if( equalsIgnoringAsciiSpace( attr, "cfg(test)" ) || equalsIgnoringAsciiSpace( attr, "test" ) )
    {
        return true;
    }
    const std::size_t sep = attr.rfind( "::" );
    return sep != std::string_view::npos && equalsIgnoringAsciiSpace( attr.substr( sep + 2 ), "test" );
}

// Does the contiguous attribute run PRECEDING `item` carry a test marker? Rust attributes are SIBLING
// `attribute_item` nodes in front of the item they decorate, not children of it (verified by --match
// probes on real parses, not assumed) — so the scan walks backwards and stops at the first sibling
// that is neither an attribute nor a comment, which is where this item's own attribute run began.
inline bool rustItemCarriesTestAttr( TSNode item, std::string_view src ) noexcept
{
    for( TSNode prev = ts_node_prev_sibling( item ); !ts_node_is_null( prev ); prev = ts_node_prev_sibling( prev ) )
    {
        const char* t = ts_node_type( prev );
        if( std::strcmp( t, "attribute_item" ) == 0 )
        {
            const std::uint32_t childCount = ts_node_child_count( prev );
            for( std::uint32_t ci = 0; ci < childCount; ++ci )
            {
                const TSNode ch = ts_node_child( prev, ci );
                if( std::strcmp( ts_node_type( ch ), "attribute" ) == 0 && rustAttrIsTestMarker( nodeTextOf( ch, src ) ) )
                {
                    return true;
                }
            }
            continue;
        }
        if( std::strcmp( t, "line_comment" ) == 0 || std::strcmp( t, "block_comment" ) == 0 )
        {
            continue;   // a doc comment may sit between an attribute and its item
        }
        break;
    }
    return false;
}

// Python `class Test<Something>` — the unittest/pytest convention. The character after `Test` MUST be
// uppercase or '_', which is exactly what stops `class Testament` (a real English word, and the
// gate's negative control) from matching. A class named exactly `Test` is also left alone: four
// characters are too short to be a convention and it is a plausible production type name.
inline bool pyTestClassName( std::string_view name ) noexcept
{
    if( name.size() < 5 || name.compare( 0, 4, "Test" ) != 0 )
    {
        return false;
    }
    const unsigned char after = static_cast<unsigned char>( name[4] );
    return ( after >= 'A' && after <= 'Z' ) || after == '_';
}

// A C# attribute's name, judged as a test marker: the three framework markers that are unambiguous
// across xUnit (`Fact`), NUnit (`Test`) and MSTest (`TestMethod`), matched on the FINAL segment so a
// fully-qualified `Xunit.FactAttribute`-style spelling still resolves. DELIBERATELY NOT MATCHED:
// `Theory`/`TestCase` (data-driven variants) and the class-level `[TestFixture]`/`[TestClass]` — each
// is a separate convention that deserves its own probe and its own gate arm rather than a guess here.
inline bool csharpAttrIsTestMarker( std::string_view name ) noexcept
{
    const std::size_t      dot = name.rfind( '.' );
    const std::string_view fin = ( dot == std::string_view::npos ) ? name : name.substr( dot + 1 );
    return fin == "Test" || fin == "Fact" || fin == "TestMethod";
}

// Does `n` carry a test-marking attribute? C# attribute lists are direct CHILDREN of the declaration
// they decorate (the mirror image of Rust's sibling placement — again verified by --match probe).
inline bool csharpNodeCarriesTestAttr( TSNode n, std::string_view src ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t ci = 0; ci < childCount; ++ci )
    {
        const TSNode list = ts_node_child( n, ci );
        if( std::strcmp( ts_node_type( list ), "attribute_list" ) != 0 )
        {
            continue;
        }
        const std::uint32_t attrCount = ts_node_child_count( list );
        for( std::uint32_t ai = 0; ai < attrCount; ++ai )
        {
            const TSNode attr = ts_node_child( list, ai );
            if(    std::strcmp( ts_node_type( attr ), "attribute" ) == 0
                && csharpAttrIsTestMarker( nodeTextOf( ts_node_child_by_field_name( attr, "name", 4 ), src ) ) )
            {
                return true;
            }
        }
    }
    return false;
}

// Python's rule, written as its own pass because the two halves are ORDERED: a `def test_*` counts
// only at MODULE level (the pytest convention), so the enclosing-class question must be answered
// before the name question. Walking outward once and testing names as they appear would mark a method
// named `test_bar` inside a production class — precisely the over-trigger this shape forbids.
inline bool pythonInFileTestScope( TSNode defNode, std::string_view src ) noexcept
{
    bool enclosedByClass = false;
    for( TSNode n = defNode; !ts_node_is_null( n ); n = ts_node_parent( n ) )
    {
        if( std::strcmp( ts_node_type( n ), "class_definition" ) != 0 )
        {
            continue;
        }
        if( pyTestClassName( nodeTextOf( ts_node_child_by_field_name( n, "name", 4 ), src ) ) )
        {
            return true;    // a member of a Test* class, at any nesting depth
        }
        enclosedByClass = true;
    }
    if( enclosedByClass || std::strcmp( ts_node_type( defNode ), "function_definition" ) != 0 )
    {
        return false;
    }
    return nodeTextOf( ts_node_child_by_field_name( defNode, "name", 4 ), src ).rfind( "test_", 0 ) == 0;
}

// Is `pred` true of `node` itself or of any of its ancestors? Three of the four in-file test rules ask
// exactly that and differ ONLY in the predicate, so the walk lives here once. Written after
// --quality-delta flagged the first hand-rolled copy as a 101-token clone of yamlKeyCaptureDropped's
// unrelated ancestor scan — the detector was right that the loop is one body, and three more copies of
// it would have been three more.
template<class NodePred>
inline bool anySelfOrAncestor( TSNode node, NodePred pred ) noexcept
{
    for( TSNode n = node; !ts_node_is_null( n ); n = ts_node_parent( n ) )
    {
        if( pred( n ) )
        {
            return true;
        }
    }
    return false;
}

// Rust: the def itself, or any enclosing `mod`/`fn`, carries a test attribute.
inline bool rustInFileTestScope( TSNode defNode, std::string_view src ) noexcept
{
    return anySelfOrAncestor( defNode, [ & ]( TSNode n ) noexcept
                                       {
                                           const char* t = ts_node_type( n );
                                           return    ( std::strcmp( t, "mod_item" ) == 0 || std::strcmp( t, "function_item" ) == 0 )
                                                  && rustItemCarriesTestAttr( n, src );
                                       } );
}

// JS/TS: the harness block is a CALL whose callee is one of three bare identifiers, and the def is
// declared somewhere inside its arguments. The member forms (`it.only`, `test.each`, `describe.skip`)
// are a DOCUMENTED GAP, not an oversight — they need their own probe and gate arm, and the bare forms
// are what the measured corpora spell.
inline bool jsInFileTestScope( TSNode defNode, std::string_view src ) noexcept
{
    return anySelfOrAncestor( defNode, [ & ]( TSNode n ) noexcept
                                       {
                                           if( std::strcmp( ts_node_type( n ), "call_expression" ) != 0 )
                                           {
                                               return false;
                                           }
                                           const std::string_view callee = nodeTextOf( ts_node_child_by_field_name( n, "function", 8 ), src );
                                           return callee == "describe" || callee == "it" || callee == "test";
                                       } );
}

// C#: the def itself, or an enclosing declaration, carries a test-marking attribute list.
inline bool csharpInFileTestScope( TSNode defNode, std::string_view src ) noexcept
{
    return anySelfOrAncestor( defNode, [ & ]( TSNode n ) noexcept { return csharpNodeCarriesTestAttr( n, src ); } );
}

// The one entry point: is this def (or an enclosing scope of it) test code by an IN-FILE convention?
// A language with no modeled convention returns false and keeps path-only classification — a zero
// here means "no in-file convention found", never "this is production" (filter.h::isTestSymbol ORs
// the path signal back in). One flat dispatch, one walk per language: the four rules have genuinely
// different SHAPES (Rust reads preceding siblings, Python must answer the enclosing-class question
// before the name question, JS/TS reads a callee, C# reads child attribute lists), so folding them
// into a single loop bought a nested language test on every ancestor and nothing else.
inline bool inFileTestScope( TSNode defNode, std::string_view src, Lang lang ) noexcept
{
    if( ts_node_is_null( defNode ) )
    {
        return false;
    }
    switch( lang )
    {
        case Lang::Rust:       return rustInFileTestScope( defNode, src );
        case Lang::Python:     return pythonInFileTestScope( defNode, src );
        case Lang::TypeScript:
        case Lang::JavaScript: return jsInFileTestScope( defNode, src );
        case Lang::CSharp:     return csharpInFileTestScope( defNode, src );
        default:               return false;
    }
}

// ---- LB-E (r10 gitnexus harvest 2026-08-20): macro-defined test bodies ----------------------------------
// `TEST_CASE( "title" ) { … }` — doctest/Catch2's block-forming test macros — cannot be expanded by
// tree-sitter, so the source parses as TWO SIBLING nodes: an (expression_statement (call_expression …)
// (MISSING ";")) and a bare (compound_statement …). Neither is a definition, so pre-kParserVer-70 the
// body's calls attributed to NOTHING (measured on this repo: five pageRankDouble sites invisible to
// --callers) — and --test-gate/--affected/tested= all rest on exactly those test→subject edges.
// queries/cpp/tags.scm captures the SHAPE only (@definition.testmacroblock); the real gates live here.
//
// The known block-forming test macros — doctest/Catch2 STRING-TITLE forms only. The GoogleTest family
// (TEST/TEST_F/TEST_P — identifier arguments) parses as a plain function_definition and never reaches
// this shape; TEST_CASE_TEMPLATE/SCENARIO_TEMPLATE lose their block INTO the argument list to error
// recovery (no sibling compound_statement — the documented gap in queries/cpp/tags.scm); SUBCASE/
// SECTION/GIVEN/WHEN/THEN are deliberately absent because they nest INSIDE a captured test body, and
// splitting one test's calls across subcase symbols would be a worse answer than one spanning symbol.
inline constexpr std::array<std::string_view, 5> kTestBlockMacroNames = { "TEST_CASE", "TEST_CASE_FIXTURE", "TEST_CASE_METHOD", "SCENARIO", "TEST_SUITE" };

// The capture-time gate + parts for a @definition.testmacroblock candidate. PRECISION OVER RECALL: ok
// only when ALL of — the callee identifier is a known test macro (an unknown `WIDGET_DEF( "x" ) { … }`
// could be anything, and minting a phantom test symbol is worse than staying blind); the statement
// carries the error-recovery MISSING ";" (a real `logCall( "x" );` before an unrelated block inside a
// function body is the same query shape with a REAL semicolon, and must not trigger); the next named
// sibling is the compound_statement body; and a non-empty title string literal sits in the argument
// list (FIRST string wins: TEST_CASE_FIXTURE/TEST_CASE_METHOD put a fixture identifier before the
// title, Catch2's "[tags]" literal comes after it).
struct TestMacroBlockParts
{
    bool   ok = false;
    TSNode body {};    // the sibling compound_statement — adopted as the def's body
    TSNode title {};   // the title string_literal node — its content becomes the symbol's name
};

inline TestMacroBlockParts testMacroBlockPartsOf( TSNode exprStmtNode, std::string_view src ) noexcept
{
    if( ts_node_is_null( exprStmtNode ) || std::strcmp( ts_node_type( exprStmtNode ), "expression_statement" ) != 0 )
    {
        return {};
    }

    // the MISSING ";" — the one structural mark separating a macro-with-block from a real statement
    bool hasMissingSemicolon = false;
    const std::uint32_t childCount = ts_node_child_count( exprStmtNode );
    for( std::uint32_t childIx = 0; childIx < childCount; ++childIx )
    {
        if( ts_node_is_missing( ts_node_child( exprStmtNode, childIx ) ) )
        {
            hasMissingSemicolon = true;
            break;
        }
    }
    if( !hasMissingSemicolon )
    {
        return {};
    }

    const TSNode body = ts_node_next_named_sibling( exprStmtNode );
    if( ts_node_is_null( body ) || std::strcmp( ts_node_type( body ), "compound_statement" ) != 0 )
    {
        return {};
    }

    // the callee must be a KNOWN test macro
    const TSNode call = ts_node_named_child( exprStmtNode, 0 );
    if( ts_node_is_null( call ) || std::strcmp( ts_node_type( call ), "call_expression" ) != 0 )
    {
        return {};
    }
    const std::string_view callee = nodeTextOf( ts_node_child_by_field_name( call, "function", 8 ), src );
    bool isKnownMacro = false;
    for( const std::string_view macroName : kTestBlockMacroNames )
    {
        if( callee == macroName )
        {
            isKnownMacro = true;
            break;
        }
    }
    if( !isKnownMacro )
    {
        return {};
    }

    // the FIRST string literal among the arguments is the title
    const TSNode args = ts_node_child_by_field_name( call, "arguments", 9 );
    const std::uint32_t argCount = ts_node_is_null( args ) ? 0u : ts_node_named_child_count( args );
    for( std::uint32_t argIx = 0; argIx < argCount; ++argIx )
    {
        const TSNode arg = ts_node_named_child( args, argIx );
        if( std::strcmp( ts_node_type( arg ), "string_literal" ) == 0 && ts_node_end_byte( arg ) > ts_node_start_byte( arg ) + 2 )   // "" is not a name
        {
            return { true, body, arg };
        }
    }
    return {};
}

// the title text: the string_literal's content with the delimiting quotes stripped. Escape sequences
// stay as written — the title is a DISPLAY string, not an identifier (its consumer bypasses
// defNameFromCapture on purpose: finalSegment would split a dotted title like "rank.step determinism").
inline std::string_view testMacroTitleOf( TSNode titleNode, std::string_view src ) noexcept
{
    std::string_view raw = nodeTextOf( titleNode, src );
    if( raw.size() >= 2 && raw.front() == '"' && raw.back() == '"' )
    {
        raw.remove_prefix( 1 );
        raw.remove_suffix( 1 );
    }
    return raw;
}

// r3 q10 (bench/headtohead/r3-headroom-2026-08-03 REPORT.md §(v) item 1): SCREAMING_SNAKE — an
// ALL-CAPS identifier of ≥2 chars ([A-Z][A-Z0-9_]+), the cross-language naming convention for a
// module-level settings/config constant. The ≥2 floor drops single-letter names (a top-level `X = …`
// is a scratch binding, not a settings table). Pure ASCII on purpose: the convention IS ASCII.
inline bool isScreamingSnakeName( std::string_view name ) noexcept
{
    if( name.size() < 2 || name[0] < 'A' || name[0] > 'Z' )
    {
        return false;
    }
    for( const char c : name )
    {
        const bool ok = ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_';
        if( !ok )
        {
            return false;
        }
    }
    return true;
}

// Which languages' @definition.constant captures are gated on SCREAMING_SNAKE. These grammars' new
// constant patterns (queries/*/tags.scm, r3 q10) structurally capture EVERY module-level binding of the
// right shape — the name gate is what scopes extraction to settings modules / feature-flag tables
// instead of every literal. Enforced HERE because tags-pass predicates never run (#match? is wired into
// --match/--lint only — measured; see the note in queries/cpp/tags.scm). Deliberately NOT gated:
// Python (vendored upstream pattern, case-blind since import — existing behavior pinned by constcheck),
// Go (const/var patterns predate this and Go constants are conventionally CamelCase), Rust (const_item/
// static_item are constants by construction — the keyword, not the case, is the evidence), Swift
// (property_declaration predates this, filtered by isSwiftLocalBinding instead).
inline bool constCaptureNeedsScreamingGate( Lang lang ) noexcept
{
    switch( lang )
    {
        case Lang::TypeScript:
        case Lang::JavaScript:
        case Lang::Ruby:
        case Lang::Java:
        case Lang::CSharp:
        case Lang::C:
        case Lang::Cpp:
        {
            return true;
        }
        default:
        {
            return false;
        }
    }
}

// Was this @name bound through an init_declarator (the r3 q10 initialized-binding patterns), or through
// the UNINITIALIZED CUDA memory-space patterns (cudacheck §7b close-out)? The two pattern families share
// one capture name, and pattern_index would be brittle against .scm reordering — the name node's ancestry
// up to the captured declaration is the robust discriminator.
inline bool nameBoundByInitDeclarator( TSNode nameNode, TSNode declNode ) noexcept
{
    for( TSNode walk = ts_node_parent( nameNode ); !ts_node_is_null( walk ) && !ts_node_eq( walk, declNode ); walk = ts_node_parent( walk ) )
    {
        if( std::strcmp( ts_node_type( walk ), "init_declarator" ) == 0 )
        {
            return true;
        }
    }
    return false;
}

// The one direct-child token scanner behind the three qualifier tests below (CUDA memory-space,
// const evidence, static storage). Filters `node`'s DIRECT children to named `namedChildType` nodes
// — plus, when acceptAnonymousToken, anonymous token children (the CUDA `__device__` shape, which
// tree-sitter-cuda parses as an anonymous child; see cudaMemorySpaceQualifierOf's contract note) —
// and returns the first child whose source text is one of `tokens` ("" = none).
inline std::string_view childTokenAmong( TSNode node, std::string_view src, const char* namedChildType, bool acceptAnonymousToken, std::initializer_list<std::string_view> tokens ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( node );
    for( std::uint32_t childIx = 0; childIx < childCount; ++childIx )
    {
        const TSNode child   = ts_node_child( node, childIx );
        const bool   isNamed = ts_node_is_named( child );
        if( isNamed && std::strcmp( ts_node_type( child ), namedChildType ) != 0 )
        {
            continue;
        }
        if( !isNamed && !acceptAnonymousToken )
        {
            continue;
        }
        const std::uint32_t beginByte = ts_node_start_byte( child );
        const std::uint32_t endByte   = ts_node_end_byte( child );
        if( endByte > src.size() || beginByte >= endByte )
        {
            continue;
        }
        const std::string_view text = src.substr( beginByte, endByte - beginByte );
        for( const std::string_view token : tokens )
        {
            if( text == token )
            {
                return text;
            }
        }
    }
    return {};
}

// CUDA memory-space qualifier of a module-scope declaration ("" = none). The uninitialized-declaration
// patterns in queries/cpp/tags.scm are STRUCTURAL and unconstrained on purpose — that query also
// compiles against tree-sitter-cpp (.cpp/.h/.metal), which has no `__constant__` token, so naming it
// there would make ts_query_new reject the whole query; tags-pass predicates never run (measured; see
// the cast-keyword note in tags.scm); and a `(type_qualifier)` child constraint cannot see `__device__`
// anyway — tree-sitter-cuda parses `__constant__`/`__managed__` as NAMED type_qualifier nodes but
// `__device__` as an ANONYMOUS token child of the declaration. The qualifier test therefore lives here,
// isCppCastKeyword's home, scanning ALL children and accepting the three spellings from exactly two node
// shapes: a named type_qualifier, or an anonymous token. The anonymous-only restriction on the second
// arm is a correctness guard, not pedantry: tree-sitter-cpp error-recovers `__device__ float x;` in a
// plain .cpp by parsing `__device__` as a NAMED type_identifier — text alone would false-positive there.
// This function is what makes the unconstrained patterns safe: every non-CUDA raw match returns "" and
// drops. Verified the strong way on the 2026-08-10 port round — the full maps of ripwire's own src/ and
// of four real C++/CUDA trees (xformers 6e10bd2, dgl f0b7cc9, MONAI 052dbb4, transformers 343c8cb86)
// are byte-identical to the pre-port binary's except for rows carrying a memory-space qualifier in a
// .cu/.cuh. (Measurement trap, recorded so it isn't re-tripped: baseline against a build of the tree you
// started from, never the PATH-installed ripwire, which can predate the r3 q10 patterns entirely.)
inline std::string_view cudaMemorySpaceQualifierOf( TSNode declNode, std::string_view src ) noexcept
{
    return childTokenAmong( declNode, src, "type_qualifier", /*acceptAnonymousToken=*/true, { "__constant__", "__device__", "__managed__" } );
}

// Does this C-family declaration (or field_declaration) carry const evidence — a `const` /
// `constexpr` / `constinit` type_qualifier as a DIRECT child? The keyword, not the name case, is
// what marks a deliberate module constant (the Rust const_item rationale, already applied to CUDA
// `__constant__` above), and it is what the 2026-08-12 census said agents actually hunt: 613 of
// 2 870 symbol-name lookups were constant-shaped, and this repo's own `constexpr std::uint32_t
// kParserVer` was invisible to its own `--for`/`--uses` because the r3 q10 gate is SCREAMING-only.
// Direct children only, on purpose: a declaration-level qualifier (`const char* k = …`, east-const
// `int const k = …`, `static const int k = …`) is the module-constant shape; a qualifier nested
// inside a pointer_declarator (`char* const k = …`, a const POINTER) stays outside this test and
// keeps the old SCREAMING-only behavior — a disclosed boundary, not a silent miss. `consteval` is
// function-only and cannot appear here; `volatile`/`restrict`/`_Atomic` are not const evidence.
inline bool declarationCarriesConstQualifier( TSNode declNode, std::string_view src ) noexcept
{
    return !childTokenAmong( declNode, src, "type_qualifier", /*acceptAnonymousToken=*/false, { "const", "constexpr", "constinit" } ).empty();
}

// The keep decision for the class-static-constant field_declaration captures (queries/cpp/tags.scm,
// module-constant round). The pattern is deliberately loose — it matches EVERY default-member-
// initializer, because tags-pass predicates never run and static/constexpr child order is free — so
// this is where the real contract lives: keep iff the field carries BOTH a `static`
// storage_class_specifier AND a const/constexpr/constinit type_qualifier. That keeps
// `static constexpr int kMaxDepth = 3;` case-blind (one per-class constant, the census target) and
// drops the two per-instance shapes the fixture pins as negatives: a plain default-initialized
// member (`int retries = 3;` — no static, no const) and a const NON-static member (`const int x = 1;`
// — per-instance state that happens to be immutable, not a class constant).
inline bool fieldConstantCaptureKept( TSNode fieldDeclNode, std::string_view src ) noexcept
{
    const bool isStaticMember = !childTokenAmong( fieldDeclNode, src, "storage_class_specifier", /*acceptAnonymousToken=*/false, { "static" } ).empty();
    return isStaticMember && declarationCarriesConstQualifier( fieldDeclNode, src );
}

// forward declarations for dropGatedCapture below — the helpers live after nodeTextOf's section.
inline bool isCjsExportTarget( TSNode nameNode, std::string_view src ) noexcept;
inline bool isPrototypeMemberTarget( TSNode nameNode, std::string_view src ) noexcept;
inline bool isPyEnumMemberTarget( TSNode nameNode, std::string_view src ) noexcept;

// The @definition.constant drop decision, in its own function for the same reason isCjsExportTarget and
// isPyEnumMemberTarget have theirs: dropGatedCapture is a dispatcher, and this is the one arm with a
// policy rather than a predicate. r3 q10 gates on SCREAMING_SNAKE; the §7b close-out adds the CUDA
// memory-space policy, C++ ONLY, as ONE decision covering both declaration shapes queries/cpp/tags.scm
// now captures. `__constant__` keeps case-blind whether initialized or not (constant by construction:
// device-read-only, host-filled via cudaMemcpyToSymbol or an initializer — the Rust const_item
// rationale; measured against NVIDIA/cuda-samples, where dxtc's initialized `kColorMetric = {…}` and
// bilateralFilter's uninitialized `cGaussian[64]` are the same kind of table). `__device__`/`__managed__`
// are MUTABLE device globals and keep only under the convention gate. An uninitialized capture with NO
// memory-space qualifier drops — the extern-const/static/alignas/volatile shape plain C++ produces by the
// hundred, which reaches here ONLY through the new structural patterns.
//
// The C-family narrowing is load-bearing, NOT a restatement of the old gate's language set:
// nameBoundByInitDeclarator is a C-family node test, and the other gated languages bind their
// @definition.constant through variable_declarator (TS/JS), field_declaration (Java/C#) or a bare
// assignment (Ruby) — every one of them would read "uninitialized" here and, having no memory-space
// qualifier either, drop WHOLESALE. Lang::C takes its own arm (module-constant round, 2026-08-12):
// queries/c/tags.scm still has no uninitialized pattern, so const-evidence-or-SCREAMING on the
// initialized shape is C's whole decision. (The 2026-08-10 measurement below predates that arm and
// pinned the CUDA port's zero-regression claim: byte-identical maps on ripwire's own src/ and 0
// added / 0 REMOVED rows on cpython 8463cb5, numpy a905925, meson f0851c9e, xformers 6e10bd2,
// dgl f0b7cc9 and transformers 343c8cb86 — ~250K symbol rows of C/C++. The module-constant round
// deliberately ADDS rows on those trees — const-qualified camel constants — which is the fix, and
// test/moduleconstcheck.sh is the gate that measures it.)
inline bool dropConstantCapture( Lang lang, std::string_view name, TSNode nameNode, TSNode roleNode, std::string_view src ) noexcept
{
    // MODULE-CONSTANT ROUND (2026-08-12): in the C family, a const/constexpr/constinit qualifier on the
    // captured declaration keeps the binding CASE-BLIND — the keyword is the evidence, exactly the
    // `__constant__` / Rust const_item rationale below. C first: its tags.scm binds only initialized
    // file-scope declarations, so const evidence (or the r3 q10 SCREAMING convention) is the whole test.
    if( lang == Lang::C )
    {
        return !( isScreamingSnakeName( name ) || declarationCarriesConstQualifier( roleNode, src ) );
    }
    if( lang != Lang::Cpp )
    {
        return constCaptureNeedsScreamingGate( lang ) && !isScreamingSnakeName( name );
    }
    // Class-static constants bind through a field_declaration (the loose default_value pattern), never
    // through init_declarator — their whole keep contract lives in fieldConstantCaptureKept.
    if( std::strcmp( ts_node_type( roleNode ), "field_declaration" ) == 0 )
    {
        return !fieldConstantCaptureKept( roleNode, src );
    }
    // Cost ordering: the common plain-C++ case (initialized + SCREAMING) resolves before any node scan,
    // and the qualifier/CUDA scans run only for non-SCREAMING names or the uninitialized CUDA patterns.
    const bool initialized = nameBoundByInitDeclarator( nameNode, roleNode );
    if( initialized && ( isScreamingSnakeName( name ) || declarationCarriesConstQualifier( roleNode, src ) ) )
    {
        return false;                                                    // r3 q10 convention keep, or const-keyword evidence
    }
    const std::string_view memSpace = cudaMemorySpaceQualifierOf( roleNode, src );
    if( memSpace == "__constant__" )
    {
        return false;                                                    // constant by construction — case-blind
    }
    if( initialized )
    {
        return true;                                                     // initialized MUTABLE non-SCREAMING global
    }
    return !( !memSpace.empty() && isScreamingSnakeName( name ) );        // uninitialized: __device__/__managed__ gated
}

// YAML's @definition.yamlkey gate — the yaml tier's one in-C++ predicate (see queries/yaml/tags.scm's
// header for why the depth cut cannot live in the query: sequence nesting between a pair and its
// document is unbounded, so no finite pattern set expresses it, and tags-pass predicates never run).
// A mapping key is a symbol iff its MAPPING depth is <= 2 — block and flow mappings counted alike
// (flow is a presentation style of the same mapping node), sequences counted NOT AT ALL (sequence
// transparency: 25.3% of real keys sit directly inside a sequence element — the steps:/containers:/
// tasks: shape — and a root-depth rule drops every one of them; 44.0% captured vs JSON's-rule 27.1%,
// measured on the 90-repo breadth corpus). Depth = the number of mapping nodes on the ancestor chain
// from the pair to the root, the pair's own mapping included; multi-document streams need no special
// case because documents never nest. The merge key `<<` (0.22% of files) is the one TEXTUAL drop —
// it parses as an ordinary plain_scalar key and a symbol named `<<` helps nobody. Alias-as-key
// (measured 0 in 4 449 files) and explicit block-node keys are dropped STRUCTURALLY by the query's
// scalar-only alternation and never reach here.
inline bool yamlKeyCaptureDropped( std::string_view name, TSNode roleNode ) noexcept
{
    if( name == "<<" )
    {
        return true;
    }
    std::uint32_t mappingDepth = 0;
    for( TSNode p = roleNode; !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* pt = ts_node_type( p );
        if( std::strcmp( pt, "block_mapping" ) == 0 || std::strcmp( pt, "flow_mapping" ) == 0 )
        {
            if( ++mappingDepth > 2u )
            {
                return true;
            }
        }
    }
    return false;
}

// The whole drop decision for every GATED definition capture, kept out of captureTagsFacts (which is
// already the file's densest dispatch point) behind ONE call, keyed on the @definition capture's own
// name. @definition.constant delegates to dropConstantCapture above (r3 q10's SCREAMING_SNAKE gate plus
// the §7b CUDA memory-space policy); @definition.enummember (the Python shape round,
// test/pyshapecheck.sh) drops when the enclosing class's base NAME is not an enum family;
// @definition.cjsexport / @definition.protomethod (the JS shape round, test/jsshapecheck.sh) drop when
// the LEFT side is not really exports/module.exports/.prototype. — the query captures every `a.b = fn`
// shape and cannot text-test, because tags-pass predicates never run (see constCaptureNeedsScreamingGate
// above).
inline bool dropGatedCapture( std::string_view defCapSv, Lang lang, std::string_view name, TSNode nameNode, TSNode roleNode, std::string_view src ) noexcept
{
    if( defCapSv == "definition.constant" )
    {
        return dropConstantCapture( lang, name, nameNode, roleNode, src );
    }
    if( defCapSv == "definition.cjsexport" )
    {
        return !isCjsExportTarget( nameNode, src );
    }
    if( defCapSv == "definition.protomethod" )
    {
        return !isPrototypeMemberTarget( nameNode, src );
    }
    if( defCapSv == "definition.enummember" )
    {
        return !isPyEnumMemberTarget( nameNode, src );
    }
    if( defCapSv == "definition.yamlkey" )
    {
        return yamlKeyCaptureDropped( name, roleNode );
    }
    if( defCapSv == "definition.testmacroblock" )
    {
        // LB-E: the query captures the shape only (any identifier-call statement before a block) —
        // the name-list, MISSING-";", sibling-body and title gates all live in testMacroBlockPartsOf.
        return !testMacroBlockPartsOf( roleNode, src ).ok;
    }
    if( defCapSv == "definition.macro" )
    {
        // macro-edges round: an EMPTY-body function-like `#define NOOP(x)` defines nothing callable — drop
        // it before it mints a symbol. The @name capture's parent IS the preproc node; object-like
        // preproc_def and Rust macro_definition fail the node-type test and are never gated.
        const TSNode defineNode = ts_node_parent( nameNode );
        return !ts_node_is_null( defineNode )
            && std::strcmp( ts_node_type( defineNode ), "preproc_function_def" ) == 0
            && !preprocFunctionDefHasBody( defineNode, src );
    }
    return false;
}

// JS shape round (test/jsshapecheck.sh): the two assignment-shape gates dropGatedCapture dispatches to.
// Both helpers take the @name capture — the `property:` field of the assignment's LEFT
// member_expression — and inspect that node's `object:` sibling.

// `exports.NAME = fn` (object is the bare identifier `exports`) or `module.exports.NAME = fn` (object is
// the member_expression `module.exports`, tested segment-by-segment, not as flat text — `module . exports`
// with interior spacing would still pass, a decoy like `moduleLike.exports` cannot).
inline bool isCjsExportTarget( TSNode nameNode, std::string_view src ) noexcept
{
    const TSNode member = ts_node_parent( nameNode );
    if( ts_node_is_null( member ) )
    {
        return false;
    }
    const TSNode obj = ts_node_child_by_field_name( member, "object", 6 );
    if( ts_node_is_null( obj ) )
    {
        return false;
    }
    const char* objType = ts_node_type( obj );
    if( std::strcmp( objType, "identifier" ) == 0 )
    {
        return nodeTextOf( obj, src ) == "exports";
    }
    if( std::strcmp( objType, "member_expression" ) == 0 )
    {
        const TSNode oo = ts_node_child_by_field_name( obj, "object", 6 );
        return std::strcmp( ts_node_type( oo ), "identifier" ) == 0
            && nodeTextOf( oo, src ) == "module"
            && nodeTextOf( ts_node_child_by_field_name( obj, "property", 8 ), src ) == "exports";
    }
    return false;
}

// `Foo.prototype.NAME = fn` at any qualifier depth: the member_expression under `object:` must name
// `prototype` as its property. Instance-slot assignments (`sock.onclose = fn`, `this.state.h = fn`)
// share the captured shape and fail exactly this test.
inline bool isPrototypeMemberTarget( TSNode nameNode, std::string_view src ) noexcept
{
    const TSNode member = ts_node_parent( nameNode );
    if( ts_node_is_null( member ) )
    {
        return false;
    }
    const TSNode obj = ts_node_child_by_field_name( member, "object", 6 );
    if( ts_node_is_null( obj ) || std::strcmp( ts_node_type( obj ), "member_expression" ) != 0 )
    {
        return false;
    }
    return nodeTextOf( ts_node_child_by_field_name( obj, "property", 8 ), src ) == "prototype";
}

// Python shape round (test/pyshapecheck.sh): `NAME = value` in a class body is a definition only when
// the class IS an enum table — otherwise it is the plain data attr the tags.scm scope line keeps out
// (12 131 django sites, re-measured 2026-08-10 at @c334c1a8ff). Enum-ness is read off the base NAME
// list (the class_definition's `superclasses` argument_list): the stdlib enum family plus django's
// Choices family, which is enum.Enum-derived and carries the bulk of django's own member sites.
// A base the name does not reveal (a subclass-of-a-subclass behind an alias) stays out: base names
// are checked statically, never resolved — the gate pins that direction too.
inline bool isPyEnumMemberTarget( TSNode nameNode, std::string_view src ) noexcept
{
    const TSNode assign = ts_node_parent( nameNode );                                    // assignment
    const TSNode stmt   = ts_node_is_null( assign ) ? assign : ts_node_parent( assign );  // expression_statement
    const TSNode body   = ts_node_is_null( stmt )   ? stmt   : ts_node_parent( stmt );    // block
    const TSNode cls    = ts_node_is_null( body )   ? body   : ts_node_parent( body );    // class_definition
    if( ts_node_is_null( cls ) || std::strcmp( ts_node_type( cls ), "class_definition" ) != 0 )
    {
        return false;
    }
    const TSNode bases = ts_node_child_by_field_name( cls, "superclasses", 12 );
    if( ts_node_is_null( bases ) )
    {
        return false;
    }
    const std::uint32_t baseCount = ts_node_named_child_count( bases );
    for( std::uint32_t baseIndex = 0; baseIndex < baseCount; ++baseIndex )
    {
        TSNode base = ts_node_named_child( bases, baseIndex );
        if( std::strcmp( ts_node_type( base ), "attribute" ) == 0 )                      // models.TextChoices → TextChoices
        {
            base = ts_node_child_by_field_name( base, "attribute", 9 );
            if( ts_node_is_null( base ) )
            {
                continue;
            }
        }
        if( std::strcmp( ts_node_type( base ), "identifier" ) != 0 )
        {
            continue;
        }
        const std::string_view baseName = nodeTextOf( base, src );
        if( baseName == "Enum" || baseName == "IntEnum" || baseName == "StrEnum"
         || baseName == "Flag" || baseName == "IntFlag" || baseName == "ReprEnum"
         || baseName == "Choices" || baseName == "TextChoices" || baseName == "IntegerChoices" )
        {
            return true;
        }
    }
    return false;
}


// ── receiver capture: the member-access vocabulary, one declarative place ────────────────────────────
// The two shapes whose receiver we inspect: C++/ObjC `field_expression` (`.argument` / `.field`) and
// Python `attribute` (`.object` / `.attribute`). Named here rather than re-spelled per call site because
// the depth-2 chain walk below applies exactly the same three questions twice, one level apart.
inline bool isMemberAccessNode( const char* t, Lang lang ) noexcept
{
    if( lang == Lang::Cpp || lang == Lang::ObjC ) { return std::strcmp( t, "field_expression" ) == 0; }
    if( lang == Lang::Python )                    { return std::strcmp( t, "attribute" ) == 0; }
    return false;
}

inline TSNode memberAccessReceiver( TSNode access, Lang lang ) noexcept
{
    return ( lang == Lang::Python ) ? ts_node_child_by_field_name( access, "object",   6 )
                                    : ts_node_child_by_field_name( access, "argument", 8 );
}

inline TSNode memberAccessField( TSNode access, Lang lang ) noexcept
{
    return ( lang == Lang::Python ) ? ts_node_child_by_field_name( access, "attribute", 9 )
                                    : ts_node_child_by_field_name( access, "field",     5 );
}

// The classified receiver of one call site. `var` is set for NamedVar / FieldOfVar, `field` for
// FieldOfThis / FieldOfVar; both "" for None / ThisObj.
struct RecvShape
{
    RecvKind    kind = RecvKind::None;
    std::string var;
    std::string field;
};

// One receiver NODE → its RecvShape. `allowChain` is the ONE-hop bound: true at the call's immediate
// receiver (a member-access receiver descends exactly one level, re-asking the same questions of its
// INNER receiver), false inside that descent — so a depth-3 chain's inner member-access classifies None
// and the whole chain degrades to the honest §2a split. `test/chainguardcheck.sh` arm (h) pins the
// bound, and the residual it leaves, as disclosed.
inline RecvShape classifyReceiver( TSNode node, Lang lang, std::string_view src, bool allowChain )
{
    const char* rt = ts_node_type( node );
    if( std::strcmp( rt, "this" ) == 0 )
    {
        return { RecvKind::ThisObj, {}, {} }; // C++ `this`
    }
    if( std::strcmp( rt, "identifier" ) == 0 )
    {
        const std::string_view v = pattern::nodeText( node, src );
        if( v.empty() )
        {
            return {};
        }
        if( lang == Lang::Python && v == "self" )
        {
            return { RecvKind::ThisObj, {}, {} }; // Python `self`
        }
        return { RecvKind::NamedVar, std::string( v ), {} };                          // `x` — Rule 2 fuel
    }
    if( allowChain && isMemberAccessNode( rt, lang ) )
    { // depth 2: the receiver is ITSELF one member access — `this->FIELD.m()` / `base.FIELD.m()`
        const TSNode innerRecv  = memberAccessReceiver( node, lang );
        const TSNode innerField = memberAccessField( node, lang );
        if( ts_node_is_null( innerRecv ) || ts_node_is_null( innerField ) )
        {
            return {};
        }
        // the intermediate must be a plain NAME — a template/computed/parenthesized form is not a field
        const char* ift = ts_node_type( innerField );
        if( std::strcmp( ift, "field_identifier" ) != 0 && std::strcmp( ift, "identifier" ) != 0 )
        {
            return {};
        }
        const std::string_view fieldTxt = pattern::nodeText( innerField, src );
        if( fieldTxt.empty() )
        {
            return {};
        }
        const RecvShape base = classifyReceiver( innerRecv, lang, src, false );
        if( base.kind == RecvKind::ThisObj )
        {
            return { RecvKind::FieldOfThis, {}, std::string( fieldTxt ) };            // `this->m_pool.run()` / `self.pool.acquire()`
        }
        if( base.kind == RecvKind::NamedVar )
        {
            return { RecvKind::FieldOfVar, base.var, std::string( fieldTxt ) };       // `cfg.opts.enable()`
        }
        return {};   // depth-3 or richer base → not decidable in one hop; degrade to §2a
    }
    return {};   // parenthesized / subscripted / call receiver → not one-hop
}

// P2-D RECEIVER capture: classify the call-site receiver of `recv.method()` / `recv->method()` so
// resolve.h can narrow before the ambiguous §2a name spray. `nameNode` is the @name capture (the called
// identifier). When it is the `.field`/`.attribute` of a member-access node, inspect that node's
// receiver (`.argument` in C++ `field_expression`, `.object` in Python `attribute`):
//   `this`/`self`        → ThisObj  (the enclosing class is definitive — Rule 1)
//   a bare `(identifier)` → NamedVar, recvVar = the variable text (the var's type pins the method — Rule 2)
//   ONE more member access whose OWN receiver is `this`/`self` or a bare identifier → FieldOfThis /
//     FieldOfVar, carrying the intermediate field name (`this->m_pool.run()` → field "m_pool";
//     `cfg.opts.enable()` → var "cfg", field "opts"). NO resolve rule consumes these yet: the receiver
//     kind exists so the five `recv == RecvKind::None` guard sites stop misclassifying a chained
//     receiver as a BARE name — Rule 1's bareCish arm wrong-narrowed `this->m_pool.run()` to the
//     caller's own class, and shadow suppression deleted `this->m_cfg.enable()` under a local named
//     `enable` (docs/EVALS.md §4 "Receiver-guard misfires"; the names carried here make a future
//     chain-resolution rule resolve-side only, with no second re-parse).
//   anything else (a depth-3 chain, `(expr)`, subscripts, a call in the chain, …) → None. The bound is
//     ONE intermediate hop, deliberately: past that the receiver is too rich to decide syntactically.
//     `test/chainguardcheck.sh` arm (h) pins the bound — and the residual it leaves — as disclosed.
// Pure-syntactic, deterministic, allocation-light: at most two short identifier copies, and none at all
// for the None/ThisObj shapes that dominate.
inline RecvShape receiverOf( TSNode nameNode, Lang lang, std::string_view src )
{
    const TSNode parent = ts_node_parent( nameNode );
    if( ts_node_is_null( parent ) )
    {
        return {};
    }
    if( !isMemberAccessNode( ts_node_type( parent ), lang ) )
    {
        return {};
    }

    const TSNode recvNode = memberAccessReceiver( parent, lang );
    if( ts_node_is_null( recvNode ) )
    {
        return {};
    }
    return classifyReceiver( recvNode, lang, src, /*allowChain=*/ true );
}

// ── P2-D Rule 2 LOCAL-VARIABLE TYPE BINDING capture (`Foo x;` → x:Foo) ───────────────────────────────
// Walk a node subtree and emit one RawBind per local variable whose TYPE is syntactically decidable, so a
// later `x.m()`/`x->m()` can narrow to `typeName::m`. Pure-syntactic, deterministic, allocation-light:
// it reads exactly the declaration/assignment shapes ground-truthed from the grammars (see the gate fixtures).
//   * The recorded typeName is the WRITTEN type's final segment (`ns::Foo` → `Foo`). It is matched against
//     class/struct symbol NAMES in buildGraph, which is the conservative safety net: an inferred type from a
//     constructor-call (`auto x = Foo()`) only narrows if `Foo` actually names a class — else it drops.
//   * Only the named-receiver shape is useful downstream, so only bare-identifier targets are recorded
//     (member targets `self.x`/`obj.f` are not — `receiverOf` doesn't capture those as recvVar either).

// the innermost bare `(identifier)` reached by unwrapping pointer/reference/parenthesized declarators —
// the actual variable name of a C++ declarator. "" if the declarator isn't a single named variable.
inline std::string_view declaratorVarName( TSNode decl, std::string_view src )
{
    for( int guard = 0; guard < 8 && !ts_node_is_null( decl ); ++guard )
    {
        const char* dt = ts_node_type( decl );
        if( std::strcmp( dt, "identifier" ) == 0 )
        {
            const std::uint32_t a = ts_node_start_byte( decl ), b = ts_node_end_byte( decl );
            return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
        }
        // unwrap a pointer/reference/parenthesized declarator to its inner `declarator` child
        const TSNode inner = ts_node_child_by_field_name( decl, "declarator", 10 );
        if( ts_node_is_null( inner ) )
        {
            return {};
        }
        decl = inner;
    }
    return {};
}

// the type NAME of a constructor-style RHS value node: `Foo()` (call_expression) or `new Foo()`
// (new_expression). Final segment of the callee/constructor identifier. "" if the value isn't a
// plain constructor call (so `auto x = makeFoo()` infers nothing here unless `makeFoo` names a class —
// and the class-name filter in buildGraph is what makes that safe).
inline std::string ctorTypeOf( TSNode value, std::string_view src )
{
    if( ts_node_is_null( value ) )
    {
        return {};
    }
    const char* vt = ts_node_type( value );
    TSNode      idn {};
    if( std::strcmp( vt, "call_expression" ) == 0 )
    { // C++/TS `Foo()`
        idn = ts_node_child_by_field_name( value, "function", 8 );
    }
    else if( std::strcmp( vt, "new_expression" ) == 0 )
    { // C++/TS `new Foo()`
        idn = ts_node_child_by_field_name( value, "constructor", 11 );
    }
    if( ts_node_is_null( idn ) )
    {
        return {};
    }
    const char* it = ts_node_type( idn );
    if( std::strcmp( it, "identifier" ) != 0 && std::strcmp( it, "type_identifier" ) != 0 && std::strcmp( it, "qualified_identifier" ) != 0 && std::strcmp( it, "scoped_identifier" ) != 0 )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( idn ), b = ts_node_end_byte( idn );
    return ( a <= b && b <= src.size() ) ? finalSegment( src.substr( a, b - a ) ) : std::string{};
}

// the written type name of a `type:`-field type node (`type_identifier`, or a qualified/scoped one). "" for
// `auto`/`placeholder_type_specifier`/templated/decltype types — those fall back to constructor inference.
inline std::string writtenTypeOf( TSNode typeNode, std::string_view src )
{
    if( ts_node_is_null( typeNode ) )
    {
        return {};
    }
    const char* tt = ts_node_type( typeNode );
    if( std::strcmp( tt, "type_identifier" ) == 0 || std::strcmp( tt, "qualified_identifier" ) == 0
        || std::strcmp( tt, "scoped_type_identifier" ) == 0 )
    {
        const std::uint32_t a = ts_node_start_byte( typeNode ), b = ts_node_end_byte( typeNode );
        return ( a <= b && b <= src.size() ) ? finalSegment( src.substr( a, b - a ) ) : std::string{};
    }
    return {};   // auto / template / decltype — type not directly written → try the initializer
}

// ── L3 fn-pointer/callback binding capture helpers ───────────────────────────────────────────────────

// the bound-function TARGET of an initializer/assignment RHS value node, for a var→FUNCTION binding:
//   `&alpha` / `&ns::alpha` (address-of) → "alpha" / "ns::alpha";  `alpha` / `ns::alpha` (bare) → same;
//   `[](){...}` (lambda) → kFnBindLambdaTarget.  "" for everything else (a call, a literal, arithmetic —
// not a recognizable single function). `wasBareIdent` reports the bare-IDENTIFIER shape so the caller can
// apply the primitive-type noise gate (`int a = b;` is almost never a function copy; `H h = beta;` through
// a typedef legitimately is).
inline std::string fnBindTargetOf( TSNode value, std::string_view src, bool& wasBareIdent )
{
    wasBareIdent = false;
    if( ts_node_is_null( value ) )
    {
        return {};
    }
    const char* vt = ts_node_type( value );
    if( std::strcmp( vt, "lambda_expression" ) == 0 )
    {
        return std::string( kFnBindLambdaTarget );
    }
    TSNode idn       = value;
    bool   addressOf = false;
    if( std::strcmp( vt, "pointer_expression" ) == 0 )
    {
        // only the ADDRESS-OF form — `*p` is also a pointer_expression, and a dereference names no function.
        const TSNode op = ts_node_child( value, 0 );
        if( ts_node_is_null( op ) || std::strcmp( ts_node_type( op ), "&" ) != 0 )
        {
            return {};
        }
        idn = ts_node_child_by_field_name( value, "argument", 8 );
        if( ts_node_is_null( idn ) )
        {
            return {};
        }
        addressOf = true;
    }
    const char* it = ts_node_type( idn );
    if( std::strcmp( it, "identifier" ) != 0 && std::strcmp( it, "qualified_identifier" ) != 0 )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( idn ), b = ts_node_end_byte( idn );
    if( a > b || b > src.size() )
    {
        return {};
    }
    wasBareIdent = !addressOf && std::strcmp( it, "identifier" ) == 0;
    return std::string( src.substr( a, b - a ) );
}

// the shape a possibly fn-pointer declarator chain (`(*fn)()` → "fn") presents, descending through
// function/parenthesized/pointer/reference declarators. `sawFn` reports crossing a function_declarator —
// the explicit fn-pointer syntax that licenses a bare-identifier initializer even under a primitive written
// type (`void (*fn)() = handler;`); `sawRef` a reference_declarator (`H& r = fn;`), where the reference
// ALIASES its initializer, so the caller must treat the bound-to variable as ESCAPED (clobbered) and never
// emit a positive for the alias; `sawPtr` a pointer_declarator, which is what separates the two shapes the
// type node alone cannot tell apart — `void (*fp)()` (a fn-pointer VARIABLE: sawFn AND sawPtr) from
// `void fp()` (a function DECLARATION: sawFn alone), which declares no variable at all. declaratorVarName
// (Rule 2) is NOT reused: parenthesized_declarator and reference_declarator carry their inner declarator as
// an UNNAMED child, which a field-only unwrap cannot reach. An array_declarator bails — an ARRAY of fn
// pointers is table territory, never a single-var binding (its indexed call must stay unresolved).
struct FnBindDeclShape
{
    std::string_view name;
    bool             sawFn  = false;
    bool             sawPtr = false;
    bool             sawRef = false;
};

inline FnBindDeclShape fnDeclaratorShape( TSNode decl, std::string_view src )
{
    FnBindDeclShape shape;
    for( int guard = 0; guard < 10 && !ts_node_is_null( decl ); ++guard )
    {
        const char* dt = ts_node_type( decl );
        if( std::strcmp( dt, "identifier" ) == 0 )
        {
            const std::uint32_t a = ts_node_start_byte( decl ), b = ts_node_end_byte( decl );
            shape.name = ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
            return shape;
        }
        if( std::strcmp( dt, "array_declarator" ) == 0 )
        {
            return shape;
        }
        const bool isRef = ( std::strcmp( dt, "reference_declarator" ) == 0 );
        shape.sawFn  = shape.sawFn  || std::strcmp( dt, "function_declarator" ) == 0;
        shape.sawPtr = shape.sawPtr || std::strcmp( dt, "pointer_declarator" ) == 0;
        shape.sawRef = shape.sawRef || isRef;
        TSNode inner = ts_node_child_by_field_name( decl, "declarator", 10 );
        if( ts_node_is_null( inner ) && ( isRef || std::strcmp( dt, "parenthesized_declarator" ) == 0 ) )
        {
            // the parenthesized/reference inner declarator is an UNNAMED child — take the first named one
            if( ts_node_named_child_count( decl ) > 0 )
            {
                inner = ts_node_named_child( decl, 0 );
            }
        }
        if( ts_node_is_null( inner ) )
        {
            return shape;
        }
        decl = inner;
    }
    return shape;
}

// tree-sitter-cpp MIS-PARSES a raw fn-pointer declaration inside a function body —
// `void (*fn)() = &alpha;` — as an assignment_expression whose LEFT is
//   call_expression( function: call_expression( function: primitive_type, arguments: ((*fn)) ), arguments: () )
// (the C grammar parses the same statement as a true declaration; only C++ takes the expression branch —
// ground-truthed with an AST dump against the vendored grammars, 2026-08-08). Decode the variable name from
// that shape. The inner callee must be a PRIMITIVE type — `void(...)` is never callable, so the shape is
// unambiguous evidence of a declaration; an identifier callee (`H (*g)()`, but equally REAL code
// `foo(*p)() = x;` assigning through a call result) stays undecoded — conservative, no false binding.
inline std::string_view misparsedFnPtrDeclVar( TSNode lhs, std::string_view src )
{
    if( ts_node_is_null( lhs ) || std::strcmp( ts_node_type( lhs ), "call_expression" ) != 0 )
    {
        return {};
    }
    const TSNode inner = ts_node_child_by_field_name( lhs, "function", 8 );
    if( ts_node_is_null( inner ) || std::strcmp( ts_node_type( inner ), "call_expression" ) != 0 )
    {
        return {};
    }
    const TSNode ty = ts_node_child_by_field_name( inner, "function", 8 );
    if( ts_node_is_null( ty ) || std::strcmp( ts_node_type( ty ), "primitive_type" ) != 0 )
    {
        return {};
    }
    const TSNode args = ts_node_child_by_field_name( inner, "arguments", 9 );
    if( ts_node_is_null( args ) || ts_node_named_child_count( args ) != 1 )
    {
        return {};
    }
    const TSNode pe = ts_node_named_child( args, 0 );
    if( std::strcmp( ts_node_type( pe ), "pointer_expression" ) != 0 )
    {
        return {};
    }
    const TSNode op = ts_node_child( pe, 0 );
    if( ts_node_is_null( op ) || std::strcmp( ts_node_type( op ), "*" ) != 0 )
    {
        return {};
    }
    const TSNode idn = ts_node_child_by_field_name( pe, "argument", 8 );
    if( ts_node_is_null( idn ) || std::strcmp( ts_node_type( idn ), "identifier" ) != 0 )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( idn ), b = ts_node_end_byte( idn );
    return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
}

// L3: an assignment whose RHS is not a recognizable single function — a CLOBBER site, emitted as a
// kFnBindClobberTarget record at the end of the walk IF the var has a fn binding in the same file.
struct FnBindClobber
{
    std::string   var;
    std::uint32_t startByte = 0;
};

// ── L3 VALUE-ASSIGNMENT NOISE GATE (r9 fix round) ────────────────────────────────────────────────────
// The DECLARATION arm gates its bare-identifier initializer on the written type (`int a = b;` is a copy,
// not a function). The ASSIGNMENT arm carries no type node at all, so before this gate EVERY `x = y;` with
// a bare-identifier RHS minted an FnAssign — `std::string line; line = zzz;` included. Two measured harms,
// both from a binding that names no function anybody could call: shadowSuppressedSite VETOES local-shadow
// suppression for any name carrying an L3 binding (calls THROUGH a bound variable must keep resolving), so
// the local handed its every read/write back to the function it shadows; and buildFnPtrBindTables' file-
// scope sweep keys FnAssign records by VAR NAME ALONE across the whole corpus, so one bogus record
// TOMBSTONED a genuine, never-clobbered file-scope binding of the same name in an unrelated file.
// The gate asks the file's own declarations of that name what the variable IS:
//   * PROVEN VALUE — declared with a concrete written type that is no function-pointer alias → the
//     assignment is a copy: no positive, a CLOBBER instead (exactly what `fn = getHandler()` records),
//     inert unless the name holds a real binding here and correctly tombstoning it when it does;
//   * FN-CAPABLE — a fn-pointer declarator (`void (*fp)()`) or a fn-pointer alias type (`H fp;`) → mint,
//     and this wins over any value evidence for the same name (recall-safe when a file reuses a name);
//   * NEITHER — `auto`, `decltype`, a template type, or a name this file never declares (a global, a
//     member, an extern): UNKNOWN, and unknown MINTS, exactly as before. When in doubt, don't gate.
// File-scoped and name-based, like every other L3 table: evidence from one function's declarations reaches
// another's assignment of the same name. That over-approximation runs toward NOT minting a binding, which
// is the side that can only cost a disclosed edge, never invent one. Address-of (`fn = &beta`) and lambda
// RHS forms are self-evidencing and never reach the gate.
// Each fact carries the DEFINITION it was declared inside, so one file declaring `std::string run;` in one
// function and `void (*run)();` in another gets both answers right; a file-scope declaration carries {0,0}
// and applies everywhere. This is a function-granular scope, deliberately coarser than the shadow spans in
// model.h — it decides what a NAME can hold, not which sites a declaration claims.
struct FnBindVarTypeFact
{
    std::string   var;
    std::string   typeName;              // final segment of a WRITTEN type name; "" for the unnamed kinds
    std::uint32_t scopeStart   = 0;      // the enclosing definition's byte span; {0,0} = file scope
    std::uint32_t scopeEnd     = 0;
    bool        concreteType  = false;   // the type node's spelling FIXES the type (never auto/decltype/template)
    bool        fnPtrVariable = false;   // the declarator chain is a function POINTER, not a plain value
};

// a bare-identifier assignment held back until the walk ends, when the file's full declaration evidence —
// including declarations the DFS has not reached yet — decides whether it mints a binding or a clobber.
// Deferring is what keeps the verdict independent of walk order, and so of the AST's shape.
struct PendingFnBindAssign
{
    std::string   var;
    std::string   target;
    std::uint32_t startByte = 0;
};

// a bare-identifier DECLARATION initializer held back the same way, and for one reason only: the fn-pointer
// ALIAS table is not complete until the walk ends, and a `typedef void (*H)();` written BELOW `H fp = beta;`
// is the difference between a binding and a copy. Unlike its assignment sibling this record carries its own
// verdict material — the declaration's WRITTEN TYPE, read straight off the node — because a declaration IS
// the variable and needs no file-wide fact lookup to say what it holds.
struct PendingFnBindDecl
{
    std::string   var;
    std::string   target;
    std::string   typeName;              // final segment of the written type; "" for the unnamed concrete kinds
    std::uint32_t startByte    = 0;
    bool          concreteType = false;  // the spelling FIXES the type (never auto/decltype/template)
};

// the gate's whole per-file state: the declared-variable type facts, the file's function-pointer type
// aliases, and the assignments AND declarations held back until both of those are complete. One object
// because they have no independent life — filled by one walk and spent together the moment it ends.
struct FnBindGateState
{
    std::vector<FnBindVarTypeFact>   facts;
    std::vector<PendingFnBindAssign> pending;
    std::vector<PendingFnBindDecl>   pendingDecl;
    HashMap<std::string, char>       aliases;
};

// true when a `type:` field node is a CONCRETE written type — one whose spelling alone fixes what the
// variable is. `name` receives the final segment for the NAMED kinds (the only ones a typedef can make a
// function pointer); the built-in and class/enum-body kinds can never be one and leave it empty. Everything
// else — `auto`, `decltype`, and any type carrying TEMPLATE ARGUMENTS — is dependent, not concrete: the
// spelling of `std::function<void()>` says nothing about callability the way `std::string` does.
inline bool concreteWrittenType( TSNode typeNode, std::string_view src, std::string& name )
{
    name.clear();
    if( ts_node_is_null( typeNode ) )
    {
        return false;
    }
    const char* tt = ts_node_type( typeNode );
    if( std::strcmp( tt, "primitive_type" ) == 0 || std::strcmp( tt, "sized_type_specifier" ) == 0
        || std::strcmp( tt, "struct_specifier" ) == 0 || std::strcmp( tt, "class_specifier" ) == 0
        || std::strcmp( tt, "union_specifier" ) == 0 || std::strcmp( tt, "enum_specifier" ) == 0 )
    {
        return true;
    }
    if( std::strcmp( tt, "type_identifier" ) != 0 && std::strcmp( tt, "qualified_identifier" ) != 0
        && std::strcmp( tt, "scoped_type_identifier" ) != 0 )
    {
        return false;
    }
    const std::string_view text = nodeTextOf( typeNode, src );
    if( text.empty() || text.find( '<' ) != std::string_view::npos )
    {
        return false;
    }
    name = finalSegment( text );
    return true;
}

// the TYPE-ALIAS name a node declares for a FUNCTION-POINTER type — `typedef void (*H)();` and
// `using H = void(*)();` both yield "H"; every other typedef/alias yields "". This is the one piece of
// evidence that separates a callable alias from an ordinary class name, both of which reach a declaration
// as a bare `type_identifier`. Same-file only, which is the disclosed limit: an alias declared in a header
// is invisible to a per-file parse, so a variable of that type stays UNKNOWN — and unknown still mints.
inline std::string_view fnPtrAliasName( TSNode n, const char* t, std::string_view src )
{
    if( std::strcmp( t, "alias_declaration" ) == 0 )
    {
        const TSNode desc = ts_node_child_by_field_name( n, "type", 4 );
        if( ts_node_is_null( desc ) )
        {
            return {};
        }
        const TSNode abst = ts_node_child_by_field_name( desc, "declarator", 10 );
        if( ts_node_is_null( abst ) || std::strcmp( ts_node_type( abst ), "abstract_function_declarator" ) != 0 )
        {
            return {};
        }
        const TSNode nm = ts_node_child_by_field_name( n, "name", 4 );
        return ts_node_is_null( nm ) ? std::string_view{} : nodeTextOf( nm, src );
    }
    if( std::strcmp( t, "type_definition" ) != 0 )
    {
        return {};
    }
    const std::uint32_t cc = ts_node_child_count( n );
    for( std::uint32_t i = 0; i < cc; ++i )
    {
        const char* fname = ts_node_field_name_for_child( n, i );
        if( fname == nullptr || std::strcmp( fname, "declarator" ) != 0 )
        {
            continue;
        }
        TSNode d       = ts_node_child( n, i );
        bool   crossed = false;
        for( int guard = 0; guard < 10 && !ts_node_is_null( d ); ++guard )
        {
            const char* dt = ts_node_type( d );
            if( std::strcmp( dt, "type_identifier" ) == 0 )
            {
                return crossed ? nodeTextOf( d, src ) : std::string_view{};
            }
            if( std::strcmp( dt, "function_declarator" ) == 0 )
            {
                crossed = true;
            }
            TSNode inner = ts_node_child_by_field_name( d, "declarator", 10 );
            if( ts_node_is_null( inner ) && ts_node_named_child_count( d ) > 0 )
            {
                inner = ts_node_named_child( d, 0 );
            }
            d = inner;
        }
    }
    return {};
}

// the byte span of the DEFINITION a node sits inside — a function body or a lambda, whichever encloses it
// first. {0,0} at file/namespace/class scope, which the gate reads as "applies everywhere": a file-scope
// variable IS in scope in every function below it.
inline std::pair<std::uint32_t, std::uint32_t> enclosingDefSpan( TSNode n )
{
    TSNode p = ts_node_parent( n );
    for( int guard = 0; guard < 128 && !ts_node_is_null( p ); ++guard )
    {
        const char* pt = ts_node_type( p );
        if( std::strcmp( pt, "function_definition" ) == 0 || std::strcmp( pt, "lambda_expression" ) == 0 )
        {
            return { ts_node_start_byte( p ), ts_node_end_byte( p ) };
        }
        p = ts_node_parent( p );
    }
    return { 0u, 0u };
}

// record one declaration node's type facts — one per DECLARED VARIABLE. Covers the three shapes that
// declare a name a later `x = y;` can target: a block/file `declaration`, a function `parameter_declaration`
// (a value parameter reassigned from another parameter is the same copy), and a `field_declaration`.
inline void collectFnBindTypeFacts( TSNode n, const char* t, std::string_view src, std::vector<FnBindVarTypeFact>& facts )
{
    if( std::strcmp( t, "declaration" ) != 0 && std::strcmp( t, "parameter_declaration" ) != 0
        && std::strcmp( t, "optional_parameter_declaration" ) != 0 && std::strcmp( t, "field_declaration" ) != 0 )
    {
        return;
    }
    std::string typeName;
    const bool  concrete           = concreteWrittenType( ts_node_child_by_field_name( n, "type", 4 ), src, typeName );
    const auto [ scopeStart, scopeEnd ] = enclosingDefSpan( n );
    const std::uint32_t cc = ts_node_child_count( n );
    for( std::uint32_t i = 0; i < cc; ++i )
    {
        const char* fname = ts_node_field_name_for_child( n, i );
        if( fname == nullptr || std::strcmp( fname, "declarator" ) != 0 )
        {
            continue;
        }
        TSNode d = ts_node_child( n, i );
        if( std::strcmp( ts_node_type( d ), "init_declarator" ) == 0 )
        {
            d = ts_node_child_by_field_name( d, "declarator", 10 );
        }
        const FnBindDeclShape shape = fnDeclaratorShape( d, src );
        if( shape.name.empty() || ( shape.sawFn && !shape.sawPtr ) )
        {
            continue;   // nameless, an array of pointers, or a plain function DECLARATION — no variable here
        }
        facts.push_back( { std::string( shape.name ), typeName, scopeStart, scopeEnd, concrete, shape.sawFn && shape.sawPtr } );
    }
}

// the gate's whole per-node collection: a declaration's variable type facts AND, from the same node, any
// function-pointer type alias it declares. `cFamily` is taken rather than checked at the call site so the
// walk carries ONE unconditional line for the evidence — a `declaration` node feeds both the L3 capture
// arms and the type facts here, and a typedef/alias node reaches neither of those arms.
inline void collectFnBindGateEvidence( TSNode n, const char* t, std::string_view src, bool cFamily, FnBindGateState& gate )
{
    if( !cFamily )
    {
        return;
    }
    collectFnBindTypeFacts( n, t, src, gate.facts );
    if( const std::string_view alias = fnPtrAliasName( n, t, src ); !alias.empty() )
    {
        gate.aliases.try_emplace( std::string( alias ), 1 );
    }
}

// the gate's verdict for one assignment: true ⇒ the file PROVED this name is a value variable where the
// assignment sits, so it is a copy and mints no binding. Only facts whose definition span CONTAINS the
// assignment count (plus file-scope ones, which contain everything); among those, fn-pointer evidence wins
// outright, and with no fact at all the name is unknown and the answer is false (mint, exactly as before).
inline bool fnBindProvenValueVar( std::string_view var, std::uint32_t startByte,
                                  const std::vector<FnBindVarTypeFact>& facts,
                                  const HashMap<std::string, char>& fnAliases )
{
    bool proven = false;
    for( const FnBindVarTypeFact& f : facts )
    {
        if( f.var != var )
        {
            continue;
        }
        if( f.scopeEnd != 0u && ( startByte < f.scopeStart || startByte >= f.scopeEnd ) )
        {
            continue;   // declared inside a definition this assignment is not in — a different variable
        }
        const bool aliasTyped = !f.typeName.empty() && fnAliases.find( f.typeName ) != fnAliases.end();
        if( f.fnPtrVariable || aliasTyped )
        {
            return false;
        }
        proven = proven || ( f.concreteType && !aliasTyped );
    }
    return proven;
}

// where a bind-record SITS: its own position (for enclosing-def attribution) plus, on VarDecl records,
// the declaring BLOCK's byte range — the shadow scope model.h's suppressShadowedReferences tests sites
// against ({0,0} on every other kind: contains nothing, inert by construction).
struct BindSite
{
    std::uint32_t startByte = 0;
    std::uint32_t spanStart = 0;
    std::uint32_t spanEnd   = 0;
};

// the ONE bind-record emitter. A nameless declarator records nothing. kind=VarDecl is the r9 shadow-
// evidence record: typeName stays EMPTY on it (shadow evidence, not narrowing fuel — nothing downstream
// ever reads a type off it), so the empty-typeName refusal applies to every OTHER kind, where it is
// load-bearing for Rule 2 (an undecidable type must degrade to §2a, not mint a half-record).
inline void pushRawBind( std::uint32_t fileId, Lang lang, std::string_view var, std::string typeName,
                         BindSite site, LocalBindKind kind, std::vector<RawBind>& binds )
{
    if( var.empty() || ( typeName.empty() && kind != LocalBindKind::VarDecl ) )
    {
        return;
    }
    RawBind b;
    b.fileId    = fileId;
    b.startByte = site.startByte;
    b.lang      = lang;
    b.kind      = kind;
    b.spanStart = site.spanStart;
    b.spanEnd   = site.spanEnd;
    b.var.assign( var );
    b.typeName  = std::move( typeName );
    binds.push_back( std::move( b ) );
}

// emit a Rule-2 binding from one declared variable: prefer the WRITTEN type; else infer from a
// constructor-style initializer (`auto x = Foo()`). Records nothing when neither is decidable.
inline void emitBind( std::uint32_t fileId, Lang lang, std::string_view var, std::string typeName,
                      std::uint32_t startByte, std::vector<RawBind>& binds )
{
    pushRawBind( fileId, lang, var, std::move( typeName ), BindSite{ startByte, 0u, 0u }, LocalBindKind::Type, binds );
}

// the scope a `declaration` node's names shadow within: the byte span, plus whether that span came from a
// PLAIN BLOCK (the only kind the declaration-point narrowing below applies to). {0,0} when nothing encloses
// (file/namespace/class scope): such a record can contain no site and is inert by construction.
struct ShadowScope
{
    std::uint32_t start      = 0;
    std::uint32_t end        = 0;
    bool          plainBlock = false;
};

// r9 shadow fix round (A5, iteration 3): the byte span a declaration's names are scoped to. A declaration
// in a control statement's HEADER — for-init (`for (int run = 0; ...)`), if/while/switch condition
// (`if (int run = f())`) — scopes to THAT STATEMENT's full span (C++: the variable lives for the whole
// statement, else-branch included), NOT the enclosing block: the header declaration is a SIBLING of the
// statement's body, so the plain compound_statement walk of iteration 2 leaked the scope past the loop and
// ate every genuine call after it. A header declaration reaches its control statement BEFORE any
// compound_statement (bodies ARE compound_statements, and C++ forbids a declaration as a braceless body),
// so "first ancestor of either kind wins" needs no field tracking — a body declaration hits the body block
// first, a header declaration the statement first. That same discrimination is what plainBlock reports.
inline ShadowScope enclosingShadowScope( TSNode n )
{
    TSNode p = ts_node_parent( n );
    for( int guard = 0; guard < 128 && !ts_node_is_null( p ); ++guard )
    {
        const char* pt = ts_node_type( p );
        if( std::strcmp( pt, "compound_statement" ) == 0 )
        {
            return { ts_node_start_byte( p ), ts_node_end_byte( p ), true };
        }
        if(    std::strcmp( pt, "for_statement" ) == 0 || std::strcmp( pt, "for_range_loop" ) == 0
            || std::strcmp( pt, "if_statement" ) == 0  || std::strcmp( pt, "while_statement" ) == 0
            || std::strcmp( pt, "switch_statement" ) == 0 )
        {
            return { ts_node_start_byte( p ), ts_node_end_byte( p ), false };
        }
        p = ts_node_parent( p );
    }
    return { 0u, 0u, false };
}

// r9 shadow fix round (A5, iteration 4): where an ordinary block declaration's names START shadowing.
// Iteration 2 started every span at the BLOCK's opening brace, which silently ate a genuine call written
// ABOVE the shadowing local (`key(); int key = 0;` lost the call — verifier attack4, a recall loss, not the
// disclosed over-suppression). THE DECLARATION POINT SHIPPED HERE IS THE END BYTE OF THE COMPLETE
// DECLARATOR, which is C++ [basic.scope.pdecl] exactly: the locus of a declarator is immediately after the
// complete declarator and before its initializer, and a structured binding's is immediately after its
// identifier-list — the outermost declarator's end byte is both. So `int a = probe(), probe = 0, b = probe;`
// keeps the call in a's initializer and suppresses b's read, and `int probe = probe;` suppresses its own
// initializer (which IS the new local, indeterminate value and all). The point itself is exact — a byte
// offset the grammar hands us, not an approximation — so what remains is the floor that was always there
// and is now simply visible ABOVE the point too: a pre-declaration site is only KEPT, never resolved, so if
// the name there denotes an OUTER local rather than the indexed symbol, --uses still name-matches it (the
// header's own "reference-name-based" disclosure). The one declaration this cannot narrow is a declarator
// tree emitShadowVarDecls refuses (`std::string key( tok );`, the most-vexing parse), which records no
// evidence at all and is the disclosed floor already.
// Applies ONLY to a plain block: a control-statement header declaration, and every whole-scope shape
// (definition/lambda/catch parameters, captures, range-for variables), is in scope from the START of its
// scope, so narrowing those would re-mint the false positives iterations 1-3 removed.
inline std::uint32_t shadowSpanStart( const ShadowScope& scope, TSNode completeDeclarator )
{
    if( !scope.plainBlock || ts_node_is_null( completeDeclarator ) )
    {
        return scope.start;
    }
    const std::uint32_t point = ts_node_end_byte( completeDeclarator );
    return point > scope.start ? point : scope.start;
}

// r9 shadow fix round (A5): every VARIABLE name a declarator declares → one VarDecl record each, carrying
// the declaring block's span. Handles the shapes the verifier refuted the first landing on:
//   * reference_declarator / parenthesized_declarator hold their inner declarator as an UNNAMED child
//     (no `declarator` field — same grammar fact fnDeclaratorVarName already works around), so a
//     field-only unwrap missed `const T& key` entirely — pass-by-const-ref, the most idiomatic C++
//     parameter shape;
//   * structured_binding_declarator (`auto& [key, w]`) declares SEVERAL names — one record per identifier;
//   * a plain function declarator still yields NOTHING (`void helper();` in a body and the most-vexing-
//     parse `Foo x();` declare a FUNCTION, whose calls must never be suppressed), while a
//     function_declarator whose inner is PARENTHESIZED is a fn-POINTER variable and stays a variable.
// Conservative by construction: an unrecognized shape captures nothing (under-suppression, the disclosed
// floor — e.g. the ctor-style most-vexing `std::string key( tok );`, which parses as a function decl).
inline void emitShadowVarDecls( std::uint32_t fileId, Lang lang, TSNode decl, std::string_view src,
                                BindSite site, std::vector<RawBind>& binds )
{
    for( int guard = 0; guard < 8 && !ts_node_is_null( decl ); ++guard )
    {
        const char* dt = ts_node_type( decl );
        if( std::strcmp( dt, "identifier" ) == 0 )
        {
            pushRawBind( fileId, lang, nodeTextOf( decl, src ), std::string{}, site, LocalBindKind::VarDecl, binds );
            return;
        }
        if( std::strcmp( dt, "structured_binding_declarator" ) == 0 )
        {
            const std::uint32_t cc = ts_node_named_child_count( decl );
            for( std::uint32_t i = 0; i < cc; ++i )
            {
                const TSNode c = ts_node_named_child( decl, i );
                if( std::strcmp( ts_node_type( c ), "identifier" ) == 0 )
                {
                    pushRawBind( fileId, lang, nodeTextOf( c, src ), std::string{}, site, LocalBindKind::VarDecl, binds );
                }
            }
            return;
        }
        TSNode inner = ts_node_child_by_field_name( decl, "declarator", 10 );
        if( ts_node_is_null( inner )
            && ( std::strcmp( dt, "reference_declarator" ) == 0 || std::strcmp( dt, "parenthesized_declarator" ) == 0 )
            && ts_node_named_child_count( decl ) > 0 )
        {
            inner = ts_node_named_child( decl, 0 );   // the inner declarator is an UNNAMED child here
        }
        if( ts_node_is_null( inner ) )
        {
            return;
        }
        if( std::strcmp( dt, "function_declarator" ) == 0 && std::strcmp( ts_node_type( inner ), "parenthesized_declarator" ) != 0 )
        {
            return;   // a FUNCTION's name, not a variable's
        }
        decl = inner;
    }
}

// one DECLARATOR → both records: the Rule-2 var→type binding and the r9 VarDecl shadow record(s). The two
// name reads stay separate on purpose — declaratorVarName descends into a function declarator (harmless
// for narrowing), emitShadowVarDecls refuses it (load-bearing for suppression).
inline void emitDeclBinds( std::uint32_t fileId, Lang lang, TSNode declNode, std::string_view src, std::string type,
                           BindSite site, std::vector<RawBind>& binds )
{
    emitBind( fileId, lang, declaratorVarName( declNode, src ), std::move( type ), site.startByte, binds );
    emitShadowVarDecls( fileId, lang, declNode, src, site, binds );
}

// one parameter_list → VarDecl records for its named parameters, scoped to the owning BODY's span. Shared
// by the function-definition and lambda arms below (their parameter semantics are identical: names local
// to the body).
inline void emitShadowParamDecls( TSNode params, std::uint32_t fileId, Lang lang, std::string_view src,
                                  BindSite bodySite, std::vector<RawBind>& binds )
{
    const std::uint32_t cc = ts_node_child_count( params );
    for( std::uint32_t i = 0; i < cc; ++i )
    {
        const TSNode p  = ts_node_child( params, i );
        const char*  pt = ts_node_type( p );
        if( std::strcmp( pt, "parameter_declaration" ) != 0 && std::strcmp( pt, "optional_parameter_declaration" ) != 0 )
        {
            continue;   // commas, `...`, attribute nodes — nothing declared
        }
        bodySite.startByte = ts_node_start_byte( p );
        emitShadowVarDecls( fileId, lang, ts_node_child_by_field_name( p, "declarator", 10 ), src, bodySite, binds );
    }
}

// A5 fix round: one LAMBDA's shadow-evidence names — parameters and capture-list names, all scoped to the
// lambda BODY's span. Lambdas are expressions, not definitions, so the definition arm below never sees
// them (the r9 sweep's A01 query is exactly a lambda parameter shadowing an indexed function). A simple
// capture (`[run]`) re-binds an outer VARIABLE (a function cannot be captured, so the name always denotes
// a variable) and an init-capture (`[trim = expr]`, node lambda_capture_initializer) introduces a NEW
// name — both are VarDecl evidence for the body span.
inline void captureLambdaShadowDecls( TSNode n, std::uint32_t fileId, Lang lang, std::string_view src,
                                      BindSite bodySite, std::vector<RawBind>& binds )
{
    const TSNode d = ts_node_child_by_field_name( n, "declarator", 10 );   // abstract_function_declarator
    if( !ts_node_is_null( d ) )
    {
        const TSNode params = ts_node_child_by_field_name( d, "parameters", 10 );
        if( !ts_node_is_null( params ) )
        {
            emitShadowParamDecls( params, fileId, lang, src, bodySite, binds );
        }
    }
    const TSNode caps = ts_node_child_by_field_name( n, "captures", 8 );   // lambda_capture_specifier
    const std::uint32_t cc = ts_node_is_null( caps ) ? 0u : ts_node_named_child_count( caps );
    for( std::uint32_t i = 0; i < cc; ++i )
    {
        const TSNode c  = ts_node_named_child( caps, i );
        const char*  ct = ts_node_type( c );
        TSNode ident {};
        if( std::strcmp( ct, "identifier" ) == 0 )
        {
            ident = c;   // simple capture `[run]` / `[&run]` (the `&` is an anonymous sibling)
        }
        else if( std::strcmp( ct, "lambda_capture_initializer" ) == 0 && ts_node_named_child_count( c ) > 0 )
        {
            const TSNode nm = ts_node_named_child( c, 0 );   // `[trim = expr]` — the FIRST named child is the introduced name
            if( std::strcmp( ts_node_type( nm ), "identifier" ) == 0 )
            {
                ident = nm;
            }
        }
        if( !ts_node_is_null( ident ) )
        {
            bodySite.startByte = ts_node_start_byte( c );
            pushRawBind( fileId, lang, nodeTextOf( ident, src ), std::string{}, bodySite, LocalBindKind::VarDecl, binds );
        }
    }
}

// a function DEFINITION's parameter_list, reached through its own declarator chain (`char* f(...)` /
// `T& f(...)` unwrap to the function_declarator). Null when the shape isn't a plain definition —
// walking only THIS chain (never bare parameter_declaration nodes) is what keeps a PROTOTYPE's
// parameters and a fn-pointer TYPE's parameter list out of shadow evidence.
inline TSNode fnDefParameterList( TSNode fnDef )
{
    TSNode decl = ts_node_child_by_field_name( fnDef, "declarator", 10 );
    for( int guard = 0; guard < 8 && !ts_node_is_null( decl ) && std::strcmp( ts_node_type( decl ), "function_declarator" ) != 0; ++guard )
    {
        decl = ts_node_child_by_field_name( decl, "declarator", 10 );
    }
    if( ts_node_is_null( decl ) || std::strcmp( ts_node_type( decl ), "function_declarator" ) != 0 )
    {
        return TSNode{};
    }
    return ts_node_child_by_field_name( decl, "parameters", 10 );
}

// r9 shadow suppression (A5 fix round): the local-declaring shapes that live OUTSIDE `declaration` nodes
// (the Rule-2 branch never sees them), dispatched on the caller's already-read node type `t`:
//   * a range-for's loop variable (`for( auto& s : v )`, incl. structured bindings) — scoped to the WHOLE
//     loop statement (iteration 3, unified with enclosingShadowScope's control-statement rule);
//   * a C++/ObjC function DEFINITION's named parameters — scoped to the definition BODY's span. Walking
//     only the definition node's own declarator chain (never bare parameter_declaration nodes) is what
//     keeps two non-scopes out: a PROTOTYPE's parameters (`void f(int run);` binds nothing anywhere) and a
//     fn-pointer type's parameter list (`void (*cb)(int run)` — those names are part of a TYPE, in no
//     scope at all);
//   * a LAMBDA's parameters and capture-list names — captureLambdaShadowDecls above;
//   * a CATCH clause's parameter — a local of its handler block (iteration 3, the noted 3b gap).
// Gates the language and node type ITSELF, so captureBindings calls it unconditionally — the shapes are
// disjoint from every branch of the Rule-2 chain there.
inline void captureShadowScopeDecls( TSNode n, const char* t, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<RawBind>& binds )
{
    if( lang != Lang::Cpp && lang != Lang::ObjC )
    {
        return;
    }
    const bool isRangeFor = std::strcmp( t, "for_range_loop" ) == 0;
    const bool isLambda   = !isRangeFor && std::strcmp( t, "lambda_expression" ) == 0;
    const bool isCatch    = !isRangeFor && !isLambda && std::strcmp( t, "catch_clause" ) == 0;
    const bool isFnDef    = !isRangeFor && !isLambda && !isCatch && std::strcmp( t, "function_definition" ) == 0;
    if( !isRangeFor && !isLambda && !isCatch && !isFnDef )
    {
        return;   // every other node type declares nothing this capture owns
    }
    const TSNode body = ts_node_child_by_field_name( n, "body", 4 );
    if( ts_node_is_null( body ) )
    {
        return;   // a body-less shape scopes nothing (declaration-only lambda/definition never parses so)
    }
    const BindSite bodySite{ ts_node_start_byte( n ), ts_node_start_byte( body ), ts_node_end_byte( body ) };
    if( isRangeFor )
    {
        // iteration 3, unified with enclosingShadowScope's control-statement rule: the loop variable scopes
        // to the WHOLE for_range_loop statement (its own span), not merely the body.
        const BindSite loopSite{ ts_node_start_byte( n ), ts_node_start_byte( n ), ts_node_end_byte( n ) };
        emitShadowVarDecls( fileId, lang, ts_node_child_by_field_name( n, "declarator", 10 ), src, loopSite, binds );
        return;
    }
    if( isLambda )
    {
        captureLambdaShadowDecls( n, fileId, lang, src, bodySite, binds );
        return;
    }
    // a catch parameter is a local of its HANDLER block (iteration 3, the noted 3b gap) — its
    // parameter_list is a direct field; a definition's sits behind the declarator chain
    // (fnDefParameterList above), which is what keeps prototypes and fn-pointer TYPE params out.
    const TSNode params = isCatch ? ts_node_child_by_field_name( n, "parameters", 10 ) : fnDefParameterList( n );
    if( !ts_node_is_null( params ) )
    {
        emitShadowParamDecls( params, fileId, lang, src, bodySite, binds );
    }
}

// emit one L3 var→function RawBind (kind FnDecl/FnAssign) — emitBind's record shape with the kind stamped
// after the push, so the two emitters share ONE body instead of cloning it.
inline void emitFnBind( std::uint32_t fileId, Lang lang, std::string_view var, std::string target,
                        std::uint32_t startByte, LocalBindKind kind, std::vector<RawBind>& binds )
{
    const std::size_t before = binds.size();
    emitBind( fileId, lang, var, std::move( target ), startByte, binds );
    if( binds.size() > before )
    {
        binds.back().kind = kind;
    }
}

// L3 capture over one C-family `declaration` node: one FnDecl record per init_declarator whose RHS names a
// function (`&alpha` / `beta` / a lambda). `&name` and lambdas are self-evidencing and emit at once;
// a BARE-IDENTIFIER initializer is the one shape a fn-pointer bind shares with a plain value copy, so it
// goes to the VALUE-INITIALIZATION NOISE GATE below (`pending`) unless the declarator itself spells a fn
// pointer, which settles it on the spot.
// A reference declarator (`H& r = fn;`) emits NO positive and clobbers the bound-to var (A5 escape guard).
inline void captureFnBindDecl( TSNode n, std::uint32_t fileId, Lang lang, std::string_view src,
                               std::vector<RawBind>& fnPos, std::vector<FnBindClobber>& fnUnk,
                               std::vector<PendingFnBindDecl>& pending )
{
    const TSNode typeNode = ts_node_child_by_field_name( n, "type", 4 );
    std::string  writtenType;
    const bool   concrete = concreteWrittenType( typeNode, src, writtenType );
    const std::uint32_t cc = ts_node_child_count( n );
    for( std::uint32_t i = 0; i < cc; ++i )
    {
        const char* fname = ts_node_field_name_for_child( n, i );
        if( fname == nullptr || std::strcmp( fname, "declarator" ) != 0 )
        {
            continue;
        }
        const TSNode c = ts_node_child( n, i );
        if( std::strcmp( ts_node_type( c ), "init_declarator" ) != 0 )
        {
            continue;   // no initializer → no binding fact here (a later assignment carries its own)
        }
        const auto [ var, sawFnDecl, sawPtrDecl, sawRef ] = fnDeclaratorShape( ts_node_child_by_field_name( c, "declarator", 10 ), src );
        const TSNode valueNode = ts_node_child_by_field_name( c, "value", 5 );
        if( sawRef )
        {
            // A5 escape guard: `H& r = fn;` / `auto& r = fn;` ALIASES fn — a write through r retargets fn
            // invisibly, so the bound-to variable is clobbered (toward tombstone, never toward resolve) and
            // the alias itself gets NO positive (its target can change under it the same way).
            if( !ts_node_is_null( valueNode ) && std::strcmp( ts_node_type( valueNode ), "identifier" ) == 0 )
            {
                const std::string_view aliased = nodeTextOf( valueNode, src );
                if( !aliased.empty() )
                {
                    fnUnk.push_back( { std::string( aliased ), ts_node_start_byte( n ) } );
                }
            }
            continue;
        }
        bool bareIdent = false;
        std::string target = fnBindTargetOf( valueNode, src, bareIdent );
        if( bareIdent && !target.empty() && !( sawFnDecl && sawPtrDecl ) )
        {
            // the declarator does not itself spell a fn pointer, so only the WRITTEN TYPE can tell a bind
            // from a copy — and that answer needs the file's complete alias table. Hold it.
            pending.push_back( { std::string( var ), std::move( target ), writtenType, ts_node_start_byte( n ), concrete } );
            continue;
        }
        emitFnBind( fileId, lang, var, std::move( target ), ts_node_start_byte( n ), LocalBindKind::FnDecl, fnPos );
    }
}

// A5 escape guard over one `pointer_expression`: `&fn` ANYWHERE makes the variable mutable through the
// pointer (`indirect_mutate(&fn)` retargets it behind the resolver's back), so any address-of over a bare
// identifier records a CLOBBER for that identifier — toward tombstone, never toward resolve. A by-value use
// (`takes_fn(fn)`, `other = fn`) copies the pointer and cannot mutate the variable, so it does NOT clobber.
// The `&alpha` inside a positive binding RHS also lands here (clobbering the FUNCTION's name as a "var") —
// harmless-conservative: it only matters if a same-named variable holds a binding in this file, and then
// refusing to resolve it is the safe side. Dereferences (`*p`) are excluded by the operator check.
inline void captureFnBindEscape( TSNode n, std::string_view src, std::vector<FnBindClobber>& fnUnk )
{
    const TSNode op = ts_node_child( n, 0 );
    if( ts_node_is_null( op ) || std::strcmp( ts_node_type( op ), "&" ) != 0 )
    {
        return;
    }
    const TSNode idn = ts_node_child_by_field_name( n, "argument", 8 );
    if( ts_node_is_null( idn ) || std::strcmp( ts_node_type( idn ), "identifier" ) != 0 )
    {
        return;
    }
    const std::string_view var = nodeTextOf( idn, src );
    if( !var.empty() )
    {
        fnUnk.push_back( { std::string( var ), ts_node_start_byte( n ) } );
    }
}

// L3 capture over one C-family `assignment_expression`: a recognizable RHS emits an FnAssign record; any
// other RHS on a bare-identifier LHS (`fn = getHandler()`, `fn = nullptr`, `n += 1`) records a CLOBBER
// candidate, emitted as a tombstone at the end of the walk IF the var has a fn binding in the same file.
// A BARE-IDENTIFIER RHS (`fn = beta;`) is neither yet: it is the one shape a plain value copy shares with a
// genuine fn-pointer rebind, and the assignment node carries no type to tell them apart — so it is held in
// `pending` for the end-of-walk value-assignment noise gate above, which asks the file's own declarations.
// The second branch decodes the C++-grammar MIS-PARSE of a raw fn-pointer declaration (`void (*fn)() =
// &alpha;` — see misparsedFnPtrDeclVar): the shape itself proves a fn-pointer declarator, so a
// bare-identifier RHS is captured immediately there — the "type" IS the evidence, no gate needed.
inline void captureFnBindAssign( TSNode n, std::uint32_t fileId, Lang lang, std::string_view src,
                                 std::vector<RawBind>& fnPos, std::vector<FnBindClobber>& fnUnk,
                                 std::vector<PendingFnBindAssign>& pending )
{
    const TSNode lhs = ts_node_child_by_field_name( n, "left",  4 );
    const TSNode rhs = ts_node_child_by_field_name( n, "right", 5 );
    if( !ts_node_is_null( lhs ) && std::strcmp( ts_node_type( lhs ), "identifier" ) == 0 )
    {
        const std::uint32_t a = ts_node_start_byte( lhs ), b = ts_node_end_byte( lhs );
        if( a <= b && b <= src.size() )
        {
            const std::string_view var = src.substr( a, b - a );
            bool bareIdent = false;
            std::string target = fnBindTargetOf( rhs, src, bareIdent );
            if( target.empty() )
            {
                fnUnk.push_back( { std::string( var ), ts_node_start_byte( n ) } );
            }
            else if( bareIdent )
            {
                pending.push_back( { std::string( var ), std::move( target ), ts_node_start_byte( n ) } );
            }
            else
            {
                emitFnBind( fileId, lang, var, std::move( target ), ts_node_start_byte( n ), LocalBindKind::FnAssign, fnPos );
            }
        }
    }
    else if( const std::string_view dvar = misparsedFnPtrDeclVar( lhs, src ); !dvar.empty() )
    {
        bool bareIdent = false;
        std::string target = fnBindTargetOf( rhs, src, bareIdent );
        if( !target.empty() )
        {
            emitFnBind( fileId, lang, dvar, std::move( target ), ts_node_start_byte( n ), LocalBindKind::FnDecl, fnPos );
        }
        else
        {
            fnUnk.push_back( { std::string( dvar ), ts_node_start_byte( n ) } );
        }
    }
}

// decide every bare-identifier assignment the walk held back, against the file's COMPLETE declaration
// evidence. A name the file proved to be a VALUE variable where the assignment sits records NOTHING — not a
// positive, and deliberately not a clobber either: a clobber is a statement ABOUT a function pointer ("this
// one is no longer trustworthy"), and the end-of-walk sweep promotes it to a real FnAssign tombstone as
// soon as any same-named var in the file holds a binding. That tombstone reads as a binding to every
// consumer — it re-vetoed the very shadow suppression this gate exists to restore. A copy into a string is
// evidence in NEITHER direction. Everything else mints its FnAssign exactly as it did before the gate.
inline void resolvePendingFnBindAssigns( std::uint32_t fileId, Lang lang, FnBindGateState& gate, std::vector<RawBind>& fnPos )
{
    for( PendingFnBindAssign& p : gate.pending )
    {
        if( !fnBindProvenValueVar( p.var, p.startByte, gate.facts, gate.aliases ) )
        {
            emitFnBind( fileId, lang, p.var, std::move( p.target ), p.startByte, LocalBindKind::FnAssign, fnPos );
        }
    }
}

// ── L3 VALUE-INITIALIZATION NOISE GATE (r9 fix round, DECLARATION arm) ───────────────────────────────
// The sibling gate above answers "what is this VARIABLE?" from the file's declarations because an
// assignment node carries no type. A declaration carries one, so this arm asks the stronger question
// directly of the node in front of it: does the WRITTEN TYPE prove a value?
//   * a CONCRETE type that is no fn-pointer alias — `std::string tag = zzz;`, `Box b = other;`,
//     `int a = b;` — is a copy. No binding. Before this gate only the PRIMITIVE half of that was caught,
//     so a CLASS-typed copy minted an FnDecl, and shadowSuppressedSite (model.h) VETOES local-shadow
//     suppression for any name carrying an L3 binding — the local handed its every read/write site back to
//     the function it shadows. That is the same harm, and the same mechanism, as the assignment arm's.
//   * a fn-pointer DECLARATOR (`void (*fp)() = handler;`) never reaches here at all: the shape is its own
//     evidence and captureFnBindDecl emits it on the spot.
//   * a same-file fn-pointer ALIAS (`typedef void (*H)(); H fp = beta;`) mints — the alias table is why
//     these records are deferred to the end of the walk rather than judged where they are written.
//   * everything else is UNKNOWN and unknown MINTS: `auto fp = f;` (the idiomatic form), `decltype(...)`,
//     and any template/dependent type. Refusing to guess is what keeps this gate from costing recall.
// DISCLOSED BLIND SPOT, pinned by test/fnptrcheck.sh arm (t): the alias evidence is SAME-FILE, so a
// `typedef void (*H)();` living in a HEADER leaves `H fp = beta;` indistinguishable from a value copy and
// its edge is gated away. It cost ZERO edges on the two corpora this round measured (this repo, 1093 files
// / 10771 edges, full map byte-identical; a 2376-file ObjC++ tree, 39741 edges, every callee row identical
// and only `unresolved=` moving 2577 → 2509) — but that is a measurement, not a proof. Widening the alias
// evidence corpus-wide is the fix if a corpus ever pays for it.
inline void resolvePendingFnBindDecls( std::uint32_t fileId, Lang lang, FnBindGateState& gate, std::vector<RawBind>& fnPos )
{
    for( PendingFnBindDecl& p : gate.pendingDecl )
    {
        const bool aliasTyped  = !p.typeName.empty() && gate.aliases.find( p.typeName ) != gate.aliases.end();
        const bool provenValue = p.concreteType && !aliasTyped;
        if( !provenValue )
        {
            emitFnBind( fileId, lang, p.var, std::move( p.target ), p.startByte, LocalBindKind::FnDecl, fnPos );
        }
    }
}

// P2-D Rule 2 local var→type bindings + the L3 fn-pointer capture. One visitor on the shared pre-order
// stream (streamSideCaptures below) — the pass used to own an identical walk of its own, which is what the
// fusion removed. Its state outlives a single node (the L3 clobber sweep needs the whole file's positives),
// so it rides in a context the driver holds by reference; bindsFinalize spends it when the stream ends.
struct BindCtx
{
    std::uint32_t              fileId = 0;
    Lang                       lang {};
    std::string_view           src;
    std::vector<RawBind>*      binds = nullptr;

    // L3 fn-pointer buffers. Positives collect here (not straight into binds) so the end-of-walk clobber
    // sweep can ask "does this var have a fn binding in this file?" — a clobbering assignment
    // (`fn = getHandler()`) matters only then, which keeps a fn-binding-free file contributing ZERO new
    // records (the whole feature inert there).
    std::vector<RawBind>       fnPos;
    std::vector<FnBindClobber> fnUnk;
    FnBindGateState            fnGate;      // value-assignment noise-gate evidence — filled by the stream, spent at the end
    bool                       cFamilyFn = false;
};

void bindsVisitNode( BindCtx& cx, TSNode n, const char* t )
{
    // The body below is the pass's own node step, unchanged; these aliases keep it reading against the
    // same names it always had rather than sprinkling `cx.` through 150 lines of grammar branches.
    FUSEPROBE_BUMP( kBinds );
    const std::uint32_t         fileId    = cx.fileId;
    const Lang                  lang      = cx.lang;
    const std::string_view      src       = cx.src;
    std::vector<RawBind>&       binds     = *cx.binds;
    std::vector<RawBind>&       fnPos     = cx.fnPos;
    std::vector<FnBindClobber>& fnUnk     = cx.fnUnk;
    FnBindGateState&            fnGate    = cx.fnGate;
    const bool                  cFamilyFn = cx.cFamilyFn;

    // C++/ObjC: `Foo x;` · `Foo* x;` · `Foo x = Foo();` · `auto x = Foo();`
    if( ( lang == Lang::Cpp || lang == Lang::ObjC ) && std::strcmp( t, "declaration" ) == 0 )
    {
        const TSNode typeNode = ts_node_child_by_field_name( n, "type", 4 );
        std::string  written  = writtenTypeOf( typeNode, src );
        // A5 fix round: the declared names shadow within their enclosing block (or, for a control-statement
        // header declaration, that whole statement) — one parent walk per declaration node, shared by every
        // declarator child below; each declarator then contributes its own declaration POINT as the span's
        // start (shadowSpanStart).
        const ShadowScope scope = enclosingShadowScope( n );
        // a `declaration` can declare several variables (`Foo a, b;`) → one binding per declarator child.
        const std::uint32_t cc = ts_node_child_count( n );
        for( std::uint32_t i = 0; i < cc; ++i )
        {
            const TSNode c  = ts_node_child( n, i );
            if( ts_node_field_name_for_child( n, i ) == nullptr )
            {
                continue;
            }
            if( std::strcmp( ts_node_field_name_for_child( n, i ), "declarator" ) != 0 )
            {
                continue;
            }
            const char* ct = ts_node_type( c );
            // `init_declarator`: name lives in its `declarator`, the RHS in its `value` (for auto inference).
            // emitDeclBinds also records the r9 VarDecl shadow fact for the declared NAME regardless of type
            // resolvability (`int run = 0;` binds no type — writtenTypeOf refuses primitives — yet the local
            // exists and shadows).
            if( std::strcmp( ct, "init_declarator" ) == 0 )
            {
                const TSNode declarator = ts_node_child_by_field_name( c, "declarator", 10 );
                std::string  type       = written.empty() ? ctorTypeOf( ts_node_child_by_field_name( c, "value", 5 ), src ) : written;
                emitDeclBinds( fileId, lang, declarator, src, std::move( type ),
                               BindSite{ ts_node_start_byte( n ), shadowSpanStart( scope, declarator ), scope.end }, binds );
            }
            else   // plain declarator (identifier / pointer_declarator / reference_declarator), no initializer
            {
                emitDeclBinds( fileId, lang, c, src, std::string( written ),
                               BindSite{ ts_node_start_byte( n ), shadowSpanStart( scope, c ), scope.end }, binds );
            }
        }
    }
    // C++ `x = Foo();` (re-assignment to a constructor) — assignment_expression inside an expression_statement.
    else if( ( lang == Lang::Cpp || lang == Lang::ObjC ) && std::strcmp( t, "assignment_expression" ) == 0 )
    {
        const TSNode lhs = ts_node_child_by_field_name( n, "left",  4 );
        const TSNode rhs = ts_node_child_by_field_name( n, "right", 5 );
        if( !ts_node_is_null( lhs ) && std::strcmp( ts_node_type( lhs ), "identifier" ) == 0 )
        {
            const std::uint32_t a = ts_node_start_byte( lhs ), b = ts_node_end_byte( lhs );
            if( a <= b && b <= src.size() )
            {
                emitBind( fileId, lang, src.substr( a, b - a ), ctorTypeOf( rhs, src ), ts_node_start_byte( n ), binds );
            }
        }
    }
    // Python `x = Foo()` — assignment with a bare-identifier LHS and a constructor-call RHS.
    else if( lang == Lang::Python && std::strcmp( t, "assignment" ) == 0 )
    {
        const TSNode lhs = ts_node_child_by_field_name( n, "left",  4 );
        const TSNode rhs = ts_node_child_by_field_name( n, "right", 5 );
        if( !ts_node_is_null( lhs ) && std::strcmp( ts_node_type( lhs ), "identifier" ) == 0 )
        {
            const std::uint32_t a = ts_node_start_byte( lhs ), b = ts_node_end_byte( lhs );
            if( a <= b && b <= src.size() )
            {
                // Python RHS constructor is a `call` node (not `call_expression`); reuse finalSegment on its callee.
                std::string type;
                if( !ts_node_is_null( rhs ) && std::strcmp( ts_node_type( rhs ), "call" ) == 0 )
                {
                    const TSNode fn = ts_node_child_by_field_name( rhs, "function", 8 );
                    if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "identifier" ) == 0 )
                    {
                        const std::uint32_t fa = ts_node_start_byte( fn ), fb = ts_node_end_byte( fn );
                        if( fa <= fb && fb <= src.size() )
                        {
                            type = finalSegment( src.substr( fa, fb - fa ) );
                        }
                    }
                }
                emitBind( fileId, lang, src.substr( a, b - a ), std::move( type ), ts_node_start_byte( n ), binds );
            }
        }
    }
    // TypeScript `const x = new Foo();` · `let y: Bar = ...;` — variable_declarator.
    else if( lang == Lang::TypeScript && std::strcmp( t, "variable_declarator" ) == 0 )
    {
        const TSNode nameNode = ts_node_child_by_field_name( n, "name", 4 );
        if( !ts_node_is_null( nameNode ) && std::strcmp( ts_node_type( nameNode ), "identifier" ) == 0 )
        {
            const std::uint32_t a = ts_node_start_byte( nameNode ), b = ts_node_end_byte( nameNode );
            if( a <= b && b <= src.size() )
            {
                // prefer the `: Type` annotation; else infer from a `new Foo()` / `Foo()` initializer.
                std::string type;
                const TSNode ann = ts_node_child_by_field_name( n, "type", 4 );   // type_annotation
                if( !ts_node_is_null( ann ) )
                {
                    const std::uint32_t cc = ts_node_child_count( ann );
                    for( std::uint32_t i = 0; i < cc; ++i )
                    {
                        const TSNode c = ts_node_child( ann, i );
                        if( std::strcmp( ts_node_type( c ), "type_identifier" ) == 0 )
                        { const std::uint32_t ta = ts_node_start_byte( c ), tb = ts_node_end_byte( c );
                          if( ta <= tb && tb <= src.size() ) { type = finalSegment( src.substr( ta, tb - ta ) ); } break; }
                    }
                }
                if( type.empty() )
                {
                    type = ctorTypeOf( ts_node_child_by_field_name( n, "value", 5 ), src );
                }
                emitBind( fileId, lang, src.substr( a, b - a ), std::move( type ), ts_node_start_byte( n ), binds );
            }
        }
    }

    // r9 shadow suppression: the local-declaring shapes OUTSIDE `declaration` nodes — a function
    // DEFINITION's named parameters and a range-for's loop variable. Unconditional (the helper gates
    // language and node type itself); disjoint from every branch of the Rule-2 chain above.
    captureShadowScopeDecls( n, t, fileId, lang, src, binds );

    // ── L3 fn-pointer/callback capture (C/C++/ObjC) — a SEPARATE if (not part of the Rule-2 chain above):
    // the same `declaration` node can carry BOTH a Rule-2 var→type fact and a var→function fact
    // (`H fnPtr = beta;` emits fnPtr:H for receiver narrowing AND fnPtr→beta for call resolution). ──
    if( cFamilyFn && std::strcmp( t, "declaration" ) == 0 )
    {
        captureFnBindDecl( n, fileId, lang, src, fnPos, fnUnk, fnGate.pendingDecl );
    }
    else if( cFamilyFn && std::strcmp( t, "assignment_expression" ) == 0 )
    {
        captureFnBindAssign( n, fileId, lang, src, fnPos, fnUnk, fnGate.pending );
    }
    else if( cFamilyFn && std::strcmp( t, "pointer_expression" ) == 0 )
    {
        captureFnBindEscape( n, src, fnUnk );   // A5: `&fn` anywhere clobbers the variable (escape guard)
    }
    collectFnBindGateEvidence( n, t, src, cFamilyFn, fnGate );   // never an `else if` — see the helper's note
}

// End-of-file step for the bindings pass: the two noise gates and the L3 clobber sweep. Split out of the
// walk (it was the tail of captureBindings) so the shared stream can run it once the last node is visited.
void bindsFinalize( BindCtx& cx )
{
    const std::uint32_t         fileId = cx.fileId;
    const Lang                  lang   = cx.lang;
    std::vector<RawBind>&       binds  = *cx.binds;
    std::vector<RawBind>&       fnPos  = cx.fnPos;
    std::vector<FnBindClobber>& fnUnk  = cx.fnUnk;
    FnBindGateState&            fnGate = cx.fnGate;

    resolvePendingFnBindDecls  ( fileId, lang, fnGate, fnPos );   // both noise gates — BEFORE the sweep, which needs
    resolvePendingFnBindAssigns( fileId, lang, fnGate, fnPos );   // fnPos final (its var scan is a membership test,
                                                                  // so the deferral cannot change a clobber verdict)

    // ── L3 clobber sweep + merge. A clobbering assignment forces the tombstone (kFnBindClobberTarget) so a
    // stale earlier binding can never win (`void (*fn)() = &alpha; fn = getHandler(); fn();` → NO edge) —
    // but only for a var that HAS a recognizable fn binding somewhere in this file, an over-approximation
    // of "same scope" that errs toward the tombstone, never toward a resolve. posCount is captured BEFORE
    // the emits below so the sweep scans only the walk's own positives.
    if( !fnPos.empty() )
    {
        const std::size_t posCount = fnPos.size();
        for( const FnBindClobber& u : fnUnk )
        {
            bool hasPos = false;
            for( std::size_t p = 0; p < posCount; ++p )
            {
                if( fnPos[p].var == u.var )
                {
                    hasPos = true;
                    break;
                }
            }
            if( hasPos )
            {
                emitFnBind( fileId, lang, u.var, std::string( kFnBindClobberTarget ), u.startByte, LocalBindKind::FnAssign, binds );
            }
        }
        for( RawBind& p : fnPos )
        {
            binds.push_back( std::move( p ) );
        }
    }
}

// ── A4-R5 CROSS-LANGUAGE FFI BINDING capture (pybind11 · extern "C" · ctypes handle) ─────────────────
// Walk a C/C++ or Python subtree and emit one BindingAlias per language-binding DECLARATION, so buildGraph
// can add a provenance-tagged FALLBACK edge across the language border. Pure-syntactic, deterministic. The
// pybind pass is GATED on a `pybind11`/`PYBIND11` signal in the file, so a repo without pybind captures
// NOTHING (the whole feature is inert → byte-identical output on any binding-free corpus). JNI needs no
// capture here — buildGraph decodes it straight from `Java_*` def names.
inline std::string ffiUnquote( std::string_view s )   // strip one layer of "..." / '...'; leaves interior verbatim
{
    if( s.size() >= 2 && ( s.front() == '"' || s.front() == '\'' ) && s.back() == s.front() )
    {
        return std::string( s.substr( 1, s.size() - 2 ) );
    }
    return std::string( s );
}

// "A::B::method" → { scope="B", name="method" }; "foo" → { "", "foo" }. Scope is the IMMEDIATE enclosing
// segment (matches buildGraph's canonByName keying); name is the final identifier segment.
inline std::pair<std::string, std::string> ffiSplitScopeName( std::string_view text )
{
    const std::size_t sep = text.rfind( "::" );
    if( sep == std::string_view::npos )
    {
        return { std::string(), finalSegment( text ) };
    }
    return { finalSegment( text.substr( 0, sep ) ), finalSegment( text.substr( sep + 2 ) ) };
}

// One visitor on the shared pre-order stream (streamSideCaptures below). The pass arms only on C++/ObjC/
// Python; the pybind sub-detector stays gated on a cheap file-level signal so ordinary `.def(` calls in
// non-pybind C++ never capture.
struct FfiCtx
{
    std::uint32_t              fileId = 0;
    std::string_view           src;
    std::vector<BindingAlias>* ffis = nullptr;
    bool                       cish      = false;
    bool                       py        = false;
    bool                       hasPybind = false;
};

FfiCtx makeFfiCtx( std::uint32_t fileId, Lang lang, std::string_view src, std::vector<BindingAlias>& ffis )
{
    FfiCtx cx;
    cx.fileId    = fileId;
    cx.src       = src;
    cx.ffis      = &ffis;
    cx.cish      = ( lang == Lang::Cpp || lang == Lang::ObjC );
    cx.py        = ( lang == Lang::Python );
    cx.hasPybind = cx.cish && ( src.find( "pybind11" ) != std::string_view::npos
                             || src.find( "PYBIND11" ) != std::string_view::npos );
    return cx;
}

void ffiVisitNode( FfiCtx& cx, TSNode n, const char* t )
{
    FUSEPROBE_BUMP( kFfi );
    const std::uint32_t        fileId    = cx.fileId;
    const std::string_view     src       = cx.src;
    std::vector<BindingAlias>& ffis      = *cx.ffis;
    const bool                 cish      = cx.cish;
    const bool                 py        = cx.py;
    const bool                 hasPybind = cx.hasPybind;

    const auto nodeSrc = [ & ]( TSNode nn ) noexcept -> std::string_view { return nodeTextOf( nn, src ); };

        // pybind11:  m.def("alias", &target)  /  cls.def("alias", &Scope::method)  /  .def_static(...)
        if( hasPybind && std::strcmp( t, "call_expression" ) == 0 )
        {
            const TSNode fn = ts_node_child_by_field_name( n, "function", 8 );
            if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "field_expression" ) == 0 )
            {
                const std::string_view meth = nodeSrc( ts_node_child_by_field_name( fn, "field", 5 ) );
                if( meth == "def" || meth == "def_static" )
                {
                    const TSNode args = ts_node_child_by_field_name( n, "arguments", 9 );
                    std::string alias, tgt;
                    const std::uint32_t cc = ts_node_is_null( args ) ? 0 : ts_node_child_count( args );
                    for( std::uint32_t i = 0; i < cc; ++i )
                    {
                        const TSNode c = ts_node_child( args, i );
                        if( !ts_node_is_named( c ) )
                        {
                            continue; // skip '(' ',' ')'
                        }
                        const std::string_view ct = ts_node_type( c );
                        if( alias.empty() && ct == "string_literal" )
                        {
                            alias = ffiUnquote( nodeSrc( c ) );
                        }
                        else if( tgt.empty() )
                        {
                            std::string_view txt = nodeSrc( c );               // `&target` / `&Scope::method`
                            if( !txt.empty() && txt.front() == '&' )
                            {
                                txt.remove_prefix( 1 );
                                while( !txt.empty() && ( txt.front() == ' ' || txt.front() == '\t' ) )
                                {
                                    txt.remove_prefix( 1 );
                                }
                                tgt = std::string( txt );
                            }
                        }
                    }
                    if( !alias.empty() && !tgt.empty() )
                    {
                        auto [ scope, name ] = ffiSplitScopeName( tgt );
                        if( !name.empty() )
                        {
                            ffis.push_back( BindingAlias{ fileId, BindKind::Pybind, false, std::move( alias ), std::move( name ), std::move( scope ) } );
                        }
                    }
                }
            }
        }
        // extern "C": every function DECLARED inside becomes reachable from ctypes/cffi/cgo by its bare name.
        else if( cish && std::strcmp( t, "linkage_specification" ) == 0 )
        {
            // confirm the linkage string is "C" (not "C++") before harvesting.
            bool isC = false;
            const std::uint32_t lc = ts_node_child_count( n );
            for( std::uint32_t i = 0; i < lc; ++i )
            {
                const TSNode c = ts_node_child( n, i );
                if( std::strcmp( ts_node_type( c ), "string_literal" ) == 0 ) { isC = ( ffiUnquote( nodeSrc( c ) ) == "C" ); break; }
            }
            if( isC )
            {
                // inner DFS: collect the identifier of every function_declarator in the linkage body.
                std::vector<TSNode> inner;
                inner.push_back( n );
                while( !inner.empty() )
                {
                    const TSNode m = inner.back();
                    inner.pop_back();
                    if( std::strcmp( ts_node_type( m ), "function_declarator" ) == 0 )
                    {
                        const TSNode decl = ts_node_child_by_field_name( m, "declarator", 10 );
                        if( !ts_node_is_null( decl ) )
                        {
                            const char* dt = ts_node_type( decl );
                            if( std::strcmp( dt, "identifier" ) == 0 || std::strcmp( dt, "field_identifier" ) == 0 )
                            {
                                std::string nm = finalSegment( nodeSrc( decl ) );
                                if( !nm.empty() )
                                {
                                    ffis.push_back( BindingAlias{ fileId, BindKind::ExternC, true, nm, nm, std::string() } );
                                }
                            }
                        }
                    }
                    const std::uint32_t mc = ts_node_child_count( m );
                    for( std::uint32_t i = 0; i < mc; ++i )
                    {
                        inner.push_back( ts_node_child( m, i ) );
                    }
                }
            }
        }
        // Python ctypes handle:  lib = CDLL(...)  /  lib = ctypes.CDLL(...)  /  lib = cdll.LoadLibrary(...)
        else if( py && std::strcmp( t, "assignment" ) == 0 )
        {
            const TSNode lhs = ts_node_child_by_field_name( n, "left",  4 );
            const TSNode rhs = ts_node_child_by_field_name( n, "right", 5 );
            if( !ts_node_is_null( lhs ) && std::strcmp( ts_node_type( lhs ), "identifier" ) == 0
                && !ts_node_is_null( rhs ) && std::strcmp( ts_node_type( rhs ), "call" ) == 0 )
            {
                const std::string_view ftext = nodeSrc( ts_node_child_by_field_name( rhs, "function", 8 ) );
                const std::string      seg   = finalSegment( ftext.substr( 0, ftext.find( '(' ) ) );   // final `.`/`::` segment
                const bool loader = seg == "CDLL" || seg == "WinDLL" || seg == "OleDLL" || seg == "PyDLL"
                                 || seg == "LoadLibrary" || seg == "dlopen";
                if( loader )
                {
                    std::string var( nodeSrc( lhs ) );
                    if( !var.empty() )
                    {
                        ffis.push_back( BindingAlias{ fileId, BindKind::CtypesHandle, true, std::move( var ), std::string(), std::string() } );
                    }
                }
            }
        }
}

// ── B6.3 HTTP-route DEF/USE capture (Express/Fastify · FastAPI/Flask decorators · fetch/axios/requests) ──
// Walk a JS/TS or Python subtree and emit a RouteDef per recognized server-side route registration and a
// RawRouteUse per recognized client-side HTTP call. Pure-syntactic, deterministic, table-driven (the verb
// name → HttpMethod lookup is model.h::kHttpMethodTable, shared by every detector below). Server detectors
// are GATED on a cheap file-level framework signal — the SAME posture as captureFfi's pybind gate above: a
// file that never mentions the framework captures NO route DEF, so the whole feature is inert (byte-
// identical output) on a framework-free corpus. Client detectors need no file gate: `fetch`, `axios.<verb>`,
// `requests.<verb>` are distinctive enough as bare shapes (the object identifier is checked EXACTLY).
// KNOWN LIMITATION (by design, never guessed): a path built from a template literal / f-string / variable
// is NOT a plain "string" node, so it is not captured — only static path literals are detected.

// the first NAMED argument in an `arguments`/`argument_list` node, iff it is a plain "string" literal
// starting with '/' once unquoted — a path-looking literal. "" for anything else (template/f-string,
// identifier, no args): a dynamic path is a deliberate non-detection, never a guess.
inline std::string firstPathStringArg( TSNode argsNode, std::string_view src )
{
    if( ts_node_is_null( argsNode ) || ts_node_named_child_count( argsNode ) == 0 )
    {
        return {};
    }
    const TSNode first = ts_node_named_child( argsNode, 0 );
    if( std::strcmp( ts_node_type( first ), "string" ) != 0 )
    {
        return {}; // template_string/f-string/identifier → skip
    }
    const std::uint32_t a = ts_node_start_byte( first ), b = ts_node_end_byte( first );
    if( a > b || b > src.size() )
    {
        return {};
    }
    std::string path = ffiUnquote( src.substr( a, b - a ) );
    if( path.empty() || path.front() != '/' )
    {
        return {};
    }
    return path;
}

// the LAST named argument's handler name: a bare identifier, or the final `.property` segment of a member
// access (`userController.getUser` → "getUser"). "" for an inline function/arrow expression (anonymous —
// the DEF fact is still recorded; buildGraph just can never attach an edge to it).
inline std::string lastArgHandlerName( TSNode argsNode, std::string_view src )
{
    if( ts_node_is_null( argsNode ) )
    {
        return {};
    }
    const std::uint32_t nc = ts_node_named_child_count( argsNode );
    if( nc == 0 )
    {
        return {};
    }
    const TSNode last = ts_node_named_child( argsNode, nc - 1 );
    const char*  lt   = ts_node_type( last );
    const auto   text = [ & ]( TSNode nn ) -> std::string_view
    {
        const std::uint32_t a = ts_node_start_byte( nn ), b = ts_node_end_byte( nn );
        return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
    };
    if( std::strcmp( lt, "identifier" ) == 0 )
    {
        return finalSegment( text( last ) );
    }
    if( std::strcmp( lt, "member_expression" ) == 0 )
    {
        const TSNode prop = ts_node_child_by_field_name( last, "property", 8 );
        if( !ts_node_is_null( prop ) )
        {
            return finalSegment( text( prop ) );
        }
    }
    return {};   // arrow_function / function_expression / anything else → inline, no name
}

// Flask `methods=[...]` keyword argument: a single-method list resolves to that verb; absent/empty/multi
// ⇒ the caller applies its own default (Flask defaults to GET when `methods=` is absent entirely).
// shared tail of every keyword-argument / options-object method extractor below: a "string" node's
// unquoted, lowercased text, resolved through model.h::kHttpMethodTable. Unknown for anything that isn't
// a plain string literal (never guess).
inline HttpMethod stringNodeToMethod( TSNode strNode, std::string_view src )
{
    if( ts_node_is_null( strNode ) || std::strcmp( ts_node_type( strNode ), "string" ) != 0 )
    {
        return HttpMethod::Unknown;
    }
    const std::uint32_t a = ts_node_start_byte( strNode ), b = ts_node_end_byte( strNode );
    if( a > b || b > src.size() )
    {
        return HttpMethod::Unknown;
    }
    std::string verb = ffiUnquote( src.substr( a, b - a ) );
    for( char& ch : verb )
    {
        ch = char( std::tolower( static_cast<unsigned char>( ch ) ) );
    }
    return httpMethodFromName( verb );
}

inline HttpMethod pyMethodsKeyword( TSNode argsNode, std::string_view src, bool& hasKeyword )
{
    hasKeyword = false;
    if( ts_node_is_null( argsNode ) )
    {
        return HttpMethod::Unknown;
    }
    const std::uint32_t nc = ts_node_named_child_count( argsNode );
    for( std::uint32_t i = 0; i < nc; ++i )
    {
        const TSNode c = ts_node_named_child( argsNode, i );
        if( std::strcmp( ts_node_type( c ), "keyword_argument" ) != 0 )
        {
            continue;
        }
        const TSNode nameN = ts_node_child_by_field_name( c, "name", 4 );
        if( ts_node_is_null( nameN ) )
        {
            continue;
        }
        const std::uint32_t na = ts_node_start_byte( nameN ), nb = ts_node_end_byte( nameN );
        if( na > nb || nb > src.size() || src.substr( na, nb - na ) != "methods" )
        {
            continue;
        }
        hasKeyword = true;
        const TSNode valueN = ts_node_child_by_field_name( c, "value", 5 );
        if( ts_node_is_null( valueN ) || std::strcmp( ts_node_type( valueN ), "list" ) != 0 )
        {
            return HttpMethod::Unknown;
        }
        if( ts_node_named_child_count( valueN ) != 1 )
        {
            return HttpMethod::Unknown; // 0 or >1 verbs → ambiguous, path-only match
        }
        return stringNodeToMethod( ts_node_named_child( valueN, 0 ), src );
    }
    return HttpMethod::Unknown;
}

// JS options-object `{ method: 'POST', ... }`: the `method` property's string-literal value, else Unknown
// (never guess — an absent/non-literal method key leaves the USE's method Unknown, which matches ANY DEF
// method per routematch::methodsCompatible in graph.h).
inline HttpMethod jsMethodProperty( TSNode objNode, std::string_view src )
{
    if( ts_node_is_null( objNode ) || std::strcmp( ts_node_type( objNode ), "object" ) != 0 )
    {
        return HttpMethod::Unknown;
    }
    const std::uint32_t nc = ts_node_named_child_count( objNode );
    for( std::uint32_t i = 0; i < nc; ++i )
    {
        const TSNode c = ts_node_named_child( objNode, i );
        if( std::strcmp( ts_node_type( c ), "pair" ) != 0 )
        {
            continue;
        }
        const TSNode keyN = ts_node_child_by_field_name( c, "key", 3 );
        if( ts_node_is_null( keyN ) )
        {
            continue;
        }
        const char* kt = ts_node_type( keyN );
        const std::uint32_t ka = ts_node_start_byte( keyN ), kb = ts_node_end_byte( keyN );
        if( ka > kb || kb > src.size() )
        {
            continue;
        }
        std::string key;
        if( std::strcmp( kt, "property_identifier" ) == 0 )
        {
            key = std::string( src.substr( ka, kb - ka ) );
        }
        else if( std::strcmp( kt, "string" ) == 0 )
        {
            key = ffiUnquote( src.substr( ka, kb - ka ) );
        }
        else
        {
            continue;
        }
        if( key != "method" )
        {
            continue;
        }
        return stringNodeToMethod( ts_node_child_by_field_name( c, "value", 5 ), src );
    }
    return HttpMethod::Unknown;
}

// One visitor on the shared pre-order stream (streamSideCaptures below). The pass arms only on Python/JS/TS;
// the SERVER detectors stay gated on a file-level framework signal, so a framework-free file still captures
// no route DEF and the whole feature stays byte-inert on a framework-free corpus.
struct RouteCtx
{
    std::uint32_t              fileId = 0;
    std::string_view           src;
    std::vector<RouteDef>*     routeDefs = nullptr;
    std::vector<RawRouteUse>*  routeUses = nullptr;
    bool                       py = false;
    bool                       js = false;
    bool                       pyServerGated = false;
    bool                       jsServerGated = false;
};

RouteCtx makeRouteCtx( std::uint32_t fileId, Lang lang, std::string_view src,
                       std::vector<RouteDef>& routeDefs, std::vector<RawRouteUse>& routeUses )
{
    RouteCtx cx;
    cx.fileId        = fileId;
    cx.src           = src;
    cx.routeDefs     = &routeDefs;
    cx.routeUses     = &routeUses;
    cx.py            = ( lang == Lang::Python );
    cx.js            = ( lang == Lang::TypeScript || lang == Lang::JavaScript );
    cx.pyServerGated = cx.py && ( src.find( "fastapi" ) != std::string_view::npos || src.find( "FastAPI" ) != std::string_view::npos
                                || src.find( "flask" )   != std::string_view::npos || src.find( "Flask" )   != std::string_view::npos );
    cx.jsServerGated = cx.js && ( src.find( "express" ) != std::string_view::npos || src.find( "fastify" ) != std::string_view::npos );
    return cx;
}

void routesVisitNode( RouteCtx& cx, TSNode n, const char* t )
{
    FUSEPROBE_BUMP( kRoutes );
    const std::uint32_t        fileId        = cx.fileId;
    const std::string_view     src           = cx.src;
    std::vector<RouteDef>&     routeDefs     = *cx.routeDefs;
    std::vector<RawRouteUse>&  routeUses     = *cx.routeUses;
    const bool                 py            = cx.py;
    const bool                 js            = cx.js;
    const bool                 pyServerGated = cx.pyServerGated;
    const bool                 jsServerGated = cx.jsServerGated;

    const auto nodeSrc = [ & ]( TSNode nn ) noexcept -> std::string_view { return nodeTextOf( nn, src ); };

        // Python server: @app.get("/path") / @app.route("/path", methods=[...]) directly above a def.
        if( pyServerGated && std::strcmp( t, "decorated_definition" ) == 0 )
        {
            const TSNode defNode = ts_node_child_by_field_name( n, "definition", 10 );
            std::string  handlerName;
            if( !ts_node_is_null( defNode ) && std::strcmp( ts_node_type( defNode ), "function_definition" ) == 0 )
            {
                const TSNode nameNode = ts_node_child_by_field_name( defNode, "name", 4 );
                if( !ts_node_is_null( nameNode ) )
                {
                    handlerName.assign( nodeSrc( nameNode ) );
                }
            }
            const std::uint32_t cc = ts_node_child_count( n );
            for( std::uint32_t i = 0; i < cc; ++i )
            {
                const TSNode dec = ts_node_child( n, i );
                if( std::strcmp( ts_node_type( dec ), "decorator" ) != 0 )
                {
                    continue;
                }
                const TSNode expr = ts_node_named_child( dec, 0 );
                if( ts_node_is_null( expr ) || std::strcmp( ts_node_type( expr ), "call" ) != 0 )
                {
                    continue;
                }
                const TSNode fn = ts_node_child_by_field_name( expr, "function", 8 );
                if( ts_node_is_null( fn ) || std::strcmp( ts_node_type( fn ), "attribute" ) != 0 )
                {
                    continue;
                }
                const std::string_view attrName = nodeSrc( ts_node_child_by_field_name( fn, "attribute", 9 ) );
                const TSNode argsNode = ts_node_child_by_field_name( expr, "arguments", 9 );
                const std::string path = firstPathStringArg( argsNode, src );
                if( path.empty() )
                {
                    continue;
                }

                HttpMethod method = HttpMethod::Unknown;
                if( attrName == "route" )
                {
                    bool hasKeyword = false;
                    const HttpMethod fromKeyword = pyMethodsKeyword( argsNode, src, hasKeyword );
                    method = hasKeyword ? fromKeyword : HttpMethod::Get;   // Flask default: GET when methods= absent
                }
                else
                {
                    method = httpMethodFromName( attrName );
                    if( method == HttpMethod::Unknown )
                    {
                        continue; // not a recognized verb shortcut (e.g. .on_event)
                    }
                }
                routeDefs.push_back( RouteDef{ fileId, ts_node_start_point( n ).row + 1, method, path, handlerName } );
            }
        }
        // JS/TS: ONE dispatch over every call_expression — client shapes (`fetch`, `axios.<verb>`) are
        // checked FIRST and UNCONDITIONALLY (their callee shape is specific enough to need no file gate),
        // so a server-gated file's axios/fetch calls are NEVER misread as a route DEF; app.get(...)/
        // router.post(...) is the gated FALLBACK, tried only when neither client shape matched. This also
        // fixes the structural trap an `if/else if` split on `jsServerGated` vs `js` would fall into: once
        // the (possibly file-gated) branch claims a call_expression, an else-if chain never lets the OTHER
        // shape see that same node.
        else if( js && std::strcmp( t, "call_expression" ) == 0 )
        {
            const TSNode fn = ts_node_child_by_field_name( n, "function", 8 );
            bool handled = false;

            if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "identifier" ) == 0 && nodeSrc( fn ) == "fetch" )
            {
                const TSNode argsNode = ts_node_child_by_field_name( n, "arguments", 9 );
                const std::string path = firstPathStringArg( argsNode, src );
                if( !path.empty() )
                {
                    HttpMethod method = HttpMethod::Get;   // fetch's documented default when no options object
                    if( ts_node_named_child_count( argsNode ) >= 2 )
                    {
                        method = jsMethodProperty( ts_node_named_child( argsNode, 1 ), src );
                    }
                    routeUses.push_back( RawRouteUse{ fileId, ts_node_start_byte( n ), ts_node_start_point( n ).row + 1, method, path } );
                }
                handled = true;   // "fetch(...)" is never ALSO a server registrar shape
            }
            else if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "member_expression" ) == 0 )
            {
                const TSNode objN = ts_node_child_by_field_name( fn, "object", 6 );
                if( !ts_node_is_null( objN ) && std::strcmp( ts_node_type( objN ), "identifier" ) == 0 && nodeSrc( objN ) == "axios" )
                {
                    const TSNode propN     = ts_node_child_by_field_name( fn, "property", 8 );
                    const HttpMethod method = httpMethodFromName( nodeSrc( propN ) );
                    if( method != HttpMethod::Unknown )
                    {
                        const TSNode argsNode = ts_node_child_by_field_name( n, "arguments", 9 );
                        const std::string path = firstPathStringArg( argsNode, src );
                        if( !path.empty() )
                        {
                            routeUses.push_back( RawRouteUse{ fileId, ts_node_start_byte( n ), ts_node_start_point( n ).row + 1, method, path } );
                        }
                    }
                    handled = true;   // "axios.<verb>(...)" is never ALSO a server registrar shape
                }
            }

            // JS/TS server FALLBACK: app.get('/path', handler) / router.post('/path', mw, handler) — last
            // arg = handler. Only tried when the callee wasn't already claimed by a client shape above, and
            // only on a file-level framework signal (captureFfi's pybind-gate posture).
            if( !handled && jsServerGated && !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "member_expression" ) == 0 )
            {
                const TSNode propN     = ts_node_child_by_field_name( fn, "property", 8 );
                const HttpMethod method = httpMethodFromName( nodeSrc( propN ) );
                if( method != HttpMethod::Unknown )
                {
                    const TSNode argsNode = ts_node_child_by_field_name( n, "arguments", 9 );
                    const std::string path = firstPathStringArg( argsNode, src );
                    if( !path.empty() )
                    {
                        const std::string handlerName = lastArgHandlerName( argsNode, src );
                        routeDefs.push_back( RouteDef{ fileId, ts_node_start_point( n ).row + 1, method, path, handlerName } );
                    }
                }
            }
        }
        // Python client: requests.get('/path') / requests.post('/path', json=...)
        else if( py && std::strcmp( t, "call" ) == 0 )
        {
            const TSNode fn = ts_node_child_by_field_name( n, "function", 8 );
            if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "attribute" ) == 0 )
            {
                const TSNode objN = ts_node_child_by_field_name( fn, "object", 6 );
                if( !ts_node_is_null( objN ) && std::strcmp( ts_node_type( objN ), "identifier" ) == 0 && nodeSrc( objN ) == "requests" )
                {
                    const TSNode attrN     = ts_node_child_by_field_name( fn, "attribute", 9 );
                    const HttpMethod method = httpMethodFromName( nodeSrc( attrN ) );
                    if( method != HttpMethod::Unknown )
                    {
                        const TSNode argsNode = ts_node_child_by_field_name( n, "arguments", 9 );
                        const std::string path = firstPathStringArg( argsNode, src );
                        if( !path.empty() )
                        {
                            routeUses.push_back( RawRouteUse{ fileId, ts_node_start_byte( n ), ts_node_start_point( n ).row + 1, method, path } );
                        }
                    }
                }
            }
        }
}

// ── ABS-3 READ / WRITE use-site capture ──────────────────────────────────────────────────────────────
// Walk a subtree and record every IDENTIFIER reference that is a value READ or an assignment WRITE, so the
// use-site index can report read-vs-write per site. The call sites (`f()` / `x.m()`) are already captured
// by the tags query as @reference.call (role=Call); the inheritance/import sites by captureBases/Includes —
// so this walk deliberately EXCLUDES those to avoid double-counting:
//   * the function-position identifier of a call (`foo` in `foo()`, `m` in `x.m()`) → already a Call ref.
//   * a definition's own name / declarator (`x` in `int x;`, `f` in `void f(){}`) → a DEF, not a use.
//   * type positions (`Foo` in `Foo x;`) → captured as inherit/compose where relevant, not a value use.
// WRITE classification (the precision-critical half): an identifier is a Write iff it is the LHS target of
//   an assignment_expression / augmented assignment (C++ `=` `+=` … are all assignment_expression; Python
//   `assignment` / `augmented_assignment`) OR the operand of a `++`/`--` (`update_expression`). Everything
//   else that references a name in a value position is a Read. Pure-syntactic, deterministic.

// two AST nodes refer to the SAME source token iff they span the identical [start,end) byte range. Used to
// test "is THIS identifier the node sitting in field X of its parent" without depending on ts_node_eq.
inline bool sameSpan( TSNode a, TSNode b ) noexcept
{
    return ts_node_start_byte( a ) == ts_node_start_byte( b ) && ts_node_end_byte( a ) == ts_node_end_byte( b );
}

// does `outer`'s [start,end) byte range contain ALL of `inner`? Used by the tags-pass body-climb to tell a
// def that IS an ancestor's signature (outside its body — adopt the ancestor's span) from a def spelled
// INSIDE that body (a nested JS/TS closure — adopting would broadcast the encloser's span onto it).
inline bool spanContains( TSNode outer, TSNode inner ) noexcept
{
    return ts_node_start_byte( inner ) >= ts_node_start_byte( outer ) && ts_node_end_byte( inner ) <= ts_node_end_byte( outer );
}

// is `id` the LHS write-target of its enclosing assignment/update? A4-F24: implements the documented contract
// — `a[i] = …` / `p->f = …` make the BASE OBJECT (`a`, `p`) the target, while the index `i` / member `f` stay
// reads. We climb through subscript/field chains while `id` is the base object (the leading sub-expression
// that shares its parent's start byte — the base always begins at the whole `a[i]`/`p->f` expression's first
// byte; the index/member begin later), then test the assignment/update parent of the climbed node.
inline bool isWriteTarget( TSNode id ) noexcept
{
    TSNode node = id;
    for( TSNode up = ts_node_parent( node ); !ts_node_is_null( up ); up = ts_node_parent( node ) )
    {
        const char* ut = ts_node_type( up );
        const bool isSubscriptOrField =    std::strcmp( ut, "subscript_expression" ) == 0   // C/C++ `a[i]`
                                        || std::strcmp( ut, "field_expression" ) == 0        // C/C++ `p->f`, `a.b`
                                        || std::strcmp( ut, "subscript" ) == 0               // Python `a[i]`
                                        || std::strcmp( ut, "attribute" ) == 0;              // Python `a.b`
        if( !( isSubscriptOrField && ts_node_start_byte( up ) == ts_node_start_byte( node ) ) )
        {
            break;                              // `id` is the index/member, or the chain ended → stop climbing
        }
        node = up;                              // `id` is the base object → it inherits the whole a[i]/p->f target-ness
    }

    const TSNode parent = ts_node_parent( node );
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const char* pt = ts_node_type( parent );

    // C++ `x++` / `--x` and Python aug targets handled via update_expression (the operand is the target).
    if( std::strcmp( pt, "update_expression" ) == 0 )
    {
        return true;
    }

    // direct LHS of an assignment: parent is the assignment node and `node` sits in its `left` field.
    const bool isAssign =    std::strcmp( pt, "assignment_expression" ) == 0       // C++ `=` `+=` `-=` …
                          || std::strcmp( pt, "assignment" ) == 0                  // Python `=`
                          || std::strcmp( pt, "augmented_assignment" ) == 0;       // Python `+=` …
    if( isAssign )
    {
        const TSNode lhs = ts_node_child_by_field_name( parent, "left", 4 );
        return !ts_node_is_null( lhs ) && sameSpan( lhs, node );
    }
    return false;
}

// is `id` the callee/function-position name of a call (already captured as a Call ref by the tags query)?
inline bool isCallCallee( TSNode id ) noexcept
{
    const TSNode parent = ts_node_parent( id );
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const char* pt = ts_node_type( parent );

    // bare call `foo()` — the function field is the identifier itself.
    if( std::strcmp( pt, "call_expression" ) == 0 || std::strcmp( pt, "call" ) == 0 )
    {
        const TSNode fn = ts_node_child_by_field_name( parent, "function", 8 );
        return !ts_node_is_null( fn ) && sameSpan( fn, id );
    }
    // member call `x.m()` / `x->m()` — `id` is the field of a field_expression/attribute that is the
    // function of a call. (The receiver `x` is NOT the callee → still captured as a read below.)
    if( std::strcmp( pt, "field_expression" ) == 0 || std::strcmp( pt, "attribute" ) == 0 )
    {
        const TSNode fieldNode = ts_node_child_by_field_name( parent, "field", 5 );
        const TSNode attrNode  = ts_node_child_by_field_name( parent, "attribute", 9 );
        const bool   isField   = ( !ts_node_is_null( fieldNode ) && sameSpan( fieldNode, id ) )
                              || ( !ts_node_is_null( attrNode )  && sameSpan( attrNode,  id ) );
        if( !isField )
        {
            return false;
        }
        const TSNode gp = ts_node_parent( parent );   // the field-access is the callee only when its parent is a call whose `function` is it
        if( ts_node_is_null( gp ) )
        {
            return false;
        }
        const char* gt = ts_node_type( gp );
        if( std::strcmp( gt, "call_expression" ) != 0 && std::strcmp( gt, "call" ) != 0 )
        {
            return false;
        }
        const TSNode fn = ts_node_child_by_field_name( gp, "function", 8 );
        return !ts_node_is_null( fn ) && sameSpan( fn, parent );
    }
    return false;
}

// A5 shadow fix round: is `id` a DECLARATION-SITE name isNonValueContext's single-`declarator`-field probe
// (arm 2) cannot see? Pre-fix each of these leaked the DECLARED name out as a role="read" site of its own
// declaration (`int& key` param/local, `auto& [key, w]`, `for (int key : arr)`, `[key = expr]`). An
// identifier directly under a reference_declarator or a structured_binding_declarator is ALWAYS a declared
// name (value expressions live under other node types); a range-for's is its `declarator` field; an
// init-capture's is its FIRST named child (the value side of `[a = b]` stays a genuine read of b).
// `variadic_declarator` (`Ts... key`) and `attributed_declarator` (`int key [[maybe_unused]]`) join the
// unconditional arm for the same grammar reason: each holds its inner declarator as an UNNAMED child, so
// arm 2's `declarator`-field probe returns null and sees nothing. Their only bare-identifier child is the
// declared name — a pack's attributes are `attribute_declaration` nodes, never loose identifiers.
// NOT fixable here, and deliberately left listed: `int (key);` — the most-vexing parse, which tree-sitter
// resolves to an `argument_list`, the same node every genuine call ARGUMENT lives under. Suppressing that
// parent would delete real reads corpus-wide to chase a shape that is vanishingly rare in real source.
// Iteration 4 adds the shape arm 2 looks straight at and still misses: a `declaration` carries one
// `declarator` FIELD PER DECLARED NAME, so ts_node_child_by_field_name — which returns the FIRST — sees
// `a` in `int a, key;` and never `key`; a bare `int key;` it misses outright, the parent type not being in
// arm 2's list at all. Iterations 1-3 could not observe either, because the block-start span suppressed the
// declaration line along with the rest of the block; declaration-point spans stop covering it.
inline bool isDeclSiteName( TSNode id, TSNode parent, const char* pt ) noexcept
{
    if( std::strcmp( pt, "reference_declarator" ) == 0 || std::strcmp( pt, "structured_binding_declarator" ) == 0
        || std::strcmp( pt, "variadic_declarator" ) == 0 || std::strcmp( pt, "attributed_declarator" ) == 0 )
    {
        return true;
    }
    if( std::strcmp( pt, "declaration" ) == 0 )
    {
        const std::uint32_t cc = ts_node_child_count( parent );
        for( std::uint32_t i = 0; i < cc; ++i )
        {
            const char* fieldName = ts_node_field_name_for_child( parent, i );
            if( fieldName != nullptr && std::strcmp( fieldName, "declarator" ) == 0 && sameSpan( ts_node_child( parent, i ), id ) )
            {
                return true;
            }
        }
        return false;
    }
    if( std::strcmp( pt, "for_range_loop" ) == 0 )
    {
        const TSNode decl = ts_node_child_by_field_name( parent, "declarator", 10 );
        return !ts_node_is_null( decl ) && sameSpan( decl, id );
    }
    if( std::strcmp( pt, "lambda_capture_initializer" ) == 0 )
    {
        return ts_node_named_child_count( parent ) > 0 && sameSpan( ts_node_named_child( parent, 0 ), id );
    }
    return false;
}

// is `id` in a NON-VALUE context — a name being DEFINED, DECLARED, or part of a qualified/scoped name —
// so it must NOT be counted as a read/write use-site? (Definition NAMES are captured by the tags query;
// qualified-name segments and declarators are not value uses.) Conservative by construction: when in doubt
// we EXCLUDE rather than mislabel — a missed read is far better than reporting a def's own name as a "read".
inline bool isNonValueContext( TSNode id ) noexcept
{
    const TSNode parent = ts_node_parent( id );
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const char* pt = ts_node_type( parent );

    // (1) part of a qualified / scoped NAME (`A::process` def name, `A::b()` qualified call name, `ns::T`
    //     type, `A::kConst` qualified value): the segment is not a plain value identifier. Calls/defs of
    //     this shape are captured by the tags query; qualified value reads are intentionally out of scope.
    if( std::strcmp( pt, "qualified_identifier" ) == 0 || std::strcmp( pt, "scoped_identifier" ) == 0 || std::strcmp( pt, "scoped_type_identifier" ) == 0 || std::strcmp( pt, "qualified_type_identifier" ) == 0 || std::strcmp( pt, "template_function" ) == 0 || std::strcmp( pt, "template_type" ) == 0 )
    {
        return true;
    }

    // (2) a declarator's NAME (a DEF/declaration, not a use): `int x;`, `void f()`, `Foo* p`, parameters.
    // `optional_parameter_declaration` is `parameter_declaration`'s DEFAULTED sibling (`int x = 0`) and
    // carries the same `declarator` field — probing the field, not the node type, is what keeps a default
    // VALUE that names a symbol (`int v = probe()`, a different field) a genuine use.
    if(    std::strcmp( pt, "function_declarator" ) == 0 || std::strcmp( pt, "init_declarator" ) == 0
        || std::strcmp( pt, "parameter_declaration" ) == 0 || std::strcmp( pt, "pointer_declarator" ) == 0
        || std::strcmp( pt, "reference_declarator" ) == 0  || std::strcmp( pt, "array_declarator" ) == 0
        || std::strcmp( pt, "optional_parameter_declaration" ) == 0 )
    {
        const TSNode decl = ts_node_child_by_field_name( parent, "declarator", 10 );
        if( !ts_node_is_null( decl ) && sameSpan( decl, id ) )
        {
            return true;
        }
    }
    // (2b) A5 shadow fix round: declaration-site names the field probe above cannot see (isDeclSiteName).
    if( isDeclSiteName( id, parent, pt ) )
    {
        return true;
    }
    // (3) Python function / parameter NAME field (a DEF/param, not a use).
    if( std::strcmp( pt, "function_definition" ) == 0 || std::strcmp( pt, "parameters" ) == 0
        || std::strcmp( pt, "typed_parameter" ) == 0 || std::strcmp( pt, "default_parameter" ) == 0
        || std::strcmp( pt, "lambda_parameters" ) == 0 )
    {
        const TSNode nm = ts_node_child_by_field_name( parent, "name", 4 );
        if( ( !ts_node_is_null( nm ) && sameSpan( nm, id ) ) || std::strcmp( pt, "parameters" ) == 0 || std::strcmp( pt, "lambda_parameters" ) == 0 )
        {
            return true;   // every direct child of a parameter list is a param NAME, not a use
        }
    }
    return false;
}

// One visitor on the shared pre-order stream (streamSideCaptures below). It keeps its OWN 512-node depth
// cap — twice the other passes' — which the shared stream honours per visitor: past 256 the FFI/route/bind
// visitors stop being called while this one keeps receiving nodes, exactly as their separate walks behaved.
struct UseCtx
{
    std::uint32_t        fileId = 0;
    Lang                 lang {};
    std::string_view     src;
    std::vector<RawRef>* refs = nullptr;
};

// A bare TYPE-MENTION node — the RefRole::Type accept set. DELIBERATELY NARROWER than isBaseTypeNode
// above, which was written for base clauses and is a superset that would misfire here:
//   * `identifier` is in that table for TS/Python base clauses; here it is already the VALUE path below,
//     and accepting it twice would re-label every ordinary read as a type.
//   * `qualified_identifier` / `scoped_type_identifier` / `generic_type` / `generic_name` /
//     `qualified_name` are CONTAINERS whose own name segment is a `type_identifier` child. Accepting the
//     container as well would emit two refs for one mention, and `qualified_name` in particular is C#'s
//     dotted-value node — a value read wearing a type node's name.
// So: the leaf node that actually spells a type, and nothing else. `std::vector<Widget>` yields exactly
// one Type ref (`Widget`); `vector` is skipped by isNonValueContext's qualified-segment rule, the same
// rule that already keeps a qualified VALUE read out of the index. The value-uses pass is armed for
// C++/ObjC/Python only (see streamSideCaptures' arming), and Python spells its annotations with plain
// `identifier`, so `user_type` (Swift) / `type_identifier` (Rust, Java, TS) are unreachable today and are
// NOT listed — a kind in this table that no armed language can produce is a claim the gate cannot check.
inline bool isTypeMentionNode( const char* nt ) noexcept
{
    static const char* const kTypeMentionKinds[] = {
        "type_identifier",   // C/C++/ObjC — the leaf node that names a class, struct, enum or typedef
    };
    for( const char* k : kTypeMentionKinds )
    {
        if( std::strcmp( nt, k ) == 0 )
        {
            return true;
        }
    }
    return false;
}

// A type-name node that is NOT a mention of some other definition. Three shapes, and each would be a
// distinct kind of lie in the use-site index:
//   (a) the NAME of a type DEFINITION (`struct Widget {…}`, `enum class E : int`, `using A = B;`,
//       `typedef struct X Y;`) — a definition is not a use of itself, and emitting one would give every
//       indexed type a permanent self-reference and inflate every blast radius by exactly one row.
//   (b) a BASE CLAUSE — that position already has its own role (RefRole::Extends, emitted by
//       captureBases), so a second row would double-count the one relation the tool already models.
//   (c) a TYPE PARAMETER's own name (`template< typename T >`) — T is being declared here, not named.
inline bool isTypeDeclarationSite( TSNode id ) noexcept
{
    const TSNode parent = ts_node_parent( id );
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const char* pt = ts_node_type( parent );

    // (b) base clause — RefRole::Extends owns this position.
    if( std::strcmp( pt, "base_class_clause" ) == 0 )
    {
        return true;
    }

    // (c) a type parameter DECLARES its name.
    if(    std::strcmp( pt, "type_parameter_declaration" ) == 0 || std::strcmp( pt, "variadic_type_parameter_declaration" ) == 0
        || std::strcmp( pt, "optional_type_parameter_declaration" ) == 0 )
    {
        return true;
    }

    // (a) the `name` field of a type definition — probe the FIELD, not the node type, so a base name or a
    // member type sitting under the same parent kind stays a genuine mention.
    static const char* const kTypeDefParents[] = {
        "struct_specifier", "class_specifier", "union_specifier", "enum_specifier", "alias_declaration", "concept_definition",
    };
    for( const char* k : kTypeDefParents )
    {
        if( std::strcmp( pt, k ) == 0 )
        {
            const TSNode nm = ts_node_child_by_field_name( parent, "name", 4 );
            if( !ts_node_is_null( nm ) && sameSpan( nm, id ) )
            {
                return true;
            }
        }
    }
    // `typedef struct X Y;` — Y is the DECLARATOR field and is the new name; X keeps its mention.
    if( std::strcmp( pt, "type_definition" ) == 0 )
    {
        const TSNode dc = ts_node_child_by_field_name( parent, "declarator", 10 );
        if( !ts_node_is_null( dc ) && sameSpan( dc, id ) )
        {
            return true;
        }
    }
    return false;
}

void usesVisitNode( UseCtx& cx, TSNode n, const char* t )
{
    FUSEPROBE_BUMP( kUses );
    // Two accept sets, one visitor. (1) bare value identifiers (C++ `identifier`, Python `identifier`) →
    // role=Read/Write, unchanged. field_identifier reads (`obj.field` non-call) are still intentionally out
    // of scope — member-field use is a richer relation we keep for a later pass. (2) bare TYPE mentions
    // (`type_identifier`) → role=Type: a type named in a signature, a declaration or a template argument IS
    // a dependency on that type, and it was captured by NOTHING before this. Both roles stay OUT of the call
    // graph (buildGraph admits Call and Macro only), so the default ranked map is byte-identical either way.
    const bool typeMention = isTypeMentionNode( t );
    if( !typeMention && std::strcmp( t, "identifier" ) != 0 )
    {
        return;
    }
    if( isCallCallee( n ) || isNonValueContext( n ) )
    {
        return;
    }
    if( typeMention && isTypeDeclarationSite( n ) )
    {
        return;
    }
    const std::string_view src = cx.src;
    const std::uint32_t    a   = ts_node_start_byte( n ), b = ts_node_end_byte( n );
    if( a < b && b <= src.size() )
    {
        RawRef r;
        r.fileId    = cx.fileId;
        r.startByte = a;
        r.line      = ts_node_start_point( n ).row + 1;
        r.lang      = cx.lang;
        r.role      = typeMention ? RefRole::Type : ( isWriteTarget( n ) ? RefRole::Write : RefRole::Read );
        r.name      = finalSegment( src.substr( a, b - a ) );   // bare identifier → already final segment
        cx.refs->push_back( std::move( r ) );
    }
}

bool prepareParserFor( TSParser* parser, const LangEntry& le )
{
    const TSLanguage* lang = le.grammar();
    if( lang == nullptr )
    {
        return false;
    }

    if( !ts_parser_set_language( parser, lang ) || !grammarAbiOk( lang ) )
    {
        // never emit a silently-empty tree — say which language we dropped.
        std::fprintf( stderr, "[ripwire] grammar ABI mismatch or set_language failed for %s — skipping language\n",
                      std::string( le.querySub ).c_str() );
        return false;
    }
    return true;
}

TSTree* parseTree( TSParser* parser, std::string_view src )
{
    TSTree* tree = nullptr;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: tree-sitter parse" );
        tree = ts_parser_parse_string( parser, nullptr, src.data(), static_cast<uint32_t>( src.size() ) );
    }
    return tree;
}

struct TreeGuard
{
    TSTree* tree = nullptr;

    explicit TreeGuard( TSTree* treeIn = nullptr ) noexcept : tree( treeIn ) {}
    TreeGuard( const TreeGuard& ) = delete;
    TreeGuard& operator=( const TreeGuard& ) = delete;
    TreeGuard( TreeGuard&& other ) noexcept : tree( other.tree ) { other.tree = nullptr; }
    TreeGuard& operator=( TreeGuard&& other ) noexcept
    {
        if( this != &other )
        {
            if( tree != nullptr )
            {
                ts_tree_delete( tree );
            }
            tree = other.tree;
            other.tree = nullptr;
        }
        return *this;
    }
    ~TreeGuard()
    {
        if( tree != nullptr )
        {
            ts_tree_delete( tree );
        }
    }
    TSTree* get() const noexcept { return tree; }
    TSTree* release() noexcept
    {
        TSTree* out = tree;
        tree = nullptr;
        return out;
    }
};

// ── ONE pre-order stream for every whole-AST side-capture pass ────────────────────────────────────────
// FFI, routes, Rust impls, bindings and value-uses each used to run their OWN iterative pre-order walk of
// the same tree, back to back. Measured with a per-pass node-pop probe on a 1659-file ObjC++/C++ corpus:
// 95.0% of files ran captureFfi AND captureBindings, 93.4% ran three passes, and every node was streamed
// 2.01x on a default run / 3.01x with --uses armed. That re-streaming — not the per-node matching, which
// is a strcmp or two — is why the `side captures` profile scope showed ~2x tree-sitter's L1D MPKI and ~2x
// its LLC misses on half the instructions. The passes now share one stream; the per-node work is unchanged.
//
// ENTRY RULES. This is the union of what the fused passes need, and it is exactly "every node", because
// FFI / bindings / value-uses each already descended unconditionally. captureIncludes is deliberately NOT
// fused: it enters only ALLOWLISTED import containers (isImportContainer) and cost 59 node pops per file
// against ~7,800 for a full walk — 0.4% of all pops. Folding it in would either make it visit ~130x more
// nodes or force a per-frame "still inside an allowlisted chain" bit, and its restricted entry set is what
// DEFINES which directives it captures. It keeps its own walk.
//
// DEPTH. Each pass's own pathological-AST cap survives as a per-visitor `maxDepth`: past its cap a visitor
// simply stops being called while the others keep descending — which is what that pass's own `continue`
// did (it skipped the node AND its subtree, and depth only grows). The stream descends while ANY armed
// visitor still wants nodes, so the heap stack's high-water mark is max(caps) — 512 with --uses armed,
// exactly what captureUses' own walk already reached, and 256 otherwise. No frame got fatter either: the
// fused frame is one TSNode + one depth, the same shape (and the same 40 bytes) as each pass's old frame.
//
// EMISSION ORDER. Every fused pass appends to its OWN output vector, so within a vector the order is that
// pass's own node order — byte-identical to running the passes back to back. `refs` is the one vector two
// fused passes could share (Rust impls and value-uses), and they are disjoint by language (Rust vs
// C++/ObjC/Python), so at most one is ever armed; sideArmsAreOrderSafe pins that invariant. Visitors are
// still invoked in the ORIGINAL pass order at each node, so the reading order matches the old call order.
// depth is 32-bit, not the 16-bit each pass used to carry: same 40 bytes after padding either way, and a
// tree deeper than 65535 can no longer WRAP the counter back under a cap and re-enable a visitor that
// should have stopped. Unreachable on a <= 1 MB file, but the old shape was the fragile one.
struct SideFrame
{
    TSNode        node;
    std::uint32_t depth;
};
static_assert( sizeof( SideFrame ) == sizeof( TSNode ) + 8, "the fused frame must not outgrow one node + a depth" );

constexpr std::uint32_t kSideDepthStd       = 256;           // FFI / routes / bindings — their own guard
constexpr std::uint32_t kSideDepthUses      = 512;           // value-uses — twice the others, as it always was
constexpr std::uint32_t kSideDepthUnbounded = 0xFFFFFFFFu;   // Rust impls — that pass never had a cap

// The armed set for one file. A pass whose context pointer is null is not armed and costs one predictable
// branch per node; that is what keeps a file-level gate from turning into an always-on walk.
struct SideArms
{
    FfiCtx*      ffi   = nullptr;
    RouteCtx*    route = nullptr;
    RustImplCtx* rust  = nullptr;
    BindCtx*     bind  = nullptr;
    UseCtx*      uses  = nullptr;
};

// see EMISSION ORDER above: the two passes that write `refs` must never be armed together.
inline bool sideArmsAreOrderSafe( const SideArms& arms ) noexcept
{
    return arms.rust == nullptr || arms.uses == nullptr;
}

void streamSideCaptures( TSNode root, const SideArms& arms )
{
    VERIFY( sideArmsAreOrderSafe( arms ) );

    std::uint32_t deepest = 0;
    if( arms.ffi   != nullptr ) { deepest = std::max( deepest, kSideDepthStd ); }
    if( arms.route != nullptr ) { deepest = std::max( deepest, kSideDepthStd ); }
    if( arms.bind  != nullptr ) { deepest = std::max( deepest, kSideDepthStd ); }
    if( arms.uses  != nullptr ) { deepest = std::max( deepest, kSideDepthUses ); }
    if( arms.rust  != nullptr ) { deepest = kSideDepthUnbounded; }
    if( deepest == 0 )
    {
        return;   // nothing armed — do not touch the tree at all
    }

    // Iterative, never recursive: worker threads get 512 KB stacks on macOS and a deep AST overflows the
    // call stack well inside any depth guard. Children are pushed in REVERSE so pops preserve left-to-right
    // source order — the determinism contract is byte-identity, and an order that depended on the walk
    // shape would break it.
    std::vector<SideFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { root, 0 } );
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );

    while( !stack.empty() )
    {
        const SideFrame frame = stack.back();
        stack.pop_back();
        FUSEPROBE_POP();
        if( frame.depth > deepest )
        {
            continue;   // past every armed visitor's cap — this subtree is nobody's business
        }
        const TSNode n = frame.node;
        const char*  t = ts_node_type( n );

        // original pass order: FFI, routes, Rust impls, bindings, value-uses.
        if( arms.ffi   != nullptr && frame.depth <= kSideDepthStd )  { ffiVisitNode   ( *arms.ffi,   n, t ); }
        if( arms.route != nullptr && frame.depth <= kSideDepthStd )  { routesVisitNode( *arms.route, n, t ); }
        if( arms.rust  != nullptr )                                  { rustImplVisitNode( *arms.rust, n, t ); }
        if( arms.bind  != nullptr && frame.depth <= kSideDepthStd )  { bindsVisitNode ( *arms.bind,  n, t ); }
        if( arms.uses  != nullptr && frame.depth <= kSideDepthUses ) { usesVisitNode  ( *arms.uses,  n, t ); }

        collectChildren( n, cursor.cur, kids );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], frame.depth + 1 } );
        }
    }
}

void captureSideFacts( const LangEntry& le, std::uint32_t fileId, std::string_view src, TSNode root,
                       std::vector<RawRef>& refs, std::vector<Include>& incs, std::vector<RawBind>& binds,
                       std::vector<BindingAlias>& ffis, std::vector<RouteDef>& routeDefs,
                       std::vector<RawRouteUse>& routeUses, bool captureValueUses )
{
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: side captures" );

#ifdef RIPWIRE_FUSE_PROBE
        std::uint64_t probeBefore[ fuseprobe::kPassCount ];
        for( int p = 0; p < fuseprobe::kPassCount; ++p )
        {
            probeBefore[ p ] = fuseprobe::tlNodes[ p ];
        }
#endif

        captureIncludes( root, le.lang, fileId, src, incs, refs );   // physical deps + ABS-3 import-role use-sites

        // A4-R5: cross-language FFI binding declarations (pybind11 / extern "C" / ctypes handle). Inert on a
        // binding-free file (pybind gated on a file signal; extern-C/ctypes only fire on their exact shapes).
        FfiCtx   ffiCtx   = makeFfiCtx( fileId, le.lang, src, ffis );

        // B6.3: HTTP-route DEF/USE facts (Express/Fastify · FastAPI/Flask · fetch/axios/requests). Server
        // detectors gated on a file-level framework signal; inert on a framework-free / non-JS/Python file.
        RouteCtx routeCtx = makeRouteCtx( fileId, le.lang, src, routeDefs, routeUses );

        // Rust IS-A: `impl Trait for T` is a top-level impl_item (sibling of the struct), unreachable from the
        // struct's def-walk. Derived type name rides `qualifier` (name-resolved in buildGraph).
        RustImplCtx rustCtx { fileId, src, &refs };

        // P2-D Rule 2: local var→type bindings (`Foo x;`), for receiver-variable narrowing. C++/ObjC/Python/TS
        // (the languages whose receiver shape `receiverOf` captures as a recvVar) — others have no consumer yet.
        // L3 adds Lang::C for the fn-pointer/callback var→function capture only: the Rule-2 branches inside
        // gate themselves on Cpp/ObjC/Python/TS, so type narrowing is byte-identical on C files.
        BindCtx bindCtx;
        bindCtx.fileId    = fileId;
        bindCtx.lang      = le.lang;
        bindCtx.src       = src;
        bindCtx.binds     = &binds;
        bindCtx.cFamilyFn = ( le.lang == Lang::Cpp || le.lang == Lang::C || le.lang == Lang::ObjC );

        // ABS-3: read/write use-site capture (bare value identifiers + assignment targets). C++/ObjC/Python —
        // the languages whose assignment/update grammar shapes isWriteTarget knows. role=Read/Write refs NEVER
        // enter the call graph (buildGraph skips role != Call), so PageRank and the default map are unchanged.
        UseCtx useCtx { fileId, le.lang, src, &refs };

        SideArms arms;
        if( ffiCtx.cish || ffiCtx.py )
        {
            arms.ffi = &ffiCtx;
        }
        if( routeCtx.py || routeCtx.js )
        {
            arms.route = &routeCtx;
        }
        if( le.lang == Lang::Rust )
        {
            arms.rust = &rustCtx;
        }
        if( le.lang == Lang::Cpp || le.lang == Lang::ObjC || le.lang == Lang::Python || le.lang == Lang::TypeScript
            || le.lang == Lang::C )
        {
            arms.bind = &bindCtx;
        }
        if( captureValueUses && ( le.lang == Lang::Cpp || le.lang == Lang::ObjC || le.lang == Lang::Python ) )
        {
            arms.uses = &useCtx;
        }

        streamSideCaptures( root, arms );

        if( arms.bind != nullptr )
        {
            bindsFinalize( bindCtx );   // L3 noise gates + clobber sweep — the tail of the old captureBindings
        }

#ifdef RIPWIRE_FUSE_PROBE
        {
            int           sawNode = 0;
            std::uint64_t maxPass = 0;
            for( int p = 0; p < fuseprobe::kPassCount; ++p )
            {
                const std::uint64_t d = fuseprobe::tlNodes[ p ] - probeBefore[ p ];
                if( d != 0 )
                {
                    ++sawNode;
                    fuseprobe::gFiles[ p ].fetch_add( 1, std::memory_order_relaxed );
                }
                if( d > maxPass )
                {
                    maxPass = d;
                }
                fuseprobe::gNodes[ p ].fetch_add( d, std::memory_order_relaxed );
            }
            fuseprobe::gNodesMaxPass.fetch_add( maxPass, std::memory_order_relaxed );
            fuseprobe::gHist[ sawNode ].fetch_add( 1, std::memory_order_relaxed );
            fuseprobe::gFilesTotal.fetch_add( 1, std::memory_order_relaxed );
        }
#endif
    }
}

void captureTagsFacts( TSQueryCursor* cursor, const LangEntry& le, std::uint32_t fileId, std::string_view src, TSNode root,
                       std::vector<RawDef>& defs, std::vector<RawRef>& refs )
{
    if( cursor == nullptr )
    {
        return;
    }

    TSQuery* query = compiledQueryFor( le );   // shared immutable query, compiled once per grammar (pre-warmed) — do NOT delete
    if( query == nullptr )
    {
        return;
    }

    {
        PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: tags query exec+captures" );
        ts_query_cursor_exec( cursor, query, root );

        TSQueryMatch match;
        while( ts_query_cursor_next_match( cursor, &match ) )
        {
            // A tags pattern yields one @definition/@reference node + a child @name.
            // Walk this match's captures: remember the role node + the name text.
            SymKind          kind     = SymKind::Other;
            bool             isDef    = false;
            bool             isRef    = false;
            std::string_view defCapSv;   // the @definition capture's name — dropGatedCapture keys the constant/cjsexport/protomethod gates on it
            std::string_view refCapSv;   // the @reference capture's name — "reference.import" routes the using-declaration role (r9 loss bucket 1)
            TSNode           roleNode {};
            bool             haveRole = false;
            std::string_view nameTxt;
            uint32_t         nameByte = 0;
            uint32_t         nameRow  = 0;   // 0-based row of the @name identifier
            bool             haveName = false;
            TSNode           nameNode {};    // the @name identifier node — for C++ scope/qualifier (E#4)

            for( uint16_t ci = 0; ci < match.capture_count; ++ci )
            {
                const TSQueryCapture& cap = match.captures[ ci ];

                uint32_t    nameLen = 0;
                const char* capName = ts_query_capture_name_for_id( query, cap.index, &nameLen );
                const std::string_view capSv( capName, nameLen );

                SymKind k = SymKind::Other;
                switch( roleOf( capSv, k ) )
                {
                    case CapRole::Def:
                    {
                        isDef          = true;
                        kind           = k;
                        defCapSv       = capSv;
                        roleNode       = cap.node;
                        haveRole       = true;
                    }
                    break;

                    case CapRole::Ref:
                    {
                        isRef    = true;
                        refCapSv = capSv;
                        roleNode = cap.node;
                        haveRole = true;
                    }
                    break;

                    case CapRole::NameOnly:
                    {
                        const uint32_t a = ts_node_start_byte( cap.node );
                        uint32_t       b = ts_node_end_byte( cap.node );

                        // A C++ conversion operator's declarator is an `operator_cast` node whose text spans
                        // the WHOLE `operator <type>() const` (the tags query captures the declarator itself —
                        // there is no sub-node spanning just `operator bool`). Trim the name's end to the end of
                        // the `type` field so the symbol name is `operator bool` / `operator MyType`, not the
                        // param list. Symbolic ops (operator==/[]/()) go through operator_name and are untouched —
                        // trimming at `(` there would wrongly cut `operator()`, so this is operator_cast-only.
                        if( std::strcmp( ts_node_type( cap.node ), "operator_cast" ) == 0 )
                        {
                            const TSNode typeNode = ts_node_child_by_field_name( cap.node, "type", 4 );
                            if( !ts_node_is_null( typeNode ) )
                            {
                                const uint32_t typeEnd = ts_node_end_byte( typeNode );
                                if( typeEnd > a && typeEnd <= b )
                                {
                                    b = typeEnd;
                                }
                            }
                        }

                        if( b <= src.size() && a <= b )
                        {
                            nameTxt  = src.substr( a, b - a );
                            nameByte = a;
                            nameRow  = ts_node_start_point( cap.node ).row;
                            nameNode = cap.node;
                            haveName = true;
                        }
                    }
                    break;

                    case CapRole::Ignore:
                    break;
                }
            }

            if( !haveName )
            {
                continue;
            }

            // Some patterns (e.g. a bare (identifier) @name) carry no @definition/@reference
            // wrapper. Treat a wrapper-less @name as a reference fallback only when the pattern
            // had a role; otherwise skip (avoids turning every identifier into an edge).
            if( !haveRole )
            {
                continue;
            }

            // C1 (memgraph F1) — see cppDefNameReseat. A null node is "nothing to re-seat".
            const auto [ reNode, reTxt, reByte, reRow ] = cppDefNameReseat( isDef && le.lang == Lang::Cpp, nameNode, src );
            if( !ts_node_is_null( reNode ) )
            {
                nameNode = reNode;  nameTxt = reTxt;  nameByte = reByte;  nameRow = reRow;
            }

            // F5: drop Swift function-local `let`/`var` bindings — they are not module symbols and, left in,
            // they steal the enclosing function's call edges (the last local binding above the call sites
            // becomes the nearest enclosing symbol). roleNode is the `property_declaration`; a `statements`
            // ancestor marks it as local. Real stored/computed members (class/struct/enum/top-level) survive.
            if( isDef && kind == SymKind::Var && le.lang == Lang::Swift && isSwiftLocalBinding( roleNode ) )
            {
                continue;
            }

            // the gated capture classes — r3 q10 constants (plus the §7b CUDA memory-space policy for the
            // uninitialized C++ shape, which needs the captured declaration node), JS export/prototype
            // assignments — in one drop decision (see dropGatedCapture for the per-class rationale and why
            // none of this can live in the query as a #match?/#eq? predicate).
            if( isDef && dropGatedCapture( defCapSv, le.lang, nameTxt, nameNode, roleNode, src ) )
            {
                continue;
            }

            if( isDef )
            {
                RawDef d;
                d.fileId    = fileId;
                d.line      = nameRow + 1;   // the identifier's line — most accurate, dedup-stable
            // The C++ tags query captures @definition on the function_declarator (name+params) — its
            // span excludes the return type AND the body. Walk up to the nearest ancestor owning a
            // "body" field (the real function_definition) so [startByte,endByte) spans the WHOLE def:
            // return type + signature + body. Fixes --expand bodies, --pack-signatures return-types,
            // AND reference enclosing-attribution (a call in a body is now inside its function span).
            // Grammars whose @definition node already owns the body (class/struct/enum) don't climb.
            TSNode defNode = roleNode;
            // defBodyNodeOf = the `body:` field, PLUS the macro-edges round's one addition: a #define's
            // replacement text (`value:` field) is adopted as a macro symbol's body, set before the climb
            // below so the climb is skipped for macros.
            TSNode body    = defBodyNodeOf( roleNode, kind );
            // LB-E testmacroblock: the def is TWO SIBLING nodes (see testMacroBlockPartsOf) — adopt the
            // sibling compound_statement as the body and the title literal as the name BEFORE the shared
            // span/complexity code below. The span's endByte and the loc row window are extended past
            // defNode's own end further down (no single node covers both siblings).
            const bool isTestMacroBlock = ( defCapSv == "definition.testmacroblock" );
            if( isTestMacroBlock )
            {
                const TestMacroBlockParts parts = testMacroBlockPartsOf( roleNode, src );
                if( !parts.ok )
                {
                    continue;   // dropGatedCapture already vetoed non-candidates — guard, don't assert
                }
                body     = parts.body;
                nameNode = parts.title;
                nameTxt  = testMacroTitleOf( parts.title, src );
                nameByte = ts_node_start_byte( parts.title );
                nameRow  = ts_node_start_point( parts.title ).row;
                d.line   = nameRow + 1;   // re-seat: d.line above was filled from the @name capture (the macro identifier)
            }
            // A Var's span is its own declaration — never climb. The climb exists to find a FUNCTION's
            // body; for a var it can only steal a container's span (a Ruby class-level constant's parent
            // chain is body_statement → class, and class owns a "body" field, so the climb would hand the
            // constant THE WHOLE CLASS — the exact Rust-method span bug the H4 W3 note above describes).
            // No-op for every pre-existing Var capture (Swift/C#/Go/Python parents hit a scope-stop or the
            // file root before any "body"-owning ancestor — verified byte-identical on the gate corpora).
            if( ts_node_is_null( body ) && kind != SymKind::Var )
            {
                TSNode child = roleNode;
                TSNode p     = ts_node_parent( roleNode );
                for( int guard = 0; !ts_node_is_null( p ) && guard < 4; ++guard )
                {
                    const char* pt = ts_node_type( p );
                    // STOP at a type/namespace/file scope: a function's body never lives above one of
                    // these, so reaching here means roleNode is a prototype/declaration with no body.
                    // (Without this, an in-class method declaration would climb into class_specifier and
                    // wrongly grab the whole CLASS body as its span — corrupting spans + ref attribution.)
                    const bool scope =    std::strcmp( pt, "class_specifier" ) == 0        || std::strcmp( pt, "struct_specifier" ) == 0
                                       || std::strcmp( pt, "field_declaration_list" ) == 0 || std::strcmp( pt, "declaration_list" ) == 0
                                       || std::strcmp( pt, "namespace_definition" ) == 0   || std::strcmp( pt, "enum_specifier" ) == 0
                                       || std::strcmp( pt, "translation_unit" ) == 0       || std::strcmp( pt, "source_file" ) == 0       // Swift top
                                       || std::strcmp( pt, "class_body" ) == 0             || std::strcmp( pt, "protocol_body" ) == 0     // Swift type bodies
                                       || std::strcmp( pt, "enum_class_body" ) == 0
                                       || std::strcmp( pt, "class_interface" ) == 0        || std::strcmp( pt, "class_implementation" ) == 0   // ObjC
                                       || std::strcmp( pt, "implementation_definition" ) == 0 || std::strcmp( pt, "protocol_declaration" ) == 0
                                       || std::strcmp( pt, "compound_statement" ) == 0     || std::strcmp( pt, "block" ) == 0;   // a function BODY: a block-scope
                    // `Type v(args);` (most-vexing-parse) must not climb up and steal its enclosing function's span. A real
                    // function definition's declarator parents directly to function_definition (found at hop 1, above), so this never fires for it.
                    if( scope )
                    {
                        // prototype/declaration: use the member/decl wrapper as the span so the RETURN
                        // TYPE is included (not just the declarator), WITHOUT grabbing the class body.
                        const char* ct = ts_node_type( child );
                        if( std::strcmp( ct, "field_declaration" ) == 0 || std::strcmp( ct, "declaration" ) == 0 )
                        {
                            defNode = child;
                        }
                        break;
                    }
                    // Adopt an ancestor's span only if roleNode sits OUTSIDE its body — i.e. roleNode is the
                    // ancestor's own signature/declarator (the C++ function_declarator → function_definition
                    // hop this climb exists for). A def spelled INSIDE the body is a different, NESTED
                    // definition — a JS/TS named const-closure (`const f = (..) => {..}` in a function body) —
                    // and adopting here broadcast the encloser's whole span (loc/cx/params/nest) onto every
                    // such closure (webpack lib/html/syntax.js: eight closures inside the 3439-line `tokenize`
                    // all reported loc=3439 cx=487). The enclosing statement_block is not in the scope-stop
                    // list above (only C-family compound_statement/block are), so nested defs escaped upward;
                    // containment is the grammar-agnostic stop. Gate: test/jsnestedcheck.sh.
                    const TSNode pb = ts_node_child_by_field_name( p, "body", 4 );
                    if( !ts_node_is_null( pb ) )
                    {
                        if( !spanContains( pb, roleNode ) ) { defNode = p; body = pb; }
                        break;
                    }
                    child = p;
                    p     = ts_node_parent( p );
                }
            }

            // ObjC-only body-field fallback for the grammar that exposes a body as an unnamed CHILD, not a
            // named "body" field. C++ function_definition owns a "body" field (found above); the ObjC grammar
            // never does, so the field lookup returns null and bodyByte would stay 0 for a real definition —
            // making an @implementation def indistinguishable from its @interface DECL (both bodyByte==0). That
            // breaks BOTH the same-file decl/def collapse (3a-bis) and graph.h's cross-file hasBody
            // (endByte > sigEndByte), doubling every ObjC symbol node AND its call edges. Recover the
            // body-present signal from a direct child:
            //   - a METHOD def: a bare `compound_statement` / `function_body` / `block` child (the `{...}`).
            //   - an ObjC CLASS: an @implementation carries `implementation_definition` member children; the
            //     matching @interface carries only `method_declaration`s → so an `implementation_definition`
            //     child is exactly "this is the class's definition, not its forward @interface".
            // A bodyLESS declaration (@interface method / @interface class) has none of these children →
            // bodyByte stays 0 → it stays a decl (the discriminant the collapse needs). GATED to Lang::ObjC so
            // C++/Python/Rust/Go/TS/Swift bodyByte — and therefore their sigEndByte, spans, and node/edge
            // output — are BYTE-for-byte unchanged (a .mm's C++ functions take the C "body"-field path above
            // and never reach here). See test/langcheck.sh c.m and the byte-identical src/ regression gate.
            if( ts_node_is_null( body ) && le.lang == Lang::ObjC )
            {
                const std::uint32_t childCount = ts_node_child_count( defNode );
                for( std::uint32_t ci = 0; ci < childCount; ++ci )
                {
                    const TSNode ch = ts_node_child( defNode, ci );
                    const char*  ct = ts_node_type( ch );
                    if( std::strcmp( ct, "compound_statement" ) == 0     || std::strcmp( ct, "function_body" ) == 0
                        || std::strcmp( ct, "block" ) == 0               || std::strcmp( ct, "implementation_definition" ) == 0 )
                    { body = ch; break; }
                }
            }

            d.startByte = ts_node_start_byte( defNode );
            d.endByte   = isTestMacroBlock ? ts_node_end_byte( body ) : ts_node_end_byte( defNode );   // LB-E: the span runs THROUGH the sibling block
            d.nameByte  = nameByte;
            d.bodyByte  = ts_node_is_null( body ) ? 0u : ts_node_start_byte( body );
            const bool  fnOrMethod = ( kind == SymKind::Function || kind == SymKind::Method );
            // LB-E: for a testmacroblock the body SIBLING is where the code lives — complexityOf walks
            // INSIDE its root node, so handing it defNode (the bare macro statement) would count nothing.
            const auto [ cxVal, ccxVal, nestVal, localsVal, ppAltVal, humpsVal, deepVal, evVal, evWhyVal ] = fnOrMethod ? complexityOf( isTestMacroBlock ? body : defNode, src, le.lang ) : Complexity{ 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, {} };
            d.cx        = cxVal;
            d.ccx       = ccxVal;
            d.locals    = localsVal;   // Phase 1: floor count, C/C++ only (model.h localsCountedLang) — 0 elsewhere, never emitted there
            // ppalt disclosure (model.h Symbol::ppAlt). Saturating at 65535 on purpose: a def past that
            // bound is beyond every triage threshold, and the attribute's claim ("the body carries
            // alternatives") is already made at 1.
            d.ppAlt     = fnOrMethod ? std::uint16_t( ppAltVal > 65535u ? 65535u : ppAltVal ) : std::uint16_t( 0 );
            // Q4 size smells (SIZE = master variable): physical LOC = span line count (end row − start row + 1);
            // param count + max nesting for functions/methods only (0 otherwise, absent in emit). All descriptive.
            {
                const std::uint32_t startRow = ts_node_start_point( defNode ).row;
                const std::uint32_t endRow   = ts_node_end_point( isTestMacroBlock ? body : defNode ).row;   // LB-E: rows through the sibling block
                d.loc = ( endRow >= startRow ) ? ( endRow - startRow + 1u ) : 1u;
            }
            d.params    = fnOrMethod ? countParams( defNode ) : std::uint16_t( 0 );
            // LB-E: a testmacroblock's parameter surface is the MACRO's business, not visible here — claim
            // inexact so the resolver's arity narrowing never trusts params=0 on a test-title symbol.
            d.arityExact = ( fnOrMethod && !isTestMacroBlock ) ? std::uint8_t( cc_paramArityExact( defNode, le.lang, kind ) ? 1 : 0 ) : std::uint8_t( 0 );   // B2.2
            // L8: the in-file test-scope bit, for EVERY kind (a `#[cfg(test)] mod` and a `class TestFoo`
            // are themselves symbols, and dropping the members while keeping the shell would be a worse
            // answer than either). Runs on defNode, whose ancestors are the enclosing scopes.
            d.testScope = isTestMacroBlock ? std::uint8_t( 1 ) : std::uint8_t( inFileTestScope( defNode, src, le.lang ) );   // LB-E: a test macro IS the in-file convention
            d.maxNest   = fnOrMethod ? std::uint8_t( nestVal > 255u ? 255u : nestVal ) : std::uint8_t( 0 );
            // The nesting profile (model.h Symbol::humps/deepLoc). Saturating at 65535 on purpose: a def past
            // either bound is beyond every triage threshold, and deepLoc is a floor already, so a clamp there
            // stays honest in the direction the attribute already claims.
            d.humps     = fnOrMethod ? std::uint16_t( humpsVal > 65535u ? 65535u : humpsVal ) : std::uint16_t( 0 );
            d.deepLoc   = fnOrMethod ? std::uint16_t( deepVal  > 65535u ? 65535u : deepVal  ) : std::uint16_t( 0 );
            // essential complexity (model.h Symbol::ev): already saturated inside ev_finalize; 0 for
            // non-function kinds and outside evCountedLang, matching the emitters' omission rule.
            d.ev        = fnOrMethod ? std::uint16_t( evVal > 65535u ? 65535u : evVal ) : std::uint16_t( 0 );
            d.evWhy     = fnOrMethod ? evWhyVal : std::array<std::uint8_t, kEvWhyTagCount>{};
            d.kind      = kind;
            d.lang      = le.lang;
            d.name      = isTestMacroBlock ? std::string( nameTxt ) : defNameFromCapture( le.lang, nameTxt );   // LB-E: a title is a display string — see testMacroTitleOf
            if( le.lang == Lang::Cpp )                              // canonical scope (E#4): out-of-line `A::b` → "A", else enclosing class/namespace
            {
                d.scope = qualifierOf( nameNode, src );
                if( d.scope.empty() )
                {
                    d.scope = enclosingScopeOf( nameNode, src );
                }
            }
            else if( le.lang == Lang::Python )
            { // P2-D Rule 1: enclosing class of a Python method → `self.m()` narrows to Class::m
                d.scope = enclosingScopeOf( nameNode, src );
            }
            else if( le.lang == Lang::Rust )
            { // H4: `impl Widget { fn new() }` → "Widget" — see rustEnclosingScopeOf
                d.scope = rustEnclosingScopeOf( nameNode, src, /*includeModules=*/true );
            }
            defs.push_back( std::move( d ) );
            if( kind == SymKind::Class || kind == SymKind::Struct || kind == SymKind::Interface )
            {
                captureBases( defNode, fileId, le.lang, src, refs );    // IS-A: inheritance edges (derived → base)
                captureFields( defNode, fileId, le.lang, src, refs );   // HAS-A: member-variable type edges (S5-E)
            }
            else if( kind == SymKind::Macro )
            {
                captureMacroBodyCalls( roleNode, fileId, le.lang, src, refs );   // macro-edges: the graph connects THROUGH the macro
            }
            }
            else if( isRef )
            {
                // H4: a C++ cast keyword is not a call — see isCppCastKeyword. Valid input, skipped, no alert.
                if( le.lang == Lang::Cpp && isCppCastKeyword( nameTxt ) )
                {
                    continue;
                }

                // using-declaration re-exports (r9 loss bucket 1): @reference.import marks the C++
                // `using ns::name;` tags pattern. The site becomes a role="import" use-site of the target
                // (never a call edge — graph.h admits Call+Macro only), and the grammar KEYWORD forms
                // (`using namespace ns;` / `using enum E;`) are dropped here at capture time, where the
                // query predicate a tags pattern cannot express IS enforceable (see the helper's note).
                const bool isImportRef = ( refCapSv == "reference.import" );
                if( isImportRef && usingDeclarationIsDirective( roleNode ) )
                {
                    continue;
                }

                RawRef r;
                r.fileId    = fileId;
                r.startByte = ts_node_start_byte( roleNode );
                r.line      = ts_node_start_point( roleNode ).row + 1;   // ABS-3: 1-based use-site line for --uses
                r.lang      = le.lang;
                r.role      = isImportRef ? RefRole::Import : RefRole::Call;   // ABS-3: @reference.call is a call use-site; @reference.import a using-decl re-export
                r.name      = finalSegment( nameTxt );
                if( le.lang == Lang::Cpp )
                {
                    r.qualifier = qualifierOf( nameNode, src ); // `A::b()` → "A" (E#4 canonical resolve)
                }
                else if( le.lang == Lang::Rust )
                {
                    r.qualifier = rustQualifierOf( nameNode, src ); // H4: `Widget::new()` → "Widget"
                }

                // H4 RE-SPLIT: the widened qualified-call pattern binds the INNER node, so a 3+-segment call's
                // captured text still carries scope (`inner::targetFn`). Recover the pair the canonical tier
                // keys on — name = the final segment, qualifier = the IMMEDIATE scope — from the text itself.
                // This must run INSTEAD OF the finalSegment() above (it overwrites both fields): finalSegment
                // truncates at the first '<', which would name `numeric_limits<std::size_t>::max` as
                // `numeric_limits` and mint an edge to the wrong symbol. Inert for every 2-segment call
                // (`rw::midFn` binds a bare identifier — no top-level `::` in the text) and for
                // `ns::tmplFn<int>()` (whose `::` sits inside no group but whose captured text is just
                // `tmplFn<int>`), so those keep their qualifierOf() result untouched.
                if( le.lang == Lang::Cpp )
                {
                    // An OPERATOR tail is recognised first: its `<`/`>` are part of the NAME, so handing it to
                    // the angle-depth scan below binds the wrong scope for the whole `>` family. See
                    // operatorNameStart. When the operator spelling starts at index 0 the capture IS the bare
                    // operator name, its parent is the qualified_identifier, and qualifierOf() already put the
                    // immediate scope in r.qualifier — nothing to re-split.
                    const std::size_t opStart = operatorNameStart( nameTxt );
                    const bool        opScoped = opStart != std::string_view::npos && opStart >= 2
                                              && nameTxt[ opStart - 1 ] == ':' && nameTxt[ opStart - 2 ] == ':';
                    if( opScoped )
                    {
                        r.name      = finalSegment( nameTxt.substr( opStart ) );                                  // `operator>` verbatim
                        r.qualifier = immediateScope( namesplit::stripTemplateArgs( nameTxt.substr( 0, opStart - 2 ) ) );
                    }
                    else if( opStart == std::string_view::npos )
                    {
                        if( const std::size_t sep = lastTopLevelScopeSep( nameTxt ); sep != std::string_view::npos )
                        {
                            r.name      = finalSegment( nameTxt.substr( sep + 2 ) );
                            r.qualifier = immediateScope( namesplit::stripTemplateArgs( nameTxt.substr( 0, sep ) ) );
                        }
                    }
                }

                if( !isImportRef )                                                       // an import site has no receiver and no argument list —
                {                                                                        //   the defaults (RecvKind::None, argCountKnown=false) are the truth
                    RecvShape rs = receiverOf( nameNode, le.lang, src );                 // P2-D: `this`/`self`/`x`/`base.field` shape
                    r.recv = rs.kind;  r.recvVar = std::move( rs.var );                  //   → one-hop narrowing in resolve.h
                    r.fieldName = std::move( rs.field );                                 //   depth-2 intermediate field; "" otherwise
                    auto [ ac, ak ] = callArity( nameNode, le.lang, src );               // B2.2: call-site positional arg count
                    r.argCount = ac;  r.argCountKnown = ak;                              //   → arity filter in graph.h
                }
                refs.push_back( std::move( r ) );
            }
        }
    }
}

}   // namespace

// =====================================================================================
// The markitdown-bridge doc cache, lifted out of ingest()'s doc post-pass worker (that function is
// already the file's largest — the logic reads better named). A doc that needs the BRIDGE
// (pdf/docx/pptx/xlsx) costs a popen + a Python-CLI start per file (~seconds), and the post-pass
// reruns every invocation by design — so on a machine WITH markitdown installed every warm run paid
// it (measured: 3.2 s wall, ~1 ms task-clock, for the two present/ decks). The extraction is a pure
// function of the file BYTES, so bridge results are cached under the shared cache dir keyed by
// content hash; the "ripwire-" prefix keeps eviction inside the existing family sweep (whose
// age+size caps also bound a markitdown UPGRADE's staleness — the input-bytes key alone would never
// notice one). An EMPTY extraction is never cached: "" means markitdown absent or errored — a fact
// about the machine, not the bytes. Hand-rolled kinds (ipynb/html/csv) stay uncached (microseconds);
// cacheEnabled=false (--no-cache) bypasses the sidecar entirely. tmpKey keeps concurrent workers'
// unpublished temp files distinct; the publish itself is a whole-file rename, so a concurrent
// reader sees every byte or none.
inline std::string docTextViaBridgeCache( const std::string& path, const std::string& ext, bool cacheEnabled, std::uint32_t tmpKey )
{
    std::string text;
    std::string bridgeBlobPath;
    if( cacheEnabled && docparse::docKindOf( ext ) == docparse::DocKind::Markitdown )
    {
        std::string docBytes;
        if( docparse::detail::readWholeFile( path, docBytes ) )
        {
            char blobName[ 64 ];
            std::snprintf( blobName, sizeof( blobName ), "ripwire-docmd-%016llx.bin",
                           static_cast<unsigned long long>( fnv1a64( docBytes ) ) );
            bridgeBlobPath = quality::resolveCacheBlobPath( quality::cacheDirLadder(), blobName );
            docparse::detail::readWholeFile( bridgeBlobPath, text );   // miss ⇒ text stays empty
        }
    }
    if( text.empty() )
    {
        text = docparse::parseDocFile( path, ext );
        if( !text.empty() && !bridgeBlobPath.empty() )
        {
            const std::string tmp = bridgeBlobPath + ".tmp" + std::to_string( tmpKey );
            std::FILE* fp = std::fopen( tmp.c_str(), "wb" );
            if( fp != nullptr )
            {
                const bool wroteAll = std::fwrite( text.data(), 1, text.size(), fp ) == text.size();
                std::fclose( fp );
                if( !wroteAll || std::rename( tmp.c_str(), bridgeBlobPath.c_str() ) != 0 )
                {
                    std::remove( tmp.c_str() );
                }
            }
        }
    }
    return text;
}

// Per-worker capacity floor for the COLD parse pool, sized from the crawl's parseable byte count.
//
// WHY THIS EXISTS. The warm reserve sums cached FileFacts, so it only runs when a cache is loaded; a cold
// run reserved nothing and every accumulator doubled up from zero — ~500 whole-vector reallocations per
// run, on the one path where all workers hammer the allocator at once.
//
// WHAT IT IS WORTH, MEASURED, so nobody re-litigates it from the plausible-sounding story. Against pristine
// HEAD on three cold corpora (this repo at ~1.1k files, plus a 2.4k-file and a 0.7k-file ObjC++/C++ tree),
// --no-cache on both sides, 9 reps: heap allocations about -505 / -465 / -420, which is only -0.29% /
// -0.06% / -0.12% of each run's total. Peak live bytes is a WASH — repeat measurements of the very same
// binaries move it between -0.6 and +2.0 MB, i.e. the sign is not stable, so the "stranded buffers" story
// does not survive contact with an allocator that reuses them. Parse-pool wall clock is a NULL RESULT: two
// independent 15-pair interleaved runs disagreed in SIGN on two of the three corpora, so machine drift
// exceeds the effect. This removes real work; it does not make the tool measurably faster, and it does not
// measurably shrink it either. Not a speedup — do not cite it as one.
//
// BYTES, NOT FILE COUNT, IS THE PREDICTOR. Over ten corpora spanning C/C++, ObjC++, Rust, Swift, Python/TS
// and generated C, refs-per-FILE spans 190x (10.6 … 2017.6) while refs-per-BYTE spans 11x; binds-per-file
// spans 1325x against 432x per byte. A file count cannot size the two families that hold the memory. Each
// divisor is the bytes-per-element of roughly the LEAST dense corpus measured, so the estimate is a floor,
// not a forecast, and lands under the real total nearly everywhere.
//
// WHY THE CAP, which is the part that is easy to get wrong. Allocations saved grow like log2( reserve )
// while the memory risked grows like the reserve itself, so the efficient point is small: measured, a
// 256-element cap keeps 84-94% of the allocations an uncapped mean-sized reserve saves, bounded by
// 256 * ( 168 + 144 + 32 + 72 ) B * nthreads ~= 1.9 MB in the worst case where every worker finishes under
// it. Reserving each worker the corpus MEAN is worse than it looks: work is uneven (the busiest worker
// holds 1.3-5.2x the mean, median ~1.9x), so a mean-sized reserve over-allocates the below-mean majority
// to suit one worker — that variant measured 1-2.5 MB of extra peak live bytes for ~60 more allocations.
//
// ROUNDED DOWN TO A POWER OF TWO. An empty vector grows 1, 2, 4, 8, … so its final capacity for n elements
// is exactly the next power of two; starting from 2^j the ladder is 2^j, 2^(j+1), … — a SUBSEQUENCE of the
// same powers. Seeding with a power of two therefore lands on the identical final capacity for any worker
// that reaches it, and can only remove growth steps. An arbitrary seed cannot say that: a vector reserved
// to R that needs R+1 doubles to 2R and can finish above where it would have landed alone.
//
// FFI and route accumulators get nothing on purpose: across the same ten corpora they total 0-363 entries
// and are non-empty on only 0-11 of 18 workers, so a reserve there would be pure waste.
struct ColdParseReserve
{
    std::size_t defs;
    std::size_t refs;
    std::size_t incs;
    std::size_t binds;
};

// fileLang and fileByteSize are the crawl's two parallel per-file arrays; a file counts toward the estimate
// only when it has a grammar, which is the same predicate the divisors were calibrated under. Keeping the
// predicate next to the constants is deliberate: change one and the other stops being calibrated.
inline ColdParseReserve coldParseReserve( std::span<const LangEntry* const> fileLang,
                                          std::span<const std::uintmax_t> fileByteSize,
                                          unsigned nthreads ) noexcept
{
    VERIFY( nthreads >= 1 );   // caller derives it from min( hardware_concurrency, nfiles ) with nfiles >= 1
    VERIFY( fileLang.size() == fileByteSize.size() );

    std::size_t parseableBytes = 0;
    for( std::size_t fileId = 0; fileId < fileLang.size(); ++fileId )
    {
        const LangEntry* le = fileLang[ fileId ];
        if( le != nullptr && le->grammar != nullptr )
        {
            parseableBytes += static_cast<std::size_t>( fileByteSize[ fileId ] );
        }
    }

    // bytes per element, calibrated 2026-08-10 against the ten-corpus census described above
    constexpr std::size_t kBytesPerDef  =  2400;
    constexpr std::size_t kBytesPerRef  =   800;
    constexpr std::size_t kBytesPerInc  = 20000;
    constexpr std::size_t kBytesPerBind =  4000;
    constexpr std::size_t kCapPerThread =   256;

    // Integer division throughout: no float, and no overflow — parseableBytes is a byte count, every divisor
    // is a nonzero constant, and nthreads is at least 1. An all-documentation tree yields 0 for every family,
    // and reserve( 0 ) is a no-op.
    const auto perThread = [ parseableBytes, nthreads, cap = kCapPerThread ]( std::size_t bytesPerElem ) noexcept
    {
        return std::min( std::bit_floor( parseableBytes / bytesPerElem / nthreads ), cap );
    };

    const ColdParseReserve r{ perThread( kBytesPerDef ), perThread( kBytesPerRef ),
                              perThread( kBytesPerInc ), perThread( kBytesPerBind ) };

    // The two properties the whole argument above rests on: every value is a power of two (so the doubling
    // ladder is unchanged) and none exceeds the cap (so the waste stays bounded).
    VERIFY( r.defs  <= kCapPerThread && ( r.defs  == 0 || std::has_single_bit( r.defs  ) ) );
    VERIFY( r.refs  <= kCapPerThread && ( r.refs  == 0 || std::has_single_bit( r.refs  ) ) );
    VERIFY( r.incs  <= kCapPerThread && ( r.incs  == 0 || std::has_single_bit( r.incs  ) ) );
    VERIFY( r.binds <= kCapPerThread && ( r.binds == 0 || std::has_single_bit( r.binds ) ) );
    return r;
}

IngestResult ingest( const char* rootDir, const std::vector<std::string>& excludeSubstr, std::string_view cacheFile,
                     std::size_t maxFileBytes, bool captureValueUses, std::string_view excludeLabel )
{
    PROFILE_SCOPE_DESCRIBE( "ingest: total (crawl + parse + model)" );
    // Cheap (a handful of bytes serialized twice) and runs once per invocation — catches a
    // writeDef/writeRef field added without updating kMinDefRecordBytesLean/kMinRefRecordBytes immediately
    // in any debug/ASan run, before it can silently weaken the cache record-count bounds check.
    verifyCacheRecordMinimaTripwire();

    IngestResult result;
    // A4-F17: rootDir is a runtime-falsifiable input (caller/CLI-supplied), so degrade — never VERIFY here.
    // In release VERIFY becomes __builtin_assume, which would delete the very guard below (the CLAUDE.md trap).
    if( rootDir == nullptr )
    {
        DEGRADED_PATH_ALERT( "ingest: null root directory — empty result" );
        return result;
    }

    // a zero/absurd ceiling would silently crawl nothing — clamp to the default (degrade, never trap).
    if( maxFileBytes == 0 )
    {
        maxFileBytes = kDefaultMaxFileBytes;
    }

    // 1) deterministic crawl -> sorted file list (this list IS result.files / the fileId space)
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: crawl (collectSources)" );
        auto [ crawledPaths, oversizeSkipped, taxonomySkips ] = collectSources( rootDir, excludeSubstr, maxFileBytes, excludeLabel );
        result.files           = std::move( crawledPaths );
        result.skippedOversize = std::move( oversizeSkipped );
        result.crawlSkips      = std::move( taxonomySkips );   // §L1: excluded / unsupported-ext / unindexed exts
    }

    // 2) parse every file IN PARALLEL — one TSParser per worker thread (parsers aren't
    //    thread-safe), per-thread raw lists merged after. Determinism is preserved: defs/refs
    //    are re-sorted below, so collection order is irrelevant.
    std::vector<RawDef>  rawDefs;
    std::vector<RawRef>  rawRefs;
    std::vector<Include> rawIncs;
    std::vector<RawBind> rawBinds;   // P2-D Rule 2: local var→type bindings
    std::vector<BindingAlias> rawFfis;   // A4-R5: cross-language FFI binding declarations
    std::vector<RouteDef>     rawRouteDefs;   // B6.3: HTTP server-side route registrations
    std::vector<RawRouteUse>  rawRouteUses;   // B6.3: HTTP client-side calls (pre fromSymbol attribution)

    // Win 1 (PERF.md P1) — lazy grammar compilation: load the cache FIRST, then compile only the
    // grammars needed by cache-miss files (new or hash-changed). On a fully-warm zero-change run,
    // zero grammars need compiling → ~70ms saved (72% of warm canyon). On a partial-change run,
    // only the grammars touched by changed files are compiled (typically 1 for a single .cpp edit).
    //
    // Implementation: a pre-pass reads+hashes each file and checks against the loaded cache;
    // misses mark their grammar. Hashes are stored so the parse pool reuses them (no double-read).
    // The constraint: compiledQueryCache() is single-writer and worker reads happen only after the ready gate
    // opens. Cold query compilation is launched before the parse pool; the main thread installs the shared
    // cache and notifies workers while they are already doing parse-side work.

    // incremental: load the content-hash cache BEFORE the prewarm. Empty cacheFile ⇒ full parse.
    // fileHash: pre-sized to nfiles here (0 = not yet hashed); the prewarm miss-detection pass
    // populates entries for files it reads; the parse pool fills the rest during normal processing.
    // A4-P7: cacheWriteNs is the loaded blob's write timestamp — the racy-rule reference for the warm-run
    // stat-gate. -1 (no/rejected cache) makes every stat check see a racy entry → always read+hash (safe).
    long long cacheWriteNs = -1;
    HashMap<std::string, FileFacts> cache =
        cacheFile.empty() ? HashMap<std::string, FileFacts>{} : loadCache( std::string( cacheFile ), rootDir, captureValueUses, cacheWriteNs );
    const std::size_t nfilesEarly = result.files.size();
    const bool needsCacheHash = !cacheFile.empty();
    std::vector<std::uint64_t> fileHash( nfilesEarly, 0 );
    // A4-P7 stat-gate: (size,mtime) observed for each file at the run that hashes it — persisted by saveCache
    // so a future warm run can trust an unchanged file without reading it. -1 ⇒ not captured (never trusted).
    std::vector<long long> fileStatSize( nfilesEarly, -1 );
    std::vector<long long> fileStatMtime( nfilesEarly, -1 );
    std::vector<FileHealth> fileHealth( nfilesEarly );   // §L1: one slot per fileId, one WRITER per slot
    std::vector<const LangEntry*> fileLang( nfilesEarly, nullptr );
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: classify file languages" );
        for( std::size_t fileId = 0; fileId < nfilesEarly; ++fileId )
        {
            const std::string ext = lowerExtensionOf( result.files[ fileId ] );
            fileLang[ fileId ] = lookupLang( ext );
        }
    }

    std::vector<const LangEntry*> toCompile;
    std::vector<TSQuery*>         compiledQueries;
    std::vector<std::thread>      queryCompilePool;
    std::atomic<bool>             queryPrewarmReady{ true };
    std::mutex                    queryPrewarmMutex;
    std::condition_variable       queryPrewarmCv;
    QueryReadyGate                queryReadyGate{ &queryPrewarmReady, &queryPrewarmMutex, &queryPrewarmCv };

    // pre-warm the per-language tags.scm cache single-threaded; workers then only READ it.
    // LAZY: compile ONLY grammars needed by changed/uncached files (the miss set).
    // The grammar set must be a SUPERSET of every grammar any worker will touch:
    //   - a cache miss → grammar guaranteed needed → mark it
    //   - a cache hit (hash-match) → worker skips parse → grammar NOT needed (safe to omit)
    //   - a .h miss that looks Objective-C → marks objc instead of cpp (same looksObjC re-route as parse pool)
    //   - an unreadable .h miss → conservatively marks both cpp and objc, matching the old safety fallback
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: compile queries (tags.scm prewarm)" );
        std::array<bool, kLangTable.size()> present {};
        bool anyUnknownHeaderMiss = false;

        // The miss-detection pass reads + FNV-hashes every cache-present code file to decide which grammars a
        // worker will actually need. That I/O + hashing was serial (~61ms on canyon warm). It is READ-ONLY and
        // a pure function of each file's bytes, so parallelize it — but keep the RESULT deterministic: every
        // thread writes ONLY its own per-index slots (fileHash[fi], isMiss[fi]); nothing is
        // push_back'd from a worker. The grammar-mark reduction that follows is a serial pass over those slots,
        // so the compiled-grammar set (and thus everything downstream) is independent of thread scheduling.
        // The 204bb02 constraint still holds: compiledQueryCache() is populated single-threaded after the
        // async compile join, and workers wait on queryPrewarmReady before reading it. fileHash is pre-filled
        // so the pool skips the re-read on a cache hit.
        std::vector<char> isMiss( nfilesEarly, 0 );              // 1 ⇒ this file's grammar is needed (cache miss/new)
        std::vector<char> isObjCHeaderMiss( nfilesEarly, 0 );    // 1 ⇒ missed .h should reroute to ObjC grammar
        std::vector<char> isUnknownHeaderMiss( nfilesEarly, 0 ); // 1 ⇒ missed .h could not be sniffed; compile fallback

        if( cache.empty() )
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: mark no-cache grammars" );

            for( std::size_t fi = 0; fi < nfilesEarly; ++fi )
            {
                const LangEntry* le = fileLang[ fi ];
                if( le == nullptr || le->grammar == nullptr )
                {
                    continue;   // doc extensions / markdown — no grammar needed
                }

                present[ static_cast<std::size_t>( le - kLangTable.data() ) ] = true;
                if( le->ext == ".h" )
                {
                    // With no cache, every header is a parse miss. Mark ObjC too so a header that reroutes
                    // after the parse pool's content sniff never blocks on an uncompiled query.
                    if( const LangEntry* objcLe = lookupLang( ".m" ) )
                    {
                        present[ static_cast<std::size_t>( objcLe - kLangTable.data() ) ] = true;
                    }
                }
            }
        }
        else
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: detect cache misses" );

            unsigned hwHash = std::thread::hardware_concurrency();
            if( hwHash == 0 )
            {
                hwHash = 1;
            }
            const unsigned nHashThreads = static_cast<unsigned>( std::min<std::size_t>( hwHash, std::max<std::size_t>( nfilesEarly, 1 ) ) );
            std::atomic<std::size_t> nextIdx{ 0 };
            std::vector<std::thread> hashPool;
            hashPool.reserve( nHashThreads );

            for( unsigned t = 0; t < nHashThreads; ++t )
            {
                hashPool.emplace_back( [ & ]()
                {
                    std::string bytes;
                    std::string headerPrefix;
                    for( ;; )
                    {
                        const std::size_t fi = nextIdx.fetch_add( 1, std::memory_order_relaxed );
                        if( fi >= nfilesEarly )
                        {
                            break;
                        }
                        try   // per-file degrade — a throw escaping a worker thread would std::terminate
                        {
                            const std::string& f = result.files[ fi ];
                            const LangEntry* le = fileLang[ fi ];
                            if( le == nullptr )
                            {
                                continue;   // doc extensions — never cached (the doc post-pass re-extracts)
                            }
                            // B0: grammar-less languages (markdown) still flow through the cache stat-gate /
                            // read+hash below so an UNCHANGED .md warm-hits without any read (previously the
                            // early grammar skip left fileHash=0 and the parse pool re-read every .md every
                            // run — the last per-run file-read the postings path had left). They only skip
                            // the grammar-miss bookkeeping at the bottom (nothing to compile for them).

                            bool hasFullBytes = false;

                            // path absent from cache ⇒ definitely a miss (no read needed). Present ⇒ try the
                            // A4-P7 stat-gate first, else read+hash.
                            if( !cache.empty() )
                            {
                                const auto cit = cache.find( f );
                                if( cit != cache.end() )
                                {
                                    const FileFacts& ff = cit->second;

                                    // A4-P7 STAT-GATE: trust the cached parse WITHOUT reading/hashing when the
                                    // current size+mtime still match the cache AND the entry is not racy (its
                                    // mtime is strictly older than the blob's own write time — a same-granule
                                    // post-hash edit could otherwise slip through undetected). Content hash stays
                                    // the authority: any mismatch, an unstatable file, or a racy entry falls
                                    // through to the read+hash path below.
                                    const StatInfo si = statSizeMtime( f );
                                    const bool statMatches = si.mtimeNs >= 0 && ff.mtimeNs >= 0
                                                          && si.sizeBytes == ff.sizeBytes
                                                          && si.mtimeNs   == ff.mtimeNs;
                                    const bool notRacy = cacheWriteNs >= 0 && ff.mtimeNs < cacheWriteNs;
                                    if( statMatches && notRacy )
                                    {
                                        fileHash[ fi ]      = ff.hash;        // parse pool sees a cache hit → never reads
                                        fileStatSize[ fi ]  = si.sizeBytes;   // carry stat forward into the re-saved blob
                                        fileStatMtime[ fi ] = si.mtimeNs;
                                        continue;   // provably unchanged — grammar NOT needed for this file
                                    }

                                    if( !readFile( f, bytes ) )
                                    {
                                        continue;   // unreadable — worker will skip it too (not a miss to compile for)
                                    }
                                    hasFullBytes = true;
                                    const std::uint64_t h = contentHash64( bytes );
                                    fileHash[ fi ] = h;   // pre-fill so the parse pool can skip the re-read on a cache hit
                                    // capture the stat observed at hash time so this file stays stat-gate-eligible next run
                                    fileStatSize[ fi ]  = si.sizeBytes >= 0 ? si.sizeBytes : (long long)bytes.size();
                                    fileStatMtime[ fi ] = si.mtimeNs;
                                    if( ff.hash == h )
                                    {
                                        continue;   // cache hit — parse skipped → grammar NOT needed for this file
                                    }
                                }
                                // else: path not in cache → miss (fall through)
                            }

                            if( le->grammar == nullptr )
                            {
                                continue;   // markdown: hash prefill only — no grammar to compile, no miss to mark
                            }

                            if( le->ext == ".h" )
                            {
                                std::string_view headerBytes;
                                if( hasFullBytes )
                                {
                                    headerBytes = bytes;
                                }
                                else if( readFilePrefix( f, headerPrefix, 8192 ) )
                                {
                                    headerBytes = headerPrefix;
                                }
                                else
                                {
                                    isUnknownHeaderMiss[ fi ] = 1;
                                }
                                if( !headerBytes.empty() && looksObjC( headerBytes ) )
                                {
                                    isObjCHeaderMiss[ fi ] = 1;
                                }
                            }
                            isMiss[ fi ] = 1;   // cache empty, path-absent, or hash-changed → grammar needed
                        }
                        catch( ... )
                        {
                            DEGRADED_PATH_ALERT( "ingest: prewarm hash worker exception on a file — treated as no-miss" );
                        }
                    }
                } );
            }
            for( std::thread& th : hashPool )
            {
                th.join();
            }
            // serial grammar-mark reduction over the per-index results (order-independent: pure boolean OR).
            {
                PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: reduce grammar set" );

                for( std::size_t fi = 0; fi < nfilesEarly; ++fi )
                {
                    if( !isMiss[fi] )
                    {
                        continue;
                    }
                    const LangEntry* le = fileLang[ fi ];
                    if( le == nullptr )
                    {
                        continue; // defensive (isMiss only set for grammar-bearing files)
                    }
                    if( le->ext == ".h" )
                    {
                        if( isObjCHeaderMiss[ fi ] )
                        {
                            if( const LangEntry* objcLe = lookupLang( ".m" ) )
                            {
                                present[ static_cast<std::size_t>( objcLe - kLangTable.data() ) ] = true;
                            }
                        }
                        else
                        {
                            present[ static_cast<std::size_t>( le - kLangTable.data() ) ] = true;
                            if( isUnknownHeaderMiss[ fi ] )
                            {
                                anyUnknownHeaderMiss = true;
                            }
                        }
                        continue;
                    }
                    present[ static_cast<std::size_t>( le - kLangTable.data() ) ] = true;
                }
                if( anyUnknownHeaderMiss )
                {
                    if( const LangEntry* objcLe = lookupLang( ".m" ) )
                    {
                        present[ static_cast<std::size_t>( objcLe - kLangTable.data() ) ] = true;
                    }
                }
            }
        }

        // distinct grammars needed by cache-miss files (several extensions share one grammar)
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: unique grammars" );

            for( std::size_t i = 0; i < kLangTable.size(); ++i )
            {
                const LangEntry& e = kLangTable[ i ];
                if( e.grammar == nullptr || e.querySub.empty() || !present[ i ] )
                {
                    continue;   // querySub "" = markdown: a grammar with NO tags.scm (custom walk) — nothing to compile
                }
                const TSLanguage* lang = e.grammar();
                bool seen = false;
                for( const LangEntry* c : toCompile )
                {
                    if( c->grammar() == lang )
                    {
                        seen = true;
                        break;
                    }
                }
                if( !seen )
                {
                    toCompile.push_back( &e );
                }
            }
        }

        // Compile distinct grammars IN PARALLEL (ts_query_new is compute-bound — PMC IPC 4.0) and install
        // into the shared cache single-threaded after the join. Query sources are immutable embedded views.
        compiledQueries.assign( toCompile.size(), nullptr );
        queryCompilePool.reserve( toCompile.size() );
        queryPrewarmReady.store( toCompile.empty(), std::memory_order_release );
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: launch ts_query_new async" );

            for( std::size_t i = 0; i < toCompile.size(); ++i )
            {
                queryCompilePool.emplace_back( [ &compiledQueries, &toCompile, i ]() { compiledQueries[ i ] = compileQueryStandalone( *toCompile[ i ] ); } );
            }
        }
    }

    // Win 2 (PERF.md P2) — dirty flag: skip saveCache when nothing changed.
    // Set by any worker that re-parses a file (cache miss or new file). On a zero-change run,
    // dirty stays false and the 7 MB re-serialization + write is skipped entirely (~11ms on full repo).
    std::atomic<bool> dirty{ false };

    // A1 (team-index) — drift-proportional observable: count files that actually RE-PARSED (cache miss /
    // changed / new). Emitted to stderr only when RIPWIRE_CACHE_STATS is set (off by default → zero
    // perturbation to any output/determinism gate), so a test can assert "restore cost is proportional to
    // drift" (modify N of F files → reparsed=N) as an executable fact, not just prose. Relaxed: a monotone
    // counter whose only reader is the post-join print, ordered by the pool join below.
    std::atomic<std::size_t> reparsedCount{ 0 };

    const std::size_t nfiles = result.files.size();
    if( nfiles )
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: parse pool (tree-sitter, parallel)" );
        // fileHash is already pre-sized to nfiles (done before the prewarm block above).
        // Entries pre-filled by the prewarm miss-detection pass (cache-present files that were read+hashed
        // there) stay as-is. Workers fill the remaining 0-valued entries for files they process.
        VERIFY( fileHash.size() == nfiles );
        unsigned hw = std::thread::hardware_concurrency();
        if( hw == 0 )
        {
            hw = 1;
        }
        const unsigned nthreads = static_cast<unsigned>( std::min<std::size_t>( hw, nfiles ) );

        std::vector<std::vector<RawDef>>  tDefs( nthreads );
        std::vector<std::vector<RawRef>>  tRefs( nthreads );
        std::vector<std::vector<Include>> tIncs( nthreads );
        std::vector<std::vector<RawBind>> tBinds( nthreads );
        std::vector<std::vector<BindingAlias>> tFfis( nthreads );
        std::vector<std::vector<RouteDef>>     tRouteDefs( nthreads );   // B6.3
        std::vector<std::vector<RawRouteUse>>  tRouteUses( nthreads );   // B6.3
        std::vector<FileFacts*>           cacheCandidateFacts( nfiles, nullptr );
        std::vector<FileFacts*>           cacheHitFacts( nfiles, nullptr );

        // Per-file byte sizes are wanted in two places below — the cold-path reserve, and the
        // longest-file-first work order. Fill at most once, on demand, so a warm run that also skips
        // the work order still performs no stat pass at all (exactly as before this was hoisted).
        std::vector<std::uintmax_t> fileByteSize;
        const auto ensureFileByteSize = [ & ]()
        {
            if( !fileByteSize.empty() )
            {
                return;
            }
            fileByteSize.assign( nfiles, 0 );
            std::error_code ec;
            for( std::size_t fileId = 0; fileId < nfiles; ++fileId )
            {
                ec.clear();
                fileByteSize[ fileId ] = fs::file_size( result.files[ fileId ], ec );
                if( ec )
                {
                    fileByteSize[ fileId ] = 0;
                }
            }
        };

        if( !cache.empty() )
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: prepare cache-hit reuse" );

            std::size_t hitDefs = 0, hitRefs = 0, hitIncs = 0, hitBinds = 0;
            for( std::size_t fileId = 0; fileId < nfiles; ++fileId )
            {
                const std::uint64_t h = fileHash[ fileId ];
                const auto it = cache.find( result.files[ fileId ] );
                if( it == cache.end() )
                {
                    continue;
                }
                cacheCandidateFacts[ fileId ] = &it->second;
                if( it->second.hash != h )
                {
                    continue;
                }
                cacheHitFacts[ fileId ] = &it->second;
                hitDefs  += it->second.defs.size();
                hitRefs  += it->second.refs.size();
                hitIncs  += it->second.incs.size();
                hitBinds += it->second.binds.size();
            }
            const auto perThreadReserve = [ nthreads ]( std::size_t total ) noexcept
            {
                return ( total + std::size_t( nthreads ) - 1 ) / std::size_t( nthreads );
            };
            const std::size_t defsPerThread  = perThreadReserve( hitDefs );
            const std::size_t refsPerThread  = perThreadReserve( hitRefs );
            const std::size_t incsPerThread  = perThreadReserve( hitIncs );
            const std::size_t bindsPerThread = perThreadReserve( hitBinds );
            for( unsigned t = 0; t < nthreads; ++t )
            {
                tDefs[ t ].reserve( defsPerThread );
                tRefs[ t ].reserve( refsPerThread );
                tIncs[ t ].reserve( incsPerThread );
                tBinds[ t ].reserve( bindsPerThread );
            }
        }
        else
        {
            // Cold: no cache to size from, so size the accumulators from the crawl's parseable byte
            // count. coldParseReserve() carries the calibration and the reasoning behind the numbers.
            PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: prepare cold reserve" );

            ensureFileByteSize();
            const ColdParseReserve cold = coldParseReserve( fileLang, fileByteSize, nthreads );
            for( unsigned t = 0; t < nthreads; ++t )
            {
                tDefs[ t ].reserve( cold.defs );
                tRefs[ t ].reserve( cold.refs );
                tIncs[ t ].reserve( cold.incs );
                tBinds[ t ].reserve( cold.binds );
            }
        }
        std::vector<std::thread>          pool;
        pool.reserve( nthreads );
        std::vector<std::size_t>          parseOrder;
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: build work order" );

            if( !queryPrewarmReady.load( std::memory_order_acquire ) )
            {
                parseOrder.resize( nfiles );
                std::iota( parseOrder.begin(), parseOrder.end(), std::size_t( 0 ) );

                ensureFileByteSize();   // already filled by the cold-path reserve above; a no-op there

                const auto parsePriority = [ & ]( std::size_t fileId ) noexcept
                {
                    const LangEntry* le = fileLang[ fileId ];
                    if( le == nullptr || le->grammar == nullptr )
                    {
                        return 0;   // docs/markdown and unknowns do not consume the tags-query barrier
                    }
                    if( !cache.empty() && cacheHitFacts[ fileId ] != nullptr )
                    {
                        return 1;   // warm cache hit: cheap copy, no parse/query work
                    }
                    return 2;       // cache miss/no-cache: full parse + tags query
                };
                std::stable_sort( parseOrder.begin(), parseOrder.end(),
                                  [ & ]( std::size_t a, std::size_t b ) noexcept
                                  {
                                      const int pa = parsePriority( a );
                                      const int pb = parsePriority( b );
                                      if( pa != pb )
                                      {
                                          return pa > pb;
                                      }
                                      if( fileByteSize[a] != fileByteSize[b] )
                                      {
                                          return fileByteSize[a] > fileByteSize[b];
                                      }
                                      return a < b;
                                  } );
            }
        }
        std::atomic<std::size_t>          nextFile{ 0 };   // lock-free work queue: threads fetch_add for the next parseOrder slot

        for( unsigned t = 0; t < nthreads; ++t )
        {
            pool.emplace_back( [ &, t ]()
            {
                ParserGuard pg;
                if( pg.p == nullptr )
                {
                    DEGRADED_PATH_ALERT( "ingest: ts_parser_new failed on a worker — its files skipped" );
                    return;
                }
                TSQueryCursor* cursor = ts_query_cursor_new();
                if( cursor == nullptr )
                {
                    DEGRADED_PATH_ALERT( "ingest: ts_query_cursor_new failed on a worker — its files skipped" );
                    return;
                }

                // B0.2: per-worker subtoken-stats builder — after a file's defs are extracted (and the file's
                // bytes are STILL in memory), tokenize each new def's doc/body spans ONCE into its persisted
                // stats (lexindex.h). Rich ingests only; a def's stats ride the RawDef through dedup/sort/cache
                // so alignment with the eventual Symbol is free. scratch is reused across defs (no rehash churn).
                HashMap<std::uint64_t, std::uint32_t> lexScratch;
                if( captureValueUses )
                {
                    lexScratch.reserve( 1024 );
                }
                const auto buildLexForNewDefs = [ & ]( std::vector<RawDef>& defs, std::size_t firstNewDefIndex, const std::string& fileBytes )
                {
                    if( !captureValueUses )
                    {
                        return;
                    }
                    for( std::size_t defIndex = firstNewDefIndex; defIndex < defs.size(); ++defIndex )
                    {
                        buildDefLexStats( fileBytes, defs[ defIndex ].startByte, defs[ defIndex ].endByte, lexScratch, defs[ defIndex ].lex );
                    }
                };

                struct PendingParsedFile
                {
                    std::uint32_t   fileId = 0;
                    const LangEntry* le    = nullptr;
                    std::string     bytes;
                    TSTree*         tree   = nullptr;

                    PendingParsedFile( std::uint32_t fileIdIn, const LangEntry* leIn, std::string&& bytesIn, TSTree* treeIn )
                        : fileId( fileIdIn ), le( leIn ), bytes( std::move( bytesIn ) ), tree( treeIn )
                    {
                    }
                    PendingParsedFile( const PendingParsedFile& ) = delete;
                    PendingParsedFile& operator=( const PendingParsedFile& ) = delete;
                    PendingParsedFile( PendingParsedFile&& other ) noexcept
                        : fileId( other.fileId ), le( other.le ), bytes( std::move( other.bytes ) ), tree( other.tree )
                    {
                        other.tree = nullptr;
                    }
                    PendingParsedFile& operator=( PendingParsedFile&& other ) noexcept
                    {
                        if( this != &other )
                        {
                            if( tree != nullptr )
                            {
                                ts_tree_delete( tree );
                            }
                            fileId = other.fileId;
                            le     = other.le;
                            bytes  = std::move( other.bytes );
                            tree   = other.tree;
                            other.tree = nullptr;
                        }
                        return *this;
                    }
                    ~PendingParsedFile()
                    {
                        if( tree != nullptr )
                        {
                            ts_tree_delete( tree );
                        }
                    }
                };

                constexpr std::size_t kMaxPendingParsedFiles = 4;
                constexpr std::size_t kMaxPendingParsedBytes = 8u * 1024u * 1024u;
                std::vector<PendingParsedFile> pendingParsed;
                pendingParsed.reserve( kMaxPendingParsedFiles );
                std::size_t pendingParsedBytes = 0;
                const auto flushPendingParsed = [ & ]()
                {
                    if( pendingParsed.empty() )
                    {
                        return;
                    }

                    {
                        PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: flush pending parsed tags" );
                        waitForQueryPrewarm( &queryReadyGate );
                        for( PendingParsedFile& pending : pendingParsed )
                        {
                            if( pending.le == nullptr || pending.tree == nullptr )
                            {
                                continue;
                            }
                            const TSNode root = ts_tree_root_node( pending.tree );
                            const std::size_t firstNewDefIndex = tDefs[ t ].size();
                            captureTagsFacts( cursor, *pending.le, pending.fileId, pending.bytes, root, tDefs[ t ], tRefs[ t ] );
                            buildLexForNewDefs( tDefs[ t ], firstNewDefIndex, pending.bytes );   // B0.2: bytes still in memory
                            ts_tree_delete( pending.tree );
                            pending.tree = nullptr;
                        }
                    }
                    pendingParsed.clear();
                    pendingParsedBytes = 0;
                };

                std::string bytes;
                for( ;; )   // lock-free work-stealing: grab the next file via the atomic counter (balances the big-file tail)
                {
                    if( queryPrewarmReady.load( std::memory_order_acquire ) && !pendingParsed.empty() )
                    {
                        flushPendingParsed();
                    }

                    const std::size_t orderIndex = nextFile.fetch_add( 1, std::memory_order_relaxed );
                    if( orderIndex >= nfiles )
                    {
                        break;
                    }
                    const std::size_t fileId = parseOrder.empty() ? orderIndex : parseOrder[ orderIndex ];
                    // per-file try/catch: a throw (bad_alloc, filesystem_error, …) escaping a
                    // std::thread entry would std::terminate the whole process. Degrade per file,
                    // honouring the "never throws" contract (the worse-than-v1 parallel hazard).
                    try
                    {
                        const std::string& path = result.files[ fileId ];

                        const LangEntry* le = fileLang[ fileId ];
                        if( le == nullptr )
                        {
                            continue; // defensive (filtered in crawl)
                        }

                        // If the prewarm miss-detection pass already read+hashed this file, the hash
                        // is already in fileHash[fileId] — skip the re-read for the hash check.
                        // We still need `bytes` for actual parsing, so the fast path (cache hit) avoids readFile entirely.
                        std::uint64_t h = fileHash[ fileId ];
                        bool bytesLoaded = false;
                        if( h == 0 )
                        {
                            // Not pre-hashed: read the file now (first time we see it in the pool)
                            if( !readFile( path, bytes ) )
                            {
                                continue;
                            }
                            if( looksBinary( bytes ) )
                            {
                                continue;
                            }
                            if( le->ext == ".h" && looksObjC( bytes ) )
                            {
                                if( const LangEntry* objcLe = lookupLang( ".m" ) )
                                {
                                    le = objcLe;
                                }
                            }
                            if( needsCacheHash )
                            {
                                h = contentHash64( bytes );
                                fileHash[ fileId ] = h;
                                // A4-P7: capture (size,mtime) at hash time so saveCache can persist a stat-gate
                                // record for this file (cold run / new file / prewarm-skipped path).
                                const StatInfo si = statSizeMtime( path );
                                fileStatSize[ fileId ]  = si.sizeBytes >= 0 ? si.sizeBytes : (long long)bytes.size();
                                fileStatMtime[ fileId ] = si.mtimeNs;
                            }
                            bytesLoaded = true;
                        }

                        if( !cache.empty() )
                        {
                            FileFacts* hit = cacheHitFacts[ fileId ];
                            if( hit == nullptr )
                            {
                                FileFacts* candidate = cacheCandidateFacts[ fileId ];
                                if( candidate != nullptr && candidate->hash == h )
                                {
                                    hit = candidate;
                                }
                            }
                            if( hit != nullptr )   // unchanged → reuse cached facts, skip parse
                            {
                                fileHealth[ fileId ] = hit->health;   // §L1: health is a cached FACT, not a re-derivation
                                for( RawDef& d : hit->defs )
                                {
                                    d.fileId = std::uint32_t( fileId );
                                    tDefs[ t ].push_back( std::move( d ) );
                                }
                                for( RawRef& rr : hit->refs )
                                {
                                    rr.fileId = std::uint32_t( fileId );
                                    tRefs[ t ].push_back( std::move( rr ) );
                                }
                                for( Include& in : hit->incs )
                                {
                                    in.fileId = std::uint32_t( fileId );
                                    tIncs[ t ].push_back( std::move( in ) );
                                }
                                for( RawBind& b : hit->binds )
                                {
                                    b.fileId = std::uint32_t( fileId );
                                    tBinds[ t ].push_back( std::move( b ) );
                                }
                                for( BindingAlias& a : hit->ffis )
                                {
                                    a.fileId = std::uint32_t( fileId );
                                    tFfis[ t ].push_back( std::move( a ) );
                                }
                                for( RouteDef& rd : hit->routeDefs )        // B6.3
                                {
                                    rd.fileId = std::uint32_t( fileId );
                                    tRouteDefs[ t ].push_back( std::move( rd ) );
                                }
                                for( RawRouteUse& ru : hit->routeUses )     // B6.3
                                {
                                    ru.fileId = std::uint32_t( fileId );
                                    tRouteUses[ t ].push_back( std::move( ru ) );
                                }
                                continue;
                            }
                        }

                        // cache miss (new file or hash changed) → need to actually parse
                        dirty.store( true, std::memory_order_relaxed );
                        reparsedCount.fetch_add( 1, std::memory_order_relaxed );   // A1: drift-proportional observable

                        // ensure bytes are loaded (may have been pre-hashed without loading the body)
                        if( !bytesLoaded )
                        {
                            if( !readFile( path, bytes ) )
                            {
                                continue;
                            }
                            if( looksBinary( bytes ) )
                            {
                                continue;
                            }
                            if( le->ext == ".h" && looksObjC( bytes ) )
                            {
                                if( const LangEntry* objcLe = lookupLang( ".m" ) )
                                {
                                    le = objcLe;
                                }
                            }
                        }

                        // hostile/degenerate JSON guard — must run BEFORE the parse (that is the whole point);
                        // the skip is a degrade with a one-line stderr note, matching the house skip style.
                        if( le->lang == Lang::Json && jsonNestsTooDeep( bytes ) )
                        {
                            std::fprintf( stderr, "[ripwire] %s: json nesting > %u levels — treated as data, not config (skipped)\n",
                                          path.c_str(), kMaxJsonNestDepth );
                            continue;
                        }

                        // hostile/degenerate YAML guard — MEMORY-SAFETY load-bearing, not just a perf guard:
                        // tree-sitter-yaml's scanner serialize() corrupts memory past ~253 block indent levels
                        // (see kMaxYamlNestDepth in ingest.h; the vendored scanner also carries the bounds fix
                        // under third_party/patches/yaml/, so this is the FIRST of two independent layers).
                        // Same house skip style as the JSON guard above: refuse BEFORE the parse, one stderr line.
                        if( le->lang == Lang::Yaml && yamlNestsTooDeep( bytes ) )
                        {
                            std::fprintf( stderr, "[ripwire] %s: yaml nesting > %u levels — treated as data, not config (skipped)\n",
                                          path.c_str(), kMaxYamlNestDepth );
                            continue;
                        }

                        if( le->lang == Lang::Markdown )
                        {
                            // hostile/degenerate markdown guard — MEMORY-SAFETY load-bearing, the yaml pair's
                            // twin: tree-sitter-markdown's scanner serialize() memcpys its open-blocks stack
                            // with NO bounds check (OOB at ~255 nested blockquote/list markers; see
                            // kMaxMdBlockDepth in ingest.h). The vendored scanner also carries the clamp under
                            // third_party/patches/markdown/, so this is the FIRST of two independent layers.
                            if( mdNestsTooDeep( bytes ) )
                            {
                                std::fprintf( stderr, "[ripwire] %s: markdown blockquote/list nesting > %u levels — treated as data, not a doc (skipped)\n",
                                              path.c_str(), kMaxMdBlockDepth );
                                continue;
                            }
                            if( !prepareParserFor( pg.p, *le ) )
                            {
                                continue;
                            }
                            TreeGuard mdTree( parseTree( pg.p, bytes ) );
                            if( mdTree.get() == nullptr )
                            {
                                continue;
                            }
                            fileHealth[ fileId ] = measureFileHealth( ts_tree_root_node( mdTree.get() ), bytes );
                            const std::string stem = fs::path( path ).stem().string();
                            const std::size_t firstNewDefIndex = tDefs[ t ].size();
                            extractMarkdown( static_cast<std::uint32_t>( fileId ), bytes, stem, ts_tree_root_node( mdTree.get() ), tDefs[ t ], tRefs[ t ] );
                            buildLexForNewDefs( tDefs[ t ], firstNewDefIndex, bytes );   // B0.2: md sections/file nodes get stats too
                        }
                        else
                        {
                            if( !prepareParserFor( pg.p, *le ) )
                            {
                                continue;
                            }

                            TreeGuard tree( parseTree( pg.p, bytes ) );
                            if( tree.get() == nullptr )
                            {
                                continue;
                            }

                            const TSNode root = ts_tree_root_node( tree.get() );
                            fileHealth[ fileId ] = measureFileHealth( root, bytes );   // §L1 — before `bytes` can be moved below
                            captureSideFacts( *le, static_cast<std::uint32_t>( fileId ), bytes, root, tRefs[ t ], tIncs[ t ], tBinds[ t ], tFfis[ t ], tRouteDefs[ t ], tRouteUses[ t ], captureValueUses );

                            const bool canQueueParsed = !queryPrewarmReady.load( std::memory_order_acquire )
                                                     && pendingParsed.size() < kMaxPendingParsedFiles
                                                     && pendingParsedBytes + bytes.size() <= kMaxPendingParsedBytes;
                            if( canQueueParsed )
                            {
                                pendingParsedBytes += bytes.size();
                                pendingParsed.emplace_back( static_cast<std::uint32_t>( fileId ), le, std::move( bytes ), tree.release() );
                                continue;
                            }

                            {
                                PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: wait query prewarm" );
                                waitForQueryPrewarm( &queryReadyGate );
                            }
                            const std::size_t firstNewDefIndex = tDefs[ t ].size();
                            captureTagsFacts( cursor, *le, static_cast<std::uint32_t>( fileId ), bytes, root, tDefs[ t ], tRefs[ t ] );
                            buildLexForNewDefs( tDefs[ t ], firstNewDefIndex, bytes );   // B0.2: bytes still in memory
                        }
                    }
                    catch( ... )
                    {
                        DEGRADED_PATH_ALERT( "ingest: worker exception on a file — skipped" );
                    }
                }
                flushPendingParsed();
                ts_query_cursor_delete( cursor );
            } );
        }

        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: wait/install async" );

            for( std::thread& th : queryCompilePool )
            {
                th.join();
            }
            // Install compiled queries single-threaded (workers are still gated). Installing TRANSFERS
            // ownership to CompiledQueryCache, which frees whatever is still resident at process teardown
            // (N2). A652: on an in-process re-ingest (long-lived MCP server) the same grammar can already
            // own a cached query, and overwriting drops the only pointer to it — delete the displaced entry
            // here or it leaks one TSQuery per grammar per re-ingest (A4-F16).
            HashMap<const TSLanguage*, TSQuery*>& cache = compiledQueryCache();
            for( std::size_t i = 0; i < toCompile.size(); ++i )
            {
                const TSLanguage* grammar = toCompile[ i ]->grammar();
                if( auto it = cache.find( grammar ); it != cache.end() && it->second != nullptr && it->second != compiledQueries[ i ] )
                {
                    ts_query_delete( it->second );
                }
                cache[ grammar ] = compiledQueries[ i ];
            }
            // A4-F1: publish readiness UNDER queryPrewarmMutex, then notify. Workers wait via
            // cv.wait(lock, pred); a lock-free store+notify here can slip between a worker's predicate check
            // and its block → lost wakeup → the worker sleeps forever and the main th.join() hangs.
            {
                std::lock_guard<std::mutex> lk( queryPrewarmMutex );
                queryPrewarmReady.store( true, std::memory_order_release );
            }
        }
        queryPrewarmCv.notify_all();

        for( std::thread& th : pool )
        {
            th.join();
        }

        // merge per-thread results (cross-thread order is irrelevant — sorted below)
        std::size_t totDefs = 0, totRefs = 0, totIncs = 0, totBinds = 0, totFfis = 0, totRouteDefs = 0, totRouteUses = 0;
        for( unsigned t = 0; t < nthreads; ++t )
        {
            totDefs  += tDefs[ t ].size();
            totRefs  += tRefs[ t ].size();
            totIncs  += tIncs[ t ].size();
            totBinds += tBinds[ t ].size();
            totFfis  += tFfis[ t ].size();
            totRouteDefs += tRouteDefs[ t ].size();
            totRouteUses += tRouteUses[ t ].size();
        }
        rawDefs.reserve( totDefs );
        rawRefs.reserve( totRefs );
        rawIncs.reserve( totIncs );
        rawBinds.reserve( totBinds );
        rawFfis.reserve( totFfis );
        rawRouteDefs.reserve( totRouteDefs );
        rawRouteUses.reserve( totRouteUses );
        for( unsigned t = 0; t < nthreads; ++t )
        {
            for( RawDef& d : tDefs[t] )
            {
                rawDefs.push_back( std::move( d ) );
            }
            for( RawRef& r : tRefs[t] )
            {
                rawRefs.push_back( std::move( r ) );
            }
            for( Include& in : tIncs[t] )
            {
                rawIncs.push_back( std::move( in ) );
            }
            for( RawBind& b : tBinds[t] )
            {
                rawBinds.push_back( std::move( b ) );
            }
            for( BindingAlias& a : tFfis[t] )
            {
                rawFfis.push_back( std::move( a ) );
            }
            for( RouteDef& rd : tRouteDefs[t] )
            {
                rawRouteDefs.push_back( std::move( rd ) );
            }
            for( RawRouteUse& ru : tRouteUses[t] )
            {
                rawRouteUses.push_back( std::move( ru ) );
            }
        }

        // P1-15: the SAME drift count, carried out of the function instead of only to stderr. The MCP
        // server discloses it per incremental pass (`_reingest`), which it could not do from an env-gated
        // print. Read once here, after the pool join that orders every worker's increment.
        result.reparsedFiles = reparsedCount.load( std::memory_order_relaxed );

        // A1 (team-index) — drift-proportional observable: report how many files re-parsed vs reused,
        // ONLY when RIPWIRE_CACHE_STATS is set (off by default → no stdout/stderr perturbation on any
        // normal run or gate). A warm restore over a tree with N-of-F files changed prints reparsed=N,
        // making the "restore cost is proportional to drift, not tree size" claim executable.
        if( std::getenv( "RIPWIRE_CACHE_STATS" ) != nullptr )
        {
            const std::size_t reparsed = reparsedCount.load( std::memory_order_relaxed );
            std::fprintf( stderr, "ripwire: cache-stats reparsed=%zu reused=%zu files=%zu\n",
                          reparsed, ( nfiles >= reparsed ? nfiles - reparsed : std::size_t( 0 ) ), nfiles );
        }

        // Win 2: rewrite cache only when at least one file changed (dirty flag set by workers above).
        // Skips the ~11ms / 7 MB serialization+write on a no-change warm run.
        if( !cacheFile.empty() && dirty.load() )
        {
            saveCache( std::string( cacheFile ), rootDir, result.files, fileHash, fileStatSize, fileStatMtime, fileHealth, rawDefs, rawRefs, rawIncs, rawBinds, rawFfis, rawRouteDefs, rawRouteUses, captureValueUses );
        }
    }

    result.fileHealth = std::move( fileHealth );   // §L1: after saveCache, before the (unmeasured) doc pass

    // ── doc post-pass (P1-B): for every collected document file (notebook/html/csv/…), extract its text and
    //    record it as the docText override + add ONE whole-file Section node so the doc is rankable + recall-
    //    able. Runs OUTSIDE the parse cache (after saveCache, before id-assignment) and is a pure function of
    //    the bytes, so a WARM run reproduces it byte-for-byte — the determinism contract holds for docs too.
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: doc post-pass (extract notebooks/html/csv)" );

        // A4-P5 (PROFILE.md P3): parseDocFile re-extracts html/csv/ipynb from scratch every run and was the
        // ~81 ms serial main-thread tail of the warm path. It is a PURE function of the file bytes, so the
        // extractions are mutually independent → parallelize across the same worker pool shape used above,
        // then MERGE deterministically in ascending-fileId order. The merge (docText[fid] + rawDefs.push) is
        // single-threaded and order-fixed, so a WARM run reproduces the map byte-for-byte (determinism holds).

        // 1) collect the doc files (cheap sequential scan) — indices stay ascending, so the merge is ordered.
        std::vector<std::uint32_t> docIds;
        for( std::uint32_t fid = 0; fid < result.files.size(); ++fid )
        {
            if( docparse::isDocExtension( lowerExtensionOf( result.files[ fid ] ) ) )
            {
                docIds.push_back( fid );
            }
        }

        // 2) extract in parallel, storing each result at its OWN slot (no cross-thread sharing of a slot →
        //    order-independent). A per-doc `hasText` gate distinguishes "not extractable" (skip) from empty.
        const std::size_t ndocs = docIds.size();
        std::vector<std::string> docTextOut( ndocs );
        std::vector<char>        docHasText( ndocs, 0 );
        std::vector<RawDefLex>   docLex( ndocs );        // B0.2: per-doc Section stats (rich only), own slot per worker
        if( ndocs > 0 )
        {
            unsigned hwDoc = std::thread::hardware_concurrency();
            if( hwDoc == 0 )
            {
                hwDoc = 1;
            }
            const unsigned nDocThreads = static_cast<unsigned>( std::min<std::size_t>( hwDoc, ndocs ) );
            std::atomic<std::size_t> nextDoc{ 0 };
            std::vector<std::thread> docPool;
            docPool.reserve( nDocThreads );
            for( unsigned t = 0; t < nDocThreads; ++t )
            {
                docPool.emplace_back( [ & ]()
                {
                    // B0.2: doc Sections are indexed by their EXTRACTED text (docText override), so their
                    // stats come from that text — computed here, in the worker that owns the slot, so the
                    // stats path never needs docText at query time either. Pure function of the bytes.
                    HashMap<std::uint64_t, std::uint32_t> docLexScratch;
                    if( captureValueUses )
                    {
                        docLexScratch.reserve( 1024 );
                    }
                    for( ;; )
                    {
                        const std::size_t di = nextDoc.fetch_add( 1, std::memory_order_relaxed );
                        if( di >= ndocs )
                        {
                            break;
                        }
                        try   // per-file degrade — a throw escaping a worker thread would std::terminate
                        {
                            const std::uint32_t fid = docIds[ di ];
                            const std::string   ext = lowerExtensionOf( result.files[ fid ] );

                            std::string text = docTextViaBridgeCache( result.files[ fid ], ext, !cacheFile.empty(), fid );
                            if( !text.empty() )
                            {
                                if( captureValueUses )
                                { // whole-file Section span [0, len) — same span the RawDef gets below
                                    buildDefLexStats( text, 0, std::uint32_t( text.size() ), docLexScratch, docLex[ di ] );
                                }
                                docTextOut[ di ] = std::move( text );
                                docHasText[ di ] = 1;
                            }
                        }
                        catch( ... )
                        {
                            DEGRADED_PATH_ALERT( "ingest: doc post-pass worker exception on a file — skipped" );
                        }
                    }
                } );
            }
            for( std::thread& th : docPool )
            {
                th.join();
            }
        }

        // 3) deterministic merge in ascending-fileId order (docIds is already ascending).
        for( std::size_t di = 0; di < ndocs; ++di )
        {
            if( !docHasText[di] )
            { // not extractable (e.g. markitdown absent) → skip
                continue;
            }
            const std::uint32_t fid = docIds[ di ];
            const std::uint32_t len = static_cast<std::uint32_t>( docTextOut[ di ].size() );
            result.docText[ fid ] = std::move( docTextOut[ di ] );

            // whole-file Section node (mirrors the markdown file-node). lang=Markdown ⇒ docs-only recall +
            // the Section down-weight; span [0,len) so the lexical scorer indexes the whole extracted body.
            RawDef d;
            d.fileId    = fid;
            d.line      = 1;
            d.startByte = 0;
            d.endByte   = len;
            d.kind      = SymKind::Section;
            d.lang      = Lang::Markdown;
            d.name      = fs::path( result.files[ fid ] ).stem().string();
            d.lex       = std::move( docLex[ di ] );   // B0.2: stats over the extracted text (empty on lean runs)
            rawDefs.push_back( std::move( d ) );
        }
    }

    PROFILE_SCOPE_DESCRIBE( "ingest: build model (dedup + symbols/refs)" );

    // 3a) dedup definitions: some grammars' tags patterns overlap (Go: type_spec + the
    //     struct/interface specializations both fire; Rust: a fn inside an impl matches both
    //     the method and the function pattern). Two matches with the same (fileId, startByte,
    //     name) are ONE definition. Collapse them, keeping the most specific kind so the
    //     downstream graph sees one node per real symbol.
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: dedup defs" );

        auto specificity = []( SymKind k ) noexcept -> int
        {
            // higher = more specific / preferred when two matches collide
            switch( k )
            {
                case SymKind::Method:    return 5;
                case SymKind::Interface: return 4;
                case SymKind::Struct:    return 3;
                case SymKind::Class:     return 3;
                case SymKind::Function:  return 2;
                case SymKind::Var:       return 1;
                default:                 return 0;   // Other
            }
        };

        // identity = the declared identifier itself: (fileId, name-token start byte). Two tags
        // patterns that both name the same identifier are the same symbol regardless of which
        // wrapper node each captured.
        std::sort( rawDefs.begin(), rawDefs.end(),
                   [ &specificity ]( const RawDef& a, const RawDef& b ) noexcept
                   {
                       if( a.fileId != b.fileId )
                       {
                           return a.fileId < b.fileId;
                       }
                       if( a.nameByte != b.nameByte )
                       {
                           return a.nameByte < b.nameByte;
                       }
                       // same identity: most-specific kind first so unique() keeps it
                       const int specificityA = specificity( a.kind ), specificityB = specificity( b.kind );
                       if( specificityA != specificityB )
                       {
                           return specificityA > specificityB;
                       }
                       // same identity AND same specificity with DIFFERENT spans (Go: `type Foo struct{}` fires
                       // two capture rows): finish the total order on span — startByte ascending, endByte
                       // DESCENDING (widest span first) — so the unique() survivor is input-order independent.
                       if( a.startByte != b.startByte )
                       {
                           return a.startByte < b.startByte;
                       }
                       return a.endByte > b.endByte;
                   } );

        const auto sameIdentity = []( const RawDef& a, const RawDef& b ) noexcept
        {
            return a.fileId == b.fileId && a.nameByte == b.nameByte;
        };
        rawDefs.erase( std::unique( rawDefs.begin(), rawDefs.end(), sameIdentity ), rawDefs.end() );
    }

    // 3a-bis) same-FILE decl/def collapse (ObjC only) — the intra-file mirror of graph.h's cross-file byName
    //     collapse. In C++ a header decl and its .cpp def live in DIFFERENT files, so (fileId, nameByte)
    //     already keeps them as two legitimate nodes (one per file) and the graph.h byName pass merges them
    //     only for resolution. ObjC breaks that symmetry: the @interface decl and the @implementation def sit
    //     in the SAME .m/.mm file with different name-token bytes, so 3a leaves BOTH as nodes — every ObjC
    //     method (and the class itself) lands twice, doubling <s> nodes AND call edges (token waste + rank
    //     distortion in every ObjC file). Collapse it here, at the same "one node per real symbol" seam: within
    //     a file, if a (name, scope, kind) group has ANY body-present definition (bodyByte > startByte — the
    //     same predicate as graph.h's hasBody, made correct for ObjC by the body-child fallback above), drop
    //     that group's bodyLESS declarations and keep the definition(s). A group with NO def anywhere in the
    //     file (an @interface method with no @implementation, a protocol-only method) keeps its decls untouched
    //     — the exact "no def anywhere keeps decls" escape hatch graph.h uses.
    //
    //     GATED to ObjC defs deliberately. (1) SCOPE: gate (d) requires C++/Python output to stay byte-for-byte
    //     identical, and this bug is ObjC-only. (2) CORRECTNESS: the (fileId, name, scope, kind) key does NOT
    //     distinguish C++ OVERLOADS — a header with `svector() = default;` (bodyLESS) + `svector(const&){...}`
    //     (body) would wrongly drop the defaulted ctor as a "shadowed decl". ObjC selectors don't overload by
    //     signature within a class, so for ObjC the key uniquely pairs exactly one decl with one def. A `.mm`'s
    //     C++ functions carry Lang::ObjC too, but a C++ overload set inside a .mm is out of this fixture's scope
    //     and the same key limitation applies — so we restrict to the observed ObjC node shapes by language and
    //     rely on the byte-identical + langcheck gates. Never manufactures a symbol the tags query didn't capture.
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: objc decl-def collapse" );

        const auto hasBody = []( const RawDef& d ) noexcept { return d.bodyByte > d.startByte; };

        // (fileId, name, scope, kind) → does the group contain at least one body-present ObjC def? one pass.
        // Only ObjC defs are keyed; non-ObjC defs are never grouped and always pass through unchanged.
        HashMap<std::string, bool> groupHasDef;
        groupHasDef.reserve( rawDefs.size() );
        std::string key;
        const auto makeKey = [ &key ]( const RawDef& d )
        {
            key.clear();
            key.append( std::to_string( d.fileId ) ).push_back( '\x1f' );
            key.append( d.name ).push_back( '\x1f' );
            key.append( d.scope ).push_back( '\x1f' );
            key.push_back( char( '0' + int( d.kind ) ) );
            return std::string_view( key );
        };
        for( const RawDef& d : rawDefs )
        {
            if( d.lang != Lang::ObjC )
            {
                continue; // C++/Python/… never participate (SCOPE + overload-safety)
            }
            const std::string_view k = makeKey( d );
            const auto [ it, inserted ] = groupHasDef.try_emplace( std::string( k ), hasBody( d ) );
            if( !inserted && hasBody( d ) )
            {
                it->second = true;
            }
        }

        // keep a def group's DEFS only; keep a decl-only group whole (escape hatch). Stable: preserves order.
        std::vector<RawDef> kept;
        kept.reserve( rawDefs.size() );
        for( RawDef& d : rawDefs )
        {
            if( d.lang == Lang::ObjC )                                // only ObjC symbols are eligible to be dropped
            {
                const auto it = groupHasDef.find( std::string( makeKey( d ) ) );
                const bool groupDef = ( it != groupHasDef.end() ) && it->second;
                if( groupDef && !hasBody( d ) )
                {
                    continue; // a decl shadowed by a same-file ObjC def → drop
                }
            }
            kept.push_back( std::move( d ) );
        }
        rawDefs = std::move( kept );
    }

    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: assign symbols" );

        // 3b) assign Symbol ids in (fileId, line, name) order — deterministic (model.h)
        std::sort( rawDefs.begin(), rawDefs.end(),
                   []( const RawDef& a, const RawDef& b ) noexcept
                   {
                       if( a.fileId != b.fileId )
                       {
                           return a.fileId < b.fileId;
                       }
                       if( a.line != b.line )
                       {
                           return a.line < b.line;
                       }
                       if( a.name != b.name )
                       {
                           return a.name < b.name;
                       }
                       return a.startByte < b.startByte;   // stable last-resort tiebreak
                   } );

        result.symbols.reserve( rawDefs.size() );
        for( std::uint32_t i = 0; i < rawDefs.size(); ++i )
        {
            const RawDef& d = rawDefs[ i ];
            Symbol s;
            s.id     = i;
            s.kind   = d.kind;
            s.lang   = d.lang;
            s.fileId = d.fileId;
            s.line   = d.line;
            s.sigStartByte = d.startByte;
            s.sigEndByte   = ( d.bodyByte > d.startByte ) ? d.bodyByte : d.endByte;
            s.endByte      = d.endByte;
            s.cx           = d.cx;
            s.ccx          = d.ccx;
            s.loc          = d.loc;      // Q4: physical line span
            s.locals       = d.locals;   // Phase 1: local-decl floor count (C/C++ only; model.h localsCountedLang)
            s.ppAlt        = d.ppAlt;    // ppalt disclosure: preproc alternative branches in the body (model.h)
            s.params       = d.params;   // Q4: parameter count (fns/methods)
            s.arityExact   = d.arityExact;   // B2.2: params is a fixed call-comparable arity
            s.testScope    = d.testScope;    // L8: an in-file test convention encloses this def
            s.maxNest      = d.maxNest;  // Q4: max control nesting (fns/methods)
            s.humps        = d.humps;   // nesting profile: regions reaching quality::kNestBar (model.h)
            s.deepLoc      = d.deepLoc; // nesting profile: lines inside them, a FLOOR (model.h)
            s.ev           = d.ev;      // essential complexity, a FLOOR (model.h; 0 outside evCountedLang)
            s.evWhy        = d.evWhy;   // per-tag contributing-jump counts (model.h kEvWhyTagTable order)
            s.name   = d.name;
            s.scope  = d.scope;
            result.symbols.push_back( std::move( s ) );
        }

        // B0.1/B0.2 (rich ingests only): flatten the per-def stats into the per-symbol CSR (rawDefs is
        // aligned 1:1 with result.symbols after the sort above) and derive the per-FILE pre-filter
        // signatures from the same hashes — the B0.1 Bloom is a pure function of the persisted postings,
        // so it costs the cache format nothing and can never disagree with the stats it gates.
        if( captureValueUses )
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/build-model: lex stats CSR + file signatures (B0)" );

            const std::size_t symbolCount = result.symbols.size();
            std::size_t       pairCount   = 0;
            for( const RawDef& d : rawDefs )
            {
                pairCount += d.lex.tokenHashes.size();
            }

            result.hasLexStats = true;
            result.lexDocBodyDl.resize( symbolCount );
            result.lexTokenRowOffsets.resize( symbolCount + 1 );
            result.lexTokenHashes.reserve( pairCount );
            result.lexTokenTfs.reserve( pairCount );
            result.lexFileSig.assign( result.files.size() * kLexFileSigWords, 0 );

            result.lexTokenRowOffsets[ 0 ] = 0;
            for( std::size_t i = 0; i < symbolCount; ++i )
            {
                const RawDefLex& lx = rawDefs[ i ].lex;
                result.lexDocBodyDl[ i ] = lx.dlWeighted;
                result.lexTokenHashes.insert( result.lexTokenHashes.end(), lx.tokenHashes.begin(), lx.tokenHashes.end() );
                result.lexTokenTfs.insert( result.lexTokenTfs.end(), lx.tokenTfs.begin(), lx.tokenTfs.end() );
                result.lexTokenRowOffsets[ i + 1 ] = std::uint32_t( result.lexTokenHashes.size() );

                const std::uint32_t fileId = rawDefs[ i ].fileId;
                if( fileId < result.files.size() )
                {
                    std::uint64_t* const sig = result.lexFileSig.data() + std::size_t( fileId ) * kLexFileSigWords;
                    for( const std::uint64_t hash : lx.tokenHashes )
                    {
                        sig[lexSigWord( hash )] |= lexSigBit( hash );
                    }
                }
            }
        }
    }

    // 4) attribute each reference to its enclosing definition (innermost span containing it).
    //    Per file: the enclosing def is the one with the latest startByte <= ref.startByte
    //    whose endByte > ref.startByte. We index defs by file via a sorted view.
    struct DefSpan
    {
        std::uint32_t startByte;
        std::uint32_t endByte;
        NodeId        id;
    };
    // group def spans by fileId in one flat array (rawDefs aligned 1:1 with result.symbols after the sort above).
    // The previous vector<vector<...>> shape allocated twice per file; offsets keep the same per-file ranges with
    // contiguous storage, which matters on C++ repos with many small headers.
    std::vector<std::size_t> fileSpanStart;
    std::vector<DefSpan>     defSpans;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: def-span index" );

        fileSpanStart.assign( result.files.size() + 1, 0 );
        for( const RawDef& d : rawDefs )
        {
            ++fileSpanStart[ d.fileId + 1 ];
        }
        for( std::size_t fileId = 1; fileId < fileSpanStart.size(); ++fileId )
        {
            fileSpanStart[ fileId ] += fileSpanStart[ fileId - 1 ];
        }

        defSpans.resize( rawDefs.size() );
        std::vector<std::size_t> fileSpanWrite = fileSpanStart;
        for( std::uint32_t i = 0; i < rawDefs.size(); ++i )
        {
            const std::size_t spanIndex = fileSpanWrite[ rawDefs[ i ].fileId ]++;
            defSpans[ spanIndex ] = { rawDefs[ i ].startByte, rawDefs[ i ].endByte, result.symbols[ i ].id };
        }

        for( std::size_t fileId = 0; fileId < result.files.size(); ++fileId )
        {
            const std::size_t begin = fileSpanStart[ fileId ];
            const std::size_t end   = fileSpanStart[ fileId + 1 ];
            // A4-F23a: startByte alone is not a total order — equal-start spans (a markdown file node and its
            // first-line heading both at byte 0) would get stdlib-dependent innermost attribution. Tie-break on
            // endByte DESCENDING (wider container first, so the sweep opens it before the nested span), then id
            // for totality → cross-platform byte-identical output.
            std::sort( defSpans.begin() + begin, defSpans.begin() + end,
                       []( const DefSpan& a, const DefSpan& b ) noexcept
                       {
                           if( a.startByte != b.startByte )
                           {
                               return a.startByte < b.startByte;
                           }
                           if( a.endByte != b.endByte )
                           {
                               return a.endByte > b.endByte;
                           }
                           return a.id < b.id;
                       } );
        }
    }

    // innermost enclosing def of a byte position: the container span with the LARGEST start ≤ pos whose end
    // is past pos (spans are start-sorted per file). Refs/bindings are consumed in deterministic
    // (fileId,startByte,...) order, so a single per-file sweep replaces one binary search per fact. The active
    // stack's back is the latest-start span still open, which is exactly the previous lookup's chosen container.
    struct DefSweep
    {
        const std::vector<DefSpan>&    spans;
        const std::vector<std::size_t>& fileStart;
        std::uint32_t                  currentFileId = std::numeric_limits<std::uint32_t>::max();
        std::size_t                    nextSpanIndex = 0;
        std::size_t                    endSpanIndex  = 0;
        std::vector<std::size_t>       activeSpanIndices;

        NodeId find( std::uint32_t fileId, std::uint32_t pos )
        {
            if( fileId != currentFileId )
            {
                currentFileId = fileId;
                nextSpanIndex = fileStart[ fileId ];
                endSpanIndex  = fileStart[ fileId + 1 ];
                activeSpanIndices.clear();
            }

            while( nextSpanIndex < endSpanIndex && spans[ nextSpanIndex ].startByte <= pos )
            {
                activeSpanIndices.push_back( nextSpanIndex++ );
            }
            while( !activeSpanIndices.empty() && spans[ activeSpanIndices.back() ].endByte <= pos )
            {
                activeSpanIndices.pop_back();
            }

            return activeSpanIndices.empty() ? kNoNode : spans[ activeSpanIndices.back() ].id;
        }
    };

    // references: emit in deterministic (fileId, startByte, name) order. A RawRef is FAT (5 std::strings ≈
    // 160 B), so we order a uint32 INDEX permutation instead of the objects themselves. Bucket by file first,
    // radix-sort each file's indices by the numeric startByte, then comparison-sort only equal-byte name ties.
    // Same ordering contract as the old comparator, but it moves the hot path onto byte histograms.
    std::vector<std::uint32_t> refOrder( rawRefs.size() );
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: sort ref index" );

        std::vector<std::size_t> refStartByFile( result.files.size() + 1, 0 );
        for( const RawRef& r : rawRefs )
        {
            ++refStartByFile[ r.fileId + 1 ];
        }
        for( std::size_t fileId = 1; fileId < refStartByFile.size(); ++fileId )
        {
            refStartByFile[ fileId ] += refStartByFile[ fileId - 1 ];
        }

        std::vector<std::size_t> refWriteByFile = refStartByFile;
        for( std::uint32_t i = 0; i < rawRefs.size(); ++i )
        {
            refOrder[ refWriteByFile[ rawRefs[ i ].fileId ]++ ] = i;
        }

        std::vector<std::uint32_t> refScratch( rawRefs.size() );
        // A4-F23b: (startByte,name) is NOT a total order — Python `class A(Foo)` captures `Foo` twice at one
        // byte with different roles (Extends + Read), so the stdlib sort's residual order was implementation-
        // dependent. Extend the key with role then isInherit for a total, cross-platform-stable ordering.
        const auto lessRefResidual = [ &rawRefs ]( const RawRef& a, const RawRef& b ) noexcept
        {
            if( a.name != b.name )
            {
                return a.name < b.name;
            }
            if( a.role != b.role )
            {
                return static_cast<std::uint8_t>( a.role ) < static_cast<std::uint8_t>( b.role );
            }
            return static_cast<int>( a.isInherit ) < static_cast<int>( b.isInherit );
        };
        const auto lessRefByByteName = [ &rawRefs, &lessRefResidual ]( std::uint32_t ia, std::uint32_t ib ) noexcept
        {
            const RawRef& a = rawRefs[ ia ];
            const RawRef& b = rawRefs[ ib ];
            if( a.startByte != b.startByte )
            {
                return a.startByte < b.startByte;
            }
            return lessRefResidual( a, b );
        };
        const auto lessRefByName = [ &rawRefs, &lessRefResidual ]( std::uint32_t ia, std::uint32_t ib ) noexcept
        {
            return lessRefResidual( rawRefs[ ia ], rawRefs[ ib ] );
        };
        const auto radixSortRefSegment = [ & ]( std::size_t begin, std::size_t end )
        {
            constexpr std::size_t kRadixThreshold = 64;
            const std::size_t count = end - begin;
            if( count < kRadixThreshold )
            {
                std::sort( refOrder.begin() + begin, refOrder.begin() + end, lessRefByByteName );
                return;
            }

            bool isAlreadySorted = true;
            for( std::size_t i = begin + 1; i < end; ++i )
            {
                if( lessRefByByteName( refOrder[ i ], refOrder[ i - 1 ] ) )
                {
                    isAlreadySorted = false;
                    break;
                }
            }
            if( isAlreadySorted )
            {
                return;
            }

            std::uint32_t* src = refOrder.data() + begin;
            std::uint32_t* dst = refScratch.data() + begin;
            bool inScratch = false;

            for( unsigned shift = 0; shift < 32; shift += 8 )
            {
                std::uint32_t hist[ 256 ] = {};
                for( std::size_t i = 0; i < count; ++i )
                {
                    ++hist[ ( rawRefs[ src[ i ] ].startByte >> shift ) & 0xffu ];
                }

                bool singleBucket = false;
                for( std::uint32_t h : hist )
                {
                    if( h == count ) { singleBucket = true; break; }
                }
                if( singleBucket )
                {
                    continue;
                }

                std::uint32_t offsets[ 256 ];
                std::uint32_t sum = 0;
                for( std::size_t i = 0; i < 256; ++i )
                {
                    offsets[ i ] = sum;
                    sum += hist[ i ];
                }
                for( std::size_t i = 0; i < count; ++i )
                {
                    const std::uint32_t idx = src[ i ];
                    const std::uint32_t bin = ( rawRefs[ idx ].startByte >> shift ) & 0xffu;
                    dst[ offsets[ bin ]++ ] = idx;
                }
                std::swap( src, dst );
                inScratch = !inScratch;
            }

            if( inScratch )
            {
                std::copy( src, src + count, refOrder.data() + begin );
            }

            std::size_t tieBegin = begin;
            while( tieBegin < end )
            {
                std::size_t tieEnd = tieBegin + 1;
                const std::uint32_t byte = rawRefs[ refOrder[ tieBegin ] ].startByte;
                while( tieEnd < end && rawRefs[ refOrder[ tieEnd ] ].startByte == byte )
                {
                    ++tieEnd;
                }
                if( tieEnd - tieBegin > 1 )
                {
                    std::sort( refOrder.begin() + tieBegin, refOrder.begin() + tieEnd, lessRefByName );
                }
                tieBegin = tieEnd;
            }
        };

        for( std::size_t fileId = 0; fileId < result.files.size(); ++fileId )
        {
            const std::size_t begin = refStartByFile[ fileId ];
            const std::size_t end   = refStartByFile[ fileId + 1 ];
            radixSortRefSegment( begin, end );
        }
    }

    // rawRefs is consumed here (never read again) → MOVE its 5 strings into each Reference instead of copying.
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: emit refs" );

        result.references.resize( rawRefs.size() );
        DefSweep refSweep{ defSpans, fileSpanStart };
        std::size_t outRefIndex = 0;
        for( std::uint32_t idx : refOrder )
        {
            RawRef& r = rawRefs[ idx ];
            Reference& ref = result.references[ outRefIndex++ ];
            ref.fileId      = r.fileId;
            ref.line        = r.line;        // ABS-3: 1-based use-site line for --uses p="file:line"
            ref.lang        = r.lang;
            ref.calleeName  = std::move( r.name );
            ref.qualifier   = std::move( r.qualifier );
            ref.role        = r.role;        // ABS-3 use-site role (call/read/write/import/extends)
            ref.isInherit   = r.isInherit;
            ref.isDocLink   = r.isDocLink;
            ref.isCompose   = r.isCompose;   // S5-E: HAS-A member-variable type edge — NEVER enters call graph
            ref.recv        = r.recv;        // P2-D receiver shape (this/self/var) for one-hop narrowing
            ref.recvVar     = std::move( r.recvVar );
            ref.argCount    = r.argCount;        // B2.2: call-site positional arg count (when countable)
            ref.argCountKnown = r.argCountKnown; // B2.2: whether argCount is reliable (no spread/splat)
            ref.fieldName   = std::move( r.fieldName );   // S5-E: the member variable name (e.g. "m_pool")
            ref.composeRel  = std::move( r.composeRel );  // S5-E: "creates" or "uses"
            ref.startByte   = r.startByte;                // shadow fix round: for the block-span containment test
            ref.fromSymbol  = refSweep.find( r.fileId, r.startByte );
        }
    }

    // P2-D Rule 2: attribute each local var→type binding to its enclosing def (same containment scan as refs),
    // in deterministic (file, byte, var) order. A binding whose position is file-scope (kNoNode) is kept too —
    // buildGraph keys on (fromSymbol, var), so a file-scope binding only ever matches a file-scope recvVar call.
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: sort+emit binds" );

        std::sort( rawBinds.begin(), rawBinds.end(),
                   []( const RawBind& a, const RawBind& b ) noexcept
                   {
                       if( a.fileId != b.fileId )
                       {
                           return a.fileId < b.fileId;
                       }
                       if( a.startByte != b.startByte )
                       {
                           return a.startByte < b.startByte;
                       }
                       if( a.var != b.var )
                       {
                           return a.var < b.var;
                       }
                       // L3: a decl can emit BOTH a Rule-2 type record and a fn record at one (file, byte, var) —
                       // kind+typeName make the order strict, so the merged-across-threads sort is a total order.
                       if( a.kind != b.kind )
                       {
                           return a.kind < b.kind;
                       }
                       return a.typeName < b.typeName;
                   } );
        result.bindings.resize( rawBinds.size() );
        DefSweep bindSweep{ defSpans, fileSpanStart };
        std::size_t outBindIndex = 0;
        for( RawBind& rb : rawBinds )   // rawBinds consumed here → move its 2 strings into the Binding
        {
            Binding& b = result.bindings[ outBindIndex++ ];
            b.fileId     = rb.fileId;
            b.kind       = rb.kind;
            b.spanStart  = rb.spanStart;   // shadow fix round: the declaring block's span rides through
            b.spanEnd    = rb.spanEnd;
            b.var        = std::move( rb.var );
            b.typeName   = std::move( rb.typeName );
            b.fromSymbol = bindSweep.find( rb.fileId, rb.startByte );
        }
    }

    result.includes = std::move( rawIncs );   // physical dependencies (#include / import), for --deps

    // A4-R5: FFI binding aliases in a deterministic total order (fileId, kind, aliasName, targetScope,
    // targetName) so buildGraph's alias tables are built identically warm-vs-cold, run-to-run.
    std::sort( rawFfis.begin(), rawFfis.end(),
               []( const BindingAlias& a, const BindingAlias& b ) noexcept
               {
                   if( a.fileId != b.fileId )
                   {
                       return a.fileId < b.fileId;
                   }
                   if( a.kind != b.kind )
                   {
                       return a.kind < b.kind;
                   }
                   if( a.aliasName != b.aliasName )
                   {
                       return a.aliasName < b.aliasName;
                   }
                   if( a.targetScope != b.targetScope )
                   {
                       return a.targetScope < b.targetScope;
                   }
                   return a.targetName < b.targetName;
               } );
    result.bindingAliases = std::move( rawFfis );

    // B6.3: HTTP-route DEFs need no byte-span attribution (their handler is resolved by NAME, in the
    // DEF's own file, by buildGraph) — just a deterministic total order.
    std::sort( rawRouteDefs.begin(), rawRouteDefs.end(),
               []( const RouteDef& a, const RouteDef& b ) noexcept
               {
                   if( a.fileId != b.fileId )
                   {
                       return a.fileId < b.fileId;
                   }
                   if( a.line != b.line )
                   {
                       return a.line < b.line;
                   }
                   if( a.method != b.method )
                   {
                       return a.method < b.method;
                   }
                   return a.path < b.path;
               } );
    result.routeDefs = std::move( rawRouteDefs );

    // B6.3: HTTP-route USEs attribute fromSymbol the same way refs/binds do above — byte-span containment
    // over the SAME defSpans/fileSpanStart sweep (a fresh DefSweep cursor; the previous ones are per-file
    // stateful and already exhausted).
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: sort+emit route uses" );

        std::sort( rawRouteUses.begin(), rawRouteUses.end(),
                   []( const RawRouteUse& a, const RawRouteUse& b ) noexcept
                   {
                       if( a.fileId != b.fileId )
                       {
                           return a.fileId < b.fileId;
                       }
                       if( a.startByte != b.startByte )
                       {
                           return a.startByte < b.startByte;
                       }
                       return a.path < b.path;
                   } );
        result.routeUses.resize( rawRouteUses.size() );
        DefSweep routeSweep{ defSpans, fileSpanStart };
        std::size_t outRouteIndex = 0;
        for( RawRouteUse& ru : rawRouteUses )   // rawRouteUses consumed here → move its string into the RouteUse
        {
            RouteUse& out = result.routeUses[ outRouteIndex++ ];
            out.fileId     = ru.fileId;
            out.line       = ru.line;
            out.method     = ru.method;
            out.path       = std::move( ru.path );
            out.fromSymbol = routeSweep.find( ru.fileId, ru.startByte );
        }
    }

    // macro-edges round: the corpus-wide role="macro" retag (model.h). AFTER the model is assembled and
    // AFTER saveCache (which stores the per-file truth, role=Call) — a #define added in one file must
    // re-judge every OTHER file's cached call sites on the next run, so the retag can never be persisted.
    retagMacroCallReferences( result );

    // r9 shadow suppression (model.h): a reference inside a function whose LOCAL declarations bind the same
    // name as a variable belongs to the local, not to any same-named indexed symbol — erase it here, the one
    // choke point BOTH consumers sit downstream of (--uses reads result.references; buildGraph resolves call
    // edges from them), so the false --uses rows and the false call edge die in the same pass. AFTER the
    // macro retag (role="macro" is preprocessor evidence and stays) and AFTER saveCache (per-file truth is
    // persisted unsuppressed; the collision gate depends on the whole corpus' symbols, so the judgment can
    // never be cached per-file — same reasoning as the retag above).
    suppressShadowedReferences( result );

    return result;
}

// text of a capture (first node with this index) in a match; false if absent / out of range.
inline bool captureText( const TSQueryMatch& m, std::uint32_t capIndex, std::string_view src, std::string& out )
{
    for( std::uint16_t i = 0; i < m.capture_count; ++i )
    {
        if( m.captures[i].index == capIndex )
        {
            const TSNode n = m.captures[i].node;
            const std::uint32_t a = ts_node_start_byte( n ), b = ts_node_end_byte( n );
            if( a <= b && b <= src.size() ) { out = std::string( src.substr( a, b - a ) ); return true; }
            return false;
        }
    }
    return false;
}

// evaluate a pattern's query predicates against a match — #eq? / #not-eq? (string/capture equality) and
// #match? / #not-match? (ECMAScript regex). ts_query never applies these itself; without this, #eq? is a no-op.
inline bool passesPredicates( const TSQuery* q, const TSQueryMatch& m, std::string_view src )
{
    std::uint32_t pc = 0;
    const TSQueryPredicateStep* steps = ts_query_predicates_for_pattern( q, m.pattern_index, &pc );
    const auto argText = [ & ]( const TSQueryPredicateStep& s, std::string& out ) -> bool
    {
        if( s.type == TSQueryPredicateStepTypeCapture )
        {
            return captureText( m, s.value_id, src, out );
        }
        if( s.type == TSQueryPredicateStepTypeString )
        {
            std::uint32_t l = 0;
            const char* v = ts_query_string_value_for_id( q, s.value_id, &l );
            out.assign( v, l );
            return true;
        }
        return false;
    };
    for( std::uint32_t i = 0; i < pc; )
    {
        std::vector<TSQueryPredicateStep> pr;
        for( ; i < pc && steps[i].type != TSQueryPredicateStepTypeDone; ++i )
        {
            pr.push_back( steps[i] );
        }
        ++i;                                                            // skip the Done step
        if( pr.size() < 3 || pr[0].type != TSQueryPredicateStepTypeString )
        {
            continue;
        }
        // TWO statements, deliberately. Written as ONE — `string_view( f( …, &nl ), nl )` — the length
        // argument `nl` and the call that WRITES it are two arguments of the SAME call, and the order in
        // which a call's arguments are evaluated is UNSPECIFIED. GCC on x86-64 evaluates them right-to-left,
        // so it read `nl` while it was still 0: `op` came out EMPTY, matched none of the operator names
        // below, and every #eq?/#not-eq?/#match?/#not-match? predicate was silently skipped (`ok` stays
        // true ⇒ nothing filtered). GCC on aarch64 and Clang everywhere evaluate left-to-right and happened
        // to get it right, which is why this only ever reddened on x86-64 Linux/gcc — measured 2026-08-02:
        // g++-13 -O0 AND -O2 on x86-64 print len=0, the same g++-13 on aarch64 and clang-18 on x86-64 print
        // len=6. Sequencing the write before the read IS the fix; do not re-inline these two lines.
        std::uint32_t nl     = 0;
        const char*   opText = ts_query_string_value_for_id( q, pr[0].value_id, &nl );
        if( opText == nullptr )
        {
            continue; // no operator name ⇒ can't evaluate ⇒ don't filter
        }
        const std::string_view op( opText, nl );
        std::string lhs, rhs;
        if( !argText( pr[1], lhs ) || !argText( pr[2], rhs ) )
        {
            continue; // can't evaluate → don't filter
        }
        bool ok = true;
        if( op == "eq?" )
        {
            ok = ( lhs == rhs );
        }
        else if( op == "not-eq?" )
        {
            ok = ( lhs != rhs );
        }
        else if( op == "match?" || op == "not-match?" )
        { try { const bool mm = std::regex_search( lhs, std::regex( rhs ) ); ok = ( op == "match?" ) ? mm : !mm; } catch( ... ) { ok = true; } }
        if( !ok )
        {
            return false;
        }
    }
    return true;
}

// ---- per-file newline-offset index → O(log n) 1-based line lookup (A4 perf) ----
// Replaces the per-capture "scan [0,startByte) counting '\n'" (byte-0 rescan, O(startByte) EACH match)
// with one O(fileBytes) pass + a binary search per capture. Byte-identical result:
//   line(b) = 1 + (# of '\n' at offset < b) = 1 + lower_bound(offsets, b) position.
// The pass itself rides rw::findByte (src/infra/fixedStr.h) — a NEON/SSE2 find-'\n' kernel that is EXACT, so the
// offsets are bit-identical to the byte-at-a-time loop this replaced and determinism is untouched. '\r' is
// not a line break here and never was. bench/bench_newline_ab.cpp races the two against libc memchr and
// asserts all three agree byte-for-byte before it reports a number; the kernel won at ~1.4x over memchr.
inline std::vector<std::uint32_t> buildNewlineOffsets( std::string_view src )
{
PROFILE_SCOPE_DESCRIBE( "strings: buildNewlineOffsets (byte scan for newline)" );
    std::vector<std::uint32_t> off;
    const char* const          begin = src.data();
    const char*                first = begin;
    const char* const          last  = begin + src.size();
    while( first < last )
    {
        first = rw::findByte( first, last, '\n' );   // NEON/SSE2 kernel, exact — same answer as the byte loop it replaced
        if( first == last )
        {
            break;
        }
        off.push_back( std::uint32_t( first - begin ) );
        ++first;
    }
    return off;
}
inline std::uint32_t lineAtByte( const std::vector<std::uint32_t>& nlOffsets, std::uint32_t bytePos ) noexcept
{
    return std::uint32_t( 1 + ( std::lower_bound( nlOffsets.begin(), nlOffsets.end(), bytePos ) - nlOffsets.begin() ) );
}

// One AstMatch row from one [startByte,endByte) span of one file. THE single place a match's snippet is
// cut: the 120-byte cap, the UTF-8 continuation-byte back-off that stops the cut splitting a codepoint,
// and the whitespace scrub that keeps the row on one line. Shared by the query walk's capture emitter and
// by the pattern walk — two callers producing byte-different snippets for the same span would be a
// difference no reader could explain, and a second copy of this is exactly the new-clone-of-reused-helper
// shape --quality-delta flags.
inline AstMatch makeAstMatch( std::uint32_t fileId, std::string_view bytes, const std::vector<std::uint32_t>& nlOffsets,
                              std::uint32_t a, std::uint32_t b, std::string tag )
{
    PROFILE_SCOPE_DESCRIBE( "strings: capture text substr + whitespace scrub" );
    std::size_t cutLen = std::min<std::size_t>( b - a, 120u );
    if( cutLen < b - a )
    {
        while( cutLen > 0 && ( static_cast<unsigned char>( bytes[a + cutLen] ) & 0xC0 ) == 0x80 )
        {
            --cutLen;
        }
    }
    std::string text( bytes.substr( a, cutLen ) );
    for( char& ch : text )
    {
        if( ch == '\n' || ch == '\r' || ch == '\t' )
        {
            ch = ' ';
        }
    }
    return AstMatch{ fileId, a, b, lineAtByte( nlOffsets, a ), std::move( tag ), std::move( text ) };
}

// ---- shared AST-query pass (--match / --lint) ----
// One compiled query, plus the group it answers for. Grouping is a property of the QUERY, not of the walk:
// a worker executes every query a file's grammar has and files the captures into that query's own bucket.
struct GroupedQuery
{
    TSQuery*      query = nullptr;
    std::string   tag;
    std::uint32_t groupIndex = 0;
};

// Every query one grammar has to answer, in BOTH shapes. `perSpec` is one compiled query per spec, the
// literal thing each spec asked for. `combined` is all of those specs' patterns compiled into ONE query.
//
// The difference is the number of TREE WALKS. ts_query_cursor_exec walks the subtree once per query, so
// forty-odd single-pattern queries walked every C++ file forty-odd times to ask forty-odd independent
// questions of the same nodes -- and the profile put 87% of --lint's whole cost inside that loop. A query
// holding forty patterns walks once and runs them off one shared automaton; each match's `pattern_index`
// says which spec answered, so nothing about the RESULT changes.
//
// Both shapes are kept: `combined` is what the workers run, `perSpec` is the fallback if the concatenated
// source does not compile (or does not report the pattern count its parts add up to), and it also owns the
// tag and group each pattern belongs to.
struct GrammarQueries
{
    std::vector<GroupedQuery>  perSpec;
    TSQuery*                   combined = nullptr;   // nullptr = degraded to one tree walk per spec
    std::vector<std::uint32_t> patternOwner;         // combined pattern index -> index into perSpec
};

// Compile every group's specs for ONE grammar, in both shapes GrammarQueries holds. Called once per
// grammar the corpus can reach, from its own thread: the language tables it reads are immutable and each
// call touches nothing but its own result.
GrammarQueries compileGrammarQueries( const TSLanguage* g, const std::vector<AstQueryGroup>& groups )
{
    GrammarQueries gqs;
    std::string    combinedSrc;
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )
    {
        if( groups[groupIndex].specs == nullptr )
        {
            continue;
        }
        for( const AstQuerySpec& spec : *groups[groupIndex].specs )
        {
            std::uint32_t off = 0;  TSQueryError err = TSQueryErrorNone;
            TSQuery*      q   = ts_query_new( g, spec.query.data(), static_cast<std::uint32_t>( spec.query.size() ), &off, &err );
            if( q == nullptr )
            {
                continue;   // this spec is not valid for this grammar -- a C++ query simply does not fire on Python
            }
            const std::uint32_t patterns = ts_query_pattern_count( q );
            for( std::uint32_t patternIndex = 0; patternIndex < patterns; ++patternIndex )
            {
                gqs.patternOwner.push_back( static_cast<std::uint32_t>( gqs.perSpec.size() ) );
            }
            gqs.perSpec.push_back( { q, spec.tag, static_cast<std::uint32_t>( groupIndex ) } );
            combinedSrc.append( spec.query );
            combinedSrc.push_back( '\n' );   // a spec may end in a `;` line comment; never let it swallow the next
        }
    }
    if( !gqs.perSpec.empty() )
    {
        std::uint32_t off = 0;  TSQueryError err = TSQueryErrorNone;
        TSQuery*      comb = ts_query_new( g, combinedSrc.data(), static_cast<std::uint32_t>( combinedSrc.size() ), &off, &err );
        if( comb != nullptr && ts_query_pattern_count( comb ) == static_cast<std::uint32_t>( gqs.patternOwner.size() ) )
        {
            gqs.combined = comb;
        }
        else
        {
            // Patterns that each compile alone are not GUARANTEED to compile together, and a pattern count that
            // does not add up would misattribute every tag. Either way the per-spec walks are still correct --
            // only slower -- so this degrades rather than fails.
            if( comb != nullptr )
            {
                ts_query_delete( comb );
            }
            DEGRADED_PATH_ALERT( "astQuery: combined per-grammar query did not compile - falling back to one tree walk per spec" );
        }
    }
    return gqs;
}

// octocode F3: the "compiled for no grammar" refusal (below) used to hand back the query verbatim and
// nothing else, so `(call_expresion)` — one deleted 's' away from the real `call_expression` — got no
// nearer a fix than staring at the S-expression. This is the hint: pull every token that LOOKS like a
// node-kind reference out of the failed query text, edit-distance each against the UNION of every linked
// grammar's own node-kind vocabulary (ts_language_symbol_count/name — the grammar's own runtime-exposed
// truth, never a hand-maintained list this tree would have to keep in sync), and report the closest.
//
// Candidate extraction is a plain text scan, not a second ts_query_new attempt: the query already failed to
// compile against EVERY linked grammar, so there is no successful parse to introspect. A node-kind token is
// an identifier immediately after `(` — `(call_expression ...)`, `(binary_expression left: (identifier))` —
// outside a quoted anonymous-token literal (`"+"`) and outside a `;` line comment; the bare wildcard `_`
// ("any node") is excluded, and predicates (`#eq?`) / field negation (`!decorator`) never start with an
// identifier char so they are excluded by construction, not by a special case. A FIELD name (`left:`) is
// never captured either — it precedes a `:`, never a `(`.
//
// Vocabulary: TSSymbolTypeRegular and TSSymbolTypeSupertype only — the two symbol kinds a query ever names
// bare. TSSymbolTypeAnonymous is a literal token (written as a quoted string, never a bare identifier) and
// TSSymbolTypeAuxiliary is grammar-internal machinery; suggesting either as "the kind you meant" would be
// a hint the reader could not type back into a query. Several extensions share one grammar object
// (.cpp/.cc/.cxx -> tree_sitter_cpp); each distinct TSLanguage* is walked once. When more than one grammar
// defines the same kind name, kLangTable's fixed row order decides which grammar the hint names — a pure
// function of the table, independent of HashMap iteration order.
//
// Deterministic across candidate tokens too: smaller edit distance wins, a tie breaks on the lexicographically
// smaller resulting KIND NAME — never on which candidate token or which grammar was tried first. Bandwidth
// cutoff matches didyoumean.h's own kMaxEditDistance (3): beyond that a "hint" is noise, not help, and the
// hint stays empty (the same honest "no plausible near-miss" contract as didYouMean()).
struct NodeKindHint { std::string kind; std::string grammar; };   // both empty ⇒ no candidate was close enough

static std::vector<std::string> extractCandidateNodeKinds( std::string_view query )
{
    std::vector<std::string> out;
    bool inString = false;
    for( std::size_t i = 0; i < query.size(); ++i )
    {
        const char c = query[i];
        if( inString )
        {
            if( c == '\\' ) { ++i; continue; }   // escape: skip the escaped byte, same rule astQueryShape uses
            if( c == '"' ) { inString = false; }
            continue;
        }
        if( c == '"' ) { inString = true; continue; }
        if( c == ';' )   // line comment: everything to end-of-line is inert
        {
            while( i + 1 < query.size() && query[i + 1] != '\n' ) { ++i; }
            continue;
        }
        if( c != '(' )
        {
            continue;
        }
        std::size_t j = i + 1;
        while( j < query.size() && std::isspace( static_cast<unsigned char>( query[j] ) ) )
        {
            ++j;
        }
        if( j >= query.size() || !( std::isalpha( static_cast<unsigned char>( query[j] ) ) || query[j] == '_' ) )
        {
            continue;   // "(#eq?" / "(!decorator" / "(\"literal\"" — none of these is a node-kind token
        }
        const std::size_t start = j;
        while( j < query.size() && ( std::isalnum( static_cast<unsigned char>( query[j] ) ) || query[j] == '_' ) )
        {
            ++j;
        }
        std::string tok( query.substr( start, j - start ) );
        if( tok != "_" && std::find( out.begin(), out.end(), tok ) == out.end() )
        {
            out.push_back( std::move( tok ) );
        }
    }
    return out;
}

static NodeKindHint nearestNodeKindHint( std::string_view query )
{
    NodeKindHint hint;
    const std::vector<std::string> candidates = extractCandidateNodeKinds( query );
    if( candidates.empty() )
    {
        return hint;   // nothing that even looks like a node-kind token (e.g. a bare syntax error)
    }

    // The union of every linked grammar's own vocabulary, first-grammar-in-table-order wins per name.
    HashMap<std::string_view, std::string_view> kindGrammar;   // node-kind name -> owning grammar's display name
    kindGrammar.reserve( 8192 );
    std::vector<const TSLanguage*> tried;
    for( const LangEntry& le : kLangTable )
    {
        if( le.grammar == nullptr || le.querySub.empty() )
        {
            continue;   // no grammar (markdown) or nothing to attribute a --match hit against
        }
        const TSLanguage* g = le.grammar();
        if( std::find( tried.begin(), tried.end(), g ) != tried.end() )
        {
            continue;   // several extensions share one grammar object
        }
        tried.push_back( g );
        const std::uint32_t symCount = ts_language_symbol_count( g );
        for( std::uint32_t s = 0; s < symCount; ++s )
        {
            const TSSymbolType ty = ts_language_symbol_type( g, static_cast<TSSymbol>( s ) );
            if( ty != TSSymbolTypeRegular && ty != TSSymbolTypeSupertype )
            {
                continue;
            }
            const char* nm = ts_language_symbol_name( g, static_cast<TSSymbol>( s ) );
            if( nm == nullptr || *nm == '\0' )
            {
                continue;
            }
            kindGrammar.try_emplace( std::string_view( nm ), le.querySub );   // first grammar in table order wins
        }
    }
    if( kindGrammar.empty() )
    {
        return hint;
    }

    constexpr int kMaxEditDistance = 3;   // same bandwidth as didYouMean()'s symbol-name cutoff
    int           bestDist = kMaxEditDistance + 1;
    for( const std::string& cand : candidates )
    {
        const std::string_view nearest = rw::nearestNameByEditDistance( kindGrammar.begin(), kindGrammar.end(), cand, kMaxEditDistance,
                                                                         []( const auto& kv ) -> std::string_view { return kv.first; } );
        if( nearest.empty() )
        {
            continue;
        }
        const int  dist   = rw::boundedEditDistance( nearest, cand, kMaxEditDistance );
        const bool better = hint.kind.empty() || dist < bestDist || ( dist == bestDist && std::string( nearest ) < hint.kind );
        if( better )
        {
            bestDist    = dist;
            hint.kind    = std::string( nearest );
            hint.grammar = std::string( kindGrammar.at( nearest ) );
        }
    }
    return hint;
}

// octocode F3: the refusal loop's own trailer, extracted so that loop's own branch count doesn't grow — a
// caller that asked for neither field pays one pointer-compare and returns, same as before this existed.
static void recordNodeKindHint( const AstQueryGroup& group, const std::string& query )
{
    if( group.nearestKindOut == nullptr && group.nearestGrammarOut == nullptr )
    {
        return;
    }
    const NodeKindHint hint = nearestNodeKindHint( query );
    if( group.nearestKindOut != nullptr )
    {
        group.nearestKindOut->push_back( hint.kind );
    }
    if( group.nearestGrammarOut != nullptr )
    {
        group.nearestGrammarOut->push_back( hint.grammar );
    }
}

// Defined further down this file, next to the rest of the unreachable-code check's helpers, and
// forward-declared here so the shared file walk can drive it — the same split as
// ingest()/astQueryGrouped() already use above.
inline void ur_walkTree( TSNode root, std::uint32_t fileId, std::string_view src, const std::vector<std::uint32_t>& nlOffsets, std::vector<AstMatch>& hits );

// Drive every BUILT-IN WALK group over one already-parsed file, each into its own bucket. Called from the
// shared worker loop with the tree and newline index the query groups are about to use, which is the whole
// point: a walk group exists so a non-query check can stop re-reading and re-parsing the corpus for itself.
// R2: one file's worth of pattern matching, kept out of runWalkGroups' dispatch body for the same reason
// ur_walkTree is — the dispatcher stays a two-line switch over walk kinds, and each walk's own logic (and
// its own reasons to grow) lives next to itself.
inline void pat_walkTree( const pattern::PatternProgramSet* set, TSNode root, std::uint32_t fileId, std::string_view bytes,
                          const std::vector<std::uint32_t>& nlOffsets, const TSLanguage* grammar, std::vector<AstMatch>& hits,
                          std::atomic<std::uint64_t>* ellipsisCappedOut )
{
    if( set == nullptr )
    {
        return;   // a Pattern group with no programs is a caller bug, but never a crash
    }
    const pattern::PatternProgram* prog = set->forGrammar( grammar );
    if( prog == nullptr )
    {
        return;   // this file's grammar is one the pattern did not resolve for — unresolved_in= says so
    }
    std::vector<std::pair<std::uint32_t, std::uint32_t>> spans;
    pattern::MatchStats                                  stats;
    pattern::findMatches( *prog, root, bytes, spans, pattern::kMaxHits, stats );
    if( ellipsisCappedOut != nullptr && stats.ellipsisCappedCount != 0 )
    {
        // Relaxed is right: nothing else is published alongside it and the only reader runs after the pool
        // has joined. Addition is associative, so the total does not depend on which worker got here first.
        ellipsisCappedOut->fetch_add( stats.ellipsisCappedCount, std::memory_order_relaxed );
    }
    for( const auto& [a, b] : spans )
    {
        if( a < b && b <= bytes.size() )
        {
            hits.push_back( makeAstMatch( fileId, bytes, nlOffsets, a, b, std::string() ) );
        }
    }
}

// `grammar` is the language THIS file was parsed with: the pattern walk needs it because one --pattern
// string compiles to a different node shape per grammar, and the wrong program against the right tree
// would silently match nothing. The unreachable-code walk ignores it (its rule is kind-name based).
inline void runWalkGroups( const std::vector<AstQueryGroup>& groups, TSNode root, std::uint32_t fileId, std::string_view bytes,
                           const std::vector<std::uint32_t>& nlOffsets, const TSLanguage* grammar, std::vector<std::vector<AstMatch>>& perGroupHits )
{
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )
    {
        if( groups[groupIndex].walk == AstWalk::UnreachableCode )
        {
            ur_walkTree( root, fileId, bytes, nlOffsets, perGroupHits[groupIndex] );
        }
        else if( groups[groupIndex].walk == AstWalk::Pattern )
        {
            pat_walkTree( groups[groupIndex].patternPrograms, root, fileId, bytes, nlOffsets, grammar, perGroupHits[groupIndex],
                          groups[groupIndex].ellipsisCappedOut );
        }
    }
}

// §L3: grammar-applicability disclosure for AstQueryGroup::grammarsOut / eligibleFilesOut (see ingest.h for
// the field docs). A SEPARATE probe over the full kLangTable rather than a read of astQueryGrouped's own
// byGrammar table, because byGrammar only ever holds grammars the CORPUS is present for — exactly the
// information this exists to supply when the honest answer is "none of them" (a query that compiles fine
// for java/csharp/typescript but the corpus is Python-only). Cost is bounded by kLangTable's size (~37
// rows) per requesting group's specs, paid only when a caller asks — every existing --lint / --lint-rules
// call site leaves both fields null, so this is a no-op for them.
static void computeGrammarDisclosure( const IngestResult& ing, const std::vector<AstQueryGroup>& groups )
{
    for( const AstQueryGroup& grp : groups )
    {
        if( grp.grammarsOut == nullptr && grp.eligibleFilesOut == nullptr )
        {
            continue;
        }
        if( grp.specs == nullptr )
        {
            continue;   // a walk-only group has no query to probe grammars for
        }
        std::vector<const TSLanguage*> triedGrammars;   // dedup tracker: several extensions share one grammar
        std::vector<const TSLanguage*> okGrammars;       // grammars at least one spec in this group compiled against
        std::vector<std::string>       okNames;          // grammarsOut dedup: TWO distinct grammar OBJECTS can
                                                          // share one display NAME (tree_sitter_typescript and
                                                          // tree_sitter_tsx are both querySub "typescript"; the
                                                          // CUDA grammar reuses "cpp") — okGrammars stays one
                                                          // entry per compiling OBJECT (eligible_files needs
                                                          // every one of them), grammarsOut stays one per NAME.
        for( const LangEntry& le : kLangTable )
        {
            if( le.grammar == nullptr || le.querySub.empty() )
            {
                continue;   // no grammar (markdown) or no tags.scm surface to compile a --match query against
            }
            const TSLanguage* g = le.grammar();
            if( std::find( triedGrammars.begin(), triedGrammars.end(), g ) != triedGrammars.end() )
            {
                continue;
            }
            triedGrammars.push_back( g );
            bool compiledAny = false;
            for( const AstQuerySpec& spec : *grp.specs )
            {
                std::uint32_t off = 0; TSQueryError err = TSQueryErrorNone;
                if( TSQuery* probe = ts_query_new( g, spec.query.data(), static_cast<std::uint32_t>( spec.query.size() ), &off, &err ) )
                {
                    ts_query_delete( probe );
                    compiledAny = true;
                    break;
                }
            }
            if( compiledAny )
            {
                okGrammars.push_back( g );
                if( grp.grammarsOut != nullptr )
                {
                    const std::string name( le.querySub );
                    if( std::find( okNames.begin(), okNames.end(), name ) == okNames.end() )
                    {
                        okNames.push_back( name );
                        grp.grammarsOut->push_back( name );
                    }
                }
            }
        }
        if( grp.eligibleFilesOut != nullptr )
        {
            std::size_t eligible = 0;
            for( std::size_t fileId = 0; fileId < ing.files.size(); ++fileId )
            {
                const std::string ext = lowerExtensionOf( diskPath( ing, std::uint32_t( fileId ) ) );
                const LangEntry*  fle = lookupLang( ext );
                if( fle == nullptr || fle->grammar == nullptr )
                {
                    continue;
                }
                if( std::find( okGrammars.begin(), okGrammars.end(), fle->grammar() ) != okGrammars.end() )
                {
                    ++eligible;
                }
            }
            *grp.eligibleFilesOut = eligible;
        }
    }
}

std::vector<std::vector<AstMatch>> astQueryGrouped( const IngestResult& ing, const std::vector<AstQueryGroup>& groups,
                                                    std::vector<std::string>* keptBytesOut )
{
    std::vector<std::vector<AstMatch>> out( groups.size() );
    if( keptBytesOut != nullptr )
    {
        keptBytesOut->assign( ing.files.size(), std::string() );   // sized BEFORE the pool starts: workers only ever write distinct slots
    }
    bool                               anySpecs = false;
    bool                               anyWalk  = false;
    for( const AstQueryGroup& group : groups )
    {
        anySpecs = anySpecs || ( group.specs != nullptr && !group.specs->empty() );
        anyWalk  = anyWalk  || ( group.walk != AstWalk::None );
    }
    // A walk group is work even with no spec anywhere: it needs the parse, not a compiled query.
    if( ( !anySpecs && !anyWalk ) || ing.files.empty() )
    {
        return out;
    }

    // The grammars this CORPUS can actually reach. ts_query_new is not cheap -- compiling every spec
    // against every one of the sixteen linked grammars was the single largest serial cost of a `--lint`
    // run, and on a corpus holding one language fifteen sixteenths of it answered a question no file
    // could ask. A grammar with no file to run on contributes no match, so not compiling for it changes
    // nothing a caller can see -- except the "did not compile for ANY grammar" disclosure below, which is
    // a statement about the QUERY and not about the corpus, and is therefore still decided over the full
    // table.
    // The `.h` remap is deliberately conservative: whether a header is ObjC is a fact about its BYTES,
    // read per file inside the walk, so any `.h` at all admits the ObjC grammar here.
    std::vector<const TSLanguage*> presentGrammars;
    {
        bool anyCHeader = false;
        for( std::size_t fileId = 0; fileId < ing.files.size(); ++fileId )
        {
            const std::string ext = lowerExtensionOf( diskPath( ing, std::uint32_t( fileId ) ) );
            anyCHeader = anyCHeader || ext == ".h";
            const LangEntry* le = lookupLang( ext );
            if( le == nullptr || le->grammar == nullptr )
            {
                continue;
            }
            const TSLanguage* g = le->grammar();
            if( std::find( presentGrammars.begin(), presentGrammars.end(), g ) == presentGrammars.end() )
            {
                presentGrammars.push_back( g );
            }
        }
        const LangEntry* objcLe = anyCHeader ? lookupLang( ".m" ) : nullptr;
        if( objcLe != nullptr && objcLe->grammar != nullptr
            && std::find( presentGrammars.begin(), presentGrammars.end(), objcLe->grammar() ) == presentGrammars.end() )
        {
            presentGrammars.push_back( objcLe->grammar() );
        }
    }

    // Compile each spec against every DISTINCT grammar it is valid for (up front, single-threaded). Queries
    // are immutable after creation → shared read-only across workers; only the cursor is per-thread.
    // ONE GRAMMAR PER THREAD. Compiling is per-grammar independent work over read-only language tables --
    // the same assumption the ingest prewarm already makes when it launches ts_query_new off-thread -- and
    // it was the longest SERIAL stretch of a --lint run: the file walk that follows is fully parallel, so
    // a single-threaded compile set the floor on the whole verb. Results land in a vector indexed by the
    // deterministic presentGrammars order and are installed in that order afterwards, so no thread's
    // arrival time reaches the map, let alone the output.
    HashMap<const TSLanguage*, GrammarQueries> byGrammar;
    {
    PROFILE_SCOPE_DESCRIBE( "astQuery: compile queries per grammar" );
    std::vector<GrammarQueries> compiledPerGrammar( presentGrammars.size() );
    {
        unsigned compileHw = std::thread::hardware_concurrency();
        if( compileHw == 0 )
        {
            compileHw = 1;
        }
        const unsigned           compileThreads = static_cast<unsigned>( std::min<std::size_t>( compileHw, std::max<std::size_t>( presentGrammars.size(), std::size_t( 1 ) ) ) );
        std::atomic<std::size_t> nextGrammar{ 0 };
        std::vector<std::thread> compilers;  compilers.reserve( compileThreads );
        for( unsigned worker = 0; worker < compileThreads; ++worker )
        {
            compilers.emplace_back( [ & ]()
            {
                for( ;; )
                {
                    const std::size_t grammarIndex = nextGrammar.fetch_add( 1, std::memory_order_relaxed );
                    if( grammarIndex >= presentGrammars.size() )
                    {
                        break;
                    }
                    compiledPerGrammar[grammarIndex] = compileGrammarQueries( presentGrammars[grammarIndex], groups );
                }
            } );
        }
        for( std::thread& th : compilers )
        {
            th.join();
        }
    }
    for( std::size_t grammarIndex = 0; grammarIndex < presentGrammars.size(); ++grammarIndex )
    {
        if( !compiledPerGrammar[grammarIndex].perSpec.empty() )
        {
            byGrammar.emplace( presentGrammars[grammarIndex], std::move( compiledPerGrammar[grammarIndex] ) );
        }
    }
    }
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )   // warn once if a spec compiled for NO grammar (malformed query)
    {
        if( groups[groupIndex].specs == nullptr )
        {
            continue;
        }
        for( const AstQuerySpec& spec : *groups[groupIndex].specs )
        {
            bool any = false;
            for( const auto& [g, qs] : byGrammar )
            {
                for( const GroupedQuery& gq : qs.perSpec )
                {
                    if( gq.groupIndex == groupIndex && gq.tag == spec.tag )
                    {
                        any = true;
                        break;
                    }
                }
                if( any )
                {
                    break;
                }
            }
                // Nothing in the corpus could run it — but "did not compile for ANY grammar" is a claim about
                // the QUERY (§P0.1: a malformed query's zero must never be presented as a measurement), so it
                // is settled against the grammars this corpus does NOT hold before it is made. First success
                // wins; a C++ query on a Python-only tree is valid and stays silent, exactly as when every
                // grammar was compiled up front.
                for( const LangEntry& absent : kLangTable )
                {
                    if( any )
                    {
                        break;
                    }
                    if( absent.grammar == nullptr )
                    {
                        continue;
                    }
                    const TSLanguage* ag = absent.grammar();
                    if( byGrammar.find( ag ) != byGrammar.end() )
                    {
                        continue;   // already tried above, and it did not compile
                    }
                    std::uint32_t off = 0;  TSQueryError err = TSQueryErrorNone;
                    if( TSQuery* probe = ts_query_new( ag, spec.query.data(), static_cast<std::uint32_t>( spec.query.size() ), &off, &err ) )
                    {
                        ts_query_delete( probe );
                        any = true;
                    }
                }
                if( !any )
                {
                    std::fprintf( stderr, "ripwire: AST query did not compile for any grammar: %.*s\n", int( spec.query.size() ), spec.query.data() );
                    if( groups[groupIndex].uncompiledOut )
                    {
                        groups[groupIndex].uncompiledOut->push_back( spec.query );
                    }
                    recordNodeKindHint( groups[groupIndex], spec.query );   // octocode F3: opt-in, see above
                }
        }
    }

    // §L3: grammar-applicability disclosure, opt-in per group (grammarsOut / eligibleFilesOut) — a standalone
    // pass so the existing groups[] loops above stay exactly as complex as they were for every caller that
    // doesn't ask for this (--lint, --lint-rules leave both null; zero cost, zero shape change for them).
    computeGrammarDisclosure( ing, groups );

    const std::size_t nfiles = ing.files.size();
    unsigned hw = std::thread::hardware_concurrency();
    if( hw == 0 )
    {
        hw = 1;
    }
    const unsigned nthreads = static_cast<unsigned>( std::min<std::size_t>( hw, nfiles ) );

    // NO mid-flight global cap: a shared match counter raced by workers makes WHICH matches survive the
    // cap scheduling-dependent (nondeterministic --lint/--match on repos past maxMatches). Collect every
    // file's matches fully (per-file counts are naturally bounded and short-lived), sort deterministically,
    // THEN truncate to maxMatches — cap membership becomes a pure function of the input.
    std::vector<std::vector<std::vector<AstMatch>>> tHits( nthreads, std::vector<std::vector<AstMatch>>( groups.size() ) );
    std::atomic<std::size_t>                        nextSlot{ 0 };
    std::vector<std::thread>                        pool;  pool.reserve( nthreads );

    // BIGGEST FILE FIRST (longest-processing-time-first) -- the same work order, for the same reason, that
    // the ingest parse pool builds before it fans out. Handing files out in crawl order leaves the corpus's
    // largest translation unit (ripwire's own src/main.cpp: 653 KB, 40x the median) to be picked up near the
    // END of the queue, where it runs alone against an otherwise idle pool and sets the wall time by itself.
    // Sorting the queue by descending on-disk size puts the stragglers first and lets the small files fill in
    // behind them. WHICH thread parses WHICH file was never part of the output -- captures are bucketed per
    // group and sorted on a total key after the join -- so this changes scheduling and nothing else.
    std::vector<std::uint32_t> walkOrder( nfiles );
    std::iota( walkOrder.begin(), walkOrder.end(), std::uint32_t( 0 ) );
    {
        std::vector<std::uintmax_t> fileByteSize( nfiles, 0 );
        std::error_code             ec;
        for( std::size_t fileId = 0; fileId < nfiles; ++fileId )
        {
            ec.clear();
            fileByteSize[fileId] = fs::file_size( diskPath( ing, std::uint32_t( fileId ) ), ec );
            if( ec )
            {
                fileByteSize[fileId] = 0;
            }
        }
        std::stable_sort( walkOrder.begin(), walkOrder.end(),
                          [ & ]( std::uint32_t a, std::uint32_t b ) noexcept
                          {
                              if( fileByteSize[a] != fileByteSize[b] )
                              {
                                  return fileByteSize[a] > fileByteSize[b];
                              }
                              return a < b;
                          } );
    }

    for( unsigned t = 0; t < nthreads; ++t )
    {
        pool.emplace_back( [ &, t ]()
        {
            ParserGuard pg;
            if( pg.p == nullptr )
            {
                return;
            }
            TSQueryCursor* cur = ts_query_cursor_new();
            std::string    readBuf;   // worker-local scratch, reused across files unless the read is retained below
            for( ;; )
            {
                const std::size_t slot = nextSlot.fetch_add( 1, std::memory_order_relaxed );
                if( slot >= nfiles )
                {
                    break;
                }
                const std::size_t fileId = walkOrder[slot];
                try
                {
                    const std::string& path = diskPath( ing, std::uint32_t( fileId ) );   // multi-root: labeled ing.files → on-disk path
                    const std::string ext = lowerExtensionOf( path );
                    const LangEntry* le = lookupLang( ext );
                    if( le == nullptr )
                    {
                        continue;
                    }
                    if( !readFile( path, readBuf ) )
                    {
                        continue;
                    }
                    if( looksBinary( readBuf ) )
                    {
                        continue;
                    }
                    if( ext == ".h" && looksObjC( readBuf ) )
                    {
                        if( const LangEntry* objcLe = lookupLang( ".m" ) )
                        {
                            le = objcLe;
                        }
                    }

                    if( le->grammar == nullptr )
                    {
                        continue; // markdown — no grammar (would deref a null fn ptr)
                    }
                    const TSLanguage* g          = le->grammar();
                    const auto        it         = byGrammar.find( g );
                    const bool        hasQueries = ( it != byGrammar.end() && !it->second.perSpec.empty() );
                    if( !hasQueries && !anyWalk )
                    {
                        continue; // no spec applies to this grammar, and no built-in walk wants the tree either
                    }

                    // THE retention point, and the reason it is here rather than at any of the exits below:
                    // handing the read over BEFORE the tree is built means every path that follows works from
                    // the retained slot, so no exit can forget to keep it and no branch can keep it twice. When
                    // nothing is retaining, `bytes` binds the worker's own scratch and the loop reuses one
                    // buffer exactly as it always did. Markdown is already gone by here — a file with no
                    // grammar has no symbol a later pass could ask about.
                    std::string& bytes = ( keptBytesOut != nullptr ) ? ( ( *keptBytesOut )[fileId] = std::move( readBuf ) ) : readBuf;

                    if( !ts_parser_set_language( pg.p, g ) || !grammarAbiOk( g ) )
                    {
                        continue;
                    }
                    TSTree* tree = nullptr;
                    {
                    PROFILE_SCOPE_DESCRIBE( "astQuery/worker: tree-sitter parse" );
                    tree = ts_parser_parse_string( pg.p, nullptr, bytes.data(), static_cast<std::uint32_t>( bytes.size() ) );
                    }
                    if( !tree )
                    {
                        continue;
                    }
                    const TSNode root = ts_tree_root_node( tree );
                    const std::vector<std::uint32_t> nlOffsets = buildNewlineOffsets( bytes );   // one pass, then binary-search per capture

                    // Built-in walk groups first: they read the SAME tree and the SAME newline index the
                    // query groups below use, into their own per-group bucket, so nothing crosses over.
                    if( anyWalk )
                    {
                        PROFILE_SCOPE_DESCRIBE( "astQuery/worker: built-in tree walk" );
                        runWalkGroups( groups, root, std::uint32_t( fileId ), bytes, nlOffsets, g, tHits[t] );
                    }
                    if( !hasQueries )
                    {
                        ts_tree_delete( tree );
                        continue;   // walk-only file — no compiled spec for this grammar
                    }

                    PROFILE_SCOPE_DESCRIBE( "astQuery/worker: cursor exec + captures" );
                    // Every capture of one match, filed under the spec that owns the pattern. Shared by both
                    // execution shapes below so the ONE walk and the fallback walks cannot drift apart.
                    const auto emitCaptures = [ & ]( const TSQueryMatch& m, const GroupedQuery& owner )
                    {
                        for( std::uint16_t c = 0; c < m.capture_count; ++c )
                        {
                            const TSNode        n = m.captures[c].node;
                            const std::uint32_t a = ts_node_start_byte( n ), b = ts_node_end_byte( n );
                            if( a >= b || b > bytes.size() )
                            {
                                continue;
                            }
                            // The snippet cut (120 bytes, UTF-8-safe, whitespace-scrubbed) lives in
                            // makeAstMatch — the pattern walk emits rows through the same helper.
                            tHits[t][owner.groupIndex].push_back( makeAstMatch( std::uint32_t( fileId ), bytes, nlOffsets, a, b, owner.tag ) );
                        }
                    };

                    if( it->second.combined != nullptr )
                    {
                        TSQuery* const q = it->second.combined;   // ONE walk for every spec this grammar has
                        ts_query_cursor_exec( cur, q, root );
                        TSQueryMatch m;
                        while( ts_query_cursor_next_match( cur, &m ) )
                        {
                            if( !passesPredicates( q, m, bytes ) )
                            {
                                continue; // honour #eq? / #match? etc. — predicates are per PATTERN, so this reads the right ones
                            }
                            if( m.pattern_index >= it->second.patternOwner.size() )
                            {
                                continue;   // unreachable: patternOwner was verified against ts_query_pattern_count
                            }
                            emitCaptures( m, it->second.perSpec[ it->second.patternOwner[ m.pattern_index ] ] );
                        }
                    }
                    else
                    {
                        for( const GroupedQuery& gq : it->second.perSpec )
                        {
                            ts_query_cursor_exec( cur, gq.query, root );
                            TSQueryMatch m;
                            while( ts_query_cursor_next_match( cur, &m ) )
                            {
                                if( !passesPredicates( gq.query, m, bytes ) )
                                {
                                    continue; // honour #eq? / #match? etc.
                                }
                                emitCaptures( m, gq );
                            }
                        }
                    }
                    ts_tree_delete( tree );
                }
                catch( ... ) { /* per-file degrade — never abort the pass */ }
            }
            ts_query_cursor_delete( cur );
        } );
    }
    for( std::thread& th : pool )
    {
        th.join();
    }

    for( auto& [g, qs] : byGrammar )
    {
        for( GroupedQuery& gq : qs.perSpec )
        {
            ts_query_delete( gq.query );
        }
        if( qs.combined != nullptr )
        {
            ts_query_delete( qs.combined );
        }
    }

    // Per group, exactly what a standalone pass produced: merge the per-thread buckets in thread order,
    // sort on the total key, then spend each tag's own budget. Nothing crosses a group boundary.
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )
    {
        const bool hasSpecs = ( groups[groupIndex].specs != nullptr && !groups[groupIndex].specs->empty() );
        if( !hasSpecs && groups[groupIndex].walk == AstWalk::None )
        {
            continue;   // a caller may pass an inert slot to keep its group indices stable
        }
        std::vector<AstMatch> merged;
        std::size_t           tot = 0;
        for( const auto& perGroup : tHits )
        {
            tot += perGroup[groupIndex].size();
        }
        merged.reserve( tot );
        for( auto& perGroup : tHits )
        {
            for( auto& m : perGroup[groupIndex] )
            {
                merged.push_back( std::move( m ) );
            }
        }
        std::sort( merged.begin(), merged.end(), [ & ]( const AstMatch& x, const AstMatch& y ) // deterministic order
                   {
                       if( ing.files[x.fileId] != ing.files[y.fileId] )
                       {
                           return ing.files[x.fileId] < ing.files[y.fileId];
                       }
                       if( x.startByte != y.startByte )
                       {
                           return x.startByte < y.startByte;
                       }
                       if( x.endByte != y.endByte )
                       {
                           return x.endByte < y.endByte; // nested same-start captures (outer+inner call at one byte) need this or std::sort leaks thread arrival order
                       }
                       return x.tag < y.tag;                                                // equal keys ⇒ identical records (text derives from [start,end)) — order among them can't affect output
                   } );

        // A built-in walk group has no spec table to budget against, and emits ONE tag — so the per-tag
        // cap below degenerates to a single truncation of the sorted list, which is byte-for-byte the tail
        // the standalone spelling ran (collect all, sort on the same total key, resize to maxMatches).
        if( !hasSpecs )
        {
            if( merged.size() > groups[groupIndex].maxMatches )
            {
                merged.resize( groups[groupIndex].maxMatches );
            }
            out[groupIndex] = std::move( merged );
            continue;
        }

        // ── deterministic PER-SPEC cap (§P0.2), applied AFTER the sort so the survivors are a pure function of
        // the input. One POOLED budget let the noisiest query eat it: `(number_literal)` alone filled 5000, the
        // pool was path-sorted then cut, and every other rule was starved of the tail of the tree — `--lint`
        // reported goto=1 on a tree with two and do-while=0 on a tree with one. Each tag now spends its OWN
        // budget, which is exactly what a separate pass per spec would have produced (same collected set, same
        // (file, startByte) order within a tag) at the cost of ONE tree walk instead of N.
        const std::vector<AstQuerySpec>&    specs = *groups[groupIndex].specs;
        HashMap<std::string, std::uint32_t> tagSlot;   tagSlot.reserve( specs.size() * 2 );
        for( const AstQuerySpec& spec : specs )
        {
            const std::uint32_t nextSlot = static_cast<std::uint32_t>( tagSlot.size() );
            tagSlot.emplace( spec.tag, nextSlot );                          // duplicate tags share one budget, by design
        }

        std::vector<std::size_t> keptPerTag( tagSlot.size(), 0 );
        std::vector<AstMatch>    keep;   keep.reserve( merged.size() );
        for( AstMatch& m : merged )
        {
            const auto slotIt = tagSlot.find( m.tag );
            VERIFY( slotIt != tagSlot.end() );                              // every emitted tag came from a spec
            std::size_t& keptCount = keptPerTag[ slotIt->second ];
            if( keptCount >= groups[groupIndex].maxMatches )
            {
                continue; // this spec's own budget is spent — never another's
            }
            ++keptCount;
            keep.push_back( std::move( m ) );
        }
        out[groupIndex] = std::move( keep );
    }
    return out;
}

// R2: the grammars the pattern surface serves, derived from kLangTable so it can never disagree with the
// crawler about which extension is which language. One row per distinct grammar OBJECT — .ts and .tsx are
// two objects sharing the name "typescript", and .cu's CUDA grammar shares "cpp", and BOTH need their own
// compiled program even though the disclosure prints one name. Membership is decided by pattern.h's
// template table: a family with no wrap templates is a family this verb does not serve, stated in exactly
// one place. kLangTable order makes the result deterministic without a sort.
// The DISCLOSURE label for one grammar object, given the labels already handed out. querySub is the
// TEMPLATE key and is deliberately shared by dialects — the C++ tags.scm and the C++ pattern templates are
// what compile against tree_sitter_cuda, and tree_sitter_tsx borrows "typescript" the same way — but a
// shared disclosure NAME is how V-3 happened: `grammars="cpp"` asserted the C++ grammar resolved on a run
// where only the CUDA object had, while eligible_files=, keyed on the object, counted the .cpp file as
// unscanned. The first object to claim a querySub keeps it verbatim (so every single-dialect language's
// output is unchanged); a later object under the same key is qualified by the extension that introduced
// it — "cpp/cu", "typescript/tsx". DERIVED, not enumerated, so a dialect grammar added tomorrow cannot
// silently re-collide by being forgotten in a table.
static std::string patternGrammarLabel( std::string_view querySub, std::string_view ext, const std::vector<pattern::GrammarRow>& taken )
{
    bool claimed = false;
    for( const pattern::GrammarRow& r : taken )
    {
        claimed = claimed || ( r.label == querySub );
    }
    if( !claimed )
    {
        return std::string( querySub );
    }
    const std::string_view bare = ( !ext.empty() && ext.front() == '.' ) ? ext.substr( 1 ) : ext;
    return std::string( querySub ) + "/" + std::string( bare );
}

// --slice (lane/paper-slice): path -> grammar object, through the ONE crawl rule (lowerExtensionOf +
// kLangTable) -- see the ingest.h declaration for why this lives here and not in slice.h.
const ::TSLanguage* sliceGrammarForFile( std::string_view path )
{
    const LangEntry* le = lookupLang( lowerExtensionOf( path ) );
    if( le == nullptr || le->grammar == nullptr )
    {
        return nullptr;
    }
    return le->grammar();
}

std::vector<pattern::GrammarRow> supportedPatternGrammars()
{
    std::vector<pattern::GrammarRow> rows;
    rows.reserve( kLangTable.size() );
    for( const LangEntry& le : kLangTable )
    {
        if( le.grammar == nullptr || le.querySub.empty() || pattern::templatesFor( le.querySub ) == nullptr )
        {
            continue;
        }
        const TSLanguage* g = le.grammar();
        bool              seen = false;
        for( const pattern::GrammarRow& r : rows )
        {
            seen = seen || ( r.grammar == g );
        }
        if( !seen )
        {
            rows.push_back( { g, le.querySub, patternGrammarLabel( le.querySub, le.ext, rows ) } );
        }
    }
    return rows;
}

PatternFileCensus eligiblePatternFiles( const IngestResult& ing, const pattern::PatternProgramSet& set )
{
    const std::vector<pattern::GrammarRow> served = supportedPatternGrammars();
    PatternFileCensus                      census;
    for( std::size_t fileId = 0; fileId < ing.files.size(); ++fileId )
    {
        const std::string ext = lowerExtensionOf( diskPath( ing, std::uint32_t( fileId ) ) );
        const LangEntry*  le  = lookupLang( ext );
        if( le == nullptr || le->grammar == nullptr )
        {
            continue;
        }
        const TSLanguage* g = le->grammar();
        if( set.forGrammar( g ) != nullptr )
        {
            ++census.eligibleCount;
            continue;
        }
        // Not resolved for. It only counts as SKIPPED if this verb serves the grammar at all — a .rb or a
        // .json file is not "skipped", it is out of scope, and unsupported= already says so.
        for( const pattern::GrammarRow& r : served )
        {
            if( r.grammar == g )
            {
                ++census.skippedCount;
                break;
            }
        }
    }
    return census;
}

// The single-group spelling every standalone caller uses. One walk, one group — byte-identical to the
// hand-written pass this replaced, and there is exactly ONE file-walk implementation to keep correct.
std::vector<AstMatch> astQuery( const IngestResult& ing, const std::vector<AstQuerySpec>& specs, std::size_t maxMatches,
                                std::vector<std::string>* uncompiledOut )
{
    const std::vector<AstQueryGroup>   one{ { &specs, maxMatches, uncompiledOut } };
    std::vector<std::vector<AstMatch>> got = astQueryGrouped( ing, one );
    return std::move( got[0] );
}

// ---- R-H span tiers: the narrow single-file parse entry (declared in ingest.h — read its header first) --
//
// Node-type classification is a rule over the type NAME, not a per-grammar table, and that is deliberate:
// twelve grammars spell the same two concepts a dozen ways (comment / line_comment / block_comment /
// multiline_comment / documentation_comment / html_comment; string / string_literal / raw_string_literal /
// interpreted_string_literal / verbatim_string_literal / template_string / string_content), and a hand-kept
// per-grammar table is exactly the surface that goes stale the next time a grammar is vendored in. The two
// substring rules below cover every one of those spellings by construction; the exact-match table carries
// only the spellings that DON'T contain either word.
//
// Substring, not prefix/suffix: `raw_string_literal` and `documentation_comment` both need it. The exact
// table must stay exact — a substring rule for "str" would classify `struct_specifier` as a string.
inline constexpr std::string_view kSpanTierExactStringTypes[] = {
    "char_literal",         // C/C++/Rust
    "character_literal",    // Java/C#
    "line_str_text",        // Swift — the TEXT inside a "…" literal
    "raw_str_part",         // Swift raw strings
    "heredoc_body",         // Bash/Ruby
    "heredoc_content",      // Bash
};

// Code (the default) unless the node's own type says otherwise.
inline SpanTier spanTierOfNodeType( const char* type ) noexcept
{
    if( type == nullptr )
    {
        return SpanTier::Code;
    }
    if( std::strstr( type, "comment" ) != nullptr )
    {
        return SpanTier::Comment;
    }
    if( std::strstr( type, "string" ) != nullptr )
    {
        return SpanTier::String;
    }
    for( const std::string_view exact : kSpanTierExactStringTypes )
    {
        if( exact.compare( type ) == 0 )
        {
            return SpanTier::String;
        }
    }
    return SpanTier::Code;
}

// Collect one tree's OUTERMOST comment/string spans. Explicit stack, not recursion: a generated file can
// nest thousands of nodes deep (the YAML grammar's own 254-level indent bug is the standing reminder), and
// a query-time pass may not be the thing that overflows the stack. A classified node is recorded and NOT
// descended into, so `string_content` inside `string_literal` cannot produce a second, overlapping span.
static void collectSpanTiers( TSNode root, std::uint32_t byteCount, SpanTierMap& out )
{
    std::vector<TSNode> stack;
    stack.push_back( root );
    while( !stack.empty() )
    {
        const TSNode n = stack.back();
        stack.pop_back();
        const SpanTier    tier = spanTierOfNodeType( ts_node_type( n ) );
        const std::uint32_t a  = ts_node_start_byte( n ), b = ts_node_end_byte( n );
        if( tier != SpanTier::Code )
        {
            if( a < b && b <= byteCount )
            {
                out.startByte.push_back( a );
                out.endByte.push_back( b );
                out.tier.push_back( std::uint8_t( tier ) );
            }
            continue;   // do not descend: the span is already claimed, whole
        }
        // ALL children, not just the named ones — a comment is an `extra` in most grammars and several
        // spell it as an anonymous node, so a named-only walk silently misses exactly the tier this
        // function exists to find.
        const std::uint32_t childCount = ts_node_child_count( n );
        for( std::uint32_t c = childCount; c > 0; --c )
        {
            stack.push_back( ts_node_child( n, c - 1 ) );
        }
    }
    // The stack walk emits in DFS pop order, which is not byte order once a subtree is skipped; the
    // classify path binary-searches, so sort here once rather than making every lookup linear.
    std::vector<std::uint32_t> order( out.startByte.size() );
    std::iota( order.begin(), order.end(), std::uint32_t( 0 ) );
    std::stable_sort( order.begin(), order.end(), [ & ]( std::uint32_t x, std::uint32_t y ) noexcept
                      { return out.startByte[x] < out.startByte[y]; } );
    SpanTierMap sorted;
    sorted.startByte.reserve( order.size() );
    sorted.endByte.reserve( order.size() );
    sorted.tier.reserve( order.size() );
    for( const std::uint32_t index : order )
    {
        sorted.startByte.push_back( out.startByte[index] );
        sorted.endByte.push_back( out.endByte[index] );
        sorted.tier.push_back( out.tier[index] );
    }
    out.startByte = std::move( sorted.startByte );
    out.endByte   = std::move( sorted.endByte );
    out.tier      = std::move( sorted.tier );
}

SpanTierBatch spanTiersOfFiles( std::span<const std::string> diskPaths )
{
    SpanTierBatch batch;
    batch.perFile.resize( diskPaths.size() );
    if( diskPaths.empty() )
    {
        return batch;
    }

    // BIGGEST FILE FIRST, the same longest-processing-time-first order (and the same reason) as
    // astQueryGrouped's pool: hand the corpus's largest translation unit out first so it cannot strand an
    // otherwise-idle pool at the tail. E5 design condition 2 — this is the pattern it named, scoped to the
    // caller's file list instead of ing.files.
    const std::size_t          fileCount = diskPaths.size();
    std::vector<std::uint32_t> walkOrder( fileCount );
    std::iota( walkOrder.begin(), walkOrder.end(), std::uint32_t( 0 ) );
    {
        std::vector<std::uintmax_t> fileByteSize( fileCount, 0 );
        std::error_code             ec;
        for( std::size_t fileIndex = 0; fileIndex < fileCount; ++fileIndex )
        {
            ec.clear();
            fileByteSize[fileIndex] = fs::file_size( diskPaths[fileIndex], ec );
            if( ec )
            {
                fileByteSize[fileIndex] = 0;
            }
        }
        std::stable_sort( walkOrder.begin(), walkOrder.end(), [ & ]( std::uint32_t a, std::uint32_t b ) noexcept
                          {
                              if( fileByteSize[a] != fileByteSize[b] )
                              {
                                  return fileByteSize[a] > fileByteSize[b];
                              }
                              return a < b;
                          } );
    }

    unsigned hw = std::thread::hardware_concurrency();
    if( hw == 0 )
    {
        hw = 1;
    }
    const unsigned            threadCount = static_cast<unsigned>( std::min<std::size_t>( hw, fileCount ) );
    std::atomic<std::size_t>  nextSlot{ 0 };
    std::atomic<std::uint64_t> bytesParsed{ 0 };
    const auto                worker = [ & ]()
    {
        ParserGuard pg;
        if( pg.p == nullptr )
        {
            DEGRADED_PATH_ALERT( "span tiers: no tree-sitter parser — hits stay unclassified (never suppressed)" );
            return;
        }
        std::string bytes;
        try
        {
            for( ;; )
            {
                const std::size_t slot = nextSlot.fetch_add( 1, std::memory_order_relaxed );
                if( slot >= fileCount )
                {
                    break;
                }
                const std::size_t  fileIndex = walkOrder[slot];
                const std::string& path      = diskPaths[fileIndex];
                const std::string  ext       = lowerExtensionOf( path );
                const LangEntry*   le        = lookupLang( ext );
                if( le == nullptr || le->grammar == nullptr )
                {
                    continue;   // markdown and every unsupported extension: unclassifiable, and it stays that way
                }
                bytes.clear();
                if( !readFile( path, bytes ) || looksBinary( bytes ) )
                {
                    continue;
                }
                if( ext == ".h" && looksObjC( bytes ) )
                {
                    if( const LangEntry* objcLe = lookupLang( ".m" ) )
                    {
                        le = objcLe;   // the SAME reroute the crawl and the AST walk both apply
                    }
                }
                const TSLanguage* g = le->grammar();
                if( g == nullptr || !ts_parser_set_language( pg.p, g ) || !grammarAbiOk( g ) )
                {
                    continue;
                }
                TSTree* tree = nullptr;
                {
                    PROFILE_SCOPE_DESCRIBE( "spanTiers/worker: tree-sitter parse" );
                    tree = ts_parser_parse_string( pg.p, nullptr, bytes.data(), static_cast<std::uint32_t>( bytes.size() ) );
                }
                if( tree == nullptr )
                {
                    continue;
                }
                collectSpanTiers( ts_tree_root_node( tree ), std::uint32_t( bytes.size() ), batch.perFile[fileIndex] );
                batch.perFile[fileIndex].isParsed = true;   // slot owned by this worker alone
                ts_tree_delete( tree );
                bytesParsed.fetch_add( bytes.size(), std::memory_order_relaxed );
            }
        }
        catch( ... )   // a throw escaping a worker thread is std::terminate — degrade to unclassified instead
        {
            DEGRADED_PATH_ALERT( "span tiers: parse worker degraded (exception swallowed) — files left unclassified" );
        }
    };
    if( threadCount <= 1 )
    {
        worker();
    }
    else
    {
        // symmetric bare scope: the workers live exactly as long as the parse batch
        std::vector<std::thread> pool;
        pool.reserve( threadCount );
        for( unsigned t = 0; t < threadCount; ++t )
        {
            pool.emplace_back( worker );
        }
        for( std::thread& w : pool )
        {
            w.join();
        }
    }

    batch.bytesParsed = bytesParsed.load( std::memory_order_relaxed );
    for( const SpanTierMap& m : batch.perFile )
    {
        if( m.isParsed )
        {
            ++batch.parsedFileCount;
        }
        else
        {
            ++batch.unparsedFileCount;
        }
    }
    return batch;
}

// ---- unreachable-code detection (built-in --lint rule "unreachable-code") ----
//
// A GENUINE block node — a brace-delimited statement list whose direct children are the block's
// statements (NOT a switch body's case list, NOT a case body). Only these are scanned: within one,
// a statement's straight-line successor is a plain sibling, so "code after an unconditional exit is
// dead" holds syntactically. Case bodies (children of case_statement) are deliberately NOT blocks
// here, so `break; x();` inside a case is never flagged (conservative — no false positives).
inline bool ur_isBlockNode( const char* t ) noexcept
{
    return    std::strcmp( t, "compound_statement" ) == 0    // C / C++ / ObjC
           || std::strcmp( t, "block" ) == 0                 // Python / Java (and other {…} blocks)
           || std::strcmp( t, "statement_block" ) == 0;      // JS / TS
}

// An UNCONDITIONAL terminator statement: once seen at a block level, control cannot fall through to
// the next sibling. `goto` is intentionally EXCLUDED — a following statement can be a label target,
// so flagging it would be a false positive (the #1 trap this check must avoid). `return_statement`
// covers C-family + Python; `raise_statement` is Python's throw.
inline bool ur_isTerminator( const char* t ) noexcept
{
    return    std::strcmp( t, "return_statement" ) == 0
           || std::strcmp( t, "break_statement" ) == 0
           || std::strcmp( t, "continue_statement" ) == 0
           || std::strcmp( t, "throw_statement" ) == 0       // C++ / ObjC / Java / JS
           || std::strcmp( t, "raise_statement" ) == 0;      // Python
}

// A node that is NOT a real statement for reachability purposes — skip it when looking for the next
// sibling after a terminator (comments, and the block's own braces/colon punctuation). tree-sitter
// exposes comments as named siblings inside a block; a comment after `return` is not dead CODE.
inline bool ur_isSkippableSibling( TSNode n ) noexcept
{
    if( !ts_node_is_named( n ) )
    {
        return true; // '{', '}', ';', ':' punctuation tokens
    }
    const char* t = ts_node_type( n );
    return std::strcmp( t, "comment" ) == 0;
}

// A jump TARGET sibling: a label or a case makes the following statements reachable out-of-line, so
// the moment one appears after a terminator we STOP scanning this block (never flag past it). This
// is the second false-positive guard (belt-and-braces with excluding goto and not scanning case
// bodies): even a stray label inside a plain block halts the dead-code claim.
inline bool ur_isJumpTarget( const char* t ) noexcept
{
    return    std::strcmp( t, "labeled_statement" ) == 0     // C-family `lbl:` (goto/switch fallthrough target)
           || std::strcmp( t, "case_statement" ) == 0        // C-family switch case/default
           || std::strcmp( t, "case" ) == 0                  // grammar variants
           || std::strcmp( t, "default" ) == 0;
}

// Walk one file's AST (iterative frame-stack DFS — the cc_walk shape, NO recursion). For every block
// node, scan its direct children left-to-right; the FIRST non-skippable statement after a terminator
// (with no intervening jump target) is unreachable → one finding at that statement's start byte.
inline void ur_walkTree( TSNode root, std::uint32_t fileId, std::string_view src, const std::vector<std::uint32_t>& nlOffsets, std::vector<AstMatch>& hits )   // A4-F25: NOT noexcept — allocates (see cc_walk)
{
    struct UrFrame { TSNode node; std::uint16_t depth; };
    std::vector<UrFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { root, 0 } );
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );

    while( !stack.empty() )
    {
        const UrFrame frame = stack.back();
        stack.pop_back();
        if( frame.depth > 512 )
        {
            continue; // pathological-AST guard (file capped at 1 MB)
        }
        const TSNode        n          = frame.node;
        const std::uint16_t childDepth = static_cast<std::uint16_t>( frame.depth + 1 );
        const char*         t          = ts_node_type( n );
        collectChildren( n, cursor.cur, kids );              // one collection serves the block scan AND the descent

        // If this is a genuine block, scan its statement siblings for a post-terminator statement.
        if( ur_isBlockNode( t ) )
        {
            bool sawTerminator = false;
            for( const TSNode c : kids )
            {
                const char* ct = ts_node_type( c );

                if( sawTerminator )
                {
                    if( ur_isSkippableSibling( c ) )
                    {
                        continue; // comment / punctuation → not code, keep looking
                    }
                    if( ur_isJumpTarget( ct ) )
                    {
                        break; // label/case → reachable out-of-line → stop, no flag
                    }
                    // First real statement after an unconditional exit in this block → UNREACHABLE.
                    const std::uint32_t a = ts_node_start_byte( c ), b = ts_node_end_byte( c );
                    if( a < b && b <= src.size() )
                    {
                        const std::uint32_t line = lineAtByte( nlOffsets, a );
                        std::size_t cutLen = std::min<std::size_t>( b - a, 120u );
                        if( cutLen < b - a )
                        { // UTF-8-safe truncation (serialize.h/astQuery pattern)
                            while( cutLen > 0 && ( static_cast<unsigned char>( src[a + cutLen] ) & 0xC0 ) == 0x80 )
                            {
                                --cutLen;
                            }
                        }
                        std::string text( src.substr( a, cutLen ) );
                        for( char& ch : text )
                        {
                            if( ch == '\n' || ch == '\r' || ch == '\t' )
                            {
                                ch = ' ';
                            }
                        }
                        hits.push_back( { fileId, a, b, line, std::string( "unreachable-code" ), std::move( text ) } );
                    }
                    break;   // one finding per block — the first dead statement; the rest are consequential noise
                }
                else if( ur_isSkippableSibling( c ) )
                {
                    continue;                                       // comments/punctuation don't set the terminator flag
                }
                else if( ur_isTerminator( ct ) )
                {
                    sawTerminator = true;                           // arm: the NEXT real sibling is unreachable
                }
                // else: an ordinary statement — reachable; a terminator inside it (nested block/branch)
                //       is handled when we descend into that child's own block, never at THIS level.
            }
        }

        // Descend into every child (blocks nest — a function body holds inner blocks, and non-block
        // statements like if/for CONTAIN blocks we must still reach). Push in reverse for L-to-R order.
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[ i - 1 ], childDepth } );
        }
    }
}

// local-variable-indexing plan, Phase 2 (PLAN.md 2026-08-06 evening) — see ingest.h's own comment for the
// full contract. Definition lives HERE (outside the anonymous namespace above) purely for LINKAGE — it
// must be externally callable to satisfy ingest.h's declaration — while every helper it calls
// (ln_extractDeclaratorIdentifiers / ln_declaratorIdentifiers / ln_declDepth / ln_collectLocalDecls) stays
// anonymous-namespace-scoped next to cc_walk/complexityOf, which they mirror.
std::vector<LocalNameFact> collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )
{
    std::vector<LocalNameFact> out;
    if( !localsCountedLang( lang ) || defBytes.empty() )
    {
        return out;   // MVP scope (model.h::localsCountedLang) — degrade to empty, never assert on a caller mistake
    }
    const TSLanguage* grammar = ( lang == Lang::C ) ? tree_sitter_c() : tree_sitter_cpp();
    TSParser* parser = ts_parser_new();
    if( parser == nullptr )
    {
        return out;
    }
    ts_parser_set_language( parser, grammar );
    TSTree* tree = ts_parser_parse_string( parser, nullptr, defBytes.data(), std::uint32_t( defBytes.size() ) );
    if( tree == nullptr )
    {
        ts_parser_delete( parser );
        return out;
    }
    const TSNode root = ts_tree_root_node( tree );
    // the def parses as a single top-level function_definition inside a translation_unit — descend into
    // the translation_unit's children (bounded: one file-worth of def text, already size-capped upstream).
    const std::uint32_t n = ts_node_child_count( root );
    for( std::uint32_t i = 0; i < n; ++i )
    {
        ln_collectLocalDecls( ts_node_child( root, i ), ts_node_child( root, i ), 512, out, defStartLine, defBytes );
    }
    ts_tree_delete( tree );
    ts_parser_delete( parser );
    return out;
}

}   // namespace rw
