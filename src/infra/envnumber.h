#pragma once

// envnumber.h — one environment variable read as a whole decimal number. The knob readers (forpage.h's tail-width
// knob, memceiling.h's budget knob) share it, so each states only its own range and its
// own reply to a bad value: whether a malformed value is refused or read as the default is the caller's decision.

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
