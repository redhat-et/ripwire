// foreditverb.h — does a `--for` task read as an EDIT? (lane θ17: the gate of the edit-file body form, forbodyptr.h pointEditBodies).
// Its own small header so the measured Python twin (tmp theta17/predict.py is_edit) can be checked against it string for string.
#pragma once

#include <algorithm>
#include <cstddef>
#include <string_view>

#include "arch.h"              // ciEqualAscii — the house ASCII case fold
#include "infra/namesplit.h"   // namesplit::isIdentChar — the one identifier-character test

namespace rw::bodyptr
{

namespace detail
{
// Edit verbs (theta17/predict.py, the measured twin: on for 87/89 GA1 DEV and 89/99 GA3 DEV edit tasks, for 0 of the S1 163, MF1 39 and
// NL1 96 where/how tasks and 7 of LD 56, each "add a new ..."). A STEM matches a word that is the stem plus lowercase letters
// ("simplif" -> simplify, simplified); a SHORT word matches exactly; both case-insensitive in the stem part.
inline constexpr std::string_view kEditStems[] = {
    "remov", "delet", "renam", "refactor", "implement", "support", "updat", "chang", "replac", "avoid", "prevent", "allow", "handl",
    "improv", "simplif", "restor", "rais", "report", "clamp", "skip", "writ", "extract", "introduc", "deprecat", "revert", "ensur",
    "expos", "enabl", "disabl", "correct", "optimi", "reduc", "return", "honou", "respect", "accept", "reject", "preserv", "treat",
    "associat", "emit", "propagat", "guard", "check", "validat", "convert", "normali", "tweak", "bump", "wrap", "unif", "clean", "apply",
    "strip", "initiali", "print", "split", "expand", "refin", "squelch", "moderni", "defin", "provid", "stop", "prefer", "flush",
    "prettif", "shorten", "speed", "limit", "trim", "rewrit", "reimplement", "memset", "requir", "declar", "rework", "restructur",
    "reorder", "merg", "inlin", "rewir", "migrat", "upgrad", "downgrad", "warn", "throw", "make", "made", "build", "fixe", "fixi", "drop",
    "move" };
inline constexpr std::string_view kEditShort[] = {
    "fix", "fixed", "add", "adds", "added", "use", "uses", "used", "set", "sets", "keep", "keeps", "pass", "passes", "cap", "pin", "run",
    "runs", "hide", "show", "feat", "perf", "chore", "do", "don't", "only", "problem" };

// `w` starts with `stem` (lowercase), ASCII case folded: the house fold (arch.h ciEqualAscii) on the prefix.
[[nodiscard]] inline bool startsWithFolded( std::string_view w, std::string_view stem ) noexcept
{
    return w.size() >= stem.size() && rw::ciEqualAscii( w.substr( 0, stem.size() ), stem );
}
// The word at `at` is an edit verb and more words follow it.
[[nodiscard]] inline bool editVerbAt( std::string_view t, std::size_t at ) noexcept
{
    std::size_t end = at;
    while( end < t.size() && ( ( t[ end ] >= 'a' && t[ end ] <= 'z' ) || ( t[ end ] >= 'A' && t[ end ] <= 'Z' ) || t[ end ] == '\'' ) ) { ++end; }
    const std::string_view w = t.substr( at, end - at );
    if( w.empty() || ( end < t.size() && ( namesplit::isIdentChar( t[ end ] ) || t[ end ] == '.' ) ) ) { return false; }
    const auto lowerRest = []( std::string_view rest ) { return std::ranges::all_of( rest, []( char c ) { return c >= 'a' && c <= 'z'; } ); };
    const bool verb      = std::ranges::any_of( kEditShort, [ & ]( std::string_view s ) { return w.size() == s.size() && startsWithFolded( w, s ); } )
                      || std::ranges::any_of( kEditStems, [ & ]( std::string_view s ) { return startsWithFolded( w, s ) && lowerRest( w.substr( s.size() ) ); } );
    const std::size_t gap = t.find_first_of( " \t\n", end );
    return verb && gap != std::string_view::npos && t.find_first_not_of( " \t\n", gap ) != std::string_view::npos;
}
// Past an optional "scope:" prefix of 1-3 words ("lib/helpers:", "feat(x):", "Build script:"): where the word after it starts, or npos.
[[nodiscard]] inline std::size_t pastScopePrefix( std::string_view t, std::size_t at ) noexcept
{
    constexpr std::string_view kScope = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./{},-*";
    for( int words = 0; words < 3; ++words )
    {
        const std::size_t e = t.find_first_not_of( kScope, at );
        if( e == at || e == std::string_view::npos ) { return std::string_view::npos; }
        std::size_t k = e;
        if( t[ k ] == '(' )
        {
            k = t.find( ')', k );
            if( k == std::string_view::npos ) { return std::string_view::npos; }
            ++k;
        }
        k += k < t.size() && t[ k ] == '!' ? 1u : 0u;
        if( k < t.size() && t[ k ] == ':' )
        {
            const std::size_t w = t.find_first_not_of( " \t\n", k + 1 );
            return w;
        }
        if( k != e || t[ e ] != ' ' ) { return std::string_view::npos; }   // only a plain word may be followed by another
        at = e + 1;
    }
    return std::string_view::npos;
}
}   // namespace detail

// Does the --for task read as an edit (its first word an edit verb, after an optional scope prefix)?
[[nodiscard]] inline bool isEditTask( std::string_view task ) noexcept
{
    const std::size_t at = task.find_first_not_of( " \t\n*\"'-" );
    if( at == std::string_view::npos ) { return false; }
    if( detail::editVerbAt( task, at ) ) { return true; }
    const std::size_t w = detail::pastScopePrefix( task, at );
    return w != std::string_view::npos && detail::editVerbAt( task, w );
}

}   // namespace rw::bodyptr
