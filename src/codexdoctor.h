#pragma once

// codexdoctor.h — read-only checks for the LIVE Codex install surface. These intentionally inspect the
// agent homes and configured commands, not this checkout's copies. No config contents or command lines are
// emitted: a doctor report may be pasted into an issue, so unrelated tokens and secrets stay dark.

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <initializer_list>
#include <iterator>
#include <optional>
#include <string>
#include <string_view>
#include "infra/envutil.h"   // rw::envOr
#include "infra/os.h"   // rw::os::which / stat — the PATH search and the same-file check
#include <vector>

#include "embedded_skills.h"   // rw::embedded_skills::kStoreKey — the ONLY thing borrowed from the
                                // embed step; the manifest-v2 parser below is this header's own, so
                                // this doctor stays independent of src/skillsinstall.h's install path.

namespace rw::codexdoctor
{

struct Check
{
    const char* name = "";
    bool ok = false;
    std::string attrs;
};

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
    return os::which( command );   // POSIX: the PATH walk this function used to hold; Windows: ';', PATHEXT, no relative entries
}

// A version-manager shim is recognised by LOCATION only — fixed, non-repo-controlled data-dir paths —
// never by executing `mise which`/`aqua which` (both would read cwd-dependent config; that path was
// proposed and explicitly rejected during redhat-et/ripwire#225 review). An env var set to the empty
// string counts as unset here, same rule `envOr` already applies everywhere else in this file.
inline bool isKnownShimPath( const std::string& path )
{
    const std::string miseData = envOr( "MISE_DATA_DIR", "" );
    const std::string miseDefault = envOr( "HOME", "" ) + "/.local/share/mise/shims/";
    const std::string aquaRoot = envOr( "AQUA_ROOT_DIR", "" );
    const std::string aquaDefault = envOr( "HOME", "" ) + "/.local/share/aquaproj-aqua/bin/";
    if( !miseData.empty() && path.rfind( miseData + "/shims/", 0 ) == 0 ) { return true; }
    if( path.rfind( miseDefault, 0 ) == 0 ) { return true; }
    if( !aquaRoot.empty() && path.rfind( aquaRoot + "/bin/", 0 ) == 0 ) { return true; }
    if( path.rfind( aquaDefault, 0 ) == 0 ) { return true; }
    return false;
}

// Byte-for-byte comparison, not dev/ino identity: the managed candidate below is a SEPARATE file a
// version manager installed (its own inode), so an install that is a perfect copy of `self` must still
// read as "the same binary" rather than "different file, so broken".
inline bool filesByteIdentical( const std::string& a, const std::string& b )
{
    std::error_code ec;
    const std::uintmax_t sizeA = std::filesystem::file_size( a, ec );
    if( ec ) { return false; }
    const std::uintmax_t sizeB = std::filesystem::file_size( b, ec );
    if( ec || sizeA != sizeB ) { return false; }
    std::ifstream fa( a, std::ios::binary );
    std::ifstream fb( b, std::ios::binary );
    if( !fa || !fb ) { return false; }
    std::vector<char> bufA( 65536 );
    std::vector<char> bufB( 65536 );
    while( fa && fb )
    {
        fa.read( bufA.data(), static_cast<std::streamsize>( bufA.size() ) );
        fb.read( bufB.data(), static_cast<std::streamsize>( bufB.size() ) );
        const std::streamsize gotA = fa.gcount();
        const std::streamsize gotB = fb.gcount();
        if( gotA != gotB ) { return false; }
        if( gotA == 0 ) { break; }
        if( std::memcmp( bufA.data(), bufB.data(), static_cast<std::size_t>( gotA ) ) != 0 ) { return false; }
    }
    return true;
}

// Enumerate ONE manager's version directories under its own on-disk layout — no config parsed, nothing
// executed — and report whether they resolve to exactly one candidate binary. More than one version
// directory is ambiguous on its face (which one is "current" is exactly the question a config file
// would answer, and reading that config is the thing this function must not do), so it counts as
// ambiguous even when only one of those directories happens to contain a binary.
struct ManagerLayout
{
    bool ambiguous = false;
    std::optional<std::string> candidate;
};

// One level of `dir`'s immediate subdirectories, never via a throwing range-for: `directory_iterator`'s
// `operator++` throws on a permission change or race mid-scan, which a doctor check must survive, not
// SIGABRT on. `ec` carries any construction/iteration error; the caller treats that as "give up",
// never as "empty".
inline std::vector<std::filesystem::path> listSubdirectories( const std::filesystem::path& dir, std::error_code& ec )
{
    namespace fs = std::filesystem;
    std::vector<fs::path> out;
    fs::directory_iterator it( dir, ec ), last;
    while( !ec && it != last )
    {
        std::error_code dec;
        if( it->is_directory( dec ) && !dec ) { out.push_back( it->path() ); }
        it.increment( ec );
    }
    return out;
}

