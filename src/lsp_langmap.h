#pragma once

// lsp_langmap.h — task E: the client's declared languageId, routed through a validated alias map
// before it may touch an anchor. The declaration is the one language fact the EDITOR was configured to
// send; ripwire --lsp discarded it (the document's language came purely from the path, and { ".h",
// Lang::Cpp } is only a convention). This file turns that string into a ripwire Lang — or into nothing.
//
// THE RULES (plan: ~/projects/oss/RIPWIRE-RUBY-E-languageid-hint.md, owner ruling 2026-10-25):
//   * raw client strings never enter any protocol echo, the resolver vocabulary, or a disclosure —
//     mapLanguageId yields Lang values, and the lanes anchor with AnchorOrigin::Client;
//   * defaults are compiled (seeded from the Zed extension's grammar names plus VSCode-family ids);
//     a config file EXTENDS/overrides them at session start — no recompile to teach ripwire an editor;
//   * the file format is a deliberately tiny TOML subset (key = "value" rows, [overrule] suffixes);
//     comments, blank lines, and unknown shapes are IGNORED (a file also holding unrelated tooling
//     must not brick the hint), while a row whose tag is not in the vocabulary is REFUSED and
//     disclosed — refuse-and-say, never guess;
//   * declarations replace the CONTEXT anchor only for files whose suffix the map lists as
//     overridable (default: the .h family), never an explicit @lang, never the corpus census, and
//     never a document-free lane (workspace/symbol cannot see any of this — arm (41)).

#include <cctype>
#include <cstdlib>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "model.h"        // Lang, langFromTag — the tag vocabulary; this file adds none
#include "graph.h"        // rw::Interner — the per-open-document declaration record
#include "lintrules.h"    // (loaded transitively; langOfPath is consulted by the LANES, not here)
#include "docparse.h"     // rw::docparse::detail::readWholeFile — the config read
#include "infra/emit.h"   // rw::emitTo — the disclose lines

