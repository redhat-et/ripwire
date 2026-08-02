#pragma once

// clones.h — token-normalized duplicate detection (--clones), function/method level. The CCFinder/PMD-CPD
// idea: normalize each body to a token stream (identifiers → $I, literals →
// $N/$S, keywords + operators + punctuation kept), then group functions with identical normalized streams.
// Catches Type-1 (exact) and Type-2 (renamed-variable) clones. Agent value: "this already exists — reuse
// it, don't reimplement" (and "if you fix this, fix its twins"). Type-3 (gapped) clones are a later upgrade.

#include "model.h"
#include "Diagnostics.h"   // DEGRADED_PATH_ALERT — graceful-degrade on the Type-3 pair-cap guard (never throw)
#include "hashutil.h"      // sanitizer-clean modulo-2^64 FNV multiplication

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

namespace rw
{

// union of control-flow / declaration keywords across our 7 languages — kept verbatim (not normalised to
// $I) so two bodies with different control flow don't collide. Completeness isn't critical: a missed
// keyword just becomes $I (slightly more permissive matching).
inline bool cloneIsKeyword( std::string_view w ) noexcept
{
    // O(1) membership (A4-P3): a function-local static hash set, built once on first use (guaranteed-safe
    // C++ static init), replaces the old ~150-wide linear std::find that ran per identifier token, millions
    // of times per pass. Determinism is trivially preserved: this is a pure membership test, order-free.
    static const HashMap<std::string_view, std::uint8_t> kw = []
    {
        HashMap<std::string_view, std::uint8_t> m;
        for( std::string_view k : {
            "if","else","for","while","do","switch","case","default","break","continue","return","goto",
            "struct","class","enum","union","namespace","template","typename","typedef","using","public","private","protected","virtual","override","final",
            "const","constexpr","consteval","static","inline","extern","volatile","mutable","auto","void","int","float","double","char","bool","long","short","unsigned","signed",
            "new","delete","this","nullptr","true","false","sizeof","operator","friend","explicit","try","catch","throw",
            "def","elif","except","finally","lambda","pass","raise","with","yield","import","from","as","global","nonlocal","in","is","not","and","or","None","True","False","self",
            "func","var","let","mutating","protocol","extension","guard","defer","where","repeat","fallthrough","init","deinit","fn","impl","trait","mod","pub","use","match","loop","move","ref","dyn","async","await",
            "package","interface","map","chan","go","select","type","range","function","typeof","instanceof","export" } )
            m.emplace( k, std::uint8_t( 1 ) );
        return m;
    }();
    return kw.find( w ) != kw.end();
}

// Bounded char-literal probe: at src[i]=='\'', return the FULL token length (incl. both quotes, ≥3) iff a
// plausible close exists within a short lookahead — 'x', '\n', '\\', '\0', '\xNN', '\123'; else 0, meaning the
// caller must treat ' as ordinary punctuation. This is the A4-F2 fix: an unpaired ' (Rust lifetime `'a`, an
// apostrophe that survived into a token stream) no longer scans to the next quote and swallows the whole body.
inline std::size_t cloneCharLiteralLen( const std::string& src, std::size_t i, std::size_t n ) noexcept
{
    // caller guarantees src[i] == '\''
    std::size_t j = i + 1;
    if( j >= n ) return 0;
    if( src[j] == '\\' )
    {
        j += 2;                                          // backslash + at least one escaped byte ('\n', '\\', '\'')
        const std::size_t cap = i + 8;                   // bound the scan so '\xFFFF'-shaped input stays a constant
        while( j < n && j < cap && src[j] != '\'' ) ++j; // consume multi-byte escapes ('\xNN', '\123')
    }
    else j += 1;                                         // exactly one content byte ('x')
    return ( j < n && src[j] == '\'' ) ? ( j - i + 1 ) : 0;
}

// normalize bytes [a,b) → a token stream; identifiers→$I, numbers→$N, strings/chars→$S, // and /* */
// comments dropped, keywords/operators/punctuation kept. tokenCount returns the number of tokens emitted.
// stripHashComments: when the body's language uses `#` for line comments (Python/shell/Ruby), drop `#`-to-EOL
// too (A4-F2 — otherwise an apostrophe in a `# don't …` comment opened a bogus char literal). Strings/chars are
// consumed by the branches above `#`, so a `#` inside a literal is never mistaken for a comment.
inline std::string normalizeSpan( const std::string& src, std::uint32_t a, std::uint32_t b, std::uint32_t& tokenCount,
                                  bool stripHashComments = false )
{
    std::string out;
    tokenCount = 0;
    std::size_t i = a, n = std::min<std::size_t>( b, src.size() );
    const auto idc = []( unsigned char c ) { return std::isalnum( c ) || c == '_'; };
    while( i < n )
    {
        const unsigned char c = static_cast<unsigned char>( src[i] );   // explicit: a raw char >=0x80 implicitly converting is the UBSan sign-change class (CI round 4 artifact)
        if( std::isspace( c ) )                              { ++i; continue; }
        if( c == '/' && i + 1 < n && src[i + 1] == '/' )     { i += 2; while( i < n && src[i] != '\n' ) ++i; continue; }
        if( c == '/' && i + 1 < n && src[i + 1] == '*' )     { i += 2; while( i + 1 < n && !( src[i] == '*' && src[i + 1] == '/' ) ) ++i; i = std::min( n, i + 2 ); continue; }
        if( stripHashComments && c == '#' )                  { i += 1; while( i < n && src[i] != '\n' ) ++i; continue; }
        if( c == '"' )                                       { ++i; while( i < n && src[i] != '"' ) { if( src[i] == '\\' ) ++i; ++i; } ++i; out += "$S "; ++tokenCount; continue; }
        // ' opens a char literal only with a plausible close (bounded lookahead) AND not directly after an
        // identifier/digit byte — else it's punctuation (Rust lifetime `'a`, a stray apostrophe). Digit
        // separators (1'000'000) are absorbed by the number branch below, never reaching here.
        if( c == '\'' )
        {
            const bool afterWord = ( i > a && idc( (unsigned char)src[i - 1] ) );
            const std::size_t lit = afterWord ? 0 : cloneCharLiteralLen( src, i, n );
            if( lit ) { i += lit; out += "$S "; ++tokenCount; continue; }
            out += '\'';  out += ' ';  ++i;  ++tokenCount;  continue;   // punctuation
        }
        if( std::isdigit( c ) )                              { while( i < n && ( idc( (unsigned char)src[i] ) || src[i] == '.' || ( src[i] == '\'' && i + 1 < n && idc( (unsigned char)src[i + 1] ) ) ) ) ++i; out += "$N "; ++tokenCount; continue; }
        if( std::isalpha( c ) || c == '_' )
        {
            const std::size_t s = i;
            while( i < n && idc( (unsigned char)src[i] ) ) ++i;
            const std::string_view w( src.data() + s, i - s );
            if( cloneIsKeyword( w ) ) { out += w; out += ' '; } else out += "$I ";
            ++tokenCount;
            continue;
        }
        out += char( c );  out += ' ';  ++i;  ++tokenCount;   // operator / punctuation
    }
    return out;
}

// type: 2 = exact normalized-stream match (Type-1/2, similarity==1); 3 = near-miss (Type-3, similarity in
// [kType3MinSimilarity,1)). Defaults keep every existing consumer (main.cpp --clones emit, quality.h duplication
// delta) byte-identical: they read only .members/.tokens, and findClones() still returns ONLY type==2 groups.
// normalize bytes [a,b) → a VECTOR of normalized tokens (same normalization as normalizeSpan: identifiers→$I,
// numbers→$N, strings→$S, comments dropped, keywords/operators/punctuation verbatim). The Type-3 pass needs the
// token SEQUENCE (for LCS / k-gram fingerprints), not the joined string. tokenCount == out.size() by construction.
inline std::vector<std::string> normalizeTokens( const std::string& src, std::uint32_t a, std::uint32_t b,
                                                 bool stripHashComments = false )
{
    std::vector<std::string> out;
    std::size_t i = a, n = std::min<std::size_t>( b, src.size() );
    const auto  idc = []( unsigned char c ) { return std::isalnum( c ) || c == '_'; };
    while( i < n )
    {
        const unsigned char c = static_cast<unsigned char>( src[i] );   // explicit: a raw char >=0x80 implicitly converting is the UBSan sign-change class (CI round 4 artifact)
        if( std::isspace( c ) )                              { ++i; continue; }
        if( c == '/' && i + 1 < n && src[i + 1] == '/' )     { i += 2; while( i < n && src[i] != '\n' ) ++i; continue; }
        if( c == '/' && i + 1 < n && src[i + 1] == '*' )     { i += 2; while( i + 1 < n && !( src[i] == '*' && src[i + 1] == '/' ) ) ++i; i = std::min( n, i + 2 ); continue; }
        if( stripHashComments && c == '#' )                  { i += 1; while( i < n && src[i] != '\n' ) ++i; continue; }
        if( c == '"' )                                       { ++i; while( i < n && src[i] != '"' ) { if( src[i] == '\\' ) ++i; ++i; } ++i; out.emplace_back( "$S" ); continue; }
        // ' → char literal only with a plausible close and not right after an identifier/digit byte (A4-F2).
        if( c == '\'' )
        {
            const bool afterWord = ( i > a && idc( (unsigned char)src[i - 1] ) );
            const std::size_t lit = afterWord ? 0 : cloneCharLiteralLen( src, i, n );
            if( lit ) { i += lit; out.emplace_back( "$S" ); continue; }
            out.emplace_back( 1, '\'' );  ++i;  continue;   // punctuation
        }
        if( std::isdigit( c ) )                              { while( i < n && ( idc( (unsigned char)src[i] ) || src[i] == '.' || ( src[i] == '\'' && i + 1 < n && idc( (unsigned char)src[i + 1] ) ) ) ) ++i; out.emplace_back( "$N" ); continue; }
        if( std::isalpha( c ) || c == '_' )
        {
            const std::size_t s = i;
            while( i < n && idc( (unsigned char)src[i] ) ) ++i;
            const std::string_view w( src.data() + s, i - s );
            if( cloneIsKeyword( w ) ) out.emplace_back( w ); else out.emplace_back( "$I" );
            continue;
        }
        out.emplace_back( 1, char( c ) );  ++i;   // operator / punctuation
    }
    return out;
}

struct CloneGroup
{
    std::vector<NodeId> members;
    std::uint32_t       tokens;
    std::uint8_t        type       = 2;      // 2 = exact (Type-1/2), 3 = gapped near-miss (Type-3)
    float               similarity = 1.0f;   // 1.0 for exact; LCS-ratio in [kType3MinSimilarity,1) for Type-3
};

// Find function/method bodies with identical normalized token streams (≥ minTokens, ≥2 members).
inline std::vector<CloneGroup> findClones( const IngestResult& ing, int minTokens )
{
    // Require a real body (a [sigEndByte,endByte) region exists): excludes prototypes AND the
    // most-vexing-parse phantoms — block-scope `Type name(args);` variable decls the grammar shapes like a
    // function declarator (they have no body, so sigEndByte==endByte). We compare the BODY, so
    // same-implementation / different-name still matches.
    std::vector<std::vector<NodeId>> byFile( ing.files.size() );
    for( const Symbol& s : ing.symbols )
        if( ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && s.fileId < byFile.size()
            && s.endByte > s.sigEndByte )
            byFile[ s.fileId ].push_back( s.id );

    HashMap<std::string, std::vector<NodeId>> groups;   // normalized body → member symbol ids
    HashMap<NodeId, std::uint32_t>            tok;       // symbol → token count (for ranking)
    std::string bytes;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( byFile[f].empty() ) continue;
        std::FILE* fp = std::fopen( diskPath( ing, std::uint32_t( f ) ).c_str(), "rb" );
        if( !fp ) continue;
        std::fseek( fp, 0, SEEK_END );
        const long sz = std::ftell( fp );
        std::fseek( fp, 0, SEEK_SET );
        bytes.clear();
        if( sz > 0 ) { bytes.resize( std::size_t( sz ) ); if( std::fread( bytes.data(), 1, std::size_t( sz ), fp ) != std::size_t( sz ) ) bytes.clear(); }
        std::fclose( fp );
        if( bytes.empty() ) continue;

        for( NodeId id : byFile[f] )
        {
            const Symbol& s = ing.symbols[id];
            std::uint32_t tc = 0;
            const bool    hash = ( s.lang == Lang::Python || s.lang == Lang::Bash || s.lang == Lang::Ruby );   // `#` line comments
            std::string   norm = normalizeSpan( bytes, s.sigEndByte, s.endByte, tc, hash );   // the BODY only [sigEndByte,endByte)
            if( int( tc ) < minTokens ) continue;
            tok[id] = tc;
            groups[ std::move( norm ) ].push_back( id );
        }
    }

