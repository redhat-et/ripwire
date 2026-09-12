#pragma once
#include "infra/emit.h" // rw::emitTo / emitRaw / formatTo — THE emitter and its siblings

#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_crawl.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif
#include "infra/tablelookup.h"   // findByField — the same lookup wrap's agentTarget uses

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
// .yml/.yaml pair made it 36, the .php/.phtml/.lua trio made it 40, the .ex/.exs pair made it 42, the
// .rst/.adoc/.org/.mdx prose quartet made it 46, .dart made it 47 and .kt made it 48. Sizing it to the row count is what
// makes
// `std::array<bool, kLangTable.size()> present` (the grammar-prewarm set,
// below) exact too, and it turns "added a row and forgot the extent" into a compile error rather than a
// silent drop.
//
// THE PLAIN-TEXT PROSE FORMATS (.rst/.adoc/.org/.mdx), on the SAME grammar and the same walk as markdown.
// docparse.h's kMarkdownGrammarExts is the NAME list every reader-facing prose lens consults; the
// static_assert under this table ties the two together so neither can grow alone. Four SINGLE-PURPOSE
// prose extensions — an extension that exists for nothing but documents — that the crawl indexed nowhere
// before 2026-09-09, so a repository whose decision history lives in `docs/adr/*.rst` got "0 relevant of 0
// document files" out of --recall.
//
// WHY THE MARKDOWN GRAMMAR AND NOT AN EXTRACTOR PER FORMAT. Measured, not assumed. reStructuredText's
// title underlines (`=====`, `-----`) ARE setext headings, so the existing section tier tiles a real .rst
// document with no new code at all and --recall serves the DECISION rather than the whole file. On a real
// 292-file, 2.28 MB astropy `.rst` documentation tree, five pre-registered questions at three budgets:
// heading-tiled answered 15/15 while the same prose with its setext underlines removed (the one-unit
// control) answered 9/15, and tiled was CHEAPER at every budget (mean est_tokens 1299/2659/5379 against
// 1436/2781/6041 at max-tokens 2000/4000/8000). An extractor per format would have bought that same
// benefit for a docText copy of every byte, a second body-resolution rule and a fifth parser to keep
// deterministic. `=` and `-` cover 1321 of that corpus's 1948 underlines (67.8%); `*`/`^`/`"`/`~`/`+`/`#`
// titles are read as prose, which costs recall precision inside a file and nothing else.
//
// WHAT THIS HONESTLY DOES NOT DO, disclosed because --recall says `section-granular` only when it is true:
// AsciiDoc's `== Section` and Org-mode's `* Heading` are NOT markdown headings (the former is a paragraph,
// the latter a list item), so those files carry the file-level node alone and serve as ONE whole-file
// unit. A heading detector per format is a later lane with its own measurement. `.mdx` is markdown with
// JSX, which the block grammar already reads as html blocks (opaque). Gate: test/textdocscheck.sh.
constexpr std::array<LangEntry, 48> kLangTable = {{
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
    { ".ex",   Lang::Elixir,     &tree_sitter_elixir,     "elixir"     },
    { ".exs",  Lang::Elixir,     &tree_sitter_elixir,     "elixir"     },
    { ".dart", Lang::Dart,       &tree_sitter_dart,       "dart"       },
    // Lua: no classes, no imports. The five function-definition spellings and the one call node are the
    // whole extractable structure (queries/lua/tags.scm states the metatable/dynamic-dispatch floor).
    { ".lua",  Lang::Lua,        &tree_sitter_lua,        "lua"        },   // Lua — function/method defs (5 shapes) + calls
    // Kotlin: `.kts` (Gradle script DSL) is deliberately NOT a row here yet — its trailing-lambda
    // density needs its own parse-quality probe before riding this grammar; `.kt` only for now.
    { ".kt",   Lang::Kotlin,     &tree_sitter_kotlin,     "kotlin"     },   // Kotlin — classes/objects/interfaces/functions + calls; JVM-bridged to Java (graph.h langCompatible)
    { ".md",   Lang::Markdown,   &tree_sitter_markdown,   ""           },   // Markdown DOC tier — headings/sections via extractMarkdown()'s custom tree walk; NO tags.scm (query stays "")
    { ".markdown", Lang::Markdown, &tree_sitter_markdown, ""           },   // sibling extension, same walk
    { ".rst",  Lang::Markdown,   &tree_sitter_markdown,   ""           },   // reStructuredText — underlined titles tile as setext
    { ".adoc", Lang::Markdown,   &tree_sitter_markdown,   ""           },   // AsciiDoc — whole-file unit (see above)
    { ".org",  Lang::Markdown,   &tree_sitter_markdown,   ""           },   // Org-mode — whole-file unit (see above)
    { ".mdx",  Lang::Markdown,   &tree_sitter_markdown,   ""           },   // MDX — markdown with JSX islands
}};

// SIBLING-COMPLETENESS GUARD (METHODOLOGY §3), at COMPILE time. docparse.h owns the NAME list every
// reader-facing prose lens consults; this table owns the GRAMMAR rows. Adding a format to one and not the
// other is exactly the defect this lane fixed — `.rst` counted as prose for ordering while the crawl
// indexed it nowhere — so it is made impossible rather than merely documented.
constexpr bool everyMarkdownGrammarExtHasARow() noexcept
{
    for( const std::string_view ext : docparse::kMarkdownGrammarExts )
    {
        const LangEntry* row = findByField( kLangTable, &LangEntry::ext, ext );
        if( row == nullptr || row->lang != Lang::Markdown )
        {
            return false;
        }
    }
    return true;
}

static_assert( everyMarkdownGrammarExtHasARow(),
               "every docparse::kMarkdownGrammarExts entry needs a kLangTable row on Lang::Markdown — "
               "a prose format admitted by one and not the other is indexed nowhere while every lens calls it prose" );

