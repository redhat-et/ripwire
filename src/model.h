#pragma once

// model.h — the shared data model for ripwire: the contract between INGEST (tree-sitter)
// and the GRAPH / RANK / SERIALIZE stages. POD/DOD, ids not pointers, dense indices.
//
// Flow:  ingest() → IngestResult { files, symbols(defs), references(unresolved calls) }
//        → graph: resolve references to symbol ids, build the in-edge CSR + wOutDeg
//        → rank:  personalized PageRank over the CSR
//        → serialize: top-K symbols (by rank) → minified XML, grouped by file.

#include "infra/profileScope.h"
#include "infra/enumcount.h"   // rw::enumCountIsExact — the compile-time proof beside each k*Count a cache reader validates against
#include "infra/tablelookup.h"   // rw::findByField — kCallForwarders below
#include "infra/sortutil.h"  // svLess — JS/TS builtin-member tables below (binary_search, no signed-char wrap)
#include "smallvec.h"   // rw::SmallVec — THE ONE ALIAS; the per-key span lists and per-file id buckets below
#include "structlayout.h"   // cross-translation-unit sizeof/alignof tripwire for the shared model

#include <algorithm>   // std::sort — symbolsByFile below; std::binary_search — isJsTsBuiltinMember
#include <tuple>       // std::tie — lessUnindexedExt's mixed-direction compare
#include <array>       // Symbol::evWhy — the fixed-size ev_why tag counters
#include <cstdint>
#include <optional>    // rubyTypedRecvOf — a Ruby reference's built receiver type, or none
#include <string>
#include <span>        // CallForwarderLang::forwarders
#include <string_view>
#include <type_traits>   // std::is_trivially_copyable_v — the VarSpan layout pin below
#include <vector>

#if defined( CTX_USE_STD_MAP )
    #include <unordered_map>
#else
    #include "unordered_dense.h"   // ankerl flat hash map — far faster than std::unordered_map
#endif

