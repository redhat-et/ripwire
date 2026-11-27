// shstatus_harness.cpp — prints src/shstatus.h's calls in test/lib/exitstatus.py's CLI format, one
// `file:line<TAB>verdict<TAB>how<TAB>cmd` row per call, so test/gateexitcheck.sh arm (H4) can diff the two copies of the
// one matcher over every gate. Built by that arm from the header alone: c++ -std=c++23 -I src test/shstatus_harness.cpp.
#include "shstatus.h"

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>

int main( int argc, char** argv )
{
    int rc = 0;
    for( int a = 1; a < argc; ++a )
    {
        std::ifstream in( argv[a], std::ios::binary );
        if( !in )
        {
            std::printf( "%s:0\terror\tcannot read\t-\n", argv[a] );
            rc = 2;
            continue;
        }
        std::ostringstream ss;
        ss << in.rdbuf();
        const std::string src = ss.str();
        for( const rw::shstatus::Call& c : rw::shstatus::scan( src ) )
        {
            std::printf( "%s:%u\t%s\t%s\t%s\n", argv[a], c.line, c.verdict.c_str(), c.how.c_str(), c.cmd.c_str() );
        }
    }
    return rc;
}
