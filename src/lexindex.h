#pragma once

// lexindex.h — the SHARED subtoken machinery behind B0.1/B0.2:
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
#include "infra/hashutil.h"   // fnv1aMultiply — the same sanitizer-clean modulo-2^64 FNV family as the cache hashes
#include "infra/strkern.h"   // classMasks — THE byte-parallel character-class kernel the walk below is built on

#include <algorithm>
#include <bit>
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
    if( defStart > src.size() )
    {
        defStart = src.size();
    }
    std::size_t ls = defStart;
    while( ls > 0 && src[ls - 1] != '\n' )
    {
        --ls; // start of the def's own line
    }
    for( int guard = 0; guard < 16 && ls > 0; ++guard )     // up to 16 preceding comment lines
    {
        const std::size_t pe = ls - 1;                      // '\n' ending the previous line
        std::size_t       ps = pe;
        while( ps > 0 && src[ps - 1] != '\n' )
        {
            --ps; // start of the previous line
        }
        std::size_t t = ps;
        while( t < pe && ( src[t] == ' ' || src[t] == '\t' ) )
        {
            ++t; // skip indent
        }
        const bool comment = ( t + 1 < pe && src[t] == '/' && ( src[t + 1] == '/' || src[t + 1] == '*' ) )
                          || ( t < pe && src[t] == '*' );   // // , /* , or a * continuation of a block
        if( !comment )
        {
            break;
        }
        ls = ps;
    }
    return ls;
}

// ASCII lowercase for one already-classified token byte. The tokenizer's consumers all need it and none
// of them may spell it differently: since 2026-08-19 a token can carry INTERIOR uppercase (an all-caps
// run is one token), so "lowercase the head, trust the rest" is no longer a legal shortcut anywhere.
// EXPLICIT unsigned narrowing — `char` is signed here, and G1's implicit-integer-sign-change fires on any
// byte ≥ 0x80 (hashutil.h owns the full note).
inline constexpr unsigned char lexLowerByte( unsigned char c ) noexcept
{
    return ( c >= 'A' && c <= 'Z' ) ? static_cast<unsigned char>( c - 'A' + 'a' ) : c;
}

// Does the token span [tok, tok+tokLen) equal the ALL-LOWERCASE string `lowerQuery` of the same length,
// once the span is lowercased? The BM25 scan compares query subtokens (lowercased by subtokens()) against
// raw corpus spans, and an acronym span like "MCP" is the case a plain memcmp gets wrong.
inline bool lexTokenEqualsLowered( const char* tok, std::size_t tokLen, const char* lowerQuery ) noexcept
{
    for( std::size_t k = 0; k < tokLen; ++k )
    {
        if( lowerQuery[k] != char( lexLowerByte( static_cast<unsigned char>( tok[k] ) ) ) )
        {
            return false;
        }
    }
    return true;
}

