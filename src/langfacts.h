#pragma once
// langfacts.h — the per-language FACTS table (the "6c" step of the language-specific layer): one row per `Lang`, one column
// per fact that shared code reads about a language, instead of a `== Lang::X` compare at the point of use.
//
// WHY A TABLE. A shared file that says `if( r.lang == Lang::Ruby )` hides the reason (what does Ruby have that the others do not?)
// and hides the next language that has it. A column is named for its REASON, reads down the table beside every other language,
// and a new language is one more row instead of an edit at every site. CONTRIBUTING's rule applies: a new `== Lang::X` in a shared
// file is a red flag, and test/langidentitycheck.sh's ratchet counts them.
//
// THE RULES.
//   * A column is a fact about a language, decided per language: a bool, an enum or a small list. Never a function.
//   * A column is named for its reason (`overloadSignatures`), never for a language (`isTypeScript`) or a family (`isCFamily`).
//   * An OPTIONAL column defaults to the conservative answer: `false` = "the shared path", so a new language that says nothing
//     gets the behaviour every other language without the fact gets.
//   * A REQUIRED column is typed `Must<T>`: it has no default constructor, so a row that leaves it out of its designated
//     initializer does not compile. Today only the row's own key (`lang`) is required; a column every new language must decide
//     (and cannot sensibly default) is declared `Must<...>` the day it is added.
//   * The table is `std::array<LangFacts, kLangCount>`: a missing row is a compile error (the unwritten element has no `lang`),
//     and `firstMisorderedRow` proves each row sits at its own `Lang` index, so langFacts(l) is one load.
//   * Reading a language past the enum (a corrupt cache byte) answers the all-default row, like the other enum-indexed tables.
//
// WHAT IS NOT HERE. Hooks (an algorithm that differs over the tree or the graph) and family-owned sparse rows live beside their
// shared handler (reports/lang-specific-layer.md §2); this header holds only the values. It includes nothing but model.h, so both
// translation units (ingest.cpp and main.cpp) can read it.

#include "model.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <span>
#include <string_view>

namespace rw
{

/// A required column of a LangFacts row: no default constructor, so a designated initializer that omits it fails to compile.
template<class T>
struct Must
{
    T value;
    constexpr Must( T v ) noexcept : value( v ) {}   // implicit on purpose: `.lang = Lang::Cpp` spells the row's key
    constexpr operator T() const noexcept { return value; }
};

/// Lane qn-input: how a WRITTEN seed prefix names this language's module (graph.h resolveAllByWrittenSpelling). FilePath: the
/// prefix's head names directories or the file stem of the definition's path, verbatim (`-` read as `_`), and the module — the
/// one-entity identity — is the file. PackageDir: the same reading, but the module is the directory (Go: a package is its
/// directory, so build-tag twins are one entity). ConstantPath: FilePath, and a CamelCase segment also reads as its snake_case
/// file or directory name (Ruby's loader convention: `Shop::Cart` in shop/cart.rb). SourceChain: no path is read; the
/// definition's enclosing namespaces and classes plus its written qualifier, off the source, are the module (C, C++). DirsOnly:
/// FilePath without the stem — a file is not a namespace (Swift, Kotlin, Java, C#: `Foo.bar` never names a top-level `bar` in Foo.swift).
enum class WrittenModuleRule : std::uint8_t
{
    FilePath,
    PackageDir,
    ConstantPath,
    SourceChain,
    DirsOnly,
};

/// Lane fc2-lego-extparent: which of the file's own import facts can show that an extends / implements clause names a type
/// from OUTSIDE the tree (graph.h baseBoundOutsideTree), so no in-tree namesake is listed as its base. None: the language's
/// imports cannot rule one out here (a C# `using`, a Swift `import`, a C++ include: the clause keeps its by-name edge).
enum class BaseImportEvidence : std::uint8_t
{
    None,           // no import fact read
    PythonImport,   // `from ext import Base` / `import ext` + `ext.Base`: the Phase-5 import verdict ('x' = every binding outside)
    JsImport,       // `import { Base } from 'lib'` (the import tables' External outcome) / `lib.Base` (the qualifier verdict)
    RustUse,        // `use ext::Base;` whose first segment is not crate/self/super/an in-tree module (FE-A rustOutsideUse)
    JvmImport,      // `import org.ext.Base` / `extends org.ext.Base` of a package the tree does not declare
};

/// What shared code asks about a language. Every optional column is false for a language that says nothing.
struct LangFacts
{
    Must<Lang> lang;   // the row's own key — the order check below proves row i is Lang(i)

