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
// default; Codex uses the cross-agent ~/.agents/skills discovery root documented by current Codex.
//
// The line is a deterministic three-way probe, not an unconditional checkout command — a prebuilt-binary
// user has no checkout, and printing `bash skills/install.sh` at them is a dead instruction:
//   (a) ./skills/install.sh exists relative to cwd            → the relative checkout line;
//   (b) else <exeDir>/../share/ripwire/skills/install.sh      → `bash "<that absolute path>"` — the copy
//       the curl installer stages at <prefix>/share/ripwire/skills (fixed design contract vs
//       <prefix>/bin/<binary>; executablePath is already realpath'd by selfExecutablePath);
//   (c) else                                                  → a clone-pointer comment, never a dead command.
inline void wrapPrintSkillsLine( std::FILE* out, const std::string_view agent, const std::string_view executablePath )
{
    if( agent != "claude" && agent != "codex" )
    {
        return;
    }
    const bool  isCodex     = ( agent == "codex" );
    const char* codexFlag   = isCodex ? " --codex" : "";
    const char* destComment = isCodex ? "${AGENTS_HOME:-~/.agents}/skills" : "~/.claude/skills";

    namespace fs = std::filesystem;
    std::error_code ec;

    // The `--hook` line rides along on the SAME resolved installer for Claude and Codex. It is RECOMMENDED
    // because it is the only lever here that intercepts a default at the moment it is chosen: a skill
    // fires only if the agent recognizes a moment AND spends a call to load it, whereas reaching for
    // Read costs nothing. Still a SEPARATE command, never folded into the line above — opt-in is the
    // hook's design contract, and hookcheck.sh asserts a bare install never touches settings.json.
    const auto hookLine = [ out, isCodex ]( const char* installer, const bool quoted )
    {
        const char* hookFlags = isCodex ? " --codex --hook" : " --hook";
        std::fprintf( out, quoted ? "bash \"%s\"%s   # RECOMMENDED: advisory Read/Grep -> ripwire CLI nudge + session primer (opt-in, never blocks)\n"
                                  : "bash %s%s   # RECOMMENDED: advisory Read/Grep -> ripwire CLI nudge + session primer (opt-in, never blocks)\n",
                      installer, hookFlags );
    };

    // (a) checkout cwd — the repo's own installer is right here
    if( fs::is_regular_file( "skills/install.sh", ec ) && !ec )
    {
        std::fprintf( out, "bash skills/install.sh%s   # deploy to %s (drift-gated)\n", codexFlag, destComment );
        hookLine( "skills/install.sh", false );
        return;
    }

    // (b) prebuilt install — the staged copy next to the binary's prefix
    ec.clear();
    const fs::path stagedInstaller = fs::path( executablePath ).parent_path().parent_path() / "share" / "ripwire" / "skills" / "install.sh";
    if( !executablePath.empty() && fs::is_regular_file( stagedInstaller, ec ) && !ec )
    {
        std::fprintf( out, "bash \"%s\"%s   # deploy to %s (drift-gated)\n", stagedInstaller.string().c_str(), codexFlag, destComment );
        hookLine( stagedInstaller.string().c_str(), true );
        return;
    }

    // (c) nothing local — point at the source instead of printing a command that cannot run
    std::fprintf( out, "# skills not found locally — clone https://github.com/redhat-et/ripwire and run skills/install.sh%s\n", codexFlag );
}

// agent → the context/rules file its use-when blurb belongs in (declarative table, one row per client)
struct WrapBlurbTarget
{
    std::string_view agent;        // agent identifier (CLI argument)
    std::string_view targetFile;   // the file the user pastes the blurb into
};

inline constexpr WrapBlurbTarget kWrapBlurbTargets[] = {
    { "claude",   "CLAUDE.md" },
    { "codex",    "AGENTS.md" },
    { "opencode", "AGENTS.md" },   // read automatically: project root, and ~/.config/opencode/AGENTS.md
    { "cursor",   ".cursor/rules (a .mdc file)" },
    { "windsurf", ".windsurfrules" },
    { "gemini",   "GEMINI.md" },
    { "aider",    "CONVENTIONS.md" },
};