// ── THE BOUNDARY RULE, AND THE MASK ALGEBRA THAT COMPUTES IT ────────────────────────────────────────
//
// THE RULE (unchanged since 2026-08-19; docs/EVALS.md §4 "Subtoken acronym shredding"; gate:
// test/subtokencheck.sh). A token is a maximal [A-Za-z0-9] run, cut at two seams:
//   * the plain camel seam — an UPPERCASE byte whose predecessor was not uppercase ("fooBar" -> foo|Bar);
//   * the ACRONYMWord seam — the LAST uppercase of an all-caps run, and only when a LOWERCASE letter
//     follows it ("HTTPServer" -> HTTP|Server). A run followed by end, digit or separator stays whole:
//     "MCP" is one token, "MCP2Server" is mcp2|server.
// The lookahead is one byte and the split lands BEFORE the byte that triggers it. Tokens shorter than two
// bytes are dropped BY THE CALLER, exactly as subtokens() does.
//
// Until 2026-09-10 that rule was a per-byte state machine, written out TWICE (once here, once in the
// fused-hash walker below) — the shape that let the acronym bug live in one copy and not the other. It is
// now a single block walk over rw::strkern::classMasks, and the two public walkers are both thin wrappers
// over it, so there is no second copy left to drift. P2-3/S1 of PLAN_FULL_AUDIT_2026-09-10: this walk runs
// over every doc-comment and body field of every symbol, at query time inside the BM25 scan and again at
// index time, so it is one of the few loops in the tree that genuinely touches every byte of the corpus —
// the case where SIMD pays (see the F3 note at the top of infra/strkern.h for the case where it does not).
//
// THE ALGEBRA. With one bit per byte — A = alnum, U = upper, L = lower, `<< 1` meaning "the byte before",
// `>> 1` meaning "the byte after" — the state machine's `emit` points are:
//
//     inToken(k)  ==  A[k-1]                     the old `tokStartByte != kNoTokenByte`: the walker sets a
//                                                start at every alnum byte and clears it at every
//                                                separator, so "in a token at k" is exactly "byte k-1 was
//                                                alnum". prevUpper likewise IS U[k-1] whenever A[k-1] holds
//                                                (the walker's reset-to-false at a separator only matters
//                                                when A[k-1] is false, and A[k-1] already gates the term).
//     split       =  U & (A<<1) & ( ~(U<<1) | (L>>1) )        an upper byte, inside a token, whose
//                                                             predecessor was not upper (camel) OR whose
//                                                             successor is lower (ACRONYMWord)
//     starts      =  ( A & ~(A<<1) ) | split                  a run's first byte, plus every split point
//     cuts        =  starts | ~A                              where a token can END: at the next start, or
//                                                             at the next separator
//
// A token therefore runs from each `starts` bit to the NEXT `cuts` bit (or to the end of the text). Worked
// through by hand on the seam table, which is also how test/strkern_harness.cpp's arm F1 pins it:
//     "fooBar"      A=111111  U=bit3            split={3}      starts={0,3}   -> foo | Bar
//     "HTTPServer"  U={0..4}  L={5..9}          split={4}      starts={0,4}   -> HTTP | Server
//                   (k=1..3 fail: predecessor IS upper and successor is not lower)
//     "MCP2Server"  U={0,1,2,4} digit={3}       split={4}      starts={0,4}   -> MCP2 | Server
//                   (k=4 passes on the CAMEL half: U[3] is false, byte 3 being a digit)
//     "MCP"         no k has a lower successor  split={}       starts={0}     -> MCP
//
// Correctness is not argued from this comment: test/strkerncheck.sh's arms F1/F2/G4 compare these walkers
// against VERBATIM copies of the pre-2026-09-10 state machines on 100k random buffers (including a
// camel/acronym-dense alphabet), on the seam table above, and on every byte of src/ and docs/ — spans AND
// fused hashes, byte for byte.

