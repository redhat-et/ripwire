#pragma once

// commentcoherence.h — `--comment-coherence`: two published, deterministic measures of what a doc
// comment SAYS, per function/method — not whether it is stale (that is --doc-drift's job; see the note
// below), but whether its words carry information beyond the name they sit next to.
//
//   c_coeff   Steidl / Hummel / Juergens coherence coefficient, ICPC 2013 "Quality Analysis of Source
//             Code Comments". The fraction of WORDS in the comment that are "similar" to a word in the
//             method's own (split) name, similarity = Levenshtein distance < 2, case-insensitive.
//             ¡¡ HIGH c_coeff IS BAD !! — a comment that mostly repeats the name's own words carries
//             no information the name did not already give the reader; that is the OPPOSITE of the naive
//             "high coherence sounds good" reading, and this file says so everywhere the number is
//             printed, per CLAUDE.md non-negotiable #3 (a surface must not let a reader misread its own
//             direction).
//
//   cic       Scalabrino et al. CIC (Comments-Identifiers Consistency), ICPC 2016 "Automatically
//             Assessing Code Understandability" / JSEP 2018. Jaccard overlap of two method-local TERM
//             SETS: the comment's vocabulary vs the method's own identifier vocabulary, both preprocessed
//             (operators/keywords stripped, camelCase/snake_case split, English stopwords dropped,
//             deduplicated). cic = |Comments(m) ∩ Ids(m)| / |Comments(m) ∪ Ids(m)|.
//
// THEY MEASURE DIFFERENT THINGS AND ARE EXPECTED TO DISAGREE. c_coeff compares the comment against the
// NAME (a handful of words); cic compares it against every IDENTIFIER the method touches (parameters,
// locals, callees, fields — usually many more words than the name alone). A comment can restate the name
// (high c_coeff) while still sharing real vocabulary with the body's other identifiers (non-trivial cic),
// or vice-versa. Report both; a reader who wants one number has misunderstood the axis — the readability
// literature is explicit that no metric or combination correlates strongly with measured understandability
// (Scalabrino ASE'17, Trockman MSR'18), which is why this is a LENS, never a verdict.
//
// SCOPE: fires only where a doc comment ACTUALLY EXISTS immediately above the definition (docCommentBefore,
// serialize.h's L2 extractor — the same "consecutive // /// //! //< lines, or a directly-adjacent /* */
// block" rule --pack-task's context uses, so "is there a comment" never drifts from what a bundle would
// show a reader). A symbol with NO comment is UNAVAILABLE for this measure — not a zero, never scored —
// and is counted on the root as no_comment=, per CLAUDE.md non-negotiable #3 ("a zero means none found,
// never none exists"). A comment that tokenizes to zero words (e.g. "// ---") is the same UNAVAILABLE
// case and is folded into the same count.
//
// RELATIONSHIP TO --doc-drift, ON PURPOSE. --doc-drift answers "is this claim still TRUE" (a stale
// file:line/symbol/constant reference in a MARKDOWN document) — staleness, checked against the live
// index. This verb never checks truth or freshness; it answers "does this SOURCE doc-comment carry
// information, or does it just echo the name" — content, checked against the comment's own words. The two
// are complementary axes over disjoint inputs (markdown claims vs C-family/ObjC/Python doc-comments) and
// deliberately do not share a code path; a symbol can be perfectly fresh (nothing for --doc-drift to
// flag) and still restate its own name (high c_coeff here), or vice versa.
//
// SUBSTRATE REUSE, not reinvention: splitIdentifier / editDistanceCapped / toLowerAscii are naminglens.h's
// (the same conservative case/digit/ACRONYMWord splitter and bounded Levenshtein the naming-confusable
// lint rule uses); the identifier scan over a definition's [sigStartByte, endByte) span is clones.h's
// scanCodeTokens, the same call readability.h makes for its own token pass. ONE tokenizer
// (naminglens::splitIdentifier) serves BOTH measures here: applied to the comment's flattened text it is
// simultaneously "the comment's words" (c_coeff, unfiltered, duplicates kept — the paper's literal
// definition) and, after stopword-dropping and deduplication, "the comment's TERM SET" (cic's LHS).

#include "model.h"
#include "clones.h"        // scanCodeTokens, usesHashLineComments — the identifier scan over a definition's span
#include "naminglens.h"    // splitIdentifier, editDistanceCapped, toLowerAscii — the shared name/word substrate
#include "docparse.h"      // docparse::detail::readWholeFile — the canonical whole-file byte read
#include "serialize.h"     // docCommentBefore (L2 extractor) + escapeXml
#include "pageview.h"      // pageWindow + pageDisclosure — THE TRUNCATION VOCABULARY
#include "infra/Diagnostics.h"   // DEGRADED_PATH_ALERT — an unreadable file degrades the scan, never aborts it

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