// The ONE shared use-when blurb — single source of truth for every agent recipe (the gate diffs the
// body across agents, so a per-agent fork of this text is a red gate, not a variant). A binary on
// PATH is invisible to an agent until its context file says when to reach for it; this is the
// distilled protocol, sized to paste whole.
//
// The closing "defaults to break" block is stated as PROHIBITIONS, and stated LAST, both on purpose.
// An affirmative verb catalog competes badly with an existing habit — an agent that already knows how
// to open a file does not weigh a list of alternatives; a prohibition interrupts the habit instead of
// bidding against it. Last, because actionable content at the END of a long context measures up to
// +30% stronger (the same finding behind `--order=important-last`). Keep it last if you extend this.
//
// The body sits at the CEILING of wrapverbscheck.sh's 10-20 line band. That is deliberate, not an
// oversight: the next line added here has to displace one, which is the point of a size contract on a
// block whose whole value is that a human will paste it whole.
inline std::vector<std::string_view> wrapUseWhenBlurbLines()
{
    return {
        "## ripwire — deterministic codebase maps (on PATH as `ripwire`)",
        "Reach for it BEFORE blind grep + whole-file reads. First call ~1s cold; after that warm, ~0.1s.",
        "- Orient on a task: `ripwire <dir> --for=\"<task in words>\"` — ranked, quality-annotated",
        "  signatures. Paste symbol/file names from the issue verbatim; named mentions get anchored.",
        "- One task: `--pack-task=\"<task>\"`; before parallel agents: `--plan-lanes=N --task=\"<goal>\"`, then read `lanes[].execution`.",
        "- Have a stack trace / build error: `ripwire <dir> --from-trace=FILE` (`-` = stdin) —",
        "  paste the error, don't paraphrase it into a query.",
        "- Who calls X: `--callers=SYM`. \"Is it safe to change X?\" needs the full blast radius:",
        "  `--impact=SYM` (transitive) plus `--uses=SYM` (every read/write/import site).",
        "- Apply a whole-symbol edit without a whole-file Read: `--replace-symbol-body=SYM` plus `--edit-payload=FILE|-`",
        "  (or insert-before/after); the receipt carries region, blob_sha, edit_check, tests_to_run + ONE next= — no re-read after it; `--edit-check=SYM` is for a contract question WITHOUT an edit in hand.",
        "- Before writing a new fn/class/helper: `--exemplar=\"<what you're writing>\"` — duplicates are born on small tasks.",
        "- Before calling work done: `--quality-delta` (what you made worse), then `--test-gate`.",
        "- Trust notes: counts marked counts_floor are floors, not totals; a zero means \"none",
        "  found\", never \"none exists\".",
        "Defaults to break (less context is measurably MORE accurate, not just cheaper — code-repair",
        "accuracy fell 29% -> 3% as context grew 32K -> 256K tokens, LongCodeBench):",
        "- Do NOT open a file you have not located first: rank with `--for`/`--grep`, then read what it names.",
        "- Do NOT read a whole file to understand one symbol: `--expand=SYM` gives the body + callee sigs.",
        "- Do NOT fan reads across several files to learn one thing: `--pack-task=\"<task>\"` is one call.",
    };
}

// Print the pasteable context-wiring block for one agent: a comment fence naming the client's own
// rules file, the shared body as plain lines (they land in a markdown-ish context file, so no `#`
// prefix — a leading `#` would turn prose into headings on paste), and a closing comment fence.
inline void wrapPrintBlurb( std::FILE* out, const std::string_view agent )
{
    std::string_view targetFile;
    for( const WrapBlurbTarget& t : kWrapBlurbTargets )
    {
        if( t.agent == agent )
        {
            targetFile = t.targetFile;
        }
    }
    if( targetFile.empty() )
    {
        return;
    }

    std::fprintf( out, "#\n# context wiring — a binary on PATH is invisible to an agent until its rules file says when\n"
                       "# to reach for it. Paste the block below into %.*s:\n", int( targetFile.size() ), targetFile.data() );
    std::fprintf( out, "# --- paste into %.*s ---\n", int( targetFile.size() ), targetFile.data() );
    for( const std::string_view line : wrapUseWhenBlurbLines() )
    {
        std::fprintf( out, "%.*s\n", int( line.size() ), line.data() );
    }
    std::fprintf( out, "# --- end paste ---\n" );
}

