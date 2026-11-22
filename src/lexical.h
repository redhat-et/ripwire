#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings


// lexical.h — subtoken (camelCase / snake_case) BM25 over symbols, for `--query` / `--for` retrieval.
// The eval-at-scale showed lexical name-overlap beats pure graph structure for "find related code", so the
// relevance path is lexical and is NOT fused with PageRank (the eval showed fusion HURTS relatedness —
// importance ≠ relevance). Each symbol's BM25 doc = its name subtokens + callees' names + its DOC-COMMENT
// and BODY text, so a query matches code by what it DOES, not just what it's named. Deterministic.

#include "model.h"
#include "elixir_resolve.h"      // elixirBaseName — the arity-less spelling of an Elixir `name/N`, a second whole-name token for the name-exact lane
#include "docparse.h"            // detail::readWholeFile — THE canonical whole-file byte read (P2-4); never re-rolled
#include "lexindex.h"            // B0: the ONE subtoken state machine + docCommentStart + persisted-stats types
#include "sarif.h"               // rootRelativeUri — the ONE root-relative path view, included directly
                                 // rather than reached transitively (recall.h gets it via serialize.h)
                                 // because pass 1.5 SCORES the string recall.h PRINTS. A pure path helper
                                 // over model.h despite the header's name: no cycle.
#include "infra/profileScope.h"  // PROFILE_SCOPE self-profiling — gated by PROFILE_ENABLED (off unless -DRIPWIRE_PROFILE=ON)
#include "infra/strkern.h"      // Byteset256 — the head set below is that type, not a second bitmap
#include "infra/sortutil.h"      // deterministic sanitizer-clean score sorting for adaptive cuts
#include "infra/namesplit.h"     // hasIdentifierShape — the ONE camel/snake predicate chooseForRanker shares with mention.h
#include "infra/charconvcompat.h" // rw::parseFloating — envKnob's full-token finite parse of a RIPWIRE_* knob

#include <algorithm>
#include <atomic>
#include <bit>
#include <charconv>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <initializer_list>
#include <optional>
#include <span>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>
#include <type_traits>
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

inline std::string suffixStem( std::string w, std::span<const std::string_view> suffixes );

// How many DISTINCT subtokens of `name` — each suffix-stemmed first by `stemSuffixes` when given (suffixStem) — are among `words`.
// `words` is a handful, read by linear find. The member-name slice's (formembers.h wordOverlap); the tail's tsym= reads WHICH words
// match instead (fortailterms.h tailTermMask, the same split and stem).
inline std::ptrdiff_t subtokenOverlap( std::string_view name, const std::vector<std::string>& words, std::span<const std::string_view> stemSuffixes = {} )
{
    std::vector<std::string> toks;
    subtokens( name, toks );
    for( std::string& t : toks )
    {
        t = suffixStem( std::move( t ), stemSuffixes );
    }
    sortutil::sortUnique( toks );
    return std::ranges::count_if( toks, [ & ]( const std::string& t ) { return std::ranges::find( words, t ) != words.end(); } );
}

// A light suffix stem: the FIRST of `suffixes` (in order) that `w` ends with and that leaves 3+ bytes is cut; "ies" becomes "y".
// The suffix list is the caller's measured rule (forfilesyms.h kLightStemSuffixes for <syms>, fortailterms.h kTailTermSuffixes
// for tsym=); an empty list leaves `w` as is.
inline std::string suffixStem( std::string w, std::span<const std::string_view> suffixes )
{
    for( const std::string_view suf : suffixes )
    {
        if( w.size() > suf.size() + 2 && std::string_view( w ).ends_with( suf ) )
        {
            w.resize( w.size() - suf.size() );
            if( suf == "ies" )
            {
                w += 'y';
            }
            return w;
        }
    }
    return w;
}

// Does `text` carry one of `words` (lowercased subtokens) as a subtoken? `words` is a handful, read by linear find. Shared by the
// --for fold's member slice (forfold.h) and the path owner-word key (pathroute.h).
inline bool holdsSubtokenWord( std::string_view text, const std::vector<std::string>& words )
{
    std::vector<std::string> toks;
    subtokens( text, toks );
    return std::ranges::any_of( toks, [ & ]( const std::string& t ) { return std::ranges::find( words, t ) != words.end(); } );
}

// ── L-W (routing-loop round 2026-09-12): what the BM25 pass saw, read back out ──────────────────────────
// Per symbol, which of the query's unique terms it matched, and per term, how many symbols matched it — the
// integers lexicalScoresTiered accumulates anyway, exposed rather than re-derived by a second tokenizer that
// could drift from this one. Read by forpage.h (coverage= on the --for root; the --for --limit=N file page).
// Filled only when a caller passes it; a null caller's scores are byte-identical to before the parameter.
//   terms[u]    the u-th unique query term (the tf row it owns after the LB-3 fold)
//   df[u]       symbols with tf > 0 for terms[u] in any field — the document frequency the idf reads
//   nameMask    per symbol, bit u set iff its NAME field alone carried terms[u] (captured inside pass 1,
//               before the callee-name, path, doc and body fields land in the same row)
//   anyMask     per symbol, bit u set iff it carried terms[u] in any field (the final row, after the fold)
// Masks are maskWords 64-bit words per symbol (maskWords = ceil(terms/64)): a pasted stack trace with a
// hundred unique terms is tracked in full, nothing silently dropped from the share.
//
// BM25's idf for a term carried by n of the N units the corpus statistics count — the ONE spelling of the expression:
// the scorer's per-term table (LexBm25Stats), its MaxScore bound and the evidence below all read it. An absent term
// (n = 0) weighs as the rarest possible term, ln( (N+0.5)/0.5 + 1 ), never as nothing.
inline double bm25Idf( double N, double n ) noexcept
{
    return std::log( ( N - n + 0.5 ) / ( n + 0.5 ) + 1.0 );
}

struct LexTermEvidence
{
    std::vector<std::string>   terms;
    std::vector<std::uint32_t> df;
    std::vector<std::uint64_t> nameMask;   // symbolCount × maskWords
    std::vector<std::uint64_t> anyMask;    // symbolCount × maskWords
    std::size_t                maskWords   = 0;
    std::size_t                symbolCount = 0;
    std::size_t                statsCount  = 0;   // the symbols the corpus statistics count (symbolCount less lexicalScoresTiered's statsOut)

    // input blow-up disclosure (dedupeQueryTerms / kMaxUniqueQueryTerms): terms.size() is the KEPT unique
    // term count; termsSeenTotal is every distinct term the query actually contained. Equal unless the
    // query was capped, in which case termsCapped is true and terms.size() < termsSeenTotal — the header
    // must say so rather than let a truncated term list read as a complete one.
    std::size_t                termsSeenTotal = 0;
    bool                       termsCapped    = false;

    static constexpr std::size_t maskWordsFor( std::size_t termCount ) noexcept { return ( termCount + 63 ) / 64; }
    const std::uint64_t*         anyMaskOf( std::size_t sym ) const noexcept { return anyMask.data() + sym * maskWords; }
    static bool                  hasBit( const std::uint64_t* mask, std::size_t u ) noexcept { return ( mask[ u / 64 ] >> ( u % 64 ) ) & 1u; }

    // BM25's own idf for term u over the `statsCount` symbols the statistics count (bm25Idf, the scorer's expression)
    double idf( std::size_t u ) const noexcept { return bm25Idf( double( statsCount ), double( df[u] ) ); }
};

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

// ─── BM25 PARAMETERS — the ONE definition every scoring site in this file reads (A4 unification) ──────
// k1 (term-frequency saturation) and b (length normalization) used to be declared TWICE — once in
// lexicalScoresTiered, once in lexicalScoresNameExactTiered — as separate `constexpr double k1 = 1.5, b =
// 0.75;` lines that had to be kept in sync by hand. The early-termination bound in lexicalScoresTiered's
// pruned branch (bm25ImpactBound below) derived its cap from ITS OWN local copy, which is the trap: change
// k1 or b at one site without also updating the bound and MaxScore pruning starts discarding candidates
// whose true score exceeds the now-stale cap — no crash, no error, just a quietly worse top-K. Both
// scoring sites and the bound now read the SAME resolved (k1,b), so they cannot drift apart again.
// test/bm25boundcheck.sh asserts the bound stays a genuine upper bound for whatever this resolves to.
//
// RIPWIRE_BM25_K1 / RIPWIRE_BM25_B override the shipped defaults, clamped to a range that keeps BM25 in a
// sane regime (k1 <= 0 collapses term-frequency saturation to a step function; b outside [0,1] inverts or
// overshoots length normalization) — the RIPWIRE_PATHTOK_W / RIPWIRE_BASENAME_W precedent a few hundred
// lines below, calibration sweeps ONLY (bench/bm25_sweep.py). A nonzero-from-default value shipping as the
// new default requires the sweep's own pre-registered acceptance verdict (docs/EVALS.md); this commit
// changes neither shipped value.
struct Bm25Params
{
    double k1;
    double b;
};

inline constexpr Bm25Params kBm25Default{ 1.5, 0.75 };

// A RIPWIRE_* calibration knob. Unset, or set empty, is the caller's default. A set value must parse IN FULL as a
// finite number, or it is refused back to that default with one stderr line naming it, so a sweep cannot run on the
// default while believing it set something. atof/atoi were unchecked: "nan" read as NaN, which std::clamp passes
// straight through into every BM25 score; "8x" as 8; "abc" as 0, then clamped to the floor — three rankings nobody
// configured (test/bm25boundcheck.sh (3b)/(3c), test/lb3namecheck.sh (b-junk)).
template<class T> requires std::is_arithmetic_v<T>
inline std::optional<T> envKnob( const char* name ) noexcept
{
    const char* const text = std::getenv( name );
    if( text == nullptr || *text == '\0' )
    {
        return std::nullopt;
    }
    const char* const      end   = text + std::strlen( text );
    T                      value = T{};
    std::from_chars_result parsed{};
    if constexpr( std::is_floating_point_v<T> )
    {
        parsed = rw::parseFloating( text, end, value );
    }
    else
    {
        parsed = std::from_chars( text, end, value );
    }
    if( parsed.ec == std::errc{} && parsed.ptr == end && std::isfinite( double( value ) ) )
    {
        return value;
    }
    // emitRaw, not emitTo: nothing here needs formatting, and every caller is a noexcept scoring path
    rw::emitRaw( stderr, "ripwire: ignoring " );
    rw::emitRaw( stderr, name );
    rw::emitRaw( stderr, "=\"" );
    rw::emitRaw( stderr, text );
    rw::emitRaw( stderr, std::is_floating_point_v<T> ? "\" (not a finite number) — the default applies\n"
                                                    : "\" (not a whole number in int range) — the default applies\n" );
    return std::nullopt;
}

inline Bm25Params resolveBm25Params() noexcept
{
    Bm25Params p = kBm25Default;
    if( const std::optional<double> k1 = envKnob<double>( "RIPWIRE_BM25_K1" ) )
    {
        p.k1 = std::clamp( *k1, 0.1, 10.0 );
    }
    if( const std::optional<double> b = envKnob<double>( "RIPWIRE_BM25_B" ) )
    {
        p.b = std::clamp( *b, 0.0, 1.0 );
    }
    return p;
}

// The provably-safe per-term impact bound (MaxScore "max contribution"), derived from the SAME (k1,b) the
// exact scoring loop uses. idf: this term's IDF. T: the largest weighted tf of this term anywhere in the
// corpus (tfMaxOf[u] at the call site). See LexTopKPruner for the full monotonicity
// proof this bound relies on — it holds for ANY k1 > 0 and ANY b in [0,1], not just the shipped defaults.
inline double bm25ImpactBound( double idf, double T, const Bm25Params& p ) noexcept
{
    return idf * ( T * ( p.k1 + 1.0 ) ) / ( T + p.k1 * ( 1.0 - p.b ) ) * ( 1.0 + 1e-9 );
}

// ── input blow-up guard: bound the UNIQUE term count a query can spend on tfFlat's S×terms allocation ────
// --for/--pack-task's task string is agent-supplied text, not a hand-typed query — an agent can (and one
// round did) paste a whole file/log/issue body. A 480 KB task string measured 5.2 GB RSS in ONE tfFlat
// allocation (S symbols × that many unique query terms × 4 bytes) before this guard existed: a single
// request pushed the process past the host's memory ceiling. Deduping to unique terms (below) was ALREADY
// correct — the gap was that "unique" had no ceiling of its own, so a query with little internal repetition
// (natural-language prose, a pasted diff, a stack trace) stayed as big as the input.
//
// The longest REAL --for/--pack-task query on record in this repo (grep -rhoE -- '--for="[^"]{1,}"'
// bench/ docs/, ranked by word count) is 10 words: "per connection state that holds the active
// transaction and query" (docs/EVALS.md). This cap sits at ~102× that — the owner's "caps are blow-up
// guards, not budgets to hug; set them at the pathological tail, not the typical case" ruling (memory
// owner-quality-first-caps-are-blowup-guards.md) — so an ordinary task description, even an unusually long
// one, never meets it; only a pathological paste does.
inline constexpr std::size_t kMaxUniqueQueryTerms = 1024;

// The historical dedupe (first-wins index into the unique-term list, one df/tf row per unique term, every
// OCCURRENCE still contributing once via uniqueIndexOfQtok), now capped at maxUnique. Byte-identical to the
// uncapped dedupe for any query with <= maxUnique unique terms — every real query on record clears that by
// a wide margin — so this only ever changes behaviour on the tail the cap exists for. A term seen after the
// cap fills gets kDroppedTerm: it owns no tf row, so it scores like any subtoken absent from the match
// table (zero contribution) rather than growing the S×terms allocation further. Disclosed via .capped /
// .uniqueSeenTotal so a truncated query never reads as a complete one.
struct DedupedQueryTerms
{
    static constexpr std::size_t kDroppedTerm = std::size_t( -1 );

    std::vector<std::string> uniqueToks;                // size() <= maxUnique passed to dedupeQueryTerms
    std::vector<std::size_t> uniqueIndexOfQtok;          // one entry per input token; kDroppedTerm past the cap
    std::size_t              uniqueSeenTotal = 0;        // every DISTINCT term seen, kept or dropped — exact, never an occurrence count
    bool                     capped          = false;    // uniqueSeenTotal > uniqueToks.size()
};

inline DedupedQueryTerms dedupeQueryTerms( const std::vector<std::string>& qToks, std::size_t maxUnique )
{
    DedupedQueryTerms out;
    out.uniqueIndexOfQtok.resize( qToks.size() );
    out.uniqueToks.reserve( std::min( qToks.size(), maxUnique ) );
    // The spellings the cap DROPPED, so a repeat of one is not counted as a new distinct term (the kept-terms scan
    // below only sees what was kept: every repeat of a dropped term used to miss it and count again, turning the
    // disclosed terms_total into an occurrence count — CodeRabbit on #277). Views into qToks, which outlives the
    // loop, so the set costs no copy and never holds more entries than the query has tokens: no memory beyond the
    // input already in hand, and O(1) per dropped token where the capped linear scan stays bounded by maxUnique.
    ankerl::unordered_dense::set<std::string_view> droppedSpellings;
    for( std::size_t qi = 0; qi < qToks.size(); ++qi )
    {
        const auto found = std::find( out.uniqueToks.begin(), out.uniqueToks.end(), qToks[qi] );
        if( found != out.uniqueToks.end() )
        {
            out.uniqueIndexOfQtok[qi] = std::size_t( found - out.uniqueToks.begin() );
            continue;
        }
        if( out.uniqueToks.size() < maxUnique )
        {
            ++out.uniqueSeenTotal;                        // a genuinely new distinct term, kept
            out.uniqueIndexOfQtok[qi] = out.uniqueToks.size();
            out.uniqueToks.push_back( qToks[qi] );
        }
        else
        {
            out.uniqueIndexOfQtok[qi] = DedupedQueryTerms::kDroppedTerm;
            out.capped               = true;
            if( droppedSpellings.insert( std::string_view( qToks[qi] ) ).second )
            {
                ++out.uniqueSeenTotal;                    // a genuinely new distinct term, dropped — counted once
            }
        }
    }
    return out;
}

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