    /// TypeScript: a bodyless function, or a bodyless method that is not an interface / abstract / ambient contract, is an OVERLOAD
    /// SIGNATURE: the language requires the implementation to follow it in the same declaration list, so it joins that implementation
    /// as one definition (defattrib.h). In Java, Go, Rust, Swift or C# a bodyless member is a contract and a definition of its own.
    bool overloadSignatures = false;

    /// Ruby: an instance receiver resolves through the language's own class-object lookup (the singleton / instance sides of a
    /// class, a typed or closed receiver, `self` through included modules) before the shared receiver rules (graph.h).
    bool classObjectLookup = false;

    /// Ruby: a method's ancestors include mixed-in modules, so a base-class walk climbs the mixin-aware chain rather than the
    /// declared inheritance chain (graph.h).
    bool mixinAncestry = false;

    /// Ruby: an element access `recv[ k ]` whose receiver the shape rules cannot classify (a call result, a richer expression) is
    /// still recorded as a site on that receiver, because the typing walk may type it later (`Report.new[ :x ]`). Python and the
    /// rest record nothing for such a receiver (ingest_binds.h subscriptOperatorRef).
    bool keepsUnshapedSubscript = false;

    /// Ruby: a constant receiver is a path as written (`Outer::Cache`), kept on the site so the resolver scopes it; a name has no
    /// other spelling in the languages without constant paths (ingest_binds.h subscriptOperatorRef).
    bool constantPathReceiver = false;

    /// Elixir: `quote` bodies are inert syntax (an AST being built, not code that runs), so a call candidate inside one is a
    /// declined fact, never an edge (ingest_sidecap.h; the predicate itself lives in ingest_elixir.h).
    bool hasInertQuoteRegions = false;

    /// C++: defect-shape's whole-tree input is the macro-name set, and a changed C++ file (a .h reads as C++) can only be
    /// judged against the base's whole set. A changed C or Objective-C file does not need it, by today's behaviour
    /// (verbs_quality.h; pinned by test/qddegradecheck.sh (E3)).
    bool defectShapeNeedsMacroSet = false;

    /// Rust: a trait's bodyless method signature is no definition the index keeps (only a bodied default is), so a trait's contract
    /// cannot be read off its members. The dispatch tier (ifacedispatch.h) takes the implementors' methods of the called name without
    /// it, and leaves a standard-member name (`clone`, `iter`: graph.h StdMemberGate) to the name tiers as before.
    bool contractSignaturesUnindexed = false;

    /// Rust: a type's methods for a trait sit in that trait's own `impl T for X` block, apart from its inherent `impl X` methods,
    /// and a call through `dyn T` / `impl T` / a `T` bound reaches only the former and T's defaults (ingest_relations.h records each
    /// trait impl block as an ImplBlock binding; ifacedispatch.h keeps the candidates inside one).
    bool traitImplBlocks = false;

    /// Go, TypeScript, JavaScript: a type conforms to an interface (TS: to any object type) by its members alone, with no clause
    /// naming it — an object literal, a structurally matching class — so an implements list is never the whole set, and one
    /// candidate is never the only implementor (ifacedispatch.h: a list of two or more is still declined, as a floor).
    bool structuralTyping = false;

    /// Java: a lambda or a method reference implements any interface with exactly one abstract method, with no class the index
    /// keeps, so such an interface's implementors list is open (ifacedispatch.h). Kotlin opts in per interface (`fun interface`,
    /// recorded at ingest as an anonymous implementor) and, below, through Java.
    bool samLambdas = false;

    /// Kotlin: a Java file passes a lambda to ANY Kotlin interface with one abstract method (in bytecode it is a plain Java
    /// interface, `fun interface` or not), so with a samLambdas-language file in the tree such an interface's implementors list is
    /// open too (ifacedispatch.h). A Kotlin-only tree is unchanged.
    bool samFromJavaLambdas = false;

    /// Kotlin: `run`, `let`, `apply`, `also` and `with` are stdlib scope functions, and a call to one with a trailing lambda is
    /// that function, never a Java or other-language method of the same name (graph.h FE-A, kotlinScopeDecide; the call-site fact
    /// is captured in ingest_sidecap.h).
    bool trailingLambdaScopeFns = false;

    /// Python: unittest, Django and pytest call setUp, tearDown, setup_method and the other test-framework hooks themselves
    /// (quality.h pythonFrameworkInvokedSymbol).
    bool frameworkEntryHooks = false;