inline constexpr std::size_t kCommentCoherenceRowCap = 40;   // same shape as --readability's 40

// A fixed, general-English stopword list — deliberately broad rather than SE-tuned or exhaustive (the
// same disclosed-fixed-list posture as lexical.h's isRouteStopword, just sized for PROSE rather than
// short queries). Used ONLY to build cic's term sets; c_coeff's word list is intentionally unfiltered
// (the Steidl paper compares ALL comment words against the name, stopwords included).
inline bool isCommentStopword( std::string_view w ) noexcept
{
    static constexpr std::string_view kStop[] = {
        "a", "an", "the", "and", "or", "but", "if", "then", "else", "for", "to", "of", "in", "on", "at",
        "by", "with", "from", "as", "is", "are", "was", "were", "be", "been", "being", "this", "that",
        "these", "those", "it", "its", "itself", "which", "who", "whom", "what", "when", "where", "why",
        "how", "not", "no", "nor", "so", "than", "too", "very", "can", "will", "just", "should", "now",
        "do", "does", "did", "doing", "have", "has", "had", "having", "we", "you", "your", "i", "he", "she",
        "they", "them", "their", "our", "us", "also", "into", "over", "after", "before", "between", "up",
        "down", "out", "about", "again", "once", "here", "there", "all", "any", "both", "each", "few",
        "more", "most", "other", "some", "such", "only", "own" };
    for( const std::string_view s : kStop )
    {
        if( w == s )
        {
            return true;
        }
    }
    return false;
}

// splitIdentifier(...) lowercased, one call site — the ONE tokenizer this whole lens uses (header note).
inline void lowerSplitInto( std::string_view text, std::vector<std::string>& scratch, std::vector<std::string>& out )
{
    naminglens::splitIdentifier( text, scratch );
    out.reserve( out.size() + scratch.size() );
    for( const std::string& tok : scratch )
    {
        out.push_back( naminglens::toLowerAscii( tok ) );
    }
}

// dedupe + drop stopwords, IN PLACE, sorted (a term SET, not a word list — cic's inputs).
inline void toTermSet( std::vector<std::string>& words )
{
    words.erase( std::remove_if( words.begin(), words.end(),
                                  []( const std::string& w ) { return w.empty() || isCommentStopword( w ); } ),
                 words.end() );
    std::sort( words.begin(), words.end() );
    words.erase( std::unique( words.begin(), words.end() ), words.end() );
}

// |A ∩ B| and |A ∪ B| over two SORTED, deduplicated term sets — one merge walk, no container beyond the
// two inputs (CONTRIBUTING.md §3: never std::map/unordered_map; a sorted-vector merge is the house idiom).
inline void jaccardCounts( const std::vector<std::string>& a, const std::vector<std::string>& b,
                            std::size_t& outIntersection, std::size_t& outUnion ) noexcept
{
    std::size_t i = 0, j = 0, inter = 0, uni = 0;
    while( i < a.size() && j < b.size() )
    {
        if( a[i] == b[j] )
        {
            ++inter; ++uni; ++i; ++j;
        }
        else if( a[i] < b[j] )
        {
            ++uni; ++i;
        }
        else
        {
            ++uni; ++j;
        }
    }
    uni += ( a.size() - i ) + ( b.size() - j );
    outIntersection = inter;
    outUnion        = uni;
}

// one measured function/method. POD; the vector of these IS the report.
struct CommentCoherenceRow
{
    NodeId        id;
    double        cCoeff;             // Steidl: fraction of comment words restating the name (HIGH = bad)
    double        cic;                // Scalabrino: Jaccard(comment terms, identifier terms)
    std::uint32_t commentWordCount;   // c_coeff's denominator — ALL comment words, unfiltered
    std::uint32_t restatingWordCount; // c_coeff's numerator
    std::uint32_t commentTermCount;   // |Comments(m)| — post stopword-drop + dedupe
    std::uint32_t idTermCount;        // |Ids(m)|       — post stopword-drop + dedupe
    std::uint32_t sharedTermCount;    // |Comments(m) ∩ Ids(m)|
};