// ── P2-3: the query-side head mask + length buckets (PLAN_FULL_AUDIT_2026-09-10) ─────────────────────
//
// The BM25 pass-2 scan is the hottest loop in the tool — 81.7% of `--pack-task`'s busy time — because for
// EVERY subtoken of the corpus it walked the WHOLE query match table, string-comparing as it went. That
// inner loop is linear in the table, and the table grows with the question (and doubles again when
// RIPWIRE_QSTEM arms its stem variants), so a longer query cost quadratically more for no retrieval gain.
//
// Almost every one of those comparisons was decidable from two bytes of metadata. A corpus token can only
// match a table row of the SAME LENGTH whose FIRST byte agrees. Both facts are precomputed once per query:
//
//   headBits   a 256-bit set of the table's (already lowercased) first bytes. A corpus token whose head is
//              not in the set touches NO string at all — one shift and one test, and the overwhelmingly
//              common answer is "no".
//   bucketIdx  the rows grouped by token length, CSR-style (bucketOff[len] .. bucketOff[len+1]), in
//              ascending row order. A surviving token iterates only the rows that CAN match it.
//
// Byte-identity is structural, not measured-and-hoped. The surviving predicate at the call site is
// character for character the one that was there before (the memcmp fast path AND the
// lexTokenEqualsLowered acronym fallback, in that order), the rows are visited in ascending m exactly as
// the linear scan visited them, and the table's strings are distinct so at most one row can ever match.
// What changed is only WHICH rows are looked at, and every skipped row is one the old predicate would
// have rejected on its length or its head.
//
// kMaxLen is a BUCKETING BOUND, never an answer bound: a row longer than it goes into `longRows`, which is
// scanned in full with the length test intact. A query subtoken of 65+ bytes is a pathology, not a query,
// and this keeps it correct rather than special-casing it out.
struct LexHeadIndex
{
    static constexpr std::size_t kMaxLen = 64;
    static constexpr std::size_t kNoRow  = ~std::size_t( 0 );

    strkern::Byteset256        heads;        // the 256-bit head set — the SAME byte-set type strkern.h
                                             // already owns, not a second hand-rolled bitmap beside it
    std::vector<std::uint32_t> bucketOff;    // kMaxLen + 2 entries; CSR offsets by token length
    std::vector<std::uint32_t> bucketIdx;
    std::vector<std::uint32_t> longRows;

    // The match-table row this corpus token belongs to, or kNoRow. `tokOf( m )` returns row m's
    // all-lowercase token; the caller owns the table's storage.
    //
    // THE PREDICATE IS THE ORIGINAL ONE, character for character — length, then head, then the memcmp
    // fast path, then the lexTokenEqualsLowered acronym fallback, in that order. That is what makes the
    // whole P2-3 change byte-identical by construction rather than by hope: rows are still visited in
    // ascending m, at most one row can match (the table's strings are distinct), and every row this
    // skips is one the old linear scan would have rejected on its length or its head alone.
    template<class TokOfFn>
    std::size_t matchRow( const char* tok, std::size_t tokLen, TokOfFn&& tokOf ) const
    {
        const unsigned char headByte = ( tok[0] >= 'A' && tok[0] <= 'Z' ) ? static_cast<unsigned char>( tok[0] - 'A' + 'a' )
                                                                         : static_cast<unsigned char>( tok[0] );
        if( !heads.contains( headByte ) )
        {
            return kNoRow;             // no table row starts with this byte — not one string is touched
        }
        const char           head  = char( headByte );
        const std::uint32_t* first = tokLen <= kMaxLen ? bucketIdx.data() + bucketOff[ tokLen ] : longRows.data();
        const std::uint32_t* last  = tokLen <= kMaxLen ? bucketIdx.data() + bucketOff[ tokLen + 1 ] : longRows.data() + longRows.size();
        for( ; first != last; ++first )
        {
            const std::size_t  m = *first;
            const std::string& q = tokOf( m );
            if( q.size() == tokLen && q[0] == head
                && ( std::memcmp( q.data() + 1, tok + 1, tokLen - 1 ) == 0 || lexTokenEqualsLowered( tok, tokLen, q.data() ) ) )
            {
                return m;
            }
        }
        return kNoRow;
    }
};

// `tokOf( m )` returns row m's (all-lowercase) token. A template rather than a span of strings because the
// caller's match table is an array of structs, and copying its strings out to build an index over them
// would cost more than the index saves.
template<class TokOfFn>
inline LexHeadIndex buildLexHeadIndex( std::size_t rowCount, TokOfFn&& tokOf )
{
    LexHeadIndex ix;
    ix.bucketOff.assign( LexHeadIndex::kMaxLen + 2, 0 );
    for( std::size_t m = 0; m < rowCount; ++m )
    {
        const std::string& q = tokOf( m );
        if( q.empty() )
        {
            continue;               // cannot happen (subtokens() drops < 2 bytes), but q[0] is read below
        }
        const unsigned char head = static_cast<unsigned char>( q[0] );
        ix.heads.add( head );
        if( q.size() <= LexHeadIndex::kMaxLen )
        {
            ++ix.bucketOff[ q.size() + 1 ];      // counts, shifted by one: the prefix sum turns them into offsets
        }
    }
    for( std::size_t len = 1; len < ix.bucketOff.size(); ++len )
    {
        ix.bucketOff[len] += ix.bucketOff[ len - 1 ];
    }
    ix.bucketIdx.resize( ix.bucketOff.back() );
    std::vector<std::uint32_t> fill( ix.bucketOff.begin(), ix.bucketOff.end() );
    for( std::size_t m = 0; m < rowCount; ++m )
    {
        const std::string& q = tokOf( m );
        if( q.empty() )
        {
            continue;
        }
        if( q.size() <= LexHeadIndex::kMaxLen )
        {
            ix.bucketIdx[ fill[ q.size() ]++ ] = std::uint32_t( m );   // ascending m within each bucket
        }
        else
        {
            ix.longRows.push_back( std::uint32_t( m ) );
        }
    }
    return ix;
}

// THE pass-2 scan text for one file, resolved by ONE rule in ONE place: the docText override when the file
// has one, else the file's bytes moved into `scratch`. An EMPTY string means "skip this file" — what an empty
// docText override and an unreadable file have always meant. `scratch` owns those bytes for as long as the
// caller holds the returned pointer. Extracted 2026-09-06 out of the pass-2 worker below, which is the densest
// branch nest in this function.
inline const std::string* lexicalScanText( const IngestResult& ing, std::size_t f, std::string& scratch )
{
    // P1-B: a document file (notebook/html/csv) is indexed by its EXTRACTED text, not its raw bytes, so a
    // query matches the notebook's prose/code, not its JSON envelope (read-only lookup — docText is never
    // written here, so concurrent finds are safe).
    if( const auto it = ing.docText.find( std::uint32_t( f ) ); it != ing.docText.end() )
    {
        return &it->second;
    }
    // P2-4 (PLAN_FULL_AUDIT_2026-09-10): this used to be `ifstream` + `ostringstream << rdbuf()` +
    // `str()`, which is TWO full copies of every file in the corpus — the stream buffer's growth, then
    // `str()`'s copy out of it — on the path that reads every indexed file once per cold query. The
    // canonical whole-file read is docparse::detail::readWholeFile (commentcoherence.h, quality.h,
    // renamemine.h, githarden.h, graph.h and mergescout.h all already reach for it, and mergescout's own
    // comment records that it used to be a hand-rolled copy): one open, one size probe, one fread into the
    // string it returns, which is moved into `scratch` — zero intermediate copies. An unreadable file is
    // nullopt, and value_or's empty string is exactly the "skip this file" contract above.
    scratch = docparse::detail::readWholeFile( diskPath( ing, std::uint32_t( f ) ) ).value_or( std::string() );
    return &scratch;
}

// LP1 (2026-11-21): the CODE lens's default weight for pass 1.6's basename-only field — what the --for ranking
// (verbs_for.h computeLensRanking, which --pack-task and the change lanes share) and its MCP twins (mcpverbs.h forTaskText,
// packTaskText) pass as basenameFieldDefaultW on every subtoken call of the route, so CLI and MCP rank alike. A question
// names a FILE or a package more often than a function ("lib/theme.githelpers: remove dead code", "restorer: reject …"),
// and a symbol's own text rarely repeats its file's name. Two peers win GA1 DEV cells on exactly this signal:
// codebase-memory-mcp indexes each node's file path and qualified name at the SAME BM25 weight as its name, graphify seeds
// from the file node a query word names. LP1 shipped 2 (under the name field ×3, over the body ×1). MEASURED on GA1 DEV n=89
// (in-sample; LP1): w=2 completes 1 more task and takes 0 tasks down at any rung; the FULL-path field (RIPWIRE_PATHTOK_W=1)
// took 2 tasks down — r3_pathtok's held-out finding again, the reason this is the basename and not the path.
// OWNER RULING (2026-11-23): the default is 1, not LP1's 2. At 2 a file-name match lifts every function of a same-named
// file by the same amount, so a long function in a large file sinks behind its short siblings under BM25 length
// normalization (test/ownerhopcheck.sh G/guard: `broadcast` among 105 short handlers of pkg/broadcast.py, rank 2 -> 107;
// at 1 it stays at 2). Weight 1 keeps the held-out completeness unchanged (126 / 83 / 4 of 213) and fixes that case.
// RIPWIRE_BASENAME_W still overrides it (0 = the historical ranking). test/forbasenamedefaultcheck.sh pins it.
inline constexpr int kForBasenameFieldW = 1;

// The kRankFlagNotLexRanked units (model.h) as a per-symbol mask, 1 = left out; EMPTY when the index holds none, so a corpus
// without such units runs the historical pass byte-for-byte. One pass over the symbols per ranking call.
inline std::vector<char> notLexRankedMask( const IngestResult& ing )
{
    std::vector<char> mask;
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        if( notLexRanked( ing.symbols[i] ) )
        {
            if( mask.empty() )
            {
                mask.assign( ing.symbols.size(), 0 );
            }
            mask[i] = 1;
        }
    }
    return mask;
}

// ─── lexicalScoresTiered's steps, in the order it runs them ─────────────────────────────────────────────
// lexicalScoresTiered (below) reads as the list of these steps. Each one makes ONE decision and names it:
// which units the corpus statistics count, which tokens a corpus subtoken can match, what each field adds,
// which stem variants are rare enough to keep, which query terms separate, and which units are scored.

// TIER STEP — which units the BM25 corpus statistics count. Decided ONCE per call, per unit, as one of three roles:
//   kCounted   scored, and counted in the statistics: the symbol count, every document frequency, the average length
//   kStatsOut  scored like any other unit but kept OUT of the statistics (the caller's statsOut — filter.h
//              sphinxTxtStatsExclusion). It scores against the whole ranked corpus instead: rankedCount units, its
//              term's counted df plus the statsOut df, and the ranked average length.
//   kUnranked  a kRankFlagNotLexRanked unit (model.h): never scored (0), and no document in either corpus — so a
//              Sphinx .txt section scores as it did before HTML units existed.
// An unranked unit that the caller also lists in statsOut is kUnranked: unranked wins. roleOf is EMPTY when every unit
// is kCounted, so a corpus with neither kind pays no per-unit lookup and runs the historical pass byte-for-byte.
struct LexCorpusRoles
{
    enum Role : std::uint8_t
    {
        kCounted  = 0,
        kStatsOut = 1,
        kUnranked = 2,
    };

    std::vector<std::uint8_t> roleOf;              // per unit; empty = every unit kCounted
    std::size_t               countedCount = 0;    // the units the statistics count (the BM25 N of a counted unit)
    std::size_t               rankedCount  = 0;    // counted + statsOut: the corpus a statsOut unit scores against

    Role role( std::size_t i ) const noexcept { return roleOf.empty() ? kCounted : Role( roleOf[i] ); }
    bool isUnranked( std::size_t i ) const noexcept { return role( i ) == kUnranked; }
    bool isStatsOut( std::size_t i ) const noexcept { return role( i ) == kStatsOut; }
    // a unit's weight in every corpus statistic: 1 counted, 0 otherwise (statsOut and unranked alike)
    int  statsWeight( std::size_t i ) const noexcept { return role( i ) == kCounted ? 1 : 0; }
};

inline LexCorpusRoles assignLexCorpusRoles( const IngestResult& ing, const std::vector<char>* statsOut )
{
    const std::size_t S = ing.symbols.size();
    LexCorpusRoles    roles;
    for( std::size_t i = 0; i < S; ++i )
    {
        const bool listedOut = statsOut != nullptr && i < statsOut->size() && ( *statsOut )[i] != 0;
        const auto role      = notLexRanked( ing.symbols[i] ) ? LexCorpusRoles::kUnranked
                             : listedOut                      ? LexCorpusRoles::kStatsOut
                                                              : LexCorpusRoles::kCounted;
        if( role != LexCorpusRoles::kCounted && roles.roleOf.empty() )
        {
            roles.roleOf.assign( S, LexCorpusRoles::kCounted );
        }
        if( role != LexCorpusRoles::kCounted )
        {
            roles.roleOf[i] = role;
        }
        roles.countedCount += role == LexCorpusRoles::kCounted ? 1 : 0;
        roles.rankedCount += role != LexCorpusRoles::kUnranked ? 1 : 0;
    }
    return roles;
}

// One row of a query's match table: a token a corpus subtoken is compared against, and the unique query term whose
// tf/idf row it scores into — itself for an exact term (row m == u), the original term for an LB-3 stem variant.
struct LexMatchTok
{
    std::string   tok;
    std::uint32_t u;
};

// The LB-3 arm S suffix rules for ONE query term, in the order the match table admits them (first-wins): a
// plural/participle query token ("splits", "resolved", "hoisting") cannot exact-match the singular subtoken a
// compound name carries (SplitChunksPlugin → split; resolve.h → resolve) — the measured LB-3 anatomy (bench/r7 + r8,
// three independent confirmations). Candidates only: the 3-byte floor and the first-wins dedupe are the table's.
inline std::vector<std::string> lightStemVariantsOf( const std::string& t )
{
    const auto isConsonant = []( char c )
    {
        return c >= 'a' && c <= 'z' && c != 'a' && c != 'e' && c != 'i' && c != 'o' && c != 'u';
    };
    const std::size_t L    = t.size();
    const auto        ends = [ & ]( std::string_view suf ) { return L >= suf.size() && t.compare( L - suf.size(), suf.size(), suf ) == 0; };
    // a doubled final consonant before the suffix ("flagged", "running"): the undoubled stem is a variant too
    const auto        doubledBefore = [ & ]( std::size_t suffixLen ) { return t[L - suffixLen - 1] == t[L - suffixLen - 2] && isConsonant( t[L - suffixLen - 1] ); };
    std::vector<std::string> variants;
    if( ends( "s" ) && !ends( "ss" ) && L >= 4 )
    {
        variants.push_back( t.substr( 0, L - 1 ) );                  // splits → split
    }
    if( ends( "es" ) && L >= 5 )
    {
        variants.push_back( t.substr( 0, L - 2 ) );                  // classes → class
    }
    if( ends( "ed" ) && L >= 5 )
    {
        variants.push_back( t.substr( 0, L - 1 ) );                  // resolved → resolve
        variants.push_back( t.substr( 0, L - 2 ) );                  // parsed → pars (rarely useful, harmless)
    }
    if( ends( "ed" ) && L >= 6 && doubledBefore( 2 ) )
    {
        variants.push_back( t.substr( 0, L - 3 ) );                  // flagged → flag
    }
    if( ends( "ing" ) && L >= 6 )
    {
        variants.push_back( t.substr( 0, L - 3 ) );                  // hoisting → hoist
        variants.push_back( t.substr( 0, L - 3 ) + "e" );            // caching → cache
    }
    if( ends( "ing" ) && L >= 7 && doubledBefore( 3 ) )
    {
        variants.push_back( t.substr( 0, L - 4 ) );                  // running → run
    }
    return variants;
}

