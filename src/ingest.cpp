// ingest.cpp — Phase 2 INGEST. Deterministic crawl + tree-sitter tags-query extraction.
//
// Pipeline:
//   crawl -> skip-filter -> SORT paths (byte order) -> per-file parse + ONE tags query ->
//   collect raw defs/refs -> assign Symbol ids in (file,line,name) order ->
//   attribute each Reference to its enclosing definition by byte-span containment.
//
// Single-threaded (v1). Never throws: every recoverable problem degrades + DISCLOSE.

#include "ingest.h"
#include "docparse.h"          // P1-B: non-code document ingest (notebooks/html/csv + markitdown bridge)
#include "arch.h"              // T5: relForHash — root-relative path key, reused for cache portability
#include "quality.h"           // A5: cacheDirLadder + sweepStaleCacheBlobsOnce — the cache-dir hygiene hook (saveCache)
#include "embedded_queries.h"  // configure-generated constexpr tags.scm table; no runtime source-tree dependency
#include "infra/nodekind.h"    // rw::kindIs - the inline node-kind compare the per-AST-node dispatch chains run on (OPTREMARKS F3)
#include "infra/fieldid.h"     // rw::fieldChild - the same defect one layer down: the field NAME resolved once per grammar, not per node
#include "infra/hashutil.h"    // sanitizer-clean modulo-2^64 FNV multiplication
#include "infra/namesplit.h"   // H4: stripTemplateArgs for the C++ qualified-call re-split (shared with tracelocus.h)
#include "infra/jsonesc.h"     // rw::shSingleQuote - the git ignore probe quotes its root the same way every other git popen does
#include "infra/fixedStr.h"    // rw::findByte — the NEON/SSE2 byte scan buildNewlineOffsets rides
#include "infra/ownedfile.h"   // rw::OwnedFile — readFile/readFilePrefix own their stream, so no return path skips the close
#include "infra/statclock.h"   // rw::saturatingNanoseconds — statSizeTimes' stat timestamps without signed overflow past 2262
#include "lexindex.h"          // B0.1/B0.2: shared subtoken state machine + per-def lexical statistics builder
#include "didyoumean.h"        // octocode F3: boundedEditDistance/nearestNameByEditDistance — the ONE near-miss
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings

                                // primitive, reused for a --match query's node-kind tokens (see nearestNodeKindHint)
