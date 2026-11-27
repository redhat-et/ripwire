// main.cpp — parse one record from a fixed string.
#include <string>

#include "parser.h"

int main()
{
    const std::string record = "head er\nbody text here #foot";
    int at = parseHeader( record, 0 );
    at = parseBody( record, at );
    return parseFooter( record, at ) > 0 ? 0 : 1;
}
