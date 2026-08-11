#pragma once

// clones.h — token-normalized duplicate detection (--clones), function/method level. The CCFinder/PMD-CPD
// idea: normalize each body to a token stream (identifiers → $I, literals →
// $N/$S, keywords + operators + punctuation kept), then group functions with identical normalized streams.
// Catches Type-1 (exact) and Type-2 (renamed-variable) clones. Agent value: "this already exists — reuse
// it, don't reimplement" (and "if you fix this, fix its twins"). Type-3 (gapped) clones are a later upgrade.

#include "model.h"
#include "infra/Diagnostics.h"  // DEGRADED_PATH_ALERT — graceful-degrade on the Type-3 pair-cap guard (never throw)
#include "infra/hashutil.h"     // sanitizer-clean modulo-2^64 FNV multiplication

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
        {
            m.emplace( k, std::uint8_t( 1 ) );
        }
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
    if( j >= n )
    {
        return 0;
    }
    if( src[j] == '\\' )
    {
        j += 2;                                          // backslash + at least one escaped byte ('\n', '\\', '\'')
        const std::size_t cap = i + 8;                   // bound the scan so '\xFFFF'-shaped input stays a constant
        while( j < n && j < cap && src[j] != '\'' )
        {
            ++j; // consume multi-byte escapes ('\xNN', '\123')
        }
    }
    else
    {
        j += 1; // exactly one content byte ('x')
    }
    return ( j < n && src[j] == '\'' ) ? ( j - i + 1 ) : 0;
}

// Multi-byte operator spellings, for the scanner's maximal-munch mode (see munchMultiByteOperators below).
// Only --readability asks for it today: `!=` scored as TWO operators is measuring punctuation, not operators.
// Maximal munch over the WHOLE table (longest match wins), so declaration order here is not load-bearing and
// a later addition cannot silently shadow an existing row.
// The `?\?` spellings are ESCAPED on purpose: `??=` is the trigraph for `#`. C++17 removed trigraph
// translation so the literal is correct either way, but clang warns (-Wtrigraphs) and a -Werror toolchain
// would turn that warning into a broken build on another platform. The backslash costs nothing and says why.
inline constexpr std::string_view kMultiByteOperators[] = {
    "<<=", ">>=", "...", "**=", "<=>", "===", "!==", "?\?=",
    "==", "!=", "<=", ">=", "&&", "||", "++", "--", "+=", "-=", "*=", "/=", "%=",
    "&=", "|=", "^=", "<<", ">>", "->", "=>", "::", "**", "?\?", "?.", "|>", ":=", "<-", ".."
};

// Longest operator spelling starting at src[i], or 0 when none matches (caller falls back to one byte).
inline std::size_t multiByteOperatorLen( const std::string& src, std::size_t i, std::size_t n ) noexcept
{
    std::size_t best = 0;
    for( const std::string_view op : kMultiByteOperators )
    {
        if( op.size() > best && i + op.size() <= n && src.compare( i, op.size(), op ) == 0 )
        {
            best = op.size();
        }
    }
    return best;
}

// Languages whose `#` opens a line comment. Two call sites in this file spelled the disjunction inline; a
// third consumer (readability.h) made it three, so it is named once here.
//
// A constexpr BITMASK, not a `==` chain and not a linear scan of a 3-row table. Both of those spellings were
// tried first and both landed on top of an existing helper — the `==` chain on graph.h's methodsCompatible,
// the scan on lintrules.h's isValidSeverity and two more — because "is this one of N constants" is the most
// re-derived shape in the tree, and --quality-delta names each new copy of it. The mask is one shift and one
// AND with no branch, so it is also the cheapest form for something called once per indexed symbol.
inline constexpr std::uint32_t langBit( Lang lang ) noexcept { return std::uint32_t( 1 ) << std::uint32_t( lang ); }
// Toml and Yaml belong here and Json/Markdown deliberately do not: `#` opens a real line comment in TOML
// and YAML alike, whereas
// JSON has no comment syntax at all and markdown's `#` is a heading. The distinction is load-bearing rather
// than cosmetic — the loop below runs over EVERY symbol in a file with no SymKind filter, so a TOML/YAML
// t="sec"
// body reaches normalizeSpan/scanCodeTokens exactly like a function body, and a `#`-blind scan would tokenize
// a table's comments as content and let two unrelated tables clone-match on their prose.
inline constexpr std::uint32_t kHashLineCommentLangMask = langBit( Lang::Python ) | langBit( Lang::Bash ) | langBit( Lang::Ruby ) | langBit( Lang::Toml ) | langBit( Lang::Yaml );
static_assert( std::uint32_t( Lang::Yaml ) < 32, "Lang outgrew a 32-bit mask — widen kHashLineCommentLangMask" );