namespace rw
{

// project-wide fast map alias — use HashMap<>, never std::unordered_map (flat, cache-friendly).
#if defined( CTX_USE_STD_MAP )
template<class K, class V> using HashMap = std::unordered_map<K, V>;
#else
template<class K, class V> using HashMap = ankerl::unordered_dense::map<K, V>;
#endif

using NodeId = std::uint32_t;
inline constexpr NodeId kNoNode = 0xFFFFFFFFu;

// symbol kind → the terse XML attribute (t="fn|method|cls|struct|iface|var|sec|macro|modscope|type|alias|functype").
// Macro (the macro-edges round) is APPENDED before Other so no existing kind renumbers: a preprocessor
// `#define` definition (@definition.macro — C/C++ preproc_def/preproc_function_def, Rust macro_definition).
// Previously the C/Rust captures mapped to Function, which read as a lie on every t= surface; the kind now
// says what the thing IS. A macro symbol is DISCLOSED-DEGRADED by construction: its body is unparsed
// replacement text (edges out of it come from a lexical scan, see ingest.cpp captureMacroBodyCalls), and a
// call-shaped invocation of its name is a role="macro" edge, never role="call" (RefRole::Macro below).
// Field (the member-variable round, card A3) is APPENDED after Macro for the same reason: a per-object data
// member of a class/struct/union (C/C++: a non-static field_declaration; Python: the first `self.x = …` in a
// method, or an annotated class-body attribute). THE RULE (registered in docs/EVALS.md): a field is NEVER a
// member of IngestResult::symbols — it lives in IngestResult::fields, a side table with its own index space —
// so it enters no map row, no symbols= count, no PageRank/--for/--recall/--exemplar ranking, no adaptive cut,
// no lint/atom attribution, no context-ratio unit, no --tree/--outline count and no quality-delta universe.
// It is addressable ONLY through the member-selector surfaces (--uses=Owner.field, the bare-name refusal that
// lists the Owner.field spellings, --nonlocal-state's disclosure); its use-sites are resolved per site by
// graph.h collectFieldUseSites. Static data members are NOT fields (a class-static CONSTANT keeps its t="var"
// capture; a mutable static member is not extracted — disclosed). symTag("field") exists for the RawDef kind
// and diagnostics; no map emitter ever reaches it.
// ModuleScope is SYNTHETIC — no tags.scm capture produces it and no cached record carries it. ingest_model.h
// mintModuleScopeOwners() appends one per file that has a file-scope call, AFTER the parse cache is released,
// so it is the owner a top-level statement or an anonymous callback body attributes to. It is a CALLER, never a
// callee: nothing in any language can name `<file-scope>`, so it takes no in-edge and cannot become a rank hub.
// NamedType / Alias / FuncType (honesty-small-068) are APPENDED after ModuleScope so no existing kind renumbers. They
// split the old `@definition.type` → Struct bucket where a grammar's syntax PROVES the type's form, which today is Go
// alone: `type N string` / `type L[T any] []T` (a defined type over a non-struct, non-interface, non-func form, or over
// another named type) is t="type", `type F func(...)` is t="functype", `type A = B` is t="alias" (a floor: a Go 1.24
// generic alias `type A[T any] = B` reads t="type", because the grammar gives it no type_alias node). A Go struct or
// interface keeps t="struct"/t="iface". Every other language's @definition.type capture still maps to Struct (C/C++
// typedef and enum, TS/Swift/Dart aliases, Java/C#/PHP/GDScript enums, Elixir @type) — a disclosed floor, not a claim
// that those are structs. The three kinds BEHAVE as Struct did everywhere a predicate reads the kind
// (isStructOrNamedType below), so only the label changes: a label-normalised base-vs-head sample over Go fixtures and
// 26 argv found no other byte moved (2026-10-04, this lane). Dropping the helper moved nothing on
// those probes either, so it is a guard for predicates no Go fixture reaches today, not a proven behaviour.
enum class SymKind : std::uint8_t { Function, Method, Class, Struct, Interface, Var, Section, Macro, Field, Other, ModuleScope, NamedType, Alias, FuncType };
// The number of SymKind enumerators, and the bound a cached def's kind byte is VALIDATED against on the way
// back in (ingest_cache.h ByteR::enumU8). The static_assert is not a restatement: enumCountIsExact asks the
// compiler whether the last enumerator is the last NAMED value, so appending a kind without moving this is a
// build error rather than a validator that silently refuses the new kind's every cached record.
inline constexpr std::size_t kSymKindCount = static_cast<std::size_t>( SymKind::FuncType ) + 1;
static_assert( enumCountIsExact<SymKind, kSymKindCount>(), "kSymKindCount must name the LAST SymKind enumerator — move it with the append" );

inline const char* symTag( SymKind k ) noexcept
{
    switch( k )
    {
        case SymKind::Function:  return "fn";
        case SymKind::Method:    return "method";
        case SymKind::Class:     return "cls";
        case SymKind::Struct:    return "struct";
        case SymKind::Interface: return "iface";
        case SymKind::Var:       return "var";
        case SymKind::Section:   return "sec";    // data-kind defs: doc headings, JSON/YAML keys, and Ruby db/schema.rb
                                                  // columns — the Ruby ones are definitions only, NO call edges
                                                  // (graph.h buildGraph's byName skips them; see isMeasurableKind)
        case SymKind::Macro:     return "macro";  // #define (disclosed-degraded: replacement text, not a parsed body)
        case SymKind::Field:     return "field";  // member variable (id=path::Owner::field; use-sites via --uses=Owner.field)
        case SymKind::Other:     return "other";
        case SymKind::ModuleScope: return "modscope";   // the file's module scope: n="<file-scope>", no body to expand
        case SymKind::NamedType: return "type";     // Go `type N string`: a defined type whose WRITTEN form is not a struct/iface/func literal
        case SymKind::Alias:     return "alias";    // Go `type A = B`: another name for B
        case SymKind::FuncType:  return "functype"; // Go `type F func(...)`: a named function type
    }
    return "other";   // a byte past the enum; a NEW SymKind is a -Werror=switch error above, never a silent "other"
}

// The kinds the `@definition.type` bucket mapped to Struct before honesty-small-068 split Go's: every predicate that
// admitted Struct as "a named type" (callable as a conversion, a method owner, a type-like row) admits these too, so
// the split changes the t= LABEL and nothing else. Read this, not `== SymKind::Struct`, wherever the question is
// "is this a struct-or-named-type definition".
// The three split kinds are the LAST three enumerators, so they are one range; the asserts pin that.
static_assert( SymKind::Alias == SymKind( unsigned( SymKind::NamedType ) + 1 ) && SymKind::FuncType == SymKind( unsigned( SymKind::NamedType ) + 2 )
               && kSymKindCount == unsigned( SymKind::FuncType ) + 1, "NamedType..FuncType are the last, contiguous kinds" );
inline bool isStructOrNamedType( SymKind k ) noexcept
{
    return k == SymKind::Struct || k >= SymKind::NamedType;
}

// The specificity ladder, hoisted out of dedupRawDefs (ingest_model.h) by RIPWIRE-RUBY task C so the
// resolver's tower (graph.h's name matchers) and the def dedup order the SAME way from ONE table — higher =
// more specific / preferred when two matches collide on one name byte. A table, not a switch (§3's
// table-over-switch rule; --quality-delta scored the hoisted switch as a clone of the SymKind readers).
// Values are load-bearing: the dedup's total order and the picker's Method > Var > Section answer sequence
// are byte-pinned (rubyattrs/rubyschema checks, lspcheck 18). Index order is the SymKind enumerator order
// above; the size assert pins the length, so appending a kind without arming it is a build error, not a
// silent 0. The three keyed asserts below pin the enumerator ORDER at three rungs — Method at 1, Section at 6, FuncType at
// 13, each together with its table weight — so moving the top rung, the floor or the tail without its row is a build error.
// They do not pin the other eleven: a swap of two unanchored enumerators (Var with Interface) leaves every guard true while
// the position-indexed table reweights them, which is what the byte-pinned answers above are for. DISTINCT from gitmine.h's
// §H6 "specificity-ordered mapper", which orders file PATHS on a different axis; nothing there reads or shares this ladder.
inline constexpr auto kKindSpecificityTable = std::array{   // extent DEDUCED from the rows: a missing/extra row changes size() and trips the assert below
    /* Function = */   2,   // a bare function definition
    /* Method = */     5,   // most specific: a behaviour owned by a type
    /* Class = */      3,
    /* Struct = */     3,
    /* Interface = */  4,
    /* Var = */        1,
    /* Section = */    0,   // doc headings, JSON/YAML keys, schema columns: never beat a code kind on one name byte
    /* Macro = */      0,   // a #define comes from its own single capture, same value as Section/Other
    /* Field = */      1,   // never collides with Var in practice: the static/non-static gates are complementary
    /* Other = */      0,
    /* ModuleScope = */ 0,  // minted after the dedup pass runs; it can never reach it
    /* NamedType = */  1,   // Go's type_spec fires the generic definedtype AND functype on the same name byte for
    /* Alias = */      1,   // `type F func(...)`: the form-specific kind must win — FuncType below — and an alias is
                             // its own node (type_alias) that never collides
    /* FuncType = */   2,
};
static_assert( kKindSpecificityTable.size() == kSymKindCount,
               "kKindSpecificityTable: one weight per SymKind, in enum order" );
// The size assert arms an APPENDED kind; these arm a REORDERED enumerator, which no length can see. House pattern
// (serialize.h pins int(Lang::Unknown) == 12; the NamedType..FuncType assert above pins a range): ordinal and rung
// are asserted TOGETHER, keyed by enumerator. Three anchors — the top of the ladder, its floor, its tail — so a reorder
// that moves one of THOSE without its table row trips one of them; a permutation confined to the eleven unanchored
// enumerators trips none, and arming one of those is a fourth keyed assert, not a stronger claim about these three.
static_assert( unsigned( SymKind::Method ) == 1 && kKindSpecificityTable[ unsigned( SymKind::Method ) ] == 5,
               "SymKind::Method is enumerator 1 with weight 5 — the tower's top rung; move the enumerator and the table row together" );
static_assert( unsigned( SymKind::Section ) == 6 && kKindSpecificityTable[ unsigned( SymKind::Section ) ] == 0,
               "SymKind::Section is enumerator 6 with weight 0 — headings, keys and schema columns never beat a code kind on one name byte" );
static_assert( unsigned( SymKind::FuncType ) == 13 && kKindSpecificityTable[ unsigned( SymKind::FuncType ) ] == 2,
               "SymKind::FuncType is enumerator 13 (the last) with weight 2 — the Go func-type rung over NamedType/Alias" );
inline int kindSpecificity( SymKind k ) noexcept
{
    return enumTableAt( kKindSpecificityTable, k, 0 );   // a byte past the enum (a corrupt cache byte is VALIDATEd on read)
}

// The last segment of a scope (Symbol::scope) as written ("outer::Scanner" or "pkg.Outer" -> the innermost owner): the spelling the selector
// resolves as Owner.name (graph.h scopeSuffixMatches).
inline std::string_view scopeLastSegment( std::string_view sc ) noexcept
{
    const std::size_t colons = sc.rfind( "::" );
    const std::size_t dot    = sc.rfind( '.' );
    const std::size_t cut    = colons == std::string_view::npos ? ( dot == std::string_view::npos ? 0 : dot + 1 )
                                                                : ( dot == std::string_view::npos || dot < colons ? colons + 2 : dot + 1 );
    return sc.substr( cut );
}

// #324: a ModuleScope owner is SYNTHETIC (comment above the enum) — a CALLER minted after the tags.scm pass,
// never something a test (or anything else) can name or invoke, so it can never be discharged as a test
// obligation. It is legitimate wherever a CALLER is shown (--callers/--impact/--for already carry the
// t="modscope" legend for exactly that row shape) — this predicate is for the narrower, different question
// "is this symbol something a reader could write a test FOR", which a module scope answers no to unconditionally.
// ONE predicate so every such obligation listing excludes it the same way (situ.h's --test-gate untested rows,
// flipimpact.h's --flags --flip untested hosts) rather than two independently-maintained checks that could drift.
inline bool isUntestableOwner( SymKind kind ) noexcept
{
    return kind == SymKind::ModuleScope;
}

// NOTE: Json sits AFTER Unknown deliberately. serialize.h pins `static_assert( int(Lang::Unknown)==12 )`
// and sizes contentBytesByLang[13] on it (clamping any lang index >= 13 into the Unknown token-calib
// bucket — its own designed headroom). Keeping Unknown at 12 lets JSON (a pure-data language with no
// call graph) land at 13 without disturbing that file. Json is lang-incompatible with everything but
// itself via langCompatible (graph.h) and emits ZERO references, so it never forms cross-language edges.
// CSharp is appended AFTER Json for the SAME reason (B6.2): it reuses Json's headroom — index 14 also
// clamps into the Unknown bucket in serialize.h's contentBytesByLang[13] loop (harmless, additive,
// zero renumbering of any existing Lang value) — while `bytesPerTokenFor` (a linear scan, not an
// array index) still picks up its own kTokenCalib entry everywhere else. C is appended AFTER CSharp
// (L3) for the SAME reason again: index 15 clamps into the identical Unknown-bucket headroom, zero
// renumbering of Cpp..CSharp. `.h` stays C++-owned (ingest.cpp's kLangTable) — a C header parses
// acceptably under the C++ grammar and ownership of `.h` between C/C++/ObjC is inherently ambiguous
// without a project-config signal this tool doesn't have; graph.h's langCompatible bridges Cpp<->C
// (like the existing Cpp<->ObjC bridge) so a .c definition still resolves against its .h declaration.
// Toml is appended AFTER C for the SAME reason a FOURTH time: index 16 clamps into the identical
// Unknown-bucket headroom in serialize.h, zero renumbering of Cpp..C. Like Json it is a pure-data
// language — lang-incompatible with everything but itself, zero references, zero call edges.
// Yaml is appended AFTER Toml for the SAME reason a FIFTH time: index 17 clamps into the identical
// Unknown-bucket headroom in serialize.h, zero renumbering of Cpp..Toml. The third pure-data lane.
// Php (18) and Lua (19) are appended AFTER Yaml for the SAME reason a SIXTH and SEVENTH time: both
// clamp into the identical Unknown-bucket headroom in serialize.h, zero renumbering of Cpp..Yaml.
// UNLIKE Json/Toml/Yaml these two are CODE languages with real call graphs — they are simply the next
// two free indexes, and APPENDING (never inserting) is what keeps every on-disk cache key stable.
// Dart (21) is appended AFTER Elixir for the SAME reason an EIGHTH time (test/dartcheck.sh).
// Kotlin (22) is appended AFTER Dart for a NINTH time: it clamps into the identical Unknown-bucket
// headroom in serialize.h, zero renumbering of Cpp..Dart. A CODE language with a real call graph,
// JVM-bridged to Java via graph.h's langCompatible (mirroring the existing Cpp<->ObjC and Cpp<->C
// bridges) so a mixed Kotlin+Java module (the Android norm) resolves calls across the language
// boundary instead of dropping every one of them as unresolved.
enum class Lang : std::uint8_t { Cpp, Python, TypeScript, Go, Rust, Swift, ObjC, Markdown, JavaScript, Bash, Java, Ruby, Unknown, Json, CSharp, C, Toml, Yaml, Php, Lua, Elixir, Dart, Kotlin, GDScript, Clojure };
// The number of Lang enumerators. MUST stay ( last enumerator + 1 ): any per-language array sized by
// a LITERAL silently drops the tail when a language is appended, and the drop is invisible because
// the affected code paths just see a zero. That happened: nonlocalstate.h's filesByLang was a
// hardcoded 16 while Php(18), Lua(19) and Elixir(20) existed, so --nonlocal-state never disclosed
// those three as unanalyzed even though kUnanalyzedLangs listed Php and Lua. Size per-language
// arrays with this, never with a number.
inline constexpr std::size_t kLangCount = static_cast<std::size_t>( Lang::Clojure ) + 1;
// ...and the cache readers validate every cached Lang byte against it, so a stale kLangCount would also refuse
// the new language's records. The compile-time proof (infra/enumcount.h) makes the append a build error instead.
static_assert( enumCountIsExact<Lang, kLangCount>(), "kLangCount must name the LAST Lang enumerator — move it with the append" );

// short lang label — the terse XML/JSON attribute (lang="cpp|py|ts|go|rs|swift|objc|js|sh|java|rb|md|json|cs|c|toml|yaml|php|lua|ex|dart|kt|gd|clj").
// The canonical home for this switch: previously duplicated privately in htmlexport.h, moved here so a THIRD
// caller (naming-consistency's per-language vote groups) reuses it instead of growing a second copy.
/// Return the stable short output label for a language, or "?" for an unknown value.
/// constexpr so main.cpp's registration asserts can ask it about the value one past kLangCount.
inline constexpr const char* langTag( Lang l ) noexcept
{
    switch( l )
    {
        case Lang::Cpp:        return "cpp";
        case Lang::Python:     return "py";
        case Lang::TypeScript: return "ts";
        case Lang::Go:         return "go";
        case Lang::Rust:       return "rs";
        case Lang::Swift:      return "swift";
        case Lang::ObjC:       return "objc";
        case Lang::JavaScript: return "js";
        case Lang::Bash:       return "sh";
        case Lang::Java:       return "java";
        case Lang::Ruby:       return "rb";
        case Lang::Markdown:   return "md";
        case Lang::Json:       return "json";
        case Lang::CSharp:     return "cs";
        case Lang::C:          return "c";
        case Lang::Toml:       return "toml";
        case Lang::Yaml:       return "yaml";
        case Lang::Php:        return "php";
        case Lang::Lua:        return "lua";
        case Lang::Elixir:     return "ex";
        case Lang::Dart:       return "dart";
        case Lang::Kotlin:     return "kt";
        case Lang::GDScript:   return "gd";
        case Lang::Clojure:    return "clj";
        case Lang::Unknown:    return "?";
    }
    return "?";   // a byte past the enum (a corrupt cache value) still reads "?"; a NEW Lang is a -Werror=switch error above
}

// Is this a CODE language (functions, calls, state), as opposed to a data or document format or no language at all?
// It is the ONE declared exemption the per-language registration checks read: main.cpp's asserts and ingest_crawl.h's
// kLangTable mirror check. Appending a Lang used to mean remembering five tables in four files, and three shipped or
// nearly shipped one language short (02f798e3 Dart, 9418e35e five unanalyzed languages, PR #233's `.gd` row).
// There is no `default:` here on purpose: a new enumerator is a -Wswitch error on this switch, so whether it is code is
// a decision, and every table the checks read then has to agree with that decision at compile time.
inline constexpr bool isCodeLang( Lang l ) noexcept
{
    switch( l )
    {
        case Lang::Cpp: case Lang::Python: case Lang::TypeScript: case Lang::Go: case Lang::Rust: case Lang::Swift:
        case Lang::ObjC: case Lang::JavaScript: case Lang::Bash: case Lang::Java: case Lang::Ruby: case Lang::CSharp:
        case Lang::C: case Lang::Php: case Lang::Lua: case Lang::Elixir: case Lang::Dart: case Lang::Kotlin: case Lang::GDScript: case Lang::Clojure:
            return true;
        case Lang::Markdown: case Lang::Json: case Lang::Toml: case Lang::Yaml: case Lang::Unknown:
            return false;
    }
    return false;   // a byte past the enum (a corrupt cache value) is not a language
}

// Call-site RECEIVER classification (P2-D one-hop type narrowing). Captured at ingest from the AST shape
// of `recv.method()` / `recv->method()` so resolve.h can narrow BEFORE the ambiguous §2a name spray:
//   None    — a bare call `f()` or a qualified `A::f()` (no receiver expr) → §2a ladder, unchanged.
//   ThisObj — receiver is `this` (C++) / `self` (Python): the enclosing class is definitive → Rule 1.
//   NamedVar— receiver is a plain local variable `x` (`x->m()` / `x.m()`): the var's TYPE pins the method
//             (Rule 2, one-hop return-type — captured here so the rule is a later drop-in; see resolve.h).
// The capture widens by EXACTLY ONE intermediate field hop because five guard sites key on
// `recv == RecvKind::None`, and a chained receiver classified `None` misread as a BARE name: Rule 1's
// bareCish arm wrong-narrowed `this->m_pool.run()` to the caller's own class, and shadow suppression
// deleted `this->m_cfg.enable()` under a local named `enable` (docs/EVALS.md §4 "Receiver-guard
// misfires"; gate test/chainguardcheck.sh). NO resolve rule consumes the two chain kinds yet — they
// exist so those guards stop misfiring, and they carry their names (`Reference::fieldName` below is
// free on a call ref) so a future chain-resolution rule needs no second re-parse:
//   FieldOfThis — `this->m_pool.run()` / `self.pool.acquire()`: base = the enclosing class,
//                 intermediate field = fieldName.
//   FieldOfVar  — `cfg.opts.enable()` / `m_cfg.opts.enable()`: base = recvVar, intermediate = fieldName.
// DEPTH IS PINNED AT ONE HOP, not opened toward N: a depth-3 chain still classifies `None` (its
// residual misfires are DISCLOSED — chainguardcheck arm (h) pins them as a recorded fact).
//   SuperObj — Phase 5 (docs/EVALS.md "Phase 5", kParserVer 77): Python `super().m()` / `super(C, self).m()`
//              — the receiver is the `call` node whose function is the identifier `super`. Before this kind
//              existed the site classified `None` and reached the ladder as a BARE call, so the S6-C prior
//              handed it to the caller's OWN class — the one class `super()` by definition skips. Resolves
//              through the enclosing class's BASES only (resolve.h Narrower::rule1BaseWalk); a miss is the
//              `@external` veto, never a spray. APPENDED so no persisted value renumbers (RawRef rides the
//              cache with recv as a u8). Python only: isMemberAccessNode classifies C++/Python receivers and
//              C++ has no `super`.
//   LitString / LitArray / LitRegex / LitNumber / LitBoolean — TS/JS member call whose receiver type the
//              syntax already proves (a literal, or a chain of built-in methods that stay certain). APPENDED
//              so the cache u8 does not renumber. isMemberAccessNode stays false for TS/JS; receiverOf
//              classifies these beside that function, TS/JS only. A matching Foo.prototype.NAME extension
//              may bind; anything else is vetoExternal. Object literals, identifier receivers, this, casts,
//              and element-returning links (find/at/pop/shift/reduce/subscript/!) stay None.
//   JavaTypeCandidate — Java `identifier::method` (issue #74): syntax alone cannot say type or value. Ingest stamps
//              the candidate; graph resolution admits it only when the identifier names an indexed class and no Java
//              declaration in the caller shadows that name. APPENDED after the literal kinds: persisted values stay stable.
enum class RecvKind : std::uint8_t { None, ThisObj, NamedVar, FieldOfThis, FieldOfVar, SuperObj, ElixirModule, ElixirSelfModule, LitString, LitArray, LitRegex, LitNumber, LitBoolean,
    JavaTypeCandidate };
// The number of RecvKind enumerators — the bound readRef validates a cached receiver byte against (see kSymKindCount).
inline constexpr std::size_t kRecvKindCount = static_cast<std::size_t>( RecvKind::JavaTypeCandidate ) + 1;
static_assert( enumCountIsExact<RecvKind, kRecvKindCount>(), "kRecvKindCount must name the LAST RecvKind enumerator — move it with the append" );

inline bool isJsTsLitRecv( RecvKind k ) noexcept
{
    return k == RecvKind::LitString || k == RecvKind::LitArray || k == RecvKind::LitRegex
        || k == RecvKind::LitNumber || k == RecvKind::LitBoolean;
}

inline std::string_view jsLitCtorName( RecvKind k ) noexcept
{
    switch( k )
    {
        case RecvKind::LitString:  return "String";
        case RecvKind::LitArray:   return "Array";
        case RecvKind::LitRegex:   return "RegExp";
        case RecvKind::LitNumber:  return "Number";
        case RecvKind::LitBoolean: return "Boolean";
        default:                   return {};
    }
}

inline bool isJsTsBuiltinCtor( std::string_view ctor ) noexcept
{
    return ctor == "String" || ctor == "Array" || ctor == "RegExp" || ctor == "Number" || ctor == "Boolean";
}

// Names that really are members of the literal's built-in type. A Lit* call whose callee is in the
// matching table may bind a scope-matched polyfill or go External/Undefined; any other name keeps
// today's ladder (so String.prototype.shout / named-function / Object.assign / declare global survive).
inline constexpr std::string_view kJsTsStringMembers[] = {
    "anchor", "at", "big", "blink", "bold", "charAt", "charCodeAt", "codePointAt", "concat", "endsWith",
    "fixed", "fontcolor", "fontsize", "includes", "indexOf", "isWellFormed", "italics", "lastIndexOf",
    "link", "localeCompare", "match", "matchAll", "normalize", "padEnd", "padStart", "repeat", "replace",
    "replaceAll", "search", "slice", "small", "split", "startsWith", "strike", "sub", "substr", "substring",
    "sup", "toLocaleLowerCase", "toLocaleUpperCase", "toLowerCase", "toString", "toUpperCase", "toWellFormed",
    "trim", "trimEnd", "trimLeft", "trimRight", "trimStart", "valueOf",
};
inline constexpr std::string_view kJsTsArrayMembers[] = {
    "at", "concat", "copyWithin", "entries", "every", "fill", "filter", "find", "findIndex", "findLast",
    "findLastIndex", "flat", "flatMap", "forEach", "includes", "indexOf", "join", "keys", "lastIndexOf",
    "map", "pop", "push", "reduce", "reduceRight", "reverse", "shift", "slice", "some", "sort", "splice",
    "toLocaleString", "toReversed", "toSorted", "toSpliced", "toString", "unshift", "values", "with",
};
inline constexpr std::string_view kJsTsRegExpMembers[] = {
    "compile", "exec", "test", "toString",
};
inline constexpr std::string_view kJsTsNumberMembers[] = {
    "toExponential", "toFixed", "toLocaleString", "toPrecision", "toString", "valueOf",
};
inline constexpr std::string_view kJsTsBooleanMembers[] = {
    "toString", "valueOf",
};

static_assert( std::is_sorted( std::begin( kJsTsStringMembers ),  std::end( kJsTsStringMembers ),  rw::sortutil::svLess ) );
static_assert( std::is_sorted( std::begin( kJsTsArrayMembers ),   std::end( kJsTsArrayMembers ),   rw::sortutil::svLess ) );
static_assert( std::is_sorted( std::begin( kJsTsRegExpMembers ),  std::end( kJsTsRegExpMembers ),  rw::sortutil::svLess ) );
static_assert( std::is_sorted( std::begin( kJsTsNumberMembers ),  std::end( kJsTsNumberMembers ),  rw::sortutil::svLess ) );
static_assert( std::is_sorted( std::begin( kJsTsBooleanMembers ), std::end( kJsTsBooleanMembers ), rw::sortutil::svLess ) );

inline bool isJsTsBuiltinMember( std::string_view ctor, std::string_view name ) noexcept
{
    const std::string_view* b = nullptr;
    const std::string_view* e = nullptr;
    if( ctor == "String" )
    {
        b = std::begin( kJsTsStringMembers );  e = std::end( kJsTsStringMembers );
    }
    else if( ctor == "Array" )
    {
        b = std::begin( kJsTsArrayMembers );   e = std::end( kJsTsArrayMembers );
    }
    else if( ctor == "RegExp" )
    {
        b = std::begin( kJsTsRegExpMembers );  e = std::end( kJsTsRegExpMembers );
    }
    else if( ctor == "Number" )
    {
        b = std::begin( kJsTsNumberMembers );  e = std::end( kJsTsNumberMembers );
    }
    else if( ctor == "Boolean" )
    {
        b = std::begin( kJsTsBooleanMembers ); e = std::end( kJsTsBooleanMembers );
    }
    else
    {
        return false;
    }
    return std::binary_search( b, e, name, rw::sortutil::svLess );
}

// ABS-3 reference / use-site ROLE: WHAT a reference does at the use site, captured at ingest so a
// use-site index (`--uses=SYM`) can report the resolvable places a name is referenced, not just calls.
// §H4: "complete" is what this comment used to claim, and it is not true of any static name-based
// extractor — the index is a FLOOR, disclosed as counts_floor= (src/graphlegend.h).
// Smallest int that fits (≤ 7 roles) → SoA-friendly. The role is ORTHOGONAL to the call graph: only
// Call refs become PageRank edges; Read/Write/Import/Extends/Type are recorded for the use-site index and
// NEVER enter the CSR (so the default ranked map is unchanged — G5).
//   Call    — the name is in function/callee position `f(...)` / `x.m(...)` (the existing call edges).
//   Read    — the name is referenced as a VALUE / operand (`y = x + 1`, `return foo`, `f(bar)` arg).
//   Write   — the name is the LHS of an assignment / a `++`/`--`/compound-assign target (`x = …`, `x++`).
//   Import  — the name appears in an import / #include / using directive (cross-module surface).
//   Extends — the name is a base class / implemented interface (derived → base; was `isInherit`).
//   Macro   — the macro-edges round: a call-SHAPED site whose name is an indexed C-family `#define`
//             (SymKind::Macro). NEVER emitted as role="call" — call-edge honesty: the site is an expansion,
//             not a plain call, and expansion semantics (stringize/paste/conditional arms) are unmodeled.
//             Unlike Read/Write/Import/Extends it DOES enter the call graph CSR (graph.h admits Call+Macro),
//             because the edge is the feature: the graph connects THROUGH the macro symbol. Ingest always
//             records the site as Call (a per-file parse cannot know another file's #defines); the retag to
//             Macro is the corpus-wide post-pass retagMacroCallReferences below, run at every ingest exit —
//             so a cached role=Call round-trips and is re-judged fresh each run.
//   Type    — the name is a bare TYPE mention: SYM named as a type in a signature, a declaration or a template
//             argument (`Widget makeOne( Widget in )`, `std::vector<Widget>`, `const Widget* p`). Joins the
//             NEVER-in-the-CSR list above — a type mention is a dependency, not a call, so it must not touch
//             PageRank or the default ranked map. Before this role existed a type-ONLY dependent was invisible
//             to the whole use-site index: `--uses=IngestResult` reported 0 against 438 real mentions across
//             68 files, so the most-depended-upon data structure in this repo read as a graph isolate.
//             Distinct from Extends (a base clause) and from isCompose (a member variable's declared type) —
//             those two are SPECIFIC declaration forms and are unchanged; this is the general mention.
//   Value   — reference-as-value round (src/ingest_valuerefs.h, ported from codebase-memory-mcp): a function NAMED in
//             a value position — an initialiser (struct field, dict/object/array/map literal), a call argument, an
//             assignment's right-hand side, a parameter default, a return, a comparison, a JSX attribute, a decorator.
//             NOT a call and never in the CSR: it powers the <vr>/value_refs= disclosure on --callers/--callees/
//             --impact/--safe-delete/--path, role="value" on --uses, and --dead-code's value-ref-excluded=. Role-specific
//             field reuse (graph.h valueRefIndex reads exactly these): fieldName = the slot as written (into=),
//             recvVar = the simple container identifier, composeRel = the normalised key, qualifier = scope char +
//             file-shadow flag, argCount = the argument index.
//             ONE Value record per file may instead be the DEPTH CUT (qualifier = kValueRefDepthCutScope, name = "",
//             which no identifier is): the walk stopped at its depth cap there and argCount subtrees were not visited
//             (saturating), line = the first one. It is no row; valuerefindex.h counts it for the answers' depth disclosure.
//             C family only (IX-1 slot-type join): a Value row whose slot is a STRUCT FIELD also carries memberPath = the
//             field chain from the declared object to the slot ("exec"; "tty.mouse_drag_release" for an assignment
//             `c->tty.mouse_drag_release = f`) and memberCtor = the object's declared struct type ("" when unknown). A
//             SLOT FACT (qualifier = kValueRefSlotFactScope, name = ""): recvVar = a struct type, composeRel = one of its
//             fields, memberCtor = that field's declared struct type; composeRel "" makes it a typedef alias (recvVar
//             names memberCtor). No row: valuerefindex.h reads the facts to type a field chain.
//   Through — a call THROUGH a value: a called parameter, `tbl[k](…)` / `tbl.k(…)` on a container that received a
//             function value. name = the container, fieldName = the written callee, composeRel = the key,
//             qualifier = p|l|f, argCount = the parameter index. Joined to Value rows only (called_by=/through=, a
//             may-call clue); never a use site, never in the CSR.
//             qualifier = kValueRefSlotCallScope (C family, IX-1): a call through a struct FIELD `x->f( … )`, `x.a.f( … )`,
//             `t[ i ].f( … )`; name = the root identifier x, memberCtor = x's declared struct type ("" when no scope of the
//             file declares x), memberPath = the field chain ("a.f"), fieldName = the written callee. Joined by (type, field).
//   Subscript — an element access `recv[ args ]` (Ruby, Python; ingest_binds.h subscriptOperatorRef), named as the
//             receiver class's subscript OPERATOR METHOD (kSubscriptOperatorMethods: Ruby `[]` / `[]=`, Python
//             `__getitem__` / `__setitem__`); receiver fields as a call's. NOT a call by itself: graph.h's resolve loop
//             takes it up as one ONLY where a receiver rule proves the class (subscriptOperatorProven) — `self[ k ]` in a
//             class, a receiver the source types — and drops it otherwise, with no count anywhere (a `hash[ k ]` is the
//             builtin's own operator, not an unresolved call). Never a use site.
//   Inert   — an Elixir call/operator/named-capture candidate whose enclosing quote AST remains inert after live-hole re-entry.
//             It remains a site for declined/report accounting, but can never bind or mint a call edge.
//   Pattern — a NAME-TEMPLATE lookup (IX-3; src/ingest_valuerefs.h patternAt*): `getattr( o, f"watch_{n}" )`, `hasattr`,
//             `cls.__dict__.get( f"…" )` (Python), `o[ 'compile' + t ]` / o[ `on${e}` ] (JS/TS). name = the template as a
//             glob ("watch_*", never an identifier), fieldName = the literal prefix, composeRel = the literal suffix,
//             recvVar = the receiver as written, qualifier = "" (a literal side of >= 3 identifier characters) or "w"
//             (too wide: no row, a count). A MAY-dispatch clue joined to methods by name (valuerefindex.h patternSitesTo);
//             never a call, never a use site, never in the CSR or the dead set.
enum class RefRole : std::uint8_t { Call, Read, Write, Import, Extends, Macro, Type, Value, Through, Subscript, Inert, Pattern };
// The number of RefRole enumerators — the bound readRef validates a cached role byte against (see kSymKindCount).
inline constexpr std::size_t kRefRoleCount = static_cast<std::size_t>( RefRole::Pattern ) + 1;
static_assert( enumCountIsExact<RefRole, kRefRoleCount>(), "kRefRoleCount must name the LAST RefRole enumerator — move it with the append" );
static_assert( sizeof( RefRole ) == 1, "RefRole must be a single byte (SoA-friendly, smallest int that fits)" );

// the terse `role=` attribute string for the use-site index — a declarative table indexed by the enum, in enum
// order. The static_assert is the guard a switch's -Werror=switch used to be: a NEW role without a spelling is a
// build error, never a silent fallback.
inline constexpr const char* kRefRoleTagTable[] = { "call", "read", "write", "import", "extends", "macro", "type", "value", "through", "subscript", "inert", "pattern" };
static_assert( std::size( kRefRoleTagTable ) == kRefRoleCount, "kRefRoleTagTable: one spelling per RefRole, in enum order" );
inline const char* refRoleTag( RefRole r ) noexcept
{
    return enumTableAt( kRefRoleTagTable, r, "read" );   // a byte past the enum (a corrupt cache byte is VALIDATEd on read)
}

// Reference-as-value round: the grammar family whose value positions src/ingest_valuerefs.h reads, and whose
// visibility rule src/valuerefs.h resolves under — ONE table both sides index, so the capture and the resolver
// cannot disagree about which languages are armed. None = not armed (no Value/Through rows are captured).
enum class ValueRefFamily : std::uint8_t { None, C, Js, Py, Go, Rust };   // Rust: the slot join's records only (ingest_rustslots.h)
inline constexpr std::array<ValueRefFamily, kLangCount> kValueRefFamilyOfLang = []
{
    std::array<ValueRefFamily, kLangCount> table {};   // value-initialised: every language None unless armed below
    table[ static_cast<std::size_t>( Lang::C ) ]          = ValueRefFamily::C;
    table[ static_cast<std::size_t>( Lang::Cpp ) ]        = ValueRefFamily::C;
    table[ static_cast<std::size_t>( Lang::JavaScript ) ] = ValueRefFamily::Js;
    table[ static_cast<std::size_t>( Lang::TypeScript ) ] = ValueRefFamily::Js;
    table[ static_cast<std::size_t>( Lang::Python ) ]     = ValueRefFamily::Py;
    table[ static_cast<std::size_t>( Lang::Go ) ]         = ValueRefFamily::Go;
    table[ static_cast<std::size_t>( Lang::Rust ) ]       = ValueRefFamily::Rust;
    return table;
}();
inline ValueRefFamily valueRefFamily( Lang l ) noexcept
{
    return enumTableAt( kValueRefFamilyOfLang, l, ValueRefFamily::None );
}
// CALL FORWARDERS (lane fcall-forward, parser version 188, train renumbers; gate test/fcallforwardcheck.sh): a builtin
// method that, called on a FUNCTION, calls that function (kind Call) or returns it as a value (kind Value). JS/TS
// `f.call( thisArg, a )` and `f.apply( thisArg, args )` run f; `f.bind( thisArg )` hands f on without running it. When
// ingest_valuerefs.h finds the receiver `f` is a bare identifier bound to a function declaration of the file or to a
// file-scope import from a RELATIVE module (and no parameter or local of the site shadows it), a Call row becomes a
// FORWARDED call reference to `f` (Reference::forwarded) — the bare call `f( … )` it stands for, resolved by the ordinary
// tiers and then kept only where they PROVE a Function or Method (graph.h buildGraph; fix round 1): an import proves a
// binding, not a function, so an imported object, const or class, and a by-name-only answer, add nothing — and a Value
// row becomes a value reference to `f` at the slot the whole `f.bind( … )` fills. The original member reference (name `call`/`apply`) is kept unchanged. A family-owned
// sparse table: a language with no row is unchanged. Function.prototype's other methods (toString) are not forwarders.
// Floors, by language: Ruby `proc.call` / `m.to_proc` and Python `functools.partial( f )` are the same concept with
// different receivers (a Proc or Method object, not a declaration) and have no row; a receiver that is a member
// (`obj.m.call`), a parenthesised or computed expression, a local `const f = () => …`, or a TS `import f = require()`
// is not forwarded. Shared with the bare call `f()` (the forward binds exactly as it does): a function-local `var f` /
// `let f` declared AFTER the site does not shadow (scope declarations are read on scope entry), and a re-assignment
// `f = …` is not followed. The declaration proof is file + name at any depth; a declaration only in a SIBLING scope
// leaves the bare call by name alone, so that forward is dropped.
enum class CallForwardKind : std::uint8_t { Call, Value };
struct CallForwarder
{
    std::string_view name;
    CallForwardKind  kind;
    bool             argsAsArray;   // Call only: the forwarded arguments arrive as ONE array (`apply`), so the arity is unknown;
                                    //   otherwise the first argument is the receiver and the rest are the call's own (`call`)
};
// Function.prototype's forwarders, shared by the two languages that run on it.
inline constexpr CallForwarder kJsCallForwarders[] = {
    { "apply", CallForwardKind::Call, true }, { "bind", CallForwardKind::Value, false }, { "call", CallForwardKind::Call, false },
};
struct CallForwarderLang
{
    Lang                               lang;
    std::span<const CallForwarder>     forwarders;
};
inline constexpr CallForwarderLang kCallForwarders[] = {
    { Lang::JavaScript, kJsCallForwarders },
    { Lang::TypeScript, kJsCallForwarders },
};
// The language's forwarder rows — empty when it has none (the mechanism is then inert).
inline std::span<const CallForwarder> callForwardersOf( Lang lang ) noexcept
{
    const CallForwarderLang* row = findByField( kCallForwarders, &CallForwarderLang::lang, lang );
    return row != nullptr ? row->forwarders : std::span<const CallForwarder>{};
}

// The scope char (qualifier[0]) of a file's depth-cut Value record (see RefRole::Value above): written by
// src/ingest_valuerefs.h, read by src/valuerefindex.h — distinct from every row scope (f l a p x).
inline constexpr char kValueRefDepthCutScope = 'd';
// IX-1 slot-type join (see RefRole::Value / Through above): a call through a struct field, and a slot FACT (a field's
// declared struct type, or a typedef alias). Distinct from every other scope char.
inline constexpr char kValueRefSlotCallScope = 's';
inline constexpr char kValueRefSlotFactScope = 't';
// IX1-V2 (lane fn-slot): a PARAMETER stored into a slot (`func Reg( impl F ) { … Command{ EvalRW: impl } … }`): role Value,
// name "" (no row), recvVar = the storing function's name, argCount = the parameter's position (argCountKnown), memberPath =
// the field, memberCtor = the slot's type ("" unknown). valuerefindex.h SlotIndex re-slots an ARGUMENT row of a bare call of
// that function at that position (`Reg( Put )`) into the same field. Distinct from every other scope char.
inline constexpr char kValueRefSlotParamScope = 'q';
// REGISTRAR (lane registrar, Python first slice): a METHOD PARAMETER stored into a container held by a field of `self`
// (`self.receivers.append( ( key, receiver ) )`, `self.filters[ k ] = f`, tuple/list elements included): role Value, name ""
// (no row), recvVar = the method's name, argCount = the parameter's position AFTER `self` (argCountKnown), memberPath = the field.
// Written by src/ingest_valuerefs.h (kRegLangs rows with containerStores), read by src/regindex.h only. Distinct from every
// other scope char.
inline constexpr char kValueRefRegParamScope = 'g';

// IX-1 / IX1-V2: which languages record a slot join, and how — the one table both the extractor (ingest_valuerefs.h) and the
// join (valuerefindex.h) read. A language's row supplies the per-language pieces of the language-blind join (SlotIndex):
// callSide — how a call THROUGH a field is found:
//   ThroughRows: the extractor records the field calls itself (C family: kValueRefSlotCallScope rows; everyFieldCall = every
//     `x->f( … )` in C, the C++ gate otherwise);
//   MemberCallByName: an ordinary member call `x.F( … )` (a Call reference with memberCall) is a call through field F when some
//     function value is stored in a field F, joined at index time by the field name (the receiver's type is not read: the name
//     tier, via="slot-name"); the extractor records only the STORE side (Go);
//   ParenFieldCall: `(x.f)( … )`, the only spelling that calls a function-valued field (`x.f( … )` is always a method call), recorded
//     by the extractor as a kValueRefSlotCallScope row, typed when x is `self` (Rust: ingest_rustslots.h).
// typeKey — how a slot's declared struct type is keyed (both sides and --for's struct rows key the same way):
//   TypedefFacts: the type as written, through the typedef / field-type slot facts (C family);
//   PackageDir: the package DIRECTORY the type is declared in, plus its name (Go: valuerefindex.h slot_join::GoTypeKeys);
//   ModuleType: the one in-tree struct the name spells — its own file's, else its crate's, else the repo's only one (Rust:
//     slot_join::RustTypeKeys; `Self` is resolved to the impl type by the extractor).
// pathSep — a registrar may be an associated function reached by a PATH call (`CallEval::new( … )`): the argument row's callee
//   is written `Owner<pathSep>name`, resolved to the owner type's function of that name ("" = bare callees only, never a method).
// memberPointers — FN-SLOT S2 (C++): a pointer to MEMBER is a function value and its call a slot call. `&Cls::m` in a value
//   position is a Value row naming m with memberRoot = Cls (resolved to Cls's method m only, never a namesake: valuerefindex.h
//   ownedBy); `( obj.*x.f )( … )` is a slot call through field f of x's type (the `.*` proves f holds a member pointer, so no C++
//   gate applies). Floors: `->*` (the grammar reads it as an ERROR node), a member pointer held in a plain variable.
enum class VrSlotCallSide : std::uint8_t { ThroughRows, MemberCallByName, ParenFieldCall };
enum class VrSlotTypeKey : std::uint8_t { TypedefFacts, PackageDir, ModuleType };
struct VrSlotLang
{
    Lang             lang;
    bool             everyFieldCall;
    VrSlotCallSide   callSide;
    VrSlotTypeKey    typeKey;
    std::string_view pathSep;
    bool             memberPointers = false;
};
inline constexpr VrSlotLang kVrSlotLangs[] = {
    { Lang::C, true, VrSlotCallSide::ThroughRows, VrSlotTypeKey::TypedefFacts, "", false },
    { Lang::Cpp, false, VrSlotCallSide::ThroughRows, VrSlotTypeKey::TypedefFacts, "", true },
    { Lang::Go, false, VrSlotCallSide::MemberCallByName, VrSlotTypeKey::PackageDir, "", false },
    { Lang::Rust, false, VrSlotCallSide::ParenFieldCall, VrSlotTypeKey::ModuleType, "::", false },
};
inline constexpr std::array<const VrSlotLang*, kLangCount> kVrSlotLangOf = []
{
    std::array<const VrSlotLang*, kLangCount> byLang {};
    for( const VrSlotLang& row : kVrSlotLangs )
    {
        byLang[ static_cast<std::size_t>( row.lang ) ] = &row;
    }
    return byLang;
}();
// The slot row of language `l`, nullptr when it records no slot join.
inline const VrSlotLang* vrSlotLang( Lang l ) noexcept
{
    return enumTableAt( kVrSlotLangOf, l, static_cast<const VrSlotLang*>( nullptr ) );
}
// REGISTRAR (lane registrar; reports/dispatch-register-design.md REGISTRY half, the Py/TS first slice): which languages join a
// registry KEY to its registration sites, and how — the language layer src/regindex.h reads (one place for the join itself).
//   ReceiverMethod (Python): a call `K.m( f )` / `mod.K.m( f )` whose receiver K is a module variable `K = C()` and whose method
//     C.m stores parameter k into a container held by a field of self (kValueRefRegParamScope facts; containerStores names the
//     store calls); f at argument k is registered under the key K. consumerSkip: methods on K that are neither a registration
//     nor a consumer (the unregister side).
//   ProviderRecord (TypeScript): an object literal `{ provide: K, useClass: C }` (keyField + valueFields) registers C under K;
//     a consumer is a `consumerCalls` call naming K (`@Inject( K )`, `inject( K )`).
enum class RegForm : std::uint8_t { ReceiverMethod, ProviderRecord };
inline constexpr std::string_view kPyRegStores[]   = { "add", "append", "appendleft", "extend", "insert" };
inline constexpr std::string_view kPyRegSkip[]     = { "disconnect", "discard", "remove", "unregister" };
inline constexpr std::string_view kTsRegValues[]   = { "useClass", "useExisting", "useFactory", "useValue" };
inline constexpr std::string_view kTsRegConsumer[] = { "Inject", "inject" };
struct RegLang
{
    Lang                              lang;
    RegForm                           form;
    std::span<const std::string_view> containerStores;   // ReceiverMethod: `self.f.<store>( … param … )`; `self.f[ k ] = param` always
    std::span<const std::string_view> consumerSkip;      // ReceiverMethod
    std::string_view                  keyField;          // ProviderRecord
    std::span<const std::string_view> valueFields;       // ProviderRecord
    std::span<const std::string_view> consumerCalls;     // ProviderRecord
};
inline constexpr RegLang kRegLangs[] = {
    { Lang::Python, RegForm::ReceiverMethod, kPyRegStores, kPyRegSkip, "", {}, {} },
    { Lang::TypeScript, RegForm::ProviderRecord, {}, {}, "provide", kTsRegValues, kTsRegConsumer },
};
// The registrar row of language `l`, nullptr when it joins no registry (the mechanism is then inert: byte-identical answers).
inline const RegLang* regLang( Lang l ) noexcept
{
    return findByField( kRegLangs, &RegLang::lang, l );
}
inline bool slotJoinsByFieldName( Lang l ) noexcept
{
    const VrSlotLang* row = vrSlotLang( l );
    return row != nullptr && row->callSide == VrSlotCallSide::MemberCallByName;
}
// How language `l` keys a slot type (TypedefFacts for a language with no slot row: it keys nothing of its own).
inline VrSlotTypeKey slotTypeKeyOf( Lang l ) noexcept
{
    const VrSlotLang* row = vrSlotLang( l );
    return row == nullptr ? VrSlotTypeKey::TypedefFacts : row->typeKey;
}
// The path separator of language `l`'s registrar callees ("" = bare callees only).
inline std::string_view slotPathSep( Lang l ) noexcept
{
    const VrSlotLang* row = vrSlotLang( l );
    return row == nullptr ? std::string_view() : row->pathSep;
}
// A language whose slot types key by its own rule (valuerefindex.h slot_join), not through the C family's typedef facts.
inline bool slotKeysOwnTypes( Lang l ) noexcept
{
    return slotTypeKeyOf( l ) != VrSlotTypeKey::TypedefFacts;
}
// A slot type key written with the `struct` / `union` keyword (`struct thandle`) leads with this mark: a C tag is no typedef
// name, so the join never reads it through an alias. A slot fact whose composeRel is kValueRefSlotBodyRel declares that its
// owner's struct BODY is in this file (no field): one tag with bodies in two files is two types, so it joins nothing.
inline constexpr char kValueRefSlotTagMark = '\x02';
// FN-SLOT S2 (c): the slot type key of a call of a function-like macro `M( … )->f( … )` is "()M"; a macro whose body is one
// pointer cast to a named type records an alias fact "()M" → that type (ingest_valuerefs.h noteMacroCast). A "()M" no fact
// resolves (a function returning a pointer, a macro of another shape) is an unknown type: the name tier.
inline constexpr std::string_view kVrSlotMacroCastMark = "()";
inline constexpr char kValueRefSlotBodyRel = '{';
// FN-SLOT S2 fix 1 (F-2): a body fact's composeRel is kValueRefSlotBodyRel followed by the SCOPE PATH of the class (its enclosing named
// namespaces and classes, outermost first, "::"-joined; an anonymous or inline namespace is transparent; "" = the global scope).
// A C++ `&Cls::m` Value row's memberVia says where the pointer was written, so the join can tell the in-tree class from an external
// namesake: the written QUALIFIER (`grpc` in `&grpc::Server::start`, a leading "::" kept; `using ns::Cls;` supplies it for a bare
// `Cls`), the SITE (the named namespaces and classes enclosing the pointer, plus the scope an out-of-line definition's declarator
// writes) and the `using namespace` DIRECTIVES in the file (',' joined), the three joined by kVrMemberScopeSep.
inline constexpr char kVrMemberScopeSep = '\x1f';
struct VrMemberScope
{
    std::string_view qualifier;
    std::string_view site;
    std::string_view directives;
};
inline VrMemberScope vrMemberScopeOf( std::string_view via ) noexcept
{
    VrMemberScope out;
    const std::size_t a = via.find( kVrMemberScopeSep );
    if( a == std::string_view::npos )
    {
        out.qualifier = via;
        return out;
    }
    const std::size_t b = via.find( kVrMemberScopeSep, a + 1 );
    out.qualifier       = via.substr( 0, a );
    out.site            = via.substr( a + 1, b == std::string_view::npos ? std::string_view::npos : b - a - 1 );
    out.directives      = b == std::string_view::npos ? std::string_view() : via.substr( b + 1 );
    return out;
}

// Essential-complexity ev_why= reason vocabulary (the essential-complexity design note, §5.1). PUBLIC the
// moment it ships (test/attrvocabcheck.sh's standing posture; test/essentialcxcheck.sh pins the spellings):
// adding a tag later is a compatible extension, renaming one is not. Declaration order MUST track the
// EvWhyTag indices ingest.cpp writes — the table is the single source both emitters read.
inline constexpr std::size_t kEvWhyTagCount = 8;
inline constexpr const char* kEvWhyTagTable[] = {
    "guard-return",     // return/throw whose escape crosses at least one construct (incl. §1.3's guard clause)
    "loop-escape",      // break/continue out of a loop from under an intervening construct
    "switch-escape",    // break (or Java yield) out of a switch from under an intervening construct
    "goto",             // goto across a construct boundary (incl. C# goto case/default)
    "labelled-jump",    // labelled break/continue (Go/JS/TS/Java/Rust/Swift)
    "back-edge",        // Ruby redo/retry — a hand-rolled back edge outside every prime
    "fallthrough",      // Go fallthrough — an explicit intra-switch goto
    "multi-entry",      // a case label displaced into a loop/branch (Duff's device; §2.6)
};
static_assert( std::size( kEvWhyTagTable ) == kEvWhyTagCount, "kEvWhyTagTable: one spelling per ev_why tag — a spelled extent zero-fills a missing one into a null the emitter prints" );

// A definition = one node in the graph. symbols[i].id == i (dense, deterministic order).
struct Symbol
{
    NodeId        id     = kNoNode;
    SymKind       kind   = SymKind::Other;
    Lang          lang   = Lang::Unknown;
    std::uint16_t ppAlt  = 0;          // ppalt disclosure — full doc below, next to the other Q4 metric scalars.
                                       // DECLARED here, not there: the two pad bytes between `lang` (u8 x2) and
                                       // `fileId` (u32) are the struct's only remaining hole, so this u16 is free
                                       // here and +8 bytes there (measured by the static_assert below firing
                                       // 104 == 96 on the grouped placement — not hand-arithmetic).
    std::uint32_t fileId = 0;          // index into IngestResult::files
    std::uint32_t line   = 0;          // 1-based, for reference
    std::uint32_t sigStartByte = 0;    // signature span [sigStartByte, sigEndByte) in the file —
    std::uint32_t sigEndByte   = 0;    //   def start .. body start, for --pack-signatures
    std::uint32_t endByte      = 0;    // full def end (body-inclusive); [sigStartByte, endByte) = whole def, for --expand
    std::uint32_t cx           = 0;    // cyclomatic complexity (1 + decision points in the def); --metrics
    std::uint32_t ccx          = 0;    // cognitive complexity (nesting-weighted; SonarSource-style); --metrics, hotspots
    // Q4 size smells (SIZE is the master variable — §1d): computed at ingest from the def's AST/span.
    // ALL descriptive facts on --metrics ONLY, never a gate. `params`/`maxNest` are meaningful for
    // functions/methods; 0 for other kinds. `loc` is the def's physical line span (body-inclusive).
    std::uint32_t loc          = 0;    // physical lines the def spans = 1-based end line − start line + 1; --metrics loc=
    // local-variable-indexing plan, Phase 1 (docs/LOCALS_INDEXING.md): a FLOOR count of the def's own
    // local-variable DECLARATORS, populated by the SAME fused-DFS complexity walk that computes cx/ccx/
    // maxNest (ingest.cpp complexityOf/cc_walk) — zero new tree-sitter queries. MVP scope is C/C++ only
    // (see localsCountedLang below); meaningful for fns/methods only (0 for other kinds, same convention
    // as params/maxNest). Counts every `declarator`-fielded child of a `declaration` node whose PARENT is
    // the enclosing `compound_statement` (a direct block-statement local) — this naturally excludes
    // if-init/switch-condition/for-init/catch-clause declarators (their parent is the control-structure
    // node, not compound_statement) without any per-shape special case. L3 fix (2026-08-08): a
    // comma-separated statement (`int a=1,b=2,c=3;`) is ONE `declaration` node but THREE declarators, so
    // it counts as 3, not 1 (cc_countLocalDeclarators, ingest.cpp) — counting the statement instead of the
    // declarator undercounted on the exact axis the structured-binding exclusion below exists to avoid. A
    // structured-binding declarator (`auto [a,b] = …`) is still explicitly excluded (one declaration,
    // ambiguous per-declarator name count — see cc_walk's locals-counting block); a type-only declaration
    // with no declarator (a local forward decl, e.g. `struct Foo;`) now correctly counts as 0 rather than
    // the pre-fix "1". `--metrics` emits it as locals="N" locals_floor="1" (never a bare 0 for an
    // uncovered language — see localsCountedLang).
    std::uint32_t locals       = 0;
    // PPALT DISCLOSURE — count of ALTERNATIVE-introducing preprocessor nodes (`#else`/`#elif`/`#elifdef`)
    // inside the def, filled by the SAME fused cc_walk DFS that computes cx/ccx/maxNest/locals (zero new
    // tree-sitter queries). When > 0 the body carries branches that never coexist at compile time, so every
    // summed structural metric on this row (cx/ccx/nest/loc/locals) over-counts vs any single build —
    // measured ~2x on bullet's btMatrix3x3.h::getRotation (`#if BT_USE_SSE … #else … #endif`
    // implementations of the same function). ripwire does NOT guess which branch a build takes (which arm
    // compiles depends on flags it never sees — doctrine: never quietly guess); it keeps the deterministic
    // sum and DISCLOSES the alternative count so metric consumers can discount. A bare `#if…#endif` with no
    // `#else` introduces no mutually-exclusive alternative and does not count. C-family + C# by grammar
    // construction (only those grammars have preproc nodes) — no language predicate needed, unlike
    // `locals`. Meaningful for fns/methods only (0 otherwise, same convention as params/maxNest); emitted
    // as ppalt="N" on --metrics, ABSENT when 0. Saturates at 65535. See test/ppaltcheck.sh.
    // (The `ppAlt` field itself is declared UP TOP, in the pad hole after `lang` — see its own comment.)
    // NESTING-DEPTH PROFILE — what `maxNest` alone cannot say. maxNest is a MAX: one line at depth 9 and a
    // thousand lines at depth 9 report the same number, so a long BLOCKED-SEQUENTIAL function (a run of
    // shallow scoped steps, the max set by one inner loop) is indistinguishable from a TANGLED one that
    // holds depth across hundreds of lines. Every consumer of nest= inherits that blindness: the quality
    // panel's structural family, --readability's rank, the ensemble join. Two facts fix it, both filled by
    // the SAME fused cc_walk DFS (no new tree-sitter queries) and both keyed to the EXISTING structural bar
    // quality::kNestBar — no new magic number. Language-agnostic, unlike `locals`: cc_walk computes nesting
    // for every grammar. See test/nestprofilecheck.sh; `humps` is CodeScene's "bumpy road" factor.
    //
    // humps  — count of MAXIMAL control-nesting regions that reach the bar (CodeScene's "bumpy road": a rise
    //          above the threshold then a fall). One deep tangle is 1; repeated missing abstractions are
    //          many. EXACT, not a floor: each region has exactly one first-crossing node in the walk, and a
    //          region nested inside an already-deep one cannot cross again. Saturates at 65535 — a def with
    //          more humps than that is past every triage threshold and the exact number buys nothing.
    // deepLoc — physical lines lying inside those regions; deepLoc/loc is the fraction the max throws away.
    //          A FLOOR (emitted as deep_floor="1"), because the clamp that stops two humps sharing a line
    //          from billing it twice can only ever subtract. Saturates at 65535 for the same reason.
    //          deepLoc COUNTS LINES AND humps COUNTS REGIONS, so `deep < humps` is legal output and not a
    //          defect: two sibling regions genuinely share a line when both are written on it (see
    //          test/nestprofilecheck.sh arm 11's negative control), or anywhere in minified source. Three
    //          separate validators have read that shape as a bug, so the metrics legend says it out loud
    //          and arm 11 pins it as correct — alongside the case that WAS a defect, distinct-line regions
    //          collapsing because the deepEnd clamp was fed regions out of document order (nestcal r1,
    //          kParserVer 44, removed the only out-of-order call site with the clause-noting quirk itself).
    // Both are 0 exactly when maxNest < quality::kNestBar, so serialize.h omits them there rather than
    // writing a bare 0 — lossless, because `nest=` is already on the row (test/nestprofilecheck.sh arm 5
    // pins that equivalence in both directions).
    std::uint16_t humps        = 0;
    std::uint16_t deepLoc      = 0;
    // ESSENTIAL COMPLEXITY ev(G) (McCabe 1976; NIST SP 500-235) — what remains after every structured
    // region collapses. Computed SYNTACTICALLY inside the same fused cc_walk DFS (single-entry is
    // guaranteed by the grammar; only single-EXIT can fail, via jump nodes), per
    // the essential-complexity design note §2: a jump marks irreducible every construct strictly between it
    // and its target, irreducibility propagates outward to the function root (stopping at closure/
    // nested-fn boundaries), and a marked switch head contributes every arm. ev = 1 + Σ marked
    // constructs' own cx decision weights, so ev <= cx is STRUCTURAL, not hoped for. 1 = fully
    // structured (any contiguous region extracts mechanically); >= 2 = some region has a second exit
    // and extract-method on it is a rewrite, not a refactor. A FLOOR (ev_floor=): noreturn CALLS,
    // macro-hidden returns and unresolvable goto targets are invisible to a syntactic walk and can only
    // RAISE the true value — an unrecognised jump marks NOTHING, never speculatively. Strict single-exit
    // McCabe counts a guard clause (§10.1 Option A, the owner's call); evWhy is what keeps that honest —
    // the guard-return share is visible and subtractable per row. Convention note, reconciled against an
    // independent CFG reduction (test/essentialcxcheck.sh header): arm weights mirror cx exactly, so a
    // marked switch whose arms include `default:` charges every arm where a residue's E-N+2 charges
    // arms-1 — the same convention on both sides of ev <= cx, disclosed rather than special-cased.
    // 0 for non-function kinds and for languages evCountedLang excludes (Bash); saturates at 65535 with
    // humps' justification. Emitted iff ev >= 2 (absent on a cx row means EXACTLY 1 — never a bare "1").
    std::uint16_t ev           = 0;
    // evWhy[t] = how many jumps contributed under kEvWhyTagTable[t] (a jump contributes when its
    // strictly-between chain is non-empty — a tail return or an arm-tail break contributes nothing).
    // Saturates at 255 per tag: a def past that is beyond every triage threshold (humps' rule).
    std::array<std::uint8_t, kEvWhyTagCount> evWhy{};
    std::uint16_t params        = 0;   // parameter count from the def's parameter-list child; --metrics params= (NUMBER only — no 7±2)
    std::uint8_t  maxNest       = 0;   // max control-structure nesting depth reached inside the def; --metrics nest=
    std::uint8_t  arityExact    = 0;   // B2.2: 1 ⇒ `params` is a FIXED, call-comparable arity (no variadic / default
                                       // args, and NOT an implicit-`self` method) → a same-name candidate whose
                                       // params ≠ the call-site arg count is provably wrong and may be dropped.
                                       // 0 (default, the SAFE state) ⇒ never arity-filter this def. See ingest.cpp.
    // L8 IN-FILE TEST SCOPE: 1 ⇒ a syntactic in-file test convention encloses (or IS) this def — Rust
    // `#[cfg(test)] mod` / `#[test] fn`, Python `class Test*` / a module-level `def test_*`, a JS/TS
    // helper inside `describe(`/`it(`/`test(`, a C# `[Fact]`/`[Test]`/`[TestMethod]` member. Computed at
    // extraction by ingest.cpp::inFileTestScope (see its banner for what each rule deliberately does NOT
    // cover) and rides the per-file cache record, so kParserVer gates it like any other extracted fact.
    // 0 (the SAFE state) means "no in-file convention found", NEVER "this is production": the path
    // signal is the other half, and filter.h::isTestSymbol is the ONE predicate that ORs them — every
    // symbol-keyed consumer of the test partition must route through it so the two halves cannot drift.
    std::uint8_t  testScope       : 1 = 0;
    // INTERNAL LINKAGE (C and C++ only; gate test/decltodefcheck.sh arm B2): 1 ⇒ this definition is visible to its
    // own translation unit alone — it sits inside an anonymous `namespace { }` (at any depth) or carries a
    // namespace-scope `static`. A class-scope `static` member has external linkage and is NOT marked. Read by
    // graph.h::declToDefFollowThrough: a header's declaration can only be implemented by an external-linkage
    // definition, so an internal one is kept only when it sits in the declaring file itself, and is otherwise
    // counted in unproven_defs= like any other dropped candidate (the H1 note's clause 3). Computed at extraction
    // (ingest_names.h::cppInternalLinkage), rides the per-file
    // cache record, so kParserVer gates it like every other extracted fact. 0 (the SAFE state) means "no internal
    // linkage found", so a grammar that never sets it keeps today's gather. Shares testScope's byte as a bit-field:
    // Symbol has no pad byte left (the static_assert below holds unchanged).
    std::uint8_t  internalLinkage : 1 = 0;
    // STD-ROOTED SCOPE (#150, C++ only): 1 ⇒ walking this def's FULL enclosing-owner chain out to the
    // translation unit, the OUTERMOST namespace found is literally `std` — i.e. this def genuinely lives
    // inside namespace std, at any nesting depth (`std::ranges::contains`, `std::__1::ranges::contains`),
    // not merely a def whose IMMEDIATE scope happens to spell "ranges" or "__1" the way a user's own
    // `mylib::ranges::` could too. Computed at extraction by ingest_names.h::cppDefinitionRootsStd, which
    // walks the SAME ancestor chain enclosingScopeOf already walks (so the two can never disagree about
    // which def is "inside std") for an in-class/in-namespace def, or reads the written qualifier chain
    // (cppQualifiedChainRootsStd, shared with the call side) for an out-of-line `std::Type::method(){}`.
    // Read only by graph.h::keepStdQualifiedCandidates, alongside Reference::qualifierRootsStd — see that
    // guard's banner for the full rule, including why a std-rooted DECLARATION with no body still refuses
    // (K3). 0 (the safe default) on every def this bit never reaches: any non-Cpp language, or a def with
    // no enclosing namespace at all. Shares internalLinkage's byte as a 3rd bit of the SAME bit-field —
    // Symbol has no pad byte left (the static_assert below holds unchanged; this is not a new byte).
    std::uint8_t  scopeRootsStd : 1 = 0;
    // FUNCTION-LOCAL (every language; gate test/fnliteralcheck.sh §6): 1 ⇒ this FUNCTION's name is bound inside
    // another function's body (ingest_names.h enclosingFunctionScope), and IngestResult::fnLocalScopes holds that
    // function's byte span under this id. graph.h reachableByName reads it: a call outside the span cannot name this
    // def, so it yields to every candidate that call can. A 4th bit of the same byte (no new byte; the assert holds).
    std::uint8_t  fnLocal : 1 = 0;
    // B2.2 MINIMUM ARITY (train 29): the fewest arguments a call can pass — params minus defaulted ones (ingest_metrics.h
    // kParamMinLangs); 0 = no lower bound known. graph.h takes the minimum over this def AND every declaration of it before
    // dropping a candidate a shorter call cannot reach. The last 4 bits of the same byte (no new byte; the assert holds),
    // SATURATING at 15 in ingest_model.h::assignSymbols: a lower minimum only keeps candidates, so saturation is sound — a
    // 16-required-parameter def merely stops being dropped for 15-argument calls. RawDef and the cache keep the full u16.
    std::uint8_t  paramsMin : 4 = 0;
    // EXTENT HONESTY (src/extentsuspect.h, gate test/extentcheck.sh): the containment rules this def's extent,
    // scope or recovered kind FAILED, as extent::kSuspect* bits (name/head/scope/error); 0 ⇒ every rule held.
    // Computed at LOAD from facts the cache already carries (the extents, the name byte, the `recovered`
    // extraction bit), in ingest_model.h::markExtentSuspects — never persisted itself, so a rule change needs no
    // parser bump. Rows stay; surfaces DISCLOSE it as extent_suspect="name,head,scope,error" and --hotspots keeps
    // a flagged def's complexity out of its ranking. Takes the last free pad byte (the static_assert below holds).
    std::uint8_t  extentSuspect = 0;
    std::string   name;                // final identifier segment
    std::string   scope;               // enclosing class/namespace name (C++), for canonical scope::name resolution; "" if none
};

// SoA-minded tripwire: keep Symbol tight (smallest types, grouped) so the symbols[] array stays cache-dense.
// Two std::string members dominate; the scalars pack into what their alignment leaves. If this fires after a
// field add, re-check you used the smallest type and grouped it — don't just bump N (a size regression is a
// real signal here). libc++/libstdc++ std::string is 24 B (3 words); adjust N per-toolchain if it ever differs.
// `locals` (Phase 1 local-variable-indexing, docs/LOCALS_INDEXING.md) added as a uint32_t grouped with
// the other Q4 size-smell scalars, right before `loc`/`params`/`maxNest`/`arityExact` — measured (not
// assumed): sizeof(Symbol) is UNCHANGED at 48 + 2*sizeof(std::string). The scalar run before the two
// std::string members already carried 4 B of trailing alignment padding (std::string needs 8-B alignment
// on a 64-bit ABI); the new uint32_t landed in that padding for FREE — the best possible SoA outcome, not
// a coincidence worth losing: re-measure with a fresh `static_assert` fire (don't hand-arithmetic) if this
// ever needs to change again. `ppAlt` (uint16_t, ppalt disclosure) could NOT repeat the trick — `locals`
// had consumed the tail padding entirely (this assert fired 104 == 96 on that placement) — so it sits in
// the struct's one remaining hole instead, the 2 pad bytes between `lang` and `fileId` up top; sizeof
// unchanged, measured by this assert, not hand-arithmetic.
//
// `humps`/`deepLoc` (the nesting-depth profile) then cost the first real growth: 48 → 56 + 2*string,
// MEASURED with a standalone sizeof probe after this assert fired, not derived on paper. The step is
// unavoidable rather than sloppy — `locals` had spent the last of the trailing padding, so the scalar run
// ended exactly on an 8-B boundary, and Symbol's alignment is 8 (the std::string members), so ANY further
// field rounds the object up by a full 8 B no matter how small its type. Two uint16_t is therefore not a
// compromise but the whole point: it spends 4 B of that unavoidable 8 and leaves 4 B of live padding for
// the NEXT field to land in free, exactly as `locals` did. A smaller type here would buy nothing and cost
// range (both saturate at 65535 — see the fields' own comment); a uint32_t pair would have cost 16.
//
// `ev`/`evWhy` (essential complexity) then cost the second step: 56 -> 64 + 2*string, MEASURED with the
// standalone sizeof probe after this assert fired (the design predicted UNCHANGED because it budgeted the
// uint16_t alone; the eight evWhy tag counters are what force the step). The uint16_t ev spends 2 of the
// 4 B of live padding the humps/deepLoc step left; the 8×uint8_t evWhy run then crosses the 8-B boundary
// once (+8), landing with 2 B of live padding for the NEXT field. The alternative — packing evWhy into
// one uint32_t at 4 bits per tag — was rejected because a 4-bit counter saturates at 15, and printing
// "guard-return:15" for a function with 20 guard returns is a wrong count, not a floor (honesty rule #3);
// uint8_t saturating at 255 inherits humps' justification instead.
//
// `paramsMin` (B2.2 minimum arity, train 29) costs nothing: a 4-bit field in testScope's bit-field byte, whose last
// 4 bits were free. A u16 field would have cost a full 8 B (64 -> 72: extentSuspect had taken the last pad byte).
static_assert( sizeof( Symbol ) == 64 + 2 * sizeof( std::string ),
               "Symbol size changed — verify the new field uses the smallest type + is grouped (SoA); see model.h" );

// The byte span of the function whose body binds a function-local def's name (Symbol::fnLocal). A call site inside
// [start, end) of the def's own file can name the def; any other site cannot (graph.h reachableByName).
struct FnLocalScope
{
    NodeId        id    = kNoNode;
    std::uint32_t start = 0;
    std::uint32_t end   = 0;
};

// Is this symbol a DEFINITION rather than a forward DECLARATION? The house test is `endByte > sigEndByte` — a span that
// runs past its signature owns a body — and every consumer that must tell the two apart routes through here: graph.h's
// decl/def collapse, canonByName and declToDefFollowThrough; lexical.h's def-over-decl tiebreak; situ.h's decl/def
// partner pass. Kotlin breaks the house test for TYPES, which PR #126 found and fixed in graph.h's collapse (a
// CodeRabbit review finding): the language has no forward declarations, so `data class User(val name: String)`,
// `class Token`, `interface Marker` and `object Empty` are complete definitions that simply own no class_body, and read
// as declarations each was collapsed away whenever a same-named type with a body existed (a Java `User` in another
// directory included). queries/kotlin/tags.scm tags every Kotlin type @definition.class, so SymKind::Class is the kind
// that fires today; Struct and Interface are listed so a finer tag cannot quietly reopen the collapse. A bodyless Kotlin
// FUNCTION stays a declaration: an interface member or an `abstract fun` really is a contract whose body lives in an
// override. Consumers that MEASURE or SERVE a body (clones, complexity, --readability units, lexical.h's route anchor)
// keep the plain span test: a class with no body is a definition, but it has no volume. Gate: test/kotlincheck.sh §11
// (the PR's bodyless interface) and §13.
// Ruby breaks it for EVERY kind: the language has no declarations at all — no prototype, no abstract member, no
// interface — so each class, module, def, attr accessor and constant it indexes is the definition of its name. An
// `attr_reader :aliases` accessor and an empty `def on_event; end` hook own no body span, and read as declarations the
// collapse evicted them for any same-named bodied def in the family: a call inside Tracker to its own `aliases` bound to
// an unrelated Join#aliases. Gate: test/rubybarecallcheck.sh ("Ruby has no declarations").
inline bool isDefinitionNotDeclaration( const Symbol& s ) noexcept
{
    const bool kotlinType = s.lang == Lang::Kotlin && ( s.kind == SymKind::Class || isStructOrNamedType( s.kind ) || s.kind == SymKind::Interface );
    return s.endByte > s.sigEndByte || kotlinType || s.lang == Lang::Ruby;
}

// local-variable-indexing plan Phase 1 MVP scope (docs/LOCALS_INDEXING.md): C/C++ only — highest
// locals/function ratio in the survey (5-15/fn vs 3:1 Python, 0.2-0.8 Go/Rust) and `locals` is threaded
// through ingest.cpp's ALREADY C-family-only large-function/deep-nesting complexity walk, so this extends
// shipped code rather than building a new cross-language subsystem. ObjC/ObjC++ is a named fast-follow
// (ObjC's declaration-statement grammar differs enough to want its own fixture pass), not MVP. ANY caller
// that needs to know whether `locals`/`locals_floor` can be trusted for a given Symbol — serialize.h's
// --metrics emitter, naminglens.h's Phase-2 local-name walk gate — MUST route through this ONE predicate,
// so the covered-language set can never drift between the two call sites.
inline bool localsCountedLang( Lang lang ) noexcept
{
    return lang == Lang::Cpp || lang == Lang::C;
}

// Essential-complexity coverage: 12 of the 18 CODE languages — every one EXCEPT Bash, PHP, Lua, Elixir, Dart and
// Kotlin (Elixir and Dart landed without joining it, so their ev is withheld the same way). Bash (the
// essential-complexity design note, §3.2.8: `break N`/`continue N` take a numeric
// level count, `exit` and `trap` are process-level, and function boundaries are weak — not worth a
// wrong number). PHP and Lua are out for the language-port round's own reason and it is a DISCLOSED
// NON-GOAL, not an oversight: ev's per-construct weights must mirror isDecisionType exactly (the ev
// <= cx containment below depends on it), and neither language's exit vocabulary was measured in
// that round — PHP adds `goto`, `exit`/`die` as expression-position process exits and `match` arms;
// Lua has `repeat … until`, `goto`, and NO `continue` at all. Kotlin joins them for the SAME reason:
// its decision vocabulary — `when` (pattern-match, not a switch), the elvis operator `?:`, `!!`
// non-null assertion as an implicit-throw exit, and `suspend`-function early-return/cancellation
// shapes — is not yet checked against isDecisionType, so ev would either double-count `when` arms
// against `if`-chain weights or silently omit the elvis/`!!` exits, either way an unmeasured number
// presented as measured. cx/ccx/nest ARE emitted for Kotlin (the shared walk covers `when`, `try`,
// loops); only ev is withheld, so the reading is "not measured", never "measured zero". Markdown/
// Json/Toml/Yaml/Unknown never carry a cx row, so listing them here would be vacuous either way. ANY
// consumer asking whether Symbol::ev/evWhy can be trusted for a def — serialize.h's two emitters,
// ensemble.h's annotation — MUST route through this ONE predicate, for localsCountedLang's reason:
// the covered set must never drift between the emitter and any future consumer.
inline bool evCountedLang( Lang lang ) noexcept
{
    return    lang == Lang::Cpp  || lang == Lang::C     || lang == Lang::ObjC || lang == Lang::Python
           || lang == Lang::TypeScript || lang == Lang::JavaScript || lang == Lang::Go || lang == Lang::Rust
           || lang == Lang::Swift || lang == Lang::Java || lang == Lang::Ruby || lang == Lang::CSharp;
}

// local-variable-indexing plan Phase 2 (docs/LOCALS_INDEXING.md): one CAPTURED local-variable NAME,
// from the on-demand re-parse ingest.cpp's collectGatedLocalNames runs ONLY for a function that already
// cleared BOTH the existing size/complexity gate AND locals>=kNamingLocalsGateFloor (naminglens.h) — never
// promoted to a Symbol/NodeId, never entering the call graph, never cached (recomputed fresh every time a
// caller asks, since asking is rare by construction). `name` is OWNED (not the plan's literal
// "non-owning string_view"): the file bytes the re-parse reads live only as long as naminglens.h's local
// getBytes() cache for ONE lint pass, so a view into them would dangle the moment that pass's caller
// tries to hold a LocalNameFact any longer — a real lifetime constraint the plan's wording didn't have in
// view (its own self-correcting "Grounding note" already flagged that its citations needed a refresh
// pass; this is the same class of correction). `declDepth`: 1 = a direct statement in the function's OWN
// outermost block; 2+ = at least one control-structure block deeper — see checkLocalNameShape's own
// declDepth>=2 gate on naming-short.
struct LocalNameFact
{
    std::string   name;
    std::uint32_t line      = 0;   // 1-based, absolute file line (not the re-parsed substring's own row)
    std::uint8_t  declDepth = 0;
};

// An unresolved reference (call/usage). Resolved into an edge in the graph stage.
// The prefix of a C++ call's memberPath that marks an ELEMENT-ACCESS receiver (Reference::memberPath, its C++ reading).
inline constexpr std::string_view kCppElementMark = "[]";

// A Python queue call's KEYWORD arguments (isQueueCallName), carried on its call reference's composeRel (a call is no compose record and no value-ref slot, so the
// field is free there): "" none, else "k<count>" and a trailing "o" when any keyword is spelled other than `timeout` / `block` (the two
// keywords queue.Queue.put/get and asyncio.Queue take). argCount counts them too (the resolver's arity filter needs that), so
// QueueHops (backhops.h) subtracts the count to read the positional arguments. Written by ingest_sidecap.h, read by pyKwArgsOf.
inline constexpr std::uint8_t kCallKwCount = 0x7F;   // the count's mask in callArity's keyword byte (saturating)
inline constexpr std::uint8_t kCallKwOther = 0x80;   // …and the flag: a keyword other than timeout / block
// The four calls QueueHops reads (backhops.h): the only Python calls whose keyword arguments ingest records.
inline bool isQueueCallName( std::string_view name ) noexcept
{
    static constexpr std::string_view kQueueCalls[] = { "get", "get_nowait", "put", "put_nowait" };
    return std::ranges::contains( kQueueCalls, name );
}
// The languages whose queue operations the hop rule reads (a per-kind table, as backhops.h selfKeyword's: Go channels need an ingest record first).
// Ingest records the queue calls' keywords for these; QueueHops (backhops.h) pairs only their symbols.
inline bool isQueueLang( Lang lang ) noexcept
{
    static constexpr Lang kQueueLangs[] = { Lang::Python };
    return std::ranges::contains( kQueueLangs, lang );
}
inline std::string pyKwTag( std::uint8_t kw )
{
    return "k" + std::to_string( unsigned( kw & kCallKwCount ) ) + ( ( kw & kCallKwOther ) != 0 ? "o" : "" );
}
struct PyKwArgs
{
    std::uint32_t count = 0;
    bool          other = false;
};
inline PyKwArgs pyKwArgsOf( std::string_view composeRel ) noexcept
{
    PyKwArgs out;
    if( composeRel.size() < 2 || composeRel[ 0 ] != 'k' )
    {
        return out;
    }
    std::size_t i = 1;
    for( ; i < composeRel.size() && composeRel[ i ] >= '0' && composeRel[ i ] <= '9'; ++i )
    {
        out.count = out.count * 10 + std::uint32_t( composeRel[ i ] - '0' );
    }
    out.other = i < composeRel.size() && composeRel[ i ] == 'o';
    return out;
}

struct Reference
{
    NodeId        fromSymbol = kNoNode;   // enclosing symbol (caller); kNoNode if file-scope
    std::uint32_t fileId     = 0;
    std::uint32_t line       = 0;         // 1-based line of the use site (ABS-3: for `--uses` p="file:line")
    std::uint32_t startByte  = 0;         // byte offset of the use site (RawRef's own, carried through for the
                                          //   block-span containment test in suppressShadowedReferences)
    Lang          lang       = Lang::Unknown;
    bool          isInherit  = false;     // true ⇒ a base-class/implements edge (derived → base), not a call
    bool          isDocLink  = false;     // true ⇒ a doc→code mention (backtick `ident` in markdown), not a call
    bool          isCompose  = false;     // true ⇒ a HAS-A member-variable type edge (S5-E); NEVER enters call graph / PageRank
    RefRole       role       = RefRole::Call;   // ABS-3 use-site role (call/read/write/import/extends/type); see RefRole.
                                                //   Only Call enters the call graph; the rest power --uses only.
    RecvKind      recv       = RecvKind::None;  // call-site receiver shape (P2-D narrowing); see RecvKind
    std::uint16_t argCount   = 0;         // B2.2: number of positional args at the call site when countable; 0 otherwise
    bool          argCountKnown = false;  // B2.2: true ⇒ the call-site argument list was reliably counted (no spread /
                                          //   splat / apply) → arity-filter candidates against argCount; false ⇒ never filter
    bool          viaArrow   = false;     // a C++/ObjC member call written `->` (`p->m()`, not `p.m()`). On a compose ref: calleeName is the
                                          //   POINTEE of a member written `std::unique_ptr<T>` / `std::shared_ptr<T>`, which `->` reaches and
                                          //   `.` never does (`p.reset()` is the smart pointer's own member) — Rule 2b requires the call's bit
    bool          qualifierRootsStd = false;  // #150: true ⇒ the FULL WRITTEN qualifier chain at this call site is rooted in
                                          //   namespace std — `std::X`, `::std::X`, `std::ranges::X`, `std::__1::ranges::X` — not just
                                          //   `qualifier` (the IMMEDIATE segment only: "ranges" for `std::ranges::move`, indistinguishable
                                          //   from a user's own `mylib::ranges::move`). Computed at extraction, C++ only, by
                                          //   ingest_names.h::cppQualifiedChainRootsStd, which reads the ENTIRE span tree-sitter gives the
                                          //   call's outermost qualified_identifier and keys only its first written segment — never guessed
                                          //   from `qualifier` after the H4 re-split has already thrown the outer segments away. Read only by
                                          //   graph.h::keepStdQualifiedCandidates, alongside Symbol::scopeRootsStd. false (the safe default) on
                                          //   every bare/unqualified call and on every non-Cpp language (ObjC gets no `qualifier` at all today —
                                          //   see keepStdQualifiedCandidates' stated floor — so this stays false there too, by construction).
    std::string   calleeName;             // referenced name (final identifier segment)
    std::string   qualifier;              // explicit scope at the call site (`A` in `A::b()`); "" if bare/method — for canonical resolve
    std::string   recvVar;                // receiver variable identifier when recv==NamedVar/FieldOfVar (`x` in `x->m()`); "" otherwise — for Rule 2
                                          //   A Ruby receiver the code BUILDS leaves it empty: its type is memberCtor/memberVia (rubyTypedRecvOf).
    std::string   fieldName;              // member variable name when isCompose (e.g. "m_pool"); ALSO the INTERMEDIATE
                                          //   field of a depth-2 chained receiver when recv is FieldOfThis/FieldOfVar
                                          //   (`this->m_pool.run()` → "m_pool") — the two are mutually exclusive
                                          //   (a compose ref is never a call ref, and the compose readers all gate
                                          //   on isCompose), so one slot carries both; "" otherwise. A third reading,
                                          //   on a Ruby call whose receiver is a constant written with a path (recv
                                          //   NamedVar, parser version 137): the path as written (`Billing::Invoice.issue`
                                          //   → "Billing::Invoice"; `described_class` → the group's constant whole),
                                          //   recvVar keeping the final segment every class is keyed by (graph.h
                                          //   RubyClassObjects::ofIndexed); no chain or compose reader reads a NamedVar's
    std::string   composeRel;             // "creates" (value/inline) or "uses" (reference/pointer) when isCompose; "" otherwise
    // FE-A (test/falseedgecheck.sh): Go, JS/TS, Rust and C record no receiver SHAPE for a member call — `x.f()`, `JSON.parse()`,
    //   `h.render()`, C's `ops->open()` keep recv == None, exactly like a bare `f()` (ingest_binds.h receiverOf: widening recv would move every
    //   recv==None guard). These two fields tell the shapes apart WITHOUT touching recv: memberCall is true when the callee
    //   is the field of a member access, and memberRoot is the receiver chain's ROOT identifier as written (`crypto` for
    //   `crypto.subtle.verify()`, `this`, a package alias), "" when the root is not an identifier (a call, a literal,
    //   `new X()`). Read only by graph.h's FalseEdgeRules. false/"" for every other language and every non-call ref.
    bool          memberCall = false;
    std::string   memberRoot;
    // FE-B (test/receiverevidencecheck.sh): the rest of a member call's receiver chain, for the receiver-evidence rule
    //   (graph.h ReceiverEvidence). memberPath is the member names BETWEEN memberRoot and the callee, '.'-joined —
    //   "bucket" for `this.bucket.listSchemas()`, "req.raw.headers" for `ctx.req.raw.headers.get()`, "" for `root.m()`.
    //   A markdown link stores the path and slug as written here (the slug lowercased). memberCall stays false.
    //   buildGraph reads it (bindMarkdownLinks).
    //   memberCtor is the class a CONSTRUCTED receiver names, final segment — "Reply" for `new Reply( r ).send()`, Go
    //   "Merger" for `(&Merger{}).Len()` — with memberRoot "" (a construction has no root identifier). Both "" for every
    //   other shape and every language that records no member-call shape.
    //   C++ (parser version 166): memberCall stays false, and a member call whose receiver is ONE element access of a one-hop
    //   container (`m[ k ].empty()`, `v.at( i ).size()`, `rule->bindings_[ k ].empty()`) carries kCppElementMark + the container's
    //   shape here ("m", "this.items_", "rule.bindings_"; ingest_binds.h cppElementContainer) — read only by graph.h's
    //   StdMemberGate receiver exception (stdReceiverOf); chainOf reads memberPath only beside memberCall. A C/C++ type alias
    //   record and a composeRel "elem" field record carry the std container's whole written text here (ingest_relations.h
    //   stdElementContainerText). Rust (lane L6): an `impl Trait for T` inherit ref carries the trait's path as written when it is
    //   qualified (`render::Renderer`, generic arguments dropped), "" for a bare trait name (ingest_relations.h rustImplVisitNode).
    std::string   memberPath;
    std::string   memberCtor;
    // FE-B on #373: a Ruby receiver the code BUILDS (`User.new`, a finder, a FactoryBot build, a let or local holding one)
    //   carries its type here, out of band: memberCtor = the class's constant as written (or the factory name when
    //   memberFactory), memberVia = the method that built it. recvVar is then empty. Read through rubyTypedRecvOf.
    std::string   memberVia;
    bool          memberFactory = false;
    // lane fcall-forward fix 1 (test/fcallforwardcheck.sh N7 N8 N10 N11 H): a JS/TS call reference the value-ref walk
    //   FORWARDED from `f.call( … )` / `f.apply( … )` (ingest_valuerefs.h forwardCallAt) — it stands for the bare call
    //   `f( … )`, which the source never writes. graph.h buildGraph keeps its edges only where the resolver PROVES a
    //   Function/Method (no via="name", no class/const/object target): an import proves a binding, not a function.
    //   Sits beside memberFactory in the alignment padding before baseBind: sizeof(Reference) is unchanged.
    bool          forwarded = false;
    // #155 (test/kotlincheck.sh §15, test/falseedgecheck.sh arm J): a Kotlin call whose lambda is written AFTER the argument list
    //   (`s.run { }`, `with( x ) { }`); the trailing lambda of a stdlib scope function. graph.h FalseEdgeRules' Kotlin arm drops
    //   the Java-method edge such a call would bind.
    bool          trailingLambda = false;
    // lane lego-transitive fix 1 (test/legotransitivecheck.sh NS arms), an INHERIT ref only (isInherit): the same-file declaration
    //   the base name binds to by the language's lexical lookup, as 1 + the byte its name starts at (ingest_relations.h
    //   localBaseBinding; 0 = no enclosing scope declares it, 0xFFFFFFFF = a scope too large to read, nothing proven). On an
    //   inherit ref memberRoot holds the base's WRITTEN qualifier (`Outer` for `Outer.Changed`, `b` for `b::Mid`, "" bare) —
    //   memberCall is false there, so no member-call reader sees it. graph.h's implementors builder reads both (baseEvidence).
    //   Sits in memberFactory's alignment padding: sizeof(Reference) is unchanged.
    std::uint32_t baseBind = 0;
};
// The sentinels Reference::baseBind holds besides a real binding (1 + a name byte): ONE definition for the writer (ingest_relations.h
// localBaseBinding) and every reader (graph.h provenBasesOf, valuerefindex.h inheritEdges / ClassFamilies::bindBase).
inline constexpr std::uint32_t kBaseBindNone          = 0;            // no enclosing scope declares the name
inline constexpr std::uint32_t kBaseBindUnknown       = 0xFFFFFFFFu;  // a scope was too large to scan: nothing proven either way
inline constexpr std::uint32_t kBaseBindTemplateParam = 0xFFFFFFFEu;  // fn-slot S2 fix 2: the written base is a TEMPLATE PARAMETER of the deriving class (`template <class B> struct M : B`): it names no declaration
static_assert( kBaseBindTemplateParam < kBaseBindUnknown, "the readers test `>= kBaseBindTemplateParam` for both sentinels" );

// ONE rule for every reader of the reference table that counts a call SITE (train 30, fcall-forward nit N1): a FORWARDED
// reference counts only where buildGraph kept its call — `keptForwards` is Graph::keptForwards, the ascending
// ing.references indices of the forwards it bound. A reader with no graph passes none, and every forwarded reference stays
// out. Readers: --uses (verbs_navigate.h collectUseSites), sites_at= and --edit-check's sites (editcheck.h forEachCallSite),
// --edit-check's incompatible-caller flags (editCheckIncompatibleFlags), callers_floor= (countfloor.h markUnboundSpellings).
inline bool forwardCounts( const Reference& r, std::uint32_t refIndex, std::span<const std::uint32_t> keptForwards ) noexcept
{
    return !r.forwarded || std::ranges::binary_search( keptForwards, refIndex );
}

// A Ruby call whose RECEIVER the code builds (parser version 132, test/rubytypedrecvcheck.sh): `c = Client.new` then `c.get`,
// `let( :user ) { create( :user ) }` then `user.activate!`, `User.find_by( … ).activate!`. ingest_binds.h reads the shape
// by Ruby's own local rule and writes the type into the reference's OWN fields (FE-B on #373: it used to ride recvVar as an
// in-band "<Class>.<via>" token): Reference::memberCtor = the class's constant as written (`User`, `OpenSSL::Cipher`), or
// the factory name with memberFactory set for a FactoryBot build, whose class only the tree's factory definitions know
// (graph.h rubyFactoryClasses); memberVia = the method that built it (`find_by`, `new`, `create`). recvVar is left empty,
// and the receiver KIND as it was (NamedVar, FieldOfVar), so every rule that does not read the type sees the call exactly
// as before.
struct RubyTypedRecv
{
    std::string_view type;              // the class's constant as written (`User`, `Admin::User`), or the factory name
    std::string_view via;               // the method that built it: `new`, a finder, a factory build
    bool             factory = false;   // `type` names a FactoryBot factory, not a class
};


// the type a Ruby reference's receiver was built as, or nullopt for every other reference
inline std::optional<RubyTypedRecv> rubyTypedRecvOf( const Reference& r ) noexcept
{
    if( r.lang != Lang::Ruby || r.memberCtor.empty() || r.memberVia.empty() )
    {
        return std::nullopt;
    }
    return RubyTypedRecv { r.memberCtor, r.memberVia, r.memberFactory };
}

// RSpec's targets (test/rubyrspectargetcheck.sh, parser version 133): inside an example group, the receiver-less builder
// `builder` — or the bare `is_expected`, which is `expect( subject )` — returns an instance of `cls`, whose `to`/`not_to`/
// `to_not` are RSpec's. ingest_binds.h rubyValueType types the value; graph.h RubyTypedReceivers answers a call on it.
// The matchers whose chain methods are RSpec's join them (parser version 136): `receive( :m ).with( 1 )`, the `to` of
// `change { }.from( 1 ).to( 2 )` — a call on a chain rooted at one is typed as the root (ingest_binds.h
// rubyMatcherChainType); a link's own class (Change's `from` returns a ChangeFromValue) is RSpec's all the same.
struct RspecTarget
{
    std::string_view builder;
    std::string_view cls;
};
inline constexpr RspecTarget kRspecTargets[] = {
    { "expect", "RSpec::Expectations::ValueExpectationTarget" },   // `expect { … }`: kRspecBlockTarget
    { "is_expected", "RSpec::Expectations::ValueExpectationTarget" },
    { "allow", "RSpec::Mocks::AllowanceTarget" },
    { "expect_any_instance_of", "RSpec::Mocks::AnyInstanceExpectationTarget" },
    { "allow_any_instance_of", "RSpec::Mocks::AnyInstanceAllowanceTarget" },
    { "receive", "RSpec::Mocks::Matchers::Receive" },
    { "have_received", "RSpec::Mocks::Matchers::HaveReceived" },
    { "receive_messages", "RSpec::Mocks::Matchers::ReceiveMessages" },
    { "receive_message_chain", "RSpec::Mocks::Matchers::ReceiveMessageChain" },
    { "change", "RSpec::Matchers::BuiltIn::Change" },
    { "raise_error", "RSpec::Matchers::BuiltIn::RaiseError" },
    { "raise_exception", "RSpec::Matchers::BuiltIn::RaiseError" },
    { "output", "RSpec::Matchers::BuiltIn::Output" },
    { "be_within", "RSpec::Matchers::BuiltIn::BeWithin" },
    { "yield_control", "RSpec::Matchers::BuiltIn::YieldControl" },
};
inline constexpr std::string_view kRspecBlockTarget = "RSpec::Expectations::BlockExpectationTarget";

// The RSpec target a receiver typed `cls` (leading `::` dropped) by the builder `via` is — `expect { … }`'s block form
// included — or nullptr: a class reached any other way (`ValueExpectationTarget.new`) is an ordinary constant.
inline const RspecTarget* rspecTargetOf( std::string_view cls, std::string_view via ) noexcept
{
    for( const RspecTarget& t : kRspecTargets )
    {
        if( t.builder == via )
        {
            return t.cls == cls || ( via == "expect" && cls == kRspecBlockTarget ) ? &t : nullptr;
        }
    }
    return nullptr;
}

// Ruby's delegation DSL: a class that writes one defines methods the tree indexes nowhere in it (ActiveSupport's `delegate`
// and `delegate_missing_to`, Forwardable's `def_delegator(s)`), so it may answer a name no lookup over the tree finds (graph.h
// RubySelfReach); one a `class << self` writes defines the class object's (ingest_ruby.h captureRubySingletonAccessors).
inline constexpr std::string_view kRubyDelegationCalls[] = { "def_delegator", "def_delegators", "delegate", "delegate_missing_to" };

// A Jbuilder template's `json` (test/rubyrakejbuildercheck.sh, parser version 135): the template handler binds it to the
// view's JbuilderTemplate, a BasicObject whose method_missing makes every call on it a key. ingest_ruby.h types the local
// in a `.jbuilder` file; graph.h RubyTypedReceivers refuses a call on it unless the tree opens the class.
inline constexpr std::string_view kJbuilderTemplate = "JbuilderTemplate";
inline constexpr std::string_view kJbuilderLocal    = "json";

// A physical dependency: one #include / import directive (file → target). The target is the raw
// include path / module name (resolved to a file id later, for the file→file dependency graph).
struct Include
{
    std::uint32_t fileId  = 0;      // the including file
    bool          isAngle = false;  // C/C++/ObjC: true ⇒ angle include `<x.h>` (external, unresolvable
                                    //   without a build system); false ⇒ quote include `"x.h"` (resolved
                                    //   relative-to-includer) OR a non-C import. Path-precise resolution
                                    //   (resolve.h::resolvePreciseInclude) uses this to leave angle
                                    //   includes UNRESOLVED rather than basename-matching them.
    bool          isLazy   = false; // TS/JS: true ⇒ this `require("./x")` / `import("./x")` call sits
                                    //   inside a FUNCTION BODY (kJsFunctionContainers), not at module load
                                    //   time — the dependency is real (--impact's importer tier must still
                                    //   name the file) but semantically WEAKER: it fires only if and when
                                    //   that function runs. Ruby (parser version 82): true for every `autoload`,
                                    //   which is lazy by definition (the file loads on the constant's first
                                    //   use); Ruby (parser version 83): true for a constant receiver inside a
                                    //   method/lambda/block, and (parser version 86) only when EVERY
                                    //   occurrence of that (file, open, name) is inside one; Ruby (parser
                                    //   version 93): a constant ARGUMENT follows the receiver rule, and a
                                    //   RESCUE class is lazy always — Ruby evaluates the exception list only
                                    //   while matching an exception. false for every other directive kind and
                                    //   for a top-level TS/JS require/import. See ingest.cpp::captureIncludes.
    bool          isSymbolic = false; // parser version 82: true ⇒ `target` names a language-level SYMBOL (a Ruby
                                    //   constant: superclass, include/extend/prepend argument, path-less
                                    //   `autoload :Name`), resolved through the corpus's OWN definition index
                                    //   (resolve.h::RubyConstantIndex) and NEVER probed as a path. Spelling
                                    //   cannot carry this bit: `require "Foo"` is legal Ruby and `Foo.rb` a
                                    //   legal file, and on a case-insensitive filesystem a path probe for a
                                    //   constant lands on the wrong file (test/rubyconstcheck.sh, decoy arm).
    std::uint32_t byte     = 0;     // parser version 82: the directive's start byte in its file. A symbolic target
                                    //   is resolved by Ruby's LEXICAL rule, and the lexical nesting at the
                                    //   site is recovered from this byte by span containment against the
                                    //   file's class/module symbols — the same containment that attributes a
                                    //   Reference to its enclosing def, so the two sides cannot disagree.
    bool          isValueUse = false; // parser version 93: true ⇒ the directive was read off a VALUE position — a
                                    //   constant ARGUMENT of a call/super/yield or a RESCUE class — rather than
                                    //   a receiver, a superclass, a mixin, a require or an autoload. It is a
                                    //   dependency of the file (--deps, --impact's importer tier, lazy pairs)
                                    //   but it is NOT import evidence for call narrowing: `notify(Dev::Config)`
                                    //   beside `record.update!` says nothing about what `record` is, and a
                                    //   narrow that read it as an include bound update! to Config#update!
                                    //   (19 of 20 sampled bindings wrong on discourse — PR #139 review).
                                    //   buildGraph's fileIncludes skips these; every other consumer keeps them.
    std::string   target;           // raw include path ("foo.h", <vector>), module name, or (isSymbolic)
                                    //   the constant AS WRITTEN (`Base`, `::App::User`, `ActiveRecord::Base`)
};

// A Ruby class/module OPEN (parser version 82): `class X < Y … end` / `module M … end`, one record per open, with
// the name AS WRITTEN (`Base`, `App::Audited`, `::Top`). The Symbol model deliberately keeps only the
// IMMEDIATE scope (`scope` — see ingest_sidecap.h), so a compact `class Api::V1::UsersController` cannot be
// rebuilt into its full constant from symbols; this table is the carrier for what resolve.h's
// RubyConstantIndex needs and nothing else: the open's byte span (nesting is recovered by containment, the
// same way a Reference finds its enclosing def), whether the open has a body of its own, and the written
// name. The fully-qualified constant is computed in resolve.h by Ruby's own lexical rule, where the whole
// corpus is visible — a compact `class A::B` inside `module X` names X::A::B if the tree defines X::A, else
// ::A::B — never here, where only one file is.
//   namespaceOnly: the body holds nested class/module opens and NOTHING else (comments aside) — `module App
//   … end` as every file under lib/app/ writes it. Such an open defines nothing of its constant and is not a
//   DEFINER in the index (it still nests). An EMPTY open (`class Base; end`) is a definer, not a wrapper. Measured on a 3532-file Rails app: 124 constants were "defined
//   in many files" by opens, 5 by bodies. A reopening WITH a body (a monkey patch) is a real second
//   definer, and a reference then edges to every definer (test/rubyconstcheck.sh).
// Ruby-only this round; the shape (span + written name + own-body bit) fits any language whose namespaces
// reopen across files. Serialized in the cache (ingest_cache.h, kCacheVersion 17).
struct ConstOpen
{
    std::uint32_t fileId        = 0;
    std::uint32_t startByte     = 0;      // span of the class/module node
    std::uint32_t endByte       = 0;
    bool          namespaceOnly = false;
    std::string   written;                // the name as written: `Base`, `App::Audited`, `::Top`
};

// P2-D Rule 2 LOCAL-VARIABLE TYPE BINDING (`var : typeName`) captured at ingest. One record per
// `Foo x;` / `Foo* x;` / `auto x = Foo()` / `x = Foo()` (C++) or `x = Foo()` (Python) inside a function
// body — the variable→type fact that lets resolve.h narrow a later `x.m()` / `x->m()` to `typeName::m`.
// Attributed to its enclosing definition (the function the binding lives in) by byte-span containment,
// exactly like a Reference, so the scope of a binding is the same scope a call's recvVar is looked up in.
// CONSERVATIVE: only an UNAMBIGUOUS binding narrows — buildGraph drops `(fromSymbol, var)` if the same var
// is bound to two DIFFERENT types in one scope (a reassignment to another type), so a wrong narrow is
// impossible. typeName is the WRITTEN type's final segment (`A::Foo` → `Foo`), matched against class names.
//
// L3 var→FUNCTION extension (fn-pointer/callback bindings): the SAME record shape also carries
// `var = &foo` / `H h = someFunc` / `cb = <lambda>` facts, discriminated by `kind`, so a later call-shaped
// `fn()` can resolve to the bound function. Rule 2's exact capture discipline and tombstone semantics apply:
// a var assigned two DIFFERENT functions in one scope resolves to NOTHING (buildGraph tombstones it), and a
// var with ANY fn binding never falls back to the bare-name ladder (the binding proves the call goes through
// the variable, so a same-named global function would be a FALSE edge). Two sentinels ride typeName:
//   kFnBindLambdaTarget  — the RHS was a lambda: the binding EXISTS (blocks the name ladder, participates in
//                          tombstoning) but resolves to nothing extra — the lambda body is already attributed
//                          to the enclosing function.
//   kFnBindClobberTarget — an assignment whose RHS is NOT a recognizable single function (`fn = getHandler()`,
//                          `fn = nullptr`): forces the tombstone, so a stale earlier binding can never win.
enum class LocalBindKind : std::uint8_t
{
    Type,      // P2-D Rule 2: `var : typeName` (receiver-var narrowing fuel)
    FnDecl,    // L3: a DECLARATION binding `void (*fn)() = &foo;` / `H h = foo;` / `auto cb = [](){...};`
    FnAssign,  // L3: an ASSIGNMENT binding `fn = &foo;` (may target a FILE-scope var, so it also clobbers
               //     a same-named file-scope entry with a different target — see buildGraph's pass 2)
    VarDecl,   // r9 shadow suppression: a DECLARED variable NAME whose type Rule 2 could not (or need not)
               //     resolve (`int run = 0;`, a parameter, a range-for var) — typeName stays EMPTY. Evidence
               //     for suppressShadowedReferences below, NOTHING else: buildGraph's Rule-2 tables skip it
               //     (kind != Type) and the L3 fn tables skip it (typeName empty). APPENDED so no persisted
               //     kind value renumbers (RawBind rides kind through the cache as a u8).
    ParamType, // member-variable round (card A3): a C++/ObjC function DEFINITION parameter's WRITTEN type
               //     (`void f( Counter& c )` → c:Counter) — also a lambda parameter's, a typed range-for
               //     variable's and a reference local's — so `c.count` resolves to Counter.count in the field
               //     use-site index (graph.h collectFieldUseSites). Rule 2's call narrowing reads it too, but
               //     LEXICALLY (resolve.h buildScopedRecvDecls, 2026-09-16): every one of these shapes is scoped
               //     narrower than the whole function or can be redeclared inside it, so the flat per-function
               //     varType table would leak the type to other declarations of the name. The L3 fn tables skip
               //     it by kind; shadow suppression already holds the declaration's VarDecl record. importedName
               //     holds the written type WHOLE when it is qualified (`std::map<K, V>`), else "" — the same on a
               //     declaration's Type record — so the lexical lookup can refuse a name that is only a final segment.
               //     APPENDED for the same cache reason as VarDecl.
    Import,    // Phase 5 (docs/EVALS.md "Phase 5", kParserVer 77): a FILE-SCOPE import binding — `var` is the
               //     name the import binds in the module namespace, `typeName` the module target as written
               //     (`import numpy as np` → np:numpy; `import a.b` → a:a.b; `from m import x as y` → y:m;
               //     `from . import x` → x:.). fromSymbol is kNoNode (a module-level statement), spans {0,0}.
               //     Consumed by graph.h buildImportBindTable ONLY: the external-name veto reads whether the
               //     bound name's module is inside the indexed tree. Rule 2 (kind == Type), the L3 fn tables
               //     and shadow suppression all skip it by kind. Python captures these; a `from m import *`
               //     records nothing (no name is bound). APPENDED for the same cache reason as VarDecl.
               //     issue #287 (kParserVer 115): `importedName` carries one more bit for Python — "module"
               //     iff `var` names the MODULE itself (`import a.b`/`import a.b as c`), empty for `from m
               //     import x [as y]` (`var` names a MEMBER of m, not m). The module-alias receiver narrow
               //     (graph.h buildGraph) reads this to refuse `x.attr()` when `x` was bound the second way
               //     — `x` there is a value from inside m, and `.attr` is not a lookup in m's own namespace.
               //     ind4b fix 5: `from m import x as y` with y != x records "from:x" (kPythonFromMemberMark + x) — the
               //     member's ORIGINAL name, which `var` (the local alias) loses; a plain `from m import x` stays empty.
    JsImport,  // named ES import: var=local name, typeName=module, importedName=export (empty for type-only).
    JsExport,  // ES export: var=EXPORTED name; importedName=the LOCAL name it binds (empty on the declaration
               //     form, where the two are the same word). spanStart/spanEnd is the region a definition must
               //     sit inside to BE this export — the declaration itself for `export function f(){}`, the
               //     whole program for a `export { f as g }` clause, whose target may be declared anywhere in
               //     the file. Re-export (`export { f } from ...`) and default exports record nothing: see
               //     ingest_jsimports.h for why an absent name must degrade rather than refuse.
    JsShadow,  // lexical declaration hiding an ES import; spanStart/spanEnd cover the declaring scope.
    ElixirCallable, // var=name/arity, typeName=module, importedName=definition keyword; span is the declaration.
    ElixirDefault,  // var=callable name/arity, importedName=full name/arity, typeName=module; no synthetic symbol.
    ElixirImport,   // typeName=module, var=all/only/except/functions/macros; importedName=newline-delimited name/arities.
                   // spanStart/spanEnd delimit lexical visibility, starting after the directive.
    ModuleAlias,   // FE-A (test/falseedgecheck.sh): a FILE-SCOPE name bound to a module, a module member or a member of a
                   //     global object outside ES named-import syntax. var = the local name; typeName = the module as written
                   //     (`import * as qs from 'qs'`, `const qs = require( 'qs' )`, `const { parse } = require( 'cookie' )`,
                   //     Go `import c "x/y"`) — or, when isFromAssignment, the IDENTIFIER the name was destructured from
                   //     (`const { stringify } = JSON`); importedName = the member it names, "*" for the whole module. Go:
                   //     var "." is a dot import. fromSymbol kNoNode, spans {0,0}. Read only by graph.h FalseEdgeRules;
                   //     every other binding consumer filters by kind or skips file-scope records. APPENDED (cache u8).
    RubyFactory,    // parser version 132: a FactoryBot `factory :name` definition — var=the factory name (or one of its
                   //     `aliases:`), typeName=the final segment of the class it builds (ingest_ruby.h captureRubyFactories).
                   //     Read by graph.h rubyFactoryClasses ONLY; every other reader skips it by kind or finds no
                   //     variable of that name. APPENDED for the same cache reason as VarDecl.
    RubyHelperMethod, // parser version 135: a `helper_method :name` declaration at class-body position — var=the method,
                   //     typeName=the final segment of the class or module that declares it (ingest_ruby.h
                   //     rubyNoteHelperMethods). Read by graph.h RubyTopSelf ONLY. APPENDED, as above.
    RubySingletonDef, // parser version 137: a Ruby SINGLETON method — `def self.m`, a def or an accessor inside `class << self`
                   //     — at startByte, the def's own start (Symbol::sigStartByte); var=the method, typeName empty
                   //     (ingest_ruby.h rubyNoteClassSideDef, captureRubySingletonAccessors). A name the delegation DSL
                   //     defines in a `class << self` has no def: typeName=the owning class, var=the name (empty for
                   //     `delegate_missing_to`, every name). Read by graph.h's class-object lookup ONLY
                   //     (rubyClassObjectDefs). APPENDED, as above. Parser version 145: a def that is a class method of
                   //     each class INCLUDING its module rather than one of the module carries importedName
                   //     kRubyIncluderMark — a singleton def inside a concern's `included do … end`, which defines it on
                   //     the includer itself — or kRubyClassMethodsMark — a def inside its `class_methods do … end`, which
                   //     ActiveSupport::Concern extends onto the includer (ingest_ruby.h rubyDefSide).
    RubyClassMixin, // parser version 145: a mixin the CLASS OBJECT's lookup reaches rather than its instances' — the constant
                   //     of an `extend M`, or of an `include`/`prepend` inside `class << self` — at startByte, the
                   //     constant's own start, where the mixin reader puts its inherit reference (ingest_ruby.h emitCapturedRubyMixinBase since 173, captureRubyMixinBases before it);
                   //     var and typeName empty; importedName=kRubyIncluderMark when the directive sits in a concern's
                   //     `included do … end`, which extends the includer, not the concern. A module body's `extend self`
                   //     has no constant: var="self", at the directive's own start byte (ingest_ruby.h
                   //     captureRubyClassMixins). Read by graph.h's class-object lookup ONLY (rubyFqnAncestry). APPENDED,
                   //     as above.
    // FE-B (test/receiverevidencecheck.sh): the receiver-evidence facts graph.h ReceiverEvidence reads, and NOTHING else.
    //   Every other binding consumer filters by kind or skips these five by isReceiverEvidenceKind below — a field name
    //   recorded here is not a local of the method that assigns it, and a type written on a parameter is not a class the
    //   file "names" for the builtin-method gate. APPENDED (cache u8).
    RecvType,      // a parameter or local whose class the source states: var = the name, typeName = the class's final
                   //     segment, importedName = the written type whole. A TS/Python/Go parameter's annotation, a JS
                   //     `const x = new Foo()`, a Go `var x T` / `x := T{…}` / `x := &T{…}`, and a Go METHOD RECEIVER — the
                   //     receiver's record sets isFromAssignment (the method's own class, which Go spells nowhere else), and
                   //     so does a JS `Foo.prototype.m = function …` (var "", typeName Foo): that member's class.
    MemberType,    // a field whose class the source states: var = the field, typeName = the class's final segment.
                   //     fromSymbol is the def that states it — a Python method's `self.x = Foo()`, a JS/TS method's
                   //     `this.x = new Foo()`, a Go struct's `x T` — and the owning class is that def's class. A Go
                   //     EMBEDDED field (`struct { u.Chars }`) sets isFromAssignment: its methods are promoted.
    MethodAlias,   // a local bound to an object's method: var = the local, typeName = the object's variable,
                   //     importedName = the method (Python `feed = parser.feed`).
    NameAlias,     // a file's local spelling of an imported class: var = the local name, typeName = the name it imports
                   //     (Python `from m import Stylesheet as Sheet`; JS/TS read their JsImport records instead).
    StaticMember,  // a JS/TS class member declared `static`: var = the member's name, typeName "static", recorded INSIDE its
                   //     body so it attributes to the member. A call on the CLASS reaches only these, a call on an INSTANCE
                   //     only the others (the two sides of the lookup; #373's Ruby class-object rule, here for JS/TS).
    RubyMainMixin, // parser version 174 (lane ruby-pair): a Ruby file's TOP-LEVEL `include M` / `extend M` / `self.extend M` —
                   //     self there is the main object, which then answers M's methods (rake's `self.extend Rake::DSL`). One
                   //     record per constant, at the constant's own start: typeName = the constant as written, importedName =
                   //     the directive ("include" / "extend"), spanStart = the constant's 1-based line; var stays EMPTY and the
                   //     record is file-scope, so no local-name table reads it. Read by graph.h rubyMainObjectMixins ONLY
                   //     (--lego's `<impl t="object" n="main">` row). APPENDED (cache u8).
    // Train 29 lane call-result-typing (test/receiverevidencecheck.sh (L)): a binding initialised by a CALL takes the callee's
    // DECLARED return type. Both kinds are receiver evidence (isReceiverEvidenceKind): graph.h's resolve loop alone reads them.
    CallResult,    // a local bound to a call's result (Go `x := f()` / `a, b := f()`, Rust `let x = f()?` / `let (a, _) = f()?`):
                   //     var = the bound name, typeName = the callee's final name, startByte = the CALL's start byte (the call
                   //     Reference's own; with typeName it names one call), spanStart/spanEnd = where the name is visible (the same span as the name's RecvType
                   //     tombstone, which the typed fact replaces), resultIndex = the position it binds (kWholeResult: the whole
                   //     value), unwrapDepth = the unwrap operators applied before binding (Rust `?` / `.unwrap()` / `.expect()`).
                   //     Rust: importedName = the qualifier a path call is written with (`crate::m::T`, `fs::File`, `Self`), else "".
    ReturnType,    // one DECLARED result of a function definition, at startByte = the def's own start (Symbol::sigStartByte):
                   //     resultIndex = its position (kWholeResult: a single non-tuple result), typeName = the class it names
                   //     after the language's transparent wrappers (Go `*T`, Rust `Box<T>` / `&T`), importedName = the type
                   //     written WHOLE when it is qualified (`os.File`, `std::fs::File`), else "", unwrapDepth = the
                   //     Result/Option layers above it (each needs one unwrap operator at the call site). var stays empty.
                   //     C++ writes importedName only for a non-std qualified result (`ext::Config`), which graph.h resolves.
                   //     Rust sets isFromAssignment when the result is written `Self` (typeName = the impl's type).
    TypeImport,    // fix round 1: a file's import of a TYPE name (Java/Kotlin `import a.b.C [as D]`, Rust `use a::b::C [as D]`,
                   //     brace groups flattened): var = the local name it binds (`C` / `D`; "*" for a wildcard or glob),
                   //     typeName = the imported item's own name ("" for "*"), importedName = the path as written
                   //     (`java.io.File`, `std::fs::File`, `crate::model` for a glob). Read by graph.h's call-result type
                   //     resolution (receiverevidence.h ReceiverEvidence::resultClassOf) ONLY. APPENDED (cache u8).
                   //     C++ (fix round 2): a using-declaration `using a::C;` (var `C`) and a using-directive `using namespace
                   //     a;` (var "*", importedName `a`), with spanStart/spanEnd = the scope it is declared in (a namespace
                   //     body, a function body (fix round 4: a local class's member result sits inside it), or the whole
                   //     file: 0 .. 0xFFFFFFFF) — the span marks a C++ row: Java/Kotlin/Rust rows carry none ({0,0}). A
                   //     class-scope using records nothing. Java (fix round 4): a single-static-import `import static a.B.N;`
                   //     (var `N`: it imports every static member named N, a member TYPE included) and a static-import-on-
                   //     demand (var "*", importedName `a.B`).
    Namespace,     // fix round 2: a lexical scope the index has no symbol for — a C++ `namespace` (not `inline`), a TS
                   //     `namespace` / `module` — var = its name as written (`a::b`, `a.b`; "" when anonymous), spanStart/
                   //     spanEnd = its body. Read by graph.h's call-result type resolution ONLY: a class nested in one is
                   //     not in scope outside it, and a C++ class is visible from the namespaces its own encloses. A Java /
                   //     Kotlin file's `package a.b` is one with NO span ({0,0}: it scopes nothing lexically) — the packages
                   //     the tree declares, whatever directory holds them (an import of another one is from outside). APPENDED.
    TypeAlias,     // fix round 3: a declaration that binds a TYPE NAME to another type — C++ `using A = T;` / `typedef T A;` /
                   //     `namespace a = b;`, Rust `type A = T;`, Kotlin `typealias A = T`, TS `type A = T` / `import A = n.T`:
                   //     var = the name bound, importedName = the target as written (blanks removed), startByte = the
                   //     declaration's start. C++ rows carry the scope they are declared in as spanStart/spanEnd (a
                   //     namespace or class body, or the whole file: 0 .. 0xFFFFFFFF) like a using row; the other families'
                   //     rows carry none ({0,0}): their scope is the innermost one holding startByte. Read by graph.h's
                   //     call-result type resolution ONLY: an alias of the spelling in force at a callee is a binding the
                   //     result type is never resolved past (an outside target names nothing; an in-tree one is a floor). APPENDED.
                   //     Fix round 4: typeName marks the rows that bind a spelling WITHOUT an alias target (kTypeBind* constants):
                   //     "forward" a C++ bodiless `struct S;` / `class S;` / `union S;`, "shadow" a type declaration the index
                   //     keeps no class symbol for (a Java `record` / `@interface`, a C++ union defined outside a declaration),
                   //     "unparsed" a region the parser cannot read as declarations, which may declare ANY name (var "!": a
                   //     C++ macro invocation or parse error where a declaration must stand, with its scope's span; a Rust
                   //     block enclosing a nested fn that holds a statement- or item-position macro, at the block's start).
                   //     Fix round 5: "unrecorded" a C++ class declaration only a macro can have written, which tree-sitter-cpp
                   //     reads as a function or a variable (`class API S {…}`, `struct API S;`): one row per identifier its head
                   //     spells (S among them), no span — a class of that name the index does not record exists in the tree.
    // Lane h1-annot (test/receiverevidencecheck.sh (Q)): a Python augmented assignment REBINDS its name to whatever the in-place
    // operator returns. Both kinds are receiver evidence (isReceiverEvidenceKind): graph.h ReceiverEvidence alone reads them.
    AugAssign,     // a Python `x op= v` on a bare name: var = the name, typeName = the in-place method the operator calls (`+=`
                   //     → `__iadd__`; ingest_binds.h kPythonInPlaceMethods), importedName = the binary method Python falls back
                   //     to when the class defines no in-place one (`__add__`), no span (a Python name is function-wide).
                   //     ReceiverEvidence keeps the class C `x` held only when the method Python calls — C's in-place method
                   //     (its own, else the shallowest base's: ONE definition), else its binary one — carries an
                   //     OperatorResult record naming "self" or C; otherwise `x` gets a tombstone, as a plain reassignment
                   //     does. APPENDED (cache u8).
    OperatorResult, // a Python operator method an augmented assignment can call (`__iadd__` … `__ior__`, `__add__` … `__or__`)
                   //     whose result is provably its receiver's class: var = the method's name, startByte = its body's start
                   //     (the record attributes to the method), typeName = "self" (every `return` returns the first
                   //     parameter bare — at least one, no `yield`, nested defs / lambdas / classes not read — or the return
                   //     annotation is `Self`) or the method's own class name (the return annotation names it: `-> Color`,
                   //     `-> "Color"`). A method that proves neither records nothing. APPENDED.
    DispatchType,  // lane L6 (interface-typed dispatch): a Rust parameter, local or struct field typed only as SOME implementor of a
                   //     trait — `&dyn T`, `Box<dyn T>`, `impl T` / `&impl T`, or a type parameter `G` bounded by T (`G: T` inline
                   //     or in a `where` clause) — never as T itself. var = the name (a field: the field), typeName = the trait's
                   //     final segment, importedName = the trait as written when qualified (`crate::render::Renderer`), else "",
                   //     and for a generic bound `G: <the trait as written>` (the bound= text a row carries); isFromAssignment =
                   //     a struct FIELD (fromSymbol the struct), else a parameter or local (spanStart/spanEnd where it is
                   //     visible, as a RecvType). It stands in for the binding's tombstone: the name hides an outer binding and
                   //     types no class. Read by receiverevidence.h (ReceiverEvidence::noteDispatchWritten) ONLY. APPENDED.
    ImplBlock,     // lane L6 fix round 1 (candidate-set completeness): a block that implements the type named `var` (its final segment).
                   //     typeName = the implementing type's name — a Rust `impl T for X` block (typeName "X", spanStart/spanEnd = the
                   //     whole impl item, so a method inside it is one of X's T methods, never an inherent one) — or "" for an
                   //     implementor no class the index keeps names: a Java anonymous class `new T() { … }`, a Kotlin object
                   //     expression `object : T { … }` or `fun interface T` (a lambda), a Rust trait under a mock attribute
                   //     (`#[automock]` writes MockT). Read by graph.h's implementors-map pass (an unnamed one opens T's list) and
                   //     ifacedispatch.h ONLY. APPENDED.
    // FC3 (T1 class 14 ALIAS-THROUGH-ASSIGNMENT): a JS/TS binding WRITTEN after its declaration — `Eng = Foo`, `[Eng] = [Foo]`,
    // `({ Eng } = { Eng: Foo })`, `Eng += …`, `Eng++`, `for ( Eng of xs )`, a second `var Eng = Foo`, but not a write whose
    // value keeps the name (`equal = util.equal`) — so a BARE call or construction by that name in its scope is undecided
    // (ingest_jsimports.h captureJsRebindFacts). var = the name; spanStart/spanEnd = the WHOLE scope of the declaration the
    // write resolves to (the program, for a name the file never declares): byte order is not run order, a closure or a loop
    // sees the write anywhere in it; startByte = the file's END, so the record has no owner (fromSymbol kNoNode) and no
    // (fromSymbol, var) local-name reader takes it for a function's local. An ES import or `const` binding records nothing:
    // writing one throws. Read by graph.h buildGraph (a bare call is unresolved, no edge; a member call is hedged by name) and FalseEdgeRules (as a shadow: no
    // external veto) ONLY. isFromAssignment = the declaration already BOUND a value (an initializer, a parameter, a `class` /
    // `function` / import / `for` head — not `var x;` / `let x;` / an undeclared name): a MEMBER call through the name
    // (`tank.spill()` after `let tank = new Tank(); tank = b`) has no receiver evidence at all then and goes to the by-name hedge
    // (via=name); over a `var x;` / `let x;` / undeclared name only the root's SPELLING stops deciding (`Eng = Foo; Eng.make()` is
    // not the class `Eng`) while a stated type (`let app; … app = new Hono(); app.request()`) keeps its receiver reading. APPENDED (cache u8).
    JsRebind,
    // Lane js-def-naming (QN-OBJLIT-NAMED): a JS/TS MODULE-SCOPE object literal bound to a name — `const Widget = { run() {} }`,
    // `export const Widget = { … }`, `var Widget = { … }`. var = the binding name; spanStart/spanEnd = the object literal, so a
    // member inside it is that literal's (the index stores no owner for it: langfacts.h objectLiteralMembers). fromSymbol kNoNode
    // (a module-level statement). Read by graph.h resolveAllByWrittenSpelling ONLY: a spelling whose owner segment is the
    // literal's name (`Widget.run`) could name that member, so beside a class of that name it is unknown, never the class alone.
    // APPENDED (cache u8).
    JsObjectLiteral,
    // Lane alias-import (ALIAS-IMPORT): a JS/TS RE-EXPORT clause — `export { a } from './m'`, `export { a as b } from './m'`,
    // `export * from './m'` (and the `export type` spellings). var = the EXPORTED name ("*" for a star re-export), typeName = the
    // module specifier as written (quotes stripped), importedName = the name it takes from that module ("*" for a star).
    // `export * as ns from` records nothing (it binds a namespace, not a name). fromSymbol kNoNode, spans {0,0}, sited at the
    // statement. Written by ingest_importcap.h emitCapturedImportBind (the binds channel's Web arm) and read by forreexport.h
    // ONLY (the --for re-export hop rows): it is never a call edge and no resolver table reads it (every other binding reader
    // filters by kind). APPENDED (cache u8).
    ReExport,
};
// fix round 4: the TypeAlias rows that bind a spelling with no alias target (model.h LocalBindKind::TypeAlias, typeName)
inline constexpr std::string_view kTypeBindForward  = "forward";
inline constexpr std::string_view kTypeBindShadow   = "shadow";
inline constexpr std::string_view kTypeBindUnparsed = "unparsed";
inline constexpr std::string_view kTypeBindUnrecorded = "unrecorded";
// The number of LocalBindKind enumerators — the bound readBind validates a cached kind byte against (see kSymKindCount).
inline constexpr std::size_t kLocalBindKindCount = static_cast<std::size_t>( LocalBindKind::ReExport ) + 1;
// FE-B: the kinds only graph.h ReceiverEvidence (and, for the two call-result kinds, its resolve loop) reads (see RecvType above).
// L6's ImplBlock is in the set for the same reason: its var is the TRAIT / interface being implemented, never a name bound in the
// enclosing function, so the generic binding readers (localNameSet, the fn-pointer tables, nonlocalstate) must skip it (its two
// readers, graph.h's implementors-map pass and ifacedispatch.h, filter by kind).
inline bool isReceiverEvidenceKind( LocalBindKind k ) noexcept
{
    // FE-B's five are appended in one run (RecvType .. StaticMember); the call-result five (CallResult .. TypeAlias) after
    // RubyMainMixin, h1-annot's two (AugAssign, OperatorResult) right after them, and L6's DispatchType and ImplBlock after
    // those: one run CallResult .. ImplBlock
    static_assert( std::uint8_t( LocalBindKind::StaticMember ) - std::uint8_t( LocalBindKind::RecvType ) == 4, "FE-B's five receiver-evidence kinds stay one run" );
    static_assert( std::uint8_t( LocalBindKind::ImplBlock ) - std::uint8_t( LocalBindKind::CallResult ) == 8, "the call-result, in-place, dispatch and impl-block kinds stay one run" );
    return ( k >= LocalBindKind::RecvType && k <= LocalBindKind::StaticMember ) || ( k >= LocalBindKind::CallResult && k <= LocalBindKind::ImplBlock );
}
// The language family whose call results take a callee's declared result type (train 29 call-result typing), ONE row read
// by ingest (which records CallResult / ReturnType / TypeImport) and by graph.h (where the type resolves, and which
// receiver tables the typed local lands in). None: the language records nothing (JavaScript, Python, …).
enum class CallResultFamily : std::uint8_t { None, Go, Rust, Cpp, Jvm, TypeScript };
inline CallResultFamily callResultFamilyOf( Lang l ) noexcept
{
    switch( l )
    {
        case Lang::Go:                     return CallResultFamily::Go;
        case Lang::Rust:                   return CallResultFamily::Rust;
        // C++ / ObjC OFF (owner 2026-10-17, fix round 6): a macro the parser reads as code (an export macro in a class head, an
        // `#if` around a declaration, a namespace-opening macro, …) can declare the result's name unseen, so no C++ call result
        // is typed yet — base behaviour. CallResultFamily::Cpp's readers (Rule 2's varType / scopedRecvDecls are its sink) stay
        // for the macro-aware C++ card; mapping this row back to Cpp turns them on.
        case Lang::Cpp: case Lang::ObjC:   return CallResultFamily::None;
        case Lang::Java: case Lang::Kotlin: return CallResultFamily::Jvm;
        case Lang::TypeScript:             return CallResultFamily::TypeScript;
        default:                           return CallResultFamily::None;
    }
}
// The WRAPPER rows a family's written type is read through (lane rust-receivers; the call-result reader shares them) — data,
// one row per wrapper name, matched on the wrapper's last path segment (`std::rc::Rc` is `Rc`):
//   Transparent: auto-deref reaches the argument's members — the class is the argument (`Box<T>`; `&T` / `&mut T` are the
//                grammar's reference_type, read without a row).
//   Layer:       the value is not a T until one unwrap operator (`?`, `.unwrap()`, `.expect( … )`) is applied (Result, Option):
//                a call result counts it into unwrapDepth; a WRITTEN local, parameter or field of that type names no class.
//   Hides:       a shared pointer or a cell whose OWN members a call written on it may reach — Rc / Arc (`clone`, `as_ref`,
//                `borrow`, …), RefCell / Cell / Mutex / RwLock (`borrow`, `get`, `lock`, …): its argument is not read at all.
// A generic type no row names (`Vec<T>`, `HashMap<K, V>`, an in-tree `Stack<T>`) is its own head class, resolved like any name.
enum class TypeWrap : std::uint8_t { None, Transparent, Layer, Hides };
struct TypeWrapperRow
{
    std::string_view name;
    TypeWrap         wrap;
};
inline constexpr std::array<TypeWrapperRow, 9> kRustTypeWrappers = { {
    { "Box", TypeWrap::Transparent }, { "Result", TypeWrap::Layer }, { "Option", TypeWrap::Layer },
    { "Rc", TypeWrap::Hides }, { "Arc", TypeWrap::Hides }, { "RefCell", TypeWrap::Hides }, { "Cell", TypeWrap::Hides },
    { "Mutex", TypeWrap::Hides }, { "RwLock", TypeWrap::Hides },
} };
// each family's wrapper rows, indexed by CallResultFamily (Go / C++ / JVM / TS read their wrappers in their own readers
// today, ingest_binds.h: empty rows)
inline constexpr std::array<std::span<const TypeWrapperRow>, std::size_t( CallResultFamily::TypeScript ) + 1> kTypeWrappersOf = { {
    /* None */ {}, /* Go */ {}, /* Rust */ kRustTypeWrappers, /* Cpp */ {}, /* Jvm */ {}, /* TypeScript */ {},
} };
static_assert( enumCountIsExact<CallResultFamily, kTypeWrappersOf.size()>(), "kTypeWrappersOf must have one row per CallResultFamily — add the row with the append" );
// the row `name` has in family `f`'s wrapper table (None: no row — the name is a class of its own)
inline TypeWrap typeWrapOf( CallResultFamily f, std::string_view name ) noexcept
{
    const std::span<const TypeWrapperRow> rows = kTypeWrappersOf[ std::size_t( f ) ];
    const auto                            row  = std::ranges::find( rows, name, &TypeWrapperRow::name );
    return row == rows.end() ? TypeWrap::None : row->wrap;
}
// Binding::resultIndex of a record about a WHOLE result (a single non-tuple result; a Rust `let t = pair()?` binding all of it).
inline constexpr std::uint8_t kWholeResult = 0xFF;
// lane iface-peel (LangFacts::returnTypedDispatchLet): a ReturnType whose unwrapDepth carries this bit names a TRAIT the result
// dispatches through (Rust `-> &dyn T` / `-> Box<dyn T>` / `-> impl T`), never a class: typeName = the trait, importedName = its
// path when qualified. No call-result reader that compares depths can match it by accident (a call's own depth never has the
// bit); graph.h typeCallResults alone reads it, and types the local as SOME implementor of the trait (ReceiverEvidence::LocalFact
// iface). The low bits stay the Result/Option layers (always 0 today: a layered trait object is not read).
inline constexpr std::uint8_t kDispatchResultBit = 0x80;
// lane iface-peel fix 1 (B1): the memberVia of a C++ MEMBER record (isCompose, a field name) whose written type is a TEMPLATE
// PARAMETER of an enclosing `template <…>` (`template <class Handle> class S { Handle h_; }`): the name is the parameter, never
// the smart-pointer alias of that spelling in some namespace. resolve.h SmartAliasPeel::pointeeOf alone reads it, to keep the
// member's base reading; every other reader of a compose record ignores memberVia (a C++ member record carries none otherwise).
inline constexpr std::string_view kTemplateParamMemberType = "<tparam>";
// train 42b CR harvest: the memberVia of a C++ MEMBER record declared as a POINTER to a non-smart written type (`FilterSharedPtr* p_;`):
// `p_->` reaches the alias's smart pointer, never the pointee. resolve.h SmartAliasPeel::pointeeOf alone reads it (base reading kept).
inline constexpr std::string_view kPointerMemberType = "<ptr>";
// lane iface-peel fix 1 (B1): the LEXICAL SCOPE of a C++ declaration, written on its record's memberRoot (a compose record's only
// use of that field): the enclosing namespaces and classes, outermost first, joined by "::" — a class element is prefixed "#"
// (`Envoy::Network::#ConnectionImpl`), an anonymous namespace is kAnonScopeElement, an inline namespace is transparent (left
// out). kLocalScope is a declaration inside a function body (its scope is a block this index does not model). Written by
// ingest_relations.h cppScopePath on an alias record and on a member record (the member's class last); read by resolve.h
// SmartAliasPeel alone. The C++ call-result bindings are OFF (callResultFamilyOf), so no Namespace record exists to read.
inline constexpr std::string_view kAnonScopeElement = "(anon)";
inline constexpr std::string_view kLocalScope       = "(local)";
// The importedName of a Ruby class-object binding that acts on each class INCLUDING the module, not on the module
// (LocalBindKind::RubySingletonDef, RubyClassMixin; parser version 145): written in a concern's `included do`, or a def
// in its `class_methods do`.
inline constexpr std::string_view kRubyIncluderMark     = "included";
inline constexpr std::string_view kPythonFromMemberMark  = "from:";   // Python Import importedName prefix: `from m import x as y` records "from:x" (never equals "module")
inline constexpr std::string_view kRubyClassMethodsMark = "class_methods";
static_assert( enumCountIsExact<LocalBindKind, kLocalBindKindCount>(), "kLocalBindKindCount must name the LAST LocalBindKind enumerator — move it with the append" );

inline constexpr const char* kFnBindLambdaTarget  = "(lambda)";    // parens are illegal in identifiers, so
inline constexpr const char* kFnBindClobberTarget = "(unknown)";   //   neither sentinel can match a real def

// One main-object implementor row (Graph::rubyMainMixins, ordered by base, then by site): the module the top level mixes in,
// and the directive's site.
struct RubyMainMixinRow
{
    NodeId        base   = kNoNode;
    std::uint32_t fileId = 0;
    std::uint32_t line   = 0;   // the constant's 1-based line
};

// PY-ALIAS-SPLIT-MARKER: a Python def or class statement at MODULE scope that sits inside a compound statement (`if`, `try`,
// `with`, `for`, `while`, `match`: it may not run) files, besides its ordinary VarDecl, a second VarDecl spelled with this prefix
// (`?f`). No identifier starts with it, so no name lookup ever matches the record; graph.h pythonRenamedImportPin reads it as "f may
// be unbound", the case where a module `__getattr__` (PEP 562, consulted only for names the module lacks) answers instead.
inline constexpr std::string_view kPythonCondDefPrefix = "?";
// A Python lambda parameter or comprehension target `K` files a VarDecl spelled `~K` at the lambda / comprehension (its enclosing def's
// scope, else module scope). No identifier starts with it, so no name lookup ever matches the record; src/regindex.h reads it as "K is
// another variable here" (a registrar key named like a lambda parameter is not the key).
inline constexpr std::string_view kPythonLocalScopePrefix = "~";

struct Binding
{
    NodeId        fromSymbol = kNoNode;   // enclosing function/method (the binding's scope); kNoNode if file-scope
    std::uint32_t fileId     = 0;
    LocalBindKind kind       = LocalBindKind::Type;
    bool          isFromAssignment = false;   // kind==ModuleAlias: typeName is an IDENTIFIER, not a module (`const { a } = JSON`).
                                              // kind==Type: read off a C++ ASSIGNMENT's callee (`x = f( … )`), not a declaration —
                                              //   a function's name as often as a class's, so buildGraph drops it unless a class of
                                              //   that name exists (resolve.h assignmentNamesNoClass). Rides the padding after `kind`.
                                              // kind==ReturnType (Rust): the result is written `Self` (LocalBindKind::ReturnType).
    std::uint8_t  resultIndex = kWholeResult; // kind==CallResult/ReturnType: the result position (see LocalBindKind). Rides the padding.
    std::uint8_t  unwrapDepth = 0;            // kind==CallResult/ReturnType: unwrap operators / layers (see LocalBindKind). Rides the padding.
    std::uint32_t startByte  = 0;         // the record's own position (RawBind::startByte). ONE declaration's
                                          //   VarDecl and its typed record (Type or ParamType) carry the SAME
                                          //   value — that shared byte is how Rule 2's lexical receiver lookup
                                          //   (buildScopedRecvDecls) knows a scope and a written type belong to
                                          //   one declaration. Rides the padding after `kind`: no size change.
    std::uint32_t spanStart  = 0;         // VarDecl: the byte span the name shadows within — a block
    std::uint32_t spanEnd    = 0;         //   declaration runs from its DECLARATION POINT (end of the complete
                                          //   declarator, [basic.scope.pdecl]) to the block's end; a whole-scope
                                          //   shape (parameters, captures, range-for and control-statement header
                                          //   declarations) from its scope's start. See suppressShadowedReferences.
                                          //   ES/Elixir bindings also use spans as documented in LocalBindKind.
                                          //   {0,0} on a scope-less shadow capture (contains nothing).
    std::string   var;                    // the declared variable identifier (`x`)
    std::string   importedName;           // JsImport: the requested export name; never a global-name fallback.
                                          //   Type/ParamType: the written type WHOLE when it is qualified, else "".
                                          //   JsExport: the LOCAL name the exported spelling binds (empty when
                                          //   the two are identical). Elixir: see LocalBindKind's field contracts.
    std::string   typeName;               // kind==Type: the written type's final segment (`Foo`), resolved to a
                                          //   class in buildGraph. kind==FnDecl/FnAssign: the bound FUNCTION
                                          //   name as written minus `&` (`alpha`, `ns::alpha`), or a sentinel.
};
static_assert( sizeof( Binding ) == 6 * sizeof( std::uint32_t ) + 3 * sizeof( std::string ),
               "Binding's scalars are five u32, a u8 kind, a bool and two u8 in 24 bytes — the four ride one u32 slot" );

// R5 cross-language FFI binding alias. A language-binding DECLARATION found in a C/C++ file (or a
// ctypes-handle assignment in a Python file) that makes a C/C++ definition reachable under a DIFFERENT
// language's name — so the call graph stops truncating at the language border. Captured PURELY
// syntactically at ingest; buildGraph turns each into a provenance-tagged FALLBACK alias edge, consulted
// ONLY when the normal langCompatible ladder drops a call (so a same-language local def ALWAYS wins).
//   Pybind       — `m.def("alias", &Scope::target)` / `.def("alias", &target)`: aliasName is the
//                  Python-visible name, targetName/targetScope the bound C++ symbol. Sound (explicit).
//   ExternC      — a function declared inside `extern "C"`: aliasName==targetName==the C symbol name,
//                  reachable from ctypes/cffi/cgo by that bare name. LOW-confidence (name-pattern).
//   CtypesHandle — a Python `lib = CDLL(...)`/`ctypes.CDLL(...)`/`cdll.LoadLibrary(...)`/`ffi.dlopen(...)`:
//                  aliasName is the handle VARIABLE; it gates ExternC resolution of a `lib.foo()` call so
//                  a bare `x.foo()` never manufactures an FFI edge. (Not itself an alias edge.)
//   Jni          — decoded in buildGraph from a `Java_pkg_Cls_method` def name (no ingest capture); not
//                  stored here.
enum class BindKind : std::uint8_t { Pybind, ExternC, CtypesHandle };
// The number of BindKind enumerators — the bound readFfi validates a cached kind byte against (see kSymKindCount).
inline constexpr std::size_t kBindKindCount = static_cast<std::size_t>( BindKind::CtypesHandle ) + 1;
static_assert( enumCountIsExact<BindKind, kBindKindCount>(), "kBindKindCount must name the LAST BindKind enumerator — move it with the append" );

struct BindingAlias
{
    std::uint32_t fileId  = 0;                  // the file the binding declaration lives in (restamped on cache load)
    BindKind      kind    = BindKind::Pybind;
    bool          lowConf = false;              // a name-pattern guess (ExternC/ctypes) → honesty flag on the edge
    std::string   aliasName;                    // foreign-visible name (pybind "name"); or the ctypes handle var
    std::string   targetName;                   // C/C++ symbol final-segment name (`cpp_fn`, `method`); "" for CtypesHandle
    std::string   targetScope;                  // C/C++ symbol scope (`T` for `&T::method`); "" if none
};

// S5-E HAS-A composition edge (owner class → member type): one record per member-variable
// declaration whose type resolved to a known class/struct. Stored OUTSIDE the call graph so
// PageRank, ranks, and the default map are UNCHANGED. Emitted only in --for and --around.
struct ComposeEdge
{
    NodeId      ownerSym  = kNoNode;   // the enclosing class symbol (fromSymbol of the RawRef)
    NodeId      typeSym   = kNoNode;   // the member type symbol (resolved by name, any-file)
    std::string fieldName;             // the member variable name (e.g. "m_pool")
    std::string typeName;              // the type name as written (e.g. "SpherePool")
    std::string ownerName;             // the owner class name (redundant but handy for serializer)
    std::string rel;                   // "creates" (value) or "uses" (reference/pointer)
};

// B6.3 HTTP-route cross-service edge kind. A route DEF is a server-side registration (Express/Fastify
// `app.get('/path', handler)`, FastAPI/Flask `@app.get("/path") def handler(): ...`); a route USE is a
// client-side call (`fetch('/path')`, `axios.get('/path')`, `requests.get('/path')`). Both are captured
// PURELY syntactically at ingest (table-driven, see ingest.cpp captureRoutes) — same posture as
// BindingAlias above: names/paths are recorded here, resolved to NodeIds later in buildGraph (graph.h),
// which matches USE→DEF by (method, path) and stores the synthesized result OUTSIDE the call graph
// (Graph::routeEdges) so PageRank and the default map are byte-identical on any route-free corpus.
// Cross-root matching is INTENTIONAL: a (method,path) match between a client
// root and a server root IS explicit evidence, unlike a bare same-name guess.
enum class HttpMethod : std::uint8_t { Get, Post, Put, Patch, Delete, Unknown };
// The number of HttpMethod enumerators — the bound readRouteDef/readRouteUse validate a cached method byte against.
inline constexpr std::size_t kHttpMethodCount = static_cast<std::size_t>( HttpMethod::Unknown ) + 1;
static_assert( enumCountIsExact<HttpMethod, kHttpMethodCount>(), "kHttpMethodCount must name the LAST HttpMethod enumerator — move it with the append" );

// ordinal-indexed table (declaration order MUST track the enum above) — the `method=` XML attribute.
// Unknown ⇒ "" (omitted attribute value, matches EITHER side per routematch::methodsCompatible).
inline constexpr const char* kHttpMethodTagTable[] = { "GET", "POST", "PUT", "PATCH", "DELETE", "" };
static_assert( std::size( kHttpMethodTagTable ) == kHttpMethodCount, "kHttpMethodTagTable needs one tag per HttpMethod enumerator" );

inline const char* httpMethodTag( HttpMethod m ) noexcept
{
    const auto idx = static_cast<std::size_t>( m );
    return idx < ( sizeof( kHttpMethodTagTable ) / sizeof( kHttpMethodTagTable[0] ) ) ? kHttpMethodTagTable[ idx ] : "";
}

// declarative name→method table (house style: table over switch), shared by every detector: Python
// decorator attribute names (`app.get`), JS/TS registrar + axios methods (`app.post`/`axios.post`), and
// Python `requests.VERB`. httpMethodFromName (graph-independent, pure) lives beside it.
inline constexpr struct { const char* name; HttpMethod method; } kHttpMethodTable[] = {
    { "get",    HttpMethod::Get    },
    { "post",   HttpMethod::Post   },
    { "put",    HttpMethod::Put    },
    { "patch",  HttpMethod::Patch  },
    { "delete", HttpMethod::Delete },
};

inline HttpMethod httpMethodFromName( std::string_view name ) noexcept
{
    for( const auto& e : kHttpMethodTable )
    {
        if( name == e.name )
        {
            return e.method;
        }
    }
    return HttpMethod::Unknown;
}

struct RouteDef      // server-side route registration — one record per recognized app.VERB(...)/@app.VERB(...)
{
    std::uint32_t fileId      = 0;                  // restamped on cache load, like BindingAlias.fileId
    std::uint32_t line        = 0;                   // 1-based, the registration/decorator line
    HttpMethod    method      = HttpMethod::Unknown;
    std::string   path;                              // AS WRITTEN — template segments verbatim ("/users/{id}", "/users/:id")
    std::string   handlerName;                       // final identifier segment of the handler; "" ⇒ inline/anonymous
                                                      // (unresolved — buildGraph can never attach an edge to it)
};

struct RouteUse       // client-side HTTP call — one record per recognized fetch/axios/requests call
{
    std::uint32_t fileId      = 0;
    std::uint32_t line        = 0;
    NodeId        fromSymbol  = kNoNode;             // enclosing function/method making the call; kNoNode if file-scope
    HttpMethod    method      = HttpMethod::Unknown;
    std::string   path;
};

// B6.3 synthesized route USE→DEF edge — OUTSIDE the call graph (PageRank/default map unchanged, exactly
// like ComposeEdge above). Populated in buildGraph (graph.h) by matching RouteUse against RouteDef on
// (method, path); emitted only via serialize.h::packRoutes (--for / --around), gated on non-empty so a
// route-free corpus stays byte-identical to pre-B6.3 output.
struct RouteEdge
{
    NodeId        fromSym  = kNoNode;              // the USE's enclosing symbol; kNoNode if file-scope
    NodeId        toSym    = kNoNode;              // the DEF's handler symbol — ALWAYS resolved (unresolved-handler
                                                   // DEFs are excluded before an edge is ever created; see buildGraph)
    HttpMethod    method   = HttpMethod::Unknown;  // the matched DEF's method (concrete when the DEF named one)
    std::string   path;                            // the DEF's path, as written (template form)
    std::string   fromName;                        // redundant, for the serializer (see ComposeEdge precedent); "" if fromSym==kNoNode
    std::string   toName;                          // the handler symbol's name
};

// One otherwise-indexable file the crawl DROPPED for exceeding a size ceiling — the skipped_oversize=
// population, itemized (the count alone said the corpus was truncated without naming what was absent).
// `path` is the CRAWL spelling, the same vocabulary result.files uses, so a row joins the map's p=
// values; the multi-root merge relabels it to `<label>/<rel>` exactly like files. `limitBytes` is the
// ceiling that dropped the file (--max-file-size's value, or kMaxJsonConfigBytes for the .json lane),
// so sizeBytes > limitBytes is self-evident in the row.
struct SkippedOversize
{
    std::string   path;
    std::uint64_t sizeBytes  = 0;
    std::uint64_t limitBytes = 0;
};

// §L1 — THE SKIP TAXONOMY. `oversize` above was the only drop reason the tool could NAME, so every
// other way a file left the corpus read as "nothing was dropped": --skipped reported oversize="0" on a
// tree where the crawl had passed over thousands of files, which is the honesty contract's own failure
// mode (a zero that means "none exists" rather than "none found"). These two classes complete it.
//
// `excluded` — matched a --exclude substring while carrying an INDEXABLE extension. Only files the walk
// actually enumerated appear: an --exclude that prunes a whole DIRECTORY stops the walk at the directory,
// so its contents are never seen and CANNOT be listed. Those prunes are counted separately
// (excludedDirs) and the verb says out loud that the file count under them is unknown, not zero.
//
// `unsupported` — a source/text-looking extension with no grammar and no doc handler. This is the class
// that hides a whole LANGUAGE: on facebook/infer (11 923 files, ~60% OCaml) the map header gave no
// indication that the repo's primary language contributed nothing to it.
struct SkippedFile
{
    std::string   path;
    std::uint64_t sizeBytes = 0;
    std::string   ext;        // lowercased, leading '.'; "" when the name carries no extension
};

// One unindexed extension and how many files wore it — the header's `unindexed=` roll-up, itemized.
struct UnindexedExt
{
    std::string   ext;
    std::uint64_t files = 0;
};

// The ONE ordering `unindexed=` is emitted in — most files first, extension name as the tiebreak. Shared
// (not re-spelled at each sort site) because it rides the DEFAULT map header from two different producers:
// the single-root crawl, and the multi-root merge that unions their histograms. An order that differed
// between those two, or that depended on hash-map iteration, would be a determinism bug.
inline bool lessUnindexedExt( const UnindexedExt& a, const UnindexedExt& b ) noexcept
{
    // MIXED-DIRECTION sort via one swapped std::tie: `files` compares with the operands reversed (so the
    // LARGER count sorts first) while `ext` compares in normal order (so the smaller name breaks the tie).
    // Written this way rather than as the two-branch comparator it replaces because that shape is one the
    // clone lens groups with every other two-field comparator in the tree — this tree already holds several.
    return std::tie( b.files, a.ext ) < std::tie( a.files, b.ext );
}

// The non-oversize crawl disclosures. Row vectors are CAPPED (kMaxSkipRowsPerClass) so a tree with a
// million unindexed files cannot be a memory hazard; the counts beside them are EXACT and the cap is
// disclosed on the emitted row set, never silent.
// Deliberately NOT merged into IngestResult::skippedOversize: that vector's SIZE is the map header's
// skipped_oversize= count, and one accounting number must keep one meaning (the "one source, never two
// counters" rule above).
// §N6-C — WHICH ignore rules the crawl actually consulted for this root. The map narrows a corpus only
// where it can explain the narrowing, so the four states stay apart rather than collapsing into a bool: a
// reader whose symbol vanished needs to tell "the repository declares that file ignored" from "the walk
// never asked" from "you turned the rule off".
enum class IgnoreMode : std::uint8_t
{
    Unavailable = 0,   // no git work tree at this root, or no git binary — TODAY'S FULL WALK, nothing ignored
    Git         = 1,   // git's own ignore rules were consulted and applied
    Off         = 2,   // --no-ignore: the caller asked for the full walk
    // The root ITSELF sits inside an ignored subtree (`ripwire build/` in a repo whose .gitignore holds
    // `build/`). git answers "./" — everything — and honouring that would hand back an EMPTY map for a
    // directory the user pointed at deliberately. Full walk, and the mode says why: a silent empty map is
    // the worst available reading of "map this".
    RootIgnored = 3
};

struct CrawlSkips
{
    std::vector<SkippedFile>  excluded;             // capped rows, path-sorted
    std::vector<SkippedFile>  unsupported;          // capped rows, path-sorted
    std::uint64_t             excludedFiles   = 0;  // EXACT count (rows may be fewer)
    std::uint64_t             unsupportedFiles = 0; // EXACT count (rows may be fewer)
    std::uint64_t             excludedDirs    = 0;  // subtrees pruned by --exclude: contents NEVER enumerated
    // Subtrees pruned by BUILT-IN POLICY, not by anything the caller asked for: the committed denylist
    // (ingest.h kCrawlSkipDirs — node_modules/.git/build/…) and the CMakeCache.txt build-output sentinel.
    // Kept apart from excludedDirs on purpose. Both classes stop the walk at the directory, so both leave
    // the contents UNKNOWN rather than zero — but a reader debugging "why is my tree not in the map"
    // needs to tell "this build always skips that" from "you asked me to skip that", and one counter
    // cannot say both. Before this existed, all three prune paths converged on
    // disable_recursion_pending() and only the --exclude one incremented anything, so `--skipped` over a
    // tree with node_modules/ reported EVERY counter zero while whole subtrees had been dropped.
    std::uint64_t             prunedDirs      = 0;
    std::vector<UnindexedExt> unindexedExts;        // EXACT histogram, sorted files desc then ext asc