    /// Python: a closure inside a method can call `self.hook()` / `cls.hook()` for its host, so a receiver-bound call dispatches
    /// through the host's overrides (quality.h pythonReceiverParameters, pythonDispatchRequests). A separate fact from the hooks.
    bool closureReceiverDispatch = false;

    /// Kotlin: an `interface` is a class_declaration like a class (queries/kotlin/tags.scm: "both land here as @definition.class"),
    /// so the symbol's kind cannot tell the two apart; shared code that needs an interface (ifacedispatch.h's lambda test) reads a
    /// class of such a language as a possible one.
    bool interfaceReadsAsClass = false;

    /// Java: the member names that never count toward an interface's single abstract method (JLS 9.8: a public method of
    /// java.lang.Object an interface redeclares, as java.util.Comparator does equals). Names only; an overload is still ignored,
    /// which can only open more lists. Empty for a language with no such rule.
    std::span<const std::string_view> samIgnoredMembers = {};

    /// Java, Kotlin: an expression can implement an interface or extend a class anonymously (`new T() { … }`, `object : T { … }`;
    /// Kotlin's `fun interface` lets a lambda do it), recorded at ingest as an ImplBlock binding with no implementor name, which
    /// opens that type's implementors list (ingest_binds.h anonymousImplementorOf).
    bool anonymousImplementors = false;

    /// Markdown: a link targets a section, so shared graph code treats this language's sections as link targets (graph.h).
    bool linkSections = false;

    /// C, C++, Objective-C: a function span the parser reports DIRECTLY inside a function's span is read as a misread (htop's
    /// `else if (…) {` inside a macro-heavy body read as a function named `if`), never a closure (src/closures.h; this fact
    /// decides only the closure relation, no symbol or edge). A lambda or a block is anonymous, and a C++ local class's
    /// methods sit inside the class's scope, not directly in the function, so neither is a closure either way.
    bool noNestedNamedFunctions = false;

    /// C++: a `using X = std::shared_ptr<I>;` / `typedef std::unique_ptr<I> X;` alias (the std smart pointers whose `->` reaches
    /// their first template argument, ingest_relations.h kStdSmartPointers) types a member written X as I for `->` alone, like a
    /// member written `std::shared_ptr<I>` itself (lane iface-peel; the alias record carries the pointee, graph.h
    /// buildFieldNarrowTables follows a bounded alias chain). A `.` call on such a member reaches the smart pointer, never I.
    bool aliasPeelsSmartPointer = false;

    /// Rust: a function whose declared result is a trait object or an opaque type (`&dyn T`, `Box<dyn T>`, `impl T`) types the
    /// local its call initialises as SOME implementor of T, exactly as a local written `let x: &dyn T` (lane iface-peel; the
    /// dispatch tier, ifacedispatch.h, then declines the call on it or proves its one implementor). Only through the call's own
    /// ONE proven edge (graph.h typeCallResults); a by-name callee types nothing, and a generic `-> T` is never read.
    bool returnTypedDispatchLet = false;

    /// Rust: a construction is a call to the type's conventional constructor METHOD (`T::new( … )`), not to the type itself, so
    /// --affected's class-new backstop (testmap.h classNewTestRows) reads a call to this method of a class as building it. Empty =
    /// the language constructs by calling the class (`new T(` JS/TS/Java/C#, `T(` Python/Kotlin/C++), which needs no column.
    std::string_view constructorMethod = {};

    /// TypeScript / JavaScript: a construction (`new X()`, `new N.X()`) builds whatever its import binding resolves to, so --affected's
    /// class-new row takes its l= only from a construction the import resolver pins to the reached class (testmap.h ClassNewJsBinds,
    /// graph.h pinJsImport), never from the written name. The other languages keep the name test (classNewCallNames).
    bool importBoundConstruction = false;

    /// QUALNAME-1 (src/memberowner.h): the separator a member row prints between its owner and its name, as the language itself
    /// spells a member: `Owner::name` in C, C++, Rust and PHP (scope resolution; PHP methods store no scope today, so none prints), `Owner#name` in Ruby (the instance-method form
    /// RDoc uses; a `def self.x` singleton prints `#` too, since the index does not tell the two apart), `Owner.name` elsewhere.
    /// Every spelling is one the selectors resolve (graph.h resolveAllByScopeQualified / resolveAllByDottedScope).
    std::string_view memberSeparator = ".";

