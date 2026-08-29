#pragma once

// queryshape.h — what SHAPE is this query, as a fact about the query text alone.
//
// The ranking lenses treat every --for/--pack-task query the same way, which is right for a conceptual
// phrase and wrong for the two artefacts agents paste most often:
//
//   * a TRACE — a stack trace, a sanitizer report, a compiler diagnostic. The answer is code by
//     construction; a README or a changelog whose prose happens to match the failure excerpt is never it.
//   * a BUG-REPORT FORM — a pasted issue whose template scaffolding survived the paste. The repository's
//     own `.github/ISSUE_TEMPLATE/*.md` is written in exactly that vocabulary, so the strongest lexical
//     match for the form is the form.
//
// This header answers ONLY "which shape is this text" — it knows nothing about paths, symbols, or scores.
// The path half (which files are documents, which are repository meta-prose) and the multiplier live in
// filter.h beside the tier table they extend; keeping the two halves apart is what stops a second copy of
// either classifier from appearing.
//
// TRACE DETECTION REUSES --from-trace'S OWN FRAME EXTRACTOR (tracein.h) and does not add a second parser.
// That is a deliberate trade: the shape verdict inherits that extractor's coverage exactly, including its
// blind spots. A Go panic's `\t/path/file.go:23 +0x1d` frame carries a trailing offset, so neither the
// compiler shape (no diagnostic colon) nor the generic shape (the whole line must be the location) claims
// it, and a Go panic pasted alone is therefore NOT trace-shaped here. That is a miss, not a wrong answer:
// the query ranks exactly as it does today. One extractor with a known gap beats two extractors that
// disagree.
//
// CONSERVATISM IS THE WHOLE DESIGN. A false positive demotes documents for someone who was legitimately
// asking about documents, so both detectors are built to under-fire:
//   * generic `path:line` frames alone never decide the trace shape — that is the space a URL with a port
//     and a `Type.py:12` mention live in;
//   * a bug-report label counts only where it is used as a LABEL (at a line start, or behind markdown
//     heading / bullet / emphasis punctuation), never inside a sentence, and TWO DISTINCT families must
//     fire. "where do we document the expected behavior and the steps to reproduce" scores zero.
// The escape hatch survives either way: the demotion is a shrink-only multiplier, and the query-mention
// anchor runs after it, so a document the query literally names is still lifted.