    std::vector<CloneGroup> out;
    for( auto& [norm, members] : groups )
        if( members.size() >= 2 ) out.push_back( { members, tok[ members[0] ] } );
    std::sort( out.begin(), out.end(), [ & ]( const CloneGroup& x, const CloneGroup& y )
               {   // biggest clones first; stable tiebreak by first member's file:line
                   if( x.tokens != y.tokens ) return x.tokens > y.tokens;
                   const Symbol& sx = ing.symbols[ x.members[0] ];  const Symbol& sy = ing.symbols[ y.members[0] ];
                   return ing.files[sx.fileId] != ing.files[sy.fileId] ? ing.files[sx.fileId] < ing.files[sy.fileId] : sx.line < sy.line;
               } );
    return out;
}

// ── Type-3 (gapped / near-miss) clone detection ────────────────────────────────────────────────────────────
//
// Two symbols are a Type-3 clone when their NORMALIZED token streams are HIGHLY similar but NOT identical (an
// inserted / deleted / changed statement). Exact (Type-1/2) matches are handled by findClones() and are EXCLUDED
// here (they would score 1.0). Algorithm + cost bound:
//
//   1. Normalize each candidate body to a token vector (normalizeTokens). Keep only bodies with ≥ minTokens
//      tokens (same floor as findClones) — small bodies produce noise.
//   2. Collapse exact duplicates: bodies with an identical stream are Type-1/2, not Type-3; one representative
//      per distinct stream enters the candidate set (dedup by stream hash — deterministic, no cost blowup).
//   3. Fingerprint each candidate: the SET of its k-gram (k=kFpGram) hashes. Bucket candidates by fingerprint so
//      only pairs SHARING ≥1 k-gram are ever compared — the prefilter that avoids O(N²).
//   4. For each candidate pair, three cheap gates gate the expensive compare:
//         (a) length band  min(len)/max(len) ≥ kType3LenBand   — an LCS-ratio ≥ 0.8 is impossible outside it,
//         (a′) minhash sketch pre-gate (Y3): a 128-component 8-bit minhash of the fingerprint set (fixed
//              permutation constants — zero randomness), compared in O(kSketchHashes) byte ops; a pair whose
//              matching-component count sits far below the kType3MinFpJaccard operating point is rejected
//              WITHOUT running the O(|fp|) exact merge. See the bound table beside kSketchMinMatches.
//         (b) Jaccard of the k-gram fingerprint sets ≥ kType3MinFpJaccard — a lexical lower bound on similarity.
//      B1 ORDER: gate (a) is O(1) and PURE, so it runs BEFORE the `pairSeen` de-dup bookkeeping — a length-mismatched
//      pair (the common case) is dropped with one float compare and never touches the hashmap, skipping its share of
//      the ~60.5 M raw-visit find+emplace ops that dominated the pass. Gates (a′) and (b) are O(kSketchHashes) and
//      O(|fp|), NOT O(1), so they stay AFTER the de-dup: a pair recurs in every bucket it shares a k-gram with, and
//      re-running them per recurrence is a large net loss (measured ~3× slower for (b)) — behind `pairSeen` each runs
//      once per distinct pair. Gates (a)+(b) are pure, so their order relative to the de-dup never changes WHICH
//      distinct pairs pass both: with the sketch pre-gate compiled out (-DCTX_TYPE3_SKETCH_OFF) the emitted SET is
//      byte-identical to the pre-Y3 code. The sketch gate (a′) is also pure and deterministic, but it is an
//      ε-approximation of (b): its miss probability at the J=0.40 boundary is ≤ 4.8e-7 per pair (table below), and
//      the emitted set was verified pair-identical against the exact baseline on this repo src/, SFML, and llama.cpp
//      (test/clonebandcheck.sh asserts the parity on a borderline-including fixture on every run).
//   5. Only pairs passing (a)+(a′)+(b) get the O(n·m) LCS over the two token sequences (n,m ≤ per-body token count;
//      capped at kType3MaxTokensForLcs so one pathological pair can't dominate). similarity = 2·LCS/(|a|+|b|).
//   6. Report pairs with kType3MinSimilarity ≤ similarity < 1.0 as CloneGroup{ {a,b}, tokens, type=3, similarity }.
//
// Cost bound: N candidates, bucketed by k-gram → the number of compared pairs is bounded by shared-fingerprint
// co-occurrence (near-linear for typical corpora), NOT N². Each compare is O(n·m) with n,m ≤ kType3MaxTokensForLcs,
// so worst-case per pair is a fixed constant. No full all-pairs edit distance is ever computed. Deterministic:
// similarity is a pure function of the two token streams; groups are emitted sorted by (first id, second id).

