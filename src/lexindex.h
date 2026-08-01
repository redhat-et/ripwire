#pragma once

// lexindex.h — the SHARED subtoken machinery behind B0.1/B0.2 (PLAN_researchImprove2026 Phase B0):
// one tokenizer state machine used by BOTH the query-time BM25 scan (lexical.h scanField) and the
// index-time per-definition statistics builder (ingest.cpp), so the two can never drift — the postings
// path's byte-identity to the scan path is structural, not coincidental.
//
// WHAT IS PERSISTED (rich cache family only, captureValueUses=true): for each definition, the weighted
// subtoken term-frequency table of its DOC-COMMENT (×kLexWeightDoc) + BODY (×kLexWeightBody) fields —
// (subtokenHash → weighted tf) sorted by hash — plus the weighted doc-length those fields contribute.
// Exact integer counts, built once at parse time from the SAME byte spans lexical.h Pass 2 scans, so a
// warm query recomputes BM25 from lookups with NO file re-read/re-tokenize (R1 hypothesis #1) and lands
// on the identical dl[]/tf[] integers the scan would produce → identical doubles → identical bytes.

#include "model.h"
#include "hashutil.h"   // fnv1aMultiply — the same sanitizer-clean modulo-2^64 FNV family as the cache hashes

#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// field weights for the two file-text BM25F fields (lexical.h keeps name=3 / callee=1 locally; these two
// are shared because the index-time builder must weigh doc/body EXACTLY like the query-time scan).
inline constexpr int kLexWeightDoc  = 2;
inline constexpr int kLexWeightBody = 1;

// per-FILE subtoken pre-filter signature (B0.1): one bit per subtoken hash over the file's doc/body
// fields. No false negatives — a clear bit proves NO symbol in the file contains that subtoken, so the
// per-symbol tf walk can skip the whole file; a false positive just walks the (cheap) stats. 512 bits.
inline constexpr std::size_t kLexFileSigWords = 8;    // 8 × u64 = 512 bits per file
inline constexpr std::uint64_t lexSigBit( std::uint64_t hash ) noexcept { return std::uint64_t( 1 ) << ( hash & 63u ); }
inline constexpr std::size_t   lexSigWord( std::uint64_t hash ) noexcept { return std::size_t( ( hash >> 6 ) & ( kLexFileSigWords - 1 ) ); }

// Scan back from a def's start byte over the CONTIGUOUS comment block directly above it (// , /// , /* , or
// a * continuation line), returning the byte where that doc-comment begins. So [docCommentStart, endByte)
// covers doc-comment + signature + body — the text we index so a query matches intent + behavior, not just
// the name. Bounded at 16 lines; stops at the first non-comment line (no bridging across blank gaps).
inline std::size_t docCommentStart( const std::string& src, std::size_t defStart ) noexcept
{
    if( defStart > src.size() ) defStart = src.size();
    std::size_t ls = defStart;
    while( ls > 0 && src[ ls - 1 ] != '\n' ) --ls;          // start of the def's own line
    for( int guard = 0; guard < 16 && ls > 0; ++guard )     // up to 16 preceding comment lines
    {
        const std::size_t pe = ls - 1;                      // '\n' ending the previous line
        std::size_t       ps = pe;
        while( ps > 0 && src[ ps - 1 ] != '\n' ) --ps;      // start of the previous line
        std::size_t t = ps;
        while( t < pe && ( src[t] == ' ' || src[t] == '\t' ) ) ++t;   // skip indent
        const bool comment = ( t + 1 < pe && src[t] == '/' && ( src[t + 1] == '/' || src[t + 1] == '*' ) )
                          || ( t < pe && src[t] == '*' );   // // , /* , or a * continuation of a block
        if( !comment ) break;
        ls = ps;
    }
    return ls;
}

