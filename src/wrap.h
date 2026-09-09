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
#include <unistd.h>   // wrapCommandToken (2026-09-06)
#include "skillscan.h"
#include "infra/tablelookup.h"   // findByField — shared with ingest's lookupLang

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

// ── THE AGENT REGISTRY ───────────────────────────────────────────────────────────────────────────
// One row per agent. Adding an agent is a ROW, not a branch.
//
// WHY. Agent identity was branched on in ~30 places across 7 files, and this file alone held three
// parallel lists — context file, detection root, and an if/else recipe chain — kept in agreement by
// hand. Two contributor PRs (#46, #51) adding one agent had to touch all of them.
//
// COMMON vs SPECIFIC. The eighteen SKILL.md files are COMMON: every agent here reads the same
// `name:`/`description:` frontmatter and the same body, so there is one copy of the content and no
// per-agent fork of it. What genuinely varies is a handful of facts, and those are columns. Recipe
// PROSE stays per-agent below, because a TOML stanza is not a JSON stanza and pretending otherwise
// ships a config that parses and does nothing — the exact failure opencodewrapcheck.sh exists for.
//
// PRIMARY is separate from MCP FORM. What we RECOMMEND is a different question from how the agent's
// MCP config is SPELLED. Conflating them is how the codex recipe came to carry a "CLI-first" header
// above a body that emitted only TOML. Where an agent can shell out, the CLI is the recommendation:
// it costs zero context until invoked, whereas a registered MCP server's verb schemas are resident
// every turn whether a verb is called or not (docs/EVALS.md §5). The MCP form is still emitted.
//
// A SHARED ROOT IS A REPEATED VALUE, NEVER A SPECIAL CASE. Codex and openclaw both discover
// ~/.agents/skills; openclaw's own docs call it a "compatibility skill root".
//
// CAVEATS ARE A COLUMN. A root can be conditional — openclaw excludes ~/.agents/skills entirely when
// OPENCLAW_STATE_DIR is not the default ~/.openclaw. Flattening that away would make this tool claim
// support it cannot deliver, so the condition is carried on the row and printed to the user.
enum class WrapPrimary : std::uint8_t { Cli, Mcp, RepoMap };
enum class McpForm     : std::uint8_t { None, CliAdd, Json, Toml, JsonMcpKey };

struct AgentTarget
{
    std::string_view name;
    std::string_view displayName;   // the PRODUCT name. Lost when a shared emitter replaced per-agent
                                    // branches: "ripwire -> openclaw" and "-> Claude Code" are not the
                                    // same sentence, and the branch that knew the difference is gone.
    std::string_view contextFile;
    std::string_view contextNote;   // the rest of the truth about contextFile — a second path it is also
                                    // read from, or WHOSE file it is. openclaw needs this one badly.
    std::string_view homeDir;
    std::string_view skillsRoot;    // "" when this repo owns no verified discovery path
    std::string_view skillsFlag;    // installer flag selecting that root ("" = installer default)
    bool             hookSlot;
    WrapPrimary      primary;
    McpForm          mcpForm;
    std::string_view mcpAddPre;    // McpForm::CliAdd only: the command up to where the path goes
    std::string_view mcpAddPost;   //                     ... and the remainder after it
    std::string_view caveat;
};