inline bool usesHashLineComments( Lang lang ) noexcept
{
    return ( ( kHashLineCommentLangMask >> std::uint32_t( lang ) ) & std::uint32_t( 1 ) ) != 0;
}

// What the scanner decided a token IS. The consumer decides what to DO with that — normalize it away
// (--clones) or keep it verbatim (--readability) — which is the whole reason the two are separable.
enum class CodeTokenKind : std::uint8_t { Identifier, Keyword, Number, String, Punctuation };

// ══ THE ONE CODE SCANNER ══════════════════════════════════════════════════════════════════════════════
// Bytes [a,b) → every token, as a VERBATIM slice of `src` plus its kind; whitespace and `//`, `/* */` (and,
// with stripHashComments, `#`-to-EOL) comments dropped. Every token-stream consumer in the tree is a
// projection of this one loop:
//   --clones       erases identity  — identifiers→$I, numbers→$N, strings/chars→$S (normalizeSpan below)
//   --readability  keeps identity   — the slices ARE the Halstead operand/operator vocabulary
// It was two copies before readability.h would have made it three, and --quality-delta named the third as a
// 778-token clone of both the moment it landed. A template sink rather than a returned vector: --clones runs
// this over every function body in the corpus, so the shared form must not add an allocation per body.
//
// stripHashComments (A4-F2): without it an apostrophe in a `# don't …` comment opens a bogus char literal.
// Strings and chars are consumed by the branches ABOVE `#`, so a `#` inside a literal is never a comment.
//
// munchMultiByteOperators: OFF (the --clones shape) emits punctuation one byte at a time, so `!=` is two
// tokens. ON (the --readability shape) takes the longest match from kMultiByteOperators, because a Halstead
// operator count that scores `!=` as two operators is measuring punctuation, not operators. It is a
// PARAMETER and not a unification precisely because flipping it for --clones would change that verb's
// normalized streams — i.e. its output bytes — and the new lens must be purely additive (G5).
//
// `sink( std::string_view token, CodeTokenKind kind )` is called once per token, in source order.
template<typename Sink>
inline void scanCodeTokens( const std::string& src, std::size_t a, std::size_t b, bool stripHashComments,
                            bool munchMultiByteOperators, Sink&& sink )
{
    const std::size_t n = std::min<std::size_t>( b, src.size() );
    std::size_t       i = std::min<std::size_t>( a, n );
    const auto        idc = []( unsigned char c ) noexcept { return std::isalnum( c ) != 0 || c == '_'; };

    while( i < n )
    {
        const unsigned char c = static_cast<unsigned char>( src[i] );   // explicit: a raw char >=0x80 implicitly converting is the UBSan sign-change class (CI round 4 artifact)
        if( std::isspace( c ) != 0 )
        {
            ++i;
            continue;
        }
        if( c == '/' && i + 1 < n && src[i + 1] == '/' )
        {
            i += 2;
            while( i < n && src[i] != '\n' )
            {
                ++i;
            }
            continue;
        }
        if( c == '/' && i + 1 < n && src[i + 1] == '*' )
        {
            i += 2;
            while( i + 1 < n && !( src[i] == '*' && src[i + 1] == '/' ) )
            {
                ++i;
            }
            i = std::min( n, i + 2 );
            continue;
        }
        if( stripHashComments && c == '#' )
        {
            ++i;
            while( i < n && src[i] != '\n' )
            {
                ++i;
            }
            continue;
        }
        if( c == '"' )
        {
            const std::size_t begin = i;
            ++i;
            while( i < n && src[i] != '"' )
            {
                if( src[i] == '\\' )
                {
                    ++i;
                }
                ++i;
            }
            i = std::min( n, i + 1 );
            sink( std::string_view( src.data() + begin, i - begin ), CodeTokenKind::String );
            continue;
        }
        // ' opens a char literal only with a plausible close (bounded lookahead) AND not directly after an
        // identifier/digit byte — else it's punctuation (Rust lifetime `'a`, a stray apostrophe). Digit
        // separators (1'000'000) are absorbed by the number branch below, never reaching here.
        if( c == '\'' )
        {
            const bool        afterWord = i > a && idc( static_cast<unsigned char>( src[i - 1] ) );
            const std::size_t lit       = afterWord ? 0 : cloneCharLiteralLen( src, i, n );
            if( lit != 0 )
            {
                sink( std::string_view( src.data() + i, lit ), CodeTokenKind::String );
                i += lit;
                continue;
            }
            sink( std::string_view( src.data() + i, 1 ), CodeTokenKind::Punctuation );
            ++i;
            continue;
        }
        if( std::isdigit( c ) != 0 )
        {
            const std::size_t begin = i;
            while( i < n && ( idc( static_cast<unsigned char>( src[i] ) ) || src[i] == '.'
                              || ( src[i] == '\'' && i + 1 < n && idc( static_cast<unsigned char>( src[i + 1] ) ) ) ) )
            {
                ++i;
            }
            sink( std::string_view( src.data() + begin, i - begin ), CodeTokenKind::Number );
            continue;
        }
        if( std::isalpha( c ) != 0 || c == '_' )
        {
            const std::size_t begin = i;
            while( i < n && idc( static_cast<unsigned char>( src[i] ) ) )
            {
                ++i;
            }
            const std::string_view w( src.data() + begin, i - begin );
            sink( w, cloneIsKeyword( w ) ? CodeTokenKind::Keyword : CodeTokenKind::Identifier );
            continue;
        }
        const std::size_t opLen = munchMultiByteOperators ? multiByteOperatorLen( src, i, n ) : std::size_t( 0 );
        const std::size_t len   = opLen != 0 ? opLen : std::size_t( 1 );
        sink( std::string_view( src.data() + i, len ), CodeTokenKind::Punctuation );
        i += len;
    }
}

