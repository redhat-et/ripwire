#pragma once
#if !defined( RIPWIRE_MAIN_TU )
#error "verbs_doctor.h is a SECTION of src/main.cpp's translation unit - include it only from main.cpp (see the verb-family split note there)"
#endif

// verbs_doctor.h — the --doctor verb family (runDoctor + its probes and agent-surface rows), moved
// VERBATIM from main.cpp in the 2026-08-29 split. This is not a standalone header: it reopens
// main.cpp's unnamed namespace (one TU, one unnamed namespace — everything here keeps the internal
// linkage it had inside main.cpp, so the split adds zero API surface) and leans on main.cpp's own
// top-of-file #includes and preamble helpers. The RIPWIRE_MAIN_TU guard turns a second includer into
// a compile error instead of a silent per-TU-copy ODR trap.

namespace
{

// ─── --doctor: self-diagnosis (standing item) ─────────────────────────────────────────────────────
// A DIAGNOSTIC verb, not the deterministic map: every check below reports on THIS machine's
// environment (binary identity, PATH resolution, filesystem, git, tree-sitter grammars) — by
// construction its output varies run-to-run and machine-to-machine, so the det-gate
// ("byte-identical run-to-run") does NOT apply to --doctor. Never crashes: every probe degrades to
// ok="0" (or a "can't tell" attr) on failure, never aborts. Single-root only for v1 — refused
// earlier in main() alongside --eval/--test-gate/--quality-delta (each check below is per-repo or
// per-machine, not something a multi-root workspace composes cleanly).
//
// Kept OUT of ingest.cpp/ingest.h/mcp.h/quality.h by task scope: the grammar-probe check (2) compiles
// the same configure-generated immutable query views as ingest, without consulting the source checkout.
extern "C"
{
    const TSLanguage* tree_sitter_cpp( void );
    const TSLanguage* tree_sitter_python( void );
    const TSLanguage* tree_sitter_go( void );
    const TSLanguage* tree_sitter_rust( void );
    const TSLanguage* tree_sitter_typescript( void );
    const TSLanguage* tree_sitter_tsx( void );
    const TSLanguage* tree_sitter_swift( void );
    const TSLanguage* tree_sitter_objc( void );
    const TSLanguage* tree_sitter_javascript( void );
    const TSLanguage* tree_sitter_bash( void );
    const TSLanguage* tree_sitter_java( void );
    const TSLanguage* tree_sitter_ruby( void );
    const TSLanguage* tree_sitter_json( void );
    const TSLanguage* tree_sitter_toml( void );
    const TSLanguage* tree_sitter_yaml( void );
    const TSLanguage* tree_sitter_c_sharp( void );
    const TSLanguage* tree_sitter_c( void );
    const TSLanguage* tree_sitter_cuda( void );
    const TSLanguage* tree_sitter_markdown( void );
    const TSLanguage* tree_sitter_php( void );
    const TSLanguage* tree_sitter_lua( void );
}

// This process's own executable path, realpath'd. macOS uses _NSGetExecutablePath and Linux uses
// /proc/self/exe because argv[0] is often just "ripwire" after shell PATH resolution. Other platforms
// fall back to realpath(argv0), then an explicit PATH search. Never crashes: failure degrades to "".
inline std::string selfExecutablePath( const char* argv0 )
{
#if defined( __APPLE__ )
    char          buf[ PATH_MAX ];
    std::uint32_t size = sizeof( buf );
    if( _NSGetExecutablePath( buf, &size ) == 0 )
    {
        char resolved[ PATH_MAX ];
        if( ::realpath( buf, resolved ) )
        {
            return std::string( resolved );
        }
        return std::string( buf );
    }
#elif defined( __linux__ )
    char          buf[ PATH_MAX ];
    const ssize_t byteCount = ::readlink( "/proc/self/exe", buf, sizeof( buf ) - 1 );
    if( byteCount > 0 )
    {
        buf[ byteCount ] = '\0';
        char resolved[ PATH_MAX ];
        if( ::realpath( buf, resolved ) )
        {
            return std::string( resolved );
        }
        return std::string( buf );
    }
#endif
    char resolved[ PATH_MAX ];
    if( argv0 && ::realpath( argv0, resolved ) )
    {
        return std::string( resolved );
    }

    // Last-resort PATH search for platforms without a process-executable API. Returning a bare argv0
    // would recreate the exact Codex Desktop failure this path is used to prevent.
    if( argv0 && *argv0 && !std::strchr( argv0, '/' ) )
    {
        const char* pathEnv = std::getenv( "PATH" );
        std::string_view remaining = pathEnv ? std::string_view( pathEnv ) : std::string_view();
        while( !remaining.empty() )
        {
            const std::size_t split = remaining.find( ':' );
            const std::string_view dir = remaining.substr( 0, split );
            const std::string candidate = std::string( dir.empty() ? "." : dir ) + "/" + argv0;
            if( ::realpath( candidate.c_str(), resolved ) && ::access( resolved, X_OK ) == 0 )
            {
                return std::string( resolved );
            }
            if( split == std::string_view::npos )
            {
                break;
            }
            remaining.remove_prefix( split + 1 );
        }
    }
    return {};
}

// popen a shell command, return its trimmed stdout ("" on any failure — never crashes). One shared copy
// (quality.h popenTrimmed) serves this and the quality git one-liners.
inline std::string doctorPopenTrim( const std::string& cmd )
{
    return rw::quality::popenTrimmed( cmd );
}

// §P11 doctor item: --doctor's failing rows used to print raw mtimes/sizes/counts with no conclusion — the
// one verb whose job is diagnosis made the reader do the diagnosis. Each helper below returns the empty
// string on a PASSING check and a ` hint="..."` attribute fragment on a failing one, naming the derived
// verdict (which side is stale, which grammars failed, what to fix) instead of leaving raw facts to
// interpret. Pulled out of runDoctor (rather than inlined per check) so five small conditionals don't add
// their nesting-weighted cognitive-complexity/verbosity cost to a function that dispatches six checks already.

inline std::string doctorBinaryPathVerdictAttr( bool copied, const std::string& selfPath, const std::string& whichPath,
                                                const struct stat& selfSt, const struct stat& whichSt, std::vector<char>& esc )
{
    if( copied )
    {
        return " copied=\"1\"";
    }
    const bool        selfIsOlder = selfSt.st_mtime < whichSt.st_mtime;
    const std::string olderPath   = selfIsOlder ? selfPath : whichPath;
    const std::string newerPath   = selfIsOlder ? whichPath : selfPath;
    return " hint=\"" + std::string( rw::escapeXml( std::string_view(
                  "STALE: " + olderPath + " is older than " + newerPath
                + " — rebuild/reinstall so PATH points at the newer one, or invoke "
                + newerPath + " directly" ), esc ) ) + "\"";
}

inline std::string doctorGrammarsHint( int loaded, int expected, const std::string& failedLabels, std::vector<char>& esc )
{
    if( loaded == expected )
    {
        return "";
    }
    return " hint=\"" + std::string( rw::escapeXml( std::string_view(
                  "failed to compile: " + failedLabels
                + " — a build/embedded-resource mismatch (rebuild with cmake --build build -j; "
                  "if it persists the embedded tags.scm for that language is stale)" ), esc ) ) + "\"";
}

// --doctor check 2's probe, in full: does each compiled-in grammar's tags.scm actually compile
// (ts_query_new — the same operation ingest()'s prewarm performs)? Pulled out of runDoctor (not just the
// hint) so the for-loop + its two ifs (pre-existing) and the label-collecting else (new, for the hint
// above) all land on a new symbol instead of runDoctor's own complexity.
struct DoctorGrammarProbe { int loaded = 0; int expected = 0; std::string failedLabels; };

// The probe for a grammar that ships NO tags.scm (markdown — ingest walks its tree directly): the honest
// health check is the pairing ingest actually uses, set_language + a real parse of a one-line doc.
inline bool doctorParseProbe( const TSLanguage* ( *grammar )( void ) )
{
    bool      ok = false;
    TSParser* p  = ts_parser_new();
    if( p != nullptr )
    {
        if( ts_parser_set_language( p, grammar() ) )
        {
            static constexpr std::string_view kProbeDoc = "# t\n";
            TSTree* t = ts_parser_parse_string( p, nullptr, kProbeDoc.data(), std::uint32_t( kProbeDoc.size() ) );
            if( t != nullptr )
            {
                ok = !ts_node_is_null( ts_tree_root_node( t ) );
                ts_tree_delete( t );
            }
        }
        ts_parser_delete( p );
    }
    return ok;
}

inline DoctorGrammarProbe doctorProbeGrammars()
{
    struct GEntry { const char* querySub; const TSLanguage* (*grammar)( void ); const char* label; };
    static const GEntry kTable[] = {
        { "cpp",        &tree_sitter_cpp,        "cpp"        },
        { "python",     &tree_sitter_python,     "python"     },
        { "go",         &tree_sitter_go,         "go"         },
        { "rust",       &tree_sitter_rust,       "rust"       },
        { "typescript", &tree_sitter_typescript, "typescript" },
        { "typescript", &tree_sitter_tsx,        "tsx"        },
        { "swift",      &tree_sitter_swift,      "swift"      },
        { "objc",       &tree_sitter_objc,       "objc"       },
        { "javascript", &tree_sitter_javascript, "javascript" },
        { "bash",       &tree_sitter_bash,       "bash"       },
        { "java",       &tree_sitter_java,       "java"       },
        { "ruby",       &tree_sitter_ruby,       "ruby"       },
        { "json",       &tree_sitter_json,       "json"       },
        // The four below were MISSING while the binary linked them, so --doctor reported "13 of 13
        // grammars ok" on a build carrying 17 probeable entries: a csharp/c/cuda/toml query that failed
        // to compile was invisible to the one check whose whole job is to say so. Found by the TOML
        // round's sibling sweep (docs/METHODOLOGY.md §3). `cuda` deliberately shares the "cpp" querySub
        // — it is a generated superset of tree-sitter-cpp and rides cpp's tags.scm, exactly as `tsx`
        // shares "typescript" above — so what is probed for it is cpp's query against the CUDA grammar,
        // which is precisely the pairing ingest uses.
        { "toml",       &tree_sitter_toml,       "toml"       },
        { "yaml",       &tree_sitter_yaml,       "yaml"       },
        { "csharp",     &tree_sitter_c_sharp,    "csharp"     },
        { "c",          &tree_sitter_c,          "c"          },
        { "cpp",        &tree_sitter_cuda,       "cuda"       },
        { "php",        &tree_sitter_php,        "php"        },
        { "lua",        &tree_sitter_lua,        "lua"        },
        // markdown carries NO tags.scm — ingest extracts sections by a custom tree walk, so the honest
        // probe is the pairing ingest actually uses: set_language + a real parse, not a query compile.
        { nullptr,      &tree_sitter_markdown,   "markdown"   },
    };
    DoctorGrammarProbe out;
    out.expected = int( sizeof( kTable ) / sizeof( kTable[0] ) );
    for( const GEntry& g : kTable )
    {
        bool ok = false;
        if( g.querySub == nullptr )
        {
            ok = doctorParseProbe( g.grammar );
        }
        else
        {
            const std::string_view scm = rw::embedded_queries::queryFor( g.querySub );
            if( !scm.empty() )
            {
                std::uint32_t errOff  = 0;
                TSQueryError  errType = TSQueryErrorNone;
                TSQuery*      q       = ts_query_new( g.grammar(), scm.data(), static_cast<std::uint32_t>( scm.size() ), &errOff, &errType );
                if( q ) { ok = true; ts_query_delete( q ); }
            }
        }
        if( ok )
        {
            ++out.loaded;
        }
        else
        {
            if( !out.failedLabels.empty() )
            {
                out.failedLabels += ",";
            }
            out.failedLabels += g.label;
        }
    }
    return out;
}

// §L10: `capHit` is a NARROWER fact than `truncated` — truncated is "count and/or bytes may be short for
// SOME reason" (an I/O error mid-scan counts too), while capHit is specifically "we stopped counting at
// kMaxCacheBlobCount because there may be more, not because anything failed". blobCount lands on EXACTLY
// the same value (kMaxCacheBlobCount) whether the true count is exactly that many or far more, so
// blobs="4096" alone cannot tell a reader which; blobs_floor= (emitted only when capHit) closes that gap
// the same way counts_floor= does everywhere else in this tool. An I/O-error truncation never sets capHit,
// so it never gets a floor label it cannot back — the count it stopped at there IS the true count so far.
struct DoctorCacheStats { std::size_t blobCount = 0; std::uintmax_t totalBytes = 0; bool truncated = false; bool capHit = false; };

// Count legacy flat blobs plus the current one-level, two-hex shard layout. The 4K cap matches cache
// hygiene's retained-blob cap; truncated= makes an I/O error or over-cap result an honest floor.
inline DoctorCacheStats doctorCacheStats( const std::string& dir )
{
    namespace fs = std::filesystem;
    DoctorCacheStats out;
    const auto account = [ & ]( const fs::directory_entry& entry )
    {
        const std::string name = entry.path().filename().string();
        if( name.rfind( "ripwire-", 0 ) != 0 ) { return; }
        std::error_code ec;
        if( !entry.is_regular_file( ec ) ) { if( ec ) { out.truncated = true; } return; }
        if( out.blobCount >= rw::quality::kMaxCacheBlobCount ) { out.truncated = true; out.capHit = true; return; }
        ++out.blobCount;
        const auto byteSize = entry.file_size( ec );
        if( ec ) { out.truncated = true; return; }
        out.totalBytes += byteSize;
    };
    const auto scanShard = [ & ]( const fs::path& shard )
    {
        std::error_code ec;
        fs::directory_iterator it( shard, ec ), end;
        if( ec ) { out.truncated = true; return; }
        while( it != end && !out.truncated )
        {
            account( *it );
            it.increment( ec );
            if( ec ) { out.truncated = true; }
        }
    };
    const auto isShardName = []( const std::string& name )
    {
        return name.size() == 2 && std::isxdigit( static_cast<unsigned char>( name[0] ) )
             && std::isxdigit( static_cast<unsigned char>( name[1] ) );
    };

    std::error_code ec;
    fs::directory_iterator it( dir, ec ), end;
    if( ec ) { out.truncated = true; return out; }
    while( it != end && !out.truncated )
    {
        const std::string name = it->path().filename().string();
        if( name.rfind( "ripwire-", 0 ) == 0 )
        {
            account( *it );
        }
        else if( isShardName( name ) )
        {
            std::error_code sec;
            if( it->is_directory( sec ) ) { scanShard( it->path() ); }
            else if( sec ) { out.truncated = true; }
        }
        it.increment( ec );
        if( ec ) { out.truncated = true; }
    }
    return out;
}

inline std::string doctorCacheDirHint( bool writable, const std::string& dir, std::vector<char>& esc )
{
    if( writable )
    {
        return "";
    }
    return " hint=\"" + std::string( rw::escapeXml( std::string_view(
                  "cannot write to " + dir + " (from TMPDIR/XDG_CACHE_HOME/tmp fallback) — fix its "
                  "permissions, or point TMPDIR/XDG_CACHE_HOME at a directory you can write to" ), esc ) ) + "\"";
}

inline std::string doctorGitHint( bool gitAvailable )
{
    if( gitAvailable )
    {
        return "";
    }
    return " hint=\"git not found on PATH — install it (required for --hotspots/--cochange/--owners/"
           "--merge-scout/--quality-delta and every other churn-mining verb) or check PATH\"";
}

inline std::string doctorTrackedBinariesHint( bool ok, std::size_t staleCount )
{
    if( ok )
    {
        return "";
    }
    return " hint=\"" + std::to_string( staleCount ) + " stale tracked binar" + ( staleCount == 1 ? "y" : "ies" )
         + " — the source (src0=, src1=, …) was committed AFTER its binary (p0=, p1=, …); "
           "rebuild the binary from that newer source and recommit it\"";
}

struct DoctorAgentRows
{
    int checks = 0;
    int passed = 0;
    std::string rows;
    std::string rootAttr;
};

inline DoctorAgentRows doctorAgentRows( const rw::Config& cfg, const char* argv0 )
{
    DoctorAgentRows out;
    if( cfg.agent != "codex" && cfg.agent != "claude" ) { return out; }
    const bool claude = cfg.agent == "claude";
    out.rootAttr = claude ? " agent=\"claude\"" : " agent=\"codex\"";
    const std::string self = selfExecutablePath( argv0 );
    for( const rw::codexdoctor::Check& check : ( claude ? rw::codexdoctor::claudeInspect( self )
                                                        : rw::codexdoctor::inspect( self ) ) )
    {
        ++out.checks;
        if( check.ok ) { ++out.passed; }
        out.rows += "<c n=\"" + std::string( check.name ) + "\" ok=\"" + ( check.ok ? "1" : "0" ) + "\"";
        if( !check.attrs.empty() ) { out.rows += " " + check.attrs; }
        out.rows += "/>";
    }
    return out;
}

int runDoctor( const rw::Config& cfg, const char* argv0 )
{
    using namespace rw;

    int                checks = 0;
    int                okCount = 0;
    std::string        rows;
    std::vector<char>  esc;

    const auto row = [ & ]( const char* name, bool ok, const std::string& attrs )
    {
        ++checks;
        if( ok )
        {
            ++okCount;
        }
        rows += "<c n=\"";  rows += name;  rows += "\" ok=\"";  rows += ( ok ? "1" : "0" );  rows += "\"";
        if( !attrs.empty() ) { rows += " "; rows += attrs; }
        rows += "/>";
    };

    // ---- check 1: binary-vs-PATH staleness (no --version mechanism exists — checked; compare
    // realpath'd identity via (device,inode), then mtime/size, of argv[0]'s resolved binary vs
    // `which ripwire`'s) ----
    {
        const std::string selfPath  = selfExecutablePath( argv0 );
        const std::string whichPath = doctorPopenTrim( "which ripwire 2>/dev/null" );
        struct stat        selfSt {};
        struct stat         whichSt {};
        const bool haveSelf  = !selfPath.empty()  && ::stat( selfPath.c_str(),  &selfSt )  == 0;
        const bool haveWhich = !whichPath.empty() && ::stat( whichPath.c_str(), &whichSt ) == 0;

        bool        ok    = true;
        std::string attrs = "self=\"" + std::string( escapeXml( selfPath, esc ) ) + "\"";
        attrs += " which=\"" + std::string( escapeXml( whichPath, esc ) ) + "\"";

        if( !haveWhich )
        {
            attrs += " on_path=\"0\"";   // ripwire not found on PATH at all — not itself a failure (may run via absolute path)
        }
        else if( haveSelf )
        {
            const bool sameFile = ( selfSt.st_dev == whichSt.st_dev && selfSt.st_ino == whichSt.st_ino );
            attrs += " on_path=\"1\" same_file=\"" + std::string( sameFile ? "1" : "0" ) + "\"";
            if( !sameFile )
            {
                // install.sh COPIES the binary (dev/ino always differ from the source build) rather than
                // symlinking it, so a raw same_file="0" false-positives on every install that worked fine.
                // Cheap content-equality fallback (degrade, don't crash): equal mtime AND equal size is the
                // sanctioned proxy for "copied but identical" — a genuine stale shadow almost always differs
                // in at least one. Only a real mismatch still flags ok=false.
                const bool copied = ( selfSt.st_mtime == whichSt.st_mtime && selfSt.st_size == whichSt.st_size );
                ok = copied;   // this exact failure bit the LocBench round — stale PATH binary shadows a freshly built one
                attrs += " self_mtime=\""  + std::to_string( (long long)selfSt.st_mtime )  + "\"";
                attrs += " self_size=\""   + std::to_string( (long long)selfSt.st_size )    + "\"";
                attrs += " which_mtime=\"" + std::to_string( (long long)whichSt.st_mtime ) + "\"";
                attrs += " which_size=\""  + std::to_string( (long long)whichSt.st_size )   + "\"";
                // §P11 doctor item: a raw ok="0" with four raw timestamps made the reader do the
                // subtraction themselves — name which of the two IS the stale one (older mtime) and the
                // fix, so the LocBench-round failure this check exists for reads as a VERDICT.
                attrs += doctorBinaryPathVerdictAttr( copied, selfPath, whichPath, selfSt, whichSt, esc );
            }
        }
        else
        {
            attrs += " on_path=\"1\"";   // could stat the PATH copy but not our own argv[0]-derived path — degrade, don't fail
        }
        row( "binary-path", ok, attrs );
    }

    // ---- check 2: grammar availability — probe each compiled-in grammar's tags.scm actually
    // compiles (ts_query_new), the same operation ingest()'s prewarm performs; count vs expected ----
    // gp OUTLIVES this block on purpose: check 5 reports the same grammar count and used to carry it as a
    // hardcoded "13" with a comment promising it matched this table. It did not — the table reached 17
    // while the literal stayed 13. Reading the one probe twice is what makes that promise structural.
    const DoctorGrammarProbe gp = doctorProbeGrammars();
    {
        std::string grammarAttrs = "loaded=\"" + std::to_string( gp.loaded ) + "\" expected=\"" + std::to_string( gp.expected ) + "\"";
        grammarAttrs += doctorGrammarsHint( gp.loaded, gp.expected, gp.failedLabels, esc );
        row( "grammars", gp.loaded == gp.expected, grammarAttrs );
    }

    // ---- check 3: cache-dir health — resolves, writable (create+delete a probe file), report
    // existing ripwire-* blob count + total bytes (eviction sanity: flag >50 blobs, informational) ----
    {
        const std::string dir   = cacheDirLadder();
        const std::string probe = dir + "/.ripwire-doctor-probe-" + std::to_string( ::getpid() );
        bool writable = false;
        if( std::FILE* f = std::fopen( probe.c_str(), "wb" ) )
        {
            std::fputs( "doctor", f );
            std::fclose( f );
            writable = ( ::unlink( probe.c_str() ) == 0 );
        }

        const DoctorCacheStats stats = doctorCacheStats( dir );
        std::string attrs = "dir=\"" + std::string( escapeXml( dir, esc ) ) + "\"";
        attrs += " blobs=\"" + std::to_string( stats.blobCount ) + "\"";
        if( stats.capHit )
        {
            attrs += " blobs_floor=\"1\"";   // §L10: blobs= landed on the scan cap — could be exactly that many, could be more
        }
        attrs += " bytes=\"" + std::to_string( stats.totalBytes ) + "\"";
        attrs += " many=\"" + std::string( stats.blobCount > 50 ? "1" : "0" ) + "\"";   // eviction sanity flag, informational (never fails the check)
        attrs += " truncated=\"" + std::string( stats.truncated ? "1" : "0" ) + "\"";
        attrs += doctorCacheDirHint( writable, dir, esc );
        row( "cache-dir", writable, attrs );
    }

    // ---- check 4: git reachability — `git` on PATH + the target dir's repo status; degrades
    // gracefully on non-repos (ok=1, repo="0" — doctor diagnoses, non-repo isn't sickness) ----
    {
        const std::string gitVer       = doctorPopenTrim( "git --version 2>/dev/null" );
        const bool        gitAvailable = !gitVer.empty();
        std::string        attrs        = "git=\"" + std::string( gitAvailable ? "1" : "0" ) + "\"";
        if( gitAvailable )
        {
            const std::string root   = std::string( cfg.rootPath );
            const std::string isRepo = doctorPopenTrim( "git -c core.quotepath=false -C " + shSingleQuote( root )
                                                          + " rev-parse --is-inside-work-tree 2>/dev/null" );
            const bool repo = ( isRepo == "true" );
            attrs += " repo=\"" + std::string( repo ? "1" : "0" ) + "\"";
            if( repo )
            {
                const bool history = gitRepoHasHistory( root );
                attrs += " history=\"" + std::string( history ? "1" : "0" ) + "\"";
                if( history )
                {
                    // §A10.4: 9-hex-char width, matching the at= convention (gitstamp.h) every other
                    // repo-reading verb uses — this was the tool's one remaining 40-char head=.
                    attrs += " head=\"" + std::string( escapeXml( gitHeadSha( root ).substr( 0, 9 ), esc ) ) + "\"";
                }
            }
        }
        attrs += doctorGitHint( gitAvailable );
        row( "git", gitAvailable, attrs );
    }

    // ---- check 5: tree-sitter version + language count (informational, always ok=1) ----
    {
        const std::uint32_t cppAbi = ts_language_abi_version( tree_sitter_cpp() );
        std::string attrs = "core_abi=\"" + std::to_string( TREE_SITTER_LANGUAGE_VERSION ) + "\"";
        attrs += " cpp_grammar_abi=\"" + std::to_string( cppAbi ) + "\"";
        attrs += " languages=\"" + std::to_string( gp.expected ) + "\"";   // distinct compiled-in grammar entries — DERIVED from check 2's kTable, not restated
        row( "tree-sitter", true, attrs );
    }

    // ---- check 6: tracked-binary staleness — a committed binary whose last-touching
    // commit is a STRICT ancestor of a same-directory/same-stem source's last-touching commit: someone edited
    // the source and never recommitted the binary. Git-commit-order only (never mtime — see binstale.h's
    // header for why); "dependent source" is a naming heuristic, not a build-graph fact — see the same header
    // for exactly what this can and cannot see. ok="0" (and doctor's overall exit 1) iff any pair fires; a
    // non-git root or a >kMaxTrackedFiles repo degrades to ok="1" scanned="0" rather than guess.
    {
        const binstale::BinaryStaleResult bs = binstale::computeBinaryStaleness( std::string( cfg.rootPath ) );
        std::string attrs = "tracked=\"" + std::to_string( bs.trackedCount ) + "\"";
        attrs += " binaries=\"" + std::to_string( bs.binariesFound ) + "\"";
        attrs += " non_git=\"" + std::string( bs.nonGitRoot ? "1" : "0" ) + "\"";
        attrs += " truncated=\"" + std::string( bs.truncated ? "1" : "0" ) + "\"";
        attrs += " stale=\"" + std::to_string( bs.stale.size() ) + "\"";
        // cap the inline listing (doctor is a one-screen diagnostic, not a report) — every dropped pair is
        // still counted in stale="N" above, so a capped display never under-reports the finding.
        constexpr std::size_t kShown = 8;
        for( std::size_t i = 0; i < bs.stale.size() && i < kShown; ++i )
        {
            const binstale::StaleBinary& s = bs.stale[i];
            attrs += " p" + std::to_string( i ) + "=\"" + std::string( escapeXml( s.path, esc ) ) + "\"";
            attrs += " src" + std::to_string( i ) + "=\"" + std::string( escapeXml( s.srcPath, esc ) ) + "\"";
        }
        if( bs.stale.size() > kShown )
        {
            attrs += " more=\"" + std::to_string( bs.stale.size() - kShown ) + "\"";
        }
        const bool ok = bs.nonGitRoot || bs.truncated || bs.stale.empty();
        // §P11 doctor item: name the derived verdict, not just p0=/src0='s raw pair — the fix is always the
        // same shape (rebuild + recommit), so state it once instead of leaving the reader to infer it.
        attrs += doctorTrackedBinariesHint( ok, bs.stale.size() );
        row( "tracked-binaries", ok, attrs );
    }

    const DoctorAgentRows agentRows = doctorAgentRows( cfg, argv0 );
    checks += agentRows.checks;
    okCount += agentRows.passed;
    rows += agentRows.rows;

    // r26-stamp Task A: anchor this diagnostic to the commit (+dirty state) it ran against — cheap here
    // (check 4 above already paid for a git rev-parse/status probe on this same root; two more subprocess
    // calls are noise next to that), and omitted entirely on a non-git root rather than printed as a placeholder.
    const std::string doctorAt = gitstamp::atAttr( std::string( cfg.rootPath ) );
    // M10 / lens2-crossverb L6 (capture-audit-2026-09-04): TWO shas were in play and neither was labelled.
    // `at=` above is the TREE's HEAD right now; `--version` separately printed "git <sha>" — the commit this
    // BINARY was compiled from (cmake/version_stamp.cmake bakes it) — and in any session that commits without
    // rebuilding, the ordinary state of a dev tree mid-task, the two differ. A reader could not tell which
    // sha described what. They now ride side by side under names that say so, and the value is byte-identical
    // to --version's (one constant, two surfaces — test/doctorcheck.sh arm H pins that).
    // Deliberately NOT a check: a binary older than HEAD is normal between a commit and the next build, and
    // failing there would cry wolf on every commit — this is the FACT; the verdict would be noise. The
    // genuinely wrong case (a stale PATH copy shadowing a fresh build) still belongs to `binary-path` above,
    // which decides it on inode/mtime/size and never on this sha.
    const std::string doctorBuiltFrom = std::string( " built_from=\"" ) + std::string( escapeXml( kRipwireGitStamp, esc ) ) + "\"";
    // §P8 collision: this root spelled its COUNT `ok=` while every <c> child directly beneath it spells its
    // BOOL `ok=` — two meanings on adjacent lines of one document. Renamed per the index-vs-count rule;
    // `passed=` pairs with the `checks=` denominator beside it. The count had ZERO parsers (doctorcheck.sh's
    // 8 assertions all read the CHILD bool), so the half with readers keeps its name.
    // §L10: --doctor had NO legend at all — every row's attributes were --help-only prose. checks=/passed=
    // and each <c ok=> are self-explaining; what is not is the pair the cache-dir row's own comment above
    // already knew was confusing (blobs= landing on the scan cap either means "exactly that many" or
    // "at least that many" and the bare number cannot say which), so the legend names exactly that one,
    // plus the one other zero-vs-unmeasured ambiguity on this document (tracked-binaries' truncated=)
    // rather than restating every attribute's --help sentence here.
    std::string out = "<!-- doctor: checks=/passed= are the row count/how many passed; each <c name= ok=> is one check, its OTHER "
                       "attributes are check-specific (see help). cache-dir's blobs= is capped at 4096 (kMaxCacheBlobCount); "
                       "blobs_floor=\"1\" means the cap fired and blobs= is AT LEAST that many, not exactly (absent = the true "
                       "count); truncated=\"1\" covers that AND an I/O error mid-scan, so blobs_floor= is the narrower, more "
                       "useful claim when both matter. tracked-binaries' truncated=\"1\" means the git-history scan was SKIPPED "
                       "entirely (too many tracked files), so its stale=\"0\" there means unmeasured, never a clean scan. -->"
                       "<doctor checks=\"" + std::to_string( checks ) + "\" passed=\"" + std::to_string( okCount ) + "\"" + agentRows.rootAttr + doctorAt + doctorBuiltFrom + ">";
    out += rows;
    out += "</doctor>";
    std::fputs( out.c_str(), stdout );
    std::fputc( '\n', stdout );
    return ( okCount == checks ) ? 0 : 1;
}

}   // namespace — verbs_doctor.h section of main.cpp