struct CommentCoherenceScan
{
    std::vector<CommentCoherenceRow> rows;
    std::uint32_t                    noCommentCount     = 0;  // documented=false symbols — UNAVAILABLE, never scored
    std::uint32_t                    unreadableFileCount = 0; // >0 ⇒ rows is a FLOOR, disclosed on the root
};

inline CommentCoherenceScan computeCommentCoherence( const IngestResult& ing )
{
    CommentCoherenceScan scan;

    const std::size_t fileCount = ing.files.size();
    std::vector<std::string> fileBytes( fileCount );
    std::vector<char>        fileLoaded( fileCount, 0 );
    std::vector<char>        fileFailed( fileCount, 0 );

    std::vector<std::string> splitScratch;
    std::vector<std::string> nameWords;
    std::vector<std::string> commentWords;      // unfiltered — c_coeff's word list
    std::vector<std::string> commentTerms;      // filtered+deduped — cic's LHS
    std::vector<std::string> idWords;
    std::vector<std::string> idTerms;           // filtered+deduped — cic's RHS

    for( std::size_t symbolIndex = 0; symbolIndex < ing.symbols.size(); ++symbolIndex )
    {
        const Symbol& s = ing.symbols[symbolIndex];
        if( s.kind != SymKind::Function && s.kind != SymKind::Method )
        {
            continue;
        }
        if( s.endByte <= s.sigEndByte )
        {
            continue;   // no body: nothing for Ids(m) to measure
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
                DEGRADED_PATH_ALERT( "comment-coherence: an indexed file could not be read — its functions are absent from the report" );
            }
        }
        if( fileFailed[s.fileId] != 0 )
        {
            continue;
        }

        const std::string& src = fileBytes[s.fileId];
        const std::string  doc = docCommentBefore( src, s.sigStartByte );
        if( doc.empty() )
        {
            ++scan.noCommentCount;   // UNAVAILABLE — no comment to measure, never a zero
            continue;
        }

        commentWords.clear();
        lowerSplitInto( doc, splitScratch, commentWords );
        if( commentWords.empty() )
        {
            ++scan.noCommentCount;   // a comment with zero measurable words is the same UNAVAILABLE case
            continue;
        }

        nameWords.clear();
        lowerSplitInto( s.name, splitScratch, nameWords );

        // c_coeff: fraction of (unfiltered) comment words within Levenshtein <2 of ANY name word.
        std::uint32_t restating = 0;
        for( const std::string& cw : commentWords )
        {
            for( const std::string& nw : nameWords )
            {
                if( naminglens::editDistanceCapped( cw, nw, 1 ) <= 1 )
                {
                    ++restating;
                    break;
                }
            }
        }
        const double cCoeff = double( restating ) / double( commentWords.size() );

        // cic: Jaccard over the two preprocessed term SETS.
        commentTerms = commentWords;
        toTermSet( commentTerms );

        idWords.clear();
        scanCodeTokens( src, s.sigStartByte, s.endByte, usesHashLineComments( s.lang ), true,
                        [ & ]( std::string_view token, CodeTokenKind kind )
                        {
                            if( kind != CodeTokenKind::Identifier )
                            {
                                return;   // "strip operators/keywords" (task spec) — kind already sorts them out
                            }
                            lowerSplitInto( token, splitScratch, idWords );
                        } );
        idTerms = idWords;
        toTermSet( idTerms );

        std::size_t inter = 0, uni = 0;
        jaccardCounts( commentTerms, idTerms, inter, uni );
        const double cic = uni != 0 ? double( inter ) / double( uni ) : 0.0;   // both sets empty: degenerate, disclosed here

        CommentCoherenceRow row;
        row.id                 = NodeId( symbolIndex );
        row.cCoeff              = cCoeff;
        row.cic                 = cic;
        row.commentWordCount    = std::uint32_t( commentWords.size() );
        row.restatingWordCount  = restating;
        row.commentTermCount    = std::uint32_t( commentTerms.size() );
        row.idTermCount         = std::uint32_t( idTerms.size() );
        row.sharedTermCount     = std::uint32_t( inter );
        scan.rows.push_back( row );
    }

    // Primary order: c_coeff DESCENDING — the "mostly restates the name" rows lead, matching the
    // headline direction this lens exists to surface (header note: HIGH c_coeff IS BAD). cic is reported
    // on every row but is NOT the sort key: the two axes are expected to disagree (header note), so cic
    // breaks ties only (ascending — low term-overlap alongside a name-restating comment is the worst
    // combination), then the symbol id (already assigned in file/line/name order).
    std::sort( scan.rows.begin(), scan.rows.end(),
               []( const CommentCoherenceRow& a, const CommentCoherenceRow& b ) noexcept
               {
                   if( a.cCoeff != b.cCoeff )
                   {
                       return a.cCoeff > b.cCoeff;
                   }
                   if( a.cic != b.cic )
                   {
                       return a.cic < b.cic;
                   }
                   return a.id < b.id;
               } );
    return scan;
}