// The --clones PROJECTION of a scanned token: identity erased, control flow kept. One statement of the
// mapping, so the joined-string and vector forms below cannot drift apart. A declarative table indexed by
// the kind, not a switch chain (CONTRIBUTING.md §3) — an EMPTY row means "keep the token verbatim", which is
// what keywords and punctuation do. Row order is the CodeTokenKind declaration order; the static_assert is
// what makes reordering the enum a compile error rather than a silent re-mapping of $I onto $N.
inline constexpr std::string_view kCloneNormalForms[] = { "$I", "", "$N", "$S", "" };
static_assert( std::size( kCloneNormalForms ) == std::size_t( CodeTokenKind::Punctuation ) + 1,
               "kCloneNormalForms must carry exactly one row per CodeTokenKind, in declaration order" );

inline std::string_view cloneNormalizedForm( std::string_view token, CodeTokenKind kind ) noexcept
{
    const std::string_view form = kCloneNormalForms[ std::size_t( kind ) ];
    return form.empty() ? token : form;
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
    scanCodeTokens( src, a, b, stripHashComments, false,
                    [ & ]( std::string_view token, CodeTokenKind kind )
                    {
                        out += cloneNormalizedForm( token, kind );
                        out += ' ';
                        ++tokenCount;
                    } );
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
    scanCodeTokens( src, a, b, stripHashComments, false,
                    [ & ]( std::string_view token, CodeTokenKind kind )
                    {
                        out.emplace_back( cloneNormalizedForm( token, kind ) );
                    } );
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
    const SymbolsByFile byFile = symbolsByFileInIdOrder(
        ing, []( const Symbol& s ) { return ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && s.endByte > s.sigEndByte; } );

    // normalized body → member symbol ids. N=2 is FREE: rw::svector<NodeId,1> and <NodeId,2> are both 16 B
    // (the union's inline array can never be smaller than the heap pointer it shares storage with), so the
    // second slot costs nothing and lifts inline coverage from 97.8%/94.9% to 99.5%/98.8% across the two
    // census corpora. Almost every distinct body is unique — the whole point of the pass is that the rare
    // key with ≥2 members is a clone — so this replaces ~2.4K/7.2K one-element heap blocks with none.
    HashMap<std::string, rw::SmallVec<NodeId, 2>> groups;
    HashMap<NodeId, std::uint32_t>                tok;   // symbol → token count (for ranking)
    std::string bytes;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        if( byFile[f].empty() )
        {
            continue;
        }
        std::FILE* fp = std::fopen( diskPath( ing, std::uint32_t( f ) ).c_str(), "rb" );
        if( !fp )
        {
            continue;
        }
        std::fseek( fp, 0, SEEK_END );
        const long sz = std::ftell( fp );
        std::fseek( fp, 0, SEEK_SET );
        bytes.clear();
        if( sz > 0 )
        {
            bytes.resize( std::size_t( sz ) );
            if( std::fread( bytes.data(), 1, std::size_t( sz ), fp ) != std::size_t( sz ) )
            {
                bytes.clear();
            }
        }
        std::fclose( fp );
        if( bytes.empty() )
        {
            continue;
        }

        for( NodeId id : byFile[f] )
        {
            const Symbol& s = ing.symbols[id];
            std::uint32_t tc = 0;
            const bool    hash = usesHashLineComments( s.lang );   // `#` line comments
            std::string   norm = normalizeSpan( bytes, s.sigEndByte, s.endByte, tc, hash );   // the BODY only [sigEndByte,endByte)
            if( int( tc ) < minTokens )
            {
                continue;
            }
            tok[id] = tc;
            groups[ std::move( norm ) ].push_back( id );
        }
    }

    std::vector<CloneGroup> out;
    for( auto& [norm, members] : groups )
    {
        if( members.size() >= 2 )
        {
            // CloneGroup::members stays a std::vector — it is the RETURNED type, read by four verbs and by
            // quality.h, and it is materialized only for the ≥2-member groups (2.2%/1.1% of keys), so the
            // one allocation per emitted group is not what this conversion was about.
            out.push_back( { std::vector<NodeId>( members.begin(), members.end() ), tok[members[0]] } );
        }
    }
    std::sort( out.begin(), out.end(), [ & ]( const CloneGroup& x, const CloneGroup& y ) { // biggest clones first; stable tiebreak by first member's file:line
        if( x.tokens != y.tokens )
        {
            return x.tokens > y.tokens;
        }
        const Symbol& sx = ing.symbols[x.members[0]];
        const Symbol& sy = ing.symbols[y.members[0]];
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
    for( std::uint32_t j = 0; j < kSketchHashes; ++j )
    {
        m[j] = sketchSplitmix64( j + 1 ) | 1ull; // odd ⇒ bijective multiply mod 2^64
    }
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
            if( h < mn )
            {
                mn = h;
            }
        }
        sig[j] = std::uint8_t( mn );
    }
}