// THE query's match table: one row per unique exact term (rows 0..uniqueCount, m == u), then — only when RIPWIRE_QSTEM=1
// arms LB-3 arm S — the terms' light-stem variants as PROVISIONAL rows (m ≥ uniqueCount), each owning its own tf column.
// Variants are QUERY-side only and score into the ORIGINAL token's tf/idf row, so corpus stats and the cache format are
// untouched. ONE shared table drives the scan branch, the persisted-stats branch, and every field pass — parity by
// construction (test/postingscheck.sh; armed arm in test/lb3namecheck.sh). A variant string already claimed by an
// earlier token (or equal to any exact token) is dropped, first-wins, so a doc token maps to exactly one row in either
// branch. The shipped default stays OFF until the LB-3 acceptance verdict (scratchpad lb3/preregistration.md) lands.
//
// IDF guard, rung R3 (LB-3 retry, scratchpad lb3retry/preregistration.md): the un-guarded round measured the failure:
// a corpus-common variant ("split" on webpack) hands its term-frequency mass to every competitor whose doc/body rides
// the same subtoken, displacing currently-hit truths (EVALS §7) — and the mass is BODY frequency (`.split()` call
// sites), which is why the name-carrier bound (rungs R1/R2) measured too low to catch it. So a variant enters the table
// PROVISIONALLY; admission is decided after pass 2 (admitRareStemVariants), when both pass-2 sources have measured
// its doc/body document frequency as the SAME integers. The guard never sees a user's EXACT query token — only derived
// variants — so it structurally cannot drop a truth's own carrier (the LB-1 IDF-floor failure).
inline std::vector<LexMatchTok> buildLexMatchTable( const std::vector<std::string>& uniqueToks )
{
    const std::size_t        uniqueCount = uniqueToks.size();
    std::vector<LexMatchTok> rows;
    rows.reserve( uniqueCount * 2 );
    for( std::size_t u = 0; u < uniqueCount; ++u )
    {
        rows.push_back( { uniqueToks[u], std::uint32_t( u ) } );
    }
    const char* qstemEnv = std::getenv( "RIPWIRE_QSTEM" );
    if( qstemEnv == nullptr || *qstemEnv != '1' )
    {
        return rows;
    }
    const auto alreadyClaimed = [ &rows ]( const std::string& v )
    { return std::ranges::any_of( rows, [ & ]( const LexMatchTok& row ) { return row.tok == v; } ); };
    for( std::size_t u = 0; u < uniqueCount; ++u )
    {
        for( std::string& v : lightStemVariantsOf( uniqueToks[u] ) )
        {
            if( v.size() >= 3 && !alreadyClaimed( v ) )            // sub-3-byte stems are noise, frozen rule; first-wins
            {
                rows.push_back( { std::move( v ), std::uint32_t( u ) } );
            }
        }
    }
    return rows;
}

// ── SIRA term margin (docs/EVALS.md "Corpus-statistics term margin", PRE-REGISTERED 2026-09-05) — the arming ──
// The decision itself needs corpus statistics that do not exist until after pass 2 (judgeTermMargins); all that is
// read here is whether it is armed and at which rung, ONCE per query: the tf tables carry it, pass 1 counts nameDf
// only when it is armed, the fold folds nameDf only then, and judgeTermMargins decides only then — one predicate.
// bits is the k of "a term separates iff idf_u >= k * ln 2", k = 1 being the shipped rule and the only rung this round
// may ship (the ladder is frozen in the registration). 0 = disarmed: the scorer is the historical one byte-for-byte.
struct LexTermMargin
{
    int  bits = 0;
    bool armed() const noexcept { return bits > 0; }
};

inline LexTermMargin termMarginFromEnv()
{
    const char* env = std::getenv( "RIPWIRE_TERMMARGIN" );
    if( env == nullptr || *env == '0' )
    {
        return {};
    }
    const std::optional<int> bits = envKnob<int>( "RIPWIRE_TERMMARGIN_BITS" );
    return { bits ? std::clamp( *bits, 1, 8 ) : 1 };
}

// The per-query BM25 term table AFTER the stem-variant fold — the historical layout, one row per unique query term:
// dl[i] = doc i's weighted subtoken count (the BM25 document length), tf[i * uniqueCount + u] = the weighted term
// frequency of unique term u in doc i, and nameDf[u] = the term margin's name-field document frequency (empty when the
// margin is disarmed). Every step from the term evidence on reads THIS type, and the only way to make one is the fold
// (LexMatchTfTable::foldAdmittedVariants below), so no later step can see a provisional variant column or a match-row
// stride. Integer counts are exact, so the float scoring later runs in strict doc order with the historical expressions.
struct LexTermTfTable
{
    std::size_t      uniqueCount = 0;
    std::vector<int> dl;
    std::vector<int> tf;
    std::vector<int> nameDf;
    LexTermMargin    margin;

    std::size_t docCount() const noexcept { return dl.size(); }
    const int*  row( std::size_t doc ) const noexcept { return tf.data() + doc * uniqueCount; }
};

// The same table BEFORE the fold, while the field passes add into it: one row per MATCH-table row (tf[i * matchCount() + m]),
// so the LB-3 stem variants sit in provisional columns m ≥ uniqueCount (none when RIPWIRE_QSTEM is off, and then the fold
// is a move). Beside tf it keeps the two per-row facts only the field passes can see: nameDf (pass 1, the name field
// alone; sized only when the margin is armed) and variantDocDf (pass 2, the units whose doc/body fields carry each
// variant — the R3 admission signal). The fold consumes the table and turns all of it into a LexTermTfTable at once.
//
// Every write goes through the add members below, and every field's evidence through ONE tokenizer:
// scanTextInto streams a field through lexindex.h forEachLexSubtoken (the same state machine subtokens() mirrors and the
// B0.2 index-time builder uses): a token is a maximal alphanumeric run between separators, cut at a lower/digit → Upper
// transition and at the ACRONYMWord seam. Tokens shorter than 2 bytes are dropped, exactly like subtokens(). No strings,
// no maps — just in-place span-vs-query compares through the P2-3 head index (LexHeadIndex above). Since 2026-08-19 an
// all-caps run survives as ONE token, so a span's INTERIOR bytes can be uppercase and memcmp alone would miss it; the
// memcmp stays as the fast path and only a span already agreeing on length AND head falls through to
// lexTokenEqualsLowered — the rare acronym case, arm D's seam.
struct LexMatchTfTable
{
    const std::vector<LexMatchTok>& matchToks;
    std::size_t                     uniqueCount;   // rows 0..uniqueCount are the exact query terms, the rest stem variants
    LexTermMargin                   margin;
    LexHeadIndex                    headIndex;
    std::vector<int>                dl;
    std::vector<int>                tf;
    std::vector<int>                nameDf;         // per match row: ranked units whose NAME field alone carries it
    std::vector<std::uint32_t>      variantDocDf;   // per stem variant: units whose doc/body fields carry it

    LexMatchTfTable( std::size_t docCount, const std::vector<LexMatchTok>& rows, std::size_t exactCount, LexTermMargin termMargin )
        : matchToks( rows ), uniqueCount( exactCount ), margin( termMargin ),
          headIndex( buildLexHeadIndex( rows.size(), [ &rows ]( std::size_t m ) -> const std::string& { return rows[m].tok; } ) ),
          dl( docCount, 0 ), tf( docCount * rows.size(), 0 ), nameDf( termMargin.armed() ? rows.size() : 0, 0 ),
          variantDocDf( rows.size() - exactCount, 0u )
    {
        DASSERT( exactCount <= rows.size(), "the match table lists the exact query terms first, then their stem variants" );
    }

    std::size_t matchCount() const noexcept { return matchToks.size(); }
    std::size_t variantCount() const noexcept { return matchToks.size() - uniqueCount; }
    int*        row( std::size_t doc ) noexcept { return tf.data() + doc * matchCount(); }
    const int*  row( std::size_t doc ) const noexcept { return tf.data() + doc * matchCount(); }

    // Streams `text` at weight w into a caller-owned tf row and length accumulator (the per-file basename rows use it
    // directly; addField is the per-doc form). Exact tokens own rows 0..uniqueCount (m == u there).
    void scanTextInto( int* tfRow, int& wtAccum, std::string_view text, int w ) const
    {
        const auto tokOf        = [ this ]( std::size_t m ) -> const std::string& { return matchToks[m].tok; };
        int        fieldTokenWt = 0;
        forEachLexSubtoken( text, [ & ]( std::size_t tokStartByte, std::size_t tokEndByte )
        {
            const std::size_t tokLen = tokEndByte - tokStartByte;
            if( tokLen < 2 )
            {
                return;
            }
            fieldTokenWt += w;
            if( const std::size_t m = headIndex.matchRow( text.data() + tokStartByte, tokLen, tokOf ); m != LexHeadIndex::kNoRow )
            {
                tfRow[m] += w;
            }
        } );
        wtAccum += fieldTokenWt;
    }

    void addField( std::size_t doc, std::string_view text, int w ) { scanTextInto( row( doc ), dl[doc], text, w ); }

    // a field scanned once per FILE and shared by every doc in it (pass 1.6): its tf row and its length, added
    void addFileField( std::size_t doc, const int* fileRow, int fileWt )
    {
        int* const tfRow = row( doc );
        for( std::size_t m = 0; m < matchCount(); ++m )
        {
            tfRow[m] += fileRow[m];
        }
        dl[doc] += fileWt;
    }

    // the persisted-stats branch's exact stored integers (B0.2): a doc's doc/body length, and one term's tf
    void addStoredLength( std::size_t doc, int length ) { dl[doc] += length; }
    void addStoredTf( std::size_t doc, std::size_t m, int count ) { row( doc )[m] += count; }

    // pass 1, right after a ranked doc's NAME field and before any other field lands in its row: count its name hits
    // into nameDf — only while the term margin is armed (nameDf is unsized otherwise)
    void countNameFieldDf( std::size_t doc )
    {
        if( !margin.armed() )
        {
            return;
        }
        const int* const nameRow = row( doc );
        for( std::size_t m = 0; m < matchCount(); ++m )
        {
            nameDf[m] += nameRow[m] > 0 ? 1 : 0;
        }
    }

    // The R3 fold, one flag per variant (admitRareStemVariants): an admitted variant's column adds into its original
    // term's row, a rejected one's is dropped (its evidence — name, callee, path, basename, doc, body — vanishes without
    // touching dl: document length counts all subtokens scanned, never matches). nameDf folds the SAME way, so the margin
    // test sees one row per unique term on either arm. A doc carrying both the exact token and an admitted variant in its
    // name is counted twice, so a folded nameDf is a CEILING, not a count — stated rather than hidden. It matters only
    // when RIPWIRE_QSTEM and the margin are both armed, and both ship off.
    LexTermTfTable foldAdmittedVariants( const std::vector<char>& admitted ) &&
    {
        DASSERT( admitted.size() == variantCount(), "one admission flag per stem variant" );
        const std::size_t docCount = dl.size();
        LexTermTfTable    terms;
        terms.uniqueCount = uniqueCount;
        terms.margin      = margin;
        terms.dl          = std::move( dl );
        if( variantCount() == 0 )
        {
            terms.tf     = std::move( tf );       // disarmed: already the historical layout
            terms.nameDf = std::move( nameDf );
            return terms;
        }
        terms.tf.assign( docCount * uniqueCount, 0 );
        for( std::size_t i = 0; i < docCount; ++i )
        {
            foldRowInto( terms.tf.data() + i * uniqueCount, row( i ), admitted );
        }
        if( margin.armed() )
        {
            terms.nameDf.assign( uniqueCount, 0 );
            foldRowInto( terms.nameDf.data(), nameDf.data(), admitted );
        }
        return terms;
    }

private:
    // one match-width row (tf, or nameDf) into a unique-width one: the exact columns copied, each admitted variant's
    // column added into its term's
    void foldRowInto( int* dst, const int* src, const std::vector<char>& admitted ) const
    {
        std::copy( src, src + uniqueCount, dst );
        for( std::size_t v = 0; v < admitted.size(); ++v )
        {
            dst[ matchToks[ uniqueCount + v ].u ] += admitted[v] != 0 ? src[ uniqueCount + v ] : 0;
        }
    }
};

// A field's weight: the caller's lens default, or the RIPWIRE_* calibration knob (clamped 0..8) when set. 0 = the
// field is not scanned at all.
inline int fieldWeightOrEnv( int lensDefaultW, const char* envName )
{
    if( const std::optional<int> knob = envKnob<int>( envName ) )
    {
        return std::clamp( *knob, 0, 8 );
    }
    return lensDefaultW;
}

// Field weights: a query term in a symbol's NAME outranks one in its DOC-COMMENT, which outranks one buried in its
// BODY — so an exactly-named function beats a struct that merely mentions the word, and an algorithm beats a
// comment-dense enum (the "keyword magnet" the review flagged). BM25 tf accumulates these weighted contributions; dl is
// weighted to match, so length normalization stays consistent. Doc/body weights are the SHARED constants (lexindex.h) —
// the index-time stats builder must weigh those two fields identically or the postings path would diverge from the scan.
inline constexpr int kLexWeightName = 3, kLexWeightCallee = 1;

// pass 1 — name (×kLexWeightName) + callee-name (×kLexWeightCallee) fields, which need no file text. Two per-unit facts
// are separable ONLY here, after a unit's name field and before its callee, path, doc and body fields land in the same
// tf row, so this pass also captures which terms each unit's NAME carries ("name hits"), two ways:
//   L-W   evidenceOut->nameMask, bit u set iff the NAME field alone carried terms[u] (skipped when evidenceOut is null)
//   SIRA  table.nameDf[m] = ranked units whose NAME FIELD ALONE carries match-table row m (only when the margin is
//         armed). This is the statistic the LB-1 negative is the reason for: that round's IDF floor read document
//         frequency only, and so deleted `module` — the truth's OWN name carrier — on a corpus where `module` is
//         everywhere in bodies. A term that names between 1 and S/2 symbols separates on the field ripwire weights highest
//         (×3) whatever its body mass says, and is kept. Pass 1 runs before the pass-2 branch split, so the scan and
//         persisted-stats paths read the identical integers.
inline void addNameAndCalleeFieldsCapturingNameHits( LexMatchTfTable& table, const IngestResult& ing, const std::vector<std::uint32_t>& outOff,
                                                     const std::vector<NodeId>& outTargets, const LexCorpusRoles& roles,
                                                     LexTermEvidence* evidenceOut )
{
    const std::size_t S             = ing.symbols.size();
    const std::size_t uniqueCount   = table.uniqueCount;
    const std::size_t evidenceWords = LexTermEvidence::maskWordsFor( uniqueCount );
    if( evidenceOut )
    {
        evidenceOut->maskWords = evidenceWords;
        evidenceOut->nameMask.assign( S * evidenceWords, 0u );
    }
    for( std::size_t i = 0; i < S; ++i )
    {
        table.addField( i, ing.symbols[i].name, kLexWeightName );
        const int* const nameRow = table.row( i );   // name field only: nothing else has run for this unit yet
        if( evidenceOut && !roles.isUnranked( i ) )
        {
            std::uint64_t* words = evidenceOut->nameMask.data() + i * evidenceWords;
            for( std::size_t u = 0; u < uniqueCount; ++u )
            {
                words[ u / 64 ] |= nameRow[u] > 0 ? std::uint64_t( 1 ) << ( u % 64 ) : 0u;
            }
        }
        if( !roles.isUnranked( i ) )
        {
            table.countNameFieldDf( i );   // SIRA nameDf, armed only
        }
        for( std::uint32_t e = outOff[i]; e < outOff[i + 1]; ++e )
        {
            table.addField( i, ing.symbols[ outTargets[e] ].name, kLexWeightCallee );
        }
    }
}

