#pragma once
// outputceiling.h — CL1 (owner ruling 2026-11-21): THE OUTPUT CEILING. No DEFAULT call prints more than an agent harness shows
// inline; a larger answer pages itself by its OWN unit and names the next page as a pasteable next=.
//
// WHY THIS NUMBER. Claude Code's documented limits (code.claude.com/docs, read 2026-11-21):
//   * Bash tool, "Output limits": a valid result arrives "Inline up to roughly 30,000 characters by default; past that, the
//     path of a file saved to the session directory ... plus a preview of up to the first 2,000 characters". BASH_MAX_OUTPUT_LENGTH
//     "doesn't raise the inline ceilings: a valid result over the inline ceiling arrives as a file path plus preview regardless
//     of this variable". A FAILED command (a non-zero exit outside grep/find/diff…) gets "roughly 10,000 characters", a
//     head-and-tail excerpt.
//   * MCP: a result is saved to a file past MAX_MCP_OUTPUT_TOKENS (default 25,000 tokens) or past 50,000 characters.
// MEASURED once (TR1, ga-zod-12): a 30,849 B answer reached the agent as a 2,295-char preview — the answer never arrived.
// So the ceiling is the 30,000-character inline limit less 20 %: kOutputCeilingChars. It is a CONSTRAINT, not a target
// (docs/METHODOLOGY.md §9): an answer under it is byte-identical to before — one disclosed exception: a bare --expand whose
// symbol's file is 16-64 KB now says reason="whole-file NB over pack-budget 16000B" (that file is no longer a candidate) —
// and every cut it causes is disclosed on the root.
//
// It counts BYTES, which is never fewer than characters, so a byte-bounded answer is character-bounded too.
//
// The verbs that read it (each cuts its OWN unit; test/outputceilingcheck.sh pins every one):
//   --lint      findings (<f> rows): a byte-budgeted sorted prefix, continued by next="--lint … --offset=K" (verbs_lint.h)
//   --expand    body lines: the default --pack-budget-bytes leaves the answer under the ceiling; a cut body says lines="lo-hi/T"
//               and next= names the slice that continues it (serialize.h)
//   --batch     whole <q> sub-answers: offset= shown= has_more= next_offset= and next="--batch=FILE --offset=K" on the root; a <q>
//               larger than a page is served alone and whole, over_ceiling="1" plus one stderr line; --page-bytes=0 is the whole
//               batch (batchpage.h). Research audit 2026-11-26 item 2: the MCP twin pages the same unit (#774).
//   --for --page-bytes=0   the whole answer by request: printed whole, plus ONE stderr line when it is over the ceiling
#include <cstddef>

namespace rw
{

inline constexpr std::size_t kHarnessInlineChars = 30000;                                    // Claude Code Bash tool's inline ceiling (docs, above)
inline constexpr std::size_t kOutputCeilingChars = kHarnessInlineChars - kHarnessInlineChars / 5;   // 24,000: the inline limit less 20 %

// The page a whole-unit verb serves: units [offset, end) and the bytes they take beside the page's fixed part.
struct WholeUnitPage
{
    std::size_t end  = 0;   // one past the last unit on the page
    std::size_t used = 0;   // fixedBytes plus the units' bytes; > ceiling only when one unit alone is over it
};

// From `offset`, as many WHOLE units as fit under `ceiling` beside `fixedBytes` (the root, the legend, the close), and never
// fewer than one: a unit larger than a page is served whole on its own page rather than cut, and the caller discloses it
// (used > ceiling). `units` is any sized range of strings or views; `offset` must be < units.size().
template <class Units>
[[nodiscard]] inline WholeUnitPage fitWholeUnits( const Units& units, std::size_t offset, std::size_t fixedBytes,
                                                  std::size_t ceiling = kOutputCeilingChars ) noexcept
{
    WholeUnitPage page{ offset, fixedBytes };
    while( page.end < units.size() && ( page.end == offset || page.used + units[ page.end ].size() <= ceiling ) )
    {
        page.used += units[ page.end ].size();
        ++page.end;
    }
    return page;
}

}   // namespace rw