inline constexpr const char* kCommentCoherenceLegend =
    "<!-- ripwire comment-coherence: two content measures per documented function/method, MOST NAME-RESTATING FIRST. "
    "p=path:line n=symbol name "
    "c_coeff=Steidl/Hummel/Juergens coherence coefficient (ICPC 2013): fraction of the comment's words within "
    "Levenshtein distance under 2 of a word in the symbol's own (split) name. HIGH c_coeff IS BAD: it means the "
    "comment mostly repeats the name and adds no information; this is the OPPOSITE of the naive 'high coherence "
    "sounds good' reading. words=the comment's total word count (c_coeff's denominator, UNFILTERED: stopwords "
    "kept, matching the paper) restate=the numerator, words that matched a name word "
    "cic=Scalabrino Comments-Identifiers Consistency (ICPC 2016 / JSEP 2018): Jaccard overlap of two "
    "method-local TERM SETS: the comment's vocabulary vs every identifier the definition's own span uses "
    "(parameters, locals, callees, fields), both preprocessed (operators/keywords stripped by construction, "
    "camelCase/snake_case split, English stopwords dropped, deduplicated). "
    "c_terms=|Comments(m)| i_terms=|Ids(m)| shared=size of their overlap; from these, cic = shared/(c_terms+i_terms-shared). "
    "c_coeff and cic measure DIFFERENT things and are expected to DISAGREE: report both, never collapse to one "
    "number. Fires ONLY where a doc comment actually exists immediately above the definition; a symbol with none "
    "(or one that tokenizes to zero words) is UNAVAILABLE for this measure, never scored: counted in no_comment=, "
    "never as a zero. Complements doc-drift, which checks markdown CLAIM staleness, a disjoint axis over disjoint "
    "input; this verb never checks staleness and doc-drift never checks content. "
    "documented=functions/methods measured (rows emitted) no_comment=eligible symbols with nothing to measure "
    "unreadable_files=indexed files this pass could not read; their functions are absent, so documented= is a FLOOR "
    "shown=rows printed capped=1 when rows were dropped; raise the default cap with limit=N (offset=M pages), "
    "which also prints total= has_more= next_offset= offset= limit= -->";

inline int writeCommentCoherenceReport( const IngestResult& ing, int pageLimit, int pageOffset )
{
    const CommentCoherenceScan scan  = computeCommentCoherence( ing );
    const std::size_t          total = scan.rows.size();
    const PageWindow            page  = pageWindow( total, effectiveRowCap( pageLimit, int( kCommentCoherenceRowCap ) ), pageOffset );
    const std::size_t           shown = page.end > page.begin ? page.end - page.begin : 0;

    char disclosure[kPageDisclosureCap];
    pageDisclosure( disclosure, sizeof disclosure, shown, total, page.end, pageLimit, pageOffset, true );

    std::fputs( kCommentCoherenceLegend, stdout );
    std::printf( "<comment_coherence documented=\"%zu\" no_comment=\"%u\"%s", total, scan.noCommentCount, disclosure );
    if( scan.unreadableFileCount != 0 )
    {
        std::printf( " unreadable_files=\"%u\"", scan.unreadableFileCount );
    }
    std::printf( ">" );

    std::vector<char> escPath;
    std::vector<char> escName;
    for( std::size_t rowIndex = page.begin; rowIndex < page.end; ++rowIndex )
    {
        const CommentCoherenceRow& row  = scan.rows[rowIndex];
        const Symbol&               s    = ing.symbols[row.id];
        const std::string           path( escapeXml( ing.files[s.fileId], escPath ) );
        const std::string           name( escapeXml( s.name, escName ) );
        std::printf( "<fn p=\"%s:%u\" n=\"%s\" c_coeff=\"%.3f\" words=\"%u\" restate=\"%u\" "
                     "cic=\"%.3f\" c_terms=\"%u\" i_terms=\"%u\" shared=\"%u\"/>",
                     path.c_str(), s.line, name.c_str(),
                     row.cCoeff, row.commentWordCount, row.restatingWordCount,
                     row.cic, row.commentTermCount, row.idTermCount, row.sharedTermCount );
    }
    std::printf( "</comment_coherence>" );
    return 0;
}

}   // namespace rw