// pass 1.5 — path field (×kwPath): the symbol's file path scanned through the SAME state machine.
// pathFieldDefaultW is the CALLER's lens decision: the RECALL lens (docs) passes 1 — a query naming a
// "readme" / "report" / "paired table" should be able to hit the doc whose PATH says exactly that, and
// bench/recalleval/ is the instrument that measured the +0.03 lenient-MRR / doc-sibling recovery this
// buys (2026-08-03, gate: test/recallevalcheck.sh). The CODE lenses (--for and friends) still pass 0:
// a nonzero default THERE requires the pre-registered locbench acceptance gate
// (bench/locbench/results/r3_pathtok/PREREG.md), unchanged. RIPWIRE_PATHTOK_W overrides either default
// for calibration sweeps only. Paths need no file text, so the pass sits before the pass-2 branch split and
// runs identically over the scan and persisted-stats paths — postings parity holds by construction and
// the cache format is untouched.
//
// R-R RANKING (2026-08-25): the scanned string is the ROOT-RELATIVE VIEW, never ing.files[f] itself,
// which stays absolute because the emission lane proved it must (g.canonId, Regression::key, every
// pathQualifiedKey and the ingest cache's relForHash compare all key off it). Scanning it verbatim indexed
// every directory ABOVE the corpus as corpus vocabulary — and a directory that spelled a query word
// then matched EVERY document and collapsed that word's idf — so two clones of ONE commit at different
// checkout depths ranked --recall differently: 11 of 42 frozen queries reordered, 5 of them returning a
// different SET of documents (registered + measured in docs/EVALS.md; test/recallrankdepthcheck.sh).
//
// A VIEW, not a move — and the same helper recall.h PRINTS the separator path with, so the scored and
// the printed spelling of a file cannot disagree. rootRelativeUri(p, "") returns p bar a leading "./",
// exactly what a relative-root run already scanned, which is why this is a CONVERGENCE onto the
// already-invariant `ripwire .` rather than a new ranking opinion. Multi-root passes no prefix:
// ing.files already hold "<label>/<root-relative>".
inline void addPathField( LexMatchTfTable& table, const IngestResult& ing, int kwPath, std::string_view pathRootPrefix )
{
    if( kwPath <= 0 )
    {
        return;
    }
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        if( const std::uint32_t f = ing.symbols[i].fileId; f < ing.files.size() )
        {
            table.addField( i, rw::sarif::rootRelativeUri( ing.files[f], pathRootPrefix ), kwPath );
        }
    }
}

// pass 1.6 — LB-3 arm B: basename-only field (×kwBase). The r3_pathtok retry, narrowed per that
// round's own rejection note (bench/locbench/results/r3_pathtok/PREREG.md): FULL paths lost
// held-out to generic-directory noise, so only the basename is scanned, and the scan is amortized
// per FILE (each basename tokenized once, its row added per symbol) honoring r3's "amortize
// first". Needs no file text → runs before the pass-2 branch split; parity and the cache format
// untouched. RIPWIRE_BASENAME_W (0..8) overrides basenameFieldDefaultW; a nonzero shipped default
// requires the LB-3 acceptance verdict (gate: test/lb3namecheck.sh). The code lens now passes
// kForBasenameFieldW (above) on GA1 DEV evidence only — the acceptance verdict is still owed.
//
// R-R: takes the same root-relative view as pass 1.5. PROVABLY a no-op here — the basename is whatever
// follows the last '/', which the root prefix cannot change — and applied anyway so the two path passes
// cannot drift apart. One reading of ing.files[f], one rule; a future reader who changes one pass finds
// the other already agreeing rather than discovering half the path tokenization was still absolute.
inline void addBasenameField( LexMatchTfTable& table, const IngestResult& ing, int kwBase, std::string_view pathRootPrefix )
{
    if( kwBase <= 0 )
    {
        return;
    }
    const std::size_t fileCount = ing.files.size();
    std::vector<int>  fileTf( fileCount * table.matchCount(), 0 );
    std::vector<int>  fileWt( fileCount, 0 );
    for( std::size_t f = 0; f < fileCount; ++f )
    {
        const std::string_view path = rw::sarif::rootRelativeUri( ing.files[f], pathRootPrefix );
        const std::size_t      cut  = path.find_last_of( '/' );
        const std::string_view base = cut == std::string_view::npos ? path : path.substr( cut + 1 );
        table.scanTextInto( fileTf.data() + f * table.matchCount(), fileWt[f], base, kwBase );
    }
    for( std::size_t i = 0; i < ing.symbols.size(); ++i )
    {
        if( const std::uint32_t f = ing.symbols[i].fileId; f < fileCount && fileWt[f] != 0 )
        {
            table.addFileField( i, fileTf.data() + std::size_t( f ) * table.matchCount(), fileWt[f] );
        }
    }
}

// Which pass-2 source an ingest offers: B0.2 (R1 hypothesis #1) — a RICH ingest carries per-symbol weighted subtoken
// statistics built ONCE at parse/cache time, from the SAME byte spans through the SAME state machine, so the per-query
// work is pure lookups: no file re-read, no corpus re-tokenize. The stored dl/tf values are the exact integers the scan
// would accumulate, and the float scoring is shared, so the two sources are byte-identical (test/postingscheck.sh).
inline bool hasPersistedLexStats( const IngestResult& ing ) noexcept
{
    const std::size_t S = ing.symbols.size();
    return ing.hasLexStats && ing.lexTokenRowOffsets.size() == S + 1 && ing.lexDocBodyDl.size() == S;
}

// pass 2 from persisted stats — doc-comment + body evidence as stored integers, and table.variantDocDf: per stem variant,
// the units whose stored doc/body rows carry it (the R3 guard's admission signal; stored rows hold each hash once → one
// bump per unit). The match rows are reached by the same normalized-lowercase hash index time used, over the FULL match table
// (exact tokens + LB-3 stem variants), each hash mapped to its own tf ROW — the same row targeting the scan applies.
// try_emplace keeps the FIRST entry on the astronomically-unlikely 64-bit collision between two DISTINCT table strings,
// so both transfer strategies agree deterministically.
inline void addDocBodyFieldsFromPersistedStats( LexMatchTfTable& table, const IngestResult& ing )
{
    PROFILE_SCOPE_DESCRIBE( "lexical: pass 2 via persisted subtoken stats (cached tf/dl, no corpus re-tokenize)" );
    const std::size_t S           = ing.symbols.size();
    const std::size_t matchCount  = table.matchCount();
    const std::size_t uniqueCount = table.uniqueCount;

    // dl first: BM25 length normalization needs EVERY doc's weighted length whether or not it matches
    // the query (avgdl sums them all), so this runs unconditionally — exact stored integers.
    for( std::size_t i = 0; i < S; ++i )
    {
        table.addStoredLength( i, int( ing.lexDocBodyDl[i] ) );
    }

    std::vector<std::uint64_t>            matchHash( matchCount );
    HashMap<std::uint64_t, std::uint32_t> rowIndexOfHash;
    rowIndexOfHash.reserve( matchCount );
    for( std::size_t m = 0; m < matchCount; ++m )
    {
        matchHash[m] = lexSubtokenHash( table.matchToks[m].tok.data(), table.matchToks[m].tok.size() );
        rowIndexOfHash.try_emplace( matchHash[m], std::uint32_t( m ) );
    }
    const auto addStoredTerm = [ & ]( std::size_t i, std::uint32_t m, std::uint32_t storedTf )
    {
        table.addStoredTf( i, m, int( storedTf ) );
        if( m >= uniqueCount )
        {
            ++table.variantDocDf[ m - uniqueCount ];   // stored rows hold each hash once → one df bump per symbol
        }
    };

    // B0.1 per-file pre-filter: skip a whole file's tf walks when its 512-bit signature excludes every
    // query subtoken — no false negatives (dl above is already complete; tf for such a file is provably
    // zero), and a false positive just walks the cheap stats rows. Symbol ids are file-contiguous
    // (assigned in fileId,line,name order), so the test amortizes to one signature check per file.
    const bool useFileSig      = ing.lexFileSig.size() == ing.files.size() * kLexFileSigWords;
    const auto fileMayHoldTerm = [ & ]( std::uint32_t f )
    {
        const std::uint64_t* sig = ing.lexFileSig.data() + std::size_t( f ) * kLexFileSigWords;
        return std::ranges::any_of( matchHash, [ sig ]( std::uint64_t h ) { return ( sig[ lexSigWord( h ) ] & lexSigBit( h ) ) != 0; } );
    };
    std::uint32_t lastFileId       = kNoNode;
    bool          lastFileMayMatch = true;
    for( std::size_t i = 0; i < S; ++i )
    {
        const std::uint32_t rowBegin = ing.lexTokenRowOffsets[i];
        const std::uint32_t rowEnd   = ing.lexTokenRowOffsets[ i + 1 ];
        const std::uint32_t f        = ing.symbols[i].fileId;
        const bool          sigTests = useFileSig && f < ing.files.size();
        if( rowBegin == rowEnd )
        {
            continue; // no doc/body tokens → nothing to transfer
        }
        if( sigTests && f != lastFileId )
        {
            lastFileId       = f;                       // one membership probe per FILE (B0.1)
            lastFileMayMatch = fileMayHoldTerm( f );
        }
        if( sigTests && !lastFileMayMatch )
        {
            continue;
        }

        // exact tf transfer — walk whichever side is smaller: probe the query map per stored token, or
        // binary-search each DISTINCT query hash in the symbol's sorted row. Identical sums either way
        // (the map dedupes hash-colliding query tokens for both strategies).
        const std::uint64_t* rowHash = ing.lexTokenHashes.data();
        if( std::size_t( rowEnd - rowBegin ) <= matchCount * 8 )       // ~log2(row) probes vs one map probe per entry
        {
            for( std::uint32_t e = rowBegin; e < rowEnd; ++e )
            {
                if( const auto it = rowIndexOfHash.find( rowHash[e] ); it != rowIndexOfHash.end() )
                {
                    addStoredTerm( i, it->second, ing.lexTokenTfs[e] );
                }
            }
            continue;
        }
        for( const auto& [ hash, m ] : rowIndexOfHash )            // iteration order is score-irrelevant: rows are disjoint per HASH (+= commutes)
        {
            const std::uint64_t* lo = rowHash + rowBegin;
            const std::uint64_t* hi = rowHash + rowEnd;
            if( const std::uint64_t* it = std::lower_bound( lo, hi, hash ); it != hi && *it == hash )
            {
                addStoredTerm( i, m, ing.lexTokenTfs[ std::size_t( it - rowHash ) ] );
            }
        }
    }
}

// pass 2 by scanning (lean ingests, --no-cache lean verbs, multi-root merges, stubs) — doc-comment (×kLexWeightDoc) +
// body (×kLexWeightBody) evidence, streamed ONE file at a time touching only that file's symbols: peak memory is a single
// file's text, not the whole corpus held at once (symbol order within a file is irrelevant: integer counts commute
// exactly). Fills the same table.variantDocDf the persisted branch fills, from the scan's own counts.
//
// Files stream across a small worker pool: each worker holds ONE file's text at a time, and a file's symbols are touched
// only by the worker that claimed the file — every dl[i] / tf row has exactly ONE writer (no locks needed). Determinism:
// all pooled writes are exact integer counts and the float scoring stays single-threaded in doc order, so worker
// scheduling cannot change a byte of output (no cross-doc float reductions — the det-gate rule). The per-(file, variant)
// df tallies likewise have ONE writer each and merge single-threaded in file order.
inline void addDocBodyFieldsByFileScan( LexMatchTfTable& table, const IngestResult& ing )
{
    const std::size_t fileCount    = ing.files.size();
    const std::size_t variantCount = table.variantCount();

    const SymbolsByFile symbolsOfFile = symbolsByFileInIdOrder( ing, []( const Symbol& ) { return true; } );

    std::vector<std::uint32_t> dfPerFile( variantCount > 0 ? fileCount * variantCount : 0, 0u );   // sized only when armed
    const auto scanFileSymbols = [ & ]( std::size_t f, const std::string& src )
    {
        const std::string_view sv = src;
        std::vector<int>       variantTfBefore( variantCount );
        for( const NodeId i : symbolsOfFile[f] )
        {
            const Symbol&     s         = ing.symbols[i];
            const std::size_t bodyStart = std::min<std::size_t>( s.sigStartByte, src.size() );
            const std::size_t end       = std::min<std::size_t>( s.endByte, src.size() );
            const std::size_t docStart  = docCommentStart( src, bodyStart );
            const int* const  variantTf = table.row( i ) + table.uniqueCount;
            // snapshot the variant columns: df must count ONLY pass-2 (doc/body) growth, never pass-1 name/callee tf
            std::copy( variantTf, variantTf + variantCount, variantTfBefore.begin() );
            if( bodyStart > docStart )
            {
                table.addField( i, sv.substr( docStart, bodyStart - docStart ), kLexWeightDoc );
            }
            if( end > bodyStart )
            {
                table.addField( i, sv.substr( bodyStart, end - bodyStart ), kLexWeightBody );
            }
            for( std::size_t v = 0; v < variantCount; ++v )
            {
                dfPerFile[ f * variantCount + v ] += variantTf[v] > variantTfBefore[v] ? 1u : 0u;
            }
        }
    };
    std::atomic<std::size_t> nextFileIndex { 0 };
    const auto               fileWorker = [ & ]() noexcept
    {
        try
        {
            std::string loadedText;
            for( std::size_t f = nextFileIndex.fetch_add( 1 ); f < fileCount; f = nextFileIndex.fetch_add( 1 ) )
            {
                if( symbolsOfFile[f].empty() )
                {
                    continue; // no symbols in this file → skip
                }
                const std::string* src = lexicalScanText( ing, f, loadedText );
                if( src != nullptr && !src->empty() )
                {
                    scanFileSymbols( f, *src );   // unreadable/empty → degrade (skip), as before
                }
            }
        }
        catch( ... )   // a throw escaping a worker thread is std::terminate — degrade to partial counts instead
        {
            rw::emitRaw( stderr, "ripwire: lexical scan worker degraded (exception swallowed)\n" );
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
            table.variantDocDf[v] += dfPerFile[ f * variantCount + v ];
        }
    }
}

// pass 2 — doc-comment (×kLexWeightDoc) + body (×kLexWeightBody), from whichever source the ingest has (hasPersistedLexStats)
inline void addDocBodyFields( LexMatchTfTable& table, const IngestResult& ing )
{
    if( hasPersistedLexStats( ing ) )
    {
        addDocBodyFieldsFromPersistedStats( table, ing );
        return;
    }
    addDocBodyFieldsByFileScan( table, ing );
}

