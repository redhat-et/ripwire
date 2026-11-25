// forbodiesform.h — the SWITCH between the two forms of the bodies on a `--for` answer's first page (lane NB1, owner ruling 162;
// forbodyptr.h is the pointer form). Its own small header for the reason forrowsform.h has one: cli.h (the --bodies= flag's closed
// set) and forbodyptr.h (the rewrite) both decide with it and neither may include the other.
#pragma once

#include <cstdlib>
#include <string_view>

namespace rw::bodyptr
{

// THE SWITCH (ruling 162: inline by default, the pointer form behind a flag until a pre-registered live check says otherwise).
// `bodies` is --bodies= as typed: "inline" or "pointer" decide, whatever the environment says (FLAG OVER ENV, both ways, the
// --rows= precedent); empty — the flag was not typed — leaves it to RIPWIRE_BODY_POINTERS (any value = pointer), else inline.
// cli.h validateForClosedModifiers refuses any other value before a run.
inline constexpr std::string_view kBodiesInline  = "inline";
inline constexpr std::string_view kBodiesPointer = "pointer";
[[nodiscard]] inline bool bodyPointersOn( std::string_view bodies = {} ) noexcept
{
    return bodies.empty() ? std::getenv( "RIPWIRE_BODY_POINTERS" ) != nullptr : bodies == kBodiesPointer;
}

// THE EDIT-FILE FORM (lane θ17, default OFF): only the bodies in the file an edit task will edit become pointer rows (forbodyptr.h
// pointEditBodies). An environment knob only, below both switches above: --bodies= typed, or RIPWIRE_BODY_POINTERS set, decides first.
[[nodiscard]] inline bool bodyEditFormOn( std::string_view bodies = {} ) noexcept
{
    return bodies.empty() && std::getenv( "RIPWIRE_BODY_POINTERS" ) == nullptr && std::getenv( "RIPWIRE_BODIES_EDIT" ) != nullptr;
}

}   // namespace rw::bodyptr
