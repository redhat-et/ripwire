#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_docpass.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings

// ingest_docpass.h — the P1-B doc post-pass, moved VERBATIM out of ingest() in the 2026-08-30
// decomposition: the markitdown-bridge byte cache and the parallel extract + deterministic merge
// that turns every collected document file (notebook/html/csv/…) into a docText override plus one
// whole-file Section node. Runs OUTSIDE the parse cache and is a pure function of the bytes, so a
// warm run reproduces it byte-for-byte. Same contract as every ingest_*.h: reopens `namespace rw`
// and the unnamed namespace inside it — one TU, one unnamed namespace, internal linkage unchanged,
// zero new API surface — under the RIPWIRE_INGEST_TU guard.

namespace rw
{

// Publish `text` as the doc bridge cache blob, best effort. The temp is created through the shared exclusive
// no-follow helper (rw::pathguard::createExclTempFile), whose RAII holder removes it unless commit() renamed it;
// `.tmp` stays in the name so a residue glob still matches, and fdopen keeps the fwrite/fclose shape. A failed
// create, write or rename keeps the extracted text and discloses that the cache was not written.
inline void publishDocBridgeBlob( const std::string& bridgeBlobPath, std::uint32_t tmpKey, const std::string& text )
{
    rw::pathguard::ExclTempFile temp  = rw::pathguard::createExclTempFile( bridgeBlobPath + ".tmp" + std::to_string( tmpKey ) + ".", "", 0666 );
    const int                   rawFd = temp.ok() ? temp.releaseFd() : -1;
    std::FILE*                  fp    = rawFd >= 0 ? os::fdopen( rawFd, "wb" ) : nullptr;
    if( fp == nullptr )
    {
        if( rawFd >= 0 )
        {
            os::close( rawFd );
        }
        DISCLOSE( Diagnostics::answerUnchanged, "the doc text is kept for this run: only the bridge cache is not written",
                  "ingest: doc bridge cache could not create its temp file — the text is kept, the cache is not written" );
        return;
    }
    const bool wroteAll = std::fwrite( text.data(), 1, text.size(), fp ) == text.size();
    const bool closed   = std::fclose( fp ) == 0;
    if( !wroteAll || !closed )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "the doc text is kept for this run: only the bridge cache is not written",
                  "ingest: doc bridge cache write failed — the text is kept, the cache is not written" );
        return;
    }
    if( !temp.commit( bridgeBlobPath ) )
    {
        DISCLOSE( Diagnostics::answerUnchanged, "the doc text is kept for this run: only the bridge cache is not written",
                  "ingest: doc bridge cache rename failed — the text is kept, the cache is not written" );
    }
}

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
// A bridge doc whose bytes have no cached extraction asks docparse::markitdownMayRun() before the popen: false means
// the shell could not start markitdown, so the answer is "" without the popen — what the popen answered (rc 127),
// minus one shell start per doc per run. The cache is still consulted first, so a blob extracted while markitdown
// was installed keeps answering after it is removed, exactly as before.
inline std::string docTextViaBridgeCache( const std::string& path, const std::string& ext, bool cacheEnabled, std::uint32_t tmpKey )
{
    EXPECTS( !path.empty(), "doc post-pass: every crawled doc path is a non-empty spelling" );
    std::string text;
    std::string bridgeBlobPath;
    const bool  viaBridge = docparse::docKindOf( ext ) == docparse::DocKind::Markitdown;
    if( cacheEnabled && viaBridge )
    {
        if( const std::optional<std::string> docBytes = docparse::detail::readWholeFile( path ) )
        {
            char blobName[ 64 ];
            rw::formatTo( blobName, sizeof( blobName ), "ripwire-docmd-{:016x}.bin",
                           static_cast<unsigned long long>( fnv1a64( *docBytes ) ) );
            bridgeBlobPath = quality::resolveCacheBlobPath( quality::cacheDirLadder(), blobName );
            text = docparse::detail::readWholeFile( bridgeBlobPath ).value_or( std::string() );   // miss ⇒ text stays empty
        }
    }
    if( text.empty() && viaBridge && !docparse::markitdownMayRun() )
    {
        return text;   // no cached extraction, and no markitdown the shell could start: the popen's own answer, ""
    }
    if( text.empty() )
    {
        text = docparse::parseDocFile( path, ext );
        if( !text.empty() && !bridgeBlobPath.empty() )
        {
            publishDocBridgeBlob( bridgeBlobPath, tmpKey, text );
        }
    }
    return text;
}

