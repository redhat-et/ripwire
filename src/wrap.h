#pragma once

// wrap.h — `ripwire wrap <agent>`: print the copy-paste recipe that wires ripwire into a coding
// agent's loop. The adoption pattern from the competitive scan: get the deterministic map/MCP IN
// FRONT of the agent instead of waiting to be invoked by hand. Pure — prints to stdout, no side
// effects, no config mutation (the user reviews + runs it), deterministic. MCP-speaking agents get
// the server stanza; aider (no MCP) gets the repo-map-as-read-only-context recipe.
//
// P1-C: before printing the recipe, scan ./skills and .agents/skills for CRITICAL findings.
// CRITICAL → stderr warning + return 1 (unless --force in argv). WARN → print + continue.

#include "mcp.h"       // kMcpVerbTable / kMcpVerbCount — the single source of truth for the MCP verb list (A4-S2)
#include "skillscan.h"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// Render kMcpVerbTable as three comma-joined, grouped lines (read / flagship-reflex / edit) for
// the wrap recipe's "verbs the agent can then call mid-task" comment block. Derives from the
// same table mcp.h's tools/list JSON is kept in sync with — see the A4-S2 comment on
// kMcpVerbTable — so a verb can't ship without appearing here. Returns text ready to be printed
// one line at a time by the caller (each line already has no trailing newline).
inline std::vector<std::string> wrapVerbGroupLines()
{
    std::string readLine, reflexLine, editLine;
    for( const McpVerbInfo& v : kMcpVerbTable )
    {
        std::string* line = ( v.group == McpVerbGroup::Read )           ? &readLine
                           : ( v.group == McpVerbGroup::FlagshipReflex ) ? &reflexLine
                                                                          : &editLine;
        if( !line->empty() )
        {
            *line += ", ";
        }
        *line += v.name;
    }
    return {
        "#   read:             " + readLine,
        "#   flagship reflex:  " + reflexLine,
        "#   edit:             " + editLine,
    };
}

// Append the install command only where this repo owns a verified discovery path. Claude is the installer
// default; Codex uses its explicit mode so `wrap codex` cannot silently populate the wrong agent home.
inline void wrapPrintSkillsLine( std::FILE* out, const std::string_view agent )
{
    if( agent == "claude" )
    {
        std::fprintf( out, "bash skills/install.sh   # deploy to ~/.claude/skills (drift-gated)\n" );
    }
    else if( agent == "codex" )
    {
        std::fprintf( out, "bash skills/install.sh --codex   # deploy to ${CODEX_HOME:-~/.codex}/skills (drift-gated)\n" );
    }
}

inline void wrapList( std::FILE* out )
{
    std::fprintf( out,
        "ripwire wrap <agent> — print the recipe to wire ripwire into an agent's loop.\n"
        "  MCP agents:  claude  cursor  codex  windsurf  gemini\n"
        "  repo-map:    aider\n"
        "  example:     ripwire wrap claude\n"
        "  --all        detect every installed agent + emit each one's config\n" );
}

// TOML basic-string escape for the executable path embedded in the Codex registration stanza.
// The path is machine-local adoption output, not part of the deterministic repository map.
inline std::string wrapTomlString( const std::string_view value )
{
    std::string out;
    out.reserve( value.size() + 8 );
    for( const char c : value )
    {
        if( c == '\\' || c == '"' )
        {
            out.push_back( '\\' );
        }
        out.push_back( c );
    }
    return out;
}

// emit a standard JSON MCP-server stanza for the editors that share that shape
inline void wrapMcpJson( const char* configPath )
{
    std::printf(
        "# ripwire -> add to %s\n"
        "{\n"
        "  \"mcpServers\": {\n"
        "    \"ripwire\": { \"command\": \"ripwire\", \"args\": [\"--mcp\"] }\n"
        "  }\n"
        "}\n", configPath );
}

// Agent configuration: name, config directory path (using ~ for home), and a lambda to
// check if it's installed (directory exists). The lambda captures the home expansion.
struct AgentConfig
{
    std::string_view name;           // agent identifier (CLI argument)
    std::string_view configDirTpl;   // config directory path (with ~ for home; aider uses empty)
    // return true if this agent's config directory exists
    std::function<bool()> isInstalled;
};