#include "tracein.h"   // extractFrames / FrameFormat — the SHIPPED frame extractor, never a second one

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace rw
{
namespace queryshape
{

// ── the bug-report form vocabulary, one row per FAMILY ──────────────────────────────────────────────────
// Rows are families, not phrases, so "expected behavior" and "expected behaviour" cannot both count toward
// the two-family threshold. Spellings are lowercase; the query is lowercased once before matching. An
// empty slot ends a row.
struct FormLabel
{
    const char*      family;
    std::string_view spellings[ 3 ];
};

inline constexpr FormLabel kFormLabels[] = {
    { "describe-the-bug",   { "describe the bug", "bug description", "describe the issue" } },
    { "steps-to-reproduce", { "steps to reproduce", "reproduction steps", "to reproduce" } },
    { "expected",           { "expected behavior", "expected behaviour", "expected result" } },
    { "actual",             { "actual behavior", "actual behaviour", "current behavior" } },
    { "additional-context", { "additional context", "additional information", "anything else" } },
    { "screenshots",        { "screenshots", "screenshot" } },
    { "environment",        { "system information", "environment", "version information" } },
    { "repro-example",      { "minimal reproducible example", "reproducible example", "minimal example" } },
    { "feature-request",    { "is your feature request related to a problem", "describe the solution",
                              "describe alternatives" } },
};

inline constexpr std::size_t kFormLabelCount = sizeof( kFormLabels ) / sizeof( kFormLabels[0] );

// A markdown task-list checkbox is its own family — a pasted form often carries the boxes even when its
// headings were edited away.
inline constexpr std::string_view kCheckboxSpellings[] = { "- [ ]", "- [x]", "* [ ]", "* [x]" };

// TWO distinct families, never one: a single template phrase appears in ordinary prose about templates.
inline constexpr std::size_t kMinFormFamilies = 2;

// the verdict — both flags can be true (a bug report that pastes its traceback), and the multiplier only
// asks whether EITHER did, so there is no precedence rule to get wrong.
struct Verdict
{
    bool        trace         = false;
    bool        bugReport     = false;
    std::size_t frameCount    = 0;    // frames the shipped extractor read out of the query
    const char* frameFormat   = "";   // the dominant format's own label ("python", "asan", …)
    std::size_t formFamilies  = 0;    // distinct bug-report label families that fired

    bool fires() const noexcept { return trace || bugReport; }
};

namespace detail
{

inline std::string lowerAscii( std::string_view text )
{
    std::string out;
    out.reserve( text.size() );
    for( const char ch : text )   // EXPLICIT narrowing, as elsewhere in this tree
    {
        const unsigned char c = static_cast<unsigned char>( ch );
        out.push_back( ( c >= 'A' && c <= 'Z' ) ? char( c - 'A' + 'a' ) : char( c ) );
    }
    return out;
}

// The head of one line with a form's own scaffolding stripped: leading blanks, markdown heading / bullet /
// emphasis / quote marks, and an ordered-list "1." / "2)" prefix. Whatever remains is where a FIELD LABEL
// would begin if this line carries one — and a line head is what a form label literally is, which is why
// the match below is line-oriented rather than a search over the whole text. A phrase found anywhere is
// what over-fires on prose; a phrase found at the head of its own line does not.
inline std::string_view labelHeadOf( std::string_view line ) noexcept
{
    std::size_t k = 0;
    while( k < line.size() )
    {
        const char c = line[k];
        const bool scaffold = c == ' ' || c == '\t' || c == '\r' || c == '#' || c == '*' || c == '-'
                           || c == '_' || c == '>' || c == '|' || c == '+' || c == '.' || c == ')'
                           || c == ':' || ( c >= '0' && c <= '9' );
        if( !scaffold )
        {
            break;
        }
        ++k;
    }
    return line.substr( k );
}

} // namespace detail

// The classifier. Pure over the query text: no I/O, no corpus, no allocation beyond one lowercased copy,
// so two runs on the same text agree by construction.
inline Verdict classify( std::string_view query )
{
    Verdict v;

    // ── trace ────────────────────────────────────────────────────────────────────────────────────────
    // A frame whose shape is SPECIFIC (python `File "…", line N`, an ASan `#N … in`, a node `at fn (…)`,
    // a compiler `path:line:col:` diagnostic) is on its own enough. Generic `path:line` frames are not —
    // they need a second frame-shaped line to corroborate, which prose that merely mentions a location
    // never has.
    const tracein::FrameScan scan = tracein::extractFrames( query );
    std::size_t              specificFrames = 0;
    for( const tracein::ParsedFrame& f : scan.frames )
    {
        if( f.format != tracein::FrameFormat::Generic )
        {
            ++specificFrames;
        }
    }
    v.trace      = specificFrames > 0 || ( !scan.frames.empty() && scan.frameShapedLines >= 2 );
    v.frameCount = scan.frames.size();
    if( v.trace )
    {
        v.frameFormat = tracein::formatSpec( tracein::dominantFormat( scan.frames ) ).label;
    }

    // ── bug-report form ──────────────────────────────────────────────────────────────────────────────
    const std::string lower = detail::lowerAscii( query );
    bool              fired[ kFormLabelCount ] = {};
    for( std::size_t start = 0; start <= lower.size(); )
    {
        const std::size_t      nl   = lower.find( '\n', start );
        const std::size_t      end  = ( nl == std::string::npos ) ? lower.size() : nl;
        const std::string_view head = detail::labelHeadOf( std::string_view( lower ).substr( start, end - start ) );
        start = ( nl == std::string::npos ) ? lower.size() + 1 : nl + 1;

        for( std::size_t r = 0; r < kFormLabelCount; ++r )
        {
            for( std::string_view phrase : kFormLabels[r].spellings )
            {
                if( !phrase.empty() && head.starts_with( phrase ) )
                {
                    fired[r] = true;   // one family, one vote, however many lines spell it
                    break;
                }
            }
        }
    }
    for( const bool hit : fired )
    {
        v.formFamilies += hit ? 1u : 0u;
    }
    for( std::string_view box : kCheckboxSpellings )
    {
        if( lower.find( box ) != std::string::npos )
        {
            ++v.formFamilies;
            break;   // the checkbox family votes once however many boxes there are
        }
    }
    v.bugReport = v.formFamilies >= kMinFormFamilies;

    return v;
}

} // namespace queryshape
} // namespace rw