const LangEntry* lookupLang( std::string_view ext ) noexcept
{
    return findByField( kLangTable, &LangEntry::ext, ext );
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
    if( tail == "field" )          // member variable (card A3) — gated (dropGatedCapture: static members / non-self targets drop)
    {
        return SymKind::Field;
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
// Most code languages want the split — `ns::f` / `pkg.F` must key on the bare `f` that byName resolves.
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
// For data-config languages, preserving dots cannot widen the call graph: they emit no @reference
// captures, and graph.h's langCompatible isolates them from code languages.
// Elixir DOES emit call references. Its module/protocol names retain their dotted spelling here;
// function-definition captures are already bare names. captureTagsFacts still applies finalSegment
// to reference names, so preserving Elixir definition captures does not create a byName mismatch.
//
// This lives beside finalSegment rather than inside captureTagsFacts on purpose — the caller is a very
// large function already over the complexity bar, and a policy branch buried in it is both invisible and
// a measured regression (--quality-delta scored the inline ternary at +3 ccx).
/// Return an owned definition lookup name, preserving config keys and Elixir module names verbatim.
std::string defNameFromCapture( Lang lang, std::string_view raw )
{
    if( lang == Lang::Json || lang == Lang::Toml || lang == Lang::Yaml || lang == Lang::Elixir )
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
//
// errNodes/errBytes ALSO count invalid UTF-8 byte sequences found in the leading whitespace-sample window
// (one per bad sequence, since tree-sitter's error recovery does not reliably flag them as ERROR/MISSING —
// a garbage byte run can parse as an unrecognized leaf with no error node at all).
FileHealth measureFileHealth( TSNode root, std::string_view bytes )
{
    FileHealth h;
    h.fileBytes = std::uint32_t( bytes.size() > 0xFFFFFFFFull ? 0xFFFFFFFFull : bytes.size() );

    // Walks the sample codepoint-by-codepoint (jsonesc::utf8SeqLen, already the shared UTF-8 validator
    // for mcp.h/ccjson.h) rather than byte-by-byte: a whitespace byte is only meaningful outside a
    // multi-byte sequence, and this lets the same pass also catch invalid UTF-8 — see below — for free.
    // A bad sequence resyncs one byte at a time, same as any decoder recovering from garbage. Bad
    // sequences are recorded as ascending START POSITIONS (the scan runs left to right), which is what
    // lets the ERROR walk below dedup against them with std::lower_bound instead of a per-span scan.
    const std::size_t         sample = bytes.size() < kHealthWsSampleBytes ? bytes.size() : kHealthWsSampleBytes;
    std::uint32_t              ws    = 0;
    std::vector<std::uint32_t> badUtf8Positions;
    for( std::size_t i = 0; i < sample; )
    {
        const int seqLen = jsonesc::utf8SeqLen( bytes.data(), i, bytes.size() );
        if( seqLen == 0 )
        {
            badUtf8Positions.push_back( std::uint32_t( i ) );
            ++i;
            continue;
        }
        if( seqLen == 1 )
        {
            const unsigned char c = ( unsigned char ) bytes[ i ];
            if( c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v' )
            {
                ++ws;
            }
        }
        i += std::size_t( seqLen );
    }
    h.wsBytes = ws;

    // Invalid UTF-8 in the leading sample is unparseable content by construction, but tree-sitter's own
    // error recovery does not reliably surface it as an ERROR/MISSING node (a garbage byte run can be
    // swallowed as an unrecognized leaf with no error flag at all — confirmed empirically on a random-byte
    // .kt file: ts_node_has_error(root) came back false). Fold it into errNodes/errBytes rather than adding
    // a parallel disclosure field: it is exactly what those two attributes already mean to a reader —
    // "bytes this build could not interpret" — just found by a byte-level scan instead of a tree walk.
    // A position that falls inside a top-most ERROR span below is the SAME problem tree-sitter already
    // flagged there, and counting it twice would push err_ratio (errBytes/fileBytes) past its documented
    // <=1.0 ceiling — so coverage is tallied WHILE walking and folded in ONCE, after, rather than adding
    // every position up front and backing out duplicates mid-walk: `h` holds a correct value at every
    // point in this function, never a transiently over-counted one a reader mid-function could observe.
    if( !ts_node_has_error( root ) )
    {
        // no ERROR span for a bad sequence to overlap — every one found is a genuinely new finding
        h.errNodes += std::uint32_t( badUtf8Positions.size() );
        h.errBytes += std::uint32_t( badUtf8Positions.size() );
        return h;
    }

    std::vector<TSNode> stack;
    ChildCursor         cursor( root );   // reused across nodes — this walk never recurses
    stack.push_back( root );
    std::uint32_t coveredBadUtf8 = 0;   // badUtf8Positions entries already inside a counted top-most ERROR span
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
            if( hi > lo && !badUtf8Positions.empty() )
            {
                const auto lo_it = std::lower_bound( badUtf8Positions.begin(), badUtf8Positions.end(), lo );
                const auto hi_it = std::lower_bound( lo_it, badUtf8Positions.end(), hi );
                coveredBadUtf8 += std::uint32_t( hi_it - lo_it );
            }
            continue;   // top-most only — see the note above
        }
        if( ts_node_is_missing( n ) )
        {
            ++h.errNodes;
            continue;
        }
        // O(children), not O(children²). The root of a RECOVERED file is exactly where the width is
        // largest and least controlled — one comment flood plus one unparseable token measured 56× the
        // identical flood with no error in it before this became a cursor (test/childwalkscalecheck.sh,
        // arm B4; the rule is on src/infra/tschildren.h). Filtered in place: `stack` is the work list,
        // and only the children that carry an error belong on it.
        forEachChild( n, cursor.cur, [ &stack ]( TSNode c )
        {
            if( ts_node_has_error( c ) || ts_node_is_missing( c ) )
            {
                stack.push_back( c );
            }
            return true;
        } );
    }
    // Fold in only the bad-UTF-8 positions NOT already covered by a top-most ERROR span above.
    const std::uint32_t uncoveredBadUtf8 = std::uint32_t( badUtf8Positions.size() ) - coveredBadUtf8;
    h.errNodes += uncoveredBadUtf8;
    h.errBytes += uncoveredBadUtf8;
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

// ── the Kotlin string-template nesting prescan (kotlinStringsNestTooDeep) and its three lexical helpers ──────────────

// The byte length of the character literal that starts at bytes[ i ] == '\'', or 0 when none does. The grammar's shape
// is `'` (an escape, or ONE codepoint that is not a quote or a newline) `'`, and the parser's internal lexer takes it
// whole, so a quote inside one (`'"'`) is never offered to the external scanner as a string start.
inline std::size_t kotlinCharLiteralLength( std::string_view bytes, std::size_t i ) noexcept
{
    const auto byteAt = [ & ]( std::size_t k ) noexcept -> unsigned char { return k < bytes.size() ? static_cast<unsigned char>( bytes[ k ] ) : 0u; };
    const unsigned char first  = byteAt( i + 1 );
    std::size_t         length = 0;
    if( first == '\\' )
    {
        length = ( byteAt( i + 2 ) == 'u' ) ? 8u : 4u;   // '\uXXXX' or a one-character escape
    }
    else if( first != 0u && first != '\'' && first != '\n' && first != '\r' )
    {
        std::size_t codepointBytes = 1;
        if( ( first >> 5 ) == 0x6u )
        {
            codepointBytes = 2;
        }
        else if( ( first >> 4 ) == 0xEu )
        {
            codepointBytes = 3;
        }
        else if( ( first >> 3 ) == 0x1Eu )
        {
            codepointBytes = 4;
        }
        length = codepointBytes + 2u;
    }
    return ( length > 0 && byteAt( i + length - 1 ) == '\'' ) ? length : 0u;
}

// The index just past the `/* … */` comment whose `/*` starts at bytes[ i ], nesting exactly as the vendored scanner's
// scan_multiline_comment does — including its reading of an unterminated comment, which runs to end of input.
inline std::size_t kotlinBlockCommentEnd( std::string_view bytes, std::size_t i ) noexcept
{
    std::size_t k         = i + 2;
    std::size_t depth     = 1;
    bool        afterStar = false;
    while( k < bytes.size() )
    {
        const char c = bytes[ k ];
        ++k;
        if( c == '*' )
        {
            afterStar = true;
        }
        else if( c == '/' && afterStar )
        {
            afterStar = false;
            if( --depth == 0 )
            {
                return k;
            }
        }
        else
        {
            afterStar = false;
            if( c == '/' && k < bytes.size() && bytes[ k ] == '*' )
            {
                ++depth;
                ++k;
            }
        }
    }
    return k;
}

// In Kotlin CODE: the index just past a token that is consumed WHOLE before the external scanner can see a quote inside
// it — a `//` comment, a nested `/* */` comment, a character literal, a backtick identifier — or `i` itself when none
// starts at bytes[ i ].
inline std::size_t kotlinCodeTriviaEnd( std::string_view bytes, std::size_t i ) noexcept
{
    const std::size_t byteCount = bytes.size();
    const char        c         = bytes[ i ];
    const char        next      = ( i + 1 < byteCount ) ? bytes[ i + 1 ] : '\0';
    if( c == '/' && next == '/' )
    {
        const std::size_t newline = bytes.find( '\n', i );
        return ( newline == std::string_view::npos ) ? byteCount : newline;
    }
    if( c == '/' && next == '*' )
    {
        return kotlinBlockCommentEnd( bytes, i );
    }
    if( c == '\'' )
    {
        return i + kotlinCharLiteralLength( bytes, i );
    }
    if( c == '`' )
    {
        const std::size_t close = bytes.find_first_of( "`\r\n", i + 1 );
        const bool        named = close != std::string_view::npos && bytes[ close ] == '`' && close > i + 1;
        return named ? close + 1 : i;
    }
    return i;
}

enum class KotlinStringEvent : std::uint8_t { None, OpenInterpolation, CloseString };

// One step of the vendored scanner's scan_string_content at bytes[ i ], inside an open string of the given shape: the
// index after the bytes it consumes, and whether those bytes opened an interpolation or closed the string.
//   `$`  a run of at least the string's `$` prefix followed by `{` opens an interpolation; any other run is content.
//   `\`  skips the byte after it, and `\$` the byte after the `$` too: the scanner's loop falls through to its bottom
//        advance, so `\$${` is content, never an interpolation. Before a quote the string's shape decides. In a
//        single-quoted string `\$"` CLOSES it (upstream's own reading, mirrored because the stack follows it) and `\"` is
//        content. In a triple-quoted string `\` is no escape before a quote, bare or as `\$` (vendored patch 002), so the
//        quote is read again by the triple-quote close test.
//   `"`  closes a single-quoted string; a run of three or more closes a triple-quoted one, and shorter runs are content.
inline std::pair<std::size_t, KotlinStringEvent> kotlinStringStep( std::string_view bytes, std::size_t i, bool tripleQuoted,
                                                                   std::size_t dollars ) noexcept
{
    const std::size_t byteCount = bytes.size();
    const auto        byteAt    = [ & ]( std::size_t k ) noexcept -> char { return k < byteCount ? bytes[ k ] : '\0'; };
    const auto        runOf     = [ & ]( char c ) noexcept
    {
        std::size_t run = 0;
        while( i + run < byteCount && bytes[ i + run ] == c )
        {
            ++run;
        }
        return run;
    };
    switch( bytes[ i ] )
    {
        case '$':
        {
            const std::size_t run   = runOf( '$' );
            const bool        opens = run >= dollars && byteAt( i + run ) == '{';
            return { i + run + ( opens ? 1u : 0u ), opens ? KotlinStringEvent::OpenInterpolation : KotlinStringEvent::None };
        }
        case '\\':
        {
            const bool        escapesDollar = byteAt( i + 1 ) == '$';
            const std::size_t quoteAt       = i + ( escapesDollar ? 2u : 1u );
            if( tripleQuoted && byteAt( quoteAt ) == '"' )
            {
                return { quoteAt, KotlinStringEvent::None };   // the triple-quote close test reads this quote again
            }
            if( escapesDollar )
            {
                return { i + 3, byteAt( i + 2 ) == '"' ? KotlinStringEvent::CloseString : KotlinStringEvent::None };
            }
            return { i + 2, KotlinStringEvent::None };
        }
        case '"':
        {
            if( !tripleQuoted )
            {
                return { i + 1, KotlinStringEvent::CloseString };
            }
            const std::size_t run = runOf( '"' );
            return { i + run, run >= 3 ? KotlinStringEvent::CloseString : KotlinStringEvent::None };
        }
        default:
        {
            return { i + 1, KotlinStringEvent::None };
        }
    }
}

// True when string-template nesting would take tree-sitter-kotlin's scanner string stack past kMaxKotlinStringNestDepth —
// see that constant in ingest.h for the defect. Like the json/yaml/markdown prescans: one deterministic O(n) byte scan
// BEFORE any parse, never a wall-clock timeout. Unlike them it is not a shape ESTIMATE, because the stack it bounds
// changes in exactly two places — a string START pushes one entry and a string END pops one — so this scan MIRRORS the
// vendored scanner's state machine (scan_string_start / scan_string_content; kotlinStringStep above carries the string
// half). In code — top level, or inside an interpolation, which closes at the `}` balancing its `${` — a quote after an
// optional `$` run is a string START, and kotlinCodeTriviaEnd skips what the parser's internal lexer takes whole first.
// What a byte mirror cannot see is the parser's ERROR RECOVERY, which is why the ceiling sits 4x under the cliff rather
// than at it, and why the vendored patch that turns the scanner's own abort() into a refused push is a second,
// independent layer and not a formality.
bool kotlinStringsNestTooDeep( std::string_view bytes ) noexcept
{
    struct NestFrame
    {
        bool        isString     = false;
        bool        tripleQuoted = false;
        std::size_t dollars      = 1;   // a string: how long a `$` run must be to open an interpolation inside it
        std::size_t openBraces   = 0;   // an interpolation: `{` opened inside this `${ … }` and not yet closed
    };
    // String and interpolation frames strictly alternate above top-level code, so twice the ceiling bounds the stack —
    // and the string push that would pass the ceiling IS the verdict, so it is reached before the array could fill.
    std::array<NestFrame, 2u * kMaxKotlinStringNestDepth> frames {};
    std::size_t       frameCount  = 0;
    std::uint32_t     stringDepth = 0;
    const std::size_t byteCount   = bytes.size();
    std::size_t       i           = 0;
    while( i < byteCount )
    {
        NestFrame* const top = ( frameCount > 0 ) ? &frames[ frameCount - 1 ] : nullptr;
        if( top != nullptr && top->isString )
        {
            const auto [ next, event ] = kotlinStringStep( bytes, i, top->tripleQuoted, top->dollars );
            i = next;
            if( event == KotlinStringEvent::CloseString )
            {
                --frameCount;
                --stringDepth;
            }
            else if( event == KotlinStringEvent::OpenInterpolation && frameCount < frames.size() )
            {
                frames[ frameCount ] = NestFrame{};
                ++frameCount;
            }
            continue;
        }
        const std::size_t afterTrivia = kotlinCodeTriviaEnd( bytes, i );
        if( afterTrivia != i )
        {
            i = afterTrivia;
            continue;
        }
        std::size_t dollarRun = 0;
        while( i + dollarRun < byteCount && bytes[ i + dollarRun ] == '$' )
        {
            ++dollarRun;
        }
        if( i + dollarRun < byteCount && bytes[ i + dollarRun ] == '"' )
        {
            if( stringDepth >= kMaxKotlinStringNestDepth || frameCount >= frames.size() )
            {
                return true;
            }
            const std::size_t quote  = i + dollarRun;
            const bool        triple = quote + 2 < byteCount && bytes[ quote + 1 ] == '"' && bytes[ quote + 2 ] == '"';
            frames[ frameCount ] = NestFrame{ true, triple, std::clamp<std::size_t>( dollarRun, 1u, 255u ), 0u };   // the scanner caps its prefix at 255
            ++frameCount;
            ++stringDepth;
            i = quote + ( triple ? 3u : 1u );
            continue;
        }
        if( top != nullptr && bytes[ i ] == '{' )
        {
            ++top->openBraces;
        }
        else if( top != nullptr && bytes[ i ] == '}' )
        {
            if( top->openBraces == 0 )
            {
                --frameCount;   // the brace that balances `${` closes the interpolation: back inside its string
            }
            else
            {
                --top->openBraces;
            }
        }
        i += ( dollarRun > 0 ) ? dollarRun : 1u;
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

// §SEC1 — a file the crawl REFUSED because its link left the root. Its own recorder rather than
// recordCrawlDrop, and the difference is the point: recordCrawlDrop pays `entry.file_size()`, which FOLLOWS
// the link and would therefore measure the very out-of-root file the refusal exists to leave unread. bytes=0
// here is the NOT-MEASURED sentinel, not a claim of an empty file (see CrawlSkips::escaped in model.h).
// The count is EXACT and always incremented; only the row is capped, exactly like every sibling class.
void recordRootEscape( CrawlSkips& skips, const std::string& path, std::string_view ext )
{
    ++skips.escapedFiles;
    if( skips.escaped.size() < kMaxSkipRowsPerClass )
    {
        skips.escaped.push_back( { path, 0ull, std::string( ext ) } );
    }
    DEGRADED_PATH_ALERT( "ingest: a symlink's target leaves the crawl root — file refused (see --skipped why=escaped-root)" );
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
// THE THIRD TEST, FOR ONE CLASS ONLY (§N6-C, closed 2026-09-09). The unsupported-ext population is not
// merely reported — grep's aux scan (search.h grepCollectAux) READS it and SERVES its hits — so it must
// hold only files the REPOSITORY did not ask to hide either, on exactly the rule it already applies to
// --exclude. Before this test existed the crawl asked the ignore set only about files that survived
// here, so a file that was both gitignored and of an unindexed extension was rowed as unsupported-ext:
// measured, --regex='^#include' served four hits from a `.cpp.bak` beside its source that the
// repository's own .gitignore names (rg does not open it), while unindexed_files_scanned= and
// unsupported_ext= both counted it, so nothing disclosed that an ignored file had been read.
// test/grepignorecheck.sh pins the fix. `ignored` is a LAZY predicate for the same reason fullPath is:
// the lookup stringifies the path, so it is paid only once the two cheaper tests have already admitted
// the file to this class — never for a binary asset or an --exclude'd file, and never for an indexable
// file, which takes the crawl's own ignore test after this returns false. A file dropped here is in NO
// class — neither this one nor ignored=, exactly as an --exclude'd unsupported-ext file is in neither
// this one nor excluded=: ignored= describes only what would OTHERWISE HAVE BEEN INDEXED (the number the
// map header's accounting invariant carries), and a language this build cannot read that the repository
// hid is not a disclosure the reader is owed. --no-ignore makes the predicate false, so the escape hatch
// restores the row and both counts with it.
//
// `fullPath` is the caller's LAZY path materializer, taken as a template parameter rather than a
// std::string: a monorepo crawl walks far more non-source files than source ones, and stringifying every
// one of them to record the handful that are reportable would be a real per-file cost for nothing.
template< typename PathFn, typename IgnoredFn >
bool recordPreSizeDrop( CrawlSkips& skips, HashMap<std::string, std::uint64_t>& extTally,
                        const std::string& ext, bool excluded, const fs::directory_entry& entry, PathFn&& fullPath, IgnoredFn&& ignored )
{
    if( lookupLang( ext ) == nullptr && !docparse::isDocExtension( ext ) )
    {
        if( !excluded && !isNonTextExtension( ext ) && !ignored() )
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

// ── §N6-C: THE IGNORE PROBE — what a repository already told us it does not want indexed ─────────────
//
// ripwire is named for ripgrep, whose defining default is that ignored files are not searched. Everything
// below exists to make the crawl's default agree with that.
//
// WHY GIT, AND NOT A .gitignore MATCHER OF OUR OWN. Measured, then decided. A native matcher has to be
// bug-compatible with git across nested .gitignore precedence, negation (`!keep.c`), `**`, the trailing-
// slash directory form, `core.excludesFile`, `.git/info/exclude`, and macOS case folding — and the moment
// it diverges it deletes source from a corpus while claiming the repository asked for that. Shelling to
// git costs ONE fork per root and is exact by construction: measured 0.02 s (ugrep, rocksdb), 0.15 s
// (duckdb), 0.02 s on this repository's own root with `--directory` (bench/PROFILE.md carries the row).
// This is not a new dependency — gitmine.h, crossref.h, prcontext.h, quality.h and binstale.h all already
// popen git, and the zero-runtime-dependency guardrail (G3) is about what the BINARY links, not about an
// optional tool whose absence degrades. Its absence degrades here exactly as it does there: no git work
// tree, or no git binary, and the crawl is today's full walk with IgnoreMode::Unavailable saying so.
//
// `--directory` is load-bearing for the cost, not a convenience: it collapses a wholly-ignored directory
// to one entry, so a 150K-file node_modules/ costs one line of output and one prune, never an enumeration.
// The price is that a pruned subtree's file count is UNKNOWN — which is precisely what ignoredDirs= says,
// on the same contract excludedDirs=/prunedDirs= already carry.
// `-z` (NUL-separated) rather than the default: git QUOTES paths containing unusual bytes, and a quoted
// path silently fails to match the walk's own spelling, i.e. under-prunes with no diagnostic.
struct GitIgnoreSet
{
    bool                     available = false;   // git answered; dirs/files are authoritative for this root
    bool                     rootIgnored = false; // git answered "./" — the ROOT is itself ignored (see IgnoreMode)
    std::vector<std::string> dirs;                // root-relative, NO trailing '/', sorted
    std::vector<std::string> files;               // root-relative, sorted
};

// A probe answer larger than this is refused whole rather than applied in part: a PARTIAL ignore set
// under-prunes silently, which is the one failure mode this lane exists to remove. With `--directory` the
// realistic ceiling is kilobytes (26 entries on this repository), so this is a hostile-input guard, not a
// working limit.
constexpr std::size_t kMaxIgnoreProbeBytes = 64ull * 1024ull * 1024ull;

// Ask git which paths under `rootDir` its own ignore rules cover. Never throws; every failure mode returns
// `available=false`, which the caller reads as "walk everything, and say that is what happened".
// A root with no `.git` anywhere above it is not a git root: say so without spawning git at all. The
// nongitqmetricscheck contract — non-git retrieval never invokes git merely to degrade — covers this probe
// exactly as it covers churn. Worktrees and submodules keep `.git` as a FILE, so the test is existence, not
// directory-ness; the walk stops at the filesystem root.
bool underGitRoot( const char* rootDir )
{
    std::string dir = rootDir == nullptr ? std::string( "." ) : std::string( rootDir );
    char        resolved[ PATH_MAX ];
    if( ::realpath( dir.c_str(), resolved ) != nullptr )
    {
        dir = resolved;
    }
    for( ;; )
    {
        struct stat st;
        if( ::stat( ( dir + "/.git" ).c_str(), &st ) == 0 )
        {
            return true;
        }
        const std::size_t slash = dir.find_last_of( '/' );
        if( slash == std::string::npos || slash == 0 )
        {
            return false;
        }
        dir.resize( slash );
    }
}

GitIgnoreSet collectGitIgnored( const char* rootDir )
{
    GitIgnoreSet out;
    if( !underGitRoot( rootDir ) )
    {
        return out;
    }
    const std::string cmd = "git -C " + shSingleQuote( rootDir == nullptr ? std::string( "." ) : std::string( rootDir ) )
                          + " -c core.quotepath=false ls-files --others --ignored --exclude-standard --directory -z 2>/dev/null";
    std::FILE* pipe = ::popen( cmd.c_str(), "r" );
    if( pipe == nullptr )
    {
        DEGRADED_PATH_ALERT( "ingest: cannot run git for the ignore probe — full walk" );
        return out;
    }
    std::string buf;
    char        chunk[ 8192 ];
    bool        overflowed = false;
    for( std::size_t n = std::fread( chunk, 1, sizeof( chunk ), pipe ); n > 0; n = std::fread( chunk, 1, sizeof( chunk ), pipe ) )
    {
        if( buf.size() + n > kMaxIgnoreProbeBytes )
        {
            overflowed = true;
            break;
        }
        buf.append( chunk, n );
    }
    const int rc = ::pclose( pipe );
    if( rc != 0 )
    {
        return out;   // not a git work tree, or no git binary — the DESIGNED degrade, silent by contract
    }
    if( overflowed )
    {
        DEGRADED_PATH_ALERT( "ingest: git ignore probe exceeded its byte ceiling — full walk" );
        return out;
    }

    for( std::size_t i = 0; i < buf.size(); )
    {
        const std::size_t nul     = buf.find( '\0', i );
        const std::size_t rawEnd  = nul == std::string::npos ? buf.size() : nul;   // one past the entry's last byte
        // A trailing-slash entry is a DIRECTORY in git's output; anything else is one file. Read off the RAW
        // bytes before the trims below remove the slash — and off rawEnd > i, so an empty entry (two NULs in
        // a row, which -z should never produce and this must not index out of) is simply not a directory.
        const bool        isDir   = rawEnd > i && buf[ rawEnd - 1 ] == '/';
        std::string_view  ent( buf.data() + i, rawEnd - i );
        i = rawEnd + 1;
        while( !ent.empty() && ent.back() == '/' )
        {
            ent.remove_suffix( 1 );
        }
        while( ent.size() >= 2 && ent[ 0 ] == '.' && ent[ 1 ] == '/' )
        {
            ent.remove_prefix( 2 );
        }
        if( ent.empty() )
        {
            continue;   // an empty record: not an answer about any path, so it is skipped, not interpreted
        }
        if( ent == "." )
        {
            // git named the root itself ("./"): this root lives inside an ignored subtree. Honouring that
            // empties the map, so the whole answer is discarded and the mode records why (RootIgnored).
            out.rootIgnored = true;
            return out;
        }
        if( isDir ) { out.dirs.emplace_back( ent ); }
        else        { out.files.emplace_back( ent ); }
    }
    std::sort( out.dirs.begin(),  out.dirs.end() );
    std::sort( out.files.begin(), out.files.end() );
    out.available = true;
    return out;
}

// Sorted-vector membership. A binary search over a contiguous, already-sorted vector beats a hash map at
// these sizes and costs no allocation, and — unlike a HashMap — has no iteration order that could reach
// output (the G2 container rule's standing caveat).
//
// WHERE THE CALLER MUST TEST IT, because the ordering is the contract. The FILE test runs AFTER the
// extension classification and the --exclude match (the same reason recordPreSizeDrop's header gives for
// its own two): `ignored` then only ever describes a file that would OTHERWISE HAVE BEEN INDEXED, which is
// what lets the header's accounting invariant carry it — indexed= + oversize= + excluded= + ignored= = the
// population the crawl enumerated. The ONE earlier consult is recordPreSizeDrop's unsupported-ext branch,
// which asks the same predicate before it records a row and records NOTHING when the answer is yes: that
// class is served by grep's aux scan, so unsupported_ext=/unindexed= describe the population grep actually
// reads, and an ignored file of an unindexed extension is counted in neither class (its header has the
// measured leak). The DIRECTORY test runs after the built-in denylist for the mirror reason: ignoredDirs=
// then counts only the subtrees no rule this build already carried had pruned.
bool pathInIgnoreSet( const std::vector<std::string>& sorted, std::string_view rel ) noexcept
{
    return std::binary_search( sorted.begin(), sorted.end(), rel,
                               []( std::string_view a, std::string_view b ) noexcept { return a < b; } );
}

// §N6-C — the probe AND the mode it implies, as one decision, so collectSources reads the answer instead
// of computing it. One fork per root, paid only for a directory root the walk actually opened: the probe
// is worthless on a single-file root and must not be charged to a root the walk already refused.
GitIgnoreSet probeIgnoreSet( const char* rootDir, bool respectGitignore, IgnoreMode& modeOut )
{
    if( !respectGitignore )
    {
        return {};   // modeOut was already set to Off by the caller, before any early return could skip it
    }
    PROFILE_SCOPE_DESCRIBE( "ingest: crawl (git ignore probe)" );
    GitIgnoreSet set = collectGitIgnored( rootDir );
    modeOut = set.available ? IgnoreMode::Git : set.rootIgnored ? IgnoreMode::RootIgnored : IgnoreMode::Unavailable;
    return set;
}

// §L1/§N6-C — WHY the walk stopped at this directory, recorded. Contents are UNKNOWN past here whichever
// rule stopped us, but WHICH rule is itself the disclosure, so the three classes carry three counters
// (CrawlSkips::excludedDirs / ::ignoredDirs / ::prunedDirs). `excluded` is the only user-driven prune;
// `ignoredDir` is the repository's own declaration; everything else that reaches here is built-in policy
// (kCrawlSkipDirs, or the CMakeCache.txt build-output sentinel). The ignore class is ROWED as well as
// counted: a pruned subtree's contents are unknown, but its PATH is the one fact a reader chasing a
// vanished symbol needs, and it costs one capped row per subtree.
template< typename PathFn >
void recordDirPrune( CrawlSkips& skips, bool excluded, bool ignoredDir, const fs::directory_entry& entry, PathFn&& fullPath )
{
    if( excluded )        { ++skips.excludedDirs;  return; }
    if( ignoredDir )      { recordCrawlDrop( skips.ignoredDirRows, skips.ignoredDirs, fullPath(), {}, entry );  return; }
    ++skips.prunedDirs;
}

// §L1: establish the ordering contract on everything the crawl collected out of order. The row vectors
// sort by path; the extension histogram comes out of a HashMap, whose iteration order is an implementation
// detail, so it sorts by count DESC then extension ASC. That last one matters more than usual: it rides
// the DEFAULT map header, where an order that depended on hash iteration would be a determinism bug.
void finalizeCrawlSkips( CrawlSkips& skips, const HashMap<std::string, std::uint64_t>& extTally )
{
    PROFILE_SCOPE_DESCRIBE( "ingest/crawl: finalize skip rows" );
    const auto byPath = []( const SkippedFile& a, const SkippedFile& b ) noexcept { return a.path < b.path; };
    std::sort( skips.excluded.begin(), skips.excluded.end(), byPath );
    std::sort( skips.unsupported.begin(), skips.unsupported.end(), byPath );
    std::sort( skips.ignored.begin(), skips.ignored.end(), byPath );               // §N6-C, same contract
    std::sort( skips.ignoredDirRows.begin(), skips.ignoredDirRows.end(), byPath ); // §N6-C, same contract
    std::sort( skips.escaped.begin(), skips.escaped.end(), byPath );               // §SEC1, same contract
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
                            std::size_t maxFileBytes, std::string_view excludeLabel = {}, bool respectGitignore = true )
{
    std::vector<std::string>     out;
    std::vector<SkippedOversize> skipped;
    CrawlSkips                   skips;
    HashMap<std::string, std::uint64_t> extTally;   // unindexed source/text-looking ext -> file count

    // §N6-C: the mode is set before ANY early return, so a single-file root, an unopenable root and a
    // refused probe all report what was consulted rather than inheriting a default that implies more.
    skips.ignoreMode = respectGitignore ? IgnoreMode::Unavailable : IgnoreMode::Off;

    std::error_code ec;
    fs::path root = fs::path( rootDir );

    // §SEC1 — the boundary, canonicalized ONCE for the whole walk (ingest.h carries the rule and the reasons).
    // Computed before the single-file branch because that branch is its own boundary: a user who names a file
    // directly has selected it, and realpath'ing the root makes the file trivially inside itself.
    const std::string rootReal = canonicalCrawlRoot( rootDir == nullptr ? std::string_view{} : std::string_view( rootDir ) );

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

    const GitIgnoreSet ignoreSet = probeIgnoreSet( rootDir, respectGitignore, skips.ignoreMode );   // §N6-C

    const fs::recursive_directory_iterator end;
    {
        PROFILE_SCOPE_DESCRIBE( "ingest/crawl: directory walk (stat + classify)" );
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
                // §N6-C: the ignore rule is tested LAST, so ignoredDirs= counts only the subtrees no rule this
                // build already carried had pruned — every existing counter keeps the meaning it had, and the
                // new one is exactly "what honouring .gitignore additionally removed".
                bool ignoredDir = false;
                if( !skip && ignoreSet.available )
                {
                    ignoredDir = pathInIgnoreSet( ignoreSet.dirs, relForHash( fullPath(), rootDir ) );
                    skip       = ignoredDir;
                }
                if( skip )
                {
                    it.disable_recursion_pending();
                    recordDirPrune( skips, excluded, ignoredDir, *it, fullPath );   // §L1/§N6-C: see its header
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

            // §SEC1 — THE CRAWL BOUNDARY, and it is tested BEFORE the extension is classified. Order is the
            // contract here exactly as it is for the two drops below, but for a different reason: the
            // unsupported-ext class is READ AND SERVED by grep's aux scan (search.h grepCollectAux), so a
            // boundary test placed after the classification leaves a `.txt` link to an out-of-root file
            // serving its bytes through --grep with every other arm of the fix green. Measured; it is arm 5
            // of test/crawlescapecheck.sh. After isDenylistedName for the mirror reason the other tests sit
            // where they do: this class then holds only files that would OTHERWISE HAVE BEEN READ.
            //
            // `is_symlink()` reads the cached readdir type, so the cost of this line on a symlink-free tree
            // is a branch; only a symlink pays the realpath inside crawlPathStaysInRoot.
            const bool isLink = it->is_symlink( ec );
            ec.clear();
            if( isLink && !crawlPathStaysInRoot( fullPath(), rootReal ) )
            {
                recordRootEscape( skips, fullPath(), lowerExtensionOf( name ) );
                continue;
            }

            // extension must be a known source language OR a doc format (P1-B: notebooks/html/csv are collected
            // like code so they get a fileId; they're skipped by the tree-sitter parse loop and handled in the
            // doc post-pass instead). Use the filename here so rejected regular files do not pay to stringify the
            // full path; materialize the full path only after the extension survives.
            //
            // §N6-C: the repository's own verdict on this file, ONE lazy predicate shared by the two sites that
            // ask it — the lookup stringifies the path (relForHash over fullPath), so it is evaluated only where
            // a class actually consults it, never for a binary asset or an --exclude'd file. False under
            // --no-ignore, on a non-git root, and when git could not answer (ignoreSet.available).
            const auto ignored = [ & ]() -> bool
            {
                return ignoreSet.available && pathInIgnoreSet( ignoreSet.files, relForHash( fullPath(), rootDir ) );
            };

            // §L1: the two NON-SIZE drops are classified and recorded together (recordPreSizeDrop) — see its
            // header for why the tests must run in that order, why the unsupported-ext class alone consults the
            // ignore verdict BEFORE it records a row, and why none of it is written inline here.
            const std::string ext = lowerExtensionOf( name );
            if( recordPreSizeDrop( skips, extTally, ext, excluded, *it, fullPath, ignored ) )
            {
                continue;
            }

            // §N6-C: AFTER the extension and the --exclude match — see pathInIgnoreSet's header for the ordering.
            if( ignored() )
            {
                recordCrawlDrop( skips.ignored, skips.ignoredFiles, fullPath(), ext, *it );
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

// ---- read a file's bytes (false when it cannot be opened, sized or read in full) ----
// Deliberately an out-parameter, unlike docparse::detail::readWholeFile: the parse pool and the AST-query pass
// each hand in one worker-local buffer and reuse it for every file they read, so its capacity carries over.
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

// The first `maxBytes` of a file, into `out` for the same reason as readFile: each prewarm hash worker reuses one
// header-prefix buffer for every file it probes.
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

// ---- A4-P7 stat-gate helpers: (size,mtime,ctime) probe + cache-write wall clock ----
// The warm-run shortcut trusts a cached parse WITHOUT reading/hashing the file when its size AND mtime
// AND ctime still match the cache, and the cached mtime is not "racy" (see saveCache/kCacheVersion).
//
// WHY ctime IS THE THIRD FIELD AND NOT A CONTENT HASH (card A3 follow-up, docs/EVALS.md). (size, mtime)
// alone leaves one hole, and it is reachable by ordinary tools rather than only by an attacker: an editor
// that preserves mtime, a `git checkout` of an older revision, a `cp -p`/`touch -r` restore, all paired
// with an edit that happens to keep the byte length. The gate then trusts a file whose content changed
// and the answer is silently stale — reproduced on argv, and now gated (statgatecheck (b2),
// freshnesscheck arms 6/7). The obvious fix, re-hashing every stat-equal file, is the whole warm path:
// on the common no-change run EVERY file is stat-equal, so it degenerates to a whole-tree re-read and
// deletes the reason the gate exists.
//
// st_ctime — inode CHANGE time on POSIX, not creation time — closes it for free. It moves on any write to
// the file AND on the utimes() that performs the mtime restore, and POSIX exposes no interface for setting
// it: an unprivileged process cannot put it back. It costs no syscall here, because this ::stat already
// returns it. What it does NOT cover: a caller who can move the system clock backward, raw block-device
// manipulation, and a filesystem that maintains no distinct ctime (FAT/exFAT, some SMB mounts) — there the
// gate degrades to exactly the pre-ctime behaviour, which is why the racy rule below is KEPT, not replaced.
//
// GRANULARITY: both timestamps carry whatever the platform/filesystem exposes — APFS and ext4 give true
// nanoseconds, HFS+/some network mounts only whole seconds (the sub-ns field reads 0). The racy-git
// rule makes coarse granularity SAFE rather than merely lossy: any file whose mtime lands in the same
// granule as the cache write is force-re-hashed, so a same-granule post-hash edit can never be trusted.
struct StatInfo { long long mtimeNs; long long sizeBytes; long long ctimeNs; };   // all -1 if the path cannot be stat'd
inline StatInfo statSizeTimes( const std::string& path ) noexcept
{
    struct stat st;
    if( ::stat( path.c_str(), &st ) != 0 )
    {
        return { -1, -1, -1 };
    }
#if defined( __APPLE__ )
    const long long m = (long long)st.st_mtimespec.tv_sec * 1000000000LL + st.st_mtimespec.tv_nsec;
    const long long c = (long long)st.st_ctimespec.tv_sec * 1000000000LL + st.st_ctimespec.tv_nsec;
#elif defined( __linux__ )
    const long long m = (long long)st.st_mtim.tv_sec * 1000000000LL + st.st_mtim.tv_nsec;
    const long long c = (long long)st.st_ctim.tv_sec * 1000000000LL + st.st_ctim.tv_nsec;
#else
    const long long m = (long long)st.st_mtime * 1000000000LL;   // whole-second fallback
    const long long c = (long long)st.st_ctime * 1000000000LL;
#endif
    return { m, (long long)st.st_size, c };
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
        rw::emitTo( stderr, "[ripwire] tags.scm compile error for {} at byte {} (err {}) — skipping language\n",
                      std::string( le.querySub ).c_str(), errOff, (int)errType );
    }
    return q;
}

// ---- the [grammar][field] TSFieldId table, filled ONCE per grammar (src/infra/fieldid.h) ----
// Same shape and same invariant as the compiled-query cache above: written single-threaded before any
// parse worker exists, read lock-free per AST node afterwards. It warms EVERY grammar the table can
// name rather than the crawl's miss set, for two reasons. First, the miss set is empty on a fully-warm
// run, and the AST walks that read this table are not: --slice, --lint and the preprocessor reader parse
// outside the tags prewarm entirely. Second, the cost is a fixed few hundred microseconds — 23 grammars
// x 41 field names, each one linear-scan resolved ONCE — against a per-AST-node saving, so paying it for
// a grammar the run never uses is cheaper than reasoning about which runs need which.
//
// The function-local static is what makes it idempotent and thread-safe at the seam (ingest() can be
// re-entered in a long-lived MCP server); rw::warmFieldIds itself is neither, which is why nothing else
// may call it. Gate: test/fieldidcheck.sh arm E-warm.
// A 65th extension row must be a compile error, not a run that silently keeps the by-name path: the row
// count bounds the DISTINCT grammar count the loop below registers, so this assert bounds the registry.
static_assert( kLangTable.size() <= kFieldIdCapacity,
               "kLangTable has more rows than rw::kFieldIdCapacity — raise the capacity in src/infra/fieldid.h" );

inline void warmFieldIdTable()
{
    static const bool warmed = []()
    {
        for( const LangEntry& le : kLangTable )
        {
            if( le.grammar != nullptr )
            {
                warmFieldIds( le.grammar() );      // nullptr-safe and idempotent; markdown rows have no grammar
            }
        }
        return true;
    }();
    (void) warmed;
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