inline std::vector<AgentConfig> getAgentConfigs() noexcept
{
    namespace fs = std::filesystem;
    const char* home = std::getenv( "HOME" );
    if( !home )
    {
        home = "";
    }

    // Each agent's detection: expand ~ in the template path and check if it exists
    const auto expandPath = [ home ]( std::string_view tpl ) -> std::string
    {
        if( tpl.empty() )
        {
            return std::string();
        }
        if( tpl.front() == '~' )
        {
            std::string s( home );
            s.append( tpl.begin() + 1, tpl.end() );
            return s;
        }
        return std::string( tpl );
    };
    const auto checkExists = [ home ]( std::string_view tpl ) -> std::function<bool()>
    {
        return [ tpl, home ]() -> bool
        {
            if( tpl.empty() )
            {
                return false; // aider has no config dir
            }
            std::string path = tpl.front() == '~' ? std::string( home ) + std::string( tpl.begin() + 1, tpl.end() )
                                                   : std::string( tpl );
            std::error_code ec;
            return fs::is_directory( path, ec ) && !ec;
        };
    };

    return {
        { "claude",   "~/.claude",                         checkExists( "~/.claude" ) },
        { "cursor",   "~/.cursor",                         checkExists( "~/.cursor" ) },
        { "codex",    "~/.codex",                          checkExists( "~/.codex" ) },
        { "windsurf", "~/.codeium/windsurf",               checkExists( "~/.codeium/windsurf" ) },
        { "gemini",   "~/.gemini",                         checkExists( "~/.gemini" ) },
        { "aider",    "",                                  []() { return true; } },   // aider is always available
    };
}

// Scan a local skills directory (best-effort). Returns worst severity found (0/1/2).
// Prints WARN/CRITICAL findings to stderr. Silent on no findings / dir absent.
inline int wrapScanSkillDir( const std::string& dir, bool force ) noexcept
{
    namespace fs = std::filesystem;
    std::error_code ec;
    if( !fs::exists( dir, ec ) || ec )
    {
        return 0;
    }

    // Collect + sort .md paths for determinism.
    std::vector<std::string> mdPaths;
    for( const auto& entry : fs::recursive_directory_iterator( dir, fs::directory_options::skip_permission_denied, ec ) )
    {
        if( !ec && entry.is_regular_file( ec ) && !ec && entry.path().extension() == ".md" )
        {
            mdPaths.push_back( entry.path().string() );
        }
        ec.clear();
    }
    std::sort( mdPaths.begin(), mdPaths.end() );

    int maxSev = 0;
    for( const std::string& p : mdPaths )
    {
        const std::vector<SkillFinding> findings = scanSkillFile( p );
        const int code = skillScanExitCode( findings );
        if( code <= 0 )
        {
            continue;
        }
        if( code > maxSev )
        {
            maxSev = code;
        }
        for( const SkillFinding& f : findings )
        {
            if( f.sev == SkillSeverity::Info )
            {
                continue; // silent on INFO
            }
            std::fprintf( stderr, "ripwire wrap: %s  %s:%d  %s  — \"%s\"\n",
                          skillSeverityStr( f.sev ), p.c_str(), f.line, f.rule, f.excerpt.c_str() );
        }
    }
    return maxSev;
}

