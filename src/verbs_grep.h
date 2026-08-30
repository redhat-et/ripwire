#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_grep.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

// verbs_grep.h — the --grep verb family, moved VERBATIM from main.cpp in the 2026-08-29 split:
// GrepEncOptions/GrepHandleAttrs, the five grep emitters (handle legend, enc rows, suggest,
// unindexed, tier), the term/corpus attribute builders, emitGrepReport and runGrep. The --match/
// --regex outcomes live in verbs_lint.h — their only caller is runLint's dispatch block. Same
// contract as every verbs_*.h: reopens main.cpp's unnamed namespace — one TU, one unnamed namespace,
// internal linkage unchanged, zero new API surface — under the RIPWIRE_MAIN_TU guard.

namespace
{

// --grep=STR: parallel literal search; each hit annotated with its enclosing symbol (code-aware, not just
// file:line). Shares grepCollect() with the MCP `grep` verb so they never diverge. Its own function (the
// named-verb-handler shape): §P8 added a windowing step over the
// hit list, and the emitter was all of runGrep.
// §P11.1: grepCollect() returns TIER-then-path order (source → test/bench → docs), so the row cap and the
// --limit/--offset window below both walk an order that puts code first. This emitter never re-sorts, which
// is what keeps the CLI verb and the MCP `grep` verb on one order.
//
// §A0/§A1 — COLLECT, then SORT, then WINDOW, and in that order. §P8 made `cap` BOTH the row cap and the
// scan's collection budget, so `--limit`/`--offset` decided what was ever collected: the tier sort then ran
// over a different set per page (rows dropped and duplicated across seams, `total=` growing as the offset
// advanced) and `cfg.pageOffset + rowCap` overflowed `int` at --limit=536870912 into a confident hits="0".
// Both die with the same rule: the window is a pure slice of the fully-collected, fully-sorted list, and
// nothing derived from --limit/--offset reaches grepCollect() at all.
// R1b <enc> emission, lifted out of emitGrepReport (the named-verb-handler shape — the emitter stays the
// window/disclosure logic, the enrichment block is its own concern). Row semantics live in search.h's
// grepEnclosingRows; this is pure serialization. amp/tested follow serialize.h's lean lens grammar:
// only when the vector exists AND the value is worth a token, max/any over the row's name group.
struct GrepEncOptions
{
    const std::vector<std::uint32_t>* amp;
    const std::vector<std::uint8_t>*  tested;
    bool                              handles;
    std::string_view                  root;
    std::vector<char>&                esc;
};

class GrepHandleAttrs
{
public:
    GrepHandleAttrs( const rw::IngestResult& ing, const rw::Graph& g, bool enabled, std::string_view root )
        : ing_( ing ), g_( g ), enabled_( enabled ), root_( root ) {}

    std::string forRow( const rw::GrepEncRow& row )
    {
        if( !enabled_ )
        {
            return {};
        }
        if( row.defCount != 1 || row.ids.size() != 1 )
        {
            return " handle_omitted=\"ambiguous\"";
        }
        const rw::NodeId id = row.ids.front();
        const rw::Symbol& s = ing_.symbols[id];
        if( s.kind == rw::SymKind::Section )
        {
            return " handle_omitted=\"non-code\"";
        }
        const std::uint64_t contentHash = hashFor( s.fileId );
        const std::string handle = rw::sourceHandleFor( ing_, g_, root_, id, contentHash );
        return handle.empty() ? " handle_omitted=\"unreadable\"" : " h=\"" + handle + "\"";
    }

private:
    std::uint64_t hashFor( std::uint32_t fileId )
    {
        const auto cached = fileHashes_.find( fileId );
        if( cached != fileHashes_.end() )
        {
            return cached->second;
        }
        bool readOk = false;
        const std::string bytes = rw::mcpdetail::readFileBytes( rw::diskPath( ing_, fileId ), readOk );
        const std::uint64_t hash = readOk ? rw::mcpdetail::byteHash( bytes.data(), bytes.size() ) : 0;
        fileHashes_.emplace( fileId, hash );
        return hash;
    }