constexpr float         kType3MinSimilarity  = 0.80f;   // report pairs with LCS-ratio ≥ this (and < 1.0)
constexpr float         kType3LenBand        = 0.70f;   // skip pairs whose token-count ratio is below this
constexpr float         kType3MinFpJaccard   = 0.40f;   // lexical prefilter: skip pairs with k-gram Jaccard below this
constexpr std::uint32_t kFpGram              = 5;       // k for the k-gram fingerprints
constexpr std::size_t   kType3MaxTokensForLcs = 4096;   // cap the LCS DP dimension per body (cost guard)
// Hard cap on compared (LCS-worthy) pairs (belt-and-suspenders guard) — bounds `comparedPairs`, the count of pairs
// that clear BOTH gates and reach the LCS. Since B1 the O(1) length band runs before the `pairSeen` bookkeeping (so a
// length-mismatched pair never enters the hashmap), so on a pathological cap-hitting corpus the kept set is "the first
// N pairs that survive the length band AND the Jaccard gate" in the deterministic (insertion-ordered bucket, idx-sorted)
// walk — never the raw ~60.5 M intra-bucket visits. It affects emitted output only on such a corpus (none of the
// shipped corpora reach it; verified byte-identical). Overridable at COMPILE TIME via -DCTX_TYPE3_MAX_PAIRS=<n> for the
// cap-hitting gate fixture ONLY (test/type3clonecheck.sh); the shipped binary always uses the 200000 default.
#ifndef CTX_TYPE3_MAX_PAIRS
#define CTX_TYPE3_MAX_PAIRS 200000
#endif
constexpr std::size_t   kType3MaxPairs        = CTX_TYPE3_MAX_PAIRS;
// A4-P2 stop-gram rule: a k-gram shared by MORE than this many candidate bodies is ubiquitous boilerplate — it
// carries no discriminative signal yet generates O(bucket²) pairs into `pairSeen` (the churn P2 measured). Skipping
// such a bucket only drops a pair whose EVERY shared k-gram is this common (it shares nothing rare); a genuine
// near-clone shares rarer grams and is still compared through a smaller bucket. Deterministic (fixed const, checked
// before any per-pair work). The bound is set well ABOVE the largest bucket real corpora produce (a large private
// C++ corpus's peak is ≈500) so it never perturbs the answer there — it is a worst-case guard for pathological duplicate-heavy
// inputs where a single boilerplate 5-gram would otherwise spawn millions of pairs.
constexpr std::size_t   kType3MaxBucket       = 1024;   // skip fingerprint buckets larger than this (stop-gram cut)