// The ONE subtoken state machine (extracted verbatim from lexical.h scanField so index-time and query-time
// tokenization are the same function): a token is a maximal [optional uppercase][lowercase/digit]* run
// between separators — an interior uppercase char always starts a NEW token, so only a token's FIRST byte
// can be uppercase. Emits RAW [tokStartByte, tokEndByte) spans; callers apply the ≥2-byte drop themselves
// (mirroring subtokens()/scanField exactly).
template<class EmitFn>
inline void forEachLexSubtoken( std::string_view text, EmitFn&& emit )
{
    constexpr std::size_t kNoTokenByte = ~std::size_t( 0 );
    std::size_t           tokStartByte = kNoTokenByte;
    for( std::size_t k = 0; k < text.size(); ++k )
    {
        const unsigned char c     = static_cast<unsigned char>( text[k] );
        const bool          upper = c >= 'A' && c <= 'Z';
        const bool          lower = c >= 'a' && c <= 'z';
        const bool          digit = c >= '0' && c <= '9';
        if( !upper && !lower && !digit )                                                                       // separator
        {
            if( tokStartByte != kNoTokenByte ) { emit( tokStartByte, k ); tokStartByte = kNoTokenByte; }
            continue;
        }
        if( upper && tokStartByte != kNoTokenByte ) { emit( tokStartByte, k ); tokStartByte = k; continue; }   // camel boundary
        if( tokStartByte == kNoTokenByte ) tokStartByte = k;
    }
    if( tokStartByte != kNoTokenByte ) emit( tokStartByte, text.size() );
}

// FNV-1a 64 over the token's NORMALIZED bytes (first byte lowercased; the state machine guarantees every
// later byte is already lowercase/digit) — so hashing a corpus token equals hashing the all-lowercase
// query subtoken it would string-match. 64-bit keys make a cross-token collision (the only way the
// postings path could diverge from the scan path) astronomically unlikely; the postingscheck equivalence
// gate verifies byte-identity on the real corpora.
inline std::uint64_t lexSubtokenHash( const char* tok, std::size_t tokLen ) noexcept
{
    std::uint64_t       h    = 1469598103934665603ull;
    const unsigned char head = static_cast<unsigned char>( tok[0] );
    h ^= ( head >= 'A' && head <= 'Z' ) ? static_cast<unsigned char>( head - 'A' + 'a' ) : head;
    h  = hashutil::fnv1aMultiply( h );
    for( std::size_t k = 1; k < tokLen; ++k ) { h ^= static_cast<unsigned char>( tok[k] ); h = hashutil::fnv1aMultiply( h ); }
    return h;
}

// per-definition persisted lexical statistics (B0.2) — SoA pair arrays sorted by hash (deterministic
// regardless of accumulation order), plus the weighted doc/body token count (the def's Pass-2 dl share).
struct RawDefLex
{
    std::uint32_t              dlWeighted = 0;   // Σ field-weighted subtoken count over doc(×2)+body(×1)
    std::vector<std::uint64_t> tokenHashes;      // sorted ascending; parallel to tokenTfs
    std::vector<std::uint32_t> tokenTfs;         // weighted term frequency per hash (exact integers)
};