// matching-component count of two sketches — the pre-gate's whole per-pair cost (auto-vectorizes to byte lanes).
inline std::uint32_t cloneSketchMatches( const std::uint8_t* a, const std::uint8_t* b ) noexcept
{
    std::uint32_t m = 0;
    for( std::uint32_t j = 0; j < kSketchHashes; ++j )
    {
        m += std::uint32_t( a[j] == b[j] );
    }
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
    for( const char c : t )
    {
        h = hashutil::fnv1aAbsorb( h, c );
    }
    h ^= 0x9e3779b97f4a7c15ull;  h = hashutil::fnv1aMultiply( h );   // token separator so [ab][c] != [a][bc]
    return h;
}

// LCS length of two token-ID sequences via rolling two-row DP. O(|a|·|b|) time, O(min) space. Comparing interned
// u32 ids (A4-P2) instead of std::string cells makes each DP cell a scalar compare. Sequences are clamped to
// kType3MaxTokensForLcs by the caller so this stays a bounded constant per pair.
inline std::size_t cloneLcsLen( const std::vector<std::uint32_t>& a, const std::vector<std::uint32_t>& b )
{
    const std::size_t na = a.size(), nb = b.size();
    if( na == 0 || nb == 0 )
    {
        return 0;
    }
    std::vector<std::uint32_t> prev( nb + 1, 0 ), cur( nb + 1, 0 );
    for( std::size_t i = 1; i <= na; ++i )
    {
        for( std::size_t j = 1; j <= nb; ++j )
        {
            cur[j] = ( a[i - 1] == b[j - 1] ) ? prev[j - 1] + 1 : std::max( prev[j], cur[j - 1] );
        }
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
    const SymbolsByFile byFile = symbolsByFileInIdOrder(
        ing, []( const Symbol& s ) { return ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && s.endByte > s.sigEndByte; } );

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
        if( byFile[f].empty() )
        {
            continue;
        }
        std::FILE* fp = std::fopen( diskPath( ing, std::uint32_t( f ) ).c_str(), "rb" );
        if( !fp )
        {
            continue; // degrade: unreadable file just contributes no candidates (never a crash)
        }
        std::fseek( fp, 0, SEEK_END );
        const long sz = std::ftell( fp );
        std::fseek( fp, 0, SEEK_SET );
        bytes.clear();
        if( sz > 0 )
        {
            bytes.resize( std::size_t( sz ) );
            if( std::fread( bytes.data(), 1, std::size_t( sz ), fp ) != std::size_t( sz ) )
            {
                bytes.clear();
            }
        }
        std::fclose( fp );
        if( bytes.empty() )
        {
            continue;
        }

        for( NodeId id : byFile[f] )
        {
            const Symbol&            s    = ing.symbols[id];
            const bool               hash = usesHashLineComments( s.lang );
            std::vector<std::string> raw  = normalizeTokens( bytes, s.sigEndByte, s.endByte, hash );
            if( int( raw.size() ) < minTokens )
            {
                continue;
            }

            // dedup exact streams: hash the joined token TEXT (byte-identical to the pre-A4-P2 hash); keep only the
            // first id per distinct stream. Done over `raw` so the exact-dedup equivalence classes never shift.
            std::uint64_t sh = 1469598103934665603ull;
            for( const std::string& t : raw )
            {
                for( const char c : t )
                {
                    sh = hashutil::fnv1aAbsorb( sh, c );
                }
                sh ^= 0x2full;
                sh = hashutil::fnv1aMultiply( sh );
            }
            if( streamSeen.find( sh ) != streamSeen.end() )
            {
                continue; // exact clone of an earlier candidate → skip (Type-1/2)
            }
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
                    for( std::uint32_t k = 0; k < kFpGram; ++k )
                    {
                        g = cloneTokenHash( raw[i + k], g );
                    }
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
    //
    // N=4, and the census' N=8 OVERSHOOTS — this is the one place in the wave where more inline slots make
    // total memory WORSE, because the payload is concentrated in a handful of huge buckets (max 1 423/2 986)
    // while the COUNT is dominated by tiny ones. Coverage by N over the two census corpora:
    //     N :   1     2     4     8    16          instance bytes: 16 16 24 40 72
    //   here: 48.3  63.6  76.1  84.8  90.8
    //   cr48: 39.9  55.0  68.1  78.6  86.6
    // Marginal coverage per byte is 1.57/1.64 going 2→4 and 0.54/0.66 going 4→8 — a 2.6-2.9x cliff, the
    // knee. Above it the header array grows faster than the heap blocks it saves: at 53 127 buckets, N=8
    // adds 850 KB of inline slots to spare ~225 KB of heap, so total footprint is ~5.1 MB against N=4's
    // ~4.5 MB (std::vector today: ~5.3 MB). N=4 is also exactly the 24 bytes a std::vector header already
    // costs, so the array itself does not grow at all and two thirds of the heap blocks simply stop.
    HashMap<std::uint64_t, rw::SmallVec<std::uint32_t, 4>> buckets;
    for( std::uint32_t ci = 0; ci < cands.size(); ++ci )
    {
        for( std::uint64_t g : cands[ci].fp )
        {
            buckets[g].push_back( ci );
        }
    }

    // Enumerate candidate PAIRS via co-occurrence in any bucket; de-dup pairs with a seen-set.
    HashMap<std::uint64_t, std::uint8_t> pairSeen;
    std::vector<CloneGroup>              out;
    std::size_t                          comparedPairs = 0;
    const auto pairKey = []( std::uint32_t x, std::uint32_t y ) noexcept
    { return ( std::uint64_t( x ) << 32 ) | std::uint64_t( y ); };

    for( auto& [g, idxs] : buckets )
    {
        (void)g;
        if( idxs.size() < 2 )
        {
            continue;
        }
        // Stop-gram cut (A4-P2): a bucket bigger than kType3MaxBucket is a ubiquitous k-gram — O(size²) pairs of
        // pure boilerplate. Skip it; any real near-clone in it shares a rarer gram and is compared via a smaller
        // bucket. Fixed threshold + this is before any per-pair work, so the decision is fully deterministic.
        if( idxs.size() > kType3MaxBucket )
        {
            continue;
        }
        std::sort( idxs.begin(), idxs.end() );   // deterministic pair enumeration within the bucket
        for( std::size_t a = 0; a < idxs.size(); ++a )
        {
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
                if( hi == 0 || float( lo ) / float( hi ) < kType3LenBand )
                {
                    continue;
                }

                // De-dup the length-band survivors (once per distinct pair) + charge the deterministic cap. `pairSeen`
                // is insertion-order-free (pure membership) and the bucket walk is insertion-ordered + idx-sorted, so
                // the kept/dropped split on a cap-hitting corpus is fully deterministic.
                const std::uint64_t pk = pairKey( ia, ib );
                if( pairSeen.find( pk ) != pairSeen.end() )
                {
                    continue;
                }
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
                        else if( ca.fp[i] < cb.fp[j] ) { ++i; }
                        else
                        {
                            ++j;
                        }
                    }
                }
                const std::size_t uni = ca.fp.size() + cb.fp.size() - inter;
                if( uni == 0 || float( inter ) / float( uni ) < kType3MinFpJaccard )
                {
                    continue;
                }

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
                if( den == 0 )
                {
                    continue;
                }
                const float sim = 2.0f * float( lcs ) / float( den );
                if( sim < kType3MinSimilarity || sim >= 1.0f )
                {
                    continue; // < 1.0: exact would be Type-1/2
                }

                // member order stable by symbol id (small id first) → deterministic emit.
                const NodeId x = std::min( ca.id, cb.id ), y = std::max( ca.id, cb.id );
                out.push_back( { { x, y }, std::max( candTokens[ia], candTokens[ib] ), std::uint8_t( 3 ), sim } );
            }
        }
    }
