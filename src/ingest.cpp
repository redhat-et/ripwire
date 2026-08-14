// ingest.cpp — Phase 2 INGEST. Deterministic crawl + tree-sitter tags-query extraction.
//
// Pipeline:
//   crawl -> skip-filter -> SORT paths (byte order) -> per-file parse + ONE tags query ->
//   collect raw defs/refs -> assign Symbol ids in (file,line,name) order ->
//   attribute each Reference to its enclosing definition by byte-span containment.
//
// Single-threaded (v1). Never throws: every recoverable problem degrades + DEGRADED_PATH_ALERT.

#include "ingest.h"
#include "docparse.h"          // P1-B: non-code document ingest (notebooks/html/csv + markitdown bridge)
#include "arch.h"              // T5: relForHash — root-relative path key, reused for cache portability
#include "quality.h"           // A5: cacheDirLadder + sweepStaleCacheBlobsOnce — the cache-dir hygiene hook (saveCache)
#include "embedded_queries.h"  // configure-generated constexpr tags.scm table; no runtime source-tree dependency
#include "infra/hashutil.h"    // sanitizer-clean modulo-2^64 FNV multiplication
#include "infra/namesplit.h"   // H4: stripTemplateArgs for the C++ qualified-call re-split (shared with tracelocus.h)
#include "infra/fixedStr.h"    // rw::findByte — the NEON/SSE2 byte scan buildNewlineOffsets rides
#include "lexindex.h"          // B0.1/B0.2: shared subtoken state machine + per-def lexical statistics builder

#include "infra/Diagnostics.h"
#include "infra/profileScope.h"  // PROFILE_SCOPE self-profiling — gated by PROFILE_ENABLED (off unless -DRIPWIRE_PROFILE=ON)

#include <tree_sitter/api.h>

#include <algorithm>
#include <array>
#include <bit>                 // std::bit_floor — the cold-path reserve rounds to a power of two
#include <cctype>
#include <chrono>              // A4-P7: wall-clock cache-write timestamp for the racy-git rule
#include <cstdio>
#include <cstdlib>             // std::getenv — RIPWIRE_CACHE_STATS drift observable
#include <cstring>
#include <sys/stat.h>          // A4-P7: stat() for the (size,mtime) warm-run shortcut
#include <unistd.h>            // getpid — unique per-process cache temp name
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

#ifdef RIPWIRE_FUSE_PROBE
// ── Side-capture walk probe (compile-time opt-in; absent from every shipped build) ────────────────────
// The instrument behind the walk fusion in captureSideFacts. It separates the two things that "one more
// pass" can mean, because only one of them is what the fusion removes:
//   * STREAM POPS  — frames popped off a walk stack. One per node PER WALK, so N back-to-back walks over
//                    the same tree cost N x. This is the tree-streaming cost the fusion attacks.
//   * VISITOR CALLS — per-node matching work for one pass. Fusion does NOT reduce these; a pass still
//                    inspects every node it used to. If these move, a fact was dropped or double-counted.
// Compiled out entirely unless -DRIPWIRE_FUSE_PROBE is on the command line, so the plain/asan/profile
// builds are unaffected. Everything lands on STDERR — stdout is the XML map under a byte-identity gate.
//
//    cmake -S . -B build_probe -DCMAKE_CXX_FLAGS=-DRIPWIRE_FUSE_PROBE && cmake --build build_probe -j
//    TMPDIR=$(mktemp -d) ./build_probe/ripwire <corpus> >/dev/null      # TMPDIR forces a cold parse
namespace fuseprobe
{
enum PassId : int { kInc = 0, kFfi = 1, kRoutes = 2, kRustImpls = 3, kBinds = 4, kUses = 5, kPassCount = 6 };
inline const char* const kPassName[ kPassCount ] = { "captureIncludes", "captureFfi", "captureRoutes", "captureRustImpls", "captureBindings", "captureUses" };

inline thread_local std::uint64_t tlNodes[ kPassCount ] = {};   // visitor calls, this thread, cumulative
inline std::atomic<std::uint64_t> gNodes[ kPassCount ];         // visitor calls per pass, corpus-wide
inline std::atomic<std::uint64_t> gFiles[ kPassCount ];         // files on which the pass saw >=1 node
inline std::atomic<std::uint64_t> gHist[ kPassCount + 1 ];      // files by count of passes that saw a node
inline std::atomic<std::uint64_t> gFilesTotal { 0 };
inline std::atomic<std::uint64_t> gNodesMaxPass { 0 };          // sum of the per-file LARGEST pass = AST-size proxy
inline std::atomic<std::uint64_t> gStreamPops { 0 };            // THE fusion metric: frames popped, all walks

inline void bump( int pass ) noexcept { ++tlNodes[ pass ]; }
inline void pop() noexcept { gStreamPops.fetch_add( 1, std::memory_order_relaxed ); }

struct Dump
{
    ~Dump()
    {
        const std::uint64_t files = gFilesTotal.load();
        std::uint64_t       calls = 0;
        for( int p = 0; p < kPassCount; ++p )
        {
            calls += gNodes[ p ].load();
        }
        std::fprintf( stderr, "\n[fuseprobe] files_with_a_parsed_tree=%llu\n", (unsigned long long) files );
        std::fprintf( stderr, "[fuseprobe] %-18s %13s %10s %8s\n", "pass", "visitor_calls", "files", "%files" );
        for( int p = 0; p < kPassCount; ++p )
        {
            const std::uint64_t f = gFiles[ p ].load();
            std::fprintf( stderr, "[fuseprobe] %-18s %13llu %10llu %7.1f%%\n", kPassName[ p ], (unsigned long long) gNodes[ p ].load(),
                          (unsigned long long) f, files ? 100.0 * double( f ) / double( files ) : 0.0 );
        }
        const std::uint64_t astProxy = gNodesMaxPass.load();
        const std::uint64_t pops     = gStreamPops.load();
        std::fprintf( stderr, "[fuseprobe] visitor_calls=%llu  ast_size_proxy(sum of per-file max pass)=%llu\n",
                      (unsigned long long) calls, (unsigned long long) astProxy );
        std::fprintf( stderr, "[fuseprobe] STREAM_POPS=%llu  streams_per_node=%.2fx  <-- the number fusion moves\n",
                      (unsigned long long) pops, astProxy ? double( pops ) / double( astProxy ) : 0.0 );
        std::fprintf( stderr, "[fuseprobe] files by number of passes that SAW a node:\n" );
        for( int k = 0; k <= kPassCount; ++k )
        {
            const std::uint64_t f = gHist[ k ].load();
            if( f != 0 )
            {
                std::fprintf( stderr, "[fuseprobe]   %d pass%s : %10llu files (%5.1f%%)\n", k, k == 1 ? " " : "es", (unsigned long long) f,
                              files ? 100.0 * double( f ) / double( files ) : 0.0 );
            }
        }
        std::fflush( stderr );
    }
};
inline Dump gDump;
}   // namespace fuseprobe
    #define FUSEPROBE_BUMP( p ) ::fuseprobe::bump( ::fuseprobe::p )
    #define FUSEPROBE_POP()     ::fuseprobe::pop()
#else
    #define FUSEPROBE_BUMP( p ) ( (void) 0 )
    #define FUSEPROBE_POP()     ( (void) 0 )
