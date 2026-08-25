#pragma once

// lexical.h — subtoken (camelCase / snake_case) BM25 over symbols, for `--query` / `--for` retrieval.
// The eval-at-scale showed lexical name-overlap beats pure graph structure for "find related code", so the
// relevance path is lexical and is NOT fused with PageRank (the eval showed fusion HURTS relatedness —
// importance ≠ relevance). Each symbol's BM25 doc = its name subtokens + callees' names + its DOC-COMMENT
// and BODY text, so a query matches code by what it DOES, not just what it's named. Deterministic.

#include "model.h"
#include "lexindex.h"            // B0: the ONE subtoken state machine + docCommentStart + persisted-stats types
#include "infra/profileScope.h"  // PROFILE_SCOPE self-profiling — gated by PROFILE_ENABLED (off unless -DRIPWIRE_PROFILE=ON)
#include "infra/sortutil.h"      // deterministic sanitizer-clean score sorting for adaptive cuts

#include <algorithm>
#include <atomic>
#include <bit>
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
//
// An UPPERCASE RUN IS ONE TOKEN (the ACRONYMWord rule, 2026-08-19). "MCP" → [mcp], "HTTPServer" →
// [http, server], "IOError" → [io, error], "XMLHttpRequest" → [xml, http, request]: only the LAST
// uppercase of a run of ≥2 starts a new token, and only when a lowercase letter follows it. Until
// 2026-08-19 the camel test compared against `cur.back()` — the ALREADY-LOWERCASED accumulator, whose
// last byte can never be uppercase — so the "previous byte was uppercase" guard was dead code and every
// acronym came apart into 1-byte fragments that the `size() >= 2` rule then dropped. `subtokens("MCP")`
// returned NOTHING, which is why a SKILL.md description about MCP indexed zero `mcp` tokens. The
// previous byte's case now lives in its own flag, where lowercasing cannot erase it.
// Registered + measured: docs/EVALS.md §4 "Subtoken acronym shredding"; gate: test/subtokencheck.sh.
// The rule is naminglens.h::splitIdentifier's, so the repo's two identifier splitters agree.
//
// This DELEGATES to lexindex.h's forEachLexSubtoken rather than restating the state machine. It used to
// restate it, and the acronym bug is what that cost: three hand-kept copies of one rule, one of which
// (this one) compared against a lowercased accumulator and so lost the case information the rule needs.
// Appends to `out` (does not clear) — every caller either passes a fresh vector or clears it first.
inline void subtokens( std::string_view id, std::vector<std::string>& out )
{
    forEachLexSubtoken( id, [ & ]( std::size_t tokStartByte, std::size_t tokEndByte )
    {
        const std::size_t tokLen = tokEndByte - tokStartByte;
        if( tokLen < 2 )
        {
            return;                                       // the ≥2-byte drop, applied by every consumer
        }
        std::string tok;
        tok.reserve( tokLen );
        for( std::size_t k = tokStartByte; k < tokEndByte; ++k )
        {
            tok.push_back( char( lexLowerByte( static_cast<unsigned char>( id[k] ) ) ) );
        }
        out.push_back( std::move( tok ) );
    } );
}

// docCommentStart moved to lexindex.h (B0.2): the index-time stats builder must scan the EXACT spans this
// header's Pass 2 scans, so the span logic lives beside the shared tokenizer. Still visible here (include).

// R4: weak-result honesty threshold. When the --for lens's TOP-ranked match's raw
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
// pruneTopK (B0 round 2, H2 — MaxScore-style SAFE early termination): when > 0, the caller only consumes the top-pruneTopK ranked
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
// defined with the LB-2 anchor-plausibility machinery below; the LB-3 variant guard reuses the bound
inline std::uint32_t routeCarrierCap( const IngestResult& ing ) noexcept;