done:
    // Deterministic order: by (first member id, second member id). Similarity is a pure function of the streams,
    // so ties are impossible for a fixed pair; the id sort fully determines the sequence.
    std::sort( out.begin(), out.end(), []( const CloneGroup& p, const CloneGroup& q )
               { return p.members[0] != q.members[0] ? p.members[0] < q.members[0] : p.members[1] < q.members[1]; } );
    st.emittedPairs = out.size();
    if( statsOut )
    {
        *statsOut = st;
    }
    return out;
}


// ── P0-6: from PAIRS to GROUPS, and the corpus duplication percentage ────────────────────────────────
//
// WHY. The detector's output shape is a lie of omission at the reporting layer. findClones() returns real
// groups, but findClonesType3() returns PAIRS by construction — three functions that are all near-copies of
// each other come out as three rows of two, and a reader counting rows concludes there are three separate
// duplication problems instead of one cluster of three. Union-find over the pair graph recovers the cluster
// (every row gets the id of the component it belongs to), and once components exist the corpus can be
// priced: how much of this codebase is redundant?
//
// THE DEFINITION, because a percentage without one is a number nobody can act on:
//
//   duplicated LOC  = Σ over components of ( Σ member loc − max member loc )
//   total LOC       = Σ loc over every symbol the DETECTOR considered (function/method with a real body)
//   dup_pct         = 100 × duplicated / total
//
// The per-component rule — "all members except the largest one" — is the deliberate choice the brief asks
// to be disclosed. A 3-clone group counts its LOC TWICE, not once and not three times: one instance is the
// code you would keep, the other two are the redundancy. Counting all three would say a corpus that is one
// function copied twice is 100% duplicated, which is not a number anyone can reduce; counting one would
// price a 3-way clone the same as a 2-way. The largest member is the representative (the most conservative
// choice: it minimises the reported redundancy).
//
// A symbol reachable from several clone relations lands in ONE component by construction, so no LOC is
// double-counted and duplicated ≤ total always holds.
//
// FLOOR, not total. The Type-3 pair list is capped upstream (kType3MaxPairs) and the per-file candidate
// walk is prefiltered, so a dropped pair is a component that did not get merged and a percentage that is
// too LOW. Every derived count here is a floor; the emitter labels it counts_floor="1".
//
// Deterministic: components are numbered by their smallest member id ascending, and members are collected
// by an ascending id sweep — no hash-map iteration reaches the result.
struct CloneGrouping
{
    std::vector<std::uint32_t> gidOfGroup;              // parallel to the caller's flat row stream (type-1/2 rows, then type-3 rows)
    std::uint32_t              componentCount = 0;      // distinct clone clusters (a FLOOR — see above)
    std::uint64_t              duplicatedLoc  = 0;      // redundant physical lines (a FLOOR)
    std::uint64_t              totalLoc       = 0;      // physical lines in the detector's own universe
};

