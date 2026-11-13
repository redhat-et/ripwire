#pragma once

// clones.h — token-normalized duplicate detection (--clones), function/method level. The CCFinder/PMD-CPD
// idea: normalize each body to a token stream (identifiers → $I, literals →
// $N/$S, keywords + operators + punctuation kept), then group functions with identical normalized streams.
// Catches Type-1 (exact) and Type-2 (renamed-variable) clones. Agent value: "this already exists — reuse
// it, don't reimplement" (and "if you fix this, fix its twins"). Type-3 (gapped) clones are a later upgrade.

#include "model.h"
#include "infra/Diagnostics.h"  // DISCLOSE — graceful-degrade on the Type-3 pair-cap guard (never throw)
#include "infra/hashutil.h"     // sanitizer-clean modulo-2^64 FNV multiplication

#include <algorithm>
#include <array>
#include <atomic>       // gType3PassRuns / gType3PassPairs — the QD-ENVOY-TIME cost-bound counters
#include <bit>          // std::popcount — CloneLcsBits counts the zero bits of its DP vector
#include <cctype>
#include <cstdint>
#include <cstdlib>      // std::getenv — RIPWIRE_LCS_VERIFY
#include <span>         // cloneLcsLen — a clamped token run is a view, not a copy
#include <limits>       // std::numeric_limits — the mask-width static_assert: an index shifted into a mask must fit it
#include <cstdio>
#include <string>
#include <utility>      // std::forward — the C-family scanCodeTokens spelling hands its sink to the CodeScanOptions one
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
// SHIFT WIDTH vs ENUM COUNT. A shift by a value at or past the mask's width is undefined behaviour, and the language
// masks are shifted by a Lang at RUNTIME (usesHashLineComments below, lintcatalog.h's corpusLangMask), where no
// constant evaluation refuses it. So the count every such mask is built over is pinned to the mask type's width: a
// 33rd language is a build error here, beside the shift, not UB in a lens. (A Lang byte past the enum from a corrupt
// cache is the cache reader's to refuse; this is the bound for every value the enum can name.)
static_assert( kLangCount <= std::numeric_limits<decltype( langBit( Lang::Cpp ) )>::digits,
               "Lang outgrew the 32-bit language masks (langBit, kHashLineCommentLangMask, LintCatalogRow::langMask) — widen them" );
// Toml and Yaml belong here and Json/Markdown deliberately do not: `#` opens a real line comment in TOML
// and YAML alike, whereas
// JSON has no comment syntax at all and markdown's `#` is a heading. The distinction is load-bearing rather
// than cosmetic — the loop below runs over EVERY symbol in a file with no SymKind filter, so a TOML/YAML
// t="sec"
// body reaches normalizeSpan/scanCodeTokens exactly like a function body, and a `#`-blind scan would tokenize
// a table's comments as content and let two unrelated tables clone-match on their prose.
// PHP joins them: `#` is one of PHP's THREE comment openers (`//`, `#`, `/* */`), and a `#`-blind scan
// would tokenize `# TODO` lines as body content. Lua deliberately does NOT: its line comment is `--`,
// and `#t` is the LENGTH operator on a real expression — masking it in would delete live code from the
// normalized span and manufacture clone matches. (Lua's `--` opener is not modelled here at all; that is
// a disclosed floor of the clone lens for Lua, in the safe direction — comments count as content, so two
// bodies must agree on their COMMENTS too before they clone-match, which can only ever miss a clone.)
// Kotlin is not in this mask: its line comment is `//`, handled unconditionally by the scanner below.
inline constexpr std::uint32_t kHashLineCommentLangMask = langBit( Lang::Python ) | langBit( Lang::Bash ) | langBit( Lang::Ruby ) | langBit( Lang::Toml ) | langBit( Lang::Yaml )
                                                       | langBit( Lang::Php ) | langBit( Lang::Elixir ) | langBit( Lang::GDScript );
static_assert( kLangCount <= std::numeric_limits<decltype( kHashLineCommentLangMask )>::digits,
               "Lang outgrew a 32-bit mask — widen kHashLineCommentLangMask" );

// Is `lang`'s bit set in a langBit mask? One shift and one AND, the form every mask predicate below shares (so the
// second predicate did not land as a 29-token clone of the first, which --quality-delta named when it did).
inline constexpr bool langInMask( std::uint32_t mask, Lang lang ) noexcept { return ( ( mask >> std::uint32_t( lang ) ) & std::uint32_t( 1 ) ) != 0; }

inline bool usesHashLineComments( Lang lang ) noexcept { return langInMask( kHashLineCommentLangMask, lang ); }

// Languages whose `'` opens a STRING literal (CodeScanOptions::singleQuoteStrings), not a char literal: the three the
// builtin-method name gate has a table for (graph.h BuiltinMethodGate::tableFor), which is the one consumer that asks.
// Only Python is exercised today (the gate's same-file rule is Python-only; test/commenttokencheck.sh A-I); the JS-family
// and Ruby rows are the lexical fact, kept so a later extension of that rule cannot scan `'…'` as code by omission. Not
// in this mask, deliberately: C/C++/Java/Rust (char literals), and every language the clone/readability lenses scan,
// whose normalized streams must keep their bytes.
inline constexpr std::uint32_t kSingleQuoteStringLangMask = langBit( Lang::Python ) | langBit( Lang::Ruby ) | langBit( Lang::JavaScript ) | langBit( Lang::TypeScript );
static_assert( kLangCount <= std::numeric_limits<decltype( kSingleQuoteStringLangMask )>::digits,
               "Lang outgrew a 32-bit mask — widen kSingleQuoteStringLangMask" );

