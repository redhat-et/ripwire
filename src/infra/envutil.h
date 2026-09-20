#pragma once

#include <cstdlib>
#include <string>

// envutil.h — envOr, in one place. Was byte-identical in codexdoctor.h and skillsinstall.h; a
// second copy is exactly the drift risk CLAUDE.md's reuse-first rule exists to close.
namespace rw
{

// Empty is treated as unset, the rule every `${VAR:-default}` read in this codebase follows.
inline std::string envOr( const char* name, std::string fallback )
{
    const char* value = std::getenv( name );
    return ( value && *value ) ? std::string( value ) : std::move( fallback );
}

} // namespace rw
