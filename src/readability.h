#pragma once

// readability.h — `--readability`: the Posnett/Hindle/Devanbu (MSR 2011) readability lens, per function.
//
// Three numbers per function or method, one token pass, all closed-form — no model, no corpus, no network:
//   V  Halstead volume            V = N * log2(eta),  N = operator+operand tokens, eta = DISTINCT such tokens
//   E  token entropy              Shannon entropy of the definition's token-frequency distribution, in bits
//   L  lines                      Symbol::loc, the definition's physical line span (already indexed; not recomputed)
//   P  Posnett score              P = sigmoid( 8.87 - 0.033*V + 0.40*L - 1.5*E ), the paper's published fit
// Rows are emitted LEAST readable first (ascending P) — the verb is a RANKING lens, which is the only claim
// the literature supports for it (Scalabrino ASE'17 and Trockman MSR'18 both find no readability metric
// correlates strongly with measured understandability; Fakhoury ICPC'19 finds the classic models miss real
// readability-improving commits). So P is never a grade, never a gate, and never a verdict — it orders a
// worklist, and the legend says so where the reader meets it.
//
// THE ONE APPROXIMATION, stated rather than discovered later. Halstead's operator/operand partition is
// per-grammar in the literature; this lens uses ONE token-class table for every indexed language —
// keywords + punctuation are operators, identifiers + literals are operands (halsteadRoleOf below, a pure
// projection of clones.h's CodeTokenKind). Per-language refinement is deliberately out of scope,
// and --help discloses it. Note what does NOT depend on the partition: because every token is exactly one
// of the two, N = N1+N2 is the token count and eta = eta1+eta2 is the distinct-token count, so V itself is
// partition-independent. The split is reported as ops= (the operator half of toks=) so a reader can see it
// rather than take it on trust.
//
// SPAN. One span serves all four numbers: the WHOLE definition [sigStartByte, endByte), signature included.
// Posnett fit on snippets, and a function's snippet includes its signature; a body-only span would also put
// L and the token stream on different footings, since sigEndByte lands mid-line (right after the parameter
// list) so a body-only line count is off by one against what the reader sees. A definition with no body
// (prototype, abstract, interface method: endByte <= sigEndByte) is NOT measured — there is nothing to read.
//
// DETERMINISM. Token counts live in a HashMap, whose iteration order must never reach output (CONTRIBUTING.md
// §3, Containers) — and for a float SUM that rule is sharper than usual, because reordering the addends
// changes the bits. The entropy sum therefore runs over the (token text)-SORTED vector, and the row sort key
// is total: ascending P, descending V, then NodeId (already assigned in file/line/name order).

#include "model.h"
#include "clones.h"             // scanCodeTokens — THE ONE code scanner (this lens is its keep-identity projection,
#include "graphlegend.h"   // R-E fix (2026-08-19): rw::rootRelPathsLegend — the ONE root= definition
                                //                  --clones is its erase-identity one) + usesHashLineComments
#include "docparse.h"           // docparse::detail::readWholeFile — the canonical whole-file byte read (reused, not re-rolled)
#include "pageview.h"           // pageWindow + pageDisclosure — THE TRUNCATION VOCABULARY
#include "serialize.h"          // escapeXml
#include "infra/Diagnostics.h"  // DEGRADED_PATH_ALERT — an unreadable file degrades the scan, never aborts it

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// The display cap, in the same shape as --hotspots' 40: raisable with --limit, paged with --offset.
inline constexpr std::size_t kReadabilityRowCap = 40;

// The Posnett MSR 2011 coefficients, verbatim. Named so a reader can check them against the paper without
// decoding four literals inside one expression.
inline constexpr double kPosnettIntercept = 8.87;
inline constexpr double kPosnettVolume    = -0.033;
inline constexpr double kPosnettLines     = 0.40;
inline constexpr double kPosnettEntropy   = -1.5;

// The logistic clamp: |z| beyond this saturates the double anyway, and clamping keeps the PRINTED value
// stable instead of depending on how std::exp rounds an overflowing argument.
inline constexpr double kPosnettZClamp = 40.0;

enum class TokenRole : std::uint8_t { Operator, Operand };

// THE token-class table: clones.h's scanner already decided what each token IS, so this is a pure
// CodeTokenKind → Halstead-role projection and not a second classifier. Deliberately total — every token the
// scanner emits is exactly one of the two roles, which is what makes V partition-independent (header note).
inline TokenRole halsteadRoleOf( CodeTokenKind kind ) noexcept
{
    switch( kind )
    {
        case CodeTokenKind::Identifier:  return TokenRole::Operand;    // a name
        case CodeTokenKind::Number:      return TokenRole::Operand;    // a literal
        case CodeTokenKind::String:      return TokenRole::Operand;    // a literal
        case CodeTokenKind::Keyword:     return TokenRole::Operator;
        case CodeTokenKind::Punctuation: return TokenRole::Operator;
    }
    return TokenRole::Operator;
}

