#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_docpass.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_docpass.h — the P1-B doc post-pass, moved VERBATIM out of ingest() in the 2026-08-30
// decomposition: the markitdown-bridge byte cache and the parallel extract + deterministic merge
// that turns every collected document file (notebook/html/csv/…) into a docText override plus one
// whole-file Section node. Runs OUTSIDE the parse cache and is a pure function of the bytes, so a
// warm run reproduces it byte-for-byte. Same contract as every ingest_*.h: reopens `namespace rw`
// and the unnamed namespace inside it — one TU, one unnamed namespace, internal linkage unchanged,
// zero new API surface — under the RIPWIRE_INGEST_TU guard.

namespace rw
{

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

namespace
{

// ── doc post-pass (P1-B): for every collected document file (notebook/html/csv/…), extract its text and
//    record it as the docText override + add ONE whole-file Section node so the doc is rankable + recall-
//    able. Runs OUTSIDE the parse cache (after saveCache, before id-assignment) and is a pure function of
//    the bytes, so a WARM run reproduces it byte-for-byte — the determinism contract holds for docs too.
inline void runDocPostPass( IngestResult& result, std::vector<RawDef>& rawDefs, bool cacheEnabled, bool captureValueUses )
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

                        std::string text = docTextViaBridgeCache( result.files[ fid ], ext, cacheEnabled, fid );
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

}   // namespace

}   // namespace rw