    // §N6-C — the .gitignore lane. TWO counters for the same reason excludedDirs and prunedDirs are two:
    // an ignored FILE is an exact drop the walk saw and counted, an ignored SUBTREE stops the walk at the
    // directory and leaves its contents UNKNOWN rather than zero. Both classes are tested LAST, after the
    // extension classification, the --exclude match and the built-in denylist, so every existing counter
    // keeps exactly the meaning it had: ignoredFiles counts files that would OTHERWISE HAVE BEEN INDEXED
    // (which is what makes it the number the header's accounting invariant can carry), and ignoredDirs
    // counts only the subtrees no other rule had already pruned. The one class that consults the verdict
    // EARLIER is `unsupported` above: grep serves that population, so a gitignored file of an unindexed
    // extension is not rowed there either — it is in no class at all, exactly as an --exclude'd one
    // already was (ingest_crawl.h recordPreSizeDrop's header).
    std::vector<SkippedFile>  ignored;              // capped rows, path-sorted — the individual ignored files
    std::vector<SkippedFile>  ignoredDirRows;       // capped rows, path-sorted — the pruned subtrees (bytes 0, ext "")
    std::uint64_t             ignoredFiles    = 0;  // EXACT count (rows may be fewer)
    std::uint64_t             ignoredDirs     = 0;  // subtrees pruned by git's ignore rules: contents NEVER enumerated
    IgnoreMode                ignoreMode      = IgnoreMode::Unavailable;   // NOT-ASKED is the honest default

