#pragma once

// codexdoctor.h — read-only checks for the LIVE Codex install surface. These intentionally inspect the
// agent homes and configured commands, not this checkout's copies. No config contents or command lines are
// emitted: a doctor report may be pasted into an issue, so unrelated tokens and secrets stay dark.

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <initializer_list>
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
    // `copied` is a HEURISTIC pass (mtime+size equality, the cp -p install shape) — it cannot prove byte
    // identity, so the row discloses which of the two predicates it passed on rather than folding them.
    Check out{ "codex-binary", haveActive && ( !haveSelf || same || copied ),
               "on_path=\"" + std::string( haveActive ? "1" : "0" ) + "\" same_file=\"" + ( same ? "1" : "0" )
               + "\" copied_heuristic=\"" + ( same ? "0" : copied ? "1" : "0" ) + "\"" };
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

// ---- HookSurvey — the facts BOTH agents' hook checks are made of, gathered once. The two agents
//      register different hook scripts under different event names in different files, but the four
//      questions are identical: was the config readable, how many entries name the nudge script, how
//      many name the router, and does every one of those commands resolve to something executable.
//      What differs is only which needles to look for and how the answers are worded, so the survey is
//      shared and the two checks below stay short enough to read side by side.
struct HookSurvey
{
    bool read = false;
    std::string json;
    std::vector<std::string> nudge;
    std::vector<std::string> route;
    bool nudgeExecutable = false;
    bool routeExecutable = false;
};

inline HookSurvey surveyHooks( const std::filesystem::path& path, std::string_view nudgeNeedle, std::string_view routeNeedle )
{
    HookSurvey out;
    out.json = readSmallFile( path, out.read );
    out.nudge = commandValuesContaining( out.json, nudgeNeedle );
    out.route = commandValuesContaining( out.json, routeNeedle );
    out.nudgeExecutable = everyCommandExecutable( out.nudge );
    out.routeExecutable = everyCommandExecutable( out.route );
    return out;
}

inline bool namesEvents( const HookSurvey& survey, std::initializer_list<const char*> events )
{
    return std::all_of( events.begin(), events.end(),
                        [ & ]( const char* event ) { return survey.json.find( event ) != std::string::npos; } );
}

// ---- hookRow — the row SHAPE both agents emit: configured, how many nudge references, and one
//      route field whose key and value each agent chooses. Factored out with the survey above so the
//      two checks below are four lines each and read as a pair of policies rather than a pair of
//      near-identical bodies; the attribute vocabulary then cannot drift between agents by accident.
inline Check hookRow( const char* name, const HookSurvey& survey, bool ok,
                      const char* routeKey, const std::string& routeValue, const char* hint )
{
    Check out{ name, ok,
               "configured=\"" + std::string( survey.read ? "1" : "0" ) + "\" nudge_refs=\""
               + std::to_string( survey.nudge.size() ) + "\" " + routeKey + "=\"" + routeValue + "\"" };
    if( !out.ok ) { out.attrs += " hint=\"" + std::string( hint ) + "\""; }
    return out;
}

inline Check hooksCheck( const std::filesystem::path& hooksPath )
{
    // Two nudge references, not one: the PreToolUse entry and the SessionStart entry are registered
    // together, and a config carrying only one of them is a half-finished install.
    const HookSurvey survey = surveyHooks( hooksPath, "ripwire-codex-nudge.sh", "ripwire-codex-route.sh" );
    const bool ok = survey.read && namesEvents( survey, { "PreToolUse", "SessionStart", "UserPromptSubmit" } )
                 && survey.nudge.size() >= 2 && !survey.route.empty() && survey.nudgeExecutable && survey.routeExecutable;
    return hookRow( "codex-hooks", survey, ok, "route_refs", std::to_string( survey.route.size() ),
                    "run bash skills/install.sh --codex --hook to refresh all advisory Codex hooks" );
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

// ---- THE CLAUDE SURFACE. It lives in this header rather than a claudedoctor.h of its own because it
//      reuses `commandValuesContaining`, `everyCommandExecutable`, `readSmallFile` and `skillsCheck`
//      verbatim: a second header would either duplicate those four or export them, and the file is
//      already "read-only checks for a LIVE agent install surface" rather than "checks for Codex".
//
//      WHAT IT ADDS OVER THE CODEX ROW: `route_hook`, a plain boolean saying whether
//      hooks/ripwire-claude-route.sh is registered as a UserPromptSubmit hook. That hook is the
//      instrument the band pre-registered in docs/EVALS.md §4 is measured through, so "is it actually
//      wired up" is a question whose answer must not be inferred from the absence of rows in a log —
//      an unregistered hook and a hook that never fires produce the same empty log.
//
//      As everywhere else in this file, no configuration CONTENT is emitted: a doctor report gets
//      pasted into issues, so the row carries counts and booleans and never a command line.
inline Check claudeHooksCheck( const std::filesystem::path& settingsPath )
{
    // `route_hook` is a BOOLEAN here where the Codex row prints a count, and that is the one place the
    // two rows deliberately differ: the Claude router is registered exactly once or not at all, and the
    // pre-registered readout's first question is "is the instrument wired up", not "how many times".
    const HookSurvey survey = surveyHooks( settingsPath, "ripwire-nudge.sh", "ripwire-claude-route.sh" );
    const bool routeOk = !survey.route.empty() && namesEvents( survey, { "UserPromptSubmit" } ) && survey.routeExecutable;
    const bool ok = survey.read && namesEvents( survey, { "PreToolUse", "SessionStart" } )
                 && survey.nudge.size() >= 2 && survey.nudgeExecutable && routeOk;
    return hookRow( "claude-hooks", survey, ok, "route_hook", routeOk ? "1" : "0",
                    "run bash skills/install.sh --hook to register the meter, the primer and the prompt router" );
}

// The two shared checks name Codex in their remediation hints, and a hint that tells a Claude Code
// user to run the Codex installer is worse than no hint at all. The MEASUREMENT is identical for both
// agents; only the closing sentence differs, so it is rewritten here rather than parameterised through
// call sites that would then have to keep two strings in step.
inline void retargetHint( Check& check, std::string_view claudeHint )
{
    const std::size_t at = check.attrs.find( " hint=\"" );
    if( at == std::string::npos ) { return; }
    check.attrs = check.attrs.substr( 0, at ) + " hint=\"" + std::string( claudeHint ) + "\"";
}

inline std::vector<Check> claudeInspect( const std::string& selfPath )
{
    const std::filesystem::path claudeHome = envOr( "HOME", "" ) + "/.claude";
    Check binary = binaryCheck( selfPath );
    binary.name = "claude-binary";
    retargetHint( binary, "reinstall the current build so Claude Code shell calls and this doctor resolve the same ripwire binary" );
    Check skills = skillsCheck( claudeHome / "skills" );
    skills.name = "claude-skills";
    retargetHint( skills, "run bash skills/install.sh --claude to restore exact manifest parity" );
    return { binary, skills, claudeHooksCheck( claudeHome / "settings.json" ) };
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