// Files named exactly "ripwire" anywhere under `dir` — never following a symlink, and never
// throwing (recursive_directory_iterator's own operator++ can throw on a permission change or race
// mid-scan, same reason listSubdirectories above hand-rolls its own increment(ec) loop). Depth is
// capped at 8: real manager trees are 2-3 levels deep (mise: <version>/<archive>/; aqua:
// <version>/<archive>.tar.gz/<archive>/), and a cap turns a hostile/huge tree into "found nothing
// this deep", never a runaway walk.
inline std::vector<std::filesystem::path> findRipwireBinaries( const std::filesystem::path& dir )
{
    namespace fs = std::filesystem;
    std::vector<fs::path> out;
    std::error_code ec;
    fs::recursive_directory_iterator it( dir, fs::directory_options::skip_permission_denied, ec ), last;
    while( !ec && it != last )
    {
        std::error_code fec;
        if( it->path().filename() == "ripwire" && it->is_regular_file( fec ) && !fec ) { out.push_back( it->path() ); }
        if( it.depth() >= 8 ) { it.disable_recursion_pending(); }
        it.increment( ec );
    }
    return out;
}

// A manager's version directory may nest the real binary arbitrarily deep — mise extracts a release
// archive as <version>/<archive-name>/ripwire (no fixed "bin/"; a prior version of this function
// assumed one and misreported every real mise install as managed_unverified), aqua nests one level
// deeper still behind its own proxy (<version>/<archive>.tar.gz/<archive>/ripwire). Rather than
// hardcode a second exact shape that will rot the next time either manager repackages, this searches
// for exactly one file named "ripwire" under the version directory and reports the same
// ambiguous/no-candidate contract listSubdirectories' caller already relies on: more than one match
// is exactly as undecidable as more than one version directory.
inline ManagerLayout resolveManagerVersionLayout( const std::string& root )
{
    namespace fs = std::filesystem;
    ManagerLayout out;
    std::error_code ec;
    const std::vector<fs::path> versions = listSubdirectories( root, ec );
    if( ec || versions.size() > 1 ) { out.ambiguous = versions.size() > 1; return out; }
    if( versions.size() != 1 ) { return out; }
    const std::vector<fs::path> binaries = findRipwireBinaries( versions.front() );
    if( binaries.size() > 1 ) { out.ambiguous = true; return out; }
    if( binaries.size() == 1 ) { out.candidate = binaries.front().string(); }
    return out;
}

// Resolve a managed install purely from the manager's own on-disk layout. Returns the real binary path
// only when exactly one candidate exists across BOTH managers combined; ambiguity in either manager's
// layout, or zero candidates in both, is reported to the caller as disclosed-unknown rather than guessed.
inline std::optional<std::string> resolveManagedInstall()
{
    const std::string miseInstalls = envOr( "MISE_DATA_DIR", envOr( "HOME", "" ) + "/.local/share/mise" ) + "/installs/ripwire";
    // aqua nests every package under pkgs/<registry>/<host>/<owner>/<repo>/ — "github_release/github.com"
    // is aqua's own registry/host pair for a GitHub Releases-sourced package, not a ripwire-specific
    // choice, and redhat-et/ripwire is this project's own coordinates (review item 8: the prior root
    // omitted the registry/host segment entirely and could never resolve a real aqua install).
    const std::string aquaPkgs = envOr( "AQUA_ROOT_DIR", envOr( "HOME", "" ) + "/.local/share/aquaproj-aqua" ) + "/pkgs/github_release/github.com/redhat-et/ripwire";
    const ManagerLayout mise = resolveManagerVersionLayout( miseInstalls );
    const ManagerLayout aqua = resolveManagerVersionLayout( aquaPkgs );
    if( mise.ambiguous || aqua.ambiguous ) { return std::nullopt; }
    std::vector<std::string> candidates;
    if( mise.candidate ) { candidates.push_back( *mise.candidate ); }
    if( aqua.candidate ) { candidates.push_back( *aqua.candidate ); }
    if( candidates.size() != 1 ) { return std::nullopt; }   // zero or ambiguous — caller discloses unknown
    return candidates.front();
}