// ── Y3: the deterministic minhash pre-gate ────────────────────────────────────────────────────────────────
// On real corpora the overwhelming majority of distinct length-band-surviving pairs are grossly dissimilar
// (llama.cpp: 99.1 % of 4.48 M pairs at k-gram Jaccard < 0.20, yet each paid the full O(|fp|) exact merge —
// the --quality-delta floor). The pre-gate estimates the Jaccard with kSketchHashes independent 8-bit minhash
// components and rejects a pair when fewer than kSketchMinMatches components agree; only plausibly-similar
// pairs reach the exact merge, which stays the sole authority on kType3MinFpJaccard.
//
// DETERMINISM: each component j is min over the fingerprint set of a FIXED bijection of the 64-bit gram hash
// (multiply by the odd constant kSketchMul[j], then one xorshift — both bijective mod 2^64), truncated to its
// low byte (b-bit minhash). The constants come from a compile-time splitmix64 stream: no randomness, no seed,
// no wall clock — byte-identical across runs and machines, exactly like the fingerprints it is built from.
//
// RECALL BOUND (exact binomial, match probability p = J + (1-J)/256 — the +1/256 is the 8-bit truncation
// collision floor; H = 128, threshold m ≥ 26 ⇒ operating point m/H ≈ 0.20):
//     P( reject | J = 0.40 ) = 4.8e-7      P( accept | J = 0.10 ) = 6.1e-4
//     P( reject | J = 0.45 ) = 1.0e-9      P( accept | J = 0.15 ) = 7.8e-2
//     P( reject | J = 0.50 ) = 7.1e-13     P( accept | J = 0.20 ) = 5.4e-1
// i.e. a pair AT the exact-gate boundary is lost with p < 5e-7 (per pair, fixed for a given corpus — the
// "probability" is over the fixed hash family, so the miss set is deterministic), while the sub-0.15-Jaccard
// mass that dominates real corpora is rejected at ≥ 92 %. Verified pair-identical vs the exact baseline on
// this repo src/, SFML, and llama.cpp (0 pairs lost of 25k emitted); test/clonebandcheck.sh re-proves parity
// on every run, including a borderline pair engineered just above the 0.40 boundary.
// -DCTX_TYPE3_SKETCH_OFF compiles the pre-gate out (the exact-everywhere baseline; used by the parity gate).
constexpr std::uint32_t kSketchHashes     = 128;   // minhash components per candidate (1 byte each)
constexpr std::uint32_t kSketchMinMatches = 26;    // pass to the exact merge iff ≥ this many components match

