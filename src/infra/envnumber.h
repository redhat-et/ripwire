#pragma once

// envnumber.h — one environment variable read as a whole decimal number. Every knob reader in the host tree shares it,
// so this file decides nothing about any one knob: the range a value must fall in, and the reply to a bad one — refuse
// the run, or fall back to the default — belong to the caller. That is why the result carries `set` and `parsed` as
// separate bits rather than one bool: "absent" and "present but malformed" are different answers, and only the caller
// knows which of them is an error.

#include <charconv>
#include <cstdint>
#include <cstdlib>   // std::getenv
#include <string_view>

namespace rw
{
struct EnvNumber
{
    bool             set    = false;   // the variable exists (it may be empty)
    bool             parsed = false;   // non-empty, and every character a digit of one in-range number
    std::uint64_t    value  = 0;       // valid only when parsed
    std::string_view text;             // the raw value ("" when unset)
};
inline EnvNumber readEnvNumber( const char* name ) noexcept
{
    EnvNumber   n;
    const char* v = std::getenv( name );
    if( v == nullptr )
    {
        return n;
    }
    n.set  = true;
    n.text = std::string_view( v );
    const auto [ end, ec ] = std::from_chars( n.text.data(), n.text.data() + n.text.size(), n.value );
    n.parsed = !n.text.empty() && ec == std::errc() && end == n.text.data() + n.text.size();
    return n;
}
} // namespace rw
