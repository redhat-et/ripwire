#pragma once

// Vitest run hints: a nearest package.json with a literal npm test script and declared Vitest dependency.
// No installed package, successful run, or satisfied test-gate obligation is inferred from the manifest.
#include "ingest.h"       // kMaxJsonConfigBytes, IngestResult, diskPath, rootRelPath
#include "filter.h"       // isTestPath
#include "docparse.h"     // readWholeFile
#include "mention.h"      // baseNameOf
#include "pythonrunner.h" // topLevelEvidence: reject malformed JSON through the vendored grammar
#include "sarif.h"        // rootRelativeUri
#include "infra/jsonesc.h" // shSingleQuote

#include <filesystem>
#include <ranges>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

extern "C" const TSLanguage* tree_sitter_json( void );

namespace rw::vitestrunner
{

// Vitest 3.2's default include (packages/vitest/src/defaults.ts at v3.2.0) is
// **/*.{test,spec}.?(c|m)[jt]s?(x). No vitest.config is read, so a test/ directory or a
// test_ / _test name is not enough. The marker sits immediately before the last extension:
// ".mts" is one extension, and stripping only ".ts" would reject lib.spec.mts.
inline bool defaultVitestFileName( std::string_view path ) noexcept
{
    const std::string_view name = mention_detail::baseNameOf( path );
    const std::size_t dot = name.rfind( '.' );
    if( dot == std::string_view::npos || dot == 0 )
    {
        return false;
    }
    const std::string_view extension = name.substr( dot );
    static constexpr std::string_view kExtensions[] = {
        ".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts"
    };
    bool supported = false;
    for( const std::string_view known : kExtensions )
    {
        if( extension == known )
        {
            supported = true;
            break;
        }
    }
    if( !supported )
    {
        return false;
    }
    const std::string_view stem = name.substr( 0, dot );
    return stem.ends_with( ".test" ) || stem.ends_with( ".spec" );
}

// Shared with TestRunnerIndex's existing script-command spelling: safe bytes stay readable;
// every other path is passed to the shell as one quoted argument.
inline bool shellSafePath( std::string_view p ) noexcept
{
    if( p.empty() || p.front() == '-' )
    {
        return false;
    }
    for( const char c : p )
    {
        const bool safe = ( c >= 'A' && c <= 'Z' ) || ( c >= 'a' && c <= 'z' ) || ( c >= '0' && c <= '9' )
                       || c == '.' || c == '_' || c == '/' || c == '-';
        if( !safe )
        {
            return false;
        }
    }
    return true;
}

class Index
{
public:
    explicit Index( const IngestResult& ing, std::string_view rootPrefix )
        : ing_( &ing ), rootPrefix_( rootPrefix )
    {
        for( const std::uint32_t f : std::views::iota( std::uint32_t( 0 ), std::uint32_t( ing.files.size() ) ) )
        {
            if( mention_detail::baseNameOf( diskPath( ing, f ) ) == "package.json" )
            {
                packages_.push_back( f );
            }
        }
    }

    std::string commandFor( std::uint32_t fileId ) const { return deriveVitest( fileId ); }

private:
    // Only literal keys count as manifest evidence. A duplicate relevant key is ambiguous and returns no node.
    static TSNode jsonField( TSNode object, std::string_view source, std::string_view key, bool* duplicate = nullptr ) noexcept
    {
        if( ts_node_is_null( object ) || std::string_view( ts_node_type( object ) ) != "object" )
        {
            return {};
        }
        TSNode found{};
        for( std::uint32_t i = 0; i < ts_node_named_child_count( object ); ++i )
        {
            const TSNode pair = ts_node_named_child( object, i );
            if( std::string_view( ts_node_type( pair ) ) != "pair" )
            {
                continue;
            }
            const TSNode name = ts_node_named_child( pair, 0 );
            const std::string_view spelling = source.substr( ts_node_start_byte( name ), ts_node_end_byte( name ) - ts_node_start_byte( name ) );
            if( spelling.size() != key.size() + 2 || spelling.front() != '"' || spelling.back() != '"'
                || spelling.substr( 1, key.size() ) != key )
            {
                continue;
            }
            if( !ts_node_is_null( found ) )
            {
                if( duplicate != nullptr ) { *duplicate = true; }
                return {};
            }
            found = ts_node_named_child( pair, 1 );
        }
        return found;
    }

    static std::string_view jsonLiteral( TSNode node, std::string_view source ) noexcept
    {
        return ts_node_is_null( node ) ? std::string_view() : source.substr( ts_node_start_byte( node ), ts_node_end_byte( node ) - ts_node_start_byte( node ) );
    }