// ── IDF-guard admission (rung R3) — the same decision after EITHER pass-2 source ─────────────────────────
// A variant whose doc/body document frequency is corpus-common (df > max(8, rankedCount/64)) is rejected; a corpus-rare
// one is admitted and folds into its original token's row — the exact integers the un-guarded arm would have
// accumulated there. The cap reads the ranked corpus: an unranked unit does not widen it. Returns one flag per variant
// (empty when disarmed); RIPWIRE_QSTEM_DEBUG prints each verdict on stderr.
inline std::vector<char> admitRareStemVariants( const LexMatchTfTable& table, std::size_t rankedCount )
{
    const std::vector<std::uint32_t>& dfVariant = table.variantDocDf;
    const std::uint32_t sOver64    = std::uint32_t( rankedCount / 64 );
    const std::uint32_t variantCap = sOver64 > 8u ? sOver64 : 8u;
    std::vector<char>   admitted( dfVariant.size(), 0 );
    for( std::size_t v = 0; v < dfVariant.size(); ++v )
    {
        admitted[v] = dfVariant[v] <= variantCap ? 1 : 0;
    }
    const bool debug = !dfVariant.empty() && std::getenv( "RIPWIRE_QSTEM_DEBUG" ) != nullptr;
    for( std::size_t v = 0; v < dfVariant.size() && debug; ++v )
    {
        rw::emitTo( stderr, "qstem-guard: \"{}\" df={} cap={} {}\n", table.matchToks[ table.uniqueCount + v ].tok.c_str(), dfVariant[v],
                    variantCap, admitted[v] != 0 ? "admitted" : "rejected" );
    }
    return admitted;
}

// ── L-W: the term evidence, read off the FINAL tf rows (LexTermTfTable: every field, the fold applied) — one S×U
// integer scan, the same "tf > 0" fact the document frequency counts when scoring. nameMask is pass 1's
// (addNameAndCalleeFieldsCapturingNameHits), sized for the same term count — asserted, not assumed.
inline void recordTermEvidence( LexTermEvidence& evidence, const LexTermTfTable& table, const LexCorpusRoles& roles, const DedupedQueryTerms& dedup )
{
    const std::size_t S             = table.docCount();
    const std::size_t uniqueCount   = table.uniqueCount;
    const std::size_t evidenceWords = LexTermEvidence::maskWordsFor( uniqueCount );
    DASSERT( evidence.maskWords == evidenceWords && evidence.nameMask.size() == S * evidenceWords,
             "pass 1 captures the name mask for the same symbols and terms before the evidence is recorded" );
    evidence.termsSeenTotal = dedup.uniqueSeenTotal;
    evidence.termsCapped    = dedup.capped;
    evidence.terms.assign( dedup.uniqueToks.begin(), dedup.uniqueToks.end() );
    evidence.df.assign( uniqueCount, 0u );
    evidence.anyMask.assign( S * evidenceWords, 0u );
    evidence.symbolCount = S;
    evidence.statsCount  = roles.countedCount;
    for( std::size_t i = 0; i < S; ++i )
    {
        const int* const row   = table.row( i );
        std::uint64_t*   words = evidence.anyMask.data() + i * evidenceWords;
        const int        w     = roles.statsWeight( i );
        for( std::size_t u = 0; u < uniqueCount && !roles.isUnranked( i ); ++u )
        {
            evidence.df[u] += row[u] > 0 ? std::uint32_t( w ) : 0u;
            words[ u / 64 ] |= row[u] > 0 ? std::uint64_t( 1 ) << ( u % 64 ) : 0u;
        }
    }
}

// ── SIRA term margin — the decision (docs/EVALS.md, PRE-REGISTERED 2026-09-05) ────────────────────
// A query term earns its contribution by SEPARATING the target from corpus-level confusers, not by
// looking relevant. BM25's own idf says when that stops being true: at df = S/2,
// idf = ln( (S-n+0.5)/(n+0.5) + 1 ) is exactly ln 2 — one bit, the point at which observing the term
// halves the candidate space. Above it the term carries less than a bit and hands its tf mass to
// whichever document recites it most, which on a natural-language query ("how does the csrf token
// get validated") is the prose, not the answer. This ranker has no query-side stopword list, and a
// corpus-statistics margin test is that idea derived from the tree in front of it rather than
// written down in English — a Rust corpus's `mut` and a Python corpus's `self` are caught by the
// same arithmetic that catches `the`, with nothing language-specific anywhere.
//
// TWO FIELDS, because ONE field is how the LB-1 negative happened. That round's IDF floor read
// document frequency alone and deleted `module` — the truth's own name carrier — flipping a hit to
// a miss (docs/EVALS.md §7). A term that names between 1 and S/2 symbols separates on the field
// this scorer weights highest, whatever its body mass says, so the name margin keeps it. A term
// naming NOTHING has no name margin to appeal to; a term naming MORE than half the corpus has no
// margin there either.
//
// THE SOLE-ANCHOR GUARD, and the trap inside it. Suppression is skipped entirely unless a PRESENT,
// non-suppressed term survives it — otherwise a query whose every term is corpus-saturating scores
// zero everywhere, which is the catastrophic shape, not a ranking. "Present" is load-bearing and is
// the subtle half: an ABSENT term (df = 0) has the LARGEST idf in the whole scheme,
// ln( (S+0.5)/0.5 + 1 ), so an implementation that asks "did a higher-idf term survive?" without
// excluding absent terms reads a typo beside the anchor as excellent evidence and drops the anchor.
// Gated: test/termmargincheck.sh arms (b), (c) and (d), each red before this code existed.
//
// KEPT OR DROPPED, never fractionally weighted. A kept term's contribution is the historical
// expression evaluated in the historical order — bit-identical, not merely close — and a dropped
// term's impact cap is 0, so the MaxScore bound stays a valid bound and the pruned and exhaustive
// modes stay byte-identical to each other. `dl` is untouched: a suppressed term's EVIDENCE
// vanishes, the document's length does not, exactly the posture the R3 variant guard already takes.
//
// Each present term gets ONE verdict, decided here; termKept and the RIPWIRE_TERMMARGIN_DEBUG lines both read it.
enum class TermMarginVerdict : std::uint8_t
{
    kAbsent,              // df 0: contributes nothing, survives nothing
    kDocSeparates,        // kept: its document frequency alone is under the cut
    kNameSeparates,       // kept: it names between 1 and cut units (the LB-1 protection)
    kSoleAnchor,          // would be suppressed, but no present term survives — suppression withheld for the whole query
    kSuppressed,
};

// Returns termKept per unique term: all 1 when the margin is disarmed.
inline std::vector<char> judgeTermMargins( const LexTermTfTable& table, const LexCorpusRoles& roles, const std::vector<std::string>& uniqueToks )
{
    const std::size_t uniqueCount = table.uniqueCount;
    std::vector<char> termKept( uniqueCount, 1 );
    if( !table.margin.armed() )
    {
        return termKept;
    }
    // df in fixed doc order over the folded rows — the same integers both pass-2 sources produced
    std::vector<int> dfMargin( uniqueCount, 0 );
    for( std::size_t i = 0; i < table.docCount(); ++i )
    {
        const int* const tfRow = table.row( i );
        const int        w     = roles.statsWeight( i );
        for( std::size_t u = 0; u < uniqueCount; ++u )
        {
            dfMargin[u] += tfRow[u] > 0 ? w : 0;
        }
    }
    // "separates" at k bits: idf_u >= k*ln2  ⇔  (S-n+0.5)/(n+0.5) + 1 >= 2^k  ⇔  n <= (S+0.5)/2^k - 0.5,
    // which at k = 1 is exactly n <= S/2. Evaluated in doubles from integer inputs, so it is a pure
    // function of (S, n, k) and cannot vary run to run.
    const double                   separationCut = ( double( roles.countedCount ) + 0.5 ) / std::exp2( double( table.margin.bits ) ) - 0.5;
    std::vector<TermMarginVerdict> verdict( uniqueCount, TermMarginVerdict::kAbsent );
    std::size_t                    presentCount = 0, survivorCount = 0;
    for( std::size_t u = 0; u < uniqueCount; ++u )
    {
        const bool separatesDoc  = double( dfMargin[u] ) <= separationCut;
        const bool separatesName = table.nameDf[u] > 0 && double( table.nameDf[u] ) <= separationCut;
        verdict[u] = dfMargin[u] == 0 ? TermMarginVerdict::kAbsent
                   : separatesDoc     ? TermMarginVerdict::kDocSeparates
                   : separatesName    ? TermMarginVerdict::kNameSeparates
                                      : TermMarginVerdict::kSuppressed;
        presentCount += dfMargin[u] > 0 ? 1 : 0;
        survivorCount += verdict[u] == TermMarginVerdict::kDocSeparates || verdict[u] == TermMarginVerdict::kNameSeparates ? 1 : 0;
    }
    const bool applySuppression = survivorCount > 0;            // the sole-anchor guard
    for( std::size_t u = 0; u < uniqueCount; ++u )
    {
        if( verdict[u] == TermMarginVerdict::kSuppressed && !applySuppression )
        {
            verdict[u] = TermMarginVerdict::kSoleAnchor;
        }
        termKept[u] = verdict[u] == TermMarginVerdict::kSuppressed ? 0 : 1;
    }
    if( std::getenv( "RIPWIRE_TERMMARGIN_DEBUG" ) != nullptr )
    {
        static constexpr const char* kVerdictText[] = { "absent", "kept (doc-separates)", "kept (name-separates)", "kept (sole-anchor)",
                                                        "SUPPRESSED" };
        for( std::size_t u = 0; u < uniqueCount; ++u )
        {
            rw::emitTo( stderr, "term-margin: \"{}\" df={}/{} nameDf={} bits={} {}\n", uniqueToks[u].c_str(), dfMargin[u], roles.countedCount,
                        table.nameDf[u], table.margin.bits, kVerdictText[ std::size_t( verdict[u] ) ] );
        }
        rw::emitTo( stderr, "term-margin: {} present, {} survive, suppression {}\n", presentCount, survivorCount,
                    applySuppression ? "applied" : "withheld (sole-anchor)" );
    }
    return termKept;
}

// The corpus statistics BM25 scores against, tallied in ONE pass over the final tf rows in ascending doc id, and the
// (k1, b) it scores with (A4: resolveBm25Params, the ONE definition the impact bound reads too).
// avgdl accumulates in the historical doc order (integer sums: exact in any order anyway). dfreq[u] = COUNTED units
// containing unique query token u (w ≥ 1, so tf > 0 ⇔ the old docs[i] contained it); dfOut[u] = statsOut units carrying
// it (all 0 with no statsOut). A counted unit scores with (countedCount, dfreq, avgdlCounted); a statsOut unit against
// the whole ranked corpus (rankedCount, dfreq + dfOut, avgdlRanked), as with no statsOut. That choice is made HERE,
// once per term and role: idfCounted / idfRanked (bm25Idf over each role's N and df) and avgdlOf(role) are what the
// scorer and the MaxScore bound read, so neither re-derives which corpus a unit scores against.
struct LexBm25Stats
{
    std::vector<int>           dfreq;
    std::vector<int>           dfOut;
    std::vector<int>           tfMaxOf;        // per term, its largest weighted tf anywhere — the MaxScore bound's T
    std::vector<std::uint32_t> candidateIds;   // ascending: every unit with any tf > 0
    std::vector<double>        idfCounted;     // per term, a counted unit's idf: bm25Idf( countedCount, dfreq )
    std::vector<double>        idfRanked;      // per term, a statsOut unit's idf: bm25Idf( rankedCount, dfreq + dfOut )
    double                     avgdlCounted = 0;
    double                     avgdlRanked  = 0;
    Bm25Params                 params       = kBm25Default;

    double idfOf( std::size_t u, bool statsOut ) const noexcept { return statsOut ? idfRanked[u] : idfCounted[u]; }
    double avgdlOf( bool statsOut ) const noexcept { return statsOut ? avgdlRanked : avgdlCounted; }
};

inline LexBm25Stats tallyBm25Stats( const LexTermTfTable& table, const LexCorpusRoles& roles )
{
    const std::size_t S           = table.docCount();
    const std::size_t uniqueCount = table.uniqueCount;
    LexBm25Stats      st;
    st.dfreq.assign( uniqueCount, 0 );
    st.dfOut.assign( uniqueCount, 0 );
    st.tfMaxOf.assign( uniqueCount, 0 );
    st.candidateIds.reserve( 1024 );
    for( std::size_t i = 0; i < S; ++i )
    {
        st.avgdlCounted += roles.statsWeight( i ) != 0 ? table.dl[i] : 0;
        st.avgdlRanked += roles.isUnranked( i ) ? 0 : table.dl[i];
        const int* const tfRow = table.row( i );
        const int        w     = roles.statsWeight( i );
        const int        out   = roles.isStatsOut( i ) ? 1 : 0;
        bool             any   = false;
        for( std::size_t u = 0; u < uniqueCount; ++u )
        {
            const bool carries = tfRow[u] > 0;
            st.dfreq[u] += carries ? w : 0;
            st.dfOut[u] += carries ? out : 0;
            st.tfMaxOf[u] = std::max( st.tfMaxOf[u], tfRow[u] );
            any           = any || carries;
        }
        if( any )
        {
            st.candidateIds.push_back( std::uint32_t( i ) );
        }
    }
    st.avgdlCounted /= double( roles.countedCount ? roles.countedCount : 1 );
    st.avgdlRanked /= double( roles.rankedCount ? roles.rankedCount : 1 );
    st.idfCounted.resize( uniqueCount );
    st.idfRanked.resize( uniqueCount );
    for( std::size_t u = 0; u < uniqueCount; ++u )
    {
        st.idfCounted[u] = bm25Idf( double( roles.countedCount ), double( st.dfreq[u] ) );
        st.idfRanked[u]  = bm25Idf( double( roles.rankedCount ), double( st.dfreq[u] + st.dfOut[u] ) );
    }
    st.params = resolveBm25Params();
    return st;
}