    /// Kotlin, C#: a method name may be overloaded and the index keeps no call-comparable arity for it (ingest_metrics.h
    /// cc_paramShape's language gate; Java has one), so the dispatch tier cannot tell an override from an overload by its
    /// parameter count (receiverevidence.h overloadedAbove; lane L6, folded from a `Lang::` compare in train 33).
    bool overloadsWithoutArity = false;

    /// The import facts that can prove a base clause names an outside type (BaseImportEvidence; graph.h baseBoundOutsideTree).
    BaseImportEvidence baseImportEvidence = BaseImportEvidence::None;

    /// C, C++, Objective-C: a file sees every file its #includes reach, transitively (a header's own #include is in force in
    /// the includer), so the by-name hedge's import rule (pathgaps.h NamesakeRule, K5 rule 2b) follows the include closure;
    /// every other language's import names one module, so that rule reads the direct import edge only.
    bool transitiveIncludes = false;

    /// JavaScript, TypeScript: a bare call by a name whose binding is WRITTEN in its scope (`Eng = Foo; new Eng()`) is undecided —
    /// it names neither the declaration nor a same-spelled definition — so it binds nothing (FC3: the LocalBindKind::JsRebind
    /// records of ingest_jsimports.h captureJsRebindFacts, read by graph.h buildGraph).
    bool writtenBindingUndecided = false;

    /// How a written seed prefix names this language's module (WrittenModuleRule above).
    WrittenModuleRule writtenModule = WrittenModuleRule::FilePath;

    /// TypeScript: a `namespace` / `module` body holds members the index stores no owner for (the Namespace binds, model.h), so the
    /// written-spelling tier (graph.h resolveAllByWrittenSpelling) reads the body's name off those binds. The other languages' owners are symbols.
    bool namespaceBodies = false;

    /// TypeScript, JavaScript: an object literal's members are indexed with no owner (an unnamed container), so the written-spelling
    /// tier treats such a member as a candidate whose object name is unknown (graph.h resolveAllByWrittenSpelling).
    bool objectLiteralMembers = false;

    /// The keyword a method names its own instance by, as a receiver chain's ROOT spells it (lane receiver-fixes: a `this.f.m()` /
    /// `self.f.m()` field receiver, receiverevidence.h foreignFieldOwner / dispatchReceiverOf). `this` unless the language says
    /// otherwise; elsewhere the same text is an ordinary name (a JS `const self = …`, a Python local `this`) that proves nothing.
    std::string_view instanceReceiver = "this";

    /// TypeScript, JavaScript: a class member is indexed with no Symbol::scope; its owner is the one class whose body holds it
    /// (graph.h containedOwnersOf), the rule the written-spelling tier binds `Class.method` by and memberowner.h prints n= by.
    bool containmentOwners = false;

    /// Python: a leading underscore on a module-level name, or on a module/package path component, marks an internal interface (PEP 8),
    /// the language's only stand-in for the `static` linkage C/C++ spells; --dead-code's test-only rows read it (quality.h
    /// underscorePrivateDef). Elsewhere a leading underscore is a naming habit that hides nothing.
    bool underscorePrivacy = false;

    /// C, C++, Objective-C: the `static` keyword on a free function in its signature is INTERNAL LINKAGE (the storage class), the one
    /// internal-interface mark --dead-code's rows rest on (quality.h symbolHasStaticLinkage). Elsewhere the word is not that keyword: a
    /// Python parameter `static=False`, a TypeScript literal type `'static'`, a Rust `'static` lifetime, a string default all spell it
    /// without meaning linkage, and a function in those languages carries no `static` storage class at all.
    bool staticLinkage = false;

    /// Lua: a line starting `--` is a comment (elsewhere it is a decrement, `--n;`). hopbody.h isStatementLine reads it when it
    /// counts a thin delegator's statement lines (lane path-hop-body-fix1, review F3).
    bool dashDashComments = false;