// ── B0 round 2: the fused-hash tokenizer walk — forEachLexSubtoken with the FNV-1a rolling INSIDE the
// state machine, so the index-time stats builder touches each byte ONCE (the split shape walked every
// token's bytes twice: once to find the span, once to hash it — this seam is the rich-parse tail the
// index/cold budgets pay). Emits ( tokStartByte, tokEndByte, normalizedHash ); the hash is EXACTLY
// lexSubtokenHash( text + tokStartByte, len ): the first byte is lowercased before mixing, and every
// later byte is already lowercase/digit by the state machine's camel rule, so no other normalization
// exists to drift. Query-time scanField keeps the hash-free walker above (it string-compares instead).
template<class EmitFn>
inline void forEachLexSubtokenHashed( std::string_view text, EmitFn&& emit )
{
    constexpr std::size_t kNoTokenByte = ~std::size_t( 0 );
    constexpr std::uint64_t kFnvBasis  = 1469598103934665603ull;
    std::size_t           tokStartByte = kNoTokenByte;
    std::uint64_t         h            = kFnvBasis;
    const auto beginToken = [ & ]( unsigned char c, std::size_t k ) noexcept
    {
        tokStartByte = k;
        h  = kFnvBasis;
        h ^= ( c >= 'A' && c <= 'Z' ) ? static_cast<unsigned char>( c - 'A' + 'a' ) : c;
        h  = hashutil::fnv1aMultiply( h );
    };
    for( std::size_t k = 0; k < text.size(); ++k )
    {
        const unsigned char c     = static_cast<unsigned char>( text[k] );
        const bool          upper = c >= 'A' && c <= 'Z';
        const bool          lower = c >= 'a' && c <= 'z';
        const bool          digit = c >= '0' && c <= '9';
        if( !upper && !lower && !digit )                                                                       // separator
        {
            if( tokStartByte != kNoTokenByte ) { emit( tokStartByte, k, h ); tokStartByte = kNoTokenByte; }
            continue;
        }
        if( upper && tokStartByte != kNoTokenByte ) { emit( tokStartByte, k, h ); beginToken( c, k ); continue; }   // camel boundary
        if( tokStartByte == kNoTokenByte ) { beginToken( c, k ); continue; }
        h ^= c;                                                                                                // interior byte: already lowercase/digit
        h  = hashutil::fnv1aMultiply( h );
    }
    if( tokStartByte != kNoTokenByte ) emit( tokStartByte, text.size(), h );
}

// Build one def's stats from the SAME spans lexical.h Pass 2 scans: doc-comment [docCommentStart, bodyStart)
// at ×kLexWeightDoc and body [bodyStart, endByte) at ×kLexWeightBody, tokens < 2 bytes dropped. `scratch`
// is a caller-owned accumulator reused across defs (reserve once, clear per def — no rehash churn).
inline void buildDefLexStats( const std::string& src, std::uint32_t startByte, std::uint32_t endByte,
                              HashMap<std::uint64_t, std::uint32_t>& scratch, RawDefLex& out )
{
    scratch.clear();
    out.dlWeighted = 0;
    const std::string_view sv        = src;
    const std::size_t      bodyStart = std::min<std::size_t>( startByte, src.size() );
    const std::size_t      end       = std::min<std::size_t>( endByte, src.size() );
    const std::size_t      docStart  = docCommentStart( src, bodyStart );

    // one field through the fused state machine — the exact scanField accounting (≥2-byte drop BEFORE
    // the weight is added, weighted dl accumulated per field), each byte touched once (walk + hash fused)
    const auto scanFieldStats = [ & ]( std::string_view text, std::uint32_t w )
    {
        std::uint32_t fieldTokenWt = 0;
        forEachLexSubtokenHashed( text, [ & ]( std::size_t tokStartByte, std::size_t tokEndByte, std::uint64_t tokenHash )
        {
            if( tokEndByte - tokStartByte < 2 ) return;
            fieldTokenWt += w;
            scratch[ tokenHash ] += w;
        } );
        out.dlWeighted += fieldTokenWt;
    };
    if( bodyStart > docStart ) scanFieldStats( sv.substr( docStart, bodyStart - docStart ), std::uint32_t( kLexWeightDoc ) );
    if( end > bodyStart )      scanFieldStats( sv.substr( bodyStart, end - bodyStart ), std::uint32_t( kLexWeightBody ) );

    // extract sorted-by-hash pair arrays (HashMap iteration order must never reach persisted bytes)
    out.tokenHashes.clear();
    out.tokenTfs.clear();
    out.tokenHashes.reserve( scratch.size() );
    for( const auto& [ hash, tf ] : scratch ) out.tokenHashes.push_back( hash );
    std::sort( out.tokenHashes.begin(), out.tokenHashes.end() );
    out.tokenTfs.reserve( out.tokenHashes.size() );
    for( const std::uint64_t hash : out.tokenHashes ) out.tokenTfs.push_back( scratch.find( hash )->second );
}


}   // namespace rw
