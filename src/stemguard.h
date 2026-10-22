// stemguard.h — guarded stem scoring for the word ranker. Pure: no IngestResult, no Bm25Params, so a unit test
// includes it alone (test/verify_stemguard.cpp). lexical.h and recall.h are the callers.
//
// THE RULE. A stem-only match never outscores an exact match, for any stemmer, any theta below 1 and any length.
//
// Per query word u and symbol i, with idf over the symbols that hold u as typed or as a stem:
//   exact_iu = idf_u * sat( tfExact_iu, L_i )
//   floor_u  = min of exact_iu over symbols with tfExact_iu > 0, or idf_u when none has one
//   stem_iu  = theta * floor_u * stemOnly_iu / max_i( stemOnly_iu )
//   word_iu  = exact_iu + stem_iu
// A symbol without the typed word scores stem_iu <= theta * floor_u < floor_u, and every symbol with the typed word
// scores at least floor_u. For two or more words a per-word guard is not enough, so the query adds a tier:
//   final_i  = k_i * ( P + 1 ) + S_i
// k_i is the number of kept query words symbol i holds as typed, S_i the summed word scores, and P an upper bound on
// every S_i. Each typed word is worth more than any S_i can add, so more typed words always rank first.
//
// Measured in bench/stemabc (Gq, raw signal, max normalizer, theta 0.5). docs/ARCHITECTURE.md has the account.
#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

#ifndef RIPWIRE_STEMGUARD_THETA
#define RIPWIRE_STEMGUARD_THETA 0.5   // the can-go-red arm of test/stemguardcheck.sh builds with 1.0
#endif

namespace rw
{

inline constexpr double kLexStemTheta = RIPWIRE_STEMGUARD_THETA;

struct StemGuardTable
{
    std::size_t         docCount  = 0;
    std::size_t         termCount = 0;
    std::vector<int>    stemOnly;   // docCount x termCount, tfStemAll - tfExact, clamped at 0
    std::vector<int>    stemMax;    // per term, the largest stemOnly
    std::vector<int>    df;         // per term, symbols holding it as typed or as a stem
    std::vector<double> idf;        // per term
    std::vector<double> floorE;     // per term, the weakest exact word score
    std::vector<double> cap;        // per term, an upper bound on word_iu for every symbol
};

// The BM25 length factor and saturation, the same expressions both scoring branches use.
inline double stemGuardLength( double k1, double b, int dl, double avgdl ) noexcept
{
    return 1.0 - b + b * dl / ( avgdl > 0 ? avgdl : 1.0 );
}

inline double stemGuardExact( double idf, double k1, double L, int tf ) noexcept
{
    return tf > 0 ? idf * ( double( tf ) * ( k1 + 1.0 ) ) / ( double( tf ) + k1 * L ) : 0.0;
}

// One pass over the rows for df, stemOnly and the maxima, a second for the exact floor.
inline StemGuardTable buildStemGuard( std::size_t docCount, std::size_t termCount, const int* tfExact, const int* tfStemAll,
                                      const int* dl, double avgdl, double k1, double b )
{
    StemGuardTable t;
    t.docCount  = docCount;
    t.termCount = termCount;
    if( docCount == 0 || termCount == 0 )
    {
        return t;
    }
    t.stemOnly.assign( docCount * termCount, 0 );
    t.stemMax.assign( termCount, 0 );
    t.df.assign( termCount, 0 );
    t.idf.assign( termCount, 0.0 );
    t.floorE.assign( termCount, 0.0 );
    t.cap.assign( termCount, 0.0 );
    std::vector<int> maxExact( termCount, 0 );
    for( std::size_t i = 0; i < docCount; ++i )
    {
        for( std::size_t u = 0; u < termCount; ++u )
        {
            const std::size_t at   = i * termCount + u;
            const int         only = std::max( 0, tfStemAll[ at ] - tfExact[ at ] );
            t.stemOnly[ at ]       = only;
            t.stemMax[ u ]         = std::max( t.stemMax[ u ], only );
            maxExact[ u ]          = std::max( maxExact[ u ], tfExact[ at ] );
            t.df[ u ] += ( tfExact[ at ] > 0 || only > 0 ) ? 1 : 0;
        }
    }
    for( std::size_t u = 0; u < termCount; ++u )
    {
        t.idf[ u ] = std::log( ( double( docCount ) - t.df[ u ] + 0.5 ) / ( t.df[ u ] + 0.5 ) + 1.0 );
        bool   any   = false;
        double floorE = 0.0;
        for( std::size_t i = 0; i < docCount; ++i )
        {
            const int tf = tfExact[ i * termCount + u ];
            if( tf > 0 )
            {
                const double e = stemGuardExact( t.idf[ u ], k1, stemGuardLength( k1, b, dl[ i ], avgdl ), tf );
                floorE         = any ? std::min( floorE, e ) : e;
                any            = true;
            }
        }
        t.floorE[ u ] = any ? floorE : t.idf[ u ];
        // The impact bound: tf <= T and dl >= 0 give exact <= idf * T(k1+1) / (T + k1(1-b)). The slack covers rounding.
        const double T = double( maxExact[ u ] );
        const double exactBound = T > 0 ? t.idf[ u ] * ( T * ( k1 + 1.0 ) ) / ( T + k1 * ( 1.0 - b ) ) * ( 1.0 + 1e-9 ) : 0.0;
        const double stemBound  = t.stemMax[ u ] > 0 ? kLexStemTheta * t.floorE[ u ] * ( 1.0 + 1e-9 ) : 0.0;
        t.cap[ u ]              = exactBound + stemBound;
    }
    return t;
}

// word_iu for one symbol and one term.
inline double stemGuardWord( const StemGuardTable& t, const int* tfExact, const int* dl, double avgdl, double k1, double b,
                             std::size_t doc, std::size_t term ) noexcept
{
    const std::size_t at = doc * t.termCount + term;
    const double      ex = stemGuardExact( t.idf[ term ], k1, stemGuardLength( k1, b, dl[ doc ], avgdl ), tfExact[ at ] );
    const double stem = t.stemOnly[ at ] > 0 ? kLexStemTheta * t.floorE[ term ] * double( t.stemOnly[ at ] ) / double( t.stemMax[ term ] ) : 0.0;
    return ex + stem;
}

// True when the symbol holds the term as typed or as a stem.
inline bool stemGuardMatches( const StemGuardTable& t, const int* tfExact, std::size_t doc, std::size_t term ) noexcept
{
    const std::size_t at = doc * t.termCount + term;
    return tfExact[ at ] > 0 || t.stemOnly[ at ] > 0;
}

// final = k * (P + 1) + S, and zero when nothing matched, so an unmatched symbol never enters a tier.
inline double stemGuardTier( double peakBound, int exactWords, double s ) noexcept
{
    return s > 0.0 ? double( exactWords ) * ( peakBound + 1.0 ) + s : 0.0;
}

}   // namespace rw