    bool packageHasVitest( std::uint32_t packageId ) const
    {
        if( const auto cached = packageEvidence_.find( packageId ); cached != packageEvidence_.end() )
        {
            return cached->second;
        }
        bool evidence = false;
        const std::optional<std::string> bytes = docparse::detail::readWholeFile( diskPath( *ing_, packageId ) );
        if( bytes && bytes->size() <= kMaxJsonConfigBytes )
        {
            evidence = pythonrunner::topLevelEvidence( *bytes, tree_sitter_json(), [ & ]( TSNode object )
            {
                if( std::string_view( ts_node_type( object ) ) != "object" )
                {
                    return false;
                }
                bool duplicateManager = false;
                const std::string_view manager = jsonLiteral( jsonField( object, *bytes, "packageManager", &duplicateManager ), *bytes );
                if( duplicateManager || ( !manager.empty() && !manager.starts_with( "\"npm@" ) ) )
                {
                    return false;
                }
                const TSNode scripts = jsonField( object, *bytes, "scripts" );
                if( jsonLiteral( jsonField( scripts, *bytes, "test" ), *bytes ) != "\"vitest run\"" )
                {
                    return false;
                }
                const TSNode deps = jsonField( object, *bytes, "dependencies" );
                const TSNode devDeps = jsonField( object, *bytes, "devDependencies" );
                const auto hasVitest = [ & ]( TSNode parent )
                {
                    const std::string_view version = jsonLiteral( jsonField( parent, *bytes, "vitest" ), *bytes );
                    return version.size() > 2 && version.front() == '"' && version.back() == '"';
                };
                return hasVitest( deps ) || hasVitest( devDeps );
            } );
        }
        return packageEvidence_.emplace( packageId, evidence ).first->second;
    }

    std::string deriveVitest( std::uint32_t fileId ) const
    {
        const std::string& target = diskPath( *ing_, fileId );
        if( !defaultVitestFileName( target ) || !isTestPath( rootRelPath( *ing_, fileId ) ) )
        {
            return {};
        }
        std::uint32_t nearest = UINT32_MAX;
        std::size_t nearestDirLength = 0;
        std::string_view testInPackage;
        std::string_view packageDir;
        for( const std::uint32_t p : packages_ )
        {
            if( !ing_->realPaths.empty() && ing_->fileRoot[fileId] != ing_->fileRoot[p] ) { continue; }
            const std::string& packagePath = diskPath( *ing_, p );
            const std::size_t slash = packagePath.rfind( '/' );
            const std::string_view dir = slash == std::string::npos ? std::string_view( "." ) : std::string_view( packagePath ).substr( 0, slash );
            std::string_view relative;
            if( dir == "." && target.rfind( "./", 0 ) == 0 ) { relative = std::string_view( target ).substr( 2 ); }
            else if( dir == "." && !target.starts_with( '/' ) && !target.starts_with( "../" ) ) { relative = target; }
            else if( dir == "/" && target.starts_with( '/' ) ) { relative = std::string_view( target ).substr( 1 ); }
            else if( target.size() > dir.size() + 1 && target.compare( 0, dir.size(), dir ) == 0 && target[ dir.size() ] == '/' )
            { relative = std::string_view( target ).substr( dir.size() + 1 ); }
            if( !relative.empty() && ( nearest == UINT32_MAX || dir.size() > nearestDirLength ) )
            {
                nearest = p; nearestDirLength = dir.size(); testInPackage = relative; packageDir = dir;
            }
        }
        if( nearest == UINT32_MAX || !packageHasVitest( nearest ) )
        {
            return {};
        }
        // An ignored or oversized nearer manifest still owns its subtree. Do not borrow an ancestor's
        // command when the crawl omitted the configuration that would decide the runner.
        for( std::size_t slash = testInPackage.find( '/' ); slash != std::string_view::npos;
             slash = testInPackage.find( '/', slash + 1 ) )
        {
            const std::string nestedPackage = std::string( packageDir ) + "/" + std::string( testInPackage.substr( 0, slash ) ) + "/package.json";
            std::error_code ec;
            const std::filesystem::file_status status = std::filesystem::symlink_status( nestedPackage, ec );
            if( ( !ec && status.type() != std::filesystem::file_type::not_found )
                || ( ec && ec != std::errc::no_such_file_or_directory ) )
            {
                return {};
            }
        }
        std::string prefix = packageDir == rootPrefix_ ? "." : std::string( rw::sarif::rootRelativeUri( packageDir, rootPrefix_ ) );
        if( prefix.starts_with( '-' ) ) { prefix.insert( 0, "./" ); }
        std::string testArg( testInPackage );
        if( testArg.starts_with( '-' ) ) { testArg.insert( 0, "./" ); }
        const auto shellArg = []( std::string_view value )
        { return shellSafePath( value ) ? std::string( value ) : rw::shSingleQuote( std::string( value ) ); };
        return "npm --prefix " + shellArg( prefix ) + " run test -- " + shellArg( testArg );
    }

    const IngestResult*                  ing_;
    std::string                          rootPrefix_;
    std::vector<std::uint32_t>           packages_;
    mutable HashMap<std::uint32_t, bool> packageEvidence_;
};

} // namespace rw::vitestrunner
