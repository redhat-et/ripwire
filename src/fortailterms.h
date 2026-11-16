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
#include <cstddef>
#include <cstdlib>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// The names one code tail row may ADD after its own sym= names (never in their place). Knob: reports/knob-census.md ADDENDUM
// 2026-11-14 (tail-sym-terms): +0.9-1.2 KB median per terse answer, about +3.5 KB on the full question (lab T1/T5).
inline constexpr std::size_t kTailSymTermNames = 2;

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
        if( std::ranges::find( out, st ) == out.end() )
        {
            out.push_back( std::move( st ) );
        }
    }
    return out;
}

// How many distinct task words `name`'s own subtokens carry, each stemmed (0: the name shares none). `terms` is unique, so this is
// the count of distinct stemmed name subtokens among them.
inline std::size_t tailTermScore( std::string_view name, const std::vector<std::string>& terms )
{
    return std::size_t( subtokenOverlap( name, terms, tailterms_detail::kTailTermSuffixes ) );
}

}   // namespace rw