// One measured function. POD; the vector of these IS the report.
struct ReadabilityRow
{
    NodeId        id;
    std::uint32_t lineCount;        // L — Symbol::loc
    std::uint32_t tokenCount;       // N — operator + operand tokens
    std::uint32_t operatorCount;    // N1 — the operator half of tokenCount
    std::uint32_t vocabularyCount;  // eta — distinct tokens
    double        volume;           // V
    double        entropy;          // E, bits
    double        posnett;          // P
};

struct ReadabilityScan
{
    std::vector<ReadabilityRow> rows;
    std::uint32_t               unreadableFileCount;   // >0 ⇒ rows is a FLOOR, disclosed on the root
};

inline double posnettScore( double volume, double lineCount, double entropy ) noexcept
{
    const double z       = kPosnettIntercept + kPosnettVolume * volume + kPosnettLines * lineCount + kPosnettEntropy * entropy;
    const double clamped = std::clamp( z, -kPosnettZClamp, kPosnettZClamp );
    return 1.0 / ( 1.0 + std::exp( -clamped ) );
}

// The measurement pass. Reads each indexed file at most once; a file that cannot be read is counted and
// skipped (DEGRADED_PATH_ALERT), never fatal — the whole pipeline must survive a malformed repo.
inline ReadabilityScan computeReadability( const IngestResult& ing )
{
    ReadabilityScan scan;
    scan.unreadableFileCount = 0;

    const std::size_t fileCount = ing.files.size();
    std::vector<std::string> fileBytes( fileCount );      // sized ONCE: the token views point into these
    std::vector<char>        fileLoaded( fileCount, 0 );
    std::vector<char>        fileFailed( fileCount, 0 );

    std::vector<std::string_view>                     tokens;
    std::vector<std::pair<std::string_view, std::uint32_t>> counts;
    HashMap<std::string_view, std::uint32_t>          freq;

    for( std::size_t symbolIndex = 0; symbolIndex < ing.symbols.size(); ++symbolIndex )
    {
        const Symbol& s = ing.symbols[symbolIndex];
        if( s.kind != SymKind::Function && s.kind != SymKind::Method )
        {
            continue;
        }
        if( s.endByte <= s.sigEndByte )
        {
            continue;   // no body: a prototype / abstract declaration is not a thing to read
        }
        if( s.fileId >= fileCount )
        {
            continue;
        }
        if( fileLoaded[s.fileId] == 0 )
        {
            fileLoaded[s.fileId] = 1;
            if( !docparse::detail::readWholeFile( diskPath( ing, s.fileId ), fileBytes[s.fileId] ) )
            {
                fileFailed[s.fileId] = 1;
                ++scan.unreadableFileCount;
                DEGRADED_PATH_ALERT( "readability: an indexed file could not be read — its functions are absent from the report" );
            }
        }
        if( fileFailed[s.fileId] != 0 )
        {
            continue;
        }

        // ONE scan, maximal-munch operators on (see clones.h scanCodeTokens). The views point into
        // fileBytes[fileId], which is sized once above and never reallocated, so they stay valid.
        tokens.clear();
        std::uint32_t operatorCount = 0;
        scanCodeTokens( fileBytes[s.fileId], s.sigStartByte, s.endByte, usesHashLineComments( s.lang ), true,
                        [ & ]( std::string_view token, CodeTokenKind kind )
                        {
                            tokens.push_back( token );
                            operatorCount += halsteadRoleOf( kind ) == TokenRole::Operator ? 1u : 0u;
                        } );
        if( tokens.empty() )
        {
            continue;   // nothing measurable; a zero here would read as "perfectly readable"
        }

        freq.clear();
        freq.reserve( tokens.size() );
        for( const std::string_view t : tokens )
        {
            ++freq[t];
        }

        // Hash iteration order must not reach a float sum: copy out and sort by token text first.
        counts.assign( freq.begin(), freq.end() );
        std::sort( counts.begin(), counts.end(),
                   []( const auto& a, const auto& b ) noexcept { return a.first < b.first; } );

        const double total   = double( tokens.size() );
        double       entropy = 0.0;
        for( const auto& [ text, count ] : counts )
        {
            const double p = double( count ) / total;
            entropy -= p * std::log2( p );
        }

        ReadabilityRow row;
        row.id              = NodeId( symbolIndex );
        row.lineCount       = s.loc;
        row.tokenCount      = std::uint32_t( tokens.size() );
        row.operatorCount   = operatorCount;
        row.vocabularyCount = std::uint32_t( counts.size() );
        row.volume          = total * std::log2( double( counts.size() ) );
        row.entropy         = entropy;
        row.posnett         = posnettScore( row.volume, double( row.lineCount ), row.entropy );
        scan.rows.push_back( row );
    }

    // Least readable FIRST. Total order: P ascending, then V descending (bigger is harder at equal P), then
    // the symbol id — already assigned in (file, line, name) order, so this is byte-stable without a string
    // compare. Tolerance bands do not apply to a SORT (CONTRIBUTING.md §3): the determinism gate does.
    std::sort( scan.rows.begin(), scan.rows.end(),
               []( const ReadabilityRow& a, const ReadabilityRow& b ) noexcept
               {
                   if( a.posnett != b.posnett )
                   {
                       return a.posnett < b.posnett;
                   }
                   if( a.volume != b.volume )
                   {
                       return a.volume > b.volume;
                   }
                   return a.id < b.id;
               } );
    return scan;
}

