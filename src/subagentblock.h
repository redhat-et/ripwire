#pragma once
// subagentblock.h — THE THREE-MOMENT BRIEF BLOCK, the one constant two surfaces print: `ripwire wrap claude`'s blurb line (wrap.h)
// and the last section of `--brief` (brief.h). It lives in its own header so brief.h, which the MCP verbs include, can reach it
// without wrap.h (wrap.h includes mcp.h). The text is unchanged from wrap.h; test/subagentroutecheck.sh (M) still holds the hook's
// copy byte-equal to what `ripwire wrap claude` prints.
//
// What an orchestrator pastes into a subagent's brief (lane HK2, 2026-11-21). Three moments, each with its call, because lane RO1
// measured (observational, stored sessions) that an implementer subagent's first source action was ripwire in 5% of lanes whose
// brief said nothing (n=369) and 34-39% of lanes whose brief carried the routing (n=38, n=66), that the same protocol sitting in
// CLAUDE.md moved it to 6% (13 of 215), and that a NAMED verification verb was run in 90% of lanes against 47% unnamed. So the
// brief is the lever and each moment is named. No token saving is shown. Every verb but --for carries --legend=compact, the
// blurb's own posture (test/wrapverbscheck.sh arm 7 holds every command the blurb spells to it). One line, no newline: it rides on
// a blurb line, and hooks/ripwire-nudge.sh --agent-brief appends the same bytes to a spawn prompt (test/subagentroutecheck.sh (M)
// holds the two byte-equal).

#include <string_view>

namespace rw
{

inline constexpr std::string_view kSubagentBriefBlock =
    "ripwire is on PATH — before reading source, `ripwire <dir> --for=\"<task>\"`, Read its ranges in one turn; before the first edit, `--expand=SYM --legend=compact`, `--callers=SYM --legend=compact` or `--impact=SYM --legend=compact`; "
    "before reporting done, commit, then `--quality-delta=BASE..HEAD --legend=compact` and `--test-gate --legend=compact`.";

}   // namespace rw
