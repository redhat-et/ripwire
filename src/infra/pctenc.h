#pragma once
// pctenc.h — append a string percent-encoded (`%XX`, upper-case hex), escaping exactly the bytes a caller names.
//
// WHY THIS EXISTS. lsp.h's file-URI path encoder and recall.h's path-list header attributes (demoted_names=,
// mirror_dirs=) each spelled the same byte loop out — `%` plus two digits from a table for a reserved byte, the byte
// itself otherwise — with different reserved sets. --quality-delta flagged the second as a clone of the first.
// The reserved set is the only thing that differs, so it is the parameter; control bytes and DEL are always
// escaped, because no caller can carry them raw.

#include <string>
#include <string_view>

namespace rw
{

// `isReserved( unsigned char )` names the printable bytes to escape on top of the control bytes and DEL.
template< typename IsReserved >
inline void appendPercentEncoded( std::string& out, std::string_view s, IsReserved isReserved )
{
    static constexpr char kHex[] = "0123456789ABCDEF";
    for( const char ch : s )
    {
        const auto byte = static_cast<unsigned char>( ch );
        if( byte == '%' || byte < 0x20 || byte == 0x7F || isReserved( byte ) )
        {
            out += '%';
            out += kHex[ byte >> 4 ];
            out += kHex[ byte & 0x0F ];
        }
        else
        {
            out += ch;
        }
    }
}

}   // namespace rw
