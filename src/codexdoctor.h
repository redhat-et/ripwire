#pragma once

// codexdoctor.h — read-only checks for the LIVE Codex install surface. These intentionally inspect the
// agent homes and configured commands, not this checkout's copies. No config contents or command lines are
// emitted: a doctor report may be pasted into an issue, so unrelated tokens and secrets stay dark.

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace rw::codexdoctor
{

struct Check
{
    const char* name = "";
    bool ok = false;
    std::string attrs;
};

inline std::string envOr( const char* name, std::string fallback )
{
    const char* value = std::getenv( name );
    return value && *value ? std::string( value ) : std::move( fallback );
}

inline std::string readSmallFile( const std::filesystem::path& path, bool& ok )
{
    ok = false;
    std::error_code ec;
    const std::uintmax_t byteCount = std::filesystem::file_size( path, ec );
    if( ec || byteCount > 1024 * 1024 ) { return {}; }
    std::ifstream input( path, std::ios::binary );
    if( !input ) { return {}; }
    std::string text( std::istreambuf_iterator<char>( input ), {} );
    ok = input.good() || input.eof();
    return text;
}

inline std::string resolveExecutable( std::string_view command )
{
    if( command.empty() ) { return {}; }
    const auto executable = []( const std::string& path )
    {
        return ::access( path.c_str(), X_OK ) == 0;
    };
    if( command.find( '/' ) != std::string_view::npos )
    {
        const std::string path( command );
        return executable( path ) ? path : std::string();
    }
    const char* pathEnv = std::getenv( "PATH" );
    std::string_view remaining = pathEnv ? std::string_view( pathEnv ) : std::string_view();
    while( !remaining.empty() )
    {
        const std::size_t split = remaining.find( ':' );
        const std::string_view dir = remaining.substr( 0, split );
        const std::string candidate = std::string( dir.empty() ? "." : dir ) + "/" + std::string( command );
        if( executable( candidate ) ) { return candidate; }
        if( split == std::string_view::npos ) { break; }
        remaining.remove_prefix( split + 1 );
    }
    return {};
}

inline Check binaryCheck( const std::string& selfPath )
{
    const std::string active = resolveExecutable( "ripwire" );
    struct stat selfSt {};
    struct stat activeSt {};
    const bool haveSelf = !selfPath.empty() && ::stat( selfPath.c_str(), &selfSt ) == 0;
    const bool haveActive = !active.empty() && ::stat( active.c_str(), &activeSt ) == 0;
    const bool same = haveSelf && haveActive && selfSt.st_dev == activeSt.st_dev && selfSt.st_ino == activeSt.st_ino;
    const bool copied = haveSelf && haveActive && selfSt.st_mtime == activeSt.st_mtime && selfSt.st_size == activeSt.st_size;
    Check out{ "codex-binary", haveActive && ( !haveSelf || same || copied ),
               "on_path=\"" + std::string( haveActive ? "1" : "0" ) + "\" same_file=\"" + ( same ? "1" : "0" ) + "\"" };
    if( !out.ok ) { out.attrs += " hint=\"reinstall the current build so Codex shell calls and this doctor resolve the same ripwire binary\""; }
    return out;
}

struct SkillManifest
{
    bool read = false;
    bool version = false;
    bool duplicate = false;
    std::vector<std::string> declared;
};

inline SkillManifest skillManifest( const std::filesystem::path& path )
{
    SkillManifest out;
    const std::string manifest = readSmallFile( path, out.read );
    for( std::size_t at = 0; at <= manifest.size(); )
    {
        const std::size_t end = manifest.find( '\n', at );
        const std::string_view line( manifest.data() + at, ( end == std::string::npos ? manifest.size() : end ) - at );
        if( line == "version=1" ) { out.version = true; }
        else if( line.rfind( "skill=ripwire-", 0 ) == 0 ) { out.declared.emplace_back( line.substr( 6 ) ); }
        if( end == std::string::npos ) { break; }
        at = end + 1;
    }
    std::sort( out.declared.begin(), out.declared.end() );
    out.duplicate = std::adjacent_find( out.declared.begin(), out.declared.end() ) != out.declared.end();
    return out;
}

inline std::vector<std::string> liveSkills( const std::filesystem::path& skillHome, bool& scanned )
{
    std::vector<std::string> live;
    std::error_code ec;
    std::filesystem::directory_iterator it( skillHome, ec ), last;
    while( !ec && it != last )
    {
        const std::string name = it->path().filename().string();
        std::error_code sec;
        if( name.rfind( "ripwire-", 0 ) == 0 && it->is_directory( sec ) && !sec ) { live.push_back( name ); }
        it.increment( ec );
    }
    std::sort( live.begin(), live.end() );
    scanned = !ec;
    return live;
}

inline Check skillsCheck( const std::filesystem::path& skillHome )
{
    const SkillManifest manifest = skillManifest( skillHome / ".ripwire-manifest-v1" );
    bool scanned = false;
    const std::vector<std::string> live = liveSkills( skillHome, scanned );
    Check out{ "codex-skills", manifest.read && manifest.version && scanned && !manifest.duplicate && !manifest.declared.empty() && manifest.declared == live,
               "manifest=\"" + std::string( manifest.read ? "1" : "0" ) + "\" declared=\"" + std::to_string( manifest.declared.size() )
               + "\" live=\"" + std::to_string( live.size() ) + "\"" };
    if( !out.ok ) { out.attrs += " hint=\"run bash skills/install.sh --codex to restore exact manifest parity\""; }
    return out;
}

inline std::vector<std::string> commandValuesContaining( const std::string& json, std::string_view needle )
{
    std::vector<std::string> out;
    for( std::size_t at = json.find( needle ); at != std::string::npos; at = json.find( needle, at + needle.size() ) )
    {
        const std::size_t begin = json.rfind( '"', at );
        const std::size_t end = json.find( '"', at );
        if( begin != std::string::npos && end != std::string::npos ) { out.push_back( json.substr( begin + 1, end - begin - 1 ) ); }
    }
    return out;
}

inline bool everyCommandExecutable( const std::vector<std::string>& commands )
{
    return std::all_of( commands.begin(), commands.end(), []( const std::string& command )
    {
        const std::size_t arg = command.find( " --" );
        return !resolveExecutable( command.substr( 0, arg ) ).empty();
    } );
}

inline Check hooksCheck( const std::filesystem::path& hooksPath )
{
    bool read = false;
    const std::string json = readSmallFile( hooksPath, read );
    const std::vector<std::string> nudge = commandValuesContaining( json, "ripwire-codex-nudge.sh" );
    const std::vector<std::string> route = commandValuesContaining( json, "ripwire-codex-route.sh" );
    const bool events = json.find( "PreToolUse" ) != std::string::npos && json.find( "SessionStart" ) != std::string::npos
                     && json.find( "UserPromptSubmit" ) != std::string::npos;
    Check out{ "codex-hooks", read && events && nudge.size() >= 2 && !route.empty() && everyCommandExecutable( nudge ) && everyCommandExecutable( route ),
               "configured=\"" + std::string( read ? "1" : "0" ) + "\" nudge_refs=\"" + std::to_string( nudge.size() )
               + "\" route_refs=\"" + std::to_string( route.size() ) + "\"" };
    if( !out.ok ) { out.attrs += " hint=\"run bash skills/install.sh --codex --hook to refresh all advisory Codex hooks\""; }
    return out;
}

inline std::string tomlString( std::string_view section, std::string_view key )
{
    const std::size_t at = section.find( key );
    const std::size_t equal = at == std::string_view::npos ? at : section.find( '=', at + key.size() );
    const std::size_t quote = equal == std::string_view::npos ? equal : section.find( '"', equal + 1 );
    const std::size_t close = quote == std::string_view::npos ? quote : section.find( '"', quote + 1 );
    return close == std::string_view::npos ? std::string() : std::string( section.substr( quote + 1, close - quote - 1 ) );
}

inline Check mcpCheck( const std::filesystem::path& configPath )
{
    bool read = false;
    const std::string toml = readSmallFile( configPath, read );
    const std::string header = "[mcp_servers.ripwire]";
    const std::size_t begin = toml.find( header );
    const std::size_t next = begin == std::string::npos ? begin : toml.find( "\n[", begin + header.size() );
    const std::string_view section = begin == std::string::npos ? std::string_view() : std::string_view( toml ).substr(
        begin, ( next == std::string::npos ? toml.size() : next ) - begin );
    const std::string command = tomlString( section, "command" );
    const bool executable = !resolveExecutable( command ).empty();
    const bool mcpArg = section.find( "\"--mcp\"" ) != std::string_view::npos;
    Check out{ "codex-mcp", read && !section.empty() && executable && mcpArg,
               "configured=\"" + std::string( read && !section.empty() ? "1" : "0" ) + "\" command_exec=\""
               + ( executable ? "1" : "0" ) + "\" mcp_arg=\"" + ( mcpArg ? "1" : "0" ) + "\"" };
    if( !out.ok ) { out.attrs += " hint=\"run ripwire wrap codex and apply the printed mcp_servers.ripwire recipe\""; }
    return out;
}

inline std::vector<Check> inspect( const std::string& selfPath )
{
    const std::string home = envOr( "HOME", "" );
    const std::filesystem::path agentHome = envOr( "AGENTS_HOME", home + "/.agents" );
    const std::filesystem::path codexHome = envOr( "CODEX_HOME", home + "/.codex" );
    return { binaryCheck( selfPath ), skillsCheck( agentHome / "skills" ), hooksCheck( codexHome / "hooks.json" ),
             mcpCheck( codexHome / "config.toml" ) };
}

}   // namespace rw::codexdoctor