// ── H2 (B0 round 2): MaxScore-style SAFE early termination, decided once ────────────────────────────────
// Armed only when the caller opted in (pruneTopK > 0: it consumes only the top-pruneTopK ranked units, plus
// `alwaysExact` — e.g. every interface packLego may surface) AND the RIPWIRE_NO_PRUNE escape hatch is off (the
// postingscheck equivalence gate flips it). Disarmed, skips() is always false and the scorer is exhaustive.
//
// The PROVABLY-SAFE per-term impact bound (the MaxScore "max contribution"): a term u's contribution to any doc is
// idf_u × tf(k1+1)/(tf + k1(1−b+b·dl/avgdl)). Two exact monotonicities bound it: it INCREASES in tf (so tf ≤ T :=
// tfMaxOf[u], the largest weighted tf of u anywhere in the corpus) and DECREASES in dl (dl ≥ 0 ⇒ the mixed factor
// ≥ 1−b), giving
//   contribution ≤ idf_u × T(k1+1)/(T + k1(1−b))   in REAL arithmetic.
// In IEEE doubles each side is computed with ≤ 7 rounded ops (relative error ≤ 7·2⁻⁵³ ≈ 8e-16), so the ×(1+1e-9)
// slack — six orders of magnitude above the worst accumulated rounding, and likewise above the U·2⁻⁵³ summation
// error of the per-doc bound sum — makes the COMPUTED cap strictly ≥ the COMPUTED contribution. The Section ×0.30
// down-weight and the §P4 tier multiplier (both (0,1], shrink-only) only shrink a real score, never the bound.
// Hence: bound < θ ⇒ computed score < θ, unconditionally. capOcc folds in the query-occurrence multiplicity (BM25
// adds one contribution PER occurrence).
//
// θ = K-th best exact score seen so far (min-heap; grows monotonically). θ at skip time ≤ final θ ≤ the true K-th
// best overall, and skipping needs bound < θ STRICTLY, so a skipped doc's true score is strictly below the final
// K-th score — it cannot enter the top-K even via the (score desc, id asc) tie-break. Docs are visited in ascending id
// (determinism). Safety is absolute, not approximate: the emitted top-K set, their EXACT scores, and their
// (score desc, id asc) order are byte-identical to exhaustive scoring.
class LexTopKPruner
{
public:
    LexTopKPruner( std::size_t pruneTopK, const std::vector<char>* alwaysExact, const LexBm25Stats& st, const DedupedQueryTerms& dedup,
                   const std::vector<char>& termKept )
        : topK_( std::getenv( "RIPWIRE_NO_PRUNE" ) == nullptr ? pruneTopK : 0 ), alwaysExact_( alwaysExact )
    {
        if( topK_ == 0 )
        {
            return;
        }
        heap_.reserve( topK_ );
        const std::size_t uniqueCount = st.dfreq.size();
        std::vector<int>  occCount( uniqueCount, 0 );
        for( const std::size_t u : dedup.uniqueIndexOfQtok )
        {
            if( u != DedupedQueryTerms::kDroppedTerm )   // capped past kMaxUniqueQueryTerms — owns no row, no contribution
            {
                ++occCount[u];
            }
        }
        capOcc_.assign( uniqueCount, 0.0 );
        for( std::size_t u = 0; u < uniqueCount; ++u )
        {
            if( st.dfreq[u] + st.dfOut[u] == 0 || termKept[u] == 0 )
            {
                continue; // never contributes anywhere — a suppressed term's cap stays 0, and a cap of
                          // 0 bounds a contribution of 0, so the MaxScore proof above is unchanged
            }
            // the larger of the two roles' idf bounds the contribution; a role no unit carrying u plays contributes 0
            const double idfIn  = st.dfreq[u] > 0 ? st.idfCounted[u] : 0.0;
            const double idfAll = st.dfOut[u] > 0 ? st.idfRanked[u] : 0.0;
            const double idf    = std::max( idfIn, idfAll );
            const double cap1   = bm25ImpactBound( idf, double( st.tfMaxOf[u] ), st.params );   // A4: shared bound, same (k1,b)
            capOcc_[u]          = cap1 * double( occCount[u] );
        }
    }

    // true iff unit i provably cannot enter the top-K: its bound (adds only, fixed u-ascending order) is below θ
    bool skips( std::uint32_t i, const int* tfRow ) const
    {
        if( topK_ == 0 || ( alwaysExact_ && i < alwaysExact_->size() && ( *alwaysExact_ )[i] != 0 ) )
        {
            return false;
        }
        double ub = 0.0;
        for( std::size_t u = 0; u < capOcc_.size(); ++u )
        {
            if( tfRow[u] > 0 )
            {
                ub += capOcc_[u];
            }
        }
        return ub < theta_;
    }

    void record( double sc )
    {
        if( topK_ == 0 )
        {
            return;
        }
        if( heap_.size() < topK_ )
        {
            heap_.push_back( sc );
            std::push_heap( heap_.begin(), heap_.end(), std::greater<double>{} );
            theta_ = heap_.size() == topK_ ? heap_.front() : theta_;
            return;
        }
        if( sc > heap_.front() )
        {
            std::pop_heap( heap_.begin(), heap_.end(), std::greater<double>{} );
            heap_.back() = sc;
            std::push_heap( heap_.begin(), heap_.end(), std::greater<double>{} );
            theta_ = heap_.front();
        }
    }

private:
    std::size_t              topK_;
    const std::vector<char>* alwaysExact_;
    std::vector<double>      capOcc_;
    std::vector<double>      heap_;              // min-heap over exact final scores
    double                   theta_ = -1.0;      // scores are ≥ 0 ⇒ no skips until K units scored
};

// The exact BM25 score of every candidate the pruner does not rule out — the historical expressions in the historical
// order (one contribution PER query occurrence, ascending qi; a kept term only, and termKept is all-1 disarmed). Every
// other unit keeps the +0.0f the vector starts with, which is exactly what exhaustive scoring computes for it:
//   - a non-candidate has no tf > 0 for any term, so its sum is +0.0, and the Section ×0.30 and the §P4 tier multiplier
//     keep it +0.0 because every multiplier is in (0,1] (filter.h rankTierSymbolMultipliersShaped; the DASSERT below);
//   - a kRankFlagNotLexRanked unit (model.h) scores 0;
//   - a pruned unit provably cannot enter the top-K the caller consumes (LexTopKPruner).
// So the exhaustive mode needs no loop of its own: it is this loop with a pruner that never skips.
inline std::vector<float> scoreLexCandidates( const IngestResult& ing, const LexTermTfTable& table, const LexBm25Stats& st, const LexCorpusRoles& roles,
                                              const DedupedQueryTerms& dedup, const std::vector<char>& termKept, LexTopKPruner& pruner,
                                              const std::vector<float>* symbolScoreMul )
{
    DASSERT( symbolScoreMul == nullptr || std::ranges::all_of( *symbolScoreMul, []( float mul ) { return mul > 0.f && mul <= 1.f; } ),
             "a tier multiplier outside (0,1] would score a non-candidate unit other than +0.0f and break the MaxScore bound" );
    const std::vector<std::size_t>& uniqueIndexOfQtok = dedup.uniqueIndexOfQtok;
    const std::vector<int>&         dl                = table.dl;
    const double                    k1 = st.params.k1, b = st.params.b;
    std::vector<float>              score( dl.size(), 0.f );
    for( const std::uint32_t i : st.candidateIds )
    {
        const int* tfRow = table.row( i );
        if( roles.isUnranked( i ) || pruner.skips( i, tfRow ) )
        {
            continue;
        }
        const bool   outI = roles.isStatsOut( i );
        const double avgI = st.avgdlOf( outI );
        double sc = 0;
        for( std::size_t qi = 0; qi < uniqueIndexOfQtok.size(); ++qi )
        {
            const std::size_t u  = uniqueIndexOfQtok[qi];
            if( u == DedupedQueryTerms::kDroppedTerm )
            {
                continue;               // capped past kMaxUniqueQueryTerms — owns no row, no contribution
            }
            const int         tf = tfRow[u];
            if( tf == 0 || termKept[u] == 0 )
            {
                continue; // old: docs[i].find( qt ) == end — termKept is all-1 disarmed, so this is that
            }
            const double idf = st.idfOf( u, outI );
            sc += idf * ( tf * ( k1 + 1.0 ) ) / ( tf + k1 * ( 1.0 - b + b * dl[i] / ( avgI > 0 ? avgI : 1.0 ) ) );
        }
        // Markdown headings (sec) compete on name-match with code; down-weight so a doc stays FINDABLE but
        // code wins when both match — fixes prose swamping retrieval in doc-heavy repos (review finding #4).
        if( ing.symbols[i].kind == SymKind::Section )
        {
            sc *= 0.30;
        }
        if( symbolScoreMul && i < symbolScoreMul->size() )
        {
            sc *= double( ( *symbolScoreMul )[i] ); // §P4 tier down-weight — shrink-only, bound-safe
        }
        score[i] = float( sc );
        pruner.record( sc );
    }
    return score;
}

// BM25 score of `query` against each symbol's doc (name subtokens + callees' names + DOC-COMMENT & BODY
// text). Returns a per-symbol score vector (size = symbols.size()). Cold path: one query. The steps above, in order.
inline std::vector<float> lexicalScoresTiered( const IngestResult& ing, const std::vector<std::uint32_t>& outOff,
                                               const std::vector<NodeId>& outTargets, std::string_view query,
                                               std::size_t pruneTopK, const std::vector<char>* alwaysExact,
                                               const std::vector<float>* symbolScoreMul, int pathFieldDefaultW = 0,
                                               int basenameFieldDefaultW = 0, std::string_view pathRootPrefix = {},
                                               LexTermEvidence* evidenceOut = nullptr,   // L-W: the term evidence, read back out (see the struct)
                                               const std::vector<char>* statsOut = nullptr )   // units scored but kept OUT of the corpus statistics
{
    PROFILE_SCOPE_DESCRIBE( "lexical: lexicalScores (BM25 over symbols)" );
    const std::size_t    S     = ing.symbols.size();
    const LexCorpusRoles roles = assignLexCorpusRoles( ing, statsOut );

    // query subtokens — occurrence order preserved (BM25 adds one contribution PER occurrence, as before);
    // an empty query scores exactly 0 everywhere (0.0 survives the Section down-weight unchanged)
    std::vector<std::string> qToks;
    subtokens( query, qToks );
    if( qToks.empty() )
    {
        if( evidenceOut )
        {
            *evidenceOut             = LexTermEvidence{};
            evidenceOut->symbolCount = S;
            evidenceOut->statsCount  = S;   // no term, so no idf ever reads it
        }
        return std::vector<float>( S, 0.f );
    }

    // dedupe to the unique terms whose statistics we need — a duplicated query word must not double-count
    // tf, but still contributes once PER OCCURRENCE in the scoring loop (uniqueIndexOfQtok maps back) —
    // capped (see dedupeQueryTerms above) so a pathologically term-rich query cannot blow up the tf table's
    // S×terms allocation below.
    const DedupedQueryTerms        dedup     = dedupeQueryTerms( qToks, kMaxUniqueQueryTerms );
    const std::vector<LexMatchTok> matchToks = buildLexMatchTable( dedup.uniqueToks );
    LexMatchTfTable                fields( S, matchToks, dedup.uniqueToks.size(), termMarginFromEnv() );

    // the fields, weakest dependence first: name + callee (pass 1), path (1.5) and basename (1.6) need no file text,
    // so they run before the pass-2 source split; then doc-comment + body (pass 2) from whichever source the ingest has
    addNameAndCalleeFieldsCapturingNameHits( fields, ing, outOff, outTargets, roles, evidenceOut );
    addPathField( fields, ing, fieldWeightOrEnv( pathFieldDefaultW, "RIPWIRE_PATHTOK_W" ), pathRootPrefix );
    addBasenameField( fields, ing, fieldWeightOrEnv( basenameFieldDefaultW, "RIPWIRE_BASENAME_W" ), pathRootPrefix );
    addDocBodyFields( fields, ing );

    // what the corpus statistics decide: which stem variants stay (the fold leaves one row per query term), then
    // which query terms separate
    const std::vector<char> admitted = admitRareStemVariants( fields, roles.rankedCount );
    const LexTermTfTable    terms    = std::move( fields ).foldAdmittedVariants( admitted );
    if( evidenceOut )
    {
        recordTermEvidence( *evidenceOut, terms, roles, dedup );
    }
    const std::vector<char> termKept = judgeTermMargins( terms, roles, dedup.uniqueToks );

    // score: corpus statistics, then every candidate the MaxScore pruner (armed only on request) does not rule out
    const LexBm25Stats stats = tallyBm25Stats( terms, roles );
    LexTopKPruner      pruner( pruneTopK, alwaysExact, stats, dedup, termKept );
    return scoreLexCandidates( ing, terms, stats, roles, dedup, termKept, pruner, symbolScoreMul );
}

// the un-tiered contract every pre-§P4 caller keeps (evals, exemplar, --recall): same arity as always,
// byte-identical scores (a null multiplier is the identity in scoreLexCandidates above, pruned or exhaustive).
inline std::vector<float> lexicalScores( const IngestResult& ing, const std::vector<std::uint32_t>& outOff,
                                         const std::vector<NodeId>& outTargets, std::string_view query,
                                         std::size_t pruneTopK = 0, const std::vector<char>* alwaysExact = nullptr,
                                         int pathFieldDefaultW = 0, std::string_view pathRootPrefix = {} )
{
    return lexicalScoresTiered( ing, outOff, outTargets, query, pruneTopK, alwaysExact, nullptr, pathFieldDefaultW,
                                /*basenameFieldDefaultW=*/0, pathRootPrefix );
}

