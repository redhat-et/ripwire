#pragma once
// fortailterms.h — TAIL-SYM-TERMS (G2 of the depth lab, reports/depth-gc-lab-1114.md; owner GO 2026-11-14): the task words a
// --for tail row's sym= may add names by, and how a symbol NAME scores against them.
//
// THE RULE (the lab's frozen emulation, tmp/depth-gc-lab/emul.py task_terms/sym_score, ported as is):
//   task words: the task's identifier subtokens (lexical.h subtokens: camelCase, snake_case and acronym seams, lowercased) of
//               3+ bytes, not all digits and not on kTailTermStop, each light-stemmed (kTailTermSuffixes), unique in task order;
//   a name's score: how many distinct task words are among the stems of the name's own subtokens (2+ bytes). The NAME only:
//               a body or doc hit does not count (the lab scored names; lexical.h anyMask counts every field).
// HOW IT DIFFERS FROM THE --for RANKER'S TERMS (lexical.h LexTermEvidence): the ranker keeps every 2+ byte subtoken of the task
// (no stop list: its IDF does that work) and matches exact subtokens (its stem variants are a guarded, IDF-admitted side table).
// A name slot has no IDF to lean on, so this rule drops question glue ("which", "function", "file", "call") outright and
// stems both sides, as the lab measured it (`plans` meets restorePlanHook's `Plan`).
// Kept apart from forfilesyms.h matchWords (the <syms> block's words): that list and stemmer were measured on <syms>, this one
// on the tail (the two differ in ~40 stop words and in the -er/-ation suffixes); one moving would move the other's numbers.

#include "infra/sortutil.h" // svLess: the stop list's byte order (the Linux G1 leg aborts on the default comparator)
#include "lexical.h"   // subtokens — the shared identifier splitter

#include <algorithm>
#include <array>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// The names one code tail row may ADD after its own sym= names (never in their place). Knob: reports/knob-census.md ADDENDUM
// 2026-11-14 (tail-sym-terms): +0.9-1.2 KB median per terse answer, about +3.5 KB on the full question (lab T1/T5).
inline constexpr std::size_t kTailSymTermNames = 2;

// TSYM-WRONG-DECOYS (2026-11-16): a name is added only on DISTINCTIVE evidence. The lane's first cut printed ~14.5 k names on fire321
// (+5.4 % bytes) and 3 gold-WRONG decoys (a backup hook for a restore question, the Windows loop for a Linux one, the AOT compiler's
// handler for the runtime decorator): a name holding ONE common task word, or one of many names of a file that is all about that word.
//   kTailSymTermFileMatches: the file holds at most this many symbols whose names share a task word. More, and the word is the
//                            file's own topic (its sym= already speaks to it); a name picked among them by PageRank is a guess.
//   kTailSymTermEvidence:    the name and its file's PATH together carry at least this many DISTINCT task words, so one generic
//                            word ("plan", "create", "template") with nothing else of the question behind it adds nothing.
// Measured offline on the lane's fire321 (tmp/tsym-decoys/lab): 740 of 14,490 names kept, 3 of the 6 item gains (the other 3 are
// one-word or whole-file matches, indistinguishable from the decoys), 0 of the 3 decoys. Knob census ADDENDUM 2026-11-16.
inline constexpr std::size_t kTailSymTermFileMatches = 3;
inline constexpr std::size_t kTailSymTermEvidence    = 2;
// A task has at most this many words (tailTermMask's bits); later words are dropped. A --for task is a sentence or a question.
inline constexpr std::size_t kTailTermMaxWords = 64;

// The legend clause defining tsym=, present-only: spliced right after the tail clause (serialize.h kForFileTailLegend; the compact
// twin after verbs_for.h kForCompactLegendTail) only when a shown row carries it (forpage.h fileTailTermNamesShown), so an answer
// whose tail gained no name keeps its bytes. The JSON answer has no legend: "tsym_why" rides beside "tsym". No "--" (XML comment).
inline constexpr std::string_view kForFileTailTermsLegend =
    "; tail tsym= up to 2 more of that file's symbols whose names share a task word (stemmed; question words such as which, function, "
    "file are ignored), best match first, after sym= and never in its place: a name match, not a lens rank";
inline constexpr std::string_view kForCompactFileTailTermsLegend = "; t tsym= up to 2 more file symbols named by a task word (a name match)";
inline constexpr std::string_view kForFileTailTermsWhy = "up to 2 more of the file's symbols whose names share a task word, after sym (a name match, not a lens rank)";
static_assert( kTailSymTermNames == 2 && kForFileTailTermsLegend.contains( "up to 2 " ) && kForCompactFileTailTermsLegend.contains( "up to 2 " )
                   && kForFileTailTermsWhy.contains( "up to 2 " ) && !kForFileTailTermsLegend.contains( "--" )
                   && !kForCompactFileTailTermsLegend.contains( "--" ),
               "every TAIL-SYM-TERMS clause spells kTailSymTermNames (move them with it); the legend ones carry no \"--\"" );