    /// Python: a string literal as a function's FIRST statement is its docstring, not code; hopbody.h bodyStatementLines does not
    /// count it (lane path-hop-body-fix1, review F4: a documented one-line delegator is still thin).
    bool leadingDocstring = false;
};

/// java.lang.Object's public methods an interface may redeclare abstract (LangFacts::samIgnoredMembers).
inline constexpr std::array<std::string_view, 3> kJavaObjectMethods = { "equals", "hashCode", "toString" };

/// The rows, one per Lang in enum order. A language says only the facts it has.
inline constexpr std::array<LangFacts, kLangCount> kLangFacts = { {
    { .lang = Lang::Cpp, .defectShapeNeedsMacroSet = true, .noNestedNamedFunctions = true, .aliasPeelsSmartPointer = true, .memberSeparator = "::",
      .transitiveIncludes = true, .writtenModule = WrittenModuleRule::SourceChain, .staticLinkage = true },
    { .lang = Lang::Python, .frameworkEntryHooks = true, .closureReceiverDispatch = true, .baseImportEvidence = BaseImportEvidence::PythonImport,
      .instanceReceiver = "self", .underscorePrivacy = true, .leadingDocstring = true },
    { .lang = Lang::TypeScript, .overloadSignatures = true, .structuralTyping = true, .importBoundConstruction = true, .baseImportEvidence = BaseImportEvidence::JsImport,
      .writtenBindingUndecided = true, .namespaceBodies = true, .objectLiteralMembers = true, .containmentOwners = true },
    { .lang = Lang::Go, .structuralTyping = true, .writtenModule = WrittenModuleRule::PackageDir },
    { .lang = Lang::Rust, .contractSignaturesUnindexed = true, .traitImplBlocks = true, .returnTypedDispatchLet = true, .constructorMethod = "new", .memberSeparator = "::", .baseImportEvidence = BaseImportEvidence::RustUse,
      .instanceReceiver = "self" },
    { .lang = Lang::Swift, .writtenModule = WrittenModuleRule::DirsOnly, .instanceReceiver = "self" },
    { .lang = Lang::ObjC, .noNestedNamedFunctions = true, .transitiveIncludes = true, .staticLinkage = true },
    { .lang = Lang::Markdown, .linkSections = true },
    { .lang = Lang::JavaScript, .structuralTyping = true, .importBoundConstruction = true, .baseImportEvidence = BaseImportEvidence::JsImport,
      .writtenBindingUndecided = true, .objectLiteralMembers = true, .containmentOwners = true },
    { .lang = Lang::Bash },
    { .lang = Lang::Java, .samLambdas = true, .samIgnoredMembers = kJavaObjectMethods, .anonymousImplementors = true, .baseImportEvidence = BaseImportEvidence::JvmImport,
      .writtenModule = WrittenModuleRule::DirsOnly },
    { .lang = Lang::Ruby, .classObjectLookup = true, .mixinAncestry = true, .keepsUnshapedSubscript = true, .constantPathReceiver = true,
      .memberSeparator = "#", .writtenModule = WrittenModuleRule::ConstantPath, .instanceReceiver = "self" },
    { .lang = Lang::Unknown },
    { .lang = Lang::Json },
    { .lang = Lang::CSharp, .overloadsWithoutArity = true, .writtenModule = WrittenModuleRule::DirsOnly },
    { .lang = Lang::C, .noNestedNamedFunctions = true, .memberSeparator = "::", .transitiveIncludes = true, .writtenModule = WrittenModuleRule::SourceChain,
      .staticLinkage = true },
    { .lang = Lang::Toml },
    { .lang = Lang::Yaml },
    { .lang = Lang::Php, .memberSeparator = "::" },
    { .lang = Lang::Lua, .dashDashComments = true },
    { .lang = Lang::Elixir, .hasInertQuoteRegions = true },
    { .lang = Lang::Dart },
    { .lang = Lang::Kotlin, .samFromJavaLambdas = true, .trailingLambdaScopeFns = true, .interfaceReadsAsClass = true, .anonymousImplementors = true, .overloadsWithoutArity = true,
      .baseImportEvidence = BaseImportEvidence::JvmImport, .writtenModule = WrittenModuleRule::DirsOnly },
    { .lang = Lang::GDScript },
    { .lang = Lang::Clojure },
} };

/// The index of the first row that is not at its own Lang index, or the table size when every row is.
template<std::size_t N>
constexpr std::size_t firstMisorderedRow( const std::array<LangFacts, N>& table ) noexcept
{
    const auto misplaced = std::ranges::find_if( table, [ expected = std::size_t( 0 ) ]( const LangFacts& row ) mutable
                                                 { return static_cast<std::size_t>( static_cast<Lang>( row.lang ) ) != expected++; } );
    return static_cast<std::size_t>( misplaced - table.begin() );
}
static_assert( firstMisorderedRow( kLangFacts ) == kLangCount, "kLangFacts: one row per Lang, in enum order — the compiler's note 'evaluates to A == B' gives the first row out of place as A (B = kLangCount)" );

/// The row of `l`; a value past the enum (a corrupt cache byte) reads the all-default row.
inline constexpr LangFacts langFacts( Lang l ) noexcept
{
    return enumTableAt( kLangFacts, l, LangFacts { .lang = Lang::Unknown } );
}

}   // namespace rw
