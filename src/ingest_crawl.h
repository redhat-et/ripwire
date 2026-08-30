#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_crawl.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_crawl.h — crawl + parse setup, moved VERBATIM from ingest.cpp in the 2026-08-29 split: the
// limits/skip config, the extension -> {lang, grammar, query} table (lookupLang), capture-role and
// DEF-name policy (roleOf/finalSegment/defNameFromCapture), skip rules, §L1 parse health, the
// JSON/YAML/MD nest-depth guards, the deterministic crawl with its drop taxonomy (collectSources),
// file IO (readFile/readFilePrefix), the A4-P7 stat-gate helpers, and the embedded tags-query text +
// compiled-query cache/prewarm. Everything the ingest pipeline needs BEFORE a file is parsed. Same
// contract as every ingest_*.h: reopens `namespace rw` and the unnamed namespace inside it — one TU,
// one unnamed namespace, internal linkage unchanged, zero new API surface — under the
// RIPWIRE_INGEST_TU guard.

namespace rw
{

namespace
{

// ---- limits / skip config (all in one place) ----
// The per-file byte ceiling is now a RUNTIME value (default kDefaultMaxFileBytes = 4 MB, ingest.h),
// threaded through collectSources so --max-file-size can override it. Kept here as the last-resort
// fallback for any caller that somehow crawls with a zero ceiling.
// (kBinarySniffCap moved to ingest.h — see rw::looksBinary there, now shared with grep's aux-file scan.)

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
// .yml/.yaml pair made it 36, and the .php/.phtml/.lua trio made it 40. Sizing it to the row count is what makes
// `std::array<bool, kLangTable.size()> present` (the grammar-prewarm set,
// below) exact too, and it turns "added a row and forgot the extent" into a compile error rather than a
// silent drop.
constexpr std::array<LangEntry, 40> kLangTable = {{
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
    // PHP rides tree-sitter-php's `php/` sub-grammar (NOT `php_only/`) — see CMakeLists. That grammar
    // treats everything outside `<?php … ?>` as `text`, which is why a `.phtml` template and a Blade
    // view (`*.blade.php` — still a `.php` extension) index without an ERROR subtree instead of parsing
    // as one. Both extensions therefore share one row shape; no separate template tier exists or is needed.
    { ".php",  Lang::Php,        &tree_sitter_php,        "php"        },   // PHP — classes/interfaces/traits/enums/functions/methods + calls
    { ".phtml", Lang::Php,       &tree_sitter_php,        "php"        },   // PHP template (markup + <?php ?> islands) — same grammar, same query
    // Lua: no classes, no imports. The five function-definition spellings and the one call node are the
    // whole extractable structure (queries/lua/tags.scm states the metatable/dynamic-dispatch floor).
    { ".lua",  Lang::Lua,        &tree_sitter_lua,        "lua"        },   // Lua — function/method defs (5 shapes) + calls
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
    if( tail == "testmacroblock" )   // LB-E: doctest/Catch2 `TEST_CASE( "title" ) { … }` — gated (testMacroBlockPartsOf)
    {
        return SymKind::Function;
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

// (looksBinary moved to ingest.h as rw::looksBinary — unqualified lookup below still finds it, same namespace.)

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
// '@' declarations. @ is not valid C++ outside a string/comment — and "outside a string/comment" is load-
// bearing, not negligible (kParserVer 74): a C++ header ABOUT Objective-C handling says "@interface" in a
// doc comment (src/ingest_model.h's collapseObjCDeclDefs contract did), and the raw substring search this
// replaces rerouted the whole header to the objc grammar, which cannot parse namespaces/lambdas/noexcept —
// every C++ symbol in the file was shredded at EXTRACTION with no --skipped row and no floor. So the scan
// masks // and /* */ comments plus string/char literals (raw strings included) and only counts an '@' that
// sits in live code. Truncation honesty: a comment/string/raw-delimiter left OPEN at the 8 KB window edge
// masks the rest of the window — a real @interface past an 8 KB leading comment is missed, exactly as it
// was under the substring search's window.
// The two literal-skip helpers, shared shape: given the opening byte's index, return the index of the
// LAST byte the literal consumed (the caller's ++i steps past it), or npos when the window ends inside
// the literal (the caller stops scanning — the truncation-honesty case above).
//
// Ordinary "…" / '…' with backslash escapes. An unterminated-on-line literal returns the newline's own
// index, so the scan RESUMES on the next line — a lone quote in broken code must not mask the rest of
// the window.
std::size_t sniffSkipQuoted( std::string_view head, std::size_t openIndex, char quote ) noexcept
{
    for( std::size_t i = openIndex + 1; i < head.size(); ++i )
    {
        if( head[ i ] == '\\' ) { ++i; continue; }                   // skip the escaped char (incl. \")
        if( head[ i ] == quote || head[ i ] == '\n' ) { return i; }
    }
    return std::string_view::npos;
}

// R"delim( … )delim" — no escapes, so skip to its exact closing sequence, allocation-free (rIndex names
// the R; the prefix letters u8/u/U/L before it are plain identifier chars to this scan and need no
// special casing — the R adjacent to the quote is the discriminant).
std::size_t sniffSkipRawString( std::string_view head, std::size_t rIndex ) noexcept
{
    const std::size_t open = head.find( '(', rIndex + 2 );
    if( open == std::string_view::npos ) { return std::string_view::npos; }
    const std::string_view delim = head.substr( rIndex + 2, open - ( rIndex + 2 ) );
    for( std::size_t close = open + 1; ; ++close )
    {
        close = head.find( ')', close );
        if( close == std::string_view::npos ) { return std::string_view::npos; }
        if( head.compare( close + 1, delim.size(), delim ) == 0
            && close + 1 + delim.size() < head.size() && head[ close + 1 + delim.size() ] == '"' )
        {
            return close + 1 + delim.size();                         // the closing '"'
        }
    }
}

// One masked-region dispatch: does a comment or literal START at index i? Returns the region's last
// byte (the caller's ++i steps past it), npos when the region is open at the window edge, or i itself
// when no region starts here (i.e. head[ i ] is live code). Comment notes: line comments end at EOL (a
// trailing backslash-continuation only matters to a real compiler; the next line re-enters the scan
// harmlessly). The char-literal guard: a ' whose LEFT neighbor is an identifier/digit char is a C++14
// digit separator (1'000'000) or a literal-suffix boundary, not a literal opener — treating it as one
// would swallow real code up to the next stray quote.
std::size_t sniffSkipMaskedRegion( std::string_view head, std::size_t i ) noexcept
{
    const std::size_t npos = std::string_view::npos;
    const char        c    = head[ i ];
    const char        next = ( i + 1 < head.size() ) ? head[ i + 1 ] : '\0';

    if( c == '/' && next == '/' ) { return head.find( '\n', i + 2 ); }
    if( c == '/' && next == '*' ) { const std::size_t close = head.find( "*/", i + 2 ); return ( close == npos ) ? npos : close + 1; }
    if( c == 'R' && next == '"' ) { return sniffSkipRawString( head, i ); }
    if( c == '"' )                { return sniffSkipQuoted( head, i, '"' ); }
    const bool identBefore = i > 0 && ( std::isalnum( static_cast<unsigned char>( head[ i - 1 ] ) ) || head[ i - 1 ] == '_' );
    if( c == '\'' && !identBefore ) { return sniffSkipQuoted( head, i, '\'' ); }
    return i;
}

bool looksObjC( std::string_view bytes ) noexcept
{
    const std::string_view head = bytes.substr( 0, bytes.size() < 8192 ? bytes.size() : 8192 );

    for( std::size_t i = 0; i < head.size(); ++i )
    {
        const std::size_t last = sniffSkipMaskedRegion( head, i );
        if( last != i )
        {
            if( last == std::string_view::npos ) { return false; }   // region open at the window edge
            i = last;
            continue;
        }

        // live code: the three distinctive ObjC declaration keywords, same tokens as the substring era.
        if( head[ i ] == '@'
            && (    head.compare( i + 1, 9,  "interface" )      == 0
                 || head.compare( i + 1, 8,  "protocol" )       == 0
                 || head.compare( i + 1, 14, "implementation" ) == 0 ) )
        {
            return true;
        }
    }
    return false;
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

    // If the root is a regular file, index just that one file instead of refusing.
    if( fs::is_regular_file( root, ec ) && !ec )
    {
        // Process this single file through the same validation pipeline as directory walk would.
        const std::string name = root.filename().string();
        if( !isDenylistedName( name ) )
        {
            const std::string ext = lowerExtensionOf( name );
            // Check if extension is supported (source language or doc format).
            if( lookupLang( ext ) != nullptr || docparse::isDocExtension( ext ) )
            {
                const std::uintmax_t sz = fs::file_size( root, ec );
                if( !ec && sz <= maxFileBytes )
                {
                    out.push_back( rootDir );
                }
                else if( !ec && sz > maxFileBytes )
                {
                    skipped.push_back( { rootDir, sz, maxFileBytes } );
                }
            }
            else if( !isNonTextExtension( ext ) )
            {
                ++extTally[ ext ];
            }
        }
        ec.clear();
        return { std::move( out ), std::move( skipped ), std::move( skips ) };
    }

    // Otherwise treat root as a directory.
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
                // §L1: contents UNKNOWN past here, whichever rule stopped us — but WHICH rule is itself the
                // disclosure, so the two classes carry two counters (see CrawlSkips::excludedDirs /
                // ::prunedDirs). `excluded` is the only user-driven prune; everything else that reached this
                // branch is built-in policy (kCrawlSkipDirs or the CMakeCache.txt build-output sentinel).
                if( excluded )
                {
                    ++skips.excludedDirs;
                }
                else
                {
                    ++skips.prunedDirs;
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
}   // namespace — ingest_crawl.h section of ingest.cpp

}   // namespace rw
