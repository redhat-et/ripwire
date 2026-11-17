// sitesatshort_unit.cpp — the (U) half of test/sitesatshortcheck.sh: rw::siteTokensFor (src/sitetokens.h) on the caller rows
// no index the CLI builds can produce. Every site of a caller is in the caller's own file today (Reference::fromSymbol is
// assigned per file), so the cross-file token, the mixed row and the all-digit-fragment row are reachable ONLY here. A
// rule no fixture reaches is still code the next change can break, so each is pinned on synthetic rows. The driver also
// prints each row as `ROW <p file>|<legacy value>|<new value>` so the shell arm can put it through the same
// reconstruction it applies to real answers. Exit 0 = every case holds; the driver FAILs when it ran no case.

#include "sitetokens.h"

#include <cstdio>
#include <string>
#include <string_view>
#include <vector>

namespace
{

int failures = 0;
int cases    = 0;

// One row: the tokens the rule prints must be exactly `want`, in order. The ROW line carries the row's p= file, the value
// it had before the short form (every site as file:line) and the value it has now, each space-separated.
void expectRow( std::string_view what, std::string_view rowFile, const std::vector<rw::SpelledSite>& sites, const std::vector<std::string>& want )
{
    const std::vector<std::string> got = rw::siteTokensFor( rowFile, sites );
    ++cases;
    failures += got == want ? 0 : 1;
    std::printf( "  %s  %.*s\n", got == want ? "PASS" : "FAIL", int( what.size() ), what.data() );
    std::printf( "ROW %.*s|", int( rowFile.size() ), rowFile.data() );
    for( std::size_t i = 0; i < sites.size(); ++i )
    {
        std::printf( "%s%s:%u", i == 0 ? "" : " ", sites[i].first.c_str(), unsigned( sites[i].second ) );
    }
    std::printf( "|" );
    for( std::size_t i = 0; i < got.size(); ++i )
    {
        std::printf( "%s%s", i == 0 ? "" : " ", got[i].c_str() );
    }
    std::printf( "\n" );
}

void expectFlag( std::string_view what, std::string_view path, bool want )
{
    ++cases;
    const bool got = rw::pathReadsAsBareLine( path );
    std::printf( "  %s  %.*s\n", got == want ? "PASS" : "FAIL", int( what.size() ), what.data() );
    failures += got == want ? 0 : 1;
}

} // namespace

int main()
{
    // the common row: every site in the row's own file
    expectRow( "same file: bare lines only", "a.c", { { "a.c", 8 }, { "a.c", 9 }, { "a.c", 10 } }, { "8", "9", "10" } );
    expectRow( "a site ABOVE the definition line is still a bare line (no delta, no sign)", "arguments.c", { { "arguments.c", 512 } }, { "512" } );
    expectRow( "own path with a space: bare lines, the path is not printed at all", "my dir/sp.py", { { "my dir/sp.py", 3 }, { "my dir/sp.py", 4 } }, { "3", "4" } );
    expectRow( "own path with an all-digit fragment: still bare (the path is not in the value)", "d 12 x/own.py", { { "d 12 x/own.py", 3 } }, { "3" } );

    // the rows nothing reaches today
    expectRow( "cross-file: a foreign site keeps its FULL token", "a.c", { { "b.c", 4 } }, { "b.c:4" } );
    expectRow( "mixed row: bare for the own file, full for the other", "a.c", { { "a.c", 8 }, { "b.c", 4 }, { "a.c", 9 } }, { "8", "b.c:4", "9" } );
    expectRow( "a prefix is not equality: a.c vs a.cpp stays full", "a.c", { { "a.cpp", 2 } }, { "a.cpp:2" } );
    expectRow( "spelling, not identity: ./a.c is not a.c", "a.c", { { "./a.c", 2 } }, { "./a.c:2" } );
    expectRow( "foreign path with a space but no all-digit fragment: still mixed", "a.c", { { "a.c", 8 }, { "my dir/b.c", 4 } }, { "8", "my dir/b.c:4" } );

    // the all-digit fragment: the WHOLE row goes full, so no bare line stands beside the fragment
    expectRow( "foreign path with an all-digit fragment: the whole row is full form", "a.c", { { "a.c", 8 }, { "d 12 x/b.c", 4 }, { "a.c", 9 } },
               { "a.c:8", "d 12 x/b.c:4", "a.c:9" } );
    expectRow( "leading all-digit fragment: whole row full", "a.c", { { "a.c", 8 }, { "12 b.c", 4 } }, { "a.c:8", "12 b.c:4" } );
    expectRow( "tab-delimited all-digit fragment: whole row full", "a.c", { { "a.c", 8 }, { "d\t7\tb.c", 4 } }, { "a.c:8", "d\t7\tb.c:4" } );
    expectRow( "a trailing digit fragment carries :line, so it is no bare line: mixed", "a.c", { { "a.c", 8 }, { "d 12", 4 } }, { "8", "d 12:4" } );

    expectFlag( "pathReadsAsBareLine: plain path", "src/a.c", false );
    expectFlag( "pathReadsAsBareLine: digits inside a name", "v2/a12.c", false );
    expectFlag( "pathReadsAsBareLine: space, no digit fragment", "my dir/a.c", false );
    expectFlag( "pathReadsAsBareLine: middle fragment", "d 12 x/a.c", true );
    expectFlag( "pathReadsAsBareLine: last fragment only", "d 12", false );
    expectFlag( "pathReadsAsBareLine: empty", "", false );

    std::printf( "%s: %d case(s), %d failure(s)\n", failures == 0 && cases > 0 ? "OK" : "FAIL", cases, failures );
    return failures == 0 && cases > 0 ? 0 : 1;
}