    // The one PARSE-time class in this taxonomy: files the crawl INDEXED (they keep their fileId and stay inside files=
    // and unmeasured=) that a pre-parse nesting guard then refused, so they contribute no symbols. Today only the Kotlin
    // string-template guard rows its refusals (ingest.h kMaxKotlinStringNestDepth); the json/yaml/markdown guards are
    // counted in unmeasured= alone. Filled after the parse pool, never by the walk, and NOT part of the accounting
    // invariant's drop classes — a refused file is already inside indexed=.
    std::vector<SkippedFile>  nestRefused;          // capped rows, path-sorted
    std::uint64_t             nestRefusedFiles = 0; // EXACT count (rows may be fewer)
    // The second PARSE-time class, filled beside nestRefused: indexed files whose facts are PARTIAL — an extraction pass
    // stopped at a nesting bound, the grammar's tags query was unavailable, or the extraction threw part-way (the facts
    // before the throw are kept). Inside indexed=, never cached as whole; NOT one of the accounting invariant's drop classes.
    std::vector<SkippedFile>  extractPartial;       // capped rows, path-sorted
    std::uint64_t             extractPartialFiles = 0; // EXACT count (rows may be fewer)

    // §SEC1 — files the crawl REFUSED because a symlink took them out of the root they were crawled under
    // (ingest.h's crawl-boundary rule; darkflags.h's CMake walk applies the same rule to its own harvest).
    // A class of its own, and tested FIRST, because none of the classes above can carry it honestly: this is
    // not a language this build cannot read, not something the user asked to hide, and not something the
    // repository declared uninteresting — it is content this tool declined to disclose. Folding it into
    // `unsupported` would be actively wrong: grep's aux scan READS that population, which is exactly how the
    // fifth serving channel stayed open (test/crawlescapecheck.sh arm 5).
    //
    // The rows carry bytes=0 as the NOT-MEASURED sentinel the ignored-dir rows already use, deliberately: a
    // size would have to come from `file_size()` on the link, which follows it, and handing back the size of
    // a file we just declined to read gives away a piece of what the refusal withheld. The path is the
    // IN-ROOT link, never the target, for the same reason.
    std::vector<SkippedFile>  escaped;              // capped rows, path-sorted (bytes 0 = not measured)
    std::uint64_t             escapedFiles    = 0;  // EXACT count (rows may be fewer)
    // The DISCLOSE sink for a file the crawl refused because its link left the root: the exact count escaped_root= prints.
    enum class DisclosureWhy : std::uint8_t
    {
        SymlinkEscapesRoot,
    };
    void disclose( DisclosureWhy ) noexcept
    {
        ++escapedFiles;
    }
};

// §L1 — PARSE HEALTH: a per-indexed-file record of how much of the file the parser actually understood,
// and whether the file looks machine-written. Both classes are DISCLOSURE ONLY — the file stays indexed
// and every symbol it contributed stays in the map. The point is that a reader can tell the difference
// between "no symbols here" and "symbols we cannot vouch for".
//
// errNodes/errBytes are a PARSER-STATE fact, never a syntax verdict: tree-sitter error recovery fires on
// a valid file written in a dialect the vendored grammar predates just as it fires on a truncated one, and
// a reader needs to be told about BOTH. Hence the label "degraded-parse", not "invalid syntax".
//
// fileBytes == 0 is the NOT-MEASURED sentinel (an indexed file always has a size): the ingest never
// parsed that file — a doc-format file handled by the doc post-pass, a file the binary sniff or a nesting
// guard refused, or a read failure. The verb reports those as a separate count, never as zero findings.
// The doc post-pass is deliberately left on that side of the line: a notebook's EXTRACTED prose has no
// tree-sitter parse that could be degraded, and inventing a clean reading for it would be exactly the
// guess this lane exists to remove.
// Round-trips the incremental cache (ingest_cache.h, since kCacheVersion 13): the auto-cache is the DEFAULT path, and
// a disclosure that evaporates on the warm run is worse than none.
struct FileHealth
{
    std::uint32_t errNodes  = 0;   // ERROR + MISSING nodes in the file's parse tree, plus invalid UTF-8
                                    // sequences found in the leading sample (see measureFileHealth)
    std::uint32_t errBytes  = 0;   // bytes covered by the TOP-MOST ERROR nodes (MISSING is zero-width);
                                    // one byte per invalid UTF-8 sequence start, same caveat as errNodes
    std::uint32_t fileBytes = 0;   // the parsed byte length; 0 ⇒ NOT MEASURED (see above)
    std::uint32_t wsBytes   = 0;   // whitespace bytes in the leading min(fileBytes, 4096) sample
    std::uint32_t macroBlanked = 0;   // member-macro re-parse (src/macroreparse.h): invocations blanked for the ADOPTED
                                      // parse this file's symbols came from; 0 ⇒ the first parse was kept. errNodes and
                                      // errBytes above always describe the parse extraction actually read.
    std::uint32_t useBoundsBlanked = 0;   // its Rust layer (src/rustusebounds.h): precise-capturing use<..> bounds
                                          // blanked for the ADOPTED parse; 0 ⇒ the first parse was kept
};

// Output of ingestion. Deterministic: files sorted lexicographically, symbol ids assigned
// in (file, line, name) order so the whole pipeline is reproducible run-to-run.
// ── #350 layer 3: the memory guard stopped this ingest before it finished (src/memguard.h). Unset on every run
//    that finished — which is every run whose footprint stayed under the guard's lines, i.e. every normal run —
//    so nothing reads it unless the guard fired. Set ONLY through DISCLOSE( memoryStop, … ): the map header's
//    memory_stop=/memory_parsed=/memory_limit=/memory_pressure= and the MCP envelope's _memory_stop read it.
struct MemoryStop
{
    enum class Phase : std::uint8_t
    {
        None,
        Crawl,   // the crawl stopped first: files= is what it had seen, sorted — a floor of the tree
        Parse,   // the crawl finished and the parse stopped
    };
    Phase         phase       = Phase::None;   // where the guard FIRST stopped work
    bool          parseCut    = false;         // the parse stopped (after a whole crawl or after a stopped one)
    bool          byPressure  = false;         // the OS memory-pressure signal stopped it, not the footprint limit
    std::uint32_t parsedFiles = 0;             // parseCut only: the unbroken prefix of the parse order that finished
    std::uint64_t limitBytes  = 0;             // the guard's hard limit when it fired (what --max-memory would raise)