// splitmix64 — the standard 64-bit mix; constexpr so the permutation-constant table is built at compile time.
inline constexpr std::uint64_t sketchSplitmix64( std::uint64_t x ) noexcept
{
    // wraparound mod 2^64 is the design; this function is ONLY evaluated at compile time (the kSketchMul
    // constexpr table below), so the G1 unsigned-overflow sanitizer never sees it — but the multiplies are
    // routed through the sanitizer-clean helper anyway so a future runtime caller can't trip G1.
    x += 0x9e3779b97f4a7c15ull;
    x = hashutil::multiplyModulo64( x ^ ( x >> 30 ), 0xbf58476d1ce4e5b9ull );
    x = hashutil::multiplyModulo64( x ^ ( x >> 27 ), 0x94d049bb133111ebull );
    return x ^ ( x >> 31 );
}

// the FIXED permutation constants — one odd multiplier per component, from the splitmix64 stream.
inline constexpr std::array<std::uint64_t, kSketchHashes> kSketchMul = []
{
    std::array<std::uint64_t, kSketchHashes> m{};
    for( std::uint32_t j = 0; j < kSketchHashes; ++j ) m[j] = sketchSplitmix64( j + 1 ) | 1ull;   // odd ⇒ bijective multiply mod 2^64
    return m;
}();

// build one candidate's sketch: sig[j] = low byte of min over the fp set of the j-th fixed bijection.
// O(kSketchHashes·|fp|) integer ops, done ONCE per candidate — amortized across every pair it appears in.
inline void cloneSketchSig( const std::vector<std::uint64_t>& fp, std::uint8_t* sig ) noexcept
{
    for( std::uint32_t j = 0; j < kSketchHashes; ++j )
    {
        const std::uint64_t mul = kSketchMul[j];
        std::uint64_t       mn  = ~0ull;                 // empty fp ⇒ 0xFF sentinel components (never bucketed anyway)
        for( const std::uint64_t g : fp )
        {
            std::uint64_t h = hashutil::multiplyModulo64( g, mul );   // sanitizer-clean modulo-2^64 (G1 integer stack)
            h ^= h >> 32;                                // fold the well-mixed high half into the compared/stored bits
            if( h < mn ) mn = h;
        }
        sig[j] = std::uint8_t( mn );
    }
}

// matching-component count of two sketches — the pre-gate's whole per-pair cost (auto-vectorizes to byte lanes).
inline std::uint32_t cloneSketchMatches( const std::uint8_t* a, const std::uint8_t* b ) noexcept
{
    std::uint32_t m = 0;
    for( std::uint32_t j = 0; j < kSketchHashes; ++j ) m += std::uint32_t( a[j] == b[j] );
    return m;
}

// Optional per-pass observability (test/clonebandcheck.sh asserts the reduction on these COUNTERS, never wall
// time). Production callers pass nothing; the counters cost a handful of register increments.
struct Type3Stats
{
    std::uint64_t candidateCount = 0;   // distinct-stream candidates entering the pair search
    std::uint64_t rawPairVisits  = 0;   // intra-bucket pair visits, incl. per-bucket recurrences (pre length-band)
    std::uint64_t distinctPairs  = 0;   // post length-band + de-dup — the pre-gate's input
    std::uint64_t sketchRejects  = 0;   // rejected by the minhash pre-gate (never merged)
    std::uint64_t jaccardMerges  = 0;   // exact fingerprint merges run
    std::uint64_t lcsRuns        = 0;   // pairs that cleared every gate and reached the LCS DP
    std::uint64_t emittedPairs   = 0;   // final Type-3 pairs returned
};