inline bool usesSingleQuoteStrings( Lang lang ) noexcept { return langInMask( kSingleQuoteStringLangMask, lang ); }

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
// singleQuoteStrings (CodeScanOptions): OFF (every C-family consumer) keeps the `'` branch below — a char literal with a
// plausible close, else punctuation. ON, a `'` opens a STRING that runs to the next unescaped `'`, exactly as `"` does,
// because in Python, Ruby and the JS family `'…'` IS a string: with it off, `'Pool warm'` scans as `'` `Pool` `warm` `'`
// and the words inside a log message count as code. An f-string's `{…}` is string content here (the graph.h consumer reads
// the fields itself, StringTokenPosition::isFormatString).
//
// tripleQuoteStrings (CodeScanOptions): OFF (the default) reads `"""` as `""` then `"` — a quote INSIDE the triple would then
// close the string early and flip code and string for the rest of the span. ON, a `"""` or `'''` opens one STRING that runs
// to the matching closing triple, as Python reads it, so an apostrophe or a lone `"` inside a docstring stays string
// content (commenttokencheck arm Q). The one consumer is graph.h identifierTokenCountExceeds, for Python.
//
// slashComments (CodeScanOptions): ON (every C-family consumer, and the default) drops `//`-to-EOL and `/* … */` as
// comments. OFF keeps them as punctuation, because in Python `//` is floor division: `n = total // 2; kind = Pool` must
// not lose the rest of its line (commenttokencheck arm P). The one consumer that turns it off is the same graph.h count,
// for Python (PHP has `#` AND `//` comments, so the `#`-comment mask is not the right switch).
//
// `sink( std::string_view token, CodeTokenKind kind )` is called once per token, in source order.
struct CodeScanOptions
{
    bool stripHashComments       = false;   // `#` to EOL is a comment (usesHashLineComments)
    bool munchMultiByteOperators = false;   // longest match from kMultiByteOperators (the --readability shape)
    bool singleQuoteStrings      = false;   // `'` opens a string literal, not a char literal (Python, Ruby, the JS family)
    bool slashComments           = true;    // `//` to EOL and `/* … */` are comments (off: Python's `//` is floor division)
    bool tripleQuoteStrings      = false;   // `"""…"""` / `'''…'''` is one string to its closing triple (Python)
};

// The scanner options for `lang`'s comment and string rules, in ONE place (the two consumers that read string literals spelled the
// same five fields: graph.h identifierTokenCountExceeds, forcallerhop.h forBodyHoldsTaskMessage). Python: `//` is floor division, not a
// comment, and `"""`/`'''` open one triple-quoted string; `#` comments and `'` strings per the two language masks above.
inline CodeScanOptions stringAwareScanOptions( Lang lang, bool munchMultiByteOperators ) noexcept
{
    return CodeScanOptions{ .stripHashComments = usesHashLineComments( lang ), .munchMultiByteOperators = munchMultiByteOperators,
                            .singleQuoteStrings = usesSingleQuoteStrings( lang ), .slashComments = lang != Lang::Python,
                            .tripleQuoteStrings = lang == Lang::Python };
}