    enum class DisclosureWhy : std::uint8_t
    {
        CrawlOverLimit,
        CrawlUnderPressure,
        ParseOverLimit,
        ParseUnderPressure,
    };
    void disclose( DisclosureWhy why ) noexcept
    {
        const bool isCrawl = why == DisclosureWhy::CrawlOverLimit || why == DisclosureWhy::CrawlUnderPressure;
        if( phase == Phase::None )
        {
            phase = isCrawl ? Phase::Crawl : Phase::Parse;
        }
        parseCut   = parseCut || !isCrawl;
        byPressure = byPressure || why == DisclosureWhy::CrawlUnderPressure || why == DisclosureWhy::ParseUnderPressure;
    }
    [[nodiscard]] bool isSet() const noexcept { return phase != Phase::None; }
};

struct IngestResult
{
    std::vector<std::string> files;

    // §P0.4/§P0.5d: the otherwise-indexable files the crawl DROPPED for exceeding a per-file size
    // ceiling (--max-file-size / kDefaultMaxFileBytes, OR the .json lane's fixed kMaxJsonConfigBytes — §B13.1;
    // the two are mutually exclusive per file, so nothing is counted twice). `--max-file-size=8K` silently
    // dropped ~296 of ~759 files and the header reported files=463 as if that were the corpus. Empty on every
    // default run of a tree with nothing oversized; the header count is surfaced only when non-zero — absent
    // means nothing was skipped. The invariant a reader may rely on: files= + skipped_oversize= = the
    // population the crawl considered, at EVERY --max-file-size setting. The header emits size() as
    // skipped_oversize=; --skipped itemizes the rows (one source, never two counters). Sorted by path.
    std::vector<SkippedOversize> skippedOversize;