namespace
{

// DOCS-UNITS D5 — a doc's extracted text, and for an HTML page its unit boundaries too (htmldoc.h). Every other kind
// goes through the bridge cache exactly as before and leaves `heads` and `flatText` empty. `flatText`: an HTML page's
// whole-text reading (docparse.h extractHtmlFlat), what every lexical ranking lens has always read for the page; the doc
// post-pass builds the file node's statistics from it. A page whose content region is empty (all navigation chrome) keeps
// that reading as its text too: it is the page's only text, and its file node stays indexed as it was before the section tree.
inline std::string docTextOfDoc( const std::string& path, const std::string& ext, bool cacheEnabled, std::uint32_t tmpKey,
                                 std::vector<docparse::HtmlHeading>& heads, std::string& flatText )
{
    if( docparse::docKindOf( ext ) != docparse::DocKind::Html )
    {
        return docTextViaBridgeCache( path, ext, cacheEnabled, tmpKey );
    }
    const std::optional<std::string> bytes = docparse::detail::readWholeFile( path );
    if( !bytes )
    {
        DISCLOSE( "docparse: cannot read document file" );
        rw::emitTo( stderr, "ripwire: doc {}: cannot read — omitted from the index (the skipped verb counts it as unmeasured)\n", path.c_str() );
        return {};
    }
    docparse::HtmlDoc doc = docparse::extractHtmlDoc( *bytes );
    flatText              = docparse::extractHtmlFlat( *bytes );
    if( doc.text.empty() )
    {
        return flatText;   // no content region: the whole-text reading, no units (heads stays empty)
    }
    heads = std::move( doc.headings );
    return std::move( doc.text );
}

// Each HTML unit's Section stats over its subtree span (rich runs only), one RawDefLex per unit, in unit order.
inline void buildHtmlUnitLex( const std::string& text, const std::vector<docparse::HtmlHeading>& heads, HashMap<std::uint64_t, std::uint32_t>& scratch,
                              std::vector<RawDefLex>& out )
{
    out.resize( heads.size() );
    for( std::size_t h = 0; h < heads.size(); ++h )
    {
        buildDefLexStats( text, heads[ h ].startByte, heads[ h ].endByte, scratch, out[ h ] );
    }
}

// One Section per HTML unit, shaped like a markdown heading's: [startByte, endByte) is the subtree in the extracted text,
// the heading construct is the signature, the enclosing unit is the scope. nameByte is the unit's start: unique within the
// file (two units never start at one byte: each opening tag adds its separator first) and never the file node's EOF.
inline void pushHtmlUnitDefs( std::uint32_t fid, const std::vector<docparse::HtmlHeading>& heads, std::vector<RawDefLex>& lex,
                              std::vector<RawDef>& rawDefs )
{
    for( std::size_t h = 0; h < heads.size(); ++h )
    {
        const docparse::HtmlHeading& u = heads[ h ];
        RawDef d;
        d.fileId    = fid;
        d.line      = u.line;
        d.startByte = u.startByte;
        d.endByte   = u.endByte;
        d.nameByte  = u.startByte;
        d.bodyByte  = u.sigEnd;
        d.kind      = SymKind::Section;
        d.lang      = Lang::Markdown;
        d.name      = u.name;
        d.rankFlags = kRankFlagRecallOnly;   // --recall's unit: no lexical lens ranks it, no name binds it (model.h)
        for( std::size_t p = h; p > 0; --p )
        {
            if( heads[ p - 1 ].level < u.level && heads[ p - 1 ].endByte > u.startByte )
            {
                d.scope = heads[ p - 1 ].name;
                break;
            }
        }
        if( h < lex.size() )
        {
            d.lex = std::move( lex[ h ] );
        }
        rawDefs.push_back( std::move( d ) );
    }
}

// One document's extraction, filled by the worker that owns the slot (runDocPostPass step 2).
struct DocSlot
{
    std::string                         text;
    bool                                hasText    = false;
    bool                                recallOnly = false;   // DOCS-UNITS-FIX: the file node takes kRankFlagRecallOnly (model.h)
    RawDefLex                           lex;                  // B0.2: the file node's Section stats (rich only)
    std::vector<docparse::HtmlHeading>  heads;                // DOCS-UNITS D5: an HTML page's units
    std::vector<RawDefLex>              headLex;              // and their stats (rich only), one per unit
};

inline void extractDocSlot( const std::string& path, std::uint32_t fid, bool cacheEnabled, bool captureValueUses,
                            HashMap<std::uint64_t, std::uint32_t>& scratch, DocSlot& slot )
{
    const std::string ext  = lowerExtensionOf( path );
    std::string       flat;   // an HTML page's whole-text reading (docTextOfDoc): its file node's statistics
    std::string       text = docTextOfDoc( path, ext, cacheEnabled, fid, slot.heads, flat );
    // an HTML page with body text but no whole-text reading had no node before the section tree: --recall reads its node,
    // nothing else ranks or names it
    slot.recallOnly = docparse::docKindOf( ext ) == docparse::DocKind::Html && flat.empty();
    if( text.empty() )
    {
        return;
    }
    if( captureValueUses )
    { // whole-file Section span [0, len) — over the whole-text reading for an HTML page (docTextOfDoc)
        const std::string& lexText = flat.empty() ? text : flat;
        buildDefLexStats( lexText, 0, std::uint32_t( lexText.size() ), scratch, slot.lex );
        buildHtmlUnitLex( text, slot.heads, scratch, slot.headLex );
    }
    slot.text    = std::move( text );
    slot.hasText = true;
}

// The document's whole-file Section node (mirrors the markdown file-node), then its HTML units. lang=Markdown ⇒ docs-only recall +
// the Section down-weight; span [0,len) so the lexical scorer indexes the whole extracted body.
inline void pushDocFileNode( IngestResult& result, std::uint32_t fid, DocSlot& slot, std::vector<RawDef>& rawDefs )
{
    const std::uint32_t len = static_cast<std::uint32_t>( slot.text.size() );
    result.docText[ fid ]   = std::move( slot.text );
    RawDef d;
    d.fileId    = fid;
    d.line      = 1;
    d.startByte = 0;
    d.endByte   = len;
    // dedup identity (ingest_model.h dedupRawDefs: fileId, nameByte): a page with units names its node at EOF, a byte no unit starts
    // at, so a heading at the page's first byte (an HTML fragment opening with <h1>) does not collapse into the node
    d.nameByte  = slot.heads.empty() ? 0 : len;
    d.kind      = SymKind::Section;
    d.lang      = Lang::Markdown;
    d.name      = fs::path( result.files[ fid ] ).stem().string();
    d.lex       = std::move( slot.lex );   // B0.2: stats over the extracted text (empty on lean runs)
    d.rankFlags = slot.recallOnly ? kRankFlagRecallOnly : std::uint8_t( 0 );
    rawDefs.push_back( std::move( d ) );
    pushHtmlUnitDefs( fid, slot.heads, slot.headLex, rawDefs );
}

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
    const std::size_t   ndocs = docIds.size();
    std::vector<DocSlot> docSlots( ndocs );
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
            docPool.emplace_back( [ & ]() noexcept
            {
                // B0.2: doc Sections are indexed by their EXTRACTED text (docText override), so their
                // stats come from that text — computed here, in the worker that owns the slot, so the
                // stats path never needs docText at query time either. Pure function of the bytes.
                HashMap<std::uint64_t, std::uint32_t> docLexScratch;
                if( captureValueUses )
                {
                    docLexScratch.reserve( 1024 );
                }
                for( std::size_t di = nextDoc.fetch_add( 1, std::memory_order_relaxed ); di < ndocs; di = nextDoc.fetch_add( 1, std::memory_order_relaxed ) )
                {
                    try   // per-file degrade — a throw escaping a worker thread would std::terminate
                    {
                        extractDocSlot( result.files[ docIds[ di ] ], docIds[ di ], cacheEnabled, captureValueUses, docLexScratch, docSlots[ di ] );
                    }
                    catch( ... )
                    {
                        DISCLOSE( "ingest: doc post-pass worker exception on a file — skipped" );
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
        if( docSlots[ di ].hasText )   // not extractable (e.g. markitdown absent) → skip
        {
            pushDocFileNode( result, docIds[ di ], docSlots[ di ], rawDefs );
        }
    }
}

}   // namespace

}   // namespace rw
