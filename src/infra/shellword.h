#pragma once
// shellword.h — the shell-word primitives the two shell readers share: darkflags.h (the Bash env lane) and
// shstatus.h (the B43 exit-status matcher's C++ port). Both grew the same whitespace trim and the same
// redirect-word test; --quality-delta flagged the second copy. They live in infra/ because neither reader
// may include the other: darkflags.h pulls in the ingest graph, and shstatus.h stays std-and-infra only so
// the H4 harness (test/shstatus_harness.cpp, compiled by test/gateexitcheck.sh) still builds it alone.

#include <cctype>
#include <cstddef>
#include <string_view>

namespace rw::shellword
{

// s without its leading and trailing ASCII whitespace (the C locale's isspace: space \t \n \v \f \r).
inline std::string_view trimView( std::string_view s )
{
    std::size_t a = 0, b = s.size();
    while( a < b && std::isspace( (unsigned char)s[a] ) )
    {
        ++a;
    }
    while( b > a && std::isspace( (unsigned char)s[b - 1] ) )
    {
        --b;
    }
    return s.substr( a, b - a );
}

// `<f`, `>f`, `2>f`, `<`: a redirection word (^\d*[<>]), which ends a keyword's name list (`read -r line < VERSION`
// writes `line`) and is never a command's operand.
inline bool shellIsRedirect( std::string_view word ) noexcept
{
    std::size_t k = 0;
    while( k < word.size() && std::isdigit( (unsigned char)word[k] ) )
    {
        ++k;
    }
    return k < word.size() && ( word[k] == '<' || word[k] == '>' );
}

}   // namespace rw::shellword
