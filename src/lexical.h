#pragma once

// lexical.h — subtoken (camelCase / snake_case) BM25 over symbols, for `--query` / `--for` retrieval.
// The eval-at-scale showed lexical name-overlap beats pure graph structure for "find related code", so the
// relevance path is lexical and is NOT fused with PageRank (the eval showed fusion HURTS relatedness —
// importance ≠ relevance). Each symbol's BM25 doc = its name subtokens + callees' names + its DOC-COMMENT
// and BODY text, so a query matches code by what it DOES, not just what it's named. Deterministic.

#include "model.h"
#include "lexindex.h"           // B0: the ONE subtoken state machine + docCommentStart + persisted-stats types
#include "profileScope.h"       // PROFILE_SCOPE self-profiling — gated by PROFILE_ENABLED (off unless -DRIPWIRE_PROFILE=ON)
#include "sortutil.h"           // deterministic sanitizer-clean score sorting for adaptive cuts

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <functional>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace rw
{

// split an identifier into lowercase subtokens on camelCase / digit / non-alnum boundaries.
// "updateCollisionPositionVelocity" → [update, collision, position, velocity]; "_max_speed" → [max, speed].
inline void subtokens( std::string_view id, std::vector<std::string>& out )
{
    std::string cur;
    const auto  flush = [ & ] { if( cur.size() >= 2 ) out.push_back( cur ); cur.clear(); };
    for( unsigned char c : id )
    {
        const bool upper = c >= 'A' && c <= 'Z';
        const bool lower = c >= 'a' && c <= 'z';
        const bool digit = c >= '0' && c <= '9';
        if( !upper && !lower && !digit ) { flush(); continue; }                       // separator
        if( upper && !cur.empty() && !( cur.back() >= 'A' && cur.back() <= 'Z' ) ) flush();   // camel boundary
        cur.push_back( char( upper ? c - 'A' + 'a' : c ) );
    }
    flush();
}

// docCommentStart moved to lexindex.h (B0.2): the index-time stats builder must scan the EXACT spans this
// header's Pass 2 scans, so the span logic lives beside the shared tokenizer. Still visible here (include).

// R4 (AUDIT5 research lane): weak-result honesty threshold. When the --for lens's TOP-ranked match's raw
// BM25 score falls below this, the lexical evidence behind the whole ranking is too thin to trust — the
// header says so (weak="1") instead of silently presenting a plausible-looking but ungrounded top-K, so the
// calling agent knows to reformulate rather than trust the ranking. Calibrated empirically (2026-07-22) by
// running --for against this repo's own src/ and the test fixture corpora:
//   * exact-symbol-name and multi-word conceptual queries mined from each corpus's own vocabulary score
//     5-24 on src/ and 1.1-5.6 on the small test fixtures — notably the two EXISTING golden-gate queries
//     score 5.01 (routecheck's "how does resolution work" on test/routefix) and 5.58 (anchorcheck's
//     "frobnicate widget cache" on test/anchorfix);
//   * pure-gibberish queries with zero corpus overlap (misspelled symbols, made-up words) score EXACTLY 0
//     on every corpus tried — BM25 has nothing to accumulate.
// The valley sits between "0 (a genuine miss, or a sliver of incidental single-token noise)" and "the
// observed strong-query floor (~5 even on tiny fixtures)". kWeakLexicalScoreThreshold is set well BELOW that
// floor for margin — conservative per the product rule "under-fire, don't cry wolf": a query that clears 1.0
// has real, non-incidental lexical grounding somewhere in the corpus.
inline constexpr float kWeakLexicalScoreThreshold = 1.0f;

// BM25 score of `query` against each symbol's doc (name subtokens + callees' names + DOC-COMMENT & BODY
// text). Returns a per-symbol score vector (size = symbols.size()). Cold path: one query.
//
// Only the QUERY's few subtokens ever reach the scoring loop, so instead of tokenizing the whole corpus
// into per-doc HashMap<string,int> (the old shape: every file's text → per-token strings → S maps + a
// global dfreq map — ~0.5 s and hundreds of MB on a 1800-file repo), we stream each field ONCE through the
// same subtoken state machine as subtokens() and keep only integers: dl[i] (weighted subtoken count = BM25
// doc length) and tfFlat[i][u] (weighted term frequency of the query's unique tokens). Integer counts are
// exact so fill order is free, and the per-doc float arithmetic below runs in strict doc order with the
// SAME expressions as before → byte-identical scores.
// pruneTopK (B0 round 2, H2 — MaxScore-style SAFE early termination, PLAN_researchImprove2026 B0.4 /
// research/2026-07/R1-retrieval-cost.md §3): when > 0, the caller only consumes the top-pruneTopK ranked
// symbols (plus `alwaysExact` — e.g. every interface packLego may surface), so symbols that PROVABLY
// cannot enter that top-K skip the exact double-precision scoring (their slot stays the same +0.0f the
// exhaustive loop would produce for a no-match doc — but here even matching docs below the bound are
// skipped). Safety is absolute, not approximate: the emitted top-K set, their EXACT scores, and their
// (score desc, id asc) order are byte-identical to exhaustive scoring — see the bound derivation at the
// pruned loop. 0 = exhaustive (every earlier call site, --query, evals). RIPWIRE_NO_PRUNE=1 in the
// environment force-disables pruning (the postingscheck equivalence gate flips it).
// symbolScoreMul (§P4 tier de-prioritization, filter.h rankTierSymbolMultipliers): an optional per-symbol
// (0,1] multiplier applied exactly where the Section down-weight is — INSIDE the scoring loop, so MaxScore
// pruning stays provably safe (a shrink-only factor never lifts a score above its impact bound) and the
// pruned/exhaustive branches stay byte-identical to each other. nullptr (every non-lens caller: evals,
// exemplar kind-donation, --recall) = the pre-§P4 scores, byte for byte. The tiered form is a SEPARATE
// entry point (not a 7th parameter on lexicalScores) so the widely-called public contract keeps its arity;
// lexicalScores below forwards here with no multiplier.
inline std::vector<float> lexicalScoresTiered( const IngestResult& ing, const std::vector<std::uint32_t>& outOff,
                                               const std::vector<NodeId>& outTargets, std::string_view query,
                                               std::size_t pruneTopK, const std::vector<char>* alwaysExact,
                                               const std::vector<float>* symbolScoreMul )
{
    PROFILE_SCOPE_DESCRIBE( "lexical: lexicalScores (BM25 over symbols)" );
    const std::size_t S = ing.symbols.size();

    // query subtokens — occurrence order preserved (BM25 adds one contribution PER occurrence, as before);
    // an empty query scores exactly 0 everywhere (0.0 survives the Section down-weight unchanged)
    std::vector<std::string> qToks;
    subtokens( query, qToks );
    if( qToks.empty() ) return std::vector<float>( S, 0.f );

    // dedupe to the unique terms whose statistics we need — a duplicated query word must not double-count
    // tf, but still contributes once PER OCCURRENCE in the scoring loop (uniqueIndexOfQtok maps back)
    std::vector<std::string> uniqueToks;
    std::vector<std::size_t> uniqueIndexOfQtok( qToks.size() );
    for( std::size_t qi = 0; qi < qToks.size(); ++qi )
    {
        const auto found      = std::find( uniqueToks.begin(), uniqueToks.end(), qToks[qi] );
        uniqueIndexOfQtok[qi] = std::size_t( found - uniqueToks.begin() );
        if( found == uniqueToks.end() ) uniqueToks.push_back( qToks[qi] );
    }
    const std::size_t uniqueCount = uniqueToks.size();

    // per-doc integer stats (SoA): dl[i] = weighted subtoken count, tfFlat[i*uniqueCount+u] = weighted term
    // frequency of unique query token u in doc i
    std::vector<int> dl( S, 0 );
    std::vector<int> tfFlat( S * uniqueCount, 0 );

    // Field weights: a query term in a symbol's NAME outranks one in its DOC-COMMENT, which outranks one
    // buried in its BODY — so an exactly-named function beats a struct that merely mentions the word, and an
    // algorithm beats a comment-dense enum (the "keyword magnet" the review flagged). BM25 tf accumulates
    // these weighted contributions; dl is weighted to match, so length normalization stays consistent.
    // Doc/body weights are the SHARED constants (lexindex.h) — the index-time stats builder must weigh
    // those two fields identically or the postings path would diverge from this scan.
    constexpr int kwName = 3, kwCallee = 1, kwDoc = kLexWeightDoc, kwBody = kLexWeightBody;

    // stream one field through the ONE shared state machine (lexindex.h forEachLexSubtoken — the same
    // tokenizer subtokens() mirrors and the B0.2 index-time builder uses): a token is a maximal [optional
    // uppercase][lowercase/digit]* run between separators, so only a token's FIRST byte can be uppercase,
    // which the matcher exploits. Tokens shorter than 2 bytes are dropped, exactly like subtokens().
    // No strings, no maps — just in-place span-vs-query compares.
    const auto scanField = [ & ]( std::size_t docIndex, std::string_view text, int w )
    {
        int* const tfRow        = tfFlat.data() + docIndex * uniqueCount;
        int        fieldTokenWt = 0;
        forEachLexSubtoken( text, [ & ]( std::size_t tokStartByte, std::size_t tokEndByte )
        {
            const std::size_t tokLen = tokEndByte - tokStartByte;
            if( tokLen < 2 ) return;
            fieldTokenWt += w;
            const char* tok  = text.data() + tokStartByte;
            const char  head = ( tok[0] >= 'A' && tok[0] <= 'Z' ) ? char( tok[0] - 'A' + 'a' ) : tok[0];
            for( std::size_t u = 0; u < uniqueCount; ++u )
            {
                const std::string& q = uniqueToks[u];
                if( q.size() == tokLen && q[0] == head && std::memcmp( q.data() + 1, tok + 1, tokLen - 1 ) == 0 )
                {
                    tfRow[u] += w;
                    break;                            // unique tokens are distinct → at most one can match
                }
            }
        } );
        dl[ docIndex ] += fieldTokenWt;
    };

    // pass 1 — name (×kwName) + callee-name (×kwCallee) fields need no file text
    for( std::size_t i = 0; i < S; ++i )
    {
        scanField( i, ing.symbols[i].name, kwName );
        for( std::uint32_t e = outOff[i]; e < outOff[i + 1]; ++e )
            scanField( i, ing.symbols[ outTargets[e] ].name, kwCallee );
    }

    // pass 2 — doc-comment (×kwDoc) + body (×kwBody) evidence.
    //
    // B0.2 (R1 hypothesis #1): a RICH ingest carries per-symbol weighted subtoken statistics built ONCE at
    // parse/cache time — from the SAME byte spans through the SAME state machine — so the per-query work
    // here is pure lookups: no file re-read, no corpus re-tokenize (the O(corpus-bytes) per-query term is
    // gone). The stored dl/tf values are the exact integers the scan branch would accumulate, and the float
    // scoring loop below is shared, so the two branches are byte-identical (test/postingscheck.sh).
    if( ing.hasLexStats && ing.lexTokenRowOffsets.size() == S + 1 && ing.lexDocBodyDl.size() == S )
    {
        PROFILE_SCOPE_DESCRIBE( "lexical: pass 2 via persisted subtoken stats (cached tf/dl, no corpus re-tokenize)" );

        // dl first: BM25 length normalization needs EVERY doc's weighted length whether or not it matches
        // the query (avgdl sums them all), so this runs unconditionally — exact stored integers.
        for( std::size_t i = 0; i < S; ++i ) dl[i] += int( ing.lexDocBodyDl[i] );

        // query-token hashes — the same normalized-lowercase hash index time used. try_emplace keeps the
        // FIRST unique index on the astronomically-unlikely 64-bit collision between two DISTINCT query
        // tokens, so both transfer strategies below agree deterministically.
        std::vector<std::uint64_t>            uniqueHash( uniqueCount );
        HashMap<std::uint64_t, std::uint32_t> uniqueIndexOfHash;
        uniqueIndexOfHash.reserve( uniqueCount );
        for( std::size_t u = 0; u < uniqueCount; ++u )
        {
            uniqueHash[u] = lexSubtokenHash( uniqueToks[u].data(), uniqueToks[u].size() );
            uniqueIndexOfHash.try_emplace( uniqueHash[u], std::uint32_t( u ) );
        }

        // B0.1 per-file pre-filter: skip a whole file's tf walks when its 512-bit signature excludes every
        // query subtoken — no false negatives (dl above is already complete; tf for such a file is provably
        // zero), and a false positive just walks the cheap stats rows. Symbol ids are file-contiguous
        // (assigned in fileId,line,name order), so the test amortizes to one signature check per file.
        const bool    useFileSig       = ing.lexFileSig.size() == ing.files.size() * kLexFileSigWords;
        std::uint32_t lastFileId       = kNoNode;
        bool          lastFileMayMatch = true;
        for( std::size_t i = 0; i < S; ++i )
        {
            const std::uint32_t rowBegin = ing.lexTokenRowOffsets[i];
            const std::uint32_t rowEnd   = ing.lexTokenRowOffsets[ i + 1 ];
            if( rowBegin == rowEnd ) continue;                             // no doc/body tokens → nothing to transfer

            // one membership probe per FILE against the query's subtoken bits (B0.1)
            if( const std::uint32_t f = ing.symbols[i].fileId; useFileSig && f < ing.files.size() )
            {
                if( f != lastFileId )
                {
                    lastFileId       = f;
                    lastFileMayMatch = false;
                    const std::uint64_t* sig = ing.lexFileSig.data() + std::size_t( f ) * kLexFileSigWords;
                    for( std::size_t u = 0; u < uniqueCount && !lastFileMayMatch; ++u )
                        if( sig[ lexSigWord( uniqueHash[u] ) ] & lexSigBit( uniqueHash[u] ) ) lastFileMayMatch = true;
                }
                if( !lastFileMayMatch ) continue;
            }

            // exact tf transfer — walk whichever side is smaller: probe the query map per stored token, or
            // binary-search each DISTINCT query hash in the symbol's sorted row. Identical sums either way
            // (the map dedupes hash-colliding query tokens for both strategies).
            int* const           tfRow   = tfFlat.data() + i * uniqueCount;
            const std::uint64_t* rowHash = ing.lexTokenHashes.data();
            if( std::size_t( rowEnd - rowBegin ) <= uniqueCount * 8 )      // ~log2(row) probes vs one map probe per entry
            {
                for( std::uint32_t e = rowBegin; e < rowEnd; ++e )
                    if( const auto it = uniqueIndexOfHash.find( rowHash[e] ); it != uniqueIndexOfHash.end() )
                        tfRow[ it->second ] += int( ing.lexTokenTfs[e] );
            }
            else
            {
                for( const auto& [ hash, u ] : uniqueIndexOfHash )         // iteration order is score-irrelevant: rows are disjoint per u
                {
                    const std::uint64_t* lo = rowHash + rowBegin;
                    const std::uint64_t* hi = rowHash + rowEnd;
                    if( const std::uint64_t* it = std::lower_bound( lo, hi, hash ); it != hi && *it == hash )
                        tfRow[u] += int( ing.lexTokenTfs[ std::size_t( it - rowHash ) ] );
                }
            }
        }
    }
    else
    {
        // scan branch (lean ingests, --no-cache lean verbs, multi-root merges, stubs): CSR file→symbol
        // index, then stream ONE file at a time touching only that file's symbols — peak memory is a single
        // file's text, not the whole corpus held at once (symbol order within a file is irrelevant: integer
        // counts commute exactly).
        const std::size_t          fileCount = ing.files.size();
        std::vector<std::uint32_t> fileRowOffsets( fileCount + 1, 0 );
        for( std::size_t i = 0; i < S; ++i )
            if( ing.symbols[i].fileId < fileCount ) ++fileRowOffsets[ ing.symbols[i].fileId + 1 ];
        for( std::size_t f = 0; f < fileCount; ++f ) fileRowOffsets[ f + 1 ] += fileRowOffsets[f];
        std::vector<std::uint32_t> fileSymbolIds( fileRowOffsets[ fileCount ] );
        {
            std::vector<std::uint32_t> writeCursor( fileRowOffsets.begin(), fileRowOffsets.end() - 1 );
            for( std::size_t i = 0; i < S; ++i )
                if( ing.symbols[i].fileId < fileCount ) fileSymbolIds[ writeCursor[ ing.symbols[i].fileId ]++ ] = std::uint32_t( i );
        }
        // Files stream across a small worker pool: each worker holds ONE file's text at a time, and a file's
        // symbols are touched only by the worker that claimed the file — every dl[i] / tfFlat row has exactly
        // ONE writer (no locks needed). Determinism: all pooled writes are exact integer counts and the float
        // scoring below stays single-threaded in doc order, so worker scheduling cannot change a byte of
        // output (no cross-doc float reductions — the det-gate rule).
        const auto scanFileSymbols = [ & ]( std::size_t f, const std::string& src )
        {
            const std::string_view sv = src;
            for( std::uint32_t r = fileRowOffsets[f]; r < fileRowOffsets[ f + 1 ]; ++r )
            {
                const std::size_t i         = fileSymbolIds[r];
                const Symbol&     s         = ing.symbols[i];
                const std::size_t bodyStart = std::min<std::size_t>( s.sigStartByte, src.size() );
                const std::size_t end       = std::min<std::size_t>( s.endByte, src.size() );
                const std::size_t docStart  = docCommentStart( src, bodyStart );
                if( bodyStart > docStart ) scanField( i, sv.substr( docStart, bodyStart - docStart ), kwDoc );
                if( end > bodyStart )      scanField( i, sv.substr( bodyStart, end - bodyStart ), kwBody );
            }
        };
        std::atomic<std::size_t> nextFileIndex { 0 };
        const auto               fileWorker = [ & ]
        {
            try
            {
                std::string loadedText;
                for( std::size_t f = nextFileIndex.fetch_add( 1 ); f < fileCount; f = nextFileIndex.fetch_add( 1 ) )
                {
                    if( fileRowOffsets[f] == fileRowOffsets[ f + 1 ] ) continue;   // no symbols in this file → skip
                    // P1-B: a document file (notebook/html/csv) is indexed by its EXTRACTED text, not its raw
                    // bytes, so a query matches the notebook's prose/code, not its JSON envelope (read-only
                    // lookup — docText is never written here, so concurrent finds are safe).
                    if( const auto it = ing.docText.find( std::uint32_t( f ) ); it != ing.docText.end() )
                    {
                        if( !it->second.empty() ) scanFileSymbols( f, it->second );
                        continue;
                    }
                    loadedText.clear();
                    std::ifstream in( diskPath( ing, std::uint32_t( f ) ), std::ios::binary );
                    if( in ) { std::ostringstream ss; ss << in.rdbuf(); loadedText = ss.str(); }
                    if( !loadedText.empty() ) scanFileSymbols( f, loadedText );    // unreadable/empty → degrade (skip), as before
                }
            }
            catch( ... )   // a throw escaping a worker thread is std::terminate — degrade to partial counts instead
            {
                std::fprintf( stderr, "ripwire: lexical scan worker degraded (exception swallowed)\n" );
            }
        };
        const std::size_t hwThreadCount = std::thread::hardware_concurrency();
        const std::size_t workerCount   = std::min( { hwThreadCount ? hwThreadCount : 1, fileCount ? fileCount : 1, std::size_t( 16 ) } );
        if( workerCount <= 1 ) fileWorker();
        else
        {
            // symmetric bare scope: workers live exactly as long as the pooled scan
            std::vector<std::thread> workers;
            workers.reserve( workerCount );
            for( std::size_t w = 0; w < workerCount; ++w ) workers.emplace_back( fileWorker );
            for( std::thread& worker : workers ) worker.join();
        }
    }

    // corpus stats — avgdl accumulates in the SAME doc order as before (identical doubles); dfreq[u] =
    // number of docs containing unique query token u (w ≥ 1, so tf > 0 ⇔ the old docs[i] contained it)
    double avgdl = 0; for( int d : dl ) avgdl += d;  avgdl /= double( S ? S : 1 );

    constexpr double   k1 = 1.5, b = 0.75;
    std::vector<float> score( S, 0.f );

    // ── H2 (B0 round 2): MaxScore-style safe pruning — only when the caller opted in AND the env
    //    escape hatch is off. The exhaustive branch below is the pre-H2 code, byte-for-byte.
    const bool pruneActive = pruneTopK > 0 && std::getenv( "RIPWIRE_NO_PRUNE" ) == nullptr;
    if( pruneActive )
    {
        // one pass: candidates (any tf > 0 — every other doc scores EXACTLY the same +0.0f either way),
        // exact dfreq, and the per-term max weighted tf the impact bound needs. Ascending doc id.
        std::vector<int>           dfreq( uniqueCount, 0 );
        std::vector<int>           tfMaxOf( uniqueCount, 0 );
        std::vector<std::uint32_t> candidateIds;
        candidateIds.reserve( 1024 );
        for( std::size_t i = 0; i < S; ++i )
        {
            const int* tfRow = tfFlat.data() + i * uniqueCount;
            bool       any   = false;
            for( std::size_t u = 0; u < uniqueCount; ++u )
                if( tfRow[u] > 0 ) { ++dfreq[u]; if( tfRow[u] > tfMaxOf[u] ) tfMaxOf[u] = tfRow[u]; any = true; }
            if( any ) candidateIds.push_back( std::uint32_t( i ) );
        }

        // ── the PROVABLY-SAFE per-term impact bound (the MaxScore "max contribution") ────────────────
        // A term u's contribution to any doc is idf_u × tf(k1+1)/(tf + k1(1−b+b·dl/avgdl)). Two exact
        // monotonicities bound it: it INCREASES in tf (so tf ≤ T := tfMaxOf[u], the largest weighted tf
        // of u anywhere in the corpus) and DECREASES in dl (dl ≥ 0 ⇒ the mixed factor ≥ 1−b), giving
        //   contribution ≤ idf_u × T(k1+1)/(T + k1(1−b))   in REAL arithmetic.
        // In IEEE doubles each side is computed with ≤ 7 rounded ops (relative error ≤ 7·2⁻⁵³ ≈ 8e-16),
        // so the ×(1+1e-9) slack — six orders of magnitude above the worst accumulated rounding, and
        // likewise above the U·2⁻⁵³ summation error of the per-doc bound sum below — makes the COMPUTED
        // cap strictly ≥ the COMPUTED contribution. The Section ×0.30 down-weight and the §P4 tier
        // multiplier (both (0,1], shrink-only) only shrink a real score, never the bound.
        // Hence: bound < θ ⇒ computed score < θ, unconditionally.
        // capOcc folds in the query-occurrence multiplicity (BM25 adds one contribution PER occurrence).
        std::vector<double> capOcc( uniqueCount, 0.0 );
        {
            std::vector<int> occCount( uniqueCount, 0 );
            for( std::size_t qi = 0; qi < qToks.size(); ++qi ) ++occCount[ uniqueIndexOfQtok[qi] ];
            for( std::size_t u = 0; u < uniqueCount; ++u )
            {
                if( dfreq[u] == 0 ) continue;                    // never contributes anywhere
                const int    n    = dfreq[u];
                const double idf  = std::log( ( double( S ) - n + 0.5 ) / ( n + 0.5 ) + 1.0 );
                const double T    = double( tfMaxOf[u] );
                const double cap1 = idf * ( T * ( k1 + 1.0 ) ) / ( T + k1 * ( 1.0 - b ) ) * ( 1.0 + 1e-9 );
                capOcc[u]         = cap1 * double( occCount[u] );
            }
        }

        // top-K threshold θ = K-th best exact score seen so far (min-heap; grows monotonically). θ at
        // skip time ≤ final θ ≤ the true K-th best overall, and skipping needs bound < θ STRICTLY, so a
        // skipped doc's true score is strictly below the final K-th score — it cannot enter the top-K
        // even via the (score desc, id asc) tie-break. Docs are processed in ascending id (determinism).
        std::vector<double> heap;                                // min-heap over exact final scores
        heap.reserve( pruneTopK );
        double theta = -1.0;                                     // scores are ≥ 0 ⇒ no skips until K docs scored
        for( const std::uint32_t i : candidateIds )
        {
            const int* tfRow = tfFlat.data() + std::size_t( i ) * uniqueCount;

            // cheap upper bound: adds only, fixed u-ascending order (deterministic)
            double ub = 0.0;
            for( std::size_t u = 0; u < uniqueCount; ++u )
                if( tfRow[u] > 0 ) ub += capOcc[u];
            const bool mustScore = alwaysExact && i < alwaysExact->size() && (*alwaysExact)[i] != 0;
            if( !mustScore && ub < theta ) continue;             // provably cannot enter the top-K → skip

            // exact score — the IDENTICAL expressions, in the IDENTICAL order, as the exhaustive branch
            double sc = 0;
            for( std::size_t qi = 0; qi < qToks.size(); ++qi )
            {
                const std::size_t u  = uniqueIndexOfQtok[qi];
                const int         tf = tfRow[u];
                if( tf == 0 ) continue;
                const int    n   = dfreq[u];
                const double idf = std::log( ( double( S ) - n + 0.5 ) / ( n + 0.5 ) + 1.0 );
                sc += idf * ( tf * ( k1 + 1.0 ) ) / ( tf + k1 * ( 1.0 - b + b * dl[i] / ( avgdl > 0 ? avgdl : 1.0 ) ) );
            }
            if( ing.symbols[i].kind == SymKind::Section ) sc *= 0.30;
            if( symbolScoreMul && i < symbolScoreMul->size() ) sc *= double( (*symbolScoreMul)[i] );   // §P4 tier down-weight — shrink-only, bound-safe
            score[i] = float( sc );

            if( heap.size() < pruneTopK )
            {
                heap.push_back( sc );
                std::push_heap( heap.begin(), heap.end(), std::greater<double>{} );
                if( heap.size() == pruneTopK ) theta = heap.front();
            }
            else if( sc > heap.front() )
            {
                std::pop_heap( heap.begin(), heap.end(), std::greater<double>{} );
                heap.back() = sc;
                std::push_heap( heap.begin(), heap.end(), std::greater<double>{} );
                theta = heap.front();
            }
        }
        return score;
    }

    std::vector<int> dfreq( uniqueCount, 0 );
    for( std::size_t i = 0; i < S; ++i )
        for( std::size_t u = 0; u < uniqueCount; ++u )
            if( tfFlat[ i * uniqueCount + u ] > 0 ) ++dfreq[u];

    for( std::size_t i = 0; i < S; ++i )
    {
        double sc = 0;
        for( std::size_t qi = 0; qi < qToks.size(); ++qi )
        {
            const std::size_t u  = uniqueIndexOfQtok[qi];
            const int         tf = tfFlat[ i * uniqueCount + u ];
            if( tf == 0 ) continue;                       // old: docs[i].find( qt ) == end
            const int    n   = dfreq[u];
            const double idf = std::log( ( double( S ) - n + 0.5 ) / ( n + 0.5 ) + 1.0 );
            sc += idf * ( tf * ( k1 + 1.0 ) ) / ( tf + k1 * ( 1.0 - b + b * dl[i] / ( avgdl > 0 ? avgdl : 1.0 ) ) );
        }
        // Markdown headings (sec) compete on name-match with code; down-weight so a doc stays FINDABLE but
        // code wins when both match — fixes prose swamping retrieval in doc-heavy repos (review finding #4).
        if( ing.symbols[i].kind == SymKind::Section ) sc *= 0.30;
        if( symbolScoreMul && i < symbolScoreMul->size() ) sc *= double( (*symbolScoreMul)[i] );   // §P4 tier down-weight (same factor as the pruned branch)
        score[i] = float( sc );
    }
    return score;
}

// the un-tiered contract every pre-§P4 caller keeps (evals, exemplar, --recall): same arity as always,
// byte-identical scores (a null multiplier is the identity in both scoring branches above).
inline std::vector<float> lexicalScores( const IngestResult& ing, const std::vector<std::uint32_t>& outOff,
                                         const std::vector<NodeId>& outTargets, std::string_view query,
                                         std::size_t pruneTopK = 0, const std::vector<char>* alwaysExact = nullptr )
{
    return lexicalScoresTiered( ing, outOff, outTargets, query, pruneTopK, alwaysExact, nullptr );
}

// ─── whole-name / name-exact BM25 (EXPERIMENTAL, --route's identifier-query ranker) ──────────────────
//
// lexicalScores() above SUBTOKENIZES both the query and each symbol's document, so "buildGraph" matches
// any symbol whose name/body contains "build" OR "graph". That is right for CONCEPTUAL queries but wrong
// when the query LITERALLY NAMES a symbol: there you want the symbol whose WHOLE name is "buildGraph",
// not every builder and every graph. This variant scores the query — tokenized on WHITESPACE only, NOT
// subtokenized — against each symbol's document = its WHOLE lowercased name (one token; and its
// container::name as a second whole token when a scope exists, so "graph::buildgraph" can also match).
// Same BM25 constants (k1=1.5, b=0.75) and the same Section down-weight as lexicalScores. bench/
// ANSWERQUALITY.md's co-change table shows whole-name BM25 wins at deeper k — but that is a SEED-based
// finding, so this ships only behind --route (experimental) until query-time evidence justifies it.
//
// Deterministic: integer tf/df counts (fill order free) + single-threaded float scoring in doc order.
// symbolScoreMul: same §P4 tier down-weight as lexicalScoresTiered (same separate-entry-point shape: the
// public 2-arg lexicalScoresNameExact keeps its arity and forwards below). A fixture symbol queried by its
// EXACT name stays findable — its competitors score 0 (no other whole name matches), so shrinking the hit
// cannot bury it; when a source symbol and a fixture stub share a name, the source one now wins the tie.
inline std::vector<float> lexicalScoresNameExactTiered( const IngestResult& ing, std::string_view query,
                                                        const std::vector<float>* symbolScoreMul )
{
    PROFILE_SCOPE_DESCRIBE( "lexical: lexicalScoresNameExact (whole-name BM25 over symbols)" );
    const std::size_t S = ing.symbols.size();

    // query tokens: split on WHITESPACE only, lowercased, ≥2 bytes (parallels the ≥2 rule of subtokens()).
    // NOT subtokenized — a query token like "buildGraph" stays one token so it can equal a whole name.
    std::vector<std::string> qToks;
    {
        std::string cur;
        const auto  flush = [ & ] { if( cur.size() >= 2 ) qToks.push_back( cur ); cur.clear(); };
        for( unsigned char c : query )
        {
            if( c == ' ' || c == '\t' || c == '\n' || c == '\r' ) { flush(); continue; }
            cur.push_back( ( c >= 'A' && c <= 'Z' ) ? char( c - 'A' + 'a' ) : char( c ) );
        }
        flush();
    }
    if( qToks.empty() ) return std::vector<float>( S, 0.f );

    // dedupe to unique terms (one df/tf statistic each); each occurrence still contributes in the loop
    std::vector<std::string> uniqueToks;
    std::vector<std::size_t> uniqueIndexOfQtok( qToks.size() );
    for( std::size_t qi = 0; qi < qToks.size(); ++qi )
    {
        const auto found      = std::find( uniqueToks.begin(), uniqueToks.end(), qToks[qi] );
        uniqueIndexOfQtok[qi] = std::size_t( found - uniqueToks.begin() );
        if( found == uniqueToks.end() ) uniqueToks.push_back( qToks[qi] );
    }
    const std::size_t uniqueCount = uniqueToks.size();

    // per-doc integer stats (SoA): dl[i] = whole-name token count (1, or 2 with a scope), tfFlat = weighted tf
    std::vector<int> dl( S, 0 );
    std::vector<int> tfFlat( S * uniqueCount, 0 );

    // lowercase-compare a symbol's whole name (one token) against every unique query token
    const auto matchWholeName = [ & ]( std::size_t i, std::string_view name )
    {
        if( name.size() < 2 ) return;                         // mirror the ≥2 drop
        int* const tfRow = tfFlat.data() + i * uniqueCount;
        ++dl[i];
        for( std::size_t u = 0; u < uniqueCount; ++u )
        {
            const std::string& q = uniqueToks[u];
            if( q.size() != name.size() ) continue;
            bool eq = true;
            for( std::size_t k = 0; k < name.size() && eq; ++k )
            {
                const unsigned char nc = static_cast<unsigned char>( name[k] );
                const char          lc = ( nc >= 'A' && nc <= 'Z' ) ? char( nc - 'A' + 'a' ) : char( nc );
                if( lc != q[k] ) eq = false;
            }
            if( eq ) { ++tfRow[u]; break; }                   // unique tokens distinct → at most one match
        }
    };

    // document = whole name (+ container::name as a second whole token, when a scope exists)
    for( std::size_t i = 0; i < S; ++i )
    {
        const Symbol& s = ing.symbols[i];
        matchWholeName( i, s.name );
        if( !s.scope.empty() )
        {
            std::string qualified = s.scope;
            qualified += "::";
            qualified += s.name;
            matchWholeName( i, qualified );
        }
    }

    // corpus stats (same doc order → identical doubles); dfreq[u] = #docs containing unique token u
    double avgdl = 0; for( int d : dl ) avgdl += d;  avgdl /= double( S ? S : 1 );
    std::vector<int> dfreq( uniqueCount, 0 );
    for( std::size_t i = 0; i < S; ++i )
        for( std::size_t u = 0; u < uniqueCount; ++u )
            if( tfFlat[ i * uniqueCount + u ] > 0 ) ++dfreq[u];

    constexpr double   k1 = 1.5, b = 0.75;
    std::vector<float> score( S, 0.f );
    for( std::size_t i = 0; i < S; ++i )
    {
        double sc = 0;
        for( std::size_t qi = 0; qi < qToks.size(); ++qi )
        {
            const std::size_t u  = uniqueIndexOfQtok[qi];
            const int         tf = tfFlat[ i * uniqueCount + u ];
            if( tf == 0 ) continue;
            const int    n   = dfreq[u];
            const double idf = std::log( ( double( S ) - n + 0.5 ) / ( n + 0.5 ) + 1.0 );
            sc += idf * ( tf * ( k1 + 1.0 ) ) / ( tf + k1 * ( 1.0 - b + b * dl[i] / ( avgdl > 0 ? avgdl : 1.0 ) ) );
        }
        if( ing.symbols[i].kind == SymKind::Section ) sc *= 0.30;   // same prose down-weight as lexicalScores
        if( symbolScoreMul && i < symbolScoreMul->size() ) sc *= double( (*symbolScoreMul)[i] );   // §P4 tier down-weight
        score[i] = float( sc );
    }
    return score;
}

// the un-tiered name-exact contract (--route, evals): unchanged arity, byte-identical scores.
inline std::vector<float> lexicalScoresNameExact( const IngestResult& ing, std::string_view query )
{
    return lexicalScoresNameExactTiered( ing, query, nullptr );
}

// ─── deterministic, confidence-GATED query-shape router (--route) ─────────────────────────────────────
//
// Which ranker fits THIS query? A pure, transparent RULE (not ML) — no wall-clock, no RNG — so the same
// query always routes the same way.
//
// THE FAILURE THE GATE FIXES: the first router escalated to name-exact whenever ANY query word case-
// insensitively equalled SOME symbol name. Common words (map / node / file / score) coincide with symbol
// names, so a genuinely CONCEPTUAL phrase ("serialize the ranked map") got mis-routed to name-exact — where
// whole-name BM25 has nothing to match a prose phrase against and COLLAPSES (--eval-retrieval measured
// routed/doc-phrase MRR 0.42 src / 0.14 root vs subtoken+body's 0.99 / 0.81). The "some symbol shares this
// word" trigger is too eager: one incidental coincidence is not evidence the query NAMES a symbol.
//
// THE GATE (confidence-gated routing, kept in lock-step with the printed `reason`):
//   1. Drop tiny stopwords; count the remaining CONTENT words = nWords.
//   2. A content word is a STRONG identifier signal iff EITHER
//        (a) it is camelCase / snake_case shaped — explicit identifier SYNTAX, unambiguous intent; OR
//        (b) it case-insensitively equals an existing symbol's WHOLE name (it literally names a symbol).
//   3. Route to NAME-EXACT only when the query is DOMINATED by identifier signal — either
//        • it carries explicit camelCase/snake syntax in a short lookup-shaped query, OR
//        • EVERY content word is a whole-name symbol hit (nWords>=1 and wholeNameHits==nWords).
//      Otherwise fall back to SUBTOKEN+BODY.
//   4. Reason for the gate's shape: a conceptual doc-phrase of N>=3 words carries at most an INCIDENTAL
//      coincidence or two (wholeNameHits < nWords by construction — the prose words that aren't symbol names
//      break the "all words name symbols" test), so it falls back by construction — this fixes the crater
//      WITHOUT a tuned magic number. A real identifier query is short and its content words ARE the symbols,
//      so wholeNameHits==nWords holds and it routes. "All content words name symbols" is a strict, principled
//      whole-query confidence test, not a per-word OR — that inversion (all, not any) is the whole fix.
//      (A single generic word that happens to equal a symbol name — "map" — still routes to name-exact, which
//      is correct: a one-word query whose only word IS a symbol name is an identifier lookup, and name-exact
//      is the measured winner on that shape; the crater was multi-word phrases, not single-word lookups.)
enum class LexMode { SubtokenBody, NameExact };
struct RouteChoice { LexMode which = LexMode::SubtokenBody; std::string reason; };

// is `w` a single stopword we ignore when counting query intent words?
inline bool isRouteStopword( std::string_view w ) noexcept
{
    static constexpr std::string_view kStop[] = {
        "the", "a", "an", "is", "are", "to", "of", "in", "for", "how",
        "does", "do", "where", "what", "which", "on", "with" };
    for( std::string_view s : kStop ) if( w == s ) return true;
    return false;
}

// lowercase a short token into a caller buffer (identifiers are short; no allocation churn in the hot loop)
inline std::string routeLower( std::string_view w )
{
    std::string out( w );
    for( char& c : out ) if( c >= 'A' && c <= 'Z' ) c = char( c - 'A' + 'a' );
    return out;
}

inline RouteChoice chooseForRanker( const IngestResult& ing, std::string_view query )
{
    // split query on whitespace into raw words (case preserved — camelCase detection needs it)
    std::vector<std::string_view> words;
    {
        std::size_t start = std::string_view::npos;
        for( std::size_t k = 0; k <= query.size(); ++k )
        {
            const bool sep = k == query.size() || query[k] == ' ' || query[k] == '\t' || query[k] == '\n' || query[k] == '\r';
            if( sep ) { if( start != std::string_view::npos ) { words.push_back( query.substr( start, k - start ) ); start = std::string_view::npos; } }
            else if( start == std::string_view::npos ) start = k;
        }
    }

    // Count non-stopword CONTENT words. For each, decide whether it is a STRONG identifier signal:
    //   • an explicit camelCase/snake token (decisive only in a short lookup-shaped query), or
    //   • a case-insensitive WHOLE-name symbol hit (the word literally IS a symbol name).
    // We accumulate wholeNameHits (words that name a symbol) and record the first explicit-syntax token, then
    // apply the confidence gate: route to name-exact only when identifier signal DOMINATES the whole query
    // (an explicit camel/snake token in a short query, or every content word is a whole-name hit), never on
    // one incidental coincidence buried in prose.
    std::size_t nWords          = 0;
    std::size_t wholeNameHits   = 0;                           // content words that equal an existing symbol name
    bool        hasCamelSnake   = false;                       // any content word is camelCase / snake_case shaped
    std::string identifierHit;                                 // the token that best evidences the name-exact route (for the reason)

    // Build ONE lowercase-name SET over all symbols ONCE per query (was: a routeLower(s.name) heap
    // allocation per size-matched symbol per word below — O(contentWords × symbols) allocations, millions
    // on a 100k-symbol tree). A single membership probe per word replaces the O(symbols) linear scan; the
    // routed-vs-plain decision is unchanged (it was, and remains, a pure "does this word name a symbol"
    // membership test).
    ankerl::unordered_dense::set<std::string> lowerSymbolNames;
    lowerSymbolNames.reserve( ing.symbols.size() );
    for( const Symbol& s : ing.symbols )
        lowerSymbolNames.insert( routeLower( s.name ) );

    for( std::string_view w : words )
    {
        const std::string lw = routeLower( w );
        if( isRouteStopword( lw ) ) continue;
        ++nWords;

        // camelCase / snake_case shape: an interior uppercase (aB) or an interior underscore (a_b)
        bool camel = false, snake = false;
        for( std::size_t k = 1; k < w.size(); ++k )
        {
            const char c = w[k];
            if( c >= 'A' && c <= 'Z' && w[k - 1] >= 'a' && w[k - 1] <= 'z' ) camel = true;
            if( c == '_' && k + 1 < w.size() ) snake = true;
        }
        if( camel || snake )
        {
            hasCamelSnake = true;
            if( identifierHit.empty() ) identifierHit = std::string( w );
            ++wholeNameHits;                                   // explicit identifier syntax also counts toward "all words name symbols"
            continue;
        }

        // else: does the token (case-insensitively) equal an existing symbol's WHOLE name? then it names one.
        if( lowerSymbolNames.find( lw ) != lowerSymbolNames.end() )
        {
            ++wholeNameHits;
            if( identifierHit.empty() ) identifierHit = std::string( w );
        }
    }

    // CONFIDENCE GATE: identifier signal must DOMINATE the whole query, not just appear once in it.
    //   • explicit camel/snake syntax is decisive only in a SHORT lookup-shaped query. Long issue prose,
    //     stack traces, and review prompts routinely contain one identifier among many intent words; treating
    //     that incidental token as the whole query discards every prose/body term.
    //   • every content word is a whole-name symbol hit (nWords>=1 and wholeNameHits==nWords).
    // A conceptual phrase fails BOTH (it has prose words that name no symbol), so it falls back — by
    // construction, no tuned constant. The threshold IS the structure of the query, which is the point.
    constexpr std::size_t kMaxIdentifierLookupWords = 2;
    const bool nameExact = ( hasCamelSnake && nWords <= kMaxIdentifierLookupWords )
                        || ( nWords >= 1 && wholeNameHits == nWords );

    RouteChoice rc;
    if( nameExact )
    {
        rc.which  = LexMode::NameExact;
        rc.reason = "name-exact BM25 — query names a symbol (" + identifierHit + ")";
    }
    else if( nWords >= 3 )
    {
        rc.which  = LexMode::SubtokenBody;
        rc.reason = "subtoken+body BM25 (--for's default) — no strong name hit, multi-word conceptual query";
    }
    else
    {
        rc.which  = LexMode::SubtokenBody;
        rc.reason = "subtoken+body BM25 (--for's default) — no strong name hit; broad query, plain rg may also win";
    }
    return rc;
}

// ── Adaptive-k relevance-cliff cut (RESEARCH_outputEconomy §2 / lever 2; arXiv 2506.08479) ────────────
// --for/--query sorts by a blended lens score then groups by file and DISCARDS the score, so the "cliff"
// (where a sharp query's few relevant hits give way to a long low-score tail) is unobservable. A fixed
// top-k is provably wrong at BOTH ends: too generous for a sharp query (~75% tail), meaningless for a
// broad common-word query where the score saturates and NO knee exists. Adaptive-k cuts at the largest
// RELATIVE score gap within [floor, ceiling] — a sharp query keeps few, a flat/broad one hits the ceiling
// (cap-and-note; the measured broad case has no knee, so the ceiling is the honest answer, not a cut).
// Pure function of the score vector → deterministic. Never emits an empty set (floor >= 1).
struct AdaptiveCut
{
    std::size_t kept       = 0;      // how many top-ranked symbols to keep (in [floor, ceiling])
    std::size_t cliffRank  = 0;      // 1-based rank AT which the cut was made (== kept when a real cliff drove it)
    int         dropPct    = 0;      // the relative drop at the cliff, as a whole percent (0 ⇒ hit the ceiling, no knee)
    bool        hitCeiling = false;  // true ⇒ no knee beat the flat-tail heuristic; capped at ceiling (broad query)
    std::size_t positiveHits = 0;    // how many symbols scored > 0 for this query (the natural cap: a sharp query
                                     // often has FEWER positive hits than the ceiling — kept==positiveHits then)
};

// scores: the lens rank vector (per-symbol, unsorted). floor/ceiling bound the kept count.
//
// scanFullDistribution (default false — --query's exposed-score behavior is unchanged): when true, the cliff
// scan runs over the ENTIRE positive-score distribution, not just the top `ceilingK`, THEN the resulting kept
// count is clamped into [floor, ceiling]. This is the fix for --for (RESEARCH lever 2 follow-up): --for caps
// at 40 and the sharp query's real cliff often sits BELOW the cap while the head within 40 is flat — so a scan
// bounded at the cap finds no knee and keeps 40/40 (inert). Scanning the raw distribution finds the true cliff
// (a sharp query's head is small, so kept clamps down to few; a broad query saturates → no knee → ceiling).
// --query does NOT set this: its ceiling is already the full map top-k, so its scan already covers the
// meaningful range and its measured behavior (sharp cuts, broad keeps all) must stay byte-identical.
inline AdaptiveCut adaptiveCut( const std::vector<float>& scores, std::size_t floorK, std::size_t ceilingK,
                                bool scanFullDistribution = false )
{
    AdaptiveCut cut;

    // positive scores only, sorted DESC (id tie-break is irrelevant to the gap analysis — pure magnitudes).
    std::vector<float> pos;
    pos.reserve( scores.size() );
    for( float s : scores ) if( s > 0.f ) pos.push_back( s );
    sortutil::radixSortNonNegativeFloatsDesc( pos );

    // clamp the working ceiling to what actually has positive score (a query with few hits can't keep more).
    const std::size_t avail = pos.size();
    cut.positiveHits = avail;
    if( avail == 0 ) { cut.kept = std::min( floorK, ceilingK ); cut.cliffRank = cut.kept; cut.hitCeiling = true; return cut; }
    std::size_t hardCeil = std::min( ceilingK, avail );
    if( hardCeil < floorK ) hardCeil = std::min( floorK, avail );   // floor may exceed the few available hits
    const std::size_t f = std::min( floorK, hardCeil );

    // How far to scan for the cliff: bounded at the ceiling by default (--query), or across the FULL raw
    // positive distribution when scanFullDistribution (--for) — so a cliff sitting below the cap is still seen.
    const std::size_t scanEnd = scanFullDistribution ? avail : hardCeil;

    // scan the candidate cut positions over [1, scanEnd): find the index i where the RELATIVE drop from the
    // previous score is largest — that's the cliff. A cut "at rank i" keeps ranks [1, i] (i symbols). We scan
    // from rank 1 (not the floor) so a sharp head-cliff BELOW the floor is still detected — the floor then
    // clamps the kept count up (so an ultra-sharp query keeps exactly the floor, NOT the whole ceiling:
    // everything past the pre-floor cliff is tail we deliberately drop).
    // Two candidates are tracked in one pass: the WITHIN-CAP cliff (bestCap*, i restricted to < hardCeil) is
    // the only one eligible to actually cut — a cut has to land inside the window we can return. The GLOBAL
    // cliff (best*, i up to scanEnd) can sit beyond hardCeil in full-distribution mode; it never drives the
    // cut, only the honesty flag (A4-F4: previously the single global-max drop was used for BOTH roles, so a
    // routine 90%+ tail drop beyond hardCeil silently starved the in-cap material cliff of ever being chosen —
    // the mode was inert on exactly the sharp queries it exists for).
    std::size_t bestCutKept    = 0;
    double      bestDrop       = 0.0;
    std::size_t bestCapCutKept = 0;
    double      bestCapDrop    = 0.0;
    for( std::size_t i = 1; i < scanEnd; ++i )
    {
        const double prev = double( pos[ i - 1 ] );
        const double here = double( pos[ i ] );
        const double drop = prev > 0.0 ? ( prev - here ) / prev : 0.0;
        if( drop > bestDrop ) { bestDrop = drop; bestCutKept = i; }               // cut BEFORE rank i+1 ⇒ keep i
        if( i < hardCeil && drop > bestCapDrop ) { bestCapDrop = drop; bestCapCutKept = i; }
    }

    // require a MATERIAL cliff to cut below the ceiling (avoid cutting on trivial float noise). ~20% relative
    // drop is a conservative "conceptual query" knee (RESEARCH §2); below that the tail is flat → keep ceiling.
    constexpr double kMinCliffDrop = 0.20;
    if( bestCapDrop >= kMinCliffDrop )
    {
        // A real cliff WITHIN the cap → cut there, even if a larger drop exists beyond hardCeil (that one
        // can't be honored as a cut anyway — there's nothing past the ceiling in the output). Clamp UP to floor.
        cut.kept       = std::max( bestCapCutKept, f );
        cut.cliffRank  = bestCapCutKept;                // TRUE cliff rank (may be < kept when floor-clamped)
        cut.dropPct    = int( bestCapDrop * 100.0 + 0.5 );
        cut.hitCeiling = false;
    }
    else
    {
        cut.kept       = hardCeil;                     // flat/broad OR the only real cliff is beyond the cap
        cut.cliffRank  = hardCeil;
        // honesty flag only: if the global scan found a material cliff beyond hardCeil, surface its magnitude
        // even though we cannot cut there (the window can't shrink past what the caller asked to see).
        cut.dropPct    = ( bestDrop >= kMinCliffDrop ) ? int( bestDrop * 100.0 + 0.5 ) : 0;
        cut.hitCeiling = true;
    }
    if( cut.kept < f )  cut.kept = f;   // floor guard (never below the floor)
    return cut;
}

}   // namespace rw