template<typename Sink>
inline void scanCodeTokens( const std::string& src, std::size_t a, std::size_t b, CodeScanOptions options, Sink&& sink )
{
    const bool        stripHashComments       = options.stripHashComments;
    const bool        munchMultiByteOperators = options.munchMultiByteOperators;
    const std::size_t n = std::min<std::size_t>( b, src.size() );
    std::size_t       i = std::min<std::size_t>( a, n );
    const auto        idc = []( unsigned char c ) noexcept { return std::isalnum( c ) != 0 || c == '_'; };
    // a `"`-style string: from the opening quote to the next unescaped close (or the end of the span), one String token;
    // with tripleQuoteStrings, an opening `"""` runs to the next unescaped `"""`
    const auto        quoted = [ & ]( char quote )
    {
        const std::size_t begin  = i;
        const bool        triple = options.tripleQuoteStrings && i + 2 < n && src[i + 1] == quote && src[i + 2] == quote;
        const std::size_t width  = triple ? 3 : 1;
        i += width;
        while( i < n )
        {
            if( src[i] == '\\' )
            {
                i += 2;
                continue;
            }
            if( src[i] == quote && ( !triple || ( i + 2 < n && src[i + 1] == quote && src[i + 2] == quote ) ) )
            {
                break;
            }
            ++i;
        }
        i = std::min( n, i + width );
        sink( std::string_view( src.data() + begin, i - begin ), CodeTokenKind::String );
    };

    while( i < n )
    {
        const unsigned char c = static_cast<unsigned char>( src[i] );   // explicit: a raw char >=0x80 implicitly converting is the UBSan sign-change class (CI round 4 artifact)
        if( std::isspace( c ) != 0 )
        {
            ++i;
            continue;
        }
        if( options.slashComments && c == '/' && i + 1 < n && src[i + 1] == '/' )
        {
            i += 2;
            while( i < n && src[i] != '\n' )
            {
                ++i;
            }
            continue;
        }
        if( options.slashComments && c == '/' && i + 1 < n && src[i + 1] == '*' )
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
            quoted( '"' );
            continue;
        }
        if( c == '\'' && options.singleQuoteStrings )
        {
            quoted( '\'' );
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

// The C-family spelling every --clones / --readability / --comment-coherence / --clone-idiom call site uses: `'` stays a
// char literal. The two flags map onto CodeScanOptions in declaration order; nothing else differs.
template<typename Sink>
inline void scanCodeTokens( const std::string& src, std::size_t a, std::size_t b, bool stripHashComments,
                            bool munchMultiByteOperators, Sink&& sink )
{
    scanCodeTokens( src, a, b, CodeScanOptions{ stripHashComments, munchMultiByteOperators, false }, std::forward<Sink>( sink ) );
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

// CLONES-PERSIST: the exact-clone KEY of one body, packed in one u64 so the cache can carry it per Function/Method def
// and a warm findClones groups bodies with no file I/O. High 40 bits: FNV-1a over the SAME byte stream normalizeSpan
// builds (each normalized form plus its ' '), top bit forced so a computed key is never kCloneKeyNone; low 24 bits:
// the token count, SATURATING at 2^24-1 (a floor the minTokens test can still pass; the verify step re-counts).
// Equal normalized strings give equal keys, so grouping by key yields a SUPERSET of every true clone group;
// findClones then re-reads only the members of keys with >= 2 bodies and compares the real strings, so a hash
// collision can never print a false clone.
inline constexpr unsigned      kCloneKeyTokenBits = 24;
inline constexpr std::uint64_t kCloneKeyTokenMask = ( std::uint64_t( 1 ) << kCloneKeyTokenBits ) - 1;
inline constexpr std::uint64_t kCloneKeyNone      = 0;   // not computed (old record, keyless def, oversized body)

inline std::uint32_t cloneKeyTokens( std::uint64_t key ) noexcept
{
    return std::uint32_t( key & kCloneKeyTokenMask );
}

inline std::uint64_t cloneBodyKey( const std::string& src, std::uint32_t a, std::uint32_t b, bool stripHashComments )
{
    std::uint64_t hash   = 14695981039346656037ull;   // FNV-1a 64 offset basis
    std::uint64_t tokens = 0;
    scanCodeTokens( src, a, b, stripHashComments, false,
                    [ & ]( std::string_view token, CodeTokenKind kind )
                    {
                        for( const char c : cloneNormalizedForm( token, kind ) )
                        {
                            hash = hashutil::fnv1aAbsorb( hash, c );
                        }
                        hash = hashutil::fnv1aAbsorb( hash, ' ' );
                        ++tokens;
                    } );
    const std::uint64_t tokenField = tokens < kCloneKeyTokenMask ? tokens : kCloneKeyTokenMask;   // saturates: findClones re-counts on verify
    return ( hash & ~kCloneKeyTokenMask ) | ( std::uint64_t( 1 ) << 63 ) | tokenField;
}

// Read one indexed file whole, the way both clone passes always have. false (and `bytes` empty) when it cannot be
// opened or read, or is empty: such a file contributes no bodies (never a crash).
inline bool readCloneSourceFile( const IngestResult& ing, std::uint32_t fileId, std::string& bytes )
{
    bytes.clear();
    std::FILE* fp = std::fopen( diskPath( ing, fileId ).c_str(), "rb" );
    if( !fp )
    {
        return false;
    }
    std::fseek( fp, 0, SEEK_END );
    const long sz = std::ftell( fp );
    std::fseek( fp, 0, SEEK_SET );
    if( sz > 0 )
    {
        bytes.resize( std::size_t( sz ) );
        if( std::fread( bytes.data(), 1, std::size_t( sz ), fp ) != std::size_t( sz ) )
        {
            bytes.clear();
        }
    }
    std::fclose( fp );
    return !bytes.empty();
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

// CLONES-PERSIST: findClones runs in two passes over flat arrays (no per-body string, no node map).
//   (1) KEY every candidate body: from ing.cloneKeys (written at ingest, carried by the cache) with no file I/O; a
//       body without a key (a def no parse worker keyed, an IngestResult built without the side array) reads its
//       file once and is keyed here.
//   (2) VERIFY: only bodies whose key is shared by >= 2 bodies (clone groups are ~2 % of keys) are re-read and their
//       real normalized strings compared, exactly as the one-pass detector compared them, so a key collision splits
//       into its true groups and never prints a false clone.
namespace clonepass
{
struct KeyRow
{
    std::uint64_t key;
    std::uint32_t seq;   // the one-pass detector's visiting order (file, then id): a group's member order
    NodeId        id;
};

struct VerifyRow
{
    std::uint32_t seq;
    std::uint32_t run;           // which shared key this body belongs to
    NodeId        id;
    std::uint32_t tokens = 0;
    bool          read   = false;   // false: the file could not be read now, or the body is under minTokens — no part
    std::string   norm;
};

// Pass 1. Same candidate set as the one-pass detector: a Function/Method with a real body region [sigEndByte,endByte)
// — this excludes prototypes AND the most-vexing-parse phantoms (block-scope `Type name(args);` variable decls the
// grammar shapes like a function declarator have no body, so sigEndByte==endByte). We compare the BODY, so
// same-implementation / different-name still matches.
inline std::vector<KeyRow> keyBodies( const IngestResult& ing, int minTokens )
{
    const SymbolsByFile byFile = symbolsByFileInIdOrder(
        ing, []( const Symbol& s ) { return ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && s.endByte > s.sigEndByte; } );
    const bool keysFit = ing.cloneKeys.size() == ing.symbols.size();
    std::vector<KeyRow> rows;
    std::string         bytes;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        bool loaded = false;
        bool ok     = false;
        for( NodeId id : byFile[f] )
        {
            std::uint64_t key = keysFit ? ing.cloneKeys[id] : kCloneKeyNone;
            if( key == kCloneKeyNone )
            {
                if( !loaded )
                {
                    ok     = readCloneSourceFile( ing, f, bytes );
                    loaded = true;
                }
                if( !ok )
                {
                    continue;
                }
                const Symbol& s = ing.symbols[id];
                key             = cloneBodyKey( bytes, s.sigEndByte, s.endByte, usesHashLineComments( s.lang ) );
            }
            // A saturated token field is a floor, not a count: keep the body for the verify step, which re-counts.
            const std::uint32_t keyTokens = cloneKeyTokens( key );
            if( keyTokens == kCloneKeyTokenMask || int( keyTokens ) >= minTokens )
            {
                rows.push_back( { key, std::uint32_t( rows.size() ), id } );
            }
        }
    }
    return rows;
}

// The rows of keys shared by >= 2 bodies, numbered by run (one run per shared key), in seq order.
inline std::vector<VerifyRow> sharedKeyRows( std::vector<KeyRow> rows )
{
    std::sort( rows.begin(), rows.end(), []( const KeyRow& x, const KeyRow& y ) { return x.key != y.key ? x.key < y.key : x.seq < y.seq; } );
    std::vector<VerifyRow> shared;
    std::uint32_t          runCount = 0;
    for( std::size_t i = 0; i < rows.size(); )
    {
        std::size_t j = i + 1;
        while( j < rows.size() && rows[j].key == rows[i].key )
        {
            ++j;
        }
        if( j - i >= 2 )
        {
            for( std::size_t k = i; k < j; ++k )
            {
                shared.push_back( { rows[k].seq, runCount, rows[k].id } );
            }
            ++runCount;
        }
        i = j;
    }
    std::sort( shared.begin(), shared.end(), []( const VerifyRow& x, const VerifyRow& y ) { return x.seq < y.seq; } );
    return shared;
}

// Pass 2's reads: in seq order, so each file is read once; fills norm/tokens/read.
inline void normalizeShared( const IngestResult& ing, int minTokens, std::vector<VerifyRow>& shared )
{
    std::string   bytes;
    std::uint32_t loadedFile = std::numeric_limits<std::uint32_t>::max();
    bool          fileOk     = false;
    for( VerifyRow& v : shared )
    {
        const Symbol& s = ing.symbols[v.id];
        if( s.fileId != loadedFile )
        {
            fileOk     = readCloneSourceFile( ing, s.fileId, bytes );
            loadedFile = s.fileId;
        }
        if( fileOk )
        {
            v.norm = normalizeSpan( bytes, s.sigEndByte, s.endByte, v.tokens, usesHashLineComments( s.lang ) );
            v.read = int( v.tokens ) >= minTokens;
        }
    }
}

// One shared key's rows [first, last) (seq order): split by the real normalized string, keep every split of >= 2.
inline void appendVerifiedGroups( const std::vector<VerifyRow>& shared, std::size_t first, std::size_t last, std::vector<CloneGroup>& out )
{
    std::vector<std::size_t>         heads;   // the first row of each distinct normalized string
    std::vector<std::vector<NodeId>> split;   // parallel to heads
    for( std::size_t k = first; k < last; ++k )
    {
        if( !shared[k].read )
        {
            continue;
        }
        std::size_t h = 0;
        while( h < heads.size() && shared[heads[h]].norm != shared[k].norm )
        {
            ++h;
        }
        if( h == heads.size() )
        {
            heads.push_back( k );
            split.emplace_back();
        }
        split[h].push_back( shared[k].id );
    }
    for( std::size_t h = 0; h < heads.size(); ++h )
    {
        if( split[h].size() >= 2 )
        {
            out.push_back( { std::move( split[h] ), shared[heads[h]].tokens } );
        }
    }
}

// Biggest clones first; tiebreak by first member's file:line, then its id (a total order: two groups never share a
// first member).
inline void sortGroups( const IngestResult& ing, std::vector<CloneGroup>& groups )
{
    std::sort( groups.begin(), groups.end(), [ & ]( const CloneGroup& x, const CloneGroup& y ) {
        if( x.tokens != y.tokens )
        {
            return x.tokens > y.tokens;
        }
        const Symbol& sx = ing.symbols[x.members[0]];
        const Symbol& sy = ing.symbols[y.members[0]];
        if( ing.files[sx.fileId] != ing.files[sy.fileId] )
        {
            return ing.files[sx.fileId] < ing.files[sy.fileId];
        }
        return sx.line != sy.line ? sx.line < sy.line : x.members[0] < y.members[0];
    } );
}
}   // namespace clonepass

// Find function/method bodies with identical normalized token streams (≥ minTokens, ≥2 members).
inline std::vector<CloneGroup> findClones( const IngestResult& ing, int minTokens )
{
    std::vector<clonepass::VerifyRow> shared = clonepass::sharedKeyRows( clonepass::keyBodies( ing, minTokens ) );
    clonepass::normalizeShared( ing, minTokens, shared );
    std::sort( shared.begin(), shared.end(), []( const clonepass::VerifyRow& x, const clonepass::VerifyRow& y ) { return x.run != y.run ? x.run < y.run : x.seq < y.seq; } );
    std::vector<CloneGroup> out;
    for( std::size_t i = 0; i < shared.size(); )
    {
        std::size_t j = i + 1;
        while( j < shared.size() && shared[j].run == shared[i].run )
        {
            ++j;
        }
        clonepass::appendVerifiedGroups( shared, i, j, out );
        i = j;
    }
    clonepass::sortGroups( ing, out );
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
//      QD-LCS runs it bit-parallel, n·⌈m/64⌉ word steps, and stops once the pair cannot reach the threshold;
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
    std::uint64_t lcsComputed    = 0;   // LCS DPs actually run (a cap re-run reuses the candidate walk's; never a parity counter)
    std::uint64_t partnersPeak   = 0;   // the candidate walk's largest partner list (distinct candidates: <= candidateCount)
    // RIPWIRE_LCS_VERIFY=1 only (test/lcsidentitycheck.sh): every LCS the pass ran, re-run by the plain DP and compared
    std::uint64_t lcsVerified         = 0;   // pairs compared against the plain DP
    std::uint64_t lcsVerifyExits      = 0;   // ... of which the fast path answered "below need" (the early exit)
    std::uint64_t lcsVerifyMismatches = 0;   // a kept length that differs, or an exit on a pair that reaches need
    bool          pairCapHit     = false;   // kType3MaxPairs fired: the pair list (and every count built on it) is a FLOOR

    // The DISCLOSE sink for the pass's one degrade. Until 2026-09-24 the cap used the one-argument DISCLOSE, whose
    // trace compiles out under NDEBUG, so a shipped binary that hit the cap said nothing, while --clones printed
    // counts_floor="1" on every run whether or not the cap fired. The sink records it; the emitters read pairCapHit.
    enum class DisclosureWhy : std::uint8_t
    {
        PairCapHit,
    };
    void disclose( DisclosureWhy why ) noexcept
    {
        switch( why )
        {
            case DisclosureWhy::PairCapHit: pairCapHit = true; break;
        }
    }
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
//
// T3-LCS (QD-ENVOY-TIME): the two rows are the CALLER's scratch, grown once per pass instead of allocated per pair,
// and the per-row refill is gone. It was dead work: column 0 of every row is 0 and never written, and columns 1..nb
// of the row about to be filled are all overwritten before any is read (cell j reads only the previous row and
// cell j-1 of its own row). The rows swap as pointers; the result is the same value cell for cell.
//
// QD-LCS early exit: `need` > 0 asks only "does the LCS reach `need`?". Row i's last cell is LCS(a[0..i], b), and each
// later row adds at most 1, so once that cell plus the rows left is below `need` the answer is no, and the DP stops
// and returns that bound (a value below `need`). A pair that reaches `need` never stops early and gets its exact
// length. `need` = 0 (the default) is the plain DP.
inline std::size_t cloneLcsLen( std::span<const std::uint32_t> a, std::span<const std::uint32_t> b, std::vector<std::uint32_t>& prevRow,
                                std::vector<std::uint32_t>& curRow, std::size_t need = 0 )
{
    const std::size_t na = a.size(), nb = b.size();
    if( na == 0 || nb == 0 )
    {
        return 0;
    }
    if( std::min( na, nb ) < need )
    {
        return std::min( na, nb );
    }
    prevRow.assign( nb + 1, 0 );
    curRow.assign( nb + 1, 0 );
    std::uint32_t*       prev = prevRow.data();
    std::uint32_t*       cur  = curRow.data();
    const std::uint32_t* bs   = b.data();
    for( std::size_t i = 0; i < na; ++i )
    {
        const std::uint32_t ai = a[i];
        for( std::size_t j = 1; j <= nb; ++j )
        {
            cur[j] = ( ai == bs[j - 1] ) ? prev[j - 1] + 1 : std::max( prev[j], cur[j - 1] );
        }
        std::swap( prev, cur );
        const std::size_t reach = prev[nb] + ( na - 1 - i );   // the most the LCS can still reach
        if( reach < need )
        {
            return reach;
        }
    }
    return prev[nb];
}

// The early exit's `need` for a pair whose ratio denominator is `den` (= |a| + |b|): ceil(0.4·den) less one. A kept pair
// has 2·LCS/den ≥ kType3MinSimilarity (0.8), so LCS ≥ ceil(0.4·den); the one-token margin keeps the exit clear of float
// rounding (the global profile builds with -ffast-math), since a length two below that ceiling is at least 2/den under
// the threshold. Integer arithmetic only, so it is the same on every compiler.
inline std::size_t type3LcsNeed( std::size_t den ) noexcept
{
    static_assert( kType3MinSimilarity == 0.80f, "type3LcsNeed hard-codes the 0.8 ratio as 2/5" );
    const std::size_t ceilTwoFifths = ( 2 * den + 4 ) / 5;
    return ceilTwoFifths == 0 ? 0 : ceilTwoFifths - 1;
}

// QD-LCS bit-parallel: the LCS length of `a` against many `b`s, 64 DP cells per machine word (Allison-Dix 1986, in the
// form of Hyyrö 2004, "Bit-parallel LCS-length computation revisited"). load(a) builds one match mask per distinct token
// of a: bit k is set where a[k] is that token. lcs(b) then keeps one bit vector V over a's positions, all ones at the
// start, and for each token of b updates
//     U = V & M[token];   V = (V + U) | (V & ~M[token])
// where the add carries across words. After the last token the LCS is the number of zero bits in V's low |a| bits. A
// token of b that a does not hold leaves V unchanged, so its row costs one table load. The answer equals cloneLcsLen's
// cell for cell; test/lcsidentitycheck.sh checks both against an independent DP on a fuzz set and on real pairs.
//
// Built for the Type-3 pair walk, where one candidate meets every partner in turn: the walk loads a candidate once and
// runs every partner against its masks. The slot table is indexed by token id (the pass interns ids densely), grows to
// the largest id seen and is cleared through the list of ids a load touched, so a load costs O(|a|) and no hashing.
//
// `need` has cloneLcsLen's contract: an answer ≥ need is exact, and once the LCS cannot reach `need` the scan stops and
// returns a bound below it. The bound after j tokens of b is zeros(V) + (|b| - j), and it falls by at most one per token,
// so it is counted (a popcount pass) only at the first token where it could have fallen below `need`, not every row.
class CloneLcsBits
{
public:
    void load( std::span<const std::uint32_t> a )
    {
        for( const std::uint32_t t : used_ )
        {
            slot_[t] = 0;
        }
        used_.clear();
        masks_.clear();
        size_  = a.size();
        words_ = ( size_ + 63 ) / 64;
        for( std::size_t k = 0; k < size_; ++k )
        {
            const std::uint32_t t = a[k];
            if( t >= slot_.size() )
            {
                slot_.resize( std::size_t( t ) + 1, 0 );
            }
            if( slot_[t] == 0 )
            {
                used_.push_back( t );
                slot_[t] = std::uint32_t( used_.size() );
                masks_.resize( masks_.size() + words_, 0 );
            }
            masks_[ ( slot_[t] - 1 ) * words_ + k / 64 ] |= std::uint64_t( 1 ) << ( k % 64 );
        }
    }

    std::size_t lcs( std::span<const std::uint32_t> b, std::size_t need = 0 )
    {
        const std::size_t nb       = b.size();
        const std::size_t shortest = std::min( size_, nb );
        if( shortest == 0 || shortest < need )
        {
            return shortest;
        }
        v_.assign( words_, ~std::uint64_t( 0 ) );
        std::uint64_t* const v    = v_.data();
        std::size_t          next = nb - need + 1;   // the first token count after which the bound can be below need
        for( std::size_t j = 0; j < nb; ++j )
        {
            const std::uint32_t t = b[j];
            if( t < slot_.size() && slot_[t] != 0 )
            {
                const std::uint64_t* const m     = masks_.data() + std::size_t( slot_[t] - 1 ) * words_;
                std::uint64_t              carry = 0;
                for( std::size_t w = 0; w < words_; ++w )
                {
                    const std::uint64_t vw = v[w];
                    const std::uint64_t u  = vw & m[w];
                    v[w]                   = infra::platform::addWithCarry64( vw, u, carry ) | ( vw & ~m[w] );
                }
            }
            if( j + 1 == next )
            {
                const std::size_t reach = zeros() + ( nb - j - 1 );   // the most the LCS can still reach
                if( reach < need )
                {
                    return reach;
                }
                next = j + 2 + ( reach - need );
            }
        }
        return zeros();
    }

private:
    // the zero bits of V in a's |a| positions: the LCS of a and the tokens of b seen so far
    std::size_t zeros() const noexcept
    {
        std::size_t ones = 0;
        for( std::size_t w = 0; w + 1 < words_; ++w )
        {
            ones += std::size_t( std::popcount( v_[w] ) );
        }
        const std::size_t topBits = size_ - ( words_ - 1 ) * 64;   // 1..64 live bits in the last word
        const std::uint64_t topMask = topBits == 64 ? ~std::uint64_t( 0 ) : ( std::uint64_t( 1 ) << topBits ) - 1;
        ones += std::size_t( std::popcount( v_[words_ - 1] & topMask ) );
        return size_ - ones;
    }

    std::vector<std::uint32_t> slot_;    // token id -> 1 + its mask row in masks_; 0 = not in a
    std::vector<std::uint32_t> used_;    // the ids the last load gave a slot (cleared by the next load)
    std::vector<std::uint64_t> masks_;   // one row of words_ words per distinct token of a
    std::vector<std::uint64_t> v_;       // the DP's bit vector, words_ words
    std::size_t                size_  = 0;
    std::size_t                words_ = 0;
};

// One Type-3 candidate: one representative per DISTINCT normalized stream (findClonesType3 below collects them).
struct Type3Cand
{
    NodeId                     id;
    std::vector<std::uint32_t> toks;    // normalized token sequence (interned ids; LCS input)
    std::vector<std::uint64_t> fp;      // sorted, de-duplicated k-gram fingerprint set
};
// fingerprint gram → the candidates holding it, in ascending candidate order (see findClonesType3 on N=4)
using Type3Buckets = HashMap<std::uint64_t, rw::SmallVec<std::uint32_t, 4>>;

// THE PAIR SEARCH of findClonesType3: every distinct candidate pair that shares a usable bucket and is in the length
// band goes through the cap, the sketch, the Jaccard merge and the LCS, once. run() returns the kept pairs (unsorted;
// the caller sorts) and leaves the counters in `st`.
//
// THE WALK (T3-PAIRSEEN, QD-ENVOY-TIME): candidate-major, with no global pair table. Candidate ia's partners are every
// ib > ia that shares a usable bucket with it and is in its length band; they are gathered from ia's own grams into one
// scratch list, sorted and de-duplicated, then gated in ascending ib. That visits exactly the raw pairs the bucket walk
// visits (each bucket's every a < b once) and gates exactly the same distinct pairs, so every Type3Stats count and —
// after the caller's id sort — the emitted vector are the same. What it drops is the `pairSeen` hash the bucket walk
// de-duplicates through: one find (and, for a new pair, an emplace with rehash growth) per length-band survivor, 31 %
// of the pass on envoy and the bulk of its 1.68 GB peak.
//
// THE CAP is the one place the two walks can differ. kType3MaxPairs keeps the FIRST N gated pairs, and "first" is a
// visit order: ascending (ia, ib) in the candidate walk, bucket order in the bucket walk. A pass that reaches the cap
// is therefore re-run by the bucket walk from the start, so the pairs a capped corpus keeps — and the disclosure — are
// the ones it always kept. The re-run does not pay the LCS twice (CodeRabbit 4542253199): the candidate walk records
// each LCS it ran, (pair, similarity) in ascending pair order (its visit order), and the bucket walk looks a pair up
// there before running the DP. The record is at most kType3MaxPairs entries (12 B each) and dies with the search.
// The partner list holds each partner ONCE (CodeRabbit 4542253208): a per-candidate stamp drops a repeat as it is
// visited, so the list is bounded by the candidate count, not by ia's raw bucket visits. Shipped corpora do not reach the cap, and test/clonebandcheck.sh runs both walks, capped and
// uncapped, against each other (-DCTX_TYPE3_BUCKET_WALK compiles the candidate walk out).
class Type3PairSearch
{
public:
    Type3PairSearch( const std::vector<Type3Cand>& cands, const std::vector<std::uint32_t>& candTokens, const std::vector<std::uint8_t>& candSig,
                     const Type3Buckets& buckets, Type3Stats& st, bool verifyLcs = false ) noexcept
        : cands_( cands ), candTokens_( candTokens ), candSig_( candSig ), buckets_( buckets ), st_( st ), verifyLcs_( verifyLcs )
    {
    }

    std::vector<CloneGroup> run()
    {
        for( const auto& [g, idxs] : buckets_ )
        {
            (void)g;
            ASSUME( std::is_sorted( idxs.begin(), idxs.end() ) && std::adjacent_find( idxs.begin(), idxs.end() ) == idxs.end(),
                    "a bucket lists each candidate once, in candidate order" );
        }
#ifndef CTX_TYPE3_BUCKET_WALK
        if( walkByCandidate() )
        {
            return std::move( out_ );
        }
#endif
        // The bucket walk, as it has always run: every counter restarts, and the cap's "first N" are bucket order. The LCS
        // ratios the candidate walk computed are read back, not recomputed (similarityOf).
        out_.clear();
        rerun_            = true;
        comparedPairs_    = 0;
        st_.rawPairVisits = st_.distinctPairs = st_.sketchRejects = st_.jaccardMerges = st_.lcsRuns = 0;
        walkByBucket();
        return std::move( out_ );
    }

private:
    // (a) length band FIRST (B1) — O(1) and a PURE function of the pair, so it runs ahead of any de-dup bookkeeping and
    // drops the common length-mismatched pair with a single float compare. The Jaccard gate (b) is O(|fp|) and
    // DELIBERATELY stays behind the de-dup: a pair recurs in every bucket it shares a k-gram with, so re-running the
    // merge per recurrence is a large net loss (measured ~3× slower). Emitted SET is unchanged by where either sits: the
    // gates are pure. Outside the band an LCS-ratio ≥ kType3MinSimilarity is impossible, so dropping here is exact.
    // Reads the SoA candTokens array ONLY (Y3): two 4-byte loads from a cache-resident array per raw visit.
    bool inLengthBand( std::uint32_t ia, std::uint32_t ib ) const noexcept
    {
        const std::uint32_t lo = std::min( candTokens_[ia], candTokens_[ib] ), hi = std::max( candTokens_[ia], candTokens_[ib] );
        return hi != 0 && !( float( lo ) / float( hi ) < kType3LenBand );
    }
    // Stop-gram cut (A4-P2): a bucket bigger than kType3MaxBucket is a ubiquitous k-gram — O(size²) pairs of pure
    // boilerplate. Skipped by both walks; any real near-clone in it shares a rarer gram and is compared via a smaller
    // bucket. A fixed threshold, decided before any per-pair work, so the decision is fully deterministic.
    static bool usableBucket( const rw::SmallVec<std::uint32_t, 4>& idxs ) noexcept { return idxs.size() >= 2 && idxs.size() <= kType3MaxBucket; }

    // One DISTINCT length-band-surviving pair (ia < ib) through the cap, the sketch, the Jaccard merge and the LCS, in
    // the order the pass has always run them; false = the cap stops the pass before this pair.
    bool gatePair( std::uint32_t ia, std::uint32_t ib )
    {
        if( comparedPairs_ >= kType3MaxPairs )
        {
            return false;
        }
        ++st_.distinctPairs;
#ifndef CTX_TYPE3_SKETCH_OFF
        // (a′) Y3 minhash pre-gate — O(kSketchHashes) byte compares against the operating point; the grossly
        // dissimilar pairs that dominate real corpora (99 % at J < 0.20 on llama.cpp) die here without ever
        // paying the O(|fp|) exact merge. Pure + deterministic (fixed constants); recall bound at the top.
        if( cloneSketchMatches( candSig_.data() + std::size_t( ia ) * kSketchHashes, candSig_.data() + std::size_t( ib ) * kSketchHashes ) < kSketchMinMatches )
        {
            ++st_.sketchRejects;
            return true;
        }
#endif
        const Type3Cand& ca = cands_[ia];
        const Type3Cand& cb = cands_[ib];
        // (b) fingerprint Jaccard — lexical lower bound on similarity, both fp sets sorted → merge count. Behind the
        // de-dup, so it runs once per distinct length-band-surviving pair, not once per recurrence.
        ++st_.jaccardMerges;
        std::size_t inter = 0;
        for( std::size_t i = 0, j = 0; i < ca.fp.size() && j < cb.fp.size(); )
        {
            if( ca.fp[i] == cb.fp[j] ) { ++inter; ++i; ++j; }
            else if( ca.fp[i] < cb.fp[j] ) { ++i; }
            else
            {
                ++j;
            }
        }
        const std::size_t uni = ca.fp.size() + cb.fp.size() - inter;
        if( uni == 0 || float( inter ) / float( uni ) < kType3MinFpJaccard )
        {
            return true;
        }
        // (c) the expensive compare: LCS over token sequences, each a view of its first kType3MaxTokensForLcs (T3-LCS).
        ++comparedPairs_;
        ++st_.lcsRuns;
        const std::span<const std::uint32_t> pa( ca.toks.data(), std::min( ca.toks.size(), kType3MaxTokensForLcs ) );
        const std::span<const std::uint32_t> pb( cb.toks.data(), std::min( cb.toks.size(), kType3MaxTokensForLcs ) );
        const std::size_t den = pa.size() + pb.size();
        const float       sim = similarityOf( ia, ib, pa, pb );
        if( den == 0 || sim < kType3MinSimilarity || sim >= 1.0f )
        {
            return true; // < 1.0: exact would be Type-1/2
        }
        // member order stable by symbol id (small id first) → deterministic emit.
        out_.push_back( { { std::min( ca.id, cb.id ), std::max( ca.id, cb.id ) }, std::max( candTokens_[ia], candTokens_[ib] ), std::uint8_t( 3 ), sim } );
        return true;
    }

    // The LCS ratio of (ia, ib): the candidate walk computes and records it; the bucket walk's cap re-run reads the record
    // first (the walk recorded in ascending pair order, so the record is sorted) and computes only a pair it lacks.
    float similarityOf( std::uint32_t ia, std::uint32_t ib, std::span<const std::uint32_t> pa, std::span<const std::uint32_t> pb )
    {
        const std::uint64_t key = ( std::uint64_t( ia ) << 32 ) | ib;
        if( rerun_ )
        {
            const auto it = std::lower_bound( lcsKeys_.begin(), lcsKeys_.end(), key );
            if( it != lcsKeys_.end() && *it == key )
            {
                return lcsSims_[ std::size_t( it - lcsKeys_.begin() ) ];
            }
        }
        ++st_.lcsComputed;
        const std::size_t den = pa.size() + pb.size();
        // below type3LcsNeed the ratio cannot reach kType3MinSimilarity, so the DP may stop early with a smaller value
        const std::size_t need = type3LcsNeed( den );
        if( lcsBitsFor_ != ia )   // the candidate walk meets every partner of ia in a row: one load serves them all
        {
            lcsBits_.load( pa );
            lcsBitsFor_ = ia;
        }
        const std::size_t lcs = lcsBits_.lcs( pb, need );
        if( verifyLcs_ )
        {
            verifyLcs( pa, pb, need, lcs );
        }
        const float       sim = den == 0 ? 0.0f : 2.0f * float( lcs ) / float( den );
        if( !rerun_ )
        {
            ASSUME( lcsKeys_.empty() || lcsKeys_.back() < key, "the candidate walk gates pairs in ascending (ia, ib)" );
            lcsKeys_.push_back( key );
            lcsSims_.push_back( sim );
        }
        return sim;
    }

    // The identity check behind RIPWIRE_LCS_VERIFY: the fast answer `lcs` for `need` against the plain DP's exact length. A
    // length at or above `need` must be exact; one below it must come from a pair whose exact length is below it too.
    // The bit-parallel LCS run to the end (no need) must equal the plain DP on every pair, exited or not.
    void verifyLcs( std::span<const std::uint32_t> pa, std::span<const std::uint32_t> pb, std::size_t need, std::size_t lcs )
    {
        const std::size_t exact = cloneLcsLen( pa, pb, verifyPrevRow_, verifyCurRow_ );
        const bool        bad   = ( lcs >= need ? lcs != exact : exact >= need ) || lcsBits_.lcs( pb ) != exact;
        ++st_.lcsVerified;
        st_.lcsVerifyExits += lcs < need ? 1 : 0;
        st_.lcsVerifyMismatches += bad ? 1 : 0;
    }

    // The candidate walk (see the class comment); false = it reached the cap and the bucket walk must answer.
    bool walkByCandidate()
    {
        std::vector<std::uint32_t> partners;
        std::vector<std::uint32_t> stamp( cands_.size(), 0 );   // stamp[ib] == ia + 1: ib is already in ia's list
        for( std::uint32_t ia = 0; ia < cands_.size(); ++ia )
        {
            partners.clear();
            for( const std::uint64_t g : cands_[ia].fp )
            {
                const auto it = buckets_.find( g );   // every gram of every candidate was bucketed
                if( it == buckets_.end() || !usableBucket( it->second ) )
                {
                    continue;
                }
                for( auto p = std::upper_bound( it->second.begin(), it->second.end(), ia ); p != it->second.end(); ++p )
                {
                    ++st_.rawPairVisits;
                    if( stamp[ *p ] != ia + 1 && inLengthBand( ia, *p ) )
                    {
                        stamp[ *p ] = ia + 1;
                        partners.push_back( *p );
                    }
                }
            }
            st_.partnersPeak = std::max<std::uint64_t>( st_.partnersPeak, partners.size() );
            std::sort( partners.begin(), partners.end() );
            for( const std::uint32_t ib : partners )
            {
                if( !gatePair( ia, ib ) )
                {
                    return false;
                }
            }
        }
        return true;
    }

    // The bucket walk: every usable bucket's a < b pairs in bucket order, de-duplicated through `pairSeen` (pure
    // membership; the walk is insertion-ordered, so the kept/dropped split on a cap-hitting corpus is deterministic).
    void walkByBucket()
    {
        HashMap<std::uint64_t, std::uint8_t> pairSeen;
        for( const auto& [g, idxs] : buckets_ )
        {
            (void)g;
            if( !usableBucket( idxs ) )
            {
                continue;
            }
            for( std::size_t a = 0; a < idxs.size(); ++a )
            {
                for( std::size_t b = a + 1; b < idxs.size(); ++b )
                {
                    const std::uint32_t ia = idxs[a], ib = idxs[b];   // ia < ib: the bucket is in candidate order
                    ++st_.rawPairVisits;
                    if( !inLengthBand( ia, ib ) || !pairSeen.emplace( ( std::uint64_t( ia ) << 32 ) | ib, std::uint8_t( 1 ) ).second )
                    {
                        continue;
                    }
                    if( !gatePair( ia, ib ) )
                    {
                        DISCLOSE( st_, Type3Stats::DisclosureWhy::PairCapHit, "clones: Type-3 pair cap hit — first N compared (both-gate-surviving) near-misses kept, rest skipped" );
                        return;
                    }
                }
            }
        }
    }

    const std::vector<Type3Cand>&     cands_;
    const std::vector<std::uint32_t>& candTokens_;   // SoA token counts (the length band's only read)
    const std::vector<std::uint8_t>&  candSig_;      // SoA minhash bytes, kSketchHashes per candidate
    const Type3Buckets&               buckets_;
    Type3Stats&                       st_;
    std::vector<CloneGroup>           out_;
    std::size_t                       comparedPairs_ = 0;
    CloneLcsBits                      lcsBits_;   // the bit-parallel LCS, loaded with candidate lcsBitsFor_ (QD-LCS)
    std::uint32_t                     lcsBitsFor_ = ~std::uint32_t( 0 );   // the candidate lcsBits_ holds; none at the start
    std::vector<std::uint32_t>        verifyPrevRow_, verifyCurRow_;   // the RIPWIRE_LCS_VERIFY plain DP's rows
    std::vector<std::uint64_t>        lcsKeys_;   // the candidate walk's LCS record: (ia << 32 | ib), ascending
    std::vector<float>                lcsSims_;   // ... and each pair's similarity
    bool                              rerun_ = false;   // the bucket walk is re-running a capped pass: read the record first
    bool                              verifyLcs_ = false;   // RIPWIRE_LCS_VERIFY: check every LCS against the plain DP
};

// Find Type-3 (gapped) clone PAIRS: normalized streams highly similar (LCS-ratio ≥ kType3MinSimilarity) but not
// identical. Each returned group has exactly two members {loId,hiId} with type==3 and the measured similarity.
// Deterministic; bounded (see the header block). Does NOT alter findClones() — callers opt into this pass.
// statsOut (optional): per-pass pair-visit counters for the clonebandcheck gate; never affects the result.
// QD-ENVOY-TIME cost bound: Type-3 passes this process ran, and the pairs they emitted in all. --quality-delta prints both on
// its RIPWIRE_STATS line, and test/qdtype3oncecheck.sh holds the run count to one per call (the pairs are its premise).
// Relaxed: a count read once at the end, never a synchronization point.
inline std::atomic<std::uint32_t> gType3PassRuns{ 0 };
inline std::atomic<std::uint64_t> gType3PassPairs{ 0 };

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
    std::vector<Type3Cand>                cands;
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
        if( !readCloneSourceFile( ing, f, bytes ) )
        {
            continue; // degrade: an unreadable or empty file just contributes no candidates (never a crash)
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
    Type3Buckets buckets;
    for( std::uint32_t ci = 0; ci < cands.size(); ++ci )
    {
        for( std::uint64_t g : cands[ci].fp )
        {
            buckets[g].push_back( ci );
        }
    }

    const bool              verifyLcs = std::getenv( "RIPWIRE_LCS_VERIFY" ) != nullptr;
    std::vector<CloneGroup> out       = Type3PairSearch( cands, candTokens, candSig, buckets, st, verifyLcs ).run();
    if( verifyLcs )
    {
        rw::emitTo( stderr, "ripwire: lcs-verify pairs={} early_exits={} mismatches={}\n", st.lcsVerified, st.lcsVerifyExits, st.lcsVerifyMismatches );
    }
    // Deterministic order: by (first member id, second member id). Similarity is a pure function of the streams,
    // so ties are impossible for a fixed pair; the id sort fully determines the sequence.
    std::sort( out.begin(), out.end(), []( const CloneGroup& p, const CloneGroup& q )
               { return p.members[0] != q.members[0] ? p.members[0] < q.members[0] : p.members[1] < q.members[1]; } );
    st.emittedPairs = out.size();
    gType3PassRuns.fetch_add( 1, std::memory_order_relaxed );
    gType3PassPairs.fetch_add( out.size(), std::memory_order_relaxed );
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
// too LOW. When the cap fired (Type3Stats::pairCapHit) every derived count here is a floor, and the emitter
// labels it counts_floor="1" type3_capped="1" — on that run only (2026-09-24; it used to print on every run).
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