// FNV-1a over a token — used to reduce a k-gram to a single 64-bit fingerprint (order-sensitive within the gram).
// The fingerprint + stream-dedup hashes are computed over the token TEXT (not the interned id) on purpose: it keeps
// the bucketing / Jaccard / exact-dedup equivalence classes BYTE-IDENTICAL to the pre-A4-P2 code, so the perf work
// (interning → scalar LCS) never perturbs which pairs are found. Only the LCS DP itself moved to interned u32 ids.
// The Y3 minhash sketch is likewise computed from these same token-TEXT fingerprints (with the fixed kSketchMul
// constants above), so the pre-gate inherits the identical equivalence classes — never a second hash domain.
inline std::uint64_t cloneTokenHash( const std::string& t, std::uint64_t seed ) noexcept
{
    std::uint64_t h = seed;
    for( const char c : t ) h = hashutil::fnv1aAbsorb( h, c );
    h ^= 0x9e3779b97f4a7c15ull;  h = hashutil::fnv1aMultiply( h );   // token separator so [ab][c] != [a][bc]
    return h;
}

// LCS length of two token-ID sequences via rolling two-row DP. O(|a|·|b|) time, O(min) space. Comparing interned
// u32 ids (A4-P2) instead of std::string cells makes each DP cell a scalar compare. Sequences are clamped to
// kType3MaxTokensForLcs by the caller so this stays a bounded constant per pair.
inline std::size_t cloneLcsLen( const std::vector<std::uint32_t>& a, const std::vector<std::uint32_t>& b )
{
    const std::size_t na = a.size(), nb = b.size();
    if( na == 0 || nb == 0 ) return 0;
    std::vector<std::uint32_t> prev( nb + 1, 0 ), cur( nb + 1, 0 );
    for( std::size_t i = 1; i <= na; ++i )
    {
        for( std::size_t j = 1; j <= nb; ++j )
            cur[j] = ( a[i - 1] == b[j - 1] ) ? prev[j - 1] + 1 : std::max( prev[j], cur[j - 1] );
        std::swap( prev, cur );
        std::fill( cur.begin(), cur.end(), 0u );
    }
    return prev[nb];
}