    const rw::IngestResult& ing_;
    const rw::Graph&        g_;
    bool                    enabled_;
    std::string_view        root_;
    rw::HashMap<std::uint32_t, std::uint64_t> fileHashes_;
};

void emitGrepHandleLegend( bool enabled )
{
    if( !enabled )
    {
        return;
    }
    std::printf( "<!-- ripwire grep handles: h= is sym#<stable-identity-hash>@<whole-file-content-hash>; "
                 "the content half pins the exact file bytes scanned, so an edit after any file change refuses as stale. "
                 "Only one editable enclosing definition receives h=. handle_omitted=ambiguous means the name grouped "
                 "several definitions; non-code means a document/data section has no safe definition span; unreadable "
                 "means no content hash could be proven. -->" );
}

void emitGrepEncRows( const rw::IngestResult& ing, const rw::Graph& g, std::span<const rw::GrepHit> hits,
                      const GrepEncOptions& opt )
{
    using namespace rw;
    GrepHandleAttrs handleAttrs( ing, g, opt.handles, opt.root );
    for( const GrepEncRow& row : grepEnclosingRows( ing, g, hits ) )
    {
        const auto en = rw::escapeXml( row.chain, opt.esc );
        std::printf( "<enc n=\"%.*s\" callers=\"%u\"", int( en.size() ), en.data(), row.callerCount );
        if( row.defCount > 1 )
        {
            std::printf( " defs=\"%u\"", row.defCount );
        }
        if( row.cx > 0 )
        {
            std::printf( " cx=\"%u\"", row.cx );
        }
        std::uint32_t ampMax = 0;  bool anyTested = false;
        for( const NodeId id : row.ids )
        {
            if( opt.amp && id < opt.amp->size() )
            {
                ampMax = std::max( ampMax, (*opt.amp)[id] );
            }
            if( opt.tested && id < opt.tested->size() && (*opt.tested)[id] )
            {
                anyTested = true;
            }
        }
        if( ampMax > 0 )
        {
            std::printf( " amp=\"%u\"", ampMax );
        }
        if( anyTested )
        {
            std::printf( " tested=\"1\"" );
        }
        std::fputs( handleAttrs.forRow( row ).c_str(), stdout );
        std::printf( "/>" );
    }
}

// R1a <suggest> emission, lifted out of emitGrepReport for the same reason. What to suggest is
// search.h's grepZeroHitSuggestions (shared with the MCP twin); this is pure serialization.
void emitGrepSuggest( const rw::IngestResult& ing, const std::string& pat, bool regex, std::vector<char>& esc )
{
    using namespace rw;
    const GrepZeroHitSuggestions sug = grepZeroHitSuggestions( ing, pat, regex );
    if( sug.near.empty() && !sug.offerFor )
    {
        return;
    }
    std::printf( "<suggest" );
    if( !sug.near.empty() )
    {
        const auto nn = rw::escapeXml( sug.near, esc );
        std::printf( " near=\"%.*s\"", int( nn.size() ), nn.data() );
    }
    if( sug.offerFor )
    {
        const auto fp = rw::escapeXml( pat, esc );
        std::printf( " next=\"--for=&quot;%.*s&quot;\"", int( fp.size() ), fp.data() );
    }
    std::printf( "/>" );
}

// §R-J: the three root attributes unindexed_files_scanned=/unindexed_files_skipped=/
// unindexed_candidates_capped= as one string fragment — a pure function of the aux collection, lifted out
// so emitGrepReport's own body states only "compute aux, then ask what it discloses" rather than the
// three-attribute assembly itself. unindexed_files_scanned= is unconditional (0 is informative: it means
// no unsupported-ext candidate existed, or none survived the size/binary guard — never "this build lacks
// the feature"); the other two follow corpus_excluded='s convention above: absent means zero/false.
std::string grepUnindexedAttrs( const rw::GrepAuxCollection& aux )
{
    const std::uint32_t skipped = aux.filesSkippedOversize + aux.filesSkippedBinary + aux.filesUnreadable;
    std::string          attr    = " unindexed_files_scanned=\"" + std::to_string( aux.filesScanned ) + "\"";
    if( skipped > 0 )
    {
        attr += " unindexed_files_skipped=\"" + std::to_string( skipped ) + "\"";
    }
    if( aux.candidatesCapped )
    {
        attr += " unindexed_candidates_capped=\"1\"";
    }
    return attr;
}

// §R-J <unindexed> emission, lifted out of emitGrepReport for the same reason emitGrepEncRows/
// emitGrepSuggest above were: pure serialization of an already-collected list (search.h's grepCollectAux),
// so the "collapse by contiguous path" grouping loop is a helper's job, not emitGrepReport's. Omitted
// entirely (prints nothing) when there is nothing to say — the same "absent means none" convention
// corpus_excluded=/corpus_oversize= use, so a caller never needs an empty-check before calling this.
void emitGrepUnindexed( const std::vector<rw::GrepAuxHit>& hits, bool singleRoot, const std::string& rootPrefix, std::vector<char>& esc )
{
    using namespace rw;
    if( hits.empty() )
    {
        return;
    }
    const auto ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    std::printf( "<unindexed>" );
    for( std::size_t i = 0; i < hits.size(); )
    {
        std::size_t j = i;
        std::printf( "<f p=\"%s\">", ex( singleRoot ? rw::sarif::rootRelativeUri( hits[i].path, rootPrefix )
                                                     : std::string_view( hits[i].path ) ).c_str() );
        for( ; j < hits.size() && hits[j].path == hits[i].path; ++j )
        {
            const GrepAuxHit& h = hits[j];
            std::string        safe;
            appendCdataSafe( h.text, safe );
            std::printf( "<hit l=\"%u\"><m><![CDATA[", h.line );
            std::fwrite( safe.data(), 1, safe.size(), stdout );
            std::printf( "]]></m></hit>" );
        }
        std::printf( "</f>" );
        i = j;
    }
    std::printf( "</unindexed>" );
}

// R-H span tiers: the legend clause and the root attributes, lifted out of emitGrepReport for exactly the
// reason emitGrepUnindexed/grepUnindexedAttrs above were — pure serialization of an already-computed
// report, gated on ONE predicate (GrepTierReport::hasDisclosure), so the emitter's own body says "print the
// tier disclosure" rather than carrying six conditional appends. Both return empty when the run held
// nothing back, which is the byte-identical-to-untiered contract.
//
// Kept DENSE on purpose (G4): this clause rides every answer that holds a row back, and on a small answer
// legend prose IS the answer — an early draft cost ~1.2 KB and ate the row saving whole.
const char* grepTierLegend( const rw::GrepTierReport& tier )
{
    if( !tier.hasDisclosure() )
    {
        return "";
    }
    return "SPAN TIERS: each hit is classified by the tree-sitter span it sits in (code/comment/string) and this answer serves "
           "the CODE tier, or — when no hit is code — comment and string TOGETHER; tier= names what was served when it is not "
           "code, so a pattern living only in prose is answered, never emptied. "
           "suppressed_comment=/suppressed_string= are the classified hits held back: not in hits=, and the "
           "reason complete= cannot appear. Pass grep-in=any (dashes omitted) for every tier. Hit files are parsed on demand "
           "under a fixed budget: tier_parsed= how many were classified, tier_budget= which ceiling stopped it (files or bytes, "
           "present only then), tier_unclassified= hits in files nothing classified — always EMITTED, never suppressed. ";
}

// Present only when this answer actually held something back or stopped short — absent-means-nothing-was-
// tiered, the same convention corpus_excluded= follows. tier= is narrowed further to the NON-DEFAULT case:
// naming the code tier on every answer would be ~12 bytes restating the default on the overwhelming
// majority that serve it.
std::string grepTierAttrs( const rw::GrepTierReport& tier )
{
    if( !tier.hasDisclosure() )
    {
        return {};
    }
    std::string attrs;
    if( tier.suppressedComment > 0 )
    {
        attrs += " suppressed_comment=\"" + std::to_string( tier.suppressedComment ) + "\"";
    }
    if( tier.suppressedString > 0 )
    {
        attrs += " suppressed_string=\"" + std::to_string( tier.suppressedString ) + "\"";
    }
    if( std::strcmp( tier.emittedTier, "code" ) != 0 )
    {
        attrs += std::string( " tier=\"" ) + tier.emittedTier + "\"";
    }
    attrs += " tier_parsed=\"" + std::to_string( tier.tieredFileCount ) + "\"";
    if( tier.unclassifiedHits > 0 )
    {
        attrs += " tier_unclassified=\"" + std::to_string( tier.unclassifiedHits ) + "\"";
    }
    if( tier.budgetHit != nullptr )
    {
        attrs += std::string( " tier_budget=\"" ) + tier.budgetHit + "\"";
    }
    return attrs;
}

std::vector<rw::GrepTerm> makeGrepTerms( const rw::Config& cfg )
{
    std::vector<rw::GrepTerm> terms;
    terms.reserve( cfg.grepAnd.size() + cfg.grepNot.size() );
    for( const std::string_view t : cfg.grepAnd ) { terms.push_back( rw::GrepTerm{ std::string( t ), false } ); }
    for( const std::string_view t : cfg.grepNot ) { terms.push_back( rw::GrepTerm{ std::string( t ), true } ); }
    return terms;
}

void emitCompactGrepLegend()
{
    std::printf( "<!-- ripwire grep ripwire.grep/v1: files group source-ordered hits; l=line, m=matched text, "
                 "in=enclosing name when known. shown/capped disclose the printed window; hits_capped=1 makes hits a floor; "
                 "complete=1 only for an exhaustive literal scan whose whole unfiltered window printed. root anchors relative p; "
                 "enc callers remain a call-graph floor; tier/suppressed and unindexed/corpus attrs disclose excluded populations. -->" );
}

std::string grepTermsAttrs( std::string_view pattern, std::span<const rw::GrepTerm> terms, rw::GrepScope scope,
                            std::uint32_t suppressed, std::vector<char>& esc )
{
    if( terms.empty() ) { return {}; }
    std::string termsList( rw::escapeXml( pattern, esc ) );
    for( const rw::GrepTerm& term : terms )
    {
        termsList += term.negated ? " -" : " +";
        termsList += rw::escapeXml( term.term, esc );
    }
    return " terms=\"" + termsList + "\" scope=\"" + ( scope == rw::GrepScope::File ? "file" : "line" )
         + "\" terms_suppressed=\"" + std::to_string( suppressed ) + "\"";
}

std::string grepCorpusAttrs( const rw::IngestResult& ing )
{
    std::string attrs;
    if( ing.crawlSkips.excludedFiles > 0 )
    {
        attrs += " corpus_excluded=\"" + std::to_string( ing.crawlSkips.excludedFiles ) + "\"";
    }
    if( !ing.skippedOversize.empty() )
    {
        attrs += " corpus_oversize=\"" + std::to_string( ing.skippedOversize.size() ) + "\"";
    }
    return attrs;
}

// R1 (the 2026-08-12 usage mine) widened the signature beyond (cfg, ing): `g` feeds the <enc> rows'
// callers= (in-edge CSR — data the graph already holds, zero new analysis), and amp/tested ride along
// ONLY when a co-run (--metrics) already computed them — grep itself never triggers the qmetrics pass
// or the git popen. Null pointers are the normal case and emit nothing.
// ─── §P4.1 — the grep SCAN PHASES, liftable ahead of the graph ────────────────────────────────────
//
// WHY THIS EXISTS. The three phases below (the parallel literal scan, the boolean post-filter + span
// tiering it feeds, and the unindexed aux scan) read ONLY `cfg` and `ing`. They do not touch the call
// graph — the graph enters this verb in exactly one place, the <enc> rows' callers= count. But the
// pipeline built the graph FIRST and then ran them, so on a warm answer two independent CPU-bound
// stretches ran back to back: buildGraph on the main thread (~40 ms on the measured corpus) followed by
// ~47 ms of scan work. Lifting them into a struct lets main() start them on one thread while buildGraph
// runs on another, so the answer pays max(graph, scan) instead of their sum. See bench/PROFILE.md.
//
// IT IS AN OVERLAP, NOT A SHORTCUT. Every phase computes exactly what it computed before, from exactly
// the same inputs, and the result is consumed after the join in a fixed order — so nothing about the
// output can depend on which finished first (determinism is a contract, and a concurrency change is
// precisely where that gets lost). A run whose answering verb is not grep never starts the thread and a
// prefetch that degrades sets valid=false, which makes this verb recompute inline — in BOTH cases the
// bytes are the ones the serial path produced, which is what test/grepfastcheck.sh arm (6) pins.
struct GrepScanPhases
{
    rw::GrepCollection        found;
    rw::GrepTierReport        tier;
    rw::GrepAuxCollection     aux;
    std::vector<rw::GrepTerm> terms;                 // owned: argv string_views become owned strings exactly once
    rw::GrepScope             scope           = rw::GrepScope::Line;
    std::uint32_t             termsSuppressed = 0;
    bool                      valid           = false;   // false ⇒ never computed (or degraded) — recompute inline
};

GrepScanPhases collectGrepScanPhases( const rw::Config& cfg, const rw::IngestResult& ing )
{
    using namespace rw;
    const std::string pat( cfg.grep );
    GrepScanPhases    phases;
    {
        PROFILE_SCOPE_DESCRIBE( "grep/1: grepCollect scan" );
        phases.found = grepCollect( ing, pat, cfg.grepRegex, cfg.noPrefilter );
    }
    // G3 (2026-08-15 harvest, report-ugrep §F2): boolean AND/NOT as a post-filter over the collected raw
    // hits — literal-only, already refused together with --regex in validateConfig. Built here (not in
    // Config) so the CLI value strings (string_views into argv) become owned std::strings exactly once.
    phases.terms = makeGrepTerms( cfg );
    phases.scope = ( cfg.grepScope == "file" ) ? GrepScope::File : GrepScope::Line;
    if( !phases.terms.empty() )
    {
        phases.found = grepApplyBooleanTerms( ing, std::move( phases.found ), std::span<const GrepTerm>( phases.terms ),
                                              phases.scope, phases.termsSuppressed );
    }
    // R-H (2026-08-15 harvest report-ugrep §F3/§F4, funded by wave-2 E5): SPAN TIERS — classify each
    // surviving hit by the tree-sitter span it sits in and serve the tightest NON-EMPTY tier. Runs AFTER the
    // boolean filter on purpose: tiering the survivors is both cheaper and the only reading that matches
    // what this answer will print. The bounded on-demand parse and its disclosed bail-out live in
    // search.h::grepApplySpanTiers (which owns the budget), never in astQuery — see its header.
    {
        PROFILE_SCOPE_DESCRIBE( "grep/2: span tiers" );
        phases.found = grepApplySpanTiers( ing, std::move( phases.found ), ( cfg.grepIn == "any" ) ? GrepIn::Any : GrepIn::Code,
                                           phases.tier, /*useMemo=*/!cfg.noCache );
    }
    // §R-J: additive scan over CrawlSkips::unsupported — the "unsupported-ext, text-looking" population the
    // crawl already computed at ingest time (queries/*/tags.scm and its siblings). Reuses the SAME per-file
    // ceiling the crawl applies to indexed files, so a huge unsupported-ext file is excluded exactly like an
    // oversized indexed one would be. See search.h's grepCollectAux for the honesty fields and why this is a
    // separate hit type rather than a widened GrepRawHit::fileId domain (the lane report has the option write-up).
    {
        PROFILE_SCOPE_DESCRIBE( "grep/3: aux unindexed scan" );
        const std::size_t maxAuxFileBytes = cfg.maxFileBytes == 0 ? kDefaultMaxFileBytes : cfg.maxFileBytes;
        phases.aux = grepCollectAux( ing.crawlSkips, pat, cfg.grepRegex, maxAuxFileBytes );
    }
    phases.valid = true;
    return phases;
}

// §P4.1 launch seam — the whole of the overlap, so main()'s pipeline body stays three statements with no
// branch of its own. The three scan phases read only `cfg` and `ing`; the call graph enters this verb in
// exactly one place, the <enc> rows' caller counts. Serially that meant a warm answer paid buildGraph and
// then an equally CPU-bound scan one after the other; started here they overlap, and the answer pays the
// larger of the two rather than their sum (bench/PROFILE.md has the measured split).
//
// WHEN is not re-derived here: the caller hands in §B11.4's precedence-table WINNER — the single source of
// dispatch order, pinned pair-by-pair by test/dispatchordercheck.sh — so a run some other verb answers
// starts no thread and pays nothing. Returns a non-joinable thread whenever nothing should run: the
// caller's join is then a no-op, `out` keeps valid=false, and the verb computes the phases inline, which is
// the pre-P4.1 control path verbatim. The result is consumed ONLY after the join, in a fixed order, so no
// byte of the output can depend on which thread finished first — the determinism contract a concurrency
// change is most likely to break, and the one test/grepfastcheck.sh arm (6) exists to pin.
std::thread startGrepScanPrefetch( const rw::Config& cfg, const rw::IngestResult& ing, const char* winningVerbFlag, GrepScanPhases& out )
{
    // Two narrowing conditions, both here so main() carries neither: grep must be the verb that will ANSWER
    // (the caller hands in §B11.4's own winner, never a re-derived guess), and a --regex that will be REFUSED
    // scans nothing — exactly as the serial path refuses before scanning.
    const bool grepAnswers  = winningVerbFlag != nullptr && std::strcmp( winningVerbFlag, "--grep" ) == 0;
    const bool regexRefused = cfg.grepRegex && rw::regexCompileError( std::string( cfg.grep ) ).has_value();
    if( !grepAnswers || regexRefused )
    {
        return {};
    }
    return std::thread( [ &out, &cfg, &ing ]()
                        {
                            try
                            {
                                out = collectGrepScanPhases( cfg, ing );
                            }
                            catch( ... )   // a throw crossing this thread boundary would be std::terminate
                            {
                                out.valid = false;
                                DEGRADED_PATH_ALERT( "grep: scan prefetch degraded (exception swallowed) — the verb recomputes inline" );
                            }
                        } );
}

// The matching join. A one-line seam rather than an `if` in the pipeline body, so the caller reads as three
// statements with no branch of its own: a prefetch that never started is simply not joinable.
void joinGrepScanPrefetch( std::thread& worker )
{
    if( worker.joinable() )
    {
        worker.join();
    }
}

int emitGrepReport( const rw::Config& cfg, const rw::IngestResult& ing, const rw::Graph& g,
                    const std::vector<std::uint32_t>* amp, const std::vector<std::uint8_t>* tested,
                    const GrepScanPhases* prefetched )
{
    using namespace rw;
    const std::string          pat( cfg.grep );
    const int                  histCap = cfg.packTopN > 0 ? cfg.packTopN : 100;
    const int                  rowCap  = effectiveRowCap( cfg.pageLimit, histCap );

    // §P0.4: an invalid --regex used to scan nothing and print hits="0" at exit 0 with an EMPTY stderr —
    // indistinguishable from a true negative on every channel. Refuse before scanning, so the prefilter
    // and --no-prefilter paths refuse identically and no <grep> element is produced at all.
    if( cfg.grepRegex )
    {
        if( const std::optional<std::string> reErr = regexCompileError( pat ) )
        {
            // The lead-in is deliberately NEUTRAL ("refused", not "invalid"): regexCompileError() also
            // refuses patterns that are perfectly valid ECMAScript — L5's non-portable escapes and M2's
            // catastrophic-backtracking family — so "is not a valid regular expression" would be false
            // for two of its three verdicts. The reason string itself names which case it was.
            std::fprintf( stderr, "ripwire: --regex='%s' refused, nothing was scanned: %s "
                                  "(a hits=\"0\" here would be a failure, not a measurement — fix the pattern, e.g. ripwire <dir> --regex='fnv1a\\w+')\n",
                          pat.c_str(), reErr->c_str() );
            return 1;
        }
    }

    // --regex uses the sound Russ-Cox trigram prefilter by default; --no-prefilter forces a full scan
    // (the oracle the soundness gate compares against — prefiltered must equal full-scan).
    // grepBefore/grepAfter default to 0 (--grep-context/-before/-after unset) ⇒ GrepHit::before/after
    // stay empty and the <hit> emission below takes the ORIGINAL self-closing path byte-for-byte —
    // this is the byte-identical-when-unset contract.
    //
    // §P4.1: the scan phases are collectGrepScanPhases()'s (above) — main() may already have run them
    // alongside buildGraph. `prefetched` is that result when it exists; nullptr, or a degraded prefetch,
    // recomputes them right here from the same inputs, which is the pre-P4.1 control path verbatim.
    GrepScanPhases        localPhases;
    const GrepScanPhases* phases = ( prefetched != nullptr && prefetched->valid ) ? prefetched : nullptr;
    if( phases == nullptr )
    {
        localPhases = collectGrepScanPhases( cfg, ing );
        phases      = &localPhases;
    }
    const GrepCollection&           found           = phases->found;
    const GrepTierReport&           tierReport      = phases->tier;
    const GrepAuxCollection&        aux             = phases->aux;
    const std::vector<GrepTerm>&    grepTerms       = phases->terms;
    const GrepScope                 grepScopeVal    = phases->scope;
    const std::uint32_t             termsSuppressed = phases->termsSuppressed;
    PROFILE_SCOPE_DESCRIBE( "grep/4: window + enrich + emit" );

    const std::size_t          hitCount = found.raw.size();
    // files= counts the whole COLLECTED set, never the printed page — it is a property of the search, so it
    // must read the same on every page of a walk (it used to be counted over the window's rows).
    std::uint32_t prev = UINT32_MAX;  int filesMatched = 0;
    for( const GrepRawHit& r : found.raw )
    {
        if( r.fileId != prev )
        {
            ++filesMatched;
            prev = r.fileId;
        } // hits sorted by file
    }
    // the WINDOW: a pure slice of the sorted list. pageWindow() clamps a past-the-end offset to an empty
    // page, so a 64-bit offset can never index out of range.
    const PageWindow           grepPage = pageWindow( hitCount, rowCap, cfg.pageOffset );
    const std::vector<GrepHit> hits     = grepEnrich( ing, std::span<const GrepRawHit>( found.raw ).subspan( grepPage.begin, grepPage.end - grepPage.begin ),
                                                      cfg.grepBefore, cfg.grepAfter );
    std::vector<char> esc;
    const auto        ex = [ & ]( std::string_view s ) -> std::string { return std::string( escapeXml( s, esc ) ); };
    // CDATA-safe a context block: split any ]]> (would prematurely close the CDATA) and scrub XML-illegal
    // control bytes (G4) — same rule serialize.h applies to <src>/<bodies> bodies, kept local per this
    // agent's scope (search.h/main.cpp only, serialize.h owned by another concurrent agent).
    const auto cdataSafe = [ & ]( std::string_view body ) -> std::string
    {
        std::string safe;
        safe.reserve( body.size() );
        for( std::size_t i = 0; i < body.size(); ++i )
        {
            if( i + 2 < body.size() && body[i] == ']' && body[i + 1] == ']' && body[i + 2] == '>' )
            { safe += "]]]]><![CDATA[>"; i += 2; }
            else
            { safe += xmlSafeByte( body[i] ); }
        }
        return safe;
    };
    // P2.1: hits= counted everything, the listing stopped at the row cap, and nothing said so.
    // shown=/capped= (the --communities / --graph-query vocabulary) close it.
    // hits_capped= is a SECOND, deeper cut this emitter does not own: grepCollect() stops COLLECTING at the
    // fixed kGrepCollectionBudget raw matches (search.h), so on a pattern common enough to exhaust it
    // `hits=` is itself a FLOOR, not a total. §A1: that ceiling no longer moves with --limit/--offset, so
    // hits=/files=/total= now read the SAME on every page of a walk.
    const int         hitsCapped = found.isBudgetReached ? 1 : 0;
    // T1 (completeness claims — the mirror of the floor vocabulary). complete="1" appears on the root
    // exactly when this listing is EXHAUSTIVE over the index, so a consumer need not re-derive (re-grep)
    // the answer. Four conditions, each with a mutation arm in test/completecheck.sh:
    //   scan   — every indexed file read end to end: LITERAL scans only. A regex answer never claims, in
    //            EITHER prefilter mode: prefiltered, the claim would rest on the analyzer rather than on a
    //            full read; and no-prefilter may not claim what prefiltered does not, because the two modes
    //            are contractually byte-identical (test/regexcheck.sh's soundness oracle diffs them — the
    //            prefilter is a performance switch, never an answer switch);
    //   ceiling — the collection budget was not reached (hits_capped="0"), or hits= is itself a floor;
    //   read   — no indexed file was unreadable and no worker degraded (found's own honesty bits);
    //   window — the printed page starts at row 0 and reaches the last hit (shown == hits).
    // A FALSE claim here is the worst bug this tool can ship; when any condition fails, NOTHING is added
    // (the floor/truncation vocabulary already covers partial answers — no complete="0" noise).
    //   tier   — R-H: a tier-filtered listing did NOT print every hit it found, so it may not wear the
    //            claim either. This is the same rule the window arm applies to a page: complete= says "a hit
    //            absent above is absent from every indexed file", and that is false the moment a comment or
    //            string row was held back. --grep-in=any (no filtering) keeps the claim, which is what makes
    //            the claim recoverable rather than lost.
    const bool scanExhaustive = found.cleanScan() && !cfg.grepRegex;
    const bool windowWhole    = grepPage.begin == 0 && grepPage.end == hitCount;
    const bool nothingHeldBack = tierReport.suppressedComment == 0 && tierReport.suppressedString == 0;
    const char* const completeAttr = ( scanExhaustive && windowWhole && nothingHeldBack ) ? " complete=\"1\"" : "";
    char              grab[ 192 ];
    // G1 (2026-08-15 harvest, report-memgraph §F6): a single-root run's `ing.files` carry the crawl root's
    // OWN spelling (a leading "./" for a relative root, the full absolute path for an absolute one — see
    // sarif.h's rootRelativeUri, which this reuses rather than re-deriving the same strip). Multi-root
    // workspaces already carry the compact `<label>/<relpath>` identity (model.h) and are left untouched —
    // scoped out here, not silently degraded: `root=` is simply absent and `p=` reads as it always did.
    const bool        singleRoot = ing.realPaths.empty() && cfg.roots.size() == 1;
    const std::string rootPrefix = singleRoot ? rw::sarif::rootPrefixOf( std::string( cfg.roots[0] ) ) : std::string();
    const auto         pathFor   = [ & ]( std::uint32_t fileId ) -> std::string_view
    {
        return singleRoot ? rw::sarif::rootRelativeUri( ing.files[ fileId ], rootPrefix ) : std::string_view( ing.files[ fileId ] );
    };
    std::string rootAttr;
    if( singleRoot )
    {
        rootAttr = " root=\"" + ex( cfg.roots[0] ) + "\"";
    }
    // Collapse (byte-identical match text within one file folding into one <hit> + <at> sites, search.h's
    // grepGroupByFile) is safe only on the UNPAGINATED default view: paging math runs upstream in RAW-hit
    // space (the §A0/§A1 seam contract, test/grepseamcheck.sh) and a paged window's <hit> COUNT must stay
    // the window size shown= already promises. Context lines are per-site too — folding would drop them.
    const bool collapseOn = cfg.pageLimit == 0 && cfg.pageOffset == 0 && cfg.grepBefore == 0 && cfg.grepAfter == 0;
    // §P8 collision, documented not renamed: both `in=` meanings are load-bearing (10 and 13+ consumers,
    // two byte-exact goldens, five SKILL.md files), so the legend names the other one instead.
    // §A10.3: the ORDER is stated, because the rows are silently reordered otherwise — whereis's legend
    // states its ordering in full and grep's said nothing.
    // §B12.4 in-band (W3FIX): same shared clause as --impact, so limit="0" is DEFINED on the first screen of
    // the two verbs an agent walks most, not only in --help and pageview.h.
    if( cfg.legend == "compact" )
    {
        emitCompactGrepLegend();
    }
    else
    {
    std::printf( "<!-- ripwire grep: parallel literal/regex scan; hits GROUP by file under <f p=\"…\">, each <hit> carrying its LINE "
                 "(l=), matched text (m) and enclosing symbol (in=, a NAME here; the same spelling is a fan-in COUNT in for/pack-task/exemplar; "
                 "ABSENT (never an empty in= value) when no symbol encloses the hit, which is NOT the same claim as file scope — and "
                 "on a file row carrying parse_degraded=\"1\" it is NO CLAIM AT ALL: that file's parse holds ERROR/MISSING nodes "
                 "(the skipped verb itemizes err=/err_ratio=), symbols there may be unextracted, so read in= absence inside it as "
                 "UNKNOWN, not as file scope; absence of parse_degraded= on a row means the parse was clean, except that a file the "
                 "ingest never parsed at all — doc-format, binary-sniffed, unreadable — is also unmarked, the skipped verb's "
                 "unmeasured class). "
                 "root= on the root element is the crawl root every <f p=…> is now RELATIVE to (single-root runs only; absent ⇒ p= is the "
                 "path ingest itself used, unchanged). ORDER: SOURCE files before test/bench files before docs, then path and line. "
                 "shown=/capped= = rows printed vs found (a count of underlying HITS, the same unit hits= uses, not of printed <hit> "
                 "elements); hits_capped=\"1\" ⇒ hits= is a FLOOR (collection budget reached). " );
    // G3 (2026-08-15 harvest): terms=/scope=/terms_suppressed= appear ONLY when the run passed and/not —
    // deliberately no literal "--and"/"--not" substring (illegal "--" digraph inside an XML comment; spelled
    // without the leading dashes, matching this legend's own convention) — and so does the PROSE defining
    // them. It is ~630 B that used to ride on EVERY answer, including the overwhelming majority that can
    // never emit those three attributes: a zero-hit answer paid 631 of its bytes defining what was not
    // there. Legend text is the one part of a grep answer that does NOT amortize over hits, so on small
    // answers it IS the answer. legendcoveragecheck is unharmed by construction — it asks whether every
    // attribute the answer EMITS is defined where the reader meets it, and a clause gated on exactly its
    // attributes' own condition is present precisely when it can be needed. Gates: grepbytescheck's
    // uncapped small-hit arm; grepandcheck (4d)/(4e) still assert the prose IS there on an and/not run.
    if( !grepTerms.empty() )
    {
        std::printf( "terms= (present only with and/not) restates the whole boolean query as it was EVALUATED: the base pattern, then "
                     "each and term prefixed +, each not term prefixed -. scope=line (default) requires every term on the SAME matched "
                     "line as the base pattern; scope=file requires every term ANYWHERE in the file, independent of which line matched. "
                     "terms_suppressed= counts the raw hits the boolean filter REJECTED — a different axis from hits_capped= (a collection-"
                     "budget ceiling): hits=/shown=/etc. already read the FILTERED count, so terms_suppressed= exists only so a reader can "
                     "recover how many the un-filtered scan would have shown. " );
    }
    // R-H span tiers: the prose is gated on exactly the condition its own attributes are (the terms= clause
    // above set the precedent, and legendcoveragecheck's rule is "define what you EMIT"). An answer that
    // held nothing back emits no tier attribute and pays no tier prose — byte-identical to the pre-tier
    // verb, which is the "purely additive" contract. Helper above; empty string when there is nothing to say.
    std::printf( "%s", grepTierLegend( tierReport ) );
    std::printf(
                 // G1 (2026-08-15 harvest): byte-identical match text within one file's hits on the UNPAGINATED default view folds into
                 // ONE <hit> row plus <at l=… in=…/> children for the extra sites — n= on the <hit> (present only when >1) is 1+the <at>
                 // count, so summing n= across a page's <hit> rows recovers shown=. Paging or --grep-context/-before/-after disables the
                 // fold (a paged window's row count must stay honest; context lines are per-site and would be lost by folding).
                 // Deliberately no literal "<at " substring above (space after the tag name): row-counting
                 // gates that scan this legend's OWN comment for "<hit "/"<at " row markers (test/pagingsweepcheck.sh's
                 // disclose()) would double-count the illustrated example as a real row otherwise.
                 "A byte-identical match at OTHER sites in the SAME file folds into the first <hit>'s n= (default 1, unset) and an at-tagged "
                 "sibling element (l=/in=, self-closing) per extra site — never on a paged or grep-context/-before/-after answer (dashes "
                 "omitted, illegal in an XML comment), where every site keeps its own <hit>. "
                 // R1 (the 2026-08-12 usage mine): the two follow-up answers, defined in-band — the legend is the only prose a mid-task agent
                 // reads, so it carries the honesty duties: <suggest> is labeled SUGGESTIONS (a zero stays "none found"), callers= carries the FLOOR caveat.
                 // Deliberately NO attribute=value literal in the added sentences ("a zero-hit answer", never a quoted hits value): several gates
                 // parse this verb's header counters by grep, and a quoted numeric example here would be matched first — the quality-delta legend's rule.
                 "After the hit rows, <enc> rows list each DISTINCT enclosing symbol NAME of THIS page (first-appearance order, bounded by the page) with callers= its 1-hop DISTINCT-caller count, "
                 "unioned across same-named defs like the callers verb (a FLOOR — dynamic dispatch contributes no edge), defs= how many defs the name grouped (only when more than one), cx= complexity; "
                 "amp=/tested= join only when a metrics co-run already computed that lens. On a zero-hit answer a <suggest> element may follow: SUGGESTIONS, never matches — near= the nearest indexed "
                 "symbol name (did-you-mean), next= a ready-to-paste conceptual fallback; absent for regex/non-word-like patterns or when nothing plausible exists. "
                 // T1: the completeness claim, defined where it appears (no attribute=value literal in these
                 // sentences, same rule as the R1 additions above — gates parse this legend by grep).
                 "COMPLETENESS: complete= on the root (value 1) means this listing is EXHAUSTIVE and a consumer need not re-derive it: "
                 "a LITERAL scan read every indexed file end to end, hit no collection ceiling, and printed every hit it found — so on "
                 "this answer a zero really is zero and a hit absent above is absent from every indexed file. The claim is "
                 "complete-within-the-index ONLY: most files the ingest skipped were never scanned (the skipped verb lists exactly "
                 "which, with reasons; the ONE exception is the unindexed_files_scanned= class right below, itself never covered by "
                 "complete=), and files outside the indexed roots are outside the claim. It never appears on a regex answer (the "
                 "prefilter is a performance switch that may not change the answer, so neither mode claims), a capped or paged listing, "
                 "or a scan that could not read a file; its ABSENCE claims nothing. The enc rows' caller counts stay FLOORS regardless "
                 "— complete= speaks for the hit rows alone. "
                 // §R-J (Wave-2 harvest item R-J): queries/*/tags.scm (and any other unsupported-ext file that
                 // still reads as text) used to be invisible to EVERY verb — including the H-severity bug hunt
                 // whose root cause lived at that exact path. This is the fix: additively scan the crawl's own
                 // unsupported-ext/text-looking population and print its hits in a trailing block, never
                 // folded into the indexed count above and never claimed by complete=.
                 "unindexed_files_scanned= counts files outside the index (unsupported-ext, but text-looking — the skipped verb's "
                 "own unsupported-ext class) that THIS answer additionally scanned for the same pattern; their hits print inside a "
                 "trailing unindexed element (present only when it found something), holding its own <f> rows in the same shape as "
                 "above, and never carry in= — there is no symbol table to check for such a file, which is not the same claim as file "
                 "scope. unindexed_files_skipped= (present only when nonzero) counts "
                 "candidates this scan saw but did not read: over the max-file-size ceiling, sniffed binary, or unreadable. "
                 "unindexed_candidates_capped=\"1\" (present only when true) means the CANDIDATE list itself (the skipped verb's own "
                 "500-row-per-class cap) was already a floor, so files past it were never considered here either — see the skipped verb "
                 "for every row. "
                 // G4 (2026-08-15 harvest): corpus_excluded=/corpus_oversize= — present only when non-zero,
                 // same absent-means-none convention as skippedOversize itself (model.h). Deliberately no
                 // literal 'hits="0"' example below (a quoted numeric example — the quality-delta legend's
                 // own rule, restated here after it bit a naive ` hits="N"` extraction downstream twice).
                 "corpus_excluded= counts files an exclude filter (or built-in crawl policy) kept OUT of the index entirely; "
                 "corpus_oversize= counts files the crawl SAW but dropped for exceeding the size ceiling. Both answer what an "
                 "otherwise-empty answer alone cannot: not in this repo, or in a file that was never scanned — the skipped "
                 "verb itemizes the rows behind either count. "
                 "%s -->", rw::kPageRaiseCapClause );
    }
    emitGrepHandleLegend( cfg.grepHandles );
    // G3: terms=/scope=/suppressed= — only when AND/NOT was actually given, so a plain --grep answer
    // stays byte-identical to before G3 landed (the "purely additive" rule every ripwire flag follows).
    const std::string termsAttr = grepTermsAttrs( pat, grepTerms, grepScopeVal, termsSuppressed, esc );
    // G4 (2026-08-15 harvest, report-ugrep §F6): corpus_excluded=/corpus_oversize= — so hits="0" can
    // distinguish "not in this repo" from "in a file the crawl never scanned" (an --exclude= match, or a
    // file past --max-file-size). Absent when zero, matching skippedOversize's own "absent means nothing
    // was skipped" convention (model.h) — never a re-run hint (--skipped already itemizes the rows).
    const std::string corpusAttr = grepCorpusAttrs( ing );
    // R-H: the tier disclosure (helper above) — empty when nothing was held back.
    const std::string tierAttr = grepTierAttrs( tierReport );
    // §R-J: unindexed_files_scanned=/unindexed_files_skipped=/unindexed_candidates_capped= (helper above).
    const std::string auxAttr = grepUnindexedAttrs( aux );
    const char* schemaAttr = cfg.legend == "compact" ? " schema=\"ripwire.grep/v1\"" : "";
    std::printf( "<grep pattern=\"%s\"%s%s%s files=\"%d\" hits=\"%zu\"%s hits_capped=\"%d\"%s%s%s%s>",
                 ex( pat ).c_str(), schemaAttr, rootAttr.c_str(), termsAttr.c_str(), filesMatched, hitCount,
                 pageDisclosure( grab, sizeof( grab ), grepPage.end - grepPage.begin, hitCount, grepPage.end,
                                 cfg.pageLimit, cfg.pageOffset, true ),
                 hitsCapped, completeAttr, tierAttr.c_str(), corpusAttr.c_str(), auxAttr.c_str() );
    // G1 (2026-08-15 harvest): hits GROUP by file under <f p="…">, root-relative when this is a single-root
    // run (report-memgraph §F6: the absolute root prefix alone was 42.5% of a real --grep payload; the
    // repeated-per-hit path was report-octocode §F1's 31.4%). Byte-identical text within one file's group
    // folds via grepGroupByFile (search.h) when collapseOn — n= on the row (present only >1) plus <at l=…
    // in=…/> children carry the folded sites (report-graphrag Finding 2, 18.7% on a real corpus).
    // <m> = the Matched line itself, in the same one-letter CDATA shape as <b>efore and <a>fter (P5:
    // a hit used to say WHERE the pattern is but never WHAT it matched — with the context flags it
    // printed the lines around the hit and skipped the hit's own line, and without them it printed no
    // text at all, so in either mode the agent had to re-read the file to see what it had searched
    // for). Always emitted, in before → matched → after reading order, so a <hit> is never
    // self-closing now. appendCdataSafe (serialize.h) rather than the local cdataSafe lambda: the
    // matched line is arbitrary file bytes, so invalid UTF-8 must be scrubbed too, not just C0.
    for( const GrepFileGroup& group : grepGroupByFile( std::span<const GrepHit>( hits ), collapseOn ) )
    {
        // parse_degraded routing (2026-08-30, degradedhintcheck): join the health fact the skipped verb
        // already computed — over a shredded parse the in=-absent claim below is unknowable, and the
        // reader must not be sent hunting for a rename (the looksObjC misroute cost exactly that hunt).
        std::printf( "<f p=\"%s\"%s>", ex( pathFor( group.fileId ) ).c_str(),
                     fileParseDegraded( ing, group.fileId ) ? " parse_degraded=\"1\"" : "" );
        for( const GrepCollapsedHit& c : group.hits )
        {
            const GrepHit& h = c.hit;
            std::printf( "<hit l=\"%u\"", h.line );
            if( !h.enclosing.empty() )                // in= honesty: ABSENT means no enclosing symbol, never in=""
            {
                std::printf( " in=\"%s\"", ex( h.enclosing ).c_str() );
            }
            if( !c.more.empty() )
            {
                std::printf( " n=\"%zu\"", c.more.size() + 1 );   // 1 (this row) + the folded sites — sums to shown=
            }
            std::printf( ">" );
            if( !h.before.empty() )
            {
                const std::string safe = cdataSafe( h.before );
                std::printf( "<b><![CDATA[" );  std::fwrite( safe.data(), 1, safe.size(), stdout );  std::printf( "]]></b>" );
            }
            {
                std::string safe;
                appendCdataSafe( h.text, safe );
                std::printf( "<m><![CDATA[" );  std::fwrite( safe.data(), 1, safe.size(), stdout );  std::printf( "]]></m>" );
            }
            if( !h.after.empty() )
            {
                const std::string safe = cdataSafe( h.after );
                std::printf( "<a><![CDATA[" );  std::fwrite( safe.data(), 1, safe.size(), stdout );  std::printf( "]]></a>" );
            }
            for( const GrepHitSite& site : c.more )
            {
                std::printf( "<at l=\"%u\"", site.line );
                if( !site.enclosing.empty() )
                {
                    std::printf( " in=\"%s\"", ex( site.enclosing ).c_str() );
                }
                std::printf( "/>" );
            }
            std::printf( "</hit>" );
        }
        std::printf( "</f>" );
    }

    // ── §R-J: the aux block — files OUTSIDE the index (see unindexed_files_scanned= above), wrapped in its
    // OWN <unindexed> element (helper above) rather than left as bare <f> rows appended to the indexed
    // list. That boundary is load-bearing, not decoration: without it a reader (or a naive tag-walker)
    // cannot tell an indexed hit from a query/config file the crawl never parsed, which is exactly the
    // ambiguity complete= and in='s honesty rules exist to prevent elsewhere in this answer. Printed
    // strictly AFTER the indexed block (indexed source always outranks a query/config file for a reader's
    // attention) — and deliberately never folded/collapsed like grepGroupByFile does above: the candidate
    // population is already crawl-bounded (kMaxSkipRowsPerClass), so the folding machinery would add
    // complexity for a set too small to need it. No in= — see GrepAuxHit's own comment in search.h for why
    // that is a missing FIELD, not an omitted attribute.
    emitGrepUnindexed( aux.hits, singleRoot, rootPrefix, esc );

    // ── R1b: the <enc> block — the map's context on the answer, no second call (helper above) ──────
    const GrepEncOptions encOpt{ amp, tested, cfg.grepHandles,
                                cfg.roots.size() == 1 ? cfg.roots[0] : std::string_view(), esc };
    emitGrepEncRows( ing, g, std::span<const GrepHit>( hits ), encOpt );

    // ── R1a: the zero-hit follow-up — suggestions, labeled as such, never matches (helper above) ───
    // §R-J: also suppressed when the AUX block found the pattern — a real hit in queries/cpp/tags.scm is not
    // a zero-hit answer just because it sits outside the index, and printing SUGGESTIONS beside real matches
    // would misdescribe an answer that already found what it was looking for.
    if( hitCount == 0 && aux.hits.empty() )
    {
        emitGrepSuggest( ing, pat, cfg.grepRegex, esc );
    }
    std::printf( "</grep>" );
    return 0;
}

std::optional<int> runGrep( const MainDispatch& d )
{
    if( d.cfg.grep.empty() )
    {
        return std::nullopt; // not this verb — fall through the dispatch chain
    }
    // body: emitGrepReport() above. amp/tested are non-null only when a co-run (--metrics) computed
    // them at dispatch build time — grep itself never asks for the analysis (R1's no-new-analysis rule).
    return emitGrepReport( d.cfg, d.ing, d.g, d.ampPtr, d.testedPtr, d.grepPhases );
}

}   // namespace — verbs_grep.h section of main.cpp