namespace rw
{
namespace lspmap
{

// The client's word for a language, canonicalized for map matching: lowered (D5's doctrine applied to
// the protocol's ONE client-authored language string) with whitespace/dashes folded away, but '+' KEPT
// — folding it would collide the ids "C++" and "c", whose entries mean Cpp and C respectively. Cap 40:
// no id we route is longer, and an oversized tail is not a language we know ('refuse, never guess',
// same shape as the tag parser). Shared by defaults and config — one spelling of 'canonical key'.
inline std::string canonicalKey( std::string_view s )
{
    if( s.empty() || s.size() > 40 )
    {
        return {};   // an empty/ludicrous key can never be an id, and joining it at the lookup site
                     // would let every oversized key alias one another
    }
    std::string out( s );
    for( char& c : out )
    {
        c = static_cast< char >( std::tolower( static_cast< unsigned char >( c ) ) );
    }
    for( std::size_t i = 0; i < out.size(); )
    {
        if( out[ i ] == ' ' || out[ i ] == '-' )
        {
            out.erase( out.begin() + static_cast< std::ptrdiff_t >( i ) );
        }
        else
        {
            ++i;
        }
    }
    return out;
}

// Compiled defaults, seeded from the Zed extension's grammar names (the client strings that actually
// arrive from it) plus the lowercase ids VSCode-family editors send. An entry maps a canonicalized
// client id to OUR tag; langFromTag then owns the tag -> Lang decision, so this table holds no
// language logic of its own and one vocabulary answers in both directions.
inline const std::vector<std::pair<std::string, std::string>>& defaultLangAliases()
{
    static const std::vector<std::pair<std::string, std::string>> rows = {
        { "c", "c" }, { "c++", "cpp" }, { "cpp", "cpp" }, { "csharp", "cs" }, { "objective c", "objc" },
        { "objective-c", "objc" }, { "javascript", "js" }, { "typescript", "ts" }, { "tsx", "js" },
        { "python", "py" }, { "ruby", "rb" }, { "rust", "rs" }, { "go", "go" }, { "java", "java" },
        { "kotlin", "kt" }, { "swift", "swift" }, { "elixir", "ex" }, { "shellscript", "sh" },
        { "bash", "sh" }, { "markdown", "md" }, { "json", "json" }, { "yaml", "yaml" },
        { "php", "php" }, { "lua", "lua" }, { "dart", "dart" }, { "gdscript", "gd" }, { "toml", "toml" },
        { "clojure", "clj" }, { "astro", "js" },   // astro's script blocks index as the JS family
    };
    return rows;
}

struct LangMap
{
    std::vector<std::pair<std::string, Lang>> rows;   // canonical client id -> Lang; file rows ride BEFORE defaults (first hit wins)
    std::string source;                               // "" = compiled defaults only; else the file that rode
    std::vector<std::string> rejects;                 // file rows refused (tag not in the vocabulary), verbatim, for the disclose
    std::vector<std::string> overrule                 // suffixes whose INDEXED language the declaration may replace;
        = { ".h", ".hpp", ".hh", ".hxx" };             // the C-family convention set — where langOfPath only guesses
    // task E: didOpen declarations (fileId+1 -> languageId; index 0 stays the reserved 'absent' slot because
    // fileId 0 is a valid file). The map loads ONCE per server process (runLsp preamble, before the request
    // loop), so the record rides the same object the lanes read — and the single-threaded loop means the
    // didOpen write and the lane reads never race.
    std::vector< std::pair< std::string, std::string > > decls;   // (disk path, client languageId) — path-keyed: fileIds shift across in-life index rebuilds, paths do not
};

// The tiny TOML subset we accept (the zero-dep rule): `key = "value"` client-map rows and an
// [overrule] `suffixes = [".h", ...]` single-line string array. See the file header for what is
// ignored and why; lowering at parse time keeps the lookup one comparison.
inline LangMap parseLangMapFile( const std::string& text )
{
    LangMap m;
    bool    inOverrule = false;
    std::size_t pos    = 0;
    while( pos <= text.size() )
    {
        const std::size_t nl  = text.find( '\n', pos );
        const std::string lineFull( text.substr( pos, ( nl == std::string::npos ? text.size() : nl ) - pos ) );   // OWN storage: a view bound straight to the substr temporary dangles
        std::string_view  line = lineFull;   // lives for the whole iteration
        while( !line.empty() && ( line.front() == ' ' || line.front() == '\t' || line.front() == '\r' ) )
        {
            line.remove_prefix( 1 );
        }
        if( line.empty() || line.front() == '#' )
        {
            if( nl == std::string::npos ) break;
            pos = nl + 1;
            continue;
        }
        if( line.front() == '[' )
        {
            inOverrule = line.find( "overrule" ) != std::string_view::npos;
            if( nl == std::string::npos ) break;
            pos = nl + 1;
            continue;
        }
        const std::size_t eq = line.find( '=' );
        if( eq != std::string::npos )
        {
            std::string key( line.substr( 0, eq ) );
            while( !key.empty() && ( key.back() == ' ' || key.back() == '\t' ) )
            {
                key.pop_back();
            }
            while( !key.empty() && ( key.front() == ' ' || key.front() == '\t' ) )
            {
                key.erase( key.begin() );
            }
            if( key.size() >= 2 && key.front() == '"' && key.back() == '"' )
            {
                key = key.substr( 1, key.size() - 2 );   // a TOML quoted key names the same thing as its bare spelling
            }
            const std::string val( line.substr( eq + 1 ) );
            if( inOverrule && key == "suffixes" )
            {
                std::vector<std::string> suf;
                for( std::size_t p = 0; ( p = val.find( '"', p ) ) != std::string::npos; )
                {
                    const std::size_t e = val.find( '"', p + 1 );
                    if( e == std::string::npos )
                    {
                        break;
                    }
                    suf.push_back( val.substr( p + 1, e - p - 1 ) );
                    p = e + 1;
                }
                if( !suf.empty() )
                {
                    m.overrule = std::move( suf );   // the section exists to scope the set: a listed list replaces the default, an empty one keeps it
                }
            }
            else if( !inOverrule )
            {
                const std::size_t q1 = val.find( '"' );
                const std::size_t q2 = val.rfind( '"' );
                if( q1 != std::string::npos && q2 > q1 )
                {
                    const std::string tag = val.substr( q1 + 1, q2 - q1 - 1 );
                    Lang            lang  = Lang::Unknown;
                    if( !langFromTag( tag, lang ) || tag == "?" )   // '?' is langTag(Unknown)'s own spelling — refuse to register the sentinel as a real alias
                    {
                        m.rejects.push_back( key + "=" + tag );
                    }
                    else if( const std::string k = canonicalKey( key ); !k.empty() )
                    {
                        m.rows.emplace_back( k, lang );
                    }
                }
            }
        }
        if( nl == std::string::npos )
        {
            break;
        }
        pos = nl + 1;
    }
    return m;
}

// Search order: --lsp-langmap=PATH (unreadable = disclosed, defaults kept — a hint source missing is
// not a server error), then $XDG_CONFIG_HOME/ripwire/lsp-langmap.toml, then $HOME/.config/... — first
// readable file rides, defaults answer for everything it does not map.
inline LangMap loadLangMap( std::string_view explicitPath, std::string_view startupRoot )
{
    LangMap m;
    for( const auto& [id, tag] : defaultLangAliases() )
    {
        Lang lang = Lang::Unknown;
        if( langFromTag( tag, lang ) && tag != "?" )
        {
            m.rows.emplace_back( canonicalKey( id ), lang );
        }
    }
    std::vector<std::string> candidates;
    if( !explicitPath.empty() )
    {
        candidates.emplace_back( explicitPath );
    }
    if( const char* xdg = std::getenv( "XDG_CONFIG_HOME" ); xdg != nullptr && xdg[ 0 ] != '\0' )
    {
        candidates.emplace_back( std::string( xdg ) + "/ripwire/lsp-langmap.toml" );
    }
    if( !startupRoot.empty() )   // the plan's workspace slot: the repo the editor opened can teach ripwire its own maps
    {
        candidates.emplace_back( std::string( startupRoot ) + "/.ripwire/lsp-langmap.toml" );
    }
    if( const char* home = std::getenv( "HOME" ); home != nullptr && home[ 0 ] != '\0' )
    {
        candidates.emplace_back( std::string( home ) + "/.config/ripwire/lsp-langmap.toml" );
    }
    for( const std::string& path : candidates )
    {
        const std::optional<std::string> raw = docparse::detail::readWholeFile( path );
        if( !raw )
        {
            if( path == explicitPath )
            {
                emitTo( stderr, "ripwire: --lsp: --lsp-langmap= file unreadable: {} — the XDG, repo and user config candidates are still searched; the startup line names the map that ends up in force\n", path );
            }
            continue;
        }
        LangMap file  = parseLangMapFile( *raw );
        file.source   = path;
        for( const auto& row : m.rows )
        {
            file.rows.emplace_back( row.first, row.second );   // defaults ride AFTER the file: first-hit wins, file overrides
        }
        m = std::move( file );
        break;
    }
    return m;
}

inline std::optional<Lang> mapLanguageId( const LangMap& m, std::string_view languageId )
{
    const std::string key = canonicalKey( languageId );
    if( key.empty() )
    {
        return std::nullopt;
    }
    for( const auto& [id, lang] : m.rows )
    {
        if( id == key )
        {
            return lang;
        }
    }
    return std::nullopt;
}

// Provenance once per session on the banner channel: which file rode, how many aliases answer, and
// every row that was refused (empty mapLanguageId results are NOT disclosed per-request — (39) pins
// an unknown id as silent no-op, byte-identical to no declaration; the refuse here is about the
// operator's FILE being wrong, not about client behavior).
inline void discloseMap( const LangMap& m )
{
    if( !m.source.empty() )
    {
        emitTo( stderr, "ripwire: --lsp: languageId map from {} ({} aliases active)\n", m.source, m.rows.size() );
    }
    if( !m.rejects.empty() )
    {
        std::string list;
        for( const std::string& rej : m.rejects )
        {
            if( !list.empty() )
            {
                list += ", ";
            }
            list += rej;
        }
        emitTo( stderr, "ripwire: --lsp: languageId map rows refused (tag not in the vocabulary): {}\n", list );
    }
}

}   // namespace lspmap
}   // namespace rw