// The legend the reader meets FIRST. Every attribute this verb emits is DEFINED here in the house `name=`
// form (test/legendcoveragecheck.sh derives that mechanically). No `--` digraph anywhere in it: that is
// illegal inside an XML comment, which is why flags are named bare (see src/graphlegend.h).
inline constexpr const char* kReadabilityLegend =
    "<!-- ripwire readability: the Posnett/Hindle/Devanbu (MSR 2011) closed-form lens, one row per function "
    "or method, LEAST READABLE FIRST. p=path:line n=symbol name lines=L, the definition's physical line span "
    "toks=N, the operator+operand tokens of the whole definition (signature included) "
    "ops=N1, the operator half of toks (keywords and punctuation; the rest are identifiers and literals) "
    "vocab=eta, distinct tokens vol=Halstead volume V, N*log2(eta) ent=E, Shannon entropy of the token "
    "frequency distribution, in bits posnett=P, sigmoid(8.87 - 0.033V + 0.40L - 1.5E), the paper's published fit. "
    "ONE token-class table serves every language, so V is a cross-language APPROXIMATION, not a per-grammar "
    "count. P was fitted on snippets of 20 lines or fewer: read the ORDER, not the number, and never as a grade. "
    "functions=functions and methods measured (a declaration with no body is not measured) "
    "shown=rows printed capped=1 when rows were dropped; raise the default cap with limit=N (offset=M pages), "
    "which also prints total= has_more= next_offset= offset= limit= "
    "unreadable_files=indexed files this pass could not read; their functions are absent, so functions= is a FLOOR -->";

// Emit the report. Returns the process exit code — always 0: this is a lens, not a gate. `rootPrefix`/
// `rootAttr` — R-E (2026-08-17 harvest), same convention writeContextRatioReport takes (see contextratio.h).
inline int writeReadabilityReport( const IngestResult& ing, int pageLimit, int pageOffset,
                                   std::string_view rootPrefix = {}, const std::string& rootAttr = std::string() )
{
    const ReadabilityScan scan  = computeReadability( ing );
    const std::size_t     total = scan.rows.size();
    const PageWindow      page  = pageWindow( total, effectiveRowCap( pageLimit, int( kReadabilityRowCap ) ), pageOffset );
    const std::size_t     shown = page.end > page.begin ? page.end - page.begin : 0;

    char disclosure[kPageDisclosureCap];
    pageDisclosure( disclosure, sizeof disclosure, shown, total, page.end, pageLimit, pageOffset, true );

    std::fputs( kReadabilityLegend, stdout );
    // R-E fix (2026-08-19): the shared root-relative clause, emitted exactly when root= is (graphlegend.h).
    std::fputs( rw::rootRelPathsLegend( !rootAttr.empty() ), stdout );
    std::printf( "<readability functions=\"%zu\"%s", total, disclosure );
    if( scan.unreadableFileCount != 0 )
    {
        std::printf( " unreadable_files=\"%u\"", scan.unreadableFileCount );
    }
    std::printf( "%s>", rootAttr.c_str() );

    // TWO scratch buffers, not one reused twice in the same call: escapeXml returns a VIEW into its `out`,
    // so a second call with the same buffer invalidates the first view — and argument evaluation order is
    // unspecified, which makes the single-buffer spelling a bug that shows up only under some compilers.
    std::vector<char> escPath;
    std::vector<char> escName;
    for( std::size_t rowIndex = page.begin; rowIndex < page.end; ++rowIndex )
    {
        const ReadabilityRow&  row  = scan.rows[rowIndex];
        const Symbol&          s    = ing.symbols[row.id];
        const std::string_view rel  = rootPrefix.empty() ? std::string_view( ing.files[s.fileId] ) : rw::sarif::rootRelativeUri( ing.files[s.fileId], rootPrefix );
        const std::string      path( escapeXml( rel, escPath ) );
        const std::string     name( escapeXml( s.name, escName ) );
        std::printf( "<fn p=\"%s:%u\" n=\"%s\" lines=\"%u\" toks=\"%u\" ops=\"%u\" vocab=\"%u\" vol=\"%.1f\" ent=\"%.2f\" posnett=\"%.3f\"/>",
                     path.c_str(), s.line, name.c_str(),
                     row.lineCount, row.tokenCount, row.operatorCount, row.vocabularyCount,
                     row.volume, row.entropy, row.posnett );
    }
    std::printf( "</readability>" );
    return 0;
}

}   // namespace rw
