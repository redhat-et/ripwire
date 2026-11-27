// test_parser.cpp — the record parser's header, body and footer on small records.
#include <cassert>
#include <string>

#include "../src/parser.h"

int main()
{
    assert( parseHeader( "a b\nc", 0 ) == 4 );
    assert( parseBody( "x y #z", 0 ) == 4 );
    assert( parseFooter( "#z", 0 ) == 2 );
    return 0;
}
