#pragma once

// Python run hints need evidence: a main guard or a pytest project. Imports alone do not run tests.
// Reuse the vendored parsers so examples in docstrings and TOML multiline strings are not evidence.
#include "docparse.h"
#include "infra/Diagnostics.h"
#include "infra/fieldid.h"
#include "infra/tschildren.h"

#include <filesystem>
#include <limits>
#include <string>
#include <string_view>

extern "C"
{
    const TSLanguage* tree_sitter_python( void );
    const TSLanguage* tree_sitter_toml( void );
}

namespace rw::pythonrunner
{

/// Parse source with the supplied grammar and return whether a top-level child satisfies predicate.
/// Reject oversized input, parse failures and syntax errors; predicate must not throw or retain nodes.
template<class Predicate>
inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate& predicate )
{
    if( source.size() > std::numeric_limits<std::uint32_t>::max() )
    {
        return false;
    }
    // The parser cannot come back null (tree-sitter's allocator aborts rather than return null (third_party/deps/tree_sitter/lib/src/alloc.c), and no ripwire code calls ts_set_allocator), and `language` is one of this file's two statically linked
    // grammars (tree_sitter_python / tree_sitter_toml — the only callers), whose ABI version is fixed at build time.
    TSParser* parser = ts_parser_new();
    ASSUME( parser != nullptr, "ts_parser_new: the default tree-sitter allocator aborts on failure" );
    const bool isLanguageSet = ts_parser_set_language( parser, language );
    ASSUME( isLanguageSet, "the Python and TOML grammars are linked into this binary at a supported ABI" );
    TSTree* tree = ts_parser_parse_string( parser, nullptr, source.data(), std::uint32_t( source.size() ) );
    ts_parser_delete( parser );
    if( tree == nullptr )
    {
        // The one real degrade: an external scanner error on this (external) text ends the parse with no tree. No evidence
        // is found, and a test row without evidence already says so — run_unknown="1", no runner guessed.
        DISCLOSE( Diagnostics::answerUnchanged, "an unparsed file yields no evidence, and a row without evidence reads run_unknown=1, never a guessed runner",
                  "Python runner: parse failed" );
        return false;
    }
    const TSNode root = ts_tree_root_node( tree );
    bool found = false;
    if( !ts_node_has_error( root ) )
    {
        ChildCursor cursor( root );
        forEachChild( root, cursor.cur, [ & ]( TSNode node )
        {
            found = predicate( node );
            return !found;
        } );
    }
    ts_tree_delete( tree );
    return found;
}

/// Recognize a plain __name__ == "__main__" comparison in either operand order.
/// condition must belong to source; comments, chains and other spellings are conservatively rejected.
inline bool mainComparison( TSNode condition, std::string_view source )
{
    if( ts_node_is_null( condition ) || std::string_view( ts_node_type( condition ) ) != "comparison_operator"
        || ts_node_child_count( condition ) != 3 )
    {
        return false;
    }
    // Fixed three-child comparison: comments or chained comparisons are conservatively not evidence.
    const auto spelling = [ & ]( std::uint32_t childIndex )
    {
        const TSNode child = ts_node_child( condition, childIndex );
        return source.substr( ts_node_start_byte( child ), ts_node_end_byte( child ) - ts_node_start_byte( child ) );
    };
    const auto mainLiteral = []( std::string_view text ) { return text == "\"__main__\"" || text == "'__main__'"; };
    return spelling( 1 ) == "==" && ( ( spelling( 0 ) == "__name__" && mainLiteral( spelling( 2 ) ) )
        || ( mainLiteral( spelling( 0 ) ) && spelling( 2 ) == "__name__" ) );
}

/// Return whether valid Python source contains a recognized top-level main guard.
/// Nested guards and examples inside comments or strings do not establish script entry-point evidence.
inline bool hasMainGuard( std::string_view source )
{
    return topLevelEvidence( source, tree_sitter_python(), [ & ]( TSNode node )
    {
        if( std::string_view( ts_node_type( node ) ) != "if_statement" )
        {
            return false;
        }
        return mainComparison( fieldChild( node, NodeField::Condition ), source );
    } );
}

