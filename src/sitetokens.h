#pragma once

// sitetokens.h — SITES-SHORT (2026-11-17): the ONE spelling of a caller row's call-site tokens (sites_at=).
//
// A caller row prints p="file:line" (where the CALLER is defined) and its call sites. Until this header a site was always
// the full `file:line` token, and the file was always the row's own: measured over 519,363 tokens in 314,017 rows of 17
// corpora, 0 named another file, so 75.5% of the attribute's bytes repeated the p= beside them and the line digits, the
// only new information, were 6.4%. `--edit-check`'s sites_l= already prints bare lines against its row's p=.
//
// THE RULE IS A STRING COMPARISON AT EMIT TIME, not that measurement:
//   * the site's file, spelled as the row spells it, EQUALS the row's p= file  -> the bare line;
//   * anything else                                                            -> the full `file:line` token, as before.
// So a row that one day does hold a foreign site (nothing reaches that today: Reference::fromSymbol is assigned by a
// per-file sweep) prints it whole and the answer stays right. A mixed row prints a mix.
//
// WHAT WAS MEASURED AND REFUSED
//   * A delta against p='s line: 23 of 292,537 rows hold a site ABOVE the definition line (tmux: p="arguments.c:524"
//     with a site at 512), so deltas need a sign and arithmetic the reader must get right, for 898 B more than this form.
//   * Omitting the attribute on equality: an ABSENT sites_at= already means "no call here is spelled like the called
//     name" (an aliased import), so absence is taken. The bare line is printed instead.
//   * THE ALL-DIGIT FRAGMENT. Tokens are space-separated, so a FOREIGN path holding a whitespace-delimited all-digit
//     fragment (`d 12 x/a.py:3` -> `d`, `12`, `x/a.py:3`) would read as a bare line `12` beside real bare lines. A row
//     holding such a token is printed ENTIRELY in the full form: byte for byte the value it had before this header, with
//     no bare line in it for the fragment to be mistaken for. (The row's OWN path may hold such a fragment freely: its
//     tokens are bare lines, so its path is not printed in the value at all, which also ends the old form's own
//     ambiguity for a path with a space.)
//
// Standard-library only, on purpose: test/sitesatshort_unit.cpp drives the rule directly on the rows no index produces.

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// One call site as its row will spell it: the file (root-relative exactly as p= prints it) and the 1-based line.
using SpelledSite = std::pair<std::string, std::uint32_t>;

// Does the full token `path:line` put an all-digit fragment between two whitespace cuts? The path's LAST fragment is
// never one: it is printed with `:line` attached. Whitespace is XML's (space, tab, CR, LF), what a reader splits on.
inline bool pathReadsAsBareLine( std::string_view path ) noexcept
{
    constexpr std::string_view kSpace = " \t\r\n";
    std::size_t fragmentStart = 0;
    for( std::size_t cut = path.find_first_of( kSpace ); cut != std::string_view::npos; cut = path.find_first_of( kSpace, fragmentStart ) )
    {
        const std::string_view fragment = path.substr( fragmentStart, cut - fragmentStart );
        if( !fragment.empty() && std::all_of( fragment.begin(), fragment.end(), []( char c ) { return c >= '0' && c <= '9'; } ) )
        {
            return true;
        }
        fragmentStart = cut + 1;
    }
    return false;
}

// The tokens of one caller row, in the order given: a bare line for a site in `rowFile`, the full `file:line` otherwise,
// and every token full when a foreign path would read as a bare line (the header's third refusal).
inline std::vector<std::string> siteTokensFor( std::string_view rowFile, std::span<const SpelledSite> sites )
{
    const bool wholeRowFull = std::any_of( sites.begin(), sites.end(),
                                           [ & ]( const SpelledSite& s ) { return s.first != rowFile && pathReadsAsBareLine( s.first ); } );
    std::vector<std::string> tokens;
    tokens.reserve( sites.size() );
    for( const SpelledSite& s : sites )
    {
        tokens.push_back( !wholeRowFull && s.first == rowFile ? std::to_string( s.second ) : s.first + ":" + std::to_string( s.second ) );
    }
    return tokens;
}

} // namespace rw