inline constexpr AgentTarget kAgentTargets[] = {
    { "claude",   "Claude Code",  "CLAUDE.md",                   "",
      "~/.claude",           "~/.claude/skills",                 "",            true,  WrapPrimary::Cli,     McpForm::CliAdd,     "claude mcp add ripwire -- ",          " --mcp\n",            "" },
    { "codex",    "OpenAI Codex", "AGENTS.md",                   "",
      "~/.codex",            "${AGENTS_HOME:-~/.agents}/skills", " --codex",    true,  WrapPrimary::Cli,     McpForm::Toml,       "",                                    "",                    "" },
    { "cursor",   "Cursor",       ".cursor/rules (a .mdc file)", "",
      "~/.cursor",           "",                                 "",            false, WrapPrimary::Mcp,     McpForm::Json,       "",                                    "",                    "" },
    { "windsurf", "Windsurf",     ".windsurfrules",              "",
      "~/.codeium/windsurf", "",                                 "",            false, WrapPrimary::Mcp,     McpForm::Json,       "",                                    "",                    "" },
    { "gemini",   "Gemini CLI",   "GEMINI.md",                   "",
      "~/.gemini",           "",                                 "",            false, WrapPrimary::Mcp,     McpForm::Json,       "",                                    "",                    "" },
    { "opencode", "opencode",     "AGENTS.md",                   "also read globally from ~/.config/opencode/AGENTS.md",
      "~/.config/opencode",  "",                                 "",            false, WrapPrimary::Cli,     McpForm::JsonMcpKey, "",                                    "",                    "" },
    // openclaw, corrected 2026-09-08 after review. THE CONTEXT FILE WAS WRONG and it mattered: the first
    // version of this row said "AGENTS.md", and the CLI-first prose then told a coding user to paste the
    // wiring into their REPO's AGENTS.md. openclaw never reads that. Its AGENTS.md is the operator's
    // WORKSPACE bootstrap file under the state dir. A recipe naming the wrong file is worse than no row.
    //
    // The skills root is a REPEATED VALUE (Codex's ~/.agents/skills — openclaw's docs call it a
    // "compatibility skill root"), but written LITERALLY, not as ${AGENTS_HOME:-...}: openclaw honours no
    // such env var, so a Codex user who has relocated AGENTS_HOME would otherwise be told to install
    // exactly where openclaw will not look.
    { "openclaw", "openclaw",     "~/.openclaw/workspace/AGENTS.md", "openclaw's own workspace bootstrap file — NOT your repository's AGENTS.md",
      "~/.openclaw",         "~/.agents/skills",                 " --openclaw", false, WrapPrimary::Cli,     McpForm::CliAdd,     "openclaw mcp add ripwire --command ", " --arg --mcp\n",      "skills are read from ~/.agents/skills ONLY when OPENCLAW_STATE_DIR is the default ~/.openclaw; openclaw honours no AGENTS_HOME, and its before_tool_call is a plugin API, not a shell hook slot" },
    // Hermes. Authored in PR #51 (AnkitArya); the maintainer's kAgentTargets consolidation (2026-09-08)
    // folded the six hand-edited Hermes branches here into one row. HERMES_HOME honours the same
    // relocation the installer's --hermes target does. The pre_tool_call hook slot EXISTS (config.yaml)
    // but hooks/ripwire-nudge.sh is not ported yet, so hookSlot stays false until that port lands -
    // emitting a --hook line today would print a command the installer honestly refuses.
    { "hermes",   "Hermes",       "AGENTS.md",                   "",
      "~/.hermes",           "${HERMES_HOME:-~/.hermes}/skills", " --hermes",   false, WrapPrimary::Cli,     McpForm::CliAdd,     "hermes mcp add ripwire --command ",   " --args --mcp\n# verify: hermes mcp test ripwire\n",    "hermes exposes hooks:pre_tool_call in config.yaml (PreToolUse-shaped) but ripwire's nudge hook is not ported yet: the hook install line stays off until that port lands" },
    { "aider",    "aider",        "CONVENTIONS.md",              "",
      "",                    "",                                 "",            false, WrapPrimary::RepoMap, McpForm::None,       "",                                    "",                    "" },
};