// Emit the configuration recipe for a single agent (shared by runWrap and --all logic)
inline void wrapEmitAgent( const std::string_view agent, const std::vector<std::string>& verbLines,
                           const std::string_view executablePath ) noexcept
{
    if( agent == "claude" )
    {
        std::printf(
            "# ripwire -> Claude Code (MCP — deterministic, no LLM, no embeddings)\n"
            "claude mcp add ripwire -- ripwire --mcp\n"
            "# verbs the agent can then call mid-task (%zu total):\n", kMcpVerbCount );
        for( const std::string& line : verbLines )
        {
            std::printf( "%s\n", line.c_str() );
        }
        std::printf( "# (no-MCP one-shot orientation: ripwire . --for=\"<task>\" --max-tokens=2000)\n" );
    }
    else if( agent == "cursor" )
    {
        wrapMcpJson( ".cursor/mcp.json  (project)  or  ~/.cursor/mcp.json  (global)" );
    }
    else if( agent == "windsurf" )
    {
        wrapMcpJson( "~/.codeium/windsurf/mcp_config.json" );
    }
    else if( agent == "gemini" )
    {
        wrapMcpJson( "~/.gemini/settings.json" );
    }
    else if( agent == "codex" )
    {
        const std::string command = wrapTomlString( executablePath );
        std::printf(
            "# ripwire -> OpenAI Codex CLI — add to ~/.codex/config.toml\n"
            "[mcp_servers.ripwire]\n"
            "command = \"%s\"\n"
            "args = [\"--mcp\"]\n", command.c_str() );
    }
    else if( agent == "aider" )
    {
        std::printf(
            "# ripwire -> aider (no MCP; feed a ranked repo map as read-only context)\n"
            "ripwire . --for=\"<your task>\" --max-tokens=2000 > .ripwire-map.txt\n"
            "aider --read .ripwire-map.txt\n"
            "# re-run the first line when the tree changes; the warm cache makes it ~instant.\n" );
    }

    // every MCP agent recipe also gets the grouped verb list printed as a comment (cursor/windsurf/
    // gemini/codex use a plain JSON/TOML stanza with no verb comment of their own, so add it here
    // instead of duplicating the printf calls per-branch); aider has no MCP verbs to list.
    if( agent == "cursor" || agent == "windsurf" || agent == "gemini" || agent == "codex" )
    {
        std::printf( "# verbs the agent can then call mid-task (%zu total):\n", kMcpVerbCount );
        for( const std::string& line : verbLines )
        {
            std::printf( "%s\n", line.c_str() );
        }
    }

    // A4-S2: adoption recipes name a skill install step only for verified agent discovery paths.
    wrapPrintSkillsLine( stdout, agent );
}

inline int runWrap( int argc, char** argv, const std::string_view executablePath )
{
    if( argc < 3 ) { wrapList( stdout ); return 0; }
    const std::string_view arg = argv[ 2 ];

    // ── P1-C: scan local skill directories before emitting the recipe ─────────────────────────
    // Best-effort: missing dirs are silently skipped. CRITICAL → block unless --force.
    bool force = false;
    for( int i = 3; i < argc; ++i )
    {
        if( std::string_view( argv[i] ) == "--force" )
        {
            force = true;
        }
    }

    int warnSev  = wrapScanSkillDir( "./skills",       force );
    int warnSev2 = wrapScanSkillDir( ".agents/skills", force );
    const int maxWrapSev = std::max( warnSev, warnSev2 );

    if( maxWrapSev >= 2 && !force )
    {
        std::fprintf( stderr,
            "ripwire wrap: CRITICAL skill findings above — refusing to emit recipe.\n"
            "              Fix the skills or re-run with --force to proceed anyway.\n" );
        return 1;
    }

    // All MCP verbs, grouped — derived from mcp.h's kMcpVerbTable so this cannot re-drift (A4-S2).
    const std::vector<std::string> verbLines = wrapVerbGroupLines();

    // ── Handle --all: detect + emit every installed agent ─────────────────────────────────────
    if( arg == "--all" )
    {
        const std::vector<AgentConfig> agents = getAgentConfigs();
        int configuredCount = 0, skippedCount = 0;

        for( const AgentConfig& ac : agents )
        {
            if( !ac.isInstalled() )
            {
                ++skippedCount;
                continue;
            }
            if( configuredCount > 0 )
            {
                std::printf( "\n" ); // blank line separator between agents
            }
            std::printf( "# ──── %.*s ────\n", int( ac.name.size() ), ac.name.data() );
            wrapEmitAgent( ac.name, verbLines, executablePath );
            ++configuredCount;
        }

        std::printf( "\n# summary: %d surfaces configured, %d skipped (not detected)\n",
                     configuredCount, skippedCount );
        return 0;
    }

    // ── Handle single agent request ───────────────────────────────────────────────────────────
    const std::string_view agent = arg;
    if( agent == "claude" || agent == "cursor" || agent == "windsurf" || agent == "gemini" ||
        agent == "codex" || agent == "aider" )
    {
        wrapEmitAgent( agent, verbLines, executablePath );
        return 0;
    }

    std::fprintf( stderr, "ripwire wrap: unknown agent '%.*s'\n", int( agent.size() ), agent.data() );
    wrapList( stderr );
    wrapMcpJson( "your client's MCP config (generic stanza)" );   // don't leave them stuck
    return 2;
}

}   // namespace rw