#include "pattern.h"           // R2: the pattern surface's compiler + matcher — AstWalk::Pattern rides the shared file walk
#include "preprocdead.h"       // #62: the ONE literal `#if 0` rule (shared with slice.h) — dead call sites never become edges
#include "extentsuspect.h"     // extent honesty: the containment rules + the recovered/suspect bit vocabulary
#include "macroreparse.h"      // member-macro re-parse: the scanner, the offset-preserving blank, the adoption rule
#include "regexguard.h"        // #match?/#not-match?: the screen, the compile and the guarded match (ingest_astquery.h)
#include "infra/stackthreads.h"   // kCallerStackBytesFloor — #match? bounds a captured node's text the same way skillscan.h/--arch do (F-B4)

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
#include "infra/os.h"          // rw::os — stat for the (size,mtime) warm-run shortcut (A4-P7); open/pread/fstat for the cache blob's own read descriptor (v15); getpid for the per-process cache temp name
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
inline const char* const kPassName[] = { "captureIncludes", "captureFfi", "captureRoutes", "captureRustImpls", "captureBindings", "captureUses" };
static_assert( std::size( kPassName ) == kPassCount, "kPassName is indexed by PassId — one name per pass" );

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
        rw::emitTo( stderr, "\n[fuseprobe] files_with_a_parsed_tree={}\n", (unsigned long long) files );
        rw::emitTo( stderr, "[fuseprobe] {:<18} {:>13} {:>10} {:>8}\n", "pass", "visitor_calls", "files", "%files" );
        for( int p = 0; p < kPassCount; ++p )
        {
            const std::uint64_t f = gFiles[ p ].load();
            rw::emitTo( stderr, "[fuseprobe] {:<18} {:>13} {:>10} {:7.1f}%\n", kPassName[ p ], (unsigned long long) gNodes[ p ].load(),
                          (unsigned long long) f, files ? 100.0 * double( f ) / double( files ) : 0.0 );
        }
        const std::uint64_t astProxy = gNodesMaxPass.load();
        const std::uint64_t pops     = gStreamPops.load();
        rw::emitTo( stderr, "[fuseprobe] visitor_calls={}  ast_size_proxy(sum of per-file max pass)={}\n",
                      (unsigned long long) calls, (unsigned long long) astProxy );
        rw::emitTo( stderr, "[fuseprobe] STREAM_POPS={}  streams_per_node={:.2f}x  <-- the number fusion moves\n",
                      (unsigned long long) pops, astProxy ? double( pops ) / double( astProxy ) : 0.0 );
        rw::emitRaw( stderr, "[fuseprobe] files by number of passes that SAW a node:\n" );
        for( int k = 0; k <= kPassCount; ++k )
        {
            const std::uint64_t f = gHist[ k ].load();
            if( f != 0 )
            {
                rw::emitTo( stderr, "[fuseprobe]   {} pass{} : {:>10} files ({:5.1f}%)\n", k, k == 1 ? " " : "es", (unsigned long long) f,
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
    const TSLanguage* tree_sitter_elixir( void );
    const TSLanguage* tree_sitter_dart( void );
    const TSLanguage* tree_sitter_kotlin( void );
    const TSLanguage* tree_sitter_gdscript( void );
}

// ── the ingest-family sections (2026-08-29 split; ingest() phases followed 2026-08-30) ──────────────
// Each ingest_*.h below is a SECTION of this translation unit, not a library header: it reopens
// `namespace rw` AND the unnamed namespace inside it (one TU, one unnamed namespace), sees every
// #include and grammar entry point above, and is included exactly once, right here — the same
// mechanism as main.cpp's verb-family split, with RIPWIRE_INGEST_TU as the enforcement: any other
// includer is a compile error. Order matters — a later section may call an earlier one (the
// side-capture section calls the metrics section's complexityOf; everything may call the crawl
// section's language table; the four PHASE sections at the bottom — prewarm/parsepool/docpass/model,
// the named stages of ingest() itself — call into everything above them, and parsepool calls
// prewarm's install helper). The --match/--lint tail (ingest_astquery.h) is rw-level rather than
// unnamed and is included at the very END of this file, exactly where its content sat before the
// split.
#define RIPWIRE_INGEST_TU 1
#include "ingest_crawl.h"
#include "ingest_cache.h"
#include "ingest_metrics.h"
#include "ingest_relations.h"
#include "ingest_jsimports.h"
#include "ingest_docs.h"
#include "ingest_names.h"
#include "ingest_binds.h"
#include "ingest_elixir.h"
#include "ingest_sidecap.h"
#include "ingest_prewarm.h"
#include "ingest_parsepool.h"
#include "ingest_docpass.h"
#include "ingest_model.h"


namespace rw
{

// ---- index-identity disclosure (declared in ingest.h; contract and motivation there) ----
// Two thin exports out of this TU's unnamed namespace, so `--doctor` reads the SAME constants the cache
// guard is compiled against and runs the SAME openCacheFrame the read path runs. Nothing here parses, so
// both are safe to call from doctor's pre-ingest phase.
CacheIdentity cacheIdentity() noexcept
{
    CacheIdentity id;
    id.cacheVersion  = kCacheVersion;
    id.parserVerLean = parserVerFor( false );
    id.parserVerRich = parserVerFor( true );
    id.artifactArch  = kArtifactArch;
    return id;
}

const char* cacheArtifactVerdict( const std::string& path, bool captureValueUses )
{
    return cacheRejectName( inspectCacheArtifact( path, captureValueUses ) );
}

// Every prefix a cwd-spelled selector path can carry before its root-relative part (IngestResult::crawlRootPrefixes), in
// the order selectorRootTail tries them: the root as typed, the root relative to the cwd, the root's absolute spellings.
// $PWD is trusted only when its realpath IS getcwd, so a stale inherited PWD is ignored; a spelling that cannot be
// computed is left out, never guessed. Lexical throughout, apart from the one realpath of the root and of $PWD.
static std::vector<std::string> selectorRootPrefixes( const std::string& root )
{
    const auto normal = []( const std::filesystem::path& p ) {
        std::string s = p.lexically_normal().string();
        while( s.size() > 1 && s.back() == '/' ) { s.pop_back(); }
        return s;
    };
    std::vector<std::string> out;
    const auto add = [ & ]( std::string s ) {
        if( !s.empty() && std::find( out.begin(), out.end(), s ) == out.end() ) { out.push_back( std::move( s ) ); }
    };
    const std::filesystem::path rootPath( root.empty() ? std::string( "." ) : root );
    add( normal( rootPath ) );   // as typed: "test/fixture", "../repo", "/abs/repo", "."
    char cwdBuf[ PATH_MAX ];
    const char* const cwd = os::getcwd( cwdBuf, sizeof( cwdBuf ) );
    std::vector<std::string> cwds;   // the cwd's absolute spellings: logical first
    if( cwd != nullptr )
    {
        const char* const pwd = std::getenv( "PWD" );
        char pwdBuf[ PATH_MAX ];
        if( pwd != nullptr && pwd[0] == '/' && os::realpath( pwd, pwdBuf ) != nullptr && std::strcmp( pwdBuf, cwd ) == 0 )
        {
            cwds.push_back( normal( pwd ) );
        }
        cwds.push_back( normal( cwd ) );
    }
    std::vector<std::string> absolutes;
    if( rootPath.is_absolute() )
    {
        absolutes.push_back( normal( rootPath ) );
    }
    for( const std::string& c : cwds )
    {
        if( !rootPath.is_absolute() ) { absolutes.push_back( normal( std::filesystem::path( c ) / rootPath ) ); }
    }
    char realBuf[ PATH_MAX ];
    if( os::realpath( rootPath.c_str(), realBuf ) != nullptr )
    {
        absolutes.push_back( normal( realBuf ) );
    }
    for( const std::string& a : absolutes )
    {
        for( const std::string& c : cwds )
        {
            if( a == c )
            {
                add( "." );
            }
            else if( a.size() > c.size() + 1 && a.compare( 0, c.size(), c ) == 0 && ( c == "/" || a[ c.size() ] == '/' ) )
            {
                add( a.substr( c == "/" ? 1 : c.size() + 1 ) );   // the root relative to the cwd
            }
        }
    }
    for( std::string& a : absolutes )
    {
        add( std::move( a ) );
    }
    return out;
}

IngestResult ingest( const char* rootDir, const std::vector<std::string>& excludeSubstr, std::string_view cacheFile,
                     std::size_t maxFileBytes, bool captureValueUses, std::string_view excludeLabel, bool respectGitignore,
                     IngestLayout )
{
    PROFILE_SCOPE_DESCRIBE( "ingest: total (crawl + parse + model)" );
    // Cheap (a handful of bytes serialized twice) and runs once per invocation — catches a
    // writeDef/writeRef field added without updating kMinDefRecordBytesLean/kMinRefRecordBytes immediately
    // in any debug/ASan run, before it can silently weaken the cache record-count bounds check.
    verifyCacheRecordMinimaTripwire();

    IngestResult result;
    // A4-F17 said the root is a runtime-falsifiable input, and its CONTENT is: the crawl below degrades on a root that does
    // not exist or cannot be read. Its POINTER is not: every caller hands a std::string's c_str() or an argv entry behind an
    // argc check (main.cpp, mcpverbs.h, mcpindex.h, quality.h, dmm.h, mergescout.h, editpreview.h, tsprobe.cpp and the
    // test harnesses, traced 2026-09-19), so a null here is a caller bug, which EXPECTS blames.
    EXPECTS( rootDir != nullptr, "ingest: the caller passes a root path, never null" );

    // a zero/absurd ceiling would silently crawl nothing — clamp to the default (degrade, never trap).
    if( maxFileBytes == 0 )
    {
        maxFileBytes = kDefaultMaxFileBytes;
    }

    // 1) deterministic crawl -> sorted file list (this list IS result.files / the fileId space)
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: crawl (collectSources)" );
        auto [ crawledPaths, oversizeSkipped, taxonomySkips ] = collectSources( rootDir, excludeSubstr, maxFileBytes, excludeLabel, respectGitignore );
        result.files           = std::move( crawledPaths );
        // #228: record the root once, for rootRelPath (model.h). A directory crawl joins it onto every path; a
        // single-file root IS its one path, so the root-relative view anchors at that file's directory instead.
        const std::string_view rootArg( rootDir );
        result.crawlRoot = rootArg;
        if( result.files.size() == 1 && result.files.front() == rootArg )
        {
            const std::size_t lastSlash = rootArg.rfind( '/' );
            result.crawlRoot = ( lastSlash == std::string_view::npos ) ? std::string_view{} : rootArg.substr( 0, std::max<std::size_t>( lastSlash, 1 ) );
        }
        result.crawlRootPrefixes = selectorRootPrefixes( result.crawlRoot );   // #281: a selector typed from the cwd (graph.h selectorRootTail)
        result.skippedOversize = std::move( oversizeSkipped );
        result.crawlSkips      = std::move( taxonomySkips );   // §L1: excluded / unsupported-ext / unindexed exts
    }

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
    // scan.hash: pre-sized to nfiles here (0 = not yet hashed); the prewarm miss-detection pass
    // populates entries for files it reads; the parse pool fills the rest during normal processing.
    // A4-P7: cacheStats.blobWriteNs is the loaded blob's own mtime — the racy-rule reference for the
    // warm-run stat-gate. -1 (no/rejected cache) makes every stat check see a racy entry → always
    // read+hash (safe). v15: result.files is passed in because the blob's offset table lets the load
    // deserialise ONLY the records for the files THIS crawl asked for — a wider configuration's blob is
    // never walked past its table (docs/EVALS.md, the offset-table retry).
    // The [grammar][field] TSFieldId table (src/infra/fieldid.h), filled before ANY thread exists. Every
    // AST walk downstream — the parse pool, --slice, --lint, the preprocessor reader — reads it lock-free.
    warmFieldIdTable();

    CacheLoadStats cacheStats;
    HashMap<std::string, FileFacts> cache =
        cacheFile.empty() ? HashMap<std::string, FileFacts>{}
                          : loadCache( std::string( cacheFile ), rootDir, captureValueUses, result.files, cacheStats );
    const long long cacheWriteNs = cacheStats.blobWriteNs;
    // per-fileId scan arrays (language classify + hash/stat-gate + health slots) — ingest_prewarm.h
    IngestFileScan scan = makeFileScan( result.files );

    // lazy tags.scm prewarm: detect the cache-miss set (prefilling scan.hash/stat), launch the async
    // grammar compiles, and hand the compile/ready state to the parse pool via `prewarm` (ingest_prewarm.h).
    QueryPrewarm   prewarm;
    prewarmTagsQueries( result.files, cache, cacheWriteNs, scan, prewarm );

    // 2) the parallel parse pool — per-thread accumulators, cache-hit reuse, hostile-input guards,
    //    the pending-parsed-tree overlap with the async query compile, the install/gate-open moment,
    //    the deterministic merge, and the dirty-gated saveCache (ingest_parsepool.h).
    RawFacts raw = runParsePool( result, rootDir, cacheFile, captureValueUses, cache, cacheStats, scan, prewarm );

    // Cache facts are only needed by the parse pool. Release their map and bucket storage before the model tail
    // creates symbols/references, so a warm run does not carry the cache and the assembled model at once.
    HashMap<std::string, FileFacts>().swap( cache );

    result.fileHealth = std::move( scan.health );   // §L1: after saveCache, before the (unmeasured) doc pass
    collectNestRefusals( scan, result );             // the Kotlin nesting guard's refusals, as --skipped rows (ingest_prewarm.h)
    collectExtractPartials( scan, result );          // files whose facts came back partial, as --skipped rows (ingest_prewarm.h)

    // ── doc post-pass (P1-B): every collected document file (notebook/html/csv/…) becomes a docText
    //    override + one whole-file Section node — parallel extract, deterministic ascending-fileId merge
    //    (ingest_docpass.h, with the markitdown-bridge byte cache).
    runDocPostPass( result, raw.defs, !cacheFile.empty(), captureValueUses );

    PROFILE_SCOPE_DESCRIBE( "ingest: build model (dedup + symbols/refs)" );

    // 3a) dedup definitions — overlapping tags patterns collapse to one node per real symbol (ingest_model.h)
    dedupRawDefs( raw.defs );

    // 3a-bis) same-FILE decl/def collapse (ObjC only) — @interface decl vs @implementation def (ingest_model.h)
    collapseObjCDeclDefs( raw.defs );

    // 3a-ter) member-variable round: FIELD defs leave the symbol universe here (IngestResult::fields side table)
    std::vector<RawDef> fieldDefs = partitionFieldDefs( raw.defs );
    assignFields( result, fieldDefs );

    // 3b) assign Symbol ids in (fileId, line, name) order + the rich-ingest lex-stats CSR (ingest_model.h)
    assignSymbols( result, raw.defs, captureValueUses );

    // 4) attribute each reference to its enclosing definition (innermost span containing it) — the
    //    per-file DefSpanIndex + DefSweep cursor every fact family below shares (ingest_model.h).
    DefSpanIndex spanIndex = buildDefSpanIndex( result, raw.defs );

    // 4a) extent honesty — the containment rules over the same sorted spans; bits land on Symbol::extentSuspect.
    markExtentSuspects( result, raw.defs, spanIndex );

    // references: order a uint32 index permutation (radix by startByte), then MOVE each RawRef's strings
    // into its Reference while the shared sweep attributes fromSymbol (ingest_model.h).
    std::vector<std::uint32_t> refOrder = orderReferences( raw.refs, result.files.size() );
    emitReferences( result, raw.refs, refOrder, spanIndex );
    std::vector<std::uint32_t>().swap( refOrder );
    std::vector<RawRef>().swap( raw.refs );
    dropFieldDefinitionSites( result, fieldDefs );   // member-variable round: a field's defining assignment is not a use of it
    std::vector<RawDef>().swap( fieldDefs );

    // Symbol names/scopes and the definition spans have been transferred to the model/index; the raw definition
    // object array is no longer read after this point.
    std::vector<RawDef>().swap( raw.defs );

    // P2-D Rule 2 bindings, A4-R5 FFI aliases, B6.3 route defs/uses — each in its deterministic total
    // order, span-attributed families over the same DefSpanIndex (ingest_model.h).
    emitBindings( result, raw.binds, spanIndex );
    std::vector<RawBind>().swap( raw.binds );

    result.includes = std::move( raw.incs );   // physical dependencies (#include / import), for --deps
    result.constOpens = std::move( raw.constOpens );   // parser version 82: Ruby class/module opens → resolve.h's constant index

    emitBindingAliases( result, raw.ffis );
    emitRouteDefs( result, raw.routeDefs );
    emitRouteUses( result, raw.routeUses, spanIndex );
    std::vector<RawRouteUse>().swap( raw.routeUses );

    // No later model pass needs the containment index. Drop it before the macro/shadow passes, which operate on
    // the assembled result and can otherwise overlap its storage with a dead span table.
    spanIndex = DefSpanIndex{};

    // macro-edges round: the corpus-wide role="macro" retag (model.h). AFTER the model is assembled and
    // AFTER saveCache (which stores the per-file truth, role=Call) — a #define added in one file must
    // re-judge every OTHER file's cached call sites on the next run, so the retag can never be persisted.
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: macro retag (corpus-wide post-pass)" );
        retagMacroCallReferences( result );
    }

    // r9 shadow suppression (model.h): a reference inside a function whose LOCAL declarations bind the same
    // name as a variable belongs to the local, not to any same-named indexed symbol — erase it here, the one
    // choke point BOTH consumers sit downstream of (--uses reads result.references; buildGraph resolves call
    // edges from them), so the false --uses rows and the false call edge die in the same pass. AFTER the
    // macro retag (role="macro" is preprocessor evidence and stays) and AFTER saveCache (per-file truth is
    // persisted unsuppressed; the collision gate depends on the whole corpus' symbols, so the judgment can
    // never be cached per-file — same reasoning as the retag above).
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: shadow suppression (r9 post-pass)" );
        suppressShadowedReferences( result );
    }

    return result;
}
}   // namespace rw

// The --match/--lint tail: rw-level query services, a SECTION of this same TU (see the split note
// at the top). Included last, exactly where its content sat before the 2026-08-29 split.
#include "ingest_astquery.h"