inline constexpr const AgentTarget* agentTarget( const std::string_view name ) noexcept
{
    return findByField( kAgentTargets, &AgentTarget::name, name );
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
    const AgentTarget* row = agentTarget( agent );
    if( row == nullptr || row->skillsRoot.empty() )
    {
        return;                      // no verified discovery path for this agent — say nothing
    }
    const std::string flagStr( row->skillsFlag );
    const std::string destStr( row->skillsRoot );
    const char* const codexFlag   = flagStr.c_str();
    const char* const destComment = destStr.c_str();
    const bool        hasHook     = row->hookSlot;   // a COLUMN, not inferred from the skills flag

    namespace fs = std::filesystem;
    std::error_code ec;

    // The `--hook` line rides along on the SAME resolved installer for Claude and Codex. It is RECOMMENDED
    // because it is the only lever here that intercepts a default at the moment it is chosen: a skill
    // fires only if the agent recognizes a moment AND spends a call to load it, whereas reaching for
    // Read costs nothing. Still a SEPARATE command, never folded into the line above — opt-in is the
    // hook's design contract, and hookcheck.sh asserts a bare install never touches settings.json.
    // openclaw was the case that proved this has to be a column: it shares Codex's skills root, so any
    // rule inferring "codex-shaped" from a non-empty skills flag hands it a --codex --hook line for a
    // hook slot it does not have. A row now states it.
    const auto hookLine = [ out, hasHook, &flagStr ]( const char* installer, const bool quoted )
    {
        if( !hasHook )
        {
            return;
        }
        const std::string hookFlagStr = flagStr + " --hook";
        const char* hookFlags = hookFlagStr.c_str();
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
// (the per-agent context file is a column in kAgentTargets above)

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
    const AgentTarget* blurbRow = agentTarget( agent );
    std::string_view   targetFile = ( blurbRow != nullptr ) ? blurbRow->contextFile : std::string_view{};
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
        "ripwire wrap <agent> — print the recipe to wire ripwire into an agent's loop.\n" );

    // Printed FROM the table: a row added above shows up here without anyone remembering to update prose.
    static constexpr struct { WrapPrimary p; std::string_view label; } kGroups[] = {
        { WrapPrimary::Cli,     "  CLI-first:   " },
        { WrapPrimary::Mcp,     "  MCP config:  " },
        { WrapPrimary::RepoMap, "  repo-map:    " },
    };
    for( const auto& g : kGroups )
    {
        std::fprintf( out, "%.*s", int( g.label.size() ), g.label.data() );
        const char* sep = "";
        for( const AgentTarget& a : kAgentTargets )
        {
            if( a.primary == g.p )
            {
                std::fprintf( out, "%s%.*s", sep, int( a.name.size() ), a.name.data() );
                sep = "  ";      // SEPARATOR, not a suffix — a suffix leaves trailing blanks on every line
            }
        }
        std::fprintf( out, "\n" );
    }
    std::fprintf( out,
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
// 2026-09-06 (stranger audit): every recipe spelled the server command as the bare word `ripwire`. The
// installer's own last line is "<dir> is not on PATH — add it", so a new user who then ran this binary by
// absolute path got a recipe that registers a server their agent cannot start, silently. When NOTHING on
// PATH is named ripwire, the recipe names this binary by its absolute path instead. When something is, the
// bare word stays — --doctor's binary-path row is the place a stale PATH copy is judged, not here — and the
// gates that pin the recipe's shape run with a PATH copy present.
inline std::string wrapCommandToken( const std::string_view executablePath )
{
    namespace fs = std::filesystem;
    const char* pathEnv = std::getenv( "PATH" );
    std::string_view path( pathEnv ? pathEnv : "" );
    while( !path.empty() )
    {
        const std::size_t    colon = path.find( ':' );
        const std::string_view dir = path.substr( 0, colon );
        path = ( colon == std::string_view::npos ) ? std::string_view() : path.substr( colon + 1 );
        if( dir.empty() )
        {
            continue;
        }
        std::error_code ec;
        const fs::path  candidate = fs::path( std::string( dir ) ) / "ripwire";
        if( fs::is_regular_file( candidate, ec ) && !ec && ::access( candidate.c_str(), X_OK ) == 0 )
        {
            return "ripwire";
        }
    }
    return executablePath.empty() ? std::string( "ripwire" ) : std::string( executablePath );
}

inline void wrapPrintPathNote( const std::string& token )
{
    if( token != "ripwire" )
    {
        std::printf( "# NOTE: nothing on PATH is named ripwire right now, so the command below is this binary's absolute path;\n"
                     "#       put its directory on PATH (the installer printed the export line) and the bare word works too.\n" );
    }
}

inline void wrapMcpJson( const char* configPath, const std::string& token )
{
    wrapPrintPathNote( token );
    std::printf(
        "# ripwire -> add to %s\n"
        "{\n"
        "  \"mcpServers\": {\n"
        "    \"ripwire\": { \"command\": \"%s\", \"args\": [\"--mcp\"] }\n"
        "  }\n"
        "}\n", configPath, token.c_str() );
}

// opencode's config is a DIFFERENT shape, not a different path: the top-level key is `mcp` (not
// `mcpServers`), the entry carries an explicit `type`, and `command` is a single string ARRAY
// rather than a command/args pair. The two cannot share wrapMcpJson's literal — and emitting the
// familiar shape here would be the worst possible failure, since opencode parses that config
// happily and then ignores it. Callers print their own "add to <path>" guidance, so this emits the
// object alone. Keys are held to McpLocalConfig's six (the published schema sets
// additionalProperties:false); test/opencodewrapcheck.sh checks this against the pinned copy.
inline void wrapMcpJsonOpencode( const std::string& token )
{
    std::printf(
        "{\n"
        "  \"$schema\": \"https://opencode.ai/config.json\",\n"
        "  \"mcp\": {\n"
        "    \"ripwire\": { \"type\": \"local\", \"command\": [\"%s\", \"--mcp\"] }\n"
        "  }\n"
        "}\n", token.c_str() );
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

// Detection for ONE row. Split out of getAgentConfigs so that an agent's exception does not raise the
// complexity of the loop that walks the table — --quality-delta refused the combined version (19 -> 24
// against a bar of 15), and it was right: "how do we detect opencode" and "walk every row" are two
// different jobs that happened to be in one function.
inline std::function<bool()> agentDetector( const AgentTarget& row, const std::string& home )
{
    namespace fs = std::filesystem;

    if( row.homeDir.empty() )
    {
        return []() { return true; };   // aider ships no config dir — it is always available
    }

    if( row.name == "opencode" )
    {
        // opencode resolves every path through xdg-basedir, so ~/.config/opencode is the DEFAULT, not
        // the location — XDG_CONFIG_HOME relocates it. Accept ~/.opencode as the second candidate.
        return [ home ]() -> bool
        {
            std::error_code   ec;
            const char*       xdg  = std::getenv( "XDG_CONFIG_HOME" );
            const std::string base = ( xdg && *xdg ) ? std::string( xdg ) : home + "/.config";
            if( fs::is_directory( base + "/opencode", ec ) && !ec )
            {
                return true;
            }
            ec.clear();
            return fs::is_directory( home + "/.opencode", ec ) && !ec;
        };
    }

    const std::string expanded = ( row.homeDir.front() == '~' )
                                     ? home + std::string( row.homeDir.begin() + 1, row.homeDir.end() )
                                     : std::string( row.homeDir );
    return [ expanded ]() -> bool
    {
        std::error_code ec;
        return fs::is_directory( expanded, ec ) && !ec;
    };
}

// BUILT FROM THE TABLE, not beside it. This was the FIFTH parallel list and the one that mattered most:
// `wrap openclaw` printed a correct recipe while `wrap --all` could not see openclaw at all, because a
// row had been added to the table and nowhere else. The homeDir column was dead until this loop read it.
inline std::vector<AgentConfig> getAgentConfigs() noexcept
{
    const char*       homeEnv = std::getenv( "HOME" );
    const std::string home    = ( homeEnv != nullptr ) ? homeEnv : "";

    std::vector<AgentConfig> configs;
    configs.reserve( std::size( kAgentTargets ) );
    for( const AgentTarget& a : kAgentTargets )
    {
        configs.push_back( { a.name, a.homeDir, agentDetector( a, home ) } );
    }
    return configs;
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

// ONE recipe path for every agent that can shell out, and the point is that the RECOMMENDATION does
// not vary by agent — only the MCP alternative does. Before this there were four near-identical
// CLI-first blocks waiting to happen (opencode had one; codex claimed to be CLI-first in its header
// and emitted only TOML; claude emitted `claude mcp add` while the README told readers to reach for
// the CLI first). A shared emitter makes the recommendation impossible to state inconsistently.
//
// WHY THE CLI IS THE RECOMMENDATION, once, here, instead of in four places: it costs zero context
// until it is invoked. A registered MCP server's verb schemas are resident in the model's context
// every turn whether a verb is called or not (docs/EVALS.md §5). The MCP form is still emitted below
// it, because a warm index across calls is a real reason to want one.
inline void wrapEmitCliFirst( const AgentTarget& row, const std::string& token,
                              const std::string_view executablePath,
                              const std::vector<std::string>& verbLines ) noexcept
{
    std::printf( "# ripwire -> %.*s (CLI-first)\n", static_cast<int>( row.displayName.size() ), row.displayName.data() );
    wrapPrintPathNote( token );
    std::printf(
        "# RECOMMENDED — this agent can run shell commands, so call the CLI directly. It costs\n"
        "# nothing until you invoke it, and it reads %.*s, so the paste block below IS the wiring:\n"
        "%s . --for=\"<your task>\" --token-budget=2000\n"
        "#\n"
        "# ...then add --legend=compact to every FOLLOW-UP call: the legend is a small share of a --for\n"
        "# bundle but most of a --callers/--uses/--impact answer, and the payload is byte-identical either\n"
        "# way. `ripwire --help` carries the measured range (one place, gate-held) -- this line does not\n"
        "# repeat it, because two copies of a number is one copy that goes stale:\n"
        "#   ripwire . --callers=SYM --legend=compact\n",
        static_cast<int>( row.contextFile.size() ), row.contextFile.data(), token.c_str() );
    if( !row.contextNote.empty() )
    {
        std::printf( "#        (%.*s)\n", static_cast<int>( row.contextNote.size() ), row.contextNote.data() );
    }
    if( !row.caveat.empty() )
    {
        std::printf( "# NOTE: %.*s\n", static_cast<int>( row.caveat.size() ), row.caveat.data() );
    }
    if( row.mcpForm == McpForm::None )
    {
        return;
    }
    std::printf( "#\n# ALTERNATIVE — register the MCP server instead, for a warm index across calls:\n" );
    switch( row.mcpForm )
    {
        case McpForm::CliAdd:
        {
            // Two plain literals printed as DATA. An earlier draft stored one printf template here and
            // passed it as a non-literal format string, which then wanted a consteval guard proving
            // every row held exactly one %s. Splitting the command at its substitution point removes
            // the hazard rather than containing it: there is no format string left to get wrong.
            std::printf( "%.*s%s%.*s",
                         static_cast<int>( row.mcpAddPre.size() ),  row.mcpAddPre.data(),
                         token.c_str(),
                         static_cast<int>( row.mcpAddPost.size() ), row.mcpAddPost.data() );
            break;
        }
        case McpForm::Toml:
        {
            // ABSOLUTE, never the PATH token: Codex Desktop may not inherit the shell PATH, so a
            // bare "ripwire" here produces a config that looks right and never starts. Gated by
            // skillinstallcheck.sh, which caught exactly this when the shared emitter first landed.
            const std::string command = wrapTomlString( executablePath );
            std::printf(
                "# The MCP surface here is deliberately RESTRICTED to audit/health verbs — the CLI above is\n"
                "# the general-purpose path, and a narrow always-on server is easier to trust than a wide one.\n"
                "# Add this ABSOLUTE command to ~/.codex/config.toml (Desktop may not inherit shell PATH):\n"
                "[mcp_servers.ripwire]\n"
                "command = \"%s\"\n"
                "args = [\"--mcp\"]\n"
                "enabled_tools = [\"analyze\", \"quality_delta\", \"flags\", \"doc_drift\"]\n"
                "default_tools_approval_mode = \"approve\"\n", command.c_str() );
            break;
        }
        case McpForm::JsonMcpKey:
            std::printf(
                "# opencode.json (project) or ~/.config/opencode/opencode.json (global; merged\n"
                "# per-key, project wins). The key is \"mcp\" — the \"mcpServers\" shape other clients\n"
                "# use parses fine here and is then silently ignored:\n" );
            wrapMcpJsonOpencode( token );
            break;
        case McpForm::Json:
        case McpForm::None:
            break;
    }
    std::printf( "# verbs the agent can then call mid-task (%zu total):\n", kMcpVerbCount );
    for( const std::string& line : verbLines )
    {
        std::printf( "%s\n", line.c_str() );
    }
}

// Emit the configuration recipe for a single agent (shared by runWrap and --all logic)
inline void wrapEmitAgent( const std::string_view agent, const std::vector<std::string>& verbLines,
                           const std::string_view executablePath ) noexcept
{
    const std::string token = wrapCommandToken( executablePath );   // 2026-09-06: "ripwire", or this binary's absolute path when PATH has none

    // Every agent that can shell out takes ONE shared path. Rows decide, not branches.
    const AgentTarget* const cliRow = agentTarget( agent );
    const bool cliFirst = ( cliRow != nullptr && cliRow->primary == WrapPrimary::Cli );

    // MCP clients get their product name from the row too — only the STANZA SHAPE differs between them,
    // and that is all the branches below decide. Emitted here rather than inside each branch so a new
    // MCP row cannot forget it.
    if( cliRow != nullptr && cliRow->primary == WrapPrimary::Mcp )
    {
        std::printf( "# ripwire -> %.*s (MCP — deterministic, no LLM, no embeddings)\n",
                     static_cast<int>( cliRow->displayName.size() ), cliRow->displayName.data() );
    }

    if( cliFirst )
    {
        wrapEmitCliFirst( *cliRow, token, executablePath, verbLines );
    }
    else if( agent == "cursor" )
    {
        wrapMcpJson( ".cursor/mcp.json  (project)  or  ~/.cursor/mcp.json  (global)", token );
    }
    else if( agent == "windsurf" )
    {
        wrapMcpJson( "~/.codeium/windsurf/mcp_config.json", token );
    }
    else if( agent == "gemini" )
    {
        wrapMcpJson( "~/.gemini/settings.json", token );
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
    if( !cliFirst && ( agent == "cursor" || agent == "windsurf" || agent == "gemini" ) )
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
    if( agentTarget( agent ) != nullptr )   // the table IS the accept-list; a new row needs no edit here
    {
        wrapEmitAgent( agent, verbLines, executablePath );
        return 0;
    }

    std::fprintf( stderr, "ripwire wrap: unknown agent '%.*s'\n", int( agent.size() ), agent.data() );
    wrapList( stderr );
    wrapMcpJson( "your client's MCP config (generic stanza)", wrapCommandToken( executablePath ) );   // don't leave them stuck
    return 2;
}

}   // namespace rw
