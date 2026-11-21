// forrowsform.h — the SWITCH between the two forms of a `--for` answer's <sigs>/<tail> rows (lane FMT2; forrowlines.h is the form).
// Its own small header because two places decide with it and neither may include the other: cli.h (the --rows= flag's closed
// set, and --version's rows=) and forrowlines.h (the encoder).
#pragma once

#include <cstdlib>
#include <string_view>

namespace rw::rowlines
{

// THE SWITCH (owner ruling 153: lines by default, both forms reachable). `rows` is --rows= as typed: "lines" or "elements" decide,
// whatever the environment says (the flag is the more specific ask, so FLAG OVER ENV, both ways); empty — the flag was not typed —
// leaves it to RIPWIRE_NO_ROWLINES (any value = elements), else lines. cli.h validateForClosedModifiers refuses any other value before a run.
inline constexpr std::string_view kRowsLines    = "lines";
inline constexpr std::string_view kRowsElements = "elements";
[[nodiscard]] inline bool rowLinesOn( std::string_view rows = {} ) noexcept
{
    return rows.empty() ? std::getenv( "RIPWIRE_NO_ROWLINES" ) == nullptr : rows == kRowsLines;
}
// The form this process serves by default, as --version discloses it (rows=).
[[nodiscard]] inline std::string_view defaultRowsName() noexcept { return rowLinesOn() ? kRowsLines : kRowsElements; }

}   // namespace rw::rowlines