/// Find the exact tool.pytest.ini_options table key in valid TOML source.
/// String contents are not tables; quoted or differently spaced key spellings are not recognized.
inline bool hasPytestTable( std::string_view source )
{
    return topLevelEvidence( source, tree_sitter_toml(), [ & ]( TSNode node )
    {
        if( std::string_view( ts_node_type( node ) ) != "table" )
        {
            return false;
        }
        // The first named child is the table key; values and their multiline strings are separate nodes.
        const TSNode key = ts_node_named_child( node, 0 );
        return !ts_node_is_null( key ) && source.substr( ts_node_start_byte( key ), ts_node_end_byte( key ) - ts_node_start_byte( key ) )
            == "tool.pytest.ini_options";
    } );
}

/// Find a standalone [tool:pytest] section in setup.cfg text.
/// Track value indentation so section-looking continuation lines cannot establish pytest evidence.
inline bool hasPytestSection( std::string_view source )
{
    std::size_t valueIndent = std::string_view::npos;
    while( !source.empty() )
    {
        const std::size_t end = source.find( '\n' );
        const std::string_view line = source.substr( 0, end );
        const std::size_t start = line.find_first_not_of( " \t\r" );
        // INI values continue on more-indented lines; a table-looking example there is still a value.
        if( start != std::string_view::npos && ( valueIndent == std::string_view::npos || start <= valueIndent ) )
        {
            const std::string_view content = line.substr( start );
            if( content.starts_with( "[tool:pytest]" ) && content.substr( 13 ).find_first_not_of( " \t\r" ) == std::string_view::npos )
            {
                return true;
            }
            if( content.front() == '[' )
            {
                valueIndent = std::string_view::npos;
            }
            else if( content.front() != '#' && content.front() != ';' && content.find_first_of( "=:" ) != std::string_view::npos )
            {
                valueIndent = start;
            }
        }
        if( end == std::string_view::npos )
        {
            break;
        }
        source.remove_prefix( end + 1 );
    }
    return false;
}

/// Check one directory for regular, non-symlink pytest configuration files.
/// pytest.ini or conftest.py suffices; pyproject.toml and setup.cfg require a recognized pytest section.
inline bool pytestConfigAt( const std::filesystem::path& dir )
{
    // Do not follow a config symlink out of the scanned project.
    const auto regular = [ & ]( const char* name )
    {
        std::error_code ec;
        return std::filesystem::is_regular_file( std::filesystem::symlink_status( dir / name, ec ) );
    };
    if( regular( "pytest.ini" ) || regular( "conftest.py" ) )
    {
        return true;
    }
    if( regular( "pyproject.toml" ) && hasPytestTable( docparse::detail::readWholeFile( ( dir / "pyproject.toml" ).string() ).value_or( "" ) ) )
    {
        return true;
    }
    return regular( "setup.cfg" ) && hasPytestSection( docparse::detail::readWholeFile( ( dir / "setup.cfg" ).string() ).value_or( "" ) );
}

/// Search from file's parent through root, inclusive, for pytest configuration.
/// Paths are normalized lexically; an absent root, path error or file outside root yields no evidence.
inline bool hasPytestProject( const std::string& file, std::string_view root )
{
    namespace fs = std::filesystem;
    if( root.empty() )
    {
        return false;   // No known crawl boundary: do not inherit the user's unrelated parent config.
    }
    std::error_code ec;
    fs::path boundary = fs::absolute( fs::path( root ), ec ).lexically_normal();
    if( ec )
    {
        return false;
    }
    // absolute(".") normalizes to a trailing separator, while parent_path() does not. They are one root.
    if( boundary.has_relative_path() && boundary.filename().empty() )
    {
        boundary = boundary.parent_path();
    }
    fs::path dir = fs::absolute( fs::path( file ), ec ).lexically_normal().parent_path();
    const fs::path relative = dir.lexically_relative( boundary );
    if( ec || relative.empty() || *relative.begin() == ".." )
    {
        return false;
    }
    for( ;; dir = dir.parent_path() )
    {
        if( pytestConfigAt( dir ) )
        {
            return true;
        }
        if( dir == boundary || dir == dir.parent_path() )
        {
            return false;
        }
    }
}

} // namespace rw::pythonrunner