    CrawlSkips              crawlSkips;   // §L1 skip taxonomy + unindexed-ext histogram — see CrawlSkips
    std::vector<FileHealth> fileHealth;   // §L1 parse health, parallel to `files` — see FileHealth

    // #157: fileId -> 1 when ingest's own pre-parse nesting guard (json/yaml/markdown/kotlin) refused this
    // file, 0 otherwise. Parallel to `files`, EXACT (unlike crawlSkips.nestRefused's capped row list), so
    // every OTHER corpus-reading parse site (the --match/--pattern/--lint structural-query walk in
    // ingest_astquery.h) can stay consistent with ingest's own refusal by asking this array instead of
    // re-deciding the question with a second, independently-maintained prescan. Empty on a lean/stub
    // IngestResult that never ran the parse pool (a fileId past its size means "not captured", never "not
    // refused" — every reader must bounds-check, the same discipline crawlSkips itself uses).
    std::vector<std::uint8_t> nestRefusedFile;

    std::vector<Symbol>      symbols;      // definitions (NEVER a SymKind::Field — see fields)
    std::vector<Symbol>      fields;       // member-variable round (card A3): the FIELD side table. Symbol::id is the index
                                           // INTO THIS VECTOR (a FieldId, not a NodeId), kind == SymKind::Field, scope == the
                                           // owner, canonical id path::Owner::field. Sorted like symbols ((fileId, line, name,
                                           // startByte)); reachable only through graph.h's resolveFieldSelector.
    std::vector<FnLocalScope> fnLocalScopes;   // one row per Symbol::fnLocal def, ascending id: the span of the function
                                               // whose body binds its name (SoA side table: Symbol has no byte left for it)
    std::vector<Reference>   references;   // unresolved calls
    std::vector<Include>     includes;     // #include / import directives (physical dependencies)
    std::vector<ConstOpen>   constOpens;   // parser version 82: Ruby class/module opens, for the constant index (resolve.h)
    std::vector<Binding>     bindings;     // P2-D Rule 2: local var→type bindings (`Foo x;`), for receiver-var narrowing
    std::vector<BindingAlias> bindingAliases;  // R5: cross-language FFI binding declarations (pybind/extern-C/ctypes)
    std::vector<RouteDef>    routeDefs;     // B6.3: HTTP server-side route registrations (unresolved handler names)
    std::vector<RouteUse>    routeUses;     // B6.3: HTTP client-side calls (fromSymbol resolved by byte-span, like Reference)