inline void wrapList( std::FILE* out )
{
    std::fprintf( out,
        "ripwire wrap <agent> — print the recipe to wire ripwire into an agent's loop.\n"
        "  MCP agents:  claude  cursor  codex  windsurf  gemini\n"
        "  CLI-first:   opencode\n"
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

// opencode's config is a DIFFERENT shape, not a different path: the top-level key is `mcp` (not
// `mcpServers`), the entry carries an explicit `type`, and `command` is a single string ARRAY
// rather than a command/args pair. The two cannot share wrapMcpJson's literal — and emitting the
// familiar shape here would be the worst possible failure, since opencode parses that config
// happily and then ignores it. Callers print their own "add to <path>" guidance, so this emits the
// object alone. Keys are held to McpLocalConfig's six (the published schema sets
// additionalProperties:false); test/opencodewrapcheck.sh checks this against the pinned copy.
inline void wrapMcpJsonOpencode()
{
    std::printf(
        "{\n"
        "  \"$schema\": \"https://opencode.ai/config.json\",\n"
        "  \"mcp\": {\n"
        "    \"ripwire\": { \"type\": \"local\", \"command\": [\"ripwire\", \"--mcp\"] }\n"
        "  }\n"
        "}\n" );
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

    // opencode resolves every path through xdg-basedir, so ~/.config/opencode is the DEFAULT, not
    // the location — XDG_CONFIG_HOME relocates it. Accept ~/.opencode as the second candidate.
    const auto opencodeInstalled = [ home ]() -> bool
    {
        std::error_code   ec;
        const char*       xdg  = std::getenv( "XDG_CONFIG_HOME" );
        const std::string base = ( xdg && *xdg ) ? std::string( xdg ) : std::string( home ) + "/.config";
        if( fs::is_directory( base + "/opencode", ec ) && !ec )
        {
            return true;
        }
        ec.clear();
        return fs::is_directory( std::string( home ) + "/.opencode", ec ) && !ec;
    };

    return {
        { "claude",   "~/.claude",                         checkExists( "~/.claude" ) },
        { "cursor",   "~/.cursor",                         checkExists( "~/.cursor" ) },
        { "codex",    "~/.codex",                          checkExists( "~/.codex" ) },
        { "windsurf", "~/.codeium/windsurf",               checkExists( "~/.codeium/windsurf" ) },
        { "gemini",   "~/.gemini",                         checkExists( "~/.gemini" ) },
        { "opencode", "~/.config/opencode",                opencodeInstalled },
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
        std::printf( "# (no-MCP one-shot orientation: ripwire . --for=\"<task>\" --token-budget=2000)\n" );
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
            "# ripwire -> OpenAI Codex (CLI-first; optional MCP is restricted to audit/health verbs)\n"
            "# Add this absolute command to ~/.codex/config.toml (Desktop may not inherit shell PATH):\n"
            "[mcp_servers.ripwire]\n"
            "command = \"%s\"\n"
            "args = [\"--mcp\"]\n"
            "enabled_tools = [\"analyze\", \"quality_delta\", \"flags\", \"doc_drift\"]\n"
            "default_tools_approval_mode = \"approve\"\n", command.c_str() );
    }
    else if( agent == "opencode" )
    {
        // CLI FIRST, MCP second — the one recipe in this table that leads with the shell path.
        // opencode ships a `bash` tool, so the CLI is available to it, and the CLI costs zero
        // context until it is invoked; a registered MCP server's verb schemas are resident every
        // turn whether any verb is called or not (measured in docs/EVALS.md §5). Where an agent can
        // shell out, that standing cost is the whole difference, so the shell recipe goes first.
        std::printf(
            "# ripwire -> opencode (github.com/anomalyco/opencode)\n"
            "# RECOMMENDED — opencode has a `bash` tool, so call the CLI directly. It costs nothing\n"
            "# until you invoke it, and opencode reads AGENTS.md automatically (project root, plus\n"
            "# ~/.config/opencode/AGENTS.md globally), so the paste block below IS the whole wiring:\n"
            "ripwire . --for=\"<your task>\" --token-budget=2000\n"
            "#\n"
            "# ALTERNATIVE — register the MCP server instead, for a warm index across calls. Add to\n"
            "# opencode.json (project) or ~/.config/opencode/opencode.json (global; the two are\n"
            "# merged per-key and the project file wins). The key is \"mcp\" — the \"mcpServers\" shape\n"
            "# other clients use parses fine here and is then silently ignored:\n" );
        wrapMcpJsonOpencode();
    }
    else if( agent == "aider" )
    {
        std::printf(
            "# ripwire -> aider (no MCP; feed a ranked repo map as read-only context)\n"
            "ripwire . --for=\"<your task>\" --token-budget=2000 > .ripwire-map.txt\n"
            "aider --read .ripwire-map.txt\n"
            "# re-run the first line when the tree changes; the warm cache makes it ~instant.\n" );
    }

    // every MCP agent recipe also gets the grouped verb list printed as a comment (cursor/windsurf/
    // gemini/codex use a plain JSON/TOML stanza with no verb comment of their own, so add it here
    // instead of duplicating the printf calls per-branch); aider has no MCP verbs to list.
    if( agent == "cursor" || agent == "windsurf" || agent == "gemini" || agent == "codex" || agent == "opencode" )
    {
        std::printf( "# verbs the agent can then call mid-task (%zu total):\n", kMcpVerbCount );
        for( const std::string& line : verbLines )
        {
            std::printf( "%s\n", line.c_str() );
        }
    }

    // A4-S2: adoption recipes name a skill install step only for verified agent discovery paths.
    wrapPrintSkillsLine( stdout, agent, executablePath );

    // context wiring: every recipe ends with the pasteable use-when blurb for the client's rules file.
    wrapPrintBlurb( stdout, agent );
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
        agent == "codex" || agent == "aider" || agent == "opencode" )
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
