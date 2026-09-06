#pragma once

// eval.h — deterministic, LLM-free self-eval (--eval): which ranking recovers a change's CO-CHANGED files
// best? Gold = git's changed-file set per commit. For each qualifying commit (>=2 changed source files,
// <=20 to drop bulk sweeps): seed = the changed file with the MOST symbols (the change's likely hub); gold
// = the OTHER changed files; measure recall@k. The HISTORICAL eval AVERAGES over the last N commits — a
// real benchmark, not n=1 (the n=1 lesson: a single seed is noise). Rankers compared:
//   ripwire = PageRank teleported onto the seed file's symbols      (structural / importance)
//   BM25    = file docs of WHOLE symbol+callee names               (lexical baseline)
//   BM25sub = file docs of camelCase/snake SUBTOKENS               (deterministic-relatedness candidate, E#2)
//   fused   = RRF(ripwire, BM25sub)                                 (does structure ADD on top of lexical?)
//   anchored= anchoredLexicalRank over BM25body                     (--for --anchor's LARGER-style fusion)
// Falls back to the current git diff (n=1) when no history is available. NOT a golden: on a live repo the
// numbers move as commits land — it's a benchmark you re-run, not a byte-stable snapshot.

#include "model.h"
#include "graph.h"
#include "gitmine.h"
#include "lexical.h"   // subtokens()
#include "arch.h"      // rw::fnv1a64 — the path-free sample key; never a second copy of the hash
#include "infra/jsonesc.h"   // W2-M0: rw::jsonStringEnd — the canonical escape-aware JSON string walk

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace rw
{

// recall@k = (gold files within the top-k of `ranked`) / |gold|
inline float recallAtK( const std::vector<std::uint32_t>& ranked, const std::vector<char>& gold,
                        std::size_t goldTotal, std::size_t k )
{
    if( goldTotal == 0 )
    {
        return 0.f;
    }
    std::size_t hit = 0;
    for( std::size_t i = 0; i < ranked.size() && i < k; ++i )
    {
        if( gold[ranked[i]] )
        {
            ++hit;
        }
    }
    return float( hit ) / float( goldTotal );
}

// rank file ids by score descending, id-tiebroken (deterministic)
inline std::vector<std::uint32_t> rankFiles( const std::vector<float>& score )
{
    std::vector<std::uint32_t> order( score.size() );
    for( std::uint32_t f = 0; f < score.size(); ++f )
    {
        order[f] = f;
    }
    std::sort( order.begin(), order.end(),
               [ & ]( std::uint32_t a, std::uint32_t b ) { return score[a] != score[b] ? score[a] > score[b] : a < b; } );
    return order;
}

struct EvalAcc { double r5 = 0, r10 = 0, r20 = 0; };
inline void addRecall( EvalAcc& a, const std::vector<std::uint32_t>& ranked, const std::vector<char>& gold, std::size_t goldTotal )
{
    a.r5  += recallAtK( ranked, gold, goldTotal, 5 );
    a.r10 += recallAtK( ranked, gold, goldTotal, 10 );
    a.r20 += recallAtK( ranked, gold, goldTotal, 20 );
}

// BM25 of `seed`'s doc-bag against every file (seed excluded = -1). docs/dl/avg/df describe ONE tokenization.
inline std::vector<float> bm25Seeded( const std::vector<HashMap<std::string, int>>& docs, const std::vector<int>& dl,
                                      double avg, const HashMap<std::string, int>& df, std::uint32_t F, std::uint32_t seed )
{
    constexpr double   k1 = 1.5, b = 0.75;
    std::vector<float> sc( F, 0.f );
    for( std::uint32_t f = 0; f < F; ++f )
    {
        if( f == seed ) { sc[f] = -1.f; continue; }
        double s = 0;
        for( const auto& [ qt, qc ] : docs[ seed ] )
        {
            const auto it = docs[f].find( qt );
            if( it == docs[f].end() )
            {
                continue;
            }
            const auto   di  = df.find( qt );
            const int    n   = ( di == df.end() ) ? 1 : di->second;
            const int    tf  = it->second;
            const double idf = std::log( ( double( F ) - n + 0.5 ) / ( n + 0.5 ) + 1.0 );
            s += idf * ( tf * ( k1 + 1.0 ) ) / ( tf + k1 * ( 1.0 - b + b * dl[f] / ( avg > 0 ? avg : 1.0 ) ) );
        }
        sc[f] = float( s );
    }
    return sc;
}

// anchored (--for --anchor's fusion, file-granularity mirror): lift the SHIPPING lexical
// base (BM25body — what --for's lexicalScores indexes) to per-symbol anchor confidences, run the REAL
// anchoredLexicalRank (top-N symbol anchors → PPR personalization → λ score-blend), then score a file by
// its BEST symbol (a max — a sum would multiply the file-constant lexical term by symbol count and distort
// the base). Files with no symbols keep the pure (rescaled) lexical term, so the anchored ranking differs
// from BM25body ONLY where the graph walk actually adds mass. Degenerate lexical (no positive score)
// degrades to the base unchanged.
inline std::vector<float> anchoredFileScore( const IngestResult& ing, const Graph& g,
                                             const std::vector<float>& bScore, std::uint32_t seed )
{
    const std::uint32_t F = std::uint32_t( bScore.size() );
    std::vector<float>  lexSym( ing.symbols.size(), 0.f );
    for( const Symbol& s : ing.symbols )
    {
        lexSym[s.id] = bScore[s.fileId];
    }
    const std::vector<float> aSym = anchoredLexicalRank( g, lexSym );

    float bmax = 0.f;
    for( std::uint32_t f = 0; f < F; ++f )
    {
        if( bScore[f] > bmax )
        {
            bmax = bScore[f];
        }
    }
    std::vector<float> aScore( F, 0.f );
    if( bmax > 0.f )
    {
        for( std::uint32_t f = 0; f < F; ++f )
        {
            aScore[f] = ( 1.0f - anchorcfg::kGraphBlend ) * bScore[f] / bmax;
        }
        for( const Symbol& s : ing.symbols )
        {
            if( aSym[s.id] > aScore[s.fileId] )
            {
                aScore[s.fileId] = aSym[s.id];
            }
        }
    }
    else
    {
        aScore = bScore;                                          // degenerate lexical → anchored degrades to it
    }
    aScore[ seed ] = -1.f;
    return aScore;
}

// §P11.12: the interpretive footer for --eval's ranker table, pulled into its own function so the 9-line
// note doesn't inflate runEval's own verbosity (--quality-delta's LOC kind) — this table used to end with a
// bare ranking, which reads as "ripwire loses to BM25" without saying the two rows measure different things.
// --eval-retrieval next door already carries an equivalent note; this table needed the same treatment
// (adoption decisions get read straight off it).
inline void printEvalRankerNote()
{
    std::printf( "  note: `ripwire` here is the DEFAULT MAP's structural-only PageRank (importance, not\n"
                 "        relatedness) — it is NOT what a --for/--query retrieval call ranks with. BM25 /\n"
                 "        BM25sub / BM25body are QUERY-TIME lexical rankers (whole-name / subtoken /\n"
                 "        subtoken+body); fused = RRF(ripwire, BM25sub); anchored = BM25body + anchored PPR\n"
                 "        expansion (--for --anchor, EXPERIMENTAL). The SHIPPED default for --for/--query is\n"
                 "        the subtoken+body lexical family (routed to name-exact only for an identifier-shaped\n"
                 "        query — lexical.h chooseForRanker), so a gap between the ripwire and BM25* rows here\n"
                 "        is structural-importance-vs-lexical-relatedness on a co-change task, not the shipped\n"
                 "        retrieval path losing to an alternative it was never running.\n" );
}

inline int runEval( const std::string& root, const IngestResult& ing, const Graph& g, const std::vector<char>& currentDiff )
{
    const std::uint32_t F = std::uint32_t( ing.files.size() );

    // ---- build BOTH lexical doc models ONCE (whole-name + subtoken), reused across every seed ----
    std::vector<HashMap<std::string, int>> dW( F ), dS( F );
    std::vector<int>                       dlW( F, 0 ), dlS( F, 0 );
    std::vector<std::string>               toks;
    const auto add = [ & ]( std::uint32_t f, const std::string& name )
    {
        dW[f][ name ]++; dlW[f]++;
        toks.clear(); subtokens( name, toks );
        for( const std::string& t : toks ) { dS[f][t]++; dlS[f]++; }
    };
    for( const Symbol& s : ing.symbols )
    {
        add( s.fileId, s.name );
    }
    for( const Reference& rf : ing.references )
    {
        add( rf.fileId, rf.calleeName );
    }

    double avgW = 0, avgS = 0;
    for( int d : dlW )
    {
        avgW += d;
    }
    avgW /= ( F ? F : 1 );
    for( int d : dlS )
    {
        avgS += d;
    }
    avgS /= ( F ? F : 1 );
    HashMap<std::string, int> dfW, dfS;
    for( const auto& d : dW )
    {
        for( const auto& [t, c] : d )
        {
            ++dfW[t];
        }
    }
    for( const auto& d : dS )
    {
        for( const auto& [t, c] : d )
        {
            ++dfS[t];
        }
    }

    // dB = dS (subtoken names+callees, ~2× weighted) + WHOLE-FILE body subtokens — "does adding the file's
    // body vocabulary help relatedness?" (E#2 round 2; mirrors what lexicalScores actually indexes). One
    // read per file, up front.
    std::vector<HashMap<std::string, int>> dB  = dS;
    std::vector<int>                       dlB = dlS;
    for( std::uint32_t f = 0; f < F; ++f )
    {
        std::ifstream in( diskPath( ing, std::uint32_t( f ) ), std::ios::binary );
        if( !in )
        {
            continue;
        }
        std::ostringstream ss;  ss << in.rdbuf();
        const std::string body = ss.str();
        toks.clear(); subtokens( body, toks );
        for( const std::string& t : toks ) { dB[f][t]++; dlB[f]++; }
    }
    double avgB = 0;
    for( int d : dlB )
    {
        avgB += d;
    }
    avgB /= ( F ? F : 1 );
    HashMap<std::string, int> dfB;
    for( const auto& d : dB )
    {
        for( const auto& [t, c] : d )
        {
            ++dfB[t];
        }
    }

    // same-directory baseline: the cheapest real prior ("co-edited files often live together"). Beating it
    // is the bar any structural/lexical ranker must clear to be worth its complexity.
    std::vector<std::string> fileDir( F );
    for( std::uint32_t f = 0; f < F; ++f )
    { const std::string& p = ing.files[f]; const std::size_t sl = p.rfind( '/' ); fileDir[f] = ( sl == std::string::npos ) ? std::string() : p.substr( 0, sl ); }

    std::vector<std::uint32_t> symCount( F, 0 );
    for( const Symbol& s : ing.symbols )
    {
        ++symCount[s.fileId];
    }

    // ---- the benchmark sample: qualifying commit sets (>=2 files); current diff is the n=1 fallback ----
    std::vector<std::vector<std::uint32_t>> sets = gitCommitFileSets( root, ing, "36 months ago", 20 );
    std::vector<std::vector<std::uint32_t>> qual;
    for( const auto& cs : sets )
    {
        if( cs.size() >= 2 )
        {
            qual.push_back( cs );
        }
    }
    constexpr std::size_t kMaxSample = 80;
    if( qual.size() > kMaxSample )
    {
        qual.resize( kMaxSample ); // newest-first (git log order)
    }
    const bool historical = !qual.empty();
    if( !historical )
    {
        std::vector<std::uint32_t> cur;
        for( std::uint32_t f = 0; f < F; ++f )
        {
            if( currentDiff[f] )
            {
                cur.push_back( f );
            }
        }
        if( cur.size() < 2 ) { std::fprintf( stderr, "ripwire --eval: no git-history sample and <2 changed files\n" ); return 1; }
        qual.push_back( cur );
    }

    EvalAcc accCtx, accW, accS, accB, accF, accA, accDir;
    int     n = 0;
    for( const auto& cs : qual )
    {
        std::uint32_t seed = cs.front();                              // seed = most-symbols file (tie → lowest id)
        for( std::uint32_t f : cs )
        {
            if( symCount[f] > symCount[seed] )
            {
                seed = f;
            }
        }
        std::vector<char> gold( F, 0 );
        std::size_t       goldTotal = 0;
        for( std::uint32_t f : cs )
        {
            if( f != seed )
            {
                gold[f] = 1;
                ++goldTotal;
            }
        }
        if( goldTotal == 0 )
        {
            continue;
        }

        std::vector<char> seedMask( F, 0 );  seedMask[ seed ] = 1;    // ripwire: PageRank teleported on the seed
        // .rank only: a scoring harness, not an emitter — it produces a measurement, not a ranked document
        // with a root to disclose on.
        const std::vector<float> r = rankGraphTeleport( g, diffTeleport( ing, seedMask ) ).rank;
        std::vector<float>       ctxScore( F, 0.f );
        for( const Symbol& s : ing.symbols )
        {
            ctxScore[s.fileId] += r[s.id];
        }
        ctxScore[ seed ] = -1.f;

        const std::vector<float> wScore = bm25Seeded( dW, dlW, avgW, dfW, F, seed );
        const std::vector<float> sScore = bm25Seeded( dS, dlS, avgS, dfS, F, seed );
        const std::vector<float> bScore = bm25Seeded( dB, dlB, avgB, dfB, F, seed );
        std::vector<float>       fScore = rrfFuse( { &ctxScore, &sScore } );  fScore[ seed ] = -1.f;

        const std::vector<float> aScore = anchoredFileScore( ing, g, bScore, seed );   // --for --anchor mirror

        addRecall( accCtx, rankFiles( ctxScore ), gold, goldTotal );
        addRecall( accW,   rankFiles( wScore ),   gold, goldTotal );
        addRecall( accS,   rankFiles( sScore ),   gold, goldTotal );
        addRecall( accB,   rankFiles( bScore ),   gold, goldTotal );
        addRecall( accF,   rankFiles( fScore ),   gold, goldTotal );
        addRecall( accA,   rankFiles( aScore ),   gold, goldTotal );

        std::vector<float> dScore( F, 0.f );   // same-directory baseline (1 if same dir as seed, else 0)
        for( std::uint32_t f = 0; f < F; ++f )
        {
            dScore[f] = ( f != seed && fileDir[f] == fileDir[seed] ) ? 1.f : 0.f;
        }
        dScore[ seed ] = -1.f;
        addRecall( accDir, rankFiles( dScore ), gold, goldTotal );
        ++n;
    }
    if( n == 0 ) { std::fprintf( stderr, "ripwire --eval: no qualifying commits\n" ); return 1; }

    const double N   = n;
    const auto   row = [ & ]( const char* name, const EvalAcc& a )
    { std::printf( "  %-9s %8.1f%% %9.1f%% %9.1f%%\n", name, 100.0 * a.r5 / N, 100.0 * a.r10 / N, 100.0 * a.r20 / N ); };
    std::printf( "ripwire --eval  (co-change recovery, averaged over %d %s)\n",
                 n, historical ? "historical commits" : "current diff [n=1, no history]" );
    std::printf( "  %-9s %9s %10s %10s\n", "ranker", "recall@5", "recall@10", "recall@20" );
    row( "ripwire", accCtx );   // structural (PageRank) — importance, not relatedness
    row( "BM25",    accW );     // lexical, whole-name (the original baseline)
    row( "BM25sub", accS );     // lexical, SUBTOKEN names+callees (E#2 round 1 winner)
    row( "BM25body",accB );     // lexical, SUBTOKEN names+callees + WHOLE-FILE body (E#2 round 2)
    row( "fused",   accF );     // RRF(structural, subtoken)
    row( "anchored",accA );     // BM25body + lexically-anchored PPR expansion (--for --anchor, LARGER-style)
    row( "same-dir",accDir );   // cheapest real prior — the bar to beat
    std::printf( "  %-9s %8.1f%% %9.1f%% %9.1f%%   <- floor (random ranking over F=%u files)\n", "random",
                 F > 1 ? 100.0 * 5.0  / double( F - 1 ) : 0.0,
                 F > 1 ? 100.0 * 10.0 / double( F - 1 ) : 0.0,
                 F > 1 ? 100.0 * 20.0 / double( F - 1 ) : 0.0, F );
    printEvalRankerNote();   // §P11.12: names what each ranker is + which one --for/--query actually ships
    return 0;
}

// ── KNOWN-ITEM RETRIEVAL EVAL (--eval-retrieval) ──────────────────────────────────────────────────────
// The co-change --eval above is SEED-based: it validates which ranker recovers a change's OTHER files from a
// seed file, but it CANNOT validate query-TIME ranker choice — does name-exact beat subtoken+body on a NAME
// query? does anchoring help or hurt? Known-item retrieval is the standard IR eval for exactly that: the gold
// item is IN the corpus by construction, so leave-nothing-out is correct. For a deterministic sample of
// symbols that HAVE a doc-comment, build two synthetic queries per symbol — (a) the whole NAME, (b) a
// stopworded phrase from the doc-comment's first line — and for each ranker measure the rank of the gold
// symbol. Report MRR + recall@1/5/10 per ranker per query-mode. Deterministic (no threading in the numbers:
// the rank of the gold symbol is a pure function of the score vector, which is itself deterministic).

// rank (1-based) of `gold` in `score`, sorted desc with id tie-break (matches every other ranker here).
// A gold symbol with a non-positive score that ties many zeros still gets a well-defined deterministic rank.
// MIDRANK over ties — the standard IR/statistics convention, and the SECOND place path spelling used to
// decide a published number. This used to break ties by `i < gold`, i.e. by symbol id, i.e. by CRAWL order,
// i.e. by path: a gold symbol under an early-sorting directory won every tie it was in and one under a
// late-sorting directory lost every tie. That is invisible while the ranker has signal and total where it
// has none — on the name-exact/doc-phrase row nearly every symbol ties at 0, so the reported rank was
// essentially "how many files sort before mine", and the row's recall@1 was luck, not retrieval.
//
// The gold's rank is now its EXPECTED rank under a fair shuffle of the symbols it ties with:
//     1 + #{strictly better} + #{tied with gold, excluding gold} / 2
// which no ordering of the corpus can move. It is fractional by construction, so recall@k reads as
// "the expected rank is within k" — a two-way tie at the top scores 1.5 and does NOT take recall@1
// credit, which is the pessimistic-but-fair reading of a coin flip.
inline double rankOfSymbol( const std::vector<float>& score, NodeId gold )
{
    const float g = score[ gold ];
    std::size_t better = 0;                                   // symbols scoring strictly ahead of gold
    std::size_t tied   = 0;                                   // symbols scoring exactly gold, gold itself excluded
    for( NodeId i = 0; i < score.size(); ++i )
    {
        if( score[i] > g )
        {
            ++better;
        }
        else if( score[i] == g && i != gold )
        {
            ++tied;
        }
    }
    return 1.0 + double( better ) + double( tied ) / 2.0;
}

// first non-empty line of the doc-comment block above `s`, lowercased comment markers stripped, split into
// content WORDS with route-stopwords removed — the (b) doc-phrase query. Empty ⇒ no usable phrase.
inline std::string docPhraseFirstLine( const std::string& src, std::size_t defStart )
{
    const std::size_t ds = docCommentStart( src, defStart );
    if( ds >= defStart )
    {
        return {}; // no doc-comment above the def
    }
    // walk lines [ds, defStart); take the FIRST that carries alphabetic content after stripping markers.
    std::size_t p = ds;
    while( p < defStart )
    {
        std::size_t e = p;
        while( e < defStart && src[e] != '\n' )
        {
            ++e;
        }
        std::string_view line( src.data() + p, e - p );
        // strip leading whitespace + comment markers (// , /// , /* , * , -- , # )
        std::size_t t = 0;
        while( t < line.size() && ( line[t] == ' ' || line[t] == '\t' ) )
        {
            ++t;
        }
        while( t < line.size() && ( line[t] == '/' || line[t] == '*' || line[t] == '#' || line[t] == '-' ) )
        {
            ++t;
        }
        std::string_view content = line.substr( t );
        // does it carry >=1 alphabetic word? build a stopworded phrase from it if so.
        std::string phrase;
        std::size_t ws = std::string_view::npos;
        const auto flush = [ & ]( std::size_t a, std::size_t b )
        {
            if( a == std::string_view::npos )
            {
                return;
            }
            std::string w( content.substr( a, b - a ) );
            for( char& c : w )
            {
                if( c >= 'A' && c <= 'Z' )
                {
                    c = char( c - 'A' + 'a' );
                }
            }
            if( w.size() >= 2 && !isRouteStopword( w ) )
            {
                if( !phrase.empty() )
                {
                    phrase += ' ';
                }
                phrase += w;
            }
        };
        for( std::size_t k = 0; k <= content.size(); ++k )
        {
            const bool alpha = k < content.size() && ( ( content[k] >= 'a' && content[k] <= 'z' ) || ( content[k] >= 'A' && content[k] <= 'Z' ) );
            if( alpha )
            {
                if( ws == std::string_view::npos )
                {
                    ws = k;
                }
            }
            else        { flush( ws, k ); ws = std::string_view::npos; }
        }
        if( !phrase.empty() )
        {
            return phrase; // first content-bearing line wins
        }
        p = e + 1;
    }
    return {};
}

struct RetrievalAcc { double mrr = 0; std::size_t r1 = 0, r5 = 0, r10 = 0, n = 0; };
inline void addRetrieval( RetrievalAcc& a, double rank )
{
    a.mrr += 1.0 / rank;
    if( rank <= 1 )
    {
        ++a.r1;
    }
    if( rank <= 5 )
    {
        ++a.r5;
    }
    if( rank <= 10 )
    {
        ++a.r10;
    }
    ++a.n;
}

// The sampler is an INSTRUMENT, and until 2026-09-05 it reported properties of the CORPUS while claiming to
// report properties of the RANKER. It walked symbol ids from 0 and stopped at the first 150 doc-commented
// symbols; ids are assigned in CRAWL order and the crawl is sorted by path (that ordering is deliberate — it
// is what makes the whole tool deterministic), so the gold set was really "whichever 150 doc-commented
// symbols sort earliest by path". `bench/` sorts before `src/`. A contributor who documented a benchmark
// harness — touching no ranking code whatsoever — displaced real symbols off the tail and moved a PUBLISHED
// number with the ranker byte-identical. Measured at db6a416d with ONE identical 60-symbol probe file placed
// at two paths in an otherwise byte-identical corpus: subtoken/name MRR 0.834 at `aaa_probe/` versus 0.729 at
// `zzz_probe/`, and subtoken/doc-phrase 0.620 versus 0.976. A third of an MRR from path spelling alone.
//
// So: the population is EVERY qualifying symbol, and membership depends only on a symbol's OWN scope::name
// identity — never on its path, never on how many symbols happen to precede it. At or below kMaxScored the
// eval is EXHAUSTIVE (there is no sample, so there is no sampling rule left to get wrong); above it the cut
// is by smallest fnv1a64(scope::name), which is path-free and order-free, and it cuts on the KEY so every
// symbol sharing an identity is admitted or refused together rather than being split by a count boundary.
// Either way the report PRINTS population/scored/rule, because a sample whose rule is invisible is precisely
// the thing that failed here (METHODOLOGY §9 #6: every number has an instrument).
//
// This eval is NOT a golden. Two DISTINCT sensitivities were conflated when the defect was first reported,
// and only the first is a bug: (1) sample membership depending on path ORDER — fixed here; (2) ranks moving
// because the CORPUS changed — irreducible and legitimate, since more files mean more distractors. Growing
// the repo still moves these numbers, and should.
// One gold item: the symbol to be recovered, plus the two synthetic queries built from it. `key` is the
// PATH-FREE identity the population is ordered and cut by — deliberately not the path-qualified key the
// quality baselines use, because this one must be invariant under MOVING a file, which is the whole
// property test/knownitemcheck.sh's order-independence arm asserts.
struct RetrievalGoldItem
{
    std::uint64_t key = 0;
    NodeId        gold = kNoNode;
    std::string   name;
    std::string   phrase;
    std::string   scope;
};

struct RetrievalGold
{
    std::vector<RetrievalGoldItem> scored;              // what the eval will actually grade, in canonical order
    std::size_t                    population = 0;      // how many symbols QUALIFIED, whether or not they were scored
    bool                           exhaustive = true;   // scored == population: no sample, so no sampling rule
};

// THE POPULATION: every symbol carrying a usable doc-phrase, in crawl order (the caller imposes the
// canonical order — this function must not be trusted to, and does not claim to). Kept separate from the
// cut below because "who is eligible" and "which of the eligible are graded" are the two questions the old
// single fused loop answered at once, which is exactly how it managed to answer the second one by path.
inline std::vector<RetrievalGoldItem> qualifyingGoldPool( const IngestResult& ing )
{
    // Read each file's content once, cached; a symbol qualifies iff docPhraseFirstLine yields a non-empty
    // stopworded phrase (so BOTH query modes are well-defined for every scored symbol — same gold set).
    HashMap<std::uint32_t, std::string> contents;
    const auto contentOf = [ & ]( std::uint32_t fid ) -> const std::string&
    {
        const auto it = contents.find( fid );
        if( it != contents.end() )
        {
            return it->second;
        }
        std::string s;
        if( fid < ing.files.size() )
        { std::ifstream in( diskPath( ing, fid ), std::ios::binary ); if( in ) { std::ostringstream ss; ss << in.rdbuf(); s = ss.str(); } }
        return contents.emplace( fid, std::move( s ) ).first->second;
    };

    std::vector<RetrievalGoldItem> pool;
    for( NodeId id = 0; id < ing.symbols.size(); ++id )
    {
        const Symbol& s = ing.symbols[id];
        if( s.name.size() < 3 )
        {
            continue; // a 1-2 char name is a degenerate query — skip
        }
        const std::string& src = contentOf( s.fileId );
        if( src.empty() )
        {
            continue;
        }
        std::string phrase = docPhraseFirstLine( src, s.sigStartByte );
        if( phrase.empty() )
        {
            continue;
        }
        const std::uint64_t key = rw::fnv1a64( s.scope.empty() ? s.name : ( s.scope + "::" + s.name ) );
        pool.push_back( { key, id, s.name, std::move( phrase ), s.scope } );
    }
    return pool;
}

// Order the population canonically and cut it to `maxScored`. Nothing here may consult crawl order, path,
// or position — the whole contract of this function is that its output depends only on the identities in
// the population, which is what test/knownitemcheck.sh's order-independence arm holds it to.
inline RetrievalGold buildRetrievalGold( const IngestResult& ing, std::size_t maxScored )
{
    std::vector<RetrievalGoldItem> pool = qualifyingGoldPool( ing );

    RetrievalGold out;
    out.population = pool.size();
    if( pool.empty() )
    {
        return out;
    }

    // Canonical order: by the path-free key, then by the identity itself, then by the phrase. Crawl order —
    // and therefore path order — is never consulted, so both WHICH symbols are scored and the ORDER their
    // reciprocal ranks accumulate in are identical however the tree is laid out.
    std::sort( pool.begin(), pool.end(), [ ]( const RetrievalGoldItem& a, const RetrievalGoldItem& b )
    {
        if( a.key != b.key )     { return a.key < b.key; }
        if( a.scope != b.scope ) { return a.scope < b.scope; }
        if( a.name != b.name )   { return a.name < b.name; }
        return a.phrase < b.phrase;
    } );

    if( out.population <= maxScored )
    {
        out.scored = std::move( pool );
        return out;
    }

    // Cut on the KEY, never on a raw count: a whole identity is admitted or refused together, so the cut
    // cannot be decided by which of two same-named symbols the crawl happened to reach first.
    out.exhaustive = false;
    std::size_t cut = 0;
    while( cut < pool.size() && out.scored.size() < maxScored )
    {
        const std::uint64_t k = pool[cut].key;
        std::size_t         e = cut;
        while( e < pool.size() && pool[e].key == k )
        {
            ++e;
        }
        for( std::size_t i = cut; i < e; ++i )
        {
            out.scored.push_back( std::move( pool[i] ) );
        }
        cut = e;
    }
    return out;
}

inline int runEvalRetrieval( const IngestResult& ing, const Graph& g )
{
    // Chosen so this repo's own two published roots (`src/` and `.`) both run EXHAUSTIVE — the numbers we
    // publish carry no sampling rule at all. It is a safety valve for corpora far larger than ours, not a
    // budget: each scored symbol costs 8 whole-corpus rankings, so an unbounded eval is quadratic.
    constexpr std::size_t kMaxScored = 4000;

    const RetrievalGold                   goldSet    = buildRetrievalGold( ing, kMaxScored );
    const std::size_t                     population = goldSet.population;
    const bool                            exhaustive = goldSet.exhaustive;
    const std::vector<RetrievalGoldItem>& sample     = goldSet.scored;
    if( sample.empty() ) { std::fprintf( stderr, "ripwire --eval-retrieval: no doc-commented symbols to sample\n" ); return 1; }

    // Resolve the corpus text ONCE. lexicalScores re-opens every file in the tree on every call, which is
    // right for a single query and ruinous here: two calls per scored symbol over 3,497 symbols was ~11.8
    // million file opens per run, and 48% of this eval's CPU was system time. Hoisting the read out of the
    // per-query loop changes no scored value — the scan sees byte-identical text, just not via the kernel.
    const std::vector<std::string> corpusText = buildLexicalCorpusText( ing );

    // rankers: subtoken+body (--for default), name-exact, anchored (over subtoken+body), routed (chooseForRanker).
    // Two query modes: name (a), doc-phrase (b). One RetrievalAcc per (ranker, mode).
    RetrievalAcc subN, subP, exN, exP, anN, anP, rtN, rtP;
    std::size_t  routedNameExactPicks = 0;                    // how often routing chose name-exact on a NAME query

    const auto scoreAndRank = [ & ]( const std::vector<float>& sc, NodeId gold ) { return rankOfSymbol( sc, gold ); };

    for( const RetrievalGoldItem& sm : sample )
    {
        // (a) NAME query
        {
            const std::vector<float> sub = lexicalScores( ing, g.outOff, g.outTargets, sm.name, 0, nullptr, 0, {}, &corpusText );
            const std::vector<float> ex  = lexicalScoresNameExact( ing, sm.name );
            const std::vector<float> an  = anchoredLexicalRank( g, sub );
            const RouteChoice        rc  = chooseForRanker( ing, sm.name );
            const std::vector<float>& rt = ( rc.which == LexMode::NameExact ) ? ex : sub;
            if( rc.which == LexMode::NameExact )
            {
                ++routedNameExactPicks;
            }
            addRetrieval( subN, scoreAndRank( sub, sm.gold ) );
            addRetrieval( exN,  scoreAndRank( ex,  sm.gold ) );
            addRetrieval( anN,  scoreAndRank( an,  sm.gold ) );
            addRetrieval( rtN,  scoreAndRank( rt,  sm.gold ) );
        }
        // (b) DOC-PHRASE query
        {
            const std::vector<float> sub = lexicalScores( ing, g.outOff, g.outTargets, sm.phrase, 0, nullptr, 0, {}, &corpusText );
            const std::vector<float> ex  = lexicalScoresNameExact( ing, sm.phrase );
            const std::vector<float> an  = anchoredLexicalRank( g, sub );
            const RouteChoice        rc  = chooseForRanker( ing, sm.phrase );
            const std::vector<float>& rt = ( rc.which == LexMode::NameExact ) ? ex : sub;
            addRetrieval( subP, scoreAndRank( sub, sm.gold ) );
            addRetrieval( exP,  scoreAndRank( ex,  sm.gold ) );
            addRetrieval( anP,  scoreAndRank( an,  sm.gold ) );
            addRetrieval( rtP,  scoreAndRank( rt,  sm.gold ) );
        }
    }

    // ---- report: one table, ranker × query-mode, MRR + recall@1/5/10 ----
    const auto row = [ & ]( const char* ranker, const char* mode, const RetrievalAcc& a )
    {
        const double N = double( a.n ? a.n : 1 );
        std::printf( "  %-9s %-11s %6.3f %8.1f%% %8.1f%% %8.1f%%\n",
                     ranker, mode, a.mrr / N,
                     100.0 * double( a.r1 ) / N, 100.0 * double( a.r5 ) / N, 100.0 * double( a.r10 ) / N );
    };
    std::printf( "ripwire --eval-retrieval  (known-item, %zu doc-commented symbols; gold is in-corpus by construction)\n", sample.size() );
    // The sampling rule states itself. `exhaustive` means scored == population: there is no sample and no
    // rule, so nothing about the corpus's layout can reach the numbers below.
    if( exhaustive )
    {
        std::printf( "  sample: population=%zu scored=%zu rule=exhaustive (every qualifying symbol; path- and order-independent)\n",
                     population, sample.size() );
    }
    else
    {
        std::printf( "  sample: population=%zu scored=%zu rule=smallest-key CAPPED — a SUBSET, not the population\n"
                     "          (smallest fnv1a64(scope::name) over the population, cut on the key so an identity is never split;\n"
                     "           path- and order-independent, but a corpus this size is NOT graded exhaustively — say so when citing it)\n",
                     population, sample.size() );
    }
    std::printf( "  %-9s %-11s %6s %9s %9s %9s\n", "ranker", "query-mode", "MRR", "recall@1", "recall@5", "recall@10" );
    row( "subtoken", "name",      subN );
    row( "subtoken", "doc-phrase",subP );
    row( "name-exact","name",     exN );
    row( "name-exact","doc-phrase",exP );
    row( "anchored", "name",      anN );
    row( "anchored", "doc-phrase",anP );
    row( "routed",   "name",      rtN );
    row( "routed",   "doc-phrase",rtP );
    std::printf( "  note: routing chose name-exact on %zu/%zu NAME queries (a NAME query is always identifier-shaped);\n"
                 "        the confidence gate routes doc-phrase queries to name-exact ONLY when EVERY content word names a symbol\n"
                 "        (or an explicit camel/snake token appears) AND every matched name is specific enough to anchor on —\n"
                 "        a common name (many definitions, or a subtoken carried by many symbol names) declines the route — so\n"
                 "        conceptual prose falls back to subtoken+body; routed tracks the better ranker on BOTH modes\n"
                 "        (routed==name-exact on name, ~=subtoken+body on doc-phrase).\n",
                 routedNameExactPicks, sample.size() );
    return 0;
}

// ── SESSION-TRACE-MINED RETRIEVAL EVAL (--eval-mined) ─────────────────────────────────────────────────
// Consumes a `minedpair.jsonl` artifact (bench/mine_traces.py) — one mined
// (query, gold_files) pair per line, mined from THIS developer's own local Claude Code session
// transcripts. File-granularity sibling of the two evals above: gold is a SET of files (§2.2: no seed
// file — the query text is the probe, same posture as --eval-retrieval, not --eval's seed-based one).
// Arms mirror bench/locbench's for/query/anchor (no metric invented): `for`/`query` both use the
// confidence-gated routed lexical score (chooseForRanker → lexicalScoresNameExact | lexicalScores) —
// they coincide today because --for and --query share that exact default computation absent --anchor
// (main.cpp:721-746 / :3059-3082); `anchor` runs anchoredLexicalRank over that same base (--for --anchor,
// EXPERIMENTAL). Symbol scores are max-pooled to file scores (mirrors bench/locbench's file-level
// convention and eval.h's own anchoredFileScore). recall@k REUSES recallAtK/rankFiles verbatim — zero
// drift risk, proven by Gate #3 (metric-parity). Acc@k (ALL gold within top-k, bench/locbench's strict
// definition) and MRR (reciprocal rank of the FIRST gold hit) are new, but score-vector-agnostic — no
// separate ranking math. `random` is the analytic k/F floor, same shape as --eval's random row (no seed
// excluded here). assisted/unassisted (§3.2 ripwire_assisted tag) print as two SEPARATE tables, never
// blended — the unassisted population is the only one that isn't grading ripwire's own homework.

struct MinedPair
{
    std::string              query;
    std::vector<std::string> goldPaths;
    bool                     assisted = false;
};

// ---- a deliberately NARROW JSON-line reader for exactly bench/mine_traces.py's minedpair schema (not
//      a general parser: no arbitrary nesting, no numeric-array support) — the producer is our own
//      miner, so the shape is fixed by us. Degrades a malformed/foreign line to `false` (the caller
//      skips it), never throws: a hand-edited or truncated fixture line just drops out of the sample.
namespace minedjson
{
    // index just past the closing (unescaped) quote of the JSON string starting at s[pos]=='"'
    //
    // W2-M0: the escape-aware walk is rw::jsonStringEnd (jsonesc.h), shared with mcpdetail::stringEnd —
    // these were the repo's last two copies of it. The two RETURN CONVENTIONS are deliberately not unified:
    // this one clamps a truncated line to size() so the narrow fixture reader above just runs out of input,
    // where the MCP side needs npos to detect truncation. Same walk, two documented adaptations.
    inline std::size_t skipString( const std::string& s, std::size_t pos )
    {
        if( pos >= s.size() || s[pos] != '"' )
        {
            return pos;
        }
        const std::size_t close = rw::jsonStringEnd( s, pos );
        return ( close != std::string::npos ) ? close + 1 : s.size();
    }

    // decode a JSON string literal s[pos..end) (pos at the opening quote, end just past the closing one)
    // into plain UTF-8 text — the standard escapes plus \uXXXX (incl. surrogate pairs).
    inline std::string unescape( const std::string& s, std::size_t pos, std::size_t end )
    {
        std::string out;
        if( end == std::string::npos || end <= pos + 1 || end > s.size() )
        {
            return out;
        }
        for( std::size_t i = pos + 1; i + 1 < end; ++i )
        {
            if( s[i] != '\\' ) { out += s[i]; continue; }
            if( i + 1 >= end )
            {
                break;
            }
            const char e = s[ ++i ];
            switch( e )
            {
                case '"':  out += '"';  break;
                case '\\': out += '\\'; break;
                case '/':  out += '/';  break;
                case 'n':  out += '\n'; break;
                case 't':  out += '\t'; break;
                case 'r':  out += '\r'; break;
                case 'b':  out += '\b'; break;
                case 'f':  out += '\f'; break;
                case 'u':
                {
                    if( i + 4 >= end )
                    {
                        break;
                    }
                    const auto hex4 = [ & ]( std::size_t at ) -> unsigned
                    {
                        unsigned v = 0;
                        for( int k = 0; k < 4; ++k )
                        {
                            const char h = s[ at + k ];
                            v <<= 4;
                            if( h >= '0' && h <= '9' )
                            {
                                v |= unsigned( h - '0' );
                            }
                            else if( h >= 'a' && h <= 'f' )
                            {
                                v |= unsigned( h - 'a' + 10 );
                            }
                            else if( h >= 'A' && h <= 'F' )
                            {
                                v |= unsigned( h - 'A' + 10 );
                            }
                        }
                        return v;
                    };
                    unsigned cp = hex4( i + 1 );
                    i += 4;
                    if( cp >= 0xD800 && cp <= 0xDBFF && i + 6 < end && s[ i + 1 ] == '\\' && s[ i + 2 ] == 'u' )
                    {
                        const unsigned lo = hex4( i + 3 );
                        if( lo >= 0xDC00 && lo <= 0xDFFF ) { cp = 0x10000u + ( ( cp - 0xD800u ) << 10 ) + ( lo - 0xDC00u ); i += 6; }
                    }
                    if( cp < 0x80 )
                    {
                        out += char( cp );
                    }
                    else if( cp < 0x800 )
                    {
                        out += char( 0xC0 | ( cp >> 6 ) );
                        out += char( 0x80 | ( cp & 0x3F ) );
                    }
                    else if( cp < 0x10000 ){ out += char( 0xE0 | ( cp >> 12 ) ); out += char( 0x80 | ( ( cp >> 6 ) & 0x3F ) ); out += char( 0x80 | ( cp & 0x3F ) ); }
                    else                   { out += char( 0xF0 | ( cp >> 18 ) ); out += char( 0x80 | ( ( cp >> 12 ) & 0x3F ) ); out += char( 0x80 | ( ( cp >> 6 ) & 0x3F ) ); out += char( 0x80 | ( cp & 0x3F ) ); }
                    break;
                }
                default: out += e; break;
            }
        }
        return out;
    }

    // find `"key"`, then the JSON STRING value after its colon; returns the [start,end) quote span.
    inline bool findStringValue( const std::string& s, const char* key, std::size_t from, std::size_t& vs, std::size_t& ve )
    {
        const std::string needle = std::string( "\"" ) + key + "\"";
        const std::size_t k = s.find( needle, from );
        if( k == std::string::npos )
        {
            return false;
        }
        const std::size_t c = s.find( ':', k + needle.size() );
        if( c == std::string::npos )
        {
            return false;
        }
        std::size_t q = c + 1;
        while( q < s.size() && ( s[q] == ' ' || s[q] == '\t' ) )
        {
            ++q;
        }
        if( q >= s.size() || s[q] != '"' )
        {
            return false;
        }
        vs = q; ve = skipString( s, q );
        return true;
    }

    inline bool findBool( const std::string& s, const char* key, std::size_t from, bool& val )
    {
        const std::string needle = std::string( "\"" ) + key + "\"";
        const std::size_t k = s.find( needle, from );
        if( k == std::string::npos )
        {
            return false;
        }
        const std::size_t c = s.find( ':', k + needle.size() );
        if( c == std::string::npos )
        {
            return false;
        }
        std::size_t q = c + 1;
        while( q < s.size() && ( s[q] == ' ' || s[q] == '\t' ) )
        {
            ++q;
        }
        if( s.compare( q, 4, "true" ) == 0 )  { val = true;  return true; }
        if( s.compare( q, 5, "false" ) == 0 ) { val = false; return true; }
        return false;
    }
}   // namespace minedjson

// parse one minedpair.jsonl line. Returns false (degrade — caller skips the line) on any malformed or
// under-qualifying record: no query, no gold_files, or the query/gold_files keys are absent entirely.
inline bool parseMinedLine( const std::string& line, MinedPair& out )
{
    out = MinedPair{};
    std::size_t qs, qe;
    if( !minedjson::findStringValue( line, "query", 0, qs, qe ) )
    {
        return false;
    }
    out.query = minedjson::unescape( line, qs, qe );

    bool assisted = false;
    minedjson::findBool( line, "ripwire_assisted", 0, assisted );   // absent → false (degrade)
    out.assisted = assisted;

    const std::size_t gf = line.find( "\"gold_files\"" );
    if( gf == std::string::npos )
    {
        return false;
    }
    const std::size_t arrEnd = line.find( ']', gf );
    std::size_t pos = gf;
    for( ;; )
    {
        std::size_t ps, pe;
        if( !minedjson::findStringValue( line, "path", pos, ps, pe ) )
        {
            break;
        }
        if( arrEnd != std::string::npos && ps > arrEnd )
        {
            break; // past the gold_files array close
        }
        out.goldPaths.push_back( minedjson::unescape( line, ps, pe ) );
        pos = pe;
    }
    return !out.query.empty() && !out.goldPaths.empty();
}

// max-pool a per-SYMBOL score vector to per-FILE (a file's score = its best symbol's score; files with
// no symbols keep the 0 baseline — every lexical score here is BM25-non-negative). Mirrors
// anchoredFileScore's pooling above and bench/locbench's file-level convention (§5.3).
inline std::vector<float> maxPoolToFiles( const IngestResult& ing, const std::vector<float>& symScore, std::uint32_t F )
{
    std::vector<float> fileScore( F, 0.f );
    for( const Symbol& s : ing.symbols )
    {
        if( s.id < symScore.size() && symScore[s.id] > fileScore[s.fileId] )
        {
            fileScore[s.fileId] = symScore[s.id];
        }
    }
    return fileScore;
}

// strict Acc@k (bench/locbench's definition): ALL gold files land within the top-k, not just some.
inline bool allGoldWithinK( const std::vector<std::uint32_t>& ranked, const std::vector<char>& gold, std::size_t goldTotal, std::size_t k )
{
    if( goldTotal == 0 )
    {
        return false;
    }
    std::size_t hit = 0;
    for( std::size_t i = 0; i < ranked.size() && i < k; ++i )
    {
        if( gold[ranked[i]] )
        {
            ++hit;
        }
    }
    return hit == goldTotal;
}

// 1-based rank of the FIRST gold file to appear in `ranked` (reciprocal of this = the pair's MRR
// contribution — standard "first relevant hit" MRR for a multi-relevant gold set).
inline std::size_t firstGoldRank( const std::vector<std::uint32_t>& ranked, const std::vector<char>& gold )
{
    for( std::size_t i = 0; i < ranked.size(); ++i )
    {
        if( gold[ranked[i]] )
        {
            return i + 1;
        }
    }
    return ranked.size() + 1;
}

struct MinedAcc
{
    EvalAcc     recall;
    double      acc5 = 0, acc10 = 0, acc20 = 0;
    double      mrr  = 0;
    std::size_t n    = 0;
};
inline void addMinedRow( MinedAcc& a, const std::vector<std::uint32_t>& ranked, const std::vector<char>& gold, std::size_t goldTotal )
{
    addRecall( a.recall, ranked, gold, goldTotal );
    if( allGoldWithinK( ranked, gold, goldTotal, 5 ) )
    {
        a.acc5 += 1;
    }
    if( allGoldWithinK( ranked, gold, goldTotal, 10 ) )
    {
        a.acc10 += 1;
    }
    if( allGoldWithinK( ranked, gold, goldTotal, 20 ) )
    {
        a.acc20 += 1;
    }
    a.mrr += 1.0 / double( firstGoldRank( ranked, gold ) );
    ++a.n;
}

inline int runEvalMined( const std::string& root, const IngestResult& ing, const Graph& g, const std::string& path )
{
    std::ifstream in( path );
    if( !in ) { std::fprintf( stderr, "ripwire --eval-mined: cannot open '%s'\n", path.c_str() ); return 1; }

    // gold paths in the artifact are REPO-RELATIVE (the miner strips the repo root); ing.files carry
    // the as-invoked crawl paths (absolute or CWD-relative). Index BOTH forms so `ripwire /abs/repo
    // --eval-mined=…` and `ripwire relative/root --eval-mined=…` resolve the same gold set. Exact
    // string keys only — no fuzzy suffix matching (a basename collision must not silently mis-credit
    // a ranker).
    const std::uint32_t F = std::uint32_t( ing.files.size() );
    // Same hoist as --eval-retrieval: lexicalScores re-opens every file in the tree on every call, so a loop
    // over mined pairs re-read the whole corpus per pair (METHODOLOGY §3 — the sibling instances of a defect
    // are the defect). Byte-identical scores; the scan just stops going via the kernel.
    const std::vector<std::string> corpusText = buildLexicalCorpusText( ing );
    HashMap<std::string, std::uint32_t> pathToFile;               // gold-path → fileId (as-crawled + root-relative)
    const std::string rootPrefix = root.empty() ? std::string() : ( root.back() == '/' ? root : root + "/" );
    for( std::uint32_t f = 0; f < F; ++f )
    {
        pathToFile[ ing.files[f] ] = f;
        if( !rootPrefix.empty() && ing.files[f].size() > rootPrefix.size() && ing.files[f].compare( 0, rootPrefix.size(), rootPrefix ) == 0 )
        {
            pathToFile[ ing.files[f].substr( rootPrefix.size() ) ] = f;
        }
    }

    MinedAcc    forA[2], queryA[2], anchorA[2];                    // [0]=unassisted, [1]=assisted (§3.2)
    std::size_t nPairs[2] = { 0, 0 };
    std::size_t skipped = 0, underqualified = 0;
    std::string line;
    while( std::getline( in, line ) )
    {
        if( line.empty() )
        {
            continue;
        }
        MinedPair p;
        if( !parseMinedLine( line, p ) ) { ++skipped; continue; }

        std::vector<char> gold( F, 0 );
        std::size_t        goldTotal = 0;
        for( const std::string& gp : p.goldPaths )
        {
            const auto it = pathToFile.find( gp );
            if( it != pathToFile.end() && !gold[ it->second ] ) { gold[ it->second ] = 1; ++goldTotal; }
        }
        if( goldTotal < 2 ) { ++underqualified; continue; }        // §2.2 floor (mirrors runEval's cs.size()>=2)

        const int idx = p.assisted ? 1 : 0;

        // `for` == `query`: both are today's exact --for/--query default (routed lexical, no --anchor) —
        // see the block comment above. Computed once, scored into both rows (never a drifted second impl).
        const RouteChoice        rc   = chooseForRanker( ing, p.query );
        const std::vector<float> base = ( rc.which == LexMode::NameExact ) ? lexicalScoresNameExact( ing, p.query )
                                                                            : lexicalScores( ing, g.outOff, g.outTargets, p.query, 0, nullptr, 0, {}, &corpusText );
        const std::vector<float> forFileScore = maxPoolToFiles( ing, base, F );
        addMinedRow( forA[idx],   rankFiles( forFileScore ), gold, goldTotal );
        addMinedRow( queryA[idx], rankFiles( forFileScore ), gold, goldTotal );

        const std::vector<float> anchorSym       = anchoredLexicalRank( g, base );
        const std::vector<float> anchorFileScore = maxPoolToFiles( ing, anchorSym, F );
        addMinedRow( anchorA[idx], rankFiles( anchorFileScore ), gold, goldTotal );

        ++nPairs[idx];
    }
    if( nPairs[0] + nPairs[1] == 0 )
    {
        std::fprintf( stderr, "ripwire --eval-mined: no qualifying pairs (>=2 in-corpus gold files) in '%s' "
                              "(%zu malformed, %zu under-qualified)\n", path.c_str(), skipped, underqualified );
        return 1;
    }

    const auto printTable = [ & ]( const char* label, MinedAcc& fA, MinedAcc& qA, MinedAcc& aA, std::size_t n )
    {
        std::printf( "ripwire --eval-mined  (%s, %zu session-mined pair%s; gold = files the session Edited/Wrote)\n",
                     label, n, n == 1 ? "" : "s" );
        if( n == 0 ) { std::printf( "  (no %s pairs)\n", label ); return; }
        const double N = double( n );
        std::printf( "  %-8s %8s %9s %9s   %7s %8s %8s   %6s\n",
                     "arm", "recall@5", "recall@10", "recall@20", "acc@5", "acc@10", "acc@20", "mrr" );
        const auto row = [ & ]( const char* name, const MinedAcc& a )
        {
            std::printf( "  %-8s %7.1f%% %8.1f%% %8.1f%%   %6.1f%% %7.1f%% %7.1f%%   %6.3f\n", name,
                         100.0 * a.recall.r5 / N, 100.0 * a.recall.r10 / N, 100.0 * a.recall.r20 / N,
                         100.0 * a.acc5 / N, 100.0 * a.acc10 / N, 100.0 * a.acc20 / N, a.mrr / N );
        };
        row( "for",    fA );
        row( "query",  qA );
        row( "anchor", aA );
        std::printf( "  %-8s %7.1f%% %8.1f%% %8.1f%%   <- floor (random ranking over F=%u files; this eval's gold is a file SET with no seed file, so nothing is excluded from the draw)\n",
                     "random",
                     F > 0 ? 100.0 * std::min<double>( 5.0,  F ) / double( F ) : 0.0,
                     F > 0 ? 100.0 * std::min<double>( 10.0, F ) / double( F ) : 0.0,
                     F > 0 ? 100.0 * std::min<double>( 20.0, F ) / double( F ) : 0.0, F );
    };

    printTable( "unassisted", forA[0], queryA[0], anchorA[0], nPairs[0] );
    printTable( "assisted (ripwire_assisted=true — the session had already seen ripwire's own output; NOT independent evidence)",
               forA[1], queryA[1], anchorA[1], nPairs[1] );
    if( skipped || underqualified )
    {
        std::fprintf( stderr, "ripwire --eval-mined: skipped %zu malformed line(s), %zu under-qualified pair(s) (<2 in-corpus gold files)\n",
                     skipped, underqualified );
    }
    return 0;
}

}   // namespace rw