    // Doc-ingest override (P1-B): for a document file (notebook/html/csv/…) this holds its EXTRACTED text,
    // keyed by fileId. lexical.h / recall.h index + emit this instead of the raw bytes, so a notebook is
    // retrieved by its prose, not its JSON. Empty for code/markdown files (they read straight from disk).
    HashMap<std::uint32_t, std::string> docText;

    // ── B0.2 persisted subtoken statistics (lexindex.h; RICH ingests only — hasLexStats gates use).
    //    Per-symbol CSR over (subtokenHash, weighted tf) pairs for the doc-comment+body BM25F fields,
    //    plus each symbol's weighted doc/body token count and a per-file 512-bit pre-filter signature
    //    (B0.1). Built at parse time / restored from the rich cache, in symbol-id order → deterministic.
    //    lexical.h Pass 2 consumes these instead of re-reading + re-tokenizing every file per query;
    //    when hasLexStats is false (lean ingest, multi-root merge, stub) the scan path runs unchanged.
    bool                       hasLexStats = false;
    std::vector<std::uint32_t> lexTokenRowOffsets;   // size symbols.size()+1 — CSR row bounds (32-bit ids)
    std::vector<std::uint64_t> lexTokenHashes;       // sorted ascending within each symbol's row
    std::vector<std::uint32_t> lexTokenTfs;          // weighted tf, parallel to lexTokenHashes
    std::vector<std::uint32_t> lexDocBodyDl;         // size symbols.size() — weighted doc+body token count
    std::vector<std::uint64_t> lexFileSig;           // size files.size()×kLexFileSigWords — B0.1 file Bloom

    // ── Multi-root workspace identity — ALL EMPTY on a single-root run (the
    //    byte-identity quarantine: every consumer guards on emptiness). Populated ONLY by
    //    workspace.h::mergeWorkspaceIngests when 2+ roots survive dedupe. When populated, ing.files hold
    //    the LABELED spelling `<label>/<root-relative-path>` (the identity every surface emits) and
    //    realPaths hold the on-disk crawl spelling (what any fopen/stat must use — see diskPath below).
    std::vector<std::string>   realPaths;    // fileId → on-disk path (empty ⇒ ing.files ARE the disk paths)
    std::vector<std::uint32_t> fileRoot;     // fileId → root index (canonical label order)
    std::vector<std::string>   rootLabels;   // root index → label (shortest unique whole-segment suffix)
    std::vector<std::string>   rootPaths;    // root index → the root path as passed (post-dedupe)
    std::vector<std::string>   rootReals;    // root index → realpath (cross-root include probes, git -C)

    // ── The crawl root, as the crawl joined it onto every path (single root only). `files` keep that spelling
    //    because it is also the disk spelling every read and edit opens — but it must never decide an ANSWER.
    //    `ripwire .`, `ripwire "$PWD"`, `ripwire "$PWD/"`, a symlink to the tree and `ripwire ../repo` are one
    //    tree, and every question about a file's place IN that tree (which file an import names, whether it
    //    sits under test/ or fixtures/, how many path bytes a row prints) reads rootRelPath below instead.
    //    Recorded once by ingest(); a single-file root records the file's directory. EMPTY on a multi-root
    //    merge, whose `files` are already the labeled root-relative identity (rootRelPath is then the identity).
    std::string                crawlRoot;
    // …and every PREFIX a selector path typed from the cwd can start with before the root-relative part (graph.h
    // selectorRootTail): the root as typed, then the root expressed relative to the cwd, then its absolute spellings
    // (joined onto the shell's logical $PWD and onto getcwd, and its realpath — a user types the logical spelling, and
    // a symlinked prefix such as /tmp vs /private/tmp makes the two differ). "." means the root IS the cwd, so a `./`
    // path is root-relative. Lexically normalised, no trailing '/', each once. Recorded once by ingest(); empty on a
    // multi-root merge, like crawlRoot.
    std::vector<std::string>   crawlRootPrefixes;

    // ── P1-15: how many files this run actually RE-EXTRACTED (cache miss / changed / new) rather than
    //    reusing from the content-hash cache — the number RIPWIRE_CACHE_STATS has always printed as
    //    `reparsed=`, promoted to a field so the MCP server can disclose an incremental pass's cost
    //    (`_reingest`) without the caller re-running the binary under an env observable. PROCESS HISTORY,
    //    not tree state: a cold run re-extracts everything and a warm one re-extracts the drift, so nothing
    //    that must be byte-identical warm-vs-cold may fold it in. Multi-root: the merge sums the per-root
    //    values, so one number describes the whole pass.
    std::size_t                reparsedFiles = 0;