// The shim-recognised branch of `binaryCheck`, split out so that function's own complexity stays
// readable: recognising the shim is one decision, resolving what it points at is a second, and this
// is the second — a single-candidate managed install compared byte-for-byte, or a disclosed unknown.
inline Check shimBinaryCheck( const std::string& selfPath )
{
    if( const std::optional<std::string> managed = resolveManagedInstall() )
    {
        const bool haveSelf = !selfPath.empty();
        const bool sameFile = haveSelf && filesByteIdentical( selfPath, *managed );
        Check out{ "codex-binary", !haveSelf || sameFile,
                   "on_path=\"1\" managed=\"1\" same_file=\"" + std::string( sameFile ? "1" : "0" ) + "\"" };
        if( !out.ok ) { out.attrs += " hint=\"the version manager's installed ripwire differs from this one — re-run its install (e.g. `mise install`/`aqua install`) to update it\""; }
        return out;
    }
    // The shim itself is recognised, but the manager's on-disk layout does not resolve to exactly
    // one candidate — disclosed unknown, distinct from both ok=1 and a broken/STALE report.
    return { "codex-binary", true, "on_path=\"1\" managed_unverified=\"1\"" };
}

// The pre-Task-14 fallback for a non-shim `active`: dev/ino identity, then the mtime+size "copied"
// heuristic. Unchanged in substance, just split out of `binaryCheck` alongside `shimBinaryCheck` above.
inline Check fallbackBinaryCheck( const std::string& selfPath, const std::string& active )
{
    os::stat_t selfSt {};
    os::stat_t activeSt {};
    const bool haveSelf = !selfPath.empty() && os::stat( selfPath.c_str(), &selfSt ) == 0;
    const bool haveActive = !active.empty() && os::stat( active.c_str(), &activeSt ) == 0;
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

inline Check binaryCheck( const std::string& selfPath )
{
    const std::string active = resolveExecutable( "ripwire" );
    if( !active.empty() && isKnownShimPath( active ) ) { return shimBinaryCheck( selfPath ); }
    return fallbackBinaryCheck( selfPath, active );
}

// This is codexdoctor's OWN small manifest-v1/v2 reader, deliberately separate from
// `rw::skillsinstall`'s manifest writer: this header does read-only checks of the LIVE surface
// independent of the checkout/install mechanism (see the file banner above), and the only real
// dependency it takes from the embed step is `rw::embedded_skills::kStoreKey` for the staleness
// comparison below.
struct SkillManifest
{
    bool read = false;
    bool version = false;      // true for EITHER v1 or v2 — see `schemaVersion` for which
    int schemaVersion = 0;
    std::string source;        // "" for v1 (pre-migration) or a v2 manifest with no source= line
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
        if( line == "version=1" ) { out.version = true; out.schemaVersion = 1; }
        else if( line == "version=2" ) { out.version = true; out.schemaVersion = 2; }
        else if( line.rfind( "source=", 0 ) == 0 ) { out.source = std::string( line.substr( 7 ) ); }
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

// `installCmd` is the exact repair command to print — codex still names the shell installer
// (`test/codexdoctorcheck.sh` greps that literal), Claude names the embedded verb (Task 12's
// collapsed single-line probe). Threading it through here, rather than rewriting the hint text
// after the fact the way `retargetHint` does for the other two agent-generic checks, is deliberate:
// this row now has THREE distinct hint bodies (not-installed / stale / parity), and a post-hoc
// string-splice would have to duplicate that branching to retarget any one of them correctly.
// The one hint line a not-ok skillsCheck prints, chosen from three distinct causes (stale source=,
// an untracked live entry the installer would refuse to touch, or plain non-parity) — split out of
// skillsCheck so that function is fact-gathering only, this one is message-formatting only.
inline std::string skillsCheckHint( bool stale, const std::vector<std::string>& live,
                                     const std::vector<std::string>& declared, std::string_view installCmd )
{
    if( stale )
    {
        return "run " + std::string( installCmd ) + " (embedded skills have moved on since this was installed)";
    }
    if( live.size() > declared.size() )
    {
        // I2 (round-2 review): declared < live means an untracked ripwire-* entry sits at a name
        // ripwire never linked — real content --force refuses to touch (installForAgent), not a
        // foreign symlink it can repair, so naming --force here would print a remedy that refuses.
        std::vector<std::string> untracked;
        std::set_difference( live.begin(), live.end(), declared.begin(), declared.end(), std::back_inserter( untracked ) );
        std::string names;
        for( const std::string& n : untracked ) { names += ( names.empty() ? "" : ", " ) + n; }
        return names + " exist" + ( untracked.size() == 1 ? "s" : "" ) + " at this skill home but "
             + std::string( installCmd ) + " never linked " + ( untracked.size() == 1 ? "it" : "them" )
             + " — remove it manually if it is not meant to be there";
    }
    return "run " + std::string( installCmd ) + " --force to restore exact manifest parity";
}

inline Check skillsCheck( const std::filesystem::path& skillHome, std::string_view installCmd )
{
    // v2 (schema-versioned, carries `source=`) is preferred when present; a still-unmigrated v1
    // install reads fine too, it just never knows `stale` — that's `knowsSource` below, not a
    // separate code path.
    const std::filesystem::path manifestPathV2 = skillHome / ".ripwire-manifest-v2";
    std::error_code existsEc;
    const bool hasV2 = std::filesystem::exists( manifestPathV2, existsEc );
    const SkillManifest manifest = skillManifest( hasV2 ? manifestPathV2 : skillHome / ".ripwire-manifest-v1" );

    if( !manifest.read )
    {
        // Nothing installed yet is not the same finding as a broken/stale install — ok=1 here on
        // purpose, so a fresh checkout doesn't read as "install is broken". `manifest="0"` is kept
        // (not just `not_installed="1"`) because it is the discriminator existing gates already read
        // to tell "relocated dir is genuinely empty" from "fell back to reading the wrong home".
        return { "codex-skills", true, "manifest=\"0\" not_installed=\"1\" hint=\"run " + std::string( installCmd ) + "\"" };
    }

    bool scanned = false;
    const std::vector<std::string> live = liveSkills( skillHome, scanned );
    const bool parity = manifest.version && scanned && !manifest.duplicate && !manifest.declared.empty() && manifest.declared == live;

    const std::string currentStoreKey( rw::embedded_skills::kStoreKey );
    const bool knowsSource = manifest.schemaVersion == 2 && !manifest.source.empty();
    const bool stale = knowsSource && manifest.source != currentStoreKey;

    Check out{ "codex-skills", parity && !stale,
               "manifest=\"" + std::string( manifest.read ? "1" : "0" ) + "\" declared=\"" + std::to_string( manifest.declared.size() )
               + "\" live=\"" + std::to_string( live.size() ) + "\"" };
    if( stale ) { out.attrs += " stale=\"1\""; }
    if( !out.ok ) { out.attrs += " hint=\"" + skillsCheckHint( stale, live, manifest.declared, installCmd ) + "\""; }
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
    // I2b (round-2 review): the old hint's command now routes into the Codex --hook merge refusal
    // ("not implemented yet", exit 2, no hooks.json written) — printing it would silently no-op.
    return hookRow( "codex-hooks", survey, ok, "route_refs", std::to_string( survey.route.size() ),
                    "Codex advisory hook registration is not implemented in this build (skills install --codex --hook refuses); edit ~/.codex/hooks.json manually if you need it" );
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
                    "run ripwire skills install --claude --hook to register the meter, the primer and the prompt router" );
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
    // CLAUDE_CONFIG_DIR relocates Claude Code's WHOLE config directory — skills/ and settings.json
    // together — so reading $HOME/.claude here would report a correct relocated install as missing
    // skills and an unregistered hook, with a hint telling the user to re-run an installer that had
    // already succeeded. Same envOr() shape as CODEX_HOME/AGENTS_HOME below, including its rule that
    // an env var set to the empty string is UNSET (the shell installers spell that as ${VAR:-...}).
    const std::filesystem::path claudeHome = envOr( "CLAUDE_CONFIG_DIR", envOr( "HOME", "" ) + "/.claude" );
    Check binary = binaryCheck( selfPath );
    binary.name = "claude-binary";
    retargetHint( binary, "reinstall the current build so Claude Code shell calls and this doctor resolve the same ripwire binary" );
    Check skills = skillsCheck( claudeHome / "skills", "ripwire skills install --claude" );
    skills.name = "claude-skills";
    return { binary, skills, claudeHooksCheck( claudeHome / "settings.json" ) };
}

inline std::vector<Check> inspect( const std::string& selfPath )
{
    const std::string home = envOr( "HOME", "" );
    const std::filesystem::path agentHome = envOr( "AGENTS_HOME", home + "/.agents" );
    const std::filesystem::path codexHome = envOr( "CODEX_HOME", home + "/.codex" );
    // I6 (2026-09-18 review round 1): `skills install --codex` is implemented and works (unlike
    // hooksCheck's own hint just below, which still names the shell installer on purpose — the Codex
    // --hook merge is unimplemented and refuses loudly, so pointing at it would be a worse hint).
    return { binaryCheck( selfPath ), skillsCheck( agentHome / "skills", "ripwire skills install --codex" ), hooksCheck( codexHome / "hooks.json" ),
             mcpCheck( codexHome / "config.toml" ) };
}

}   // namespace rw::codexdoctor