// dup_pct as the emitter prints it: 0.0 when there is nothing to divide (a real zero — "none found").
inline double cloneDuplicationPercent( const CloneGrouping& gp ) noexcept
{
    return gp.totalLoc == 0 ? 0.0 : 100.0 * double( gp.duplicatedLoc ) / double( gp.totalLoc );
}

// `exact` = findClones() output, `gapped` = findClonesType3() output; gidOfGroup comes back in that same
// concatenated order, which is the order --clones emits rows in.
inline CloneGrouping groupClones( const IngestResult& ing, const std::vector<CloneGroup>& exact, const std::vector<CloneGroup>& gapped )
{
    CloneGrouping out;
    out.gidOfGroup.assign( exact.size() + gapped.size(), 0u );

    // The detector's own universe — the SAME predicate findClones/findClonesType3 filter candidates with, so
    // the denominator can never include code the numerator was never allowed to look at.
    for( const Symbol& s : ing.symbols )
    {
        if( ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && s.endByte > s.sigEndByte )
        {
            out.totalLoc += s.loc;
        }
    }

    const std::uint32_t symbolCount = static_cast<std::uint32_t>( ing.symbols.size() );
    if( symbolCount == 0 || out.gidOfGroup.empty() )
    {
        return out;
    }

    // union-find over symbol ids: flat u32 parent array, path-halving find, union-by-smaller-root so the
    // representative of a component is always its smallest member (which is also the numbering key below).
    std::vector<std::uint32_t> parent( symbolCount );
    for( std::uint32_t i = 0; i < symbolCount; ++i )
    {
        parent[i] = i;
    }
    const auto find = [ & ]( std::uint32_t x )
    {
        while( parent[x] != x )
        {
            parent[x] = parent[ parent[x] ];
            x         = parent[x];
        }
        return x;
    };
    const auto unite = [ & ]( std::uint32_t a, std::uint32_t b )
    {
        const std::uint32_t ra = find( a ), rb = find( b );
        if( ra == rb )
        {
            return;
        }
        // smaller root wins ⇒ root == min member id
        if( ra < rb ) { parent[rb] = ra; } else { parent[ra] = rb; }
    };
    const auto uniteGroup = [ & ]( const CloneGroup& gp )
    {
        for( std::size_t m = 1; m < gp.members.size(); ++m )
        {
            if( gp.members[m] < symbolCount && gp.members[0] < symbolCount )
            {
                unite( gp.members[0], gp.members[m] );
            }
        }
    };
    for( const CloneGroup& gp : exact )
    {
        uniteGroup( gp );
    }
    for( const CloneGroup& gp : gapped )
    {
        uniteGroup( gp );
    }

    // Number the components that a clone relation actually touched, by smallest member id ascending. An
    // ascending sweep over ids means the numbering is a pure function of the graph, not of iteration order.
    std::vector<std::uint32_t> denseIdOfRoot( symbolCount, UINT32_MAX );
    std::vector<char>          inClone( symbolCount, 0 );
    const auto markGroup = [ & ]( const CloneGroup& gp )
    {
        for( NodeId id : gp.members )
        {
            if( id < symbolCount )
            {
                inClone[id] = 1;
            }
        }
    };
    for( const CloneGroup& gp : exact )
    {
        markGroup( gp );
    }
    for( const CloneGroup& gp : gapped )
    {
        markGroup( gp );
    }

    std::vector<std::uint64_t> sumLocOfDense, maxLocOfDense;
    for( std::uint32_t id = 0; id < symbolCount; ++id )
    {
        if( !inClone[id] )
        {
            continue;
        }
        const std::uint32_t root = find( id );
        if( denseIdOfRoot[root] == UINT32_MAX )
        {
            denseIdOfRoot[root] = static_cast<std::uint32_t>( sumLocOfDense.size() );
            sumLocOfDense.push_back( 0 );
            maxLocOfDense.push_back( 0 );
        }
        const std::uint32_t dense = denseIdOfRoot[root];
        const std::uint64_t loc   = ing.symbols[id].loc;
        sumLocOfDense[dense] += loc;
        maxLocOfDense[dense] = std::max( maxLocOfDense[dense], loc );
    }
    out.componentCount = static_cast<std::uint32_t>( sumLocOfDense.size() );
    for( std::size_t d = 0; d < sumLocOfDense.size(); ++d )
    {
        out.duplicatedLoc += sumLocOfDense[d] - maxLocOfDense[d];   // every copy but the representative
    }

    // Finally, the per-ROW ids, in the emitter's own row order.
    for( std::size_t i = 0; i < exact.size(); ++i )
    {
        out.gidOfGroup[i] = exact[i].members.empty() ? 0u : denseIdOfRoot[ find( exact[i].members[0] ) ];
    }
    for( std::size_t i = 0; i < gapped.size(); ++i )
    {
        out.gidOfGroup[ exact.size() + i ] = gapped[i].members.empty() ? 0u : denseIdOfRoot[ find( gapped[i].members[0] ) ];
    }
    return out;
}

}   // namespace rw