// The ONE subtoken state machine. Emits RAW [tokStartByte, tokEndByte) spans; callers apply the >= 2-byte
// drop themselves (mirroring subtokens()/scanField exactly).
//
// Block-at-a-time, kBlockBytes at a time (16 on NEON, 32 on AVX2), with three carries across the block
// seam: whether the byte before the block was alnum and whether it was upper (the `<< 1` terms), and
// whether the byte AFTER the block is lowercase (the `>> 1` term — read as a single byte, since it is one
// byte and reading it here is cheaper than keeping a lookahead register). `pending` carries a token that
// began in an earlier block, so a token straddling any number of blocks is emitted once, with its true
// start and end.
template<class EmitSpanFn>
inline void forEachLexTokenSpan( std::string_view text, EmitSpanFn&& emitSpan )
{
    constexpr std::size_t kNoTokenByte = ~std::size_t( 0 );
    const std::size_t     n            = text.size();
    const char*           p            = text.data();
    std::size_t           pending      = kNoTokenByte;   // start byte of a token still looking for its end
    bool                  prevAlnum    = false;          // A[base-1]
    bool                  prevUpper    = false;          // U[base-1]

    for( std::size_t base = 0; base < n; base += strkern::kBlockBytes )
    {
        const std::size_t width = ( n - base < strkern::kBlockBytes ) ? ( n - base ) : strkern::kBlockBytes;
        strkern::Masks    m;
        strkern::classMasks( p + base, width, m );

        // `1u << 32` is undefined, and width IS 32 on the AVX2 block — hence the explicit all-ones case
        // rather than a shift that happens to work on this compiler.
        const std::uint32_t valid = ( width >= 32 ) ? ~std::uint32_t( 0 ) : ( ( std::uint32_t( 1 ) << width ) - 1u );

        const unsigned char after        = ( base + width < n ) ? static_cast<unsigned char>( p[ base + width ] ) : 0u;
        const std::uint32_t nextLowerBit = ( after >= 'a' && after <= 'z' ) ? ( std::uint32_t( 1 ) << ( width - 1 ) ) : 0u;

        // The block's LAST bit is the next block's carry (prevAlnum/prevUpper below), so it is dropped from
        // the shift on purpose — masked out first, because on the 32-byte AVX2 block every bit of the mask
        // is live and `x << 1` losing a set bit is what -fsanitize=integer's unsigned-shift-base rejects
        // (a 16-byte NEON mask never had a bit there to lose, which is why arm64 never saw it).
        constexpr std::uint32_t kBelowTop = ~std::uint32_t( 0 ) >> 1;
        const std::uint32_t alnumShift = ( ( m.alnum & kBelowTop ) << 1 ) | ( prevAlnum ? 1u : 0u );   // bit k = A[k-1]
        const std::uint32_t upperShift = ( ( m.upper & kBelowTop ) << 1 ) | ( prevUpper ? 1u : 0u );   // bit k = U[k-1]
        const std::uint32_t lowerAhead = ( m.lower >> 1 ) | nextLowerBit;              // bit k = L[k+1]

        const std::uint32_t split  = m.upper & alnumShift & ( ~upperShift | lowerAhead ) & valid;
        const std::uint32_t starts = ( m.alnum & ~alnumShift & valid ) | split;
        std::uint32_t       cuts   = starts | ( ~m.alnum & valid );

        while( cuts != 0 )
        {
            const unsigned    bitIndex = unsigned( std::countr_zero( cuts ) );
            cuts &= cuts - 1u;
            const std::size_t pos = base + bitIndex;
            if( pending != kNoTokenByte )
            {
                emitSpan( pending, pos );
            }
            pending = ( ( starts >> bitIndex ) & 1u ) != 0 ? pos : kNoTokenByte;
        }

        const std::uint32_t lastBit = std::uint32_t( 1 ) << ( width - 1 );
        prevAlnum = ( m.alnum & lastBit ) != 0;
        prevUpper = ( m.upper & lastBit ) != 0;
    }

    if( pending != kNoTokenByte )
    {
        emitSpan( pending, n );   // a token that runs to the end of the text has no cut byte to end it
    }
}

// The query-time walker: spans only (scanField string-compares instead of hashing).
template<class EmitFn>
inline void forEachLexSubtoken( std::string_view text, EmitFn&& emit )
{
    forEachLexTokenSpan( text, [ & ]( std::size_t tokStartByte, std::size_t tokEndByte ) { emit( tokStartByte, tokEndByte ); } );
}

