#pragma once
// pydottedpath.h — THE ONE resolver from a dotted Python path to an indexed module file and to one definition in it. Two
// callers: manifest entry points (epmanifest.h, `module:attr`) and dotted-string literals (fordottedstring.h, `a.b.C`).

#include "model.h"        // IngestResult, Symbol, rootRelPath, kNoFile

#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// The indexed module file of `module` (dotted) for a manifest in directory `mdir` (root-relative, "" = the root): a .py file
// under mdir whose path within it is `a/b/c.py` or `a/b/c/__init__.py`, or ends with "/" + one of those (a package directory
// such as src/). Several: the one directly under mdir or under mdir/src wins when it is the only such; else ambiguous (kNoFile).
// `inTree` says whether any file matched at all.
inline std::uint32_t epModuleFile( const IngestResult& ing, std::string_view mdir, std::string_view module, bool& inTree )
{
    std::string path( module );
    std::replace( path.begin(), path.end(), '.', '/' );
    const std::string asFile = path + ".py";
    const std::string asPkg  = path + "/__init__.py";
    std::vector<std::uint32_t> any;
    std::vector<std::uint32_t> direct;
    for( std::uint32_t f = 0; f < ing.files.size(); ++f )
    {
        std::string_view rel = rootRelPath( ing, f );
        if( !mdir.empty() )
        {
            if( rel.size() <= mdir.size() || !rel.starts_with( mdir ) || rel[ mdir.size() ] != '/' )
            {
                continue;
            }
            rel.remove_prefix( mdir.size() + 1 );
        }
        for( const std::string_view want : { std::string_view( asFile ), std::string_view( asPkg ) } )
        {
            if( rel == want || rel == "src/" + std::string( want ) )
            {
                direct.push_back( f );
                any.push_back( f );
            }
            else if( rel.size() > want.size() && rel.ends_with( want ) && rel[ rel.size() - want.size() - 1 ] == '/' )
            {
                any.push_back( f );
            }
        }
    }
    inTree = !any.empty();
    // only a file AT the module's import path (under mdir or mdir/src) is that module; a deeper same-suffix file
    // (tools/cli.py for `cli`, tests/fixtures/pkg/mod.py) may be another module of the same name: unresolved, never a def
    return direct.size() == 1 ? direct.front() : kNoFile;
}

// Is `s` what the attribute path `attr` names in its module? The last segment is the name; the rest is the owner chain, which
// must equal the symbol's scope (a top-level def has no scope, or — a class — its own name as scope, as the index stores it).
inline bool epAttrNames( const Symbol& s, std::string_view attr )
{
    const std::size_t      dot   = attr.rfind( '.' );
    const std::string_view name  = dot == std::string_view::npos ? attr : attr.substr( dot + 1 );
    const std::string_view owner = dot == std::string_view::npos ? std::string_view() : attr.substr( 0, dot );
    if( s.name != name )
    {
        return false;
    }
    if( s.kind != SymKind::Function && s.kind != SymKind::Method && s.kind != SymKind::Class && s.kind != SymKind::Var )
    {
        return false;
    }
    if( owner.empty() )
    {
        return s.scope.empty() || s.scope == s.name;
    }
    if( s.scope == owner )
    {
        return true;
    }
    // the index may spell a nested owner with "::" — compare segment by segment
    std::string dotted = s.scope;
    for( std::size_t k = dotted.find( "::" ); k != std::string::npos; k = dotted.find( "::", k + 1 ) )
    {
        dotted.replace( k, 2, "." );
    }
    return dotted == owner;
}

}   // namespace rw