#endif

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
    const TSLanguage* tree_sitter_toml( void );
    const TSLanguage* tree_sitter_yaml( void );
    const TSLanguage* tree_sitter_c_sharp( void );
    const TSLanguage* tree_sitter_c( void );
    const TSLanguage* tree_sitter_cuda( void );
    const TSLanguage* tree_sitter_markdown( void );
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
// The extent is EXACT, not headroom: it was 32 with 32 rows, .toml made it 33, .pyi made it 34 and the
// .yml/.yaml pair made it 36. Sizing it to the row count is what makes
// `std::array<bool, kLangTable.size()> present` (the grammar-prewarm set,
// below) exact too, and it turns "added a row and forgot the extent" into a compile error rather than a
// silent drop.
constexpr std::array<LangEntry, 37> kLangTable = {{
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
    // The former §7b limit (a `__constant__ float T[ 64 ];` module table yielded no symbol) is CLOSED as
    // of kParserVer 60: the real gap was the missing initializer — the r3 q10 patterns required an
    // init_declarator, and the cudaMemcpyToSymbol idiom never has one. tags.scm now carries structural
    // uninitialized-declaration patterns and cudaMemorySpaceQualifierOf gates them at capture time
    // (`__constant__` case-blind; `__device__`/`__managed__` behind the SCREAMING gate) — pinned positive
    // in test/cudacheck.sh §7b, which also pins the by-design non-goals: a lower-case mutable `__device__`
    // global stays out, and an uninitialized declaration with NO memory-space qualifier (the plain-C++
    // extern/static/alignas shapes) is dropped, so non-CUDA C++ maps are unchanged.
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
    { ".pyi",  Lang::Python,     &tree_sitter_python,     "python"     },   // typing stub — often a library's ONLY Python-visible API (a Rust/C core's whole Python surface lives in one .pyi)
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
    { ".toml", Lang::Toml,       &tree_sitter_toml,       "toml"       },   // TOML — [table] headers + their keys as t="sec"; DATA, no call edges
    { ".yml",  Lang::Yaml,       &tree_sitter_yaml,       "yaml"       },   // YAML — mapping keys (mdepth<=2, seqs transparent) as t="sec"; DATA, no call edges
    { ".yaml", Lang::Yaml,       &tree_sitter_yaml,       "yaml"       },   // YAML sibling extension (k8s manifests favour it)
    { ".cs",   Lang::CSharp,     &tree_sitter_c_sharp,    "csharp"     },   // C# — classes/structs/interfaces/records/enums/methods/props + calls
    { ".md",   Lang::Markdown,   &tree_sitter_markdown,   ""           },   // Markdown DOC tier — headings/sections via extractMarkdown()'s custom tree walk; NO tags.scm (query stays "")
    { ".markdown", Lang::Markdown, &tree_sitter_markdown, ""           },   // sibling extension, same walk — scope disclosed: .md/.markdown only
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
    if( tail == "enummember" )     // Python `NAME = value` in an enum-family class — gated (isPyEnumMemberTarget)
    {
        return SymKind::Var;
    }
    if( tail == "module" )
    {
        return SymKind::Other;
    }
    if( tail == "macro" )
    {
        // macro-edges round: honest kind (was Function). C preproc_def/preproc_function_def, C++
        // preproc_function_def, Rust macro_definition — t="macro", a disclosed-degraded callable.
        return SymKind::Macro;
    }
    if( tail == "type" )
    {
        return SymKind::Struct; // typedef/alias/enum bucket
    }
    if( tail == "section" )
    {
        return SymKind::Section; // JSON object keys (t="sec"), same kind as markdown headings
    }
    if( tail == "yamlkey" )        // YAML mapping keys — gated (yamlKeyCaptureDropped: depth cut + merge key)
    {
        return SymKind::Section;
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
    // '<' is safe; the C++/TS bare-identifier path has no '<' → no-op (byte-identical). One carve-out:
    // a type-argument list always FOLLOWS an identifier, so a name that STARTS with '<' is not a generic
    // — it is a Swift operator function (`<`, `<=`, `<+>`), which the strip would erase to "".
    if( const std::size_t lt = raw.find( '<' ); lt != std::string_view::npos && lt > 0 )
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

// ---- the DEF-name policy: which captured names get finalSegment's scope split, and which are whole ----
// Every code language wants the split — `ns::f` / `pkg.F` must key on the bare `f` that byName resolves.
// The DATA-CONFIG languages want the opposite, because there a `.` is part of the NAME and not a scope
// separator: a TOML table header IS its dotted spelling, so `[tool.ruff.lint]` must be findable as
// `tool.ruff.lint` rather than as `lint` — a name that collides with every other `lint` in a repo and makes
// `--grep=tool.ruff` miss the very table it names.
//
// JSON belongs here for the SAME reason and was ALREADY wrong before TOML existed: a package.json
// dependency `"lodash.merge"` was indexed as `merge` (measured; the TOML round's sibling sweep is what
// surfaced it). YAML is the third tenant: a `dotted.plain.key:` is one key whose name contains dots.
// Covering all three is the sibling-completeness rule docs/METHODOLOGY.md §3 calls the dominant
// defect class here — fixing the instance and leaving its sibling broken is the failure it names.
//
// Widening a name here cannot widen the CALL GRAPH: the data-config languages emit zero @reference
// captures, and graph.h's langCompatible already keeps each lang-isolated from every code language.
//
// This lives beside finalSegment rather than inside captureTagsFacts on purpose — the caller is a very
// large function already over the complexity bar, and a policy branch buried in it is both invisible and
// a measured regression (--quality-delta scored the inline ternary at +3 ccx).
std::string defNameFromCapture( Lang lang, std::string_view raw )
{
    if( lang == Lang::Json || lang == Lang::Toml || lang == Lang::Yaml )
    {
        return std::string( raw );
    }
    return finalSegment( raw );
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

// §L1 — PARSE HEALTH, measured on the tree the ingest ALREADY built (no second parse, no second read).
//
// What it answers: of the files that ARE in the index, which ones did the parser only partly understand,
// and which ones look machine-written? Before this, a corpus of 252 deliberately-invalid Python files
// reported oversize="0" — "index complete" — while every symbol drawn from it was garbage.
//
// COST. `ts_node_has_error` is a flag on the subtree, so a clean file pays one O(1) test and nothing
// else; the walk below descends only into children that carry the flag, so it is proportional to the
// damage rather than to the file. The whitespace sample is a bounded 4 KB scan of bytes already in cache.
//
// WHY TOP-MOST ERROR SPANS. An ERROR node's subtree is itself full of error-flagged nodes; summing all of
// them would count the same bytes many times and produce a ratio above 1. Descent stops at the outermost
// ERROR, so errBytes is a true byte measure of "what the parser could not interpret". MISSING nodes are
// zero-width by construction (the parser inserted a token that was not there), so they contribute to
// errNodes and nothing to errBytes — which is exactly why BOTH numbers are disclosed, not just a ratio.
FileHealth measureFileHealth( TSNode root, std::string_view bytes )
{
    FileHealth h;
    h.fileBytes = std::uint32_t( bytes.size() > 0xFFFFFFFFull ? 0xFFFFFFFFull : bytes.size() );

    const std::size_t sample = bytes.size() < kHealthWsSampleBytes ? bytes.size() : kHealthWsSampleBytes;
    std::uint32_t     ws     = 0;
    for( std::size_t i = 0; i < sample; ++i )
    {
        const unsigned char c = ( unsigned char ) bytes[ i ];
        if( c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v' )
        {
            ++ws;
        }
    }
    h.wsBytes = ws;

    if( !ts_node_has_error( root ) )
    {
        return h;
    }

    std::vector<TSNode> stack;
    stack.push_back( root );
    while( !stack.empty() )
    {
        const TSNode n = stack.back();
        stack.pop_back();
        if( ts_node_is_error( n ) )
        {
            ++h.errNodes;
            const std::uint32_t lo = ts_node_start_byte( n );
            const std::uint32_t hi = ts_node_end_byte( n );
            h.errBytes += hi > lo ? hi - lo : 0u;
            continue;   // top-most only — see the note above
        }
        if( ts_node_is_missing( n ) )
        {
            ++h.errNodes;
            continue;
        }
        const std::uint32_t kids = ts_node_child_count( n );
        for( std::uint32_t i = 0; i < kids; ++i )
        {
            const TSNode c = ts_node_child( n, i );
            if( ts_node_has_error( c ) || ts_node_is_missing( c ) )
            {
                stack.push_back( c );
            }
        }
    }
    return h;
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

// True when block indentation implies a scanner indent stack anywhere near tree-sitter-yaml's
// serialize() cliff — see kMaxYamlNestDepth in ingest.h for the defect arithmetic. Like jsonNestsTooDeep,
// one deterministic O(n) byte scan BEFORE any parse — never a wall-clock timeout, which would break the
// byte-identical-output contract. It OVER-approximates the scanner's indent stack, and the direction is
// the whole design: an over-count skips a degenerate file with a disclosed stderr note; an under-count
// would hand the parser a file whose state serialization corrupts memory. Three over-approximations:
//   - a stack of open indent COLUMNS, popped when a line dedents to or past them; every content line
//     charges its own column (a wrapped plain-scalar continuation counts like a key line);
//   - each leading `- ` / `? ` / `: ` block marker after the indent opens one more level on its line
//     (`- - - x` builds three scanner levels on one unindented line);
//   - the verdict charges 2 stack slots per open column, because a block mapping and a block sequence
//     can open at the SAME column (`key:` over `- item` at indent 0 is two scanner pushes, one column).
// Lines inside block scalars and multi-line quoted values are indistinguishable without a parse and
// count like any other line — over-approximation again (a block scalar would need 30+ distinct
// increasing indents to trigger). Flow nesting (`{`/`[`) is deliberately NOT counted: the scanner's
// serialize stack grows only on BLOCK begins (verified against every push_ind site in the vendored
// scanner.c), so a deep one-line flow document is bounded by the generic parse path, not this one.
bool yamlNestsTooDeep( std::string_view bytes ) noexcept
{
    constexpr std::uint32_t kColCap = kMaxYamlNestDepth;   // more slots than can survive the 2x verdict below
    std::uint32_t openCols[ kColCap ];
    std::uint32_t openCount = 0;
    std::size_t   i = 0;
    const std::size_t byteCount = bytes.size();
    while( i < byteCount )
    {
        // leading indent (tabs are invalid YAML block indentation; charging them anyway only over-counts)
        std::uint32_t col = 0;
        while( i < byteCount && ( bytes[ i ] == ' ' || bytes[ i ] == '\t' ) ) { ++col; ++i; }
        // block markers: `- ` (sequence entry), `? ` (explicit key), `: ` (explicit value)
        std::uint32_t markerLevels = 0;
        while( i + 1 < byteCount && ( bytes[ i ] == '-' || bytes[ i ] == '?' || bytes[ i ] == ':' )
               && ( bytes[ i + 1 ] == ' ' || bytes[ i + 1 ] == '\t' ) )
        {
            ++markerLevels; i += 2; col += 2;
        }
        const bool blankOrComment = ( i >= byteCount || bytes[ i ] == '\n' || bytes[ i ] == '\r' || bytes[ i ] == '#' );
        if( !blankOrComment || markerLevels > 0 )
        {
            const std::uint32_t base = col - 2u * markerLevels;
            while( openCount > 0 && openCols[ openCount - 1 ] >= base ) { --openCount; }   // dedent pops
            for( std::uint32_t m = 0; m <= markerLevels; ++m )                             // this line's level + one per marker
            {
                if( openCount >= kColCap )
                {
                    return true;                        // proxy-stack overflow IS the too-deep verdict
                }
                openCols[ openCount ] = base + 2u * m;
                ++openCount;
            }
            if( 2u * openCount > kMaxYamlNestDepth )
            {
                return true;
            }
        }
        while( i < byteCount && bytes[ i ] != '\n' ) { ++i; }   // rest of line is content, not structure
        if( i < byteCount ) { ++i; }
    }
    return false;
}

// True when blockquote/list nesting implies an open-blocks stack anywhere near tree-sitter-markdown's
// serialize() cliff — see kMaxMdBlockDepth in ingest.h for the defect arithmetic. Like the json/yaml
// prescans: one deterministic O(n) byte scan BEFORE any parse, over-approximating in the safe
// direction (an over-count skips a degenerate file with a disclosed stderr note; an under-count would
// hand the parser a file whose state serialization corrupts memory). Per line, the estimate is:
//   - one slot per leading '>' blockquote marker (spaces/tabs may interleave: `> > >` is depth 3);
//   - one slot per list marker in the leading run (`-`/`*`/`+` or `N.`/`N)` followed by space —
//     CommonMark nests a NEW list per marker, so `- - - x` opens three blocks on one line);
//   - plus remaining leading indent width / 2 (a nested list level costs ~2 columns, so deep
//     indentation built across earlier lines shows up as this line's indent).
// The scanner's stack does accumulate ACROSS lines, but only by way of markers/indent that some line
// exhibits — the deepest line's estimate bounds the stack the scanner can hold there. Stateless per
// line, so a thematic break (`---`, 3 markers) or ASCII art never comes near 200.
bool mdNestsTooDeep( std::string_view bytes ) noexcept
{
    std::size_t       i         = 0;
    const std::size_t byteCount = bytes.size();
    while( i < byteCount )
    {
        std::uint32_t slots  = 0;
        std::uint32_t indent = 0;
        bool          leading = true;
        while( i < byteCount && bytes[ i ] != '\n' && leading )
        {
            const char c = bytes[ i ];
            if( c == ' ' || c == '\t' )
            {
                ++indent; ++i;
            }
            else if( c == '>' )
            {
                ++slots; ++i;
            }
            else if( ( c == '-' || c == '*' || c == '+' ) && ( i + 1 >= byteCount || bytes[ i + 1 ] == ' ' || bytes[ i + 1 ] == '\t' || bytes[ i + 1 ] == '\n' ) )
            {
                ++slots; ++i;   // the marker only; its following space rides the indent branch (over-counts, safely)
            }
            else if( c >= '0' && c <= '9' )
            {
                std::size_t d = i;
                while( d < byteCount && bytes[ d ] >= '0' && bytes[ d ] <= '9' ) { ++d; }
                if( d < byteCount && ( bytes[ d ] == '.' || bytes[ d ] == ')' ) && ( d + 1 >= byteCount || bytes[ d + 1 ] == ' ' || bytes[ d + 1 ] == '\t' || bytes[ d + 1 ] == '\n' ) )
                {
                    ++slots; i = d + 1;   // digits + the ./) delimiter; the space rides the indent branch
                }
                else
                {
                    leading = false;
                }
            }
            else
            {
                leading = false;
            }
        }
        if( slots + indent / 2u > kMaxMdBlockDepth )
        {
            return true;
        }
        while( i < byteCount && bytes[ i ] != '\n' ) { ++i; }
        if( i < byteCount ) { ++i; }
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
// §P0.5d: the crawl also reports WHICH otherwise-indexable files it dropped for exceeding A SIZE CEILING,
// so the map header can say `skipped_oversize=` (the count) and --skipped can name the rows, instead of
// presenting a truncated corpus as the whole tree.
// §B13.1: "a size ceiling" is TWO ceilings — maxFileBytes (--max-file-size) and the fixed kMaxJsonConfigBytes
// the .json lane applies on top of it — and the list covers both, because a file the reader cannot see is
// equally invisible whichever ceiling dropped it. They are mutually exclusive per file (see the drop sites);
// each row records the ceiling that dropped it as limitBytes.
// §L1: record ONE non-size drop. The count is exact and always incremented; the ROW is collected only
// while the class is under its ceiling, and `file_size()` is only paid for a row that will actually be
// printed — the tally itself must not cost a stat per asset file on a monorepo crawl. Extracted rather
// than written twice inside the crawl loop: two copies added a nesting level and 27 points of complexity
// to collectSources, which is what ripwire's own --quality-delta said about the first draft of this lane.

void recordCrawlDrop( std::vector<SkippedFile>& rows, std::uint64_t& exactCount,
                      const std::string& path, std::string_view ext, const fs::directory_entry& entry )
{
    ++exactCount;
    if( rows.size() >= kMaxSkipRowsPerClass )
    {
        return;
    }
    std::error_code     ec;
    const std::uintmax_t sz = entry.file_size( ec );
    rows.push_back( { path, ec ? 0ull : std::uint64_t( sz ), std::string( ext ) } );
}

// §L1: the crawl's two NON-SIZE drop tests, together, because they are one decision with one ordering
// contract — is this file a crawl candidate at all, and if not, is its absence something the reader needs
// told about? Returns true when the caller must skip the file (the drop, if reportable, is already
// recorded).
//
// ORDER IS THE CONTRACT. The EXTENSION is classified first and the --exclude match second, so `excluded`
// only ever describes a file that would OTHERWISE have been indexed (an --exclude'd .png is not a
// disclosure, it is a picture the user asked not to see) and `unsupported-ext` only ever describes a file
// the user did NOT ask to hide (an --exclude'd .ml is requested absence, not a language this build cannot
// read). Swap the two and both classes start lying.
//
// `fullPath` is the caller's LAZY path materializer, taken as a template parameter rather than a
// std::string: a monorepo crawl walks far more non-source files than source ones, and stringifying every
// one of them to record the handful that are reportable would be a real per-file cost for nothing.
template< typename PathFn >
bool recordPreSizeDrop( CrawlSkips& skips, HashMap<std::string, std::uint64_t>& extTally,
                        const std::string& ext, bool excluded, const fs::directory_entry& entry, PathFn&& fullPath )
{
    if( lookupLang( ext ) == nullptr && !docparse::isDocExtension( ext ) )
    {
        if( !excluded && !isNonTextExtension( ext ) )
        {
            ++extTally[ ext ];
            recordCrawlDrop( skips.unsupported, skips.unsupportedFiles, fullPath(), ext, entry );
        }
        return true;
    }
    if( excluded )
    {
        recordCrawlDrop( skips.excluded, skips.excludedFiles, fullPath(), ext, entry );
        return true;
    }
    return false;
}

// §L1: establish the ordering contract on everything the crawl collected out of order. The row vectors
// sort by path; the extension histogram comes out of a HashMap, whose iteration order is an implementation
// detail, so it sorts by count DESC then extension ASC. That last one matters more than usual: it rides
// the DEFAULT map header, where an order that depended on hash iteration would be a determinism bug.
void finalizeCrawlSkips( CrawlSkips& skips, const HashMap<std::string, std::uint64_t>& extTally )
{
    const auto byPath = []( const SkippedFile& a, const SkippedFile& b ) noexcept { return a.path < b.path; };
    std::sort( skips.excluded.begin(), skips.excluded.end(), byPath );
    std::sort( skips.unsupported.begin(), skips.unsupported.end(), byPath );
    skips.unindexedExts.reserve( extTally.size() );
    for( const auto& [ ext, count ] : extTally )
    {
        skips.unindexedExts.push_back( { ext, count } );
    }
    std::sort( skips.unindexedExts.begin(), skips.unindexedExts.end(), lessUnindexedExt );
}

// §L1: the same walk now also reports the OTHER two ways a file leaves the corpus — an --exclude hit and
// an extension with no grammar — plus the unindexed-extension histogram the map header rolls up. Nothing
// new is dropped here: every one of those files was already absent, it was merely absent ANONYMOUSLY, so
// `--skipped` could answer "oversize=0" on a tree it had passed over wholesale. See model.h::CrawlSkips.
struct CrawlResult
{
    std::vector<std::string>     paths;
    std::vector<SkippedOversize> skipped;
    CrawlSkips                   skips;
};

CrawlResult collectSources( const char* rootDir, const std::vector<std::string>& excludeSubstr,
                            std::size_t maxFileBytes, std::string_view excludeLabel = {} )
{
    std::vector<std::string>     out;
    std::vector<SkippedOversize> skipped;
    CrawlSkips                   skips;
    HashMap<std::string, std::uint64_t> extTally;   // unindexed source/text-looking ext -> file count

    std::error_code ec;
    fs::path root = fs::path( rootDir );

    auto opts = fs::directory_options::skip_permission_denied;
    fs::recursive_directory_iterator it( root, opts, ec );
    if( ec )
    {
        DEGRADED_PATH_ALERT( "ingest: cannot open root directory — empty result" );
        return { std::move( out ), std::move( skipped ), std::move( skips ) };
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
                if( excluded )
                {
                    ++skips.excludedDirs;   // §L1: contents UNKNOWN past here — see CrawlSkips::excludedDirs
                }
            }
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
        //
        // §L1: the two NON-SIZE drops are classified and recorded together (recordPreSizeDrop) — see its
        // header for why the two tests must run in that order, and why they are not written inline here.
        const std::string ext = lowerExtensionOf( name );
        if( recordPreSizeDrop( skips, extTally, ext, excluded, *it, fullPath ) )
        {
            continue;
        }

        const std::uintmax_t sz = it->file_size( ec );
        if( ec || sz > maxFileBytes )
        {
            if( !ec && sz > maxFileBytes )
            {
                // §P0.5d: a size drop is reportable, not invisible — path + size + the ceiling that dropped it
                skipped.push_back( { fullPath(), std::uint64_t( sz ), std::uint64_t( maxFileBytes ) } );
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
        // both ceilings is counted once, there — which is why one list serves both and no file is counted
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
            skipped.push_back( { fullPath(), std::uint64_t( sz ), std::uint64_t( kMaxJsonConfigBytes ) } );
            continue;
        }

        // YAML-lane ceiling (see kMaxYamlConfigBytes): the same hazard class as .json — a machine-written
        // DATA population behind a config extension — at YAML's own measured calibration: 512 KB, because
        // JSON's 256 KB would drop real hand-maintained config (NeMo's 293 KB cicd-main.yml). Counted in
        // skipped_oversize exactly like its two siblings above, for the same accounting invariant.
        if( sz > kMaxYamlConfigBytes && ( ext == ".yml" || ext == ".yaml" ) )
        {
            skipped.push_back( { fullPath(), std::uint64_t( sz ), std::uint64_t( kMaxYamlConfigBytes ) } );
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
    // Same discipline for the drop list: collection order is the filesystem's, so sort before it can
    // reach output (--skipped rows are emitted in this order).
    std::sort( skipped.begin(), skipped.end(),
               []( const SkippedOversize& a, const SkippedOversize& b ) noexcept { return a.path < b.path; } );
    finalizeCrawlSkips( skips, extTally );   // §L1: the two new row classes + the extension histogram
    return { std::move( out ), std::move( skipped ), std::move( skips ) };
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
    std::uint16_t ppAlt     = 0;   // preproc alternative branches (#else/#elif) inside the def (see model.h Symbol::ppAlt)
    std::uint16_t humps     = 0;   // nesting profile: regions reaching quality::kNestBar (see model.h Symbol::humps)
    std::uint16_t deepLoc   = 0;   // nesting profile: lines inside them, a FLOOR (see model.h Symbol::deepLoc)
    std::uint16_t ev        = 0;   // essential complexity, a FLOOR (see model.h Symbol::ev); 0 outside evCountedLang
    std::array<std::uint8_t, kEvWhyTagCount> evWhy{};   // per-tag contributing-jump counts (model.h kEvWhyTagTable)
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
    LocalBindKind kind      = LocalBindKind::Type;   // Type = Rule 2 var→type; FnDecl/FnAssign = L3 var→function
    std::uint32_t spanStart = 0;   // kind==VarDecl only: the declaring BLOCK's byte span (shadow scope);
    std::uint32_t spanEnd   = 0;   //   {0,0} on every other kind — see model.h Binding
    std::string   var;             // the declared variable identifier (`x`)
    std::string   typeName;        // kind==Type: the written type's final segment (`Foo`);
                                   // kind==FnDecl/FnAssign: the bound function name (or an L3 sentinel)
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
constexpr std::uint32_t kCacheVersion = 13;           // 13 (§L1 parse health): each FILE record gains the
                                                      //    four FileHealth u32s (errNodes, errBytes, fileBytes,
                                                      //    wsBytes) right after the stat-gate pair. The auto-cache
                                                      //    is the DEFAULT path, so a health measurement that did
                                                      //    not round-trip it would evaporate on the second run and
                                                      //    report "nothing degraded" on a corpus it had never
                                                      //    re-read — the exact zero-means-none-exists defect the
                                                      //    lane exists to kill. A v12 blob has no such bytes, so
                                                      //    the version guard rejects it (self-healing full reparse
                                                      //    repopulates health).
                                                      // 12 (B6.3): FILE records gain two new record arrays —
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
constexpr std::uint32_t kParserVer    = 63;           // bump on any grammar/.scm/extraction change
                                                      // 63 (2026-08-12 markdown section tier, test/mdsectioncheck.sh):
                                                      //    .md/.markdown now parse with the vendored tree-sitter-markdown
                                                      //    block grammar — headings (ATX + setext) become sections with
                                                      //    REAL SPANS (heading → next same-or-higher heading), parent-
                                                      //    heading scopes, and link/mention edges; html-block phantom
                                                      //    headings vanish; .markdown joins the table. The extracted SET
                                                      //    and the spans both change on any md-bearing tree, so v62
                                                      //    blobs must be rejected.
                                                      // 62 (2026-08-12 module-constant round, test/moduleconstcheck.sh):
                                                      //    C/C++ const-qualified module constants index CASE-BLIND —
                                                      //    a const/constexpr/constinit type_qualifier on an INITIALIZED
                                                      //    module-scope declaration keeps the binding regardless of
                                                      //    name case (declarationCarriesConstQualifier; previously the
                                                      //    r3 q10 SCREAMING-only gate dropped every k-camel constant,
                                                      //    which made this repo's own kParserVer unfindable by its own
                                                      //    --for/--uses — the 2026-08-12 census's 21.4% constant-shaped
                                                      //    lookup family). queries/cpp/tags.scm also gains the
                                                      //    class-static field_declaration capture (static + const
                                                      //    qualifier + in-class initializer, fieldConstantCaptureKept —
                                                      //    NO class-static constant was indexed before, even SCREAMING).
                                                      //    The extracted SET grows on any C/C++-bearing tree (this repo:
                                                      //    src/ +~350 rows), so v61 blobs miss rows -> reject.
                                                      //    Deferred with probe evidence (2026-08-12): enumerators
                                                      //    (corpus blow-up: >=5000 capture-cap hits on a 2 377-file private ObjC++/C++ validation tree),
                                                      //    TS/JS non-SCREAMING top-level consts (r3 q10 pinned policy,
                                                      //    constcheck arm 3), variable templates, `T* const` pointer
                                                      //    constants, out-of-line static-member definitions.
                                                      // 61 (2026-08-11 YAML config-key tier): .yml/.yaml indexed for
                                                      //    the first time — mapping keys at mdepth<=2 (sequences
                                                      //    transparent) become t="sec" symbols via queries/yaml/
                                                      //    tags.scm + the definition.yamlkey gate. A v60 blob on a
                                                      //    YAML-bearing tree is missing every such row -> reject.
                                                      //    Known, disclosed cost: one cold re-parse everywhere.
                                                      // 60 (2026-08-10 language-port round): one shared bump covering
                                                      //    THREE hand-ported language rounds, each stranded on a branch
                                                      //    this tree never had. Listed separately because each changes
                                                      //    the extracted SET on a different corpus.
                                                      //    (a) PYTHON shapes: annotated class attributes, gated
                                                      //        enum-family members, class lambda attrs, one-guard-deep
                                                      //        + tuple-unpack module bindings, and .pyi routing.
                                                      //        RE-MEASURED at v59 on django@c334c1a8ff /
                                                      //        pydantic@8898b8f: every one of those shapes read 0.0%
                                                      //        EXCLUSIVE recall. A v59 blob on a Python-bearing tree
                                                      //        is missing those rows -> reject.
                                                      //    (b) SWIFT shapes (hand port of stranded bb78f97, which
                                                      //        originally landed at kParserVer 41): enum_entry /
                                                      //        typealias_declaration / associatedtype_declaration /
                                                      //        protocol_property_declaration / the builtin-operator-
                                                      //        token alternation in function_declaration's name:
                                                      //        field. RE-MEASURED at v59/v60 on Alamofire@0455bfb +
                                                      //        swift-nio@72973283, the 2026-08-04 corpora pinned to
                                                      //        the same SHAs.
                                                      //    (c) TYPESCRIPT #private: tags.scm gains the #private
                                                      //        method / field-arrow / call-ref coverage JS already
                                                      //        had -- a sibling-completeness gap, not a new shape.
                                                      //    Shared finalSegment() gains the leading-'<' carve-out (a
                                                      //    Swift operator name like `<` or `<+>` is not a generic
                                                      //    type-argument list, which the unconditional strip erased
                                                      //    to ""). That touches the shared C++/TS/JS/Python path, so
                                                      //    it changes the extracted SET only for a name legitimately
                                                      //    starting with '<'; every other language's bare-identifier
                                                      //    path is unaffected (tsshapecheck / jsshapecheck /
                                                      //    pyshapecheck / constcheck / langcheck stay green).
                                                      //    The vendored scanner.c UBSan fix that rode the same source
                                                      //    commit was deliberately NOT ported -- see the header of
                                                      //    test/swiftshapecheck.sh for the reason and its trigger.
                                                      //    (d) CUDA memory-space module bindings (cudacheck 7b
                                                      //        close-out): queries/cpp/tags.scm gained the
                                                      //        UNINITIALIZED qualified-declaration patterns and
                                                      //        ingest gained cudaMemorySpaceQualifierOf
                                                      //        (`__constant__` case-blind, `__device__`/
                                                      //        `__managed__` behind the SCREAMING gate). Keyed on
                                                      //        Lang::Cpp, NOT on constCaptureNeedsScreamingGate --
                                                      //        that gate also covers TS/JS/Ruby/Java/C#/C, whose
                                                      //        constants bind through non-C-family nodes and would
                                                      //        read as uninitialized and be dropped wholesale.
                                                      //        Verified zero removed rows over ~250K symbol rows /
                                                      //        ~2 200 C/C++ files; MONAI's 80 adds are an exact
                                                      //        multiset match to its 80 __constant__ source lines.
                                                      //    ONE bump for all four is deliberate: they land together,
                                                      //    so no released version ever keyed a cache on one without
                                                      //    the others. Record shape unchanged, kCacheVersion stays.
                                                      // 59 (TOML config-key tier): +TOML (.toml) — a NEW
                                                      //    grammar and a new .scm, so the extracted SET
                                                      //    changes on any tree holding a .toml. Table
                                                      //    headers and their keys become t="sec" defs; no
                                                      //    references, so edges are unchanged. Key depth is
                                                      //    HEADER-relative, not root-relative — JSON's
                                                      //    "top-level + 2nd-level" cut ported literally
                                                      //    would capture 38.3% of keys and miss every key
                                                      //    under a 2-dotted table. Known, disclosed cost:
                                                      //    one cold re-parse everywhere.
                                                      // 58 (r9 A5 iteration 6): the L3 DECLARATION arm gets
                                                      //    the matching value-INITIALIZATION noise gate — a
                                                      //    bare-identifier initializer mints a fn-pointer
                                                      //    binding only when the declarator spells one, the
                                                      //    written type is a same-file fn-pointer alias, or
                                                      //    the type is UNKNOWN (`auto`, template, decltype).
                                                      //    A CLASS type used to sail through the primitive-
                                                      //    only gate, so `std::string tag = zzz;` minted a
                                                      //    binding that vetoed shadow suppression for the
                                                      //    local's whole scope.
                                                      // 57 (r9 A5 iteration 5): the L3 assignment arm gets
                                                      //    the value-assignment NOISE GATE — a bare-
                                                      //    identifier `x = y;` mints a fn-pointer binding
                                                      //    only when the file's own declarations do not
                                                      //    prove x a value variable (`std::string line;
                                                      //    line = zzz;` no longer vetoes shadow
                                                      //    suppression, nor tombstones a same-named
                                                      //    file-scope binding corpus-wide).
                                                      // 56: three declarator shapes isNonValueContext
                                                      //    could not see stop leaking their DECLARED name
                                                      //    out as a read of the symbol they shadow — a
                                                      //    DEFAULTED parameter (`int key = 0`, parent
                                                      //    optional_parameter_declaration), a pack
                                                      //    (`Ts... key`) and an attributed declarator
                                                      //    (`int key [[maybe_unused]]`).
                                                      // 55 (r9 A5 iteration 4): an ordinary BLOCK
                                                      //    declaration's shadow span starts at its
                                                      //    DECLARATION POINT (end of the complete
                                                      //    declarator, [basic.scope.pdecl]) instead of the
                                                      //    block's brace, so a genuine call written above
                                                      //    the local survives; whole-scope shapes keep
                                                      //    their spans, and isDeclSiteName gains the
                                                      //    `declaration` arm the narrowed span un-masks.
                                                      //    Span VALUES + reference population change →
                                                      //    old caches must be rejected; mirror bumped in
                                                      //    the SAME commit.
                                                      // 54 (r9 A5 iteration 3): shadow spans stop at the
                                                      //    owning CONTROL STATEMENT — a for/if/while/switch
                                                      //    header declaration scopes to that statement's
                                                      //    span, no longer leaking past the loop; range-for
                                                      //    unified to the whole-statement span; catch
                                                      //    parameters captured (handler-block span). Span
                                                      //    VALUES land in cached bind records → extraction
                                                      //    output changes → old caches must be rejected.
                                                      //    quality.h's mirror bumped in the SAME commit.
                                                      // 53 (r9 A5 fix round): shadow suppression tightened
                                                      //    to BLOCK spans (RawBind gains spanStart/spanEnd —
                                                      //    a bind-record FORMAT change, rejected via this
                                                      //    bump) and the capture now sees reference
                                                      //    declarators, structured bindings, lambda params
                                                      //    and capture-list names. quality.h's mirror
                                                      //    bumped in the SAME commit.
                                                      // 52 (r9 loss bucket 2): local-shadow suppression —
                                                      //    captureBindings gains kind=VarDecl records (every
                                                      //    declared C++/ObjC variable NAME incl. primitives,
                                                      //    definition parameters, range-for vars) — a NEW
                                                      //    bind kind on the per-file record → old caches
                                                      //    lack the rows and must be rejected. quality.h's
                                                      //    kIngestParserVerMirror bumped in the SAME commit.
                                                      // 51 (r9 loss bucket 1): C++ `using ns::name;`
                                                      //    re-export sites now mint a role="import" RawRef
                                                      //    (new tags.scm @reference.import pattern +
                                                      //    usingDeclarationIsDirective guard) — a NEW ref
                                                      //    kind on the per-file record → old caches lack
                                                      //    the rows and must be rejected. quality.h's
                                                      //    kIngestParserVerMirror bumped in the SAME commit.
                                                      // 48 (macro-edges): function-like #define → t="macro"
                                                      //    symbols (C++ gains the capture; C/Rust re-kind
                                                      //    Function→Macro), replacement-text call scan, and
                                                      //    the role="macro" invocation retag.
                                                      // 47 (L3, 2026-08-08 audit): `locals` now counts
                                                      //    DECLARATORS, not declaration statements —
                                                      //    cc_countLocalDeclarators sums every
                                                      //    `declarator`-fielded child of a countable
                                                      //    `declaration` node instead of the fused DFS
                                                      //    incrementing by one per statement. A
                                                      //    comma-separated local (`int a,b,c;`) moves from
                                                      //    locals=1 to locals=3, and a type-only local
                                                      //    declaration (no declarator at all) moves from 1
                                                      //    to 0 — a VALUE change on the per-file RawDef
                                                      //    record's existing `locals` u32 (no format
                                                      //    change) → old caches carry the undercounted
                                                      //    number and must be rejected. quality.h's
                                                      //    kIngestParserVerMirror bumped in the SAME
                                                      //    commit (P0.2).
                                                      // 46: integration/quality-fleet merge of TWO independent 45s
                                                      //    — the integrated ppalt+nestcal 45 (below) and ev(G),
                                                      //    which took 45 on feat/nest-profile (entry next; it had
                                                      //    skipped 44 to dodge exactly this trap, but the
                                                      //    integration line had already spent 45). The merged
                                                      //    extraction (ppalt + nestcal clause semantics + ev/evWhy
                                                      //    + Swift guard decision counting) matches neither
                                                      //    lineage, so neither's blobs may be served. Mirror moved
                                                      //    in the same commit; qschemetrip re-pinned.
                                                      // 45 (feat/nest-profile numbering): essential complexity (the essential-complexity design note).
                                                      //    45 and not 44: the nesting-quirk round on a sibling
                                                      //    branch independently took 44 for the else-clause hump
                                                      //    rewrite; two independent 44s would cross-hit caches at
                                                      //    merge (that trap already fired once between two 43s).
                                                      //    RawDef/Symbol gain `ev` (u16 FLOOR) + `evWhy` (8×u8 tag
                                                      //    counters), computed inside the fused cc_walk DFS — a
                                                      //    FORMAT change to the per-file def record (u32 + 8×u8
                                                      //    after deepLoc) → old caches must be rejected. ALSO a
                                                      //    VALUE change: Swift `guard_statement` joins
                                                      //    isDecisionType (it is a decision point every cyclomatic
                                                      //    tool counts; required so ev's counting of the
                                                      //    guard-else exit keeps ev <= cx structural), so Swift
                                                      //    cx moves on guard-bearing defs. quality.h's
                                                      //    kIngestParserVerMirror bumped in the SAME commit (P0.2).
                                                      // 43 (feat/nest-profile numbering): deepLoc line accounting fixed in cc_walk's else/elif
                                                      //    clause — the hump PROFILE pass now runs forward
                                                      //    (document order) instead of inside the backwards PUSH
                                                      //    loop, so the `else` token's own line is no longer
                                                      //    clamped away behind its block's high-water end. deep=
                                                      //    VALUES move on else-at-the-bar shapes, so caches
                                                      //    written by 42 hold numbers this build would not
                                                      //    produce and must be rejected.
                                                      // 45: integration/quality-fleet merge of the ppalt line
                                                      //    (43 below) and the nestcal r1 line (44 below) — the
                                                      //    merged extraction (ppalt disclosure + r1 else/elif
                                                      //    clause semantics) matches neither lineage, so the
                                                      //    merge takes a fresh number and both sides' blobs are
                                                      //    rejected. Mirror moved in the same commit.
                                                      // 44: the merge of TWO independent 43s, so neither 43's
                                                      //    caches may be served. One 43 was nestcal r1 (else/elif
                                                      //    clause bodies no longer double-deepen — no per-child
                                                      //    maxNest bump or hump minting; nest/humps/deep/ccx
                                                      //    values shift). The other 43 fixed deepLoc's clamp
                                                      //    order for else-clause regions (cc_noteElseRegions,
                                                      //    forward pass); r1's removal of clause noting subsumes
                                                      //    it — every surviving cc_noteHump site notes one node
                                                      //    pre-descent, so document order holds by construction.
                                                      // 43: ppalt disclosure — RawDef/Symbol gained a `ppAlt` u16
                                                      //    counting the ALTERNATIVE-introducing preprocessor nodes
                                                      //    (preproc_else/preproc_elif/preproc_elifdef) inside the
                                                      //    def, filled by the same fused cc_walk DFS: structural
                                                      //    metrics sum branches that never coexist at compile time
                                                      //    (bullet's btMatrix3x3.h::getRotation, ~2x vs any one
                                                      //    build), and the row now DISCLOSES it instead of anyone
                                                      //    guessing a branch. A FORMAT change (new u32 between
                                                      //    locals and params in the def record) → reject old blobs.
                                                      //    quality.h kIngestParserVerMirror bumped in the SAME
                                                      //    commit (P0.2). (Was 42 on its own branch; renumbered 43
                                                      //    at integration — it collided with the independent 42
                                                      //    below.)
                                                      // 42: nested-closure span attribution — the body-climb in
                                                      //    the tags pass no longer adopts an ancestor whose body
                                                      //    CONTAINS the def (JS/TS named const-closures nested in
                                                      //    a function stole the encloser's whole span, so their
                                                      //    cached startByte/endByte/loc/cx/params are wrong) →
                                                      //    old blobs carry the bad spans and must be rejected.
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
struct FileFacts { std::uint64_t hash = 0; long long sizeBytes = -1; long long mtimeNs = -1; FileHealth health; std::vector<RawDef> defs; std::vector<RawRef> refs; std::vector<Include> incs; std::vector<RawBind> binds; std::vector<BindingAlias> ffis; std::vector<RouteDef> routeDefs; std::vector<RawRouteUse> routeUses; };

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
    w.u32( d.line ); w.u32( d.startByte ); w.u32( d.endByte ); w.u32( d.nameByte ); w.u32( d.bodyByte ); w.u32( d.cx ); w.u32( d.ccx ); w.u32( d.loc ); w.u32( d.locals ); w.u32( d.ppAlt ); w.u32( d.humps ); w.u32( d.deepLoc ); w.u32( d.ev ); w.u32( d.params ); w.u8( d.maxNest ); w.u8( d.arityExact ); w.u8( std::uint8_t( d.kind ) ); w.u8( std::uint8_t( d.lang ) ); w.str( d.name ); w.str( d.scope );
    for( const std::uint8_t tagCount : d.evWhy ) { w.u8( tagCount ); }   // 8×u8, fixed order (model.h kEvWhyTagTable)
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
// they sit next to the writer functions whose field list they must match. A LEAN def record is 14 u32 +
// 12 u8 + 2 empty str(len u32) fields = 14*4 + 12*1 + 2*4 = 76 bytes (Phase 1, local-variable-indexing,
// PLAN.md 2026-08-06 evening: `locals` u32 joined the run — 9 -> 10; the ppalt disclosure added `ppAlt`,
// written as a u32 — 10 -> 11; the nesting profile then added `humps` and `deepLoc`, written as u32 each —
// 11 -> 13; essential complexity then added `ev` as a u32 in the run plus the 8×u8 evWhy tag counters
// after the strings — 13 -> 14 u32 and 4 -> 12 u8, so 56 + 12 + 8 = 76); the RICH (withLex) extra is
// dlWeighted u32 + tokenCount u32 + tfWidth u8 = 9 bytes. A ref record is 3 u32 + 7 u8 + 5 empty
// str(len u32) fields = 3*4 + 7*1 + 5*4 = 39 bytes. verifyCacheRecordMinimaTripwire() below derives these
// same numbers from the REAL writer functions at runtime so the next field added to writeDef/writeRef
// can't silently stale them.
inline constexpr std::size_t kMinDefRecordBytesLean      = 76;   // 14×u32 + 12×u8 + 2×str(len u32, empty)
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
    RawDef d; d.line = r.u32(); d.startByte = r.u32(); d.endByte = r.u32(); d.nameByte = r.u32(); d.bodyByte = r.u32(); d.cx = r.u32(); d.ccx = r.u32(); d.loc = r.u32(); d.locals = r.u32(); d.ppAlt = std::uint16_t( r.u32() ); d.humps = std::uint16_t( r.u32() ); d.deepLoc = std::uint16_t( r.u32() ); d.ev = std::uint16_t( r.u32() ); d.params = std::uint16_t( r.u32() ); d.maxNest = r.u8(); d.arityExact = r.u8(); d.kind = SymKind( r.u8() ); d.lang = Lang( r.u8() ); d.name = r.str(); d.scope = r.str();
    for( std::uint8_t& tagCount : d.evWhy ) { tagCount = r.u8(); }   // mirrors writeDef's fixed 8×u8 order
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
inline void   writeBind( ByteW& w, const RawBind& b ) { w.u32( b.startByte ); w.u8( std::uint8_t( b.lang ) ); w.u8( std::uint8_t( b.kind ) ); w.u32( b.spanStart ); w.u32( b.spanEnd ); w.str( b.var ); w.str( b.typeName ); }
inline RawBind readBind( ByteR& r ) { RawBind b; b.startByte = r.u32(); b.lang = Lang( r.u8() ); b.kind = LocalBindKind( r.u8() ); b.spanStart = r.u32(); b.spanEnd = r.u32(); b.var = r.str(); b.typeName = r.str(); return b; }
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
    const std::size_t kMinFileRecordBytes = 68 + ( captureValueUses ? 4 : 0 );   // path str + hash + sizeBytes + mtimeNs + FileHealth + six record counts, all empty (v6: +2×u64; v10 rich: + dict count u32; v12/B6.3: +2×u32 route counts; v13/§L1: +4×u32 health)
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
            ff.health.errNodes  = r.u32();       // §L1 parse health (v13) — fileBytes==0 keeps its
            ff.health.errBytes  = r.u32();       //   NOT-MEASURED meaning across the round trip
            ff.health.fileBytes = r.u32();
            ff.health.wsBytes   = r.u32();
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
                       const std::vector<FileHealth>& fileHealth,   // §L1 (v13): parse health, per fileId
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
    // The cache-write side's per-file record indexes. Split by MEASURED shape, not by symmetry:
    //   dIdx  — one entry per DEFINITION; same distribution as model.h's SymbolsByFile (mean 8.4/18.2 per
    //           file, p90 18/37), so it takes that index's measured N=8 knee.
    //   iIdx/aIdx/rdIdx/ruIdx — includes, FFI aliases and the two route tables. N=2 is FREE (rw::svector's
    //           inline array shares storage with the heap pointer, so <uint32,1> and <uint32,2> are both
    //           16 B — a THIRD smaller than the std::vector header it replaces) and covers 85.4%/59.1%,
    //           99.7%/100%, 99.9%/100% and 99.9%/100% of files across the two census corpora.
    //   rIdx/bIdx — deliberately LEFT as std::vector. Means of 155/248 and 28/59 references and bindings per
    //           file with 17%/40% of files empty and no early knee: an N that covered them would have to be
    //           in the hundreds. They are CSR candidates, a separate wave, not small-vector material.
    std::vector<rw::SmallVec<std::uint32_t, 8>> dIdx( F );
    std::vector<std::vector<std::uint32_t>>     rIdx( F ), bIdx( F );
    std::vector<rw::SmallVec<std::uint32_t, 2>> iIdx( F ), aIdx( F ), rdIdx( F ), ruIdx( F );
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
            {
                // §L1 (v13): parse health, at a FIXED wire offset right after the stat-gate pair. An
                // out-of-range f writes the default (fileBytes 0), which the reader already means as
                // NOT MEASURED — no sentinel of its own, and no way to mistake it for "clean".
                const FileHealth fh = f < fileHealth.size() ? fileHealth[f] : FileHealth{};
                w.u32( fh.errNodes );  w.u32( fh.errBytes );  w.u32( fh.fileBytes );  w.u32( fh.wsBytes );
            }
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
           || std::strcmp( t, "switch_expression_arm" ) == 0
           // Swift `guard cond else { exit }` — a decision point every cyclomatic tool counts, previously
           // missed (kParserVer 44). Also load-bearing for essential complexity: ev's per-construct weights
           // mirror this predicate exactly (ev_ctrl machinery below), so counting the guard-else exit in ev
           // without counting the guard here would break the structural ev <= cx containment.
           || std::strcmp( t, "guard_statement" ) == 0;
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

// shared by cc_countLocalDeclarators (below) and ln_declaratorIdentifiers (Phase 2, further down): is child
// `ci` of `declNode` one comma-separated declarator SLOT? The vendored grammar gives every comma-separated
// declarator its own `declarator`-FIELDED direct child of the `declaration` node (`int a=1,b=2;` has TWO) —
// pulled out to ONE predicate so the two counting/walking loops that need it never drift on the field name.
inline bool cc_isDeclaratorField( TSNode declNode, std::uint32_t ci ) noexcept
{
    const char* fieldName = ts_node_field_name_for_child( declNode, ci );
    return fieldName != nullptr && std::strcmp( fieldName, "declarator" ) == 0;
}

// L3 fix (2026-08-08 audit): a `declaration` node already proven countable by cc_isCountableLocalDecl can
// still introduce MORE THAN ONE local — `int a=1,b=2,…,j=10;` is ONE `declaration` node holding TEN
// comma-separated declarators, and counting the STATEMENT ("1") instead of each DECLARATOR undercounts on
// exactly the axis cc_isCountableLocalDecl's own structured-binding exclusion exists to avoid (a `locals=`
// that doesn't mean "how many names were declared"). Counts cc_isDeclaratorField direct children — no
// recursion: a declarator's own nested pointer/reference/array wrapper is still one name, one
// comma-separated slot, one `declarator` field. A declaration with ZERO declarator-fielded children (a
// type-only statement, e.g. a local `struct Foo;` forward declaration) now correctly counts as zero rather
// than the previous "1" — a declaration that names no local was never meant to be a local, and the old
// per-statement count silently over-counted that shape too.
inline std::uint32_t cc_countLocalDeclarators( TSNode n ) noexcept
{
    std::uint32_t count = 0;
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t ci = 0; ci < childCount; ++ci )
    {
        if( cc_isDeclaratorField( n, ci ) )
        {
            ++count;
        }
    }
    return count;
}

// Every accumulator the fused walk fills, in ONE bundle. It used to be six by-reference out-parameters
// threaded through cc_walk's signature; the ppalt disclosure and the nesting-depth profile together
// would have made that ten, which is the
// parameter-count smell --metrics itself reports. One struct, passed by reference, is the same code with a
// name — and the walk's own hot loop touches it exactly as before.
struct CcAccum
{
    std::uint32_t cog     = 0;   // cognitive complexity (nesting-weighted)
    std::uint32_t cyclo   = 0;   // cyclomatic decision count (cx = 1 + this)
    std::uint32_t maxNest = 0;   // deepest control nesting reached  → Symbol::maxNest
    std::uint32_t locals  = 0;   // Phase 1 local-declaration floor  → Symbol::locals
    std::uint32_t ppAlt   = 0;   // preproc alternative branches      → Symbol::ppAlt   (see model.h)
    std::uint32_t humps   = 0;   // regions reaching quality::kNestBar → Symbol::humps   (see model.h)
    std::uint32_t deepLoc = 0;   // lines inside those regions        → Symbol::deepLoc  (a FLOOR)
    std::uint32_t deepEnd = 0;   // 1-based end row of the last counted hump — the anti-double-count clamp
};


// An ALTERNATIVE-introducing preprocessor node: `#else` / `#elif` / `#elifdef` inside the def mean the
// body carries code that never coexists at compile time, so every summed structural metric (cx/ccx/nest/
// loc/locals) over-counts vs any single build (bullet's btMatrix3x3.h::getRotation: both arms of a
// BT_USE_SSE guard, ~2x). ripwire never guesses which arm a build takes — it COUNTS the alternatives and
// the row discloses them (ppalt=, serialize.h). A bare `#if…#endif` with no `#else` introduces no
// mutually-exclusive alternative and deliberately does not count. Prefix match so grammar-internal
// variants (the `_in_field_declaration_list` family) ride along; both prefixes are 12 bytes. C, C++ and
// C# spell these node types identically (verified by real parses — test/ppaltcheck.sh's own fixtures);
// ObjC/CUDA/Metal share the C/C++ preproc node family (kPreprocConditionalNodes below). Grammars without
// a preprocessor simply never match — no per-language gate needed.
inline bool cc_isPreprocAlternative( const char* t ) noexcept
{
    return std::strncmp( t, "preproc_else", 12 ) == 0 || std::strncmp( t, "preproc_elif", 12 ) == 0;
}


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

// ═══ essential complexity ev(G) — the syntactic single-exit reduction (the essential-complexity design note) ═══
//
// THE RULE (§2.2, reference-verified — see test/essentialcxcheck.sh's reconciliation header): a jump marks
// irreducible every control construct STRICTLY BETWEEN it and its target construct; irreducibility then
// propagates OUTWARD to the function root (stopping at closure/nested-fn boundaries); a marked switch head
// contributes every arm. ev = 1 + Σ (own cx decision weight of every marked construct). Weights are
// EXACTLY `isNamed && isDecisionType(t)` — one weight-1 arena node per cyclo-counted decision node and
// never more — which is what makes ev <= cx structural rather than hoped for (boolean operators add to
// cyclo but never enter the arena, widening the gap only in the safe direction).
//
// THE FLOOR RULE (§6, load-bearing): an unrecognised jump node type, or an unresolvable target, marks
// NOTHING. Never mark speculatively. Every failure mode — a noreturn call, a macro-hidden return, a label
// this scan cannot find, a grammar shape not in the tables below — therefore lands in the UNDER-counting
// direction, so emitted ev <= true ev(G) always, which is what lets serialize.h stamp ev_floor="1".
//
// DATA STRUCTURE (§2.3, G2): a parent-index arena, not a CFG — POD nodes, 32-bit handles, no edges, no
// graph library. Pre-order guarantees parent index < child index, which the propagation pass exploits.
enum class CtrlKind : std::uint8_t { Loop, Switch, Case, Branch, Try, Catch, Fn, Block, Labelled };
struct CtrlNode
{
    std::uint32_t parent;   // arena index of the innermost enclosing construct; kNoCtrl at function root
    std::uint16_t weight;   // this construct's OWN cx decision weight (isDecisionType), see above
    std::uint8_t  kind;     // CtrlKind
    std::uint8_t  marked;   // 0/1 — in the irreducible residue
};
static_assert( sizeof( CtrlNode ) == 8, "CtrlNode is the ev arena's hot element — keep it POD and tight" );
inline constexpr std::uint32_t kNoCtrl = 0xFFFFFFFFu;

// EvWhyTag indices MUST track model.h's kEvWhyTagTable declaration order — the table is the single
// source of the public spellings; these are the write-side indices.
enum class EvWhyTag : std::uint8_t { GuardReturn = 0, LoopEscape, SwitchEscape, Goto, LabelledJump, BackEdge, Fallthrough, MultiEntry };

// Everything the walk accumulates for one def's ev. Vectors are constructed per complexityOf call and
// reserve small — the same per-def allocation posture as cc_walk's own frame stack/kids (A4-F25: NOT
// noexcept; bad_alloc propagates to the per-file degrade catch).
struct EvCtx
{
    std::vector<CtrlNode> arena;
    struct LabelDef     { std::uint32_t ctrl; std::string name; };            // label -> its construct's arena index
    struct PendingJump  { std::uint32_t ctrl; std::uint8_t tag; std::string label; };   // gotos + labelled jumps, resolved post-walk
    std::vector<LabelDef>    labels;
    std::vector<PendingJump> pending;
    std::uint32_t            why[ kEvWhyTagCount ] = {};
};

// jump-target kind masks for ev_findTarget
enum : std::uint8_t { kEvTgtLoop = 1, kEvTgtSwitch = 2, kEvTgtBlock = 4, kEvTgtTry = 8, kEvTgtFn = 16 };

// source text of the first child with one of the given node types ("" when absent). Jump statements are
// grammar-bounded shapes (a keyword + at most a label/expression), so the indexed child form is right here
// (see the O(children) note above collectChildren — this is a bounded-shape scan, not an unbounded walk).
inline std::string_view ev_childText( TSNode n, std::string_view src, std::initializer_list<const char*> types ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t ci = 0; ci < childCount; ++ci )
    {
        const TSNode child = ts_node_child( n, ci );
        const char*  ct    = ts_node_type( child );
        for( const char* want : types )
        {
            if( std::strcmp( ct, want ) == 0 )
            {
                const std::uint32_t a = ts_node_start_byte( child ), b = ts_node_end_byte( child );
                if( b <= src.size() && b > a )
                {
                    return src.substr( a, b - a );
                }
            }
        }
    }
    return {};
}

// does the node carry an ANONYMOUS keyword child with this exact spelling? (C# `goto case 1;` /
// `yield break;` — the discriminating token is unnamed, so type-based lookup cannot see it.)
inline bool ev_hasAnonKeyword( TSNode n, std::string_view src, std::string_view keyword ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t ci = 0; ci < childCount; ++ci )
    {
        const TSNode child = ts_node_child( n, ci );
        if( ts_node_is_named( child ) )
        {
            continue;
        }
        const std::uint32_t a = ts_node_start_byte( child ), b = ts_node_end_byte( child );
        if( b <= src.size() && b - a == keyword.size() && src.substr( a, b - a ) == keyword )
        {
            return true;
        }
    }
    return false;
}

// one label spelling across the grammars: Rust labels carry a leading tick (`'outer`), Swift statement
// labels a trailing colon (`outer:`); the jump side and the definition side must agree byte-for-byte.
inline std::string_view ev_normalizeLabel( std::string_view label ) noexcept
{
    if( !label.empty() && label.front() == '\'' ) { label.remove_prefix( 1 ); }
    if( !label.empty() && label.back() == ':' )   { label.remove_suffix( 1 ); }
    return label;
}

// nearest enclosing construct of an allowed kind, walking parent links. A Fn node is a hard boundary:
// return-family jumps may TARGET it (kEvTgtFn), everything else fails there — a break can never leave a
// closure, so resolving past one would mark constructs the jump provably does not cross (floor rule).
// Returns kNoCtrl for "function root" when the mask includes kEvTgtFn, and for FAILURE otherwise — the
// callers' masks make the two cases unambiguous per jump family.
inline std::uint32_t ev_findTarget( const EvCtx& ctx, std::uint32_t from, std::uint8_t mask ) noexcept
{
    for( std::uint32_t i = from; i != kNoCtrl; i = ctx.arena[i].parent )
    {
        const CtrlKind k = CtrlKind( ctx.arena[i].kind );
        if( k == CtrlKind::Fn )
        {
            return ( mask & kEvTgtFn ) ? i : kNoCtrl;
        }
        if( ( ( mask & kEvTgtLoop ) && k == CtrlKind::Loop ) || ( ( mask & kEvTgtSwitch ) && k == CtrlKind::Switch )
            || ( ( mask & kEvTgtBlock ) && k == CtrlKind::Block ) || ( ( mask & kEvTgtTry ) && k == CtrlKind::Try ) )
        {
            return i;
        }
    }
    return kNoCtrl;   // reached the function root
}

// a throw's target: the nearest enclosing try — but a try whose chain we enter THROUGH its own catch
// clause is not a landing site (a rethrow propagates outward), so a Catch on the chain skips the next Try.
inline std::uint32_t ev_findThrowTarget( const EvCtx& ctx, std::uint32_t from ) noexcept
{
    bool skipOwnTry = false;
    for( std::uint32_t i = from; i != kNoCtrl; i = ctx.arena[i].parent )
    {
        const CtrlKind k = CtrlKind( ctx.arena[i].kind );
        if( k == CtrlKind::Fn )
        {
            return i;
        }
        if( k == CtrlKind::Catch )
        {
            skipOwnTry = true;
        }
        else if( k == CtrlKind::Try )
        {
            if( skipOwnTry ) { skipOwnTry = false; }
            else             { return i; }
        }
    }
    return kNoCtrl;   // function root — an uncaught throw is a guard-shaped exit
}

// mark every construct STRICTLY BETWEEN `from` and `target` (exclusive). A Case arm that is the target's
// own DIRECT arm is the jump's normal exit (design §2.2 row 1 — `case 1: … break;` is structured) and is
// skipped when excludeDirectArm. Returns whether this jump CONTRIBUTES to ev_why: it must have crossed a
// construct that actually raises ev — one carrying decision weight, or a switch head (whose arms then
// complete). A weight-0 transparent wrapper alone (a goto label around the tail return, a bare Try) does
// not make a jump a contributor — the tag counts must explain a RAISED ev, not narrate the walk.
// Already-marked nodes still count — two breaks under one if are two contributing jumps, not one.
inline bool ev_markBetween( EvCtx& ctx, std::uint32_t from, std::uint32_t target, bool excludeDirectArm ) noexcept
{
    bool contributed = false;
    for( std::uint32_t i = from; i != target && i != kNoCtrl; i = ctx.arena[i].parent )
    {
        if( excludeDirectArm && CtrlKind( ctx.arena[i].kind ) == CtrlKind::Case && ctx.arena[i].parent == target )
        {
            continue;
        }
        ctx.arena[i].marked = 1;
        if( ctx.arena[i].weight > 0 || CtrlKind( ctx.arena[i].kind ) == CtrlKind::Switch )
        {
            contributed = true;
        }
    }
    return contributed;
}

inline void ev_countWhy( EvCtx& ctx, EvWhyTag tag ) noexcept
{
    ++ctx.why[ std::size_t( tag ) ];
}

// is `t` a control construct the arena tracks, and of what kind? Lang-gated where node-type spellings
// collide across grammars (Swift's `do_statement` is a try, the C family's a loop; Ruby's bare-word kinds
// double as anonymous keyword tokens elsewhere — the caller's isNamed gate recovers them, exactly as
// cc_isNestingControl's note explains). Node-type spellings verified against the VENDORED grammars via
// real parses (--match probes per language), not assumed — the ln_extractDeclaratorIdentifiers discipline.
inline bool ev_ctrlKindFor( const char* t, Lang lang, CtrlKind& kindOut ) noexcept
{
    // branches
    if(    std::strcmp( t, "if_statement" ) == 0        || std::strcmp( t, "if_expression" ) == 0
        || std::strcmp( t, "conditional_expression" ) == 0 || std::strcmp( t, "ternary_expression" ) == 0
        || std::strcmp( t, "guard_statement" ) == 0     || std::strcmp( t, "conditional" ) == 0
        || std::strcmp( t, "elif_clause" ) == 0         || std::strcmp( t, "else_clause" ) == 0
        || std::strcmp( t, "elsif" ) == 0               || std::strcmp( t, "if" ) == 0
        || std::strcmp( t, "unless" ) == 0              || std::strcmp( t, "if_modifier" ) == 0
        || std::strcmp( t, "unless_modifier" ) == 0 )
    {
        kindOut = CtrlKind::Branch;
        return true;
    }
    // loops (Swift's do_statement is a TRY and is handled below)
    if(    std::strcmp( t, "for_statement" ) == 0       || std::strcmp( t, "for_range_loop" ) == 0
        || std::strcmp( t, "for_in_statement" ) == 0    || std::strcmp( t, "for_expression" ) == 0
        || std::strcmp( t, "while_statement" ) == 0     || std::strcmp( t, "while_expression" ) == 0
        || std::strcmp( t, "loop_expression" ) == 0     || std::strcmp( t, "foreach_statement" ) == 0
        || std::strcmp( t, "repeat_while_statement" ) == 0
        || ( std::strcmp( t, "do_statement" ) == 0 && lang != Lang::Swift )
        || std::strcmp( t, "while" ) == 0               || std::strcmp( t, "until" ) == 0
        || std::strcmp( t, "for" ) == 0                 || std::strcmp( t, "while_modifier" ) == 0
        || std::strcmp( t, "until_modifier" ) == 0 )
    {
        kindOut = CtrlKind::Loop;
        return true;
    }
    // switch/match heads (weight 0 — the arms carry the decisions, as in cx)
    if(    std::strcmp( t, "switch_statement" ) == 0    || std::strcmp( t, "switch_expression" ) == 0
        || std::strcmp( t, "match_expression" ) == 0    || std::strcmp( t, "match_statement" ) == 0
        || std::strcmp( t, "expression_switch_statement" ) == 0 || std::strcmp( t, "type_switch_statement" ) == 0
        || std::strcmp( t, "select_statement" ) == 0    || std::strcmp( t, "case" ) == 0
        || std::strcmp( t, "case_match" ) == 0 )
    {
        kindOut = CtrlKind::Switch;
        return true;
    }
    // arms
    if(    std::strcmp( t, "case_statement" ) == 0      || std::strcmp( t, "switch_section" ) == 0
        || std::strcmp( t, "switch_expression_arm" ) == 0 || std::strcmp( t, "match_arm" ) == 0
        || std::strcmp( t, "expression_case" ) == 0     || std::strcmp( t, "communication_case" ) == 0
        || std::strcmp( t, "default_case" ) == 0        || std::strcmp( t, "type_case" ) == 0
        || std::strcmp( t, "case_clause" ) == 0         || std::strcmp( t, "switch_entry" ) == 0
        || std::strcmp( t, "switch_rule" ) == 0         || std::strcmp( t, "switch_block_statement_group" ) == 0
        || std::strcmp( t, "when" ) == 0                || std::strcmp( t, "in_clause" ) == 0 )
    {
        kindOut = CtrlKind::Case;
        return true;
    }
    // try / catch (Swift spells try as do_statement + catch_block)
    if(    std::strcmp( t, "try_statement" ) == 0       || std::strcmp( t, "try_with_resources_statement" ) == 0
        || std::strcmp( t, "begin" ) == 0               || ( std::strcmp( t, "do_statement" ) == 0 && lang == Lang::Swift ) )
    {
        kindOut = CtrlKind::Try;
        return true;
    }
    if(    std::strcmp( t, "catch_clause" ) == 0        || std::strcmp( t, "except_clause" ) == 0
        || std::strcmp( t, "catch_block" ) == 0         || std::strcmp( t, "rescue" ) == 0 )
    {
        kindOut = CtrlKind::Catch;
        return true;
    }
    // function boundaries — the jump barrier. A miss here is the ONE table error that would OVER-count
    // (a return inside an unrecognised closure shape would mark the outer function's constructs), which
    // is why this list errs wide and every entry was probe-verified.
    if(    std::strcmp( t, "lambda_expression" ) == 0   || std::strcmp( t, "lambda" ) == 0
        || std::strcmp( t, "closure_expression" ) == 0  || std::strcmp( t, "function_definition" ) == 0
        || std::strcmp( t, "function_declaration" ) == 0 || std::strcmp( t, "function_expression" ) == 0
        || std::strcmp( t, "arrow_function" ) == 0      || std::strcmp( t, "generator_function" ) == 0
        || std::strcmp( t, "generator_function_declaration" ) == 0 || std::strcmp( t, "method_definition" ) == 0
        || std::strcmp( t, "method_declaration" ) == 0  || std::strcmp( t, "func_literal" ) == 0
        || std::strcmp( t, "function_item" ) == 0       || std::strcmp( t, "lambda_literal" ) == 0
        || std::strcmp( t, "local_function_statement" ) == 0 || std::strcmp( t, "anonymous_method_expression" ) == 0
        || std::strcmp( t, "method" ) == 0              || std::strcmp( t, "singleton_method" ) == 0 )
    {
        kindOut = CtrlKind::Fn;
        return true;
    }
    // Ruby blocks — a jump scope of their own (`each do … next end`: next is the block's normal exit);
    // lang-gated because Go/Java/C# spell their PLAIN braces "block", which must stay out of the arena.
    if( lang == Lang::Ruby && ( std::strcmp( t, "block" ) == 0 || std::strcmp( t, "do_block" ) == 0 ) )
    {
        kindOut = CtrlKind::Block;
        return true;
    }
    if( std::strcmp( t, "labeled_statement" ) == 0 )
    {
        kindOut = CtrlKind::Labelled;
        return true;
    }
    return false;
}

// append one arena node; registers labels (labeled_statement wrappers; Rust/Swift loops carrying their
// own label child) and fires the §2.6 multi-entry detection for displaced arms. Returns the new index.
inline std::uint32_t ev_appendCtrl( EvCtx& ctx, TSNode n, CtrlKind kind, std::uint16_t weight, std::uint32_t parentIdx, Lang lang, std::string_view src )
{
    const std::uint32_t newIdx = std::uint32_t( ctx.arena.size() );
    ctx.arena.push_back( CtrlNode{ parentIdx, weight, std::uint8_t( kind ), 0 } );
    if( kind == CtrlKind::Labelled )
    {
        const std::string_view label = ev_normalizeLabel( ev_childText( n, src, { "statement_identifier", "label_name", "identifier" } ) );
        if( !label.empty() )
        {
            ctx.labels.push_back( { newIdx, std::string( label ) } );
        }
    }
    else if( ( kind == CtrlKind::Loop || kind == CtrlKind::Switch ) && ( lang == Lang::Rust || lang == Lang::Swift ) )
    {
        // Rust: `'outer: loop { … }` — the label is a child of the loop expression itself.
        // Swift: `outer: for … { … }` — a statement_label child, colon included.
        const std::string_view label = ev_normalizeLabel( ev_childText( n, src, { "label", "statement_label" } ) );
        if( !label.empty() )
        {
            ctx.labels.push_back( { newIdx, std::string( label ) } );
        }
    }
    if( kind == CtrlKind::Case && parentIdx != kNoCtrl )
    {
        const CtrlKind parentKind = CtrlKind( ctx.arena[ parentIdx ].kind );
        if( parentKind != CtrlKind::Switch && parentKind != CtrlKind::Case )
        {
            // §2.6 — a case label displaced under a loop/branch between it and its switch (Duff's device):
            // a REAL multi-entry region the single-entry theorem excludes everywhere else. Mark the arm;
            // outward propagation then keeps the displacing construct, the switch, and every sibling arm.
            ctx.arena[ newIdx ].marked = 1;
            ev_countWhy( ctx, EvWhyTag::MultiEntry );
        }
    }
    return newIdx;
}

// note one visited node for ev: either it opens a control construct (-> new arena node, returned as the
// children's ctrl) or it is a jump (-> resolve or defer). Anything else returns parentIdx unchanged.
// Caller guarantees isNamed (anonymous keyword tokens must never look like Ruby's bare-word nodes).
inline std::uint32_t ev_noteNode( EvCtx& ctx, TSNode n, const char* t, std::uint32_t parentIdx, Lang lang, std::string_view src )
{
    CtrlKind kind;
    if( ev_ctrlKindFor( t, lang, kind ) )
    {
        return ev_appendCtrl( ctx, n, kind, std::uint16_t( isDecisionType( t ) ? 1 : 0 ), parentIdx, lang, src );
    }

    // ── jumps. Every rule below: resolve the target (ancestors only — the arena already holds them in a
    //    pre-order walk), mark strictly between, count the tag iff the chain was non-empty. Unresolvable
    //    (or unrecognised) ⇒ mark nothing — the floor rule.
    const bool isRuby = ( lang == Lang::Ruby );

    // return-family: target = nearest closure boundary, else the function root. Ruby `return` passes
    // THROUGH blocks (a non-local method return), which kEvTgtFn-only masks give for free.
    const auto noteReturn = [ & ]()
    {
        if( ev_markBetween( ctx, parentIdx, ev_findTarget( ctx, parentIdx, kEvTgtFn ), false ) )
        {
            ev_countWhy( ctx, EvWhyTag::GuardReturn );
        }
    };
    const auto noteThrow = [ & ]()
    {
        if( ev_markBetween( ctx, parentIdx, ev_findThrowTarget( ctx, parentIdx ), false ) )
        {
            ev_countWhy( ctx, EvWhyTag::GuardReturn );
        }
    };
    // break/continue-family: `armExit` = an arm-tail break is the target's normal exit (row 1).
    const auto noteEscape = [ & ]( std::uint8_t mask, bool armExit )
    {
        const std::uint32_t target = ev_findTarget( ctx, parentIdx, mask );
        if( target == kNoCtrl )
        {
            return;   // no such construct below the closure boundary — never mark speculatively
        }
        if( ev_markBetween( ctx, parentIdx, target, armExit ) )
        {
            ev_countWhy( ctx, CtrlKind( ctx.arena[ target ].kind ) == CtrlKind::Switch ? EvWhyTag::SwitchEscape : EvWhyTag::LoopEscape );
        }
    };

    if( std::strcmp( t, "return_statement" ) == 0 || std::strcmp( t, "return_expression" ) == 0
        || std::strcmp( t, "co_return_statement" ) == 0 || ( isRuby && std::strcmp( t, "return" ) == 0 ) )
    {
        noteReturn();
    }
    else if( std::strcmp( t, "throw_statement" ) == 0 || std::strcmp( t, "raise_statement" ) == 0 )
    {
        noteThrow();
    }
    else if( std::strcmp( t, "break_statement" ) == 0 || std::strcmp( t, "continue_statement" ) == 0 )
    {
        const bool             isBreak = ( t[0] == 'b' );
        const std::string_view label   = ev_normalizeLabel( ev_childText( n, src, { "statement_identifier", "label_name", "identifier" } ) );
        if( !label.empty() )
        {
            ctx.pending.push_back( { parentIdx, std::uint8_t( EvWhyTag::LabelledJump ), std::string( label ) } );
        }
        else
        {
            // Python's match does not capture break (§3.1's easily-missed case) — its head is in the arena
            // as a Switch for structure, but a Python break resolves past it to the loop.
            const std::uint8_t mask = isBreak ? std::uint8_t( lang == Lang::Python ? kEvTgtLoop : ( kEvTgtLoop | kEvTgtSwitch ) )
                                              : std::uint8_t( kEvTgtLoop );
            noteEscape( mask, isBreak );
        }
    }
    else if( std::strcmp( t, "break_expression" ) == 0 || std::strcmp( t, "continue_expression" ) == 0 )
    {
        // Rust: `break 'label` / `continue 'label` carry a label child; a bare break targets the loop only.
        const std::string_view label = ev_normalizeLabel( ev_childText( n, src, { "label", "loop_label" } ) );
        if( !label.empty() )
        {
            ctx.pending.push_back( { parentIdx, std::uint8_t( EvWhyTag::LabelledJump ), std::string( label ) } );
        }
        else
        {
            noteEscape( kEvTgtLoop, t[0] == 'b' );
        }
    }
    else if( isRuby && ( std::strcmp( t, "break" ) == 0 || std::strcmp( t, "next" ) == 0 ) )
    {
        noteEscape( kEvTgtLoop | kEvTgtBlock, false );
    }
    else if( isRuby && ( std::strcmp( t, "redo" ) == 0 || std::strcmp( t, "retry" ) == 0 ) )
    {
        // genuine back edges outside every prime (§3.1): mark the chain AND the target construct itself —
        // even a redo sitting directly in the loop body makes that loop a hand-rolled goto shape.
        const std::uint32_t target = ev_findTarget( ctx, parentIdx, std::uint8_t( t[2] == 'd' ? ( kEvTgtLoop | kEvTgtBlock ) : kEvTgtTry ) );
        if( target != kNoCtrl )
        {
            ev_markBetween( ctx, parentIdx, target, false );
            ctx.arena[ target ].marked = 1;
            ev_countWhy( ctx, EvWhyTag::BackEdge );
        }
    }
    else if( std::strcmp( t, "goto_statement" ) == 0 )
    {
        if( lang == Lang::CSharp && ( ev_hasAnonKeyword( n, src, "case" ) || ev_hasAnonKeyword( n, src, "default" ) ) )
        {
            // C# `goto case L;` / `goto default;` — an explicit intra-switch goto: target the enclosing
            // switch WITHOUT the arm-exit grace (jumping INTO another arm is never a normal exit).
            const std::uint32_t target = ev_findTarget( ctx, parentIdx, kEvTgtSwitch );
            if( target != kNoCtrl && ev_markBetween( ctx, parentIdx, target, false ) )
            {
                ev_countWhy( ctx, EvWhyTag::Goto );
            }
        }
        else
        {
            const std::string_view label = ev_normalizeLabel( ev_childText( n, src, { "statement_identifier", "label_name", "identifier" } ) );
            if( !label.empty() )
            {
                ctx.pending.push_back( { parentIdx, std::uint8_t( EvWhyTag::Goto ), std::string( label ) } );
            }
        }
    }
    else if( std::strcmp( t, "fallthrough_statement" ) == 0 )
    {
        // Go — an explicit intra-switch goto; counts (§3.1). The arm itself is marked (no arm-exit grace),
        // and propagation then keeps the switch and every sibling arm. (Swift's fallthrough is an
        // undetectable hidden token in its grammar — probe-verified — so Swift under-counts here: floor.)
        const std::uint32_t target = ev_findTarget( ctx, parentIdx, kEvTgtSwitch );
        if( target != kNoCtrl && ev_markBetween( ctx, parentIdx, target, false ) )
        {
            ev_countWhy( ctx, EvWhyTag::Fallthrough );
        }
    }
    else if( std::strcmp( t, "yield_statement" ) == 0 )
    {
        if( lang == Lang::Java )
        {
            // a switch-expression's value production — the arm's normal exit when at arm tail; an escape
            // when it crosses an intervening construct (same geometry as break-to-switch).
            const std::uint32_t target = ev_findTarget( ctx, parentIdx, kEvTgtSwitch );
            if( target != kNoCtrl && ev_markBetween( ctx, parentIdx, target, true ) )
            {
                ev_countWhy( ctx, EvWhyTag::SwitchEscape );
            }
        }
        else if( lang == Lang::CSharp && ev_hasAnonKeyword( n, src, "break" ) )
        {
            noteReturn();   // `yield break` ends the iterator — a return; `yield return` is a suspension, not a jump
        }
    }
    else if( std::strcmp( t, "control_transfer_statement" ) == 0 )
    {
        // Swift wraps break/continue/return/throw in one node kind; the keyword is its first token.
        const std::uint32_t a = ts_node_start_byte( n );
        const std::string_view rest = ( a < src.size() ) ? src.substr( a ) : std::string_view{};
        const std::string_view label = ev_normalizeLabel( ev_childText( n, src, { "simple_identifier" } ) );
        if( rest.starts_with( "break" ) || rest.starts_with( "continue" ) )
        {
            if( !label.empty() )
            {
                ctx.pending.push_back( { parentIdx, std::uint8_t( EvWhyTag::LabelledJump ), std::string( label ) } );
            }
            else
            {
                noteEscape( rest.starts_with( "break" ) ? std::uint8_t( kEvTgtLoop | kEvTgtSwitch ) : std::uint8_t( kEvTgtLoop ), rest.starts_with( "break" ) );
            }
        }
        else if( rest.starts_with( "return" ) )
        {
            noteReturn();
        }
        else if( rest.starts_with( "throw" ) )
        {
            noteThrow();
        }
    }
    return parentIdx;
}

// post-walk finalization: resolve the label-addressed jumps (a label can sit AFTER its goto), run the
// outward propagation, complete marked switches' arms, and sum. Returns ev (>= 1) and the tag counters.
inline void ev_finalize( EvCtx& ctx, std::uint32_t& evOut, std::array<std::uint8_t, kEvWhyTagCount>& whyOut )
{
    // 1. label-addressed jumps — goto via lowest common ancestor (§2.5), labelled break/continue via the
    //    ancestor check. A label that is missing, duplicated, or across a closure boundary marks NOTHING.
    for( const EvCtx::PendingJump& jump : ctx.pending )
    {
        std::uint32_t labelCtrl = kNoCtrl;
        bool          found = false, duplicated = false;
        for( const EvCtx::LabelDef& def : ctx.labels )
        {
            if( def.name == jump.label )
            {
                duplicated = found;
                labelCtrl  = def.ctrl;
                found      = true;
            }
        }
        if( !found || duplicated )
        {
            continue;
        }
        if( EvWhyTag( jump.tag ) == EvWhyTag::LabelledJump )
        {
            // the labelled construct must be an ANCESTOR reached without crossing a closure boundary
            bool reachable = false;
            for( std::uint32_t i = jump.ctrl; i != kNoCtrl; i = ctx.arena[i].parent )
            {
                if( CtrlKind( ctx.arena[i].kind ) == CtrlKind::Fn ) { break; }
                if( i == labelCtrl ) { reachable = true; break; }
            }
            if( reachable && ev_markBetween( ctx, jump.ctrl, labelCtrl, false ) )
            {
                ev_countWhy( ctx, EvWhyTag::LabelledJump );
            }
        }
        else   // goto
        {
            // both chains, each ending at the first closure boundary (inclusive, so two nodes under the
            // SAME closure still meet); no common node + any boundary ⇒ different scopes ⇒ mark nothing.
            const auto chainOf = [ & ]( std::uint32_t from, std::vector<std::uint32_t>& out, bool& hitFn )
            {
                out.clear();
                hitFn = false;
                for( std::uint32_t i = from; i != kNoCtrl; i = ctx.arena[i].parent )
                {
                    out.push_back( i );
                    if( CtrlKind( ctx.arena[i].kind ) == CtrlKind::Fn ) { hitFn = true; break; }
                }
            };
            std::vector<std::uint32_t> jumpChain, labelChain;
            bool jumpHitFn = false, labelHitFn = false;
            chainOf( jump.ctrl, jumpChain, jumpHitFn );
            chainOf( labelCtrl, labelChain, labelHitFn );
            std::uint32_t lca      = kNoCtrl;
            std::size_t   lcaJump  = jumpChain.size(), lcaLabel = labelChain.size();
            for( std::size_t j = 0; j < jumpChain.size() && lca == kNoCtrl; ++j )
            {
                for( std::size_t l = 0; l < labelChain.size(); ++l )
                {
                    if( labelChain[l] == jumpChain[j] )
                    {
                        lca = jumpChain[j]; lcaJump = j; lcaLabel = l;
                        break;
                    }
                }
            }
            if( lca == kNoCtrl && ( jumpHitFn || labelHitFn ) )
            {
                continue;   // different closure scopes (a label name reused inside a lambda) — floor rule
            }
            bool contributed = false;
            const auto markChainNode = [ & ]( std::uint32_t idx )
            {
                ctx.arena[ idx ].marked = 1;
                if( ctx.arena[ idx ].weight > 0 || CtrlKind( ctx.arena[ idx ].kind ) == CtrlKind::Switch )
                {
                    contributed = true;   // same contributor rule as ev_markBetween: a crossed construct that raises ev
                }
            };
            for( std::size_t j = 0; j < lcaJump; ++j )   { markChainNode( jumpChain[j] ); }
            for( std::size_t l = 0; l < lcaLabel; ++l )  { markChainNode( labelChain[l] ); }
            if( contributed )
            {
                ev_countWhy( ctx, EvWhyTag::Goto );
            }
        }
    }

    // 2. outward propagation (§2.2): an uncollapsed child keeps its ancestors in the residue. Ascending
    //    index order + early stop is correct because parents precede children in a pre-order arena, and a
    //    walk that marks a node always finishes that node's whole chain in the same sweep. Closure
    //    boundaries (Fn) and Ruby blocks (Block) contain their tangles — the outer function's constructs
    //    stay reducible around them.
    for( std::uint32_t i = 0; i < std::uint32_t( ctx.arena.size() ); ++i )
    {
        if( !ctx.arena[i].marked )
        {
            continue;
        }
        for( std::uint32_t p = ctx.arena[i].parent; p != kNoCtrl; p = ctx.arena[p].parent )
        {
            const CtrlKind k = CtrlKind( ctx.arena[p].kind );
            if( k == CtrlKind::Fn || k == CtrlKind::Block || ctx.arena[p].marked )
            {
                break;
            }
            ctx.arena[p].marked = 1;
        }
    }

    // 3. a marked switch head contributes EVERY arm (§2.2 last row). Ascending order cascades through
    //    nested consecutive labels (an arm whose parent is itself an arm).
    for( std::uint32_t i = 0; i < std::uint32_t( ctx.arena.size() ); ++i )
    {
        if( CtrlKind( ctx.arena[i].kind ) != CtrlKind::Case || ctx.arena[i].parent == kNoCtrl )
        {
            continue;
        }
        const CtrlNode& parent = ctx.arena[ ctx.arena[i].parent ];
        if( parent.marked && ( CtrlKind( parent.kind ) == CtrlKind::Switch || CtrlKind( parent.kind ) == CtrlKind::Case ) )
        {
            ctx.arena[i].marked = 1;
        }
    }

    // 4. ev = 1 + Σ marked weights (saturating, humps' rule), and the tag counters (saturating at u8).
    std::uint32_t sum = 1;
    for( const CtrlNode& node : ctx.arena )
    {
        if( node.marked )
        {
            sum += node.weight;
        }
    }
    evOut = ( sum > 65535u ) ? 65535u : sum;
    for( std::size_t tagIndex = 0; tagIndex < kEvWhyTagCount; ++tagIndex )
    {
        whyOut[ tagIndex ] = std::uint8_t( ctx.why[ tagIndex ] > 255u ? 255u : ctx.why[ tagIndex ] );
    }
}

// A4-F25: NOT noexcept — the frame-stack vector allocates, so under memory pressure bad_alloc must be
// allowed to propagate to the per-file degrade catch, not turn into terminate().
inline void cc_walk( TSNode start, std::uint32_t startNesting, std::string_view src, CcAccum& acc, int startDepth,
                      bool countLocals,   // Phase 1: countLocals gates on lang (model.h localsCountedLang), C/C++ only
                      Lang lang, EvCtx* evCtx )   // essential complexity: nullptr outside model.h evCountedLang — zero work then
{
    // iterative pre-order DFS — an EXPLICIT frame stack, not recursion: worker threads get 512 KB stacks on
    // macOS, so a deep AST overflows the call stack well inside the depth guard. Children are pushed in
    // reverse so pops preserve the original left-to-right visit order; the guard bounds the heap stack.
    struct CcFrame { TSNode node; std::uint32_t nesting; std::uint32_t ctrl; std::uint16_t depth; };   // ctrl: innermost enclosing ev arena index (kNoCtrl at root)
    std::vector<CcFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { start, startNesting, kNoCtrl, static_cast<std::uint16_t>( startDepth ) } );
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

        // essential complexity: one arena/jump note per named node, and the ctrl index the children
        // inherit. All jump nodes are named in every supported grammar, and the isNamed gate is what
        // keeps Ruby's bare-word kinds from colliding with anonymous keyword tokens (see the note above).
        const std::uint32_t ctrl = ( evCtx != nullptr && isNamed ) ? ev_noteNode( *evCtx, n, t, frame.ctrl, lang, src ) : frame.ctrl;

        // cyclomatic (flat decision count) accumulated in the SAME DFS as cognitive — one walk, both metrics.
        if( isNamed && isDecisionType( t ) )
        {
            ++acc.cyclo;
        }
        // ppalt disclosure: an alternative-introducing preproc node is neither control nor decision, so it
        // falls through to the generic descent below (its children ARE walked and summed — that summing is
        // exactly what this counter discloses).
        if( isNamed && cc_isPreprocAlternative( t ) )
        {
            ++acc.ppAlt;
        }
        // Phase 1 (local-variable-indexing): same fused DFS, third accumulator — zero extra tree-sitter
        // queries. countLocals is false for every non-C/C++ def (model.h localsCountedLang), so this whole
        // check compiles to a single branch-not-taken for every other language's walk. L3 fix (2026-08-08):
        // counts DECLARATORS (cc_countLocalDeclarators), not declaration statements — `int a,b,c;` is one
        // countable `declaration` node but three locals; see cc_countLocalDeclarators' own comment.
        if( countLocals && isNamed && cc_isCountableLocalDecl( n, t ) )
        {
            acc.locals += cc_countLocalDeclarators( n );
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
                stack.push_back( { kids[i - 1], childNest, ctrl, childDepth } );
            }
            continue;
        }
        if( isNamed && ( std::strcmp( t, "elif_clause" ) == 0 || std::strcmp( t, "else_clause" ) == 0
                         || std::strcmp( t, "elsif" ) == 0 ) )   // else / elif / else-if (+ Ruby `elsif`): flat +1 (cognitive)
        {
            acc.cog += 1u;
            collectChildren( n, cursor.cur, kids );
            for( std::size_t i = kids.size(); i > 0; --i )
            {
                const TSNode c  = kids[ i - 1 ];
                const char*  ct = ts_node_type( c );
                if( std::strcmp( ct, "if_statement" ) == 0 || std::strcmp( ct, "if_expression" ) == 0 )
                {
                    // C-family `else if`: descend into the if's CHILDREN so cognitive doesn't re-score it as a
                    // fresh control — but cyclomatic still counts that `if` as a decision (parity with the old walk).
                    // ev: that if never becomes a frame, so it gets its arena node HERE (Branch, weight 1 — 1:1
                    // with the cyclo increment above, preserving the structural ev <= cx containment).
                    ++acc.cyclo;
                    const std::uint32_t elifCtrl = ( evCtx != nullptr ) ? ev_appendCtrl( *evCtx, c, CtrlKind::Branch, 1, ctrl, lang, src ) : ctrl;
                    collectChildren( c, cursor.cur, elifKids );   // NOT kids — that iteration is still live
                    for( std::size_t j = elifKids.size(); j > 0; --j )
                    {
                        stack.push_back( { elifKids[j - 1], nesting, elifCtrl, childDepth } );
                    }
                }
                else
                {
                    // An else/elif body sits at the construct's PRIMARY-body level: `nesting` here is the
                    // clause's inherited frame nesting, which already carries the parent construct's +1 (the
                    // if pushed ALL its children at childNest). Deepening again — as this branch did before
                    // the nestcal r1 round — double-counted every clause body AND raised maxNest/minted one
                    // hump per clause CHILD (the anonymous keyword token, the condition, `:`), which is how a
                    // 20-line elif ladder reported humps=16. No maxNest bump and no cc_noteHump belong here:
                    // the parent construct recorded this depth when IT crossed, and a clause opens no new
                    // depth (matches Java/Go/C#, whose grammars have no clause node and were always flat).
                    // (ev rides along untouched: `ctrl` is the clause's own arena index from ev_noteNode.)
                    stack.push_back( { c, nesting, ctrl, childDepth } );
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
                stack.push_back( { kids[i - 1], nesting + 1, ctrl, childDepth } );
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
            stack.push_back( { kids[i - 1], nesting, ctrl, childDepth } );
        }
    }
}
struct Complexity { std::uint32_t cx; std::uint32_t ccx; std::uint32_t maxNest; std::uint32_t locals; std::uint32_t ppAlt; std::uint32_t humps; std::uint32_t deepLoc; std::uint32_t ev; std::array<std::uint8_t, kEvWhyTagCount> evWhy; };
// `lang`: Phase 1 (local-variable-indexing) gates the locals accumulator to model.h's localsCountedLang
// (C/C++ only, MVP scope) INSIDE the same fused walk — every other language pays one branch-not-taken
// per node and gets locals=0, which the caller (this file, RawDef→Symbol) leaves at 0 and serialize.h
// never emits (absent, not a bare "0" — see localsCountedLang's own comment).
inline Complexity complexityOf( TSNode root, std::string_view src, Lang lang )   // one fused DFS → cx, ccx, maxNest, locals, ppAlt, the nesting profile, AND ev
{                                                                     // A4-F25: NOT noexcept — cc_walk (and kids here) allocate
    CcAccum acc;
    const bool countLocals = localsCountedLang( lang );
    // essential complexity rides the SAME walk (zero new tree-sitter queries). ONE arena/label/pending set
    // across all top-level children — a goto and its label can sit in sibling statements — finalized once
    // the whole def has been walked. nullptr outside evCountedLang: every other language pays one
    // branch-not-taken per node and gets ev=0, which serialize.h never emits (model.h evCountedLang).
    EvCtx        evCtx;
    EvCtx* const evPtr = evCountedLang( lang ) ? &evCtx : nullptr;
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );
    collectChildren( root, cursor.cur, kids );              // start INSIDE the def (the def node is neither control nor decision)
    // ONE accumulator across all top-level children: the deepEnd clamp has to see the whole def in document
    // order, and humps in sibling statements are humps of the same function.
    for( const TSNode c : kids )
    {
        cc_walk( c, 0, src, acc, 0, countLocals, lang, evPtr );
    }
    // cx = 1 + decisions ; ccx = nesting-weighted cognitive ; maxNest = deepest control nesting ;
    // locals = Phase 1 floor count ; ppAlt = preproc alternative branches (model.h Symbol::ppAlt) ;
    // humps/deepLoc = the nesting profile ; ev/evWhy = essential complexity (model.h Symbol) —
    // 0 outside evCountedLang, >= 1 inside it.
    Complexity out{ 1u + acc.cyclo, acc.cog, acc.maxNest, acc.locals, acc.ppAlt, acc.humps, acc.deepLoc, 0u, {} };
    if( evPtr != nullptr )
    {
        ev_finalize( evCtx, out.ev, out.evWhy );
    }
    return out;
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
// introduces (plural: `int a, b;` is ONE declaration with TWO "declarator:"-fielded children — since the L3
// fix, Phase 1's COUNT (cc_countLocalDeclarators, above) agrees with Phase 2 here at the SLOT level: both
// count 2. They still differ one level deeper — this walk recurses INTO each slot to find the actual name
// node(s) Phase 2 judges, where Phase 1 only needs the slot count — reusing cc_isDeclaratorField for the
// shared "which children are declarator slots" scan, not re-typing the field-name check.
inline void ln_declaratorIdentifiers( TSNode declNode, std::vector<TSNode>& outIdents )
{
    const std::uint32_t n = ts_node_child_count( declNode );
    for( std::uint32_t i = 0; i < n; ++i )
    {
        if( cc_isDeclaratorField( declNode, i ) )
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
// down, OUTSIDE this anonymous namespace — same split as ingest()/astQueryGrouped() in this same file:
// an anonymous-namespace definition would give it INTERNAL linkage, which cannot satisfy ingest.h's
// declaration. The ln_* helpers above stay in here (internal-only, next to cc_walk/complexityOf which they
// mirror) and remain visible to that later definition, exactly like ingest()/astQueryGrouped() already
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

// ---- macro-edges round: function-like `#define` body handling -------------------------------------------
// The C-family grammars expose a macro's replacement text as ONE opaque `preproc_arg` token — tree-sitter
// does not parse it, so no tags pattern can ever see a call inside it. Two helpers close that honestly:
//
//   preprocFunctionDefHasBody — the indexing gate: an empty (or all-whitespace) replacement defines nothing
//     callable, so `#define NOOP(x)` stays unindexed rather than minting a body-less callable symbol.
//
//   captureMacroBodyCalls — a LEXICAL scan of the replacement text for call-shaped identifiers (`ident (`),
//     emitting one role=Call RawRef per hit at its real byte position, so the existing byte-span sweep
//     attributes it to the macro symbol (whose span covers the whole #define) and the graph connects
//     THROUGH the macro (handler → LOG_ERR → logImpl). Disclosed-degraded by construction — this is a
//     lexer, not a parser — and conservative about the known noise sources: string/char literals are
//     skipped, C/C++ control keywords are skipped, the macro's OWN parameters are skipped (`x(` where x is
//     a param is the CALLER's token, not a body call), a `#`/`##`-preceded identifier is stringize/paste
//     operand (a synthetic token, never emitted), and the macro's own name is skipped (a self-reference
//     does not expand). Function-like macros ONLY — an object-like #define is not a call-edge participant.

// is `w` a C/C++ keyword that can legally precede `(` in a macro body without being a call?
bool macroBodyKeyword( std::string_view w ) noexcept
{
    static constexpr std::string_view kw[] = {
        "if", "for", "while", "switch", "return", "sizeof", "defined", "do", "else", "goto",
        "case", "default", "alignof", "typeof", "decltype", "throw", "catch", "new", "delete",
    };
    return std::find( std::begin( kw ), std::end( kw ), w ) != std::end( kw );
}

// the `value:` (preproc_arg) child of a preproc_function_def / preproc_def; null node if absent.
TSNode preprocValueNode( TSNode defineNode ) noexcept
{
    return ts_node_child_by_field_name( defineNode, "value", 5 );
}

// the def's body node: the `body:` field for every function/class grammar, and — macro-edges round — a
// #define's `value:` (preproc_arg) replacement text. Adopting the value as the body gives a macro symbol a
// real signature/body split (sigEnd = replacement start), which is ALSO what makes graph.h's decl/def
// collapse treat an indexed macro as a DEFINITION (hasBody: endByte > sigEndByte) instead of a shadowable
// forward decl. Kept out of captureTagsFacts (the file's densest dispatch point) behind one call.
TSNode defBodyNodeOf( TSNode roleNode, SymKind kind ) noexcept
{
    TSNode body = ts_node_child_by_field_name( roleNode, "body", 4 );
    if( ts_node_is_null( body ) && kind == SymKind::Macro )
    {
        body = ts_node_child_by_field_name( roleNode, "value", 5 );
    }
    return body;
}

bool preprocFunctionDefHasBody( TSNode defineNode, std::string_view src ) noexcept
{
    const TSNode value = preprocValueNode( defineNode );
    if( ts_node_is_null( value ) )
    {
        return false;
    }
    const uint32_t a = ts_node_start_byte( value );
    const uint32_t b = ts_node_end_byte( value );
    if( a >= b || b > src.size() )
    {
        return false;
    }
    for( uint32_t i = a; i < b; ++i )
    {
        const char c = src[i];
        if( c != ' ' && c != '\t' && c != '\\' && c != '\n' && c != '\r' )
        {
            return true;   // at least one real token byte — a statement/expression body
        }
    }
    return false;
}

void captureMacroBodyCalls( TSNode defineNode, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<RawRef>& refs )
{
    // function-like `#define` only: object-like preproc_def is not a call-edge participant, and the
    // non-C-family @definition.macro capture (Rust macro_definition) has no preproc replacement to scan.
    // Checked HERE so the captureTagsFacts call site stays a single kind test.
    if( std::strcmp( ts_node_type( defineNode ), "preproc_function_def" ) != 0 )
    {
        return;
    }
    const TSNode value = preprocValueNode( defineNode );
    if( ts_node_is_null( value ) )
    {
        return;
    }
    const uint32_t va = ts_node_start_byte( value );
    const uint32_t vb = ts_node_end_byte( value );
    if( va >= vb || vb > src.size() )
    {
        return;
    }

    // the macro's own name (self-reference never expands) + its parameter names (a param used call-shaped
    // is the ARGUMENT's business, not a body call — `#define CALL(f) f()` has no resolvable callee here).
    std::string macroName;
    if( const TSNode nameNode = ts_node_child_by_field_name( defineNode, "name", 4 ); !ts_node_is_null( nameNode ) )
    {
        const uint32_t na = ts_node_start_byte( nameNode );
        const uint32_t nb = ts_node_end_byte( nameNode );
        if( na < nb && nb <= src.size() )
        {
            macroName.assign( src.substr( na, nb - na ) );
        }
    }
    std::vector<std::string> params;
    if( const TSNode paramsNode = ts_node_child_by_field_name( defineNode, "parameters", 10 ); !ts_node_is_null( paramsNode ) )
    {
        const uint32_t pc = ts_node_child_count( paramsNode );
        for( uint32_t i = 0; i < pc; ++i )
        {
            const TSNode ch = ts_node_child( paramsNode, i );
            if( std::strcmp( ts_node_type( ch ), "identifier" ) == 0 )
            {
                const uint32_t pa = ts_node_start_byte( ch );
                const uint32_t pb = ts_node_end_byte( ch );
                if( pa < pb && pb <= src.size() )
                {
                    params.emplace_back( src.substr( pa, pb - pa ) );
                }
            }
        }
    }
    const auto isParam = [ & ]( std::string_view w ) noexcept
    {
        for( const std::string& p : params )
        {
            if( w == p )
            {
                return true;
            }
        }
        return false;
    };

    const uint32_t baseRow  = ts_node_start_point( value ).row;   // 0-based row of the replacement's first byte
    uint32_t       newlines = 0;                                  // '\n' seen so far inside [va, i)
    const auto     isIdent  = []( char c ) noexcept
    { return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_'; };

    uint32_t i = va;
    while( i < vb )
    {
        const char c = src[i];
        if( c == '\n' )
        {
            ++newlines;
            ++i;
            continue;
        }
        if( c == '"' || c == '\'' )                    // string / char literal: skip to the unescaped close
        {
            const char q = c;
            ++i;
            while( i < vb && src[i] != q )
            {
                if( src[i] == '\n' )
                {
                    ++newlines;
                }
                i += ( src[i] == '\\' && i + 1 < vb ) ? 2u : 1u;
            }
            ++i;
            continue;
        }
        if( !( isIdent( c ) && !( c >= '0' && c <= '9' ) ) )
        {
            ++i;
            continue;
        }
        // an identifier starts here. `#ident` / `##ident` is a stringize/paste operand — synthetic, skip.
        const uint32_t idStart = i;
        const bool     pasted  = idStart > va && src[ idStart - 1 ] == '#';
        while( i < vb && isIdent( src[i] ) )
        {
            ++i;
        }
        const std::string_view word = src.substr( idStart, i - idStart );
        // lookahead across whitespace + `\`-newline continuations for the call-shaped `(`. j only PEEKS —
        // the main scan resumes at i (the identifier end), so a peeked-over '\n' is still line-counted there.
        uint32_t j = i;
        while( j < vb && ( src[j] == ' ' || src[j] == '\t' || src[j] == '\r'
                           || ( src[j] == '\\' && j + 1 < vb && src[ j + 1 ] == '\n' ) ) )
        {
            j += ( src[j] == '\\' ) ? 2u : 1u;
        }
        if( j >= vb || src[j] != '(' || pasted || macroBodyKeyword( word ) || isParam( word ) || word == macroName )
        {
            continue;   // not a call shape (or a known non-callee) — resume the scan at the byte after the identifier
        }
        RawRef r;
        r.fileId    = fileId;
        r.startByte = idStart;                                   // real byte position → span-attributed to the macro symbol
        r.line      = baseRow + newlines + 1;                    // 1-based physical line of the identifier
        r.lang      = lang;
        r.role      = RefRole::Call;                             // a real call once expanded; target resolved by name like any call
        r.name      = std::string( word );
        refs.push_back( std::move( r ) );
    }
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
// `impl T { … }` (inherent, no trait) is skipped. Descends so `impl`s nested in `mod {}` are still seen.
//
// This pass no longer owns a walk: it is one visitor on the shared pre-order stream (see
// streamSideCaptures below), which is why the body is a per-node step and not a loop. It had no depth cap
// of its own, so its visitor arms at kSideDepthUnbounded and the shared stream reproduces that exactly.
struct RustImplCtx
{
    std::uint32_t         fileId = 0;
    std::string_view      src;
    std::vector<RawRef>*  refs = nullptr;
};

void rustImplVisitNode( RustImplCtx& cx, TSNode node, const char* t )
{
    FUSEPROBE_BUMP( kRustImpls );
    if( std::strcmp( t, "impl_item" ) != 0 )
    {
        return;
    }
    const TSNode traitNode = ts_node_child_by_field_name( node, "trait", 5 );
    const TSNode typeNode  = ts_node_child_by_field_name( node, "type",  4 );
    if( ts_node_is_null( traitNode ) || ts_node_is_null( typeNode ) )
    {
        return;
    }
    const std::string_view src = cx.src;
    const uint32_t ta = ts_node_start_byte( traitNode ), tb = ts_node_end_byte( traitNode );
    const uint32_t da = ts_node_start_byte( typeNode ),  db = ts_node_end_byte( typeNode );
    if( ta < tb && tb <= src.size() && da < db && db <= src.size() )
    {
        RawRef r;
        r.fileId    = cx.fileId;
        r.startByte = ta;                       // inside the impl header (file-scope; fromSymbol resolves via qualifier)
        r.line      = ts_node_start_point( traitNode ).row + 1;
        r.lang      = Lang::Rust;
        r.isInherit = true;
        r.role      = RefRole::Extends;
        r.name      = finalSegment( src.substr( ta, tb - ta ) );   // the TRAIT (base) name
        r.qualifier = finalSegment( src.substr( da, db - da ) );   // the DERIVED type name (Car/Bike) — resolved by name in buildGraph
        cx.refs->push_back( std::move( r ) );
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
        FUSEPROBE_BUMP( kInc );
        FUSEPROBE_POP();
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

// ── THE MARKDOWN SECTION TIER (collapse-queue G2/G3, gate: test/mdsectioncheck.sh) ──────────────────────
// A heading is to a doc what a function is to a file. Parsed with the vendored tree-sitter-markdown BLOCK
// grammar (custom tree walk, no tags.scm — section spans and heading hierarchy need the tree, not a
// capture list). We extract:
//   (1) a FILE-LEVEL node spanning the whole file (named by the filename stem) so heading-less docs stay
//       visible + rankable AND so cross-file [[wikilinks]]/[x](other.md) links have a target;
//   (2) every ATX (# .. ######) AND setext (===/---) heading as a Section def whose SPAN runs from the
//       heading to the next same-or-higher heading — bodyByte = the heading construct's end, so the
//       signature is the heading line and [bodyByte, endByte) is the section body --expand serves. The
//       span rule runs over the MERGED ATX+setext heading list because the grammar nests `section` nodes
//       on ATX only (probed 2026-08-12: a setext H1 does NOT open a section node) — the level rule is the
//       ratified design, the grammar's section nesting is not. scope = the nearest shallower heading
//       (parent), so the canonical id is path::Parent::Child — identity stays path-qualified;
//   (3) NOTHING inside fenced/indented code, html blocks, front-matter (minus/plus_metadata) or
//       blockquotes becomes structure: headings are read only off heading AST nodes outside block_quote,
//       and the inline line scan below skips OPAQUE byte ranges collected from the same walk (fenced code
//       is also never handed to the language grammar that owns it — no double-index);
//   (4) inline-code `identifiers` → doc→code mentions (isDocLink, resolved in buildGraph, OUT of the call
//       graph) — unchanged semantics, now attributed to their enclosing SECTION by the span containment
//       scan;
//   (5) links → edges: [[slug]] (the agent-memory/Obsidian convention) and [text](other.md) /
//       [label]: other.md → a ref named by the target's stem (the resolve ladder's same-dir preference
//       lands it on the file node); [text](#anchor) → a ref named by the matching heading in THIS file
//       (GitHub slugify; same-file preference wins) — a doc-section→doc-section edge. Dangling links drop.
// Determinism: the walk is a preorder over the AST (byte order); pending anchors resolve in byte order.
// Names are XML-escaped downstream; CR bytes never enter a name, embedded newlines flatten to spaces.
namespace mdtier
{

struct MdHeading
{
    std::uint32_t level     = 0;   // 1..6
    std::uint32_t startByte = 0;   // heading construct start (== the section's defStart)
    std::uint32_t sigEnd    = 0;   // heading construct end (ATX line / setext underline incl. newline)
    std::uint32_t nameByte  = 0;   // heading-text start (dedup identity)
    std::uint32_t endByte   = 0;   // section span end — filled by the post-pass
    std::uint32_t line      = 0;   // 1-based
    std::string   name;            // heading text: closing #s stripped, \r dropped, \n flattened
};

struct MdWalkOut
{
    std::vector<MdHeading>                                 headings;
    std::vector<std::pair<std::uint32_t, std::uint32_t>>   opaque;    // byte ranges the line scan must skip
    std::vector<std::pair<std::uint32_t, std::uint32_t>>   refDefs;   // link_reference_definition DESTINATION spans
};

inline std::string mdCleanHeadingText( std::string_view raw )
{
    std::string name;
    name.reserve( raw.size() );
    for( const char c : raw )
    {
        if( c == '\r' ) { continue; }
        name += ( c == '\n' ) ? ' ' : c;
    }
    while( !name.empty() && ( name.back() == ' ' || name.back() == '\t' ) ) { name.pop_back(); }
    while( !name.empty() && name.back() == '#' ) { name.pop_back(); }        // ATX closing sequence — the
    while( !name.empty() && ( name.back() == ' ' || name.back() == '\t' ) ) { name.pop_back(); }   // grammar keeps it (probed)
    return name;
}

// GitHub anchor slug of a heading name: alnum lowered, spaces→'-', '-'/'_' kept, everything else
// dropped. First match wins on collision (GitHub's -1/-2 suffixes are not modelled; a collided anchor
// resolves to the first heading — disclosed here rather than guessed).
inline std::string mdSlugOf( std::string_view name )
{
    std::string slug;
    slug.reserve( name.size() );
    for( const char c : name )
    {
        if( ( c >= 'a' && c <= 'z' ) || ( c >= '0' && c <= '9' ) || c == '_' || c == '-' ) { slug += c; }
        else if( c >= 'A' && c <= 'Z' ) { slug += char( c - 'A' + 'a' ); }
        else if( c == ' ' || c == '\t' ) { slug += '-'; }
    }
    return slug;
}

inline void mdWalk( TSNode node, std::string_view src, bool inQuote, std::uint32_t depth, MdWalkOut& out )
{
    if( depth > 512u )
    {
        return;   // the depth prescan (mdNestsTooDeep) bounds real trees far below this; belt only
    }
    const char*         type = ts_node_type( node );
    const std::uint32_t a    = ts_node_start_byte( node );
    const std::uint32_t b    = ts_node_end_byte( node );
    if( std::strcmp( type, "fenced_code_block" ) == 0 || std::strcmp( type, "indented_code_block" ) == 0
        || std::strcmp( type, "html_block" ) == 0 || std::strcmp( type, "minus_metadata" ) == 0
        || std::strcmp( type, "plus_metadata" ) == 0 )
    {
        out.opaque.emplace_back( a, b );
        return;   // nothing inside is structure, mention or link
    }
    if( std::strcmp( type, "link_reference_definition" ) == 0 )
    {
        out.opaque.emplace_back( a, b );   // not mention-scanned …
        const std::uint32_t n = ts_node_named_child_count( node );
        for( std::uint32_t i = 0; i < n; ++i )
        {
            TSNode ch = ts_node_named_child( node, i );
            if( std::strcmp( ts_node_type( ch ), "link_destination" ) == 0 )
            {
                out.refDefs.emplace_back( ts_node_start_byte( ch ), ts_node_end_byte( ch ) );   // … but its destination IS a link
            }
        }
        return;
    }
    if( !inQuote && std::strcmp( type, "atx_heading" ) == 0 )
    {
        MdHeading           h;
        const std::uint32_t n = ts_node_named_child_count( node );
        for( std::uint32_t i = 0; i < n; ++i )
        {
            TSNode      ch = ts_node_named_child( node, i );
            const char* ct = ts_node_type( ch );
            if( std::strncmp( ct, "atx_h", 5 ) == 0 && ct[ 5 ] >= '1' && ct[ 5 ] <= '6' )
            {
                h.level = std::uint32_t( ct[ 5 ] - '0' );
            }
            else if( std::strcmp( ct, "inline" ) == 0 )
            {
                const std::uint32_t ia = ts_node_start_byte( ch );
                h.name     = mdCleanHeadingText( src.substr( ia, ts_node_end_byte( ch ) - ia ) );
                h.nameByte = ia;
                h.line     = ts_node_start_point( ch ).row + 1;
            }
        }
        if( h.level >= 1 && !h.name.empty() )
        {
            h.startByte = a;
            h.sigEnd    = b;
            out.headings.push_back( std::move( h ) );
        }
        return;
    }
    if( !inQuote && std::strcmp( type, "setext_heading" ) == 0 )
    {
        MdHeading           h;
        const std::uint32_t n = ts_node_named_child_count( node );
        for( std::uint32_t i = 0; i < n; ++i )
        {
            TSNode      ch = ts_node_named_child( node, i );
            const char* ct = ts_node_type( ch );
            if( std::strcmp( ct, "setext_h1_underline" ) == 0 ) { h.level = 1; }
            else if( std::strcmp( ct, "setext_h2_underline" ) == 0 ) { h.level = 2; }
            else if( std::strcmp( ct, "paragraph" ) == 0 )
            {
                const std::uint32_t pn = ts_node_named_child_count( ch );
                for( std::uint32_t j = 0; j < pn; ++j )
                {
                    TSNode in = ts_node_named_child( ch, j );
                    if( std::strcmp( ts_node_type( in ), "inline" ) == 0 )
                    {
                        const std::uint32_t ia = ts_node_start_byte( in );
                        h.name     = mdCleanHeadingText( src.substr( ia, ts_node_end_byte( in ) - ia ) );
                        h.nameByte = ia;
                        h.line     = ts_node_start_point( in ).row + 1;
                    }
                }
            }
        }
        if( h.level >= 1 && !h.name.empty() )
        {
            h.startByte = a;
            h.sigEnd    = b;
            out.headings.push_back( std::move( h ) );
        }
        return;
    }
    const bool          quoteHere = inQuote || std::strcmp( type, "block_quote" ) == 0;   // a quoted heading is
    const std::uint32_t n         = ts_node_named_child_count( node );                    // quoted content, not structure
    for( std::uint32_t i = 0; i < n; ++i )
    {
        mdWalk( ts_node_named_child( node, i ), src, quoteHere, depth + 1, out );
    }
}

} // namespace mdtier

void extractMarkdown( std::uint32_t fileId, std::string_view src, std::string_view stem, TSNode root,
                      std::vector<RawDef>& defs, std::vector<RawRef>& refs )
{
    using mdtier::MdHeading;

    // (1) file-level node — span [0,size) ⇒ the lexical scorer indexes the whole fact body; cross-file
    // links land here. bodyByte stays 0 (no signature/body split — this node IS the whole doc).
    // nameByte = src.size() (EOF), NOT 0: (fileId, nameByte) is the global dedup identity, and a SETEXT
    // heading whose paragraph opens the file puts its name at byte 0 — with nameByte 0 the file node and
    // that heading TIED on every sort key (same kind, same startByte, and an equal endByte whenever the
    // first heading's span runs to EOF), so std::sort's instability let the unique() survivor flip with
    // worker arrival order (caught 2026-08-12: bench scoreboards flapping in --merge-scout's changed set).
    // No identifier can START at EOF, so this identity is collision-free by construction.
    {
        RawDef d;
        d.fileId = fileId; d.line = 1; d.startByte = 0; d.endByte = std::uint32_t( src.size() );
        d.nameByte = std::uint32_t( src.size() ); d.bodyByte = 0; d.kind = SymKind::Section; d.lang = Lang::Markdown;
        d.name.assign( stem );
        defs.push_back( std::move( d ) );
    }

    mdtier::MdWalkOut walk;
    mdtier::mdWalk( root, src, false, 0, walk );

    // The walk is preorder ⇒ headings and opaque ranges arrive in byte order; VERIFY rather than re-sort
    // (a re-sort would hide a walk-order bug behind deterministic-looking output).
    for( std::size_t i = 1; i < walk.headings.size(); ++i )
    {
        VERIFY( walk.headings[ i - 1 ].startByte <= walk.headings[ i ].startByte );
    }

    // (2) section spans + hierarchy over the MERGED heading list: endByte = next same-or-higher heading's
    // start (else EOF); scope = nearest earlier heading with a strictly shallower level.
    for( std::size_t i = 0; i < walk.headings.size(); ++i )
    {
        MdHeading&    h       = walk.headings[ i ];
        std::uint32_t spanEnd = std::uint32_t( src.size() );
        for( std::size_t j = i + 1; j < walk.headings.size(); ++j )
        {
            if( walk.headings[ j ].level <= h.level )
            {
                spanEnd = walk.headings[ j ].startByte;
                break;
            }
        }
        h.endByte = spanEnd;

        std::string scope;
        for( std::size_t p = i; p > 0; --p )   // p-- in the condition wraps at 0 under -fsanitize=integer (G1)
        {
            if( walk.headings[ p - 1 ].level < h.level )
            {
                scope = walk.headings[ p - 1 ].name;
                break;
            }
        }

        RawDef d;
        d.fileId    = fileId;
        d.line      = h.line;
        d.startByte = h.startByte;
        d.endByte   = spanEnd;
        d.nameByte  = h.nameByte;
        d.bodyByte  = h.sigEnd;    // signature = the heading construct; [bodyByte, endByte) = the section body
        d.kind      = SymKind::Section;
        d.lang      = Lang::Markdown;
        d.name      = h.name;
        d.scope     = std::move( scope );
        defs.push_back( std::move( d ) );
    }

    // opaque-range membership for the line scan below. Ranges arrive in byte order and never nest (every
    // opaque node type is a leaf block for the walk), so a linear cursor suffices.
    const auto& opaque       = walk.opaque;
    std::size_t opaqueCursor = 0;
    const auto  inOpaque     = [ & ]( std::uint32_t pos ) noexcept
    {
        while( opaqueCursor < opaque.size() && opaque[ opaqueCursor ].second <= pos ) { ++opaqueCursor; }
        return opaqueCursor < opaque.size() && opaque[ opaqueCursor ].first <= pos;
    };

    // link-target handling shared by inline links, reference definitions and (via slug) anchors.
    // Cross-file: [x](other.md) / [x](../a/other.md#frag) → ref named by the target's STEM (the resolve
    // ladder's same-dir preference lands it on other.md's file node, exactly like [[other]]). Anchors:
    // [x](#slug) → pending, resolved against THIS file's headings once they are all known.
    std::vector<std::pair<std::uint32_t, std::string>> pendingAnchors;   // (refByte, slug)
    const auto emitLinkTarget = [ & ]( std::string_view target, std::uint32_t refByte )
    {
        if( target.size() >= 2 && target.front() == '<' && target.back() == '>' )
        {
            target = target.substr( 1, target.size() - 2 );
        }
        if( const std::size_t sp = target.find_first_of( " \t" ); sp != std::string_view::npos )
        {
            target = target.substr( 0, sp );   // a following "title" is not part of the destination
        }
        if( target.empty() )
        {
            return;
        }
        if( target.front() == '#' )
        {
            std::string slug;
            for( const char c : target.substr( 1 ) ) { slug += ( c >= 'A' && c <= 'Z' ) ? char( c - 'A' + 'a' ) : c; }
            pendingAnchors.emplace_back( refByte, std::move( slug ) );
            return;
        }
        if( const std::size_t frag = target.find( '#' ); frag != std::string_view::npos )
        {
            target = target.substr( 0, frag );   // cross-file anchor part deferred (stem edge only, disclosed)
        }
        const bool isMd = target.size() > 3 && ( target.ends_with( ".md" ) || target.ends_with( ".markdown" ) );
        if( !isMd )
        {
            return;   // http/image/other targets are not doc→doc edges
        }
        const std::size_t slash = target.find_last_of( '/' );
        std::string_view  base  = ( slash == std::string_view::npos ) ? target : target.substr( slash + 1 );
        base = base.substr( 0, base.rfind( '.' ) );
        if( !base.empty() )
        {
            RawRef r;
            r.fileId = fileId; r.startByte = refByte; r.lang = Lang::Markdown; r.isInherit = false;
            r.name.assign( base );
            refs.push_back( std::move( r ) );
        }
    };

    // (4)+(5) the inline line scan: `backtick` mentions and [text](target) links — outside every opaque
    // range. Line-based exactly as before the grammar landed; the AST replaces only the hand-rolled fence
    // toggle (which knew ```/~~~ but not html blocks, front-matter or indented code).
    for( std::size_t i = 0; i < src.size(); )
    {
        const std::size_t lineStart = i;
        std::size_t       j         = i;
        while( j < src.size() && src[ j ] != '\n' )
        {
            ++j; // [lineStart, j) = this line, no newline
        }
        if( inOpaque( std::uint32_t( lineStart ) ) )
        {
            i = ( j < src.size() ) ? j + 1 : j;
            continue;
        }
        std::string_view line = src.substr( lineStart, j - lineStart );
        if( !line.empty() && line.back() == '\r' )
        {
            line.remove_suffix( 1 ); // CRLF: drop the trailing CR — LF/CRLF byte-identity
        }

        // inline-code `identifiers` → doc→code mentions; resolved to real code symbols in buildGraph
        // (stored in g.mentions, OUT of the call graph). Accepts only clean idents (len≥3).
        for( std::size_t b = 0; b + 1 < line.size(); )
        {
            if( line[ b ] != '`' ) { ++b; continue; }
            std::size_t e = b + 1;
            while( e < line.size() && line[ e ] != '`' )
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
            { const char ch = span[ k ]; ok = ( ch >= 'A' && ch <= 'Z' ) || ( ch >= 'a' && ch <= 'z' ) || ( ch >= '0' && ch <= '9' ) || ch == '_'; }
            if( ok )
            {
                RawRef rr;
                rr.fileId = fileId;  rr.startByte = std::uint32_t( lineStart + b );  rr.lang = Lang::Markdown;
                rr.isInherit = false;  rr.isDocLink = true;  rr.name.assign( span );
                refs.push_back( std::move( rr ) );
            }
            b = e + 1;
        }

        // [text](target) links (images ride along; non-.md targets drop in emitLinkTarget). [[wikilinks]]
        // are NOT handled here — their own scan below keeps its historical shape.
        for( std::size_t b = 0; b + 1 < line.size(); ++b )
        {
            if( line[ b ] != '[' )
            {
                continue;
            }
            if( line[ b + 1 ] == '[' )
            {
                ++b;   // a [[wikilink]] — skip both brackets so its inner text is not read as a link
                continue;
            }
            const std::size_t close = line.find( ']', b + 1 );
            if( close == std::string_view::npos )
            {
                break;
            }
            if( close + 1 < line.size() && line[ close + 1 ] == '(' )
            {
                const std::size_t rp = line.find( ')', close + 2 );
                if( rp != std::string_view::npos )
                {
                    emitLinkTarget( line.substr( close + 2, rp - close - 2 ), std::uint32_t( lineStart + b ) );
                    b = rp;
                    continue;
                }
            }
            b = close;
        }

        if( j < src.size() )
        {
            i = j + 1;
        }
        else
        {
            i = j;
        }
    }

    // reference-style definitions ([label]: target) — destinations straight off the AST.
    for( const auto& [ da, db ] : walk.refDefs )
    {
        emitLinkTarget( src.substr( da, db - da ), da );
    }

    // (5b) [[wikilink]] edges: [[slug]] / [[slug|text]] / [[slug#sec]] → a ref from this file's node to
    // the node named `slug`. The resolver makes it a same-dir file→file edge; dangling links drop.
    // Opaque-aware now: a [[link]] inside a fence/html block/front-matter is quoted text, not an edge.
    {
        std::size_t wikiCursor = 0;   // the shared inOpaque cursor is already past EOF — use a fresh one
        const auto  wikiOpaque = [ & ]( std::uint32_t pos ) noexcept
        {
            while( wikiCursor < opaque.size() && opaque[ wikiCursor ].second <= pos ) { ++wikiCursor; }
            return wikiCursor < opaque.size() && opaque[ wikiCursor ].first <= pos;
        };
        for( std::size_t i = 0; i + 1 < src.size(); ++i )
        {
            if( src[ i ] != '[' || src[ i + 1 ] != '[' || wikiOpaque( std::uint32_t( i ) ) )
            {
                continue;
            }
            const std::size_t open = i + 2;
            std::size_t       e    = open;
            while( e + 1 < src.size() && src[ e ] != '\n' && !( src[ e ] == ']' && src[ e + 1 ] == ']' ) )
            {
                ++e;
            }
            if( e + 1 >= src.size() || src[ e ] != ']' || src[ e + 1 ] != ']' ) { i = e; continue; }   // no closing ]] on this line
            std::string_view slug = src.substr( open, e - open );
            for( std::size_t k = 0; k < slug.size(); ++k )
            {
                if( slug[ k ] == '|' || slug[ k ] == '#' )
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

    // (5c) anchors: [x](#slug) → the heading whose GitHub slug matches, in THIS file (first match wins on
    // a collision — GitHub's -1/-2 suffixes are not modelled). Dangling anchors drop, like wikilinks.
    for( const auto& [ refByte, slug ] : pendingAnchors )
    {
        for( const MdHeading& h : walk.headings )
        {
            if( mdtier::mdSlugOf( h.name ) == slug )
            {
                RawRef r;
                r.fileId = fileId; r.startByte = refByte; r.lang = Lang::Markdown; r.isInherit = false;
                r.name = h.name;
                refs.push_back( std::move( r ) );
                break;
            }
        }
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

// First DIRECT child of `n` whose node type is `type`, or a null node when none exists — the one
// child-scan shape shared by the using-declaration keyword guard below and the phantom-`::` probe
// (hasPhantomScopeSeparator), so the two cannot drift into near-clones of each other.
inline TSNode firstChildOfType( TSNode n, const char* type ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( n );
    for( std::uint32_t i = 0; i < childCount; ++i )
    {
        const TSNode child = ts_node_child( n, i );
        if( std::strcmp( ts_node_type( child ), type ) == 0 )
        {
            return child;
        }
    }
    return TSNode {};
}

// using-declaration re-exports (r9 loss bucket 1): TRUE when a C++ `using_declaration` node is a grammar
// KEYWORD form rather than a single-symbol re-export — `using namespace ns;` (its qualified spelling
// `using namespace lib::nested;` carries a qualified_identifier and so matches the tags pattern) or
// `using enum E;` (C++20; re-exports the ENUMERATORS, not the named type, so an import row for the type
// would over-claim). Both are VALID INPUT, skipped at capture time exactly like the cast keywords above:
// the grammar puts the keyword in an anonymous child with no field name, which a tags-query pattern
// cannot negate (passesPredicates is wired into --match/--lint only, never the tags pass).
inline bool usingDeclarationIsDirective( TSNode n ) noexcept
{
    return !ts_node_is_null( firstChildOfType( n, "namespace" ) ) || !ts_node_is_null( firstChildOfType( n, "enum" ) );
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
    const TSNode sep = firstChildOfType( qualified, "::" );
    return !ts_node_is_null( sep ) && ts_node_is_missing( sep );   // no separator child at all → pre-existing behaviour untouched (false)
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

// Was this @name bound through an init_declarator (the r3 q10 initialized-binding patterns), or through
// the UNINITIALIZED CUDA memory-space patterns (cudacheck §7b close-out)? The two pattern families share
// one capture name, and pattern_index would be brittle against .scm reordering — the name node's ancestry
// up to the captured declaration is the robust discriminator.
inline bool nameBoundByInitDeclarator( TSNode nameNode, TSNode declNode ) noexcept
{
    for( TSNode walk = ts_node_parent( nameNode ); !ts_node_is_null( walk ) && !ts_node_eq( walk, declNode ); walk = ts_node_parent( walk ) )
    {
        if( std::strcmp( ts_node_type( walk ), "init_declarator" ) == 0 )
        {
            return true;
        }
    }
    return false;
}

// The one direct-child token scanner behind the three qualifier tests below (CUDA memory-space,
// const evidence, static storage). Filters `node`'s DIRECT children to named `namedChildType` nodes
// — plus, when acceptAnonymousToken, anonymous token children (the CUDA `__device__` shape, which
// tree-sitter-cuda parses as an anonymous child; see cudaMemorySpaceQualifierOf's contract note) —
// and returns the first child whose source text is one of `tokens` ("" = none).
inline std::string_view childTokenAmong( TSNode node, std::string_view src, const char* namedChildType, bool acceptAnonymousToken, std::initializer_list<std::string_view> tokens ) noexcept
{
    const std::uint32_t childCount = ts_node_child_count( node );
    for( std::uint32_t childIx = 0; childIx < childCount; ++childIx )
    {
        const TSNode child   = ts_node_child( node, childIx );
        const bool   isNamed = ts_node_is_named( child );
        if( isNamed && std::strcmp( ts_node_type( child ), namedChildType ) != 0 )
        {
            continue;
        }
        if( !isNamed && !acceptAnonymousToken )
        {
            continue;
        }
        const std::uint32_t beginByte = ts_node_start_byte( child );
        const std::uint32_t endByte   = ts_node_end_byte( child );
        if( endByte > src.size() || beginByte >= endByte )
        {
            continue;
        }
        const std::string_view text = src.substr( beginByte, endByte - beginByte );
        for( const std::string_view token : tokens )
        {
            if( text == token )
            {
                return text;
            }
        }
    }
    return {};
}

// CUDA memory-space qualifier of a module-scope declaration ("" = none). The uninitialized-declaration
// patterns in queries/cpp/tags.scm are STRUCTURAL and unconstrained on purpose — that query also
// compiles against tree-sitter-cpp (.cpp/.h/.metal), which has no `__constant__` token, so naming it
// there would make ts_query_new reject the whole query; tags-pass predicates never run (measured; see
// the cast-keyword note in tags.scm); and a `(type_qualifier)` child constraint cannot see `__device__`
// anyway — tree-sitter-cuda parses `__constant__`/`__managed__` as NAMED type_qualifier nodes but
// `__device__` as an ANONYMOUS token child of the declaration. The qualifier test therefore lives here,
// isCppCastKeyword's home, scanning ALL children and accepting the three spellings from exactly two node
// shapes: a named type_qualifier, or an anonymous token. The anonymous-only restriction on the second
// arm is a correctness guard, not pedantry: tree-sitter-cpp error-recovers `__device__ float x;` in a
// plain .cpp by parsing `__device__` as a NAMED type_identifier — text alone would false-positive there.
// This function is what makes the unconstrained patterns safe: every non-CUDA raw match returns "" and
// drops. Verified the strong way on the 2026-08-10 port round — the full maps of ripwire's own src/ and
// of four real C++/CUDA trees (xformers 6e10bd2, dgl f0b7cc9, MONAI 052dbb4, transformers 343c8cb86)
// are byte-identical to the pre-port binary's except for rows carrying a memory-space qualifier in a
// .cu/.cuh. (Measurement trap, recorded so it isn't re-tripped: baseline against a build of the tree you
// started from, never the PATH-installed ripwire, which can predate the r3 q10 patterns entirely.)
inline std::string_view cudaMemorySpaceQualifierOf( TSNode declNode, std::string_view src ) noexcept
{
    return childTokenAmong( declNode, src, "type_qualifier", /*acceptAnonymousToken=*/true, { "__constant__", "__device__", "__managed__" } );
}

// Does this C-family declaration (or field_declaration) carry const evidence — a `const` /
// `constexpr` / `constinit` type_qualifier as a DIRECT child? The keyword, not the name case, is
// what marks a deliberate module constant (the Rust const_item rationale, already applied to CUDA
// `__constant__` above), and it is what the 2026-08-12 census said agents actually hunt: 613 of
// 2 870 symbol-name lookups were constant-shaped, and this repo's own `constexpr std::uint32_t
// kParserVer` was invisible to its own `--for`/`--uses` because the r3 q10 gate is SCREAMING-only.
// Direct children only, on purpose: a declaration-level qualifier (`const char* k = …`, east-const
// `int const k = …`, `static const int k = …`) is the module-constant shape; a qualifier nested
// inside a pointer_declarator (`char* const k = …`, a const POINTER) stays outside this test and
// keeps the old SCREAMING-only behavior — a disclosed boundary, not a silent miss. `consteval` is
// function-only and cannot appear here; `volatile`/`restrict`/`_Atomic` are not const evidence.
inline bool declarationCarriesConstQualifier( TSNode declNode, std::string_view src ) noexcept
{
    return !childTokenAmong( declNode, src, "type_qualifier", /*acceptAnonymousToken=*/false, { "const", "constexpr", "constinit" } ).empty();
}

// The keep decision for the class-static-constant field_declaration captures (queries/cpp/tags.scm,
// module-constant round). The pattern is deliberately loose — it matches EVERY default-member-
// initializer, because tags-pass predicates never run and static/constexpr child order is free — so
// this is where the real contract lives: keep iff the field carries BOTH a `static`
// storage_class_specifier AND a const/constexpr/constinit type_qualifier. That keeps
// `static constexpr int kMaxDepth = 3;` case-blind (one per-class constant, the census target) and
// drops the two per-instance shapes the fixture pins as negatives: a plain default-initialized
// member (`int retries = 3;` — no static, no const) and a const NON-static member (`const int x = 1;`
// — per-instance state that happens to be immutable, not a class constant).
inline bool fieldConstantCaptureKept( TSNode fieldDeclNode, std::string_view src ) noexcept
{
    const bool isStaticMember = !childTokenAmong( fieldDeclNode, src, "storage_class_specifier", /*acceptAnonymousToken=*/false, { "static" } ).empty();
    return isStaticMember && declarationCarriesConstQualifier( fieldDeclNode, src );
}

// forward declarations for dropGatedCapture below — the helpers live after nodeTextOf's section.
inline bool isCjsExportTarget( TSNode nameNode, std::string_view src ) noexcept;
inline bool isPrototypeMemberTarget( TSNode nameNode, std::string_view src ) noexcept;
inline bool isPyEnumMemberTarget( TSNode nameNode, std::string_view src ) noexcept;

// The @definition.constant drop decision, in its own function for the same reason isCjsExportTarget and
// isPyEnumMemberTarget have theirs: dropGatedCapture is a dispatcher, and this is the one arm with a
// policy rather than a predicate. r3 q10 gates on SCREAMING_SNAKE; the §7b close-out adds the CUDA
// memory-space policy, C++ ONLY, as ONE decision covering both declaration shapes queries/cpp/tags.scm
// now captures. `__constant__` keeps case-blind whether initialized or not (constant by construction:
// device-read-only, host-filled via cudaMemcpyToSymbol or an initializer — the Rust const_item
// rationale; measured against NVIDIA/cuda-samples, where dxtc's initialized `kColorMetric = {…}` and
// bilateralFilter's uninitialized `cGaussian[64]` are the same kind of table). `__device__`/`__managed__`
// are MUTABLE device globals and keep only under the convention gate. An uninitialized capture with NO
// memory-space qualifier drops — the extern-const/static/alignas/volatile shape plain C++ produces by the
// hundred, which reaches here ONLY through the new structural patterns.
//
// The C-family narrowing is load-bearing, NOT a restatement of the old gate's language set:
// nameBoundByInitDeclarator is a C-family node test, and the other gated languages bind their
// @definition.constant through variable_declarator (TS/JS), field_declaration (Java/C#) or a bare
// assignment (Ruby) — every one of them would read "uninitialized" here and, having no memory-space
// qualifier either, drop WHOLESALE. Lang::C takes its own arm (module-constant round, 2026-08-12):
// queries/c/tags.scm still has no uninitialized pattern, so const-evidence-or-SCREAMING on the
// initialized shape is C's whole decision. (The 2026-08-10 measurement below predates that arm and
// pinned the CUDA port's zero-regression claim: byte-identical maps on ripwire's own src/ and 0
// added / 0 REMOVED rows on cpython 8463cb5, numpy a905925, meson f0851c9e, xformers 6e10bd2,
// dgl f0b7cc9 and transformers 343c8cb86 — ~250K symbol rows of C/C++. The module-constant round
// deliberately ADDS rows on those trees — const-qualified camel constants — which is the fix, and
// test/moduleconstcheck.sh is the gate that measures it.)
inline bool dropConstantCapture( Lang lang, std::string_view name, TSNode nameNode, TSNode roleNode, std::string_view src ) noexcept
{
    // MODULE-CONSTANT ROUND (2026-08-12): in the C family, a const/constexpr/constinit qualifier on the
    // captured declaration keeps the binding CASE-BLIND — the keyword is the evidence, exactly the
    // `__constant__` / Rust const_item rationale below. C first: its tags.scm binds only initialized
    // file-scope declarations, so const evidence (or the r3 q10 SCREAMING convention) is the whole test.
    if( lang == Lang::C )
    {
        return !( isScreamingSnakeName( name ) || declarationCarriesConstQualifier( roleNode, src ) );
    }
    if( lang != Lang::Cpp )
    {
        return constCaptureNeedsScreamingGate( lang ) && !isScreamingSnakeName( name );
    }
    // Class-static constants bind through a field_declaration (the loose default_value pattern), never
    // through init_declarator — their whole keep contract lives in fieldConstantCaptureKept.
    if( std::strcmp( ts_node_type( roleNode ), "field_declaration" ) == 0 )
    {
        return !fieldConstantCaptureKept( roleNode, src );
    }
    // Cost ordering: the common plain-C++ case (initialized + SCREAMING) resolves before any node scan,
    // and the qualifier/CUDA scans run only for non-SCREAMING names or the uninitialized CUDA patterns.
    const bool initialized = nameBoundByInitDeclarator( nameNode, roleNode );
    if( initialized && ( isScreamingSnakeName( name ) || declarationCarriesConstQualifier( roleNode, src ) ) )
    {
        return false;                                                    // r3 q10 convention keep, or const-keyword evidence
    }
    const std::string_view memSpace = cudaMemorySpaceQualifierOf( roleNode, src );
    if( memSpace == "__constant__" )
    {
        return false;                                                    // constant by construction — case-blind
    }
    if( initialized )
    {
        return true;                                                     // initialized MUTABLE non-SCREAMING global
    }
    return !( !memSpace.empty() && isScreamingSnakeName( name ) );        // uninitialized: __device__/__managed__ gated
}

// YAML's @definition.yamlkey gate — the yaml tier's one in-C++ predicate (see queries/yaml/tags.scm's
// header for why the depth cut cannot live in the query: sequence nesting between a pair and its
// document is unbounded, so no finite pattern set expresses it, and tags-pass predicates never run).
// A mapping key is a symbol iff its MAPPING depth is <= 2 — block and flow mappings counted alike
// (flow is a presentation style of the same mapping node), sequences counted NOT AT ALL (sequence
// transparency: 25.3% of real keys sit directly inside a sequence element — the steps:/containers:/
// tasks: shape — and a root-depth rule drops every one of them; 44.0% captured vs JSON's-rule 27.1%,
// measured on the 90-repo breadth corpus). Depth = the number of mapping nodes on the ancestor chain
// from the pair to the root, the pair's own mapping included; multi-document streams need no special
// case because documents never nest. The merge key `<<` (0.22% of files) is the one TEXTUAL drop —
// it parses as an ordinary plain_scalar key and a symbol named `<<` helps nobody. Alias-as-key
// (measured 0 in 4 449 files) and explicit block-node keys are dropped STRUCTURALLY by the query's
// scalar-only alternation and never reach here.
inline bool yamlKeyCaptureDropped( std::string_view name, TSNode roleNode ) noexcept
{
    if( name == "<<" )
    {
        return true;
    }
    std::uint32_t mappingDepth = 0;
    for( TSNode p = roleNode; !ts_node_is_null( p ); p = ts_node_parent( p ) )
    {
        const char* pt = ts_node_type( p );
        if( std::strcmp( pt, "block_mapping" ) == 0 || std::strcmp( pt, "flow_mapping" ) == 0 )
        {
            if( ++mappingDepth > 2u )
            {
                return true;
            }
        }
    }
    return false;
}

// The whole drop decision for every GATED definition capture, kept out of captureTagsFacts (which is
// already the file's densest dispatch point) behind ONE call, keyed on the @definition capture's own
// name. @definition.constant delegates to dropConstantCapture above (r3 q10's SCREAMING_SNAKE gate plus
// the §7b CUDA memory-space policy); @definition.enummember (the Python shape round,
// test/pyshapecheck.sh) drops when the enclosing class's base NAME is not an enum family;
// @definition.cjsexport / @definition.protomethod (the JS shape round, test/jsshapecheck.sh) drop when
// the LEFT side is not really exports/module.exports/.prototype. — the query captures every `a.b = fn`
// shape and cannot text-test, because tags-pass predicates never run (see constCaptureNeedsScreamingGate
// above).
inline bool dropGatedCapture( std::string_view defCapSv, Lang lang, std::string_view name, TSNode nameNode, TSNode roleNode, std::string_view src ) noexcept
{
    if( defCapSv == "definition.constant" )
    {
        return dropConstantCapture( lang, name, nameNode, roleNode, src );
    }
    if( defCapSv == "definition.cjsexport" )
    {
        return !isCjsExportTarget( nameNode, src );
    }
    if( defCapSv == "definition.protomethod" )
    {
        return !isPrototypeMemberTarget( nameNode, src );
    }
    if( defCapSv == "definition.enummember" )
    {
        return !isPyEnumMemberTarget( nameNode, src );
    }
    if( defCapSv == "definition.yamlkey" )
    {
        return yamlKeyCaptureDropped( name, roleNode );
    }
    if( defCapSv == "definition.macro" )
    {
        // macro-edges round: an EMPTY-body function-like `#define NOOP(x)` defines nothing callable — drop
        // it before it mints a symbol. The @name capture's parent IS the preproc node; object-like
        // preproc_def and Rust macro_definition fail the node-type test and are never gated.
        const TSNode defineNode = ts_node_parent( nameNode );
        return !ts_node_is_null( defineNode )
            && std::strcmp( ts_node_type( defineNode ), "preproc_function_def" ) == 0
            && !preprocFunctionDefHasBody( defineNode, src );
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

// Python shape round (test/pyshapecheck.sh): `NAME = value` in a class body is a definition only when
// the class IS an enum table — otherwise it is the plain data attr the tags.scm scope line keeps out
// (12 131 django sites, re-measured 2026-08-10 at @c334c1a8ff). Enum-ness is read off the base NAME
// list (the class_definition's `superclasses` argument_list): the stdlib enum family plus django's
// Choices family, which is enum.Enum-derived and carries the bulk of django's own member sites.
// A base the name does not reveal (a subclass-of-a-subclass behind an alias) stays out: base names
// are checked statically, never resolved — the gate pins that direction too.
inline bool isPyEnumMemberTarget( TSNode nameNode, std::string_view src ) noexcept
{
    const TSNode assign = ts_node_parent( nameNode );                                    // assignment
    const TSNode stmt   = ts_node_is_null( assign ) ? assign : ts_node_parent( assign );  // expression_statement
    const TSNode body   = ts_node_is_null( stmt )   ? stmt   : ts_node_parent( stmt );    // block
    const TSNode cls    = ts_node_is_null( body )   ? body   : ts_node_parent( body );    // class_definition
    if( ts_node_is_null( cls ) || std::strcmp( ts_node_type( cls ), "class_definition" ) != 0 )
    {
        return false;
    }
    const TSNode bases = ts_node_child_by_field_name( cls, "superclasses", 12 );
    if( ts_node_is_null( bases ) )
    {
        return false;
    }
    const std::uint32_t baseCount = ts_node_named_child_count( bases );
    for( std::uint32_t baseIndex = 0; baseIndex < baseCount; ++baseIndex )
    {
        TSNode base = ts_node_named_child( bases, baseIndex );
        if( std::strcmp( ts_node_type( base ), "attribute" ) == 0 )                      // models.TextChoices → TextChoices
        {
            base = ts_node_child_by_field_name( base, "attribute", 9 );
            if( ts_node_is_null( base ) )
            {
                continue;
            }
        }
        if( std::strcmp( ts_node_type( base ), "identifier" ) != 0 )
        {
            continue;
        }
        const std::string_view baseName = nodeTextOf( base, src );
        if( baseName == "Enum" || baseName == "IntEnum" || baseName == "StrEnum"
         || baseName == "Flag" || baseName == "IntFlag" || baseName == "ReprEnum"
         || baseName == "Choices" || baseName == "TextChoices" || baseName == "IntegerChoices" )
        {
            return true;
        }
    }
    return false;
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

// ── L3 fn-pointer/callback binding capture helpers ───────────────────────────────────────────────────

// the bound-function TARGET of an initializer/assignment RHS value node, for a var→FUNCTION binding:
//   `&alpha` / `&ns::alpha` (address-of) → "alpha" / "ns::alpha";  `alpha` / `ns::alpha` (bare) → same;
//   `[](){...}` (lambda) → kFnBindLambdaTarget.  "" for everything else (a call, a literal, arithmetic —
// not a recognizable single function). `wasBareIdent` reports the bare-IDENTIFIER shape so the caller can
// apply the primitive-type noise gate (`int a = b;` is almost never a function copy; `H h = beta;` through
// a typedef legitimately is).
inline std::string fnBindTargetOf( TSNode value, std::string_view src, bool& wasBareIdent )
{
    wasBareIdent = false;
    if( ts_node_is_null( value ) )
    {
        return {};
    }
    const char* vt = ts_node_type( value );
    if( std::strcmp( vt, "lambda_expression" ) == 0 )
    {
        return std::string( kFnBindLambdaTarget );
    }
    TSNode idn       = value;
    bool   addressOf = false;
    if( std::strcmp( vt, "pointer_expression" ) == 0 )
    {
        // only the ADDRESS-OF form — `*p` is also a pointer_expression, and a dereference names no function.
        const TSNode op = ts_node_child( value, 0 );
        if( ts_node_is_null( op ) || std::strcmp( ts_node_type( op ), "&" ) != 0 )
        {
            return {};
        }
        idn = ts_node_child_by_field_name( value, "argument", 8 );
        if( ts_node_is_null( idn ) )
        {
            return {};
        }
        addressOf = true;
    }
    const char* it = ts_node_type( idn );
    if( std::strcmp( it, "identifier" ) != 0 && std::strcmp( it, "qualified_identifier" ) != 0 )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( idn ), b = ts_node_end_byte( idn );
    if( a > b || b > src.size() )
    {
        return {};
    }
    wasBareIdent = !addressOf && std::strcmp( it, "identifier" ) == 0;
    return std::string( src.substr( a, b - a ) );
}

// the shape a possibly fn-pointer declarator chain (`(*fn)()` → "fn") presents, descending through
// function/parenthesized/pointer/reference declarators. `sawFn` reports crossing a function_declarator —
// the explicit fn-pointer syntax that licenses a bare-identifier initializer even under a primitive written
// type (`void (*fn)() = handler;`); `sawRef` a reference_declarator (`H& r = fn;`), where the reference
// ALIASES its initializer, so the caller must treat the bound-to variable as ESCAPED (clobbered) and never
// emit a positive for the alias; `sawPtr` a pointer_declarator, which is what separates the two shapes the
// type node alone cannot tell apart — `void (*fp)()` (a fn-pointer VARIABLE: sawFn AND sawPtr) from
// `void fp()` (a function DECLARATION: sawFn alone), which declares no variable at all. declaratorVarName
// (Rule 2) is NOT reused: parenthesized_declarator and reference_declarator carry their inner declarator as
// an UNNAMED child, which a field-only unwrap cannot reach. An array_declarator bails — an ARRAY of fn
// pointers is table territory, never a single-var binding (its indexed call must stay unresolved).
struct FnBindDeclShape
{
    std::string_view name;
    bool             sawFn  = false;
    bool             sawPtr = false;
    bool             sawRef = false;
};

inline FnBindDeclShape fnDeclaratorShape( TSNode decl, std::string_view src )
{
    FnBindDeclShape shape;
    for( int guard = 0; guard < 10 && !ts_node_is_null( decl ); ++guard )
    {
        const char* dt = ts_node_type( decl );
        if( std::strcmp( dt, "identifier" ) == 0 )
        {
            const std::uint32_t a = ts_node_start_byte( decl ), b = ts_node_end_byte( decl );
            shape.name = ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
            return shape;
        }
        if( std::strcmp( dt, "array_declarator" ) == 0 )
        {
            return shape;
        }
        const bool isRef = ( std::strcmp( dt, "reference_declarator" ) == 0 );
        shape.sawFn  = shape.sawFn  || std::strcmp( dt, "function_declarator" ) == 0;
        shape.sawPtr = shape.sawPtr || std::strcmp( dt, "pointer_declarator" ) == 0;
        shape.sawRef = shape.sawRef || isRef;
        TSNode inner = ts_node_child_by_field_name( decl, "declarator", 10 );
        if( ts_node_is_null( inner ) && ( isRef || std::strcmp( dt, "parenthesized_declarator" ) == 0 ) )
        {
            // the parenthesized/reference inner declarator is an UNNAMED child — take the first named one
            if( ts_node_named_child_count( decl ) > 0 )
            {
                inner = ts_node_named_child( decl, 0 );
            }
        }
        if( ts_node_is_null( inner ) )
        {
            return shape;
        }
        decl = inner;
    }
    return shape;
}

// tree-sitter-cpp MIS-PARSES a raw fn-pointer declaration inside a function body —
// `void (*fn)() = &alpha;` — as an assignment_expression whose LEFT is
//   call_expression( function: call_expression( function: primitive_type, arguments: ((*fn)) ), arguments: () )
// (the C grammar parses the same statement as a true declaration; only C++ takes the expression branch —
// ground-truthed with an AST dump against the vendored grammars, 2026-08-08). Decode the variable name from
// that shape. The inner callee must be a PRIMITIVE type — `void(...)` is never callable, so the shape is
// unambiguous evidence of a declaration; an identifier callee (`H (*g)()`, but equally REAL code
// `foo(*p)() = x;` assigning through a call result) stays undecoded — conservative, no false binding.
inline std::string_view misparsedFnPtrDeclVar( TSNode lhs, std::string_view src )
{
    if( ts_node_is_null( lhs ) || std::strcmp( ts_node_type( lhs ), "call_expression" ) != 0 )
    {
        return {};
    }
    const TSNode inner = ts_node_child_by_field_name( lhs, "function", 8 );
    if( ts_node_is_null( inner ) || std::strcmp( ts_node_type( inner ), "call_expression" ) != 0 )
    {
        return {};
    }
    const TSNode ty = ts_node_child_by_field_name( inner, "function", 8 );
    if( ts_node_is_null( ty ) || std::strcmp( ts_node_type( ty ), "primitive_type" ) != 0 )
    {
        return {};
    }
    const TSNode args = ts_node_child_by_field_name( inner, "arguments", 9 );
    if( ts_node_is_null( args ) || ts_node_named_child_count( args ) != 1 )
    {
        return {};
    }
    const TSNode pe = ts_node_named_child( args, 0 );
    if( std::strcmp( ts_node_type( pe ), "pointer_expression" ) != 0 )
    {
        return {};
    }
    const TSNode op = ts_node_child( pe, 0 );
    if( ts_node_is_null( op ) || std::strcmp( ts_node_type( op ), "*" ) != 0 )
    {
        return {};
    }
    const TSNode idn = ts_node_child_by_field_name( pe, "argument", 8 );
    if( ts_node_is_null( idn ) || std::strcmp( ts_node_type( idn ), "identifier" ) != 0 )
    {
        return {};
    }
    const std::uint32_t a = ts_node_start_byte( idn ), b = ts_node_end_byte( idn );
    return ( a <= b && b <= src.size() ) ? src.substr( a, b - a ) : std::string_view{};
}

// L3: an assignment whose RHS is not a recognizable single function — a CLOBBER site, emitted as a
// kFnBindClobberTarget record at the end of the walk IF the var has a fn binding in the same file.
struct FnBindClobber
{
    std::string   var;
    std::uint32_t startByte = 0;
};

// ── L3 VALUE-ASSIGNMENT NOISE GATE (r9 fix round) ────────────────────────────────────────────────────
// The DECLARATION arm gates its bare-identifier initializer on the written type (`int a = b;` is a copy,
// not a function). The ASSIGNMENT arm carries no type node at all, so before this gate EVERY `x = y;` with
// a bare-identifier RHS minted an FnAssign — `std::string line; line = zzz;` included. Two measured harms,
// both from a binding that names no function anybody could call: shadowSuppressedSite VETOES local-shadow
// suppression for any name carrying an L3 binding (calls THROUGH a bound variable must keep resolving), so
// the local handed its every read/write back to the function it shadows; and buildFnPtrBindTables' file-
// scope sweep keys FnAssign records by VAR NAME ALONE across the whole corpus, so one bogus record
// TOMBSTONED a genuine, never-clobbered file-scope binding of the same name in an unrelated file.
// The gate asks the file's own declarations of that name what the variable IS:
//   * PROVEN VALUE — declared with a concrete written type that is no function-pointer alias → the
//     assignment is a copy: no positive, a CLOBBER instead (exactly what `fn = getHandler()` records),
//     inert unless the name holds a real binding here and correctly tombstoning it when it does;
//   * FN-CAPABLE — a fn-pointer declarator (`void (*fp)()`) or a fn-pointer alias type (`H fp;`) → mint,
//     and this wins over any value evidence for the same name (recall-safe when a file reuses a name);
//   * NEITHER — `auto`, `decltype`, a template type, or a name this file never declares (a global, a
//     member, an extern): UNKNOWN, and unknown MINTS, exactly as before. When in doubt, don't gate.
// File-scoped and name-based, like every other L3 table: evidence from one function's declarations reaches
// another's assignment of the same name. That over-approximation runs toward NOT minting a binding, which
// is the side that can only cost a disclosed edge, never invent one. Address-of (`fn = &beta`) and lambda
// RHS forms are self-evidencing and never reach the gate.
// Each fact carries the DEFINITION it was declared inside, so one file declaring `std::string run;` in one
// function and `void (*run)();` in another gets both answers right; a file-scope declaration carries {0,0}
// and applies everywhere. This is a function-granular scope, deliberately coarser than the shadow spans in
// model.h — it decides what a NAME can hold, not which sites a declaration claims.
struct FnBindVarTypeFact
{
    std::string   var;
    std::string   typeName;              // final segment of a WRITTEN type name; "" for the unnamed kinds
    std::uint32_t scopeStart   = 0;      // the enclosing definition's byte span; {0,0} = file scope
    std::uint32_t scopeEnd     = 0;
    bool        concreteType  = false;   // the type node's spelling FIXES the type (never auto/decltype/template)
    bool        fnPtrVariable = false;   // the declarator chain is a function POINTER, not a plain value
};

// a bare-identifier assignment held back until the walk ends, when the file's full declaration evidence —
// including declarations the DFS has not reached yet — decides whether it mints a binding or a clobber.
// Deferring is what keeps the verdict independent of walk order, and so of the AST's shape.
struct PendingFnBindAssign
{
    std::string   var;
    std::string   target;
    std::uint32_t startByte = 0;
};

// a bare-identifier DECLARATION initializer held back the same way, and for one reason only: the fn-pointer
// ALIAS table is not complete until the walk ends, and a `typedef void (*H)();` written BELOW `H fp = beta;`
// is the difference between a binding and a copy. Unlike its assignment sibling this record carries its own
// verdict material — the declaration's WRITTEN TYPE, read straight off the node — because a declaration IS
// the variable and needs no file-wide fact lookup to say what it holds.
struct PendingFnBindDecl
{
    std::string   var;
    std::string   target;
    std::string   typeName;              // final segment of the written type; "" for the unnamed concrete kinds
    std::uint32_t startByte    = 0;
    bool          concreteType = false;  // the spelling FIXES the type (never auto/decltype/template)
};

// the gate's whole per-file state: the declared-variable type facts, the file's function-pointer type
// aliases, and the assignments AND declarations held back until both of those are complete. One object
// because they have no independent life — filled by one walk and spent together the moment it ends.
struct FnBindGateState
{
    std::vector<FnBindVarTypeFact>   facts;
    std::vector<PendingFnBindAssign> pending;
    std::vector<PendingFnBindDecl>   pendingDecl;
    HashMap<std::string, char>       aliases;
};

// true when a `type:` field node is a CONCRETE written type — one whose spelling alone fixes what the
// variable is. `name` receives the final segment for the NAMED kinds (the only ones a typedef can make a
// function pointer); the built-in and class/enum-body kinds can never be one and leave it empty. Everything
// else — `auto`, `decltype`, and any type carrying TEMPLATE ARGUMENTS — is dependent, not concrete: the
// spelling of `std::function<void()>` says nothing about callability the way `std::string` does.
inline bool concreteWrittenType( TSNode typeNode, std::string_view src, std::string& name )
{
    name.clear();
    if( ts_node_is_null( typeNode ) )
    {
        return false;
    }
    const char* tt = ts_node_type( typeNode );
    if( std::strcmp( tt, "primitive_type" ) == 0 || std::strcmp( tt, "sized_type_specifier" ) == 0
        || std::strcmp( tt, "struct_specifier" ) == 0 || std::strcmp( tt, "class_specifier" ) == 0
        || std::strcmp( tt, "union_specifier" ) == 0 || std::strcmp( tt, "enum_specifier" ) == 0 )
    {
        return true;
    }
    if( std::strcmp( tt, "type_identifier" ) != 0 && std::strcmp( tt, "qualified_identifier" ) != 0
        && std::strcmp( tt, "scoped_type_identifier" ) != 0 )
    {
        return false;
    }
    const std::string_view text = nodeTextOf( typeNode, src );
    if( text.empty() || text.find( '<' ) != std::string_view::npos )
    {
        return false;
    }
    name = finalSegment( text );
    return true;
}

// the TYPE-ALIAS name a node declares for a FUNCTION-POINTER type — `typedef void (*H)();` and
// `using H = void(*)();` both yield "H"; every other typedef/alias yields "". This is the one piece of
// evidence that separates a callable alias from an ordinary class name, both of which reach a declaration
// as a bare `type_identifier`. Same-file only, which is the disclosed limit: an alias declared in a header
// is invisible to a per-file parse, so a variable of that type stays UNKNOWN — and unknown still mints.
inline std::string_view fnPtrAliasName( TSNode n, const char* t, std::string_view src )
{
    if( std::strcmp( t, "alias_declaration" ) == 0 )
    {
        const TSNode desc = ts_node_child_by_field_name( n, "type", 4 );
        if( ts_node_is_null( desc ) )
        {
            return {};
        }
        const TSNode abst = ts_node_child_by_field_name( desc, "declarator", 10 );
        if( ts_node_is_null( abst ) || std::strcmp( ts_node_type( abst ), "abstract_function_declarator" ) != 0 )
        {
            return {};
        }
        const TSNode nm = ts_node_child_by_field_name( n, "name", 4 );
        return ts_node_is_null( nm ) ? std::string_view{} : nodeTextOf( nm, src );
    }
    if( std::strcmp( t, "type_definition" ) != 0 )
    {
        return {};
    }
    const std::uint32_t cc = ts_node_child_count( n );
    for( std::uint32_t i = 0; i < cc; ++i )
    {
        const char* fname = ts_node_field_name_for_child( n, i );
        if( fname == nullptr || std::strcmp( fname, "declarator" ) != 0 )
        {
            continue;
        }
        TSNode d       = ts_node_child( n, i );
        bool   crossed = false;
        for( int guard = 0; guard < 10 && !ts_node_is_null( d ); ++guard )
        {
            const char* dt = ts_node_type( d );
            if( std::strcmp( dt, "type_identifier" ) == 0 )
            {
                return crossed ? nodeTextOf( d, src ) : std::string_view{};
            }
            if( std::strcmp( dt, "function_declarator" ) == 0 )
            {
                crossed = true;
            }
            TSNode inner = ts_node_child_by_field_name( d, "declarator", 10 );
            if( ts_node_is_null( inner ) && ts_node_named_child_count( d ) > 0 )
            {
                inner = ts_node_named_child( d, 0 );
            }
            d = inner;
        }
    }
    return {};
}

// the byte span of the DEFINITION a node sits inside — a function body or a lambda, whichever encloses it
// first. {0,0} at file/namespace/class scope, which the gate reads as "applies everywhere": a file-scope
// variable IS in scope in every function below it.
inline std::pair<std::uint32_t, std::uint32_t> enclosingDefSpan( TSNode n )
{
    TSNode p = ts_node_parent( n );
    for( int guard = 0; guard < 128 && !ts_node_is_null( p ); ++guard )
    {
        const char* pt = ts_node_type( p );
        if( std::strcmp( pt, "function_definition" ) == 0 || std::strcmp( pt, "lambda_expression" ) == 0 )
        {
            return { ts_node_start_byte( p ), ts_node_end_byte( p ) };
        }
        p = ts_node_parent( p );
    }
    return { 0u, 0u };
}

// record one declaration node's type facts — one per DECLARED VARIABLE. Covers the three shapes that
// declare a name a later `x = y;` can target: a block/file `declaration`, a function `parameter_declaration`
// (a value parameter reassigned from another parameter is the same copy), and a `field_declaration`.
inline void collectFnBindTypeFacts( TSNode n, const char* t, std::string_view src, std::vector<FnBindVarTypeFact>& facts )
{
    if( std::strcmp( t, "declaration" ) != 0 && std::strcmp( t, "parameter_declaration" ) != 0
        && std::strcmp( t, "optional_parameter_declaration" ) != 0 && std::strcmp( t, "field_declaration" ) != 0 )
    {
        return;
    }
    std::string typeName;
    const bool  concrete           = concreteWrittenType( ts_node_child_by_field_name( n, "type", 4 ), src, typeName );
    const auto [ scopeStart, scopeEnd ] = enclosingDefSpan( n );
    const std::uint32_t cc = ts_node_child_count( n );
    for( std::uint32_t i = 0; i < cc; ++i )
    {
        const char* fname = ts_node_field_name_for_child( n, i );
        if( fname == nullptr || std::strcmp( fname, "declarator" ) != 0 )
        {
            continue;
        }
        TSNode d = ts_node_child( n, i );
        if( std::strcmp( ts_node_type( d ), "init_declarator" ) == 0 )
        {
            d = ts_node_child_by_field_name( d, "declarator", 10 );
        }
        const FnBindDeclShape shape = fnDeclaratorShape( d, src );
        if( shape.name.empty() || ( shape.sawFn && !shape.sawPtr ) )
        {
            continue;   // nameless, an array of pointers, or a plain function DECLARATION — no variable here
        }
        facts.push_back( { std::string( shape.name ), typeName, scopeStart, scopeEnd, concrete, shape.sawFn && shape.sawPtr } );
    }
}

// the gate's whole per-node collection: a declaration's variable type facts AND, from the same node, any
// function-pointer type alias it declares. `cFamily` is taken rather than checked at the call site so the
// walk carries ONE unconditional line for the evidence — a `declaration` node feeds both the L3 capture
// arms and the type facts here, and a typedef/alias node reaches neither of those arms.
inline void collectFnBindGateEvidence( TSNode n, const char* t, std::string_view src, bool cFamily, FnBindGateState& gate )
{
    if( !cFamily )
    {
        return;
    }
    collectFnBindTypeFacts( n, t, src, gate.facts );
    if( const std::string_view alias = fnPtrAliasName( n, t, src ); !alias.empty() )
    {
        gate.aliases.try_emplace( std::string( alias ), 1 );
    }
}

// the gate's verdict for one assignment: true ⇒ the file PROVED this name is a value variable where the
// assignment sits, so it is a copy and mints no binding. Only facts whose definition span CONTAINS the
// assignment count (plus file-scope ones, which contain everything); among those, fn-pointer evidence wins
// outright, and with no fact at all the name is unknown and the answer is false (mint, exactly as before).
inline bool fnBindProvenValueVar( std::string_view var, std::uint32_t startByte,
                                  const std::vector<FnBindVarTypeFact>& facts,
                                  const HashMap<std::string, char>& fnAliases )
{
    bool proven = false;
    for( const FnBindVarTypeFact& f : facts )
    {
        if( f.var != var )
        {
            continue;
        }
        if( f.scopeEnd != 0u && ( startByte < f.scopeStart || startByte >= f.scopeEnd ) )
        {
            continue;   // declared inside a definition this assignment is not in — a different variable
        }
        const bool aliasTyped = !f.typeName.empty() && fnAliases.find( f.typeName ) != fnAliases.end();
        if( f.fnPtrVariable || aliasTyped )
        {
            return false;
        }
        proven = proven || ( f.concreteType && !aliasTyped );
    }
    return proven;
}

// where a bind-record SITS: its own position (for enclosing-def attribution) plus, on VarDecl records,
// the declaring BLOCK's byte range — the shadow scope model.h's suppressShadowedReferences tests sites
// against ({0,0} on every other kind: contains nothing, inert by construction).
struct BindSite
{
    std::uint32_t startByte = 0;
    std::uint32_t spanStart = 0;
    std::uint32_t spanEnd   = 0;
};

// the ONE bind-record emitter. A nameless declarator records nothing. kind=VarDecl is the r9 shadow-
// evidence record: typeName stays EMPTY on it (shadow evidence, not narrowing fuel — nothing downstream
// ever reads a type off it), so the empty-typeName refusal applies to every OTHER kind, where it is
// load-bearing for Rule 2 (an undecidable type must degrade to §2a, not mint a half-record).
inline void pushRawBind( std::uint32_t fileId, Lang lang, std::string_view var, std::string typeName,
                         BindSite site, LocalBindKind kind, std::vector<RawBind>& binds )
{
    if( var.empty() || ( typeName.empty() && kind != LocalBindKind::VarDecl ) )
    {
        return;
    }
    RawBind b;
    b.fileId    = fileId;
    b.startByte = site.startByte;
    b.lang      = lang;
    b.kind      = kind;
    b.spanStart = site.spanStart;
    b.spanEnd   = site.spanEnd;
    b.var.assign( var );
    b.typeName  = std::move( typeName );
    binds.push_back( std::move( b ) );
}

// emit a Rule-2 binding from one declared variable: prefer the WRITTEN type; else infer from a
// constructor-style initializer (`auto x = Foo()`). Records nothing when neither is decidable.
inline void emitBind( std::uint32_t fileId, Lang lang, std::string_view var, std::string typeName,
                      std::uint32_t startByte, std::vector<RawBind>& binds )
{
    pushRawBind( fileId, lang, var, std::move( typeName ), BindSite{ startByte, 0u, 0u }, LocalBindKind::Type, binds );
}

// the scope a `declaration` node's names shadow within: the byte span, plus whether that span came from a
// PLAIN BLOCK (the only kind the declaration-point narrowing below applies to). {0,0} when nothing encloses
// (file/namespace/class scope): such a record can contain no site and is inert by construction.
struct ShadowScope
{
    std::uint32_t start      = 0;
    std::uint32_t end        = 0;
    bool          plainBlock = false;
};

// r9 shadow fix round (A5, iteration 3): the byte span a declaration's names are scoped to. A declaration
// in a control statement's HEADER — for-init (`for (int run = 0; ...)`), if/while/switch condition
// (`if (int run = f())`) — scopes to THAT STATEMENT's full span (C++: the variable lives for the whole
// statement, else-branch included), NOT the enclosing block: the header declaration is a SIBLING of the
// statement's body, so the plain compound_statement walk of iteration 2 leaked the scope past the loop and
// ate every genuine call after it. A header declaration reaches its control statement BEFORE any
// compound_statement (bodies ARE compound_statements, and C++ forbids a declaration as a braceless body),
// so "first ancestor of either kind wins" needs no field tracking — a body declaration hits the body block
// first, a header declaration the statement first. That same discrimination is what plainBlock reports.
inline ShadowScope enclosingShadowScope( TSNode n )
{
    TSNode p = ts_node_parent( n );
    for( int guard = 0; guard < 128 && !ts_node_is_null( p ); ++guard )
    {
        const char* pt = ts_node_type( p );
        if( std::strcmp( pt, "compound_statement" ) == 0 )
        {
            return { ts_node_start_byte( p ), ts_node_end_byte( p ), true };
        }
        if(    std::strcmp( pt, "for_statement" ) == 0 || std::strcmp( pt, "for_range_loop" ) == 0
            || std::strcmp( pt, "if_statement" ) == 0  || std::strcmp( pt, "while_statement" ) == 0
            || std::strcmp( pt, "switch_statement" ) == 0 )
        {
            return { ts_node_start_byte( p ), ts_node_end_byte( p ), false };
        }
        p = ts_node_parent( p );
    }
    return { 0u, 0u, false };
}

// r9 shadow fix round (A5, iteration 4): where an ordinary block declaration's names START shadowing.
// Iteration 2 started every span at the BLOCK's opening brace, which silently ate a genuine call written
// ABOVE the shadowing local (`key(); int key = 0;` lost the call — verifier attack4, a recall loss, not the
// disclosed over-suppression). THE DECLARATION POINT SHIPPED HERE IS THE END BYTE OF THE COMPLETE
// DECLARATOR, which is C++ [basic.scope.pdecl] exactly: the locus of a declarator is immediately after the
// complete declarator and before its initializer, and a structured binding's is immediately after its
// identifier-list — the outermost declarator's end byte is both. So `int a = probe(), probe = 0, b = probe;`
// keeps the call in a's initializer and suppresses b's read, and `int probe = probe;` suppresses its own
// initializer (which IS the new local, indeterminate value and all). The point itself is exact — a byte
// offset the grammar hands us, not an approximation — so what remains is the floor that was always there
// and is now simply visible ABOVE the point too: a pre-declaration site is only KEPT, never resolved, so if
// the name there denotes an OUTER local rather than the indexed symbol, --uses still name-matches it (the
// header's own "reference-name-based" disclosure). The one declaration this cannot narrow is a declarator
// tree emitShadowVarDecls refuses (`std::string key( tok );`, the most-vexing parse), which records no
// evidence at all and is the disclosed floor already.
// Applies ONLY to a plain block: a control-statement header declaration, and every whole-scope shape
// (definition/lambda/catch parameters, captures, range-for variables), is in scope from the START of its
// scope, so narrowing those would re-mint the false positives iterations 1-3 removed.
inline std::uint32_t shadowSpanStart( const ShadowScope& scope, TSNode completeDeclarator )
{
    if( !scope.plainBlock || ts_node_is_null( completeDeclarator ) )
    {
        return scope.start;
    }
    const std::uint32_t point = ts_node_end_byte( completeDeclarator );
    return point > scope.start ? point : scope.start;
}

// r9 shadow fix round (A5): every VARIABLE name a declarator declares → one VarDecl record each, carrying
// the declaring block's span. Handles the shapes the verifier refuted the first landing on:
//   * reference_declarator / parenthesized_declarator hold their inner declarator as an UNNAMED child
//     (no `declarator` field — same grammar fact fnDeclaratorVarName already works around), so a
//     field-only unwrap missed `const T& key` entirely — pass-by-const-ref, the most idiomatic C++
//     parameter shape;
//   * structured_binding_declarator (`auto& [key, w]`) declares SEVERAL names — one record per identifier;
//   * a plain function declarator still yields NOTHING (`void helper();` in a body and the most-vexing-
//     parse `Foo x();` declare a FUNCTION, whose calls must never be suppressed), while a
//     function_declarator whose inner is PARENTHESIZED is a fn-POINTER variable and stays a variable.
// Conservative by construction: an unrecognized shape captures nothing (under-suppression, the disclosed
// floor — e.g. the ctor-style most-vexing `std::string key( tok );`, which parses as a function decl).
inline void emitShadowVarDecls( std::uint32_t fileId, Lang lang, TSNode decl, std::string_view src,
                                BindSite site, std::vector<RawBind>& binds )
{
    for( int guard = 0; guard < 8 && !ts_node_is_null( decl ); ++guard )
    {
        const char* dt = ts_node_type( decl );
        if( std::strcmp( dt, "identifier" ) == 0 )
        {
            pushRawBind( fileId, lang, nodeTextOf( decl, src ), std::string{}, site, LocalBindKind::VarDecl, binds );
            return;
        }
        if( std::strcmp( dt, "structured_binding_declarator" ) == 0 )
        {
            const std::uint32_t cc = ts_node_named_child_count( decl );
            for( std::uint32_t i = 0; i < cc; ++i )
            {
                const TSNode c = ts_node_named_child( decl, i );
                if( std::strcmp( ts_node_type( c ), "identifier" ) == 0 )
                {
                    pushRawBind( fileId, lang, nodeTextOf( c, src ), std::string{}, site, LocalBindKind::VarDecl, binds );
                }
            }
            return;
        }
        TSNode inner = ts_node_child_by_field_name( decl, "declarator", 10 );
        if( ts_node_is_null( inner )
            && ( std::strcmp( dt, "reference_declarator" ) == 0 || std::strcmp( dt, "parenthesized_declarator" ) == 0 )
            && ts_node_named_child_count( decl ) > 0 )
        {
            inner = ts_node_named_child( decl, 0 );   // the inner declarator is an UNNAMED child here
        }
        if( ts_node_is_null( inner ) )
        {
            return;
        }
        if( std::strcmp( dt, "function_declarator" ) == 0 && std::strcmp( ts_node_type( inner ), "parenthesized_declarator" ) != 0 )
        {
            return;   // a FUNCTION's name, not a variable's
        }
        decl = inner;
    }
}

// one DECLARATOR → both records: the Rule-2 var→type binding and the r9 VarDecl shadow record(s). The two
// name reads stay separate on purpose — declaratorVarName descends into a function declarator (harmless
// for narrowing), emitShadowVarDecls refuses it (load-bearing for suppression).
inline void emitDeclBinds( std::uint32_t fileId, Lang lang, TSNode declNode, std::string_view src, std::string type,
                           BindSite site, std::vector<RawBind>& binds )
{
    emitBind( fileId, lang, declaratorVarName( declNode, src ), std::move( type ), site.startByte, binds );
    emitShadowVarDecls( fileId, lang, declNode, src, site, binds );
}

// one parameter_list → VarDecl records for its named parameters, scoped to the owning BODY's span. Shared
// by the function-definition and lambda arms below (their parameter semantics are identical: names local
// to the body).
inline void emitShadowParamDecls( TSNode params, std::uint32_t fileId, Lang lang, std::string_view src,
                                  BindSite bodySite, std::vector<RawBind>& binds )
{
    const std::uint32_t cc = ts_node_child_count( params );
    for( std::uint32_t i = 0; i < cc; ++i )
    {
        const TSNode p  = ts_node_child( params, i );
        const char*  pt = ts_node_type( p );
        if( std::strcmp( pt, "parameter_declaration" ) != 0 && std::strcmp( pt, "optional_parameter_declaration" ) != 0 )
        {
            continue;   // commas, `...`, attribute nodes — nothing declared
        }
        bodySite.startByte = ts_node_start_byte( p );
        emitShadowVarDecls( fileId, lang, ts_node_child_by_field_name( p, "declarator", 10 ), src, bodySite, binds );
    }
}

// A5 fix round: one LAMBDA's shadow-evidence names — parameters and capture-list names, all scoped to the
// lambda BODY's span. Lambdas are expressions, not definitions, so the definition arm below never sees
// them (the r9 sweep's A01 query is exactly a lambda parameter shadowing an indexed function). A simple
// capture (`[run]`) re-binds an outer VARIABLE (a function cannot be captured, so the name always denotes
// a variable) and an init-capture (`[trim = expr]`, node lambda_capture_initializer) introduces a NEW
// name — both are VarDecl evidence for the body span.
inline void captureLambdaShadowDecls( TSNode n, std::uint32_t fileId, Lang lang, std::string_view src,
                                      BindSite bodySite, std::vector<RawBind>& binds )
{
    const TSNode d = ts_node_child_by_field_name( n, "declarator", 10 );   // abstract_function_declarator
    if( !ts_node_is_null( d ) )
    {
        const TSNode params = ts_node_child_by_field_name( d, "parameters", 10 );
        if( !ts_node_is_null( params ) )
        {
            emitShadowParamDecls( params, fileId, lang, src, bodySite, binds );
        }
    }
    const TSNode caps = ts_node_child_by_field_name( n, "captures", 8 );   // lambda_capture_specifier
    const std::uint32_t cc = ts_node_is_null( caps ) ? 0u : ts_node_named_child_count( caps );
    for( std::uint32_t i = 0; i < cc; ++i )
    {
        const TSNode c  = ts_node_named_child( caps, i );
        const char*  ct = ts_node_type( c );
        TSNode ident {};
        if( std::strcmp( ct, "identifier" ) == 0 )
        {
            ident = c;   // simple capture `[run]` / `[&run]` (the `&` is an anonymous sibling)
        }
        else if( std::strcmp( ct, "lambda_capture_initializer" ) == 0 && ts_node_named_child_count( c ) > 0 )
        {
            const TSNode nm = ts_node_named_child( c, 0 );   // `[trim = expr]` — the FIRST named child is the introduced name
            if( std::strcmp( ts_node_type( nm ), "identifier" ) == 0 )
            {
                ident = nm;
            }
        }
        if( !ts_node_is_null( ident ) )
        {
            bodySite.startByte = ts_node_start_byte( c );
            pushRawBind( fileId, lang, nodeTextOf( ident, src ), std::string{}, bodySite, LocalBindKind::VarDecl, binds );
        }
    }
}

// a function DEFINITION's parameter_list, reached through its own declarator chain (`char* f(...)` /
// `T& f(...)` unwrap to the function_declarator). Null when the shape isn't a plain definition —
// walking only THIS chain (never bare parameter_declaration nodes) is what keeps a PROTOTYPE's
// parameters and a fn-pointer TYPE's parameter list out of shadow evidence.
inline TSNode fnDefParameterList( TSNode fnDef )
{
    TSNode decl = ts_node_child_by_field_name( fnDef, "declarator", 10 );
    for( int guard = 0; guard < 8 && !ts_node_is_null( decl ) && std::strcmp( ts_node_type( decl ), "function_declarator" ) != 0; ++guard )
    {
        decl = ts_node_child_by_field_name( decl, "declarator", 10 );
    }
    if( ts_node_is_null( decl ) || std::strcmp( ts_node_type( decl ), "function_declarator" ) != 0 )
    {
        return TSNode{};
    }
    return ts_node_child_by_field_name( decl, "parameters", 10 );
}

// r9 shadow suppression (A5 fix round): the local-declaring shapes that live OUTSIDE `declaration` nodes
// (the Rule-2 branch never sees them), dispatched on the caller's already-read node type `t`:
//   * a range-for's loop variable (`for( auto& s : v )`, incl. structured bindings) — scoped to the WHOLE
//     loop statement (iteration 3, unified with enclosingShadowScope's control-statement rule);
//   * a C++/ObjC function DEFINITION's named parameters — scoped to the definition BODY's span. Walking
//     only the definition node's own declarator chain (never bare parameter_declaration nodes) is what
//     keeps two non-scopes out: a PROTOTYPE's parameters (`void f(int run);` binds nothing anywhere) and a
//     fn-pointer type's parameter list (`void (*cb)(int run)` — those names are part of a TYPE, in no
//     scope at all);
//   * a LAMBDA's parameters and capture-list names — captureLambdaShadowDecls above;
//   * a CATCH clause's parameter — a local of its handler block (iteration 3, the noted 3b gap).
// Gates the language and node type ITSELF, so captureBindings calls it unconditionally — the shapes are
// disjoint from every branch of the Rule-2 chain there.
inline void captureShadowScopeDecls( TSNode n, const char* t, std::uint32_t fileId, Lang lang, std::string_view src, std::vector<RawBind>& binds )
{
    if( lang != Lang::Cpp && lang != Lang::ObjC )
    {
        return;
    }
    const bool isRangeFor = std::strcmp( t, "for_range_loop" ) == 0;
    const bool isLambda   = !isRangeFor && std::strcmp( t, "lambda_expression" ) == 0;
    const bool isCatch    = !isRangeFor && !isLambda && std::strcmp( t, "catch_clause" ) == 0;
    const bool isFnDef    = !isRangeFor && !isLambda && !isCatch && std::strcmp( t, "function_definition" ) == 0;
    if( !isRangeFor && !isLambda && !isCatch && !isFnDef )
    {
        return;   // every other node type declares nothing this capture owns
    }
    const TSNode body = ts_node_child_by_field_name( n, "body", 4 );
    if( ts_node_is_null( body ) )
    {
        return;   // a body-less shape scopes nothing (declaration-only lambda/definition never parses so)
    }
    const BindSite bodySite{ ts_node_start_byte( n ), ts_node_start_byte( body ), ts_node_end_byte( body ) };
    if( isRangeFor )
    {
        // iteration 3, unified with enclosingShadowScope's control-statement rule: the loop variable scopes
        // to the WHOLE for_range_loop statement (its own span), not merely the body.
        const BindSite loopSite{ ts_node_start_byte( n ), ts_node_start_byte( n ), ts_node_end_byte( n ) };
        emitShadowVarDecls( fileId, lang, ts_node_child_by_field_name( n, "declarator", 10 ), src, loopSite, binds );
        return;
    }
    if( isLambda )
    {
        captureLambdaShadowDecls( n, fileId, lang, src, bodySite, binds );
        return;
    }
    // a catch parameter is a local of its HANDLER block (iteration 3, the noted 3b gap) — its
    // parameter_list is a direct field; a definition's sits behind the declarator chain
    // (fnDefParameterList above), which is what keeps prototypes and fn-pointer TYPE params out.
    const TSNode params = isCatch ? ts_node_child_by_field_name( n, "parameters", 10 ) : fnDefParameterList( n );
    if( !ts_node_is_null( params ) )
    {
        emitShadowParamDecls( params, fileId, lang, src, bodySite, binds );
    }
}

// emit one L3 var→function RawBind (kind FnDecl/FnAssign) — emitBind's record shape with the kind stamped
// after the push, so the two emitters share ONE body instead of cloning it.
inline void emitFnBind( std::uint32_t fileId, Lang lang, std::string_view var, std::string target,
                        std::uint32_t startByte, LocalBindKind kind, std::vector<RawBind>& binds )
{
    const std::size_t before = binds.size();
    emitBind( fileId, lang, var, std::move( target ), startByte, binds );
    if( binds.size() > before )
    {
        binds.back().kind = kind;
    }
}

// L3 capture over one C-family `declaration` node: one FnDecl record per init_declarator whose RHS names a
// function (`&alpha` / `beta` / a lambda). `&name` and lambdas are self-evidencing and emit at once;
// a BARE-IDENTIFIER initializer is the one shape a fn-pointer bind shares with a plain value copy, so it
// goes to the VALUE-INITIALIZATION NOISE GATE below (`pending`) unless the declarator itself spells a fn
// pointer, which settles it on the spot.
// A reference declarator (`H& r = fn;`) emits NO positive and clobbers the bound-to var (A5 escape guard).
inline void captureFnBindDecl( TSNode n, std::uint32_t fileId, Lang lang, std::string_view src,
                               std::vector<RawBind>& fnPos, std::vector<FnBindClobber>& fnUnk,
                               std::vector<PendingFnBindDecl>& pending )
{
    const TSNode typeNode = ts_node_child_by_field_name( n, "type", 4 );
    std::string  writtenType;
    const bool   concrete = concreteWrittenType( typeNode, src, writtenType );
    const std::uint32_t cc = ts_node_child_count( n );
    for( std::uint32_t i = 0; i < cc; ++i )
    {
        const char* fname = ts_node_field_name_for_child( n, i );
        if( fname == nullptr || std::strcmp( fname, "declarator" ) != 0 )
        {
            continue;
        }
        const TSNode c = ts_node_child( n, i );
        if( std::strcmp( ts_node_type( c ), "init_declarator" ) != 0 )
        {
            continue;   // no initializer → no binding fact here (a later assignment carries its own)
        }
        const auto [ var, sawFnDecl, sawPtrDecl, sawRef ] = fnDeclaratorShape( ts_node_child_by_field_name( c, "declarator", 10 ), src );
        const TSNode valueNode = ts_node_child_by_field_name( c, "value", 5 );
        if( sawRef )
        {
            // A5 escape guard: `H& r = fn;` / `auto& r = fn;` ALIASES fn — a write through r retargets fn
            // invisibly, so the bound-to variable is clobbered (toward tombstone, never toward resolve) and
            // the alias itself gets NO positive (its target can change under it the same way).
            if( !ts_node_is_null( valueNode ) && std::strcmp( ts_node_type( valueNode ), "identifier" ) == 0 )
            {
                const std::string_view aliased = nodeTextOf( valueNode, src );
                if( !aliased.empty() )
                {
                    fnUnk.push_back( { std::string( aliased ), ts_node_start_byte( n ) } );
                }
            }
            continue;
        }
        bool bareIdent = false;
        std::string target = fnBindTargetOf( valueNode, src, bareIdent );
        if( bareIdent && !target.empty() && !( sawFnDecl && sawPtrDecl ) )
        {
            // the declarator does not itself spell a fn pointer, so only the WRITTEN TYPE can tell a bind
            // from a copy — and that answer needs the file's complete alias table. Hold it.
            pending.push_back( { std::string( var ), std::move( target ), writtenType, ts_node_start_byte( n ), concrete } );
            continue;
        }
        emitFnBind( fileId, lang, var, std::move( target ), ts_node_start_byte( n ), LocalBindKind::FnDecl, fnPos );
    }
}

// A5 escape guard over one `pointer_expression`: `&fn` ANYWHERE makes the variable mutable through the
// pointer (`indirect_mutate(&fn)` retargets it behind the resolver's back), so any address-of over a bare
// identifier records a CLOBBER for that identifier — toward tombstone, never toward resolve. A by-value use
// (`takes_fn(fn)`, `other = fn`) copies the pointer and cannot mutate the variable, so it does NOT clobber.
// The `&alpha` inside a positive binding RHS also lands here (clobbering the FUNCTION's name as a "var") —
// harmless-conservative: it only matters if a same-named variable holds a binding in this file, and then
// refusing to resolve it is the safe side. Dereferences (`*p`) are excluded by the operator check.
inline void captureFnBindEscape( TSNode n, std::string_view src, std::vector<FnBindClobber>& fnUnk )
{
    const TSNode op = ts_node_child( n, 0 );
    if( ts_node_is_null( op ) || std::strcmp( ts_node_type( op ), "&" ) != 0 )
    {
        return;
    }
    const TSNode idn = ts_node_child_by_field_name( n, "argument", 8 );
    if( ts_node_is_null( idn ) || std::strcmp( ts_node_type( idn ), "identifier" ) != 0 )
    {
        return;
    }
    const std::string_view var = nodeTextOf( idn, src );
    if( !var.empty() )
    {
        fnUnk.push_back( { std::string( var ), ts_node_start_byte( n ) } );
    }
}

// L3 capture over one C-family `assignment_expression`: a recognizable RHS emits an FnAssign record; any
// other RHS on a bare-identifier LHS (`fn = getHandler()`, `fn = nullptr`, `n += 1`) records a CLOBBER
// candidate, emitted as a tombstone at the end of the walk IF the var has a fn binding in the same file.
// A BARE-IDENTIFIER RHS (`fn = beta;`) is neither yet: it is the one shape a plain value copy shares with a
// genuine fn-pointer rebind, and the assignment node carries no type to tell them apart — so it is held in
// `pending` for the end-of-walk value-assignment noise gate above, which asks the file's own declarations.
// The second branch decodes the C++-grammar MIS-PARSE of a raw fn-pointer declaration (`void (*fn)() =
// &alpha;` — see misparsedFnPtrDeclVar): the shape itself proves a fn-pointer declarator, so a
// bare-identifier RHS is captured immediately there — the "type" IS the evidence, no gate needed.
inline void captureFnBindAssign( TSNode n, std::uint32_t fileId, Lang lang, std::string_view src,
                                 std::vector<RawBind>& fnPos, std::vector<FnBindClobber>& fnUnk,
                                 std::vector<PendingFnBindAssign>& pending )
{
    const TSNode lhs = ts_node_child_by_field_name( n, "left",  4 );
    const TSNode rhs = ts_node_child_by_field_name( n, "right", 5 );
    if( !ts_node_is_null( lhs ) && std::strcmp( ts_node_type( lhs ), "identifier" ) == 0 )
    {
        const std::uint32_t a = ts_node_start_byte( lhs ), b = ts_node_end_byte( lhs );
        if( a <= b && b <= src.size() )
        {
            const std::string_view var = src.substr( a, b - a );
            bool bareIdent = false;
            std::string target = fnBindTargetOf( rhs, src, bareIdent );
            if( target.empty() )
            {
                fnUnk.push_back( { std::string( var ), ts_node_start_byte( n ) } );
            }
            else if( bareIdent )
            {
                pending.push_back( { std::string( var ), std::move( target ), ts_node_start_byte( n ) } );
            }
            else
            {
                emitFnBind( fileId, lang, var, std::move( target ), ts_node_start_byte( n ), LocalBindKind::FnAssign, fnPos );
            }
        }
    }
    else if( const std::string_view dvar = misparsedFnPtrDeclVar( lhs, src ); !dvar.empty() )
    {
        bool bareIdent = false;
        std::string target = fnBindTargetOf( rhs, src, bareIdent );
        if( !target.empty() )
        {
            emitFnBind( fileId, lang, dvar, std::move( target ), ts_node_start_byte( n ), LocalBindKind::FnDecl, fnPos );
        }
        else
        {
            fnUnk.push_back( { std::string( dvar ), ts_node_start_byte( n ) } );
        }
    }
}

// decide every bare-identifier assignment the walk held back, against the file's COMPLETE declaration
// evidence. A name the file proved to be a VALUE variable where the assignment sits records NOTHING — not a
// positive, and deliberately not a clobber either: a clobber is a statement ABOUT a function pointer ("this
// one is no longer trustworthy"), and the end-of-walk sweep promotes it to a real FnAssign tombstone as
// soon as any same-named var in the file holds a binding. That tombstone reads as a binding to every
// consumer — it re-vetoed the very shadow suppression this gate exists to restore. A copy into a string is
// evidence in NEITHER direction. Everything else mints its FnAssign exactly as it did before the gate.
inline void resolvePendingFnBindAssigns( std::uint32_t fileId, Lang lang, FnBindGateState& gate, std::vector<RawBind>& fnPos )
{
    for( PendingFnBindAssign& p : gate.pending )
    {
        if( !fnBindProvenValueVar( p.var, p.startByte, gate.facts, gate.aliases ) )
        {
            emitFnBind( fileId, lang, p.var, std::move( p.target ), p.startByte, LocalBindKind::FnAssign, fnPos );
        }
    }
}

// ── L3 VALUE-INITIALIZATION NOISE GATE (r9 fix round, DECLARATION arm) ───────────────────────────────
// The sibling gate above answers "what is this VARIABLE?" from the file's declarations because an
// assignment node carries no type. A declaration carries one, so this arm asks the stronger question
// directly of the node in front of it: does the WRITTEN TYPE prove a value?
//   * a CONCRETE type that is no fn-pointer alias — `std::string tag = zzz;`, `Box b = other;`,
//     `int a = b;` — is a copy. No binding. Before this gate only the PRIMITIVE half of that was caught,
//     so a CLASS-typed copy minted an FnDecl, and shadowSuppressedSite (model.h) VETOES local-shadow
//     suppression for any name carrying an L3 binding — the local handed its every read/write site back to
//     the function it shadows. That is the same harm, and the same mechanism, as the assignment arm's.
//   * a fn-pointer DECLARATOR (`void (*fp)() = handler;`) never reaches here at all: the shape is its own
//     evidence and captureFnBindDecl emits it on the spot.
//   * a same-file fn-pointer ALIAS (`typedef void (*H)(); H fp = beta;`) mints — the alias table is why
//     these records are deferred to the end of the walk rather than judged where they are written.
//   * everything else is UNKNOWN and unknown MINTS: `auto fp = f;` (the idiomatic form), `decltype(...)`,
//     and any template/dependent type. Refusing to guess is what keeps this gate from costing recall.
// DISCLOSED BLIND SPOT, pinned by test/fnptrcheck.sh arm (t): the alias evidence is SAME-FILE, so a
// `typedef void (*H)();` living in a HEADER leaves `H fp = beta;` indistinguishable from a value copy and
// its edge is gated away. It cost ZERO edges on the two corpora this round measured (this repo, 1093 files
// / 10771 edges, full map byte-identical; a 2376-file ObjC++ tree, 39741 edges, every callee row identical
// and only `unresolved=` moving 2577 → 2509) — but that is a measurement, not a proof. Widening the alias
// evidence corpus-wide is the fix if a corpus ever pays for it.
inline void resolvePendingFnBindDecls( std::uint32_t fileId, Lang lang, FnBindGateState& gate, std::vector<RawBind>& fnPos )
{
    for( PendingFnBindDecl& p : gate.pendingDecl )
    {
        const bool aliasTyped  = !p.typeName.empty() && gate.aliases.find( p.typeName ) != gate.aliases.end();
        const bool provenValue = p.concreteType && !aliasTyped;
        if( !provenValue )
        {
            emitFnBind( fileId, lang, p.var, std::move( p.target ), p.startByte, LocalBindKind::FnDecl, fnPos );
        }
    }
}

// P2-D Rule 2 local var→type bindings + the L3 fn-pointer capture. One visitor on the shared pre-order
// stream (streamSideCaptures below) — the pass used to own an identical walk of its own, which is what the
// fusion removed. Its state outlives a single node (the L3 clobber sweep needs the whole file's positives),
// so it rides in a context the driver holds by reference; bindsFinalize spends it when the stream ends.
struct BindCtx
{
    std::uint32_t              fileId = 0;
    Lang                       lang {};
    std::string_view           src;
    std::vector<RawBind>*      binds = nullptr;

    // L3 fn-pointer buffers. Positives collect here (not straight into binds) so the end-of-walk clobber
    // sweep can ask "does this var have a fn binding in this file?" — a clobbering assignment
    // (`fn = getHandler()`) matters only then, which keeps a fn-binding-free file contributing ZERO new
    // records (the whole feature inert there).
    std::vector<RawBind>       fnPos;
    std::vector<FnBindClobber> fnUnk;
    FnBindGateState            fnGate;      // value-assignment noise-gate evidence — filled by the stream, spent at the end
    bool                       cFamilyFn = false;
};

void bindsVisitNode( BindCtx& cx, TSNode n, const char* t )
{
    // The body below is the pass's own node step, unchanged; these aliases keep it reading against the
    // same names it always had rather than sprinkling `cx.` through 150 lines of grammar branches.
    FUSEPROBE_BUMP( kBinds );
    const std::uint32_t         fileId    = cx.fileId;
    const Lang                  lang      = cx.lang;
    const std::string_view      src       = cx.src;
    std::vector<RawBind>&       binds     = *cx.binds;
    std::vector<RawBind>&       fnPos     = cx.fnPos;
    std::vector<FnBindClobber>& fnUnk     = cx.fnUnk;
    FnBindGateState&            fnGate    = cx.fnGate;
    const bool                  cFamilyFn = cx.cFamilyFn;

    // C++/ObjC: `Foo x;` · `Foo* x;` · `Foo x = Foo();` · `auto x = Foo();`
    if( ( lang == Lang::Cpp || lang == Lang::ObjC ) && std::strcmp( t, "declaration" ) == 0 )
    {
        const TSNode typeNode = ts_node_child_by_field_name( n, "type", 4 );
        std::string  written  = writtenTypeOf( typeNode, src );
        // A5 fix round: the declared names shadow within their enclosing block (or, for a control-statement
        // header declaration, that whole statement) — one parent walk per declaration node, shared by every
        // declarator child below; each declarator then contributes its own declaration POINT as the span's
        // start (shadowSpanStart).
        const ShadowScope scope = enclosingShadowScope( n );
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
            // `init_declarator`: name lives in its `declarator`, the RHS in its `value` (for auto inference).
            // emitDeclBinds also records the r9 VarDecl shadow fact for the declared NAME regardless of type
            // resolvability (`int run = 0;` binds no type — writtenTypeOf refuses primitives — yet the local
            // exists and shadows).
            if( std::strcmp( ct, "init_declarator" ) == 0 )
            {
                const TSNode declarator = ts_node_child_by_field_name( c, "declarator", 10 );
                std::string  type       = written.empty() ? ctorTypeOf( ts_node_child_by_field_name( c, "value", 5 ), src ) : written;
                emitDeclBinds( fileId, lang, declarator, src, std::move( type ),
                               BindSite{ ts_node_start_byte( n ), shadowSpanStart( scope, declarator ), scope.end }, binds );
            }
            else   // plain declarator (identifier / pointer_declarator / reference_declarator), no initializer
            {
                emitDeclBinds( fileId, lang, c, src, std::string( written ),
                               BindSite{ ts_node_start_byte( n ), shadowSpanStart( scope, c ), scope.end }, binds );
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

    // r9 shadow suppression: the local-declaring shapes OUTSIDE `declaration` nodes — a function
    // DEFINITION's named parameters and a range-for's loop variable. Unconditional (the helper gates
    // language and node type itself); disjoint from every branch of the Rule-2 chain above.
    captureShadowScopeDecls( n, t, fileId, lang, src, binds );

    // ── L3 fn-pointer/callback capture (C/C++/ObjC) — a SEPARATE if (not part of the Rule-2 chain above):
    // the same `declaration` node can carry BOTH a Rule-2 var→type fact and a var→function fact
    // (`H fnPtr = beta;` emits fnPtr:H for receiver narrowing AND fnPtr→beta for call resolution). ──
    if( cFamilyFn && std::strcmp( t, "declaration" ) == 0 )
    {
        captureFnBindDecl( n, fileId, lang, src, fnPos, fnUnk, fnGate.pendingDecl );
    }
    else if( cFamilyFn && std::strcmp( t, "assignment_expression" ) == 0 )
    {
        captureFnBindAssign( n, fileId, lang, src, fnPos, fnUnk, fnGate.pending );
    }
    else if( cFamilyFn && std::strcmp( t, "pointer_expression" ) == 0 )
    {
        captureFnBindEscape( n, src, fnUnk );   // A5: `&fn` anywhere clobbers the variable (escape guard)
    }
    collectFnBindGateEvidence( n, t, src, cFamilyFn, fnGate );   // never an `else if` — see the helper's note
}

// End-of-file step for the bindings pass: the two noise gates and the L3 clobber sweep. Split out of the
// walk (it was the tail of captureBindings) so the shared stream can run it once the last node is visited.
void bindsFinalize( BindCtx& cx )
{
    const std::uint32_t         fileId = cx.fileId;
    const Lang                  lang   = cx.lang;
    std::vector<RawBind>&       binds  = *cx.binds;
    std::vector<RawBind>&       fnPos  = cx.fnPos;
    std::vector<FnBindClobber>& fnUnk  = cx.fnUnk;
    FnBindGateState&            fnGate = cx.fnGate;

    resolvePendingFnBindDecls  ( fileId, lang, fnGate, fnPos );   // both noise gates — BEFORE the sweep, which needs
    resolvePendingFnBindAssigns( fileId, lang, fnGate, fnPos );   // fnPos final (its var scan is a membership test,
                                                                  // so the deferral cannot change a clobber verdict)

    // ── L3 clobber sweep + merge. A clobbering assignment forces the tombstone (kFnBindClobberTarget) so a
    // stale earlier binding can never win (`void (*fn)() = &alpha; fn = getHandler(); fn();` → NO edge) —
    // but only for a var that HAS a recognizable fn binding somewhere in this file, an over-approximation
    // of "same scope" that errs toward the tombstone, never toward a resolve. posCount is captured BEFORE
    // the emits below so the sweep scans only the walk's own positives.
    if( !fnPos.empty() )
    {
        const std::size_t posCount = fnPos.size();
        for( const FnBindClobber& u : fnUnk )
        {
            bool hasPos = false;
            for( std::size_t p = 0; p < posCount; ++p )
            {
                if( fnPos[p].var == u.var )
                {
                    hasPos = true;
                    break;
                }
            }
            if( hasPos )
            {
                emitFnBind( fileId, lang, u.var, std::string( kFnBindClobberTarget ), u.startByte, LocalBindKind::FnAssign, binds );
            }
        }
        for( RawBind& p : fnPos )
        {
            binds.push_back( std::move( p ) );
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

// One visitor on the shared pre-order stream (streamSideCaptures below). The pass arms only on C++/ObjC/
// Python; the pybind sub-detector stays gated on a cheap file-level signal so ordinary `.def(` calls in
// non-pybind C++ never capture.
struct FfiCtx
{
    std::uint32_t              fileId = 0;
    std::string_view           src;
    std::vector<BindingAlias>* ffis = nullptr;
    bool                       cish      = false;
    bool                       py        = false;
    bool                       hasPybind = false;
};

FfiCtx makeFfiCtx( std::uint32_t fileId, Lang lang, std::string_view src, std::vector<BindingAlias>& ffis )
{
    FfiCtx cx;
    cx.fileId    = fileId;
    cx.src       = src;
    cx.ffis      = &ffis;
    cx.cish      = ( lang == Lang::Cpp || lang == Lang::ObjC );
    cx.py        = ( lang == Lang::Python );
    cx.hasPybind = cx.cish && ( src.find( "pybind11" ) != std::string_view::npos
                             || src.find( "PYBIND11" ) != std::string_view::npos );
    return cx;
}

void ffiVisitNode( FfiCtx& cx, TSNode n, const char* t )
{
    FUSEPROBE_BUMP( kFfi );
    const std::uint32_t        fileId    = cx.fileId;
    const std::string_view     src       = cx.src;
    std::vector<BindingAlias>& ffis      = *cx.ffis;
    const bool                 cish      = cx.cish;
    const bool                 py        = cx.py;
    const bool                 hasPybind = cx.hasPybind;

    const auto nodeSrc = [ & ]( TSNode nn ) noexcept -> std::string_view { return nodeTextOf( nn, src ); };

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

// One visitor on the shared pre-order stream (streamSideCaptures below). The pass arms only on Python/JS/TS;
// the SERVER detectors stay gated on a file-level framework signal, so a framework-free file still captures
// no route DEF and the whole feature stays byte-inert on a framework-free corpus.
struct RouteCtx
{
    std::uint32_t              fileId = 0;
    std::string_view           src;
    std::vector<RouteDef>*     routeDefs = nullptr;
    std::vector<RawRouteUse>*  routeUses = nullptr;
    bool                       py = false;
    bool                       js = false;
    bool                       pyServerGated = false;
    bool                       jsServerGated = false;
};

RouteCtx makeRouteCtx( std::uint32_t fileId, Lang lang, std::string_view src,
                       std::vector<RouteDef>& routeDefs, std::vector<RawRouteUse>& routeUses )
{
    RouteCtx cx;
    cx.fileId        = fileId;
    cx.src           = src;
    cx.routeDefs     = &routeDefs;
    cx.routeUses     = &routeUses;
    cx.py            = ( lang == Lang::Python );
    cx.js            = ( lang == Lang::TypeScript || lang == Lang::JavaScript );
    cx.pyServerGated = cx.py && ( src.find( "fastapi" ) != std::string_view::npos || src.find( "FastAPI" ) != std::string_view::npos
                                || src.find( "flask" )   != std::string_view::npos || src.find( "Flask" )   != std::string_view::npos );
    cx.jsServerGated = cx.js && ( src.find( "express" ) != std::string_view::npos || src.find( "fastify" ) != std::string_view::npos );
    return cx;
}

void routesVisitNode( RouteCtx& cx, TSNode n, const char* t )
{
    FUSEPROBE_BUMP( kRoutes );
    const std::uint32_t        fileId        = cx.fileId;
    const std::string_view     src           = cx.src;
    std::vector<RouteDef>&     routeDefs     = *cx.routeDefs;
    std::vector<RawRouteUse>&  routeUses     = *cx.routeUses;
    const bool                 py            = cx.py;
    const bool                 js            = cx.js;
    const bool                 pyServerGated = cx.pyServerGated;
    const bool                 jsServerGated = cx.jsServerGated;

    const auto nodeSrc = [ & ]( TSNode nn ) noexcept -> std::string_view { return nodeTextOf( nn, src ); };

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

// does `outer`'s [start,end) byte range contain ALL of `inner`? Used by the tags-pass body-climb to tell a
// def that IS an ancestor's signature (outside its body — adopt the ancestor's span) from a def spelled
// INSIDE that body (a nested JS/TS closure — adopting would broadcast the encloser's span onto it).
inline bool spanContains( TSNode outer, TSNode inner ) noexcept
{
    return ts_node_start_byte( inner ) >= ts_node_start_byte( outer ) && ts_node_end_byte( inner ) <= ts_node_end_byte( outer );
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

// A5 shadow fix round: is `id` a DECLARATION-SITE name isNonValueContext's single-`declarator`-field probe
// (arm 2) cannot see? Pre-fix each of these leaked the DECLARED name out as a role="read" site of its own
// declaration (`int& key` param/local, `auto& [key, w]`, `for (int key : arr)`, `[key = expr]`). An
// identifier directly under a reference_declarator or a structured_binding_declarator is ALWAYS a declared
// name (value expressions live under other node types); a range-for's is its `declarator` field; an
// init-capture's is its FIRST named child (the value side of `[a = b]` stays a genuine read of b).
// `variadic_declarator` (`Ts... key`) and `attributed_declarator` (`int key [[maybe_unused]]`) join the
// unconditional arm for the same grammar reason: each holds its inner declarator as an UNNAMED child, so
// arm 2's `declarator`-field probe returns null and sees nothing. Their only bare-identifier child is the
// declared name — a pack's attributes are `attribute_declaration` nodes, never loose identifiers.
// NOT fixable here, and deliberately left listed: `int (key);` — the most-vexing parse, which tree-sitter
// resolves to an `argument_list`, the same node every genuine call ARGUMENT lives under. Suppressing that
// parent would delete real reads corpus-wide to chase a shape that is vanishingly rare in real source.
// Iteration 4 adds the shape arm 2 looks straight at and still misses: a `declaration` carries one
// `declarator` FIELD PER DECLARED NAME, so ts_node_child_by_field_name — which returns the FIRST — sees
// `a` in `int a, key;` and never `key`; a bare `int key;` it misses outright, the parent type not being in
// arm 2's list at all. Iterations 1-3 could not observe either, because the block-start span suppressed the
// declaration line along with the rest of the block; declaration-point spans stop covering it.
inline bool isDeclSiteName( TSNode id, TSNode parent, const char* pt ) noexcept
{
    if( std::strcmp( pt, "reference_declarator" ) == 0 || std::strcmp( pt, "structured_binding_declarator" ) == 0
        || std::strcmp( pt, "variadic_declarator" ) == 0 || std::strcmp( pt, "attributed_declarator" ) == 0 )
    {
        return true;
    }
    if( std::strcmp( pt, "declaration" ) == 0 )
    {
        const std::uint32_t cc = ts_node_child_count( parent );
        for( std::uint32_t i = 0; i < cc; ++i )
        {
            const char* fieldName = ts_node_field_name_for_child( parent, i );
            if( fieldName != nullptr && std::strcmp( fieldName, "declarator" ) == 0 && sameSpan( ts_node_child( parent, i ), id ) )
            {
                return true;
            }
        }
        return false;
    }
    if( std::strcmp( pt, "for_range_loop" ) == 0 )
    {
        const TSNode decl = ts_node_child_by_field_name( parent, "declarator", 10 );
        return !ts_node_is_null( decl ) && sameSpan( decl, id );
    }
    if( std::strcmp( pt, "lambda_capture_initializer" ) == 0 )
    {
        return ts_node_named_child_count( parent ) > 0 && sameSpan( ts_node_named_child( parent, 0 ), id );
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
    // `optional_parameter_declaration` is `parameter_declaration`'s DEFAULTED sibling (`int x = 0`) and
    // carries the same `declarator` field — probing the field, not the node type, is what keeps a default
    // VALUE that names a symbol (`int v = probe()`, a different field) a genuine use.
    if(    std::strcmp( pt, "function_declarator" ) == 0 || std::strcmp( pt, "init_declarator" ) == 0
        || std::strcmp( pt, "parameter_declaration" ) == 0 || std::strcmp( pt, "pointer_declarator" ) == 0
        || std::strcmp( pt, "reference_declarator" ) == 0  || std::strcmp( pt, "array_declarator" ) == 0
        || std::strcmp( pt, "optional_parameter_declaration" ) == 0 )
    {
        const TSNode decl = ts_node_child_by_field_name( parent, "declarator", 10 );
        if( !ts_node_is_null( decl ) && sameSpan( decl, id ) )
        {
            return true;
        }
    }
    // (2b) A5 shadow fix round: declaration-site names the field probe above cannot see (isDeclSiteName).
    if( isDeclSiteName( id, parent, pt ) )
    {
        return true;
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

// One visitor on the shared pre-order stream (streamSideCaptures below). It keeps its OWN 512-node depth
// cap — twice the other passes' — which the shared stream honours per visitor: past 256 the FFI/route/bind
// visitors stop being called while this one keeps receiving nodes, exactly as their separate walks behaved.
struct UseCtx
{
    std::uint32_t        fileId = 0;
    Lang                 lang {};
    std::string_view     src;
    std::vector<RawRef>* refs = nullptr;
};

void usesVisitNode( UseCtx& cx, TSNode n, const char* t )
{
    FUSEPROBE_BUMP( kUses );
    // capture only bare value identifiers (C++ `identifier`, Python `identifier`). field_identifier reads
    // (`obj.field` non-call) are intentionally out of scope — member-field use is a richer relation we keep
    // for a later pass; the gate exercises plain locals/globals, which are `identifier` nodes.
    if( std::strcmp( t, "identifier" ) != 0 )
    {
        return;
    }
    if( isCallCallee( n ) || isNonValueContext( n ) )
    {
        return;
    }
    const std::string_view src = cx.src;
    const std::uint32_t    a   = ts_node_start_byte( n ), b = ts_node_end_byte( n );
    if( a < b && b <= src.size() )
    {
        RawRef r;
        r.fileId    = cx.fileId;
        r.startByte = a;
        r.line      = ts_node_start_point( n ).row + 1;
        r.lang      = cx.lang;
        r.role      = isWriteTarget( n ) ? RefRole::Write : RefRole::Read;
        r.name      = finalSegment( src.substr( a, b - a ) );   // bare identifier → already final segment
        cx.refs->push_back( std::move( r ) );
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

// ── ONE pre-order stream for every whole-AST side-capture pass ────────────────────────────────────────
// FFI, routes, Rust impls, bindings and value-uses each used to run their OWN iterative pre-order walk of
// the same tree, back to back. Measured with a per-pass node-pop probe on a 1659-file ObjC++/C++ corpus:
// 95.0% of files ran captureFfi AND captureBindings, 93.4% ran three passes, and every node was streamed
// 2.01x on a default run / 3.01x with --uses armed. That re-streaming — not the per-node matching, which
// is a strcmp or two — is why the `side captures` profile scope showed ~2x tree-sitter's L1D MPKI and ~2x
// its LLC misses on half the instructions. The passes now share one stream; the per-node work is unchanged.
//
// ENTRY RULES. This is the union of what the fused passes need, and it is exactly "every node", because
// FFI / bindings / value-uses each already descended unconditionally. captureIncludes is deliberately NOT
// fused: it enters only ALLOWLISTED import containers (isImportContainer) and cost 59 node pops per file
// against ~7,800 for a full walk — 0.4% of all pops. Folding it in would either make it visit ~130x more
// nodes or force a per-frame "still inside an allowlisted chain" bit, and its restricted entry set is what
// DEFINES which directives it captures. It keeps its own walk.
//
// DEPTH. Each pass's own pathological-AST cap survives as a per-visitor `maxDepth`: past its cap a visitor
// simply stops being called while the others keep descending — which is what that pass's own `continue`
// did (it skipped the node AND its subtree, and depth only grows). The stream descends while ANY armed
// visitor still wants nodes, so the heap stack's high-water mark is max(caps) — 512 with --uses armed,
// exactly what captureUses' own walk already reached, and 256 otherwise. No frame got fatter either: the
// fused frame is one TSNode + one depth, the same shape (and the same 40 bytes) as each pass's old frame.
//
// EMISSION ORDER. Every fused pass appends to its OWN output vector, so within a vector the order is that
// pass's own node order — byte-identical to running the passes back to back. `refs` is the one vector two
// fused passes could share (Rust impls and value-uses), and they are disjoint by language (Rust vs
// C++/ObjC/Python), so at most one is ever armed; sideArmsAreOrderSafe pins that invariant. Visitors are
// still invoked in the ORIGINAL pass order at each node, so the reading order matches the old call order.
// depth is 32-bit, not the 16-bit each pass used to carry: same 40 bytes after padding either way, and a
// tree deeper than 65535 can no longer WRAP the counter back under a cap and re-enable a visitor that
// should have stopped. Unreachable on a <= 1 MB file, but the old shape was the fragile one.
struct SideFrame
{
    TSNode        node;
    std::uint32_t depth;
};
static_assert( sizeof( SideFrame ) == sizeof( TSNode ) + 8, "the fused frame must not outgrow one node + a depth" );

constexpr std::uint32_t kSideDepthStd       = 256;           // FFI / routes / bindings — their own guard
constexpr std::uint32_t kSideDepthUses      = 512;           // value-uses — twice the others, as it always was
constexpr std::uint32_t kSideDepthUnbounded = 0xFFFFFFFFu;   // Rust impls — that pass never had a cap

// The armed set for one file. A pass whose context pointer is null is not armed and costs one predictable
// branch per node; that is what keeps a file-level gate from turning into an always-on walk.
struct SideArms
{
    FfiCtx*      ffi   = nullptr;
    RouteCtx*    route = nullptr;
    RustImplCtx* rust  = nullptr;
    BindCtx*     bind  = nullptr;
    UseCtx*      uses  = nullptr;
};

// see EMISSION ORDER above: the two passes that write `refs` must never be armed together.
inline bool sideArmsAreOrderSafe( const SideArms& arms ) noexcept
{
    return arms.rust == nullptr || arms.uses == nullptr;
}

void streamSideCaptures( TSNode root, const SideArms& arms )
{
    VERIFY( sideArmsAreOrderSafe( arms ) );

    std::uint32_t deepest = 0;
    if( arms.ffi   != nullptr ) { deepest = std::max( deepest, kSideDepthStd ); }
    if( arms.route != nullptr ) { deepest = std::max( deepest, kSideDepthStd ); }
    if( arms.bind  != nullptr ) { deepest = std::max( deepest, kSideDepthStd ); }
    if( arms.uses  != nullptr ) { deepest = std::max( deepest, kSideDepthUses ); }
    if( arms.rust  != nullptr ) { deepest = kSideDepthUnbounded; }
    if( deepest == 0 )
    {
        return;   // nothing armed — do not touch the tree at all
    }

    // Iterative, never recursive: worker threads get 512 KB stacks on macOS and a deep AST overflows the
    // call stack well inside any depth guard. Children are pushed in REVERSE so pops preserve left-to-right
    // source order — the determinism contract is byte-identity, and an order that depended on the walk
    // shape would break it.
    std::vector<SideFrame> stack;
    stack.reserve( 64 );
    stack.push_back( { root, 0 } );
    ChildCursor         cursor( root );
    std::vector<TSNode> kids;
    kids.reserve( 64 );

    while( !stack.empty() )
    {
        const SideFrame frame = stack.back();
        stack.pop_back();
        FUSEPROBE_POP();
        if( frame.depth > deepest )
        {
            continue;   // past every armed visitor's cap — this subtree is nobody's business
        }
        const TSNode n = frame.node;
        const char*  t = ts_node_type( n );

        // original pass order: FFI, routes, Rust impls, bindings, value-uses.
        if( arms.ffi   != nullptr && frame.depth <= kSideDepthStd )  { ffiVisitNode   ( *arms.ffi,   n, t ); }
        if( arms.route != nullptr && frame.depth <= kSideDepthStd )  { routesVisitNode( *arms.route, n, t ); }
        if( arms.rust  != nullptr )                                  { rustImplVisitNode( *arms.rust, n, t ); }
        if( arms.bind  != nullptr && frame.depth <= kSideDepthStd )  { bindsVisitNode ( *arms.bind,  n, t ); }
        if( arms.uses  != nullptr && frame.depth <= kSideDepthUses ) { usesVisitNode  ( *arms.uses,  n, t ); }

        collectChildren( n, cursor.cur, kids );
        for( std::size_t i = kids.size(); i > 0; --i )
        {
            stack.push_back( { kids[i - 1], frame.depth + 1 } );
        }
    }
}

void captureSideFacts( const LangEntry& le, std::uint32_t fileId, std::string_view src, TSNode root,
                       std::vector<RawRef>& refs, std::vector<Include>& incs, std::vector<RawBind>& binds,
                       std::vector<BindingAlias>& ffis, std::vector<RouteDef>& routeDefs,
                       std::vector<RawRouteUse>& routeUses, bool captureValueUses )
{
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/extractFile: side captures" );

#ifdef RIPWIRE_FUSE_PROBE
        std::uint64_t probeBefore[ fuseprobe::kPassCount ];
        for( int p = 0; p < fuseprobe::kPassCount; ++p )
        {
            probeBefore[ p ] = fuseprobe::tlNodes[ p ];
        }
#endif

        captureIncludes( root, le.lang, fileId, src, incs, refs );   // physical deps + ABS-3 import-role use-sites

        // A4-R5: cross-language FFI binding declarations (pybind11 / extern "C" / ctypes handle). Inert on a
        // binding-free file (pybind gated on a file signal; extern-C/ctypes only fire on their exact shapes).
        FfiCtx   ffiCtx   = makeFfiCtx( fileId, le.lang, src, ffis );

        // B6.3: HTTP-route DEF/USE facts (Express/Fastify · FastAPI/Flask · fetch/axios/requests). Server
        // detectors gated on a file-level framework signal; inert on a framework-free / non-JS/Python file.
        RouteCtx routeCtx = makeRouteCtx( fileId, le.lang, src, routeDefs, routeUses );

        // Rust IS-A: `impl Trait for T` is a top-level impl_item (sibling of the struct), unreachable from the
        // struct's def-walk. Derived type name rides `qualifier` (name-resolved in buildGraph).
        RustImplCtx rustCtx { fileId, src, &refs };

        // P2-D Rule 2: local var→type bindings (`Foo x;`), for receiver-variable narrowing. C++/ObjC/Python/TS
        // (the languages whose receiver shape `receiverOf` captures as a recvVar) — others have no consumer yet.
        // L3 adds Lang::C for the fn-pointer/callback var→function capture only: the Rule-2 branches inside
        // gate themselves on Cpp/ObjC/Python/TS, so type narrowing is byte-identical on C files.
        BindCtx bindCtx;
        bindCtx.fileId    = fileId;
        bindCtx.lang      = le.lang;
        bindCtx.src       = src;
        bindCtx.binds     = &binds;
        bindCtx.cFamilyFn = ( le.lang == Lang::Cpp || le.lang == Lang::C || le.lang == Lang::ObjC );

        // ABS-3: read/write use-site capture (bare value identifiers + assignment targets). C++/ObjC/Python —
        // the languages whose assignment/update grammar shapes isWriteTarget knows. role=Read/Write refs NEVER
        // enter the call graph (buildGraph skips role != Call), so PageRank and the default map are unchanged.
        UseCtx useCtx { fileId, le.lang, src, &refs };

        SideArms arms;
        if( ffiCtx.cish || ffiCtx.py )
        {
            arms.ffi = &ffiCtx;
        }
        if( routeCtx.py || routeCtx.js )
        {
            arms.route = &routeCtx;
        }
        if( le.lang == Lang::Rust )
        {
            arms.rust = &rustCtx;
        }
        if( le.lang == Lang::Cpp || le.lang == Lang::ObjC || le.lang == Lang::Python || le.lang == Lang::TypeScript
            || le.lang == Lang::C )
        {
            arms.bind = &bindCtx;
        }
        if( captureValueUses && ( le.lang == Lang::Cpp || le.lang == Lang::ObjC || le.lang == Lang::Python ) )
        {
            arms.uses = &useCtx;
        }

        streamSideCaptures( root, arms );

        if( arms.bind != nullptr )
        {
            bindsFinalize( bindCtx );   // L3 noise gates + clobber sweep — the tail of the old captureBindings
        }

#ifdef RIPWIRE_FUSE_PROBE
        {
            int           sawNode = 0;
            std::uint64_t maxPass = 0;
            for( int p = 0; p < fuseprobe::kPassCount; ++p )
            {
                const std::uint64_t d = fuseprobe::tlNodes[ p ] - probeBefore[ p ];
                if( d != 0 )
                {
                    ++sawNode;
                    fuseprobe::gFiles[ p ].fetch_add( 1, std::memory_order_relaxed );
                }
                if( d > maxPass )
                {
                    maxPass = d;
                }
                fuseprobe::gNodes[ p ].fetch_add( d, std::memory_order_relaxed );
            }
            fuseprobe::gNodesMaxPass.fetch_add( maxPass, std::memory_order_relaxed );
            fuseprobe::gHist[ sawNode ].fetch_add( 1, std::memory_order_relaxed );
            fuseprobe::gFilesTotal.fetch_add( 1, std::memory_order_relaxed );
        }
#endif
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
            std::string_view refCapSv;   // the @reference capture's name — "reference.import" routes the using-declaration role (r9 loss bucket 1)
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
                        refCapSv = capSv;
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

            // the gated capture classes — r3 q10 constants (plus the §7b CUDA memory-space policy for the
            // uninitialized C++ shape, which needs the captured declaration node), JS export/prototype
            // assignments — in one drop decision (see dropGatedCapture for the per-class rationale and why
            // none of this can live in the query as a #match?/#eq? predicate).
            if( isDef && dropGatedCapture( defCapSv, le.lang, nameTxt, nameNode, roleNode, src ) )
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
            // defBodyNodeOf = the `body:` field, PLUS the macro-edges round's one addition: a #define's
            // replacement text (`value:` field) is adopted as a macro symbol's body, set before the climb
            // below so the climb is skipped for macros.
            TSNode body    = defBodyNodeOf( roleNode, kind );
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
                    // Adopt an ancestor's span only if roleNode sits OUTSIDE its body — i.e. roleNode is the
                    // ancestor's own signature/declarator (the C++ function_declarator → function_definition
                    // hop this climb exists for). A def spelled INSIDE the body is a different, NESTED
                    // definition — a JS/TS named const-closure (`const f = (..) => {..}` in a function body) —
                    // and adopting here broadcast the encloser's whole span (loc/cx/params/nest) onto every
                    // such closure (webpack lib/html/syntax.js: eight closures inside the 3439-line `tokenize`
                    // all reported loc=3439 cx=487). The enclosing statement_block is not in the scope-stop
                    // list above (only C-family compound_statement/block are), so nested defs escaped upward;
                    // containment is the grammar-agnostic stop. Gate: test/jsnestedcheck.sh.
                    const TSNode pb = ts_node_child_by_field_name( p, "body", 4 );
                    if( !ts_node_is_null( pb ) )
                    {
                        if( !spanContains( pb, roleNode ) ) { defNode = p; body = pb; }
                        break;
                    }
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
            const auto [ cxVal, ccxVal, nestVal, localsVal, ppAltVal, humpsVal, deepVal, evVal, evWhyVal ] = fnOrMethod ? complexityOf( defNode, src, le.lang ) : Complexity{ 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, {} };
            d.cx        = cxVal;
            d.ccx       = ccxVal;
            d.locals    = localsVal;   // Phase 1: floor count, C/C++ only (model.h localsCountedLang) — 0 elsewhere, never emitted there
            // ppalt disclosure (model.h Symbol::ppAlt). Saturating at 65535 on purpose: a def past that
            // bound is beyond every triage threshold, and the attribute's claim ("the body carries
            // alternatives") is already made at 1.
            d.ppAlt     = fnOrMethod ? std::uint16_t( ppAltVal > 65535u ? 65535u : ppAltVal ) : std::uint16_t( 0 );
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
            // essential complexity (model.h Symbol::ev): already saturated inside ev_finalize; 0 for
            // non-function kinds and outside evCountedLang, matching the emitters' omission rule.
            d.ev        = fnOrMethod ? std::uint16_t( evVal > 65535u ? 65535u : evVal ) : std::uint16_t( 0 );
            d.evWhy     = fnOrMethod ? evWhyVal : std::array<std::uint8_t, kEvWhyTagCount>{};
            d.kind      = kind;
            d.lang      = le.lang;
            d.name      = defNameFromCapture( le.lang, nameTxt );
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
            else if( kind == SymKind::Macro )
            {
                captureMacroBodyCalls( roleNode, fileId, le.lang, src, refs );   // macro-edges: the graph connects THROUGH the macro
            }
            }
            else if( isRef )
            {
                // H4: a C++ cast keyword is not a call — see isCppCastKeyword. Valid input, skipped, no alert.
                if( le.lang == Lang::Cpp && isCppCastKeyword( nameTxt ) )
                {
                    continue;
                }

                // using-declaration re-exports (r9 loss bucket 1): @reference.import marks the C++
                // `using ns::name;` tags pattern. The site becomes a role="import" use-site of the target
                // (never a call edge — graph.h admits Call+Macro only), and the grammar KEYWORD forms
                // (`using namespace ns;` / `using enum E;`) are dropped here at capture time, where the
                // query predicate a tags pattern cannot express IS enforceable (see the helper's note).
                const bool isImportRef = ( refCapSv == "reference.import" );
                if( isImportRef && usingDeclarationIsDirective( roleNode ) )
                {
                    continue;
                }

                RawRef r;
                r.fileId    = fileId;
                r.startByte = ts_node_start_byte( roleNode );
                r.line      = ts_node_start_point( roleNode ).row + 1;   // ABS-3: 1-based use-site line for --uses
                r.lang      = le.lang;
                r.role      = isImportRef ? RefRole::Import : RefRole::Call;   // ABS-3: @reference.call is a call use-site; @reference.import a using-decl re-export
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

                if( !isImportRef )                                                       // an import site has no receiver and no argument list —
                {                                                                        //   the defaults (RecvKind::None, argCountKnown=false) are the truth
                    auto [ rk, rv ] = receiverOf( nameNode, le.lang, src );              // P2-D: `this`/`self`/`x` receiver shape
                    r.recv = rk;  r.recvVar = std::move( rv );                           //   → one-hop narrowing in resolve.h
                    auto [ ac, ak ] = callArity( nameNode, le.lang, src );               // B2.2: call-site positional arg count
                    r.argCount = ac;  r.argCountKnown = ak;                              //   → arity filter in graph.h
                }
                refs.push_back( std::move( r ) );
            }
        }
    }
}

}   // namespace

// =====================================================================================
// The markitdown-bridge doc cache, lifted out of ingest()'s doc post-pass worker (that function is
// already the file's largest — the logic reads better named). A doc that needs the BRIDGE
// (pdf/docx/pptx/xlsx) costs a popen + a Python-CLI start per file (~seconds), and the post-pass
// reruns every invocation by design — so on a machine WITH markitdown installed every warm run paid
// it (measured: 3.2 s wall, ~1 ms task-clock, for the two present/ decks). The extraction is a pure
// function of the file BYTES, so bridge results are cached under the shared cache dir keyed by
// content hash; the "ripwire-" prefix keeps eviction inside the existing family sweep (whose
// age+size caps also bound a markitdown UPGRADE's staleness — the input-bytes key alone would never
// notice one). An EMPTY extraction is never cached: "" means markitdown absent or errored — a fact
// about the machine, not the bytes. Hand-rolled kinds (ipynb/html/csv) stay uncached (microseconds);
// cacheEnabled=false (--no-cache) bypasses the sidecar entirely. tmpKey keeps concurrent workers'
// unpublished temp files distinct; the publish itself is a whole-file rename, so a concurrent
// reader sees every byte or none.
inline std::string docTextViaBridgeCache( const std::string& path, const std::string& ext, bool cacheEnabled, std::uint32_t tmpKey )
{
    std::string text;
    std::string bridgeBlobPath;
    if( cacheEnabled && docparse::docKindOf( ext ) == docparse::DocKind::Markitdown )
    {
        std::string docBytes;
        if( docparse::detail::readWholeFile( path, docBytes ) )
        {
            char blobName[ 64 ];
            std::snprintf( blobName, sizeof( blobName ), "ripwire-docmd-%016llx.bin",
                           static_cast<unsigned long long>( fnv1a64( docBytes ) ) );
            bridgeBlobPath = quality::resolveCacheBlobPath( quality::cacheDirLadder(), blobName );
            docparse::detail::readWholeFile( bridgeBlobPath, text );   // miss ⇒ text stays empty
        }
    }
    if( text.empty() )
    {
        text = docparse::parseDocFile( path, ext );
        if( !text.empty() && !bridgeBlobPath.empty() )
        {
            const std::string tmp = bridgeBlobPath + ".tmp" + std::to_string( tmpKey );
            std::FILE* fp = std::fopen( tmp.c_str(), "wb" );
            if( fp != nullptr )
            {
                const bool wroteAll = std::fwrite( text.data(), 1, text.size(), fp ) == text.size();
                std::fclose( fp );
                if( !wroteAll || std::rename( tmp.c_str(), bridgeBlobPath.c_str() ) != 0 )
                {
                    std::remove( tmp.c_str() );
                }
            }
        }
    }
    return text;
}

// Per-worker capacity floor for the COLD parse pool, sized from the crawl's parseable byte count.
//
// WHY THIS EXISTS. The warm reserve sums cached FileFacts, so it only runs when a cache is loaded; a cold
// run reserved nothing and every accumulator doubled up from zero — ~500 whole-vector reallocations per
// run, on the one path where all workers hammer the allocator at once.
//
// WHAT IT IS WORTH, MEASURED, so nobody re-litigates it from the plausible-sounding story. Against pristine
// HEAD on three cold corpora (this repo at ~1.1k files, plus a 2.4k-file and a 0.7k-file ObjC++/C++ tree),
// --no-cache on both sides, 9 reps: heap allocations about -505 / -465 / -420, which is only -0.29% /
// -0.06% / -0.12% of each run's total. Peak live bytes is a WASH — repeat measurements of the very same
// binaries move it between -0.6 and +2.0 MB, i.e. the sign is not stable, so the "stranded buffers" story
// does not survive contact with an allocator that reuses them. Parse-pool wall clock is a NULL RESULT: two
// independent 15-pair interleaved runs disagreed in SIGN on two of the three corpora, so machine drift
// exceeds the effect. This removes real work; it does not make the tool measurably faster, and it does not
// measurably shrink it either. Not a speedup — do not cite it as one.
//
// BYTES, NOT FILE COUNT, IS THE PREDICTOR. Over ten corpora spanning C/C++, ObjC++, Rust, Swift, Python/TS
// and generated C, refs-per-FILE spans 190x (10.6 … 2017.6) while refs-per-BYTE spans 11x; binds-per-file
// spans 1325x against 432x per byte. A file count cannot size the two families that hold the memory. Each
// divisor is the bytes-per-element of roughly the LEAST dense corpus measured, so the estimate is a floor,
// not a forecast, and lands under the real total nearly everywhere.
//
// WHY THE CAP, which is the part that is easy to get wrong. Allocations saved grow like log2( reserve )
// while the memory risked grows like the reserve itself, so the efficient point is small: measured, a
// 256-element cap keeps 84-94% of the allocations an uncapped mean-sized reserve saves, bounded by
// 256 * ( 168 + 144 + 32 + 72 ) B * nthreads ~= 1.9 MB in the worst case where every worker finishes under
// it. Reserving each worker the corpus MEAN is worse than it looks: work is uneven (the busiest worker
// holds 1.3-5.2x the mean, median ~1.9x), so a mean-sized reserve over-allocates the below-mean majority
// to suit one worker — that variant measured 1-2.5 MB of extra peak live bytes for ~60 more allocations.
//
// ROUNDED DOWN TO A POWER OF TWO. An empty vector grows 1, 2, 4, 8, … so its final capacity for n elements
// is exactly the next power of two; starting from 2^j the ladder is 2^j, 2^(j+1), … — a SUBSEQUENCE of the
// same powers. Seeding with a power of two therefore lands on the identical final capacity for any worker
// that reaches it, and can only remove growth steps. An arbitrary seed cannot say that: a vector reserved
// to R that needs R+1 doubles to 2R and can finish above where it would have landed alone.
//
// FFI and route accumulators get nothing on purpose: across the same ten corpora they total 0-363 entries
// and are non-empty on only 0-11 of 18 workers, so a reserve there would be pure waste.
struct ColdParseReserve
{
    std::size_t defs;
    std::size_t refs;
    std::size_t incs;
    std::size_t binds;
};

// fileLang and fileByteSize are the crawl's two parallel per-file arrays; a file counts toward the estimate
// only when it has a grammar, which is the same predicate the divisors were calibrated under. Keeping the
// predicate next to the constants is deliberate: change one and the other stops being calibrated.
inline ColdParseReserve coldParseReserve( std::span<const LangEntry* const> fileLang,
                                          std::span<const std::uintmax_t> fileByteSize,
                                          unsigned nthreads ) noexcept
{
    VERIFY( nthreads >= 1 );   // caller derives it from min( hardware_concurrency, nfiles ) with nfiles >= 1
    VERIFY( fileLang.size() == fileByteSize.size() );

    std::size_t parseableBytes = 0;
    for( std::size_t fileId = 0; fileId < fileLang.size(); ++fileId )
    {
        const LangEntry* le = fileLang[ fileId ];
        if( le != nullptr && le->grammar != nullptr )
        {
            parseableBytes += static_cast<std::size_t>( fileByteSize[ fileId ] );
        }
    }

    // bytes per element, calibrated 2026-08-10 against the ten-corpus census described above
    constexpr std::size_t kBytesPerDef  =  2400;
    constexpr std::size_t kBytesPerRef  =   800;
    constexpr std::size_t kBytesPerInc  = 20000;
    constexpr std::size_t kBytesPerBind =  4000;
    constexpr std::size_t kCapPerThread =   256;

    // Integer division throughout: no float, and no overflow — parseableBytes is a byte count, every divisor
    // is a nonzero constant, and nthreads is at least 1. An all-documentation tree yields 0 for every family,
    // and reserve( 0 ) is a no-op.
    const auto perThread = [ parseableBytes, nthreads, cap = kCapPerThread ]( std::size_t bytesPerElem ) noexcept
    {
        return std::min( std::bit_floor( parseableBytes / bytesPerElem / nthreads ), cap );
    };

    const ColdParseReserve r{ perThread( kBytesPerDef ), perThread( kBytesPerRef ),
                              perThread( kBytesPerInc ), perThread( kBytesPerBind ) };

    // The two properties the whole argument above rests on: every value is a power of two (so the doubling
    // ladder is unchanged) and none exceeds the cap (so the waste stays bounded).
    VERIFY( r.defs  <= kCapPerThread && ( r.defs  == 0 || std::has_single_bit( r.defs  ) ) );
    VERIFY( r.refs  <= kCapPerThread && ( r.refs  == 0 || std::has_single_bit( r.refs  ) ) );
    VERIFY( r.incs  <= kCapPerThread && ( r.incs  == 0 || std::has_single_bit( r.incs  ) ) );
    VERIFY( r.binds <= kCapPerThread && ( r.binds == 0 || std::has_single_bit( r.binds ) ) );
    return r;
}

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
        auto [ crawledPaths, oversizeSkipped, taxonomySkips ] = collectSources( rootDir, excludeSubstr, maxFileBytes, excludeLabel );
        result.files           = std::move( crawledPaths );
        result.skippedOversize = std::move( oversizeSkipped );
        result.crawlSkips      = std::move( taxonomySkips );   // §L1: excluded / unsupported-ext / unindexed exts
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
    std::vector<FileHealth> fileHealth( nfilesEarly );   // §L1: one slot per fileId, one WRITER per slot
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
                if( e.grammar == nullptr || e.querySub.empty() || !present[ i ] )
                {
                    continue;   // querySub "" = markdown: a grammar with NO tags.scm (custom walk) — nothing to compile
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

        // Per-file byte sizes are wanted in two places below — the cold-path reserve, and the
        // longest-file-first work order. Fill at most once, on demand, so a warm run that also skips
        // the work order still performs no stat pass at all (exactly as before this was hoisted).
        std::vector<std::uintmax_t> fileByteSize;
        const auto ensureFileByteSize = [ & ]()
        {
            if( !fileByteSize.empty() )
            {
                return;
            }
            fileByteSize.assign( nfiles, 0 );
            std::error_code ec;
            for( std::size_t fileId = 0; fileId < nfiles; ++fileId )
            {
                ec.clear();
                fileByteSize[ fileId ] = fs::file_size( result.files[ fileId ], ec );
                if( ec )
                {
                    fileByteSize[ fileId ] = 0;
                }
            }
        };

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
        else
        {
            // Cold: no cache to size from, so size the accumulators from the crawl's parseable byte
            // count. coldParseReserve() carries the calibration and the reasoning behind the numbers.
            PROFILE_SCOPE_DESCRIBE( "ingest/parse-pool: prepare cold reserve" );

            ensureFileByteSize();
            const ColdParseReserve cold = coldParseReserve( fileLang, fileByteSize, nthreads );
            for( unsigned t = 0; t < nthreads; ++t )
            {
                tDefs[ t ].reserve( cold.defs );
                tRefs[ t ].reserve( cold.refs );
                tIncs[ t ].reserve( cold.incs );
                tBinds[ t ].reserve( cold.binds );
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

                ensureFileByteSize();   // already filled by the cold-path reserve above; a no-op there

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
                                fileHealth[ fileId ] = hit->health;   // §L1: health is a cached FACT, not a re-derivation
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

                        // hostile/degenerate YAML guard — MEMORY-SAFETY load-bearing, not just a perf guard:
                        // tree-sitter-yaml's scanner serialize() corrupts memory past ~253 block indent levels
                        // (see kMaxYamlNestDepth in ingest.h; the vendored scanner also carries the bounds fix
                        // under third_party/patches/yaml/, so this is the FIRST of two independent layers).
                        // Same house skip style as the JSON guard above: refuse BEFORE the parse, one stderr line.
                        if( le->lang == Lang::Yaml && yamlNestsTooDeep( bytes ) )
                        {
                            std::fprintf( stderr, "[ripwire] %s: yaml nesting > %u levels — treated as data, not config (skipped)\n",
                                          path.c_str(), kMaxYamlNestDepth );
                            continue;
                        }

                        if( le->lang == Lang::Markdown )
                        {
                            // hostile/degenerate markdown guard — MEMORY-SAFETY load-bearing, the yaml pair's
                            // twin: tree-sitter-markdown's scanner serialize() memcpys its open-blocks stack
                            // with NO bounds check (OOB at ~255 nested blockquote/list markers; see
                            // kMaxMdBlockDepth in ingest.h). The vendored scanner also carries the clamp under
                            // third_party/patches/markdown/, so this is the FIRST of two independent layers.
                            if( mdNestsTooDeep( bytes ) )
                            {
                                std::fprintf( stderr, "[ripwire] %s: markdown blockquote/list nesting > %u levels — treated as data, not a doc (skipped)\n",
                                              path.c_str(), kMaxMdBlockDepth );
                                continue;
                            }
                            if( !prepareParserFor( pg.p, *le ) )
                            {
                                continue;
                            }
                            TreeGuard mdTree( parseTree( pg.p, bytes ) );
                            if( mdTree.get() == nullptr )
                            {
                                continue;
                            }
                            fileHealth[ fileId ] = measureFileHealth( ts_tree_root_node( mdTree.get() ), bytes );
                            const std::string stem = fs::path( path ).stem().string();
                            const std::size_t firstNewDefIndex = tDefs[ t ].size();
                            extractMarkdown( static_cast<std::uint32_t>( fileId ), bytes, stem, ts_tree_root_node( mdTree.get() ), tDefs[ t ], tRefs[ t ] );
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
                            fileHealth[ fileId ] = measureFileHealth( root, bytes );   // §L1 — before `bytes` can be moved below
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

        // P1-15: the SAME drift count, carried out of the function instead of only to stderr. The MCP
        // server discloses it per incremental pass (`_reingest`), which it could not do from an env-gated
        // print. Read once here, after the pool join that orders every worker's increment.
        result.reparsedFiles = reparsedCount.load( std::memory_order_relaxed );

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
            saveCache( std::string( cacheFile ), rootDir, result.files, fileHash, fileStatSize, fileStatMtime, fileHealth, rawDefs, rawRefs, rawIncs, rawBinds, rawFfis, rawRouteDefs, rawRouteUses, captureValueUses );
        }
    }

    result.fileHealth = std::move( fileHealth );   // §L1: after saveCache, before the (unmeasured) doc pass

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

                            std::string text = docTextViaBridgeCache( result.files[ fid ], ext, !cacheFile.empty(), fid );
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
            s.ppAlt        = d.ppAlt;    // ppalt disclosure: preproc alternative branches in the body (model.h)
            s.params       = d.params;   // Q4: parameter count (fns/methods)
            s.arityExact   = d.arityExact;   // B2.2: params is a fixed call-comparable arity
            s.maxNest      = d.maxNest;  // Q4: max control nesting (fns/methods)
            s.humps        = d.humps;   // nesting profile: regions reaching quality::kNestBar (model.h)
            s.deepLoc      = d.deepLoc; // nesting profile: lines inside them, a FLOOR (model.h)
            s.ev           = d.ev;      // essential complexity, a FLOOR (model.h; 0 outside evCountedLang)
            s.evWhy        = d.evWhy;   // per-tag contributing-jump counts (model.h kEvWhyTagTable order)
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
            ref.startByte   = r.startByte;                // shadow fix round: for the block-span containment test
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
                       if( a.var != b.var )
                       {
                           return a.var < b.var;
                       }
                       // L3: a decl can emit BOTH a Rule-2 type record and a fn record at one (file, byte, var) —
                       // kind+typeName make the order strict, so the merged-across-threads sort is a total order.
                       if( a.kind != b.kind )
                       {
                           return a.kind < b.kind;
                       }
                       return a.typeName < b.typeName;
                   } );
        result.bindings.resize( rawBinds.size() );
        DefSweep bindSweep{ defSpans, fileSpanStart };
        std::size_t outBindIndex = 0;
        for( RawBind& rb : rawBinds )   // rawBinds consumed here → move its 2 strings into the Binding
        {
            Binding& b = result.bindings[ outBindIndex++ ];
            b.fileId     = rb.fileId;
            b.kind       = rb.kind;
            b.spanStart  = rb.spanStart;   // shadow fix round: the declaring block's span rides through
            b.spanEnd    = rb.spanEnd;
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

    // macro-edges round: the corpus-wide role="macro" retag (model.h). AFTER the model is assembled and
    // AFTER saveCache (which stores the per-file truth, role=Call) — a #define added in one file must
    // re-judge every OTHER file's cached call sites on the next run, so the retag can never be persisted.
    retagMacroCallReferences( result );

    // r9 shadow suppression (model.h): a reference inside a function whose LOCAL declarations bind the same
    // name as a variable belongs to the local, not to any same-named indexed symbol — erase it here, the one
    // choke point BOTH consumers sit downstream of (--uses reads result.references; buildGraph resolves call
    // edges from them), so the false --uses rows and the false call edge die in the same pass. AFTER the
    // macro retag (role="macro" is preprocessor evidence and stays) and AFTER saveCache (per-file truth is
    // persisted unsuppressed; the collision gate depends on the whole corpus' symbols, so the judgment can
    // never be cached per-file — same reasoning as the retag above).
    suppressShadowedReferences( result );

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
// The pass itself rides rw::findByte (src/infra/fixedStr.h) — a NEON/SSE2 find-'\n' kernel that is EXACT, so the
// offsets are bit-identical to the byte-at-a-time loop this replaced and determinism is untouched. '\r' is
// not a line break here and never was. bench/bench_newline_ab.cpp races the two against libc memchr and
// asserts all three agree byte-for-byte before it reports a number; the kernel won at ~1.4x over memchr.
inline std::vector<std::uint32_t> buildNewlineOffsets( std::string_view src )
{
PROFILE_SCOPE_DESCRIBE( "strings: buildNewlineOffsets (byte scan for newline)" );
    std::vector<std::uint32_t> off;
    const char* const          begin = src.data();
    const char*                first = begin;
    const char* const          last  = begin + src.size();
    while( first < last )
    {
        first = rw::findByte( first, last, '\n' );   // NEON/SSE2 kernel, exact — same answer as the byte loop it replaced
        if( first == last )
        {
            break;
        }
        off.push_back( std::uint32_t( first - begin ) );
        ++first;
    }
    return off;
}
inline std::uint32_t lineAtByte( const std::vector<std::uint32_t>& nlOffsets, std::uint32_t bytePos ) noexcept
{
    return std::uint32_t( 1 + ( std::lower_bound( nlOffsets.begin(), nlOffsets.end(), bytePos ) - nlOffsets.begin() ) );
}

// ---- shared AST-query pass (--match / --lint) ----
// One compiled query, plus the group it answers for. Grouping is a property of the QUERY, not of the walk:
// a worker executes every query a file's grammar has and files the captures into that query's own bucket.
struct GroupedQuery
{
    TSQuery*      query = nullptr;
    std::string   tag;
    std::uint32_t groupIndex = 0;
};

// Every query one grammar has to answer, in BOTH shapes. `perSpec` is one compiled query per spec, the
// literal thing each spec asked for. `combined` is all of those specs' patterns compiled into ONE query.
//
// The difference is the number of TREE WALKS. ts_query_cursor_exec walks the subtree once per query, so
// forty-odd single-pattern queries walked every C++ file forty-odd times to ask forty-odd independent
// questions of the same nodes -- and the profile put 87% of --lint's whole cost inside that loop. A query
// holding forty patterns walks once and runs them off one shared automaton; each match's `pattern_index`
// says which spec answered, so nothing about the RESULT changes.
//
// Both shapes are kept: `combined` is what the workers run, `perSpec` is the fallback if the concatenated
// source does not compile (or does not report the pattern count its parts add up to), and it also owns the
// tag and group each pattern belongs to.
struct GrammarQueries
{
    std::vector<GroupedQuery>  perSpec;
    TSQuery*                   combined = nullptr;   // nullptr = degraded to one tree walk per spec
    std::vector<std::uint32_t> patternOwner;         // combined pattern index -> index into perSpec
};

// Compile every group's specs for ONE grammar, in both shapes GrammarQueries holds. Called once per
// grammar the corpus can reach, from its own thread: the language tables it reads are immutable and each
// call touches nothing but its own result.
GrammarQueries compileGrammarQueries( const TSLanguage* g, const std::vector<AstQueryGroup>& groups )
{
    GrammarQueries gqs;
    std::string    combinedSrc;
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )
    {
        if( groups[groupIndex].specs == nullptr )
        {
            continue;
        }
        for( const AstQuerySpec& spec : *groups[groupIndex].specs )
        {
            std::uint32_t off = 0;  TSQueryError err = TSQueryErrorNone;
            TSQuery*      q   = ts_query_new( g, spec.query.data(), static_cast<std::uint32_t>( spec.query.size() ), &off, &err );
            if( q == nullptr )
            {
                continue;   // this spec is not valid for this grammar -- a C++ query simply does not fire on Python
            }
            const std::uint32_t patterns = ts_query_pattern_count( q );
            for( std::uint32_t patternIndex = 0; patternIndex < patterns; ++patternIndex )
            {
                gqs.patternOwner.push_back( static_cast<std::uint32_t>( gqs.perSpec.size() ) );
            }
            gqs.perSpec.push_back( { q, spec.tag, static_cast<std::uint32_t>( groupIndex ) } );
            combinedSrc.append( spec.query );
            combinedSrc.push_back( '\n' );   // a spec may end in a `;` line comment; never let it swallow the next
        }
    }
    if( !gqs.perSpec.empty() )
    {
        std::uint32_t off = 0;  TSQueryError err = TSQueryErrorNone;
        TSQuery*      comb = ts_query_new( g, combinedSrc.data(), static_cast<std::uint32_t>( combinedSrc.size() ), &off, &err );
        if( comb != nullptr && ts_query_pattern_count( comb ) == static_cast<std::uint32_t>( gqs.patternOwner.size() ) )
        {
            gqs.combined = comb;
        }
        else
        {
            // Patterns that each compile alone are not GUARANTEED to compile together, and a pattern count that
            // does not add up would misattribute every tag. Either way the per-spec walks are still correct --
            // only slower -- so this degrades rather than fails.
            if( comb != nullptr )
            {
                ts_query_delete( comb );
            }
            DEGRADED_PATH_ALERT( "astQuery: combined per-grammar query did not compile - falling back to one tree walk per spec" );
        }
    }
    return gqs;
}

// Defined further down this file, next to the rest of the unreachable-code check's helpers, and
// forward-declared here so the shared file walk can drive it — the same split as
// ingest()/astQueryGrouped() already use above.
inline void ur_walkTree( TSNode root, std::uint32_t fileId, std::string_view src, const std::vector<std::uint32_t>& nlOffsets, std::vector<AstMatch>& hits );

// Drive every BUILT-IN WALK group over one already-parsed file, each into its own bucket. Called from the
// shared worker loop with the tree and newline index the query groups are about to use, which is the whole
// point: a walk group exists so a non-query check can stop re-reading and re-parsing the corpus for itself.
inline void runWalkGroups( const std::vector<AstQueryGroup>& groups, TSNode root, std::uint32_t fileId, std::string_view bytes,
                           const std::vector<std::uint32_t>& nlOffsets, std::vector<std::vector<AstMatch>>& perGroupHits )
{
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )
    {
        if( groups[groupIndex].walk == AstWalk::UnreachableCode )
        {
            ur_walkTree( root, fileId, bytes, nlOffsets, perGroupHits[groupIndex] );
        }
    }
}

// §L3: grammar-applicability disclosure for AstQueryGroup::grammarsOut / eligibleFilesOut (see ingest.h for
// the field docs). A SEPARATE probe over the full kLangTable rather than a read of astQueryGrouped's own
// byGrammar table, because byGrammar only ever holds grammars the CORPUS is present for — exactly the
// information this exists to supply when the honest answer is "none of them" (a query that compiles fine
// for java/csharp/typescript but the corpus is Python-only). Cost is bounded by kLangTable's size (~37
// rows) per requesting group's specs, paid only when a caller asks — every existing --lint / --lint-rules
// call site leaves both fields null, so this is a no-op for them.
static void computeGrammarDisclosure( const IngestResult& ing, const std::vector<AstQueryGroup>& groups )
{
    for( const AstQueryGroup& grp : groups )
    {
        if( grp.grammarsOut == nullptr && grp.eligibleFilesOut == nullptr )
        {
            continue;
        }
        if( grp.specs == nullptr )
        {
            continue;   // a walk-only group has no query to probe grammars for
        }
        std::vector<const TSLanguage*> triedGrammars;   // dedup tracker: several extensions share one grammar
        std::vector<const TSLanguage*> okGrammars;       // grammars at least one spec in this group compiled against
        std::vector<std::string>       okNames;          // grammarsOut dedup: TWO distinct grammar OBJECTS can
                                                          // share one display NAME (tree_sitter_typescript and
                                                          // tree_sitter_tsx are both querySub "typescript"; the
                                                          // CUDA grammar reuses "cpp") — okGrammars stays one
                                                          // entry per compiling OBJECT (eligible_files needs
                                                          // every one of them), grammarsOut stays one per NAME.
        for( const LangEntry& le : kLangTable )
        {
            if( le.grammar == nullptr || le.querySub.empty() )
            {
                continue;   // no grammar (markdown) or no tags.scm surface to compile a --match query against
            }
            const TSLanguage* g = le.grammar();
            if( std::find( triedGrammars.begin(), triedGrammars.end(), g ) != triedGrammars.end() )
            {
                continue;
            }
            triedGrammars.push_back( g );
            bool compiledAny = false;
            for( const AstQuerySpec& spec : *grp.specs )
            {
                std::uint32_t off = 0; TSQueryError err = TSQueryErrorNone;
                if( TSQuery* probe = ts_query_new( g, spec.query.data(), static_cast<std::uint32_t>( spec.query.size() ), &off, &err ) )
                {
                    ts_query_delete( probe );
                    compiledAny = true;
                    break;
                }
            }
            if( compiledAny )
            {
                okGrammars.push_back( g );
                if( grp.grammarsOut != nullptr )
                {
                    const std::string name( le.querySub );
                    if( std::find( okNames.begin(), okNames.end(), name ) == okNames.end() )
                    {
                        okNames.push_back( name );
                        grp.grammarsOut->push_back( name );
                    }
                }
            }
        }
        if( grp.eligibleFilesOut != nullptr )
        {
            std::size_t eligible = 0;
            for( std::size_t fileId = 0; fileId < ing.files.size(); ++fileId )
            {
                const std::string ext = lowerExtensionOf( diskPath( ing, std::uint32_t( fileId ) ) );
                const LangEntry*  fle = lookupLang( ext );
                if( fle == nullptr || fle->grammar == nullptr )
                {
                    continue;
                }
                if( std::find( okGrammars.begin(), okGrammars.end(), fle->grammar() ) != okGrammars.end() )
                {
                    ++eligible;
                }
            }
            *grp.eligibleFilesOut = eligible;
        }
    }
}

std::vector<std::vector<AstMatch>> astQueryGrouped( const IngestResult& ing, const std::vector<AstQueryGroup>& groups,
                                                    std::vector<std::string>* keptBytesOut )
{
    std::vector<std::vector<AstMatch>> out( groups.size() );
    if( keptBytesOut != nullptr )
    {
        keptBytesOut->assign( ing.files.size(), std::string() );   // sized BEFORE the pool starts: workers only ever write distinct slots
    }
    bool                               anySpecs = false;
    bool                               anyWalk  = false;
    for( const AstQueryGroup& group : groups )
    {
        anySpecs = anySpecs || ( group.specs != nullptr && !group.specs->empty() );
        anyWalk  = anyWalk  || ( group.walk != AstWalk::None );
    }
    // A walk group is work even with no spec anywhere: it needs the parse, not a compiled query.
    if( ( !anySpecs && !anyWalk ) || ing.files.empty() )
    {
        return out;
    }

    // The grammars this CORPUS can actually reach. ts_query_new is not cheap -- compiling every spec
    // against every one of the sixteen linked grammars was the single largest serial cost of a `--lint`
    // run, and on a corpus holding one language fifteen sixteenths of it answered a question no file
    // could ask. A grammar with no file to run on contributes no match, so not compiling for it changes
    // nothing a caller can see -- except the "did not compile for ANY grammar" disclosure below, which is
    // a statement about the QUERY and not about the corpus, and is therefore still decided over the full
    // table.
    // The `.h` remap is deliberately conservative: whether a header is ObjC is a fact about its BYTES,
    // read per file inside the walk, so any `.h` at all admits the ObjC grammar here.
    std::vector<const TSLanguage*> presentGrammars;
    {
        bool anyCHeader = false;
        for( std::size_t fileId = 0; fileId < ing.files.size(); ++fileId )
        {
            const std::string ext = lowerExtensionOf( diskPath( ing, std::uint32_t( fileId ) ) );
            anyCHeader = anyCHeader || ext == ".h";
            const LangEntry* le = lookupLang( ext );
            if( le == nullptr || le->grammar == nullptr )
            {
                continue;
            }
            const TSLanguage* g = le->grammar();
            if( std::find( presentGrammars.begin(), presentGrammars.end(), g ) == presentGrammars.end() )
            {
                presentGrammars.push_back( g );
            }
        }
        const LangEntry* objcLe = anyCHeader ? lookupLang( ".m" ) : nullptr;
        if( objcLe != nullptr && objcLe->grammar != nullptr
            && std::find( presentGrammars.begin(), presentGrammars.end(), objcLe->grammar() ) == presentGrammars.end() )
        {
            presentGrammars.push_back( objcLe->grammar() );
        }
    }

    // Compile each spec against every DISTINCT grammar it is valid for (up front, single-threaded). Queries
    // are immutable after creation → shared read-only across workers; only the cursor is per-thread.
    // ONE GRAMMAR PER THREAD. Compiling is per-grammar independent work over read-only language tables --
    // the same assumption the ingest prewarm already makes when it launches ts_query_new off-thread -- and
    // it was the longest SERIAL stretch of a --lint run: the file walk that follows is fully parallel, so
    // a single-threaded compile set the floor on the whole verb. Results land in a vector indexed by the
    // deterministic presentGrammars order and are installed in that order afterwards, so no thread's
    // arrival time reaches the map, let alone the output.
    HashMap<const TSLanguage*, GrammarQueries> byGrammar;
    {
    PROFILE_SCOPE_DESCRIBE( "astQuery: compile queries per grammar" );
    std::vector<GrammarQueries> compiledPerGrammar( presentGrammars.size() );
    {
        unsigned compileHw = std::thread::hardware_concurrency();
        if( compileHw == 0 )
        {
            compileHw = 1;
        }
        const unsigned           compileThreads = static_cast<unsigned>( std::min<std::size_t>( compileHw, std::max<std::size_t>( presentGrammars.size(), std::size_t( 1 ) ) ) );
        std::atomic<std::size_t> nextGrammar{ 0 };
        std::vector<std::thread> compilers;  compilers.reserve( compileThreads );
        for( unsigned worker = 0; worker < compileThreads; ++worker )
        {
            compilers.emplace_back( [ & ]()
            {
                for( ;; )
                {
                    const std::size_t grammarIndex = nextGrammar.fetch_add( 1, std::memory_order_relaxed );
                    if( grammarIndex >= presentGrammars.size() )
                    {
                        break;
                    }
                    compiledPerGrammar[grammarIndex] = compileGrammarQueries( presentGrammars[grammarIndex], groups );
                }
            } );
        }
        for( std::thread& th : compilers )
        {
            th.join();
        }
    }
    for( std::size_t grammarIndex = 0; grammarIndex < presentGrammars.size(); ++grammarIndex )
    {
        if( !compiledPerGrammar[grammarIndex].perSpec.empty() )
        {
            byGrammar.emplace( presentGrammars[grammarIndex], std::move( compiledPerGrammar[grammarIndex] ) );
        }
    }
    }
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )   // warn once if a spec compiled for NO grammar (malformed query)
    {
        if( groups[groupIndex].specs == nullptr )
        {
            continue;
        }
        for( const AstQuerySpec& spec : *groups[groupIndex].specs )
        {
            bool any = false;
            for( const auto& [g, qs] : byGrammar )
            {
                for( const GroupedQuery& gq : qs.perSpec )
                {
                    if( gq.groupIndex == groupIndex && gq.tag == spec.tag )
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
                // Nothing in the corpus could run it — but "did not compile for ANY grammar" is a claim about
                // the QUERY (§P0.1: a malformed query's zero must never be presented as a measurement), so it
                // is settled against the grammars this corpus does NOT hold before it is made. First success
                // wins; a C++ query on a Python-only tree is valid and stays silent, exactly as when every
                // grammar was compiled up front.
                for( const LangEntry& absent : kLangTable )
                {
                    if( any )
                    {
                        break;
                    }
                    if( absent.grammar == nullptr )
                    {
                        continue;
                    }
                    const TSLanguage* ag = absent.grammar();
                    if( byGrammar.find( ag ) != byGrammar.end() )
                    {
                        continue;   // already tried above, and it did not compile
                    }
                    std::uint32_t off = 0;  TSQueryError err = TSQueryErrorNone;
                    if( TSQuery* probe = ts_query_new( ag, spec.query.data(), static_cast<std::uint32_t>( spec.query.size() ), &off, &err ) )
                    {
                        ts_query_delete( probe );
                        any = true;
                    }
                }
                if( !any )
                {
                    std::fprintf( stderr, "ripwire: AST query did not compile for any grammar: %.*s\n", int( spec.query.size() ), spec.query.data() );
                    if( groups[groupIndex].uncompiledOut )
                    {
                        groups[groupIndex].uncompiledOut->push_back( spec.query );
                    }
                }
        }
    }

    // §L3: grammar-applicability disclosure, opt-in per group (grammarsOut / eligibleFilesOut) — a standalone
    // pass so the existing groups[] loops above stay exactly as complex as they were for every caller that
    // doesn't ask for this (--lint, --lint-rules leave both null; zero cost, zero shape change for them).
    computeGrammarDisclosure( ing, groups );

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
    std::vector<std::vector<std::vector<AstMatch>>> tHits( nthreads, std::vector<std::vector<AstMatch>>( groups.size() ) );
    std::atomic<std::size_t>                        nextSlot{ 0 };
    std::vector<std::thread>                        pool;  pool.reserve( nthreads );

    // BIGGEST FILE FIRST (longest-processing-time-first) -- the same work order, for the same reason, that
    // the ingest parse pool builds before it fans out. Handing files out in crawl order leaves the corpus's
    // largest translation unit (ripwire's own src/main.cpp: 653 KB, 40x the median) to be picked up near the
    // END of the queue, where it runs alone against an otherwise idle pool and sets the wall time by itself.
    // Sorting the queue by descending on-disk size puts the stragglers first and lets the small files fill in
    // behind them. WHICH thread parses WHICH file was never part of the output -- captures are bucketed per
    // group and sorted on a total key after the join -- so this changes scheduling and nothing else.
    std::vector<std::uint32_t> walkOrder( nfiles );
    std::iota( walkOrder.begin(), walkOrder.end(), std::uint32_t( 0 ) );
    {
        std::vector<std::uintmax_t> fileByteSize( nfiles, 0 );
        std::error_code             ec;
        for( std::size_t fileId = 0; fileId < nfiles; ++fileId )
        {
            ec.clear();
            fileByteSize[fileId] = fs::file_size( diskPath( ing, std::uint32_t( fileId ) ), ec );
            if( ec )
            {
                fileByteSize[fileId] = 0;
            }
        }
        std::stable_sort( walkOrder.begin(), walkOrder.end(),
                          [ & ]( std::uint32_t a, std::uint32_t b ) noexcept
                          {
                              if( fileByteSize[a] != fileByteSize[b] )
                              {
                                  return fileByteSize[a] > fileByteSize[b];
                              }
                              return a < b;
                          } );
    }

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
            std::string    readBuf;   // worker-local scratch, reused across files unless the read is retained below
            for( ;; )
            {
                const std::size_t slot = nextSlot.fetch_add( 1, std::memory_order_relaxed );
                if( slot >= nfiles )
                {
                    break;
                }
                const std::size_t fileId = walkOrder[slot];
                try
                {
                    const std::string& path = diskPath( ing, std::uint32_t( fileId ) );   // multi-root: labeled ing.files → on-disk path
                    const std::string ext = lowerExtensionOf( path );
                    const LangEntry* le = lookupLang( ext );
                    if( le == nullptr )
                    {
                        continue;
                    }
                    if( !readFile( path, readBuf ) )
                    {
                        continue;
                    }
                    if( looksBinary( readBuf ) )
                    {
                        continue;
                    }
                    if( ext == ".h" && looksObjC( readBuf ) )
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
                    const TSLanguage* g          = le->grammar();
                    const auto        it         = byGrammar.find( g );
                    const bool        hasQueries = ( it != byGrammar.end() && !it->second.perSpec.empty() );
                    if( !hasQueries && !anyWalk )
                    {
                        continue; // no spec applies to this grammar, and no built-in walk wants the tree either
                    }

                    // THE retention point, and the reason it is here rather than at any of the exits below:
                    // handing the read over BEFORE the tree is built means every path that follows works from
                    // the retained slot, so no exit can forget to keep it and no branch can keep it twice. When
                    // nothing is retaining, `bytes` binds the worker's own scratch and the loop reuses one
                    // buffer exactly as it always did. Markdown is already gone by here — a file with no
                    // grammar has no symbol a later pass could ask about.
                    std::string& bytes = ( keptBytesOut != nullptr ) ? ( ( *keptBytesOut )[fileId] = std::move( readBuf ) ) : readBuf;

                    if( !ts_parser_set_language( pg.p, g ) || !grammarAbiOk( g ) )
                    {
                        continue;
                    }
                    TSTree* tree = nullptr;
                    {
                    PROFILE_SCOPE_DESCRIBE( "astQuery/worker: tree-sitter parse" );
                    tree = ts_parser_parse_string( pg.p, nullptr, bytes.data(), static_cast<std::uint32_t>( bytes.size() ) );
                    }
                    if( !tree )
                    {
                        continue;
                    }
                    const TSNode root = ts_tree_root_node( tree );
                    const std::vector<std::uint32_t> nlOffsets = buildNewlineOffsets( bytes );   // one pass, then binary-search per capture

                    // Built-in walk groups first: they read the SAME tree and the SAME newline index the
                    // query groups below use, into their own per-group bucket, so nothing crosses over.
                    if( anyWalk )
                    {
                        PROFILE_SCOPE_DESCRIBE( "astQuery/worker: built-in tree walk" );
                        runWalkGroups( groups, root, std::uint32_t( fileId ), bytes, nlOffsets, tHits[t] );
                    }
                    if( !hasQueries )
                    {
                        ts_tree_delete( tree );
                        continue;   // walk-only file — no compiled spec for this grammar
                    }

                    PROFILE_SCOPE_DESCRIBE( "astQuery/worker: cursor exec + captures" );
                    // Every capture of one match, filed under the spec that owns the pattern. Shared by both
                    // execution shapes below so the ONE walk and the fallback walks cannot drift apart.
                    const auto emitCaptures = [ & ]( const TSQueryMatch& m, const GroupedQuery& owner )
                    {
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
                            PROFILE_SCOPE_DESCRIBE( "strings: capture text substr + whitespace scrub" );
                            std::string text = bytes.substr( a, cutLen );
                            for( char& ch : text )
                            {
                                if( ch == '\n' || ch == '\r' || ch == '\t' )
                                {
                                    ch = ' ';
                                }
                            }
                            tHits[t][owner.groupIndex].push_back( { std::uint32_t( fileId ), a, b, line, owner.tag, std::move( text ) } );
                        }
                    };

                    if( it->second.combined != nullptr )
                    {
                        TSQuery* const q = it->second.combined;   // ONE walk for every spec this grammar has
                        ts_query_cursor_exec( cur, q, root );
                        TSQueryMatch m;
                        while( ts_query_cursor_next_match( cur, &m ) )
                        {
                            if( !passesPredicates( q, m, bytes ) )
                            {
                                continue; // honour #eq? / #match? etc. — predicates are per PATTERN, so this reads the right ones
                            }
                            if( m.pattern_index >= it->second.patternOwner.size() )
                            {
                                continue;   // unreachable: patternOwner was verified against ts_query_pattern_count
                            }
                            emitCaptures( m, it->second.perSpec[ it->second.patternOwner[ m.pattern_index ] ] );
                        }
                    }
                    else
                    {
                        for( const GroupedQuery& gq : it->second.perSpec )
                        {
                            ts_query_cursor_exec( cur, gq.query, root );
                            TSQueryMatch m;
                            while( ts_query_cursor_next_match( cur, &m ) )
                            {
                                if( !passesPredicates( gq.query, m, bytes ) )
                                {
                                    continue; // honour #eq? / #match? etc.
                                }
                                emitCaptures( m, gq );
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
        for( GroupedQuery& gq : qs.perSpec )
        {
            ts_query_delete( gq.query );
        }
        if( qs.combined != nullptr )
        {
            ts_query_delete( qs.combined );
        }
    }

    // Per group, exactly what a standalone pass produced: merge the per-thread buckets in thread order,
    // sort on the total key, then spend each tag's own budget. Nothing crosses a group boundary.
    for( std::size_t groupIndex = 0; groupIndex < groups.size(); ++groupIndex )
    {
        const bool hasSpecs = ( groups[groupIndex].specs != nullptr && !groups[groupIndex].specs->empty() );
        if( !hasSpecs && groups[groupIndex].walk == AstWalk::None )
        {
            continue;   // a caller may pass an inert slot to keep its group indices stable
        }
        std::vector<AstMatch> merged;
        std::size_t           tot = 0;
        for( const auto& perGroup : tHits )
        {
            tot += perGroup[groupIndex].size();
        }
        merged.reserve( tot );
        for( auto& perGroup : tHits )
        {
            for( auto& m : perGroup[groupIndex] )
            {
                merged.push_back( std::move( m ) );
            }
        }
        std::sort( merged.begin(), merged.end(), [ & ]( const AstMatch& x, const AstMatch& y ) // deterministic order
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

        // A built-in walk group has no spec table to budget against, and emits ONE tag — so the per-tag
        // cap below degenerates to a single truncation of the sorted list, which is byte-for-byte the tail
        // the standalone spelling ran (collect all, sort on the same total key, resize to maxMatches).
        if( !hasSpecs )
        {
            if( merged.size() > groups[groupIndex].maxMatches )
            {
                merged.resize( groups[groupIndex].maxMatches );
            }
            out[groupIndex] = std::move( merged );
            continue;
        }

        // ── deterministic PER-SPEC cap (§P0.2), applied AFTER the sort so the survivors are a pure function of
        // the input. One POOLED budget let the noisiest query eat it: `(number_literal)` alone filled 5000, the
        // pool was path-sorted then cut, and every other rule was starved of the tail of the tree — `--lint`
        // reported goto=1 on a tree with two and do-while=0 on a tree with one. Each tag now spends its OWN
        // budget, which is exactly what a separate pass per spec would have produced (same collected set, same
        // (file, startByte) order within a tag) at the cost of ONE tree walk instead of N.
        const std::vector<AstQuerySpec>&    specs = *groups[groupIndex].specs;
        HashMap<std::string, std::uint32_t> tagSlot;   tagSlot.reserve( specs.size() * 2 );
        for( const AstQuerySpec& spec : specs )
        {
            const std::uint32_t nextSlot = static_cast<std::uint32_t>( tagSlot.size() );
            tagSlot.emplace( spec.tag, nextSlot );                          // duplicate tags share one budget, by design
        }

        std::vector<std::size_t> keptPerTag( tagSlot.size(), 0 );
        std::vector<AstMatch>    keep;   keep.reserve( merged.size() );
        for( AstMatch& m : merged )
        {
            const auto slotIt = tagSlot.find( m.tag );
            VERIFY( slotIt != tagSlot.end() );                              // every emitted tag came from a spec
            std::size_t& keptCount = keptPerTag[ slotIt->second ];
            if( keptCount >= groups[groupIndex].maxMatches )
            {
                continue; // this spec's own budget is spent — never another's
            }
            ++keptCount;
            keep.push_back( std::move( m ) );
        }
        out[groupIndex] = std::move( keep );
    }
    return out;
}

// The single-group spelling every standalone caller uses. One walk, one group — byte-identical to the
// hand-written pass this replaced, and there is exactly ONE file-walk implementation to keep correct.
std::vector<AstMatch> astQuery( const IngestResult& ing, const std::vector<AstQuerySpec>& specs, std::size_t maxMatches,
                                std::vector<std::string>* uncompiledOut )
{
    const std::vector<AstQueryGroup>   one{ { &specs, maxMatches, uncompiledOut } };
    std::vector<std::vector<AstMatch>> got = astQueryGrouped( ing, one );
    return std::move( got[0] );
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

}   // namespace rw