    // ── #350 layer 3: the memory guard stopped this ingest before it finished (MemoryStop, above)
    MemoryStop                 memoryStop;
};

// These aggregates cross the ingest/main translation-unit boundary. The record is emitted once per TU by
// structlayout.h, so a header change that leaves a mixed binary can be diagnosed after linking instead of
// passing a self-consistent static_assert in each half.
RIPWIRE_LAYOUT_REGISTER_TYPES( RIPWIRE_LAYOUT_TYPE_ENTRY( std::string ),
                               RIPWIRE_LAYOUT_TYPE_ENTRY( Symbol ),
                               RIPWIRE_LAYOUT_TYPE_ENTRY( Reference ),
                               RIPWIRE_LAYOUT_TYPE_ENTRY( Include ),
                               RIPWIRE_LAYOUT_TYPE_ENTRY( ConstOpen ),
                               RIPWIRE_LAYOUT_TYPE_ENTRY( Binding ),
                               RIPWIRE_LAYOUT_TYPE_ENTRY( BindingAlias ),
                               RIPWIRE_LAYOUT_TYPE_ENTRY( RouteDef ),
                               RIPWIRE_LAYOUT_TYPE_ENTRY( RouteUse ),
                               RIPWIRE_LAYOUT_TYPE_ENTRY( FileHealth ),
                               RIPWIRE_LAYOUT_TYPE_ENTRY( SkippedOversize ),
                               RIPWIRE_LAYOUT_TYPE_ENTRY( IngestResult ) );

// multi-root workspace cap: a sane bound on N crawl roots — an agent joining a
// handful of checkouts is the use case; hundreds of roots is a mis-glued path list, refused loudly.
inline constexpr std::size_t kMaxWorkspaceRoots = 16;

// ── S2: root-relative path for BASELINE HASHING (root-spelling portability) ─────────────────────────────
//
// .ripwire_arch_baseline is meant to be COMMITTED and portable; .ripwire_quality_baseline is gitignored,
// re-pinned before a change, and stamped with the build that pinned it (a dead set depends on call resolution),
// but both must still hash the same file the same way under every root spelling. And every path in ing.files is spelled `<ingest-root>/<relative>` verbatim — the crawl just
// prepends the root argument. So `ripwire .` embeds `./game/x.cpp` while `ripwire /abs/repo` embeds
// `/abs/repo/game/x.cpp`, giving DIFFERENT hashes for the same file → a baseline written under one root
// spelling falsely fails enforcement under another (exit 0 vs 2 for a teammate/CI with a different root).
//
// relForHash strips the ingest-root prefix LEXICALLY (never a realpath — that would be nondeterministic and
// pull in the filesystem, and would break on a symlinked/`..`-containing root), producing the SAME
// root-relative key for both spellings. Every use is a root-spelling NORMALIZATION of exactly this shape:
// the baseline hash paths, and — W3FIX — the --dead-code `./`-anchored path filter, whose "position 0 is the
// repo root" rule holds only for a root-relative path and so silently matched nothing under an absolute root
// spelling. It never touches `g.canonId`, resolution, or any storage key (see the S2 trap: canonId is
// load-bearing far beyond the baseline). Determinism: pure function of (path, root); no I/O, no state.
//
// R-R (root-relative emission) AMENDED THE LAST CLAUSE. This used to add "and it is never an emitted VALUE
// — only ever a comparison key". That is no longer true, deliberately: resolve.h::canonicalIdForEmit runs
// the path segment of every EMITTED `id=` (and the MCP handle that hashes it) through this same strip, so
// the emitted identity and the committed baseline key finally spell a file the same way. What the S2 trap
// actually protects is unchanged and still absolute: g.canonId — the in-memory identity that resolution,
// overload-set grouping and Regression::key depend on — is never rewritten. Emission is a VIEW of that
// identity; the identity itself does not move.
//
// #228 AMENDED "never resolution". rootRelPath below applies this strip to the root ingest() recorded, and
// the include/import index, the path predicates and the path-byte charges now read that view — the fix for
// answers that moved with the root's spelling. The storage key and g.canonId are still never rewritten.
//
// The strip is: remove a leading `root` prefix (with an optional trailing '/'), then normalize any residual
// leading `./` and leading `/`. A path that does not start with `root` (shouldn't happen — every file is
// under the crawl root) is returned only leading-`./`/`/`-normalized, so it degrades to a stable key rather
// than an empty one. Empty root ⇒ just the leading-`./`/`/` normalization (equivalent to root ".").
inline std::string_view relForHash( std::string_view path, std::string_view root ) noexcept
{
    // 1) strip the ingest-root prefix if present (allow one optional trailing '/' on the root).
    std::string_view rootTrim = root;
    while( rootTrim.size() > 1 && rootTrim.back() == '/' )
    {
        rootTrim.remove_suffix( 1 ); // "/abs/repo/" → "/abs/repo"
    }
    if( !rootTrim.empty() && rootTrim != "." && path.size() >= rootTrim.size()
        && path.compare( 0, rootTrim.size(), rootTrim ) == 0 )
    {
        // matched the root; the next char (if any) must be a '/' so we strip whole path components only
        // ("/abs/repo" must not eat the "repo" in "/abs/repository/...").
        std::string_view rest = path.substr( rootTrim.size() );
        if( rest.empty() || rest.front() == '/' )
        {
            path = rest;
        }
    }

    // 2) normalize residual leading "./" then leading "/" so "." / "./x" / "/x" all collapse to "x".
    while( path.size() >= 2 && path[0] == '.' && path[1] == '/' )
    {
        path.remove_prefix( 2 );
    }
    while( !path.empty() && path.front() == '/' )
    {
        path.remove_prefix( 1 );
    }
    while( path.size() >= 2 && path[0] == '.' && path[1] == '/' )
    {
        path.remove_prefix( 2 );
    }
    return path;
}

// The ONE root-relative seam, the dual of the disk-path seam below: every DECISION about a file's place in the tree reads
// this, never ing.files[fileId] directly. It is relForHash against the root the crawl recorded, so it costs a
// prefix compare and no allocation or syscall, and it is a VIEW — the stored spelling (and so every printed
// path, cache key and disk open) is untouched.
//
// Why it exists (#228). `ing.files` carry the root exactly as it was typed, and until this seam the index
// builders and the path predicates read that spelling raw. So the answer moved with the spelling: Python's
// root-relative import probe matched only under `ripwire .` (a Django clone read graph_ambiguous=5958 under
// `.` and 3135 under "$PWD"); every include index collapsed to one empty key under `ripwire ../repo`, because
// lexicalNormalize refuses a path that starts above its base; and a checkout that merely LIVES under a
// directory named tests/ or fixtures/ had every file classified as a test or a fixture under an absolute root
// and none under `.`. The --quality-delta HEAD side always ingests at an absolute temp root, so an unchanged
// tree gated under `.` and passed under "$PWD". test/rootspellingcheck.sh pins all of it.
inline std::string_view rootRelPath( const IngestResult& ing, std::uint32_t fileId ) noexcept
{
    const std::string_view path = ing.files[ fileId ];
    return ing.crawlRoot.empty() ? path : relForHash( path, ing.crawlRoot );
}

// The ONE disk-path seam: every file read/stat must go through this instead of ing.files[fileId] directly.
// Single-root (realPaths empty): returns ing.files[fileId] — byte-identical behavior, zero cost.
// Multi-root: returns the on-disk spelling behind the labeled identity path.
inline const std::string& diskPath( const IngestResult& ing, std::uint32_t fileId ) noexcept
{
    return ing.realPaths.empty() ? ing.files[ fileId ] : ing.realPaths[ fileId ];
}

// The ONE degraded-parse predicate (2026-08-30, degradedhintcheck): does this indexed file's recorded
// parse hold ERROR/MISSING nodes? fileBytes == 0 is the NOT-MEASURED sentinel and answers false — "we
// did not look" is not "degraded" (see FileHealth above). The skipped verb's classifySkipHealth applies
// the same errNodes > 0 rule when it builds its rows; grep's parse_degraded= file-row flag and the
// selector refusals' degraded clause both route through HERE, so the three surfaces can never disagree
// about what "degraded" means.
inline bool fileParseDegraded( const IngestResult& ing, std::size_t fileIndex ) noexcept
{
    return fileIndex < ing.fileHealth.size()
        && ing.fileHealth[ fileIndex ].fileBytes > 0
        && ing.fileHealth[ fileIndex ].errNodes  > 0;
}

// The member-macro re-parse's ONE per-file predicate (src/macroreparse.h): this file's symbols come from a re-parse with
// member macro invocations blanked. The skipped verb rows it (why=macro-blanked); every count below is of this.
inline bool isMacroBlankedHealth( const FileHealth& health ) noexcept
{
    return health.macroBlanked > 0;
}

// The Rust layer's per-file predicate (src/rustusebounds.h): this file's symbols come from a re-parse with its
// precise-capturing use<..> bounds blanked. The skipped verb rows it (why=use-bounds-blanked).
inline bool isUseBoundsBlankedHealth( const FileHealth& health ) noexcept
{
    return health.useBoundsBlanked > 0;
}

// ...and its corpus count: macro_blanked_files= on the map and --json headers (the skipped verb's root counts the same rows).
inline std::size_t macroBlankedFileCount( const IngestResult& ing ) noexcept
{
    return std::size_t( std::ranges::count_if( ing.fileHealth, isMacroBlankedHealth ) );
}

// The macro-edges round's honesty post-pass: a call-SHAPED reference (bare name, no receiver, no explicit
// qualifier) whose name UNIQUELY names an indexed C-family `#define` (see the uniqueness guard in the
// function body) is re-tagged RefRole::Macro, so no surface labels such an expansion role="call". Runs
// over the ASSEMBLED corpus — a per-file parse (and
// therefore the per-file cache record, which stores role=Call) cannot know another file's #defines — at
// BOTH ingest exits: the end of ingest() and the end of mergeWorkspaceIngests (a macro defined in one root,
// invoked from another). Idempotent and deterministic (one ordered pass, membership in a name set built
// from ing.symbols in id order). Restricted to C-family on BOTH sides: only C-family grammars have
// `#define`, and a same-named Python/JS call must not inherit a macro tag it cannot mean.
inline bool macroRefLang( Lang lang ) noexcept
{
    switch( lang )
    {
        case Lang::Cpp:
        case Lang::C:
        case Lang::ObjC:
        {
            return true;   // the grammars that have `#define` (ingest.cpp constCaptureNeedsScreamingGate's shape)
        }
        default:
        {
            return false;
        }
    }
}

// The UNIQUENESS GUARD's evidence (verifier collision refutation, round A5 fix): per C-family symbol
// name, bit 1 = an indexed macro def carries it, bit 2 = a NON-macro def (a real function, method, class
// ctor, or a callable var) carries it too. Only a name whose flags are EXACTLY 1 is "uniquely a macro".
struct MacroNameScan
{
    HashMap<std::string, char> flags;
    bool                       anyMacro = false;
};

inline MacroNameScan scanMacroNames( const IngestResult& ing )
{
    MacroNameScan scan;
    for( const Symbol& s : ing.symbols )
    {
        if( macroRefLang( s.lang ) )
        {
            const char bit = ( s.kind == SymKind::Macro ) ? char( 1 ) : char( 2 );
            scan.flags[ s.name ] = char( scan.flags[ s.name ] | bit );
            scan.anyMacro = scan.anyMacro || bit == 1;
        }
    }
    return scan;
}

inline void retagMacroCallReferences( IngestResult& ing )
{
    // UNIQUENESS GUARD (verifier collision refutation, round A5 fix): the retag has NO visibility model —
    // it cannot know whether the #define is in scope at a given call site — so it may only fire when the
    // name is UNIQUELY a macro in the corpus (scanMacroNames above). A name ALSO carried by any non-macro
    // C-family definition is left role="call" and takes the ordinary resolution ladder: a real `check()`
    // in a translation unit with no macro in scope must never be re-labelled because an unrelated
    // `#define check(x)` exists somewhere else. Degrade, never guess — suppression can only under-tag
    // (a plain call is the disclosed floor), never mislabel.
    const MacroNameScan scan = scanMacroNames( ing );
    if( !scan.anyMacro )
    {
        return;   // macro-free corpus: byte-identical output, zero cost beyond the symbol scan
    }
    for( Reference& r : ing.references )
    {
        if( r.role != RefRole::Call || r.isInherit || r.isDocLink || r.isCompose )
        {
            continue;
        }
        if( r.recv != RecvKind::None || !r.qualifier.empty() || !macroRefLang( r.lang ) )
        {
            continue;   // a receiver-qualified or scope-qualified call cannot be a macro invocation
        }
        const auto it = scan.flags.find( r.calleeName );
        if( it != scan.flags.end() && it->second == 1 )   // uniquely a macro — never a shared name
        {
            r.role = RefRole::Macro;
        }
    }
}

// ── LOCAL-SHADOW SUPPRESSION (r9 loss bucket 2; block-span fix round A5) ─────────────────────────────
// A reference site to name N inside the BLOCK where a LOCAL declaration binds N as a variable is a use of
// the LOCAL, not of any indexed symbol named N — C++ name lookup finds the local for that scope. The
// measured failure is real: a local `int run = 0;` put every `run` read/write inside its function into
// --uses=run (13 false sites on one r9 query), and a callable local could mint a false call edge through
// the bare-name ladder. SCOPE: each VarDecl record carries the byte span the declared name shadows within,
// and only a site whose own byte offset falls INSIDE that span is suppressed — so `{ int run = 0; } run();`
// keeps the genuine post-block call. Two span shapes, because C++ has two:
//   * an ordinary BLOCK declaration runs from its DECLARATION POINT — the end byte of the complete
//     declarator, which is [basic.scope.pdecl] exactly (immediately after the complete declarator and
//     before its initializer; for a structured binding, after its identifier-list) — to the end of the
//     enclosing compound_statement. Iteration 2 started this span at the block's opening BRACE instead,
//     which silently ate a genuine call written ABOVE the local (`key(); int key = 0;`): a recall loss,
//     not the disclosed over-suppression, so the point is now modelled rather than approximated.
//   * a WHOLE-SCOPE shape runs from the start of its scope, because its name is in scope there: a
//     definition's or lambda's parameters and a lambda's captures/init-captures (the body span), a catch
//     parameter (the handler span), a range-for variable (the loop statement), and a control-statement
//     HEADER declaration (that statement — `for (int run = 0; ...)` never reaches past its own loop).
// The residual over-approximation is the disclosed floor of emitShadowVarDecls, not of the span: a
// declarator shape it refuses (the most-vexing `std::string key( tok );`) records no evidence at all.
// Three further guards keep this suppression-only, never a mislabel:
//   * evidence is a VarDecl binding — a DECLARATION's variable name (ingest captureBindings). An
//     assignment-derived Type binding (`x = Foo();` re-binding a possibly-GLOBAL x) is NOT a declaration
//     in C++ and never suppresses.
//   * a (scope, name) that ALSO carries an L3 fn binding (FnDecl/FnAssign) is a call THROUGH the variable:
//     those references stay, so the resolve loop's binding resolution (and its tombstone honesty) is
//     untouched — `void (*cb)() = &run; cb();` keeps its reference and resolves via the binding.
//   * only a name some indexed symbol actually carries is suppressed: with no same-named definition
//     anywhere there is NO false attribution to prevent, and --uses on a plain local/parameter name (the
//     external-answer feature the writetarget gate pins) keeps its sites.
// Runs at every ingest exit AND after the multi-root merge (workspace.h), exactly like the macro retag
// above — a def named N in ANOTHER root only becomes visible to the collision gate once roots merge.
// Idempotent, deterministic (erase_if preserves order; hash maps never drive output order; span lists are
// built in ing.bindings' total order). Runs AFTER retagMacroCallReferences so a role="macro" site
// (preprocessor evidence, textually stronger than any local) is never touched.
// the suppression pass's evidence tables and their "<fromSymbol>#<name>" key builder — see the contract
// comment above suppressShadowedReferences below.
// ONE declaring-block byte span. A 2-field POD and NOT `std::pair<uint32,uint32>`, because rw::svector
// requires a trivially-copyable element and a std::pair is not reliably one.
//
// THE PRECISE CLAIM, because the loose version of it is wrong in both directions. The standard does not
// REQUIRE std::pair to be trivially copyable, so the answer is implementation-defined: libc++ (this
// toolchain, 210106) says no, libstdc++ defaults the operators and says yes. Measured here, only the two
// ASSIGNMENT operators fail — both constructors and the destructor are trivial. Same portability class as
// infra/charconvcompat.h: a thing that happens to work on one standard library is not a thing you can build
// on.
//
// AND IT IS PERMANENT, so nobody should "fix" this back to a pair later expecting the library to have caught
// up. `pair::operator=` has to be hand-written to support REFERENCE members — `std::tie( a, b ) = f()` must
// assign THROUGH the references, and a defaulted operator would be deleted. More decisively, triviality is
// part of the ABI: a trivially-copyable type can be passed in registers and a non-trivially-copyable one
// goes by hidden reference, so making pair trivial would break every by-value pair parameter already
// compiled. libc++ ships in the macOS SDK under a hard ABI-stability commitment. `std::tuple` is the same
// story for the same reasons — treat it identically.
//
// The choice this drives, stated as a rule rather than a one-off: when a conversion candidate's element is a
// std:: composite that fails the trait, replace the ELEMENT with a named POD. Routing the structure to
// ankerl instead would forfeit the branch-free size() and the memcpy bulk moves over a library accident
// rather than a design reason; ankerl is for elements that are genuinely non-trivial (a real std::string, or
// a struct that owns something). The POD is byte-identical to the pair — 8 B, same field order — and
// structured-binding reads at the use site are unchanged.
struct VarSpan
{
    std::uint32_t startByte;
    std::uint32_t endByte;
};
static_assert( sizeof( VarSpan ) == 8, "the span pair is two 32-bit byte offsets — a layout change here resizes every varSpans entry" );
static_assert( std::is_trivially_copyable_v<VarSpan>, "the whole reason this is not std::pair — see the comment above. This assert is what explains the one above it." );

struct ShadowEvidence
{
    // (fromSymbol, var) → the declaring-block spans (VarDecl evidence) · the fn-binding veto set. The veto
    // stays UN-spanned on purpose: erring toward keeping a reference is the recall-safe side.
    //
    // N=1, measured, not guessed. Every key has at least one span (a key is only created by recording one),
    // and a SECOND span means the same variable name is declared twice in one function — 4.3% of keys on the
    // 43K-symbol validation corpus, 6.0% here. At an 8-byte element rw::svector<VarSpan,1> is 16 B and
    // <VarSpan,2> is 24 B, so N=1 is a THIRD smaller than the std::vector it replaces while still holding
    // 94-96% of the lists inline; N=2 would cost exactly what std::vector costs to reach 98%. The
    // free-N-is-2 rule that holds for 4-byte elements does NOT transfer here — see infra/svector.h's
    // layout pins.
    HashMap<std::string, rw::SmallVec<VarSpan, 1>> varSpans;
    HashMap<std::string, char>                     fnBindKeys;
    HashMap<std::string, char>                     defNames;
};

// member-variable round (card A3): is this Read/Write reference a MEMBER ACCESS (`o.f`, `this->f`, `self.f`)?
// On a Read/Write ref, recv != None means exactly that (ingest_sidecap.h stampMemberReceiver). Such a site
// names a FIELD — which is never in ing.symbols — so every name-resolving consumer of the use-site stream
// (contextratio.h, nonlocalstate.h) skips it; the field index (graph.h collectFieldUseSites) answers it.
inline bool isMemberAccessSite( const Reference& r ) noexcept
{
    return ( r.role == RefRole::Read || r.role == RefRole::Write ) && r.recv != RecvKind::None;
}

// IX-1: a slot-type join record (RefRole::Value / Through above): a slot FACT (a field's struct type or a typedef alias, name
// "") or a call through a struct FIELD (name = the receiver's root variable, never a referenced symbol). Only the slot join
// (valuerefindex.h SlotIndex) reads them; every other consumer of the reference stream skips them, so a C/C++ answer that
// does not print the join (--context-ratio, --external-surface, stats, SCIP) reads the same stream it read before IX-1.
inline bool isSlotJoinRecord( const Reference& r ) noexcept
{
    if( r.qualifier.empty() )
    {
        return false;
    }
    return ( r.role == RefRole::Value
             && ( r.qualifier[0] == kValueRefSlotFactScope || r.qualifier[0] == kValueRefSlotParamScope || r.qualifier[0] == kValueRefRegParamScope ) )
        || ( r.role == RefRole::Through && r.qualifier[0] == kValueRefSlotCallScope );
}

inline void buildShadowKey( std::string& key, std::uint32_t fromSymbol, std::string_view name )
{
    key.clear();
    char digits[ 10 ];
    int  digitCount = 0;
    do { digits[ digitCount++ ] = char( '0' + fromSymbol % 10u ); fromSymbol /= 10u; } while( fromSymbol != 0u );
    while( digitCount > 0 ) { key.push_back( digits[ --digitCount ] ); }
    key.push_back( '#' );
    key.append( name );
}

// the per-reference verdict: true ⇒ the site sits inside a block where a declared local shadows the name
// (and every guard in the contract above holds). `key` is the caller's reused buffer.
inline bool shadowSuppressedSite( const Reference& r, const ShadowEvidence& ev, std::string& key )
{
    if( r.fromSymbol == kNoNode || r.isInherit || r.isDocLink || r.isCompose )
    {
        return false;
    }
    if( r.role != RefRole::Call && r.role != RefRole::Read && r.role != RefRole::Write )
    {
        return false;   // import/extends sites are never local-variable uses; role=macro stays (see contract)
    }
    if( r.recv != RecvKind::None || !r.qualifier.empty() )
    {
        return false;   // a receiver- or scope-qualified name can never resolve to a plain local
    }
    // JAVA IS REFUSED OUTRIGHT, and this arm is load-bearing rather than defensive. This pass is
    // C++/ObjC evidence: it deletes a reference because a declared local of that name shadows it at
    // that byte. Java's VarDecl records (ingest_binds.h captureJavaShadowDecls) exist for one
    // unrelated consumer — the JavaTypeCandidate receiver proof for issue #74 — and Java call sites
    // carry no classified receiver, so `b.name(name)` inside `make( Builder b, String name )` reaches
    // here as a BARE call whose name a parameter declares, and lost its call edge and its `--uses`
    // row. The refusal is not a heuristic: Java has no free functions and no callable locals, so a
    // Java call NEVER resolves to a local and there is nothing here to prevent. Python keeps its
    // veto-only evidence at an empty span for the same reason (ingest_binds.h, the note above
    // capturePythonParamShadowDecls); Java needs real spans, so the refusal lives at the consumer.
    if( r.lang == Lang::Java )
    {
        return false;
    }
    // ORDER IS A COST DECISION, not a semantic one: all four guards are pure predicates ANDed together, so
    // any order gives the same verdict — but they are not equally selective. `varSpans` is keyed on
    // "<callingSymbol>#<name>" and hits only when THIS caller declares a local of exactly this name (rare);
    // `defNames` hits whenever ANY indexed symbol anywhere carries the name (common). Testing the common one
    // first spent a second string hash on nearly every reference in the corpus to learn nothing. The
    // selective test now runs first, and the name-collision gate is asked only of the sites that got past it.
    buildShadowKey( key, r.fromSymbol, r.calleeName );
    const auto it = ev.varSpans.find( key );
    if( it == ev.varSpans.end() || ev.fnBindKeys.find( key ) != ev.fnBindKeys.end() )
    {
        return false;   // no declared local — or a fn-binding var, whose references must survive
    }
    if( ev.defNames.find( r.calleeName ) == ev.defNames.end() )
    {
        return false;   // no indexed symbol carries the name — nothing to falsely attribute to
    }
    for( const auto& [ spanStart, spanEnd ] : it->second )   // VarSpan is an aggregate — the binding reads as before
    {
        if( r.startByte >= spanStart && r.startByte < spanEnd )
        {
            return true;
        }
    }
    return false;
}

inline void suppressShadowedReferences( IngestResult& ing )
{
    PROFILE_SCOPE_DESCRIBE( "model/shadow: total" );
    ShadowEvidence ev;
    std::string    key;
    for( const Binding& b : ing.bindings )
    {
        if( b.fromSymbol == kNoNode || b.var.empty() )
        {
            continue;   // file-scope facts bind nothing here — suppression never reaches past a function
        }
        const bool isVar = ( b.kind == LocalBindKind::VarDecl );
        if( !isVar && b.kind != LocalBindKind::FnDecl && b.kind != LocalBindKind::FnAssign )
        {
            continue;   // Type bindings can come from plain assignments — declaration evidence only
        }
        buildShadowKey( key, b.fromSymbol, b.var );
        if( isVar )
        {
            // braced push_back, NOT emplace_back( a, b ): a PARENTHESIZED aggregate initialization needs
            // P0960, which Clang gained in 20 — CI's Xcode 15.4 toolchain would reject it. Same reason
            // ingest.cpp's LexPair rows are braced; see the note beside that push_back.
            ev.varSpans[ key ].push_back( VarSpan{ b.spanStart, b.spanEnd } );
        }
        else
        {
            ev.fnBindKeys.try_emplace( key, 1 );
        }
    }
    if( ev.varSpans.empty() )
    {
        return;   // VarDecl-free corpus (no captured C++/ObjC local declarations): byte-identical output
    }
    {
        PROFILE_SCOPE_DESCRIBE( "model/shadow: defNames set (one hash insert per symbol)" );
        for( const Symbol& s : ing.symbols )   // the collision gate: some indexed symbol must carry the name
        {
            ev.defNames.try_emplace( s.name, 1 );
        }
    }
    {
        PROFILE_SCOPE_DESCRIBE( "model/shadow: erase_if over references" );
        std::erase_if( ing.references, [ & ]( const Reference& r ) { return shadowSuppressedSite( r, ev, key ); } );
    }
}

// ONE file's symbol-id bucket, and the whole index. Named so the ten independent reimplementations of this
// shape share ONE type rather than ten spellings of `std::vector<std::vector<NodeId>>`.
//
// N=8 IS A MEASURED KNEE, not p90. Per-bucket cardinality over the two census corpora (1 103 files here,
// 2 376 on the 43K-symbol validation corpus), as coverage of all buckets against the instance size
// rw::svector<NodeId,N> costs:
//
//     N :   1     2     4     6     8    12    16    24    32     bytes: 16 16 24 32 40 56 72 104 136
//   here: 17.3  35.9  54.4  66.7  76.4  84.6  88.0  93.9  96.4
//   cr48: 13.9  18.4  27.7  35.9  45.1  62.0  71.3  82.2  88.3
//
// Marginal coverage per byte of instance growth falls 2→4→6→8 as 2.31 / 1.54 / 1.21 here and 1.16 / 1.04 /
// 1.15 there, then collapses to 0.51 and 0.58 at the next step — the same cliff shape the census found for
// clones' type-3 buckets. N=8 is also the LARGEST N whose total footprint (this array + the heap blocks the
// spilled buckets still take + allocator per-block overhead) does not exceed what the plain
// std::vector<std::vector<NodeId>> costs today on EITHER corpus: ~75 KB vs ~80 KB here, ~276 KB vs ~265 KB
// there, where N=16 is ~100 KB and ~323 KB. p90 (18 here, 37 there) would have bought 3-9 more points of
// coverage for 2-3x the memory.
using FileSymbols   = rw::SmallVec<NodeId, 8>;
using SymbolsByFile = std::vector<FileSymbols>;

// THE per-file symbol index every span- or line-based lookup starts from: bucket the symbol ids by file, then
// sort each bucket. `keep` selects which symbols enter it and `less` orders each bucket, because those two are
// the ONLY things that differ between callers — flipimpact.h wants every symbol in line order (the host of a
// `#if` region), ensemble.h wants only body-carrying functions in byte order (the owner of a lint finding's
// span). Both were written independently and a --quality-delta pass found them as a 159-token clone pair,
// correctly: same shape, different filter and key. Parameterizing exactly those two is what makes this ONE
// function rather than a family of near-copies, and it lives here because `IngestResult` does.
// Deterministic by construction: file buckets are indexed, never hashed, and `symbols[i].id == i` so the
// pre-sort sequence in every bucket is ascending id regardless of which caller built it.
//
// ON `less` AND TOTAL ORDERS. Four of the callers folded in here (atoms.h's OwnerIndex, search.h's grep
// index, and main.cpp's --lint dedup and --match/--lint index) compare bare `sigStartByte` with no
// tie-break, which is NOT a total order: two symbols sharing a start offset in one file may land either
// way, and std::sort is not stable. That predates this consolidation and is deliberately NOT changed here —
// giving them a tie-break would reorder ties and move emitted bytes, which a container change must not do.
// Every such sort is still deterministic run-to-run: same input sequence, same comparator, same std::sort.
template<typename Keep, typename Less>
inline SymbolsByFile symbolsByFile( const IngestResult& ing, Keep keep, Less less )
{
    SymbolsByFile byFile( ing.files.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( s.fileId < byFile.size() && keep( s ) )
        {
            byFile[ s.fileId ].push_back( s.id );
        }
    }
    for( FileSymbols& bucket : byFile )
    {
        std::sort( bucket.begin(), bucket.end(), less );
    }
    return byFile;
}

// The id-ordered form: every kept symbol, buckets left in ascending id order. `symbols[i].id == i` means the
// scan above already produces that order, so this spells "no reordering wanted" without paying a sort — the
// shape six of the ten folded-in call sites had written out by hand.
template<typename Keep>
inline SymbolsByFile symbolsByFileInIdOrder( const IngestResult& ing, Keep keep )
{
    SymbolsByFile byFile( ing.files.size() );
    for( const Symbol& s : ing.symbols )
    {
        if( s.fileId < byFile.size() && keep( s ) )
        {
            byFile[ s.fileId ].push_back( s.id );
        }
    }
    return byFile;
}

}   // namespace rw
