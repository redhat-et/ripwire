// ingest.cpp — Phase 2 INGEST. Deterministic crawl + tree-sitter tags-query extraction.
//
// Pipeline:
//   crawl -> skip-filter -> SORT paths (byte order) -> per-file parse + ONE tags query ->
//   collect raw defs/refs -> assign Symbol ids in (file,line,name) order ->
//   attribute each Reference to its enclosing definition by byte-span containment.
//
// Single-threaded (v1). Never throws: every recoverable problem degrades + DEGRADED_PATH_ALERT.

#include "ingest.h"
#include "docparse.h"           // P1-B: non-code document ingest (notebooks/html/csv + markitdown bridge)
#include "arch.h"                // T5: relForHash — root-relative path key, reused for cache portability
#include "quality.h"             // A5: cacheDirLadder + sweepStaleCacheBlobsOnce — the cache-dir hygiene hook (saveCache)
#include "embedded_queries.h"    // configure-generated constexpr tags.scm table; no runtime source-tree dependency
#include "hashutil.h"            // sanitizer-clean modulo-2^64 FNV multiplication
#include "namesplit.h"           // H4: stripTemplateArgs for the C++ qualified-call re-split (shared with tracelocus.h)
#include "lexindex.h"            // B0.1/B0.2: shared subtoken state machine + per-def lexical statistics builder

#include "Diagnostics.h"
#include "profileScope.h"        // PROFILE_SCOPE self-profiling — gated by PROFILE_ENABLED (off unless -DRIPWIRE_PROFILE=ON)

#include <tree_sitter/api.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <chrono>       // A4-P7: wall-clock cache-write timestamp for the racy-git rule
#include <cstdio>
#include <cstdlib>      // std::getenv — RIPWIRE_CACHE_STATS drift observable
#include <cstring>
#include <sys/stat.h>   // A4-P7: stat() for the (size,mtime) warm-run shortcut
#include <unistd.h>     // getpid — unique per-process cache temp name
#include <filesystem>
#include <fstream>
#include <limits>
#include <condition_variable>
#include <mutex>
#include <numeric>
#include <string>
#include <span>
#include <string_view>
#include <atomic>
#include <regex>
#include <thread>
#include <type_traits>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

// ---- tree-sitter grammar entry points (each grammar's OBJECT lib exports one) ----
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
    const TSLanguage* tree_sitter_c_sharp( void );
    const TSLanguage* tree_sitter_c( void );
    const TSLanguage* tree_sitter_cuda( void );
}

namespace rw
{

namespace
{

// ---- limits / skip config (all in one place) ----
// The per-file byte ceiling is now a RUNTIME value (default kDefaultMaxFileBytes = 4 MB, ingest.h),
// threaded through collectSources so --max-file-size can override it. Kept here as the last-resort
// fallback for any caller that somehow crawls with a zero ceiling.
constexpr std::size_t kBinarySniffCap = 4096;       // NUL-byte sniff window

// saveCache's balanced lexical-index merge carries odd runs with memcpy. Keep the
// payload's byte-copy contract explicit while preserving the former pair ordering.
struct LexPair
{
    std::uint64_t hash;
    std::uint32_t slot;

    friend constexpr bool operator<( const LexPair& lhs, const LexPair& rhs )
    {
        return lhs.hash < rhs.hash || ( lhs.hash == rhs.hash && lhs.slot < rhs.slot );
    }
};

static_assert( std::is_trivially_copyable_v<LexPair> );

// ---- the extension -> {lang, grammar fn, query file} table (DOD, no per-file switch) ----
using LangFn = const TSLanguage* (*)( void );

struct LangEntry
{
    std::string_view ext;        // file extension incl. leading dot
    Lang             lang;
    LangFn           grammar;
    std::string_view querySub;   // key into the configure-generated embedded tags.scm table
};

// Order does not matter (linear scan); kept grouped by language for readability.
constexpr std::array<LangEntry, 32> kLangTable = {{
    { ".cpp",  Lang::Cpp,        &tree_sitter_cpp,        "cpp"        },
    { ".cc",   Lang::Cpp,        &tree_sitter_cpp,        "cpp"        },
    { ".cxx",  Lang::Cpp,        &tree_sitter_cpp,        "cpp"        },
    // `.metal` = Metal Shading Language, a C++14 dialect — so it rides the C++ grammar and the C++
    // tags.scm, no grammar or query of its own (fixes a real bug: an entire shader half was invisible,
    // `--callers=ml_styleFor` returned 0). MEASURED on a real 45-shader Metal application tree (864 KB)
    // before this entry was added, not assumed: 0.81% of bytes land inside an ERROR subtree under the C++ grammar
    // (the C grammar: 12.3% — 15x worse; real C++ in the same repo: 0.00%), and every one of the 249
    // distinct `kernel`/`vertex`/`fragment` entry points is still captured, because tree-sitter's error
    // recovery localises the MSL-only qualifier to a single token and keeps the enclosing
    // function_definition intact. A control experiment that blanked every MSL-only keyword
    // (kernel/vertex/fragment/constant/device/threadgroup) before parsing cut ERROR nodes 1068->122 but
    // produced a BYTE-IDENTICAL def-name and ref-name set — so no pre-parse scrub is carried here; it
    // would be pure risk for zero graph gain. Residual known noise: an anonymous `enum : uint { ... }`
    // recovers as a NAMED enum, minting 18 junk t="type" symbols named `uint` across those 45 files
    // (0.04% of that repo's index) — accepted, not special-cased.
    // Lang::Cpp (not a new Lang::Metal) is deliberate: MSL and the C++/ObjC++ host share ONE call
    // namespace through dual-compile headers (`#if __METAL_VERSION__`), which is the whole point of
    // indexing shaders — a separate Lang would need a Metal<->Cpp bridge in langCompatible AND would
    // silently drop out of every `lang == Lang::Cpp` C-family behaviour (scope qualification, clone
    // detection, C-family lint) for no benefit.
    { ".metal", Lang::Cpp,       &tree_sitter_cpp,        "cpp"        },   // Metal Shading Language (MSL) — see above
    // `.cu`/`.cuh` = CUDA C++, on the VENDORED tree-sitter-cuda grammar — NOT the Metal-style ride on
    // the C++ grammar, and that difference is MEASURED, not assumed (2026-08-04 probe, the fixture now
    // at test/cudafix/): under tree_sitter_cpp every definition survived error recovery (__global__/
    // __device__/__launch_bounds__/template kernels — all 12 defs extracted) and device-side call edges
    // resolved, but every `kernel<<<grid, block>>>( args )` LAUNCH site produced no call reference at
    // all — `--callers=rk_reduceSum` returned count=0 — and a `__constant__` module table failed to
    // extract. Losing every host→kernel edge is the exact failure the Metal entry exists to prevent
    // (`--callers=ml_styleFor` = 0), so CUDA earns the real grammar Metal measurably did not need.
    // STILL-OPEN LIMIT (disclosed in test/cudacheck.sh §7b): the grammar now PARSES `__constant__
    // float T[ 64 ];` cleanly, but the shared cpp tags.scm module-constant pattern keys on
    // const/constexpr, so the table still yields no symbol (plain constexpr in .cu/.cuh does).
    // tree-sitter-cuda is a GENERATED superset of tree-sitter-cpp (grammar.js requires cpp's): its
    // `kernel_call_expression` is aliased to `call_expression` with a `function:` field, so the C++
    // tags.scm ("cpp" below) compiles against it unchanged and launches extract as ordinary calls.
    // Lang::Cpp (not a new Lang::Cuda) for the same deliberate reason as Metal: host and device share
    // ONE call namespace through dual-compile headers (`#ifdef __CUDACC__`), and a separate Lang would
    // need a bridge in langCompatible while dropping out of every C-family behaviour for no benefit.
    { ".cu",   Lang::Cpp,        &tree_sitter_cuda,       "cpp"        },   // CUDA C++ — see above
    { ".cuh",  Lang::Cpp,        &tree_sitter_cuda,       "cpp"        },   // CUDA header (dual-compile lives here)
    // `.h` stays C++-owned (deliberate, L3): a C header parses acceptably under the C++ grammar and
    // `.h` ownership between C/C++/ObjC is inherently ambiguous without a project-config signal this
    // tool doesn't have (an .m/.mm sibling reroutes via looksObjC() below; there is no analogous C
    // content-sniff — `#include <stdio.h>` alone isn't a reliable C-vs-C++ discriminant). graph.h's
    // langCompatible bridges Cpp<->C (like the existing Cpp<->ObjC bridge) so a `.c` DEFINITION still
    // resolves against a call/declaration living in its (C++-parsed) `.h`.
    { ".h",    Lang::Cpp,        &tree_sitter_cpp,        "cpp"        },
    { ".hpp",  Lang::Cpp,        &tree_sitter_cpp,        "cpp"        },
    { ".hh",   Lang::Cpp,        &tree_sitter_cpp,        "cpp"        },
    { ".c",    Lang::C,          &tree_sitter_c,          "c"          },   // plain C (L3) — was entirely invisible before this table gained its own row
    { ".py",   Lang::Python,     &tree_sitter_python,     "python"     },
    { ".go",   Lang::Go,         &tree_sitter_go,         "go"         },
    { ".rs",   Lang::Rust,       &tree_sitter_rust,       "rust"       },
    { ".ts",   Lang::TypeScript, &tree_sitter_typescript, "typescript" },
    { ".tsx",  Lang::TypeScript, &tree_sitter_tsx,        "typescript" },
    { ".mts",  Lang::TypeScript, &tree_sitter_typescript, "typescript" },
    { ".cts",  Lang::TypeScript, &tree_sitter_typescript, "typescript" },
    { ".swift", Lang::Swift,     &tree_sitter_swift,      "swift"      },
    { ".m",    Lang::ObjC,       &tree_sitter_objc,       "objc"       },   // Objective-C
    { ".mm",   Lang::ObjC,       &tree_sitter_objc,       "objc"       },   // Objective-C++ (ObjC layer + C-style; C++ partial)
    { ".js",   Lang::JavaScript, &tree_sitter_javascript, "javascript" },   // JavaScript — parent grammar of TypeScript
    { ".jsx",  Lang::JavaScript, &tree_sitter_javascript, "javascript" },   // JSX (the JS grammar parses jsx natively)
    { ".mjs",  Lang::JavaScript, &tree_sitter_javascript, "javascript" },   // ES module
    { ".cjs",  Lang::JavaScript, &tree_sitter_javascript, "javascript" },   // CommonJS module
    { ".sh",   Lang::Bash,       &tree_sitter_bash,       "bash"       },   // shell script
    { ".bash", Lang::Bash,       &tree_sitter_bash,       "bash"       },
    { ".zsh",  Lang::Bash,       &tree_sitter_bash,       "bash"       },   // zsh — parsed with the bash grammar (superset-ish; partial)
    { ".java", Lang::Java,       &tree_sitter_java,       "java"       },   // Java — classes/interfaces/enums/methods/ctors + calls
    { ".rb",   Lang::Ruby,       &tree_sitter_ruby,       "ruby"       },   // Ruby — class/module/def + method calls + require
    { ".json", Lang::Json,       &tree_sitter_json,       "json"       },   // JSON — top-level + 2nd-level object keys as t="sec"; DATA, no call edges
    { ".cs",   Lang::CSharp,     &tree_sitter_c_sharp,    "csharp"     },   // C# — classes/structs/interfaces/records/enums/methods/props + calls
    { ".md",   Lang::Markdown,   nullptr,                 ""           },   // no tree-sitter grammar — ATX headings via extractMarkdown()
}};

const LangEntry* lookupLang( std::string_view ext ) noexcept
{
    for( const LangEntry& e : kLangTable )
    {
        if( e.ext == ext )
        {
            return &e;
        }
    }
    return nullptr;
}

std::string lowerExtensionOf( std::string_view path )
{
    const std::size_t slash = path.find_last_of( '/' );
    const std::size_t base  = ( slash == std::string_view::npos ) ? 0 : slash + 1;
    const std::size_t dot   = path.find_last_of( '.' );
    if( dot == std::string_view::npos || dot <= base )
    {
        return {};
    }

    std::string ext;
    ext.reserve( path.size() - dot );
    for( std::size_t i = dot; i < path.size(); ++i )
    {
        ext.push_back( static_cast<char>( std::tolower( static_cast<unsigned char>( path[i] ) ) ) );
    }
    return ext;
}

// ---- capture-name prefix -> role. @definition.* -> DEF, @reference.* -> REF. ----
enum class CapRole : std::uint8_t { Ignore, NameOnly, Def, Ref };

// Map the part AFTER "definition."/"reference." to a SymKind. Falls back to Other.
SymKind defKind( std::string_view tail ) noexcept
{
    if( tail == "function" )
    {
        return SymKind::Function;
    }
    if( tail == "method" )
    {
        return SymKind::Method;
    }
    if( tail == "class" )
    {
        return SymKind::Class;
    }
    if( tail == "struct" )
    {
        return SymKind::Struct;
    }
    if( tail == "interface" )
    {
        return SymKind::Interface;
    }
    if( tail == "var" )
    {
        return SymKind::Var;
    }
    if( tail == "constant" )
    {
        return SymKind::Var;
    }
    if( tail == "cjsexport" )      // JS `module.exports.NAME = fn` / `exports.NAME = fn` — gated (isCjsExportTarget)
    {
        return SymKind::Function;
    }
    if( tail == "protomethod" )    // JS `Foo.prototype.NAME = fn` — gated (isPrototypeMemberTarget)
    {
        return SymKind::Method;
    }
    if( tail == "module" )
    {
        return SymKind::Other;
    }
    if( tail == "macro" )
    {
        return SymKind::Function;
    }
    if( tail == "type" )
    {
        return SymKind::Struct; // typedef/alias/enum bucket
    }
    if( tail == "section" )
    {
        return SymKind::Section; // JSON object keys (t="sec"), same kind as markdown headings
    }
    return SymKind::Other;
}

CapRole roleOf( std::string_view cap, SymKind& kindOut ) noexcept
{
    constexpr std::string_view kDef = "definition.";
    constexpr std::string_view kRef = "reference.";

    if( cap == "name" )
    {
        return CapRole::NameOnly;
    }

    if( cap.size() > kDef.size() && cap.substr( 0, kDef.size() ) == kDef )
    {
        kindOut = defKind( cap.substr( kDef.size() ) );
        return CapRole::Def;
    }
    if( cap.size() > kRef.size() && cap.substr( 0, kRef.size() ) == kRef )
    {
        return CapRole::Ref;
    }

    return CapRole::Ignore;   // @doc, @local.scope, etc.
}

// ---- final identifier segment (ns::f / pkg.F / mod::f -> last segment) ----
std::string finalSegment( std::string_view raw )   // allocates a std::string → not noexcept
{
    // A C++ OPERATOR name (`operator<`, `operator<<`, `operator<=>`, `operator bool`) is the one place a
    // name legitimately carries `<`/`::`-looking punctuation that is NOT a scope/type-arg separator — the
    // `<`-strip and "::"/"." splits below would mangle it to a bare `operator`. Detect the `operator`
    // keyword segment (bare `operator...` or the last `Scope::operator...`) and return it whole. Guarded on
    // a following non-identifier char so a normal identifier that merely starts with "operator" (e.g.
    // `operatorId`) still falls through to the generic path unchanged.
    if( const std::size_t op = raw.rfind( "operator" ); op != std::string_view::npos )
    {
        const bool atSegStart = ( op == 0 ) || ( raw[ op - 1 ] == ':' ) || ( raw[ op - 1 ] == '.' );
        const std::size_t after = op + 8;   // one-past `operator`
        const bool isOpToken = after >= raw.size()
                            || !( std::isalnum( static_cast<unsigned char>( raw[ after ] ) ) || raw[ after ] == '_' );
        if( atSegStart && isOpToken )
        {
            return std::string( raw.substr( op ) );   // `operator<<`, `operator bool`, etc. — verbatim
        }
    }

    // FIX #1 (generic base/impl): drop a type-argument list before ANYTHING else. A base/impl name
    // handed back as `generic_type` carries `<...>` (Java `Base<String>`, Rust `Wrapper<T>`) whose
    // bare form (`Base`/`Wrapper`) is what byName keys on. The strip MUST precede the "::"/"." split,
    // or a `::` INSIDE the args (`Foo<A::B>`) would be mistaken for the segment separator. A name never
    // legitimately contains a bare '<' (only a type-argument list opens one), so truncating at the FIRST
    // '<' is safe; the C++/TS bare-identifier path has no '<' → no-op (byte-identical).
    if( const std::size_t lt = raw.find( '<' ); lt != std::string_view::npos )
    {
        raw = raw.substr( 0, lt );
    }

    // already a bare identifier in nearly all cases; defensive split on '.' and "::".
    std::size_t pos = raw.rfind( "::" );
    if( pos != std::string_view::npos )
    {
        raw = raw.substr( pos + 2 );
    }
    pos = raw.rfind( '.' );
    if( pos != std::string_view::npos )
    {
        raw = raw.substr( pos + 1 );
    }

    // trim trailing whitespace a `Base <String>` / `Wrapper <T>` spacing left behind (grammars usually
    // hand back tight text, but a space before the '<' would otherwise leave `Base ` after the strip).
    while( !raw.empty() && ( raw.back() == ' ' || raw.back() == '\t' ) )
    {
        raw.remove_suffix( 1 );
    }
    return std::string( raw );
}

// ---- skip rules ----
bool isDenylistedName( std::string_view name ) noexcept
{
    auto endsWith = [ name ]( std::string_view suf ) noexcept
    {
        return name.size() >= suf.size() && name.substr( name.size() - suf.size() ) == suf;
    };

    if( name == "package-lock.json" )
    {
        return true; // npm lockfile — huge, machine-generated, zero config value
    }
    if( name == "npm-shrinkwrap.json" )
    {
        return true; // npm lockfile variant (same shape/size as package-lock)
    }
    if( endsWith( ".min.js" ) )
    {
        return true;
    }
    if( endsWith( "_pb2.py" ) )
    {
        return true;
    }
    if( endsWith( ".pb.go" ) )
    {
        return true;
    }
    return false;
}

// True if the first kBinarySniffCap bytes contain a NUL (binary heuristic).
bool looksBinary( std::string_view bytes ) noexcept
{
    const std::size_t n = bytes.size() < kBinarySniffCap ? bytes.size() : kBinarySniffCap;
    return std::memchr( bytes.data(), '\0', n ) != nullptr;
}

// True when raw bracket/brace nesting exceeds kMaxJsonNestDepth — degenerate or hostile DATA, never config
// (found live by bench/multiswe: tree-sitter-json's error recovery is superlinear on unclosed
// nesting; a 100 KB file of "[[[[…" from nlohmann/json's own parser-torture suite measured 43 s). One O(n)
// byte scan, quote-aware (a bracket inside a JSON string does not open a level), fully deterministic —
// never a wall-clock parse timeout, which would break the byte-identical-output contract.
bool jsonNestsTooDeep( std::string_view bytes ) noexcept
{
    std::uint32_t depth = 0;
    bool          inString = false, escaped = false;
    for( char c : bytes )
    {
        if( inString )
        {
            if( escaped )
            {
                escaped = false;
            }
            else if( c == '\\' )
            {
                escaped = true;
            }
            else if( c == '"' )
            {
                inString = false;
            }
            continue;
        }
        if( c == '"' )                       { inString = true; }
        else if( c == '[' || c == '{' )
        {
            if( ++depth > kMaxJsonNestDepth )
            {
                return true;
            }
        }
        else if( c == ']' || c == '}' )
        {
            if( depth > 0 )
            {
                --depth;
            }
        }
    }
    return false;
}

// A .h defaults to C++, but an Objective-C header (@interface/@protocol) must use the objc grammar or its
// class/protocol structure is lost to the C++ parser. Cheap content peek (first 8 KB) for the distinctive
// '@' declarations. @ is not valid C++ outside a string/comment, so false positives are negligible.
bool looksObjC( std::string_view bytes ) noexcept
{
    const std::string_view head = bytes.substr( 0, bytes.size() < 8192 ? bytes.size() : 8192 );
    return head.find( "@interface" ) != std::string_view::npos
        || head.find( "@protocol" )  != std::string_view::npos
        || head.find( "@implementation" ) != std::string_view::npos;
}

// ---- deterministic crawl: collect candidate source paths, then SORT ----
// excludeLabel (multi-root A12): non-empty ⇒ --exclude substrings match `<label>/<root-relative>` instead
// of the crawled spelling (one excludes namespace across roots). Empty ⇒ byte-identical to today.
// §P0.5d: the crawl also reports how many otherwise-indexable files it dropped for exceeding A SIZE CEILING,
// so the map header can say `skipped_oversize=` instead of presenting a truncated corpus as the whole tree.
// §B13.1: "a size ceiling" is TWO ceilings — maxFileBytes (--max-file-size) and the fixed kMaxJsonConfigBytes
// the .json lane applies on top of it — and the count covers both, because a file the reader cannot see is
// equally invisible whichever ceiling dropped it. They are mutually exclusive per file (see the drop sites).
struct CrawlResult
{
    std::vector<std::string> paths;
    std::uint32_t            oversizeSkippedCount = 0;
};

CrawlResult collectSources( const char* rootDir, const std::vector<std::string>& excludeSubstr,
                            std::size_t maxFileBytes, std::string_view excludeLabel = {} )
{
    std::vector<std::string> out;
    std::uint32_t            oversizeSkippedCount = 0;

    std::error_code ec;
    fs::path root = fs::path( rootDir );

    auto opts = fs::directory_options::skip_permission_denied;
    fs::recursive_directory_iterator it( root, opts, ec );
    if( ec )
    {
        DEGRADED_PATH_ALERT( "ingest: cannot open root directory — empty result" );
        return { std::move( out ), oversizeSkippedCount };
    }

    const fs::recursive_directory_iterator end;
    for( ; it != end; it.increment( ec ) )
    {
        if( ec )
        {
            ec.clear();
            continue;
        }

        const fs::path& p = it->path();
        std::string     full;
        const auto fullPath = [ & ]() -> const std::string&
        {
            if( full.empty() )
            {
                full = p.string();
            }
            return full;
        };

        // user --exclude substrings prune dirs and drop files (vendored/generated trees). Multi-root (A12):
        // match against the LABELED spelling so one excludes list applies uniformly across roots.
        bool excluded = false;
        if( !excludeSubstr.empty() )
        {
            std::string labeledBuf;
            std::string_view matchPath = fullPath();
            if( !excludeLabel.empty() )
            {
                labeledBuf.assign( excludeLabel );
                const std::string_view rel = relForHash( fullPath(), rootDir );
                if( !rel.empty() ) { labeledBuf.push_back( '/' );  labeledBuf.append( rel ); }
                matchPath = labeledBuf;
            }
            for( const std::string& ex : excludeSubstr )
            {
                if( !ex.empty() && matchPath.find( ex ) != std::string_view::npos ) { excluded = true; break; }
            }
        }

        // prune noise/vendor/build subtrees entirely (a .gitignore-lite default denylist)
        if( it->is_directory( ec ) )
        {
            // The denylist itself now lives in ingest.h (kCrawlSkipDirs / isSkippedCrawlDir) so darkflags.h's
            // CMake walk prunes exactly the same subtrees — see the note there.
            bool skip = excluded;
            if( !skip )
            {
                skip = isSkippedCrawlDir( p.filename().string() );
            }
            // skip any dir that contains a CMakeCache.txt — it's a build output tree
            if( !skip )
            {
                const fs::path cache_sentinel = p / "CMakeCache.txt";
                if( fs::exists( cache_sentinel, ec ) )
                {
                    skip = true;
                }
                ec.clear();
            }
            if( skip )
            {
                it.disable_recursion_pending();
            }
            continue;
        }

        if( excluded )
        {
            continue;
        }
        if( !it->is_regular_file( ec ) )
        {
            continue;
        }

        const std::string name = p.filename().string();
        if( isDenylistedName( name ) )
        {
            continue;
        }

        // extension must be a known source language OR a doc format (P1-B: notebooks/html/csv are collected
        // like code so they get a fileId; they're skipped by the tree-sitter parse loop and handled in the
        // doc post-pass instead). Use the filename here so rejected regular files do not pay to stringify the
        // full path; materialize the full path only after the extension survives.
        std::string ext = lowerExtensionOf( name );
        if( lookupLang( ext ) == nullptr && !docparse::isDocExtension( ext ) )
        {
            continue;
        }

        const std::uintmax_t sz = it->file_size( ec );
        if( ec || sz > maxFileBytes )
        {
            if( !ec && sz > maxFileBytes )
            {
                ++oversizeSkippedCount; // §P0.5d: a size drop is reportable, not invisible
            }
            ec.clear();
            continue;
        }

        // JSON-lane ceiling (see kMaxJsonConfigBytes): big .json is data, not config — skip it before it
        // mints a symbol-table explosion. Applies only to the .json extension; --max-file-size does not
        // override it upward (config files this large do not exist; data files this large are the hazard).
        //
        // §B13.1: COUNTED, exactly like the generic size drop 8 lines above. Both are "an otherwise-indexable
        // file the crawl dropped for exceeding a size ceiling", which is what skipped_oversize means, and the
        // two are mutually exclusive BY CONSTRUCTION — the generic ceiling is tested first, so a .json over
        // both ceilings is counted once, there — which is why one counter serves both and no file is counted
        // twice. Uncounted, this drop broke the header's own accounting invariant
        // (files= + skipped_oversize= = the candidate population the crawl considered): on this repo the
        // DEFAULT map reported files=866 with the attribute absent (implying 866) while --max-file-size=256K
        // reported files=861 + skipped_oversize=8 = 869. Three files — the >256 KB .json under
        // bench/locbench/ — vanished with no counter, no stderr and no legend clause, which is the exact
        // class skipped_oversize exists to kill. The ceiling itself is deliberately NOT lifted here: it is a
        // content-class guard (data vs config) that merely uses size as its proxy, so letting a SIZE flag
        // override it would trade a disclosure defect for a corpus one.
        if( sz > kMaxJsonConfigBytes && ext == ".json" )
        {
            ++oversizeSkippedCount;
            continue;
        }

        // binary sniff: the parse pool's looksBinary() already guards against binary content;
        // removing the crawl-time sniff here avoids 3 syscalls × N files on every warm run
        // (Win 3 from PERF.md). Any binary file that slips through produces zero defs/refs and
        // is invisible in the ranked map; its phantom fileId has no downstream effect.
        out.push_back( fullPath() );
    }

    // LOAD-BEARING: lexicographic (byte-order) sort fixes node-id assignment run-to-run.
    std::sort( out.begin(), out.end() );
    return { std::move( out ), oversizeSkippedCount };
}

// ---- read a file's bytes (returns false on open failure) ----
bool readFile( const std::string& path, std::string& out )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/readFile: fopen+read whole file" );

    std::FILE* fp = std::fopen( path.c_str(), "rb" );
    if( fp == nullptr )
    {
        return false;
    }

    if( std::fseek( fp, 0, SEEK_END ) != 0 )
    {
        std::fclose( fp );
        return false;
    }
    const long len = std::ftell( fp );
    if( len < 0 )
    {
        std::fclose( fp );
        return false;
    }
    if( std::fseek( fp, 0, SEEK_SET ) != 0 )
    {
        std::fclose( fp );
        return false;
    }

    out.resize( static_cast<std::size_t>( len ) );
    const std::size_t want = out.size();
    const std::size_t got  = want == 0 ? 0 : std::fread( out.data(), 1, want, fp );
    const bool ok = ( got == want ) && ( std::fclose( fp ) == 0 );
    if( !ok )
    {
        out.clear();
    }
    return ok;
}

bool readFilePrefix( const std::string& path, std::string& out, std::size_t maxBytes )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/readFilePrefix: fopen+read prefix" );

    std::FILE* fp = std::fopen( path.c_str(), "rb" );
    if( fp == nullptr )
    {
        return false;
    }

    out.resize( maxBytes );
    const std::size_t got = maxBytes == 0 ? 0 : std::fread( out.data(), 1, maxBytes, fp );
    const bool readOk = got > 0 || std::feof( fp ) != 0;
    const bool closeOk = std::fclose( fp ) == 0;
    if( !readOk || !closeOk )
    {
        out.clear();
        return false;
    }
    out.resize( got );
    return true;
}

// ---- A4-P7 stat-gate helpers: (size,mtime) probe + cache-write wall clock ----
// The warm-run shortcut trusts a cached parse WITHOUT reading/hashing the file when its size AND
// mtime still match the cache, and the cached mtime is not "racy" (see saveCache/kCacheVersion=6).
//
// GRANULARITY: mtimeNs carries whatever the platform/filesystem exposes — APFS and ext4 give true
// nanoseconds, HFS+/some network mounts only whole seconds (the sub-ns field reads 0). The racy-git
// rule makes coarse granularity SAFE rather than merely lossy: any file whose mtime lands in the same
// granule as the cache write is force-re-hashed, so a same-granule post-hash edit can never be trusted.
struct StatInfo { long long mtimeNs; long long sizeBytes; };   // (-1,-1) if the path cannot be stat'd
inline StatInfo statSizeMtime( const std::string& path ) noexcept
{
    struct stat st;
    if( ::stat( path.c_str(), &st ) != 0 )
    {
        return { -1, -1 };
    }
#if defined( __APPLE__ )
    const long long m = (long long)st.st_mtimespec.tv_sec * 1000000000LL + st.st_mtimespec.tv_nsec;
#elif defined( __linux__ )
    const long long m = (long long)st.st_mtim.tv_sec * 1000000000LL + st.st_mtim.tv_nsec;
#else
    const long long m = (long long)st.st_mtime * 1000000000LL;   // whole-second fallback
#endif
    return { m, (long long)st.st_size };
}

// L1 (Linux runtime probe) — what KIND of thing is at `path`? The cache seams need all three answers, so
// this is a tri-state and not a bool: absent is a silent miss, regular is the only usable shape, and
// anything else (directory, fifo, socket, device) is an unexpected shape worth disclosing once.
//
// The platform split it exists for: `fopen( "<a directory>", "rb" )` FAILS on macOS and SUCCEEDS on
// Linux/glibc. readFile above then fseek/ftell's that directory handle, gets a nonsense length, and
// `out.resize()`s to it — the Ubuntu probe measured `--cache=<existing directory>` dying with
// std::bad_alloc → SIGABRT (exit 134) where the same argument on macOS took the quiet cold-parse path.
// A cache blob is a REGULAR file by construction (saveCache renames one into place), so every other shape
// is the same self-healing "corrupt cache" state, on every platform.
//
// Checked BEFORE the open, never after: a FIFO at the path would BLOCK inside fopen( "rb" ) until a writer
// appeared, which no post-open fstat can undo. Race-wise it is advisory only — a path that changes shape
// between this stat and the open still lands in a degrade path, because a degrade path is all a cache miss
// has. ::stat, not ::lstat: a symlink TO a regular file is a legitimate cache blob.
enum class PathShape : std::uint8_t { Absent, RegularFile, Other };

inline PathShape shapeOfPath( const std::string& path ) noexcept
{
    struct stat st;
    const bool  isStatable = ::stat( path.c_str(), &st ) == 0;
    return !isStatable ? PathShape::Absent : ( S_ISREG( st.st_mode ) ? PathShape::RegularFile : PathShape::Other );
}

// The READ seam's use of it, named so loadCache reads as one decision instead of three lines of shape
// analysis. Absent stays silent (the ordinary cold-start miss); an odd shape is disclosed here, once, from
// the one site that knows the read is what got refused.
inline bool isReadableCacheBlob( const std::string& path ) noexcept
{
    const PathShape shape = shapeOfPath( path );
    if( shape == PathShape::Other )
    {
        DEGRADED_PATH_ALERT( "ingest: cache path is not a regular file (directory/device/fifo) — cache treated as corrupt (full reparse)" );
    }
    return shape == PathShape::RegularFile;
}

// Wall-clock now in ns since the Unix epoch — the SAME clock domain as st_mtime, so the racy-rule
// comparison (cached file mtime >= cache-blob write time ⇒ re-hash) is meaningful across the two.
inline long long wallClockNs() noexcept
{
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::system_clock::now().time_since_epoch() ).count();
}

// ---- the tags-query string per language, embedded in the executable at configure time ----
std::string_view queryFor( std::string_view querySub ) noexcept
{
    return embedded_queries::queryFor( querySub );
}

// ---- the COMPILED tags query per grammar, built ONCE and shared read-only across worker threads ----
// ts_query_new (query *compilation*) is far costlier than parsing and depends only on (grammar, tags.scm) —
// compiling it per file wasted ~80% of cold-parse CPU (measured). Compile once per grammar; workers fetch
// the shared immutable TSQuery* and create only a cheap per-thread TSQueryCursor. INVARIANT: the cache is
// written ONLY by ingest()'s prewarm (which compiles the present grammars in parallel into locals, then
// installs here single-threaded after the join), so the parse-pool workers only READ it — lock-free.
//
// OWNERSHIP (N2). The cache is the SOLE owner of every TSQuery it holds; every other holder — the parse
// pool, captureTagsFacts — only borrows the raw pointer for the length of a call, which is why ownership
// lives in the CONTAINER and not in the entries (a per-entry move-only guard would have to survive the
// map's rehash-and-move for no benefit). Same shape as ParserGuard/TreeGuard below: a struct whose
// destructor frees the tree-sitter object it holds.
//
// Before this struct existed there was no owner at all. The install loop in ingest() deletes a DISPLACED
// query on an in-process re-ingest (A652/A4-F16), which bounds growth in a long-lived MCP server, but the
// queries finally resident in the map were never freed: the map's own destructor drops the pointers at
// exit and the blocks go unreachable. Real LeakSanitizer — Linux only, absent from Apple clang, and
// therefore invisible on this repo's whole history of macOS runs — reports exactly that:
//   Direct leak of 672 B in 3 objects:  ts_malloc_default -> ts_query_new (query.c:2995)
//                                       -> compileQueryStandalone (ingest.cpp) -> ingest thread lambda
// fired by the cachefuzzcheck arms whose cache is unusable (/dev/null, a directory at the cache path), i.e.
// exactly the arms that take the L1 guard's full-reparse route and therefore compile every grammar cold.
// A suppression would have been the wrong tool: lsan_suppressions.txt exists for tree-sitter's INTERNED,
// never-freed data, and these are ordinary per-run allocations with a well-defined lifetime.
struct CompiledQueryCache
{
    HashMap<const TSLanguage*, TSQuery*> byGrammar;   // grammar → compiled query (owned)

    CompiledQueryCache()                                       = default;
    CompiledQueryCache( const CompiledQueryCache& )            = delete;
    CompiledQueryCache& operator=( const CompiledQueryCache& ) = delete;

    // Only ever runs at process teardown, single-threaded, after every parse pool has joined. Each entry is
    // a distinct query (the compile set is deduplicated BY GRAMMAR, so no two keys can alias one TSQuery)
    // and a displaced entry is deleted at the moment it is overwritten, never left in the map — so nothing
    // here can be a second delete of the same pointer.
    ~CompiledQueryCache()
    {
        for( const auto& entry : byGrammar )
        {
            if( entry.second != nullptr )
            {
                ts_query_delete( entry.second );
            }
        }
    }
};

HashMap<const TSLanguage*, TSQuery*>& compiledQueryCache()
{
    static CompiledQueryCache cache;   // grammar → compiled query; owns every TSQuery it hands out
    return cache.byGrammar;
}

struct QueryReadyGate
{
    std::atomic<bool>*       isReady = nullptr;
    std::mutex*              mutex   = nullptr;
    std::condition_variable* cv      = nullptr;
};

void waitForQueryPrewarm( const QueryReadyGate* gate )
{
    if( gate == nullptr || gate->isReady == nullptr || gate->isReady->load( std::memory_order_acquire ) )
    {
        return;
    }

    std::unique_lock<std::mutex> lock( *gate->mutex );
    gate->cv->wait( lock, [ gate ]() { return gate->isReady->load( std::memory_order_acquire ); } );
}

// Compile one grammar's tags query WITHOUT touching the shared cache. Pure (ts_query_new is a per-query
// allocation reading immutable inputs), so it is safe to run concurrently for DISTINCT grammars. The
// configure-generated query table is immutable read-only data. The caller installs the compiled result.
TSQuery* compileQueryStandalone( const LangEntry& le )
{
    if( le.grammar == nullptr )
    {
        return nullptr;                                  // markdown — no grammar/query
    }
    const std::string_view scm = queryFor( le.querySub );
    if( scm.empty() )
    {
        return nullptr;
    }
    std::uint32_t errOff  = 0;
    TSQueryError  errType = TSQueryErrorNone;
    TSQuery*      q       = ts_query_new( le.grammar(), scm.data(), static_cast<std::uint32_t>( scm.size() ), &errOff, &errType );
    if( q == nullptr )
    {
        std::fprintf( stderr, "[ripwire] tags.scm compile error for %s at byte %u (err %d) — skipping language\n",
                      std::string( le.querySub ).c_str(), errOff, (int)errType );
    }
    return q;
}

TSQuery* compiledQueryFor( const LangEntry& le )
{
    if( le.grammar == nullptr )
    {
        return nullptr;                                  // markdown — no grammar/query
    }
    const TSLanguage* lang  = le.grammar();
    auto&             cache = compiledQueryCache();
    if( const auto it = cache.find( lang ); it != cache.end() )
    {
        return it->second;
    }

    // not prewarmed — a transient readFile failure can make the prewarm miss-detection skip a grammar the
    // pool later needs. Compiling here would WRITE the shared cache from a worker thread (data race on the
    // non-thread-safe map). Degrade instead: skip the file (caller treats nullptr as "skip"); the normal
    // prewarm path repopulates on the next run.
    DEGRADED_PATH_ALERT( "ingest: tags query not prewarmed for a grammar — file skipped" );
    return nullptr;
}

// ---- a raw definition pulled from one query match (pre-id-assignment) ----
struct RawDef
{
    std::uint32_t fileId    = 0;
    std::uint32_t line      = 0;   // 1-based
    std::uint32_t startByte = 0;   // span start of the @definition node
    std::uint32_t endByte   = 0;   // span end   of the @definition node
    std::uint32_t nameByte  = 0;   // start byte of the @name identifier (dedup identity)
    std::uint32_t bodyByte  = 0;   // start of the def's "body" field = signature end (0 ⇒ none → endByte)
    std::uint32_t cx        = 0;   // cyclomatic complexity (1 + decision points); functions/methods only
    std::uint32_t ccx       = 0;   // cognitive complexity (nesting-weighted); functions/methods only
    std::uint32_t loc       = 0;   // Q4: physical line span of the def (end line − start line + 1)
    std::uint32_t locals    = 0;   // Phase 1 (local-variable-indexing, PLAN.md 2026-08-06 evening): local-decl
                                   // count from cc_walk; C/C++ only (see model.h localsCountedLang), 0 elsewhere
    std::uint16_t humps     = 0;   // nesting profile: regions reaching quality::kNestBar (see model.h Symbol::humps)
    std::uint16_t deepLoc   = 0;   // nesting profile: lines inside them, a FLOOR (see model.h Symbol::deepLoc)
    std::uint16_t params    = 0;   // Q4: parameter count (from the def's parameter-list child); fns/methods
    std::uint8_t  maxNest   = 0;   // Q4: max control-structure nesting depth inside the def (from cc_walk)
    std::uint8_t  arityExact = 0;  // B2.2: 1 ⇒ params is a fixed call-comparable arity (no variadic/default, not implicit-self)
    SymKind       kind      = SymKind::Other;
    Lang          lang      = Lang::Unknown;
    std::string   name;
    std::string   scope;               // enclosing class/namespace name (C++), for canonical scope::name
    RawDefLex     lex;                 // B0.2: doc+body weighted subtoken stats (rich ingests only; rides the
                                       //   cache record so a warm --for never re-reads/re-tokenizes the file)
};

struct RawRef
{
    std::uint32_t fileId    = 0;
    std::uint32_t startByte = 0;   // span start of the @reference node (for enclosing lookup)
    std::uint32_t line      = 0;   // 1-based line of the use site (ABS-3: --uses p="file:line")
    Lang          lang      = Lang::Unknown;
    bool          isInherit = false;   // true ⇒ base-class/implements edge (derived → base), not a call
    bool          isDocLink = false;   // true ⇒ doc→code mention (markdown `backtick` identifier), not a call
    bool          isCompose = false;   // true ⇒ HAS-A member-variable type edge (S5-E); stays OUT of call graph
    RefRole       role      = RefRole::Call;    // ABS-3 use-site role (call/read/write/import/extends); see RefRole
    RecvKind      recv      = RecvKind::None;   // call-site receiver shape (P2-D narrowing)
    std::uint16_t argCount     = 0;             // B2.2: call-site positional arg count when countable; 0 otherwise
    bool          argCountKnown = false;        // B2.2: true ⇒ argCount is reliable (no spread/splat/apply)
    std::string   name;
    std::string   qualifier;           // explicit scope at a call site (`A` in `A::b()`); C++; "" if bare/method
    std::string   recvVar;             // receiver variable when recv==NamedVar (`x` in `x->m()`); Rule 2 fuel
    std::string   fieldName;           // member variable name when isCompose (e.g. "m_pool"); "" otherwise
    std::string   composeRel;          // "creates" (value/inline) or "uses" (reference/pointer) when isCompose; "" otherwise
};

// P2-D Rule 2 raw local-variable type binding (pre-attribution). startByte sits inside the enclosing
// function body so the enclosing-def attribution (the same byte-span scan as RawRef) assigns the binding's
// scope. `var : typeName` — e.g. `Foo x;` → { "x", "Foo" }. typeName is the written type's final segment.
struct RawBind
{
    std::uint32_t fileId    = 0;
    std::uint32_t startByte = 0;   // position inside the enclosing function (for enclosing-def attribution)
    Lang          lang      = Lang::Unknown;
    std::string   var;             // the declared variable identifier (`x`)
    std::string   typeName;        // the written type's final segment (`Foo`)
};

// B6.3 raw client-side HTTP-route USE (pre-attribution). startByte sits at the call-expression's own
// start so the enclosing-def byte-span scan (same DefSweep as RawRef/RawBind) assigns fromSymbol. The
// server-side RouteDef needs no such raw/final split (its handler is resolved by NAME, see graph.h), so
// it rides model.h's own RouteDef struct straight through the cache — same posture as BindingAlias.
struct RawRouteUse
{
    std::uint32_t fileId    = 0;
    std::uint32_t startByte = 0;   // call-expression start (for enclosing-def attribution)
    std::uint32_t line      = 0;   // 1-based
    HttpMethod    method    = HttpMethod::Unknown;
    std::string   path;
};

// ---- incremental cache (--cache): per-file content hash + raw facts so a re-run re-parses ONLY
//      changed files. A parserVer bump invalidates the whole cache on any extraction change.
//      Node ids are NOT cached — they're reassigned each run by the existing deterministic sort,
//      so the cache stores fileId-free facts and re-stamps fileId on load (R3 id-positionality). --
constexpr std::uint32_t kCacheMagic   = 0x4b505443;   // "CTPK"
// 2: whole-blob FNV checksum trailer (corrupt-cache detection).
// 3 (T5): the file-path KEY stored per record switched from the verbatim absolute/as-typed ingest
//   path (`<root-arg>/<rel>`, root-spelling-dependent) to a ROOT-RELATIVE key via relForHash — the
//   same lexical root-prefix strip S2 uses for the baseline sidecars. This makes the cache PORTABLE
//   (committable): a cache built at one root spelling/absolute path is re-absolutized against the
//   CURRENT invocation's root on load, so `repo.ripwirecache` built in CI or by a teammate at a
//   different checkout path still warm-hits. Old (v2) caches store the pre-T5 key shape; bumping
//   this field makes loadCache's version guard reject them outright (magic/version/parserVer must
//   all match) rather than silently re-absolutizing a key that was never root-relative to begin
//   with — a v2 cache simply misses on every lookup that survives the guard, which is exactly the
//   self-healing full-reparse path already used for any other corrupt/stale cache.
constexpr std::uint32_t kCacheVersion = 12;           // 12 (B6.3): FILE records gain two new record arrays —
                                                      //    RouteDef (server-side route registrations) and
                                                      //    RawRouteUse (client-side HTTP calls). A v11 (or older)
                                                      //    blob has neither, so the version guard rejects it
                                                      //    outright (self-healing full reparse repopulates routes).
                                                      // 11 (B2 graph precision): RawDef gains arityExact, RawRef gains
                                                      //    argCount+argCountKnown (call-site arity for B2.2) — a v10
                                                      //    (or older) blob lacks those bytes, so the version guard
                                                      //    rejects it (self-healing full reparse rebuilds with arity).
                                                      // 10 (B0 r2, H3): the rich def records' postings shrink —
                                                      //    each FILE record gains a sorted per-file subtoken
                                                      //    DICTIONARY (u64 hashes) and each def row stores narrow
                                                      //    dict INDICES + narrowest-exact-width tfs instead of raw
                                                      //    u64 hash + u32 tf pairs (the v9 shape grew the rich
                                                      //    blob +38-56% and dragged index/warm p95). Lossless by
                                                      //    construction (widths from maxima, VERIFY'd) — a FORMAT
                                                      //    change → reject v9 blobs (v9 never shipped; local v9
                                                      //    blobs self-heal via the same full-reparse path).
                                                      // 9 (B0.2 postings): each RICH-family def record gains the
                                                      //    persisted doc/body subtoken statistics (dlWeighted +
                                                      //    sorted (hash,tf) pair arrays; lexindex.h) — a FORMAT
                                                      //    change → reject v8 blobs (self-healing full reparse
                                                      //    rebuilds them with stats). Lean records are unchanged
                                                      //    in shape but share the header version, so lean v8
                                                      //    blobs self-heal identically (one version, one guard).
                                                      // 8 (A1 team-index): header gains a kArtifactArch tag byte
                                                      //    (endian + pointer width) after parserVer — a native-endian
                                                      //    blob is only same-arch-consumable, so a foreign-arch blob
                                                      //    must self-heal to a cold parse. A HEADER change → reject
                                                      //    v7 blobs (they lack the byte → the guard mismatches).
                                                      // 7 (A4-R5): each file record gains a BindingAlias (FFI)
                                                      //    stream after binds — a FORMAT change → reject v6 blobs.
                                                      // 6 (A4-P7): header gains a u64 blob-write timestamp; each
                                                      //    file record gains (sizeBytes,mtimeNs) for the warm-run
                                                      //    stat-gate + racy rule — a FORMAT change → reject v5 blobs.
                                                      // 5: non-C import targets now store the CLEAN specifier
                                                      //    (Py `pkg.mod`, TS `./x`, Rust `crate::a::b`/`mod:x`) —
                                                      //    a target FORMAT change → old caches must be rejected.
                                                      // 4: Include gained a `bool isAngle` (quote/angle) field
constexpr std::uint32_t kParserVer    = 43;           // bump on any grammar/.scm/extraction change
                                                      // 43: deepLoc line accounting fixed in cc_walk's else/elif
                                                      //    clause — the hump PROFILE pass now runs forward
                                                      //    (document order) instead of inside the backwards PUSH
                                                      //    loop, so the `else` token's own line is no longer
                                                      //    clamped away behind its block's high-water end. deep=
                                                      //    VALUES move on else-at-the-bar shapes, so caches
                                                      //    written by 42 hold numbers this build would not
                                                      //    produce and must be rejected.
                                                      // 41: Phase 1 (local-variable-indexing, PLAN.md 2026-08-06
                                                      //    evening): RawDef/Symbol gained a `locals` uint32_t
                                                      //    FLOOR field, populated inside the existing fused cc_walk
                                                      //    DFS (C/C++ only — model.h localsCountedLang). A FORMAT
                                                      //    change to the per-file RawDef cache blob (new u32 between
                                                      //    loc and params) → old caches must be rejected, not
                                                      //    misread as an off-by-one on every later field. quality.h's
                                                      //    kIngestParserVerMirror bumped in the SAME commit (P0.2).
                                                      // 40: captureIncludes descends into import CONTAINERS instead of
                                                      //    scanning the file root's direct children. Two families, one
                                                      //    walk: (a) preprocessor conditionals —
                                                      //    `#if`/`#ifdef`/`#ifndef`/`#else`/`#elif`/`#elifdef` — in the
                                                      //    C family and C#; (b) ordinary language constructs — Python's
                                                      //    `if TYPE_CHECKING:` / `try…except ImportError` / any function,
                                                      //    method or class body, Rust's `mod x { … }` / fn / impl / trait
                                                      //    / block bodies, and C#'s block-scoped `namespace Foo { … }`.
                                                      //    None of those were ever visited before, so a v39 blob on any
                                                      //    tree using them carries a SHORT include list → reject.
                                                      // (39: JavaScript gains four definition shapes measured missing
                                                      //    against real repos (webpack@957bf3a, node@427d2e1 lib/) —
                                                      //    field_definition bound to an arrow/function, #private
                                                      //    methods (+ their call references), gated CJS export
                                                      //    assignments, gated prototype assignments. A v38 blob on a
                                                      //    JS-bearing tree is missing those rows → reject.)
                                                      // (38: TypeScript
                                                      //    gains three definition shapes measured missing against a real
                                                      //    repo (openclaw, 24 658 .ts files) — abstract_method_signature,
                                                      //    public_field_definition bound to an arrow, and a declarator
                                                      //    whose value is an as/satisfies cast WRAPPING the arrow. A v37
                                                      //    blob on a TS-bearing tree is missing those rows, so it
                                                      //    describes a different graph and must be rejected; the on-disk
                                                      //    RECORD SHAPE did not change, so only parserVer moves, not
                                                      //    kCacheVersion — the CUDA (37) precedent exactly.
                                                      //    37: +CUDA (.cu/.cuh)
                                                      //    on the vendored tree-sitter-cuda grammar (kLangTable) — the
                                                      //    crawl SET changed (two new extensions) and `<<<>>>` launch
                                                      //    sites now extract as call references, so a v36 blob on a
                                                      //    CUDA-bearing tree describes a different graph and must be
                                                      //    rejected; the on-disk RECORD SHAPE did not change, so only
                                                      //    parserVer moves, not kCacheVersion — the +Metal (30)
                                                      //    precedent exactly; 36: H4 W3 V3-verifier
                                                      //    fixup L-1 — a Rust CONTAINER no longer scopes ITSELF.
                                                      //    rustEnclosingScopeOf started its ancestor walk at the node's
                                                      //    parent, and a `mod util`/`trait Shape` definition node IS that
                                                      //    owner's own `name:` child, so the module published `util::util`
                                                      //    and the trait `Shape::Shape` — a self-scope in the canonical-id
                                                      //    space that ids are keyed on. Per-def `scope` is a CACHED field,
                                                      //    so a v35 blob carries the old self-scoped ids and a warm run
                                                      //    would serve them: extraction change, bump required. (The M-2
                                                      //    file-module guard and the M-3 canonical-multi-match routing that
                                                      //    ship alongside are RESOLUTION-only, in graph.h, and would not
                                                      //    have needed one on their own.); 35: H4 W3 MERGE of two
                                                      //    lane bumps that each shipped an in-flight 34 with a DIFFERENT
                                                      //    extraction set (the never-reuse rule again) — the RUST
                                                      //    qualified-call widening: two new reference patterns
                                                      //    (`scoped_identifier name: (identifier)` — depth-unbounded because
                                                      //    Rust nests scoped paths LEFT — and `generic_function function:
                                                      //    (identifier)` for the bare turbofish), so `Widget::new()` /
                                                      //    `util::deep::deepfn()` / `Self::helper()` / `Vec::<u32>::new()` /
                                                      //    `generic::<u32>()` now extract at all, PLUS both halves of the
                                                      //    canonical tier for Rust: per-REF `qualifier` (the path's last
                                                      //    segment, turbofish-stripped, `Self` resolved to the enclosing
                                                      //    impl type) and per-DEF `scope` (the enclosing impl/trait/mod
                                                      //    owner), PLUS the Rust method-SPAN fix (the @definition.method
                                                      //    capture moved off the `declaration_list` wrapper onto the
                                                      //    `function_item`, so spans/loc/cx/ccx/params and ref attribution
                                                      //    for Rust all change); AND the W2b-fixup operator re-split — a
                                                      //    qualified call to an OPERATOR (`outer::inner::operator>`) now
                                                      //    re-splits on the operator-name tail instead of being handed to
                                                      //    the angle-depth scan, which its trailing `>` poisoned: the
                                                      //    per-ref `qualifier` for every `>`-family operator call changes
                                                      //    from the outermost scope to the immediate one. Blobs from
                                                      //    EITHER in-flight v34 describe a different graph and must be
                                                      //    rejected; 33: H4 W2b — the C++
                                                      //    qualified-call widening. The 2-segment `qualified_identifier
                                                      //    name: (identifier)` reference pattern is REPLACED by the
                                                      //    depth-unbounded `name: (_)` (3+-segment calls now extract at all
                                                      //    depths) and a `template_function` pattern is added (explicit
                                                      //    template-argument calls, cast keywords excluded at capture time),
                                                      //    plus ingest's re-split of the widened capture into
                                                      //    name + immediate qualifier. Both the extracted REFERENCE SET and
                                                      //    per-ref `qualifier` change → every blob written by a v32 binary
                                                      //    describes a different graph and must be rejected; 32: H4 wave-2a MERGE of two
                                                      //    lane bumps that each shipped an in-flight 31 with a DIFFERENT extraction
                                                      //    set (the never-reuse-an-in-flight-number rule, further down this comment log) — C#
                                                      //    conditional-access ("?.") calls (two member_binding_expression patterns,
                                                      //    so `w?.Bump()` / `a?.b?.C()` / `w?.Gen<T>()` now emit references) AND
                                                      //    qualified-`new` call refs for TS/JS (member_expression constructor) and
                                                      //    Java (scoped_type_identifier object_creation_expression), plus the ObjC
                                                      //    field_expression call-ref parity line with C; Go's explicit-generic-
                                                      //    instantiation widening was investigated and REJECTED (comment-only .scm change, extraction unaffected),
                                                      //    so Go is unaffected by this bump; 30: +Metal (.metal) on the
                                                      //    C++ grammar, C-family `#import` include edges, and the phantom-scope
                                                      //    guard in qualifierOf (a MISSING `::` no longer publishes the return type
                                                      //    as a canonical scope) — the crawl SET, the include-edge set, AND the
                                                      //    per-def `scope` field all changed; the on-disk RECORD SHAPE did not, so
                                                      //    only parserVer moves, not kCacheVersion. 29 was an in-flight value that
                                                      //    covered only the first two of those three; it must be rejected, because a
                                                      //    v29 blob carries the pre-guard phantom scopes and a warm run would serve
                                                      //    them (observed: `--uses` reported `Out::f` warm and `f` cold on the same
                                                      //    tree). RULE THIS COST US: a cached FIELD changing is an extraction change
                                                      //    even when no record grows — bump again, do not reuse the round's earlier
                                                      //    number; 28: JSON-lane ceilings —
                                                      //    kMaxJsonConfigBytes crawl skip + kMaxJsonNestDepth hostile-data guard;
                                                      //    the crawl/parse SET changed; 27: +C (.c); 26: +JSON config keys)

// A1 (team-index artifact): architecture/ABI tag for the cache-blob header. The blob is NATIVE-ENDIAN —
// ByteW/ByteR memcpy raw ints (see ByteW below), no portable varint/LE re-encoding — so it is only safely
// consumable on a machine with the same integer byte order AND pointer width that WROTE it. This one byte
// lets loadCache's existing header guard reject a foreign-arch blob exactly like a version mismatch → the
// blob is ignored → full cold reparse → correct output, just not fast. Encodes precisely the two properties
// that make a native-endian blob same-arch-consumable: bit 0 = byte order
// (0 little / 1 big), bits 1.. = sizeof(void*) (pointer width in bytes, the ABI word size the raw-int
// widths are keyed to). "Correctness never depends on the artifact" is preserved without paying for a
// portable encoding on the hot (de)serialize path that fe47139/PERF.md P2 optimized; a future big-endian
// target that actually needs a portable re-encode is a separate gated decision,
// not pre-paid here — the guard already makes such a target CORRECT (self-heal), just not fast.
constexpr std::uint8_t kArtifactArch =
      static_cast<std::uint8_t>( ( __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__ ) ? 1u : 0u )   // bit 0: endianness
    | static_cast<std::uint8_t>( sizeof( void* ) << 1 );                                   // bits 1..: pointer width (bytes)

// The lean/rich cache FAMILY split (documented against reality per a reviewer note).
// captureValueUses gets its OWN parserVer so a lean blob and a value-uses ("rich") blob can never cross-hit;
// the caller (main.cpp:587) sets it via `needsValueUses = !usesSym.empty() || metrics || !forTask.empty() ||
// !exemplar.empty()`. So which verbs each committed artifact accelerates, precisely:
//   LEAN  (captureValueUses=false): the DEFAULT map, all nav/read verbs (--callers/--callees/--around/
//         --expand/--impact/--path/--grep/--match), --pr-context, --affected, AND --situ (it is NOT in
//         needsValueUses — the DESIGN's "--situ needs rich" aside is backwards; the lean artifact serves it).
//   RICH  (captureValueUses=true): --for, --exemplar, --metrics (and its --hotspots/quality lenses), and
//         --uses. NB: --for is the flagship orientation verb every CLAUDE.md session opens with, and it is
//         RICH — so a team that commits ONLY the lean artifact gets NO warm hit on --for/--exemplar/--metrics
//         (those cold-parse unless the rich artifact is also committed). "Lean accelerates the common
//         orientation path" therefore overstates: lean speeds the default map + nav/read + --pr-context;
//         --for-led sessions need the rich family too. See the ingest-report to the wiring wave for the
//         measured lean-vs-rich blob sizes and the both-families recommendation.
inline std::uint32_t parserVerFor( bool captureValueUses ) noexcept
{
    return kParserVer + ( captureValueUses ? 1u : 0u );   // lean and full-use caches must never cross-hit
}

// T5: renamed from fnv1a64 to contentHash64 to avoid an ODR clash now that this file also includes
// arch.h (which defines its OWN fnv1a64 for the baseline-hash path, quality.h's canonId hashing, etc.
// — same FNV-1a family, DIFFERENT offset-basis constant; this is ingest's file-content-hash cache
// KEY and must not change bit-for-bit, so it keeps its own constant rather than switching to arch.h's).
inline std::uint64_t contentHash64( std::string_view s ) noexcept
{
    std::uint64_t h = 1469598103934665603ull;
    for( const char c : s )
    {
        h = hashutil::fnv1aAbsorb( h, c );
    }
    return h;
}

// BONUS (S): a whole-blob checksum for the cache trailer. The single-lane contentHash64 above is the file-content
// hash (cache KEY — must never change), but a scalar byte loop over the multi-MB cache blob costs ~1 byte/
// cycle. This uses 8 INDEPENDENT FNV lanes (byte i feeds lane i&7) so the multiplies pipeline, then folds —
// ~5× faster on the big blob while staying a pure, deterministic function of the bytes (a lane permutation of
// FNV-1a). Purpose is integrity detection (fuzzer-found bit-flips inside cached strings), not the cache key.
inline std::uint64_t blobChecksum( std::string_view s ) noexcept
{
    std::uint64_t lane[ 8 ] = { 1469598103934665603ull, 1099511628211ull, 0x100000001b3ull, 0x9e3779b97f4a7c15ull,
                                0xc2b2ae3d27d4eb4full, 0x165667b19e3779f9ull, 0xff51afd7ed558ccdull, 0xc4ceb9fe1a85ec53ull };
    const unsigned char* p = reinterpret_cast<const unsigned char*>( s.data() );
    const std::size_t    n = s.size();
    std::size_t          i = 0;
    for( ; i + 8 <= n; i += 8 )
    { // 8 lanes advance in lockstep — no cross-lane dependency
        for( int k = 0; k < 8; ++k ) { lane[ k ] ^= p[ i + k ]; lane[ k ] = hashutil::fnv1aMultiply( lane[ k ] ); }
    }
    for( int k = 0; i < n; ++i, ++k ) { lane[ k ] ^= p[ i ]; lane[ k ] = hashutil::fnv1aMultiply( lane[ k ] ); }   // tail (< 8 bytes)

    std::uint64_t h = 1469598103934665603ull;                   // fold the 8 lanes into one 64-bit digest
    for( int k = 0; k < 8; ++k ) { h ^= lane[ k ]; h = hashutil::fnv1aMultiply( h ); }
    return h;
}

// sizeBytes/mtimeNs (A4-P7): the file's stat at the run that HASHED it — the warm-run stat-gate trusts
// this record (skips read+hash) only when the current stat still matches AND mtimeNs is not racy. -1 ⇒
// unknown (cache built before v6, or the file was unstatable at hash time) → the gate always re-hashes.
struct FileFacts { std::uint64_t hash = 0; long long sizeBytes = -1; long long mtimeNs = -1; std::vector<RawDef> defs; std::vector<RawRef> refs; std::vector<Include> incs; std::vector<RawBind> binds; std::vector<BindingAlias> ffis; std::vector<RouteDef> routeDefs; std::vector<RawRouteUse> routeUses; };

// tiny native-endian binary (de)serializer (the cache is host-local, never shipped)
struct ByteW
{
    std::string b;
    void u8 ( std::uint8_t  v ) { b.push_back( char( v ) ); }
    void u32( std::uint32_t v ) { b.append( reinterpret_cast<const char*>( &v ), 4 ); }
    void u64( std::uint64_t v ) { b.append( reinterpret_cast<const char*>( &v ), 8 ); }
    void str( std::string_view s ) { u32( std::uint32_t( s.size() ) ); b.append( s ); }
    void raw( const void* p, std::size_t n )
    {
        if( n )
        {
            b.append( reinterpret_cast<const char*>( p ), n );
        }
    } // B0.2: bulk array append (memcpy-speed (de)serialize)
    // H3 (v10): bulk row extension — one resize + raw-pointer fill instead of a bounds-checked push_back
    // per byte (the postings rows are ~3 B × millions of pairs — this seam is the saveCache hot loop).
    // The narrow ints written through it are explicit little-endian (see writeDef), so the width-packed
    // postings fields read back identically on either endianness the kArtifactArch guard admits.
    char* extend( std::size_t n ) { const std::size_t off = b.size(); b.resize( off + n ); return b.data() + off; }
};
struct ByteR
{
    const char* p; const char* end; bool ok = true;
    std::uint8_t  u8 () { if( p >= end ) { ok = false; return 0; } return std::uint8_t( *p++ ); }
    std::uint32_t u32() { std::uint32_t v = 0; if( p + 4 > end ) { ok = false; return 0; } std::memcpy( &v, p, 4 ); p += 4; return v; }
    std::uint64_t u64() { std::uint64_t v = 0; if( p + 8 > end ) { ok = false; return 0; } std::memcpy( &v, p, 8 ); p += 8; return v; }
    std::string_view view() { const std::uint32_t n = u32(); if( !ok || p + n > end ) { ok = false; return {}; } std::string_view s( p, n ); p += n; return s; }
    std::string      str () { const std::string_view s = view(); return ok ? std::string( s ) : std::string{}; }
    bool rawInto( void* dst, std::size_t n )   // B0.2: bulk array read — overflow-safe bound, memcpy into caller storage
    { if( !ok || std::size_t( end - p ) < n ) { ok = false; return false; } if( n ) { std::memcpy( dst, p, n ); p += n; } return true; }
};

// withLex (B0.2 / v10 H3): the RICH family (captureValueUses=true) persists each def's doc/body subtoken
// stats. v10 encoding: the FILE record carries a sorted per-file subtoken DICTIONARY (see saveCache), and
// each def row stores dict-relative indices at the narrowest width the dict size allows + tfs at the
// narrowest width this def's max tf needs — exact integers either way (widths chosen from maxima, never
// lossy), ~3 B/pair instead of the raw 12 B/pair of v9. The LEAN family never computes them, so its
// record shape is unchanged; the two families can never cross-hit (parserVerFor), so one flag at both
// (de)serialize seams keeps the formats in lock-step.
inline unsigned lexDictIndexWidth( std::size_t dictCount ) noexcept
{
    return dictCount <= 0x100 ? 1u : dictCount <= 0x10000 ? 2u : 4u;   // indices go up to dictCount-1
}
inline void writeDef( ByteW& w, const RawDef& d, bool withLex, std::size_t fileDictCount, const std::uint32_t* rowDictIndex )
{
    w.u32( d.line ); w.u32( d.startByte ); w.u32( d.endByte ); w.u32( d.nameByte ); w.u32( d.bodyByte ); w.u32( d.cx ); w.u32( d.ccx ); w.u32( d.loc ); w.u32( d.locals ); w.u32( d.humps ); w.u32( d.deepLoc ); w.u32( d.params ); w.u8( d.maxNest ); w.u8( d.arityExact ); w.u8( std::uint8_t( d.kind ) ); w.u8( std::uint8_t( d.lang ) ); w.str( d.name ); w.str( d.scope );
    if( withLex )
    {
        VERIFY( d.lex.tokenHashes.size() == d.lex.tokenTfs.size() );
        w.u32( d.lex.dlWeighted );
        w.u32( std::uint32_t( d.lex.tokenHashes.size() ) );
        std::uint32_t maxTf = 0;
        for( const std::uint32_t tf : d.lex.tokenTfs )
        {
            if( tf > maxTf )
            {
                maxTf = tf;
            }
        }
        const unsigned tfWidth  = maxTf <= 0xFFu ? 1u : maxTf <= 0xFFFFu ? 2u : 4u;   // exact-preserving by construction
        const unsigned idxWidth = lexDictIndexWidth( fileDictCount );
        w.u8( std::uint8_t( tfWidth ) );
        // rowDictIndex: this def's precomputed dict indices (saveCache assigns them during the k-way
        // dict merge — no per-hash search here), ascending because the row is sorted. One bulk extend +
        // specialized fill loops per width — no per-byte push_back on this multi-million-pair seam.
        const std::size_t count = d.lex.tokenTfs.size();
        char*             p     = w.extend( count * ( idxWidth + tfWidth ) );
        if( idxWidth == 1 )
        {
            for( std::size_t k = 0; k < count; ++k )
            {
                *p++ = char( rowDictIndex[k] );
            }
        }
        else if( idxWidth == 2 )
        {
            for( std::size_t k = 0; k < count; ++k )
            {
                const std::uint32_t v = rowDictIndex[k];
                p[0] = char( v );
                p[1] = char( v >> 8 );
                p += 2;
            }
        }
        else
        {
            for( std::size_t k = 0; k < count; ++k )
            {
                const std::uint32_t v = rowDictIndex[k];
                p[0] = char( v );
                p[1] = char( v >> 8 );
                p[2] = char( v >> 16 );
                p[3] = char( v >> 24 );
                p += 4;
            }
        }
        const std::uint32_t* tfs = d.lex.tokenTfs.data();
        if( tfWidth == 1 )
        {
            for( std::size_t k = 0; k < count; ++k )
            {
                *p++ = char( tfs[k] );
            }
        }
        else if( tfWidth == 2 )
        {
            for( std::size_t k = 0; k < count; ++k )
            {
                const std::uint32_t v = tfs[k];
                p[0] = char( v );
                p[1] = char( v >> 8 );
                p += 2;
            }
        }
        else
        {
            for( std::size_t k = 0; k < count; ++k )
            {
                const std::uint32_t v = tfs[k];
                p[0] = char( v );
                p[1] = char( v >> 8 );
                p[2] = char( v >> 16 );
                p[3] = char( v >> 24 );
                p += 4;
            }
        }
    }
}
inline void   writeRef( ByteW& w, const RawRef& r ) { w.u32( r.startByte ); w.u8( std::uint8_t( r.lang ) ); w.str( r.name ); w.u8( r.isInherit ? 1 : 0 ); w.u8( r.isDocLink ? 1 : 0 ); w.str( r.qualifier ); w.u8( std::uint8_t( r.recv ) ); w.str( r.recvVar ); w.u8( r.isCompose ? 1 : 0 ); w.str( r.fieldName ); w.str( r.composeRel ); w.u8( std::uint8_t( r.role ) ); w.u32( r.line ); w.u32( r.argCount ); w.u8( r.argCountKnown ? 1 : 0 ); }

// loadCache's countFits() bounds a corrupt on-disk record COUNT against remaining bytes /
// minRecordBytes BEFORE reserve() — the guard that keeps a hostile blob's 0xFFFFFFFF count from reaching
// an allocator. The minima below are named + pinned here (not hand-recounted inline at the call site) so
// they sit next to the writer functions whose field list they must match. A LEAN def record is 10 u32 +
// 4 u8 + 2 empty str(len u32) fields = 10*4 + 4*1 + 2*4 = 52 bytes (Phase 1, local-variable-indexing,
// PLAN.md 2026-08-06 evening: `locals` u32 joined the run — 9 -> 10; the nesting profile then added
// `humps` and `deepLoc`, written as u32 each — 10 -> 12, so 12*4 + 4 + 8 = 60); the RICH (withLex) extra is
// dlWeighted u32 + tokenCount u32 + tfWidth u8 = 9 bytes. A ref record is 3 u32 + 7 u8 + 5 empty
// str(len u32) fields = 3*4 + 7*1 + 5*4 = 39 bytes. verifyCacheRecordMinimaTripwire() below derives these
// same numbers from the REAL writer functions at runtime so the next field added to writeDef/writeRef
// can't silently stale them.
inline constexpr std::size_t kMinDefRecordBytesLean      = 60;   // 12×u32 + 4×u8 + 2×str(len u32, empty)
inline constexpr std::size_t kMinDefRecordBytesRichExtra =  9;   // v10 rich withLex extra: dlWeighted u32 + tokenCount u32 + tfWidth u8
inline constexpr std::size_t kMinRefRecordBytes          = 39;   // 3×u32 + 7×u8 + 5×str(len u32, empty)

inline std::size_t minDefRecordBytes( bool captureValueUses ) noexcept
{
    return kMinDefRecordBytesLean + ( captureValueUses ? kMinDefRecordBytesRichExtra : 0 );
}

// runtime tripwire: serialize a DEFAULT-CONSTRUCTED (all-empty) RawDef/RawRef through the real
// writer functions and VERIFY the byte count matches the hand-pinned constants above. This is the runtime
// equivalent of the house `static_assert( sizeof(X) == N )` layout tripwire — ByteW's size is only known at
// runtime (strings, not a POD struct), so it can't be a compile-time static_assert. VERIFY is a no-op
// optimizer hint in release (never costs a shipped run anything); in any debug/ASan build or CI it fires the
// moment a field is added to writeDef/writeRef without updating the matching constant above.
inline void verifyCacheRecordMinimaTripwire() noexcept
{
    ByteW probe;
    writeDef( probe, RawDef{}, false, 0, nullptr );
    VERIFY( probe.b.size() == kMinDefRecordBytesLean );
    probe.b.clear();
    writeDef( probe, RawDef{}, true, 0, nullptr );
    VERIFY( probe.b.size() == kMinDefRecordBytesLean + kMinDefRecordBytesRichExtra );
    probe.b.clear();
    writeRef( probe, RawRef{} );
    VERIFY( probe.b.size() == kMinRefRecordBytes );
}

inline RawDef readDef( ByteR& r, bool withLex, const std::vector<std::uint64_t>& fileDict )
{
    RawDef d; d.line = r.u32(); d.startByte = r.u32(); d.endByte = r.u32(); d.nameByte = r.u32(); d.bodyByte = r.u32(); d.cx = r.u32(); d.ccx = r.u32(); d.loc = r.u32(); d.locals = r.u32(); d.humps = std::uint16_t( r.u32() ); d.deepLoc = std::uint16_t( r.u32() ); d.params = std::uint16_t( r.u32() ); d.maxNest = r.u8(); d.arityExact = r.u8(); d.kind = SymKind( r.u8() ); d.lang = Lang( r.u8() ); d.name = r.str(); d.scope = r.str();
    if( withLex && r.ok )
    {
        d.lex.dlWeighted = r.u32();
        const std::uint32_t tokenCount = r.u32();
        const std::uint8_t  tfWidth    = r.u8();
        // a corrupt on-disk count/width must never reach resize() (the throw would escape ingest()'s
        // never-throw contract) — every honest count is bounded by remaining bytes / min pair bytes
        if( !r.ok || ( tfWidth != 1 && tfWidth != 2 && tfWidth != 4 ) ) { r.ok = false; return d; }
        const unsigned    idxWidth  = lexDictIndexWidth( fileDict.size() );
        const std::size_t needBytes = std::size_t( tokenCount ) * ( idxWidth + tfWidth );
        if( std::size_t( r.end - r.p ) < needBytes ) { r.ok = false; return d; }
        d.lex.tokenHashes.resize( tokenCount );
        d.lex.tokenTfs.resize( tokenCount );
        // decode indices → hashes through the file dict; the dict is strictly ascending (validated at
        // load) and honest rows store strictly-ascending indices, so the decoded row is sorted — the
        // invariant the query-time binary search relies on. Violations ⇒ corrupt ⇒ self-healing reparse.
        // The whole row was bounds-checked ONCE above, so these are tight raw-pointer loops (this is the
        // warm-path deserialize hot spot — ~1M pairs on a jax-class rich blob).
        const unsigned char* q         = reinterpret_cast<const unsigned char*>( r.p );
        const std::uint64_t* dict      = fileDict.data();
        const std::uint32_t  dictCount = std::uint32_t( fileDict.size() );
        std::uint64_t*       hashOut   = d.lex.tokenHashes.data();
        std::uint32_t        prevIndex = 0;
        bool                 rowOk     = true;
        const auto decodeIndexRun = [ & ]( auto readOne )
        {
            for( std::uint32_t k = 0; k < tokenCount; ++k )
            {
                const std::uint32_t dictIndex = readOne();
                if( dictIndex >= dictCount || ( k > 0 && dictIndex <= prevIndex ) ) { rowOk = false; return; }
                hashOut[k] = dict[ dictIndex ];
                prevIndex  = dictIndex;
            }
        };
        if( idxWidth == 1 )
        {
            decodeIndexRun( [ & ]() noexcept
                            { return std::uint32_t( *q++ ); } );
        }
        else if( idxWidth == 2 )
        {
            decodeIndexRun( [ & ]() noexcept
                            { const std::uint32_t v = std::uint32_t( q[0] ) | std::uint32_t( q[1] ) << 8; q += 2; return v; } );
        }
        else
        {
            decodeIndexRun( [ & ]() noexcept
                            { const std::uint32_t v = std::uint32_t( q[0] ) | std::uint32_t( q[1] ) << 8 | std::uint32_t( q[2] ) << 16 | std::uint32_t( q[3] ) << 24; q += 4; return v; } );
        }
        if( !rowOk ) { r.ok = false; return d; }
        std::uint32_t* tfOut = d.lex.tokenTfs.data();
        if( tfWidth == 1 )
        {
            for( std::uint32_t k = 0; k < tokenCount; ++k )
            {
                tfOut[k] = *q++;
            }
        }
        else if( tfWidth == 2 )
        {
            for( std::uint32_t k = 0; k < tokenCount; ++k )
            {
                tfOut[k] = std::uint32_t( q[0] ) | std::uint32_t( q[1] ) << 8;
                q += 2;
            }
        }
        else
        {
            for( std::uint32_t k = 0; k < tokenCount; ++k )
            {
                tfOut[k] = std::uint32_t( q[0] ) | std::uint32_t( q[1] ) << 8 | std::uint32_t( q[2] ) << 16 | std::uint32_t( q[3] ) << 24;
                q += 4;
            }
        }
        r.p += needBytes;
    }
    return d;
}
inline RawRef readRef ( ByteR& r ) { RawRef x; x.startByte = r.u32(); x.lang = Lang( r.u8() ); x.name = r.str(); x.isInherit = r.u8() != 0; x.isDocLink = r.u8() != 0; x.qualifier = r.str(); x.recv = RecvKind( r.u8() ); x.recvVar = r.str(); x.isCompose = r.u8() != 0; x.fieldName = r.str(); x.composeRel = r.str(); x.role = RefRole( r.u8() ); x.line = r.u32(); x.argCount = std::uint16_t( r.u32() ); x.argCountKnown = r.u8() != 0; return x; }
inline void   writeBind( ByteW& w, const RawBind& b ) { w.u32( b.startByte ); w.u8( std::uint8_t( b.lang ) ); w.str( b.var ); w.str( b.typeName ); }
inline RawBind readBind( ByteR& r ) { RawBind b; b.startByte = r.u32(); b.lang = Lang( r.u8() ); b.var = r.str(); b.typeName = r.str(); return b; }
inline void   writeFfi( ByteW& w, const BindingAlias& a ) { w.u8( std::uint8_t( a.kind ) ); w.u8( a.lowConf ? 1 : 0 ); w.str( a.aliasName ); w.str( a.targetName ); w.str( a.targetScope ); }
inline BindingAlias readFfi( ByteR& r ) { BindingAlias a; a.kind = BindKind( r.u8() ); a.lowConf = r.u8() != 0; a.aliasName = r.str(); a.targetName = r.str(); a.targetScope = r.str(); return a; }
// B6.3: RouteDef needs no startByte (its handler is resolved by NAME in buildGraph); RawRouteUse mirrors
// RawBind (startByte for the enclosing-def byte-span attribution done in the ingest() model-build below).
inline void   writeRouteDef( ByteW& w, const RouteDef& d ) { w.u32( d.line ); w.u8( std::uint8_t( d.method ) ); w.str( d.path ); w.str( d.handlerName ); }
inline RouteDef readRouteDef( ByteR& r ) { RouteDef d; d.line = r.u32(); d.method = HttpMethod( r.u8() ); d.path = r.str(); d.handlerName = r.str(); return d; }
inline void   writeRouteUse( ByteW& w, const RawRouteUse& u ) { w.u32( u.startByte ); w.u32( u.line ); w.u8( std::uint8_t( u.method ) ); w.str( u.path ); }
inline RawRouteUse readRouteUse( ByteR& r ) { RawRouteUse u; u.startByte = r.u32(); u.line = r.u32(); u.method = HttpMethod( r.u8() ); u.path = r.str(); return u; }

// T5: re-absolutize a cache-stored ROOT-RELATIVE key against the CURRENT invocation's rootDir, producing
// the exact spelling collectSources() would crawl it as (`<rootDir>/<rel>`, trailing slash on rootDir
// normalized away) — the same spelling result.files[fileId] holds, so cache.find(path) in the caller
// needs no changes. Pure string join; no filesystem I/O (mirrors relForHash's own no-realpath contract).
inline std::string reAbsolutize( std::string_view rel, std::string_view root )
{
    std::string_view rootTrim = root;
    while( rootTrim.size() > 1 && rootTrim.back() == '/' )
    {
        rootTrim.remove_suffix( 1 );
    }
    if( rootTrim.empty() )
    {
        rootTrim = "."; // empty root ⇒ same "." spelling collectSources' fs::path("") would give
    }
    std::string out;
    out.reserve( rootTrim.size() + 1 + rel.size() );
    out.append( rootTrim );
    out.push_back( '/' );
    out.append( rel );
    return out;
}

// load cache → map<path, FileFacts>, keyed by the ABSOLUTE-AS-CRAWLED path under `rootDir` (matching
// result.files' spelling) even though the on-disk record key is root-relative (T5 portability — see
// kCacheVersion=3 above). Empty on missing / corrupt / version-or-parserVer mismatch.
// blobWriteNsOut (supersedes A4-P7): the racy-rule reference a warm run's stat-gate compares
// every cached file's mtime against. STAMPED FROM A FRESH stat() OF THE CACHE FILE ITSELF (this file's own
// `path`, taken right here — necessarily "post-rename", since by the time a later run's loadCache opens it
// the writer's saveCache has long since renamed tmp -> path), NOT from the ns-precision wall-clock the
// header still carries for legacy/diagnostic reasons. Same clock+granularity domain (stat()) as the
// per-file mtimes it is compared against below — on a coarse-mtime filesystem (HFS+, many network mounts)
// the old wall-clock-vs-stat comparison was a tautology (a floored mtime is always < an unfloored LATER
// timestamp), so a same-granule post-hash edit could slip through undetected. No wall-clock read on this
// path. Left at -1 on any miss/corrupt/version-mismatch/unstatable-path (out is empty then too), which
// makes every stat-gate check see a racy entry and re-hash — the safe default.
inline HashMap<std::string, FileFacts> loadCache( const std::string& path, std::string_view rootDir, bool captureValueUses,
                                                  long long& blobWriteNsOut )
{
    PROFILE_SCOPE_DESCRIBE( "ingest: loadCache (read + deserialize)" );
    HashMap<std::string, FileFacts> out;
    blobWriteNsOut = -1;

    // L1: only a REGULAR file may reach readFile below — on Linux a directory opens cleanly and takes its
    // resize() down with it. Any other shape self-heals into a full reparse, exactly like a checksum
    // mismatch (see isReadableCacheBlob); blobWriteNsOut stays -1 ⇒ the caller cold-parses.
    if( !isReadableCacheBlob( path ) )
    {
        return out;
    }

    std::string blob;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/loadCache: read cache blob" );
        if( !readFile( path, blob ) )
        {
            return out;
        }
    }

    // BONUS (S): whole-blob FNV-1a checksum trailer (last 8 bytes). saveCache appends fnv1a64(payload) so a
    // silent bit-flip INSIDE a cached string (fuzzer-found: the count/version guards trust the record bytes)
    // is caught here → treat as corrupt → self-healing full reparse. A blob too short to hold magic+trailer
    // is corrupt too. Reader `r` is bounded to the PAYLOAD (blob minus the 8-byte trailer).
    constexpr std::size_t kTrailerBytes = 8;
    if( blob.size() < 21 + kTrailerBytes )
    {
        return out; // 3×u32 + u8 arch + u64 blobWriteNs header + trailer minimum
    }
    const std::size_t payloadLen = blob.size() - kTrailerBytes;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/loadCache: checksum trailer" );
        std::uint64_t stored = 0;
        std::memcpy( &stored, blob.data() + payloadLen, kTrailerBytes );
        if( blobChecksum( std::string_view( blob.data(), payloadLen ) ) != stored )
        {
            DEGRADED_PATH_ALERT( "ingest: cache checksum mismatch — cache treated as corrupt (full reparse)" );
            return out;
        }
    }

    ByteR r{ blob.data(), blob.data() + payloadLen };
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/loadCache: header" );
        // A1 (team-index): the kArtifactArch byte is part of the header guard — a foreign-arch blob
        // (different endianness or pointer width) mismatches here exactly like a version/parserVer
        // mismatch → out stays empty, blobWriteNsOut stays -1 → the caller cold-parses (self-heal).
        // Left-to-right && short-circuit means the u8() read only happens once magic/version/parserVer
        // have matched, keeping the byte-stream cursor consistent on the accepted path.
        if( r.u32() != kCacheMagic || r.u32() != kCacheVersion || r.u32() != parserVerFor( captureValueUses ) || r.u8() != kArtifactArch )
        {
            return out;
        }
        (void)r.u64();   // legacy wall-clock write stamp — kept in the wire format for diagnostics, no longer
                          // the racy-rule reference (F3/X5: see blobWriteNsOut below); must still be consumed
                          // to keep the byte-stream cursor aligned with the record count that follows.
    }

    // F3/X5: the racy-rule reference is THIS cache file's own on-disk mtime, stat'd fresh right now — the
    // same stat()-domain, same-granularity value every per-file mtime below is compared against. -1 (unstatable,
    // e.g. removed between the readFile above and here) ⇒ every stat-gate check sees a racy entry (safe default).
    blobWriteNsOut = statSizeMtime( path ).mtimeNs;

    // count validation: a corrupt on-disk count (e.g. 0xFFFFFFFF) must never reach reserve() — the throw
    // (length_error/bad_alloc) would escape ingest(), violating its never-throw contract. Every honest
    // count is bounded by remaining bytes / the record's MINIMUM serialized size; past that → corrupt →
    // same self-healing full-reparse path as a truncated blob (r.ok = false → out.clear() below).
    // (B0.2) a RICH def record additionally carries at least dlWeighted + tokenCount (2×u32) — the pair
    // arrays themselves are bounded per record inside readDef.
    const std::size_t kMinDefRecordBytes  = minDefRecordBytes( captureValueUses );   // F8: named + tripwire-pinned above
    constexpr std::size_t kMinIncRecordBytes  =  5;   // 1×u8 (isAngle) + 1×str(len u32, empty)
    constexpr std::size_t kMinBindRecordBytes = 13;   // 1×u32 + 1×u8 + 2×str(len u32, empty)
    constexpr std::size_t kMinFfiRecordBytes  = 14;   // 2×u8 (kind,lowConf) + 3×str(len u32, empty)
    constexpr std::size_t kMinRouteDefRecordBytes = 13;   // B6.3: 1×u32 (line) + 1×u8 (method) + 2×str(len u32, empty)
    constexpr std::size_t kMinRouteUseRecordBytes = 13;   // B6.3: 2×u32 (startByte,line) + 1×u8 (method) + 1×str(len u32, empty)
    const std::size_t kMinFileRecordBytes = 52 + ( captureValueUses ? 4 : 0 );   // path str + hash + sizeBytes + mtimeNs + six record counts, all empty (v6: +2×u64; v10 rich: + dict count u32; v12/B6.3: +2×u32 route counts)
    const auto countFits = [ &r ]( std::uint32_t recordCount, std::size_t minRecordBytes ) noexcept
    {
        if( recordCount <= std::size_t( r.end - r.p ) / minRecordBytes )
        {
            return true;
        }
        DEGRADED_PATH_ALERT( "ingest: cache record count exceeds remaining bytes — cache treated as corrupt" );
        r.ok = false;
        return false;
    };

    std::uint32_t nf = 0;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/loadCache: file count + reserve" );
        nf = r.u32();
        if( !countFits( nf, kMinFileRecordBytes ) )
        {
            return out;
        }
        out.reserve( nf );
    }
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/loadCache: deserialize file records" );
        std::vector<std::uint64_t> fileDict;   // H3 (v10): per-file subtoken dictionary (rich family only)
        for( std::uint32_t i = 0; i < nf && r.ok; ++i )
        {
            // T5: the on-disk key is ROOT-RELATIVE (relForHash'd at save time); re-absolutize against the
            // CURRENT rootDir so the map key matches result.files' spelling for this invocation exactly —
            // this is what makes a cache built under one root/checkout path warm-hit under another.
            std::string key = reAbsolutize( r.view(), rootDir );
            FileFacts   ff;
            ff.hash      = r.u64();
            ff.sizeBytes = (long long)r.u64();   // A4-P7 stat-gate discriminator
            ff.mtimeNs   = (long long)r.u64();   // A4-P7 stat-gate discriminator + racy-rule input
            if( captureValueUses )
            {
                // H3 (v10): the file's subtoken dictionary — def rows below index into it. Must be
                // strictly ascending (readDef's sorted-row invariant hangs on it); anything else is
                // corrupt → the same self-healing full-reparse path as a truncated blob.
                const std::uint32_t dictCount = r.u32();
                if( !countFits( dictCount, sizeof( std::uint64_t ) ) )
                {
                    break;
                }
                fileDict.resize( dictCount );
                if( !r.rawInto( fileDict.data(), std::size_t( dictCount ) * sizeof( std::uint64_t ) ) )
                {
                    break;
                }
                for( std::size_t k = 1; k < fileDict.size(); ++k )
                {
                    if( fileDict[k] <= fileDict[ k - 1 ] )
                    {
                        DEGRADED_PATH_ALERT( "ingest: cache file dictionary not strictly ascending — cache treated as corrupt" );
                        r.ok = false;
                        break;
                    }
                }
                if( !r.ok )
                {
                    break;
                }
            }
            const std::uint32_t nd = r.u32();
            if( !countFits( nd, kMinDefRecordBytes ) )
            {
                break;
            }
            ff.defs.reserve( nd );
            for( std::uint32_t j = 0; j < nd && r.ok; ++j )
            {
                ff.defs.push_back( readDef( r, captureValueUses, fileDict ) );
            }
            const std::uint32_t nr = r.u32();
            if( !countFits( nr, kMinRefRecordBytes ) )
            {
                break;
            }
            ff.refs.reserve( nr );
            for( std::uint32_t j = 0; j < nr && r.ok; ++j )
            {
                ff.refs.push_back( readRef( r ) );
            }
            const std::uint32_t ni = r.u32();
            if( !countFits( ni, kMinIncRecordBytes ) )
            {
                break;
            }
            ff.incs.reserve( ni );
            for( std::uint32_t j = 0; j < ni && r.ok; ++j )
            {
                const bool isAngle = r.u8() != 0;
                ff.incs.push_back( Include { 0, isAngle, r.str() } );
            }
            const std::uint32_t nb = r.u32();
            if( !countFits( nb, kMinBindRecordBytes ) )
            {
                break;
            }
            ff.binds.reserve( nb );
            for( std::uint32_t j = 0; j < nb && r.ok; ++j )
            {
                ff.binds.push_back( readBind( r ) );
            }
            const std::uint32_t na = r.u32();
            if( !countFits( na, kMinFfiRecordBytes ) )
            {
                break;
            }
            ff.ffis.reserve( na );
            for( std::uint32_t j = 0; j < na && r.ok; ++j )
            {
                ff.ffis.push_back( readFfi( r ) );
            }
            const std::uint32_t nrd = r.u32();
            if( !countFits( nrd, kMinRouteDefRecordBytes ) )
            {
                break;
            }
            ff.routeDefs.reserve( nrd );
            for( std::uint32_t j = 0; j < nrd && r.ok; ++j )
            {
                ff.routeDefs.push_back( readRouteDef( r ) ); // B6.3
            }
            const std::uint32_t nru = r.u32();
            if( !countFits( nru, kMinRouteUseRecordBytes ) )
            {
                break;
            }
            ff.routeUses.reserve( nru );
            for( std::uint32_t j = 0; j < nru && r.ok; ++j )
            {
                ff.routeUses.push_back( readRouteUse( r ) ); // B6.3
            }
            if( r.ok )
            {
                out.emplace( std::move( key ), std::move( ff ) );
            }
        }
    }
    if( !r.ok )
    {
        out.clear(); // truncated/corrupt → ignore (full reparse; self-healing)
    }
    return out;
}

// write the cache atomically (path.tmp → rename); groups the merged raw facts back by file.
// T5: `rootDir` is the CURRENT invocation's ingest root — every file key is stored root-relative
// (relForHash) rather than verbatim, so the cache blob is committable/portable (see kCacheVersion=3).
inline void saveCache( const std::string& path, std::string_view rootDir, const std::vector<std::string>& files,
                       const std::vector<std::uint64_t>& fileHash,
                       const std::vector<long long>& fileSize, const std::vector<long long>& fileMtime,
                       const std::vector<RawDef>& defs, const std::vector<RawRef>& refs, const std::vector<Include>& incs,
                       const std::vector<RawBind>& binds, const std::vector<BindingAlias>& ffis,
                       const std::vector<RouteDef>& routeDefs, const std::vector<RawRouteUse>& routeUses,   // B6.3
                       bool captureValueUses )
{
    PROFILE_SCOPE_DESCRIBE( "ingest: saveCache (serialize + write)" );

    // L1 (write half): never publish over a non-regular file, and decide it BEFORE the serialize so a
    // directory at `path` costs no wasted pass and temp write before rename(tmp,dir) fails EISDIR.
    if( shapeOfPath( path ) == PathShape::Other )
    {
        DEGRADED_PATH_ALERT( "ingest: cache path is not a regular file (directory/device/fifo) — cache not written" );
        return;
    }

    const std::size_t F = files.size();
    std::vector<std::vector<std::uint32_t>> dIdx( F ), rIdx( F ), iIdx( F ), bIdx( F ), aIdx( F ), rdIdx( F ), ruIdx( F );
    for( std::uint32_t i = 0; i < defs.size(); ++i )
    {
        if( defs[i].fileId < F )
        {
            dIdx[defs[i].fileId].push_back( i );
        }
    }
    for( std::uint32_t i = 0; i < refs.size(); ++i )
    {
        if( refs[i].fileId < F )
        {
            rIdx[refs[i].fileId].push_back( i );
        }
    }
    for( std::uint32_t i = 0; i < incs.size(); ++i )
    {
        if( incs[i].fileId < F )
        {
            iIdx[incs[i].fileId].push_back( i );
        }
    }
    for( std::uint32_t i = 0; i < binds.size(); ++i )
    {
        if( binds[i].fileId < F )
        {
            bIdx[binds[i].fileId].push_back( i );
        }
    }
    for( std::uint32_t i = 0; i < ffis.size(); ++i )
    {
        if( ffis[i].fileId < F )
        {
            aIdx[ffis[i].fileId].push_back( i );
        }
    }
    for( std::uint32_t i = 0; i < routeDefs.size(); ++i )
    {
        if( routeDefs[i].fileId < F )
        {
            rdIdx[routeDefs[i].fileId].push_back( i ); // B6.3
        }
    }
    for( std::uint32_t i = 0; i < routeUses.size(); ++i )
    {
        if( routeUses[i].fileId < F )
        {
            ruIdx[routeUses[i].fileId].push_back( i ); // B6.3
        }
    }

    // This header field is no longer the racy-rule reference — loadCache now derives that from
    // a fresh stat() of the cache file itself (same clock+granularity domain as the per-file mtimes it's
    // compared against; see loadCache's blobWriteNsOut comment for why the wall-clock-vs-stat comparison
    // this used to feed was a tautology on coarse-mtime filesystems). Kept written, at the same wire offset,
    // purely as a diagnostic "when was this blob generated" stamp — changing/removing it would bump
    // kCacheVersion for no behavioral gain.
    const long long blobWriteNs = wallClockNs();

    ByteW w;
    // A1 (team-index): kArtifactArch byte sits in the header right after parserVer so loadCache's guard
    // rejects a foreign-arch (endian/pointer-width) blob before trusting any raw-int record bytes.
    w.u32( kCacheMagic );
    w.u32( kCacheVersion );
    w.u32( parserVerFor( captureValueUses ) );
    w.u8( kArtifactArch );
    w.u64( (std::uint64_t)blobWriteNs );
    w.u32( std::uint32_t( F ) );
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/saveCache: serialize records" );
        std::vector<std::uint64_t> fileDict;                                   // per-file subtoken dictionary, reused across files
        std::vector<LexPair>       mergeA, mergeB;                             // ping-pong buffers of the balanced run-merge, reused
        std::vector<std::size_t>   runOffsets, nextRunOffsets;                 // sorted-run bounds inside the ping-pong buffer
        std::vector<std::uint32_t> pairDictIndex;                              // pair slot → dict index, in def-row order
        for( std::uint32_t f = 0; f < F; ++f )
        {
            w.str( relForHash( files[f], rootDir ) );
            w.u64( f < fileHash.size() ? fileHash[f] : 0 );
            w.u64( f < fileSize.size() ? (std::uint64_t)fileSize[f] : (std::uint64_t)-1 ); // A4-P7 stat-gate: size at hash time (-1 ⇒ unknown → gate re-hashes)
            w.u64( f < fileMtime.size() ? (std::uint64_t)fileMtime[f] : (std::uint64_t)-1 ); // A4-P7 stat-gate: mtimeNs at hash time (-1 ⇒ unknown)
            if( captureValueUses )
            {
                // H3 (v10): the sorted union of this file's def rows — subtokens repeat heavily across a
                // file's defs (nested spans re-tokenize the same text), so hoisting each distinct hash into
                // ONE per-file dictionary and storing narrow indices per row shrinks the rich blob's
                // postings from 12 B/pair to ~dictShare×8 + idxWidth + tfWidth bytes. Every row is ALREADY
                // sorted (lexindex.h buildDefLexStats), so the dict is a BALANCED PAIRWISE MERGE over the
                // rows (P·log2(rows) sequential std::merge steps — measured cheaper than both a flat
                // O(P log P) sort and a per-element k-way heap), and the final merged (hash, slot) order
                // assigns every row position's dict index in one walk. Deterministic: equal hashes all land
                // on the same dict entry regardless of slot order. This is the --index-out / prime hot path.
                fileDict.clear();
                mergeA.clear();
                runOffsets.clear();
                runOffsets.push_back( 0 );
                std::uint32_t slotCount = 0;
                for( const std::uint32_t i : dIdx[f] )
                {
                    const std::vector<std::uint64_t>& row = defs[i].lex.tokenHashes;
                    for( const std::uint64_t hash : row )
                    {
                        mergeA.push_back( LexPair{ hash, slotCount++ } );   // braced, not emplace_back( a, b ): aggregate emplace needs P0960, absent in Clang < 20 (CI's Xcode 15.4)
                    }
                    if( !row.empty() )
                    {
                        runOffsets.push_back( mergeA.size() );
                    }
                }
                std::vector<LexPair>* src = &mergeA;
                std::vector<LexPair>* dst = &mergeB;
                while( runOffsets.size() > 2 ) // > 1 run left → one merge pass
                {
                    dst->resize( src->size() ); // exact pass size — merges write via raw pointers,
                    nextRunOffsets.clear(); //   no per-element back_inserter capacity branch
                    nextRunOffsets.push_back( 0 );
                    LexPair* writeCursor = dst->data();
                    for( std::size_t runIndex = 0; runIndex + 1 < runOffsets.size(); runIndex += 2 )
                    {
                        const std::size_t lo = runOffsets[runIndex];
                        const std::size_t mid = runOffsets[runIndex + 1];
                        if( runIndex + 2 < runOffsets.size() ) // a full pair of runs → merge them
                        {
                            const std::size_t hi = runOffsets[runIndex + 2];
                            writeCursor = std::merge( src->data() + lo, src->data() + mid, src->data() + mid, src->data() + hi, writeCursor );
                        }
                        else // odd tail run: carry over
                        {
                            std::memcpy( writeCursor, src->data() + lo, ( mid - lo ) * sizeof( LexPair ) );
                            writeCursor += mid - lo;
                        }
                        nextRunOffsets.push_back( std::size_t( writeCursor - dst->data() ) );
                    }
                    runOffsets.swap( nextRunOffsets );
                    std::swap( src, dst );
                }
                pairDictIndex.resize( slotCount );
                for( const auto& [hash, slot] : *src )
                {
                    if( fileDict.empty() || fileDict.back() != hash )
                    {
                        fileDict.push_back( hash );
                    }
                    pairDictIndex[slot] = std::uint32_t( fileDict.size() - 1 );
                }
                w.u32( std::uint32_t( fileDict.size() ) );
                w.raw( fileDict.data(), fileDict.size() * sizeof( std::uint64_t ) );
            }
            w.u32( std::uint32_t( dIdx[f].size() ) );
            {
                std::size_t rowOffset = 0; // running slot offset into pairDictIndex
                for( std::uint32_t i : dIdx[f] )
                {
                    writeDef( w, defs[i], captureValueUses, fileDict.size(), pairDictIndex.data() + rowOffset );
                    if( captureValueUses )
                    {
                        rowOffset += defs[i].lex.tokenHashes.size();
                    }
                }
            }
            w.u32( std::uint32_t( rIdx[f].size() ) );
            for( std::uint32_t i : rIdx[f] )
            {
                writeRef( w, refs[i] );
            }
            w.u32( std::uint32_t( iIdx[f].size() ) );
            for( std::uint32_t i : iIdx[f] )
            {
                w.u8( incs[i].isAngle ? 1 : 0 );
                w.str( incs[i].target );
            }
            w.u32( std::uint32_t( bIdx[f].size() ) );
            for( std::uint32_t i : bIdx[f] )
            {
                writeBind( w, binds[i] );
            }
            w.u32( std::uint32_t( aIdx[f].size() ) );
            for( std::uint32_t i : aIdx[f] )
            {
                writeFfi( w, ffis[i] );
            }
            w.u32( std::uint32_t( rdIdx[f].size() ) );
            for( std::uint32_t i : rdIdx[f] )
            {
                writeRouteDef( w, routeDefs[i] ); // B6.3
            }
            w.u32( std::uint32_t( ruIdx[f].size() ) );
            for( std::uint32_t i : ruIdx[f] )
            {
                writeRouteUse( w, routeUses[i] ); // B6.3
            }
        }
    }   // symmetric bare scope: serialize-records profiling span

    // BONUS (S): append the whole-payload checksum so loadCache can catch a silent bit-flip inside a cached
    // string (the length/version guards trust the bytes; a flip there survives them). 8-byte trailer, verified
    // at load. blobChecksum is the fast 8-lane FNV variant — cheap even on a multi-MB blob.
    std::uint64_t sum = 0;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/saveCache: checksum" );
        sum = blobChecksum( std::string_view( w.b.data(), w.b.size() ) );
    }
    w.u64( sum );
    PROFILE_SCOPE_DESCRIBE( "ingest/saveCache: write + rename" );

    // unique per-process temp so two concurrent runs (this repo runs ~20 parallel sessions) don't
    // interleave writes into ONE shared "path.tmp" and rename a torn file. rename(2) is atomic; the
    // per-pid temp makes each writer's bytes whole → last-writer-wins, never a corrupt cache.
    //
    // A3-F9: fwrite/fclose were never checked, so an ENOSPC (or any short write) produced a truncated
    // temp file that still got rename()'d over the previous GOOD cache — silently destroying it (the
    // checksum trailer self-heals on next load via a full reparse, so this was perf-only, but a good
    // cache should never be clobbered without a peep). Mirrors mcpedit::atomicWrite's discipline
    // (src/mcp.h): check the write byte-count AND fclose's return, and on any failure unlink the temp
    // and leave the prior on-disk cache (if any) untouched.
    const std::string tmp = path + "." + std::to_string( getpid() ) + ".tmp";
    std::FILE* fp = std::fopen( tmp.c_str(), "wb" );
    if( !fp )
    {
        DEGRADED_PATH_ALERT( "ingest: saveCache could not open temp file for write — cache left unchanged" );
        return;
    }
    const std::size_t wrote = std::fwrite( w.b.data(), 1, w.b.size(), fp );
    const bool wErr = wrote != w.b.size() || std::fclose( fp ) != 0;
    if( wErr )
    {
        std::remove( tmp.c_str() );   // never rename a short/torn write over a good cache
        DEGRADED_PATH_ALERT( "ingest: saveCache write failed (short write or fclose error) — old cache preserved" );
        return;
    }
    if( std::rename( tmp.c_str(), path.c_str() ) != 0 )
    {
        std::remove( tmp.c_str() );   // clean up on failure
        DEGRADED_PATH_ALERT( "ingest: saveCache rename(tmp -> cache) failed — old cache preserved" );
        return;
    }

    // A5 (cache-dir hygiene): --doctor measured ~11,914 ripwire-* blobs / 2.4 GB accumulating in the cache-ladder
    // dir because only the qsnap/qheadsnap families ever evicted — this main parse-cache family (this very
    // `path`) never did. Best-effort, silent, at most once per process (see sweepStaleCacheBlobsOnce for the
    // policy + the concurrency-safety argument). `path` is the blob we just rename()'d into place, so it is
    // always the retained "keepPath" even if it happens to be the oldest survivor by mtime granularity.
    quality::sweepStaleCacheBlobsOnce( quality::cacheDirLadder(), path );
}

// ---- cyclomatic complexity: 1 + decision points in a def's subtree (Myers' &&/|| extension). ----
// Decision-point node types across our grammars (C++/Python/TS/Go/Rust/Swift + Ruby). Reported as a raw
// number (--metrics), never a gate — the map's distribution is the local baseline the agent reads against.
inline bool isDecisionType( const char* t ) noexcept
{
    return    std::strcmp( t, "if_statement" ) == 0       || std::strcmp( t, "if_expression" ) == 0
           || std::strcmp( t, "for_statement" ) == 0      || std::strcmp( t, "for_range_loop" ) == 0
           || std::strcmp( t, "for_in_statement" ) == 0   || std::strcmp( t, "for_expression" ) == 0
           || std::strcmp( t, "while_statement" ) == 0    || std::strcmp( t, "while_expression" ) == 0
           || std::strcmp( t, "do_statement" ) == 0       || std::strcmp( t, "loop_expression" ) == 0
           || std::strcmp( t, "case_statement" ) == 0     || std::strcmp( t, "match_arm" ) == 0
           || std::strcmp( t, "expression_case" ) == 0    || std::strcmp( t, "communication_case" ) == 0
           || std::strcmp( t, "catch_clause" ) == 0       || std::strcmp( t, "except_clause" ) == 0
           || std::strcmp( t, "conditional_expression" ) == 0 || std::strcmp( t, "ternary_expression" ) == 0
           || std::strcmp( t, "boolean_operator" ) == 0    // Python `and`/`or`
           // Ruby (tree-sitter-ruby node kinds): block `if`/`elsif`/`unless`/`while`/`until`/`for`, the
           // trailing modifier forms (`x if a`), each `when`/`in_clause` arm, `rescue`, and the `? :`
           // `conditional`. Ruby's `case`/`case_match` head is a nesting container (see cc_isNestingControl),
           // NOT a decision — each `when`/`in_clause` arm is the decision, matching C-family case_statement.
           || std::strcmp( t, "if" ) == 0                 || std::strcmp( t, "elsif" ) == 0
           || std::strcmp( t, "unless" ) == 0             || std::strcmp( t, "while" ) == 0
           || std::strcmp( t, "until" ) == 0              || std::strcmp( t, "for" ) == 0
           || std::strcmp( t, "if_modifier" ) == 0        || std::strcmp( t, "unless_modifier" ) == 0
           || std::strcmp( t, "while_modifier" ) == 0     || std::strcmp( t, "until_modifier" ) == 0
           || std::strcmp( t, "when" ) == 0               || std::strcmp( t, "in_clause" ) == 0
           || std::strcmp( t, "rescue" ) == 0             || std::strcmp( t, "conditional" ) == 0
           // C# (tree-sitter-c-sharp): `foreach` is a distinct loop node (not `for_statement`); each
           // classic-switch `case`/`default` arm is a `switch_section`, each modern switch-expression
           // arm is a `switch_expression_arm` — both are the per-arm decision, matching Ruby's `when`.
           || std::strcmp( t, "foreach_statement" ) == 0   || std::strcmp( t, "switch_section" ) == 0
           || std::strcmp( t, "switch_expression_arm" ) == 0;
}

// (cyclomatic is now counted inside the fused cc_walk / complexityOf below — one DFS computes cx AND ccx.)

// ---- cognitive complexity (SonarSource-style, AST-approximate across our 7 grammars) ----
// Differs from cyclomatic in the two ways that matter: (1) NESTING is
// penalised — a control structure costs 1 + current-nesting, so deep code scores higher; (2) a flat
// switch costs 1 (not 1-per-case), rewarding dispatch tables over deep if/else (the house style).
// else-if chains are flattened (a C-family else-if = +1, not +1+nesting). Boolean runs collapse:
// `a && b && c` = +1, `a && b || c` = +2. Reported as `ccx` (raw fact, never a gate).
// Known approximations: plain C-family `else {}` blocks aren't separately scored; recursion isn't added.
inline bool cc_isNestingControl( const char* t ) noexcept
{
    return    std::strcmp( t, "if_statement" ) == 0      || std::strcmp( t, "if_expression" ) == 0
           || std::strcmp( t, "for_statement" ) == 0     || std::strcmp( t, "for_range_loop" ) == 0
           || std::strcmp( t, "for_in_statement" ) == 0  || std::strcmp( t, "for_expression" ) == 0
           || std::strcmp( t, "while_statement" ) == 0   || std::strcmp( t, "while_expression" ) == 0
           || std::strcmp( t, "do_statement" ) == 0      || std::strcmp( t, "loop_expression" ) == 0
           || std::strcmp( t, "switch_statement" ) == 0  || std::strcmp( t, "switch_expression" ) == 0
           || std::strcmp( t, "match_expression" ) == 0
           || std::strcmp( t, "catch_clause" ) == 0      || std::strcmp( t, "except_clause" ) == 0
           || std::strcmp( t, "conditional_expression" ) == 0 || std::strcmp( t, "ternary_expression" ) == 0
           // Ruby (tree-sitter-ruby): the block control forms each open a nested body, so they raise nesting
           // AND score. `case`/`case_match` is the switch-equivalent container (flat +1, arms score via
           // isDecisionType — mirrors switch_statement). The trailing MODIFIER forms (`x if a`) have no nested
           // body and are deliberately absent here — they count as decisions only, matching the C-family model.
           || std::strcmp( t, "if" ) == 0                || std::strcmp( t, "unless" ) == 0
           || std::strcmp( t, "while" ) == 0             || std::strcmp( t, "until" ) == 0
           || std::strcmp( t, "for" ) == 0               || std::strcmp( t, "case" ) == 0
           || std::strcmp( t, "case_match" ) == 0        || std::strcmp( t, "rescue" ) == 0
           || std::strcmp( t, "conditional" ) == 0
           || std::strcmp( t, "foreach_statement" ) == 0;   // C# `foreach (var x in xs)` — a distinct loop node
           // NOTE: Ruby `elsif` is intentionally NOT here — like a C-family else-if / Python elif_clause it is a
           // flat +1 that does not deepen nesting; it is handled in the elif_clause/else_clause branch of cc_walk.
}
inline bool cc_isNestingOnly( const char* t ) noexcept   // raises nesting, scores nothing (lambdas/closures)
{
    return    std::strcmp( t, "lambda_expression" ) == 0 || std::strcmp( t, "lambda" ) == 0
           || std::strcmp( t, "closure_expression" ) == 0;
}
// the boolean-operator spelling of a node, or "" if it isn't one (&&/|| for C-family, and/or for Python)
inline std::string_view cc_boolOp( TSNode n, std::string_view src ) noexcept
{
    const TSNode op = ts_node_child_by_field_name( n, "operator", 8 );
    if( ts_node_is_null( op ) )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( op ), b = ts_node_end_byte( op );
    if( b > src.size() || b <= a )
    {
        return {};
    }
    const std::string_view o = src.substr( a, b - a );
    return ( o == "&&" || o == "||" || o == "and" || o == "or" ) ? o : std::string_view{};
}

// ── O(children) child collection for whole-subtree walks ─────────────────────────────────────────────
// ts_node_child( n, i ) restarts tree-sitter's child iterator from the FIRST child on every call, so an
// indexed loop over a node's C children costs O(C²). Width is attacker-controlled: ONE 980 KB file of
// 14 000 line comments hands the root 14 000 children and turned ingest into ~2 s of user CPU, quadratic
// in line count (gate: test/padscalecheck.sh). Every unbounded-width walk below therefore collects the
// child list ONCE per node with a TSTreeCursor — the same child set (named + anonymous + extras) in the
// same left-to-right order, O(C) total. The cursor and the out vector are caller-owned and reused across
// nodes, so a warm walk allocates nothing per node. Bounded-shape scans (base clauses, argument lists)
// keep the indexed form — their widths come from the grammar, not from the input file.
struct ChildCursor   // RAII — several walkers return mid-loop, so deletion must not depend on fallthrough
{
    TSTreeCursor cur;
    explicit ChildCursor( TSNode n ) noexcept : cur( ts_tree_cursor_new( n ) ) {}
    ChildCursor( const ChildCursor& ) = delete;
    ChildCursor& operator=( const ChildCursor& ) = delete;
    ~ChildCursor() { ts_tree_cursor_delete( &cur ); }
};
inline void collectChildren( TSNode n, TSTreeCursor& cur, std::vector<TSNode>& out )   // A4-F25: NOT noexcept — `out` allocates
{
    out.clear();
    ts_tree_cursor_reset( &cur, n );
    if( ts_tree_cursor_goto_first_child( &cur ) )
    {
        do
        {
            out.push_back( ts_tree_cursor_current_node( &cur ) );
        }
        while( ts_tree_cursor_goto_next_sibling( &cur ) );
    }
}

// bounded-depth search for a structured_binding_declarator anywhere under `n` — the vendored tree-sitter-cpp
// grammar nests it TWO levels below the `declaration` node (declaration -> init_declarator ->
// structured_binding_declarator for `auto [a,b] = …`; verified against the vendored grammar via a parse-tree
// dump, not assumed), so a same-level-only child scan misses it. `declaration` subtrees are grammar-bounded
// (a handful of children, not attacker-widenable like a comment run), so a small depth cap (not the
// cursor/stack machinery cc_walk itself uses for the whole-function walk) is the right tool here.
inline bool cc_declHasStructuredBinding( TSNode n, int depth ) noexcept
{
    if( depth <= 0 )
    {
        return false;   // pathological-AST guard — declaration subtrees never legitimately need this deep
    }
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t ci = 0; ci < childCount; ++ci )
    {
        const TSNode child = ts_node_child( n, ci );
        if( std::strcmp( ts_node_type( child ), "structured_binding_declarator" ) == 0 )
        {
            return true;
        }
        if( cc_declHasStructuredBinding( child, depth - 1 ) )
        {
            return true;
        }
    }
    return false;
}

// Phase 1 (local-variable-indexing, PLAN.md 2026-08-06 evening): is `n` a LOCAL-VARIABLE declaration
// statement that cc_walk's own fused DFS should count? `declaration` node whose PARENT is the enclosing
// `compound_statement` (a direct block-statement local) — one rule that, WITHOUT any per-shape special
// case, naturally excludes an if-init (`if(int x=f())`)/switch-condition/for-init declarator (parent is
// the control-structure node, not compound_statement) and a catch-clause exception declarator (parent is
// catch_clause; also a different node KIND — parameter_declaration, not declaration — in the vendored
// grammar). A structured-binding declarator (`auto [a,b] = …`) is excluded explicitly: it IS a direct
// compound_statement child but introduces an unknown-count of names from one node, so counting it as "1"
// would silently mis-state what the count means — the floor semantics (locals_floor=, model.h) already
// cover honest undercounting elsewhere; this is a DIFFERENT axis (miscounting), kept out on purpose.
// C/C++ ONLY (model.h localsCountedLang) — the caller gates on lang before ever reaching here.
inline bool cc_isCountableLocalDecl( TSNode n, const char* t ) noexcept
{
    if( std::strcmp( t, "declaration" ) != 0 )
    {
        return false;
    }
    const TSNode parent = ts_node_parent( n );
    if( ts_node_is_null( parent ) || std::strcmp( ts_node_type( parent ), "compound_statement" ) != 0 )
    {
        return false;
    }
    return !cc_declHasStructuredBinding( n, 4 );
}

// Every accumulator the fused walk fills, in ONE bundle. It used to be six by-reference out-parameters
// threaded through cc_walk's signature; the nesting-depth profile would have made that nine, which is the
// parameter-count smell --metrics itself reports. One struct, passed by reference, is the same code with a
// name — and the walk's own hot loop touches it exactly as before.
struct CcAccum
{
    std::uint32_t cog     = 0;   // cognitive complexity (nesting-weighted)
    std::uint32_t cyclo   = 0;   // cyclomatic decision count (cx = 1 + this)
    std::uint32_t maxNest = 0;   // deepest control nesting reached  → Symbol::maxNest
    std::uint32_t locals  = 0;   // Phase 1 local-declaration floor  → Symbol::locals
    std::uint32_t humps   = 0;   // regions reaching quality::kNestBar → Symbol::humps   (see model.h)
    std::uint32_t deepLoc = 0;   // lines inside those regions        → Symbol::deepLoc  (a FLOOR)
    std::uint32_t deepEnd = 0;   // 1-based end row of the last counted hump — the anti-double-count clamp
};

// A hump is a control-nesting region whose depth FIRST reaches quality::kNestBar. Counting it at the
// crossing is what makes the count exact: a deeper region inside an already-deep one has an ancestor chain
// that is already at or over the bar, so it cannot cross again and cannot be counted twice.
//
// `deepLoc` bills the crossing node's whole line span, control header included — the `if(` line is part of
// what a reader must hold in their head. Sibling humps are reached in document order (the DFS pushes
// children in reverse, so pops run left to right), so a hump starting on the line the previous one ended is
// clamped to start after it. The clamp can only ever SUBTRACT: if the order assumption is ever violated the
// result is an under-count, never an over-count, which is exactly why deepLoc is published as a floor.
inline void cc_noteHump( TSNode n, std::uint32_t fromNesting, std::uint32_t toNesting, CcAccum& acc ) noexcept
{
    if( fromNesting >= quality::kNestBar || toNesting < quality::kNestBar )
    {
        return;   // already deep (counted at an ancestor), or still shallow
    }
    ++acc.humps;
    const std::uint32_t startRow = ts_node_start_point( n ).row + 1u;   // tree-sitter rows are 0-based
    const std::uint32_t endRow   = ts_node_end_point( n ).row + 1u;
    const std::uint32_t from     = ( startRow > acc.deepEnd ) ? startRow : acc.deepEnd + 1u;
    if( endRow >= from )
    {
        acc.deepLoc += endRow - from + 1u;
    }
    if( endRow > acc.deepEnd )
    {
        acc.deepEnd = endRow;
    }
}

// The regions an else / elif / elsif clause contributes, noted in DOCUMENT order — and the order is the
// whole reason this is its own function rather than three lines inside the clause's push loop.
//
// cc_noteHump carries ONE high-water end row so that two regions overlapping on a line cannot bill it
// twice. That clamp is only correct when it is fed regions in document order: fed a later region first, it
// swallows the earlier one whole. This clause used to note its kids INSIDE the push loop, which runs
// BACKWARDS (children go onto a stack, so the last pushed pops first) — so the clause's BODY was billed
// before the `else` token on the line above it, and the token's line, already behind the high-water end,
// was clamped to nothing. Two regions, two DISTINCT lines, one line billed. Every other cc_noteHump call
// site notes exactly one node before descending; this clause is the only one that walks its own children,
// and so was the only one out of order.
//
// maxNest is a max and cyclo is a sum, so neither cares about order — only deepLoc does. Same regions and
// the same hump COUNT as before; only the sequence they are reported in changed. (Two regions that share a
// line still collapse to one line, correctly: deepLoc counts LINES, so a one-line `if(c){x;}else{y;}` at
// the bar is two regions on one line and `deep < humps` there is the honest answer — model.h says so, and
// test/nestprofilecheck.sh arm 11 pins both halves.)
inline void cc_noteElseRegions( const std::vector<TSNode>& kids, std::uint32_t nesting, CcAccum& acc ) noexcept
{
    for( const TSNode c : kids )
    {
        const char* ct = ts_node_type( c );
        if( std::strcmp( ct, "if_statement" ) == 0 || std::strcmp( ct, "if_expression" ) == 0 )
        {
            continue;   // C-family `else if`: not a region of its own — cc_walk descends into its children
        }
        if( nesting + 1 > acc.maxNest )
        {
            acc.maxNest = nesting + 1;   // Q4: else/elif body deepens by one
        }
        cc_noteHump( c, nesting, nesting + 1, acc );
    }
}

// A4-F25: NOT noexcept — the frame-stack vector allocates, so under memory pressure bad_alloc must be
// allowed to propagate to the per-file degrade catch, not turn into terminate().
inline void cc_walk( TSNode start, std::uint32_t startNesting, std::string_view src, CcAccum& acc, int startDepth,
                      bool countLocals )   // Phase 1: countLocals gates on lang (model.h localsCountedLang), C/C++ only
{
    // iterative pre-order DFS — an EXPLICIT frame stack, not recursion: worker threads get 512 KB stacks on
    // macOS, so a deep AST overflows the call stack well inside the depth guard. Children are pushed in
    // reverse so pops preserve the original left-to-right visit order; the guard bounds the heap stack.
    struct CcFrame { TSNode node; std::uint32_t nesting; std::uint16_t depth; };
    std::vector<CcFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { start, startNesting, static_cast<std::uint16_t>( startDepth ) } );
    ChildCursor         cursor( start );
    std::vector<TSNode> kids;       kids.reserve( 64 );
    std::vector<TSNode> elifKids;   elifKids.reserve( 64 );   // the else-if grandchild descent below nests inside a kids iteration

    while( !stack.empty() )
    {
        const CcFrame frame = stack.back();
        stack.pop_back();
        if( frame.depth > 512 )
        {
            continue; // pathological-AST guard (file size is already capped at 1 MB)
        }
        const TSNode        n          = frame.node;
        const std::uint32_t nesting    = frame.nesting;
        const std::uint16_t childDepth = static_cast<std::uint16_t>( frame.depth + 1 );
        const char*         t          = ts_node_type( n );
        // NAMED-only gate for the control/decision predicates: Ruby's tree-sitter node kinds are bare words
        // (`if`, `for`, `while`, `case`, `when`, ...) that ALSO collide with the ANONYMOUS keyword TOKENS
        // several grammars (JS/TS) emit under those exact type strings. Anonymous keyword tokens are never a
        // real control subtree root in ANY of our grammars — only their named parents are — so requiring
        // ts_node_is_named here recovers the correct Ruby nodes while keeping C-family/JS byte-identical.
        // (The boolean-operator / binary_expression paths below are deliberately NOT gated — unchanged.)
        const bool isNamed = ts_node_is_named( n );

        // cyclomatic (flat decision count) accumulated in the SAME DFS as cognitive — one walk, both metrics.
        if( isNamed && isDecisionType( t ) )
        {
            ++acc.cyclo;
        }
        // Phase 1 (local-variable-indexing): same fused DFS, third accumulator — zero extra tree-sitter
        // queries. countLocals is false for every non-C/C++ def (model.h localsCountedLang), so this whole
        // check compiles to a single branch-not-taken for every other language's walk.
        if( countLocals && isNamed && cc_isCountableLocalDecl( n, t ) )
        {
            ++acc.locals;
        }
        else if( std::strcmp( t, "binary_expression" ) == 0 )
        {
            const TSNode op = ts_node_child_by_field_name( n, "operator", 8 );
            if( !ts_node_is_null( op ) )
            {
                const std::uint32_t a = ts_node_start_byte( op ), b = ts_node_end_byte( op );
                if( b <= src.size() && b - a == 2 )
                {
                    const std::string_view o = src.substr( a, 2 );
                    if( o == "&&" || o == "||" )
                    {
                        ++acc.cyclo;
                    }
                }
            }
        }

        if( isNamed && cc_isNestingControl( t ) )
        {
            const bool   isIf = ( std::strcmp( t, "if_statement" ) == 0 || std::strcmp( t, "if_expression" ) == 0 );
            const TSNode p    = ts_node_parent( n );
            const bool   elseIf = isIf && !ts_node_is_null( p )
                                  && ( std::strcmp( ts_node_type( p ), "if_statement" ) == 0 || std::strcmp( ts_node_type( p ), "if_expression" ) == 0 );
            const std::uint32_t childNest = elseIf ? nesting : nesting + 1;   // else-if doesn't deepen
            acc.cog += elseIf ? 1u : ( 1u + nesting );                           // flat +1 for else-if, else +1+nesting
            if( childNest > acc.maxNest )
            {
                acc.maxNest = childNest; // Q4: deepest control nesting reached
            }
            cc_noteHump( n, nesting, childNest, acc );   // profile: did THIS control cross the bar?
            collectChildren( n, cursor.cur, kids );
            for( std::size_t i = kids.size(); i > 0; --i )
            {
                stack.push_back( { kids[i - 1], childNest, childDepth } );
            }
            continue;
        }
        if( isNamed && ( std::strcmp( t, "elif_clause" ) == 0 || std::strcmp( t, "else_clause" ) == 0
                         || std::strcmp( t, "elsif" ) == 0 ) )   // else / elif / else-if (+ Ruby `elsif`): flat +1 (cognitive)
        {
            acc.cog += 1u;
            collectChildren( n, cursor.cur, kids );
            cc_noteElseRegions( kids, nesting, acc );   // the PROFILE pass, FORWARD — read its note, the order is the point
            // The PUSH pass, backwards, so pops preserve left-to-right visit order — unchanged.
            for( std::size_t i = kids.size(); i > 0; --i )
            {
                const TSNode c  = kids[ i - 1 ];
                const char*  ct = ts_node_type( c );
                if( std::strcmp( ct, "if_statement" ) == 0 || std::strcmp( ct, "if_expression" ) == 0 )
                {
                    // C-family `else if`: descend into the if's CHILDREN so cognitive doesn't re-score it as a
                    // fresh control — but cyclomatic still counts that `if` as a decision (parity with the old walk).
                    ++acc.cyclo;
                    collectChildren( c, cursor.cur, elifKids );   // NOT kids — that iteration is still live
                    for( std::size_t j = elifKids.size(); j > 0; --j )
                    {
                        stack.push_back( { elifKids[j - 1], nesting, childDepth } );
                    }
                }
                else
                {
                    stack.push_back( { c, nesting + 1, childDepth } );   // else/elif body deepens by one
                }
            }
            continue;
        }
        if( cc_isNestingOnly( t ) )
        {
            if( nesting + 1 > acc.maxNest )
            {
                acc.maxNest = nesting + 1; // Q4: a lambda/closure body deepens nesting
            }
            cc_noteHump( n, nesting, nesting + 1, acc );
            collectChildren( n, cursor.cur, kids );
            for( std::size_t i = kids.size(); i > 0; --i )
            {
                stack.push_back( { kids[i - 1], nesting + 1, childDepth } );
            }
            continue;
        }
        const std::string_view bop = cc_boolOp( n, src );
        if( !bop.empty() && cc_boolOp( ts_node_parent( n ), src ) != bop )
        {
            ++acc.cog; // new boolean run (cognitive)
        }

        collectChildren( n, cursor.cur, kids );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], nesting, childDepth } );
        }
    }
}
struct Complexity { std::uint32_t cx; std::uint32_t ccx; std::uint32_t maxNest; std::uint32_t locals; std::uint32_t humps; std::uint32_t deepLoc; };
// `lang`: Phase 1 (local-variable-indexing) gates the locals accumulator to model.h's localsCountedLang
// (C/C++ only, MVP scope) INSIDE the same fused walk — every other language pays one branch-not-taken
// per node and gets locals=0, which the caller (this file, RawDef→Symbol) leaves at 0 and serialize.h
// never emits (absent, not a bare "0" — see localsCountedLang's own comment).
inline Complexity complexityOf( TSNode root, std::string_view src, Lang lang )   // one fused DFS → cx, ccx, maxNest, locals, AND the nesting profile
{                                                                     // A4-F25: NOT noexcept — cc_walk (and kids here) allocate
    CcAccum acc;
    const bool countLocals = localsCountedLang( lang );
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );
    collectChildren( root, cursor.cur, kids );              // start INSIDE the def (the def node is neither control nor decision)
    // ONE accumulator across all top-level children: the deepEnd clamp has to see the whole def in document
    // order, and humps in sibling statements are humps of the same function.
    for( const TSNode c : kids )
    {
        cc_walk( c, 0, src, acc, 0, countLocals );
    }
    // cx = 1 + decisions ; ccx = nesting-weighted cognitive ; maxNest = deepest control nesting ;
    // locals = Phase 1 floor count ; humps/deepLoc = the nesting profile (model.h Symbol).
    return { 1u + acc.cyclo, acc.cog, acc.maxNest, acc.locals, acc.humps, acc.deepLoc };
}

// ── local-variable-indexing plan, Phase 2 (PLAN.md 2026-08-06 evening) ─────────────────────────────────
//
// bounded-depth: the identifier(s) a DECLARATOR subtree ultimately names, following ONLY the grammar's
// "declarator:" field at each wrapper level (never "value:"/"size:"/"type:" — those hold an initializer
// expression / array-size expression / type qualifier, whose own identifiers are USE sites, not the local's
// own name; `int arr[n]` would otherwise wrongly harvest the USE of `n` as if it were a declared name).
// EXPLICIT allowlist of wrapper shapes, verified against the vendored grammar via a real parse-tree dump
// (not assumed — the exact same discipline Phase 1's structured-binding fix needed): init_declarator,
// pointer_declarator, array_declarator all expose a "declarator:" field; reference_declarator's inner
// identifier is an ANONYMOUS single child (no field name at all in this grammar — verified the same way).
// A node type NOT in this allowlist (e.g. a local function-pointer declarator, or anything the dump did not
// cover) is left UN-descended — silently fewer names captured is the safe floor outcome; a wrong or
// misattributed name is the failure mode this walk exists to avoid, per the WITHDRAWN naming-body-mismatch
// lesson (src/naminglens.h's own note): reasoning-only "this shape probably parses like X" is exactly what
// shipped wrong there.
inline void ln_extractDeclaratorIdentifiers( TSNode node, std::vector<TSNode>& outIdents, int depth ) noexcept
{
    if( depth <= 0 )
    {
        return;   // pathological-AST guard — real declarator nesting never legitimately needs this deep
    }
    const char* t = ts_node_type( node );
    if( std::strcmp( t, "identifier" ) == 0 || std::strcmp( t, "field_identifier" ) == 0 )
    {
        outIdents.push_back( node );
        return;
    }
    if( std::strcmp( t, "reference_declarator" ) == 0 )
    {
        const std::uint32_t n = ts_node_child_count( node );
        for( std::uint32_t i = 0; i < n; ++i )
        {
            ln_extractDeclaratorIdentifiers( ts_node_child( node, i ), outIdents, depth - 1 );
        }
        return;
    }
    if( std::strcmp( t, "init_declarator" ) == 0 || std::strcmp( t, "pointer_declarator" ) == 0 || std::strcmp( t, "array_declarator" ) == 0 )
    {
        const std::uint32_t n = ts_node_child_count( node );
        for( std::uint32_t i = 0; i < n; ++i )
        {
            const char* fieldName = ts_node_field_name_for_child( node, i );
            if( fieldName != nullptr && std::strcmp( fieldName, "declarator" ) == 0 )
            {
                ln_extractDeclaratorIdentifiers( ts_node_child( node, i ), outIdents, depth - 1 );
            }
        }
        return;
    }
    // unrecognized wrapper (incl. structured_binding_declarator, which should never reach here — Phase 1's
    // cc_isCountableLocalDecl already excludes any `declaration` containing one before this ever runs):
    // do not descend.
}

// one `declaration` node (already proven countable by cc_isCountableLocalDecl) → every declarator name it
// introduces (plural: `int a, b;` is ONE declaration with TWO "declarator:"-fielded children — Phase 1's
// COUNT stays "1 declaration-statement" by design, but Phase 2 needs each NAME individually to judge, so
// this deliberately extracts more granularly than Phase 1 counts — a disclosed, documented difference
// between the two phases, not a drift).
inline void ln_declaratorIdentifiers( TSNode declNode, std::vector<TSNode>& outIdents )
{
    const std::uint32_t n = ts_node_child_count( declNode );
    for( std::uint32_t i = 0; i < n; ++i )
    {
        const char* fieldName = ts_node_field_name_for_child( declNode, i );
        if( fieldName != nullptr && std::strcmp( fieldName, "declarator" ) == 0 )
        {
            ln_extractDeclaratorIdentifiers( ts_node_child( declNode, i ), outIdents, 6 );
        }
    }
}

// declDepth: count of `compound_statement` ancestors from `declNode` up to and including the function's
// OWN outermost body block (stops at `funcRoot`, the re-parsed def's root node) — so a direct top-level
// local gets declDepth=1, and a local one control-structure block deeper gets declDepth=2+, matching
// checkLocalNameShape's own declDepth>=2 gate (naminglens.h) exactly.
inline std::uint8_t ln_declDepth( TSNode declNode, TSNode funcRoot ) noexcept
{
    std::uint8_t depth = 0;
    TSNode       cur   = ts_node_parent( declNode );
    while( !ts_node_is_null( cur ) )
    {
        if( std::strcmp( ts_node_type( cur ), "compound_statement" ) == 0 )
        {
            ++depth;
            if( depth == 255 )
            {
                break;   // pathological-AST guard — matches the declDepth field's own uint8_t width
            }
        }
        if( ts_node_eq( cur, funcRoot ) )
        {
            break;
        }
        cur = ts_node_parent( cur );
    }
    return depth;
}

// bounded-width recursive descent over the WHOLE re-parsed def subtree, collecting every countable local
// declaration's name(s) — reuses cc_isCountableLocalDecl/cc_declHasStructuredBinding UNCHANGED, so the SET
// of declarations this walk visits is provably the same set Phase 1's `locals=` count already covers (no
// second, silently divergent detection rule). NOT the cursor/stack machinery cc_walk uses for a whole-
// function hot-path walk — this only ever runs on an ALREADY-GATED (rare) function, so a plain recursive
// walk (bounded by the same depth guard) is the right tool, not premature machinery.
inline void ln_collectLocalDecls( TSNode node, TSNode funcRoot, int depth, std::vector<LocalNameFact>& out,
                                   std::uint32_t defStartLine, std::string_view defBytes )
{
    if( depth <= 0 )
    {
        return;   // pathological-AST guard (mirrors cc_walk's own 512-frame guard, scaled to plain recursion)
    }
    const char* t = ts_node_type( node );
    if( ts_node_is_named( node ) && cc_isCountableLocalDecl( node, t ) )
    {
        std::vector<TSNode> idents;
        ln_declaratorIdentifiers( node, idents );
        const std::uint8_t declDepth = ln_declDepth( node, funcRoot );
        for( const TSNode& id : idents )
        {
            const std::uint32_t startByte = ts_node_start_byte( id );
            const std::uint32_t endByte   = std::min( ts_node_end_byte( id ), std::uint32_t( defBytes.size() ) );
            if( endByte <= startByte )
            {
                continue;
            }
            // row is relative to the RE-PARSED SUBSTRING (starts at row 0 = defStartLine); absolute file
            // line = defStartLine + row, so a caller never has to know this function re-parses in isolation.
            const std::uint32_t row = ts_node_start_point( id ).row;
            LocalNameFact        fact;
            fact.line      = defStartLine + row;
            fact.declDepth = declDepth;
            fact.name.assign( defBytes.substr( startByte, endByte - startByte ) );
            out.push_back( std::move( fact ) );
        }
        return;   // do not descend INTO a countable declaration's own subtree again (nothing further to find)
    }
    const std::uint32_t n = ts_node_child_count( node );
    for( std::uint32_t i = 0; i < n; ++i )
    {
        ln_collectLocalDecls( ts_node_child( node, i ), funcRoot, depth - 1, out, defStartLine, defBytes );
    }
}

// collectGatedLocalNames itself (the ingest.h-declared, EXTERNAL-linkage entry point) is defined further
// down, OUTSIDE this anonymous namespace — same split as ingest()/unreachableCheck() in this same file:
// an anonymous-namespace definition would give it INTERNAL linkage, which cannot satisfy ingest.h's
// declaration. The ln_* helpers above stay in here (internal-only, next to cc_walk/complexityOf which they
// mirror) and remain visible to that later definition, exactly like ingest()/unreachableCheck() already
// call plenty of anonymous-namespace-scoped helpers from outside the namespace block in this same TU.

// Q4 PARAMETER COUNT: find the def's parameter-list node and count its formal parameters. Parameter-list
// node types across our 7 grammars: C++/ObjC `parameter_list`, Python/TS `parameters`/`formal_parameters`,
// Go `parameter_list`, Rust `parameters`, Swift `parameter_clause`/`parameters`. The list is not always a
// direct child of the def node (C++ wraps it in a function_declarator), so we do a bounded pre-order search
// for the FIRST such list within the def subtree, then count its named parameter children (commas/parens are
// anonymous nodes and are skipped by ts_node_is_named). Deterministic + allocation-free. Reported as a raw
// NUMBER on --metrics (never a 7±2 threshold — that myth is debunked, §1d kill-list).
inline bool cc_isParamList( const char* t ) noexcept
{
    return    std::strcmp( t, "parameter_list" )   == 0     // C++/ObjC/Go
           || std::strcmp( t, "parameters" )       == 0     // Python / Rust / Swift
           || std::strcmp( t, "formal_parameters" )== 0     // TypeScript / JS
           || std::strcmp( t, "parameter_clause" ) == 0     // Swift
           || std::strcmp( t, "method_parameters" )== 0     // Ruby `def f(a, b)`
           || std::strcmp( t, "block_parameters" ) == 0     // Ruby `{ |x, y| ... }`
           || std::strcmp( t, "lambda_parameters" )== 0;    // Ruby `->(n) { ... }`
}
// a named parameter node (skip `self`/`this`-only? no — count as written, deterministic). Anonymous separators
// (',', '(', ')') are unnamed → excluded by ts_node_is_named.
inline std::uint16_t countParams( TSNode defNode )   // A4-F25: NOT noexcept — allocates (see cc_walk)
{
    // bounded pre-order search for the FIRST parameter list inside the def; then count its named children.
    struct PF { TSNode n; std::uint16_t depth; };
    std::vector<PF> stack;
    stack.reserve( 32 );
    stack.push_back( { defNode, 0 } );
    ChildCursor         cursor( defNode );
    std::vector<TSNode> kids;
    kids.reserve( 32 );
    while( !stack.empty() )
    {
        const PF f = stack.back();
        stack.pop_back();
        if( f.depth > 12 )
        {
            continue; // params live near the signature; bound the search
        }
        const char* t = ts_node_type( f.n );
        collectChildren( f.n, cursor.cur, kids );           // one collection serves both arms below
        if( f.n.id != defNode.id && cc_isParamList( t ) )   // don't treat the def node itself as a param list
        {
            std::uint16_t count = 0;
            for( const TSNode c : kids )
            {
                if( !ts_node_is_named( c ) )
                {
                    continue; // skip '(', ')', ',' separators
                }
                const char* ct = ts_node_type( c );
                if( std::strcmp( ct, "comment" ) == 0 )
                {
                    continue; // a comment inside the list is not a parameter
                }
                ++count;
            }
            return count;
        }
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], std::uint16_t( f.depth + 1 ) } );
        }
    }
    return 0;
}

// B2.2 CALL-COMPARABLE ARITY: is `params` a FIXED arity that can be compared 1:1 against a call site's
// positional-argument count? True ONLY when EVERY qualifying condition holds, so the safe default (any
// uncertainty) is FALSE → the resolver never arity-filters that candidate (zero false negatives). Conditions:
//   * the language is one whose method params do NOT include an implicit receiver AND whose default/variadic
//     forms we can positively detect (C++/Java/Swift/TS/JS). Python is filterable for FREE FUNCTIONS only —
//     a Python/Ruby METHOD lists `self`/`cls`, which the call site omits, so a naive count is off by one.
//   * the def actually HAS a parameter-list node (an empty `()` counts — a real 0-arity), and
//   * that list contains NO variadic (`...`, `*args`/`**kwargs`, Java `...`, rest `...x`) and NO defaulted /
//     optional parameter (`= v`, TS `x?`) — any of which makes the accepted arity a RANGE, not a point.
// A bounded pre-order scan of the FIRST parameter list mirrors countParams; deterministic + allocation-free.
//
// Residual conservative gap (honest): a C++ default argument written ONLY on a separate PROTOTYPE
// (`void f( int x = 5 );` in a header) and NOT on the definition (`void f( int x ){…}`) is invisible here —
// the definition's parameter shows no default. byName resolves a call to the DEFINITION, so such a candidate
// reads as a fixed arity==params. This is a source-visibility limit (the default lives on an uncaptured
// decl), not a logic bug; it can only bite when ≥2 same-name overloads are same-file/dir AND the true target
// relies on a header-only default. Whenever the default IS on the definition (the common case) the arity is
// correctly treated as elastic and the candidate is never filtered.
//
// Decided: graph.h's arity filter only excludes on `argCount > params`, so
// this residual gap can no longer drop the correct edge for an (params-1)-arg call — the header-default def
// stays a candidate and correctly re-enters amb= when a sibling overload survives too. The gap is now
// strictly a precision (not honesty) limit: a too-many-args call still provably excludes on the def's
// visible arity regardless of where a default lives, which is sound in every language.
inline bool cc_paramArityExact( TSNode defNode, Lang lang, SymKind kind ) noexcept
{
    // language / kind gate — see the header. Only these emit a filterable point arity.
    const bool langOk =    lang == Lang::Cpp || lang == Lang::Java || lang == Lang::Swift
                        || lang == Lang::TypeScript || lang == Lang::JavaScript || lang == Lang::Python;
    if( !langOk )
    {
        return false;
    }
    if( ( lang == Lang::Python || lang == Lang::Ruby ) && kind == SymKind::Method )
    {
        return false; // implicit self/cls
    }

    // an "elastic" (variadic / default / optional) node kind or token makes the arity a RANGE → not filterable.
    const auto isElastic = []( const char* t ) noexcept
    {
        return    std::strstr( t, "variadic" ) != nullptr || std::strstr( t, "splat" )   != nullptr
               || std::strstr( t, "spread" )   != nullptr || std::strstr( t, "optional" )!= nullptr
               || std::strstr( t, "default" )  != nullptr || std::strcmp( t, "rest_pattern" ) == 0
               || std::strcmp( t, "..." ) == 0 || std::strcmp( t, "=" ) == 0;
    };

    struct PF { TSNode n; std::uint16_t depth; };
    std::vector<PF> stack;
    stack.reserve( 32 );
    stack.push_back( { defNode, 0 } );
    ChildCursor         cursor( defNode );
    std::vector<TSNode> kids;
    kids.reserve( 32 );
    while( !stack.empty() )
    {
        const PF f = stack.back();
        stack.pop_back();
        if( f.depth > 12 )
        {
            continue;
        }
        const char* t = ts_node_type( f.n );
        if( f.n.id != defNode.id && cc_isParamList( t ) )       // the FIRST parameter list — scan it for elastic forms
        {
            struct QF { TSNode n; std::uint16_t depth; };
            std::vector<QF> q;
            q.reserve( 32 );
            q.push_back( { f.n, 0 } );
            while( !q.empty() )                                 // never returns to the outer loop → reusing kids below is safe
            {
                const QF g = q.back();
                q.pop_back();
                if( g.depth > 6 )
                {
                    continue; // param forms live shallow inside the list
                }
                if( g.n.id != f.n.id && isElastic( ts_node_type( g.n ) ) )
                {
                    return false;
                }
                collectChildren( g.n, cursor.cur, kids );
                for( const TSNode c : kids )
                {
                    q.push_back( { c, std::uint16_t( g.depth + 1 ) } );
                }
            }
            return true;                                        // a real parameter list, no elastic form → fixed arity
        }
        collectChildren( f.n, cursor.cur, kids );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], std::uint16_t( f.depth + 1 ) } );
        }
    }
    return false;   // no parameter-list node found at all → can't be sure → not filterable (safe)
}

// B2.2 CALL-SITE ARITY: count the positional arguments of the call whose callee identifier is `nameNode`.
// Returns { argCount, known }. `known` is true ONLY when a recognized call node + argument container is
// found for a supported language AND no spread/splat/apply argument is present (which would make the count
// unreliable). Any uncertainty → { 0, false } so the resolver never arity-filters that call (zero false
// negatives). Pure-syntactic, deterministic, allocation-free. Languages: C++/Python/TS/JS/Java/Swift/C#.
inline std::pair<std::uint16_t, bool> callArity( TSNode nameNode, Lang lang, std::string_view /*src*/ ) noexcept
{
    // walk up a bounded number of parents to the enclosing CALL node (the callee sits 1-2 levels below it).
    TSNode call{};
    bool   found = false;
    TSNode n = nameNode;
    for( int hop = 0; hop < 4 && !ts_node_is_null( n ); ++hop )
    {
        const TSNode p = ts_node_parent( n );
        if( ts_node_is_null( p ) )
        {
            break;
        }
        const char* pt = ts_node_type( p );
        if(    std::strcmp( pt, "call_expression" )       == 0     // C++/TS/JS/Swift
            || std::strcmp( pt, "call" )                  == 0     // Python
            || std::strcmp( pt, "method_invocation" )     == 0     // Java
            || std::strcmp( pt, "invocation_expression" ) == 0 )   // C#
        { call = p; found = true; break; }
        n = p;
    }
    if( !found )
    {
        return { 0, false };
    }

    // find the argument container: the `arguments` field, else the first child of a known list type.
    TSNode args = ts_node_child_by_field_name( call, "arguments", 9 );
    if( ts_node_is_null( args ) )
    {
        const std::uint32_t cc = ts_node_child_count( call );
        for( std::uint32_t i = 0; i < cc; ++i )
        {
            const TSNode c = ts_node_child( call, i );
            const char* ct = ts_node_type( c );
            if(    std::strcmp( ct, "argument_list" )  == 0 || std::strcmp( ct, "arguments" ) == 0
                || std::strcmp( ct, "value_arguments" )== 0 )     // Swift
            { args = c; break; }
        }
    }
    if( ts_node_is_null( args ) )
    {
        return { 0, false };
    }

    // count NAMED argument children; a spread / splat / apply argument makes the count unreliable → not known.
    std::uint16_t count = 0;
    const std::uint32_t an = ts_node_child_count( args );
    for( std::uint32_t i = 0; i < an; ++i )
    {
        const TSNode c = ts_node_child( args, i );
        if( !ts_node_is_named( c ) )
        {
            continue; // skip '(' ')' ',' separators
        }
        const char* ct = ts_node_type( c );
        if( std::strcmp( ct, "comment" ) == 0 )
        {
            continue;
        }
        if( std::strstr( ct, "splat" ) != nullptr || std::strstr( ct, "spread" ) != nullptr || std::strcmp( ct, "..." ) == 0 )
        {
            return { 0, false };                                  // `f(*args)` / `f(...xs)` → unreliable
        }
        ++count;
    }
    (void)lang;
    return { count, true };
}

// One parser, reused across files (single-threaded). Language set per file.
struct ParserGuard
{
    TSParser* p = ts_parser_new();
    ~ParserGuard()
    {
        if( p )
        {
            ts_parser_delete( p );
        }
    }
};

// Verify the grammar's ABI is in range for the linked core. v0.26.9 renamed the
// accessor to ts_language_abi_version; the [MIN_COMPATIBLE, LANGUAGE_VERSION] band is unchanged.
bool grammarAbiOk( const TSLanguage* lang ) noexcept
{
    const uint32_t v = ts_language_abi_version( lang );
    return v >= TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION && v <= TREE_SITTER_LANGUAGE_VERSION;
}

// A base/derived TYPE node in a base clause (the name a derived class names). Declarative table over
// the grammar node kinds we accept as a type reference — matches how byName keys symbols (final segment).
inline bool isBaseTypeNode( const char* nt ) noexcept
{
    static const char* const kBaseTypeKinds[] = {
        "type_identifier",        // C++/TS/Java class or interface name
        "identifier",             // TS `extends Foo` (JS grammar uses identifier), Python base
        "qualified_identifier",   // C++ A::Base
        "scoped_type_identifier", // C++/Rust A::Base
        "user_type",              // Swift base/protocol type
        "generic_type",           // Java/TS `implements List<T>` — final segment is still the raw name
        "generic_name",           // C# `class Foo : IList<T>` — final segment is still the raw name
        "qualified_name",         // C# `class Foo : Ns.Base` — dotted base/interface name
    };
    for( const char* k : kBaseTypeKinds )
    {
        if( std::strcmp( nt, k ) == 0 )
        {
            return true;
        }
    }
    return false;
}

// Emit one inherit RawRef (derived → base) for a base-type node. startByte sits inside the class header
// (the type node's own start), so the byte-span enclosing attribution binds fromSymbol = the derived class.
inline void emitBaseRef( TSNode typeNode, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<RawRef>& refs )
{
    const uint32_t a = ts_node_start_byte( typeNode ), b = ts_node_end_byte( typeNode );
    if( a >= b || b > src.size() )
    {
        return;
    }
    RawRef r;
    r.fileId    = fileId;
    r.startByte = a;                       // inside the class header → attributes to the derived class
    r.line      = ts_node_start_point( typeNode ).row + 1;   // ABS-3: 1-based use-site line for --uses
    r.lang      = lang;
    r.isInherit = true;
    r.role      = RefRole::Extends;        // ABS-3: a base-class / interface use-site (derived → base)
    r.name      = finalSegment( src.substr( a, b - a ) );
    refs.push_back( std::move( r ) );
}

// Capture base classes for the inheritance/Lego view: walk a class node's base clause and emit an
// inherit RawRef per base (derived → base). startByte sits inside the class header, so the enclosing
// attribution assigns fromSymbol = the derived class. Explicit-syntax langs: C++/TS/JS/Java/Python/Swift/C#.
//
// The base type can sit at one of two depths under the class node (measured against the vendored grammars):
//   DIRECT  — a type node is an immediate child of the clause:
//               C++ base_class_clause → type_identifier ; Swift inheritance_specifier → user_type ;
//               Java superclass → type_identifier ; Python superclasses/argument_list → identifier ;
//               C# base_list → identifier/generic_name/qualified_name (`class Foo : Base, IBar`)
//   WRAPPED — the clause holds a wrapper that in turn holds the type node(s):
//               TS class_heritage → {extends_clause,implements_clause} → (type_)identifier
//               Java super_interfaces → type_list → type_identifier
//               C# base_list → primary_constructor_base_type → (its `type` field child) — a record's
//               base with constructor args (`record Foo(int X) : Base(X)`)
// So after matching a clause we scan its children for type nodes AND recurse one level into any wrapper
// child, collecting type nodes at both depths (Rust is a separate pass — impl Trait for T is a sibling).
void captureBases( TSNode classNode, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<RawRef>& refs )
{
    const uint32_t cc = ts_node_child_count( classNode );
    for( uint32_t i = 0; i < cc; ++i )
    {
        const TSNode clause = ts_node_child( classNode, i );
        const char*  ct     = ts_node_type( clause );
        const bool   isClause =    std::strcmp( ct, "base_class_clause" ) == 0     // C++    : public Base
                                || std::strcmp( ct, "class_heritage" ) == 0        // TS/JS  extends / implements (wraps clauses)
                                || std::strcmp( ct, "superclasses" ) == 0          // Python class X(Base):   (field)
                                || std::strcmp( ct, "argument_list" ) == 0         // Python bases
                                || std::strcmp( ct, "superclass" ) == 0            // Java   extends Base
                                || std::strcmp( ct, "super_interfaces" ) == 0      // Java   implements I, J   (wraps type_list)
                                || std::strcmp( ct, "inheritance_specifier" ) == 0 // Swift  : Protocol
                                || std::strcmp( ct, "base_list" ) == 0;            // C#     : Base, IBar
        if( !isClause )
        {
            continue;
        }

        const uint32_t bc = ts_node_child_count( clause );
        for( uint32_t j = 0; j < bc; ++j )
        {
            const TSNode bn = ts_node_child( clause, j );
            const char*  bt = ts_node_type( bn );
            if( isBaseTypeNode( bt ) )                 // DIRECT: type node right under the clause
            {
                emitBaseRef( bn, fileId, lang, src, refs );
                continue;
            }
            // WRAPPED: descend ONE level into a wrapper (extends_clause / implements_clause / type_list)
            // and emit each type node it holds. One level is enough for every measured grammar shape.
            const uint32_t wc = ts_node_child_count( bn );
            for( uint32_t w = 0; w < wc; ++w )
            {
                const TSNode wn = ts_node_child( bn, w );
                if( isBaseTypeNode( ts_node_type( wn ) ) )
                {
                    emitBaseRef( wn, fileId, lang, src, refs );
                }
            }
        }
    }
}

// Rust inheritance capture (separate pass — different shape). `impl Trait for T { … }` is a top-level
// `impl_item` SIBLING of `struct T;`, NOT a child of the struct node, so the class-node walk above cannot
// see it. We scan every impl_item for one carrying BOTH a `trait:` field (the interface) and a `type:`
// field (the implementor), then emit an inherit RawRef whose name = the trait's final segment and whose
// DERIVED type name is stashed in `qualifier` — because the impl block lives OUTSIDE the struct's def
// span, byte-span attribution cannot bind fromSymbol = T; buildGraph resolves `qualifier` by name instead.
// `impl T { … }` (inherent, no trait) is skipped. Recurses so `impl`s nested in `mod {}` are still seen.
void captureRustImpls( TSNode root, std::uint32_t fileId, std::string_view src, std::vector<RawRef>& refs )
{
    // iterative pre-order DFS (reverse-push preserves the recursive version's left-to-right emission
    // order) — the old recursion was both stack-overflow-prone on deep ASTs and O(children²) per node.
    std::vector<TSNode> stack;
    stack.reserve( 64 );
    stack.push_back( root );
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );
    while( !stack.empty() )
    {
    const TSNode node = stack.back();
    stack.pop_back();
    if( std::strcmp( ts_node_type( node ), "impl_item" ) == 0 )
    {
        const TSNode traitNode = ts_node_child_by_field_name( node, "trait", 5 );
        const TSNode typeNode  = ts_node_child_by_field_name( node, "type",  4 );
        if( !ts_node_is_null( traitNode ) && !ts_node_is_null( typeNode ) )
        {
            const uint32_t ta = ts_node_start_byte( traitNode ), tb = ts_node_end_byte( traitNode );
            const uint32_t da = ts_node_start_byte( typeNode ),  db = ts_node_end_byte( typeNode );
            if( ta < tb && tb <= src.size() && da < db && db <= src.size() )
            {
                RawRef r;
                r.fileId    = fileId;
                r.startByte = ta;                       // inside the impl header (file-scope; fromSymbol resolves via qualifier)
                r.line      = ts_node_start_point( traitNode ).row + 1;
                r.lang      = Lang::Rust;
                r.isInherit = true;
                r.role      = RefRole::Extends;
                r.name      = finalSegment( src.substr( ta, tb - ta ) );   // the TRAIT (base) name
                r.qualifier = finalSegment( src.substr( da, db - da ) );   // the DERIVED type name (Car/Bike) — resolved by name in buildGraph
                refs.push_back( std::move( r ) );
            }
        }
    }
    collectChildren( node, cursor.cur, kids );
    for( std::size_t i = kids.size(); i > 0; --i )
    {
        stack.push_back( kids[ i - 1 ] );
    }
    }
}

// S5-E HAS-A composition edges: walk a class/struct node's field_declaration_list and emit a
// compose RawRef for each typed member variable whose type name matches a known class/struct name.
// Two sub-relations:
//   "creates" — the member is stored BY VALUE (SpherePool m_pool;) — the owner constructs it inline.
//   "uses"    — the member is a REFERENCE or POINTER (SoundEngine& m_sound; Foo* p;) — injected dep.
// These edges carry isCompose=true and are NEVER inserted into the call graph CSR; they live only in
// Graph::composeEdges for the <compose> block in --for and --around. C++ only (priority per PLAN).
void captureFields( TSNode classNode, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<RawRef>& refs )
{
    if( lang != Lang::Cpp )
    {
        return; // C++ only for S5-E; extend for Python/TS later
    }

    ChildCursor         cursor( classNode );
    std::vector<TSNode> kids;       kids.reserve( 32 );
    std::vector<TSNode> fieldKids;                       // the body's member list — width is file-controlled (comments!)
    collectChildren( classNode, cursor.cur, kids );
    for( const TSNode child : kids )
    {
        const char* ct = ts_node_type( child );

        // C++ class body is under field_declaration_list
        if( std::strcmp( ct, "field_declaration_list" ) != 0 )
        {
            continue;
        }

        collectChildren( child, cursor.cur, fieldKids );
        for( const TSNode fdecl : fieldKids )
        {
            if( std::strcmp( ts_node_type( fdecl ), "field_declaration" ) != 0 )
            {
                continue;
            }

            // The "type" field of a field_declaration. We look for:
            //   type_identifier — a plain class name (SpherePool)
            //   type_descriptor — a reference/pointer type containing a type_identifier
            // We consider type_identifier directly under type= as the declared type.
            const TSNode typeNode = ts_node_child_by_field_name( fdecl, "type", 4 );
            if( ts_node_is_null( typeNode ) )
            {
                continue;
            }

            const char* tnType = ts_node_type( typeNode );

            // Determine the type name and whether this is a reference/pointer (uses) or value (creates).
            std::string typeName;
            bool isRefOrPtr = false;   // reference (&) or pointer (*) → "uses"; else "creates"

            if( std::strcmp( tnType, "type_identifier" ) == 0 )
            {
                // `SpherePool m_pool;` — plain value member
                const uint32_t ta = ts_node_start_byte( typeNode ), tb = ts_node_end_byte( typeNode );
                if( ta >= tb || tb > src.size() )
                {
                    continue;
                }
                typeName = std::string( src.substr( ta, tb - ta ) );
                isRefOrPtr = false;
            }
            else if(    std::strcmp( tnType, "reference_declarator" ) == 0
                     || std::strcmp( tnType, "pointer_declarator" ) == 0 )
            {
                // The grammar sometimes puts a reference/pointer declarator AT the type level when there
                // is no explicit separate type node. Look for an identifier child.
                // In practice tree-sitter-cpp puts the ref/ptr in the "declarator" field, not "type".
                // This branch covers unusual parses; the main path is via the declarator below.
                continue;
            }
            else
            {
                // Not a plain type_identifier type — could be template, qualified, etc.
                // Walk the type node's children looking for the innermost type_identifier.
                bool found = false;
                const uint32_t tc2 = ts_node_child_count( typeNode );
                for( uint32_t k = 0; k < tc2 && !found; ++k )
                {
                    const TSNode tc3 = ts_node_child( typeNode, k );
                    if( std::strcmp( ts_node_type( tc3 ), "type_identifier" ) == 0 )
                    {
                        const uint32_t ta = ts_node_start_byte( tc3 ), tb = ts_node_end_byte( tc3 );
                        if( ta < tb && tb <= src.size() ) { typeName = std::string( src.substr( ta, tb - ta ) ); found = true; }
                    }
                }
                if( !found )
                {
                    continue;
                }
                // If the type node is type_specifier or similar, presume value unless declarator says otherwise.
                isRefOrPtr = false;
            }

            if( typeName.empty() )
            {
                continue;
            }

            // Now find the declarator field to extract the member name and confirm reference/pointer.
            // A C++ field_declaration declarator may be:
            //   field_identifier                       — plain value field: `SpherePool m_pool;`
            //   reference_declarator > field_identifier — reference field: `SoundEngine& m_sound;`
            //   pointer_declarator   > field_identifier — pointer field:   `Foo* m_foo;`
            const TSNode decl = ts_node_child_by_field_name( fdecl, "declarator", 10 );
            if( ts_node_is_null( decl ) )
            {
                continue;
            }

            const char* dt = ts_node_type( decl );

            std::string fieldName;
            bool        declIsRefOrPtr = false;

            if( std::strcmp( dt, "field_identifier" ) == 0 )
            {
                // plain value member
                const uint32_t da = ts_node_start_byte( decl ), db = ts_node_end_byte( decl );
                if( da >= db || db > src.size() )
                {
                    continue;
                }
                fieldName = std::string( src.substr( da, db - da ) );
                declIsRefOrPtr = false;
            }
            else if( std::strcmp( dt, "reference_declarator" ) == 0 || std::strcmp( dt, "pointer_declarator" ) == 0 )
            {
                declIsRefOrPtr = true;
                // Walk the declarator's children to find the field_identifier
                const uint32_t dc = ts_node_child_count( decl );
                for( uint32_t k = 0; k < dc; ++k )
                {
                    const TSNode dchild = ts_node_child( decl, k );
                    if( std::strcmp( ts_node_type( dchild ), "field_identifier" ) == 0 )
                    {
                        const uint32_t da = ts_node_start_byte( dchild ), db = ts_node_end_byte( dchild );
                        if( da < db && db <= src.size() ) { fieldName = std::string( src.substr( da, db - da ) ); break; }
                    }
                }
            }
            else
            {
                // E.g. init_declarator, abstract_declarator, etc. — skip for now.
                continue;
            }

            if( fieldName.empty() )
            {
                continue;
            }

            // Build the compose RawRef. startByte is set to the start of the field_declaration so the
            // enclosing symbol attribution puts fromSymbol = the containing class (same logic as captureBases).
            RawRef r;
            r.fileId     = fileId;
            r.startByte  = ts_node_start_byte( fdecl );
            r.lang       = lang;
            r.isCompose  = true;
            r.name       = typeName;        // the member-type name (SpherePool, SoundEngine, ...)
            r.fieldName  = std::move( fieldName );
            r.composeRel = ( isRefOrPtr || declIsRefOrPtr ) ? "uses" : "creates";
            refs.push_back( std::move( r ) );
        }
    }
}

// ABS-3: the importable NAME of an include/import target (final path segment, extension stripped). For a
// C++ `#include "dir/geometry.h"` → "geometry"; `<vector>` → "vector"; a `from pkg import x` target keeps
// its first identifier-ish run. Lets `--uses=geometry` surface the include site of geometry.h/.cpp.
inline std::string importName( std::string_view target )
{
    // take the last path segment (after the final '/'), then drop a trailing extension.
    const std::size_t sl = target.rfind( '/' );
    std::string_view  seg = ( sl == std::string_view::npos ) ? target : target.substr( sl + 1 );
    const std::size_t dot = seg.rfind( '.' );
    if( dot != std::string_view::npos && dot > 0 )
    {
        seg = seg.substr( 0, dot ); // strip ".h"/".hpp"/… (not a leading dot)
    }
    // keep only a leading identifier run (Python `pkg import x`, Rust `a::b` etc. → first token / segment)
    std::size_t e = 0;
    while( e < seg.size() && ( ( seg[e] >= 'A' && seg[e] <= 'Z' ) || ( seg[e] >= 'a' && seg[e] <= 'z' ) || ( seg[e] >= '0' && seg[e] <= '9' ) || seg[e] == '_' ) )
    {
        ++e;
    }
    return std::string( seg.substr( 0, e ) );
}

// LEVER-B B0: the clean written specifier of one import node, for path-precise resolution. Returns the
// node's source text — but for a TS/JS `string` specifier (`'./x'` / `"./x"`) strips the surrounding
// quote delimiters so the resolver gets `./x`, exactly as the C-family path strips `"`/`<`. A Python
// `dotted_name` (`pkg.mod`) / `relative_import` (`.rel`) / Rust `scoped_identifier` (`crate::a::b`) carry
// no quotes → returned verbatim. Determinism: a pure function of the node span + source bytes.
inline std::string importSpecifierText( TSNode node, std::string_view src )
{
    const uint32_t a = ts_node_start_byte( node ), b = ts_node_end_byte( node );
    if( a >= b || b > src.size() )
    {
        return {};
    }
    std::string_view s = src.substr( a, b - a );

    // TS/JS specifier is a `string` node whose text includes the quote delimiters; strip exactly one pair.
    if( std::strcmp( ts_node_type( node ), "string" ) == 0 && s.size() >= 2 && ( s.front() == '\'' || s.front() == '"' ) && s.back() == s.front() )
    {
        s = s.substr( 1, s.size() - 2 );
    }

    return std::string( s );
}

// C# `using Foo.Bar;` / `using static Foo;` / `using X = Foo.Bar;` target extraction, factored out of
// captureIncludes (kept as its own def to hold captureIncludes' own complexity/LOC down — one AST shape
// per language stays a one-line call at the use site, matching the existing per-branch grain there).
//
// C# namespaces do not map 1:1 onto files (unlike a Python module or a Rust `mod`), so — same as Go/
// Swift below — this is captured for --uses/--deps visibility only; resolve.h's Rule 3 precise-import
// narrower (includeLangOf) has no C# entry and DEFERS (kNoFile), matching Java's existing "Other"
// treatment: the conservative fall-through the P2-D Rule 3 contract requires.
//
// The ALIAS form `using X = Foo.Bar;` exposes a `name` field, but it names the ALIAS (`X`), not the
// aliased type — walk the `type` field instead so the target is the real aliased spelling. The plain/
// `static` form (`using Foo.Bar;` / `using static Foo;`) has NO named field at all: the grammar's
// `$._name` production is hidden-inlined, so its resolved concrete node (a qualified_name for a dotted
// path, else a bare identifier/generic_name) is just an unnamed-field child of using_directive — scan
// for the first one.
inline std::string csharpUsingTarget( TSNode usingNode, std::string_view src )
{
    if( const TSNode aliasType = ts_node_child_by_field_name( usingNode, "type", 4 ); !ts_node_is_null( aliasType ) )
    {
        return importSpecifierText( aliasType, src );
    }

    const uint32_t cc = ts_node_child_count( usingNode );
    for( uint32_t k = 0; k < cc; ++k )
    {
        const TSNode c = ts_node_child( usingNode, k );
        if( !ts_node_is_named( c ) )
        {
            continue;
        }
        const char* ct = ts_node_type( c );
        if( std::strcmp( ct, "qualified_name" ) == 0 || std::strcmp( ct, "identifier" ) == 0 || std::strcmp( ct, "generic_name" ) == 0 || std::strcmp( ct, "alias_qualified_name" ) == 0 )
        {
            return importSpecifierText( c, src );
        }
    }
    return {};
}

// The bare header path inside a C-family include spelling: `"dir/x.h"` / `<dir/x.h>` → `dir/x.h`, with
// isAngleOut set from the delimiter BEFORE it is stripped (angle = external ⇒ path-precise resolution
// leaves it unresolved). Shared by the two C-family spellings so they can never drift apart:
//   * `#include` — preproc_include's `path` field, which is EXACTLY the delimited token;
//   * `#import`  — preproc_call's `argument` field, a preproc_arg that runs to end-of-line and so can
//     carry a trailing comment (`#import "Volumetrics.h"   // vol_skyColor`, real, MeshRenderer.metal).
// Hence the CLOSING delimiter, not the end of the spelling, ends the path. A spelling with no recognised
// opening delimiter (a macro include, `#include HEADER_MACRO`) is returned verbatim in quote-form — the
// pre-existing behaviour, preserved byte-for-byte. Allocates a std::string → not noexcept.
std::string includePathOf( std::string_view spelling, bool& isAngleOut )
{
    if( spelling.size() < 2 || ( spelling.front() != '"' && spelling.front() != '<' ) )
    {
        return std::string( spelling );
    }

    isAngleOut = ( spelling.front() == '<' );
    const char closer = isAngleOut ? '>' : '"';
    const std::size_t end = spelling.find( closer, 1 );
    if( end == std::string_view::npos )
    {
        return std::string( spelling.substr( 1 ) );   // unterminated — degrade to "everything after the opener"
    }
    return std::string( spelling.substr( 1, end - 1 ) );
}

// tree-sitter does NOT flatten the preprocessor. `#if` / `#ifdef` / `#ifndef` / `#else` / `#elif` /
// `#elifdef` each parse as a CONTAINER node that OWNS every directive written between it and its
// `#endif` — so a directive under a feature guard is a GRANDchild of the file root, not a child, and the
// top-level-only child scan captureIncludes used to do could not see it at all. It was not
// mis-resolved; it was never visited. The public node-type strings below are the same in every C-family
// grammar we vendor (tree-sitter-c / -cpp / -objc / -cuda) AND in tree-sitter-c-sharp, whose
// `preproc_if_in_top_level` / `_in_field_declaration_list` / `_in_enumerator_list` internal variants all
// report these same names to `ts_node_type` — one table therefore covers every grammar with a
// preprocessor, and no per-language branch is needed. `#region` is deliberately ABSENT: C#'s
// preproc_region is a flat directive, not a container, so a `using` under it was always a root child.
//
// EVERY ARM IS CAPTURED, on purpose. We do not read the build system's `-D` flags (G3: no host-installed
// dependencies, no compile database required), so which arm of an `#if`/`#else` a particular build
// selects is not knowable here. The dependency view is therefore the UNION over all arms — a superset of
// any one configuration, never a guess at which one. That is the honest direction for this graph: an
// include that some configuration really does pull in is a real dependency, and over-capture costs a
// spurious edge while under-capture costs a false `surprising="1"` on --cochange (the defect this fixes).
//
// Tables, not switches, per the declarative-tables rule: these lists are the whole contract, readable in
// one pass, and a grammar bump that renames a node kind is a one-line edit here.
inline constexpr std::array<std::string_view, 5> kPreprocConditionalNodes = { "preproc_if", "preproc_ifdef", "preproc_else", "preproc_elif", "preproc_elifdef" };

// One membership test for every node-kind table below — a single shape rather than one hand-rolled scan
// per table (the repo already spells this `std::find( … ) != end` elsewhere; see graph.h / flipimpact.h).
inline bool namesNode( std::span<const std::string_view> table, const char* type ) noexcept
{
    return std::find( table.begin(), table.end(), std::string_view( type ) ) != table.end();
}

inline bool isPreprocConditional( const char* type ) noexcept
{
    return namesNode( kPreprocConditionalNodes, type );
}

// ─── Non-preprocessor import containers, keyed by language ───────────────────────────────────────────
//
// The preprocessor is not the only thing that wraps a directive. Ordinary language constructs do it too,
// and the same top-level-only scan dropped every one of them:
//
//   Python  `if TYPE_CHECKING: import x` and `try: import ujson / except ImportError: import json` — the
//           two canonical spellings of a conditional dependency, the direct analogue of `#ifdef` — plus
//           every function-, method- and class-body import.
//   Rust    `use` inside `mod x { … }` (including `#[cfg(unix)] mod plat`, the Rust platform guard),
//           inside a fn / impl / trait body, and inside any block expression.
//   C#      `using` inside a BLOCK-scoped `namespace Foo { … }`. The file-scoped form (`namespace Foo;`)
//           does not nest — its usings stay compilation-unit children — so it needs no entry, and
//           test/nestedimportfix/filescoped.cs is the control that keeps it that way.
//
// KEYED BY LANGUAGE ON PURPOSE. `block` and `declaration_list` are node-type names in half a dozen of
// our grammars; a shared list would send the walk into every C++/TypeScript/Java function body hunting a
// directive form those languages do not have there — cost with no recall. Each language therefore names
// only the containers ITS directives really appear in. Languages absent from the switch below (C-family,
// TS/JS, Go, Swift, Java, Ruby) get the preprocessor set and nothing else, which is the whole of what
// their grammars nest: TS/JS ESM `import` is top-level-only (a dynamic `import( … )` is a call
// expression, not an import_statement), and Go/Java imports are top-level by language rule.
//
// EVERY ENTRY HAS A FIXTURE ARM in test/nestedimportfix — an entry with no arm is an untested claim, and
// every parent chain below was read off a real parse with `--match`, never predicted from the grammar.
inline constexpr std::array<std::string_view, 16> kPythonImportContainers = {
    "block",                                                                    // every non-top-level import's DIRECT parent
    "if_statement", "elif_clause", "else_clause",                               // `if TYPE_CHECKING:` and its arms
    "try_statement", "except_clause", "except_group_clause", "finally_clause",  // `except ImportError:` / `except*`
    "with_statement", "for_statement", "while_statement",
    "match_statement", "case_clause",
    "class_definition", "function_definition", "decorated_definition"           // decorated_* wraps the def, so it needs its own entry
};

// `unsafe`/`async` blocks and `decorated_definition` above look redundant next to `block` /
// `function_definition` — they are not. They are the node the walk meets FIRST on the way down, so
// without them the descent stops one level short of the body that holds the directive.
inline constexpr std::array<std::string_view, 19> kRustImportContainers = {
    "block", "declaration_list",                                                 // the two body kinds
    "mod_item", "foreign_mod_item", "impl_item", "trait_item", "function_item",   // item containers
    "expression_statement", "let_declaration",                                    // Rust wraps a statement-position
                                                                                  // expression in one of these two, so
                                                                                  // every control-flow entry below is
                                                                                  // reachable ONLY through them
    "if_expression", "else_clause", "match_expression", "match_block", "match_arm",
    "loop_expression", "while_expression", "for_expression",
    "unsafe_block", "async_block"
};

inline constexpr std::array<std::string_view, 2> kCsharpImportContainers = { "namespace_declaration", "declaration_list" };

inline bool isImportContainer( Lang lang, const char* type ) noexcept
{
    if( isPreprocConditional( type ) )   // every grammar with a preprocessor: C/C++/ObjC/CUDA/Metal + C#
    {
        return true;
    }
    switch( lang )
    {
        case Lang::Python: return namesNode( kPythonImportContainers, type );
        case Lang::Rust:   return namesNode( kRustImportContainers, type );
        case Lang::CSharp: return namesNode( kCsharpImportContainers, type );
        default:           return false;
    }
}

// Nesting bound for the container descent. Real preprocessor guards nest a handful deep (the deepest in
// any corpus measured here is 4); Python spends TWO levels per indent (statement + block), so this bound
// has to clear ~2x the deepest plausible indentation, not the guard depth. 256 is far past either and
// exists only so a hostile or generated file cannot turn the walk into unbounded heap-stack growth.
// Exceeding it DEGRADES — deeper imports are simply not captured, the file still indexes — never fails.
constexpr std::uint16_t kMaxImportContainerDepth = 256;

// ONE import/include directive node → the written specifier, or empty when this node is not a directive
// at all. Split out of captureIncludes so the walk that FINDS directives and the per-grammar table that
// READS them stay separately readable — the walk is one shape, this is one branch per grammar spelling.
//
// Node types confirmed per grammar: C++ preproc_include (path field, "" local vs <> external); C++
// preproc_call with directive `#import` (the C/C++ grammar has no #import rule — the objc grammar does,
// and yields preproc_include there); Python import_statement/import_from_statement; Go/Swift
// import_declaration; Rust use_declaration + mod_item; C# using_directive. LEVER-B B0: non-C imports
// capture the CLEAN written specifier via grammar child fields (module path / quoted specifier / use
// argument), not a sliced clause — the sound resolver input.
//
// `isAngle` is C/C++/ObjC only: `<x.h>` (external) vs `"x.h"` (quote), returned alongside the target so
// path-precise resolution can leave angle includes unresolved. Allocates a std::string → not noexcept.
struct DirectiveTarget { std::string target; bool isAngle; };

DirectiveTarget directiveTargetOf( TSNode n, const char* t, std::string_view src )
{
    std::string target;
    bool        isAngle = false;

    if( std::strcmp( t, "preproc_include" ) == 0 )                       // C++/C/ObjC: exact file path
    {
        const TSNode pth = ts_node_child_by_field_name( n, "path", 4 );
        if( !ts_node_is_null( pth ) )
        {
            const uint32_t a = ts_node_start_byte( pth ), b = ts_node_end_byte( pth );
            if( a < b && b <= src.size() )
            {
                target = includePathOf( src.substr( a, b - a ), isAngle );
            }
        }
    }
    else if( std::strcmp( t, "preproc_call" ) == 0 )                     // C++-grammar `#import "x.h"` (ObjC/Metal spelling)
    {
        // `#import` is `#include` + include-once, so it MUST yield the same Include edge — this is
        // the edge that connects a `.metal` shader to the FX headers it pulls in (10 of the 45 shaders in
        // the measured reference tree use the `#import` spelling). Under the objc grammar it already parses
        // as preproc_include (handled above); under the C/C++ grammar there is no #import rule, so it
        // lands here as the generic preproc_call: directive:(preproc_directive) `#import`,
        // argument:(preproc_arg) `"x.h"` / `<x.h>`. EVERY other preproc_call (`#pragma`, `#error`,
        // `#warning`, an unknown directive) is not a physical dependency — the directive check below
        // is what keeps them out, so this branch never widens the include graph beyond #import.
        const TSNode dir = ts_node_child_by_field_name( n, "directive", 9 );
        const TSNode arg = ts_node_child_by_field_name( n, "argument",  8 );
        if( !ts_node_is_null( dir ) && !ts_node_is_null( arg ) )
        {
            const uint32_t da = ts_node_start_byte( dir ), db = ts_node_end_byte( dir );
            const uint32_t aa = ts_node_start_byte( arg ), ab = ts_node_end_byte( arg );
            if( da < db && db <= src.size() && aa < ab && ab <= src.size() && src.substr( da, db - da ) == "#import" )
            {
                target = includePathOf( src.substr( aa, ab - aa ), isAngle );   // trailing comment ends at the closing delimiter
            }
        }
    }
    else if( std::strcmp( t, "import_statement" ) == 0 )                 // Python `import a` / TS `import … from 'x'`
    {
        // Prefer the grammar's specifier field over slicing the whole statement (LEVER-B B0: the resolver
        // needs the REAL written specifier, not the clause). Empirically confirmed node shapes:
        //   Python: import_statement name:(dotted_name|aliased_import)  → the dotted module `pkg.mod`.
        //   TS/JS:  import_statement source:(string)                    → the quoted specifier `'./x'`.
        // ts_node_child_by_field_name returns null for the language that lacks the field, so a single
        // capture covers both grammars without a per-language branch.
        if( const TSNode src_ = ts_node_child_by_field_name( n, "source", 6 );  !ts_node_is_null( src_ ) )
        {
            target = importSpecifierText( src_, src );                    // TS/JS: strip the surrounding quotes
        }
        else if( const TSNode nm = ts_node_child_by_field_name( n, "name", 4 );  !ts_node_is_null( nm ) )
        {
            target = importSpecifierText( nm, src );                      // Python: the dotted module head
        }
    }
    else if( std::strcmp( t, "import_from_statement" ) == 0 )            // Python `from pkg.mod import Z`
    {
        // module_name:(dotted_name)  → `pkg.mod`;  module_name:(relative_import)  → `.rel` / `..up` (leading
        // dots preserved so the resolver can resolve relative-to-file). The imported-names clause is dropped.
        if( const TSNode mn = ts_node_child_by_field_name( n, "module_name", 11 );  !ts_node_is_null( mn ) )
        {
            target = importSpecifierText( mn, src );
        }
    }
    else if( std::strcmp( t, "use_declaration" ) == 0 )                  // Rust `use crate::a::b;`
    {
        // argument:(scoped_identifier|scoped_use_list|identifier|…)  → `crate::a::b`. A brace group
        // `crate::{a, b}` is kept verbatim; the resolver degrades on it (no unique single-file hit).
        if( const TSNode arg = ts_node_child_by_field_name( n, "argument", 8 );  !ts_node_is_null( arg ) )
        {
            target = importSpecifierText( arg, src );
        }
    }
    else if( std::strcmp( t, "mod_item" ) == 0 )                        // Rust `mod x;` (module-file declaration)
    {
        // A body-LESS `mod x;` declares module `x` in a sibling file (`x.rs` or `x/mod.rs`); a `mod x { … }`
        // with a body is INLINE (no file) → skip it. Prefix `mod:` so the Rust resolver applies the
        // module-file rule, distinct from a bare `use x;`. name:(identifier) → `x`.
        if( ts_node_is_null( ts_node_child_by_field_name( n, "body", 4 ) ) )
        {
            if( const TSNode nm = ts_node_child_by_field_name( n, "name", 4 );  !ts_node_is_null( nm ) )
            {
                if( std::string bare = importSpecifierText( nm, src );  !bare.empty() )
                {
                    target = "mod:" + bare;
                }
            }
        }
    }
    else if(    std::strcmp( t, "import_declaration" ) == 0 )            // Go / Swift — captured but NOT precise-resolved
    {
        // Go (needs go.mod module-root) and Swift (whole-module, no path) are DEFERRED — the precise
        // resolver leaves them unresolved. Keep the best-effort target for --uses / --deps back-compat.
        const uint32_t a = ts_node_start_byte( n ), b = ts_node_end_byte( n );
        if( a < b && b <= src.size() )
        {
            std::string_view s  = src.substr( a, b - a );
            const std::size_t sp = s.find( ' ' );                        // drop the leading keyword
            if( sp != std::string_view::npos )
            {
                s = s.substr( sp + 1 );
            }
            target.assign( s.data(), s.size() < 96 ? s.size() : 96 );
            while( !target.empty() && ( target.back() == ';' || target.back() == ' ' || target.back() == '\n' || target.back() == '\r' ) )
            {
                target.pop_back();
            }
        }
    }
    else if( std::strcmp( t, "using_directive" ) == 0 )
    { // C# `using Foo.Bar;` / `using static Foo;` / `using X = Foo.Bar;`
        target = csharpUsingTarget( n, src );                            // see csharpUsingTarget for the shape rationale
    }
    return { std::move( target ), isAngle };
}

// Capture #include / import directives (physical dependencies) by walking the file's top-level nodes —
// and the bodies of anything that WRAPS a directive, which tree-sitter does not flatten: preprocessor
// conditionals in the C family and C#, and ordinary language constructs in Python / Rust / C# (see
// isImportContainer). Each node is read by directiveTargetOf above.
// ABS-3: each directive ALSO emits an import-role RawRef (name = the importable final segment) so the
// use-site index reports import sites. The ref is file-scope (fromSymbol=kNoNode) — that is correct for
// a directive at any container depth, and it NEVER enters the call graph (role != Call → skipped in
// buildGraph). The ref's line comes from the DIRECTIVE node, never from its enclosing `#if` or body.
void captureIncludes( TSNode root, Lang lang, std::uint32_t fileId, std::string_view src, std::vector<Include>& incs, std::vector<RawRef>& refs )
{
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );
    collectChildren( root, cursor.cur, kids );   // root's width is file-controlled — never index it (O(C²))

    // Iterative pre-order walk. An EXPLICIT frame stack, not recursion: worker threads get 512 KB stacks
    // on macOS, so a deep AST overflows the call stack well inside any depth guard — cc_walk above makes
    // the same choice for the same reason. Children are pushed in REVERSE so pops preserve left-to-right
    // order, which keeps `incs`/`refs` in SOURCE order: the determinism contract is byte-identity, and an
    // order that depended on the walk shape would break it. Only ALLOWLISTED containers are entered, so a
    // language whose imports are top-level by rule (TS/JS, Go, Java) still costs exactly the old scan.
    struct IncFrame { TSNode node; std::uint16_t depth; };
    std::vector<IncFrame> stack;
    stack.reserve( 64 );
    for( std::size_t i = kids.size(); i > 0; --i )
    {
        stack.push_back( { kids[i - 1], 0 } );
    }

    while( !stack.empty() )
    {
        const IncFrame frame = stack.back();
        stack.pop_back();
        const TSNode n = frame.node;
        const char*  t = ts_node_type( n );

        // READ, then DESCEND — both, never either/or. Rust's `mod_item` is the reason: a body-LESS
        // `mod x;` is itself a directive (emitted as `mod:x`, the module-FILE declaration) while a
        // `mod x { … }` is a container whose body holds `use`s. A walk that treated container-ness as a
        // reason to skip the read would silently drop every Rust module-file declaration in the corpus.
        // For every other container the read simply returns empty, so one uniform order covers all of them.
        auto [ target, isAngle ] = directiveTargetOf( n, t, src );

        if( isImportContainer( lang, t ) )
        {
            // `#else`/`#elif`/`#elifdef` hang off their `#if` as the `alternative:` child, and Python's
            // `elif_clause`/`else_clause` hang off their `if_statement` the same way, so one uniform
            // descent reaches every arm of a chain — no separate alternative-following pass.
            if( frame.depth >= kMaxImportContainerDepth )
            {
                DEGRADED_PATH_ALERT( "ingest: import-container nesting past the depth bound — deeper imports not captured" );
            }
            else
            {
                collectChildren( n, cursor.cur, kids );   // safe: the seed iteration above is finished
                for( std::size_t i = kids.size(); i > 0; --i )
                {
                    stack.push_back( { kids[i - 1], static_cast<std::uint16_t>( frame.depth + 1 ) } );
                }
            }
        }

        if( !target.empty() )
        {
            // import-role use-site ref: name = the importable final segment (skip when the target has no
            // identifier head, e.g. a relative `../x` whose head strips to empty → nothing to resolve).
            if( std::string nm = importName( target ); !nm.empty() )
            {
                RawRef r;
                r.fileId    = fileId;
                r.startByte = ts_node_start_byte( n );   // the DIRECTIVE, not its enclosing #if → file-scope attribution
                r.line      = ts_node_start_point( n ).row + 1;
                r.role      = RefRole::Import;
                r.name      = std::move( nm );
                refs.push_back( std::move( r ) );
            }
            incs.push_back( { fileId, isAngle, std::move( target ) } );
        }
    }
}

// Markdown has no tree-sitter grammar in our set. We extract: (1) a FILE-LEVEL node spanning the whole file
// (named by the filename stem) so heading-less docs stay visible + rankable AND so it's the container that
// [[wikilinks]] attribute to; (2) ATX headings (# .. ###### + space) as Section defs — the doc's navigable
// structure (skips '#' inside ``` / ~~~ fences); (3) [[wikilink]] refs → file→file edges (the agent-memory /
// Obsidian convention) so PageRank surfaces the most-connected notes. Determinism: emitted in file/byte
// order; the global def+ref sorts handle cross-file ordering. Names are XML-escaped downstream.
void extractMarkdown( std::uint32_t fileId, std::string_view src, std::string_view stem,
                      std::vector<RawDef>& defs, std::vector<RawRef>& refs )
{
    // (1) file-level node — span [0,size) ⇒ the lexical scorer indexes the whole fact body; [[links]] land here.
    {
        RawDef d;
        d.fileId = fileId; d.line = 1; d.startByte = 0; d.endByte = std::uint32_t( src.size() );
        d.nameByte = 0; d.bodyByte = 0; d.kind = SymKind::Section; d.lang = Lang::Markdown;
        d.name.assign( stem );
        defs.push_back( std::move( d ) );
    }

    bool          inFence = false;
    std::uint32_t lineNo  = 1;
    for( std::size_t i = 0; i < src.size(); )
    {
        const std::size_t lineStart = i;
        std::size_t       j         = i;
        while( j < src.size() && src[j] != '\n' )
        {
            ++j; // [lineStart, j) = this line, no newline
        }
        std::string_view line = src.substr( lineStart, j - lineStart );
        if( !line.empty() && line.back() == '\r' )
        {
            line.remove_suffix( 1 ); // CRLF: drop the trailing CR — else it corrupts the heading name attr AND breaks LF/CRLF byte-identity
        }

        // leading indent
        std::size_t s = 0;
        while( s < line.size() && ( line[s] == ' ' || line[s] == '\t' ) )
        {
            ++s;
        }

        // fenced-code toggle: ``` or ~~~ (CommonMark allows ≤3 leading spaces)
        if( s <= 3 && line.size() - s >= 3 && ( line.compare( s, 3, "```" ) == 0 || line.compare( s, 3, "~~~" ) == 0 ) )
        {
            inFence = !inFence;
        }
        else if( !inFence && s <= 3 )
        {
            std::size_t h = s;
            while( h < line.size() && line[h] == '#' )
            {
                ++h;
            }
            const std::size_t level = h - s;
            // ATX heading: 1..6 '#', then at least one space/tab, then text
            if( level >= 1 && level <= 6 && h < line.size() && ( line[h] == ' ' || line[h] == '\t' ) )
            {
                std::size_t a = h;
                while( a < line.size() && ( line[a] == ' ' || line[a] == '\t' ) )
                {
                    ++a; // text start
                }
                std::size_t e = line.size();                                                                  // strip trailing
                while( e > a && ( line[e - 1] == ' ' || line[e - 1] == '\t' ) )
                {
                    --e;
                }
                while( e > a && line[e - 1] == '#' )
                {
                    --e; //   closing #'s
                }
                while( e > a && ( line[e - 1] == ' ' || line[e - 1] == '\t' ) )
                {
                    --e;
                }
                if( e > a )
                {
                    RawDef d;
                    d.fileId    = fileId;
                    d.line      = lineNo;
                    d.startByte = std::uint32_t( lineStart );
                    d.endByte   = std::uint32_t( j );
                    d.nameByte  = std::uint32_t( lineStart + a );   // dedup identity = heading-text start
                    d.bodyByte  = 0;
                    d.kind      = SymKind::Section;
                    d.lang      = Lang::Markdown;
                    d.name.assign( line.substr( a, e - a ) );
                    defs.push_back( std::move( d ) );
                }
            }
        }

        // (2b) inline-code `identifiers` → doc→code mentions; resolved to real code symbols in buildGraph
        // (stored in g.mentions, OUT of the call graph). Fence-aware; accepts only clean idents (len≥3).
        if( !inFence )
        {
            for( std::size_t b = 0; b + 1 < line.size(); )
            {
                if( line[b] != '`' ) { ++b; continue; }
                std::size_t e = b + 1;
                while( e < line.size() && line[e] != '`' )
                {
                    ++e;
                }
                if( e >= line.size() )
                {
                    break; // unclosed backtick on this line
                }
                std::string_view span = line.substr( b + 1, e - b - 1 );
                if( const std::size_t p = span.find( '(' ); p != std::string_view::npos )
                {
                    span = span.substr( 0, p ); // `foo()` → foo
                }
                if( const std::size_t c = span.rfind( "::" ); c != std::string_view::npos )
                {
                    span = span.substr( c + 2 ); // `A::b` → b
                }
                bool ok = span.size() >= 3 && ( ( span.front() >= 'A' && span.front() <= 'Z' ) || ( span.front() >= 'a' && span.front() <= 'z' ) || span.front() == '_' );
                for( std::size_t k = 0; ok && k < span.size(); ++k )
                { const char ch = span[k]; ok = ( ch >= 'A' && ch <= 'Z' ) || ( ch >= 'a' && ch <= 'z' ) || ( ch >= '0' && ch <= '9' ) || ch == '_'; }
                if( ok )
                {
                    RawRef rr;
                    rr.fileId = fileId;  rr.startByte = std::uint32_t( lineStart + b );  rr.lang = Lang::Markdown;
                    rr.isInherit = false;  rr.isDocLink = true;  rr.name.assign( span );
                    refs.push_back( std::move( rr ) );
                }
                b = e + 1;
            }
        }

        if( j < src.size() )
        {
            i = j + 1;
            ++lineNo;
        }
        else
        {
            i = j;
        }
    }

    // (3) [[wikilink]] edges: [[slug]] / [[slug|text]] / [[slug#sec]] → a ref from this file's node to the
    // node named `slug`. The resolver makes it a same-dir file→file edge; unresolved (dangling) links drop.
    for( std::size_t i = 0; i + 1 < src.size(); ++i )
    {
        if( src[i] != '[' || src[i + 1] != '[' )
        {
            continue;
        }
        const std::size_t open = i + 2;
        std::size_t       e    = open;
        while( e + 1 < src.size() && src[e] != '\n' && !( src[e] == ']' && src[e + 1] == ']' ) )
        {
            ++e;
        }
        if( e + 1 >= src.size() || src[e] != ']' || src[ e + 1 ] != ']' ) { i = e; continue; }   // no closing ]] on this line
        std::string_view slug = src.substr( open, e - open );
        for( std::size_t k = 0; k < slug.size(); ++k )
        {
            if( slug[k] == '|' || slug[k] == '#' )
            {
                slug = slug.substr( 0, k );
                break;
            }
        }
        while( !slug.empty() && slug.front() == ' ' )
        {
            slug.remove_prefix( 1 );
        }
        while( !slug.empty() && slug.back() == ' ' )
        {
            slug.remove_suffix( 1 );
        }
        if( !slug.empty() )
        {
            RawRef r;
            r.fileId = fileId; r.startByte = std::uint32_t( i ); r.lang = Lang::Markdown; r.isInherit = false;
            r.name.assign( slug );
            refs.push_back( std::move( r ) );
        }
        i = e + 1;   // past the closing ]]
    }
}

// E#4 canonical-resolution helpers (C++; node-type names are tree-sitter-cpp's). For a call `A::b()` the
// @name node `b` sits in a qualified_identifier whose `scope` is `A` → qualifierOf returns the IMMEDIATE
// scope component ("A", or "B" from `A::B::b`). enclosingScopeOf walks ancestors to the nearest
// class/struct/namespace and returns its name (for in-class method DEFS). Both "" when absent → caller
// falls back to bare-name resolution (so non-C++ langs and unqualified calls are unaffected).
inline std::string immediateScope( std::string_view full )
{
    const std::size_t cc = full.rfind( "::" );
    return std::string( cc == std::string_view::npos ? full : full.substr( cc + 2 ) );
}

// ── H4 qualified-call re-split helpers ───────────────────────────────────────────────────────────────────
// The widened C++ call pattern (`qualified_identifier name: (_)`) binds the INNER node at every depth, so
// the captured text of a 3+-segment call still carries scope (`inner::targetFn`,
// `numeric_limits<std::size_t>::max`). These two helpers turn that text back into the (name, immediate
// qualifier) pair the canonical resolution tier keys on — the plain finalSegment() path cannot, because it
// truncates at the FIRST '<' and would name the second example `numeric_limits`.

// The four C++ cast keywords. tree-sitter-cpp parses `static_cast<T>( x )` as
// `call_expression function: (template_function name: (identifier))` — structurally identical to a real
// explicit-template-argument call — so the template_function reference pattern matches every cast in the
// tree (171 sites in this repo's src/ alone). A cast is not a call and must not mint a reference: it is
// VALID INPUT, not a corrupt invariant, so the capture loop simply skips it (never VERIFY, never
// DEGRADED_PATH_ALERT — nothing degraded). Query predicates cannot do this: passesPredicates is wired into
// --match/--lint only, not the tags pass (measured — a `#not-eq?` left --uses=static_cast at 165).
inline bool isCppCastKeyword( std::string_view name ) noexcept
{
    return name == "static_cast" || name == "reinterpret_cast" || name == "const_cast" || name == "dynamic_cast";
}

// Start index of `text`'s trailing C++ OPERATOR NAME (`operator>`, `operator<<`, `operator()`, `operator bool`),
// or npos when the name is a plain identifier. This must be consulted BEFORE any angle-depth scanning.
//
// WHY (found by the adversarial verifier, not by construction): an operator name is the one place a NAME
// legitimately carries `<`/`>` punctuation that is not a template-argument delimiter. Scanning
// `inner::operator>` right-to-left, the trailing `>` opens a group that never closes, so
// lastTopLevelScopeSep finds NO separator, the re-split is skipped, and the qualifier falls back to
// qualifierOf()'s OUTERMOST scope — measured binding `outer::inner::operator>( x, y )` to a decoy
// `outer::operator>` with ambiguous=0 and no disclosure at all. `operator>`, `operator>>`, `operator>=` and
// `operator->` are all poisoned that way; `operator<<` merely survived by luck (depth is clamped at zero, so
// its `<`s are ignored rather than balanced). Detecting the operator tail up front cures the whole family.
//
// The first two guards mirror finalSegment()'s own operator exemption (see it above) so the two cannot
// drift: the keyword must start a SEGMENT (index 0, or right after a `::`/`.`), and the character after it
// must not continue an identifier — so `operatorId` stays a plain name and takes the ordinary path.
//
// The third guard is what makes the name TRAILING, as the contract says (V3-L-2: `rfind` alone accepted
// `op::operator>::go` and split it into name `operator>::go` / qualifier `op` — unreachable from valid C++,
// since an operator cannot name a scope, but the function promised npos for anything that is not a trailing
// operator name and did not deliver it). A SYMBOLIC operator's name is the keyword plus a run of operator
// punctuation, and it must reach the END of the text; anything after that run means a further segment
// follows, so this is not the trailing name. A SPACE after the keyword instead marks the
// `operator <type>` family (conversion operators, `operator new`/`operator delete`), whose type half may
// itself contain `::` (`operator ns::Type`) — that IS the trailing name, so the punctuation run is not
// applied to it.
inline std::size_t operatorNameStart( std::string_view text ) noexcept
{
    constexpr std::string_view kOperator      = "operator";
    constexpr std::string_view kOperatorPunct = "+-*/%^&|~!=<>()[],";   // every char a C++ operator name may use

    const std::size_t op = text.rfind( kOperator );
    if( op == std::string_view::npos )
    {
        return std::string_view::npos;
    }

    const bool atSegmentStart = ( op == 0 ) || ( text[ op - 1 ] == ':' ) || ( text[ op - 1 ] == '.' );
    if( !atSegmentStart )
    {
        return std::string_view::npos;
    }

    // `operator` must be a whole token: `operatorId` is a plain identifier that merely starts with it.
    const std::size_t after = op + kOperator.size();                    // one-past `operator`
    if( after >= text.size() )
    {
        return op; // the bare keyword ends the text
    }
    if( std::isalnum( static_cast<unsigned char>( text[ after ] ) ) || text[ after ] == '_' )
    {
        return std::string_view::npos;
    }

    // `operator <type>` — the type half owns the rest of the text, `::` and all.
    if( std::isspace( static_cast<unsigned char>( text[after] ) ) )
    {
        return op;
    }

    // symbolic: the punctuation run IS the name, and it must run to the end or this is not the tail.
    std::size_t punctEnd = after;
    while( punctEnd < text.size() && kOperatorPunct.find( text[punctEnd] ) != std::string_view::npos )
    {
        ++punctEnd;
    }
    return punctEnd == text.size() ? op : std::string_view::npos;
}

// Index of the last `::` in `text` that sits at TEMPLATE-ARGUMENT DEPTH ZERO, or npos when there is none.
// Scanned in reverse (the LAST top-level separator is the one that splits name from scope), tracking `<`/`>`
// nesting so a `::` inside template arguments never splits: `tmplFn<a::B>` has NO top-level separator, while
// `numeric_limits<std::size_t>::max` has exactly one — at the `::` before `max`.
// PRECONDITION: `text` carries no trailing operator name. Depth is clamped at zero, which makes an
// operator spelling merely IGNORED rather than balanced — that is enough for `operator<<` and NOT enough for
// the `>` family, whose unmatched `>` would leave the depth pinned above zero and hide every separator. The
// caller checks operatorNameStart() first; do not weaken that ordering.
// The loop counts a 1-based CURSOR down to zero rather than the classic `for( i = n; i-- > 0; )`: that idiom
// wraps `i` to SIZE_MAX on its final test, which `-fsanitize=integer` reports as an unsigned-integer
// overflow (observed on this very function before this shape — the G1 build caught it on the fixture).
inline std::size_t lastTopLevelScopeSep( std::string_view text ) noexcept
{
    std::size_t angleDepth = 0;
    for( std::size_t cursor = text.size(); cursor > 0; --cursor )
    {
        const std::size_t charIndex = cursor - 1;
        const char        c         = text[ charIndex ];
        if( c == '>' )
        {
            ++angleDepth;
        }
        else if( c == '<' && angleDepth > 0 )
        {
            --angleDepth;
        }
        else if( c == ':' && angleDepth == 0 && charIndex > 0 && text[ charIndex - 1 ] == ':' )
        {
            return charIndex - 1;                                 // index of the FIRST ':' of the pair
        }
    }
    return std::string_view::npos;
}
// True when a qualified_identifier's `::` separator is a MISSING node — a zero-width token tree-sitter
// INSERTED during error recovery, not one that is written in the source. Recovery reaches for this shape
// whenever two identifiers sit adjacent where the grammar expected one, so `<ReturnType> name(...)` after
// an unknown leading keyword parses as `ReturnType::name` with a phantom `::`. That is exactly what MSL's
// `vertex GalleryVertexOut gallery_vertexSphere( … )` does under the C++ grammar (L4) — and the invented
// "scope" is the RETURN TYPE, so honouring it would publish `Out::f` for a free function and try to
// resolve calls against a class that never had that member. Valid C++ never produces a MISSING `::`, so
// this guard is inert on every well-formed parse.
inline bool hasPhantomScopeSeparator( TSNode qualified ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( qualified );
    for( std::uint32_t childIndex = 0; childIndex < childCount; ++childIndex )
    {
        const TSNode child = ts_node_child( qualified, childIndex );
        if( std::strcmp( ts_node_type( child ), "::" ) == 0 )
        {
            return ts_node_is_missing( child );
        }
    }
    return false;   // no separator child at all → leave the pre-existing behaviour untouched
}
inline std::string qualifierOf( TSNode nameNode, std::string_view src )
{
    const TSNode parent = ts_node_parent( nameNode );
    if( ts_node_is_null( parent ) || std::strcmp( ts_node_type( parent ), "qualified_identifier" ) != 0 )
    {
        return {};
    }
    if( hasPhantomScopeSeparator( parent ) )
    {
        return {}; // error-recovery artefact, not a written qualification
    }
    const TSNode scope = ts_node_child_by_field_name( parent, "scope", 5 );
    if( ts_node_is_null( scope ) )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( scope ), b = ts_node_end_byte( scope );
    return ( a <= b && b <= src.size() ) ? immediateScope( src.substr( a, b - a ) ) : std::string{};
}
// ── H4 RUST qualified-call helpers (W1-MEASURE verdict) ─────────────────────────────────────────────────
// W1 measured that the Rust PATTERN ALONE under-delivers: Rust defs carried scope="" (canonByName was fed
// only by the C++/Python arms) and Rust refs carried qualifier="", so every widened `Widget::new()` fell to
// the BARE-NAME spray — and two types defining `new` in DIFFERENT directories then hit the tier-3
// unique-or-DROP rule, killing BOTH edges with no `amb=` and no `unresolved=` movement. So the pattern ships
// WITH a qualifier (ref side) and a scope (def side); together they key the canonical `qualifier::name` tier
// that C++ already uses, and idiomatic Rust resolves PRECISELY instead of silently vanishing.

// A node's source text, or "" when the node is null or its byte range does not lie inside `src`. The
// null+range guard is the same three lines every extraction helper below would otherwise repeat (it is what
// --quality-delta flagged as a clone when the Rust helpers open-coded it), so it lives once, here.
inline std::string_view nodeTextOf( TSNode node, std::string_view src ) noexcept
{
    if( ts_node_is_null( node ) )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( node ), b = ts_node_end_byte( node );
    return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
}

// True when `s` is spelled as a plain Rust identifier. The qualifier is a canonByName KEY half, so a segment
// that is not an identifier (`<T as Trait>`, a stray `>` from an unbalanced spelling) can only ever produce a
// key that matches nothing — returning "" instead routes the ref to the bare-name ladder, which is the honest
// fallback. Cheap, and it keeps garbage out of a lookup table.
inline bool isRustIdentifier( std::string_view s ) noexcept
{
    if( s.empty() || ( s[0] >= '0' && s[0] <= '9' ) )
    {
        return false;
    }
    for( const char c : s )
    {
        if( !( ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_' ) )
        {
            return false;
        }
    }
    return true;
}

// The LAST segment of a Rust path spelling — the qualifier a `path::name` call keys on.
//   `Widget`                          → "Widget"        (2-segment `Widget::new()`)
//   `util::deep`                      → "deep"          (3-segment `util::deep::deepfn()`; immediate scope, as C++)
//   `Vec::<u32>`                      → "Vec"           (TURBOFISH, decided below)
//   `std::collections::HashMap::<K,V>` → "HashMap"
//   `<T as Trait>`                    → ""              (not an identifier → bare-name ladder)
// TURBOFISH DECISION (the round owes this one explicitly): Rust spells type arguments in expression position
// as `Vec::<u32>`, i.e. the `::` SURVIVES stripping the `<…>` group, where C++'s `Vec<u32>` does not. So the
// order is: strip the trailing balanced group FIRST (namesplit::stripTemplateArgs — never rfind, which would
// split inside `Foo<a::B>`), THEN drop the separator the turbofish left behind, THEN take the last TOP-LEVEL
// `::` segment. `Vec::<u32>` → `Vec::` → `Vec` → qualifier "Vec", which is the type the call actually names.
inline std::string rustPathSegment( std::string_view pathText ) noexcept
{
    std::string_view text = namesplit::stripTemplateArgs( pathText );          // `Vec::<u32>` → `Vec::`
    if( text.size() >= 2 && text.substr( text.size() - 2 ) == "::" )
    { // the turbofish `::<` separator
        text.remove_suffix( 2 );
    }
    const std::size_t sep = lastTopLevelScopeSep( text );
    const std::string_view seg = ( sep == std::string_view::npos ) ? text : text.substr( sep + 2 );
    return isRustIdentifier( seg ) ? std::string( seg ) : std::string{};
}

// The nearest enclosing Rust scope owner's NAME, walking ancestors from `node`.
//   `impl Widget { … }` / `impl Trait for Widget { … }` → the `type:` field ("Widget") — the IMPLEMENTOR in
//        both spellings, which is exactly what a caller writes before `::`. `impl<T> Foo<T>` → "Foo".
//   `trait Shape { fn area(&self) { … } }` → "Shape"  (a defaulted trait method is called `Shape::area`)
//   `mod util { … }`                      → "util"    (only when `includeModules`)
// `includeModules=false` is the `Self::` resolution mode: `Self` is only meaningful inside an impl/trait, so a
// module must NOT be allowed to answer for it. Node kinds are Rust-unique, which is why this stays a separate
// function from enclosingScopeOf rather than three more arms in its shared list.
inline std::string rustEnclosingScopeOf( TSNode node, std::string_view src, bool includeModules )
{
    for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        const bool  isImpl  = std::strcmp( t, "impl_item" )  == 0;
        const bool  isTrait = std::strcmp( t, "trait_item" ) == 0;
        const bool  isMod   = includeModules && std::strcmp( t, "mod_item" ) == 0;
        if( !isImpl && !isTrait && !isMod )
        {
            continue;
        }

        // impl carries the implementor under `type:`; trait/mod carry their own `name:`. Anonymous/ill-formed
        // (empty text) yields "" — no usable scope — which is the same degrade as "no owner above".
        const TSNode owner = isImpl ? ts_node_child_by_field_name( p, "type", 4 ) : ts_node_child_by_field_name( p, "name", 4 );
        // V3 L-1: a container is not its OWN scope. `mod util { … }`'s definition node IS that `name:` child, so
        // the first ancestor found is the module itself and `util` would be published as `util::util` (likewise
        // `Shape::Shape`) — a self-scope in the canonical-id space, which is what ids are keyed on. Keep walking
        // to the NEXT owner instead, so a nested `mod deep` inside `mod util` still scopes to "util".
        if( !ts_node_is_null( owner ) && ts_node_eq( owner, node ) )
        {
            continue;
        }
        return rustPathSegment( nodeTextOf( owner, src ) );                      // `Foo<T>` → "Foo"; `a::B` → "B"
    }
    return {};
}

// Qualifier of a Rust CALL reference whose @name is the final segment of a `scoped_identifier`:
// `Widget::new()` → "Widget", `util::deep::deepfn()` → "deep", `Vec::<u32>::new()` → "Vec".
// Returns "" for every other shape (bare `free()`, `w.bump()`, `generic::<u32>()`, and the crate-root `::f()`
// spelling, which has no `path:` child) → those keep the pre-existing bare-name resolution untouched.
// This is a CALL ref (isInherit=false). graph.h's Rust `impl Trait for T` CHA path reads `qualifier` too, but
// only behind `if( !ir.isInherit ) continue;`, so the two uses of the field cannot collide — gated by
// test/rustqualcheck.sh §8.
inline std::string rustQualifierOf( TSNode nameNode, std::string_view src )
{
    const TSNode parent = ts_node_parent( nameNode );
    if( ts_node_is_null( parent ) || std::strcmp( ts_node_type( parent ), "scoped_identifier" ) != 0 )
    {
        return {};
    }

    std::string qualifier = rustPathSegment( nodeTextOf( ts_node_child_by_field_name( parent, "path", 4 ), src ) );
    // `Self::helper()` — resolve `Self` to the ENCLOSING impl/trait type at EXTRACTION time, so the ref keys
    // the same canonical entry the def side wrote (`Widget::helper`). Precedent: captureRustImpls already
    // reads an impl header's `type:` for inherit refs. Falls back to bare-name when there is no impl above.
    if( qualifier == "Self" )
    {
        qualifier = rustEnclosingScopeOf( nameNode, src, /*includeModules=*/false );
    }
    return qualifier;
}

inline std::string enclosingScopeOf( TSNode node, std::string_view src )
{
    for( TSNode p = ts_node_parent( node ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        // class/struct/namespace owners across grammars (names don't collide between grammars):
        //   C++: class_specifier/struct_specifier/namespace_definition · Python: class_definition.
        // Each exposes a `name` field; the nearest one is the enclosing scope used for canonical resolution
        // and P2-D Rule-1 narrowing (a `self.m()`/`this->m()`/bare member call resolves to scope::m).
        const bool scopeOwner =    std::strcmp( t, "class_specifier" )     == 0 || std::strcmp( t, "struct_specifier" )    == 0
                                || std::strcmp( t, "namespace_definition" ) == 0 || std::strcmp( t, "class_definition" )    == 0;
        if( scopeOwner )
        {
            const TSNode nm = ts_node_child_by_field_name( p, "name", 4 );
            if( ts_node_is_null( nm ) )
            {
                return {}; // anonymous → no usable scope
            }
            const std::uint32_t a = ts_node_start_byte( nm ), b = ts_node_end_byte( nm );
            return ( a <= b && b <= src.size() ) ? std::string( src.substr( a, b - a ) ) : std::string{};
        }
    }
    return {};
}

// F5: a Swift LOCAL binding — `let a = f()` / `var b = ...` inside a function/closure body — parses to the
// same `property_declaration` node as a real stored/computed MEMBER property, so the @definition.var pattern
// captures it as a spurious top-level `var` symbol AND (being the nearest enclosing symbol above the body's
// call sites) STEALS the enclosing function's call edges. The discriminant: a `statements` node is the body of
// an executable block (function_body / lambda_literal / if/for/while/… ) and NEVER wraps a member property
// directly — a stored member is a child of class_body/enum_class_body/source_file, and a computed member's
// `statements` live inside its `computed_property` CHILD, below (not above) the property_declaration. So a
// `statements` ANCESTOR uniquely marks a local binding. Walk up from the property node; a `statements` before
// any type-body/file scope ⇒ local. Swift-only (gated by the caller); no other grammar reaches here.
inline bool isSwiftLocalBinding( TSNode declNode ) noexcept
{
    for( TSNode p = ts_node_parent( declNode ); !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* t = ts_node_type( p );
        if( std::strcmp( t, "statements" ) == 0 )
        {
            return true;                                             // inside an executable block → local binding
        }
        // a member property's wrappers — reaching one first means it is NOT a local.
        if( std::strcmp( t, "class_body" ) == 0 || std::strcmp( t, "enum_class_body" ) == 0 || std::strcmp( t, "protocol_body" ) == 0 || std::strcmp( t, "source_file" ) == 0 )
        {
            return false;
        }
    }
    return false;
}

// r3 q10 (bench/headtohead/r3-headroom-2026-08-03 REPORT.md §(v) item 1): SCREAMING_SNAKE — an
// ALL-CAPS identifier of ≥2 chars ([A-Z][A-Z0-9_]+), the cross-language naming convention for a
// module-level settings/config constant. The ≥2 floor drops single-letter names (a top-level `X = …`
// is a scratch binding, not a settings table). Pure ASCII on purpose: the convention IS ASCII.
inline bool isScreamingSnakeName( std::string_view name ) noexcept
{
    if( name.size() < 2 || name[0] < 'A' || name[0] > 'Z' )
    {
        return false;
    }
    for( const char c : name )
    {
        const bool ok = ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_';
        if( !ok )
        {
            return false;
        }
    }
    return true;
}

// Which languages' @definition.constant captures are gated on SCREAMING_SNAKE. These grammars' new
// constant patterns (queries/*/tags.scm, r3 q10) structurally capture EVERY module-level binding of the
// right shape — the name gate is what scopes extraction to settings modules / feature-flag tables
// instead of every literal. Enforced HERE because tags-pass predicates never run (#match? is wired into
// --match/--lint only — measured; see the note in queries/cpp/tags.scm). Deliberately NOT gated:
// Python (vendored upstream pattern, case-blind since import — existing behavior pinned by constcheck),
// Go (const/var patterns predate this and Go constants are conventionally CamelCase), Rust (const_item/
// static_item are constants by construction — the keyword, not the case, is the evidence), Swift
// (property_declaration predates this, filtered by isSwiftLocalBinding instead).
inline bool constCaptureNeedsScreamingGate( Lang lang ) noexcept
{
    switch( lang )
    {
        case Lang::TypeScript:
        case Lang::JavaScript:
        case Lang::Ruby:
        case Lang::Java:
        case Lang::CSharp:
        case Lang::C:
        case Lang::Cpp:
        {
            return true;
        }
        default:
        {
            return false;
        }
    }
}

// forward declarations for dropGatedCapture below — the helpers live after nodeTextOf's section.
inline bool isCjsExportTarget( TSNode nameNode, std::string_view src ) noexcept;
inline bool isPrototypeMemberTarget( TSNode nameNode, std::string_view src ) noexcept;

// The whole drop decision for every GATED definition capture, kept out of captureTagsFacts (which is
// already the file's densest dispatch point) behind ONE call, keyed on the @definition capture's own
// name. Three gated classes: @definition.constant drops when the language's convention gate applies
// and the name is not SCREAMING_SNAKE (r3 q10); @definition.cjsexport / @definition.protomethod (the
// JS shape round, test/jsshapecheck.sh) drop when the assignment's LEFT side is not really
// exports/module.exports/.prototype. — the query captures every `a.b = fn` shape and cannot
// text-test, because tags-pass predicates never run (see constCaptureNeedsScreamingGate above).
inline bool dropGatedCapture( std::string_view defCapSv, Lang lang, std::string_view name, TSNode nameNode, std::string_view src ) noexcept
{
    if( defCapSv == "definition.constant" )
    {
        return constCaptureNeedsScreamingGate( lang ) && !isScreamingSnakeName( name );
    }
    if( defCapSv == "definition.cjsexport" )
    {
        return !isCjsExportTarget( nameNode, src );
    }
    if( defCapSv == "definition.protomethod" )
    {
        return !isPrototypeMemberTarget( nameNode, src );
    }
    return false;
}

// JS shape round (test/jsshapecheck.sh): the two assignment-shape gates dropGatedCapture dispatches to.
// Both helpers take the @name capture — the `property:` field of the assignment's LEFT
// member_expression — and inspect that node's `object:` sibling.

// `exports.NAME = fn` (object is the bare identifier `exports`) or `module.exports.NAME = fn` (object is
// the member_expression `module.exports`, tested segment-by-segment, not as flat text — `module . exports`
// with interior spacing would still pass, a decoy like `moduleLike.exports` cannot).
inline bool isCjsExportTarget( TSNode nameNode, std::string_view src ) noexcept
{
    const TSNode member = ts_node_parent( nameNode );
    if( ts_node_is_null( member ) )
    {
        return false;
    }
    const TSNode obj = ts_node_child_by_field_name( member, "object", 6 );
    if( ts_node_is_null( obj ) )
    {
        return false;
    }
    const char* objType = ts_node_type( obj );
    if( std::strcmp( objType, "identifier" ) == 0 )
    {
        return nodeTextOf( obj, src ) == "exports";
    }
    if( std::strcmp( objType, "member_expression" ) == 0 )
    {
        const TSNode oo = ts_node_child_by_field_name( obj, "object", 6 );
        return std::strcmp( ts_node_type( oo ), "identifier" ) == 0
            && nodeTextOf( oo, src ) == "module"
            && nodeTextOf( ts_node_child_by_field_name( obj, "property", 8 ), src ) == "exports";
    }
    return false;
}

// `Foo.prototype.NAME = fn` at any qualifier depth: the member_expression under `object:` must name
// `prototype` as its property. Instance-slot assignments (`sock.onclose = fn`, `this.state.h = fn`)
// share the captured shape and fail exactly this test.
inline bool isPrototypeMemberTarget( TSNode nameNode, std::string_view src ) noexcept
{
    const TSNode member = ts_node_parent( nameNode );
    if( ts_node_is_null( member ) )
    {
        return false;
    }
    const TSNode obj = ts_node_child_by_field_name( member, "object", 6 );
    if( ts_node_is_null( obj ) || std::strcmp( ts_node_type( obj ), "member_expression" ) != 0 )
    {
        return false;
    }
    return nodeTextOf( ts_node_child_by_field_name( obj, "property", 8 ), src ) == "prototype";
}


// P2-D RECEIVER capture: classify the call-site receiver of `recv.method()` / `recv->method()` so
// resolve.h can narrow before the ambiguous §2a name spray. `nameNode` is the @name capture (the called
// identifier). When it is the `.field`/`.attribute` of a member-access node, inspect that node's
// receiver (`.argument` in C++ `field_expression`, `.object` in Python `attribute`):
//   `this`/`self`        → ThisObj  (the enclosing class is definitive — Rule 1)
//   a bare `(identifier)` → NamedVar, recvVar = the variable text (the var's type pins the method — Rule 2)
//   anything else (chained `a.b.c`, `(expr)`, subscripts, …) → None — too rich for one-hop; degrade to §2a.
// Returns { RecvKind, recvVar }. Pure-syntactic, deterministic, allocation-light; "" recvVar unless NamedVar.
inline std::pair<RecvKind, std::string> receiverOf( TSNode nameNode, Lang lang, std::string_view src )
{
    const TSNode parent = ts_node_parent( nameNode );
    if( ts_node_is_null( parent ) )
    {
        return { RecvKind::None, {} };
    }
    const char* pt = ts_node_type( parent );

    // the member-access node whose receiver we want
    const bool isCppField = ( lang == Lang::Cpp || lang == Lang::ObjC ) && std::strcmp( pt, "field_expression" ) == 0;
    const bool isPyAttr   = ( lang == Lang::Python )                    && std::strcmp( pt, "attribute" ) == 0;
    if( !isCppField && !isPyAttr )
    {
        return { RecvKind::None, {} };
    }

    const TSNode recvNode = isCppField ? ts_node_child_by_field_name( parent, "argument", 8 )
                                       : ts_node_child_by_field_name( parent, "object",   6 );
    if( ts_node_is_null( recvNode ) )
    {
        return { RecvKind::None, {} };
    }

    const char* rt = ts_node_type( recvNode );
    if( std::strcmp( rt, "this" ) == 0 )
    {
        return { RecvKind::ThisObj, {} }; // C++ `this->m()`
    }

    if( std::strcmp( rt, "identifier" ) == 0 )
    {
        const std::uint32_t a = ts_node_start_byte( recvNode ), b = ts_node_end_byte( recvNode );
        if( a > b || b > src.size() )
        {
            return { RecvKind::None, {} };
        }
        std::string_view v = src.substr( a, b - a );
        if( lang == Lang::Python && v == "self" )
        {
            return { RecvKind::ThisObj, {} }; // Python `self.m()`
        }
        return { RecvKind::NamedVar, std::string( v ) };                              // `x->m()` / `x.m()` — Rule 2 fuel
    }
    return { RecvKind::None, {} };   // chained / parenthesized / subscripted receiver → not one-hop
}

// ── P2-D Rule 2 LOCAL-VARIABLE TYPE BINDING capture (`Foo x;` → x:Foo) ───────────────────────────────
// Walk a node subtree and emit one RawBind per local variable whose TYPE is syntactically decidable, so a
// later `x.m()`/`x->m()` can narrow to `typeName::m`. Pure-syntactic, deterministic, allocation-light:
// it reads exactly the declaration/assignment shapes ground-truthed from the grammars (see the gate fixtures).
//   * The recorded typeName is the WRITTEN type's final segment (`ns::Foo` → `Foo`). It is matched against
//     class/struct symbol NAMES in buildGraph, which is the conservative safety net: an inferred type from a
//     constructor-call (`auto x = Foo()`) only narrows if `Foo` actually names a class — else it drops.
//   * Only the named-receiver shape is useful downstream, so only bare-identifier targets are recorded
//     (member targets `self.x`/`obj.f` are not — `receiverOf` doesn't capture those as recvVar either).

// the innermost bare `(identifier)` reached by unwrapping pointer/reference/parenthesized declarators —
// the actual variable name of a C++ declarator. "" if the declarator isn't a single named variable.
inline std::string_view declaratorVarName( TSNode decl, std::string_view src )
{
    for( int guard = 0; guard < 8 && !ts_node_is_null( decl ); ++guard )
    {
        const char* dt = ts_node_type( decl );
        if( std::strcmp( dt, "identifier" ) == 0 )
        {
            const std::uint32_t a = ts_node_start_byte( decl ), b = ts_node_end_byte( decl );
            return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
        }
        // unwrap a pointer/reference/parenthesized declarator to its inner `declarator` child
        const TSNode inner = ts_node_child_by_field_name( decl, "declarator", 10 );
        if( ts_node_is_null( inner ) )
        {
            return {};
        }
        decl = inner;
    }
    return {};
}

// the type NAME of a constructor-style RHS value node: `Foo()` (call_expression) or `new Foo()`
// (new_expression). Final segment of the callee/constructor identifier. "" if the value isn't a
// plain constructor call (so `auto x = makeFoo()` infers nothing here unless `makeFoo` names a class —
// and the class-name filter in buildGraph is what makes that safe).
inline std::string ctorTypeOf( TSNode value, std::string_view src )
{
    if( ts_node_is_null( value ) )
    {
        return {};
    }
    const char* vt = ts_node_type( value );
    TSNode      idn {};
    if( std::strcmp( vt, "call_expression" ) == 0 )
    { // C++/TS `Foo()`
        idn = ts_node_child_by_field_name( value, "function", 8 );
    }
    else if( std::strcmp( vt, "new_expression" ) == 0 )
    { // C++/TS `new Foo()`
        idn = ts_node_child_by_field_name( value, "constructor", 11 );
    }
    if( ts_node_is_null( idn ) )
    {
        return {};
    }
    const char* it = ts_node_type( idn );
    if( std::strcmp( it, "identifier" ) != 0 && std::strcmp( it, "type_identifier" ) != 0 && std::strcmp( it, "qualified_identifier" ) != 0 && std::strcmp( it, "scoped_identifier" ) != 0 )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( idn ), b = ts_node_end_byte( idn );
    return ( a <= b && b <= src.size() ) ? finalSegment( src.substr( a, b - a ) ) : std::string{};
}

// the written type name of a `type:`-field type node (`type_identifier`, or a qualified/scoped one). "" for
// `auto`/`placeholder_type_specifier`/templated/decltype types — those fall back to constructor inference.
inline std::string writtenTypeOf( TSNode typeNode, std::string_view src )
{
    if( ts_node_is_null( typeNode ) )
    {
        return {};
    }
    const char* tt = ts_node_type( typeNode );
    if( std::strcmp( tt, "type_identifier" ) == 0 || std::strcmp( tt, "qualified_identifier" ) == 0
        || std::strcmp( tt, "scoped_type_identifier" ) == 0 )
    {
        const std::uint32_t a = ts_node_start_byte( typeNode ), b = ts_node_end_byte( typeNode );
        return ( a <= b && b <= src.size() ) ? finalSegment( src.substr( a, b - a ) ) : std::string{};
    }
    return {};   // auto / template / decltype — type not directly written → try the initializer
}

// emit a binding from one declared variable: prefer the WRITTEN type; else infer from a constructor-style
// initializer (`auto x = Foo()`). Records nothing when neither is decidable (degrade to §2a).
inline void emitBind( std::uint32_t fileId, Lang lang, std::string_view var, std::string typeName,
                      std::uint32_t startByte, std::vector<RawBind>& binds )
{
    if( var.empty() || typeName.empty() )
    {
        return;
    }
    RawBind b;
    b.fileId    = fileId;
    b.startByte = startByte;
    b.lang      = lang;
    b.var.assign( var );
    b.typeName  = std::move( typeName );
    binds.push_back( std::move( b ) );
}

void captureBindings( TSNode root, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<RawBind>& binds, int startDepth )
{
    // iterative pre-order DFS (explicit frame stack) — this frame held several std::string locals, so the
    // recursive form overflowed the 512 KB macOS worker-thread stack well inside the old depth guard.
    // Children are pushed in reverse so pops preserve the original left-to-right visit order.
    struct BindFrame { TSNode node; std::uint16_t depth; };
    std::vector<BindFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { root, static_cast<std::uint16_t>( startDepth ) } );
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );

    while( !stack.empty() )
    {
    const BindFrame frame = stack.back();
    stack.pop_back();
    if( frame.depth > 256 )
    {
        continue; // pathological-AST guard (file already ≤ 1 MB)
    }
    const TSNode n = frame.node;
    const char* t = ts_node_type( n );

    // C++/ObjC: `Foo x;` · `Foo* x;` · `Foo x = Foo();` · `auto x = Foo();`
    if( ( lang == Lang::Cpp || lang == Lang::ObjC ) && std::strcmp( t, "declaration" ) == 0 )
    {
        const TSNode typeNode = ts_node_child_by_field_name( n, "type", 4 );
        std::string  written  = writtenTypeOf( typeNode, src );
        // a `declaration` can declare several variables (`Foo a, b;`) → one binding per declarator child.
        const std::uint32_t cc = ts_node_child_count( n );
        for( std::uint32_t i = 0; i < cc; ++i )
        {
            const TSNode c  = ts_node_child( n, i );
            if( ts_node_field_name_for_child( n, i ) == nullptr )
            {
                continue;
            }
            if( std::strcmp( ts_node_field_name_for_child( n, i ), "declarator" ) != 0 )
            {
                continue;
            }
            const char* ct = ts_node_type( c );
            // `init_declarator`: name lives in its `declarator`, the RHS in its `value` (for auto inference)
            if( std::strcmp( ct, "init_declarator" ) == 0 )
            {
                const std::string_view var  = declaratorVarName( ts_node_child_by_field_name( c, "declarator", 10 ), src );
                std::string            type = written.empty() ? ctorTypeOf( ts_node_child_by_field_name( c, "value", 5 ), src ) : written;
                emitBind( fileId, lang, var, std::move( type ), ts_node_start_byte( n ), binds );
            }
            else   // plain declarator (identifier / pointer_declarator / reference_declarator), no initializer
            {
                emitBind( fileId, lang, declaratorVarName( c, src ), std::string( written ), ts_node_start_byte( n ), binds );
            }
        }
    }
    // C++ `x = Foo();` (re-assignment to a constructor) — assignment_expression inside an expression_statement.
    else if( ( lang == Lang::Cpp || lang == Lang::ObjC ) && std::strcmp( t, "assignment_expression" ) == 0 )
    {
        const TSNode lhs = ts_node_child_by_field_name( n, "left",  4 );
        const TSNode rhs = ts_node_child_by_field_name( n, "right", 5 );
        if( !ts_node_is_null( lhs ) && std::strcmp( ts_node_type( lhs ), "identifier" ) == 0 )
        {
            const std::uint32_t a = ts_node_start_byte( lhs ), b = ts_node_end_byte( lhs );
            if( a <= b && b <= src.size() )
            {
                emitBind( fileId, lang, src.substr( a, b - a ), ctorTypeOf( rhs, src ), ts_node_start_byte( n ), binds );
            }
        }
    }
    // Python `x = Foo()` — assignment with a bare-identifier LHS and a constructor-call RHS.
    else if( lang == Lang::Python && std::strcmp( t, "assignment" ) == 0 )
    {
        const TSNode lhs = ts_node_child_by_field_name( n, "left",  4 );
        const TSNode rhs = ts_node_child_by_field_name( n, "right", 5 );
        if( !ts_node_is_null( lhs ) && std::strcmp( ts_node_type( lhs ), "identifier" ) == 0 )
        {
            const std::uint32_t a = ts_node_start_byte( lhs ), b = ts_node_end_byte( lhs );
            if( a <= b && b <= src.size() )
            {
                // Python RHS constructor is a `call` node (not `call_expression`); reuse finalSegment on its callee.
                std::string type;
                if( !ts_node_is_null( rhs ) && std::strcmp( ts_node_type( rhs ), "call" ) == 0 )
                {
                    const TSNode fn = ts_node_child_by_field_name( rhs, "function", 8 );
                    if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "identifier" ) == 0 )
                    {
                        const std::uint32_t fa = ts_node_start_byte( fn ), fb = ts_node_end_byte( fn );
                        if( fa <= fb && fb <= src.size() )
                        {
                            type = finalSegment( src.substr( fa, fb - fa ) );
                        }
                    }
                }
                emitBind( fileId, lang, src.substr( a, b - a ), std::move( type ), ts_node_start_byte( n ), binds );
            }
        }
    }
    // TypeScript `const x = new Foo();` · `let y: Bar = ...;` — variable_declarator.
    else if( lang == Lang::TypeScript && std::strcmp( t, "variable_declarator" ) == 0 )
    {
        const TSNode nameNode = ts_node_child_by_field_name( n, "name", 4 );
        if( !ts_node_is_null( nameNode ) && std::strcmp( ts_node_type( nameNode ), "identifier" ) == 0 )
        {
            const std::uint32_t a = ts_node_start_byte( nameNode ), b = ts_node_end_byte( nameNode );
            if( a <= b && b <= src.size() )
            {
                // prefer the `: Type` annotation; else infer from a `new Foo()` / `Foo()` initializer.
                std::string type;
                const TSNode ann = ts_node_child_by_field_name( n, "type", 4 );   // type_annotation
                if( !ts_node_is_null( ann ) )
                {
                    const std::uint32_t cc = ts_node_child_count( ann );
                    for( std::uint32_t i = 0; i < cc; ++i )
                    {
                        const TSNode c = ts_node_child( ann, i );
                        if( std::strcmp( ts_node_type( c ), "type_identifier" ) == 0 )
                        { const std::uint32_t ta = ts_node_start_byte( c ), tb = ts_node_end_byte( c );
                          if( ta <= tb && tb <= src.size() ) { type = finalSegment( src.substr( ta, tb - ta ) ); } break; }
                    }
                }
                if( type.empty() )
                {
                    type = ctorTypeOf( ts_node_child_by_field_name( n, "value", 5 ), src );
                }
                emitBind( fileId, lang, src.substr( a, b - a ), std::move( type ), ts_node_start_byte( n ), binds );
            }
        }
    }

    collectChildren( n, cursor.cur, kids );
    for( std::size_t i = kids.size(); i > 0; --i )
    {
        stack.push_back( { kids[i - 1], static_cast<std::uint16_t>( frame.depth + 1 ) } );
    }
    }
}

// ── A4-R5 CROSS-LANGUAGE FFI BINDING capture (pybind11 · extern "C" · ctypes handle) ─────────────────
// Walk a C/C++ or Python subtree and emit one BindingAlias per language-binding DECLARATION, so buildGraph
// can add a provenance-tagged FALLBACK edge across the language border. Pure-syntactic, deterministic. The
// pybind pass is GATED on a `pybind11`/`PYBIND11` signal in the file, so a repo without pybind captures
// NOTHING (the whole feature is inert → byte-identical output on any binding-free corpus). JNI needs no
// capture here — buildGraph decodes it straight from `Java_*` def names.
inline std::string ffiUnquote( std::string_view s )   // strip one layer of "..." / '...'; leaves interior verbatim
{
    if( s.size() >= 2 && ( s.front() == '"' || s.front() == '\'' ) && s.back() == s.front() )
    {
        return std::string( s.substr( 1, s.size() - 2 ) );
    }
    return std::string( s );
}

// "A::B::method" → { scope="B", name="method" }; "foo" → { "", "foo" }. Scope is the IMMEDIATE enclosing
// segment (matches buildGraph's canonByName keying); name is the final identifier segment.
inline std::pair<std::string, std::string> ffiSplitScopeName( std::string_view text )
{
    const std::size_t sep = text.rfind( "::" );
    if( sep == std::string_view::npos )
    {
        return { std::string(), finalSegment( text ) };
    }
    return { finalSegment( text.substr( 0, sep ) ), finalSegment( text.substr( sep + 2 ) ) };
}

void captureFfi( TSNode root, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<BindingAlias>& ffis )
{
    const bool cish = ( lang == Lang::Cpp || lang == Lang::ObjC );
    const bool py   = ( lang == Lang::Python );
    if( !cish && !py )
    {
        return;
    }
    // pybind is gated on a cheap file-level signal so ordinary `.def(` calls in non-pybind C++ never capture.
    const bool hasPybind = cish && ( src.find( "pybind11" ) != std::string_view::npos
                                  || src.find( "PYBIND11" ) != std::string_view::npos );

    const auto nodeSrc = [ & ]( TSNode nn ) noexcept -> std::string_view
    {
        if( ts_node_is_null( nn ) )
        {
            return {};
        }
        const std::uint32_t a = ts_node_start_byte( nn ), b = ts_node_end_byte( nn );
        return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
    };

    struct FfiFrame { TSNode node; std::uint16_t depth; };
    std::vector<FfiFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { root, 0 } );
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );
    while( !stack.empty() )
    {
        const FfiFrame frame = stack.back();
        stack.pop_back();
        if( frame.depth > 256 )
        {
            continue;
        }
        const TSNode n = frame.node;
        const char*  t = ts_node_type( n );

        // pybind11:  m.def("alias", &target)  /  cls.def("alias", &Scope::method)  /  .def_static(...)
        if( hasPybind && std::strcmp( t, "call_expression" ) == 0 )
        {
            const TSNode fn = ts_node_child_by_field_name( n, "function", 8 );
            if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "field_expression" ) == 0 )
            {
                const std::string_view meth = nodeSrc( ts_node_child_by_field_name( fn, "field", 5 ) );
                if( meth == "def" || meth == "def_static" )
                {
                    const TSNode args = ts_node_child_by_field_name( n, "arguments", 9 );
                    std::string alias, tgt;
                    const std::uint32_t cc = ts_node_is_null( args ) ? 0 : ts_node_child_count( args );
                    for( std::uint32_t i = 0; i < cc; ++i )
                    {
                        const TSNode c = ts_node_child( args, i );
                        if( !ts_node_is_named( c ) )
                        {
                            continue; // skip '(' ',' ')'
                        }
                        const std::string_view ct = ts_node_type( c );
                        if( alias.empty() && ct == "string_literal" )
                        {
                            alias = ffiUnquote( nodeSrc( c ) );
                        }
                        else if( tgt.empty() )
                        {
                            std::string_view txt = nodeSrc( c );               // `&target` / `&Scope::method`
                            if( !txt.empty() && txt.front() == '&' )
                            {
                                txt.remove_prefix( 1 );
                                while( !txt.empty() && ( txt.front() == ' ' || txt.front() == '\t' ) )
                                {
                                    txt.remove_prefix( 1 );
                                }
                                tgt = std::string( txt );
                            }
                        }
                    }
                    if( !alias.empty() && !tgt.empty() )
                    {
                        auto [ scope, name ] = ffiSplitScopeName( tgt );
                        if( !name.empty() )
                        {
                            ffis.push_back( BindingAlias{ fileId, BindKind::Pybind, false, std::move( alias ), std::move( name ), std::move( scope ) } );
                        }
                    }
                }
            }
        }
        // extern "C": every function DECLARED inside becomes reachable from ctypes/cffi/cgo by its bare name.
        else if( cish && std::strcmp( t, "linkage_specification" ) == 0 )
        {
            // confirm the linkage string is "C" (not "C++") before harvesting.
            bool isC = false;
            const std::uint32_t lc = ts_node_child_count( n );
            for( std::uint32_t i = 0; i < lc; ++i )
            {
                const TSNode c = ts_node_child( n, i );
                if( std::strcmp( ts_node_type( c ), "string_literal" ) == 0 ) { isC = ( ffiUnquote( nodeSrc( c ) ) == "C" ); break; }
            }
            if( isC )
            {
                // inner DFS: collect the identifier of every function_declarator in the linkage body.
                std::vector<TSNode> inner;
                inner.push_back( n );
                while( !inner.empty() )
                {
                    const TSNode m = inner.back();
                    inner.pop_back();
                    if( std::strcmp( ts_node_type( m ), "function_declarator" ) == 0 )
                    {
                        const TSNode decl = ts_node_child_by_field_name( m, "declarator", 10 );
                        if( !ts_node_is_null( decl ) )
                        {
                            const char* dt = ts_node_type( decl );
                            if( std::strcmp( dt, "identifier" ) == 0 || std::strcmp( dt, "field_identifier" ) == 0 )
                            {
                                std::string nm = finalSegment( nodeSrc( decl ) );
                                if( !nm.empty() )
                                {
                                    ffis.push_back( BindingAlias{ fileId, BindKind::ExternC, true, nm, nm, std::string() } );
                                }
                            }
                        }
                    }
                    const std::uint32_t mc = ts_node_child_count( m );
                    for( std::uint32_t i = 0; i < mc; ++i )
                    {
                        inner.push_back( ts_node_child( m, i ) );
                    }
                }
            }
        }
        // Python ctypes handle:  lib = CDLL(...)  /  lib = ctypes.CDLL(...)  /  lib = cdll.LoadLibrary(...)
        else if( py && std::strcmp( t, "assignment" ) == 0 )
        {
            const TSNode lhs = ts_node_child_by_field_name( n, "left",  4 );
            const TSNode rhs = ts_node_child_by_field_name( n, "right", 5 );
            if( !ts_node_is_null( lhs ) && std::strcmp( ts_node_type( lhs ), "identifier" ) == 0
                && !ts_node_is_null( rhs ) && std::strcmp( ts_node_type( rhs ), "call" ) == 0 )
            {
                const std::string_view ftext = nodeSrc( ts_node_child_by_field_name( rhs, "function", 8 ) );
                const std::string      seg   = finalSegment( ftext.substr( 0, ftext.find( '(' ) ) );   // final `.`/`::` segment
                const bool loader = seg == "CDLL" || seg == "WinDLL" || seg == "OleDLL" || seg == "PyDLL"
                                 || seg == "LoadLibrary" || seg == "dlopen";
                if( loader )
                {
                    std::string var( nodeSrc( lhs ) );
                    if( !var.empty() )
                    {
                        ffis.push_back( BindingAlias{ fileId, BindKind::CtypesHandle, true, std::move( var ), std::string(), std::string() } );
                    }
                }
            }
        }

        collectChildren( n, cursor.cur, kids );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], static_cast<std::uint16_t>( frame.depth + 1 ) } );
        }
    }
}

// ── B6.3 HTTP-route DEF/USE capture (Express/Fastify · FastAPI/Flask decorators · fetch/axios/requests) ──
// Walk a JS/TS or Python subtree and emit a RouteDef per recognized server-side route registration and a
// RawRouteUse per recognized client-side HTTP call. Pure-syntactic, deterministic, table-driven (the verb
// name → HttpMethod lookup is model.h::kHttpMethodTable, shared by every detector below). Server detectors
// are GATED on a cheap file-level framework signal — the SAME posture as captureFfi's pybind gate above: a
// file that never mentions the framework captures NO route DEF, so the whole feature is inert (byte-
// identical output) on a framework-free corpus. Client detectors need no file gate: `fetch`, `axios.<verb>`,
// `requests.<verb>` are distinctive enough as bare shapes (the object identifier is checked EXACTLY).
// KNOWN LIMITATION (by design, never guessed): a path built from a template literal / f-string / variable
// is NOT a plain "string" node, so it is not captured — only static path literals are detected.

// the first NAMED argument in an `arguments`/`argument_list` node, iff it is a plain "string" literal
// starting with '/' once unquoted — a path-looking literal. "" for anything else (template/f-string,
// identifier, no args): a dynamic path is a deliberate non-detection, never a guess.
inline std::string firstPathStringArg( TSNode argsNode, std::string_view src )
{
    if( ts_node_is_null( argsNode ) || ts_node_named_child_count( argsNode ) == 0 )
    {
        return {};
    }
    const TSNode first = ts_node_named_child( argsNode, 0 );
    if( std::strcmp( ts_node_type( first ), "string" ) != 0 )
    {
        return {}; // template_string/f-string/identifier → skip
    }
    const std::uint32_t a = ts_node_start_byte( first ), b = ts_node_end_byte( first );
    if( a > b || b > src.size() )
    {
        return {};
    }
    std::string path = ffiUnquote( src.substr( a, b - a ) );
    if( path.empty() || path.front() != '/' )
    {
        return {};
    }
    return path;
}

// the LAST named argument's handler name: a bare identifier, or the final `.property` segment of a member
// access (`userController.getUser` → "getUser"). "" for an inline function/arrow expression (anonymous —
// the DEF fact is still recorded; buildGraph just can never attach an edge to it).
inline std::string lastArgHandlerName( TSNode argsNode, std::string_view src )
{
    if( ts_node_is_null( argsNode ) )
    {
        return {};
    }
    const std::uint32_t nc = ts_node_named_child_count( argsNode );
    if( nc == 0 )
    {
        return {};
    }
    const TSNode last = ts_node_named_child( argsNode, nc - 1 );
    const char*  lt   = ts_node_type( last );
    const auto   text = [ & ]( TSNode nn ) -> std::string_view
    {
        const std::uint32_t a = ts_node_start_byte( nn ), b = ts_node_end_byte( nn );
        return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
    };
    if( std::strcmp( lt, "identifier" ) == 0 )
    {
        return finalSegment( text( last ) );
    }
    if( std::strcmp( lt, "member_expression" ) == 0 )
    {
        const TSNode prop = ts_node_child_by_field_name( last, "property", 8 );
        if( !ts_node_is_null( prop ) )
        {
            return finalSegment( text( prop ) );
        }
    }
    return {};   // arrow_function / function_expression / anything else → inline, no name
}

// Flask `methods=[...]` keyword argument: a single-method list resolves to that verb; absent/empty/multi
// ⇒ the caller applies its own default (Flask defaults to GET when `methods=` is absent entirely).
// shared tail of every keyword-argument / options-object method extractor below: a "string" node's
// unquoted, lowercased text, resolved through model.h::kHttpMethodTable. Unknown for anything that isn't
// a plain string literal (never guess).
inline HttpMethod stringNodeToMethod( TSNode strNode, std::string_view src )
{
    if( ts_node_is_null( strNode ) || std::strcmp( ts_node_type( strNode ), "string" ) != 0 )
    {
        return HttpMethod::Unknown;
    }
    const std::uint32_t a = ts_node_start_byte( strNode ), b = ts_node_end_byte( strNode );
    if( a > b || b > src.size() )
    {
        return HttpMethod::Unknown;
    }
    std::string verb = ffiUnquote( src.substr( a, b - a ) );
    for( char& ch : verb )
    {
        ch = char( std::tolower( static_cast<unsigned char>( ch ) ) );
    }
    return httpMethodFromName( verb );
}

inline HttpMethod pyMethodsKeyword( TSNode argsNode, std::string_view src, bool& hasKeyword )
{
    hasKeyword = false;
    if( ts_node_is_null( argsNode ) )
    {
        return HttpMethod::Unknown;
    }
    const std::uint32_t nc = ts_node_named_child_count( argsNode );
    for( std::uint32_t i = 0; i < nc; ++i )
    {
        const TSNode c = ts_node_named_child( argsNode, i );
        if( std::strcmp( ts_node_type( c ), "keyword_argument" ) != 0 )
        {
            continue;
        }
        const TSNode nameN = ts_node_child_by_field_name( c, "name", 4 );
        if( ts_node_is_null( nameN ) )
        {
            continue;
        }
        const std::uint32_t na = ts_node_start_byte( nameN ), nb = ts_node_end_byte( nameN );
        if( na > nb || nb > src.size() || src.substr( na, nb - na ) != "methods" )
        {
            continue;
        }
        hasKeyword = true;
        const TSNode valueN = ts_node_child_by_field_name( c, "value", 5 );
        if( ts_node_is_null( valueN ) || std::strcmp( ts_node_type( valueN ), "list" ) != 0 )
        {
            return HttpMethod::Unknown;
        }
        if( ts_node_named_child_count( valueN ) != 1 )
        {
            return HttpMethod::Unknown; // 0 or >1 verbs → ambiguous, path-only match
        }
        return stringNodeToMethod( ts_node_named_child( valueN, 0 ), src );
    }
    return HttpMethod::Unknown;
}

// JS options-object `{ method: 'POST', ... }`: the `method` property's string-literal value, else Unknown
// (never guess — an absent/non-literal method key leaves the USE's method Unknown, which matches ANY DEF
// method per routematch::methodsCompatible in graph.h).
inline HttpMethod jsMethodProperty( TSNode objNode, std::string_view src )
{
    if( ts_node_is_null( objNode ) || std::strcmp( ts_node_type( objNode ), "object" ) != 0 )
    {
        return HttpMethod::Unknown;
    }
    const std::uint32_t nc = ts_node_named_child_count( objNode );
    for( std::uint32_t i = 0; i < nc; ++i )
    {
        const TSNode c = ts_node_named_child( objNode, i );
        if( std::strcmp( ts_node_type( c ), "pair" ) != 0 )
        {
            continue;
        }
        const TSNode keyN = ts_node_child_by_field_name( c, "key", 3 );
        if( ts_node_is_null( keyN ) )
        {
            continue;
        }
        const char* kt = ts_node_type( keyN );
        const std::uint32_t ka = ts_node_start_byte( keyN ), kb = ts_node_end_byte( keyN );
        if( ka > kb || kb > src.size() )
        {
            continue;
        }
        std::string key;
        if( std::strcmp( kt, "property_identifier" ) == 0 )
        {
            key = std::string( src.substr( ka, kb - ka ) );
        }
        else if( std::strcmp( kt, "string" ) == 0 )
        {
            key = ffiUnquote( src.substr( ka, kb - ka ) );
        }
        else
        {
            continue;
        }
        if( key != "method" )
        {
            continue;
        }
        return stringNodeToMethod( ts_node_child_by_field_name( c, "value", 5 ), src );
    }
    return HttpMethod::Unknown;
}

void captureRoutes( TSNode root, std::uint32_t fileId, Lang lang, std::string_view src,
                    std::vector<RouteDef>& routeDefs, std::vector<RawRouteUse>& routeUses )
{
    const bool py = ( lang == Lang::Python );
    const bool js = ( lang == Lang::TypeScript || lang == Lang::JavaScript );
    if( !py && !js )
    {
        return;
    }

    const bool pyServerGated = py && ( src.find( "fastapi" ) != std::string_view::npos || src.find( "FastAPI" ) != std::string_view::npos
                                     || src.find( "flask" )   != std::string_view::npos || src.find( "Flask" )   != std::string_view::npos );
    const bool jsServerGated = js && ( src.find( "express" ) != std::string_view::npos || src.find( "fastify" ) != std::string_view::npos );

    const auto nodeSrc = [ & ]( TSNode nn ) noexcept -> std::string_view
    {
        if( ts_node_is_null( nn ) )
        {
            return {};
        }
        const std::uint32_t a = ts_node_start_byte( nn ), b = ts_node_end_byte( nn );
        return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
    };

    struct RouteFrame { TSNode node; std::uint16_t depth; };
    std::vector<RouteFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { root, 0 } );
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );
    while( !stack.empty() )
    {
        const RouteFrame frame = stack.back();
        stack.pop_back();
        if( frame.depth > 256 )
        {
            continue;
        }
        const TSNode n = frame.node;
        const char*  t = ts_node_type( n );

        // Python server: @app.get("/path") / @app.route("/path", methods=[...]) directly above a def.
        if( pyServerGated && std::strcmp( t, "decorated_definition" ) == 0 )
        {
            const TSNode defNode = ts_node_child_by_field_name( n, "definition", 10 );
            std::string  handlerName;
            if( !ts_node_is_null( defNode ) && std::strcmp( ts_node_type( defNode ), "function_definition" ) == 0 )
            {
                const TSNode nameNode = ts_node_child_by_field_name( defNode, "name", 4 );
                if( !ts_node_is_null( nameNode ) )
                {
                    handlerName.assign( nodeSrc( nameNode ) );
                }
            }
            const std::uint32_t cc = ts_node_child_count( n );
            for( std::uint32_t i = 0; i < cc; ++i )
            {
                const TSNode dec = ts_node_child( n, i );
                if( std::strcmp( ts_node_type( dec ), "decorator" ) != 0 )
                {
                    continue;
                }
                const TSNode expr = ts_node_named_child( dec, 0 );
                if( ts_node_is_null( expr ) || std::strcmp( ts_node_type( expr ), "call" ) != 0 )
                {
                    continue;
                }
                const TSNode fn = ts_node_child_by_field_name( expr, "function", 8 );
                if( ts_node_is_null( fn ) || std::strcmp( ts_node_type( fn ), "attribute" ) != 0 )
                {
                    continue;
                }
                const std::string_view attrName = nodeSrc( ts_node_child_by_field_name( fn, "attribute", 9 ) );
                const TSNode argsNode = ts_node_child_by_field_name( expr, "arguments", 9 );
                const std::string path = firstPathStringArg( argsNode, src );
                if( path.empty() )
                {
                    continue;
                }

                HttpMethod method = HttpMethod::Unknown;
                if( attrName == "route" )
                {
                    bool hasKeyword = false;
                    const HttpMethod fromKeyword = pyMethodsKeyword( argsNode, src, hasKeyword );
                    method = hasKeyword ? fromKeyword : HttpMethod::Get;   // Flask default: GET when methods= absent
                }
                else
                {
                    method = httpMethodFromName( attrName );
                    if( method == HttpMethod::Unknown )
                    {
                        continue; // not a recognized verb shortcut (e.g. .on_event)
                    }
                }
                routeDefs.push_back( RouteDef{ fileId, ts_node_start_point( n ).row + 1, method, path, handlerName } );
            }
        }
        // JS/TS: ONE dispatch over every call_expression — client shapes (`fetch`, `axios.<verb>`) are
        // checked FIRST and UNCONDITIONALLY (their callee shape is specific enough to need no file gate),
        // so a server-gated file's axios/fetch calls are NEVER misread as a route DEF; app.get(...)/
        // router.post(...) is the gated FALLBACK, tried only when neither client shape matched. This also
        // fixes the structural trap an `if/else if` split on `jsServerGated` vs `js` would fall into: once
        // the (possibly file-gated) branch claims a call_expression, an else-if chain never lets the OTHER
        // shape see that same node.
        else if( js && std::strcmp( t, "call_expression" ) == 0 )
        {
            const TSNode fn = ts_node_child_by_field_name( n, "function", 8 );
            bool handled = false;

            if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "identifier" ) == 0 && nodeSrc( fn ) == "fetch" )
            {
                const TSNode argsNode = ts_node_child_by_field_name( n, "arguments", 9 );
                const std::string path = firstPathStringArg( argsNode, src );
                if( !path.empty() )
                {
                    HttpMethod method = HttpMethod::Get;   // fetch's documented default when no options object
                    if( ts_node_named_child_count( argsNode ) >= 2 )
                    {
                        method = jsMethodProperty( ts_node_named_child( argsNode, 1 ), src );
                    }
                    routeUses.push_back( RawRouteUse{ fileId, ts_node_start_byte( n ), ts_node_start_point( n ).row + 1, method, path } );
                }
                handled = true;   // "fetch(...)" is never ALSO a server registrar shape
            }
            else if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "member_expression" ) == 0 )
            {
                const TSNode objN = ts_node_child_by_field_name( fn, "object", 6 );
                if( !ts_node_is_null( objN ) && std::strcmp( ts_node_type( objN ), "identifier" ) == 0 && nodeSrc( objN ) == "axios" )
                {
                    const TSNode propN     = ts_node_child_by_field_name( fn, "property", 8 );
                    const HttpMethod method = httpMethodFromName( nodeSrc( propN ) );
                    if( method != HttpMethod::Unknown )
                    {
                        const TSNode argsNode = ts_node_child_by_field_name( n, "arguments", 9 );
                        const std::string path = firstPathStringArg( argsNode, src );
                        if( !path.empty() )
                        {
                            routeUses.push_back( RawRouteUse{ fileId, ts_node_start_byte( n ), ts_node_start_point( n ).row + 1, method, path } );
                        }
                    }
                    handled = true;   // "axios.<verb>(...)" is never ALSO a server registrar shape
                }
            }

            // JS/TS server FALLBACK: app.get('/path', handler) / router.post('/path', mw, handler) — last
            // arg = handler. Only tried when the callee wasn't already claimed by a client shape above, and
            // only on a file-level framework signal (captureFfi's pybind-gate posture).
            if( !handled && jsServerGated && !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "member_expression" ) == 0 )
            {
                const TSNode propN     = ts_node_child_by_field_name( fn, "property", 8 );
                const HttpMethod method = httpMethodFromName( nodeSrc( propN ) );
                if( method != HttpMethod::Unknown )
                {
                    const TSNode argsNode = ts_node_child_by_field_name( n, "arguments", 9 );
                    const std::string path = firstPathStringArg( argsNode, src );
                    if( !path.empty() )
                    {
                        const std::string handlerName = lastArgHandlerName( argsNode, src );
                        routeDefs.push_back( RouteDef{ fileId, ts_node_start_point( n ).row + 1, method, path, handlerName } );
                    }
                }
            }
        }
        // Python client: requests.get('/path') / requests.post('/path', json=...)
        else if( py && std::strcmp( t, "call" ) == 0 )
        {
            const TSNode fn = ts_node_child_by_field_name( n, "function", 8 );
            if( !ts_node_is_null( fn ) && std::strcmp( ts_node_type( fn ), "attribute" ) == 0 )
            {
                const TSNode objN = ts_node_child_by_field_name( fn, "object", 6 );
                if( !ts_node_is_null( objN ) && std::strcmp( ts_node_type( objN ), "identifier" ) == 0 && nodeSrc( objN ) == "requests" )
                {
                    const TSNode attrN     = ts_node_child_by_field_name( fn, "attribute", 9 );
                    const HttpMethod method = httpMethodFromName( nodeSrc( attrN ) );
                    if( method != HttpMethod::Unknown )
                    {
                        const TSNode argsNode = ts_node_child_by_field_name( n, "arguments", 9 );
                        const std::string path = firstPathStringArg( argsNode, src );
                        if( !path.empty() )
                        {
                            routeUses.push_back( RawRouteUse{ fileId, ts_node_start_byte( n ), ts_node_start_point( n ).row + 1, method, path } );
                        }
                    }
                }
            }
        }

        collectChildren( n, cursor.cur, kids );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], static_cast<std::uint16_t>( frame.depth + 1 ) } );
        }
    }
}

// ── ABS-3 READ / WRITE use-site capture ──────────────────────────────────────────────────────────────
// Walk a subtree and record every IDENTIFIER reference that is a value READ or an assignment WRITE, so the
// use-site index can report read-vs-write per site. The call sites (`f()` / `x.m()`) are already captured
// by the tags query as @reference.call (role=Call); the inheritance/import sites by captureBases/Includes —
// so this walk deliberately EXCLUDES those to avoid double-counting:
//   * the function-position identifier of a call (`foo` in `foo()`, `m` in `x.m()`) → already a Call ref.
//   * a definition's own name / declarator (`x` in `int x;`, `f` in `void f(){}`) → a DEF, not a use.
//   * type positions (`Foo` in `Foo x;`) → captured as inherit/compose where relevant, not a value use.
// WRITE classification (the precision-critical half): an identifier is a Write iff it is the LHS target of
//   an assignment_expression / augmented assignment (C++ `=` `+=` … are all assignment_expression; Python
//   `assignment` / `augmented_assignment`) OR the operand of a `++`/`--` (`update_expression`). Everything
//   else that references a name in a value position is a Read. Pure-syntactic, deterministic.

// two AST nodes refer to the SAME source token iff they span the identical [start,end) byte range. Used to
// test "is THIS identifier the node sitting in field X of its parent" without depending on ts_node_eq.
inline bool sameSpan( TSNode a, TSNode b ) noexcept
{
    return ts_node_start_byte( a ) == ts_node_start_byte( b ) && ts_node_end_byte( a ) == ts_node_end_byte( b );
}

// is `id` the LHS write-target of its enclosing assignment/update? A4-F24: implements the documented contract
// — `a[i] = …` / `p->f = …` make the BASE OBJECT (`a`, `p`) the target, while the index `i` / member `f` stay
// reads. We climb through subscript/field chains while `id` is the base object (the leading sub-expression
// that shares its parent's start byte — the base always begins at the whole `a[i]`/`p->f` expression's first
// byte; the index/member begin later), then test the assignment/update parent of the climbed node.
inline bool isWriteTarget( TSNode id ) noexcept
{
    TSNode node = id;
    for( TSNode up = ts_node_parent( node ); !ts_node_is_null( up ); up = ts_node_parent( node ) )
    {
        const char* ut = ts_node_type( up );
        const bool isSubscriptOrField =    std::strcmp( ut, "subscript_expression" ) == 0   // C/C++ `a[i]`
                                        || std::strcmp( ut, "field_expression" ) == 0        // C/C++ `p->f`, `a.b`
                                        || std::strcmp( ut, "subscript" ) == 0               // Python `a[i]`
                                        || std::strcmp( ut, "attribute" ) == 0;              // Python `a.b`
        if( !( isSubscriptOrField && ts_node_start_byte( up ) == ts_node_start_byte( node ) ) )
        {
            break;                              // `id` is the index/member, or the chain ended → stop climbing
        }
        node = up;                              // `id` is the base object → it inherits the whole a[i]/p->f target-ness
    }

    const TSNode parent = ts_node_parent( node );
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const char* pt = ts_node_type( parent );

    // C++ `x++` / `--x` and Python aug targets handled via update_expression (the operand is the target).
    if( std::strcmp( pt, "update_expression" ) == 0 )
    {
        return true;
    }

    // direct LHS of an assignment: parent is the assignment node and `node` sits in its `left` field.
    const bool isAssign =    std::strcmp( pt, "assignment_expression" ) == 0       // C++ `=` `+=` `-=` …
                          || std::strcmp( pt, "assignment" ) == 0                  // Python `=`
                          || std::strcmp( pt, "augmented_assignment" ) == 0;       // Python `+=` …
    if( isAssign )
    {
        const TSNode lhs = ts_node_child_by_field_name( parent, "left", 4 );
        return !ts_node_is_null( lhs ) && sameSpan( lhs, node );
    }
    return false;
}

// is `id` the callee/function-position name of a call (already captured as a Call ref by the tags query)?
inline bool isCallCallee( TSNode id ) noexcept
{
    const TSNode parent = ts_node_parent( id );
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const char* pt = ts_node_type( parent );

    // bare call `foo()` — the function field is the identifier itself.
    if( std::strcmp( pt, "call_expression" ) == 0 || std::strcmp( pt, "call" ) == 0 )
    {
        const TSNode fn = ts_node_child_by_field_name( parent, "function", 8 );
        return !ts_node_is_null( fn ) && sameSpan( fn, id );
    }
    // member call `x.m()` / `x->m()` — `id` is the field of a field_expression/attribute that is the
    // function of a call. (The receiver `x` is NOT the callee → still captured as a read below.)
    if( std::strcmp( pt, "field_expression" ) == 0 || std::strcmp( pt, "attribute" ) == 0 )
    {
        const TSNode fieldNode = ts_node_child_by_field_name( parent, "field", 5 );
        const TSNode attrNode  = ts_node_child_by_field_name( parent, "attribute", 9 );
        const bool   isField   = ( !ts_node_is_null( fieldNode ) && sameSpan( fieldNode, id ) )
                              || ( !ts_node_is_null( attrNode )  && sameSpan( attrNode,  id ) );
        if( !isField )
        {
            return false;
        }
        const TSNode gp = ts_node_parent( parent );   // the field-access is the callee only when its parent is a call whose `function` is it
        if( ts_node_is_null( gp ) )
        {
            return false;
        }
        const char* gt = ts_node_type( gp );
        if( std::strcmp( gt, "call_expression" ) != 0 && std::strcmp( gt, "call" ) != 0 )
        {
            return false;
        }
        const TSNode fn = ts_node_child_by_field_name( gp, "function", 8 );
        return !ts_node_is_null( fn ) && sameSpan( fn, parent );
    }
    return false;
}

// is `id` in a NON-VALUE context — a name being DEFINED, DECLARED, or part of a qualified/scoped name —
// so it must NOT be counted as a read/write use-site? (Definition NAMES are captured by the tags query;
// qualified-name segments and declarators are not value uses.) Conservative by construction: when in doubt
// we EXCLUDE rather than mislabel — a missed read is far better than reporting a def's own name as a "read".
inline bool isNonValueContext( TSNode id ) noexcept
{
    const TSNode parent = ts_node_parent( id );
    if( ts_node_is_null( parent ) )
    {
        return false;
    }
    const char* pt = ts_node_type( parent );

    // (1) part of a qualified / scoped NAME (`A::process` def name, `A::b()` qualified call name, `ns::T`
    //     type, `A::kConst` qualified value): the segment is not a plain value identifier. Calls/defs of
    //     this shape are captured by the tags query; qualified value reads are intentionally out of scope.
    if( std::strcmp( pt, "qualified_identifier" ) == 0 || std::strcmp( pt, "scoped_identifier" ) == 0 || std::strcmp( pt, "scoped_type_identifier" ) == 0 || std::strcmp( pt, "qualified_type_identifier" ) == 0 || std::strcmp( pt, "template_function" ) == 0 || std::strcmp( pt, "template_type" ) == 0 )
    {
        return true;
    }

    // (2) a declarator's NAME (a DEF/declaration, not a use): `int x;`, `void f()`, `Foo* p`, parameters.
    if(    std::strcmp( pt, "function_declarator" ) == 0 || std::strcmp( pt, "init_declarator" ) == 0
        || std::strcmp( pt, "parameter_declaration" ) == 0 || std::strcmp( pt, "pointer_declarator" ) == 0
        || std::strcmp( pt, "reference_declarator" ) == 0  || std::strcmp( pt, "array_declarator" ) == 0 )
    {
        const TSNode decl = ts_node_child_by_field_name( parent, "declarator", 10 );
        if( !ts_node_is_null( decl ) && sameSpan( decl, id ) )
        {
            return true;
        }
    }
    // (3) Python function / parameter NAME field (a DEF/param, not a use).
    if( std::strcmp( pt, "function_definition" ) == 0 || std::strcmp( pt, "parameters" ) == 0
        || std::strcmp( pt, "typed_parameter" ) == 0 || std::strcmp( pt, "default_parameter" ) == 0
        || std::strcmp( pt, "lambda_parameters" ) == 0 )
    {
        const TSNode nm = ts_node_child_by_field_name( parent, "name", 4 );
        if( ( !ts_node_is_null( nm ) && sameSpan( nm, id ) ) || std::strcmp( pt, "parameters" ) == 0 || std::strcmp( pt, "lambda_parameters" ) == 0 )
        {
            return true;   // every direct child of a parameter list is a param NAME, not a use
        }
    }
    return false;
}

void captureUses( TSNode root, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<RawRef>& refs, int startDepth )
{
    // iterative pre-order DFS (explicit frame stack) — see captureBindings: recursion overflows the 512 KB
    // macOS worker-thread stack on deep ASTs. Reverse-push keeps the original left-to-right visit order.
    struct UseFrame { TSNode node; std::uint16_t depth; };
    std::vector<UseFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { root, static_cast<std::uint16_t>( startDepth ) } );
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );

    while( !stack.empty() )
    {
    const UseFrame frame = stack.back();
    stack.pop_back();
    if( frame.depth > 512 )
    {
        continue; // pathological-AST guard (file already ≤ 1 MB)
    }
    const TSNode n = frame.node;
    const char* t = ts_node_type( n );

    // capture only bare value identifiers (C++ `identifier`, Python `identifier`). field_identifier reads
    // (`obj.field` non-call) are intentionally out of scope — member-field use is a richer relation we keep
    // for a later pass; the gate exercises plain locals/globals, which are `identifier` nodes.
    if( std::strcmp( t, "identifier" ) == 0 )
    {
        if( !isCallCallee( n ) && !isNonValueContext( n ) )
        {
            const std::uint32_t a = ts_node_start_byte( n ), b = ts_node_end_byte( n );
            if( a < b && b <= src.size() )
            {
                RawRef r;
                r.fileId    = fileId;
                r.startByte = a;
                r.line      = ts_node_start_point( n ).row + 1;
                r.lang      = lang;
                r.role      = isWriteTarget( n ) ? RefRole::Write : RefRole::Read;
                r.name      = finalSegment( src.substr( a, b - a ) );   // bare identifier → already final segment
                refs.push_back( std::move( r ) );
            }
        }
    }

    collectChildren( n, cursor.cur, kids );
    for( std::size_t i = kids.size(); i > 0; --i )
    {
        stack.push_back( { kids[i - 1], static_cast<std::uint16_t>( frame.depth + 1 ) } );
    }
    }
}

bool prepareParserFor( TSParser* parser, const LangEntry& le )
{
    const TSLanguage* lang = le.grammar();
    if( lang == nullptr )
    {
        return false;
    }

    if( !ts_parser_set_language( parser, lang ) || !grammarAbiOk( lang ) )
    {
        // never emit a silently-empty tree — say which language we dropped.
        std::fprintf( stderr, "[ripwire] grammar ABI mismatch or set_language failed for %s — skipping language\n",
                      std::string( le.querySub ).c_str() );
        return false;
    }
    return true;
}

TSTree* parseTree( TSParser* parser, std::string_view src )
{
    TSTree* tree = nullptr;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: tree-sitter parse" );
        tree = ts_parser_parse_string( parser, nullptr, src.data(), static_cast<uint32_t>( src.size() ) );
    }
    return tree;
}

struct TreeGuard
{
    TSTree* tree = nullptr;

    explicit TreeGuard( TSTree* treeIn = nullptr ) noexcept : tree( treeIn ) {}
    TreeGuard( const TreeGuard& ) = delete;
    TreeGuard& operator=( const TreeGuard& ) = delete;
    TreeGuard( TreeGuard&& other ) noexcept : tree( other.tree ) { other.tree = nullptr; }
    TreeGuard& operator=( TreeGuard&& other ) noexcept
    {
        if( this != &other )
        {
            if( tree != nullptr )
            {
                ts_tree_delete( tree );
            }
            tree = other.tree;
            other.tree = nullptr;
        }
        return *this;
    }
    ~TreeGuard()
    {
        if( tree != nullptr )
        {
            ts_tree_delete( tree );
        }
    }
    TSTree* get() const noexcept { return tree; }
    TSTree* release() noexcept
    {
        TSTree* out = tree;
        tree = nullptr;
        return out;
    }
};

void captureSideFacts( const LangEntry& le, std::uint32_t fileId, std::string_view src, TSNode root,
                       std::vector<RawRef>& refs, std::vector<Include>& incs, std::vector<RawBind>& binds,
                       std::vector<BindingAlias>& ffis, std::vector<RouteDef>& routeDefs,
                       std::vector<RawRouteUse>& routeUses, bool captureValueUses )
{
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: side captures" );

        captureIncludes( root, le.lang, fileId, src, incs, refs );   // physical deps + ABS-3 import-role use-sites

        // A4-R5: cross-language FFI binding declarations (pybind11 / extern "C" / ctypes handle). Inert on a
        // binding-free file (pybind gated on a file signal; extern-C/ctypes only fire on their exact shapes).
        captureFfi( root, fileId, le.lang, src, ffis );

        // B6.3: HTTP-route DEF/USE facts (Express/Fastify · FastAPI/Flask · fetch/axios/requests). Server
        // detectors gated on a file-level framework signal; inert on a framework-free / non-JS/Python file.
        captureRoutes( root, fileId, le.lang, src, routeDefs, routeUses );

        // Rust IS-A: `impl Trait for T` is a top-level impl_item (sibling of the struct), unreachable from the
        // struct's def-walk — a separate root pass. Derived type name rides `qualifier` (name-resolved in buildGraph).
        if( le.lang == Lang::Rust )
        {
            captureRustImpls( root, fileId, src, refs );
        }

        // P2-D Rule 2: local var→type bindings (`Foo x;`), for receiver-variable narrowing. C++/ObjC/Python/TS
        // (the languages whose receiver shape `receiverOf` captures as a recvVar) — others have no consumer yet.
        if( le.lang == Lang::Cpp || le.lang == Lang::ObjC || le.lang == Lang::Python || le.lang == Lang::TypeScript )
        {
            captureBindings( root, fileId, le.lang, src, binds, 0 );
        }

        // ABS-3: read/write use-site capture (bare value identifiers + assignment targets). C++/ObjC/Python —
        // the languages whose assignment/update grammar shapes isWriteTarget knows. role=Read/Write refs NEVER
        // enter the call graph (buildGraph skips role != Call), so PageRank and the default map are unchanged.
        if( captureValueUses && ( le.lang == Lang::Cpp || le.lang == Lang::ObjC || le.lang == Lang::Python ) )
        {
            captureUses( root, fileId, le.lang, src, refs, 0 );
        }
    }
}

void captureTagsFacts( TSQueryCursor* cursor, const LangEntry& le, std::uint32_t fileId, std::string_view src, TSNode root,
                       std::vector<RawDef>& defs, std::vector<RawRef>& refs )
{
    if( cursor == nullptr )
    {
        return;
    }

    TSQuery* query = compiledQueryFor( le );   // shared immutable query, compiled once per grammar (pre-warmed) — do NOT delete
    if( query == nullptr )
    {
        return;
    }

    {
        PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: tags query exec+captures" );
        ts_query_cursor_exec( cursor, query, root );

        TSQueryMatch match;
        while( ts_query_cursor_next_match( cursor, &match ) )
        {
            // A tags pattern yields one @definition/@reference node + a child @name.
            // Walk this match's captures: remember the role node + the name text.
            SymKind          kind     = SymKind::Other;
            bool             isDef    = false;
            bool             isRef    = false;
            std::string_view defCapSv;   // the @definition capture's name — dropGatedCapture keys the constant/cjsexport/protomethod gates on it
            TSNode           roleNode {};
            bool             haveRole = false;
            std::string_view nameTxt;
            uint32_t         nameByte = 0;
            uint32_t         nameRow  = 0;   // 0-based row of the @name identifier
            bool             haveName = false;
            TSNode           nameNode {};    // the @name identifier node — for C++ scope/qualifier (E#4)

            for( uint16_t ci = 0; ci < match.capture_count; ++ci )
            {
                const TSQueryCapture& cap = match.captures[ ci ];

                uint32_t    nameLen = 0;
                const char* capName = ts_query_capture_name_for_id( query, cap.index, &nameLen );
                const std::string_view capSv( capName, nameLen );

                SymKind k = SymKind::Other;
                switch( roleOf( capSv, k ) )
                {
                    case CapRole::Def:
                    {
                        isDef          = true;
                        kind           = k;
                        defCapSv       = capSv;
                        roleNode       = cap.node;
                        haveRole       = true;
                    }
                    break;

                    case CapRole::Ref:
                    {
                        isRef    = true;
                        roleNode = cap.node;
                        haveRole = true;
                    }
                    break;

                    case CapRole::NameOnly:
                    {
                        const uint32_t a = ts_node_start_byte( cap.node );
                        uint32_t       b = ts_node_end_byte( cap.node );

                        // A C++ conversion operator's declarator is an `operator_cast` node whose text spans
                        // the WHOLE `operator <type>() const` (the tags query captures the declarator itself —
                        // there is no sub-node spanning just `operator bool`). Trim the name's end to the end of
                        // the `type` field so the symbol name is `operator bool` / `operator MyType`, not the
                        // param list. Symbolic ops (operator==/[]/()) go through operator_name and are untouched —
                        // trimming at `(` there would wrongly cut `operator()`, so this is operator_cast-only.
                        if( std::strcmp( ts_node_type( cap.node ), "operator_cast" ) == 0 )
                        {
                            const TSNode typeNode = ts_node_child_by_field_name( cap.node, "type", 4 );
                            if( !ts_node_is_null( typeNode ) )
                            {
                                const uint32_t typeEnd = ts_node_end_byte( typeNode );
                                if( typeEnd > a && typeEnd <= b )
                                {
                                    b = typeEnd;
                                }
                            }
                        }

                        if( b <= src.size() && a <= b )
                        {
                            nameTxt  = src.substr( a, b - a );
                            nameByte = a;
                            nameRow  = ts_node_start_point( cap.node ).row;
                            nameNode = cap.node;
                            haveName = true;
                        }
                    }
                    break;

                    case CapRole::Ignore:
                    break;
                }
            }

            if( !haveName )
            {
                continue;
            }

            // Some patterns (e.g. a bare (identifier) @name) carry no @definition/@reference
            // wrapper. Treat a wrapper-less @name as a reference fallback only when the pattern
            // had a role; otherwise skip (avoids turning every identifier into an edge).
            if( !haveRole )
            {
                continue;
            }

            // F5: drop Swift function-local `let`/`var` bindings — they are not module symbols and, left in,
            // they steal the enclosing function's call edges (the last local binding above the call sites
            // becomes the nearest enclosing symbol). roleNode is the `property_declaration`; a `statements`
            // ancestor marks it as local. Real stored/computed members (class/struct/enum/top-level) survive.
            if( isDef && kind == SymKind::Var && le.lang == Lang::Swift && isSwiftLocalBinding( roleNode ) )
            {
                continue;
            }

            // the gated capture classes — r3 q10 constants, JS export/prototype assignments — in one
            // drop decision (see dropGatedCapture for the per-class rationale and why none of this can
            // live in the query as a #match?/#eq? predicate).
            if( isDef && dropGatedCapture( defCapSv, le.lang, nameTxt, nameNode, src ) )
            {
                continue;
            }

            if( isDef )
            {
                RawDef d;
                d.fileId    = fileId;
                d.line      = nameRow + 1;   // the identifier's line — most accurate, dedup-stable
            // The C++ tags query captures @definition on the function_declarator (name+params) — its
            // span excludes the return type AND the body. Walk up to the nearest ancestor owning a
            // "body" field (the real function_definition) so [startByte,endByte) spans the WHOLE def:
            // return type + signature + body. Fixes --expand bodies, --pack-signatures return-types,
            // AND reference enclosing-attribution (a call in a body is now inside its function span).
            // Grammars whose @definition node already owns the body (class/struct/enum) don't climb.
            TSNode defNode = roleNode;
            TSNode body    = ts_node_child_by_field_name( roleNode, "body", 4 );
            // A Var's span is its own declaration — never climb. The climb exists to find a FUNCTION's
            // body; for a var it can only steal a container's span (a Ruby class-level constant's parent
            // chain is body_statement → class, and class owns a "body" field, so the climb would hand the
            // constant THE WHOLE CLASS — the exact Rust-method span bug the H4 W3 note above describes).
            // No-op for every pre-existing Var capture (Swift/C#/Go/Python parents hit a scope-stop or the
            // file root before any "body"-owning ancestor — verified byte-identical on the gate corpora).
            if( ts_node_is_null( body ) && kind != SymKind::Var )
            {
                TSNode child = roleNode;
                TSNode p     = ts_node_parent( roleNode );
                for( int guard = 0; !ts_node_is_null( p ) && guard < 4; ++guard )
                {
                    const char* pt = ts_node_type( p );
                    // STOP at a type/namespace/file scope: a function's body never lives above one of
                    // these, so reaching here means roleNode is a prototype/declaration with no body.
                    // (Without this, an in-class method declaration would climb into class_specifier and
                    // wrongly grab the whole CLASS body as its span — corrupting spans + ref attribution.)
                    const bool scope =    std::strcmp( pt, "class_specifier" ) == 0        || std::strcmp( pt, "struct_specifier" ) == 0
                                       || std::strcmp( pt, "field_declaration_list" ) == 0 || std::strcmp( pt, "declaration_list" ) == 0
                                       || std::strcmp( pt, "namespace_definition" ) == 0   || std::strcmp( pt, "enum_specifier" ) == 0
                                       || std::strcmp( pt, "translation_unit" ) == 0       || std::strcmp( pt, "source_file" ) == 0       // Swift top
                                       || std::strcmp( pt, "class_body" ) == 0             || std::strcmp( pt, "protocol_body" ) == 0     // Swift type bodies
                                       || std::strcmp( pt, "enum_class_body" ) == 0
                                       || std::strcmp( pt, "class_interface" ) == 0        || std::strcmp( pt, "class_implementation" ) == 0   // ObjC
                                       || std::strcmp( pt, "implementation_definition" ) == 0 || std::strcmp( pt, "protocol_declaration" ) == 0
                                       || std::strcmp( pt, "compound_statement" ) == 0     || std::strcmp( pt, "block" ) == 0;   // a function BODY: a block-scope
                    // `Type v(args);` (most-vexing-parse) must not climb up and steal its enclosing function's span. A real
                    // function definition's declarator parents directly to function_definition (found at hop 1, above), so this never fires for it.
                    if( scope )
                    {
                        // prototype/declaration: use the member/decl wrapper as the span so the RETURN
                        // TYPE is included (not just the declarator), WITHOUT grabbing the class body.
                        const char* ct = ts_node_type( child );
                        if( std::strcmp( ct, "field_declaration" ) == 0 || std::strcmp( ct, "declaration" ) == 0 )
                        {
                            defNode = child;
                        }
                        break;
                    }
                    const TSNode pb = ts_node_child_by_field_name( p, "body", 4 );
                    if( !ts_node_is_null( pb ) ) { defNode = p; body = pb; break; }
                    child = p;
                    p     = ts_node_parent( p );
                }
            }

            // ObjC-only body-field fallback for the grammar that exposes a body as an unnamed CHILD, not a
            // named "body" field. C++ function_definition owns a "body" field (found above); the ObjC grammar
            // never does, so the field lookup returns null and bodyByte would stay 0 for a real definition —
            // making an @implementation def indistinguishable from its @interface DECL (both bodyByte==0). That
            // breaks BOTH the same-file decl/def collapse (3a-bis) and graph.h's cross-file hasBody
            // (endByte > sigEndByte), doubling every ObjC symbol node AND its call edges. Recover the
            // body-present signal from a direct child:
            //   - a METHOD def: a bare `compound_statement` / `function_body` / `block` child (the `{...}`).
            //   - an ObjC CLASS: an @implementation carries `implementation_definition` member children; the
            //     matching @interface carries only `method_declaration`s → so an `implementation_definition`
            //     child is exactly "this is the class's definition, not its forward @interface".
            // A bodyLESS declaration (@interface method / @interface class) has none of these children →
            // bodyByte stays 0 → it stays a decl (the discriminant the collapse needs). GATED to Lang::ObjC so
            // C++/Python/Rust/Go/TS/Swift bodyByte — and therefore their sigEndByte, spans, and node/edge
            // output — are BYTE-for-byte unchanged (a .mm's C++ functions take the C "body"-field path above
            // and never reach here). See test/langcheck.sh c.m and the byte-identical src/ regression gate.
            if( ts_node_is_null( body ) && le.lang == Lang::ObjC )
            {
                const std::uint32_t childCount = ts_node_child_count( defNode );
                for( std::uint32_t ci = 0; ci < childCount; ++ci )
                {
                    const TSNode ch = ts_node_child( defNode, ci );
                    const char*  ct = ts_node_type( ch );
                    if( std::strcmp( ct, "compound_statement" ) == 0     || std::strcmp( ct, "function_body" ) == 0
                        || std::strcmp( ct, "block" ) == 0               || std::strcmp( ct, "implementation_definition" ) == 0 )
                    { body = ch; break; }
                }
            }

            d.startByte = ts_node_start_byte( defNode );
            d.endByte   = ts_node_end_byte( defNode );
            d.nameByte  = nameByte;
            d.bodyByte  = ts_node_is_null( body ) ? 0u : ts_node_start_byte( body );
            const bool  fnOrMethod = ( kind == SymKind::Function || kind == SymKind::Method );
            const auto [ cxVal, ccxVal, nestVal, localsVal, humpsVal, deepVal ] = fnOrMethod ? complexityOf( defNode, src, le.lang ) : Complexity{ 0u, 0u, 0u, 0u, 0u, 0u };
            d.cx        = cxVal;
            d.ccx       = ccxVal;
            d.locals    = localsVal;   // Phase 1: floor count, C/C++ only (model.h localsCountedLang) — 0 elsewhere, never emitted there
            // Q4 size smells (SIZE = master variable): physical LOC = span line count (end row − start row + 1);
            // param count + max nesting for functions/methods only (0 otherwise, absent in emit). All descriptive.
            {
                const std::uint32_t startRow = ts_node_start_point( defNode ).row;
                const std::uint32_t endRow   = ts_node_end_point( defNode ).row;
                d.loc = ( endRow >= startRow ) ? ( endRow - startRow + 1u ) : 1u;
            }
            d.params    = fnOrMethod ? countParams( defNode ) : std::uint16_t( 0 );
            d.arityExact = fnOrMethod ? std::uint8_t( cc_paramArityExact( defNode, le.lang, kind ) ? 1 : 0 ) : std::uint8_t( 0 );   // B2.2
            d.maxNest   = fnOrMethod ? std::uint8_t( nestVal > 255u ? 255u : nestVal ) : std::uint8_t( 0 );
            // The nesting profile (model.h Symbol::humps/deepLoc). Saturating at 65535 on purpose: a def past
            // either bound is beyond every triage threshold, and deepLoc is a floor already, so a clamp there
            // stays honest in the direction the attribute already claims.
            d.humps     = fnOrMethod ? std::uint16_t( humpsVal > 65535u ? 65535u : humpsVal ) : std::uint16_t( 0 );
            d.deepLoc   = fnOrMethod ? std::uint16_t( deepVal  > 65535u ? 65535u : deepVal  ) : std::uint16_t( 0 );
            d.kind      = kind;
            d.lang      = le.lang;
            d.name      = finalSegment( nameTxt );
            if( le.lang == Lang::Cpp )                              // canonical scope (E#4): out-of-line `A::b` → "A", else enclosing class/namespace
            {
                d.scope = qualifierOf( nameNode, src );
                if( d.scope.empty() )
                {
                    d.scope = enclosingScopeOf( nameNode, src );
                }
            }
            else if( le.lang == Lang::Python )
            { // P2-D Rule 1: enclosing class of a Python method → `self.m()` narrows to Class::m
                d.scope = enclosingScopeOf( nameNode, src );
            }
            else if( le.lang == Lang::Rust )
            { // H4: `impl Widget { fn new() }` → "Widget" — see rustEnclosingScopeOf
                d.scope = rustEnclosingScopeOf( nameNode, src, /*includeModules=*/true );
            }
            defs.push_back( std::move( d ) );
            if( kind == SymKind::Class || kind == SymKind::Struct || kind == SymKind::Interface )
            {
                captureBases( defNode, fileId, le.lang, src, refs );    // IS-A: inheritance edges (derived → base)
                captureFields( defNode, fileId, le.lang, src, refs );   // HAS-A: member-variable type edges (S5-E)
            }
            }
            else if( isRef )
            {
                // H4: a C++ cast keyword is not a call — see isCppCastKeyword. Valid input, skipped, no alert.
                if( le.lang == Lang::Cpp && isCppCastKeyword( nameTxt ) )
                {
                    continue;
                }

                RawRef r;
                r.fileId    = fileId;
                r.startByte = ts_node_start_byte( roleNode );
                r.line      = ts_node_start_point( roleNode ).row + 1;   // ABS-3: 1-based use-site line for --uses
                r.lang      = le.lang;
                r.role      = RefRole::Call;   // ABS-3: @reference.call from the tags query is a call use-site
                r.name      = finalSegment( nameTxt );
                if( le.lang == Lang::Cpp )
                {
                    r.qualifier = qualifierOf( nameNode, src ); // `A::b()` → "A" (E#4 canonical resolve)
                }
                else if( le.lang == Lang::Rust )
                {
                    r.qualifier = rustQualifierOf( nameNode, src ); // H4: `Widget::new()` → "Widget"
                }

                // H4 RE-SPLIT: the widened qualified-call pattern binds the INNER node, so a 3+-segment call's
                // captured text still carries scope (`inner::targetFn`). Recover the pair the canonical tier
                // keys on — name = the final segment, qualifier = the IMMEDIATE scope — from the text itself.
                // This must run INSTEAD OF the finalSegment() above (it overwrites both fields): finalSegment
                // truncates at the first '<', which would name `numeric_limits<std::size_t>::max` as
                // `numeric_limits` and mint an edge to the wrong symbol. Inert for every 2-segment call
                // (`rw::midFn` binds a bare identifier — no top-level `::` in the text) and for
                // `ns::tmplFn<int>()` (whose `::` sits inside no group but whose captured text is just
                // `tmplFn<int>`), so those keep their qualifierOf() result untouched.
                if( le.lang == Lang::Cpp )
                {
                    // An OPERATOR tail is recognised first: its `<`/`>` are part of the NAME, so handing it to
                    // the angle-depth scan below binds the wrong scope for the whole `>` family. See
                    // operatorNameStart. When the operator spelling starts at index 0 the capture IS the bare
                    // operator name, its parent is the qualified_identifier, and qualifierOf() already put the
                    // immediate scope in r.qualifier — nothing to re-split.
                    const std::size_t opStart = operatorNameStart( nameTxt );
                    const bool        opScoped = opStart != std::string_view::npos && opStart >= 2
                                              && nameTxt[ opStart - 1 ] == ':' && nameTxt[ opStart - 2 ] == ':';
                    if( opScoped )
                    {
                        r.name      = finalSegment( nameTxt.substr( opStart ) );                                  // `operator>` verbatim
                        r.qualifier = immediateScope( namesplit::stripTemplateArgs( nameTxt.substr( 0, opStart - 2 ) ) );
                    }
                    else if( opStart == std::string_view::npos )
                    {
                        if( const std::size_t sep = lastTopLevelScopeSep( nameTxt ); sep != std::string_view::npos )
                        {
                            r.name      = finalSegment( nameTxt.substr( sep + 2 ) );
                            r.qualifier = immediateScope( namesplit::stripTemplateArgs( nameTxt.substr( 0, sep ) ) );
                        }
                    }
                }

                auto [ rk, rv ] = receiverOf( nameNode, le.lang, src );                  // P2-D: `this`/`self`/`x` receiver shape
                r.recv = rk;  r.recvVar = std::move( rv );                               //   → one-hop narrowing in resolve.h
                auto [ ac, ak ] = callArity( nameNode, le.lang, src );                    // B2.2: call-site positional arg count
                r.argCount = ac;  r.argCountKnown = ak;                                   //   → arity filter in graph.h
                refs.push_back( std::move( r ) );
            }
        }
    }
}

}   // namespace

// =====================================================================================
IngestResult ingest( const char* rootDir, const std::vector<std::string>& excludeSubstr, std::string_view cacheFile,
                     std::size_t maxFileBytes, bool captureValueUses, std::string_view excludeLabel )
{
    PROFILE_SCOPE_DESCRIBE( "ingest: total (crawl + parse + model)" );
    // Cheap (a handful of bytes serialized twice) and runs once per invocation — catches a
    // writeDef/writeRef field added without updating kMinDefRecordBytesLean/kMinRefRecordBytes immediately
    // in any debug/ASan run, before it can silently weaken the cache record-count bounds check.
    verifyCacheRecordMinimaTripwire();

    IngestResult result;
    // A4-F17: rootDir is a runtime-falsifiable input (caller/CLI-supplied), so degrade — never VERIFY here.
    // In release VERIFY becomes __builtin_assume, which would delete the very guard below (the CLAUDE.md trap).
    if( rootDir == nullptr )
    {
        DEGRADED_PATH_ALERT( "ingest: null root directory — empty result" );
        return result;
    }

    // a zero/absurd ceiling would silently crawl nothing — clamp to the default (degrade, never trap).
    if( maxFileBytes == 0 )
    {
        maxFileBytes = kDefaultMaxFileBytes;
    }

    // 1) deterministic crawl -> sorted file list (this list IS result.files / the fileId space)
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: crawl (collectSources)" );
        auto [ crawledPaths, oversizeSkippedCount ] = collectSources( rootDir, excludeSubstr, maxFileBytes, excludeLabel );
        result.files                = std::move( crawledPaths );
        result.skippedOversizeCount = oversizeSkippedCount;
    }

    // 2) parse every file IN PARALLEL — one TSParser per worker thread (parsers aren't
    //    thread-safe), per-thread raw lists merged after. Determinism is preserved: defs/refs
    //    are re-sorted below, so collection order is irrelevant.
    std::vector<RawDef>  rawDefs;
    std::vector<RawRef>  rawRefs;
    std::vector<Include> rawIncs;
    std::vector<RawBind> rawBinds;   // P2-D Rule 2: local var→type bindings
    std::vector<BindingAlias> rawFfis;   // A4-R5: cross-language FFI binding declarations
    std::vector<RouteDef>     rawRouteDefs;   // B6.3: HTTP server-side route registrations
    std::vector<RawRouteUse>  rawRouteUses;   // B6.3: HTTP client-side calls (pre fromSymbol attribution)

    // Win 1 (PERF.md P1) — lazy grammar compilation: load the cache FIRST, then compile only the
    // grammars needed by cache-miss files (new or hash-changed). On a fully-warm zero-change run,
    // zero grammars need compiling → ~70ms saved (72% of warm canyon). On a partial-change run,
    // only the grammars touched by changed files are compiled (typically 1 for a single .cpp edit).
    //
    // Implementation: a pre-pass reads+hashes each file and checks against the loaded cache;
    // misses mark their grammar. Hashes are stored so the parse pool reuses them (no double-read).
    // The constraint: compiledQueryCache() is single-writer and worker reads happen only after the ready gate
    // opens. Cold query compilation is launched before the parse pool; the main thread installs the shared
    // cache and notifies workers while they are already doing parse-side work.

    // incremental: load the content-hash cache BEFORE the prewarm. Empty cacheFile ⇒ full parse.
    // fileHash: pre-sized to nfiles here (0 = not yet hashed); the prewarm miss-detection pass
    // populates entries for files it reads; the parse pool fills the rest during normal processing.
    // A4-P7: cacheWriteNs is the loaded blob's write timestamp — the racy-rule reference for the warm-run
    // stat-gate. -1 (no/rejected cache) makes every stat check see a racy entry → always read+hash (safe).
    long long cacheWriteNs = -1;
    HashMap<std::string, FileFacts> cache =
        cacheFile.empty() ? HashMap<std::string, FileFacts>{} : loadCache( std::string( cacheFile ), rootDir, captureValueUses, cacheWriteNs );
    const std::size_t nfilesEarly = result.files.size();
    const bool needsCacheHash = !cacheFile.empty();
    std::vector<std::uint64_t> fileHash( nfilesEarly, 0 );
    // A4-P7 stat-gate: (size,mtime) observed for each file at the run that hashes it — persisted by saveCache
    // so a future warm run can trust an unchanged file without reading it. -1 ⇒ not captured (never trusted).
    std::vector<long long> fileStatSize( nfilesEarly, -1 );
    std::vector<long long> fileStatMtime( nfilesEarly, -1 );
    std::vector<const LangEntry*> fileLang( nfilesEarly, nullptr );
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: classify file languages" );
        for( std::size_t fileId = 0; fileId < nfilesEarly; ++fileId )
        {
            const std::string ext = lowerExtensionOf( result.files[ fileId ] );
            fileLang[ fileId ] = lookupLang( ext );
        }
    }

    std::vector<const LangEntry*> toCompile;
    std::vector<TSQuery*>         compiledQueries;
    std::vector<std::thread>      queryCompilePool;
    std::atomic<bool>             queryPrewarmReady{ true };
    std::mutex                    queryPrewarmMutex;
    std::condition_variable       queryPrewarmCv;
    QueryReadyGate                queryReadyGate{ &queryPrewarmReady, &queryPrewarmMutex, &queryPrewarmCv };

    // pre-warm the per-language tags.scm cache single-threaded; workers then only READ it.
    // LAZY: compile ONLY grammars needed by changed/uncached files (the miss set).
    // The grammar set must be a SUPERSET of every grammar any worker will touch:
    //   - a cache miss → grammar guaranteed needed → mark it
    //   - a cache hit (hash-match) → worker skips parse → grammar NOT needed (safe to omit)
    //   - a .h miss that looks Objective-C → marks objc instead of cpp (same looksObjC re-route as parse pool)
    //   - an unreadable .h miss → conservatively marks both cpp and objc, matching the old safety fallback
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: compile queries (tags.scm prewarm)" );
        std::array<bool, kLangTable.size()> present {};
        bool anyUnknownHeaderMiss = false;

        // The miss-detection pass reads + FNV-hashes every cache-present code file to decide which grammars a
        // worker will actually need. That I/O + hashing was serial (~61ms on canyon warm). It is READ-ONLY and
        // a pure function of each file's bytes, so parallelize it — but keep the RESULT deterministic: every
        // thread writes ONLY its own per-index slots (fileHash[fi], isMiss[fi]); nothing is
        // push_back'd from a worker. The grammar-mark reduction that follows is a serial pass over those slots,
        // so the compiled-grammar set (and thus everything downstream) is independent of thread scheduling.
        // The 204bb02 constraint still holds: compiledQueryCache() is populated single-threaded after the
        // async compile join, and workers wait on queryPrewarmReady before reading it. fileHash is pre-filled
        // so the pool skips the re-read on a cache hit.
        std::vector<char> isMiss( nfilesEarly, 0 );              // 1 ⇒ this file's grammar is needed (cache miss/new)
        std::vector<char> isObjCHeaderMiss( nfilesEarly, 0 );    // 1 ⇒ missed .h should reroute to ObjC grammar
        std::vector<char> isUnknownHeaderMiss( nfilesEarly, 0 ); // 1 ⇒ missed .h could not be sniffed; compile fallback

        if( cache.empty() )
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: mark no-cache grammars" );

            for( std::size_t fi = 0; fi < nfilesEarly; ++fi )
            {
                const LangEntry* le = fileLang[ fi ];
                if( le == nullptr || le->grammar == nullptr )
                {
                    continue;   // doc extensions / markdown — no grammar needed
                }

                present[ static_cast<std::size_t>( le - kLangTable.data() ) ] = true;
                if( le->ext == ".h" )
                {
                    // With no cache, every header is a parse miss. Mark ObjC too so a header that reroutes
                    // after the parse pool's content sniff never blocks on an uncompiled query.
                    if( const LangEntry* objcLe = lookupLang( ".m" ) )
                    {
                        present[ static_cast<std::size_t>( objcLe - kLangTable.data() ) ] = true;
                    }
                }
            }
        }
        else
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: detect cache misses" );

            unsigned hwHash = std::thread::hardware_concurrency();
            if( hwHash == 0 )
            {
                hwHash = 1;
            }
            const unsigned nHashThreads = static_cast<unsigned>( std::min<std::size_t>( hwHash, std::max<std::size_t>( nfilesEarly, 1 ) ) );
            std::atomic<std::size_t> nextIdx{ 0 };
            std::vector<std::thread> hashPool;
            hashPool.reserve( nHashThreads );

            for( unsigned t = 0; t < nHashThreads; ++t )
            {
                hashPool.emplace_back( [ & ]()
                {
                    std::string bytes;
                    std::string headerPrefix;
                    for( ;; )
                    {
                        const std::size_t fi = nextIdx.fetch_add( 1, std::memory_order_relaxed );
                        if( fi >= nfilesEarly )
                        {
                            break;
                        }
                        try   // per-file degrade — a throw escaping a worker thread would std::terminate
                        {
                            const std::string& f = result.files[ fi ];
                            const LangEntry* le = fileLang[ fi ];
                            if( le == nullptr )
                            {
                                continue;   // doc extensions — never cached (the doc post-pass re-extracts)
                            }
                            // B0: grammar-less languages (markdown) still flow through the cache stat-gate /
                            // read+hash below so an UNCHANGED .md warm-hits without any read (previously the
                            // early grammar skip left fileHash=0 and the parse pool re-read every .md every
                            // run — the last per-run file-read the postings path had left). They only skip
                            // the grammar-miss bookkeeping at the bottom (nothing to compile for them).

                            bool hasFullBytes = false;

                            // path absent from cache ⇒ definitely a miss (no read needed). Present ⇒ try the
                            // A4-P7 stat-gate first, else read+hash.
                            if( !cache.empty() )
                            {
                                const auto cit = cache.find( f );
                                if( cit != cache.end() )
                                {
                                    const FileFacts& ff = cit->second;

                                    // A4-P7 STAT-GATE: trust the cached parse WITHOUT reading/hashing when the
                                    // current size+mtime still match the cache AND the entry is not racy (its
                                    // mtime is strictly older than the blob's own write time — a same-granule
                                    // post-hash edit could otherwise slip through undetected). Content hash stays
                                    // the authority: any mismatch, an unstatable file, or a racy entry falls
                                    // through to the read+hash path below.
                                    const StatInfo si = statSizeMtime( f );
                                    const bool statMatches = si.mtimeNs >= 0 && ff.mtimeNs >= 0
                                                          && si.sizeBytes == ff.sizeBytes
                                                          && si.mtimeNs   == ff.mtimeNs;
                                    const bool notRacy = cacheWriteNs >= 0 && ff.mtimeNs < cacheWriteNs;
                                    if( statMatches && notRacy )
                                    {
                                        fileHash[ fi ]      = ff.hash;        // parse pool sees a cache hit → never reads
                                        fileStatSize[ fi ]  = si.sizeBytes;   // carry stat forward into the re-saved blob
                                        fileStatMtime[ fi ] = si.mtimeNs;
                                        continue;   // provably unchanged — grammar NOT needed for this file
                                    }

                                    if( !readFile( f, bytes ) )
                                    {
                                        continue;   // unreadable — worker will skip it too (not a miss to compile for)
                                    }
                                    hasFullBytes = true;
                                    const std::uint64_t h = contentHash64( bytes );
                                    fileHash[ fi ] = h;   // pre-fill so the parse pool can skip the re-read on a cache hit
                                    // capture the stat observed at hash time so this file stays stat-gate-eligible next run
                                    fileStatSize[ fi ]  = si.sizeBytes >= 0 ? si.sizeBytes : (long long)bytes.size();
                                    fileStatMtime[ fi ] = si.mtimeNs;
                                    if( ff.hash == h )
                                    {
                                        continue;   // cache hit — parse skipped → grammar NOT needed for this file
                                    }
                                }
                                // else: path not in cache → miss (fall through)
                            }

                            if( le->grammar == nullptr )
                            {
                                continue;   // markdown: hash prefill only — no grammar to compile, no miss to mark
                            }

                            if( le->ext == ".h" )
                            {
                                std::string_view headerBytes;
                                if( hasFullBytes )
                                {
                                    headerBytes = bytes;
                                }
                                else if( readFilePrefix( f, headerPrefix, 8192 ) )
                                {
                                    headerBytes = headerPrefix;
                                }
                                else
                                {
                                    isUnknownHeaderMiss[ fi ] = 1;
                                }
                                if( !headerBytes.empty() && looksObjC( headerBytes ) )
                                {
                                    isObjCHeaderMiss[ fi ] = 1;
                                }
                            }
                            isMiss[ fi ] = 1;   // cache empty, path-absent, or hash-changed → grammar needed
                        }
                        catch( ... )
                        {
                            DEGRADED_PATH_ALERT( "ingest: prewarm hash worker exception on a file — treated as no-miss" );
                        }
                    }
                } );
            }
            for( std::thread& th : hashPool )
            {
                th.join();
            }
            // serial grammar-mark reduction over the per-index results (order-independent: pure boolean OR).
            {
                PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: reduce grammar set" );

                for( std::size_t fi = 0; fi < nfilesEarly; ++fi )
                {
                    if( !isMiss[fi] )
                    {
                        continue;
                    }
                    const LangEntry* le = fileLang[ fi ];
                    if( le == nullptr )
                    {
                        continue; // defensive (isMiss only set for grammar-bearing files)
                    }
                    if( le->ext == ".h" )
                    {
                        if( isObjCHeaderMiss[ fi ] )
                        {
                            if( const LangEntry* objcLe = lookupLang( ".m" ) )
                            {
                                present[ static_cast<std::size_t>( objcLe - kLangTable.data() ) ] = true;
                            }
                        }
                        else
                        {
                            present[ static_cast<std::size_t>( le - kLangTable.data() ) ] = true;
                            if( isUnknownHeaderMiss[ fi ] )
                            {
                                anyUnknownHeaderMiss = true;
                            }
                        }
                        continue;
                    }
                    present[ static_cast<std::size_t>( le - kLangTable.data() ) ] = true;
                }
                if( anyUnknownHeaderMiss )
                {
                    if( const LangEntry* objcLe = lookupLang( ".m" ) )
                    {
                        present[ static_cast<std::size_t>( objcLe - kLangTable.data() ) ] = true;
                    }
                }
            }
        }

        // distinct grammars needed by cache-miss files (several extensions share one grammar)
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: unique grammars" );

            for( std::size_t i = 0; i < kLangTable.size(); ++i )
            {
                const LangEntry& e = kLangTable[ i ];
                if( e.grammar == nullptr || !present[ i ] )
                {
                    continue;
                }
                const TSLanguage* lang = e.grammar();
                bool seen = false;
                for( const LangEntry* c : toCompile )
                {
                    if( c->grammar() == lang )
                    {
                        seen = true;
                        break;
                    }
                }
                if( !seen )
                {
                    toCompile.push_back( &e );
                }
            }
        }

        // Compile distinct grammars IN PARALLEL (ts_query_new is compute-bound — PMC IPC 4.0) and install
        // into the shared cache single-threaded after the join. Query sources are immutable embedded views.
        compiledQueries.assign( toCompile.size(), nullptr );
        queryCompilePool.reserve( toCompile.size() );
        queryPrewarmReady.store( toCompile.empty(), std::memory_order_release );
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: launch ts_query_new async" );

            for( std::size_t i = 0; i < toCompile.size(); ++i )
            {
                queryCompilePool.emplace_back( [ &compiledQueries, &toCompile, i ]() { compiledQueries[ i ] = compileQueryStandalone( *toCompile[ i ] ); } );
            }
        }
    }

    // Win 2 (PERF.md P2) — dirty flag: skip saveCache when nothing changed.
    // Set by any worker that re-parses a file (cache miss or new file). On a zero-change run,
    // dirty stays false and the 7 MB re-serialization + write is skipped entirely (~11ms on full repo).
    std::atomic<bool> dirty{ false };

    // A1 (team-index) — drift-proportional observable: count files that actually RE-PARSED (cache miss /
    // changed / new). Emitted to stderr only when RIPWIRE_CACHE_STATS is set (off by default → zero
    // perturbation to any output/determinism gate), so a test can assert "restore cost is proportional to
    // drift" (modify N of F files → reparsed=N) as an executable fact, not just prose. Relaxed: a monotone
    // counter whose only reader is the post-join print, ordered by the pool join below.
    std::atomic<std::size_t> reparsedCount{ 0 };

    const std::size_t nfiles = result.files.size();
    if( nfiles )
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: parse pool (tree-sitter, parallel)" );
        // fileHash is already pre-sized to nfiles (done before the prewarm block above).
        // Entries pre-filled by the prewarm miss-detection pass (cache-present files that were read+hashed
        // there) stay as-is. Workers fill the remaining 0-valued entries for files they process.
        VERIFY( fileHash.size() == nfiles );
        unsigned hw = std::thread::hardware_concurrency();
        if( hw == 0 )
        {
            hw = 1;
        }
        const unsigned nthreads = static_cast<unsigned>( std::min<std::size_t>( hw, nfiles ) );

        std::vector<std::vector<RawDef>>  tDefs( nthreads );
        std::vector<std::vector<RawRef>>  tRefs( nthreads );
        std::vector<std::vector<Include>> tIncs( nthreads );
        std::vector<std::vector<RawBind>> tBinds( nthreads );
        std::vector<std::vector<BindingAlias>> tFfis( nthreads );
        std::vector<std::vector<RouteDef>>     tRouteDefs( nthreads );   // B6.3
        std::vector<std::vector<RawRouteUse>>  tRouteUses( nthreads );   // B6.3
        std::vector<FileFacts*>           cacheCandidateFacts( nfiles, nullptr );
        std::vector<FileFacts*>           cacheHitFacts( nfiles, nullptr );
        if( !cache.empty() )
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: prepare cache-hit reuse" );

            std::size_t hitDefs = 0, hitRefs = 0, hitIncs = 0, hitBinds = 0;
            for( std::size_t fileId = 0; fileId < nfiles; ++fileId )
            {
                const std::uint64_t h = fileHash[ fileId ];
                const auto it = cache.find( result.files[ fileId ] );
                if( it == cache.end() )
                {
                    continue;
                }
                cacheCandidateFacts[ fileId ] = &it->second;
                if( it->second.hash != h )
                {
                    continue;
                }
                cacheHitFacts[ fileId ] = &it->second;
                hitDefs  += it->second.defs.size();
                hitRefs  += it->second.refs.size();
                hitIncs  += it->second.incs.size();
                hitBinds += it->second.binds.size();
            }
            const auto perThreadReserve = [ nthreads ]( std::size_t total ) noexcept
            {
                return ( total + std::size_t( nthreads ) - 1 ) / std::size_t( nthreads );
            };
            const std::size_t defsPerThread  = perThreadReserve( hitDefs );
            const std::size_t refsPerThread  = perThreadReserve( hitRefs );
            const std::size_t incsPerThread  = perThreadReserve( hitIncs );
            const std::size_t bindsPerThread = perThreadReserve( hitBinds );
            for( unsigned t = 0; t < nthreads; ++t )
            {
                tDefs[ t ].reserve( defsPerThread );
                tRefs[ t ].reserve( refsPerThread );
                tIncs[ t ].reserve( incsPerThread );
                tBinds[ t ].reserve( bindsPerThread );
            }
        }
        std::vector<std::thread>          pool;
        pool.reserve( nthreads );
        std::vector<std::size_t>          parseOrder;
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: build work order" );

            if( !queryPrewarmReady.load( std::memory_order_acquire ) )
            {
                parseOrder.resize( nfiles );
                std::iota( parseOrder.begin(), parseOrder.end(), std::size_t( 0 ) );

                std::vector<std::uintmax_t> fileByteSize( nfiles, 0 );
                std::error_code ec;
                for( std::size_t fileId = 0; fileId < nfiles; ++fileId )
                {
                    ec.clear();
                    fileByteSize[ fileId ] = fs::file_size( result.files[ fileId ], ec );
                    if( ec )
                    {
                        fileByteSize[fileId] = 0;
                    }
                }

                const auto parsePriority = [ & ]( std::size_t fileId ) noexcept
                {
                    const LangEntry* le = fileLang[ fileId ];
                    if( le == nullptr || le->grammar == nullptr )
                    {
                        return 0;   // docs/markdown and unknowns do not consume the tags-query barrier
                    }
                    if( !cache.empty() && cacheHitFacts[ fileId ] != nullptr )
                    {
                        return 1;   // warm cache hit: cheap copy, no parse/query work
                    }
                    return 2;       // cache miss/no-cache: full parse + tags query
                };
                std::stable_sort( parseOrder.begin(), parseOrder.end(),
                                  [ & ]( std::size_t a, std::size_t b ) noexcept
                                  {
                                      const int pa = parsePriority( a );
                                      const int pb = parsePriority( b );
                                      if( pa != pb )
                                      {
                                          return pa > pb;
                                      }
                                      if( fileByteSize[a] != fileByteSize[b] )
                                      {
                                          return fileByteSize[a] > fileByteSize[b];
                                      }
                                      return a < b;
                                  } );
            }
        }
        std::atomic<std::size_t>          nextFile{ 0 };   // lock-free work queue: threads fetch_add for the next parseOrder slot

        for( unsigned t = 0; t < nthreads; ++t )
        {
            pool.emplace_back( [ &, t ]()
            {
                ParserGuard pg;
                if( pg.p == nullptr )
                {
                    DEGRADED_PATH_ALERT( "ingest: ts_parser_new failed on a worker — its files skipped" );
                    return;
                }
                TSQueryCursor* cursor = ts_query_cursor_new();
                if( cursor == nullptr )
                {
                    DEGRADED_PATH_ALERT( "ingest: ts_query_cursor_new failed on a worker — its files skipped" );
                    return;
                }

                // B0.2: per-worker subtoken-stats builder — after a file's defs are extracted (and the file's
                // bytes are STILL in memory), tokenize each new def's doc/body spans ONCE into its persisted
                // stats (lexindex.h). Rich ingests only; a def's stats ride the RawDef through dedup/sort/cache
                // so alignment with the eventual Symbol is free. scratch is reused across defs (no rehash churn).
                HashMap<std::uint64_t, std::uint32_t> lexScratch;
                if( captureValueUses )
                {
                    lexScratch.reserve( 1024 );
                }
                const auto buildLexForNewDefs = [ & ]( std::vector<RawDef>& defs, std::size_t firstNewDefIndex, const std::string& fileBytes )
                {
                    if( !captureValueUses )
                    {
                        return;
                    }
                    for( std::size_t defIndex = firstNewDefIndex; defIndex < defs.size(); ++defIndex )
                    {
                        buildDefLexStats( fileBytes, defs[ defIndex ].startByte, defs[ defIndex ].endByte, lexScratch, defs[ defIndex ].lex );
                    }
                };

                struct PendingParsedFile
                {
                    std::uint32_t   fileId = 0;
                    const LangEntry* le    = nullptr;
                    std::string     bytes;
                    TSTree*         tree   = nullptr;

                    PendingParsedFile( std::uint32_t fileIdIn, const LangEntry* leIn, std::string&& bytesIn, TSTree* treeIn )
                        : fileId( fileIdIn ), le( leIn ), bytes( std::move( bytesIn ) ), tree( treeIn )
                    {
                    }
                    PendingParsedFile( const PendingParsedFile& ) = delete;
                    PendingParsedFile& operator=( const PendingParsedFile& ) = delete;
                    PendingParsedFile( PendingParsedFile&& other ) noexcept
                        : fileId( other.fileId ), le( other.le ), bytes( std::move( other.bytes ) ), tree( other.tree )
                    {
                        other.tree = nullptr;
                    }
                    PendingParsedFile& operator=( PendingParsedFile&& other ) noexcept
                    {
                        if( this != &other )
                        {
                            if( tree != nullptr )
                            {
                                ts_tree_delete( tree );
                            }
                            fileId = other.fileId;
                            le     = other.le;
                            bytes  = std::move( other.bytes );
                            tree   = other.tree;
                            other.tree = nullptr;
                        }
                        return *this;
                    }
                    ~PendingParsedFile()
                    {
                        if( tree != nullptr )
                        {
                            ts_tree_delete( tree );
                        }
                    }
                };

                constexpr std::size_t kMaxPendingParsedFiles = 4;
                constexpr std::size_t kMaxPendingParsedBytes = 8u * 1024u * 1024u;
                std::vector<PendingParsedFile> pendingParsed;
                pendingParsed.reserve( kMaxPendingParsedFiles );
                std::size_t pendingParsedBytes = 0;
                const auto flushPendingParsed = [ & ]()
                {
                    if( pendingParsed.empty() )
                    {
                        return;
                    }

                    {
                        PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: flush pending parsed tags" );
                        waitForQueryPrewarm( &queryReadyGate );
                        for( PendingParsedFile& pending : pendingParsed )
                        {
                            if( pending.le == nullptr || pending.tree == nullptr )
                            {
                                continue;
                            }
                            const TSNode root = ts_tree_root_node( pending.tree );
                            const std::size_t firstNewDefIndex = tDefs[ t ].size();
                            captureTagsFacts( cursor, *pending.le, pending.fileId, pending.bytes, root, tDefs[ t ], tRefs[ t ] );
                            buildLexForNewDefs( tDefs[ t ], firstNewDefIndex, pending.bytes );   // B0.2: bytes still in memory
                            ts_tree_delete( pending.tree );
                            pending.tree = nullptr;
                        }
                    }
                    pendingParsed.clear();
                    pendingParsedBytes = 0;
                };

                std::string bytes;
                for( ;; )   // lock-free work-stealing: grab the next file via the atomic counter (balances the big-file tail)
                {
                    if( queryPrewarmReady.load( std::memory_order_acquire ) && !pendingParsed.empty() )
                    {
                        flushPendingParsed();
                    }

                    const std::size_t orderIndex = nextFile.fetch_add( 1, std::memory_order_relaxed );
                    if( orderIndex >= nfiles )
                    {
                        break;
                    }
                    const std::size_t fileId = parseOrder.empty() ? orderIndex : parseOrder[ orderIndex ];
                    // per-file try/catch: a throw (bad_alloc, filesystem_error, …) escaping a
                    // std::thread entry would std::terminate the whole process. Degrade per file,
                    // honouring the "never throws" contract (the worse-than-v1 parallel hazard).
                    try
                    {
                        const std::string& path = result.files[ fileId ];

                        const LangEntry* le = fileLang[ fileId ];
                        if( le == nullptr )
                        {
                            continue; // defensive (filtered in crawl)
                        }

                        // If the prewarm miss-detection pass already read+hashed this file, the hash
                        // is already in fileHash[fileId] — skip the re-read for the hash check.
                        // We still need `bytes` for actual parsing, so the fast path (cache hit) avoids readFile entirely.
                        std::uint64_t h = fileHash[ fileId ];
                        bool bytesLoaded = false;
                        if( h == 0 )
                        {
                            // Not pre-hashed: read the file now (first time we see it in the pool)
                            if( !readFile( path, bytes ) )
                            {
                                continue;
                            }
                            if( looksBinary( bytes ) )
                            {
                                continue;
                            }
                            if( le->ext == ".h" && looksObjC( bytes ) )
                            {
                                if( const LangEntry* objcLe = lookupLang( ".m" ) )
                                {
                                    le = objcLe;
                                }
                            }
                            if( needsCacheHash )
                            {
                                h = contentHash64( bytes );
                                fileHash[ fileId ] = h;
                                // A4-P7: capture (size,mtime) at hash time so saveCache can persist a stat-gate
                                // record for this file (cold run / new file / prewarm-skipped path).
                                const StatInfo si = statSizeMtime( path );
                                fileStatSize[ fileId ]  = si.sizeBytes >= 0 ? si.sizeBytes : (long long)bytes.size();
                                fileStatMtime[ fileId ] = si.mtimeNs;
                            }
                            bytesLoaded = true;
                        }

                        if( !cache.empty() )
                        {
                            FileFacts* hit = cacheHitFacts[ fileId ];
                            if( hit == nullptr )
                            {
                                FileFacts* candidate = cacheCandidateFacts[ fileId ];
                                if( candidate != nullptr && candidate->hash == h )
                                {
                                    hit = candidate;
                                }
                            }
                            if( hit != nullptr )   // unchanged → reuse cached facts, skip parse
                            {
                                for( RawDef& d : hit->defs )
                                {
                                    d.fileId = std::uint32_t( fileId );
                                    tDefs[ t ].push_back( std::move( d ) );
                                }
                                for( RawRef& rr : hit->refs )
                                {
                                    rr.fileId = std::uint32_t( fileId );
                                    tRefs[ t ].push_back( std::move( rr ) );
                                }
                                for( Include& in : hit->incs )
                                {
                                    in.fileId = std::uint32_t( fileId );
                                    tIncs[ t ].push_back( std::move( in ) );
                                }
                                for( RawBind& b : hit->binds )
                                {
                                    b.fileId = std::uint32_t( fileId );
                                    tBinds[ t ].push_back( std::move( b ) );
                                }
                                for( BindingAlias& a : hit->ffis )
                                {
                                    a.fileId = std::uint32_t( fileId );
                                    tFfis[ t ].push_back( std::move( a ) );
                                }
                                for( RouteDef& rd : hit->routeDefs )        // B6.3
                                {
                                    rd.fileId = std::uint32_t( fileId );
                                    tRouteDefs[ t ].push_back( std::move( rd ) );
                                }
                                for( RawRouteUse& ru : hit->routeUses )     // B6.3
                                {
                                    ru.fileId = std::uint32_t( fileId );
                                    tRouteUses[ t ].push_back( std::move( ru ) );
                                }
                                continue;
                            }
                        }

                        // cache miss (new file or hash changed) → need to actually parse
                        dirty.store( true, std::memory_order_relaxed );
                        reparsedCount.fetch_add( 1, std::memory_order_relaxed );   // A1: drift-proportional observable

                        // ensure bytes are loaded (may have been pre-hashed without loading the body)
                        if( !bytesLoaded )
                        {
                            if( !readFile( path, bytes ) )
                            {
                                continue;
                            }
                            if( looksBinary( bytes ) )
                            {
                                continue;
                            }
                            if( le->ext == ".h" && looksObjC( bytes ) )
                            {
                                if( const LangEntry* objcLe = lookupLang( ".m" ) )
                                {
                                    le = objcLe;
                                }
                            }
                        }

                        // hostile/degenerate JSON guard — must run BEFORE the parse (that is the whole point);
                        // the skip is a degrade with a one-line stderr note, matching the house skip style.
                        if( le->lang == Lang::Json && jsonNestsTooDeep( bytes ) )
                        {
                            std::fprintf( stderr, "[ripwire] %s: json nesting > %u levels — treated as data, not config (skipped)\n",
                                          path.c_str(), kMaxJsonNestDepth );
                            continue;
                        }

                        if( le->lang == Lang::Markdown )
                        {
                            const std::string stem = fs::path( path ).stem().string();
                            const std::size_t firstNewDefIndex = tDefs[ t ].size();
                            extractMarkdown( static_cast<std::uint32_t>( fileId ), bytes, stem, tDefs[ t ], tRefs[ t ] );
                            buildLexForNewDefs( tDefs[ t ], firstNewDefIndex, bytes );   // B0.2: md sections/file nodes get stats too
                        }
                        else
                        {
                            if( !prepareParserFor( pg.p, *le ) )
                            {
                                continue;
                            }

                            TreeGuard tree( parseTree( pg.p, bytes ) );
                            if( tree.get() == nullptr )
                            {
                                continue;
                            }

                            const TSNode root = ts_tree_root_node( tree.get() );
                            captureSideFacts( *le, static_cast<std::uint32_t>( fileId ), bytes, root, tRefs[ t ], tIncs[ t ], tBinds[ t ], tFfis[ t ], tRouteDefs[ t ], tRouteUses[ t ], captureValueUses );

                            const bool canQueueParsed = !queryPrewarmReady.load( std::memory_order_acquire )
                                                     && pendingParsed.size() < kMaxPendingParsedFiles
                                                     && pendingParsedBytes + bytes.size() <= kMaxPendingParsedBytes;
                            if( canQueueParsed )
                            {
                                pendingParsedBytes += bytes.size();
                                pendingParsed.emplace_back( static_cast<std::uint32_t>( fileId ), le, std::move( bytes ), tree.release() );
                                continue;
                            }

                            {
                                PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: wait query prewarm" );
                                waitForQueryPrewarm( &queryReadyGate );
                            }
                            const std::size_t firstNewDefIndex = tDefs[ t ].size();
                            captureTagsFacts( cursor, *le, static_cast<std::uint32_t>( fileId ), bytes, root, tDefs[ t ], tRefs[ t ] );
                            buildLexForNewDefs( tDefs[ t ], firstNewDefIndex, bytes );   // B0.2: bytes still in memory
                        }
                    }
                    catch( ... )
                    {
                        DEGRADED_PATH_ALERT( "ingest: worker exception on a file — skipped" );
                    }
                }
                flushPendingParsed();
                ts_query_cursor_delete( cursor );
            } );
        }

        {
            PROFILE_SCOPE_DESCRIBE( "ingest/compile-queries: wait/install async" );

            for( std::thread& th : queryCompilePool )
            {
                th.join();
            }
            // Install compiled queries single-threaded (workers are still gated). Installing TRANSFERS
            // ownership to CompiledQueryCache, which frees whatever is still resident at process teardown
            // (N2). A652: on an in-process re-ingest (long-lived MCP server) the same grammar can already
            // own a cached query, and overwriting drops the only pointer to it — delete the displaced entry
            // here or it leaks one TSQuery per grammar per re-ingest (A4-F16).
            HashMap<const TSLanguage*, TSQuery*>& cache = compiledQueryCache();
            for( std::size_t i = 0; i < toCompile.size(); ++i )
            {
                const TSLanguage* grammar = toCompile[ i ]->grammar();
                if( auto it = cache.find( grammar ); it != cache.end() && it->second != nullptr && it->second != compiledQueries[ i ] )
                {
                    ts_query_delete( it->second );
                }
                cache[ grammar ] = compiledQueries[ i ];
            }
            // A4-F1: publish readiness UNDER queryPrewarmMutex, then notify. Workers wait via
            // cv.wait(lock, pred); a lock-free store+notify here can slip between a worker's predicate check
            // and its block → lost wakeup → the worker sleeps forever and the main th.join() hangs.
            {
                std::lock_guard<std::mutex> lk( queryPrewarmMutex );
                queryPrewarmReady.store( true, std::memory_order_release );
            }
        }
        queryPrewarmCv.notify_all();

        for( std::thread& th : pool )
        {
            th.join();
        }

        // merge per-thread results (cross-thread order is irrelevant — sorted below)
        std::size_t totDefs = 0, totRefs = 0, totIncs = 0, totBinds = 0, totFfis = 0, totRouteDefs = 0, totRouteUses = 0;
        for( unsigned t = 0; t < nthreads; ++t )
        {
            totDefs  += tDefs[ t ].size();
            totRefs  += tRefs[ t ].size();
            totIncs  += tIncs[ t ].size();
            totBinds += tBinds[ t ].size();
            totFfis  += tFfis[ t ].size();
            totRouteDefs += tRouteDefs[ t ].size();
            totRouteUses += tRouteUses[ t ].size();
        }
        rawDefs.reserve( totDefs );
        rawRefs.reserve( totRefs );
        rawIncs.reserve( totIncs );
        rawBinds.reserve( totBinds );
        rawFfis.reserve( totFfis );
        rawRouteDefs.reserve( totRouteDefs );
        rawRouteUses.reserve( totRouteUses );
        for( unsigned t = 0; t < nthreads; ++t )
        {
            for( RawDef& d : tDefs[t] )
            {
                rawDefs.push_back( std::move( d ) );
            }
            for( RawRef& r : tRefs[t] )
            {
                rawRefs.push_back( std::move( r ) );
            }
            for( Include& in : tIncs[t] )
            {
                rawIncs.push_back( std::move( in ) );
            }
            for( RawBind& b : tBinds[t] )
            {
                rawBinds.push_back( std::move( b ) );
            }
            for( BindingAlias& a : tFfis[t] )
            {
                rawFfis.push_back( std::move( a ) );
            }
            for( RouteDef& rd : tRouteDefs[t] )
            {
                rawRouteDefs.push_back( std::move( rd ) );
            }
            for( RawRouteUse& ru : tRouteUses[t] )
            {
                rawRouteUses.push_back( std::move( ru ) );
            }
        }

        // A1 (team-index) — drift-proportional observable: report how many files re-parsed vs reused,
        // ONLY when RIPWIRE_CACHE_STATS is set (off by default → no stdout/stderr perturbation on any
        // normal run or gate). A warm restore over a tree with N-of-F files changed prints reparsed=N,
        // making the "restore cost is proportional to drift, not tree size" claim executable.
        if( std::getenv( "RIPWIRE_CACHE_STATS" ) != nullptr )
        {
            const std::size_t reparsed = reparsedCount.load( std::memory_order_relaxed );
            std::fprintf( stderr, "ripwire: cache-stats reparsed=%zu reused=%zu files=%zu\n",
                          reparsed, ( nfiles >= reparsed ? nfiles - reparsed : std::size_t( 0 ) ), nfiles );
        }

        // Win 2: rewrite cache only when at least one file changed (dirty flag set by workers above).
        // Skips the ~11ms / 7 MB serialization+write on a no-change warm run.
        if( !cacheFile.empty() && dirty.load() )
        {
            saveCache( std::string( cacheFile ), rootDir, result.files, fileHash, fileStatSize, fileStatMtime, rawDefs, rawRefs, rawIncs, rawBinds, rawFfis, rawRouteDefs, rawRouteUses, captureValueUses );
        }
    }

    // ── doc post-pass (P1-B): for every collected document file (notebook/html/csv/…), extract its text and
    //    record it as the docText override + add ONE whole-file Section node so the doc is rankable + recall-
    //    able. Runs OUTSIDE the parse cache (after saveCache, before id-assignment) and is a pure function of
    //    the bytes, so a WARM run reproduces it byte-for-byte — the determinism contract holds for docs too.
    {
        PROFILE_SCOPE_DESCRIBE( "ingest: doc post-pass (extract notebooks/html/csv)" );

        // A4-P5 (PROFILE.md P3): parseDocFile re-extracts html/csv/ipynb from scratch every run and was the
        // ~81 ms serial main-thread tail of the warm path. It is a PURE function of the file bytes, so the
        // extractions are mutually independent → parallelize across the same worker pool shape used above,
        // then MERGE deterministically in ascending-fileId order. The merge (docText[fid] + rawDefs.push) is
        // single-threaded and order-fixed, so a WARM run reproduces the map byte-for-byte (determinism holds).

        // 1) collect the doc files (cheap sequential scan) — indices stay ascending, so the merge is ordered.
        std::vector<std::uint32_t> docIds;
        for( std::uint32_t fid = 0; fid < result.files.size(); ++fid )
        {
            if( docparse::isDocExtension( lowerExtensionOf( result.files[ fid ] ) ) )
            {
                docIds.push_back( fid );
            }
        }

        // 2) extract in parallel, storing each result at its OWN slot (no cross-thread sharing of a slot →
        //    order-independent). A per-doc `hasText` gate distinguishes "not extractable" (skip) from empty.
        const std::size_t ndocs = docIds.size();
        std::vector<std::string> docTextOut( ndocs );
        std::vector<char>        docHasText( ndocs, 0 );
        std::vector<RawDefLex>   docLex( ndocs );        // B0.2: per-doc Section stats (rich only), own slot per worker
        if( ndocs > 0 )
        {
            unsigned hwDoc = std::thread::hardware_concurrency();
            if( hwDoc == 0 )
            {
                hwDoc = 1;
            }
            const unsigned nDocThreads = static_cast<unsigned>( std::min<std::size_t>( hwDoc, ndocs ) );
            std::atomic<std::size_t> nextDoc{ 0 };
            std::vector<std::thread> docPool;
            docPool.reserve( nDocThreads );
            for( unsigned t = 0; t < nDocThreads; ++t )
            {
                docPool.emplace_back( [ & ]()
                {
                    // B0.2: doc Sections are indexed by their EXTRACTED text (docText override), so their
                    // stats come from that text — computed here, in the worker that owns the slot, so the
                    // stats path never needs docText at query time either. Pure function of the bytes.
                    HashMap<std::uint64_t, std::uint32_t> docLexScratch;
                    if( captureValueUses )
                    {
                        docLexScratch.reserve( 1024 );
                    }
                    for( ;; )
                    {
                        const std::size_t di = nextDoc.fetch_add( 1, std::memory_order_relaxed );
                        if( di >= ndocs )
                        {
                            break;
                        }
                        try   // per-file degrade — a throw escaping a worker thread would std::terminate
                        {
                            const std::uint32_t fid = docIds[ di ];
                            const std::string   ext = lowerExtensionOf( result.files[ fid ] );
                            std::string text = docparse::parseDocFile( result.files[ fid ], ext );
                            if( !text.empty() )
                            {
                                if( captureValueUses )
                                { // whole-file Section span [0, len) — same span the RawDef gets below
                                    buildDefLexStats( text, 0, std::uint32_t( text.size() ), docLexScratch, docLex[ di ] );
                                }
                                docTextOut[ di ] = std::move( text );
                                docHasText[ di ] = 1;
                            }
                        }
                        catch( ... )
                        {
                            DEGRADED_PATH_ALERT( "ingest: doc post-pass worker exception on a file — skipped" );
                        }
                    }
                } );
            }
            for( std::thread& th : docPool )
            {
                th.join();
            }
        }

        // 3) deterministic merge in ascending-fileId order (docIds is already ascending).
        for( std::size_t di = 0; di < ndocs; ++di )
        {
            if( !docHasText[di] )
            { // not extractable (e.g. markitdown absent) → skip
                continue;
            }
            const std::uint32_t fid = docIds[ di ];
            const std::uint32_t len = static_cast<std::uint32_t>( docTextOut[ di ].size() );
            result.docText[ fid ] = std::move( docTextOut[ di ] );

            // whole-file Section node (mirrors the markdown file-node). lang=Markdown ⇒ docs-only recall +
            // the Section down-weight; span [0,len) so the lexical scorer indexes the whole extracted body.
            RawDef d;
            d.fileId    = fid;
            d.line      = 1;
            d.startByte = 0;
            d.endByte   = len;
            d.kind      = SymKind::Section;
            d.lang      = Lang::Markdown;
            d.name      = fs::path( result.files[ fid ] ).stem().string();
            d.lex       = std::move( docLex[ di ] );   // B0.2: stats over the extracted text (empty on lean runs)
            rawDefs.push_back( std::move( d ) );
        }
    }

    PROFILE_SCOPE_DESCRIBE( "ingest: build model (dedup + symbols/refs)" );

    // 3a) dedup definitions: some grammars' tags patterns overlap (Go: type_spec + the
    //     struct/interface specializations both fire; Rust: a fn inside an impl matches both
    //     the method and the function pattern). Two matches with the same (fileId, startByte,
    //     name) are ONE definition. Collapse them, keeping the most specific kind so the
    //     downstream graph sees one node per real symbol.
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: dedup defs" );

        auto specificity = []( SymKind k ) noexcept -> int
        {
            // higher = more specific / preferred when two matches collide
            switch( k )
            {
                case SymKind::Method:    return 5;
                case SymKind::Interface: return 4;
                case SymKind::Struct:    return 3;
                case SymKind::Class:     return 3;
                case SymKind::Function:  return 2;
                case SymKind::Var:       return 1;
                default:                 return 0;   // Other
            }
        };

        // identity = the declared identifier itself: (fileId, name-token start byte). Two tags
        // patterns that both name the same identifier are the same symbol regardless of which
        // wrapper node each captured.
        std::sort( rawDefs.begin(), rawDefs.end(),
                   [ &specificity ]( const RawDef& a, const RawDef& b ) noexcept
                   {
                       if( a.fileId != b.fileId )
                       {
                           return a.fileId < b.fileId;
                       }
                       if( a.nameByte != b.nameByte )
                       {
                           return a.nameByte < b.nameByte;
                       }
                       // same identity: most-specific kind first so unique() keeps it
                       const int specificityA = specificity( a.kind ), specificityB = specificity( b.kind );
                       if( specificityA != specificityB )
                       {
                           return specificityA > specificityB;
                       }
                       // same identity AND same specificity with DIFFERENT spans (Go: `type Foo struct{}` fires
                       // two capture rows): finish the total order on span — startByte ascending, endByte
                       // DESCENDING (widest span first) — so the unique() survivor is input-order independent.
                       if( a.startByte != b.startByte )
                       {
                           return a.startByte < b.startByte;
                       }
                       return a.endByte > b.endByte;
                   } );

        const auto sameIdentity = []( const RawDef& a, const RawDef& b ) noexcept
        {
            return a.fileId == b.fileId && a.nameByte == b.nameByte;
        };
        rawDefs.erase( std::unique( rawDefs.begin(), rawDefs.end(), sameIdentity ), rawDefs.end() );
    }

    // 3a-bis) same-FILE decl/def collapse (ObjC only) — the intra-file mirror of graph.h's cross-file byName
    //     collapse. In C++ a header decl and its .cpp def live in DIFFERENT files, so (fileId, nameByte)
    //     already keeps them as two legitimate nodes (one per file) and the graph.h byName pass merges them
    //     only for resolution. ObjC breaks that symmetry: the @interface decl and the @implementation def sit
    //     in the SAME .m/.mm file with different name-token bytes, so 3a leaves BOTH as nodes — every ObjC
    //     method (and the class itself) lands twice, doubling <s> nodes AND call edges (token waste + rank
    //     distortion in every ObjC file). Collapse it here, at the same "one node per real symbol" seam: within
    //     a file, if a (name, scope, kind) group has ANY body-present definition (bodyByte > startByte — the
    //     same predicate as graph.h's hasBody, made correct for ObjC by the body-child fallback above), drop
    //     that group's bodyLESS declarations and keep the definition(s). A group with NO def anywhere in the
    //     file (an @interface method with no @implementation, a protocol-only method) keeps its decls untouched
    //     — the exact "no def anywhere keeps decls" escape hatch graph.h uses.
    //
    //     GATED to ObjC defs deliberately. (1) SCOPE: gate (d) requires C++/Python output to stay byte-for-byte
    //     identical, and this bug is ObjC-only. (2) CORRECTNESS: the (fileId, name, scope, kind) key does NOT
    //     distinguish C++ OVERLOADS — a header with `svector() = default;` (bodyLESS) + `svector(const&){...}`
    //     (body) would wrongly drop the defaulted ctor as a "shadowed decl". ObjC selectors don't overload by
    //     signature within a class, so for ObjC the key uniquely pairs exactly one decl with one def. A `.mm`'s
    //     C++ functions carry Lang::ObjC too, but a C++ overload set inside a .mm is out of this fixture's scope
    //     and the same key limitation applies — so we restrict to the observed ObjC node shapes by language and
    //     rely on the byte-identical + langcheck gates. Never manufactures a symbol the tags query didn't capture.
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: objc decl-def collapse" );

        const auto hasBody = []( const RawDef& d ) noexcept { return d.bodyByte > d.startByte; };

        // (fileId, name, scope, kind) → does the group contain at least one body-present ObjC def? one pass.
        // Only ObjC defs are keyed; non-ObjC defs are never grouped and always pass through unchanged.
        HashMap<std::string, bool> groupHasDef;
        groupHasDef.reserve( rawDefs.size() );
        std::string key;
        const auto makeKey = [ &key ]( const RawDef& d )
        {
            key.clear();
            key.append( std::to_string( d.fileId ) ).push_back( '\x1f' );
            key.append( d.name ).push_back( '\x1f' );
            key.append( d.scope ).push_back( '\x1f' );
            key.push_back( char( '0' + int( d.kind ) ) );
            return std::string_view( key );
        };
        for( const RawDef& d : rawDefs )
        {
            if( d.lang != Lang::ObjC )
            {
                continue; // C++/Python/… never participate (SCOPE + overload-safety)
            }
            const std::string_view k = makeKey( d );
            const auto [ it, inserted ] = groupHasDef.try_emplace( std::string( k ), hasBody( d ) );
            if( !inserted && hasBody( d ) )
            {
                it->second = true;
            }
        }

        // keep a def group's DEFS only; keep a decl-only group whole (escape hatch). Stable: preserves order.
        std::vector<RawDef> kept;
        kept.reserve( rawDefs.size() );
        for( RawDef& d : rawDefs )
        {
            if( d.lang == Lang::ObjC )                                // only ObjC symbols are eligible to be dropped
            {
                const auto it = groupHasDef.find( std::string( makeKey( d ) ) );
                const bool groupDef = ( it != groupHasDef.end() ) && it->second;
                if( groupDef && !hasBody( d ) )
                {
                    continue; // a decl shadowed by a same-file ObjC def → drop
                }
            }
            kept.push_back( std::move( d ) );
        }
        rawDefs = std::move( kept );
    }

    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: assign symbols" );

        // 3b) assign Symbol ids in (fileId, line, name) order — deterministic (model.h)
        std::sort( rawDefs.begin(), rawDefs.end(),
                   []( const RawDef& a, const RawDef& b ) noexcept
                   {
                       if( a.fileId != b.fileId )
                       {
                           return a.fileId < b.fileId;
                       }
                       if( a.line != b.line )
                       {
                           return a.line < b.line;
                       }
                       if( a.name != b.name )
                       {
                           return a.name < b.name;
                       }
                       return a.startByte < b.startByte;   // stable last-resort tiebreak
                   } );

        result.symbols.reserve( rawDefs.size() );
        for( std::uint32_t i = 0; i < rawDefs.size(); ++i )
        {
            const RawDef& d = rawDefs[ i ];
            Symbol s;
            s.id     = i;
            s.kind   = d.kind;
            s.lang   = d.lang;
            s.fileId = d.fileId;
            s.line   = d.line;
            s.sigStartByte = d.startByte;
            s.sigEndByte   = ( d.bodyByte > d.startByte ) ? d.bodyByte : d.endByte;
            s.endByte      = d.endByte;
            s.cx           = d.cx;
            s.ccx          = d.ccx;
            s.loc          = d.loc;      // Q4: physical line span
            s.locals       = d.locals;   // Phase 1: local-decl floor count (C/C++ only; model.h localsCountedLang)
            s.params       = d.params;   // Q4: parameter count (fns/methods)
            s.arityExact   = d.arityExact;   // B2.2: params is a fixed call-comparable arity
            s.maxNest      = d.maxNest;  // Q4: max control nesting (fns/methods)
            s.humps        = d.humps;   // nesting profile: regions reaching quality::kNestBar (model.h)
            s.deepLoc      = d.deepLoc; // nesting profile: lines inside them, a FLOOR (model.h)
            s.name   = d.name;
            s.scope  = d.scope;
            result.symbols.push_back( std::move( s ) );
        }

        // B0.1/B0.2 (rich ingests only): flatten the per-def stats into the per-symbol CSR (rawDefs is
        // aligned 1:1 with result.symbols after the sort above) and derive the per-FILE pre-filter
        // signatures from the same hashes — the B0.1 Bloom is a pure function of the persisted postings,
        // so it costs the cache format nothing and can never disagree with the stats it gates.
        if( captureValueUses )
        {
            PROFILE_SCOPE_DESCRIBE( "ingest/build-model: lex stats CSR + file signatures (B0)" );

            const std::size_t symbolCount = result.symbols.size();
            std::size_t       pairCount   = 0;
            for( const RawDef& d : rawDefs )
            {
                pairCount += d.lex.tokenHashes.size();
            }

            result.hasLexStats = true;
            result.lexDocBodyDl.resize( symbolCount );
            result.lexTokenRowOffsets.resize( symbolCount + 1 );
            result.lexTokenHashes.reserve( pairCount );
            result.lexTokenTfs.reserve( pairCount );
            result.lexFileSig.assign( result.files.size() * kLexFileSigWords, 0 );

            result.lexTokenRowOffsets[ 0 ] = 0;
            for( std::size_t i = 0; i < symbolCount; ++i )
            {
                const RawDefLex& lx = rawDefs[ i ].lex;
                result.lexDocBodyDl[ i ] = lx.dlWeighted;
                result.lexTokenHashes.insert( result.lexTokenHashes.end(), lx.tokenHashes.begin(), lx.tokenHashes.end() );
                result.lexTokenTfs.insert( result.lexTokenTfs.end(), lx.tokenTfs.begin(), lx.tokenTfs.end() );
                result.lexTokenRowOffsets[ i + 1 ] = std::uint32_t( result.lexTokenHashes.size() );

                const std::uint32_t fileId = rawDefs[ i ].fileId;
                if( fileId < result.files.size() )
                {
                    std::uint64_t* const sig = result.lexFileSig.data() + std::size_t( fileId ) * kLexFileSigWords;
                    for( const std::uint64_t hash : lx.tokenHashes )
                    {
                        sig[lexSigWord( hash )] |= lexSigBit( hash );
                    }
                }
            }
        }
    }

    // 4) attribute each reference to its enclosing definition (innermost span containing it).
    //    Per file: the enclosing def is the one with the latest startByte <= ref.startByte
    //    whose endByte > ref.startByte. We index defs by file via a sorted view.
    struct DefSpan
    {
        std::uint32_t startByte;
        std::uint32_t endByte;
        NodeId        id;
    };
    // group def spans by fileId in one flat array (rawDefs aligned 1:1 with result.symbols after the sort above).
    // The previous vector<vector<...>> shape allocated twice per file; offsets keep the same per-file ranges with
    // contiguous storage, which matters on C++ repos with many small headers.
    std::vector<std::size_t> fileSpanStart;
    std::vector<DefSpan>     defSpans;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: def-span index" );

        fileSpanStart.assign( result.files.size() + 1, 0 );
        for( const RawDef& d : rawDefs )
        {
            ++fileSpanStart[ d.fileId + 1 ];
        }
        for( std::size_t fileId = 1; fileId < fileSpanStart.size(); ++fileId )
        {
            fileSpanStart[ fileId ] += fileSpanStart[ fileId - 1 ];
        }

        defSpans.resize( rawDefs.size() );
        std::vector<std::size_t> fileSpanWrite = fileSpanStart;
        for( std::uint32_t i = 0; i < rawDefs.size(); ++i )
        {
            const std::size_t spanIndex = fileSpanWrite[ rawDefs[ i ].fileId ]++;
            defSpans[ spanIndex ] = { rawDefs[ i ].startByte, rawDefs[ i ].endByte, result.symbols[ i ].id };
        }

        for( std::size_t fileId = 0; fileId < result.files.size(); ++fileId )
        {
            const std::size_t begin = fileSpanStart[ fileId ];
            const std::size_t end   = fileSpanStart[ fileId + 1 ];
            // A4-F23a: startByte alone is not a total order — equal-start spans (a markdown file node and its
            // first-line heading both at byte 0) would get stdlib-dependent innermost attribution. Tie-break on
            // endByte DESCENDING (wider container first, so the sweep opens it before the nested span), then id
            // for totality → cross-platform byte-identical output.
            std::sort( defSpans.begin() + begin, defSpans.begin() + end,
                       []( const DefSpan& a, const DefSpan& b ) noexcept
                       {
                           if( a.startByte != b.startByte )
                           {
                               return a.startByte < b.startByte;
                           }
                           if( a.endByte != b.endByte )
                           {
                               return a.endByte > b.endByte;
                           }
                           return a.id < b.id;
                       } );
        }
    }

    // innermost enclosing def of a byte position: the container span with the LARGEST start ≤ pos whose end
    // is past pos (spans are start-sorted per file). Refs/bindings are consumed in deterministic
    // (fileId,startByte,...) order, so a single per-file sweep replaces one binary search per fact. The active
    // stack's back is the latest-start span still open, which is exactly the previous lookup's chosen container.
    struct DefSweep
    {
        const std::vector<DefSpan>&    spans;
        const std::vector<std::size_t>& fileStart;
        std::uint32_t                  currentFileId = std::numeric_limits<std::uint32_t>::max();
        std::size_t                    nextSpanIndex = 0;
        std::size_t                    endSpanIndex  = 0;
        std::vector<std::size_t>       activeSpanIndices;

        NodeId find( std::uint32_t fileId, std::uint32_t pos )
        {
            if( fileId != currentFileId )
            {
                currentFileId = fileId;
                nextSpanIndex = fileStart[ fileId ];
                endSpanIndex  = fileStart[ fileId + 1 ];
                activeSpanIndices.clear();
            }

            while( nextSpanIndex < endSpanIndex && spans[ nextSpanIndex ].startByte <= pos )
            {
                activeSpanIndices.push_back( nextSpanIndex++ );
            }
            while( !activeSpanIndices.empty() && spans[ activeSpanIndices.back() ].endByte <= pos )
            {
                activeSpanIndices.pop_back();
            }

            return activeSpanIndices.empty() ? kNoNode : spans[ activeSpanIndices.back() ].id;
        }
    };

    // references: emit in deterministic (fileId, startByte, name) order. A RawRef is FAT (5 std::strings ≈
    // 160 B), so we order a uint32 INDEX permutation instead of the objects themselves. Bucket by file first,
    // radix-sort each file's indices by the numeric startByte, then comparison-sort only equal-byte name ties.
    // Same ordering contract as the old comparator, but it moves the hot path onto byte histograms.
    std::vector<std::uint32_t> refOrder( rawRefs.size() );
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: sort ref index" );

        std::vector<std::size_t> refStartByFile( result.files.size() + 1, 0 );
        for( const RawRef& r : rawRefs )
        {
            ++refStartByFile[ r.fileId + 1 ];
        }
        for( std::size_t fileId = 1; fileId < refStartByFile.size(); ++fileId )
        {
            refStartByFile[ fileId ] += refStartByFile[ fileId - 1 ];
        }

        std::vector<std::size_t> refWriteByFile = refStartByFile;
        for( std::uint32_t i = 0; i < rawRefs.size(); ++i )
        {
            refOrder[ refWriteByFile[ rawRefs[ i ].fileId ]++ ] = i;
        }

        std::vector<std::uint32_t> refScratch( rawRefs.size() );
        // A4-F23b: (startByte,name) is NOT a total order — Python `class A(Foo)` captures `Foo` twice at one
        // byte with different roles (Extends + Read), so the stdlib sort's residual order was implementation-
        // dependent. Extend the key with role then isInherit for a total, cross-platform-stable ordering.
        const auto lessRefResidual = [ &rawRefs ]( const RawRef& a, const RawRef& b ) noexcept
        {
            if( a.name != b.name )
            {
                return a.name < b.name;
            }
            if( a.role != b.role )
            {
                return static_cast<std::uint8_t>( a.role ) < static_cast<std::uint8_t>( b.role );
            }
            return static_cast<int>( a.isInherit ) < static_cast<int>( b.isInherit );
        };
        const auto lessRefByByteName = [ &rawRefs, &lessRefResidual ]( std::uint32_t ia, std::uint32_t ib ) noexcept
        {
            const RawRef& a = rawRefs[ ia ];
            const RawRef& b = rawRefs[ ib ];
            if( a.startByte != b.startByte )
            {
                return a.startByte < b.startByte;
            }
            return lessRefResidual( a, b );
        };
        const auto lessRefByName = [ &rawRefs, &lessRefResidual ]( std::uint32_t ia, std::uint32_t ib ) noexcept
        {
            return lessRefResidual( rawRefs[ ia ], rawRefs[ ib ] );
        };
        const auto radixSortRefSegment = [ & ]( std::size_t begin, std::size_t end )
        {
            constexpr std::size_t kRadixThreshold = 64;
            const std::size_t count = end - begin;
            if( count < kRadixThreshold )
            {
                std::sort( refOrder.begin() + begin, refOrder.begin() + end, lessRefByByteName );
                return;
            }

            bool isAlreadySorted = true;
            for( std::size_t i = begin + 1; i < end; ++i )
            {
                if( lessRefByByteName( refOrder[ i ], refOrder[ i - 1 ] ) )
                {
                    isAlreadySorted = false;
                    break;
                }
            }
            if( isAlreadySorted )
            {
                return;
            }

            std::uint32_t* src = refOrder.data() + begin;
            std::uint32_t* dst = refScratch.data() + begin;
            bool inScratch = false;

            for( unsigned shift = 0; shift < 32; shift += 8 )
            {
                std::uint32_t hist[ 256 ] = {};
                for( std::size_t i = 0; i < count; ++i )
                {
                    ++hist[ ( rawRefs[ src[ i ] ].startByte >> shift ) & 0xffu ];
                }

                bool singleBucket = false;
                for( std::uint32_t h : hist )
                {
                    if( h == count ) { singleBucket = true; break; }
                }
                if( singleBucket )
                {
                    continue;
                }

                std::uint32_t offsets[ 256 ];
                std::uint32_t sum = 0;
                for( std::size_t i = 0; i < 256; ++i )
                {
                    offsets[ i ] = sum;
                    sum += hist[ i ];
                }
                for( std::size_t i = 0; i < count; ++i )
                {
                    const std::uint32_t idx = src[ i ];
                    const std::uint32_t bin = ( rawRefs[ idx ].startByte >> shift ) & 0xffu;
                    dst[ offsets[ bin ]++ ] = idx;
                }
                std::swap( src, dst );
                inScratch = !inScratch;
            }

            if( inScratch )
            {
                std::copy( src, src + count, refOrder.data() + begin );
            }

            std::size_t tieBegin = begin;
            while( tieBegin < end )
            {
                std::size_t tieEnd = tieBegin + 1;
                const std::uint32_t byte = rawRefs[ refOrder[ tieBegin ] ].startByte;
                while( tieEnd < end && rawRefs[ refOrder[ tieEnd ] ].startByte == byte )
                {
                    ++tieEnd;
                }
                if( tieEnd - tieBegin > 1 )
                {
                    std::sort( refOrder.begin() + tieBegin, refOrder.begin() + tieEnd, lessRefByName );
                }
                tieBegin = tieEnd;
            }
        };

        for( std::size_t fileId = 0; fileId < result.files.size(); ++fileId )
        {
            const std::size_t begin = refStartByFile[ fileId ];
            const std::size_t end   = refStartByFile[ fileId + 1 ];
            radixSortRefSegment( begin, end );
        }
    }

    // rawRefs is consumed here (never read again) → MOVE its 5 strings into each Reference instead of copying.
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: emit refs" );

        result.references.resize( rawRefs.size() );
        DefSweep refSweep{ defSpans, fileSpanStart };
        std::size_t outRefIndex = 0;
        for( std::uint32_t idx : refOrder )
        {
            RawRef& r = rawRefs[ idx ];
            Reference& ref = result.references[ outRefIndex++ ];
            ref.fileId      = r.fileId;
            ref.line        = r.line;        // ABS-3: 1-based use-site line for --uses p="file:line"
            ref.lang        = r.lang;
            ref.calleeName  = std::move( r.name );
            ref.qualifier   = std::move( r.qualifier );
            ref.role        = r.role;        // ABS-3 use-site role (call/read/write/import/extends)
            ref.isInherit   = r.isInherit;
            ref.isDocLink   = r.isDocLink;
            ref.isCompose   = r.isCompose;   // S5-E: HAS-A member-variable type edge — NEVER enters call graph
            ref.recv        = r.recv;        // P2-D receiver shape (this/self/var) for one-hop narrowing
            ref.recvVar     = std::move( r.recvVar );
            ref.argCount    = r.argCount;        // B2.2: call-site positional arg count (when countable)
            ref.argCountKnown = r.argCountKnown; // B2.2: whether argCount is reliable (no spread/splat)
            ref.fieldName   = std::move( r.fieldName );   // S5-E: the member variable name (e.g. "m_pool")
            ref.composeRel  = std::move( r.composeRel );  // S5-E: "creates" or "uses"
            ref.fromSymbol  = refSweep.find( r.fileId, r.startByte );
        }
    }

    // P2-D Rule 2: attribute each local var→type binding to its enclosing def (same containment scan as refs),
    // in deterministic (file, byte, var) order. A binding whose position is file-scope (kNoNode) is kept too —
    // buildGraph keys on (fromSymbol, var), so a file-scope binding only ever matches a file-scope recvVar call.
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: sort+emit binds" );

        std::sort( rawBinds.begin(), rawBinds.end(),
                   []( const RawBind& a, const RawBind& b ) noexcept
                   {
                       if( a.fileId != b.fileId )
                       {
                           return a.fileId < b.fileId;
                       }
                       if( a.startByte != b.startByte )
                       {
                           return a.startByte < b.startByte;
                       }
                       return a.var < b.var;
                   } );
        result.bindings.resize( rawBinds.size() );
        DefSweep bindSweep{ defSpans, fileSpanStart };
        std::size_t outBindIndex = 0;
        for( RawBind& rb : rawBinds )   // rawBinds consumed here → move its 2 strings into the Binding
        {
            Binding& b = result.bindings[ outBindIndex++ ];
            b.fileId     = rb.fileId;
            b.var        = std::move( rb.var );
            b.typeName   = std::move( rb.typeName );
            b.fromSymbol = bindSweep.find( rb.fileId, rb.startByte );
        }
    }

    result.includes = std::move( rawIncs );   // physical dependencies (#include / import), for --deps

    // A4-R5: FFI binding aliases in a deterministic total order (fileId, kind, aliasName, targetScope,
    // targetName) so buildGraph's alias tables are built identically warm-vs-cold, run-to-run.
    std::sort( rawFfis.begin(), rawFfis.end(),
               []( const BindingAlias& a, const BindingAlias& b ) noexcept
               {
                   if( a.fileId != b.fileId )
                   {
                       return a.fileId < b.fileId;
                   }
                   if( a.kind != b.kind )
                   {
                       return a.kind < b.kind;
                   }
                   if( a.aliasName != b.aliasName )
                   {
                       return a.aliasName < b.aliasName;
                   }
                   if( a.targetScope != b.targetScope )
                   {
                       return a.targetScope < b.targetScope;
                   }
                   return a.targetName < b.targetName;
               } );
    result.bindingAliases = std::move( rawFfis );

    // B6.3: HTTP-route DEFs need no byte-span attribution (their handler is resolved by NAME, in the
    // DEF's own file, by buildGraph) — just a deterministic total order.
    std::sort( rawRouteDefs.begin(), rawRouteDefs.end(),
               []( const RouteDef& a, const RouteDef& b ) noexcept
               {
                   if( a.fileId != b.fileId )
                   {
                       return a.fileId < b.fileId;
                   }
                   if( a.line != b.line )
                   {
                       return a.line < b.line;
                   }
                   if( a.method != b.method )
                   {
                       return a.method < b.method;
                   }
                   return a.path < b.path;
               } );
    result.routeDefs = std::move( rawRouteDefs );

    // B6.3: HTTP-route USEs attribute fromSymbol the same way refs/binds do above — byte-span containment
    // over the SAME defSpans/fileSpanStart sweep (a fresh DefSweep cursor; the previous ones are per-file
    // stateful and already exhausted).
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/build-model: sort+emit route uses" );

        std::sort( rawRouteUses.begin(), rawRouteUses.end(),
                   []( const RawRouteUse& a, const RawRouteUse& b ) noexcept
                   {
                       if( a.fileId != b.fileId )
                       {
                           return a.fileId < b.fileId;
                       }
                       if( a.startByte != b.startByte )
                       {
                           return a.startByte < b.startByte;
                       }
                       return a.path < b.path;
                   } );
        result.routeUses.resize( rawRouteUses.size() );
        DefSweep routeSweep{ defSpans, fileSpanStart };
        std::size_t outRouteIndex = 0;
        for( RawRouteUse& ru : rawRouteUses )   // rawRouteUses consumed here → move its string into the RouteUse
        {
            RouteUse& out = result.routeUses[ outRouteIndex++ ];
            out.fileId     = ru.fileId;
            out.line       = ru.line;
            out.method     = ru.method;
            out.path       = std::move( ru.path );
            out.fromSymbol = routeSweep.find( ru.fileId, ru.startByte );
        }
    }

    return result;
}

// text of a capture (first node with this index) in a match; false if absent / out of range.
inline bool captureText( const TSQueryMatch& m, std::uint32_t capIndex, std::string_view src, std::string& out )
{
    for( std::uint16_t i = 0; i < m.capture_count; ++i )
    {
        if( m.captures[i].index == capIndex )
        {
            const TSNode n = m.captures[i].node;
            const std::uint32_t a = ts_node_start_byte( n ), b = ts_node_end_byte( n );
            if( a <= b && b <= src.size() ) { out = std::string( src.substr( a, b - a ) ); return true; }
            return false;
        }
    }
    return false;
}

// evaluate a pattern's query predicates against a match — #eq? / #not-eq? (string/capture equality) and
// #match? / #not-match? (ECMAScript regex). ts_query never applies these itself; without this, #eq? is a no-op.
inline bool passesPredicates( const TSQuery* q, const TSQueryMatch& m, std::string_view src )
{
    std::uint32_t pc = 0;
    const TSQueryPredicateStep* steps = ts_query_predicates_for_pattern( q, m.pattern_index, &pc );
    const auto argText = [ & ]( const TSQueryPredicateStep& s, std::string& out ) -> bool
    {
        if( s.type == TSQueryPredicateStepTypeCapture )
        {
            return captureText( m, s.value_id, src, out );
        }
        if( s.type == TSQueryPredicateStepTypeString )
        {
            std::uint32_t l = 0;
            const char* v = ts_query_string_value_for_id( q, s.value_id, &l );
            out.assign( v, l );
            return true;
        }
        return false;
    };
    for( std::uint32_t i = 0; i < pc; )
    {
        std::vector<TSQueryPredicateStep> pr;
        for( ; i < pc && steps[i].type != TSQueryPredicateStepTypeDone; ++i )
        {
            pr.push_back( steps[i] );
        }
        ++i;                                                            // skip the Done step
        if( pr.size() < 3 || pr[0].type != TSQueryPredicateStepTypeString )
        {
            continue;
        }
        // TWO statements, deliberately. Written as ONE — `string_view( f( …, &nl ), nl )` — the length
        // argument `nl` and the call that WRITES it are two arguments of the SAME call, and the order in
        // which a call's arguments are evaluated is UNSPECIFIED. GCC on x86-64 evaluates them right-to-left,
        // so it read `nl` while it was still 0: `op` came out EMPTY, matched none of the operator names
        // below, and every #eq?/#not-eq?/#match?/#not-match? predicate was silently skipped (`ok` stays
        // true ⇒ nothing filtered). GCC on aarch64 and Clang everywhere evaluate left-to-right and happened
        // to get it right, which is why this only ever reddened on x86-64 Linux/gcc — measured 2026-08-02:
        // g++-13 -O0 AND -O2 on x86-64 print len=0, the same g++-13 on aarch64 and clang-18 on x86-64 print
        // len=6. Sequencing the write before the read IS the fix; do not re-inline these two lines.
        std::uint32_t nl     = 0;
        const char*   opText = ts_query_string_value_for_id( q, pr[0].value_id, &nl );
        if( opText == nullptr )
        {
            continue; // no operator name ⇒ can't evaluate ⇒ don't filter
        }
        const std::string_view op( opText, nl );
        std::string lhs, rhs;
        if( !argText( pr[1], lhs ) || !argText( pr[2], rhs ) )
        {
            continue; // can't evaluate → don't filter
        }
        bool ok = true;
        if( op == "eq?" )
        {
            ok = ( lhs == rhs );
        }
        else if( op == "not-eq?" )
        {
            ok = ( lhs != rhs );
        }
        else if( op == "match?" || op == "not-match?" )
        { try { const bool mm = std::regex_search( lhs, std::regex( rhs ) ); ok = ( op == "match?" ) ? mm : !mm; } catch( ... ) { ok = true; } }
        if( !ok )
        {
            return false;
        }
    }
    return true;
}

// ---- per-file newline-offset index → O(log n) 1-based line lookup (A4 perf) ----
// Replaces the per-capture "scan [0,startByte) counting '\n'" (byte-0 rescan, O(startByte) EACH match)
// with one O(fileBytes) pass + a binary search per capture. Byte-identical result:
//   line(b) = 1 + (# of '\n' at offset < b) = 1 + lower_bound(offsets, b) position.
inline std::vector<std::uint32_t> buildNewlineOffsets( std::string_view src )
{
    std::vector<std::uint32_t> off;
    for( std::uint32_t i = 0; i < src.size(); ++i )
    {
        if( src[i] == '\n' )
        {
            off.push_back( i );
        }
    }
    return off;
}
inline std::uint32_t lineAtByte( const std::vector<std::uint32_t>& nlOffsets, std::uint32_t bytePos ) noexcept
{
    return std::uint32_t( 1 + ( std::lower_bound( nlOffsets.begin(), nlOffsets.end(), bytePos ) - nlOffsets.begin() ) );
}

// ---- shared AST-query pass (--match / --lint) ----
std::vector<AstMatch> astQuery( const IngestResult& ing, const std::vector<AstQuerySpec>& specs, std::size_t maxMatches,
                                std::vector<std::string>* uncompiledOut )
{
    std::vector<AstMatch> out;
    if( specs.empty() || ing.files.empty() )
    {
        return out;
    }

    // Compile each spec against every DISTINCT grammar it is valid for (up front, single-threaded). Queries
    // are immutable after creation → shared read-only across workers; only the cursor is per-thread.
    HashMap<const TSLanguage*, std::vector<std::pair<TSQuery*, std::string>>> byGrammar;
    for( const LangEntry& e : kLangTable )
    {
        if( e.grammar == nullptr )
        {
            continue; // markdown — no tree-sitter grammar (calling the null fn ptr = SIGSEGV)
        }
        const TSLanguage* g = e.grammar();
        if( byGrammar.find( g ) != byGrammar.end() )
        {
            continue;
        }
        std::vector<std::pair<TSQuery*, std::string>> compiled;
        for( const AstQuerySpec& spec : specs )
        {
            std::uint32_t off = 0;  TSQueryError err = TSQueryErrorNone;
            if( TSQuery* q = ts_query_new( g, spec.query.data(), static_cast<std::uint32_t>( spec.query.size() ), &off, &err ) )
            {
                compiled.emplace_back( q, spec.tag );
            }
        }
        byGrammar.emplace( g, std::move( compiled ) );
    }
    for( const AstQuerySpec& spec : specs )   // warn once if a spec compiled for NO grammar (malformed query)
    {
        bool any = false;
        for( const auto& [g, qs] : byGrammar )
        {
            for( const auto& [q, tag] : qs )
            {
                if( tag == spec.tag )
                {
                    any = true;
                    break;
                }
            }
            if( any )
            {
                break;
            }
        }
        if( !any )
        {
            std::fprintf( stderr, "ripwire: AST query did not compile for any grammar: %.*s\n", int( spec.query.size() ), spec.query.data() );
            if( uncompiledOut )
            {
                uncompiledOut->push_back( spec.query );
            }
        }
    }

    const std::size_t nfiles = ing.files.size();
    unsigned hw = std::thread::hardware_concurrency();
    if( hw == 0 )
    {
        hw = 1;
    }
    const unsigned nthreads = static_cast<unsigned>( std::min<std::size_t>( hw, nfiles ) );

    // NO mid-flight global cap: a shared match counter raced by workers makes WHICH matches survive the
    // cap scheduling-dependent (nondeterministic --lint/--match on repos past maxMatches). Collect every
    // file's matches fully (per-file counts are naturally bounded and short-lived), sort deterministically,
    // THEN truncate to maxMatches — cap membership becomes a pure function of the input.
    std::vector<std::vector<AstMatch>> tHits( nthreads );
    std::atomic<std::size_t>           nextFile{ 0 };
    std::vector<std::thread>           pool;  pool.reserve( nthreads );

    for( unsigned t = 0; t < nthreads; ++t )
    {
        pool.emplace_back( [ &, t ]()
        {
            ParserGuard pg;
            if( pg.p == nullptr )
            {
                return;
            }
            TSQueryCursor* cur = ts_query_cursor_new();
            std::string    bytes;
            for( ;; )
            {
                const std::size_t fileId = nextFile.fetch_add( 1, std::memory_order_relaxed );
                if( fileId >= nfiles )
                {
                    break;
                }
                try
                {
                    const std::string& path = diskPath( ing, std::uint32_t( fileId ) );   // multi-root: labeled ing.files → on-disk path
                    const std::string ext = lowerExtensionOf( path );
                    const LangEntry* le = lookupLang( ext );
                    if( le == nullptr )
                    {
                        continue;
                    }
                    if( !readFile( path, bytes ) )
                    {
                        continue;
                    }
                    if( looksBinary( bytes ) )
                    {
                        continue;
                    }
                    if( ext == ".h" && looksObjC( bytes ) )
                    {
                        if( const LangEntry* objcLe = lookupLang( ".m" ) )
                        {
                            le = objcLe;
                        }
                    }

                    if( le->grammar == nullptr )
                    {
                        continue; // markdown — no grammar (would deref a null fn ptr)
                    }
                    const TSLanguage* g  = le->grammar();
                    const auto        it = byGrammar.find( g );
                    if( it == byGrammar.end() || it->second.empty() )
                    {
                        continue; // no spec applies to this grammar
                    }
                    if( !ts_parser_set_language( pg.p, g ) || !grammarAbiOk( g ) )
                    {
                        continue;
                    }
                    TSTree* tree = ts_parser_parse_string( pg.p, nullptr, bytes.data(), static_cast<std::uint32_t>( bytes.size() ) );
                    if( !tree )
                    {
                        continue;
                    }
                    const TSNode root = ts_tree_root_node( tree );
                    const std::vector<std::uint32_t> nlOffsets = buildNewlineOffsets( bytes );   // one pass, then binary-search per capture
                    for( const auto& [q, tag] : it->second )
                    {
                        ts_query_cursor_exec( cur, q, root );
                        TSQueryMatch m;
                        while( ts_query_cursor_next_match( cur, &m ) )
                        {
                            if( !passesPredicates( q, m, bytes ) )
                            {
                                continue; // honour #eq? / #match? etc.
                            }
                            for( std::uint16_t c = 0; c < m.capture_count; ++c )
                            {
                                const TSNode        n = m.captures[c].node;
                                const std::uint32_t a = ts_node_start_byte( n ), b = ts_node_end_byte( n );
                                if( a >= b || b > bytes.size() )
                                {
                                    continue;
                                }
                                const std::uint32_t line = lineAtByte( nlOffsets, a );
                                std::size_t cutLen = std::min<std::size_t>( b - a, 120u );
                                if( cutLen < b - a )
                                { // truncated mid-text → back off UTF-8 continuation bytes so the cut never splits a codepoint (same pattern as serialize.h packSource)
                                    while( cutLen > 0 && ( static_cast<unsigned char>( bytes[a + cutLen] ) & 0xC0 ) == 0x80 )
                                    {
                                        --cutLen;
                                    }
                                }
                                std::string text = bytes.substr( a, cutLen );
                                for( char& ch : text )
                                {
                                    if( ch == '\n' || ch == '\r' || ch == '\t' )
                                    {
                                        ch = ' ';
                                    }
                                }
                                tHits[t].push_back( { std::uint32_t( fileId ), a, b, line, tag, std::move( text ) } );
                            }
                        }
                    }
                    ts_tree_delete( tree );
                }
                catch( ... ) { /* per-file degrade — never abort the pass */ }
            }
            ts_query_cursor_delete( cur );
        } );
    }
    for( std::thread& th : pool )
    {
        th.join();
    }

    for( auto& [g, qs] : byGrammar )
    {
        for( auto& [q, tag] : qs )
        {
            ts_query_delete( q );
        }
    }

    std::size_t tot = 0;
    for( const auto& v : tHits )
    {
        tot += v.size();
    }
    out.reserve( tot );
    for( auto& v : tHits )
    {
        for( auto& m : v )
        {
            out.push_back( std::move( m ) );
        }
    }
    std::sort( out.begin(), out.end(), [ & ]( const AstMatch& x, const AstMatch& y ) // deterministic order
               {
                   if( ing.files[x.fileId] != ing.files[y.fileId] )
                   {
                       return ing.files[x.fileId] < ing.files[y.fileId];
                   }
                   if( x.startByte != y.startByte )
                   {
                       return x.startByte < y.startByte;
                   }
                   if( x.endByte != y.endByte )
                   {
                       return x.endByte < y.endByte; // nested same-start captures (outer+inner call at one byte) need this or std::sort leaks thread arrival order
                   }
                   return x.tag < y.tag;                                                // equal keys ⇒ identical records (text derives from [start,end)) — order among them can't affect output
               } );

    // ── deterministic PER-SPEC cap (§P0.2), applied AFTER the sort so the survivors are a pure function of
    // the input. One POOLED budget let the noisiest query eat it: `(number_literal)` alone filled 5000, the
    // pool was path-sorted then cut, and every other rule was starved of the tail of the tree — `--lint`
    // reported goto=1 on a tree with two and do-while=0 on a tree with one. Each tag now spends its OWN
    // budget, which is exactly what a separate pass per spec would have produced (same collected set, same
    // (file, startByte) order within a tag) at the cost of ONE tree walk instead of N.
    HashMap<std::string, std::uint32_t> tagSlot;   tagSlot.reserve( specs.size() * 2 );
    for( const AstQuerySpec& spec : specs )
    {
        const std::uint32_t nextSlot = static_cast<std::uint32_t>( tagSlot.size() );
        tagSlot.emplace( spec.tag, nextSlot );                          // duplicate tags share one budget, by design
    }

    std::vector<std::size_t> keptPerTag( tagSlot.size(), 0 );
    std::vector<AstMatch>    keep;   keep.reserve( out.size() );
    for( AstMatch& m : out )
    {
        const auto slotIt = tagSlot.find( m.tag );
        VERIFY( slotIt != tagSlot.end() );                              // every emitted tag came from a spec
        std::size_t& keptCount = keptPerTag[ slotIt->second ];
        if( keptCount >= maxMatches )
        {
            continue; // this spec's own budget is spent — never another's
        }
        ++keptCount;
        keep.push_back( std::move( m ) );
    }
    return keep;
}

// ---- unreachable-code detection (built-in --lint rule "unreachable-code") ----
//
// A GENUINE block node — a brace-delimited statement list whose direct children are the block's
// statements (NOT a switch body's case list, NOT a case body). Only these are scanned: within one,
// a statement's straight-line successor is a plain sibling, so "code after an unconditional exit is
// dead" holds syntactically. Case bodies (children of case_statement) are deliberately NOT blocks
// here, so `break; x();` inside a case is never flagged (conservative — no false positives).
inline bool ur_isBlockNode( const char* t ) noexcept
{
    return    std::strcmp( t, "compound_statement" ) == 0    // C / C++ / ObjC
           || std::strcmp( t, "block" ) == 0                 // Python / Java (and other {…} blocks)
           || std::strcmp( t, "statement_block" ) == 0;      // JS / TS
}

// An UNCONDITIONAL terminator statement: once seen at a block level, control cannot fall through to
// the next sibling. `goto` is intentionally EXCLUDED — a following statement can be a label target,
// so flagging it would be a false positive (the #1 trap this check must avoid). `return_statement`
// covers C-family + Python; `raise_statement` is Python's throw.
inline bool ur_isTerminator( const char* t ) noexcept
{
    return    std::strcmp( t, "return_statement" ) == 0
           || std::strcmp( t, "break_statement" ) == 0
           || std::strcmp( t, "continue_statement" ) == 0
           || std::strcmp( t, "throw_statement" ) == 0       // C++ / ObjC / Java / JS
           || std::strcmp( t, "raise_statement" ) == 0;      // Python
}

// A node that is NOT a real statement for reachability purposes — skip it when looking for the next
// sibling after a terminator (comments, and the block's own braces/colon punctuation). tree-sitter
// exposes comments as named siblings inside a block; a comment after `return` is not dead CODE.
inline bool ur_isSkippableSibling( TSNode n ) noexcept
{
    if( !ts_node_is_named( n ) )
    {
        return true; // '{', '}', ';', ':' punctuation tokens
    }
    const char* t = ts_node_type( n );
    return std::strcmp( t, "comment" ) == 0;
}

// A jump TARGET sibling: a label or a case makes the following statements reachable out-of-line, so
// the moment one appears after a terminator we STOP scanning this block (never flag past it). This
// is the second false-positive guard (belt-and-braces with excluding goto and not scanning case
// bodies): even a stray label inside a plain block halts the dead-code claim.
inline bool ur_isJumpTarget( const char* t ) noexcept
{
    return    std::strcmp( t, "labeled_statement" ) == 0     // C-family `lbl:` (goto/switch fallthrough target)
           || std::strcmp( t, "case_statement" ) == 0        // C-family switch case/default
           || std::strcmp( t, "case" ) == 0                  // grammar variants
           || std::strcmp( t, "default" ) == 0;
}

// Walk one file's AST (iterative frame-stack DFS — the cc_walk shape, NO recursion). For every block
// node, scan its direct children left-to-right; the FIRST non-skippable statement after a terminator
// (with no intervening jump target) is unreachable → one finding at that statement's start byte.
inline void ur_walkTree( TSNode root, std::uint32_t fileId, std::string_view src, const std::vector<std::uint32_t>& nlOffsets, std::vector<AstMatch>& hits )   // A4-F25: NOT noexcept — allocates (see cc_walk)
{
    struct UrFrame { TSNode node; std::uint16_t depth; };
    std::vector<UrFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { root, 0 } );
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );

    while( !stack.empty() )
    {
        const UrFrame frame = stack.back();
        stack.pop_back();
        if( frame.depth > 512 )
        {
            continue; // pathological-AST guard (file capped at 1 MB)
        }
        const TSNode        n          = frame.node;
        const std::uint16_t childDepth = static_cast<std::uint16_t>( frame.depth + 1 );
        const char*         t          = ts_node_type( n );
        collectChildren( n, cursor.cur, kids );              // one collection serves the block scan AND the descent

        // If this is a genuine block, scan its statement siblings for a post-terminator statement.
        if( ur_isBlockNode( t ) )
        {
            bool sawTerminator = false;
            for( const TSNode c : kids )
            {
                const char* ct = ts_node_type( c );

                if( sawTerminator )
                {
                    if( ur_isSkippableSibling( c ) )
                    {
                        continue; // comment / punctuation → not code, keep looking
                    }
                    if( ur_isJumpTarget( ct ) )
                    {
                        break; // label/case → reachable out-of-line → stop, no flag
                    }
                    // First real statement after an unconditional exit in this block → UNREACHABLE.
                    const std::uint32_t a = ts_node_start_byte( c ), b = ts_node_end_byte( c );
                    if( a < b && b <= src.size() )
                    {
                        const std::uint32_t line = lineAtByte( nlOffsets, a );
                        std::size_t cutLen = std::min<std::size_t>( b - a, 120u );
                        if( cutLen < b - a )
                        { // UTF-8-safe truncation (serialize.h/astQuery pattern)
                            while( cutLen > 0 && ( static_cast<unsigned char>( src[a + cutLen] ) & 0xC0 ) == 0x80 )
                            {
                                --cutLen;
                            }
                        }
                        std::string text( src.substr( a, cutLen ) );
                        for( char& ch : text )
                        {
                            if( ch == '\n' || ch == '\r' || ch == '\t' )
                            {
                                ch = ' ';
                            }
                        }
                        hits.push_back( { fileId, a, b, line, std::string( "unreachable-code" ), std::move( text ) } );
                    }
                    break;   // one finding per block — the first dead statement; the rest are consequential noise
                }
                else if( ur_isSkippableSibling( c ) )
                {
                    continue;                                       // comments/punctuation don't set the terminator flag
                }
                else if( ur_isTerminator( ct ) )
                {
                    sawTerminator = true;                           // arm: the NEXT real sibling is unreachable
                }
                // else: an ordinary statement — reachable; a terminator inside it (nested block/branch)
                //       is handled when we descend into that child's own block, never at THIS level.
            }
        }

        // Descend into every child (blocks nest — a function body holds inner blocks, and non-block
        // statements like if/for CONTAIN blocks we must still reach). Push in reverse for L-to-R order.
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[ i - 1 ], childDepth } );
        }
    }
}

// local-variable-indexing plan, Phase 2 (PLAN.md 2026-08-06 evening) — see ingest.h's own comment for the
// full contract. Definition lives HERE (outside the anonymous namespace above) purely for LINKAGE — it
// must be externally callable to satisfy ingest.h's declaration — while every helper it calls
// (ln_extractDeclaratorIdentifiers / ln_declaratorIdentifiers / ln_declDepth / ln_collectLocalDecls) stays
// anonymous-namespace-scoped next to cc_walk/complexityOf, which they mirror.
std::vector<LocalNameFact> collectGatedLocalNames( std::string_view defBytes, std::uint32_t defStartLine, Lang lang )
{
    std::vector<LocalNameFact> out;
    if( !localsCountedLang( lang ) || defBytes.empty() )
    {
        return out;   // MVP scope (model.h::localsCountedLang) — degrade to empty, never assert on a caller mistake
    }
    const TSLanguage* grammar = ( lang == Lang::C ) ? tree_sitter_c() : tree_sitter_cpp();
    TSParser* parser = ts_parser_new();
    if( parser == nullptr )
    {
        return out;
    }
    ts_parser_set_language( parser, grammar );
    TSTree* tree = ts_parser_parse_string( parser, nullptr, defBytes.data(), std::uint32_t( defBytes.size() ) );
    if( tree == nullptr )
    {
        ts_parser_delete( parser );
        return out;
    }
    const TSNode root = ts_tree_root_node( tree );
    // the def parses as a single top-level function_definition inside a translation_unit — descend into
    // the translation_unit's children (bounded: one file-worth of def text, already size-capped upstream).
    const std::uint32_t n = ts_node_child_count( root );
    for( std::uint32_t i = 0; i < n; ++i )
    {
        ln_collectLocalDecls( ts_node_child( root, i ), ts_node_child( root, i ), 512, out, defStartLine, defBytes );
    }
    ts_tree_delete( tree );
    ts_parser_delete( parser );
    return out;
}

std::vector<AstMatch> unreachableCheck( const IngestResult& ing, std::size_t maxMatches )
{
    std::vector<AstMatch> out;
    if( ing.files.empty() )
    {
        return out;
    }

    const std::size_t nfiles = ing.files.size();
    unsigned hw = std::thread::hardware_concurrency();
    if( hw == 0 )
    {
        hw = 1;
    }
    const unsigned nthreads = static_cast<unsigned>( std::min<std::size_t>( hw, nfiles ) );

    // Per-thread hit buckets, merged + sorted after the join (same determinism discipline as astQuery:
    // no shared mid-flight counter, so WHICH findings survive the cap is a pure function of the input).
    std::vector<std::vector<AstMatch>> tHits( nthreads );
    std::atomic<std::size_t>           nextFile{ 0 };
    std::vector<std::thread>           pool;  pool.reserve( nthreads );

    for( unsigned t = 0; t < nthreads; ++t )
    {
        pool.emplace_back( [ &, t ]()
        {
            ParserGuard pg;
            if( pg.p == nullptr )
            {
                return;
            }
            std::string bytes;
            for( ;; )
            {
                const std::size_t fileId = nextFile.fetch_add( 1, std::memory_order_relaxed );
                if( fileId >= nfiles )
                {
                    break;
                }
                try
                {
                    const std::string& path = diskPath( ing, std::uint32_t( fileId ) );   // multi-root: labeled ing.files → on-disk path
                    const std::string ext = lowerExtensionOf( path );
                    const LangEntry* le = lookupLang( ext );
                    if( le == nullptr )
                    {
                        continue;
                    }
                    if( !readFile( path, bytes ) )
                    {
                        continue;
                    }
                    if( looksBinary( bytes ) )
                    {
                        continue;
                    }
                    if( ext == ".h" && looksObjC( bytes ) )
                    {
                        if( const LangEntry* objcLe = lookupLang( ".m" ) )
                        {
                            le = objcLe;
                        }
                    }
                    if( le->grammar == nullptr )
                    {
                        continue; // markdown — no grammar
                    }

                    const TSLanguage* g = le->grammar();
                    if( !ts_parser_set_language( pg.p, g ) || !grammarAbiOk( g ) )
                    {
                        continue;
                    }
                    TSTree* tree = ts_parser_parse_string( pg.p, nullptr, bytes.data(), static_cast<std::uint32_t>( bytes.size() ) );
                    if( !tree )
                    {
                        continue;
                    }
                    const std::vector<std::uint32_t> nlOffsets = buildNewlineOffsets( bytes );   // one pass; ur_walkTree binary-searches it
                    ur_walkTree( ts_tree_root_node( tree ), std::uint32_t( fileId ), bytes, nlOffsets, tHits[t] );
                    ts_tree_delete( tree );
                }
                catch( ... ) { /* per-file degrade — never abort the pass */ }
            }
        } );
    }
    for( std::thread& th : pool )
    {
        th.join();
    }

    std::size_t tot = 0;
    for( const auto& v : tHits )
    {
        tot += v.size();
    }
    out.reserve( tot );
    for( auto& v : tHits )
    {
        for( auto& m : v )
        {
            out.push_back( std::move( m ) );
        }
    }
    std::sort( out.begin(), out.end(), [ & ]( const AstMatch& x, const AstMatch& y ) // deterministic order
               {
        if( ing.files[x.fileId] != ing.files[y.fileId] ) { return ing.files[x.fileId] < ing.files[y.fileId];
}
        if( x.startByte != y.startByte ) { return x.startByte < y.startByte;
}
        if( x.endByte   != y.endByte   ) { return x.endByte   < y.endByte;     // same total tie-break as astQuery — same-start ties must not leak thread arrival order
}
        return x.tag < y.tag; } );
    if( out.size() > maxMatches )
    {
        out.resize( maxMatches );
    }
    return out;
}

}   // namespace rw
