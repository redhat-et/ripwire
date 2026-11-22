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
// (docs/METHODOLOGY.md §9): an answer under it is byte-identical to before, and every cut it causes is disclosed on the root.
//
// It counts BYTES, which is never fewer than characters, so a byte-bounded answer is character-bounded too.
//
// The verbs that read it (each cuts its OWN unit; test/outputceilingcheck.sh pins every one):
//   --lint      findings (<f> rows): a byte-budgeted sorted prefix, continued by next="--lint … --offset=K" (verbs_lint.h)
//   --expand    body lines: the default --pack-budget-bytes leaves the answer under the ceiling; a cut body says lines="lo-hi/T"
//               and next= names the slice that continues it (serialize.h)
#include <cstddef>

namespace rw
{

inline constexpr std::size_t kHarnessInlineChars = 30000;                                    // Claude Code Bash tool's inline ceiling (docs, above)
inline constexpr std::size_t kOutputCeilingChars = kHarnessInlineChars - kHarnessInlineChars / 5;   // 24,000: the inline limit less 20 %

}   // namespace rw