// Find Type-3 (gapped) clone PAIRS: normalized streams highly similar (LCS-ratio ≥ kType3MinSimilarity) but not
// identical. Each returned group has exactly two members {loId,hiId} with type==3 and the measured similarity.
// Deterministic; bounded (see the header block). Does NOT alter findClones() — callers opt into this pass.
// statsOut (optional): per-pass pair-visit counters for the clonebandcheck gate; never affects the result.
inline std::vector<CloneGroup> findClonesType3( const IngestResult& ing, int minTokens, Type3Stats* statsOut = nullptr )
{
    Type3Stats st;

    // per-file candidate ids: same body-region gate as findClones (real body, function/method).
    std::vector<std::vector<NodeId>> byFile( ing.files.size() );
    for( const Symbol& s : ing.symbols )
        if( ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && s.fileId < byFile.size()
            && s.endByte > s.sigEndByte )
            byFile[ s.fileId ].push_back( s.id );

    // Candidate = one representative per DISTINCT normalized stream (exact dups are Type-1/2, excluded here).
    // A4-P2: token streams are interned to u32 ids (one repo-wide HashMap) so the LCS DP and the k-gram
    // fingerprints compare/hash scalars, not std::strings. Interning order is process-local and never leaks:
    // ids feed only equality-compares, hashes, and set membership — every emitted field stays name/path/line-based.
    struct Cand
    {
        NodeId                     id;
        std::vector<std::uint32_t> toks;    // normalized token sequence (interned ids; LCS input)
        std::vector<std::uint64_t> fp;      // sorted, de-duplicated k-gram fingerprint set
    };
    std::vector<Cand>                     cands;
    std::vector<std::uint32_t>            candTokens;   // SoA: token count per candidate — the ONLY field the hot
                                                        // length-band check reads (flat u32 array ⇒ cache-resident
                                                        // across the tens of millions of raw pair visits, instead of
                                                        // two random ~80-byte Cand loads per visit)
    std::vector<std::uint8_t>             candSig;      // SoA: kSketchHashes minhash bytes per candidate (Y3 pre-gate)
    HashMap<std::uint64_t, NodeId>        streamSeen;   // stream-hash → first id with that exact stream (dedup)
    HashMap<std::string, std::uint32_t>   interner;     // normalized token text → dense u32 id (order-free semantics)

    std::string bytes;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( byFile[f].empty() ) continue;
        std::FILE* fp = std::fopen( diskPath( ing, std::uint32_t( f ) ).c_str(), "rb" );
        if( !fp ) continue;   // degrade: unreadable file just contributes no candidates (never a crash)
        std::fseek( fp, 0, SEEK_END );
        const long sz = std::ftell( fp );
        std::fseek( fp, 0, SEEK_SET );
        bytes.clear();
        if( sz > 0 ) { bytes.resize( std::size_t( sz ) ); if( std::fread( bytes.data(), 1, std::size_t( sz ), fp ) != std::size_t( sz ) ) bytes.clear(); }
        std::fclose( fp );
        if( bytes.empty() ) continue;

        for( NodeId id : byFile[f] )
        {
            const Symbol&            s    = ing.symbols[id];
            const bool               hash = ( s.lang == Lang::Python || s.lang == Lang::Bash || s.lang == Lang::Ruby );
            std::vector<std::string> raw  = normalizeTokens( bytes, s.sigEndByte, s.endByte, hash );
            if( int( raw.size() ) < minTokens ) continue;

            // dedup exact streams: hash the joined token TEXT (byte-identical to the pre-A4-P2 hash); keep only the
            // first id per distinct stream. Done over `raw` so the exact-dedup equivalence classes never shift.
            std::uint64_t sh = 1469598103934665603ull;
            for( const std::string& t : raw )
            {
                for( const char c : t ) sh = hashutil::fnv1aAbsorb( sh, c );
                sh ^= 0x2full;
                sh = hashutil::fnv1aMultiply( sh );
            }
            if( streamSeen.find( sh ) != streamSeen.end() ) continue;   // exact clone of an earlier candidate → skip (Type-1/2)
            streamSeen.emplace( sh, id );

            // k-gram fingerprint set (sorted+unique for Jaccard by merge) — hashed over the token TEXT, exactly as
            // before, so bucketing + Jaccard are unchanged. (Only the LCS below moved to interned u32 ids.)
            std::vector<std::uint64_t> fp;
            if( raw.size() >= kFpGram )
            {
                fp.reserve( raw.size() - kFpGram + 1 );
                for( std::size_t i = 0; i + kFpGram <= raw.size(); ++i )
                {
                    std::uint64_t g = 1469598103934665603ull;
                    for( std::uint32_t k = 0; k < kFpGram; ++k ) g = cloneTokenHash( raw[i + k], g );
                    fp.push_back( g );
                }
                std::sort( fp.begin(), fp.end() );
                fp.erase( std::unique( fp.begin(), fp.end() ), fp.end() );
            }

            // intern each token text → dense u32 id: the LCS DP (the O(n·m) hot loop, item 2) then compares scalars
            // instead of std::strings. Interning order is process-local and feeds only equality-compares.
            std::vector<std::uint32_t> toks;
            toks.reserve( raw.size() );
            for( const std::string& t : raw )
            {
                auto it = interner.find( t );
                const std::uint32_t tid = ( it != interner.end() ) ? it->second : interner.emplace( t, std::uint32_t( interner.size() ) ).first->second;
                toks.push_back( tid );
            }
            candTokens.push_back( std::uint32_t( toks.size() ) );
#ifndef CTX_TYPE3_SKETCH_OFF
            candSig.resize( candSig.size() + kSketchHashes );
            cloneSketchSig( fp, candSig.data() + candSig.size() - kSketchHashes );
#endif
            cands.push_back( { id, std::move( toks ), std::move( fp ) } );
        }
    }
    st.candidateCount = cands.size();

    // Bucket candidates by fingerprint hash → candidate indices sharing a k-gram. Only intra-bucket pairs are
    // ever compared, so a pair with ZERO shared k-grams is never touched (the O(N²) escape hatch).
    HashMap<std::uint64_t, std::vector<std::uint32_t>> buckets;
    for( std::uint32_t ci = 0; ci < cands.size(); ++ci )
        for( std::uint64_t g : cands[ci].fp )
            buckets[g].push_back( ci );

    // Enumerate candidate PAIRS via co-occurrence in any bucket; de-dup pairs with a seen-set.
    HashMap<std::uint64_t, std::uint8_t> pairSeen;
    std::vector<CloneGroup>              out;
    std::size_t                          comparedPairs = 0;
    const auto pairKey = []( std::uint32_t x, std::uint32_t y ) noexcept
    { return ( std::uint64_t( x ) << 32 ) | std::uint64_t( y ); };

    for( auto& [g, idxs] : buckets )
    {
        (void)g;
        if( idxs.size() < 2 ) continue;
        // Stop-gram cut (A4-P2): a bucket bigger than kType3MaxBucket is a ubiquitous k-gram — O(size²) pairs of
        // pure boilerplate. Skip it; any real near-clone in it shares a rarer gram and is compared via a smaller
        // bucket. Fixed threshold + this is before any per-pair work, so the decision is fully deterministic.
        if( idxs.size() > kType3MaxBucket ) continue;
        std::sort( idxs.begin(), idxs.end() );   // deterministic pair enumeration within the bucket
        for( std::size_t a = 0; a < idxs.size(); ++a )
            for( std::size_t b = a + 1; b < idxs.size(); ++b )
            {
                const std::uint32_t ia = idxs[a], ib = idxs[b];   // ia < ib by the sort

                // (a) length band FIRST (B1) — this gate is O(1) and a PURE function of the pair, so hoisting it AHEAD
                // of the `pairSeen` bookkeeping drops the common length-mismatched pair without ever touching the
                // hashmap: it replaces that pair's find+emplace (the ~60.5 M raw-visit ops that dominated the pass)
                // with a single float compare. The Jaccard gate (b) is O(|fp|), NOT O(1), and DELIBERATELY stays AFTER
                // the de-dup: a pair recurs in every bucket it shares a k-gram with, so re-running the merge per
                // recurrence is a large net loss (measured ~3× slower) — behind `pairSeen` it runs once per distinct
                // pair. Emitted SET is unchanged: the gates are pure, so their order and where the de-dup sits never
                // change WHICH distinct pairs pass both. Outside the length band an LCS-ratio ≥ kType3MinSimilarity is
                // impossible, so dropping here is exact. Reads the SoA candTokens array ONLY (Y3): two 4-byte loads
                // from a cache-resident array instead of two random Cand-struct loads per raw visit.
                ++st.rawPairVisits;
                const std::uint32_t lo = std::min( candTokens[ia], candTokens[ib] ), hi = std::max( candTokens[ia], candTokens[ib] );
                if( hi == 0 || float( lo ) / float( hi ) < kType3LenBand ) continue;

                // De-dup the length-band survivors (once per distinct pair) + charge the deterministic cap. `pairSeen`
                // is insertion-order-free (pure membership) and the bucket walk is insertion-ordered + idx-sorted, so
                // the kept/dropped split on a cap-hitting corpus is fully deterministic.
                const std::uint64_t pk = pairKey( ia, ib );
                if( pairSeen.find( pk ) != pairSeen.end() ) continue;
                pairSeen.emplace( pk, 1 );
                if( comparedPairs >= kType3MaxPairs ) { DEGRADED_PATH_ALERT( "clones: Type-3 pair cap hit — first N compared (both-gate-surviving) near-misses kept, rest skipped" ); goto done; }
                ++st.distinctPairs;

#ifndef CTX_TYPE3_SKETCH_OFF
                // (a′) Y3 minhash pre-gate — O(kSketchHashes) byte compares against the operating point; the grossly
                // dissimilar pairs that dominate real corpora (99 % at J < 0.20 on llama.cpp) die here without ever
                // paying the O(|fp|) exact merge. Pure + deterministic (fixed constants); recall bound at the top.
                if( cloneSketchMatches( candSig.data() + std::size_t( ia ) * kSketchHashes,
                                        candSig.data() + std::size_t( ib ) * kSketchHashes ) < kSketchMinMatches )
                { ++st.sketchRejects; continue; }
#endif

                const Cand& ca = cands[ia];
                const Cand& cb = cands[ib];

                // (b) fingerprint Jaccard — lexical lower bound on similarity, both fp sets sorted → merge count. Now
                // behind the de-dup, so it runs once per distinct length-band-surviving pair, not once per recurrence.
                ++st.jaccardMerges;
                std::size_t inter = 0;
                {
                    std::size_t i = 0, j = 0;
                    while( i < ca.fp.size() && j < cb.fp.size() )
                    {
                        if( ca.fp[i] == cb.fp[j] ) { ++inter; ++i; ++j; }
                        else if( ca.fp[i] < cb.fp[j] ) ++i; else ++j;
                    }
                }
                const std::size_t uni = ca.fp.size() + cb.fp.size() - inter;
                if( uni == 0 || float( inter ) / float( uni ) < kType3MinFpJaccard ) continue;

                // (c) the expensive compare: LCS over token sequences (clamped to the cost cap).
                ++comparedPairs;
                ++st.lcsRuns;
                const std::vector<std::uint32_t>* pa = &ca.toks;
                const std::vector<std::uint32_t>* pb = &cb.toks;
                std::vector<std::uint32_t>        ta, tb;
                if( pa->size() > kType3MaxTokensForLcs ) { ta.assign( pa->begin(), pa->begin() + kType3MaxTokensForLcs ); pa = &ta; }
                if( pb->size() > kType3MaxTokensForLcs ) { tb.assign( pb->begin(), pb->begin() + kType3MaxTokensForLcs ); pb = &tb; }
                const std::size_t lcs = cloneLcsLen( *pa, *pb );
                const std::size_t den = pa->size() + pb->size();
                if( den == 0 ) continue;
                const float sim = 2.0f * float( lcs ) / float( den );
                if( sim < kType3MinSimilarity || sim >= 1.0f ) continue;   // < 1.0: exact would be Type-1/2

                // member order stable by symbol id (small id first) → deterministic emit.
                const NodeId x = std::min( ca.id, cb.id ), y = std::max( ca.id, cb.id );
                out.push_back( { { x, y }, std::max( candTokens[ia], candTokens[ib] ), std::uint8_t( 3 ), sim } );
            }
    }
done:
    // Deterministic order: by (first member id, second member id). Similarity is a pure function of the streams,
    // so ties are impossible for a fixed pair; the id sort fully determines the sequence.
    std::sort( out.begin(), out.end(), []( const CloneGroup& p, const CloneGroup& q )
               { return p.members[0] != q.members[0] ? p.members[0] < q.members[0] : p.members[1] < q.members[1]; } );
    st.emittedPairs = out.size();
    if( statsOut ) *statsOut = st;
    return out;
}

}   // namespace rw