inline std::vector<float> lexicalScoresTiered( const IngestResult& ing, const std::vector<std::uint32_t>& outOff,
                                               const std::vector<NodeId>& outTargets, std::string_view query,
                                               std::size_t pruneTopK, const std::vector<char>* alwaysExact,
                                               const std::vector<float>* symbolScoreMul, int pathFieldDefaultW = 0,
                                               int basenameFieldDefaultW = 0 )
{
    PROFILE_SCOPE_DESCRIBE( "lexical: lexicalScores (BM25 over symbols)" );
    const std::size_t S = ing.symbols.size();

    // query subtokens — occurrence order preserved (BM25 adds one contribution PER occurrence, as before);
    // an empty query scores exactly 0 everywhere (0.0 survives the Section down-weight unchanged)
    std::vector<std::string> qToks;
    subtokens( query, qToks );
    if( qToks.empty() )
    {
        return std::vector<float>( S, 0.f );
    }

    // dedupe to the unique terms whose statistics we need — a duplicated query word must not double-count
    // tf, but still contributes once PER OCCURRENCE in the scoring loop (uniqueIndexOfQtok maps back)
    std::vector<std::string> uniqueToks;
    std::vector<std::size_t> uniqueIndexOfQtok( qToks.size() );
    for( std::size_t qi = 0; qi < qToks.size(); ++qi )
    {
        const auto found      = std::find( uniqueToks.begin(), uniqueToks.end(), qToks[qi] );
        uniqueIndexOfQtok[qi] = std::size_t( found - uniqueToks.begin() );
        if( found == uniqueToks.end() )
        {
            uniqueToks.push_back( qToks[qi] );
        }
    }
    const std::size_t uniqueCount = uniqueToks.size();

    // ── LB-3 arm S: conservative query-side stem variants ─────────────────────────────────────────────
    // A plural/participle query token ("splits", "resolved", "hoisting") cannot exact-match the singular
    // subtoken a compound name carries (SplitChunksPlugin → split; resolve.h → resolve) — the measured
    // LB-3 anatomy (bench/r7 + r8, three independent confirmations). Variants are QUERY-side only and
    // score into the ORIGINAL token's tf/idf row, so corpus stats and the cache format are untouched.
    // ONE shared table drives the scan branch, the persisted-stats branch, and every field pass —
    // parity by construction (test/postingscheck.sh; armed arm in test/lb3namecheck.sh). A variant
    // string already claimed by an earlier token (or equal to any exact token) is dropped, first-wins,
    // so a doc token maps to exactly one row in either branch. RIPWIRE_QSTEM=1 arms it; the shipped
    // default stays OFF until the LB-3 acceptance verdict (scratchpad lb3/preregistration.md) lands.
    struct LexMatchTok
    {
        std::string   tok;
        std::uint32_t u;
    };
    std::vector<LexMatchTok> matchToks;
    matchToks.reserve( uniqueCount * 2 );
    for( std::size_t u = 0; u < uniqueCount; ++u )
    {
        matchToks.push_back( { uniqueToks[u], std::uint32_t( u ) } );
    }
    {
        const char* qstemEnv = std::getenv( "RIPWIRE_QSTEM" );
        const bool  qstemOn  = qstemEnv != nullptr && *qstemEnv == '1';
        // derived variants are CANDIDATES first: admission into the match table happens only after the
        // IDF guard below — the guard sees the deduped candidate set, never the user's exact tokens
        std::vector<LexMatchTok> stemCandidates;
        const auto  pushVariant = [ & ]( std::string v, std::uint32_t u )
        {
            if( v.size() < 3 )
            {
                return;                                        // sub-3-byte stems are noise, frozen rule
            }
            for( const LexMatchTok& mt : matchToks )
            {
                if( mt.tok == v )
                {
                    return;                                    // first-wins: string already claimed
                }
            }
            for( const LexMatchTok& cand : stemCandidates )
            {
                if( cand.tok == v )
                {
                    return;                                    // first-wins among candidates too
                }
            }
            stemCandidates.push_back( { std::move( v ), u } );
        };
        const auto isConsonant = []( char c )
        {
            return c >= 'a' && c <= 'z' && c != 'a' && c != 'e' && c != 'i' && c != 'o' && c != 'u';
        };
        if( qstemOn )
        {
            for( std::size_t u = 0; u < uniqueCount; ++u )
            {
                const std::string& t    = uniqueToks[u];
                const std::size_t  L    = t.size();
                const auto         ends = [ & ]( std::string_view suf )
                { return L >= suf.size() && t.compare( L - suf.size(), suf.size(), suf ) == 0; };
                if( ends( "s" ) && !ends( "ss" ) && L >= 4 )
                {
                    pushVariant( t.substr( 0, L - 1 ), std::uint32_t( u ) );          // splits → split
                    if( ends( "es" ) && L >= 5 )
                    {
                        pushVariant( t.substr( 0, L - 2 ), std::uint32_t( u ) );      // classes → class
                    }
                }
                if( ends( "ed" ) && L >= 5 )
                {
                    pushVariant( t.substr( 0, L - 1 ), std::uint32_t( u ) );          // resolved → resolve
                    pushVariant( t.substr( 0, L - 2 ), std::uint32_t( u ) );          // parsed → pars (rarely useful, harmless)
                    if( L >= 6 && t[L - 3] == t[L - 4] && isConsonant( t[L - 3] ) )
                    {
                        pushVariant( t.substr( 0, L - 3 ), std::uint32_t( u ) );      // flagged → flag
                    }
                }
                if( ends( "ing" ) && L >= 6 )
                {
                    pushVariant( t.substr( 0, L - 3 ), std::uint32_t( u ) );                // hoisting → hoist
                    pushVariant( t.substr( 0, L - 3 ) + "e", std::uint32_t( u ) );          // caching → cache
                    if( L >= 7 && t[L - 4] == t[L - 5] && isConsonant( t[L - 4] ) )
                    {
                        pushVariant( t.substr( 0, L - 4 ), std::uint32_t( u ) );            // running → run
                    }
                }
            }
        }
        // ── IDF guard, rung R3 (LB-3 retry, scratchpad lb3retry/preregistration.md) ──────────────────
        // The un-guarded round measured the failure: a corpus-common variant ("split" on webpack) hands
        // its term-frequency mass to every competitor whose doc/body rides the same subtoken, displacing
        // currently-hit truths (EVALS §7) — and the mass is BODY frequency (`.split()` call sites), which
        // is why the name-carrier bound (rungs R1/R2) measured too low to catch it. So every candidate
        // enters the match table PROVISIONALLY, owning its own tf column (m ≥ uniqueCount); admission is
        // decided AFTER pass 2, when both scoring branches have measured the variant's doc/body document
        // frequency as the SAME integers (postings rows on the rich path, the scan's own counts on the
        // lean path — parity by construction), and only a corpus-rare variant (df ≤ max(8, S/64)) is
        // folded into its original token's row; a common one is discarded untouched. The guard never
        // sees a user's EXACT query token — only derived variants — so it structurally cannot drop a
        // truth's own carrier (the LB-1 IDF-floor failure).
        for( LexMatchTok& cand : stemCandidates )
        {
            matchToks.push_back( std::move( cand ) );
        }
    }
    const std::size_t matchCount = matchToks.size();

    // per-doc integer stats (SoA): dl[i] = weighted subtoken count, tfFlat[i*matchCount+m] = weighted term
    // frequency of match-table row m in doc i. Disarmed, matchCount == uniqueCount and the layout is the
    // historical one byte-for-byte; armed, provisional variant columns sit at m ≥ uniqueCount until the
    // post-pass-2 guard folds the admitted ones and the array shrinks back to uniqueCount stride.
    std::vector<int> dl( S, 0 );
    std::vector<int> tfFlat( S * matchCount, 0 );

    // Field weights: a query term in a symbol's NAME outranks one in its DOC-COMMENT, which outranks one
    // buried in its BODY — so an exactly-named function beats a struct that merely mentions the word, and an
    // algorithm beats a comment-dense enum (the "keyword magnet" the review flagged). BM25 tf accumulates
    // these weighted contributions; dl is weighted to match, so length normalization stays consistent.
    // Doc/body weights are the SHARED constants (lexindex.h) — the index-time stats builder must weigh
    // those two fields identically or the postings path would diverge from this scan.
    constexpr int kwName = 3, kwCallee = 1, kwDoc = kLexWeightDoc, kwBody = kLexWeightBody;

    // stream one field through the ONE shared state machine (lexindex.h forEachLexSubtoken — the same
    // tokenizer subtokens() mirrors and the B0.2 index-time builder uses): a token is a maximal
    // alphanumeric run between separators, cut at a lower/digit → Upper transition and at the ACRONYMWord
    // seam. Tokens shorter than 2 bytes are dropped, exactly like subtokens().
    // No strings, no maps — just in-place span-vs-query compares. Since 2026-08-19 an all-caps run survives
    // as ONE token, so a span's INTERIOR bytes can be uppercase and memcmp alone would miss it; the memcmp
    // stays as the fast path (it resolves every ordinary identifier token) and only a span already agreeing
    // on length AND head falls through to lexTokenEqualsLowered — the rare acronym case, arm D's seam.
    const auto scanTextInto = [ & ]( int* tfRow, int& wtAccum, std::string_view text, int w )
    {
        int fieldTokenWt = 0;
        forEachLexSubtoken( text, [ & ]( std::size_t tokStartByte, std::size_t tokEndByte )
        {
            const std::size_t tokLen = tokEndByte - tokStartByte;
            if( tokLen < 2 )
            {
                return;
            }
            fieldTokenWt += w;
            const char* tok  = text.data() + tokStartByte;
            const char  head = ( tok[0] >= 'A' && tok[0] <= 'Z' ) ? char( tok[0] - 'A' + 'a' ) : tok[0];
            for( std::size_t m = 0; m < matchCount; ++m )
            {
                const std::string& q = matchToks[m].tok;
                if( q.size() == tokLen && q[0] == head
                    && ( std::memcmp( q.data() + 1, tok + 1, tokLen - 1 ) == 0 || lexTokenEqualsLowered( tok, tokLen, q.data() ) ) )
                {
                    tfRow[m] += w;                    // exact tokens own rows 0..uniqueCount (m == u there)
                    break;                            // table strings are distinct → at most one can match
                }
            }
        } );
        wtAccum += fieldTokenWt;
    };
    const auto scanField = [ & ]( std::size_t docIndex, std::string_view text, int w )
    {
        scanTextInto( tfFlat.data() + docIndex * matchCount, dl[ docIndex ], text, w );
    };

    // pass 1 — name (×kwName) + callee-name (×kwCallee) fields need no file text
    for( std::size_t i = 0; i < S; ++i )
    {
        scanField( i, ing.symbols[i].name, kwName );
        for( std::uint32_t e = outOff[i]; e < outOff[i + 1]; ++e )
        {
            scanField( i, ing.symbols[ outTargets[e] ].name, kwCallee );
        }
    }

    // pass 1.5 — path field (×kwPath): the symbol's file path scanned through the SAME state machine.
    // pathFieldDefaultW is the CALLER's lens decision: the RECALL lens (docs) passes 1 — a query naming a
    // "readme" / "report" / "paired table" should be able to hit the doc whose PATH says exactly that, and
    // bench/recalleval/ is the instrument that measured the +0.03 lenient-MRR / doc-sibling recovery this
    // buys (2026-08-03, gate: test/recallevalcheck.sh). The CODE lenses (--for and friends) still pass 0:
    // a nonzero default THERE requires the pre-registered locbench acceptance gate
    // (bench/locbench/results/r3_pathtok/PREREG.md), unchanged. RIPWIRE_PATHTOK_W overrides either default
    // for calibration sweeps only. Paths need no file text, so the pass sits before the branch below and
    // runs identically over the scan and persisted-stats paths — postings parity holds by construction and
    // the cache format is untouched.
    {
        int kwPath = pathFieldDefaultW;
        if( const char* pathTokEnv = std::getenv( "RIPWIRE_PATHTOK_W" ) )
        {
            kwPath = std::clamp( std::atoi( pathTokEnv ), 0, 8 );
        }
        if( kwPath > 0 )
        {
            for( std::size_t i = 0; i < S; ++i )
            {
                if( const std::uint32_t f = ing.symbols[i].fileId; f < ing.files.size() )
                {
                    scanField( i, ing.files[f], kwPath );
                }
            }
        }
    }

    // pass 1.6 — LB-3 arm B: basename-only field (×kwBase). The r3_pathtok retry, narrowed per that
    // round's own rejection note (bench/locbench/results/r3_pathtok/PREREG.md): FULL paths lost
    // held-out to generic-directory noise, so only the basename is scanned, and the scan is amortized
    // per FILE (each basename tokenized once, its row added per symbol) honoring r3's "amortize
    // first". Needs no file text → runs before the pass-2 branch split; parity and the cache format
    // untouched. RIPWIRE_BASENAME_W (0..8) overrides basenameFieldDefaultW; a nonzero shipped default
    // requires the LB-3 acceptance verdict (gate: test/lb3namecheck.sh).
    {
        int kwBase = basenameFieldDefaultW;
        if( const char* baseEnv = std::getenv( "RIPWIRE_BASENAME_W" ) )
        {
            kwBase = std::clamp( std::atoi( baseEnv ), 0, 8 );
        }
        if( kwBase > 0 )
        {
            const std::size_t fileCount = ing.files.size();
            std::vector<int>  fileTf( fileCount * matchCount, 0 );
            std::vector<int>  fileWt( fileCount, 0 );
            for( std::size_t f = 0; f < fileCount; ++f )
            {
                const std::string_view path = ing.files[f];
                const std::size_t      cut  = path.find_last_of( '/' );
                const std::string_view base = cut == std::string_view::npos ? path : path.substr( cut + 1 );
                scanTextInto( fileTf.data() + f * matchCount, fileWt[f], base, kwBase );
            }
            for( std::size_t i = 0; i < S; ++i )
            {
                const std::uint32_t f = ing.symbols[i].fileId;
                if( f >= fileCount || fileWt[f] == 0 )
                {
                    continue;
                }
                int* const       tfRow = tfFlat.data() + i * matchCount;
                const int* const fRow  = fileTf.data() + std::size_t( f ) * matchCount;
                for( std::size_t m = 0; m < matchCount; ++m )
                {
                    tfRow[m] += fRow[m];
                }
                dl[i] += fileWt[f];
            }
        }
    }

    // per-variant doc/body document frequency, measured by whichever pass-2 branch runs — the guard's
    // admission signal (rung R3). Both branches accumulate the same integers, so admission is identical.
    const std::size_t          variantCount = matchCount - uniqueCount;
    std::vector<std::uint32_t> dfVariant( variantCount, 0u );

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
        for( std::size_t i = 0; i < S; ++i )
        {
            dl[i] += int( ing.lexDocBodyDl[i] );
        }

        // query-token hashes — the same normalized-lowercase hash index time used, over the FULL match
        // table (exact tokens + LB-3 stem variants), each hash mapped to its own tf ROW (a variant's tf
        // lands in its provisional column; the post-pass-2 guard decides whether it folds into the
        // original token's row) — the same row targeting the scan branch's table walk applies.
        // try_emplace keeps the FIRST entry on the astronomically-unlikely 64-bit collision between two
        // DISTINCT table strings, so both transfer strategies below agree deterministically.
        std::vector<std::uint64_t>            matchHash( matchCount );
        HashMap<std::uint64_t, std::uint32_t> rowIndexOfHash;
        rowIndexOfHash.reserve( matchCount );
        for( std::size_t m = 0; m < matchCount; ++m )
        {
            matchHash[m] = lexSubtokenHash( matchToks[m].tok.data(), matchToks[m].tok.size() );
            rowIndexOfHash.try_emplace( matchHash[m], std::uint32_t( m ) );
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
            if( rowBegin == rowEnd )
            {
                continue; // no doc/body tokens → nothing to transfer
            }

            // one membership probe per FILE against the query's subtoken bits (B0.1)
            if( const std::uint32_t f = ing.symbols[i].fileId; useFileSig && f < ing.files.size() )
            {
                if( f != lastFileId )
                {
                    lastFileId       = f;
                    lastFileMayMatch = false;
                    const std::uint64_t* sig = ing.lexFileSig.data() + std::size_t( f ) * kLexFileSigWords;
                    for( std::size_t m = 0; m < matchCount && !lastFileMayMatch; ++m )
                    {
                        if( sig[lexSigWord( matchHash[m] )] & lexSigBit( matchHash[m] ) )
                        {
                            lastFileMayMatch = true;
                        }
                    }
                }
                if( !lastFileMayMatch )
                {
                    continue;
                }
            }

            // exact tf transfer — walk whichever side is smaller: probe the query map per stored token, or
            // binary-search each DISTINCT query hash in the symbol's sorted row. Identical sums either way
            // (the map dedupes hash-colliding query tokens for both strategies).
            int* const           tfRow   = tfFlat.data() + i * matchCount;
            const std::uint64_t* rowHash = ing.lexTokenHashes.data();
            if( std::size_t( rowEnd - rowBegin ) <= matchCount * 8 )       // ~log2(row) probes vs one map probe per entry
            {
                for( std::uint32_t e = rowBegin; e < rowEnd; ++e )
                {
                    if( const auto it = rowIndexOfHash.find( rowHash[e] ); it != rowIndexOfHash.end() )
                    {
                        tfRow[ it->second ] += int( ing.lexTokenTfs[e] );
                        if( it->second >= uniqueCount )
                        {
                            ++dfVariant[ it->second - uniqueCount ];       // stored rows hold each hash once → one df bump per symbol
                        }
                    }
                }
            }
            else
            {
                for( const auto& [ hash, m ] : rowIndexOfHash )            // iteration order is score-irrelevant: rows are disjoint per HASH (+= commutes)
                {
                    const std::uint64_t* lo = rowHash + rowBegin;
                    const std::uint64_t* hi = rowHash + rowEnd;
                    if( const std::uint64_t* it = std::lower_bound( lo, hi, hash ); it != hi && *it == hash )
                    {
                        tfRow[m] += int( ing.lexTokenTfs[ std::size_t( it - rowHash ) ] );
                        if( m >= uniqueCount )
                        {
                            ++dfVariant[ m - uniqueCount ];
                        }
                    }
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
        {
            if( ing.symbols[i].fileId < fileCount )
            {
                ++fileRowOffsets[ing.symbols[i].fileId + 1];
            }
        }
        for( std::size_t f = 0; f < fileCount; ++f )
        {
            fileRowOffsets[f + 1] += fileRowOffsets[f];
        }
        std::vector<std::uint32_t> fileSymbolIds( fileRowOffsets[ fileCount ] );
        {
            std::vector<std::uint32_t> writeCursor( fileRowOffsets.begin(), fileRowOffsets.end() - 1 );
            for( std::size_t i = 0; i < S; ++i )
            {
                if( ing.symbols[i].fileId < fileCount )
                {
                    fileSymbolIds[writeCursor[ing.symbols[i].fileId]++] = std::uint32_t( i );
                }
            }
        }
        // Files stream across a small worker pool: each worker holds ONE file's text at a time, and a file's
        // symbols are touched only by the worker that claimed the file — every dl[i] / tfFlat row has exactly
        // ONE writer (no locks needed). Determinism: all pooled writes are exact integer counts and the float
        // scoring below stays single-threaded in doc order, so worker scheduling cannot change a byte of
        // output (no cross-doc float reductions — the det-gate rule).
        // per-(file, variant) doc/body df tallies — a file's tally has exactly ONE writer (the worker
        // that claimed the file), merged single-threaded below in file order; integer sums commute, so
        // worker scheduling cannot change the totals (the det-gate rule). Sized only when armed.
        std::vector<std::uint32_t> dfPerFile( variantCount > 0 ? fileCount * variantCount : 0, 0u );
        const auto scanFileSymbols = [ & ]( std::size_t f, const std::string& src )
        {
            const std::string_view sv = src;
            std::vector<int>       variantTfBefore( variantCount );
            for( std::uint32_t r = fileRowOffsets[f]; r < fileRowOffsets[ f + 1 ]; ++r )
            {
                const std::size_t i         = fileSymbolIds[r];
                const Symbol&     s         = ing.symbols[i];
                const std::size_t bodyStart = std::min<std::size_t>( s.sigStartByte, src.size() );
                const std::size_t end       = std::min<std::size_t>( s.endByte, src.size() );
                const std::size_t docStart  = docCommentStart( src, bodyStart );
                if( variantCount > 0 )                 // snapshot the variant columns: df must count ONLY
                {                                      // pass-2 (doc/body) growth, never pass-1 name/callee tf
                    const int* tfRow = tfFlat.data() + i * matchCount + uniqueCount;
                    std::copy( tfRow, tfRow + variantCount, variantTfBefore.begin() );
                }
                if( bodyStart > docStart )
                {
                    scanField( i, sv.substr( docStart, bodyStart - docStart ), kwDoc );
                }
                if( end > bodyStart )
                {
                    scanField( i, sv.substr( bodyStart, end - bodyStart ), kwBody );
                }
                if( variantCount > 0 )
                {
                    const int* tfRow = tfFlat.data() + i * matchCount + uniqueCount;
                    for( std::size_t v = 0; v < variantCount; ++v )
                    {
                        if( tfRow[v] > variantTfBefore[v] )
                        {
                            ++dfPerFile[ f * variantCount + v ];
                        }
                    }
                }
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
                    if( fileRowOffsets[f] == fileRowOffsets[f + 1] )
                    {
                        continue; // no symbols in this file → skip
                    }
                    // P1-B: a document file (notebook/html/csv) is indexed by its EXTRACTED text, not its raw
                    // bytes, so a query matches the notebook's prose/code, not its JSON envelope (read-only
                    // lookup — docText is never written here, so concurrent finds are safe).
                    if( const auto it = ing.docText.find( std::uint32_t( f ) ); it != ing.docText.end() )
                    {
                        if( !it->second.empty() )
                        {
                            scanFileSymbols( f, it->second );
                        }
                        continue;
                    }
                    loadedText.clear();
                    std::ifstream in( diskPath( ing, std::uint32_t( f ) ), std::ios::binary );
                    if( in ) { std::ostringstream ss; ss << in.rdbuf(); loadedText = ss.str(); }
                    if( !loadedText.empty() )
                    {
                        scanFileSymbols( f, loadedText ); // unreadable/empty → degrade (skip), as before
                    }
                }
            }
            catch( ... )   // a throw escaping a worker thread is std::terminate — degrade to partial counts instead
            {
                std::fprintf( stderr, "ripwire: lexical scan worker degraded (exception swallowed)\n" );
            }
        };
        const std::size_t hwThreadCount = std::thread::hardware_concurrency();
        const std::size_t workerCount   = std::min( { hwThreadCount ? hwThreadCount : 1, fileCount ? fileCount : 1, std::size_t( 16 ) } );
        if( workerCount <= 1 )
        {
            fileWorker();
        }
        else
        {
            // symmetric bare scope: workers live exactly as long as the pooled scan
            std::vector<std::thread> workers;
            workers.reserve( workerCount );
            for( std::size_t w = 0; w < workerCount; ++w )
            {
                workers.emplace_back( fileWorker );
            }
            for( std::thread& worker : workers )
            {
                worker.join();
            }
        }
        for( std::size_t f = 0; f < fileCount && variantCount > 0; ++f )   // deterministic df merge, file order
        {
            for( std::size_t v = 0; v < variantCount; ++v )
            {
                dfVariant[v] += dfPerFile[ f * variantCount + v ];
            }
        }
    }

    // ── IDF-guard admission + fold (rung R3) — runs identically after EITHER pass-2 branch ──────────
    // A variant whose doc/body document frequency is corpus-common (df > max(8, S/64)) is discarded:
    // its provisional column is simply never folded, so its evidence — name, callee, path, basename,
    // doc, body — vanishes without touching dl (document length counts all subtokens scanned, never
    // matches). An admitted (corpus-rare) variant folds its column into the original token's row, the
    // exact integers the un-guarded arm would have accumulated there. The array then shrinks back to
    // uniqueCount stride, and everything below — corpus stats, both scoring branches — is untouched
    // code operating on the historical layout.
    if( variantCount > 0 )
    {
        const std::uint32_t sOver64    = std::uint32_t( S / 64 );
        const std::uint32_t variantCap = sOver64 > 8u ? sOver64 : 8u;
        if( std::getenv( "RIPWIRE_QSTEM_DEBUG" ) != nullptr )
        {
            for( std::size_t v = 0; v < variantCount; ++v )
            {
                std::fprintf( stderr, "qstem-guard: \"%s\" df=%u cap=%u %s\n",
                              matchToks[ uniqueCount + v ].tok.c_str(), dfVariant[v], variantCap,
                              dfVariant[v] <= variantCap ? "admitted" : "rejected" );
            }
        }
        std::vector<int> tfFolded( S * uniqueCount, 0 );
        for( std::size_t i = 0; i < S; ++i )
        {
            const int* const src = tfFlat.data() + i * matchCount;
            int* const       dst = tfFolded.data() + i * uniqueCount;
            for( std::size_t u = 0; u < uniqueCount; ++u )
            {
                dst[u] = src[u];
            }
            for( std::size_t v = 0; v < variantCount; ++v )
            {
                if( dfVariant[v] <= variantCap )
                {
                    dst[ matchToks[ uniqueCount + v ].u ] += src[ uniqueCount + v ];
                }
            }
        }
        tfFlat = std::move( tfFolded );
    }

    // corpus stats — avgdl accumulates in the SAME doc order as before (identical doubles); dfreq[u] =
    // number of docs containing unique query token u (w ≥ 1, so tf > 0 ⇔ the old docs[i] contained it)
    double avgdl = 0;
    for( int d : dl )
    {
        avgdl += d;
    }
    avgdl /= double( S ? S : 1 );

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
            {
                if( tfRow[u] > 0 )
                {
                    ++dfreq[u];
                    if( tfRow[u] > tfMaxOf[u] )
                    {
                        tfMaxOf[u] = tfRow[u];
                    }
                    any = true;
                }
            }
            if( any )
            {
                candidateIds.push_back( std::uint32_t( i ) );
            }
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
            for( std::size_t qi = 0; qi < qToks.size(); ++qi )
            {
                ++occCount[uniqueIndexOfQtok[qi]];
            }
            for( std::size_t u = 0; u < uniqueCount; ++u )
            {
                if( dfreq[u] == 0 )
                {
                    continue; // never contributes anywhere
                }
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
            {
                if( tfRow[u] > 0 )
                {
                    ub += capOcc[u];
                }
            }
            const bool mustScore = alwaysExact && i < alwaysExact->size() && (*alwaysExact)[i] != 0;
            if( !mustScore && ub < theta )
            {
                continue; // provably cannot enter the top-K → skip
            }

            // exact score — the IDENTICAL expressions, in the IDENTICAL order, as the exhaustive branch
            double sc = 0;
            for( std::size_t qi = 0; qi < qToks.size(); ++qi )
            {
                const std::size_t u  = uniqueIndexOfQtok[qi];
                const int         tf = tfRow[u];
                if( tf == 0 )
                {
                    continue;
                }
                const int    n   = dfreq[u];
                const double idf = std::log( ( double( S ) - n + 0.5 ) / ( n + 0.5 ) + 1.0 );
                sc += idf * ( tf * ( k1 + 1.0 ) ) / ( tf + k1 * ( 1.0 - b + b * dl[i] / ( avgdl > 0 ? avgdl : 1.0 ) ) );
            }
            if( ing.symbols[i].kind == SymKind::Section )
            {
                sc *= 0.30;
            }
            if( symbolScoreMul && i < symbolScoreMul->size() )
            {
                sc *= double( ( *symbolScoreMul )[i] ); // §P4 tier down-weight — shrink-only, bound-safe
            }
            score[i] = float( sc );

            if( heap.size() < pruneTopK )
            {
                heap.push_back( sc );
                std::push_heap( heap.begin(), heap.end(), std::greater<double>{} );
                if( heap.size() == pruneTopK )
                {
                    theta = heap.front();
                }
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
    {
        for( std::size_t u = 0; u < uniqueCount; ++u )
        {
            if( tfFlat[i * uniqueCount + u] > 0 )
            {
                ++dfreq[u];
            }
        }
    }

    for( std::size_t i = 0; i < S; ++i )
    {
        double sc = 0;
        for( std::size_t qi = 0; qi < qToks.size(); ++qi )
        {
            const std::size_t u  = uniqueIndexOfQtok[qi];
            const int         tf = tfFlat[ i * uniqueCount + u ];
            if( tf == 0 )
            {
                continue; // old: docs[i].find( qt ) == end
            }
            const int    n   = dfreq[u];
            const double idf = std::log( ( double( S ) - n + 0.5 ) / ( n + 0.5 ) + 1.0 );
            sc += idf * ( tf * ( k1 + 1.0 ) ) / ( tf + k1 * ( 1.0 - b + b * dl[i] / ( avgdl > 0 ? avgdl : 1.0 ) ) );
        }
        // Markdown headings (sec) compete on name-match with code; down-weight so a doc stays FINDABLE but
        // code wins when both match — fixes prose swamping retrieval in doc-heavy repos (review finding #4).
        if( ing.symbols[i].kind == SymKind::Section )
        {
            sc *= 0.30;
        }
        if( symbolScoreMul && i < symbolScoreMul->size() )
        {
            sc *= double( ( *symbolScoreMul )[i] ); // §P4 tier down-weight (same factor as the pruned branch)
        }
        score[i] = float( sc );
    }
    return score;
}

// the un-tiered contract every pre-§P4 caller keeps (evals, exemplar, --recall): same arity as always,
// byte-identical scores (a null multiplier is the identity in both scoring branches above).
inline std::vector<float> lexicalScores( const IngestResult& ing, const std::vector<std::uint32_t>& outOff,
                                         const std::vector<NodeId>& outTargets, std::string_view query,
                                         std::size_t pruneTopK = 0, const std::vector<char>* alwaysExact = nullptr,
                                         int pathFieldDefaultW = 0 )
{
    return lexicalScoresTiered( ing, outOff, outTargets, query, pruneTopK, alwaysExact, nullptr, pathFieldDefaultW );
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
        const auto flush = [ & ] { if( cur.size() >= 2 ) { qToks.push_back( cur ); } cur.clear(); };
        for( const char ch : query )   // EXPLICIT narrowing — see subtokens() above / hashutil.h
        {
            const unsigned char c = static_cast<unsigned char>( ch );
            if( c == ' ' || c == '\t' || c == '\n' || c == '\r' ) { flush(); continue; }
            cur.push_back( ( c >= 'A' && c <= 'Z' ) ? char( c - 'A' + 'a' ) : char( c ) );
        }
        flush();
    }
    if( qToks.empty() )
    {
        return std::vector<float>( S, 0.f );
    }

    // dedupe to unique terms (one df/tf statistic each); each occurrence still contributes in the loop
    std::vector<std::string> uniqueToks;
    std::vector<std::size_t> uniqueIndexOfQtok( qToks.size() );
    for( std::size_t qi = 0; qi < qToks.size(); ++qi )
    {
        const auto found      = std::find( uniqueToks.begin(), uniqueToks.end(), qToks[qi] );
        uniqueIndexOfQtok[qi] = std::size_t( found - uniqueToks.begin() );
        if( found == uniqueToks.end() )
        {
            uniqueToks.push_back( qToks[qi] );
        }
    }
    const std::size_t uniqueCount = uniqueToks.size();

    // per-doc integer stats (SoA): dl[i] = whole-name token count (1, or 2 with a scope), tfFlat = weighted tf
    std::vector<int> dl( S, 0 );
    std::vector<int> tfFlat( S * uniqueCount, 0 );

    // lowercase-compare a symbol's whole name (one token) against every unique query token
    const auto matchWholeName = [ & ]( std::size_t i, std::string_view name )
    {
        if( name.size() < 2 )
        {
            return; // mirror the ≥2 drop
        }
        int* const tfRow = tfFlat.data() + i * uniqueCount;
        ++dl[i];
        for( std::size_t u = 0; u < uniqueCount; ++u )
        {
            const std::string& q = uniqueToks[u];
            if( q.size() != name.size() )
            {
                continue;
            }
            bool eq = true;
            for( std::size_t k = 0; k < name.size() && eq; ++k )
            {
                const unsigned char nc = static_cast<unsigned char>( name[k] );
                const char          lc = ( nc >= 'A' && nc <= 'Z' ) ? char( nc - 'A' + 'a' ) : char( nc );
                if( lc != q[k] )
                {
                    eq = false;
                }
            }
            if( eq )
            {
                ++tfRow[u];
                break;
            } // unique tokens distinct → at most one match
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
    double avgdl = 0;
    for( int d : dl )
    {
        avgdl += d;
    }
    avgdl /= double( S ? S : 1 );
    std::vector<int> dfreq( uniqueCount, 0 );
    for( std::size_t i = 0; i < S; ++i )
    {
        for( std::size_t u = 0; u < uniqueCount; ++u )
        {
            if( tfFlat[i * uniqueCount + u] > 0 )
            {
                ++dfreq[u];
            }
        }
    }

    constexpr double   k1 = 1.5, b = 0.75;
    std::vector<float> score( S, 0.f );
    for( std::size_t i = 0; i < S; ++i )
    {
        double sc = 0;
        for( std::size_t qi = 0; qi < qToks.size(); ++qi )
        {
            const std::size_t u  = uniqueIndexOfQtok[qi];
            const int         tf = tfFlat[ i * uniqueCount + u ];
            if( tf == 0 )
            {
                continue;
            }
            const int    n   = dfreq[u];
            const double idf = std::log( ( double( S ) - n + 0.5 ) / ( n + 0.5 ) + 1.0 );
            sc += idf * ( tf * ( k1 + 1.0 ) ) / ( tf + k1 * ( 1.0 - b + b * dl[i] / ( avgdl > 0 ? avgdl : 1.0 ) ) );
        }
        if( ing.symbols[i].kind == SymKind::Section )
        {
            sc *= 0.30; // same prose down-weight as lexicalScores
        }
        if( symbolScoreMul && i < symbolScoreMul->size() )
        {
            sc *= double( ( *symbolScoreMul )[i] ); // §P4 tier down-weight
        }
        score[i] = float( sc );
    }
    return score;
}

// the un-tiered name-exact contract (--route, evals): unchanged arity, byte-identical scores.
inline std::vector<float> lexicalScoresNameExact( const IngestResult& ing, std::string_view query )
{
    return lexicalScoresNameExactTiered( ing, query, nullptr );
}

// ─── definition-over-declaration TIEBREAK (name-exact route only) ─────────────────────────────────────
//
// THE DEFECT, exactly (docs/EVALS.md §4, "Definition-over-declaration tiebreak on the name-exact route";
// upstream: the E6 demotion corpus's class-2b rows). The scorer above documents its own document: a
// symbol's WHOLE NAME, one token. That is the right document for an identifier query, and it is also why
// a bare `class ClientContext;` forward declaration and the real `class ClientContext { … }` definition
// are, to this ranker, THE SAME DOCUMENT. They score bit-for-bit identically, so the order between them
// is decided entirely by the fallback tie-break in sortutil::radixSortByScoreDescId — symbol id ascending,
// i.e. crawl order, i.e. path order. duckdb forward-declares ClientContext in 85 headers; measured at
// da61bac, all four ranked rows and the single body slot of `--for="ClientContext"` were bare
// declarations and the definition never appeared. The agent is handed the name it already typed.
//
// WHAT THIS IS, AND WHAT IT DELIBERATELY IS NOT. It is a TIEBREAK. It is not a demotion of declarations
// (a declaration whose name nothing defines is still the best answer to its own name — that is arm (c) of
// test/defoverdeclcheck.sh), it is not a filter (both declarations survive, in their original order —
// arm (b)), and it is not a rescoring (all four rows still report ONE score — arm (a)). The registered
// criterion that outranks the round's own band is that ORDER AMONG NON-TIED ROWS IS BYTE-IDENTICAL, and
// the four properties below are why that holds by construction rather than by measurement:
//
//   1. Only members of an EXACT tie are touched, so no two rows already separated by score can swap.
//   2. The demoted value is std::nextafter( v, 0 ) — the immediate float predecessor — so nothing can
//      land BETWEEN it and the group it left; and if that predecessor is already an occupied score
//      anywhere in the vector the group is REFUSED outright, so nothing can land ON an occupied value
//      either. The post-state's distinct-value set is the pre-state's plus injectively-new values.
//   3. Demotion fires only in MIXED groups, in which a body-carrying member keeps `v`. So max(score) is
//      invariant, and R4's weak-evidence honesty signal (kWeakLexicalScoreThreshold, read from
//      maxScoreUndoingTier over this vector) cannot move.
//   4. Within each side of the split, id-ascending order is untouched. The net effect is exactly a
//      stable partition of the tie group: bodies first, then declarations.
//
// WHY IT LIVES HERE AND NOT IN THE SORT. Every consumer of the ranked vector — <sigs>, <bodies>,
// <compose>, the JSON twin, --format=candidates, --pack-task, the MCP `for`/`explore` verbs — derives its
// order from this one vector through the same (score desc, id asc) rule. Threading a tie-break key
// through all of them would let one emitter acquire the fix and another not, and an incoherent bundle
// (signatures ordered one way, bodies another) is a worse failure than the defect. One seam, one order.
//
// The bodyless predicate is the house one, shared verbatim with graph.h's decl/def collapse and arch.h's
// pure-interface detection: `endByte > sigEndByte`. Deterministic — integer bit patterns, fixed doc
// order, no float arithmetic beyond one nextafter. Returns the number of rows demoted; 0 means the call
// was inert and the vector is byte-identical to what the scorer produced.
inline std::size_t applyDefOverDeclTiebreak( const IngestResult& ing, std::vector<float>& score )
{
    const std::size_t S = ing.symbols.size();
    if( score.size() != S || S == 0 )
    {
        return 0;
    }

    const auto hasBody = [ & ]( std::size_t i ) noexcept { return ing.symbols[i].endByte > ing.symbols[i].sigEndByte; };
    const auto scored  = [ & ]( std::size_t i ) noexcept { return score[i] > 0.f && std::isfinite( score[i] ); };

    // the distinct POSITIVE scores actually present, ascending. For positive finite floats the IEEE bit
    // pattern is itself an ascending numeric key, so this is one uint32 sort and no float comparison.
    std::vector<std::uint32_t> distinct;
    distinct.reserve( 64 );
    for( std::size_t i = 0; i < S; ++i )
    {
        if( scored( i ) )
        {
            distinct.push_back( std::bit_cast<std::uint32_t>( score[i] ) );
        }
    }
    if( distinct.empty() )
    {
        return 0;
    }
    std::sort( distinct.begin(), distinct.end() );
    distinct.erase( std::unique( distinct.begin(), distinct.end() ), distinct.end() );

    // which distinct values hold a body-carrying member, and which hold a bodyless one
    std::vector<std::uint8_t> sawBody( distinct.size(), 0 );
    std::vector<std::uint8_t> sawDecl( distinct.size(), 0 );
    const auto slotOf = [ & ]( std::size_t i ) noexcept
    {
        const std::uint32_t bits  = std::bit_cast<std::uint32_t>( score[i] );
        const auto          found = std::lower_bound( distinct.begin(), distinct.end(), bits );
        return std::size_t( found - distinct.begin() );
    };
    for( std::size_t i = 0; i < S; ++i )
    {
        if( scored( i ) )
        {
            ( hasBody( i ) ? sawBody : sawDecl )[ slotOf( i ) ] = 1;
        }
    }

    // decide once per distinct value, from the ORIGINAL set — so two demoting groups can never collide
    // with each other (nextafter is injective) nor with a value that was already there (the refusal).
    std::vector<float> demoteTo( distinct.size(), 0.f );
    bool               anyDemote = false;
    for( std::size_t u = 0; u < distinct.size(); ++u )
    {
        if( !sawBody[u] || !sawDecl[u] )
        {
            continue; // a pure-declaration tie has nothing to prefer; a pure-definition tie has nothing to demote
        }
        const float value = std::bit_cast<float>( distinct[u] );
        const float lower = std::nextafter( value, 0.f );
        if( !( lower > 0.f ) || !std::isfinite( lower ) )
        {
            continue; // DEGRADE: no representable room below this score — the group keeps its id order
        }
        const std::uint32_t lowerBits = std::bit_cast<std::uint32_t>( lower );
        if( std::binary_search( distinct.begin(), distinct.end(), lowerBits ) )
        {
            continue; // REFUSE: that value is occupied, and moving onto it would reorder rows that were never tied
        }
        demoteTo[u] = lower;
        anyDemote   = true;
    }
    if( !anyDemote )
    {
        return 0;
    }

    std::size_t demoted = 0;
    for( std::size_t i = 0; i < S; ++i )
    {
        if( !scored( i ) || hasBody( i ) )
        {
            continue;
        }
        const std::size_t u = slotOf( i );
        if( demoteTo[u] > 0.f )
        {
            score[i] = demoteTo[u];
            ++demoted;
        }
    }
    return demoted;
}

// The name-exact ranker AS THE RETRIEVAL LENS SERVES IT: whole-name BM25 plus the definition-over-
// declaration tiebreak above. Every --for / --query / --pack-task / MCP retrieval site takes this one;
// lexicalScoresNameExactTiered and lexicalScoresNameExact stay the raw scorer, so --eval-retrieval and
// --eval-skills keep measuring the ranker itself and the skill router is provably untouched by this rule.
inline std::vector<float> lexicalScoresNameExactRanked( const IngestResult& ing, std::string_view query,
                                                       const std::vector<float>* symbolScoreMul )
{
    std::vector<float> score = lexicalScoresNameExactTiered( ing, query, symbolScoreMul );
    applyDefOverDeclTiebreak( ing, score );
    return score;
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

// ONE anchoring word's resolved DEFINITION — the same (name, defining file) pair the `anchors:` clause
// below prints, in the form a consumer can compare a symbol against. Only words that actually name a
// symbol get one: a camel/snake word matching nothing routes on SHAPE and anchors no definition, which
// is exactly the `syntax` evidence the reason prints for it.
//
// The consumer is the T3 auto-body allowance (main.cpp buildForAutoBodies, registered at docs/EVALS.md
// §4): "serve the anchor's own body or none" needs to know which symbol the anchor IS, and the NAME is
// not enough — a doc section, a type stub or a re-export shim sharing the name is a different symbol in
// a different file, and serving it in the anchor's place is the substitution that round removes.
struct RouteAnchorDef
{
    std::string   lowerName;          // routeLower of the anchoring word == routeLower of the symbol's name
    std::uint32_t fileId    = 0;      // NameAnchor::fileId — where the name is DEFINED (the first body-carrying
                                      // definition in NodeId order; see noteWholeNameDef), i.e. the same one
                                      // routeAnchorEvidence prints the path of
    std::uint32_t extraDefs = 0;      // further definitions sharing the name — the "+N" the reason discloses
};

struct RouteChoice
{
    LexMode                     which = LexMode::SubtokenBody;
    std::string                 reason;
    // Populated on the name-exact route only, in QUERY WORD order (deterministic), and only for words that
    // resolved to a definition. Empty on every other route — a route nothing anchored restricts nothing.
    std::vector<RouteAnchorDef> anchorDefs;
};

// is `w` a single stopword we ignore when counting query intent words?
inline bool isRouteStopword( std::string_view w ) noexcept
{
    static constexpr std::string_view kStop[] = {
        "the", "a", "an", "is", "are", "to", "of", "in", "for", "how",
        "does", "do", "where", "what", "which", "on", "with" };
    for( std::string_view s : kStop )
    {
        if( w == s )
        {
            return true;
        }
    }
    return false;
}

// ── ANCHOR DISCLOSURE (the `anchors:` clause of a name-exact reason) ──────────────────────────────────
//
// The confidence gate above is DOCUMENTED FRAGILE, three lines up: "a single generic word that happens to
// equal a symbol name still routes to name-exact". That is a deliberate, measured trade — one-word lookups
// are the shape name-exact wins on — but it means a route can be decided by a symbol the caller has never
// heard of. It happened: a bash helper named json() in test/nestprofilecheck.sh turned "json escape" into a
// 2-of-2 whole-name query, flipped the route, and collapsed a downstream partition to zero (mcpw3fixcheck
// H4, fixed in e7ee64c by renaming the helper). Nothing misbehaved. The header said `name-exact — query
// names a symbol (json)` and was, word for word, correct.
//
// The answer to a documented-fragile rule is to publish its evidence, not to re-tune it on one anecdote. So
// a name-exact reason now names, per anchoring word, WHERE that word was matched — and the reader can
// discount an anchor that turns out to be a one-use helper under test/ without opening anything. This is
// DISCLOSURE ONLY: not one byte of the decision moved, and test/routecheck.sh (f3) pins that as a battery.
struct NameAnchor
{
    std::uint32_t fileId    = 0;     // where this name is DEFINED — the first BODY-CARRYING definition in NodeId
                                     // order, falling back to the first definition of any kind when no definition
                                     // of the name carries a body (see noteWholeNameDef for why, and for the
                                     // measured defect the preference closes). Deterministic either way.
    std::uint32_t extraDefs = 0;     // how many further definitions share it — the anchor's ambiguity, disclosed.
                                     // A COUNT, not a choice: it is the same number whichever definition holds
                                     // fileId, and the definition-preference above must never move it.
    std::uint32_t carriers  = 0;     // symbols whose NAME contains this token as a SUBTOKEN — the token's corpus
                                     // commonness ("split" carries in SplitChunksPlugin, splitChunks, …), measured
                                     // from THIS corpus rather than guessed from a per-language stdlib list
    bool          wholeName = false; // some symbol's whole lowercased name equals this key; carrier-only entries
                                     // (a subtoken that names nothing) must NOT satisfy the whole-name membership test
    bool          bodyDef   = false; // does the symbol currently holding fileId carry a body? Private to the claim
                                     // rule below — nothing outside noteWholeNameDef reads it. It exists so the
                                     // walk can stay ONE pass: without it, "prefer a definition" would need either
                                     // a second pass or a re-lookup of the incumbent symbol.
};

// One anchor's path, shortened for a header that rides on every routed run. The leading "./" goes, and a
// path deeper than two segments keeps its TOP directory and its basename with "/.../" between them: those
// are the two parts that answer "core source, or a one-use helper?". The elision is spelled out rather than
// silently applied — a truncation a reader cannot see is the defect, not the truncation.
inline std::string routeAnchorPath( std::string_view path )
{
    std::string_view p = path;
    if( p.rfind( "./", 0 ) == 0 )
    {
        p.remove_prefix( 2 );
    }
    const std::size_t first = p.find( '/' );
    const std::size_t last  = p.rfind( '/' );
    if( first == std::string_view::npos || first == last )
    {
        return std::string( p );
    }
    return std::string( p.substr( 0, first ) ) + "/.../" + std::string( p.substr( last + 1 ) );
}

// The evidence behind ONE anchoring word: the defining file of the symbol it names, with "+N" when N further
// definitions share that name (the anchor's own ambiguity, disclosed rather than hidden behind whichever
// definition happened to be first), or the literal `syntax` when the word routed on camelCase / snake_case
// SHAPE and names no symbol at all. That last case is the one worth spelling: a reader who sees a file name
// in every anchor will read a shape-only route as a symbol hit.
inline std::string routeAnchorEvidence( const IngestResult& ing, const HashMap<std::string, NameAnchor>& names,
                                        const std::string& lowerWord )
{
    const auto at = names.find( lowerWord );
    if( at == names.end() || !at->second.wholeName )
    {
        return "syntax";                               // carrier-only entries count commonness, they name nothing
    }
    std::string evidence = routeAnchorPath( ing.files[at->second.fileId] );
    if( at->second.extraDefs != 0 )
    {
        evidence += "+" + std::to_string( at->second.extraDefs );
    }
    return evidence;
}

// The same lookup routeAnchorEvidence does, kept as a DEFINITION instead of rendered as a string. Appends
// nothing when the word names no symbol — a shape-only (camel/snake `syntax`) anchor resolves to no
// definition, so there is nothing for a consumer to compare against and the consumer must fall back to its
// un-anchored behaviour rather than restrict to an empty set. Deliberately UNCAPPED where the printed
// clause caps at four: the cap is a header-length rule, and silently dropping a resolved anchor from the
// machine-readable list would cost a body the query genuinely named.
inline void collectRouteAnchorDef( std::vector<RouteAnchorDef>& defs, const HashMap<std::string, NameAnchor>& names,
                                   const std::string& lowerWord )
{
    const auto at = names.find( lowerWord );
    if( at == names.end() || !at->second.wholeName )
    {
        return;
    }
    defs.push_back( RouteAnchorDef{ lowerWord, at->second.fileId, at->second.extraDefs } );
}

// The `anchors:` clause under construction. One `word(evidence)` per anchoring content word, appended in
// QUERY WORD order — never hash order, which is why the index below is only ever probed by key. CAPPED:
// this string rides on every routed run, and a pathological query whose every word names a symbol would
// otherwise print a paragraph into a header that is charged against the caller's budget. Over the cap the
// clause says how many it did not show, because a silently shortened list is the defect, not the shortening.
struct AnchorList
{
    static constexpr std::size_t kMaxShown = 4;
    std::string                  text;
    std::size_t                  found = 0;

    void add( std::string_view word, const std::string& evidence )
    {
        ++found;
        if( found > kMaxShown )
        {
            return;
        }
        if( !text.empty() )
        {
            text += ' ';
        }
        text += std::string( word ) + "(" + evidence + ")";
    }

    // The clause as it appears in the reason, or EMPTY when nothing anchored the route — a subtoken+body
    // route was not decided by any name match, so an anchors list on it would be evidence after the fact.
    std::string clause() const
    {
        if( text.empty() )
        {
            return std::string();
        }
        std::string out = "; anchors: " + text;
        if( found > kMaxShown )
        {
            out += " +" + std::to_string( found - kMaxShown ) + " more";
        }
        return out;
    }
};

// lowercase a short token into a caller buffer (identifiers are short; no allocation churn in the hot loop)
inline std::string routeLower( std::string_view w )
{
    std::string out( w );
    for( char& c : out )
    {
        if( c >= 'A' && c <= 'Z' )
        {
            c = char( c - 'A' + 'a' );
        }
    }
    return out;
}

// ONE lowercase-name index over all symbols, built once per query (was: a routeLower(s.name) heap allocation
// per size-matched symbol per word — O(contentWords × symbols) allocations, millions on a 100k-symbol tree).
// A single probe per word replaces the O(symbols) linear scan; the routed-vs-plain decision is unchanged, it
// was and remains a pure "does this word name a symbol" membership test.
//
// It was a SET until the anchor-disclosure round: same single pass, same one probe per word, but each entry
// now also carries where the name was FIRST defined (in NodeId order, which is file/line/name order, so the
// choice is deterministic) and how many further definitions share it.
//
// The anchor-plausibility round (LB-2) added CARRIER counts to the same pass: for every symbol, each distinct
// subtoken of its NAME bumps that token's `carriers` — so `carriers` measures how many symbol names in THIS
// corpus contain the token ("split" in webpack carries in SplitChunksPlugin, splitChunks, …). Entries a
// subtoken creates that no whole name ever claims stay wholeName=false, and both membership probes (the
// route loop and routeAnchorEvidence) test that flag — a carrier-only entry must never read as "this word
// names a symbol". Counts are order-independent sums, so the index stays a deterministic pure function of
// the corpus.
//
// ── DEFINITION OVER DECLARATION, AT THE ANCHOR (registered docs/EVALS.md §4, 2026-08-25) ──────────────
//
// `fileId` used to bind to the FIRST definition of the name in NodeId order, full stop — and NodeId order
// is path order, so on a header-heavy C++ tree it bound to whichever forward declaration happened to sort
// first. That is the SAME defect applyDefOverDeclTiebreak fixes on the ranked side, at a second site, and
// it cost the whole of that round's win: six golds moved to p=1 in the `<d>` rows and NOT ONE reached
// `<bodies>`, because the auto-body allowance narrows its candidates to the anchor's file
// (main.cpp restrictBodiesToRouteAnchor, which is correct and is the T3 substitution round's own fix). The
// declaration's file was the anchor, so the definition — ranked first, sitting right there — was filtered
// out and the caller was served the declaration's own text under the heading of an answer. Measured on
// duckdb: `--for="ClientContext"` ranked src/include/duckdb/main/client_context.hpp:65 first and served
// the body of `class ClientContext;` in extension/parquet/include/geo_parquet.hpp.
//
// So the claim passes to the first BODY-CARRYING definition in NodeId order, using the house bodyless
// predicate shared with graph.h's decl/def collapse, arch.h's pure-interface detection and the ranked-side
// tiebreak: `endByte > sigEndByte`. Three things about the shape are load-bearing:
//
//   1. it is a PREFERENCE, not a filter. A name no definition gives a body to — a type this corpus only
//      ever forward-declares — keeps the first-in-NodeId anchor it always had. There is no case in which
//      this rule leaves a name without an anchor.
//   2. it writes `fileId` and `bodyDef` and NOTHING ELSE. `wholeName`, `extraDefs` and `carriers` are
//      untouched, and those three are the entire input to the ROUTE decision and to the anchor-plausibility
//      bounds. No query can change route through this code, and no plausibility verdict can move — which
//      is a stronger statement than "the routing floors held" and is checkable by reading the diff.
//   3. ties inside the preference break on NodeId order exactly as before, so the choice stays a
//      deterministic pure function of the corpus and the one-pass walk stays one pass.
//
// one symbol's WHOLE lowercased name enters (or upgrades) its entry: the first definition claims fileId,
// the first body-carrying one TAKES it, later definitions count into extraDefs either way, and a
// carrier-only entry created earlier by some other name's subtoken is upgraded rather than shadowed.
inline void noteWholeNameDef( HashMap<std::string, NameAnchor>& names, const Symbol& s )
{
    const bool hasBody          = s.endByte > s.sigEndByte;
    const auto [ at, inserted ] = names.try_emplace( routeLower( s.name ), NameAnchor{ s.fileId, 0u, 0u, true, hasBody } );
    if( inserted )
    {
        return;
    }
    if( !at->second.wholeName )
    {
        at->second.wholeName = true;                   // a carrier-only entry meets its first DEFINITION — claim it
        at->second.fileId    = s.fileId;
        at->second.bodyDef   = hasBody;
        return;
    }
    ++at->second.extraDefs;                            // the ambiguity count is the same whoever holds the claim
    if( hasBody && !at->second.bodyDef )
    {
        at->second.fileId  = s.fileId;                 // the first body-carrying definition takes the claim from a
        at->second.bodyDef = true;                     // bodyless incumbent, and only ever from a bodyless one
    }
}

// one symbol's name-subtokens bump their tokens' carrier counts — one carrier per symbol per DISTINCT
// subtoken ("split_split" counts once). Entries this pass creates stay wholeName=false: they measure
// commonness and must never satisfy the whole-name membership test.
inline void countNameCarriers( HashMap<std::string, NameAnchor>& names, const std::vector<std::string>& parts )
{
    for( std::size_t k = 0; k < parts.size(); ++k )
    {
        bool repeat = false;
        for( std::size_t j = 0; j < k; ++j )
        {
            if( parts[ j ] == parts[ k ] )
            {
                repeat = true;
                break;
            }
        }
        if( repeat )
        {
            continue;
        }
        const auto [ at, inserted ] = names.try_emplace( parts[ k ], NameAnchor{ 0u, 0u, 1u, false } );
        if( !inserted )
        {
            ++at->second.carriers;
        }
    }
}

inline HashMap<std::string, NameAnchor> buildLowerNameIndex( const IngestResult& ing )
{
    HashMap<std::string, NameAnchor> names;
    names.reserve( ing.symbols.size() );
    std::vector<std::string> parts;
    for( const Symbol& s : ing.symbols )
    {
        noteWholeNameDef( names, s );
        parts.clear();
        subtokens( s.name, parts );
        countNameCarriers( names, parts );
    }
    return names;
}

// ── ANCHOR PLAUSIBILITY (LB-2) ────────────────────────────────────────────────────────────────────────
//
// A plain (non-camel/snake) whole-name hit is a PLAUSIBLE anchor only when the name is specific in THIS
// corpus: defined at most kMaxAnchorDefs times AND carried as a subtoken by at most routeCarrierCap symbol
// names. "split chunks" on webpack passes the membership test (a split() helper, a chunks() getter both
// exist) but the target is SplitChunksPlugin — a compound name the name-exact lane scores 0.0,
// structurally. A common carrier ("split" rides in dozens of names) or a many-definition name is
// coincidence, not intent, and the r7 probes measured the conceptual ranker recovering 5/6 of those
// misroutes. Both bounds are corpus-derived, never a per-language stdlib list — a fixed list is
// per-language, permanently stale, and wrong per-corpus ("split" is a stdlib method in JS and a perfectly
// specific free function in a C++ tree that defines it once).
//
// EXEMPT on purpose: nWords == 1 (the pinned, measured single-word lookup — the crater was multi-word
// phrases, never "map"), the camel/snake short branch (explicit identifier syntax is user intent), and
// camel/snake-shaped words inside a longer all-words query (same reason, per word) — only PLAIN whole-name
// words are tested, and the recovery evidence (r7 probes, 5/6 via --no-route) is evidence for the
// conceptual ranker alone, which is why a decline falls through instead of blending.
inline constexpr std::uint32_t kMaxAnchorDefs = 3;

// the carrier bound scales with corpus size and floors at 8 so a fixture-sized tree can still construct a
// "common" name — test/routecheck.sh (g) covers the floored regime, the r7 webpack corpus the scaled one.
inline std::uint32_t routeCarrierCap( const IngestResult& ing ) noexcept
{
    const std::uint32_t sOver128 = std::uint32_t( ing.symbols.size() / 128 );
    return sOver128 > 8u ? sOver128 : 8u;
}

// the FIRST implausible anchor of a query (query word order — deterministic), kept for the declined
// disclosure: the reason must say why, with the failing word and its measured commonness.
struct ImplausibleAnchor
{
    bool          found    = false;
    std::string   word;
    std::uint32_t carriers = 0;
    std::uint32_t defs     = 0;
};

inline void noteAnchorPlausibility( ImplausibleAnchor& imp, std::string_view lowerWord, const NameAnchor& a,
                                    std::uint32_t carrierCap )
{
    if( imp.found )
    {
        return;
    }
    const std::uint32_t defs = 1u + a.extraDefs;
    if( defs > kMaxAnchorDefs || a.carriers > carrierCap )
    {
        imp.found    = true;
        imp.word     = std::string( lowerWord );
        imp.carriers = a.carriers;
        imp.defs     = defs;
    }
}

// Truth in the header when name-exact is declined: say WHY — the failing anchor and its measured
// commonness. Deliberately carries NEITHER of the name-exact-only literals `anchors:` (routecheck f2: a
// subtoken+body route was not decided by name evidence) nor `names a symbol (` (taskechocheck parses that
// phrase as a name-exact marker).
inline std::string declinedRouteReason( const ImplausibleAnchor& imp )
{
    return "subtoken+body BM25 — name-exact declined: anchor '" + imp.word + "' is a common name ("
         + std::to_string( imp.carriers ) + " name-carriers, " + std::to_string( imp.defs )
         + " defs); conceptual ranker used";
}

// split a query on whitespace into raw words (case preserved — camelCase detection needs it)
inline std::vector<std::string_view> splitRouteWords( std::string_view query )
{
    std::vector<std::string_view> words;
    std::size_t                   start = std::string_view::npos;
    for( std::size_t k = 0; k <= query.size(); ++k )
    {
        const bool sep = k == query.size() || query[k] == ' ' || query[k] == '\t' || query[k] == '\n' || query[k] == '\r';
        if( sep ) { if( start != std::string_view::npos ) { words.push_back( query.substr( start, k - start ) ); start = std::string_view::npos; } }
        else if( start == std::string_view::npos )
        {
            start = k;
        }
    }
    return words;
}

inline RouteChoice chooseForRanker( const IngestResult& ing, std::string_view query )
{
    const std::vector<std::string_view> words = splitRouteWords( query );

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

    // ANCHOR PLAUSIBILITY (LB-2) — see the block above ImplausibleAnchor for the mechanism and its bounds.
    const std::uint32_t carrierCap = routeCarrierCap( ing );
    ImplausibleAnchor   imp;

    // ONE lowercase-name index over all symbols, built once per query — see buildLowerNameIndex.
    const HashMap<std::string, NameAnchor> lowerSymbolNames = buildLowerNameIndex( ing );
    AnchorList                             anchors;
    std::vector<RouteAnchorDef>            anchorDefs;   // the same anchors, resolved (see collectRouteAnchorDef)

    for( std::string_view w : words )
    {
        const std::string lw = routeLower( w );
        if( isRouteStopword( lw ) )
        {
            continue;
        }
        ++nWords;

        // camelCase / snake_case shape: an interior uppercase (aB) or an interior underscore (a_b)
        bool camel = false, snake = false;
        for( std::size_t k = 1; k < w.size(); ++k )
        {
            const char c = w[k];
            if( c >= 'A' && c <= 'Z' && w[k - 1] >= 'a' && w[k - 1] <= 'z' )
            {
                camel = true;
            }
            if( c == '_' && k + 1 < w.size() )
            {
                snake = true;
            }
        }
        if( camel || snake )
        {
            hasCamelSnake = true;
            if( identifierHit.empty() )
            {
                identifierHit = std::string( w );
            }
            ++wholeNameHits;                                   // explicit identifier syntax also counts toward "all words name symbols"
            anchors.add( w, routeAnchorEvidence( ing, lowerSymbolNames, lw ) );
            collectRouteAnchorDef( anchorDefs, lowerSymbolNames, lw );
            continue;
        }

        // else: does the token (case-insensitively) equal an existing symbol's WHOLE name? then it names one.
        // (carrier-only entries name nothing — wholeName gates the membership test, see buildLowerNameIndex)
        const auto at = lowerSymbolNames.find( lw );
        if( at != lowerSymbolNames.end() && at->second.wholeName )
        {
            ++wholeNameHits;
            if( identifierHit.empty() )
            {
                identifierHit = std::string( w );
            }
            anchors.add( w, routeAnchorEvidence( ing, lowerSymbolNames, lw ) );
            collectRouteAnchorDef( anchorDefs, lowerSymbolNames, lw );
            noteAnchorPlausibility( imp, lw, at->second, carrierCap );
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
    const bool camelShort = hasCamelSnake && nWords <= kMaxIdentifierLookupWords;
    const bool allNames   = nWords >= 1 && wholeNameHits == nWords;
    // ANCHOR PLAUSIBILITY (LB-2): the all-words trigger at nWords >= 2 additionally requires every plain
    // anchor to be plausible — a declined query FALLS THROUGH to subtoken+body (never a blend: route=
    // discloses that scores are comparable only within one route). Exemptions and mechanism: see the
    // ImplausibleAnchor block. nWords == 1 and the camel/snake short branch stay byte-for-byte untouched.
    const bool declined   = !camelShort && allNames && nWords >= 2 && imp.found;
    const bool nameExact  = ( camelShort || allNames ) && !declined;

    RouteChoice rc;
    if( nameExact )
    {
        rc.which  = LexMode::NameExact;
        rc.reason = "name-exact BM25 — query names a symbol (" + identifierHit + ")";
        // The evidence, appended and never substituted: downstream readers (test/taskechocheck.sh) parse the
        // clause above out of this same string. A subtoken+body route names no anchors because nothing
        // anchored it — an anchors list on a route the names did not decide would be evidence after the fact.
        rc.reason += anchors.clause();
        rc.anchorDefs = std::move( anchorDefs );   // the machine form of the same clause (see RouteAnchorDef)
    }
    else if( declined )
    {
        rc.which  = LexMode::SubtokenBody;
        rc.reason = declinedRouteReason( imp );
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

// ── Adaptive-k relevance-cliff cut (lever 2; arXiv 2506.08479) ─────────────────────────────────────────
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
    for( float s : scores )
    {
        if( s > 0.f )
        {
            pos.push_back( s );
        }
    }
    sortutil::radixSortNonNegativeFloatsDesc( pos );

    // clamp the working ceiling to what actually has positive score (a query with few hits can't keep more).
    const std::size_t avail = pos.size();
    cut.positiveHits = avail;
    if( avail == 0 ) { cut.kept = std::min( floorK, ceilingK ); cut.cliffRank = cut.kept; cut.hitCeiling = true; return cut; }
    std::size_t hardCeil = std::min( ceilingK, avail );
    if( hardCeil < floorK )
    {
        hardCeil = std::min( floorK, avail ); // floor may exceed the few available hits
    }
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
    // drop is a conservative "conceptual query" knee; below that the tail is flat → keep ceiling.
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
    if( cut.kept < f )
    {
        cut.kept = f; // floor guard (never below the floor)
    }
    return cut;
}

}   // namespace rw