// ─── whole-name / name-exact BM25 (EXPERIMENTAL, --route's identifier-query ranker) ──────────────────
//
// lexicalScores() above SUBTOKENIZES both the query and each symbol's document, so "buildGraph" matches
// any symbol whose name/body contains "build" OR "graph". That is right for CONCEPTUAL queries but wrong
// when the query LITERALLY NAMES a symbol: there you want the symbol whose WHOLE name is "buildGraph",
// not every builder and every graph. This variant scores the query — tokenized on WHITESPACE only, NOT
// subtokenized — against each symbol's document = its WHOLE lowercased name (one token; and its
// container::name as a second whole token when a scope exists, so "graph::buildgraph" can also match).
// Same BM25 parameters (resolveBm25Params(), the ONE definition above) and the same Section down-weight as
// lexicalScores — literally the same declaration since A4's unification, not just the same values. bench/
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

    // dedupe to unique terms (one df/tf statistic each); each occurrence still contributes in the loop —
    // capped (dedupeQueryTerms, kMaxUniqueQueryTerms above) against the same S×terms blow-up.
    DedupedQueryTerms         dedup               = dedupeQueryTerms( qToks, kMaxUniqueQueryTerms );
    std::vector<std::string>& uniqueToks          = dedup.uniqueToks;
    std::vector<std::size_t>& uniqueIndexOfQtok   = dedup.uniqueIndexOfQtok;
    const std::size_t         uniqueCount         = uniqueToks.size();

    // per-doc integer stats (SoA): dl[i] = whole-name token count (1, or 2 with a scope), tfFlat = weighted tf
    std::vector<int> dl( S, 0 );
    std::vector<int> tfFlat( S * uniqueCount, 0 );

    // does an (already lowercased) query token equal a symbol spelling, compared lowercase?
    const auto equalsLowered = []( const std::string& q, std::string_view name ) noexcept
    {
        if( q.size() != name.size() )
        {
            return false;
        }
        for( std::size_t k = 0; k < name.size(); ++k )
        {
            const unsigned char nc = static_cast<unsigned char>( name[k] );
            const char          lc = ( nc >= 'A' && nc <= 'Z' ) ? char( nc - 'A' + 'a' ) : char( nc );
            if( lc != q[k] )
            {
                return false;
            }
        }
        return true;
    };
    // lowercase-compare a symbol's whole name (ONE document token) against every unique query token. `alt` is
    // a second spelling the same token may equal: the arity-less form of an Elixir `name/N` — `run` for
    // `run/2` — so a query that names the function the way Elixir source spells it still hits (PR #81 review
    // item 5: `generate_phoenix_app` routed name-exact and then scored nothing, no_candidates). Empty for
    // every other symbol, where the scoring is byte-identical to before; dl counts the name once either way.
    const auto matchWholeName = [ & ]( std::size_t i, std::string_view name, std::string_view alt )
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
            if( equalsLowered( q, name ) || ( !alt.empty() && equalsLowered( q, alt ) ) )
            {
                ++tfRow[u];
                break; // unique tokens distinct → at most one match
            }
        }
    };

    // kRankFlagNotLexRanked units (model.h) are no document: no tf, no length, not in the corpus size; they score 0
    const std::vector<char> unranked = notLexRankedMask( ing );
    const std::size_t       rankedS  = S - symbolsWithRankFlag( ing, kRankFlagNotLexRanked );
    // document = whole name (+ container::name as a second whole token, when a scope exists)
    for( std::size_t i = 0; i < S; ++i )
    {
        if( !unranked.empty() && unranked[i] != 0 )
        {
            continue;
        }
        const Symbol&          s    = ing.symbols[i];
        const std::string_view base = ( s.lang == Lang::Elixir ) ? elixirBaseName( s.name ) : std::string_view( s.name );
        const std::string_view alt  = ( base.size() != s.name.size() ) ? base : std::string_view{};
        matchWholeName( i, s.name, alt );
        if( !s.scope.empty() )
        {
            std::string qualified = s.scope;
            qualified += "::";
            qualified += s.name;
            std::string qualifiedAlt;
            if( !alt.empty() )
            {
                qualifiedAlt = s.scope;
                qualifiedAlt += "::";
                qualifiedAlt += alt;
            }
            matchWholeName( i, qualified, qualifiedAlt );
        }
    }

    // corpus stats (same doc order → identical doubles); dfreq[u] = #docs containing unique token u
    double avgdl = 0;
    for( int d : dl )
    {
        avgdl += d;
    }
    avgdl /= double( rankedS ? rankedS : 1 );
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

    const Bm25Params    bm25Params = resolveBm25Params();        // A4: the ONE definition — see above
    const double        k1 = bm25Params.k1, b = bm25Params.b;
    std::vector<float> score( S, 0.f );
    for( std::size_t i = 0; i < S; ++i )
    {
        double sc = 0;
        for( std::size_t qi = 0; qi < qToks.size(); ++qi )
        {
            const std::size_t u  = uniqueIndexOfQtok[qi];
            if( u == DedupedQueryTerms::kDroppedTerm )
            {
                continue;                   // capped past kMaxUniqueQueryTerms — owns no row, no contribution
            }
            const int         tf = tfFlat[ i * uniqueCount + u ];
            if( tf == 0 )
            {
                continue;
            }
            const int    n   = dfreq[u];
            const double idf = std::log( ( double( rankedS ) - n + 0.5 ) / ( n + 0.5 ) + 1.0 );
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
// The bodyless predicate is the house one, shared with graph.h's decl/def collapse: model.h
// isDefinitionNotDeclaration (`endByte > sigEndByte`, and a Kotlin type). Deterministic — integer bit patterns, fixed doc
// order, no float arithmetic beyond one nextafter. Returns the number of rows demoted; 0 means the call
// was inert and the vector is byte-identical to what the scorer produced.
inline std::size_t applyDefOverDeclTiebreak( const IngestResult& ing, std::vector<float>& score )
{
    const std::size_t S = ing.symbols.size();
    if( score.size() != S || S == 0 )
    {
        return 0;
    }

    const auto hasBody = [ & ]( std::size_t i ) noexcept { return isDefinitionNotDeclaration( ing.symbols[ i ] ); };
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
    sortutil::sortUnique( distinct );

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
enum class LexMode : std::uint8_t { SubtokenBody, NameExact };

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

// FRAME-HIGH-CONFIDENCE: the anchor of a name-exact route, in the two forms a ranked head row can match. Empty on every other route.
struct RouteAnchorKeys
{
    std::vector<std::string> lowerNames; // each subject word's leaf, lowercased (`a.b.C::d` gives d), and each resolved anchor name
    std::vector<std::uint32_t> fileIds; // the files the anchors are defined in, and a FILE subject's own file
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
    std::string evidence = routeAnchorPath( rootRelPath( ing, at->second.fileId ) );   // #228: "/.../x.h" was every absolute root's anchor
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
// So the claim passes to the first BODY-CARRYING definition in NodeId order, using the plain span test
// `endByte > sigEndByte` — a body to SERVE, which is why it is not model.h's isDefinitionNotDeclaration (that
// predicate also counts a bodyless Kotlin type, a definition with nothing to serve). Three things about the
// shape are load-bearing:
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
inline void noteWholeNameSpelling( HashMap<std::string, NameAnchor>& names, const Symbol& s, std::string_view spelling )
{
    const bool hasBody          = s.endByte > s.sigEndByte;
    const auto [ at, inserted ] = names.try_emplace( routeLower( spelling ), NameAnchor{ s.fileId, 0u, 0u, true, hasBody } );
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

// one symbol's whole name enters the index — and, for an Elixir callable indexed as `name/N`, its arity-less
// spelling too: the source spells it `name`, and so does a query, so a plain word naming an Elixir function
// is a whole-name hit (the route fires, the anchor names its defining file) rather than a carrier-only miss
// (PR #81 review item 5). Each arity is a further definition of that spelling; extraDefs counts them.
inline void noteWholeNameDef( HashMap<std::string, NameAnchor>& names, const Symbol& s )
{
    noteWholeNameSpelling( names, s, s.name );
    if( s.lang == Lang::Elixir )
    {
        if( const std::string_view base = elixirBaseName( s.name ); base.size() != s.name.size() )
        {
            noteWholeNameSpelling( names, s, base );
        }
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
        if( notLexRanked( s ) )
        {
            continue;   // a unit no lexical lens ranks names no route (model.h kRankFlagNotLexRanked)
        }
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
    // the ranked corpus: a kRankFlagNotLexRanked unit (model.h) is no carrier and does not widen the cap
    const std::size_t   ranked   = ing.symbols.size() - symbolsWithRankFlag( ing, kRankFlagNotLexRanked );
    const std::uint32_t sOver128 = std::uint32_t( ranked / 128 );
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
    // row 6 (2026-09-12): a CODE with the evidence in parentheses — the word that was refused, how many names
    // carry it and how many definitions it has; the legend's route= reading spells what :declined means.
    return "subtoken+body:declined(" + imp.word + ";" + std::to_string( imp.carriers ) + "-carriers,"
         + std::to_string( imp.defs ) + "-defs)";
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

// FOR-ROUTE-DECLINED (src/verbs_for.h appendSubjectGraphVerbBlock): a --for task that is SPELLED as a graph question —
// `path from A to B`, `callers of X`, `common callers of A and B` — gets the --path / --callers / --connect verb
// appended to its ordinary answer. This is the subject-only half: no index, no gold, the words of the task alone.
// Each span is cut at its first qualifier word (for/with/via/in/on/when/using/during/at/near); a slot's candidates
// are its CODE-LIKE tokens last-first (a `.`/`_`/`::`/`()` or an inner capital), and no plain word is ever a
// candidate except the exact entry name `main` — "serialising a dict" / "spawning ripgrep" describe an endpoint,
// they do not name one, so such a task does not fire (test/forroutecheck.sh (n1)/(n2)). Stage 0:
// reports/for-route-s0.md (the ORCH measurement); the rules are its parse.py, minus the plain-word fallback.
enum class GraphSubjectForm : std::uint8_t
{
    Path,      // path from A to B        → --path=A,B
    Callers,   // callers of X            → --callers=X
    Common,    // common callers of A and B → --connect=A,B
};

struct GraphSubject
{
    GraphSubjectForm                       form = GraphSubjectForm::Path;
    std::vector<std::string>               spans;   // the words each slot was read from, after the qualifier cut (for the disclosure)
    std::vector<std::vector<std::string>>  slots;   // per endpoint slot, the candidates in preference order (never empty)
};

namespace detail
{
// a keyword word, case-folded, after its LEADING quote/bracket punctuation only (parse.py's `\b` before the keyword;
// the keyword must still end at whitespace, so `callers,` is not the form)
inline bool graphSubjectWordIs( std::string_view w, std::initializer_list<std::string_view> any )
{
    while( !w.empty() && std::string_view( "`'\"([{" ).find( w.front() ) != std::string_view::npos ) { w.remove_prefix( 1 ); }
    const std::string lw = routeLower( w );
    return std::find( any.begin(), any.end(), std::string_view( lw ) ) != any.end();
}

inline bool graphSubjectIsUpper( char c ) noexcept { return c >= 'A' && c <= 'Z'; }
inline bool graphSubjectIsLower( char c ) noexcept { return c >= 'a' && c <= 'z'; }

// parse.py code_like: a `.` `_` `::` or `()`; or a lower/digit then an upper (camelCase); or a capitalised word of
// length > 3 with another capital after the first letter and a lower case letter after a capital (HTTPServer).
inline bool graphSubjectCodeLike( std::string_view t ) noexcept
{
    if( t.find_first_of( "._" ) != std::string_view::npos || t.find( "::" ) != std::string_view::npos || t.find( "()" ) != std::string_view::npos )
    {
        return true;
    }
    for( std::size_t k = 1; k < t.size(); ++k )
    {
        if( graphSubjectIsUpper( t[k] ) && ( graphSubjectIsLower( t[k - 1] ) || ( t[k - 1] >= '0' && t[k - 1] <= '9' ) ) )
        {
            return true;
        }
    }
    if( t.size() > 3 && graphSubjectIsUpper( t[0] ) )
    {
        bool upperLater = false;
        for( std::size_t k = 1; k < t.size(); ++k ) { upperLater = upperLater || graphSubjectIsUpper( t[k] ); }
        bool lowerAfterUpper = false;
        for( std::size_t k = 1; k < t.size(); ++k ) { lowerAfterUpper = lowerAfterUpper || graphSubjectIsLower( t[k] ); }
        return upperLater && lowerAfterUpper;
    }
    return false;
}

// parse.py QUALW: a qualifier word ends the span (the word itself, case-folded, without surrounding punctuation);
// FOR-ROUTE fix1 (B1): so does a CLAUSE word — the span is one noun phrase, and "… to Widget.refresh and explain how X works"
// or "… then check Y" must not hand the NEXT clause's symbol to the verb.
inline bool graphSubjectQualifier( std::string_view w )
{
    while( !w.empty() && std::string_view( "`'\"([{" ).find( w.front() ) != std::string_view::npos ) { w.remove_prefix( 1 ); }
    while( !w.empty() && std::string_view( "`'\")]},;:?!." ).find( w.back() ) != std::string_view::npos ) { w.remove_suffix( 1 ); }
    return graphSubjectWordIs( w, { "for", "with", "via", "in", "on", "when", "using", "during", "at", "near",
                                    "and", "or", "then", "also", "but", "plus", "versus", "vs", "how", "what", "which", "where", "why", "while",
                                    "since", "because", "so", "if", "afterwards", "explain", "check", "however", "finally", "next", "after",
                                    "before", "whether", "who", "summarise", "summarize", "describe" } );
}

// non-ASCII quotes / brackets / sentence stops (S4): a span word is stripped of these at its edges, and a full-width stop ends the span
// (inside a word too: "Widget.refresh。然后" — no code token holds one)
inline constexpr std::string_view kSubjectOpenQuotes[]  = { "\xC2\xAB", "\xE2\x80\x9C", "\xE2\x80\x98", "\xE3\x80\x8C", "\xE3\x80\x8E", "\xEF\xBC\x88" };   // « “ ‘ 「 『 （
inline constexpr std::string_view kSubjectCloseQuotes[] = { "\xC2\xBB", "\xE2\x80\x9D", "\xE2\x80\x99", "\xE3\x80\x8D", "\xE3\x80\x8F", "\xEF\xBC\x89" };   // » ” ’ 」 』 ）
inline constexpr std::string_view kSubjectFullStops[]   = { "\xE3\x80\x82", "\xEF\xBC\x9B", "\xEF\xBC\x9A", "\xEF\xBC\x81", "\xEF\xBC\x9F", "\xEF\xBC\x8C", "\xE3\x80\x81" };   // 。 ； ： ！ ？ ， 、

// One span word, stripped: `raw` = the word up to a full-width stop (the disclosure keeps it), `text` = raw without its edge
// quotes / brackets / sentence punctuation, `stop` = a sentence stop ended it (`. , ; : ! ?` or a full-width one), `parens` = it
// ended in `()` (a call: code-like although the `()` is dropped).
struct GraphSubjectWord
{
    std::string_view raw, text;
    bool             stop   = false;
    bool             parens = false;
};

inline GraphSubjectWord graphSubjectTrimWord( std::string_view w )
{
    GraphSubjectWord r;
    for( const std::string_view fs : kSubjectFullStops )
    {
        if( const std::size_t at = w.find( fs ); at != std::string_view::npos )
        {
            w      = w.substr( 0, at );
            r.stop = true;
        }
    }
    r.raw = w;
    for( bool moved = true; moved && !w.empty(); )   // leading quote/bracket
    {
        moved = std::string_view( "`'\"([{" ).find( w.front() ) != std::string_view::npos;
        w.remove_prefix( moved ? 1 : 0 );
        for( const std::string_view q : kSubjectOpenQuotes )
        {
            if( !moved && w.starts_with( q ) ) { w.remove_prefix( q.size() ); moved = true; }
        }
    }
    for( bool moved = true; moved && !w.empty(); )   // trailing quote/bracket/sentence punctuation; `()` is remembered, then dropped
    {
        const char c = w.back();
        moved        = true;
        if( w.size() > 2 && w.ends_with( "()" ) ) { r.parens = true; w.remove_suffix( 2 ); }
        else if( std::string_view( ".,;:?!" ).find( c ) != std::string_view::npos ) { r.stop = true; w.remove_suffix( 1 ); }
        else if( std::string_view( "`'\")]}[{(" ).find( c ) != std::string_view::npos ) { w.remove_suffix( 1 ); }
        else
        {
            moved = false;
            for( const std::string_view q : kSubjectCloseQuotes )
            {
                if( !moved && w.ends_with( q ) ) { w.remove_suffix( q.size() ); moved = true; }
            }
        }
    }
    r.text = w;
    return r;
}

// `e.g.` / `i.e.` are prose, `*` would be a --path glob: neither is a name the task wrote
inline bool graphSubjectNameable( std::string_view t ) noexcept
{
    return !t.empty() && t.find( '*' ) == std::string_view::npos && t != "e.g" && t != "i.e" && t != "E.g" && t != "I.e";
}

// one slot: the span's words up to its first qualifier / clause word or its first sentence stop (the stop word is the span's LAST
// word); candidates = code-like tokens last-first, then `main` if the span holds it. Writes the read span.
inline std::vector<std::string> graphSubjectCandidates( std::span<const std::string_view> words, std::string& spanOut )
{
    std::vector<std::string> codeLike;
    bool                     hasMain = false;
    for( std::string_view w : words )
    {
        if( graphSubjectQualifier( w ) )
        {
            break;
        }
        const GraphSubjectWord t = graphSubjectTrimWord( w );
        spanOut += spanOut.empty() ? "" : " ";
        spanOut += t.raw;
        if( graphSubjectNameable( t.text ) )
        {
            if( t.parens || graphSubjectCodeLike( t.text ) ) { codeLike.emplace_back( t.text ); }
            else if( t.text == "main" ) { hasMain = true; }
        }
        if( t.stop )
        {
            break;
        }
    }
    std::vector<std::string> out( codeLike.rbegin(), codeLike.rend() );
    if( hasMain )
    {
        out.emplace_back( "main" );
    }
    return out;
}

using GraphSubjectWords = std::vector<std::string_view>;

// the slots read from w[b, e) per range, in order; nullopt when a slot holds no candidate
inline std::optional<GraphSubject> graphSubjectFill( const GraphSubjectWords& w, GraphSubjectForm form,
                                                     std::initializer_list<std::pair<std::size_t, std::size_t>> ranges )
{
    GraphSubject gs;
    gs.form = form;
    for( const auto& [ b, e ] : ranges )
    {
        std::string              span;
        std::vector<std::string> c = graphSubjectCandidates( std::span<const std::string_view>( w.data() + b, e - b ), span );
        if( c.empty() )
        {
            return std::nullopt;
        }
        gs.spans.push_back( std::move( span ) );
        gs.slots.push_back( std::move( c ) );
    }
    return gs;
}

// the first separator word at or after `from` (needs >= 1 word before it and >= 1 after it); w.size() when none
inline std::size_t graphSubjectSep( const GraphSubjectWords& w, std::size_t from, std::string_view word )
{
    for( std::size_t k = from + 1; k + 1 < w.size(); ++k )
    {
        if( routeLower( w[k] ) == word )
        {
            return k;
        }
    }
    return w.size();
}

// one form's scan: `decided` stops the parse with `gs` (a form that matched decides even when a slot is empty)
struct GraphFormScan
{
    bool                        decided = false;
    std::optional<GraphSubject> gs;
};

// common callers of A and B (the key form: once matched, its slots decide) | calls both A and B (a sentence's phrase: read only when its
// slots hold code)
inline GraphFormScan scanCommonForm( const GraphSubjectWords& w, bool sentencePhrase )
{
    for( std::size_t i = 0; i + 3 < w.size(); ++i )
    {
        const bool matched = sentencePhrase ? graphSubjectWordIs( w[i], { "call", "calls" } ) && routeLower( w[i + 1] ) == "both"
                                            : graphSubjectWordIs( w[i], { "common" } ) && graphSubjectWordIs( w[i + 1], { "caller", "callers" } ) && routeLower( w[i + 2] ) == "of";
        const std::size_t from = i + ( sentencePhrase ? 2 : 3 );
        const std::size_t a    = matched ? graphSubjectSep( w, from, "and" ) : w.size();
        if( a < w.size() )
        {
            std::optional<GraphSubject> gs = graphSubjectFill( w, GraphSubjectForm::Common, { { from, a }, { a + 1, w.size() } } );
            if( gs || !sentencePhrase )
            {
                return { true, std::move( gs ) };
            }
        }
    }
    return {};
}

// [call] path from A to B (the key form) | [call] chain from A to B (a sentence's)
inline GraphFormScan scanPathForm( const GraphSubjectWords& w, std::string_view noun )
{
    for( std::size_t i = 0; i + 3 < w.size(); ++i )
    {
        const std::size_t t = graphSubjectWordIs( w[i], { noun } ) && routeLower( w[i + 1] ) == "from" ? graphSubjectSep( w, i + 2, "to" ) : w.size();
        if( t < w.size() )
        {
            return { true, graphSubjectFill( w, GraphSubjectForm::Path, { { i + 2, t }, { t + 1, w.size() } } ) };
        }
    }
    return {};
}

inline GraphFormScan scanReachForm( const GraphSubjectWords& w )   // A reach(es) B: A's span runs back to the previous clause word or stop
{
    for( std::size_t i = 1; i + 1 < w.size(); ++i )
    {
        if( !graphSubjectWordIs( w[i], { "reach", "reaches" } ) )
        {
            continue;
        }
        std::size_t b = i;
        while( b > 0 && !graphSubjectQualifier( w[b - 1] ) && !graphSubjectTrimWord( w[b - 1] ).stop )
        {
            --b;
        }
        if( std::optional<GraphSubject> gs = graphSubjectFill( w, GraphSubjectForm::Path, { { b, i }, { i + 1, w.size() } } ) )
        {
            return { true, std::move( gs ) };
        }
    }
    return {};
}

inline GraphFormScan scanCallersForm( const GraphSubjectWords& w )   // callers of X
{
    for( std::size_t i = 0; i + 2 < w.size(); ++i )
    {
        if( graphSubjectWordIs( w[i], { "caller", "callers" } ) && routeLower( w[i + 1] ) == "of" )
        {
            return { true, graphSubjectFill( w, GraphSubjectForm::Callers, { { i + 2, w.size() } } ) };
        }
    }
    return {};
}
}   // namespace detail

// nullopt unless the task holds one of the three forms AND every slot has a candidate. Forms are tried common,
// path, callers (parse.py PATS order); the first keyword occurrence of a form anchors it; the first span ends at
// the form's first separator word (`to` / `and`), the last span runs to the end of the task.
// SENTENCE-SUBJECT: the same forms as a sentence spells them, read only when no key form matched (so nothing a key form printed is replaced). `[call] chain from A to B` is `path from A to B`; `calls both A
// and B` asks for their common callers; `A reach(es) B` is a path whose FROM span runs back from `reach` to the previous clause
// word or sentence stop ("How does `ApplicationRef.tick()` reach `refreshView`"). Every slot still needs a code-like candidate, so a
// sentence that only uses the words ("which tests reach the cache", "a chain from start to finish") reads nothing.
inline std::optional<GraphSubject> parseGraphSubject( std::string_view task )
{
    using namespace detail;
    using Scan = GraphFormScan ( * )( const GraphSubjectWords& );
    // the key forms first, in their own order, so a task one of them reads keeps the block it always had; the sentence forms only after
    static constexpr Scan kScans[] = { []( const GraphSubjectWords& x ) { return scanCommonForm( x, /*sentencePhrase=*/false ); },
                                       []( const GraphSubjectWords& x ) { return scanPathForm( x, "path" ); },
                                       &scanCallersForm,
                                       []( const GraphSubjectWords& x ) { return scanCommonForm( x, /*sentencePhrase=*/true ); },
                                       []( const GraphSubjectWords& x ) { return scanPathForm( x, "chain" ); },
                                       &scanReachForm };
    const GraphSubjectWords w = splitRouteWords( task );
    for( const Scan scan : kScans )
    {
        if( GraphFormScan r = scan( w ); r.decided )
        {
            return std::move( r.gs );
        }
    }
    return std::nullopt;
}

// is w[0..i) a lead-in a path question may open with: nothing, or `trace|show|explain` / `what is`, then an optional `the`, then an
// optional `call|code|execution` (`trace the call path from`, `what is the execution path from`, `path from`)? (S7, rv-py-mod2)
inline bool graphSubjectPathLeadIn( std::span<const std::string_view> w )
{
    std::size_t k = 0;
    if( k < w.size() && detail::graphSubjectWordIs( w[k], { "trace", "show", "explain" } ) )
    {
        ++k;
    }
    else if( k + 1 < w.size() && detail::graphSubjectWordIs( w[k], { "what" } ) && detail::graphSubjectWordIs( w[k + 1], { "is" } ) )
    {
        k += 2;
    }
    k += k < w.size() && detail::graphSubjectWordIs( w[k], { "the" } ) ? 1 : 0;
    k += k < w.size() && detail::graphSubjectWordIs( w[k], { "call", "code", "execution" } ) ? 1 : 0;
    return k == w.size();
}

// the FROM slot of `path from A to B` alone (applyPathFromUpstreamCut): A's candidates even when B names no symbol (`to the migrate
// command's handle`), which parseGraphSubject refuses as a whole; `toCands`, when given, gets B's (often none). Empty unless the task IS a
// path question: `path from` opens it (graphSubjectPathLeadIn: `trace the call path from`, `what is the path from`), and it does not also
// ask for callers (`who calls` / `callers of`, whose rows the rule would move: S7, rv-py-mod2). `strip the directory path from a_start()
// to ...` is not one.
inline std::vector<std::string> parseGraphSubjectPathFrom( std::string_view task, std::vector<std::string>* toCands = nullptr )
{
    const std::vector<std::string_view> w = splitRouteWords( task );
    for( std::size_t i = 0; i + 1 < w.size(); ++i )
    {
        if( ( detail::graphSubjectWordIs( w[i], { "who" } ) && detail::graphSubjectWordIs( w[i + 1], { "calls" } ) )
            || ( detail::graphSubjectWordIs( w[i], { "caller", "callers" } ) && detail::graphSubjectWordIs( w[i + 1], { "of" } ) ) )
        {
            return {};
        }
    }
    for( std::size_t i = 0; i + 3 < w.size(); ++i )
    {
        if( detail::graphSubjectWordIs( w[i], { "path" } ) && routeLower( w[i + 1] ) == "from" )
        {
            if( !graphSubjectPathLeadIn( std::span<const std::string_view>( w.data(), i ) ) )
            {
                return {};
            }
            for( std::size_t k = i + 3; k + 1 < w.size(); ++k )
            {
                if( routeLower( w[k] ) == "to" )
                {
                    std::string span;
                    if( toCands != nullptr )
                    {
                        std::string toSpan;
                        *toCands = detail::graphSubjectCandidates( std::span<const std::string_view>( w.data() + k + 1, w.size() - k - 1 ), toSpan );
                    }
                    return detail::graphSubjectCandidates( std::span<const std::string_view>( w.data() + i + 2, k - i - 2 ), span );
                }
            }
            return {};
        }
    }
    return {};
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

        // camelCase / snake_case shape: an interior uppercase (aB) or an interior underscore (a_b) — the ONE
        // predicate (infra/namesplit.h), shared with the named-identifier mention anchor (mention.h)
        if( namesplit::hasIdentifierShape( w ) )
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
        rc.reason = "name-exact(" + identifierHit + ")";   // row 6: a CODE; the reading lives in the legend (route=)
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
        rc.reason = "subtoken+body";   // row 6: the conceptual ranker, as a code — see the route= legend reading
    }
    else
    {
        rc.which  = LexMode::SubtokenBody;
        rc.reason = "subtoken+body:broad";   // row 6: 1-2 plain words — the legend says plain rg may also win
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
    double      bestDrop       = 0.0;
    std::size_t bestCapCutKept = 0;
    double      bestCapDrop    = 0.0;
    for( std::size_t i = 1; i < scanEnd; ++i )
    {
        const double prev = double( pos[ i - 1 ] );
        const double here = double( pos[ i ] );
        const double drop = prev > 0.0 ? ( prev - here ) / prev : 0.0;
        if( drop > bestDrop ) { bestDrop = drop; }                                // the GLOBAL cliff: only its magnitude is read
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

// The legend clause that defines confidence=/margin_pct= (below). Named (lane r2-LO) so the session dictionary
// (legenddict.h) quotes the same bytes the --for headers append.
inline constexpr std::string_view kForConfidenceNote =
    " [confidence= derives from the ranked head's largest relative score drop (margin_pct=, whole "
    "percent, 0 = none; the same gap the adaptive flag cuts at). low = flat ranking: treat the set "
    "as a starting point, not an answer]";

// ── Homonym-pool decline gate (T14; docs/research/adaptive-short-query.md on lane/research-adaptive-
// shortquery, c04affc2 — investigation only, not merged) ───────────────────────────────────────────────
// A name-exact route against a large pool of identically-named, UNRELATED symbols (every class's own
// `update()`) can still clear kMinCliffDrop above: the drop is real, but it is a drop in the SECONDARY
// (tie-break) key that orders symbols already tied on lexical score, not a drop in relevance — nothing in
// a bare word like "update" picks rank 6 over rank 7 of 231 identical name matches. Left alone, --adaptive
// narrows to a handful of an undifferentiated pool while confidence="high" claims the cut is relevance-
// driven: a confident wrong answer. Measured on two corpora (the doc's word sweep, both routed name-exact):
// every positiveHits>=50 row clears this gate (`update` 231->6, `run` 148->10, `init` 56->7, all kept<=10);
// every harmless name-exact cut measured (pools of 13-37, kept 11-35) does not — leaving a 37..56 margin for
// the threshold below. Reuses AdaptiveCut::positiveHits, already computed for the cut itself — no new
// scorer, no second pass over the score vector (the doc's own rejection criterion for the two alternatives
// it measured and dropped: a query-length/content threshold cannot separate `update` from `adaptiveCut`,
// both one token, one working correctly and one not).
constexpr std::size_t kAdaptiveHomonymPoolFloor = 50;   // positiveHits must clear this; measured gap is 37 (harmless) .. 56 (failing)

inline bool isAdaptiveHomonymDecline( bool nameExactRoute, const AdaptiveCut& cut, std::size_t floorK )
{
    return nameExactRoute && cut.positiveHits > kAdaptiveHomonymPoolFloor && cut.kept <= 2 * floorK;
}

// ── ONE predicate for "is this ranking's route the raw name-exact BM25 lane" (T14 finding 1, review
// rv-t14a.md 2026-09-20) ───────────────────────────────────────────────────────────────────────────────
// The route tag is a three-state string every producer already writes verbatim — "name-exact" |
// "subtoken+body" | "no-route" (packtask.h LensRanking::routeTag's own comment; --no-route leaves the
// field at that struct default rather than routing at all). Three call sites need "is this name-exact"
// for the homonym-decline gate above; ONE of them (runForLens) answered it as `!isConceptualRoute(tag)`
// — a DIFFERENT question ("is this NOT subtoken+body") whose negation is true on "no-route" too, so
// --no-route --adaptive silently mislabeled the un-routed subtoken+body ranking as name-exact and
// declined + fabricated a same-name count on a genuine, unrelated cliff. The other two call sites
// (emitCandidates, MCP `for`) already asked the right question, each with its own string/enum
// comparison — so CLI and MCP disagreed under --no-route. Fixing the negation in place would still
// leave three independent implementations to keep in sync; this is the one all three now call.
inline bool isNameExactRouteTag( const char* routeTag ) noexcept
{
    return routeTag != nullptr && std::strcmp( routeTag, "name-exact" ) == 0;
}

struct ForConfidence
{
    std::string attrs;      // ` confidence="high|low" margin_pct="N"` — root facts, every ladder rung
    std::string note;       // the legend clause defining both (legend-coverage contract)
    const char* level = ""; // "high" | "low" — the JSON dialect's key value
    int         marginPct = 0;
};

// homonymDecline: true when isAdaptiveHomonymDecline fired on this same cut — confidence must not claim
// "high" on a cliff driven by tie-break order rather than relevance (a decline plus a high-confidence
// stamp is the same defect wearing a different hat). marginPct is left as the TRUE measured drop even
// when declined — 0 means "no cliff found" (non-negotiable #3: a zero must mean none found, never none
// exists), and a real 25% tie-break drop is not that; the note's extra clause is what says not to trust it.
// anchorUnproven (subjectanchor.h): a name-exact route whose anchor is served from a test, doc or data file (CONFIDENCE-ANCHOR), or
// whose ranked head is not the anchor (FRAME-HIGH-CONFIDENCE). The drop may be real, but it says the name matched, not that the answer
// is here: low, and route= says why.
inline ForConfidence deriveForConfidence( const rw::AdaptiveCut& cut, int servedTopN, bool homonymDecline, bool anchorUnproven = false )
{
    ForConfidence out;
    const bool servedComplete = cut.positiveHits > 0 && cut.positiveHits <= std::size_t( servedTopN );
    const bool sharpHead = !cut.hitCeiling || servedComplete;
    out.level = ( homonymDecline || anchorUnproven || !sharpHead ) ? "low" : "high";
    out.marginPct = cut.hitCeiling ? 0 : cut.dropPct;
    char attrBuf[ 48 ];
    rw::formatTo( attrBuf, sizeof( attrBuf ), " confidence=\"{}\" margin_pct=\"{}\"", out.level, out.marginPct );
    out.attrs = attrBuf;
    // no "--" anywhere (rides inside an XML comment, where "--" is ill-formed — G4). TERSE on purpose:
    // this rides EVERY --for header and its bytes are charged under an explicit budget, so each word
    // competes with a sig row (the W3-S short-spelling precedent). The full mapping: the --for help text.
    out.note = kForConfidenceNote;
    if( homonymDecline )
    {
        // present-only (fires only on the decline itself — byte-identical elsewhere): margin_pct above is
        // real and nonzero here, which "low = flat ranking" alone does not cover — this clause is what makes
        // the two consistent (T14 requirement 2).
        char db[ 200 ];
        rw::formatTo( db, sizeof( db ),
                       " [{} symbols share this exact name; the drop above is tie-break order among them, not "
                       "relevance, so confidence stays low even though margin_pct is nonzero]",
                       cut.positiveHits );
        out.note += db;
    }
    return out;
}


}   // namespace rw