// FNV-1a 64 over the token's NORMALIZED bytes (EVERY byte lowercased) — so hashing a corpus token equals
// hashing the all-lowercase query subtoken it would string-match. Lowercasing only the first byte was
// enough until 2026-08-19, when the state machine stopped shredding all-caps runs: a token may now be
// "MCP", and hashing that as "mCP" would make the postings path miss the query token "mcp" that the scan
// path matches. 64-bit keys make a cross-token collision (the only other way the postings path could
// diverge from the scan path) astronomically unlikely; the postingscheck equivalence gate verifies
// byte-identity on the real corpora, and test/subtokencheck.sh arm C pins this against the hashed walker.
// KEEP THE RANGE TEST HERE. The hashed walker uses the branchless `c | ( ( c & 0x40 ) >> 1 )` fold, which
// is exact for [A-Za-z0-9] and WRONG for anything else ('@' would become '`'); this entry point is the one
// external callers reach with bytes nothing has classified, so it stays general.
inline std::uint64_t lexSubtokenHash( const char* tok, std::size_t tokLen ) noexcept
{
    std::uint64_t h = 1469598103934665603ull;
    for( std::size_t k = 0; k < tokLen; ++k )
    {
        h = hashutil::fnv1aAbsorb( h, char( lexLowerByte( static_cast<unsigned char>( tok[k] ) ) ) );
    }
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

// ── the index-time walker: the same spans, plus each token's normalized hash ─────────────────────────
// Emits ( tokStartByte, tokEndByte, normalizedHash ), where the hash is EXACTLY
// lexSubtokenHash( text + tokStartByte, len ). It used to be a SECOND copy of the state machine with the
// FNV rolling inside it — the "touch each byte once" shape from B0 round 2. That shape is gone because
// the classification is no longer per-byte work at all: the block walk classifies 16 (NEON) or 32 (AVX2)
// bytes at a time, and the hash then runs over the token's bytes only. Two consequences worth stating:
// the state machine now exists ONCE (the drift risk B0's own header warns about is structurally gone),
// and the bytes the hash re-reads are the ~60-70% of the corpus that are inside tokens, at L1 distance,
// having just been touched by the classifier.
//
// THE FOLD IS BRANCHLESS AND EXACT (audit item S2, Lemire's SWAR case-fold identity): every byte of a
// token is [A-Za-z0-9] by construction, and for exactly that set `c | ( ( c & 0x40 ) >> 1 )` equals
// lexLowerByte( c ) — 'A' (0x41) has the 0x40 bit and gains 0x20; 'a' (0x61) has it and already carries
// 0x20, so the OR is a no-op; a digit (0x30..0x39) has no 0x40 bit and is left alone. It is NOT a general
// ASCII fold and must never be used on a byte that has not already been classified as alnum: '@' (0x40)
// would become '`'. lexSubtokenHash below keeps the general, range-tested form for external callers, and
// test/strkerncheck.sh arm F2 asserts the two agree on every token of every file in src/ and docs/.
template<class EmitFn>
inline void forEachLexSubtokenHashed( std::string_view text, EmitFn&& emit )
{
    constexpr std::uint64_t kFnvBasis = 1469598103934665603ull;
    forEachLexTokenSpan( text, [ & ]( std::size_t tokStartByte, std::size_t tokEndByte )
    {
        std::uint64_t h = kFnvBasis;
        for( std::size_t k = tokStartByte; k < tokEndByte; ++k )
        {
            const unsigned char c = static_cast<unsigned char>( text[k] );
            h = hashutil::fnv1aAbsorb( h, char( c | ( ( c & 0x40u ) >> 1 ) ) );
        }
        emit( tokStartByte, tokEndByte, h );
    } );
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
            if( tokEndByte - tokStartByte < 2 ) { return;
}
            fieldTokenWt += w;
            scratch[ tokenHash ] += w; } );
        out.dlWeighted += fieldTokenWt;
    };
    if( bodyStart > docStart )
    {
        scanFieldStats( sv.substr( docStart, bodyStart - docStart ), std::uint32_t( kLexWeightDoc ) );
    }
    if( end > bodyStart )
    {
        scanFieldStats( sv.substr( bodyStart, end - bodyStart ), std::uint32_t( kLexWeightBody ) );
    }

    // extract sorted-by-hash pair arrays (HashMap iteration order must never reach persisted bytes)
    out.tokenHashes.clear();
    out.tokenTfs.clear();
    out.tokenHashes.reserve( scratch.size() );
    for( const auto& [hash, tf] : scratch )
    {
        out.tokenHashes.push_back( hash );
    }
    std::sort( out.tokenHashes.begin(), out.tokenHashes.end() );
    out.tokenTfs.reserve( out.tokenHashes.size() );
    for( const std::uint64_t hash : out.tokenHashes )
    {
        out.tokenTfs.push_back( scratch.find( hash )->second );
    }
}


}   // namespace rw