// RIPWIRE_NO_TAIL_SYM_TERMS=1: the pre-card tail (no name added), the ablation arm of test/tailsymtermscheck.sh and of the lane's
// measurement. Any other value, or unset, reads the default.
inline bool tailSymTermsOn()
{
    const char* v = std::getenv( "RIPWIRE_NO_TAIL_SYM_TERMS" );
    return v == nullptr || std::string_view( v ) != "1";
}

namespace tailterms_detail
{
// The lab's stop list (emul.py STOP), sorted for binary search: question words and code-generic nouns no name is about.
inline constexpr std::array<std::string_view, 177> kTailTermStop {
    "a", "actually", "all", "also", "an", "and", "any", "are", "as", "at", "be", "been", "being", "by", "call", "called", "callee",
    "callees", "caller", "callers", "calls", "can", "chain", "class", "classes", "code", "could", "describe", "did", "do", "does",
    "done", "each", "else", "end", "every", "example", "explain", "file", "files", "finally", "find", "first", "for", "from",
    "function", "functions", "get", "gets", "got", "handle", "handled", "handles", "happen", "happens", "here", "hop", "hops",
    "how", "i", "if", "implement", "implementation", "implemented", "in", "into", "is", "it", "it's", "its", "just", "last",
    "least", "less", "line", "lines", "made", "make", "makes", "many", "may", "me", "method", "methods", "might", "module",
    "modules", "more", "most", "much", "must", "my", "name", "names", "need", "needs", "new", "no", "not", "of", "old", "on",
    "one", "only", "onto", "or", "orient", "our", "over", "part", "parts", "path", "per", "point", "points", "set", "sets",
    "shall", "should", "show", "shown", "shows", "some", "step", "steps", "tell", "than", "that", "the", "their", "them", "then",
    "there", "these", "they", "thing", "things", "this", "those", "three", "through", "to", "two", "under", "use", "used", "uses",
    "using", "very", "via", "want", "was", "way", "ways", "we", "were", "what", "when", "where", "where's", "which", "who", "whom",
    "whose", "why", "will", "with", "without", "work", "works", "would", "write", "writes", "written", "yes", "you", "your"
};
static_assert( std::ranges::is_sorted( kTailTermStop, rw::sortutil::svLess ), "kTailTermStop is binary-searched: keep it sorted" );

// The lab's suffix stem (emul.py stem): the first suffix that leaves 3+ bytes is cut; -ies becomes -y.
inline constexpr std::array<std::string_view, 10> kTailTermSuffixes { "ations", "ation", "ings", "ing", "ers", "er", "ies", "es", "ed", "s" };
}   // namespace tailterms_detail

// The task's words a tail name can share, in task order, unique (empty: no row gains a name).
inline std::vector<std::string> tailTaskTerms( std::string_view task )
{
    using namespace tailterms_detail;
    std::vector<std::string> raw, out;
    subtokens( task, raw );
    for( std::string& w : raw )
    {
        const bool digits = std::ranges::all_of( w, []( char c ) { return c >= '0' && c <= '9'; } );
        if( w.size() < 3 || digits || std::ranges::binary_search( kTailTermStop, std::string_view( w ), rw::sortutil::svLess ) )
        {
            continue;
        }
        std::string st = suffixStem( std::move( w ), kTailTermSuffixes );
        if( out.size() < kTailTermMaxWords && std::ranges::find( out, st ) == out.end() )
        {
            out.push_back( std::move( st ) );
        }
    }
    return out;
}

// Which task words `text`'s own subtokens (2+ bytes, each stemmed) carry: bit i is terms[i] (tailTaskTerms keeps at most
// kTailTermMaxWords). Read for a symbol NAME (its score is the popcount) and for its file's PATH (the co-evidence of
// kTailSymTermEvidence): a path's subtokens split on '/' and '.' like any other non-identifier byte.
inline std::uint64_t tailTermMask( std::string_view text, const std::vector<std::string>& terms )
{
    std::vector<std::string> toks;
    subtokens( text, toks );
    std::uint64_t mask = 0;
    for( std::string& t : toks )
    {
        const std::string st = suffixStem( std::move( t ), tailterms_detail::kTailTermSuffixes );
        if( const auto it = std::ranges::find( terms, st ); it != terms.end() && it - terms.begin() < std::ptrdiff_t( kTailTermMaxWords ) )
        {
            mask |= std::uint64_t( 1 ) << ( it - terms.begin() );
        }
    }
    return mask;
}

}   // namespace rw
