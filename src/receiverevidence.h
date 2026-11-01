#pragma once
// receiverevidence.h — FE-B (test/receiverevidencecheck.sh): what proves a call's RECEIVER, and what does not.
//
// A member call `x.m()` (or, where the receiver is implicit, a bare `m()`) used to bind to every in-repo definition
// spelled `m` that the name ladder reached, and the answer showed each such row as a plain edge — a confident claim
// with nothing behind it but the name. This header holds the two halves of the fix:
//
//   1. ReceiverEvidence::narrow — a RESOLVE rule for receivers the source types: `this`/`self`/`cls` inside a class (and
//      the language's base-class receiver, isSuperRoot, through the bases only), a parameter or local whose class is
//      written (a TS/Python/Go annotation, a Go method receiver, a JS `new Foo()` / Python `Foo()` / Go `Foo{}` initializer), a constructed receiver
//      (`new Foo().m()`), a class-name receiver (`Foo.m()`), and a chain of fields whose classes are stated
//      (`this.bucket = new Schemas()`, Python `self.x = Foo()`, a Go struct field, a Go EMBEDDED field whose methods
//      are promoted). A hit is the call's whole answer, exactly like Rule 2. Ruby's own method lookup (mixins, typed and
//      class receivers) is deliberately NOT modelled here: Ruby keeps only the language-neutral proof below.
//   2. ReceiverEvidence::ladderProves — for a call the rules above did not answer, which name-ladder candidates the
//      language's own lookup can PROVE: an implicit receiver's own class and its bases, a free function in scope, a
//      definition in the module a receiver alias names. A call left with no proven candidate is NAME-ONLY: its rows
//      are kept, marked via="name" on every surface (graph.h Graph::outNameOnly), never dropped and never proven.
//
// What it does NOT do: infer a function's return type (`s = self.get_screen(); s.refresh()`), follow a property, or type
// a value that crossed a call boundary. Those receivers stay name-only — the honest answer, not a guess.

#include "infra/sortutil.h"   // svLess: the explicit byte order the operatorResult sort takes (portablebuildcheck #6)
#include "langfacts.h"   // langFacts(l).overloadsWithoutArity — overloadedAbove's language column
#include "model.h"
#include "resolve.h"   // includerDir; HashMap / SmallVec through it; extent::inSet (extentsuspect.h) through it
#include "smallvec.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rw
{

// The languages whose name-ladder rows the hedge covers. Every other language keeps its ladder unchanged (a disclosed
// floor in test/receiverevidencecheck.sh: Objective-C, PHP, Lua, Zig, Dart, Elixir, Scala, Bash and the rest).
inline bool receiverHedgeLang( Lang l ) noexcept
{
    switch( l )
    {
        case Lang::JavaScript: case Lang::TypeScript: case Lang::Python: case Lang::Go: case Lang::Rust: case Lang::C:
        case Lang::Cpp: case Lang::Java: case Lang::Kotlin: case Lang::CSharp: case Lang::Swift: case Lang::Ruby:
            return true;
        default:
            return false;
    }
}

// FE-B: each Go file's package import paths, built by graph.h collectGoModules — the nearest go.mod's module path plus the
// directory below it, and the path a LOCAL `replace L => ./D` gives a file under D (L plus the directory below D). A
// module-alias call proves a candidate by one of these paths EXACTLY. The directory-tail rule is left only for a candidate
// with no path when no in-tree file carries the import path either (a tree with no module facts for it at all).
struct GoPackagePaths
{
    std::vector<std::string>   nearest;    // fileId → "" when no go.mod with a module line sits at or above the file
    std::vector<std::string>   replaced;   // fileId → "" when no local replace maps the file's directory
    HashMap<std::string, char> known;      // every non-empty path in either table

    // file `f`'s entry in `table` ("" when none)
    static std::string_view pathIn( const std::vector<std::string>& table, std::uint32_t f ) noexcept
    {
        return f < table.size() ? std::string_view( table[ f ] ) : std::string_view{};
    }
    bool hasPath( std::uint32_t f ) const noexcept
    {
        return !pathIn( nearest, f ).empty() || !pathIn( replaced, f ).empty();
    }
    // does `path` name file `f`'s package exactly
    bool names( std::uint32_t f, std::string_view path ) const noexcept
    {
        return !path.empty() && ( pathIn( nearest, f ) == path || pathIn( replaced, f ) == path );
    }
    void note( std::vector<std::string>& table, std::uint32_t f, std::string path )
    {
        EXPECTS( f < table.size(), "collectGoModules sizes both tables to ing.files" );
        if( !path.empty() )
        {
            known.try_emplace( path, '\0' );
        }
        table[ f ] = std::move( path );
    }
};

// The languages where a bare `m()` inside a method is an implicit `this.m()` (or reaches a free/top-level function).
inline bool implicitReceiverLang( Lang l ) noexcept
{
    return l == Lang::Java || l == Lang::Kotlin || l == Lang::CSharp || l == Lang::Swift || l == Lang::Cpp || l == Lang::Ruby;
}

// the languages where a call written on a receiver reaches a function only as a METHOD (or through a module alias): a
// free function is never what `x.f()` calls. JS/TS (an object property may hold one), Kotlin (an extension function is a
// top-level `fun T.f()`) and C (a function-pointer field) are left out.
inline bool memberNeverReachesFreeFunction( Lang l ) noexcept
{
    return l == Lang::Python || l == Lang::Go || l == Lang::Cpp || l == Lang::Rust || l == Lang::Ruby || l == Lang::Java
        || l == Lang::CSharp || l == Lang::Swift;
}

// a call through a module alias (`pkg.F()`) reaches the module's package-level functions only, never a method: Go, where a
// package qualifier never names a receiver (train 29 call-result-typing, review decision (b): nfpm's `nfpm.Get( … )` beside
// `( *Config ).Get`). A local spelled like the import hides it before this is asked (graph.h ladderProves).
inline bool moduleCallReachesFunctionsOnly( Lang l ) noexcept
{
    switch( l )
    {
        case Lang::Go: return true;
        default:       return false;
    }
}

// (L) the languages whose own receiver rule (Rule 1) answers `self.m()`, so receiver evidence adds only a LOCAL whose class a
// binding states and the field paths below it or below `self` (ReceiverEvidence::narrowTypedLocal): Rust, whose locals are
// typed by the call results graph.h's resolve loop records (train 29) and, since rust-receivers, by a written parameter /
// `let x: T` / `let x = T { .. }` / `T::default()` type and a struct field's written type. Not typed (stated floors): a
// generic `T: Bound`, `dyn Trait` / `impl Trait`, a trait written as a type, a value behind Option / Result / Rc / Arc /
// RefCell / Cell / Mutex / RwLock, a tuple-struct field (`self.0`), a pattern other than a plain name.
inline bool receiverLocalsOnly( Lang l ) noexcept
{
    switch( l )
    {
        case Lang::Rust: return true;
        default:         return false;
    }
}

// (L) which members a call-result-typed local's CLASS owns (fix round 1: the typed fact carries the class's id, and a member
// call on the local reaches that class's own members, never a same-named class's): Lexical — the class whose span holds the
// member (Java, Kotlin, TS; a member outside every class, a Kotlin extension, belongs to the class's own file); PackageDir —
// Go, whose methods sit beside the type in its package's directory; FileOrUnique — Rust, whose `impl` blocks sit in the
// type's own file, or anywhere when no other in-tree type shares its name.
enum class MemberOwnerRule : std::uint8_t { Lexical, PackageDir, FileOrUnique };
inline MemberOwnerRule memberOwnerRuleOf( Lang l ) noexcept
{
    switch( l )
    {
        case Lang::Go:   return MemberOwnerRule::PackageDir;
        case Lang::Rust: return MemberOwnerRule::FileOrUnique;
        default:         return MemberOwnerRule::Lexical;
    }
}

// Lane h1-annot: how a written type's QUALIFIER (`pkg.T`, `mod.T`, `ns.T<…>`: the capture's RecvType / MemberType importedName)
// is checked before its final segment may name an in-tree class. GoPackage — the import path names an in-tree package that
// defines T (CallResultTypes::goQualifiedClass). FileImport — Python and TS: the qualifier's ROOT is bound by the file's
// imports to an in-tree module, package or relative path (graph.h buildQualifierVerdicts), or, bound by no import, names an
// in-tree class (`Outer.Inner`) or a TS namespace; T itself is then read by its final segment as before. None — a family whose
// capture writes no qualifier: the written type proves nothing.
enum class WrittenQualifierRule : std::uint8_t { None, GoPackage, FileImport };
inline WrittenQualifierRule writtenQualifierRuleOf( Lang l ) noexcept
{
    switch( l )
    {
        case Lang::Go:                               return WrittenQualifierRule::GoPackage;
        case Lang::Python: case Lang::TypeScript:    return WrittenQualifierRule::FileImport;
        default:                                     return WrittenQualifierRule::None;
    }
}

// the languages where `Cls.m()` is a call on the CLASS (a static or an unbound method): C++ spells that `Cls::m()` (a
// qualifier, the canonical tier's), so a C++/C/Rust receiver spelled like a class is a variable or a member; Ruby's class
// receivers are its own lookup's question
inline bool classNameReceiverLang( Lang l ) noexcept
{
    return l == Lang::JavaScript || l == Lang::TypeScript || l == Lang::Python || l == Lang::Java || l == Lang::Kotlin
        || l == Lang::CSharp || l == Lang::Swift;
}

// a call written ON a receiver — every language's member shape: Python/C++/Ruby record a RecvKind, the rest memberCall
inline bool isMemberCallRef( const Reference& r ) noexcept
{
    return r.recv != RecvKind::None || r.memberCall;
}

inline bool isThisRoot( std::string_view root ) noexcept
{
    return root == "this" || root == "self" || root == "Self";
}

// Is `root` (the call's receiver root, ReceiverEvidence::chainOf) the language's BASE-CLASS receiver — a lookup that walks
// the caller's bases only? Each spelling counts only where the grammar makes it that keyword: C# `base`; `super` in
// Java, Kotlin, Swift, JS and TS; Python's `super()` / `super(C, self)` call, which ingest records as RecvKind::SuperObj.
// Everywhere else the same text is an ordinary name — a Python/JS/Go/Java/… local `base`, a Go or C# local `super`, a
// Python name `super` that shadows the builtin — and proves nothing about the bases (its own type, if any, decides).
inline bool isSuperRoot( const Reference& r, std::string_view root ) noexcept
{
    if( r.recv == RecvKind::SuperObj )
    {
        return true;
    }
    switch( r.lang )
    {
        case Lang::CSharp:
            return root == "base";
        case Lang::Java: case Lang::Kotlin: case Lang::Swift: case Lang::JavaScript: case Lang::TypeScript:
            return root == "super";
        default:
            return false;
    }
}

// The innermost function/method of `id`'s file whose span strictly holds `id`'s span; kNoNode when none. `byFile` is
// fileId → that file's functions/methods sorted by sigStartByte. Shared by ReceiverEvidence and graph.h FalseEdgeRules.
inline NodeId innermostEnclosingFn( const IngestResult& ing, const std::vector<std::vector<NodeId>>& byFile, NodeId id )
{
    const Symbol& inner = ing.symbols[ id ];
    if( inner.fileId >= byFile.size() )
    {
        return kNoNode;
    }
    NodeId best = kNoNode;
    for( NodeId c : byFile[ inner.fileId ] )
    {
        const Symbol& s = ing.symbols[ c ];
        if( s.sigStartByte > inner.sigStartByte )
        {
            break;   // sorted by start: nothing later can hold it
        }
        if( c != id && s.endByte >= inner.endByte && ( s.sigStartByte < inner.sigStartByte || s.endByte > inner.endByte ) )
        {
            best = c;   // later starts are more inner
        }
    }
    return best;
}

// (L) fix round 3 — how a bare type name is looked up, per family (data rows read by CallResultTypes::bareClassAt): which
// scopes are levels of the lexical chain, where a family's imports bind, and which tiers follow the file. Every other
// family (Go: its package directory; C++: namespaces and includes, cppUnqualifiedClass) has its own reader.
struct BareNameRules
{
    CallResultFamily family;
    bool             itemScopesOnly;     // Rust: only an item scope is a level (rustScopesItems) — a struct / trait / impl scopes none
    bool             modIsBarrier;       // Rust: a `mod` (the file is one) is a fresh scope: no level outside it is read
    bool             importsAtAnyLevel;  // Rust: a `use` binds at the level it is written at (JVM / TS imports: the file level)
    bool             levelWildcards;     // Rust: a level's globs are read after its named bindings
    bool             inheritedMembers;   // JVM: a member type a base of an enclosing class declares (not followed: unresolved)
    bool             packageTier;        // JVM: past the file, the declared package's top-level classes and aliases
    bool             fileWildcards;      // JVM: last, the file's on-demand / star imports
};
// Rust: the symbols whose body is an item scope (a nested item, `use` or macro there is in force for what it holds) — a fn
// body, a `mod` (Other), and (fix round 6) a `const` / `static` item's value block (`const _: () = { … impl … };`, Var)
inline constexpr std::array<SymKind, 4> kRustItemScopeKinds = { SymKind::Function, SymKind::Method, SymKind::Var, SymKind::Other };
inline bool rustScopesItems( SymKind k ) noexcept { return extent::inSet( kRustItemScopeKinds, k ); }   // the shared membership test
inline constexpr BareNameRules kBareNameRules[] = {
    { CallResultFamily::Rust,       true,  true,  true,  true,  false, false, false },
    { CallResultFamily::Jvm,        false, false, false, false, true,  true,  true  },
    { CallResultFamily::TypeScript, false, false, false, false, false, false, false },
};

// (L) fix round 1 — CallResultTypes: what a declared result type names, decided in its callee's file.
// A type is recorded for a call result only when its written text RESOLVES, through the callee file's own context —
// its imports, its qualifier, its own file, then its package / module / namespace — to exactly ONE in-tree class;
// the typed local then carries that class (LocalFact::cls), never its name alone. A name imported from outside, an
// outside qualifier, a global, a name that resolves nowhere or to two classes: kNoNode, nothing recorded. The import
// and qualifier readers differ per family (the rows below); the rule is one.
struct CallResultTypes
{
    const IngestResult&                                   ing;
    HashMap<std::string, rw::SmallVec<NodeId, 2>>         classDefsByName;            // class-like name → its definitions, id order
    std::vector<std::vector<const Binding*>>              importsByFile;              // fileId → its TypeImport / JsImport records
    const HashMap<std::string, std::string>*              moduleAlias     = nullptr;  // ReceiverEvidence's "<fileId>#name" → module
    const GoPackagePaths*                                 goPackages      = nullptr;  // graph.h FalseEdgeRules::goPackages
    const HashMap<std::string, NodeId>*                   jsPinnedClasses = nullptr;  // graph.h: "<fileId>#<local>" → the class a TS import pins
    const HashMap<std::string, std::uint32_t>*            jsImportModules = nullptr;  // graph.h (lane L6): "<fileId>#<local>" → the file a TS import's module resolved to
    const ClassIdentity*                                  classIds        = nullptr;  // graph.h: C-family class identity (resolve.h)
    const std::vector<std::vector<NodeId>>*               fileIncludes    = nullptr;  // graph.h: C-family transitive include set per file (sorted)
    const HashMap<std::string, std::vector<std::string>>* chaUp           = nullptr;  // class name → its direct base names
    // fix round 2: the Namespace records (scopes the index has no symbol for) in (file, start) order, the C++ files holding a
    // namespace- or file-scope using (sorted), and each class's innermost enclosing symbol as first asked (kNoNode: file scope)
    std::vector<const Binding*>                           namespaces;
    std::vector<std::uint32_t>                            cppUsingFiles;
    HashMap<std::string, char>                            jvmPackages;     // the Java / Kotlin packages the tree declares
    mutable HashMap<NodeId, NodeId>                       enclosingMemo;
    // fix round 3: each JVM file's declared package ("" none), the files of each declared package, and every TypeAlias row
    // by the name it binds (a C++ base class's member alias)
    std::vector<std::string_view>                         filePackage;
    HashMap<std::string, std::vector<std::uint32_t>>      packageFiles;
    HashMap<std::string, std::vector<const Binding*>>     aliasesByName;
    // Rust crate/module layout, built on the first Rust resolution: a file's crate (its nearest `lib.rs` / `main.rs`
    // directory) and module path (`a::b` for src/a/b.rs or src/a/b/mod.rs), the crates by name (`mdbook_core` for
    // crates/mdbook-core/src), and each module's files
    struct RustLayout
    {
        bool                                              built = false;
        std::vector<std::uint32_t>                        crateOf;    // fileId → crate index, kNoCrate when none
        std::vector<std::string>                          moduleOf;   // fileId → module path ("" = the crate root)
        HashMap<std::string, std::uint32_t>               crateByName;
        HashMap<std::string, std::vector<std::uint32_t>>  filesOf;    // "<crate>#<module>" → its files
        HashMap<std::string, NodeId>                      inlineMods; // fix round 3: "<crate>#<module>" → an inline `mod` symbol
    };
    static constexpr std::uint32_t                        kNoCrate = 0xFFFFFFFFu;
    mutable RustLayout                                    rust;
    mutable std::string                                   nameKey;    // classesNamed's lookup buffer
    mutable std::string                                   aliasKey;   // importPathOf's / the TS pin lookup's
    mutable std::vector<std::string_view>                 usingPath;  // forEachCppUsing's per-row namespace path
    mutable std::string                                   moduleKey;  // rustModuleKey's buffer
    mutable bool                                          pathCut = false;   // fc1 fix 3: a rustPathOutside walk hit its depth cap — its false then means "cut", not "stays in the tree"

    explicit CallResultTypes( const IngestResult& i ) : ing( i ) {}

    // the index build: every class-like definition by name, and each file's import records
    void noteClass( const Symbol& s ) { classDefsByName[ s.name ].push_back( s.id ); }
    void noteImport( const Binding& b )
    {
        if( b.kind == LocalBindKind::Namespace && b.spanEnd == 0 )
        {
            jvmPackages.try_emplace( b.var, char( 1 ) );   // a Java / Kotlin `package` declaration (model.h)
            if( b.fileId < filePackage.size() )
            {
                filePackage[ b.fileId ] = b.var;
                packageFiles[ b.var ].push_back( b.fileId );
            }
            return;
        }
        if( b.kind == LocalBindKind::Namespace )
        {
            namespaces.push_back( &b );
            return;
        }
        const bool alias = b.kind == LocalBindKind::TypeAlias;
        if( ( b.kind == LocalBindKind::TypeImport || b.kind == LocalBindKind::JsImport || alias ) && b.fileId < importsByFile.size() && !b.var.empty() )
        {
            importsByFile[ b.fileId ].push_back( &b );
            if( alias )
            {
                aliasesByName[ b.var ].push_back( &b );
            }
            if( isCppScopeRow( b ) && ( cppUsingFiles.empty() || cppUsingFiles.back() != b.fileId ) )
            {
                cppUsingFiles.push_back( b.fileId );
            }
        }
    }
    // a C++ using-directive / using-declaration, or (fix round 3) a C++ alias: the rows that carry their scope's span (model.h)
    static bool isCppScopeRow( const Binding& b ) noexcept
    {
        constexpr LocalBindKind kSpanned[] = { LocalBindKind::TypeImport, LocalBindKind::TypeAlias };   // the kinds a C++ scope span rides on
        return b.spanEnd != 0 && std::ranges::find( kSpanned, b.kind ) != std::end( kSpanned );
    }
    // fix round 4: a TypeAlias row that binds its spelling with no alias target — a forward declaration, a type declaration
    // the index keeps no class for, an unparsed region (model.h kTypeBind* constants)
    static bool bindsWithoutTarget( const Binding& b ) noexcept
    {
        constexpr std::string_view kMarks[] = { kTypeBindForward, kTypeBindShadow, kTypeBindUnparsed };
        return b.kind == LocalBindKind::TypeAlias && std::ranges::find( kMarks, std::string_view( b.typeName ) ) != std::end( kMarks );
    }
    // after the last noteImport: the two lists in (file, start) / file order
    void finishIndex()
    {
        std::stable_sort( namespaces.begin(), namespaces.end(), []( const Binding* a, const Binding* b )
        {
            return a->fileId != b->fileId ? a->fileId < b->fileId : a->startByte < b->startByte;
        } );
        std::sort( cppUsingFiles.begin(), cppUsingFiles.end() );
        cppUsingFiles.erase( std::unique( cppUsingFiles.begin(), cppUsingFiles.end() ), cppUsingFiles.end() );
    }
    // the import path the file-scope name `name` binds in file `fileId` ("" when none, or rebound)
    std::string_view importPathOf( std::uint32_t fileId, std::string_view name ) const
    {
        if( moduleAlias == nullptr )
        {
            return {};
        }
        aliasKey.assign( std::to_string( fileId ) ).append( 1, '#' ).append( name );
        const auto it = moduleAlias->find( aliasKey );
        return it == moduleAlias->end() ? std::string_view{} : std::string_view( it->second );
    }
    std::string_view dirOf( std::uint32_t fileId ) const { return includerDir( rootRelPath( ing, fileId ) ); }
    // is `dir` the directory `tail` names, read from its end and segment-aligned (`a/b/model` ends `b/model`, not `del`):
    // resolve.h's tsimport::fileNamed, refusing an empty tail (the repository root names no package)
    static bool endsWithDir( std::string_view dir, std::string_view tail ) noexcept
    {
        return !tail.empty() && tsimport::fileNamed( dir, tail );
    }
    // the in-tree class-likes named `name` of family `fam` that `keep` admits: their count, and the last one in `one`
    template <class Keep>
    std::size_t classesNamed( std::string_view name, CallResultFamily fam, Keep&& keep, NodeId& one ) const
    {
        one = kNoNode;
        nameKey.assign( name );
        const auto it = classDefsByName.find( nameKey );
        if( it == classDefsByName.end() )
        {
            return 0;
        }
        std::size_t n = 0;
        for( NodeId c : it->second )
        {
            if( callResultFamilyOf( ing.symbols[ c ].lang ) == fam && keep( c ) )
            {
                one = c;
                ++n;
            }
        }
        return n;
    }
    template <class Keep>
    NodeId onlyClass( std::string_view name, CallResultFamily fam, Keep&& keep ) const
    {
        NodeId one = kNoNode;
        return classesNamed( name, fam, keep, one ) == 1 ? one : kNoNode;
    }
    // the import records of file `fileId` binding the local name `var` (TypeImport / JsImport)
    template <class Fn>
    void forEachImport( std::uint32_t fileId, std::string_view var, Fn&& fn ) const
    {
        if( fileId < importsByFile.size() )
        {
            for( const Binding* b : importsByFile[ fileId ] )
            {
                if( b->var == var )
                {
                    fn( *b );
                }
            }
        }
    }
    // ── lexical scope (fix round 2): is a class in scope, by its bare name, where the callee is declared ──
    // the Namespace records of file `f`, outermost first
    std::span<const Binding* const> namespacesOf( std::uint32_t f ) const
    {
        const auto run = std::ranges::equal_range( namespaces, f, std::ranges::less{}, []( const Binding* b ) { return b->fileId; } );
        return { run.begin(), run.end() };
    }
    // the innermost symbol of `c`'s file whose span strictly holds `c`'s — the class, module or function it is nested in;
    // kNoNode at file scope. Symbol ids ascend by (file, line), so a holder sits before `c` or after it on `c`'s own line.
    NodeId enclosingSymbol( NodeId c ) const
    {
        if( const auto it = enclosingMemo.find( c ); it != enclosingMemo.end() )
        {
            return it->second;
        }
        const Symbol& cs       = ing.symbols[ c ];
        NodeId        best     = kNoNode;
        const auto    consider = [ & ]( NodeId s )
        {
            const Symbol& o     = ing.symbols[ s ];
            const bool    holds = o.sigStartByte <= cs.sigStartByte && o.endByte >= cs.endByte && ( o.sigStartByte < cs.sigStartByte || o.endByte > cs.endByte );
            best = holds && ( best == kNoNode || o.sigStartByte > ing.symbols[ best ].sigStartByte ) ? s : best;
        };
        for( NodeId s = c; s > 0 && ing.symbols[ s - 1 ].fileId == cs.fileId; --s )
        {
            consider( s - 1 );
        }
        for( NodeId s = c + 1; s < ing.symbols.size() && ing.symbols[ s ].fileId == cs.fileId && ing.symbols[ s ].line == cs.line; ++s )
        {
            consider( s );
        }
        enclosingMemo.try_emplace( c, best );
        return best;
    }
    // Rust: the innermost item scope — a `mod` (SymKind::Other) or a fn body — enclosing symbol `s`; kNoNode at its file's
    // own level (through enclosingSymbol: an `impl` block is no symbol, so its methods sit in the scope that holds it)
    NodeId innermostItemScope( NodeId s ) const
    {
        NodeId up = enclosingSymbol( s );
        for( int guard = 0; guard < 64 && up != kNoNode && ing.symbols[ up ].kind != SymKind::Other && ing.symbols[ up ].kind != SymKind::Function
                                                       && ing.symbols[ up ].kind != SymKind::Method; ++guard )
        {
            up = enclosingSymbol( up );
        }
        return up;
    }
    // does a Namespace record of `c`'s file hold `c`
    bool inNamespace( NodeId c ) const
    {
        const Symbol& cs = ing.symbols[ c ];
        for( const Binding* ns : namespacesOf( cs.fileId ) )
        {
            if( ns->spanStart <= cs.sigStartByte && cs.sigStartByte < ns->spanEnd )
            {
                return true;
            }
        }
        return false;
    }
    // Is class `c` in scope by its bare name at byte `at` of file `f` (a callee's declaration)? In its own file every scope
    // enclosing it — an indexed symbol (class, module, function) or a Namespace record — must hold `at` too (inside, not at,
    // the scope's own start: a function's local class is not in scope in its own signature); from another file — its package,
    // its module — it must sit at file scope: a nested class is reached through its outer name, never bare.
    bool visibleAt( NodeId c, std::uint32_t f, std::uint32_t at ) const
    {
        const Symbol& cs    = ing.symbols[ c ];
        const NodeId  outer = enclosingSymbol( c );
        if( cs.fileId != f )
        {
            return outer == kNoNode && !inNamespace( c );
        }
        if( outer != kNoNode && !( ing.symbols[ outer ].sigStartByte < at && at < ing.symbols[ outer ].endByte ) )
        {
            return false;
        }
        for( const Binding* ns : namespacesOf( f ) )
        {
            const bool holdsClass = ns->spanStart <= cs.sigStartByte && cs.sigStartByte < ns->spanEnd;
            if( holdsClass && !( ns->spanStart <= at && at < ns->spanEnd ) )
            {
                return false;
            }
        }
        return true;
    }
    // ── fix round 3: ONE rule for a bare type name — every binding of the spelling visible where it is written decides ──
    // A level of the lexical chain: a symbol's span (`sym`), a Namespace record's body (sym kNoNode), or the whole file.
    struct Level
    {
        std::uint32_t start = 0;
        std::uint32_t end   = 0xFFFFFFFFu;
        NodeId        sym   = kNoNode;
        bool          wholeFile() const noexcept { return start == 0 && end == 0xFFFFFFFFu && sym == kNoNode; }
        bool          operator==( const Level& ) const = default;
    };
    // The votes of one level (or tier): each binding of the spelling there names one in-tree class, or kNoNode (outside,
    // unresolved, an alias). ONE class decides; anything else — an outside or unresolved binding, two that disagree — names
    // nothing.
    struct Ballot
    {
        bool   any   = false;
        bool   split = false;
        NodeId cls   = kNoNode;
        void   vote( NodeId c ) noexcept
        {
            split = split || c == kNoNode || ( any && c != cls );
            cls   = c;
            any   = true;
        }
        NodeId verdict() const noexcept { return any && !split ? cls : kNoNode; }
    };
    // the symbol ids of file `f` (ids ascend by file)
    std::pair<NodeId, NodeId> symbolsOf( std::uint32_t f ) const
    {
        const auto byFile = []( const Symbol& o ) { return o.fileId; };
        const auto run    = std::ranges::equal_range( ing.symbols, f, std::ranges::less{}, byFile );
        return { NodeId( run.begin() - ing.symbols.begin() ), NodeId( run.end() - ing.symbols.begin() ) };
    }
    // the innermost symbol of file `f` that `keep` admits and whose span strictly holds byte `pos`; kNoNode when none
    template <class Keep>
    NodeId innermostHolding( std::uint32_t f, std::uint32_t pos, Keep&& keep ) const
    {
        NodeId     best = kNoNode;
        const auto [ lo, hi ] = symbolsOf( f );
        for( NodeId s = lo; s < hi; ++s )
        {
            const Symbol& o     = ing.symbols[ s ];
            const bool    holds = o.sigStartByte < pos && pos < o.endByte && keep( o.kind );
            best = holds && ( best == kNoNode || o.sigStartByte > ing.symbols[ best ].sigStartByte ) ? s : best;
        }
        return best;
    }
    // the innermost level of file `f` holding byte `pos` — a symbol (strictly inside it) or a Namespace body; the file when none
    Level levelAt( std::uint32_t f, std::uint32_t pos ) const
    {
        const NodeId s    = innermostHolding( f, pos, []( SymKind k ) { return k != SymKind::ModuleScope; } );
        Level        best = s == kNoNode ? Level{} : Level{ ing.symbols[ s ].sigStartByte, ing.symbols[ s ].endByte, s };
        for( const Binding* ns : namespacesOf( f ) )
        {
            if( ns->spanStart <= pos && pos < ns->spanEnd && ( best.wholeFile() || ns->spanStart > best.start ) )
            {
                best = { ns->spanStart, ns->spanEnd, kNoNode };
            }
        }
        return best;
    }
    // every level holding byte `at` of file `f`, innermost first, the file last
    void chainAt( std::uint32_t f, std::uint32_t at, std::vector<Level>& out ) const
    {
        out.clear();
        const auto [ lo, hi ] = symbolsOf( f );
        for( NodeId s = lo; s < hi; ++s )
        {
            const Symbol& o = ing.symbols[ s ];
            if( o.kind != SymKind::ModuleScope && o.sigStartByte < at && at < o.endByte )
            {
                out.push_back( { o.sigStartByte, o.endByte, s } );
            }
        }
        for( const Binding* ns : namespacesOf( f ) )
        {
            if( ns->spanStart <= at && at < ns->spanEnd )
            {
                out.push_back( { ns->spanStart, ns->spanEnd, kNoNode } );
            }
        }
        std::ranges::sort( out, []( const Level& a, const Level& b ) { return a.start != b.start ? a.start > b.start : a.end < b.end; } );
        out.push_back( Level{} );
    }
    // the level class `c` is declared in: its enclosing symbol, or a Namespace record holding it, whichever is innermost
    Level levelOfClass( NodeId c ) const
    {
        const Symbol& cs    = ing.symbols[ c ];
        const NodeId  outer = enclosingSymbol( c );
        Level         best  = outer == kNoNode ? Level{} : Level{ ing.symbols[ outer ].sigStartByte, ing.symbols[ outer ].endByte, outer };
        for( const Binding* ns : namespacesOf( cs.fileId ) )
        {
            if( ns->spanStart <= cs.sigStartByte && cs.sigStartByte < ns->spanEnd && ( best.wholeFile() || ns->spanStart > best.start ) )
            {
                best = { ns->spanStart, ns->spanEnd, kNoNode };
            }
        }
        return best;
    }
    static bool notModule( SymKind k ) noexcept { return k != SymKind::ModuleScope; }
    static bool classKind( SymKind k ) noexcept
    {
        constexpr SymKind kClassKinds[] = { SymKind::Class, SymKind::Struct, SymKind::Interface };   // the class-like kinds
        return std::ranges::find( kClassKinds, k ) != std::end( kClassKinds );
    }
    // the innermost class of file `f` whose span holds byte `pos` (a member declaration's class); kNoNode when none
    NodeId classHolding( std::uint32_t f, std::uint32_t pos ) const { return innermostHolding( f, pos, &classKind ); }
    // JVM / C++: does a base of class `holder` — through in-tree bases, transitively (a visited set: a diamond is walked
    // once) — declare a member type `name` (a nested class, or a C++ member alias)? Such a member type is in scope inside
    // `holder` and is not followed here: the spelling names nothing.
    bool inheritsMemberType( NodeId holder, std::string_view name, CallResultFamily fam ) const
    {
        if( chaUp == nullptr )
        {
            return false;
        }
        std::vector<std::string_view> cone;
        nameKey.assign( ing.symbols[ holder ].name );
        if( const auto it = chaUp->find( nameKey ); it != chaUp->end() )
        {
            cone.assign( it->second.begin(), it->second.end() );
        }
        for( std::size_t i = 0; i < cone.size() && cone.size() < 64; ++i )
        {
            nameKey.assign( cone[ i ] );
            if( const auto it = chaUp->find( nameKey ); it != chaUp->end() )
            {
                for( const std::string& b : it->second )
                {
                    if( std::ranges::find( cone, std::string_view( b ) ) == cone.end() )
                    {
                        cone.push_back( b );
                    }
                }
            }
        }
        if( cone.empty() )
        {
            return false;
        }
        const auto inCone = [ & ]( NodeId owner ) { return owner != kNoNode && std::ranges::find( cone, std::string_view( ing.symbols[ owner ].name ) ) != cone.end(); };
        NodeId one = kNoNode;
        if( classesNamed( name, fam, [ & ]( NodeId c ) { return inCone( enclosingSymbol( c ) ); }, one ) > 0 )
        {
            return true;
        }
        nameKey.assign( name );
        const auto aliases = aliasesByName.find( nameKey );
        return aliases != aliasesByName.end() && std::ranges::any_of( aliases->second, [ & ]( const Binding* b )
        {
            const NodeId holder = classHolding( b->fileId, b->startByte );   // fix round 4: a member of the class, not of one of its bodies
            return inCone( holder ) && innermostHolding( b->fileId, b->startByte, &notModule ) == holder;
        } );
    }
    // the JVM files of one package as `f` sees it: the same declared package, or (neither declares one) the same directory
    bool samePackage( std::uint32_t f, std::uint32_t g ) const
    {
        const std::string_view pf = f < filePackage.size() ? filePackage[ f ] : std::string_view{};
        const std::string_view pg = g < filePackage.size() ? filePackage[ g ] : std::string_view{};
        return pf.empty() && pg.empty() ? dirOf( f ) == dirOf( g ) : pf == pg;
    }
    // the ONE in-tree class a named import row `b` of file `f` binds (kNoNode: outside, unresolved, or two)
    NodeId importedClass( CallResultFamily fam, std::uint32_t f, const Binding& b ) const
    {
        switch( fam )
        {
            case CallResultFamily::Rust:
            {
                const auto [ modPath, item ] = splitLast( b.importedName, "::" );
                return modPath.empty() ? kNoNode : rustClassAt( f, b.startByte, modPath, item );
            }
            case CallResultFamily::Jvm:        return jvmClassIn( b.importedName, b.typeName );
            case CallResultFamily::TypeScript:
            {
                if( jsPinnedClasses == nullptr )
                {
                    return kNoNode;
                }
                aliasKey.assign( std::to_string( f ) ).append( 1, '#' ).append( b.var );
                const auto it = jsPinnedClasses->find( aliasKey );
                return it == jsPinnedClasses->end() ? kNoNode : it->second;
            }
            default:                           return kNoNode;
        }
    }
    // a named (non-wildcard) import row of the family
    static bool namedImport( CallResultFamily fam, const Binding& b ) noexcept
    {
        return fam == CallResultFamily::TypeScript ? b.kind == LocalBindKind::JsImport : b.kind == LocalBindKind::TypeImport && b.var != "*";
    }
    // a wildcard row `b` (Rust `use m::*`, JVM `import p.*`) seen from file `f`: the class `name` it supplies; `supplies`
    // false when it supplies none — an outside or unresolved wildcard MAY supply it (kNoNode, supplies true)
    NodeId wildcardSupplies( CallResultFamily fam, std::uint32_t f, const Binding& b, std::string_view name, bool& supplies ) const
    {
        supplies = true;
        if( fam == CallResultFamily::Rust )
        {
            std::uint32_t crate = kNoCrate;
            std::string   module;
            if( !rustModuleOf( f, b.startByte, b.importedName, crate, module, 0 ) )
            {
                return kNoNode;
            }
            supplies = false;   // rust-receivers: rustItemAt sets it when the module has the item, re-exports it or may glob it in
            return rustItemAt( crate, module, name, 0, supplies );
        }
        nameKey.assign( b.importedName );
        const auto files = packageFiles.find( nameKey );
        if( files == packageFiles.end() )
        {
            return kNoNode;   // a package the tree does not declare (or a class's members: `import p.Obj.*`)
        }
        NodeId            one = kNoNode;
        const std::size_t n   = classesNamed( name, CallResultFamily::Jvm, [ & ]( NodeId c )
        {
            return std::ranges::find( files->second, ing.symbols[ c ].fileId ) != files->second.end() && levelOfClass( c ).wholeFile();
        }, one );
        supplies = n > 0;
        return n == 1 ? one : kNoNode;
    }
    // THE RULE (fix round 3). The bare type name `name` written at byte `at` of file `f` (a callee's declared result, or a
    // JVM class-name receiver at its call) names the ONE in-tree class the language's own lookup reaches: walk the lexical
    // chain innermost first; at each level collect EVERY binding of the spelling there — a class declared in it, an alias
    // (always kNoNode: not followed), a named import binding there (Rust: at any level; JVM / TS: the file), a member type a
    // base of the level's class declares (JVM: kNoNode) — and the first level with any binding decides by its Ballot; a
    // level's wildcards (Rust globs) vote only when its named bindings are silent. Rust stops at its module (a fresh
    // scope); past the file the JVM reads its package's top-level classes and aliases, then the file's on-demand imports.
    NodeId bareClassAt( CallResultFamily fam, std::uint32_t f, std::uint32_t at, std::string_view name ) const
    {
        const auto rules = std::ranges::find( kBareNameRules, fam, &BareNameRules::family );   // the family's data row
        if( rules == std::end( kBareNameRules ) || f >= importsByFile.size() )
        {
            return kNoNode;
        }
        std::vector<Level> chain;
        chainAt( f, at, chain );
        for( const Level& lv : chain )
        {
            const SymKind kind = lv.sym == kNoNode ? SymKind::Other : ing.symbols[ lv.sym ].kind;
            if( rules->itemScopesOnly && lv.sym != kNoNode && !rustScopesItems( kind ) )
            {
                continue;   // a Rust struct / trait / enum declares no item in scope (an associated type is `Self::T`)
            }
            Ballot     named;
            NodeId     one = kNoNode;
            classesNamed( name, fam, [ & ]( NodeId c )
            {
                if( ing.symbols[ c ].fileId == f && levelOfClass( c ) == lv )
                {
                    named.vote( c );
                }
                return false;
            }, one );
            forEachImport( f, name, [ & ]( const Binding& b )
            {
                const bool here = rules->importsAtAnyLevel || b.kind == LocalBindKind::TypeAlias ? levelAt( f, b.startByte ) == lv : lv.wholeFile();
                if( here && b.kind == LocalBindKind::TypeAlias )
                {
                    named.vote( kNoNode );
                }
                else if( here && namedImport( fam, b ) )
                {
                    named.vote( importedClass( fam, f, b ) );
                }
            } );
            if( !named.any && rules->inheritedMembers && lv.sym != kNoNode && classKind( kind ) && inheritsMemberType( lv.sym, name, fam ) )
            {
                named.vote( kNoNode );
            }
            if( !named.any )   // fix round 4: an unparsed region of this level (a Rust block's macro) may declare the name here
            {
                forEachImport( f, "!", [ & ]( const Binding& b )
                {
                    if( bindsWithoutTarget( b ) && levelAt( f, b.startByte ) == lv )
                    {
                        named.vote( kNoNode );
                    }
                } );
            }
            if( named.any )
            {
                return named.verdict();
            }
            if( rules->levelWildcards )
            {
                Ballot globs;
                forEachImport( f, "*", [ & ]( const Binding& b )
                {
                    bool supplies = false;
                    const NodeId c = b.kind == LocalBindKind::TypeImport && levelAt( f, b.startByte ) == lv ? wildcardSupplies( fam, f, b, name, supplies ) : kNoNode;
                    if( supplies )
                    {
                        globs.vote( c );
                    }
                } );
                if( globs.any )
                {
                    return globs.verdict();
                }
            }
            if( rules->modIsBarrier && ( lv.wholeFile() || kind == SymKind::Other ) )
            {
                return kNoNode;   // a Rust module: the name is the prelude's, an outside crate's, or unresolved
            }
        }
        if( rules->packageTier )
        {
            Ballot     pkg;
            NodeId     one = kNoNode;
            classesNamed( name, fam, [ & ]( NodeId c )
            {
                const std::uint32_t g = ing.symbols[ c ].fileId;
                if( g != f && samePackage( f, g ) && levelOfClass( c ).wholeFile() )
                {
                    pkg.vote( c );
                }
                return false;
            }, one );
            nameKey.assign( name );
            if( const auto aliases = aliasesByName.find( nameKey ); aliases != aliasesByName.end() )
            {
                for( const Binding* b : aliases->second )
                {
                    const bool declared = b->fileId < filePackage.size() && !filePackage[ b->fileId ].empty();   // a JVM file's own package
                    if( b->fileId != f && declared && samePackage( f, b->fileId ) && levelAt( b->fileId, b->startByte ).wholeFile() )
                    {
                        pkg.vote( kNoNode );   // a Kotlin `typealias` of the package
                    }
                }
            }
            if( pkg.any )
            {
                return pkg.verdict();
            }
        }
        if( rules->fileWildcards )
        {
            Ballot wild;
            forEachImport( f, "*", [ & ]( const Binding& b )
            {
                bool supplies = false;
                const NodeId c = b.kind == LocalBindKind::TypeImport ? wildcardSupplies( fam, f, b, name, supplies ) : kNoNode;
                if( supplies )
                {
                    wild.vote( c );
                }
            } );
            return wild.verdict();
        }
        return kNoNode;
    }

    // Go: `pkg.T` names a class of THIS tree only when `pkg` imports an in-tree package and that package defines exactly one
    // `T` — the exact package path when the tree has module facts (go.mod), else a directory that ends the path,
    // segment-aligned. Shared by written types (a local, parameter or field `f *os.File`) and call results.
    NodeId goQualifiedClass( std::uint32_t fileId, std::string_view whole, std::string_view cls ) const
    {
        const std::size_t dot = whole.find( '.' );
        if( dot == std::string_view::npos || cls.empty() )
        {
            return kNoNode;
        }
        const std::string path( importPathOf( fileId, whole.substr( 0, dot ) ) );
        if( path.empty() )
        {
            return kNoNode;
        }
        const bool modules = goPackages != nullptr && !goPackages->known.empty();
        return onlyPackageClass( cls, [ & ]( NodeId c )
        {
            return ( modules ? goPackages->names( ing.symbols[ c ].fileId, path ) : endsWithDir( path, dirOf( ing.symbols[ c ].fileId ) ) )
                && enclosingSymbol( c ) == kNoNode;   // a package-level type, never one local to a function
        } );
    }
    NodeId goResultClass( std::uint32_t fileId, std::uint32_t at, std::string_view whole, std::string_view cls ) const
    {
        if( !whole.empty() )
        {
            return goQualifiedClass( fileId, whole, cls );
        }
        const std::string_view dir = dirOf( fileId );   // one package is one directory
        return onlyPackageClass( cls, [ & ]( NodeId c ) { return dirOf( ing.symbols[ c ].fileId ) == dir && visibleAt( c, fileId, at ); } );
    }
    // Go: the class `cls` of the ONE package directory `keep` admits — a type a package defines once per build-tag file
    // (`Executor` in util_unix.go and util_windows.go) is one class to the member rule (PackageDir), so its first
    // definition stands for it; two packages' namesakes are kNoNode
    template <class Keep>
    NodeId onlyPackageClass( std::string_view cls, Keep&& keep ) const
    {
        NodeId           first = kNoNode;
        std::string_view dir;
        bool             one   = true;
        NodeId           last  = kNoNode;
        classesNamed( cls, CallResultFamily::Go, [ & ]( NodeId c )
        {
            if( !keep( c ) )
            {
                return false;
            }
            const std::string_view d = dirOf( ing.symbols[ c ].fileId );
            one   = one && ( first == kNoNode || d == dir );
            first = first == kNoNode ? c : first;
            dir   = first == c ? d : dir;
            return true;
        }, last );
        return one ? first : kNoNode;
    }

    // Java / Kotlin: an imported or qualified `a.b.T` names the in-tree top-level class `T` of the package `a.b` the tree
    // DECLARES (fix round 3: a Kotlin file's package need not match its directory); a tree that declares no package reads
    // the directory ending `a/b`. A nested `a.b.Outer.T` is not followed (kNoNode).
    NodeId jvmClassIn( std::string_view path, std::string_view cls ) const
    {
        const std::size_t dot = path.rfind( '.' );
        if( dot == std::string_view::npos )
        {
            return kNoNode;
        }
        if( !jvmPackages.empty() )
        {
            nameKey.assign( path.substr( 0, dot ) );
            const auto files = packageFiles.find( nameKey );
            if( files == packageFiles.end() )
            {
                return kNoNode;   // a package the tree does not declare: outside
            }
            return onlyClass( cls, CallResultFamily::Jvm, [ & ]( NodeId c )
            {
                return std::ranges::find( files->second, ing.symbols[ c ].fileId ) != files->second.end() && levelOfClass( c ).wholeFile();
            } );
        }
        std::string pkgDir( path.substr( 0, dot ) );
        std::replace( pkgDir.begin(), pkgDir.end(), '.', '/' );
        return onlyClass( cls, CallResultFamily::Jvm, [ & ]( NodeId c )
        {
            return endsWithDir( dirOf( ing.symbols[ c ].fileId ), pkgDir ) && levelOfClass( c ).wholeFile();   // a top-level class
        } );
    }
    // Java / Kotlin (fix round 3: bareClassAt's rows), the order the languages scope a simple type name in: a class nested in
    // a scope that holds the callee or a member type its classes inherit, the file's single-type imports / own top-level
    // classes / aliases, the package's top-level classes and aliases, then the on-demand imports.
    NodeId jvmResultClass( std::uint32_t fileId, std::uint32_t at, std::string_view whole, std::string_view cls ) const
    {
        return whole.empty() ? bareClassAt( CallResultFamily::Jvm, fileId, at, cls ) : jvmClassIn( whole, cls );
    }
    // D3 / D6: a JVM class-name receiver spelled `name` at byte `at` of the caller's file `fileId` names an in-tree class only
    // when the caller's file SEES one by that name (bareClassAt: its package, a single-type import naming it, an on-demand
    // import of its package, a nested class in scope): `import ext.Util;` or `import ext.*;` alone hides every in-tree
    // Util. True when the tree defines a class `name` the caller does not see.
    bool jvmHides( std::uint32_t fileId, std::uint32_t at, std::string_view name ) const
    {
        NodeId one = kNoNode;
        return classesNamed( name, CallResultFamily::Jvm, []( NodeId ) { return true; }, one ) > 0 && bareClassAt( CallResultFamily::Jvm, fileId, at, name ) == kNoNode;
    }

    // TypeScript: a name imported by name (`import { T }`, `import { U as T }`) names the ONE in-tree class graph.h's import
    // tables pin for it (buildJsImportTables: the module resolved, the export found) — an outside module, a type-only import
    // the tables do not pin, or a re-export they cannot follow names nothing; else a class of the file itself; else nothing:
    // a module neighbour is never in scope without an import, and an unimported name is a global (`Response`). A class inside
    // a `namespace` or a function is in scope only within it, and an alias there (`type T = …`, `import T = n.U`) hides any
    // outer class (bareClassAt). A namespace-qualified `ns.T` is not resolved (a floor).
    NodeId tsResultClass( std::uint32_t fileId, std::uint32_t at, std::string_view whole, std::string_view cls ) const
    {
        return whole.empty() ? bareClassAt( CallResultFamily::TypeScript, fileId, at, cls ) : kNoNode;
    }

    // Rust: the crate layout (RustLayout above), then a path's module seen from a file — `crate::`, `self::`, `super::`, an
    // in-tree crate's name, a `use`d module, or a child module of the file's own; any other root (`std`, an outside crate)
    // leaves the tree.
    void buildRustLayout() const
    {
        rust.built = true;
        const std::size_t files = ing.files.size();
        rust.crateOf.assign( files, kNoCrate );
        rust.moduleOf.assign( files, {} );
        HashMap<std::string, std::uint32_t> rootIndex;   // crate root directory → crate index
        for( std::uint32_t f = 0; f < files; ++f )
        {
            const std::string_view path = rootRelPath( ing, f );
            if( path.ends_with( "lib.rs" ) || path.ends_with( "main.rs" ) )
            {
                const std::string_view base = path.substr( includerDir( path ).empty() ? 0 : includerDir( path ).size() + 1 );
                if( base != "lib.rs" && base != "main.rs" )
                {
                    continue;
                }
                const std::string dir( includerDir( path ) );
                if( rootIndex.try_emplace( dir, std::uint32_t( rootIndex.size() ) ).second )
                {
                    // the crate's name: its package directory (`crates/mdbook-core/src` → mdbook_core), `-` read as `_`
                    std::string_view pkg = dir;
                    if( pkg == "src" || pkg.ends_with( "/src" ) )
                    {
                        pkg = includerDir( pkg );
                    }
                    std::string name( pkg.substr( includerDir( pkg ).empty() ? 0 : includerDir( pkg ).size() + 1 ) );
                    std::replace( name.begin(), name.end(), '-', '_' );
                    if( !name.empty() )
                    {
                        const auto [ it, fresh ] = rust.crateByName.try_emplace( name, rootIndex[ dir ] );
                        if( !fresh )
                        {
                            it->second = kNoCrate;   // two crates of one name: the name decides nothing
                        }
                    }
                }
            }
        }
        for( std::uint32_t f = 0; f < files; ++f )
        {
            const std::string_view path = rootRelPath( ing, f );
            if( !path.ends_with( ".rs" ) )
            {
                continue;
            }
            for( std::string_view dir = includerDir( path );; dir = includerDir( dir ) )
            {
                if( const auto it = rootIndex.find( std::string( dir ) ); it != rootIndex.end() )
                {
                    std::string module( path.substr( dir.empty() ? 0 : dir.size() + 1 ) );
                    module.resize( module.size() - 3 );   // ".rs"
                    if( module == "lib" || module == "main" || module == "mod" )
                    {
                        module.clear();
                    }
                    else if( module.ends_with( "/mod" ) )
                    {
                        module.resize( module.size() - 4 );
                    }
                    for( std::size_t at = module.find( '/' ); at != std::string::npos; at = module.find( '/', at + 2 ) )
                    {
                        module.replace( at, 1, "::" );
                    }
                    rust.crateOf[ f ]  = it->second;
                    rust.moduleOf[ f ] = module;
                    rust.filesOf[ std::to_string( it->second ) + "#" + module ].push_back( f );
                    break;
                }
                if( dir.empty() )
                {
                    break;
                }
            }
        }
        // fix round 3: every inline `mod m { … }` (SymKind::Other) is a module of its own, `<file module>::…::m` — never the
        // file of a `mod m;` declaration, whose module is that file's
        for( const Symbol& m : ing.symbols )
        {
            if( m.kind != SymKind::Other || callResultFamilyOf( m.lang ) != CallResultFamily::Rust || m.fileId >= files || rust.crateOf[ m.fileId ] == kNoCrate )
            {
                continue;
            }
            std::string module;
            rustModuleAt( m.fileId, m.sigStartByte, module );
            module = joinModule( module, m.name );
            if( !rust.filesOf.contains( rustModuleKey( rust.crateOf[ m.fileId ], module ) ) )
            {
                rust.inlineMods.try_emplace( rustModuleKey( rust.crateOf[ m.fileId ], module ), m.id );
            }
        }
    }
    // the module byte `at` of Rust file `f` sits in: the file's module, then each inline `mod` holding `at`, outermost first
    void rustModuleAt( std::uint32_t f, std::uint32_t at, std::string& module ) const
    {
        module = f < rust.moduleOf.size() ? rust.moduleOf[ f ] : std::string{};
        const auto [ lo, hi ] = symbolsOf( f );
        for( NodeId s = lo; s < hi; ++s )   // ids ascend by line: an outer mod precedes the mods it holds
        {
            const Symbol& o = ing.symbols[ s ];
            if( o.kind == SymKind::Other && o.sigStartByte < at && at < o.endByte )
            {
                module = joinModule( module, o.name );
            }
        }
    }
    // the level of a module's own items: an inline mod's span, or (a file module) the file
    Level rustModuleLevel( NodeId inlineMod ) const
    {
        return inlineMod == kNoNode ? Level{} : Level{ ing.symbols[ inlineMod ].sigStartByte, ing.symbols[ inlineMod ].endByte, inlineMod };
    }
    // `a::b` + `c` → `a::b::c`; the crate root ("") + `c` → `c`
    static std::string joinModule( std::string_view module, std::string_view seg )
    {
        return module.empty() ? std::string( seg ) : std::string( module ).append( "::" ).append( seg );
    }
    // "<crate>#<module>", RustLayout::filesOf's key, built in the reused buffer
    const std::string& rustModuleKey( std::uint32_t crate, std::string_view module ) const
    {
        buildShadowKey( moduleKey, crate, module );   // model.h's "<id>#<name>" key, the layout's own spelling
        return moduleKey;
    }
    bool rustModuleExists( std::uint32_t crate, const std::string& module ) const
    {
        return rust.filesOf.contains( rustModuleKey( crate, module ) ) || rust.inlineMods.contains( rustModuleKey( crate, module ) );
    }
    // each level of the chain at byte `at` of Rust file `f` that scopes items (a fn body, then the module it sits in: an
    // inline `mod`, or the file), innermost first, until `fn( level )` returns true or the module level is passed
    template <class Fn>
    void forEachRustScopeAt( std::uint32_t f, std::uint32_t at, Fn&& fn ) const
    {
        std::vector<Level> chain;
        chainAt( f, at, chain );
        for( const Level& lv : chain )
        {
            const SymKind kind = lv.sym == kNoNode ? SymKind::Other : ing.symbols[ lv.sym ].kind;
            if( lv.sym != kNoNode && !rustScopesItems( kind ) )
            {
                continue;
            }
            if( fn( lv ) || lv.wholeFile() || kind == SymKind::Other )
            {
                return;
            }
        }
    }
    // the `use` rows binding `name` in force at byte `at` of file `f`: those of the innermost level (a fn body, then the
    // module) that holds one — a `use` binds where it is written (fix round 3), never file-wide
    template <class Fn>
    void forEachRustUseAt( std::uint32_t f, std::uint32_t at, std::string_view name, Fn&& fn ) const
    {
        forEachRustScopeAt( f, at, [ & ]( const Level& lv )
        {
            bool found = false;
            forEachImport( f, name, [ & ]( const Binding& b )
            {
                if( b.kind == LocalBindKind::TypeImport && levelAt( f, b.startByte ) == lv )
                {
                    found = true;
                    fn( b );
                }
            } );
            return found;
        } );
    }
    // the (crate, module) `modPath` (`crate::model`, `super::x`, `mdbook_core::book`, a `use`d `model`) names at byte `at` of
    // file `f` — relative to the module `at` sits in, an inline `mod` included (fix round 3: `super::` inside `mod m` is the
    // file's module, `self::` is m)
    bool rustModuleOf( std::uint32_t f, std::uint32_t at, std::string_view modPath, std::uint32_t& crate, std::string& module, int depth ) const
    {
        if( !rust.built )
        {
            buildRustLayout();
        }
        if( f >= rust.crateOf.size() || rust.crateOf[ f ] == kNoCrate || modPath.empty() || depth > 4 )
        {
            return false;
        }
        std::vector<std::string_view> segs;
        for( std::size_t at = 0;; )
        {
            const std::size_t sep = modPath.find( "::", at );
            segs.push_back( modPath.substr( at, sep == std::string_view::npos ? std::string_view::npos : sep - at ) );
            if( sep == std::string_view::npos )
            {
                break;
            }
            at = sep + 2;
        }
        crate = rust.crateOf[ f ];
        rustModuleAt( f, at, module );
        std::size_t i = 1;
        if( segs[ 0 ] == "crate" )
        {
            module.clear();
        }
        else if( segs[ 0 ] == "super" )
        {
            for( i = 0; i < segs.size() && segs[ i ] == "super"; ++i )
            {
                if( module.empty() )
                {
                    return false;
                }
                const std::size_t up = module.rfind( "::" );
                module.resize( up == std::string::npos ? 0 : up );
            }
        }
        else if( segs[ 0 ] != "self" )
        {
            // a `use` binding of the name in force there shadows a crate of that name; two `use`s of one name decide nothing
            std::size_t     uses = 0;
            std::string     usedPath;
            std::uint32_t   usedAt = 0;
            forEachRustUseAt( f, at, segs[ 0 ], [ & ]( const Binding& b )
            {
                ++uses;
                usedPath = b.importedName;
                usedAt   = b.startByte;
            } );
            const auto byName = rust.crateByName.find( std::string( segs[ 0 ] ) );
            if( uses > 1 )
            {
                return false;
            }
            if( uses == 1 )
            {
                if( !rustModuleOf( f, usedAt, usedPath, crate, module, depth + 1 ) )
                {
                    return false;
                }
            }
            else if( byName != rust.crateByName.end() && byName->second != kNoCrate )
            {
                crate = byName->second;
                module.clear();
            }
            else if( rustModuleExists( crate, joinModule( module, segs[ 0 ] ) ) )
            {
                module = joinModule( module, segs[ 0 ] );
            }
            else
            {
                return false;   // `std`, an outside crate, an unknown name
            }
        }
        for( ; i < segs.size(); ++i )
        {
            module = joinModule( module, segs[ i ] );
        }
        return rustModuleExists( crate, module );
    }
    // the ONE Rust class `cls` module `modPath` (seen from byte `at` of `f`) defines — or re-exports: a `use` of the name at
    // the module's own level (`pub use mdbook::MDBook;` in lib.rs) is followed to the module it names (depth-bounded)
    NodeId rustClassAt( std::uint32_t f, std::uint32_t at, std::string_view modPath, std::string_view cls, int depth = 0 ) const
    {
        std::uint32_t crate = kNoCrate;
        std::string   module;
        bool          found = false;
        if( depth > 4 || !rustModuleOf( f, at, modPath, crate, module, 0 ) )
        {
            return kNoNode;
        }
        return rustItemAt( crate, module, cls, depth, found );
    }
    // the item `cls` of module (crate, module): a class declared at the module's own level (a file module's file level, an
    // inline mod's body), else a re-export there; an alias there names nothing. `found` false when the module has none.
    NodeId rustItemAt( std::uint32_t crate, const std::string& module, std::string_view cls, int depth, bool& found ) const
    {
        const auto   inl       = rust.inlineMods.find( rustModuleKey( crate, module ) );
        const NodeId inlineMod = inl == rust.inlineMods.end() ? kNoNode : inl->second;
        const Level  level     = rustModuleLevel( inlineMod );
        const auto   atLevel   = [ & ]( std::uint32_t file, std::uint32_t pos )
        {
            return inlineMod == kNoNode ? file < rust.crateOf.size() && rust.crateOf[ file ] == crate && rust.moduleOf[ file ] == module && levelAt( file, pos ).wholeFile()
                                        : file == ing.symbols[ inlineMod ].fileId && levelAt( file, pos ) == level;
        };
        NodeId            one = kNoNode;
        const std::size_t n   = classesNamed( cls, CallResultFamily::Rust, [ & ]( NodeId c )
        {
            const std::uint32_t cf = ing.symbols[ c ].fileId;   // an item of the module's own level, never of a mod or fn in it
            return inlineMod == kNoNode ? cf < rust.crateOf.size() && rust.crateOf[ cf ] == crate && rust.moduleOf[ cf ] == module && enclosingSymbol( c ) == kNoNode
                                        : enclosingSymbol( c ) == inlineMod;
        }, one );
        bool aliased = false;
        nameKey.assign( cls );
        if( const auto aliases = aliasesByName.find( nameKey ); aliases != aliasesByName.end() )
        {
            aliased = std::ranges::any_of( aliases->second, [ & ]( const Binding* b ) { return atLevel( b->fileId, b->startByte ); } );   // a Rust file's (atLevel)
        }
        if( n > 0 || aliased )
        {
            found = true;
            return n == 1 && !aliased ? one : kNoNode;
        }
        const auto files = rust.filesOf.find( rustModuleKey( crate, module ) );
        const std::vector<std::uint32_t> none;
        const std::vector<std::uint32_t>& of = inlineMod != kNoNode ? none : files == rust.filesOf.end() ? none : files->second;
        NodeId hit     = kNoNode;
        bool   globbed = false;   // rust-receivers: a glob at the module's level may bring the name in unseen (not followed)
        for( std::uint32_t mf : of )   // by reference: the layout's own list, never a copy
        {
            rustFollowReexports( mf, atLevel, cls, depth, hit, found, globbed );
        }
        if( inlineMod != kNoNode )
        {
            rustFollowReexports( ing.symbols[ inlineMod ].fileId, atLevel, cls, depth, hit, found, globbed );
        }
        found = found || globbed;
        return hit;
    }
    // rustItemAt's re-export step for one file `mf` of the module: each `use … cls` at the module's own level (`atLevel`) names
    // the class its path reaches (two: none; `found` set by any), and a glob there sets `globbed`
    template <class AtLevel>
    void rustFollowReexports( std::uint32_t mf, const AtLevel& atLevel, std::string_view cls, int depth, NodeId& hit, bool& found, bool& globbed ) const
    {
        if( mf >= importsByFile.size() )
        {
            return;
        }
        for( const Binding* b : importsByFile[ mf ] )
        {
            if( b->kind != LocalBindKind::TypeImport || ( b->var != cls && b->var != "*" ) || !atLevel( mf, b->startByte ) )
            {
                continue;
            }
            globbed = globbed || b->var == "*";
            if( b->var == cls )
            {
                const auto [ modPath, item ] = splitLast( b->importedName, "::" );
                const NodeId c = modPath.empty() ? kNoNode : rustClassAt( mf, b->startByte, modPath, item, depth + 1 );
                hit   = found ? kNoNode : c;
                found = true;
            }
        }
    }
    // (L) a qualified Rust call whose qualifier is a module path reaching `target`'s own module (`model::load()`,
    // `crate::nest::holder()`, a `use`d `nest::holder()`): the evidence the canonical tier, keyed by type scopes, lacks
    bool rustQualifierReaches( const Reference& r, NodeId target ) const
    {
        std::uint32_t crate = kNoCrate;
        std::string   module;
        if( callResultFamilyOf( r.lang ) != CallResultFamily::Rust || r.qualifier.empty() || !rustModuleOf( r.fileId, r.startByte, r.qualifier, crate, module, 0 ) )
        {
            return false;
        }
        const std::uint32_t tf = ing.symbols[ target ].fileId;
        std::string         targetModule;
        rustModuleAt( tf, ing.symbols[ target ].sigStartByte, targetModule );
        return tf < rust.crateOf.size() && rust.crateOf[ tf ] == crate && targetModule == module;
    }
    // RULE3-MEMBER-GUARD: what written binding proves `target` for a Rust call Rule 3 narrowed to it, an allowlist. A bare call: a `use`
    // of the name that does not provably leave the tree, or a glob `use` of the module holding the target. A qualified call: the
    // qualifier names the module holding the target, or the target's own type (`owner`). "Holding" takes a module's descendants too
    // and a crate root takes its whole crate, because a `pub use` re-export places an item below the path written. Not proven, counted
    // as via="name": `Ok(..)`, `assert!(..)`, a name only a glob of an unrelated module is near, `oneshot::channel()`, `String::new()` (those two then read as outside the tree, external=; graph.h).
    bool rustRule3Proves( const Reference& r, NodeId target, std::string_view owner ) const
    {
        if( !rust.built )
        {
            buildRustLayout();
        }
        const std::uint32_t tf = ing.symbols[ target ].fileId;
        if( tf >= rust.crateOf.size() || r.fileId >= rust.crateOf.size() )
        {
            return false;
        }
        std::string targetModule;
        rustModuleAt( tf, ing.symbols[ target ].sigStartByte, targetModule );
        std::uint32_t crate = kNoCrate;
        std::string   module;
        const auto    holdsTarget = [ & ]( std::string_view path, std::uint32_t at )
        {
            if( !rustModuleOf( r.fileId, at, path, crate, module, 0 ) || rust.crateOf[ tf ] != crate )
            {
                return false;
            }
            return module.empty() || targetModule == module || ( targetModule.starts_with( module ) && std::string_view( targetModule ).substr( module.size() ).starts_with( "::" ) );
        };
        if( !r.qualifier.empty() )
        {
            const std::size_t sep = r.qualifier.rfind( "::" );
            const std::string_view last = std::string_view( r.qualifier ).substr( sep == std::string::npos ? 0 : sep + 2 );
            if( !owner.empty() && last == owner )
            {
                return true;
            }
            bool aliased = false;   // `use nu_protocol::Value as NuValue; NuValue::nothing()`
            forEachRustUseAt( r.fileId, r.startByte, last, [ & ]( const Binding& b )
            {
                const std::size_t at = b.importedName.rfind( "::" );
                aliased = aliased || ( !owner.empty() && std::string_view( b.importedName ).substr( at == std::string::npos ? 0 : at + 2 ) == owner );
            } );
            return aliased || holdsTarget( r.qualifier, r.startByte );
        }
        bool proven = false;
        forEachRustUseAt( r.fileId, r.startByte, r.calleeName, [ & ]( const Binding& b )
        {
            proven = proven || !rustPathProvablyOutside( r.fileId, b.startByte, b.importedName );
        } );
        if( !proven )
        {
            forEachImport( r.fileId, "*", [ & ]( const Binding& b )
            {
                if( proven || b.kind != LocalBindKind::TypeImport )
                {
                    return;
                }
                bool brought = holdsTarget( b.importedName, b.startByte );
                if( !brought && rustModuleOf( r.fileId, b.startByte, b.importedName, crate, module, 0 ) )
                {
                    // `use super::*` over a module that itself `use`s the name (a `mod tests` calling what its parent imports), unless that `use` leaves the tree
                    rustItemAt( crate, module, r.calleeName, 0, brought );
                    brought = brought && !rustPathProvablyOutside( r.fileId, b.startByte, b.importedName + "::" + r.calleeName );
                }
                proven = brought;
            } );
        }
        return proven;
    }
    // fc1: does the Rust path `path` (a call's written qualifier, a `use`'s path) written at byte `at` of `f` PROVABLY lead out of
    // the tree — std / core / alloc, an external crate, an unknown root, the prelude, or an in-tree re-export of one? false
    // when it reaches an in-tree module or item, and whenever the walk cannot tell: two `use`s of the root, an in-tree glob
    // or an unparsed region of the file that may bring the name in, a depth cap. A file outside every crate's module tree
    // (a bench target) resolves no module: only a std / core / alloc root (by a `use` too) leads out there.
    bool rustPathOutside( std::uint32_t f, std::uint32_t at, std::string_view path, int depth = 0 ) const
    {
        if( !rust.built )
        {
            buildRustLayout();
        }
        if( depth > 4 )
        {
            pathCut = true;   // a cut, not an answer: a caller that would PROVE from "stays in the tree" reads this flag
            return false;
        }
        if( f >= rust.crateOf.size() || path.empty() )
        {
            return false;
        }
        const auto [ modPath, item ] = splitLast( path, "::" );
        std::uint32_t crate = kNoCrate;
        std::string   module;
        if( modPath.empty() || rust.crateOf[ f ] == kNoCrate || !rustModuleOf( f, at, modPath, crate, module, 0 ) )
        {
            return rustRootOutside( f, at, modPath.empty() ? item : modPath.substr( 0, modPath.find( "::" ) ), depth );
        }
        return rustReexportOutside( crate, module, item, depth );
    }
    // rustPathOutside, as a verdict: the path provably leaves the tree (an `impl other_crate::Renderer for X` names ANOTHER crate's
    // trait, not the in-tree one of that name). A cut walk, an empty path or a path into the tree is false.
    bool rustPathProvablyOutside( std::uint32_t f, std::uint32_t at, std::string_view path ) const
    {
        pathCut = false;
        return rustPathOutside( f, at, path ) && !pathCut;
    }
    // the files holding module (crate, module)'s own level: a file module's files, or (`inlineMod` set) the one file of an
    // inline `mod`, kept in `ownFile`; empty when no such module
    std::span<const std::uint32_t> rustModuleFiles( std::uint32_t crate, const std::string& module, NodeId& inlineMod, std::uint32_t& ownFile ) const
    {
        const auto inl = rust.inlineMods.find( rustModuleKey( crate, module ) );
        inlineMod      = inl == rust.inlineMods.end() ? kNoNode : inl->second;
        if( inlineMod != kNoNode )
        {
            ownFile = ing.symbols[ inlineMod ].fileId;
            return { &ownFile, 1 };
        }
        const auto files = rust.filesOf.find( rustModuleKey( crate, module ) );
        return files == rust.filesOf.end() ? std::span<const std::uint32_t>{} : std::span<const std::uint32_t>( files->second );
    }
    // rustPathOutside's in-tree module step: an item of module (crate, module) — a file module, or an inline `mod` (its
    // body) — leads out only through a named re-export at the module's own level (`pub use std::ffi::OsString;`), each
    // followed; an item declared there, or no such `use` (a glob, an unparsed region), never does
    bool rustReexportOutside( std::uint32_t crate, const std::string& module, std::string_view item, int depth ) const
    {
        NodeId        inlineMod = kNoNode;
        std::uint32_t ownFile   = 0;
        const auto    mfs       = rustModuleFiles( crate, module, inlineMod, ownFile );
        const Level   level     = rustModuleLevel( inlineMod );
        bool any = false;
        bool out = true;
        for( std::uint32_t mf : mfs )
        {
            NodeId one = kNoNode;
            if( classesNamed( item, CallResultFamily::Rust, [ & ]( NodeId c ) { return ing.symbols[ c ].fileId == mf && enclosingSymbol( c ) == inlineMod; }, one ) > 0 )
            {
                return false;
            }
            forEachImport( mf, item, [ & ]( const Binding& b )
            {
                if( b.kind == LocalBindKind::TypeImport && levelAt( mf, b.startByte ) == level )
                {
                    any = true;
                    out = out && rustPathOutside( mf, b.startByte, b.importedName, depth + 1 );
                }
            } );
        }
        return any && out;
    }
    // rustPathOutside's root step: the first segment `seg` of a path (or a bare type name) at byte `at` of `f`
    bool rustRootOutside( std::uint32_t f, std::uint32_t at, std::string_view seg, int depth ) const
    {
        if( seg == "crate" || seg == "self" || seg == "super" || seg == "Self" || rust.crateByName.contains( std::string( seg ) ) )
        {
            return false;
        }
        bool any = false;
        bool out = true;   // every `use` of the root in force (cfg-gated duplicates) leads out, or the walk keeps the row
        forEachRustUseAt( f, at, seg, [ & ]( const Binding& b )
        {
            any = true;
            out = out && rustPathOutside( f, b.startByte, b.importedName, depth + 1 );
        } );
        if( any )
        {
            return out;
        }
        std::string module;
        rustModuleAt( f, at, module );
        NodeId     one    = kNoNode;
        const bool inTree = rust.crateOf[ f ] != kNoCrate;
        if( ( inTree && rustModuleExists( rust.crateOf[ f ], joinModule( module, seg ) ) )
            || classesNamed( seg, CallResultFamily::Rust, [ & ]( NodeId c ) { return ing.symbols[ c ].fileId == f; }, one ) > 0 )
        {
            return false;   // a child module, or an item of this file
        }
        bool mayBring = rustGlobMayBring( f, at, seg, depth );   // a glob in force there, or an unparsed region of this file
        forEachImport( f, "!", [ & ]( const Binding& b ) { mayBring = mayBring || bindsWithoutTarget( b ); } );
        constexpr std::string_view kStdRoots[] = { "std", "core", "alloc" };   // the sysroot crates every target sees
        return !mayBring && ( inTree || std::ranges::find( kStdRoots, seg ) != std::end( kStdRoots ) );
    }
    // fc1 fix 1: may a glob `use` in force at byte `at` of `f` — one at a level of its chain (a fn body, then the module it
    // sits in; an outer module's globs never reach an inline `mod`) — bring the name `seg`? Only an in-tree glob whose
    // target module declares or re-exports `seg` in-tree (rustModuleMayBring); `mod tests { use super::*; }` never brings `std`
    struct GlobWalk
    {
        int                      depth;   // the glob chain's stack bound
        int                      base;    // the depth of the rustPathOutside walk this query runs under (a `use` it follows starts one deeper, so nesting stays bounded)
        std::vector<std::string> seen;    // fc1 fix 2: the (crate, module) keys this query already entered — a cycle brings nothing new
    };
    bool rustGlobMayBring( std::uint32_t f, std::uint32_t at, std::string_view seg, int depth ) const
    {
        GlobWalk walk{ 0, depth, {} };
        bool     may = false;
        forEachRustScopeAt( f, at, [ & ]( const Level& lv )
        {
            forEachImport( f, "*", [ & ]( const Binding& b )
            {
                may = may || ( levelAt( f, b.startByte ) == lv && rustGlobBrings( f, b, seg, walk ) );
            } );
            return may;
        } );
        return may;
    }
    // does the glob row `b` of file `f` — an in-tree one — bring `seg` (rustModuleMayBring of its target)?
    bool rustGlobBrings( std::uint32_t f, const Binding& b, std::string_view seg, GlobWalk& walk ) const
    {
        std::uint32_t gc = kNoCrate;
        std::string   gm;
        if( b.kind != LocalBindKind::TypeImport || !rustModuleOf( f, b.startByte, b.importedName, gc, gm, 0 ) )
        {
            return false;
        }
        ++walk.depth;
        const bool brings = rustModuleMayBring( gc, gm, seg, walk );
        --walk.depth;
        return brings;
    }
    // fc1 fix 3: does a named `use` of `seg` at `level` of file `mf` bring an in-tree binding (one that does not lead out)?
    // `named` is set when the level has one at all; a walk cut at rustPathOutside's depth cap proves nothing, so it is hedged
    bool rustNamedUsesBring( std::uint32_t mf, const Level& level, std::string_view seg, const GlobWalk& walk, bool& named ) const
    {
        bool       brings = false;
        const bool outer  = pathCut;   // a cut already taken by the enclosing walk (an earlier sibling glob) must survive this probe (CR #434)
        bool       cut    = false;
        forEachImport( mf, seg, [ & ]( const Binding& b )
        {
            if( b.kind == LocalBindKind::TypeImport && levelAt( mf, b.startByte ) == level )
            {
                named   = true;
                pathCut = false;
                const bool out = rustPathOutside( mf, b.startByte, b.importedName, walk.base + 1 );
                brings = brings || ( !out && !pathCut );
                cut    = cut || pathCut;   // a later `use` of the name must not clear an earlier one's cut either
            }
        } );
        pathCut = outer || cut;
        return brings;
    }
    // does module (crate, module) declare, or re-export from the tree, an item `seg` a glob of it brings — a child module, a
    // class or a `use` of the name at its own level that does not lead out (fc1 fix 2: a `use` of std's name there brings std's
    // binding, which is what the call sees; a private one reaches a child module's `super::*`), or a glob there whose target
    // does? fc1 fix 3: a named `use` of the name at a level shadows that level's globs (Rust's rule), so the named uses decide
    // alone and the globs are consulted only when there is none; a `use` whose walk was cut at rustPathOutside's depth cap does
    // not count as in-tree. Each module is entered once per query (`seen`: a glob cycle terminates with the true answer); the
    // depth cap is only a stack bound and answers "brings nothing" — the row is hedged, never proven onto an in-tree type
    bool rustModuleMayBring( std::uint32_t crate, const std::string& module, std::string_view seg, GlobWalk& walk ) const
    {
        if( walk.depth > 32 )
        {
            return false;
        }
        const std::string key = rustModuleKey( crate, module );
        if( std::ranges::find( walk.seen, key ) != walk.seen.end() )
        {
            return false;
        }
        walk.seen.push_back( key );
        if( rustModuleExists( crate, joinModule( module, seg ) ) )
        {
            return true;
        }
        NodeId        inlineMod = kNoNode;
        std::uint32_t ownFile   = 0;
        const auto    mfs       = rustModuleFiles( crate, module, inlineMod, ownFile );
        const Level   level     = rustModuleLevel( inlineMod );
        bool may = false;
        for( std::uint32_t mf : mfs )
        {
            NodeId one = kNoNode;
            may = may || classesNamed( seg, CallResultFamily::Rust, [ & ]( NodeId c ) { return ing.symbols[ c ].fileId == mf && enclosingSymbol( c ) == inlineMod; }, one ) > 0;
            bool named = false;   // fc1 fix 3: a named `use` of `seg` at this level shadows the level's globs (Rust's rule) and decides alone
            may = rustNamedUsesBring( mf, level, seg, walk, named ) || may;
            if( !named )
            {
                forEachImport( mf, "*", [ & ]( const Binding& b ) { may = may || ( levelAt( mf, b.startByte ) == level && rustGlobBrings( mf, b, seg, walk ) ); } );
            }
        }
        return may;
    }
    // `a::b::C` → ( `a::b`, `C` ); `C` → ( "", `C` ) — the last segment is namesplit::afterLast's
    static std::pair<std::string_view, std::string_view> splitLast( std::string_view path, std::string_view sep ) noexcept
    {
        const std::size_t at = path.rfind( sep );
        return { at == std::string_view::npos ? std::string_view{} : path.substr( 0, at ), namesplit::afterLast( path, sep ) };
    }
    // Rust (fix round 3: bareClassAt's rows): a bare name resolves at the callee's own level — its fn bodies, then its
    // module (a file, or an inline `mod`: a fresh scope, never the file's) — items, aliases and `use`s there first, then
    // the level's globs; a written path is relative to the module the callee sits in.
    NodeId rustResultClass( std::uint32_t fileId, std::uint32_t at, std::string_view whole, std::string_view cls ) const
    {
        if( !whole.empty() )
        {
            return rustClassAt( fileId, at, splitLast( whole, "::" ).first, cls );
        }
        if( !rust.built )
        {
            buildRustLayout();
        }
        return bareClassAt( CallResultFamily::Rust, fileId, at, cls );
    }

    // C++: the ONLY in-tree class named `cls` — none when two are, or (fix round 5) when a declaration only a macro can have
    // written (`class API cls {…}`) spells the name: the tree holds a class of it the index does not record
    NodeId onlyCppClass( std::string_view cls ) const
    {
        const std::string key( cls );
        const auto        it  = classIds->classesByName.find( key );
        const auto        rec = aliasesByName.find( key );   // the "unrecorded" rows ride the alias index (no span: no scope row)
        const bool unrecorded = rec != aliasesByName.end()
                             && std::ranges::any_of( rec->second, []( const Binding* b ) { return b->typeName == kTypeBindUnrecorded; } );
        return it == classIds->classesByName.end() || it->second.size() != 1 || unrecorded ? kNoNode : it->second[ 0 ];
    }
    // C++ / ObjC: Rule 2 keys a member by its class's NAME, so the class must be the ONLY in-tree class definition of that
    // name; a qualified result (`ns::T`) must also name its scope — an enclosing class of that name, the namespace path the
    // class is declared in, or a namespace its file declares non-members in — so an outside `ext::Config` never names the
    // in-tree `cfg::Config`. An unqualified result is cppUnqualifiedClass's.
    NodeId cppResultClass( std::string_view whole, std::string_view cls ) const
    {
        if( classIds == nullptr )
        {
            return kNoNode;
        }
        const NodeId c = onlyCppClass( cls );
        if( c == kNoNode )
        {
            return kNoNode;
        }
        const auto [ scope, last ] = splitLast( whole, "::" );
        if( last != cls || scope.empty() )
        {
            return kNoNode;
        }
        const NodeId outer = c < classIds->enclosingClass.size() ? classIds->enclosingClass[ c ] : kNoNode;
        if( outer != kNoNode && ing.symbols[ outer ].name == splitLast( scope, "::" ).second )
        {
            return c;
        }
        // (fix round 2) the class's own namespace path (its file's Namespace records) ends with the written scope,
        // segment-aligned: `net::wire::Frame` or `wire::Frame` for a Frame declared in namespace net::wire
        std::vector<std::string_view> classPath;
        std::vector<std::string_view> written;
        namespacePathAt( ing.symbols[ c ].fileId, ing.symbols[ c ].sigStartByte, classPath );
        appendSegments( scope, written );
        if( outer == kNoNode && written.size() <= classPath.size() && std::equal( written.rbegin(), written.rend(), classPath.rbegin() ) )
        {
            return c;
        }
        std::string nsKey;
        buildShadowKey( nsKey, ing.symbols[ c ].fileId, scope );
        return classIds->fileNamespaces.contains( nsKey ) ? c : kNoNode;
    }
    // `a::b::c` → a, b, c appended to `path`
    static void appendSegments( std::string_view qualified, std::vector<std::string_view>& path )
    {
        for( std::string_view rest = qualified;; )
        {
            const std::size_t sep = rest.find( "::" );
            path.push_back( rest.substr( 0, sep ) );
            if( sep == std::string_view::npos )
            {
                return;
            }
            rest.remove_prefix( sep + 2 );
        }
    }
    // C++ (fix round 2): the namespace path at byte `at` of file `f` — the Namespace records holding it, outermost first,
    // each name split at `::` (`namespace a::b` is two)
    void namespacePathAt( std::uint32_t f, std::uint32_t at, std::vector<std::string_view>& path ) const
    {
        path.clear();
        for( const Binding* ns : namespacesOf( f ) )
        {
            if( ns->spanStart <= at && at < ns->spanEnd )
            {
                appendSegments( ns->var, path );
            }
        }
    }
    // the namespace- and file-scope usings in force at byte `at` of file `f`: the file's own, declared before `at` in a scope
    // that holds it, and those of every in-tree header `f` includes (transitively) whose namespace path leads to `at`'s
    // (`calleePath`) — a header's `namespace cfg { using ext::Config; }` is in force in `namespace cfg` of the includer
    template <class Fn>
    void forEachCppUsing( std::uint32_t f, std::uint32_t at, const std::vector<std::string_view>& calleePath, Fn&& fn ) const
    {
        const auto rowsOf = [ & ]( std::uint32_t file, bool own )
        {
            if( file >= importsByFile.size() )
            {
                return;
            }
            for( const Binding* b : importsByFile[ file ] )
            {
                if( !isCppScopeRow( *b ) )
                {
                    continue;
                }
                if( own && !( b->startByte < at && b->spanStart <= at && at < b->spanEnd ) )
                {
                    continue;   // declared after the callee, or in a namespace that does not hold it
                }
                if( !own && innermostHolding( file, b->startByte, &notModule ) != kNoNode )
                {
                    continue;   // a class-scope alias (fix round 3) or a block-scope row (fix round 4) is in force in its own class / body only
                }
                if( !own )
                {
                    namespacePathAt( file, b->startByte, usingPath );
                    if( std::mismatch( usingPath.begin(), usingPath.end(), calleePath.begin(), calleePath.end() ).first != usingPath.end() )
                    {
                        continue;
                    }
                }
                fn( *b );
            }
        };
        rowsOf( f, true );
        if( fileIncludes == nullptr || f >= fileIncludes->size() )
        {
            return;
        }
        const std::vector<NodeId>& inc = ( *fileIncludes )[ f ];
        if( inc.size() < cppUsingFiles.size() )
        {
            for( NodeId h : inc )
            {
                if( h != f && std::binary_search( cppUsingFiles.begin(), cppUsingFiles.end(), std::uint32_t( h ) ) )
                {
                    rowsOf( std::uint32_t( h ), false );
                }
            }
            return;
        }
        for( std::uint32_t h : cppUsingFiles )
        {
            if( h != f && std::binary_search( inc.begin(), inc.end(), NodeId( h ) ) )
            {
                rowsOf( h, false );
            }
        }
    }
    // C++ (fix round 2): an UNQUALIFIED result `T` declared at byte `at` of file `f` names the ONLY in-tree class `T` only
    // where C++'s own lookup reaches it: a using-declaration of `T` in force there decides (its path resolves as a written
    // `ns::T` would — an outside `using ext::T;` names nothing); else a nested or local class must enclose the declaration
    // (visibleAt), and a namespace-scope class's namespace must enclose the declaration's own namespace or be named by a
    // using-directive in force there. An outside using-directive cannot make the in-tree class wrong — `T` would then be
    // ambiguous — so it never needs a refusal of its own. Fix round 4: then a binding of `T` the index keeps no class for
    // (cppHiddenAt) may still hide the class.
    NodeId cppUnqualifiedClass( std::uint32_t f, std::uint32_t at, std::string_view cls ) const
    {
        if( classIds == nullptr )
        {
            return kNoNode;
        }
        const NodeId c = onlyCppClass( cls );
        if( c == kNoNode )
        {
            return kNoNode;
        }
        // fix round 3: a member type a base of an enclosing class declares (a nested class, a member alias) is in scope
        // there and is not followed — the spelling names nothing
        std::vector<Level> chain;
        chainAt( f, at, chain );
        for( const Level& lv : chain )
        {
            if( lv.sym != kNoNode && classKind( ing.symbols[ lv.sym ].kind ) && inheritsMemberType( lv.sym, cls, CallResultFamily::Cpp ) )
            {
                return kNoNode;
            }
        }
        std::vector<std::string_view> calleePath;
        namespacePathAt( f, at, calleePath );
        const CppReach reach = cppReach( f, at, c, calleePath );
        return reach == CppReach::None || cppHiddenAt( f, at, c, calleePath, reach ) ? kNoNode : c;
    }
    // how the class `c` (the only in-tree class of its name) is reached from byte `at` of file `f` (cppUnqualifiedClass): through a
    // using-declaration of `cls` in force, as a nested / local class enclosing `at`, from a namespace leading the callee's,
    // through a using-directive — or not at all
    enum class CppReach : std::uint8_t { None, Declared, Nested, Leads, Directive };
    CppReach cppReach( std::uint32_t f, std::uint32_t at, NodeId c, const std::vector<std::string_view>& calleePath ) const
    {
        const std::string_view cls = ing.symbols[ c ].name;
        bool   declared = false;
        NodeId byDecl   = kNoNode;
        forEachCppUsing( f, at, calleePath, [ & ]( const Binding& b )
        {
            if( b.var == cls && !bindsWithoutTarget( b ) )   // a using-declaration resolves as a written `ns::T`; an alias (fix round 3) names nothing
            {
                const NodeId named = b.kind == LocalBindKind::TypeAlias ? kNoNode : cppResultClass( b.importedName, cls );
                byDecl   = declared && named != byDecl ? kNoNode : named;
                declared = true;
            }
        } );
        if( declared )
        {
            return byDecl == c ? CppReach::Declared : CppReach::None;
        }
        if( enclosingSymbol( c ) != kNoNode )
        {
            return visibleAt( c, f, at ) ? CppReach::Nested : CppReach::None;
        }
        std::vector<std::string_view> classPath;
        namespacePathAt( ing.symbols[ c ].fileId, ing.symbols[ c ].sigStartByte, classPath );
        if( std::mismatch( classPath.begin(), classPath.end(), calleePath.begin(), calleePath.end() ).first == classPath.end() )   // it leads the callee's
        {
            return CppReach::Leads;
        }
        bool named = false;
        forEachCppUsing( f, at, calleePath, [ & ]( const Binding& b )
        {
            if( b.var != "*" || named )
            {
                return;
            }
            // `using namespace a::b;` names the class's path itself, or its tail relative to a namespace enclosing the callee
            std::vector<std::string_view> dir;
            appendSegments( b.importedName, dir );
            if( dir.size() <= classPath.size() && std::equal( dir.rbegin(), dir.rend(), classPath.rbegin() ) )
            {
                const std::vector<std::string_view> head( classPath.begin(), classPath.end() - std::ptrdiff_t( dir.size() ) );
                named = std::mismatch( head.begin(), head.end(), calleePath.begin(), calleePath.end() ).first == head.end();
            }
        } );
        return named ? CppReach::Directive : CppReach::None;
    }
    // fix round 4: is the class `c` that `reach` found HIDDEN at byte `at` of file `f` by a binding of its name the index keeps
    // no class for, in force there (forEachCppUsing's scope rule): a union, a forward declaration of `cls`, or a macro / parse
    // error, which may declare any name. Such a binding hides `c` when it is in an inner scope: a class or function body (unless it is a forward
    // declaration of `c` itself, inside it), or — for a namespace-scope `c` that leads the callee's namespace — a namespace
    // deeper than `c`'s own. A forward declaration in `c`'s own namespace declares `c`; a binding outside the scope `c` is
    // nested in is hidden BY `c`. A class reached through a using-declaration or a using-directive is hidden by any such
    // binding in force (C++ puts a directive's names at a namespace this reader does not compute).
    bool cppHiddenAt( std::uint32_t f, std::uint32_t at, NodeId c, const std::vector<std::string_view>& calleePath, CppReach reach ) const
    {
        const Symbol&                 cs  = ing.symbols[ c ];
        const std::string_view        cls = cs.name;
        std::vector<std::string_view> classPath;
        std::vector<std::string_view> rowPath;
        namespacePathAt( cs.fileId, cs.sigStartByte, classPath );
        bool hidden = false;
        forEachCppUsing( f, at, calleePath, [ & ]( const Binding& b )
        {
            if( hidden || !bindsWithoutTarget( b ) || ( b.typeName != kTypeBindUnparsed && b.var != cls ) )   // an unparsed region may declare any name
            {
                return;
            }
            const bool forward = b.typeName == kTypeBindForward;
            if( innermostHolding( b.fileId, b.startByte, &notModule ) != kNoNode )   // a class or function body (own file only)
            {
                hidden = !( forward && b.fileId == cs.fileId && b.spanStart <= cs.sigStartByte && cs.sigStartByte < b.spanEnd );
                return;
            }
            namespacePathAt( b.fileId, b.startByte, rowPath );
            switch( reach )
            {
                case CppReach::Nested: return;   // `c` is nested in a class or body: deeper than any namespace
                case CppReach::Leads:  hidden = rowPath.size() > classPath.size(); return;   // both lead the callee's: longer is deeper
                default:               hidden = !( forward && rowPath == classPath ); return;
            }
        } );
        return hidden;
    }

    // C++ (fix round 3): does the first segment of a qualified result (`lib` in `lib::T`) name a namespace alias (or any
    // alias) in force at byte `at` of `f` — `namespace lib = ext;` makes `lib::T` ext's, never an in-tree namespace lib's
    bool cppQualifierAliased( std::uint32_t f, std::uint32_t at, std::string_view whole ) const
    {
        const std::string_view head = whole.substr( 0, whole.find( "::" ) );
        std::vector<std::string_view> calleePath;
        namespacePathAt( f, at, calleePath );
        bool aliased = false;
        forEachCppUsing( f, at, calleePath, [ & ]( const Binding& b ) { aliased = aliased || ( b.kind == LocalBindKind::TypeAlias && b.var == head ); } );
        return aliased;
    }

    // the class a ReturnType record's written type resolves to in its own (the callee's) file — kNoNode for none or several
    NodeId resultClassOf( const Binding& rt, Lang lang ) const
    {
        switch( callResultFamilyOf( lang ) )
        {
            case CallResultFamily::Go:         return goResultClass( rt.fileId, rt.startByte, rt.importedName, rt.typeName );
            case CallResultFamily::Jvm:        return jvmResultClass( rt.fileId, rt.startByte, rt.importedName, rt.typeName );
            case CallResultFamily::TypeScript: return tsResultClass( rt.fileId, rt.startByte, rt.importedName, rt.typeName );
            case CallResultFamily::Rust:       return rustResultClass( rt.fileId, rt.startByte, rt.importedName, rt.typeName );
            case CallResultFamily::Cpp:        return rt.importedName.empty() ? cppUnqualifiedClass( rt.fileId, rt.startByte, rt.typeName )
                                                    : cppQualifierAliased( rt.fileId, rt.startByte, rt.importedName ) ? kNoNode
                                                                                                                      : cppResultClass( rt.importedName, rt.typeName );
            default:                           return kNoNode;
        }
    }

    // lane L6: the class (or interface) a bare type NAME spelled at byte `at` of file `fileId` resolves to in language `lang`'s
    // scopes — resultClassOf's rows for a written, unqualified type; kNoNode for none, several, or a family with no rows
    NodeId classAtSite( Lang lang, std::uint32_t fileId, std::uint32_t at, std::string_view cls ) const
    {
        switch( callResultFamilyOf( lang ) )
        {
            case CallResultFamily::Go:         return goResultClass( fileId, at, {}, cls );
            case CallResultFamily::Jvm:        return jvmResultClass( fileId, at, {}, cls );
            case CallResultFamily::TypeScript: return tsResultClass( fileId, at, {}, cls );
            case CallResultFamily::Rust:       return rustResultClass( fileId, at, {}, cls );
            default:                           return kNoNode;
        }
    }

    // the in-tree class-likes of `cls`'s language sharing its name (cls included)
    std::size_t sameNamedClasses( NodeId cls ) const
    {
        NodeId one = kNoNode;
        return classesNamed( ing.symbols[ cls ].name, callResultFamilyOf( ing.symbols[ cls ].lang ), []( NodeId ) { return true; }, one );
    }
};

struct ReceiverEvidence
{
    static constexpr std::size_t kWalkCap = 64;   // classes visited per base walk; deterministic (sorted chaUp)

    const IngestResult&                                   ing;
    const HashMap<std::string, std::vector<std::string>>& chaUp;       // class name → its direct base names (sorted)
    const HashMap<std::string, char>&                     classNames;  // every in-repo class-like name
    std::vector<std::string>                              ownerClass;  // per symbol: the class that owns it, "" none
    std::vector<std::uint8_t>                             staticMember;    // per symbol: 1 = a JS/TS `static` member (the CLASS side)
    HashMap<std::string, rw::SmallVec<NodeId, 2>>         methodsByType;   // "Class::name" → its callables
    HashMap<std::string, rw::SmallVec<NodeId, 2>>         abstractByType;  // "Class::name" → its BODYLESS callables (the contract a call dispatches through)
    HashMap<std::string_view, char>                       abstractNames;   // every name some class declares without a body (the gate of the two walks below)
    HashMap<std::string, std::string>                     memberType;      // "Class#field" → field class ("" = tombstone)
    HashMap<std::string, NodeId>                          memberClass;     // rust-receivers: "<class id>#field" → the ONE class its written type resolved to (kNoNode = unknown)
    HashMap<std::string, NodeId>                          memberIface;     // lane L6: "<class id>#field" → the trait a `Box<dyn T>` field dispatches through (kNoNode = disagree)
    HashMap<std::string, std::vector<std::string>>        embeds;          // "Class" → its other bases: Go embedded classes (promotion)
    HashMap<std::string, std::string>                     nameAlias;       // "<fileId>#local" → the class name it imports
    // FE-B (review B4): one binding of a local name — the class it names ("" = unknown: it hides an outer binding of the
    // name and proves nothing) and the bytes it is visible in. end == 0: a record with no span (a Python name, a reassignment,
    // a base pass Type record): somewhere in its definition, extent unknown.
    struct LocalFact
    {
        std::uint32_t start = 0;
        std::uint32_t end   = 0;
        std::string   type;
        NodeId        cls   = kNoNode;   // (L) fix round 1: the ONE in-tree class `type` resolved to (kNoNode: the name alone)
        NodeId        iface = kNoNode;   // lane L6: a binding typed only as SOME implementor of this trait (type stays "")
        std::string   bound;             // lane L6: a generic bound's text (`R: Renderer`), "" otherwise
        bool operator==( const LocalFact& ) const = default;
    };
    HashMap<std::string, std::vector<LocalFact>>          localType;       // "<fromSymbol>#var" → its bindings
    HashMap<std::string, std::pair<std::string, std::string>> methodAlias; // "<fromSymbol>#var" → ( object var, method )
    HashMap<std::string, std::string>                     moduleAlias;     // "<fileId>#name" → module as written ("" = tombstone)
    std::vector<std::vector<NodeId>>                      fnsByFile;       // fileId → functions/methods sorted by start (enclosing walk)
    std::vector<std::vector<NodeId>>                      classesByFile;   // fileId → class-like symbols sorted by start
    mutable std::string                                   key;
    mutable std::vector<std::string_view>                 frontier;
    mutable rw::SmallVec<NodeId, 2>                       found;
    bool                                                  active = false;
    const HashMap<std::string, char>*                     localNames = nullptr;   // graph.h FieldNarrowTables::localNameSet
    const GoPackagePaths*                                 goPackages = nullptr;   // graph.h FalseEdgeRules::goPackages
    const HashMap<std::string, char>*                     qualifierVerdicts = nullptr;   // graph.h buildQualifierVerdicts (h1-annot)
    mutable HashMap<std::string, char>                    namespaceNames;           // every Namespace record's name and its roots, on first use
    mutable bool                                          namespaceNamesBuilt = false;
    std::vector<std::pair<NodeId, std::string_view>>      operatorResult;           // OperatorResult methods → "self" / their class, sorted (h1-annot)
    std::vector<const Binding*>                           augDropped;               // AugAssign records that dropped their name's class:
                                                                                    //   graph.h tombstones Rule 2's varType entry too
    HashMap<std::string, std::uint32_t>                   callResultDecls;          // "<scope>#var" → its CallResult records (typeCallResult)
    CallResultTypes                                       types;                    // (L) fix round 1: a declared result type's ONE class

    ReceiverEvidence( const IngestResult& i, const HashMap<std::string, std::vector<std::string>>& up, const HashMap<std::string, char>& classes )
        : ing( i ), chaUp( up ), classNames( classes ), types( i ) {}

    static bool classLike( SymKind k ) noexcept { return CallResultTypes::classKind( k ); }
    static bool callableKind( SymKind k ) noexcept
    {
        return k == SymKind::Method || k == SymKind::Function;
    }
    const std::string& keyOf( std::uint32_t id, char sep, std::string_view name ) const
    {
        key.clear();
        key.append( std::to_string( id ) );
        key.push_back( sep );
        key.append( name );
        return key;
    }
    const std::string& typeKey( std::string_view type, std::string_view sep, std::string_view name ) const
    {
        key.assign( type );
        key.append( sep );
        key.append( name );
        return key;
    }

    // ── build ─────────────────────────────────────────────────────────────────────────────────────────────────────────
    static void tombstoneInsert( HashMap<std::string, std::string>& m, const std::string& k, std::string_view v )
    {
        const auto [ it, fresh ] = m.try_emplace( k, std::string( v ) );
        if( !fresh && it->second != v )
        {
            it->second.clear();   // two different classes for one name: decide nothing
        }
    }

    void addLocalFact( const std::string& k, const Binding& b ) { addTypedFact( k, b, b.typeName, kNoNode ); }
    // the same fact naming `type` instead of the binding's own (a qualified written type refused: ""), and the one class it
    // resolved to (kNoNode: the name alone)
    void addTypedFact( const std::string& k, const Binding& b, std::string_view type, NodeId cls )
    {
        addFact( k, factOf( b, type, cls ) );
    }
    // the fact a binding states over its span ({0,0}: no span), naming `type` / `cls`
    static LocalFact factOf( const Binding& b, std::string_view type, NodeId cls )
    {
        const bool spanned = b.spanEnd > b.spanStart;
        return LocalFact{ spanned ? b.spanStart : 0u, spanned ? b.spanEnd : 0u, std::string( type ), cls };
    }
    void addFact( const std::string& k, LocalFact f )
    {
        std::vector<LocalFact>&     facts = localType[ k ];
        if( std::none_of( facts.begin(), facts.end(), [ & ]( const LocalFact& g ) { return g == f; } ) )
        {
            facts.push_back( std::move( f ) );
        }
    }

    void buildOwners()
    {
        const std::size_t N = ing.symbols.size();
        ownerClass.assign( N, {} );
        // the classes of each file by start; a symbol's owner is the innermost class whose span holds it
        classesByFile.assign( ing.files.size(), {} );
        fnsByFile.assign( ing.files.size(), {} );
        for( const Symbol& s : ing.symbols )
        {
            if( s.fileId >= ing.files.size() )
            {
                continue;
            }
            if( classLike( s.kind ) )
            {
                classesByFile[ s.fileId ].push_back( s.id );
            }
            if( classLike( s.kind ) || s.kind == SymKind::NamedType )
            {
                types.noteClass( s );   // a Go `type N int` has methods too: a result or field type may name it
            }
            if( callableKind( s.kind ) )
            {
                fnsByFile[ s.fileId ].push_back( s.id );
            }
        }
        const auto byStart = [ & ]( NodeId a, NodeId b ) { return ing.symbols[ a ].sigStartByte != ing.symbols[ b ].sigStartByte
                                                                  ? ing.symbols[ a ].sigStartByte < ing.symbols[ b ].sigStartByte : a < b; };
        for( std::vector<NodeId>& v : classesByFile ) { std::sort( v.begin(), v.end(), byStart ); }
        for( std::vector<NodeId>& v : fnsByFile )     { std::sort( v.begin(), v.end(), byStart ); }
        for( const Symbol& s : ing.symbols )
        {
            if( !s.scope.empty() )
            {
                ownerClass[ s.id ] = s.scope;   // the extractor's own scope (Python, C++, Kotlin, Ruby, JS prototype members)
                continue;
            }
            if( s.fileId >= ing.files.size() || classLike( s.kind ) )
            {
                continue;
            }
            if( const NodeId best = classAt( s.fileId, s.sigStartByte, s.endByte, s.id ); best != kNoNode )
            {
                ownerClass[ s.id ] = ing.symbols[ best ].name;
            }
        }
        // Go spells a method's class only on its receiver: the RecvType record that sets isFromAssignment
        for( const Binding& b : ing.bindings )
        {
            if( b.kind == LocalBindKind::RecvType && b.isFromAssignment && b.fromSymbol < N && !b.typeName.empty() )
            {
                ownerClass[ b.fromSymbol ] = b.typeName;
            }
        }
        ENSURES( ownerClass.size() == N && fnsByFile.size() == ing.files.size() && classesByFile.size() == ing.files.size(),
                 "one owner per symbol, one sorted list per file" );
    }

    // the innermost class-like symbol of `fileId` whose span holds [start, end) (never `self`); kNoNode when none
    NodeId classAt( std::uint32_t fileId, std::uint32_t start, std::uint32_t end, NodeId self = kNoNode ) const
    {
        NodeId best = kNoNode;
        if( fileId >= classesByFile.size() )
        {
            return best;
        }
        for( NodeId c : classesByFile[ fileId ] )
        {
            const Symbol& cs = ing.symbols[ c ];
            if( cs.sigStartByte > start )
            {
                break;
            }
            if( cs.id != self && cs.endByte >= end )
            {
                best = c;   // later starts are more inner
            }
        }
        return best;
    }
    void addBase( const std::string& owner, std::string_view base )
    {
        std::vector<std::string>& e = embeds[ owner ];
        if( std::find( e.begin(), e.end(), base ) == e.end() )
        {
            e.emplace_back( base );
            std::sort( e.begin(), e.end() );
        }
    }
    void build()
    {
        buildOwners();
        staticMember.assign( ing.symbols.size(), 0u );
        for( const Symbol& s : ing.symbols )
        {
            // a BODIED callable only: an interface's or an abstract class's bodyless signature is the contract a call
            // dispatches through, never the body it reaches — that call stays with the ladder (declined_iface= reads it)
            if( callableKind( s.kind ) && !ownerClass[ s.id ].empty() && receiverHedgeLang( s.lang ) )
            {
                ( s.endByte > s.sigEndByte ? methodsByType : abstractByType )[ typeKey( ownerClass[ s.id ], "::", s.name ) ].push_back( s.id );
                if( s.endByte <= s.sigEndByte )
                {
                    abstractNames.try_emplace( std::string_view( s.name ), char( 1 ) );
                }
            }
        }
        const std::size_t N = ing.symbols.size();
        std::vector<const Binding*> qualified;   // locals, parameters and fields written `pkg.T`: decided once every import alias is known
        std::vector<const Binding*> written;     // rust-receivers: Rust locals, parameters and fields written (or constructed) as a type
        std::vector<const Binding*> dispatch;    // lane L6: Rust locals, parameters and fields typed only through a trait (DispatchType)
        std::vector<const Binding*> augAssigns;  // Python `x op= v`: decided once every fact and method is known (h1-annot)
        types.importsByFile.assign( ing.files.size(), {} );
        types.filePackage.assign( ing.files.size(), {} );
        types.moduleAlias = &moduleAlias;
        types.goPackages  = goPackages;
        for( const Binding& b : ing.bindings )
        {
            noteCallResultFacts( b );
            if( b.kind == LocalBindKind::ModuleAlias && b.fromSymbol == kNoNode && !b.var.empty() && !b.isFromAssignment )
            {
                tombstoneInsert( moduleAlias, keyOf( b.fileId, '#', b.var ), b.typeName );
                continue;
            }
            if( b.kind == LocalBindKind::NameAlias && !b.var.empty() )
            {
                tombstoneInsert( nameAlias, keyOf( b.fileId, '#', b.var ), b.typeName );
                continue;
            }
            if( b.kind == LocalBindKind::JsImport && !b.var.empty() && !b.importedName.empty() && b.importedName != b.var )
            {
                tombstoneInsert( nameAlias, keyOf( b.fileId, '#', b.var ), b.importedName );   // `import { Context as Ctx }`
                continue;
            }
            if( b.fromSymbol >= N )
            {
                continue;
            }
            const NodeId from = factScope( b );
            const bool typedLocal = b.kind == LocalBindKind::RecvType
                                 || ( b.kind == LocalBindKind::Type && ( ing.symbols[ b.fromSymbol ].lang == Lang::TypeScript
                                                                         || ing.symbols[ b.fromSymbol ].lang == Lang::Python ) );
            if( b.kind == LocalBindKind::DispatchType )
            {
                if( !b.var.empty() && !b.typeName.empty() )
                {
                    dispatch.push_back( &b );
                }
            }
            else if( b.kind == LocalBindKind::StaticMember )
            {
                if( ing.symbols[ from ].name == b.var )   // recorded inside the member's body: the member itself
                {
                    staticMember[ from ] = 1;
                }
            }
            else if( ( b.kind == LocalBindKind::RecvType || b.kind == LocalBindKind::MemberType ) && !b.var.empty() && !b.typeName.empty()
                     && callResultFamilyOf( ing.symbols[ b.fromSymbol ].lang ) == CallResultFamily::Rust )
            {
                written.push_back( &b );   // rust-receivers: a written Rust type resolves like a declared result, once imports are known
            }
            else if( ( b.kind == LocalBindKind::RecvType || b.kind == LocalBindKind::MemberType ) && !b.var.empty() && !b.importedName.empty() )
            {
                qualified.push_back( &b );
            }
            else if( typedLocal && !b.var.empty() )
            {
                addLocalFact( keyOf( from, '#', b.var ), b );
            }
            else if( b.kind == LocalBindKind::MemberType && !b.var.empty() )
            {
                noteMemberType( b, b.typeName );
            }
            else if( b.kind == LocalBindKind::MethodAlias && !b.var.empty() )
            {
                const auto [ it, fresh ] = methodAlias.try_emplace( keyOf( from, '#', b.var ), b.typeName, b.importedName );
                if( !fresh && ( it->second.first != b.typeName || it->second.second != b.importedName ) )
                {
                    it->second.first.clear();   // rebound to something else: decide nothing
                }
            }
            else if( b.kind == LocalBindKind::AugAssign && !b.var.empty() )
            {
                augAssigns.push_back( &b );
            }
            else if( b.kind == LocalBindKind::OperatorResult )
            {
                operatorResult.emplace_back( b.fromSymbol, b.typeName );
            }
        }
        types.finishIndex();
        for( const Binding* q : qualified )
        {
            noteQualifiedWritten( *q );
        }
        for( const Binding* w : written )
        {
            noteResolvedWritten( *w );
        }
        for( const Binding* d : dispatch )
        {
            noteDispatchWritten( *d );
        }
        std::ranges::sort( operatorResult, []( const std::pair<NodeId, std::string_view>& a, const std::pair<NodeId, std::string_view>& b )
                           { return a.first != b.first ? a.first < b.first : sortutil::svLess( a.second, b.second ); } );
        active = true;
        for( const Binding* a : augAssigns )
        {
            noteAugAssign( *a );   // reads methodOf: after `active`
        }
    }
    // Lane h1-annot: a Python `x op= v` rebinds `x` to what the operator returns. The class C `x` holds in its scope — every
    // typed fact of the name agreeing on ONE class — survives only when the method Python calls is ONE definition whose
    // OperatorResult record names "self" or C: C's in-place method `a.typeName` (`__iadd__`; its own, else the shallowest
    // base's: methodOf), else — C defines none in its cone — its binary method `a.importedName` (`__add__`: `x = x + v`).
    // Otherwise (a result that is not provably C, two definitions, neither method) `x` gets a tombstone, as a plain
    // reassignment does. A name with no typed fact is left alone (nothing to drop).
    // test/receiverevidencecheck.sh (Q) AugNotSelf / AugNoDunder / AugOtherOp [N], AugSelf / AugIorSelf / AugInherited /
    // AugBinaryAnnotated [P].
    void noteAugAssign( const Binding& a )
    {
        const std::string k   = keyOf( factScope( a ), '#', a.var );   // a copy: methodOf reuses the key buffer
        const auto        it  = localType.find( k );
        if( it == localType.end() )
        {
            return;
        }
        std::string_view cls;
        NodeId           id  = kNoNode;
        bool             one = true;
        for( const LocalFact& f : it->second )
        {
            if( f.type.empty() )
            {
                continue;
            }
            one = one && ( cls.empty() || ( f.type == cls && f.cls == id ) );
            if( cls.empty() )
            {
                cls = f.type;
                id  = f.cls;
            }
        }
        if( cls.empty() || ( one && operatorKeepsClass( cls, id, a.typeName, a.importedName ) ) )
        {
            return;
        }
        addTypedFact( k, a, {}, kNoNode );
        augDropped.push_back( &a );
    }
    // (L) the call-result facts one binding feeds: the file's imports (CallResultTypes) and the function's call-initialised
    // bindings of each name (typeCallResult's TS guess rule)
    void noteCallResultFacts( const Binding& b )
    {
        types.noteImport( b );
        if( b.kind == LocalBindKind::CallResult && b.fromSymbol < ing.symbols.size() && !b.var.empty() )
        {
            ++callResultDecls[ keyOf( factScope( b ), '#', b.var ) ];
        }
    }
    // a field's class on its owner (`type` "": unknown, a tombstone); an embedded field (Go) is also a base
    void noteMemberType( const Binding& b, std::string_view type )
    {
        const Symbol&      from  = ing.symbols[ b.fromSymbol ];
        const std::string& owner = classLike( from.kind ) ? from.name : ownerClass[ b.fromSymbol ];
        if( owner.empty() )
        {
            return;
        }
        tombstoneInsert( memberType, typeKey( owner, "#", b.var ), type );
        if( b.isFromAssignment && !type.empty() )
        {
            addBase( owner, type );
        }
    }
    // a local, parameter or field written `pkg.T` (importedName = the qualified text: the Go, Python and TS captures write it)
    // names a class of THIS tree only when its qualifier passes the language's WrittenQualifierRule: Go — `pkg` imports an
    // in-tree package defining it (CallResultTypes::goQualifiedClass): `f *os.File` beside an in-tree `File` is os's File,
    // never ours (test/receiverevidencecheck.sh (L) NearOSParam, NearOSField); Python / TS (h1-annot) — the qualifier is an
    // in-tree module or namespace (qualifierInTree): `s: requests.Session`, `s: ext.Session<T>` beside an in-tree Session
    // prove nothing ((Q) PyModT, TsNsT). Anything else keeps the name as a tombstone. A Go local carries the class it resolved to.
    void noteQualifiedWritten( const Binding& q )
    {
        EXPECTS( q.fromSymbol < ing.symbols.size() && !q.importedName.empty(), "build() queues only attributed records that carry a qualifier" );
        NodeId cls  = kNoNode;
        bool   keep = false;
        switch( writtenQualifierRuleOf( ing.symbols[ q.fromSymbol ].lang ) )
        {
            case WrittenQualifierRule::GoPackage:
                cls  = types.goQualifiedClass( q.fileId, q.importedName, q.typeName );
                keep = cls != kNoNode;
                break;
            case WrittenQualifierRule::FileImport: keep = qualifierInTree( q.fileId, q.importedName ); break;
            case WrittenQualifierRule::None:       break;
        }
        const std::string_view type = keep ? std::string_view( q.typeName ) : std::string_view{};
        if( q.kind == LocalBindKind::MemberType )
        {
            noteMemberType( q, type );
            return;
        }
        addTypedFact( keyOf( factScope( q ), '#', q.var ), q, type, cls );
    }
    // rust-receivers: a Rust local, parameter or field WRITTEN as a type (or constructed: `T { .. }`, `T::default()`) names the
    // ONE in-tree class that spelling resolves to at its own site, by the call-result rule (CallResultTypes::resultClassOf: the
    // item scopes innermost first with their `use`s, items and aliases, then a path from crate / self / super / an in-tree crate
    // or module; an outside, unresolved or doubly bound spelling names nothing). Never a TRAIT (`&Renderer`, a bare trait
    // object: which impl runs is dispatch, lane L6). Anything else keeps the binding as a tombstone: it hides an outer binding
    // of the name and proves nothing. A field carries its class into memberClass, which the path walk reads.
    void noteResolvedWritten( const Binding& w )
    {
        NodeId cls = types.resultClassOf( w, ing.symbols[ w.fromSymbol ].lang );
        if( cls != kNoNode && ing.symbols[ cls ].kind == SymKind::Interface )
        {
            cls = kNoNode;
        }
        const std::string_view type = cls != kNoNode ? std::string_view( ing.symbols[ cls ].name ) : std::string_view{};
        if( w.kind == LocalBindKind::MemberType )
        {
            if( classLike( ing.symbols[ w.fromSymbol ].kind ) )   // the struct declaring the field, by its own definition
            {
                const auto [ it, fresh ] = memberClass.try_emplace( keyOf( w.fromSymbol, '#', w.var ), cls );
                if( !fresh && it->second != cls )
                {
                    it->second = kNoNode;   // two declarations of the field disagree: decide nothing
                }
            }
            return;
        }
        addTypedFact( keyOf( factScope( w ), '#', w.var ), w, type, cls );
    }
    // lane L6: a Rust parameter, local or field typed only as SOME implementor of a trait (model.h LocalBindKind::DispatchType)
    // — `&dyn T`, `Box<dyn T>`, `impl T`, a generic bounded by T. The trait resolves at the binding's own site like a written
    // type (resultClassOf's Rust rows) and must be a trait (SymKind::Interface); the binding then types no class: a local or
    // parameter is the tombstone it replaces, carrying the trait beside it, and a field its memberIface entry (the field's
    // memberClass tombstone was recorded by its own MemberType). Read by dispatchReceiverOf, for the dispatch tier alone.
    void noteDispatchWritten( const Binding& d )
    {
        const std::string_view imported = d.importedName;
        const std::size_t      colon    = imported.find( ": " );
        const std::string_view bound    = colon == std::string_view::npos ? std::string_view{} : imported;
        const std::string_view written  = colon == std::string_view::npos ? imported : imported.substr( colon + 2 );
        const std::string_view whole    = written.find( "::" ) == std::string_view::npos ? std::string_view{} : written;
        NodeId trait = types.rustResultClass( d.fileId, d.startByte, whole, d.typeName );
        if( trait != kNoNode && ing.symbols[ trait ].kind != SymKind::Interface )
        {
            trait = kNoNode;   // a class of that name: `dyn` / `impl` / a bound name a trait, never a class
        }
        if( d.isFromAssignment )   // a struct's field
        {
            if( classLike( ing.symbols[ d.fromSymbol ].kind ) )
            {
                const auto [ it, fresh ] = memberIface.try_emplace( keyOf( d.fromSymbol, '#', d.var ), trait );
                if( !fresh && it->second != trait )
                {
                    it->second = kNoNode;   // two declarations of the field disagree: decide nothing
                }
            }
            return;
        }
        LocalFact f = factOf( d, std::string_view{}, kNoNode );   // the tombstone it stands in for, carrying the trait
        f.iface = trait;
        f.bound.assign( bound );
        addFact( keyOf( factScope( d ), '#', d.var ), std::move( f ) );
    }
    // is the result of the operator Python calls on a `cls` receiver (`inPlace`, else `binary`) provably `cls` (noteAugAssign)
    bool operatorKeepsClass( std::string_view cls, NodeId id, std::string_view inPlace, std::string_view binary ) const
    {
        if( !methodOf( cls, inPlace, false, id ) && ( binary.empty() || !methodOf( cls, binary, false, id ) ) )
        {
            return false;
        }
        if( found.size() != 1 )
        {
            return false;
        }
        const auto row = std::ranges::lower_bound( operatorResult, found[ 0 ], []( NodeId a, NodeId b ) { return a < b; },
                                                   &std::pair<NodeId, std::string_view>::first );
        return row != operatorResult.end() && row->first == found[ 0 ] && ( row->second == "self" || row->second == cls );
    }
    // Python / TS (h1-annot): is the qualifier of the written type `whole` (`requests.Session`, `a.b.T`, `ns.T`) — its ROOT,
    // the name the file binds — an in-tree module, package or namespace as file `f` sees it: an import binding it decides
    // (buildQualifierVerdicts: 'i' in the tree, 'x' outside); bound by no import, an in-tree class (`Outer.Inner`) or a
    // namespace some file declares (TS `namespace Local`) passes, anything else (`NodeJS.T`, an unbound name) does not.
    bool qualifierInTree( std::uint32_t f, std::string_view whole ) const
    {
        const std::size_t dot = whole.find( '.' );
        if( dot == std::string_view::npos || dot == 0 )
        {
            return false;
        }
        const std::string_view root = whole.substr( 0, dot );
        if( qualifierVerdicts != nullptr )
        {
            if( const auto it = qualifierVerdicts->find( keyOf( f, '#', root ) ); it != qualifierVerdicts->end() )
            {
                return it->second == 'i';
            }
        }
        key.assign( root );
        if( classNames.contains( key ) )
        {
            return true;
        }
        if( !namespaceNamesBuilt )
        {
            namespaceNamesBuilt = true;
            for( const Binding* ns : types.namespaces )
            {
                namespaceNames.try_emplace( std::string( ns->var.substr( 0, ns->var.find( '.' ) ) ), char( 1 ) );   // `a.b` declares `a`
            }
        }
        return namespaceNames.contains( key );
    }
    // the definition a local binding belongs to: a typed local the extractor also indexed as a symbol of its own (a Go
    // `var c T` inside a function) belongs to the function that declares it
    NodeId factScope( const Binding& b ) const
    {
        NodeId from = b.fromSymbol;
        if( from < ing.symbols.size() && !callableKind( ing.symbols[ from ].kind ) && !classLike( ing.symbols[ from ].kind ) )
        {
            if( const NodeId fn = enclosingFn( from ); fn != kNoNode )
            {
                from = fn;
            }
        }
        return from;
    }
    // (L) call-result typing: the local `b` (a LocalBindKind::CallResult) holds class `cls` (the definition `id`) over its
    // span — the class REPLACES the empty tombstone its own declaration recorded there (the same span), so no other binding
    // of the name changes. TS: the declaration records no tombstone; its base-pass Type record (unspanned) read the call
    // initializer as a constructor naming the CALLEE (`const c = makeConfig()` → `makeConfig`). When no class has that name
    // that guess is replaced — but an unspanned record has no span to tell two declarations apart, so only when this is the
    // function's ONLY call-initialised binding of the name (callResultDecls): sibling blocks' `const c = a.make()` / `const c
    // = b.make()` type neither. False when nothing was replaced.
    bool typeCallResult( const Binding& b, std::string_view cls, NodeId id )
    {
        const auto it = localType.find( keyOf( factScope( b ), '#', b.var ) );
        if( it == localType.end() || cls.empty() )
        {
            return false;
        }
        const bool spanned = b.spanEnd > b.spanStart;
        for( LocalFact& f : it->second )
        {
            if( f.start == ( spanned ? b.spanStart : 0u ) && f.end == ( spanned ? b.spanEnd : 0u ) && f.type.empty() )
            {
                f.type.assign( cls );
                f.cls = id;
                return true;
            }
        }
        const auto decls = callResultDecls.find( it->first );
        for( LocalFact& f : it->second )
        {
            if( f.type == b.typeName && !classNames.contains( f.type ) && decls != callResultDecls.end() && decls->second == 1 )
            {
                f.type.assign( cls );
                f.cls = id;
                return true;
            }
        }
        return false;
    }

    // lane iface-peel (LangFacts::returnTypedDispatchLet): the local `b` (a CallResult) holds the result of a call whose ONE
    // proven callee declares `-> &dyn T` / `Box<dyn T>` / `impl T` (`rt`, a ReturnType carrying kDispatchResultBit). The trait
    // resolves in the CALLEE's file like a written type (noteDispatchWritten's rule) and must be a trait; the local's own
    // untyped tombstone (same span) then carries it, exactly as `let x: &dyn T` would. False when nothing was typed: no
    // tombstone, a class of that name, an unresolved or ambiguous trait.
    bool typeCallResultDispatch( const Binding& b, const Binding& rt )
    {
        const auto it = localType.find( keyOf( factScope( b ), '#', b.var ) );
        if( it == localType.end() )
        {
            return false;
        }
        const std::string_view written = rt.importedName;
        const NodeId trait = types.rustResultClass( rt.fileId, rt.startByte, written.find( "::" ) == std::string_view::npos ? std::string_view{} : written, rt.typeName );
        if( trait == kNoNode || ing.symbols[ trait ].kind != SymKind::Interface )
        {
            return false;
        }
        const bool spanned = b.spanEnd > b.spanStart;
        for( LocalFact& f : it->second )
        {
            if( f.start == ( spanned ? b.spanStart : 0u ) && f.end == ( spanned ? b.spanEnd : 0u ) && f.type.empty() && f.iface == kNoNode )
            {
                f.iface = trait;
                return true;
            }
        }
        return false;
    }

    // ── queries ───────────────────────────────────────────────────────────────────────────────────────────────────────
    // the innermost function/method of the same file whose span strictly holds `id`; kNoNode when none
    NodeId enclosingFn( NodeId id ) const { return innermostEnclosingFn( ing, fnsByFile, id ); }
    // visit `from`, then each function enclosing it, innermost first (at most 8 scopes): `visit( scope )` returns true
    // to stop there. Returns the scope it stopped at, kNoNode when no visit stopped the walk.
    template <class Visit>
    NodeId walkScopes( NodeId from, Visit&& visit ) const
    {
        NodeId cur = from;
        for( int depth = 0; depth < 8 && cur != kNoNode; ++depth )
        {
            if( visit( cur ) )
            {
                return cur;
            }
            cur = enclosingFn( cur );
        }
        return kNoNode;
    }
    // FE-B (review B4): the class local `var` holds at byte `site` of definition `scope`, by lexical scope — the innermost
    // spanned binding that holds the site (a later start is more inner; a tie of two classes is unknown), checked against
    // every binding with no span (its extent is unknown, so a disagreement is unknown). nullopt: no binding of `var` is
    // visible there; "": one is, and it names no single class. SeenLocal::cls (fix round 1): the ONE class definition the
    // binding resolved to (a call result's), kNoNode for a name alone — two facts that agree on the name but not on the
    // definition disagree.
    struct SeenLocal
    {
        std::string_view type;
        NodeId           cls   = kNoNode;
        NodeId           iface = kNoNode;   // lane L6: typed only as SOME implementor of this trait (LocalFact::iface)
        std::string_view bound;             // lane L6: that typing's generic bound text, "" when none
        bool operator==( const SeenLocal& ) const = default;
    };
    static SeenLocal seenOf( const LocalFact& f ) noexcept
    {
        SeenLocal seen;
        seen.type  = f.type;
        seen.cls   = f.cls;
        seen.iface = f.iface;   // lane L6
        seen.bound = f.bound;
        return seen;
    }
    std::optional<SeenLocal> seenLocal( NodeId scope, std::string_view var, std::uint32_t site ) const
    {
        const auto it = localType.find( keyOf( scope, '#', var ) );
        if( it == localType.end() )
        {
            return std::nullopt;
        }
        const LocalFact*         inner = nullptr;
        bool                     innerSplit = false;
        std::optional<SeenLocal> whole;
        for( const LocalFact& f : it->second )
        {
            if( f.end == 0 )
            {
                whole = ( whole.has_value() && *whole != seenOf( f ) ) ? SeenLocal{} : seenOf( f );
                continue;
            }
            if( site < f.start || site >= f.end )
            {
                continue;
            }
            if( inner == nullptr || f.start > inner->start || ( f.start == inner->start && f.end < inner->end ) )
            {
                inner      = &f;
                innerSplit = false;
            }
            else if( f.start == inner->start && f.end == inner->end && seenOf( f ) != seenOf( *inner ) )
            {
                innerSplit = true;
            }
        }
        if( inner == nullptr )
        {
            return whole;
        }
        const SeenLocal seen = innerSplit ? SeenLocal{} : seenOf( *inner );
        return ( whole.has_value() && *whole != seen ) ? SeenLocal{} : seen;
    }
    static std::optional<std::string_view> typeOf( const std::optional<SeenLocal>& seen ) noexcept
    {
        return seen.has_value() ? std::optional<std::string_view>( seen->type ) : std::nullopt;
    }
    std::optional<std::string_view> visibleLocal( NodeId scope, std::string_view var, std::uint32_t site ) const
    {
        return typeOf( seenLocal( scope, var, site ) );
    }
    // the local `var` visible at byte `site` of `from` or of a function enclosing it (the innermost that has one)
    std::optional<SeenLocal> localSeenAt( NodeId from, std::string_view var, std::uint32_t site ) const
    {
        std::optional<SeenLocal> hit;
        walkScopes( from, [ & ]( NodeId scope )
        {
            hit = seenLocal( scope, var, site );
            return hit.has_value();
        } );
        return hit;
    }
    std::optional<std::string_view> localAt( NodeId from, std::string_view var, std::uint32_t site ) const
    {
        return typeOf( localSeenAt( from, var, site ) );
    }
    // the ( object var, method ) a method alias `var` names in `from` or a function enclosing it; `scope` = where it is bound
    const std::pair<std::string, std::string>* aliasedMethod( NodeId from, std::string_view var, NodeId& scope ) const
    {
        const std::pair<std::string, std::string>* hit = nullptr;
        if( const NodeId at = walkScopes( from, [ & ]( NodeId s )
            {
                const auto it = methodAlias.find( keyOf( s, '#', var ) );
                if( it == methodAlias.end() )
                {
                    return false;
                }
                hit = it->second.first.empty() ? nullptr : &it->second;
                return true;
            } ); at != kNoNode )
        {
            scope = at;
        }
        return hit;
    }
    // is `name` a parameter or local of `from` or of a function enclosing it (any binding the extractor recorded)
    bool isLocalName( NodeId from, std::string_view name ) const
    {
        return localNames != nullptr && walkScopes( from, [ & ]( NodeId s )
        {
            return localNames->contains( keyOf( s, '#', name ) ) || localType.contains( keyOf( s, '#', name ) );
        } ) != kNoNode;
    }
    // does `from` or a function enclosing it DECLARE `name` (a parameter or a local, typed or not) — not merely bind it: Java
    // copies each field name onto its class's methods as a bound-only name (graph.h shadowJavaFieldsOntoMethods), which must
    // not hide the field itself
    bool declaresLocal( NodeId from, std::string_view name, std::uint32_t site ) const
    {
        return walkScopes( from, [ & ]( NodeId s )
        {
            if( visibleLocal( s, name, site ).has_value() )
            {
                return true;   // a binding of the name is visible at the site (review B4: by its span)
            }
            if( localNames == nullptr )
            {
                return false;
            }
            const auto it = localNames->find( keyOf( s, '#', name ) );
            return it != localNames->end() && ( it->second & kLocalNameDeclared ) != 0;
        } ) != kNoNode;
    }
    // a receiver root that names a CLASS at this site: a class-name receiver language, a class of that name, and no local
    // of the caller hiding it (`Interval = make(); Interval.validate( v )`)
    // (L) fix round 2 / 3 (D3, D6): a JVM caller that does not SEE an in-tree class `root` (an import of an outside one, an
    // outside on-demand import alone, no import at all) names an outside class — never an in-tree namesake
    bool namesClass( const Reference& r, std::string_view root, std::string_view cls ) const
    {
        return classNameReceiverLang( r.lang ) && classNames.contains( std::string( cls ) ) && !isLocalName( r.fromSymbol, root )
            && !( callResultFamilyOf( r.lang ) == CallResultFamily::Jvm && types.jvmHides( r.fileId, r.startByte, root ) );
    }
    // the class owning the caller — the caller's own owner, else the nearest enclosing function's (a closure in a method)
    std::string_view callerClass( NodeId from ) const
    {
        const NodeId at = walkScopes( from, [ & ]( NodeId s ) { return !ownerClass[ s ].empty(); } );
        return at == kNoNode ? std::string_view{} : std::string_view( ownerClass[ at ] );
    }
    // `type`'s direct bases: the inheritance names, then (Go) its embedded classes
    template <class Fn>
    void forEachBase( std::string_view type, Fn&& fn ) const
    {
        if( const auto it = chaUp.find( std::string( type ) ); it != chaUp.end() )
        {
            for( const std::string& b : it->second ) { fn( std::string_view( b ) ); }
        }
        if( const auto it = embeds.find( std::string( type ) ); it != embeds.end() )
        {
            for( const std::string& b : it->second ) { fn( std::string_view( b ) ); }
        }
    }
    // is `ancestor` the class `type` or one of its (transitive) bases
    bool inCone( std::string_view type, std::string_view ancestor ) const
    {
        if( type.empty() || ancestor.empty() )
        {
            return false;
        }
        frontier.clear();
        frontier.push_back( type );
        for( std::size_t i = 0; i < frontier.size() && i < kWalkCap; ++i )
        {
            if( frontier[ i ] == ancestor )
            {
                return true;
            }
            forEachBase( frontier[ i ], [ & ]( std::string_view b )
            {
                if( std::find( frontier.begin(), frontier.end(), b ) == frontier.end() ) { frontier.push_back( b ); }
            } );
        }
        return false;
    }
    // visit `type`'s level (depth 0), then its base levels shallowest first, each class once: `visit( level, depth )`
    // returns true to stop. Returns whether a visit stopped the walk.
    template <class Visit>
    bool walkBaseLevels( std::string_view type, Visit&& visit ) const
    {
        std::vector<std::string_view> level{ type };
        std::vector<std::string_view> seen{ type };
        for( std::size_t depth = 0; depth < kWalkCap && !level.empty(); ++depth )
        {
            if( visit( level, depth ) )
            {
                return true;
            }
            std::vector<std::string_view> next;
            for( std::string_view t : level )
            {
                forEachBase( t, [ & ]( std::string_view b )
                {
                    if( std::find( seen.begin(), seen.end(), b ) == seen.end() ) { seen.push_back( b ); next.push_back( b ); }
                } );
            }
            level.swap( next );
        }
        return false;
    }
    // `type`'s own `name`, else the shallowest base level defining it (several bases at one level: their union). The
    // answer is in `found`; false when nothing in the cone defines it. superOnly skips `type` itself (`super.m()`).
    // `cls` (fix round 1): the ONE definition `type` resolved to — its own level keeps only the members that class owns
    // (memberOwnerRuleOf), and its bases, which are known by NAME only, are walked only when no other in-tree class of its
    // language shares that name.
    bool methodOf( std::string_view type, std::string_view name, bool superOnly, NodeId cls = kNoNode ) const
    {
        EXPECTS( active, "methodOf reads the tables build() fills" );
        found.clear();
        if( type.empty() )
        {
            return false;
        }
        const bool basesByName = cls == kNoNode || types.sameNamedClasses( cls ) == 1;
        bool        redeclared = false;   // a nearer level declared the name WITHOUT a body: the nearest declaration wins, no ancestor body runs
        std::size_t foundDepth = 0;
        const bool  gated      = abstractNames.contains( name );   // no class declares the name bodyless: neither walk below can matter
        const bool  stopped    = walkBaseLevels( type, [ & ]( const std::vector<std::string_view>& level, std::size_t depth )
        {
            if( ( superOnly && depth == 0 ) || ( depth > 0 && !basesByName ) )
            {
                return depth > 0;
            }
            for( std::string_view t : level )
            {
                const std::size_t before = found.size();
                collectMethods( t, name, depth == 0 ? cls : kNoNode );
                redeclared = redeclared || ( gated && found.size() == before && abstractOn( t, name, depth == 0 ? cls : kNoNode ) );
            }
            foundDepth = depth;
            return redeclared || !found.empty();
        } );
        if( redeclared || ( stopped && !found.empty() && gated && overloadedAbove( type, name, foundDepth ) ) )
        {
            found.clear();   // EXACT OR NO ROW: an abstract re-declaration on the path is no body (the dispatch tier answers)
        }
        return stopped && !found.empty();   // a walk stopped at an unwalkable base level found nothing
    }
    // Kotlin and C# keep no call-comparable arity (ingest_metrics.h cc_paramShape's language gate; Java has one, which the name tiers'
    // arity rule reads): `found` (bodies at depth `at`) is not the call's answer when a base level ABOVE
    // declares the name without a body at a parameter count NO found body has: the call may mean that overload (Sub { override fun
    // ap() } over Mid { fun ap( x: Int ): Int }). A count a found body has is the ordinary override of it.
    bool overloadedAbove( std::string_view type, std::string_view name, std::size_t at ) const
    {
        const Lang lang = ing.symbols[ found[ 0 ] ].lang;
        if( !langFacts( lang ).overloadsWithoutArity )
        {
            return false;
        }
        return walkBaseLevels( type, [ & ]( const std::vector<std::string_view>& level, std::size_t depth )
        {
            for( std::string_view t : level )
            {
                const auto it = depth > at ? abstractByType.find( typeKey( t, "::", name ) ) : abstractByType.end();
                if( it != abstractByType.end() && std::ranges::any_of( it->second, [ & ]( NodeId a )
                    { return std::ranges::all_of( found, [ & ]( NodeId f ) { return ing.symbols[ f ].params != ing.symbols[ a ].params; } ); } ) )
                {
                    return true;
                }
            }
            return false;
        } );
    }
    // does `type` declare a callable `name` with NO body (`cls`: only the one class owns it), and own no body of it (collectMethods
    // found none): an interface's or abstract class's re-declaration of an inherited member
    bool abstractOn( std::string_view type, std::string_view name, NodeId cls ) const
    {
        const auto it = abstractByType.find( typeKey( type, "::", name ) );
        return it != abstractByType.end() && ( cls == kNoNode || std::ranges::any_of( it->second, [ & ]( NodeId c ) { return ownedBy( c, cls ); } ) );
    }
    // `type`'s own callables named `name` into `found` — only those class `cls` owns, when it is a definition
    void collectMethods( std::string_view type, std::string_view name, NodeId cls ) const
    {
        if( const auto it = methodsByType.find( typeKey( type, "::", name ) ); it != methodsByType.end() )
        {
            for( NodeId c : it->second )
            {
                if( cls == kNoNode || ownedBy( c, cls ) )
                {
                    found.push_back( c );
                }
            }
        }
    }
    // does class `cls` own member `m` (memberOwnerRuleOf)
    bool ownedBy( NodeId m, NodeId cls ) const
    {
        const Symbol& ms = ing.symbols[ m ];
        const Symbol& cs = ing.symbols[ cls ];
        switch( memberOwnerRuleOf( cs.lang ) )
        {
            case MemberOwnerRule::PackageDir:   return types.dirOf( ms.fileId ) == types.dirOf( cs.fileId );
            case MemberOwnerRule::FileOrUnique:   // fix round 3: in the type's own file, the impl sits in the type's own item scope
                return ( ms.fileId == cs.fileId && types.innermostItemScope( m ) == types.innermostItemScope( cls ) ) || types.sameNamedClasses( cls ) == 1;
            case MemberOwnerRule::Lexical:
            default:
            {
                const NodeId at = classAt( ms.fileId, ms.sigStartByte, ms.endByte, m );
                return at == cls || ( at == kNoNode && ms.fileId == cs.fileId );
            }
        }
    }
    // the class of field `field` on `type` (or the shallowest base declaring it); "" unknown
    std::string_view fieldOf( std::string_view type, std::string_view field ) const
    {
        std::string_view fieldType;
        walkBaseLevels( type, [ & ]( const std::vector<std::string_view>& level, std::size_t )
        {
            for( std::string_view t : level )
            {
                if( const auto it = memberType.find( typeKey( t, "#", field ) ); it != memberType.end() )
                {
                    fieldType = it->second;   // "" = tombstone: unknown
                    return true;
                }
            }
            return false;
        } );
        return fieldType;
    }

    // The receiver chain of a member call as ( root, path, constructed class ), in every language's spelling.
    struct Chain
    {
        std::string_view root;
        std::string_view path;
        std::string_view ctor;
        bool             valid = false;
    };
    static Chain chainOf( const Reference& r ) noexcept
    {
        Chain c;
        if( r.memberCall )
        {
            c.root  = r.memberRoot;
            c.path  = r.memberPath;
            c.ctor  = r.memberCtor;
            c.valid = !c.root.empty() || !c.ctor.empty();
            return c;
        }
        switch( r.recv )   // Python / C++ / Ruby shapes (ingest_binds.h receiverOf)
        {
            case RecvKind::ThisObj:     c.root = "self";     c.valid = true; break;
            case RecvKind::NamedVar:    c.root = r.recvVar;  c.valid = !r.recvVar.empty(); break;
            case RecvKind::FieldOfThis: c.root = "self";     c.path = r.fieldName; c.valid = !r.fieldName.empty(); break;
            case RecvKind::FieldOfVar:  c.root = r.recvVar;  c.path = r.fieldName; c.valid = !r.recvVar.empty() && !r.fieldName.empty(); break;
            case RecvKind::SuperObj:    c.root = "super";    c.valid = true; break;
            default: break;
        }
        return c;
    }

    // The class the receiver ROOT names at this site; static/super set for a class-name or super receiver. "" unknown.
    // a class name as the caller's FILE spells it, read through that file's import alias (`Ctx` → `Context`)
    std::string_view unalias( std::uint32_t fileId, std::string_view name ) const
    {
        if( const auto it = nameAlias.find( keyOf( fileId, '#', name ) ); it != nameAlias.end() && !it->second.empty() )
        {
            return it->second;
        }
        return name;
    }
    // `rootCls` (when asked, and left as the caller set it otherwise): the ONE class a call-result-typed local resolved to
    // a typed local's class as the caller reads it: a call result's resolved class as it is (its callee's file decided it,
    // so the caller's import aliases do not apply), any other through the caller's import alias
    std::string_view typedLocalClass( const Reference& r, const SeenLocal& t, NodeId* rootCls ) const
    {
        if( rootCls != nullptr && t.cls != kNoNode )
        {
            *rootCls = t.cls;
        }
        return t.cls != kNoNode ? t.type : unalias( r.fileId, t.type );
    }
    std::string_view rootClass( const Reference& r, const Chain& ch, bool& isStatic, bool& superOnly, NodeId* rootCls = nullptr ) const
    {
        isStatic  = false;
        superOnly = false;
        if( !ch.ctor.empty() )
        {
            return unalias( r.fileId, ch.ctor );
        }
        const std::string_view root = ch.root;
        if( isThisRoot( root ) || ( r.lang == Lang::Python && root == "cls" ) )
        {
            return callerClass( r.fromSymbol );
        }
        if( isSuperRoot( r, root ) )
        {
            superOnly = true;
            return callerClass( r.fromSymbol );
        }
        if( const std::optional<SeenLocal> t = localSeenAt( r.fromSymbol, root, r.startByte ); t.has_value() && !t->type.empty() )
        {
            return typedLocalClass( r, *t, rootCls );
        }
        // Java/C#/Kotlin/Swift (the implicit-receiver languages but C++, whose Rule 2b reads fields, and Ruby, whose fields
        // are @ivars): a bare `field.m()` inside a method is `this.field.m()` — the field the caller's class (or a base)
        // declares, when no parameter or local of that name hides it
        if( implicitReceiverLang( r.lang ) && r.lang != Lang::Cpp && r.lang != Lang::Ruby && !declaresLocal( r.fromSymbol, root, r.startByte ) )
        {
            const std::string_view owner = callerClass( r.fromSymbol );
            if( const std::string_view ft = owner.empty() ? std::string_view{} : fieldOf( owner, root ); !ft.empty() )
            {
                return unalias( r.fileId, ft );
            }
        }
        const std::string_view cls = unalias( r.fileId, root );
        if( namesClass( r, root, cls ) )
        {
            isStatic = true;
            return cls;
        }
        return {};
    }

    // The two SIDES of a JS/TS class lookup (#373's Ruby class-object rule, here): a call on the CLASS object reaches its
    // `static` members only, a call on an INSTANCE its other members only. True for every target in another language.
    bool onSide( const Reference& r, NodeId target, bool classSide ) const noexcept
    {
        if( r.lang != Lang::JavaScript && r.lang != Lang::TypeScript )
        {
            return true;
        }
        return target < staticMember.size() && ( staticMember[ target ] != 0 ) == classSide;
    }
    // Does `this` inside the caller name the CLASS? Only inside a static member.
    bool callerIsStatic( NodeId from ) const noexcept
    {
        return from < staticMember.size() && staticMember[ from ] != 0;
    }

    // RESOLVE: the definitions this member call's typed receiver reaches, in `found`; false when the receiver proves
    // nothing (untyped, a type this tree does not define, or a type that defines no such member anywhere in its cone).
    // `spellingDecides` false: the receiver root is a name WRITTEN in its scope (graph.h JsWrittenRoot), so the class its SPELLING names
    // is not its class — only a stated type (a typed local, a constructed receiver, `this`) may decide.
    bool narrow( const Reference& r, bool spellingDecides = true ) const
    {
        // C++, Ruby, Rust and C keep their own receiver rules (Rules 1, 2, 2b, 2c): this one adds the languages that had none
        const bool typedLang = r.lang == Lang::JavaScript || r.lang == Lang::TypeScript || r.lang == Lang::Python || r.lang == Lang::Go
                            || r.lang == Lang::Java || r.lang == Lang::Kotlin || r.lang == Lang::CSharp || r.lang == Lang::Swift;
        const bool localsOnly = receiverLocalsOnly( r.lang );
        if( !active || r.fromSymbol >= ing.symbols.size() || !r.qualifier.empty() || !( typedLang || localsOnly ) )
        {
            return false;
        }
        if( localsOnly )
        {
            return narrowTypedLocal( r );
        }
        if( !isMemberCallRef( r ) )
        {
            return r.lang == Lang::Python && narrowAliasedMethod( r );
        }
        const Chain ch = chainOf( r );
        if( !ch.valid )
        {
            return false;
        }
        bool isStatic = false, superOnly = false;
        NodeId           cls  = kNoNode;
        std::string_view type = rootClass( r, ch, isStatic, superOnly, &cls );
        if( type.empty() || ( isStatic && !spellingDecides ) || ( cls != kNoNode && !ch.path.empty() && types.sameNamedClasses( cls ) != 1 ) )
        {
            return false;   // a field path is read by NAME (memberType): below a class another in-tree class names too, a floor
        }
        // the side the receiver names: the class object (a class-name receiver, or `this`/`super` inside a static member),
        // else an instance; a stated field below always holds an instance
        bool classSide = isStatic || ( ch.ctor.empty() && ( isThisRoot( ch.root ) || isSuperRoot( r, ch.root ) ) && callerIsStatic( r.fromSymbol ) );
        std::string_view rest = ch.path;
        while( !rest.empty() )   // walk the stated field classes
        {
            const std::size_t dot = rest.find( '.' );
            const std::string_view field = rest.substr( 0, dot );
            rest = dot == std::string_view::npos ? std::string_view{} : rest.substr( dot + 1 );
            type = fieldOf( type, field );
            superOnly = false;
            classSide = false;
            if( type.empty() )
            {
                return false;
            }
        }
        if( !methodOf( type, r.calleeName, superOnly, cls ) )
        {
            return false;
        }
        // a wrong-side definition is never the answer: what is left is, and nothing left proves nothing (the ladder hedges)
        std::size_t kept = 0;
        for( std::size_t i = 0; i < found.size(); ++i )
        {
            if( onSide( r, found[ i ], classSide ) )
            {
                found[ kept++ ] = found[ i ];
            }
        }
        found.resize( kept );
        return !found.empty();
    }

    // (L) a language whose own receiver rules answer `self.m()` (receiverLocalsOnly: Rust's Rule 1): a member call on a typed
    // LOCAL — a call result graph.h's resolve loop typed, or (rust-receivers) a parameter / `let` written or constructed as an
    // in-tree type — or on a field path below one or below `self` (`self.book.iter()`, `s.inner.book.m()`), each field by the
    // ONE class its written type resolved to (memberClass), reaches that class's own members. `self.m()` itself stays Rule 1's.
    bool narrowTypedLocal( const Reference& r ) const
    {
        if( !isMemberCallRef( r ) )
        {
            return false;
        }
        const Chain ch = chainOf( r );
        if( !ch.valid || !ch.ctor.empty() || ch.root.empty() )
        {
            return false;
        }
        NodeId cls = kNoNode;
        if( ch.root == "self" )   // Rust's receiver keyword: `this` / `Self` are ordinary names here, read by their own binding below
        {
            if( ch.path.empty() )
            {
                return false;   // `self.m()`: the language's own rule (Rule 1) answers it
            }
            cls = selfClass( r.fromSymbol );
        }
        else if( const std::optional<SeenLocal> t = localSeenAt( r.fromSymbol, ch.root, r.startByte ); t.has_value() && !t->type.empty() )
        {
            cls = t->cls;
        }
        for( std::string_view rest = ch.path; !rest.empty() && cls != kNoNode; )   // the stated fields, each by its resolved class
        {
            const std::size_t      dot   = rest.find( '.' );
            const std::string_view field = rest.substr( 0, dot );
            rest = dot == std::string_view::npos ? std::string_view{} : rest.substr( dot + 1 );
            const auto it = memberClass.find( keyOf( cls, '#', field ) );
            cls = it == memberClass.end() ? kNoNode : it->second;
        }
        return cls != kNoNode && methodOf( ing.symbols[ cls ].name, r.calleeName, false, cls );
    }
    // lane L6 (interface-typed dispatch): the TYPE a member call's receiver is recorded as — the one class or interface the
    // dispatch tier (ifacedispatch.h) asks about — and, for a Rust generic, the bound that typed it. `type` kNoNode: nothing
    // recorded. Rust (receiverLocalsOnly): a parameter, local or field typed only through a trait (noteDispatchWritten), reached
    // from a local or from `self` through the fields' resolved classes. The typed languages: the receiver root's written type
    // (rootClass: a typed parameter or local, a field of the caller's class) and its stated fields (fieldOf), resolved to ONE
    // in-tree class at the call site (classAtSite) — a field path only below a class no other in-tree class names. Never a bare
    // `this` / `self` / `super` or a class-name receiver: those name the caller's own class or a static call, no dispatch;
    // `this.f.m()` (lane receiver-fixes, TS-FIELD-SELF) is f's stated type, as for any other root.
    struct DispatchReceiver
    {
        NodeId           type = kNoNode;
        std::string_view bound;
    };
    DispatchReceiver dispatchReceiverOf( const Reference& r ) const
    {
        if( !active || r.fromSymbol >= ing.symbols.size() || !r.qualifier.empty() || !isMemberCallRef( r ) )
        {
            return {};
        }
        const Chain ch = chainOf( r );
        if( !ch.valid || !ch.ctor.empty() || ch.root.empty() )
        {
            return {};
        }
        if( receiverLocalsOnly( r.lang ) )
        {
            return traitDispatchReceiver( r, ch );
        }
        // TS-FIELD-SELF: `this.f.m()` is a call on f's stated type, as `f.m()` on a typed local is; a bare `this.m()` (or one inside a
        // static member, whose `this` is the class object) names the caller's own class, no dispatch
        if( ( isThisRoot( ch.root ) && ( ch.path.empty() || ch.root != langFacts( r.lang ).instanceReceiver || callerIsStatic( r.fromSymbol ) ) )
            || isSuperRoot( r, ch.root ) )
        {
            return {};
        }
        bool             isStatic = false, superOnly = false;
        NodeId           cls  = kNoNode;
        std::string_view type = rootClass( r, ch, isStatic, superOnly, &cls );
        if( type.empty() || isStatic || superOnly )
        {
            return {};
        }
        for( std::string_view rest = ch.path; !rest.empty(); )   // the stated field classes, by name
        {
            const std::size_t      dot   = rest.find( '.' );
            const std::string_view field = rest.substr( 0, dot );
            rest = dot == std::string_view::npos ? std::string_view{} : rest.substr( dot + 1 );
            type = fieldOf( type, field );
            cls  = kNoNode;
            if( type.empty() )
            {
                return {};
            }
        }
        if( cls == kNoNode )
        {
            cls = types.classAtSite( r.lang, r.fileId, r.startByte, type );
            cls = cls != kNoNode ? cls : importedTypeClass( r, type );
            if( cls != kNoNode && !ch.path.empty() && types.sameNamedClasses( cls ) != 1 )
            {
                cls = kNoNode;   // a field's type is known by NAME: below a name two in-tree classes share, a floor
            }
        }
        return { cls, {} };
    }
    // lane receiver-fixes (TS-FIELD-SELF, PY-CTOR-ANNOT; dispatch classes #10 receiver peeling, #11 name-keyed identity): the
    // caller's own class when a member call's receiver is `this.<path>` / `self.<path>` whose last field the classes state as
    // an in-tree class or interface T (fieldOf: a written or constructed type, never a tombstone) that is neither the caller's
    // class nor one of its bases (inCone). The object such a call reaches is a T, so the caller's OWN definition of the callee
    // is no candidate: graph.h cuts it from the name tiers (before, `this.pub.provide()` with `pub: Provider` bound the
    // caller's own `provide` by name, and with that one same-file candidate the self-loop then vanished). kNoNode otherwise:
    // no path, a static side, an unknown field, a T the tree does not define, or no one class owning the caller.
    NodeId foreignFieldOwner( const Reference& r ) const
    {
        if( !active || r.fromSymbol >= ing.symbols.size() || !r.qualifier.empty() || !isMemberCallRef( r ) || receiverLocalsOnly( r.lang ) )
        {
            return kNoNode;
        }
        const Chain ch = chainOf( r );
        if( !ch.valid || !ch.ctor.empty() || ch.path.empty() || ch.root != langFacts( r.lang ).instanceReceiver || callerIsStatic( r.fromSymbol ) )
        {
            return kNoNode;
        }
        const std::string_view own  = callerClass( r.fromSymbol );
        std::string_view       type = own;
        for( std::string_view rest = ch.path; !rest.empty() && !type.empty(); )
        {
            const std::size_t dot = rest.find( '.' );
            type = fieldOf( type, rest.substr( 0, dot ) );
            rest = dot == std::string_view::npos ? std::string_view{} : rest.substr( dot + 1 );
        }
        if( own.empty() || type.empty() || type == own || inCone( own, type ) )
        {
            return kNoNode;
        }
        key.assign( type );
        return classNames.contains( key ) && !namesTypeAlias( r.lang, type ) ? selfClass( r.fromSymbol ) : kNoNode;
    }
    // a TypeScript `type T = …` is indexed as a Struct (queries/typescript/tags.scm @definition.type), and TS has no struct of its
    // own: T then names whatever the alias spells (a union, a base class), not "a class that is not the caller's". Any alias of the
    // name in the tree keeps foreignFieldOwner from cutting (a union holds the caller's class too; `type B = Base` may hold a D).
    bool namesTypeAlias( Lang lang, std::string_view name ) const
    {
        NodeId one = kNoNode;
        return callResultFamilyOf( lang ) == CallResultFamily::TypeScript
            && types.classesNamed( name, CallResultFamily::TypeScript, [ & ]( NodeId c ) { return ing.symbols[ c ].kind == SymKind::Struct; }, one ) != 0;
    }
    // TypeScript: a type name the caller's file imports by name from a module (`import { Router } from "./fmt/router"`) that the
    // import tables pin to no class — their export table holds functions and classes, never an interface — names the ONE
    // top-level INTERFACE of that name in the file the specifier resolved to, else a class of the caller's own file; kNoNode for none
    // or several (a re-export barrel: a floor), and for every other family (classAtSite's rows answer them)
    NodeId importedTypeClass( const Reference& r, std::string_view type ) const
    {
        if( callResultFamilyOf( r.lang ) != CallResultFamily::TypeScript )
        {
            return kNoNode;
        }
        std::uint32_t module = UINT32_MAX;
        if( types.jsImportModules != nullptr )
        {
            if( const auto it = types.jsImportModules->find( keyOf( r.fileId, '#', type ) ); it != types.jsImportModules->end() )
            {
                module = it->second;
            }
        }
        return types.onlyClass( type, CallResultFamily::TypeScript, [ & ]( NodeId c )
        {
            const std::uint32_t f = ing.symbols[ c ].fileId;
            return ( f == r.fileId || ( f == module && ing.symbols[ c ].kind == SymKind::Interface ) ) && types.levelOfClass( c ).wholeFile();
        } );
    }
    // Rust: a local or parameter typed through a trait, or `self.f` / `x.f.g` whose LAST field is a `Box<dyn T>` one (each
    // field above it read by its resolved class, as narrowTypedLocal reads them)
    DispatchReceiver traitDispatchReceiver( const Reference& r, const Chain& ch ) const
    {
        NodeId cls = kNoNode;
        if( isThisRoot( ch.root ) )
        {
            if( ch.path.empty() )
            {
                return {};
            }
            cls = selfClass( r.fromSymbol );
        }
        else if( const std::optional<SeenLocal> t = localSeenAt( r.fromSymbol, ch.root, r.startByte ); t.has_value() )
        {
            if( ch.path.empty() )
            {
                return { t->iface, t->bound };
            }
            cls = t->cls;
        }
        for( std::string_view rest = ch.path; !rest.empty() && cls != kNoNode; )
        {
            const std::size_t      dot   = rest.find( '.' );
            const std::string_view field = rest.substr( 0, dot );
            rest = dot == std::string_view::npos ? std::string_view{} : rest.substr( dot + 1 );
            const std::string&     k     = keyOf( cls, '#', field );
            if( rest.empty() )
            {
                const auto it = memberIface.find( k );
                return { it == memberIface.end() ? kNoNode : it->second, {} };
            }
            const auto it = memberClass.find( k );
            cls = it == memberClass.end() ? kNoNode : it->second;
        }
        return {};
    }
    // rust-receivers (fix round 1): may a Rust call written `T::f()` type the locals its result binds through `to`, a member
    // whose declared result is written `Self` (graph.h typeCallResults asks only for those: a result the base read already
    // typed keeps its base rule)? Only when the qualifier as WRITTEN at the call site (`written`: the CallResult record's
    // whole path — the Reference keeps only its last segment), resolved like a written `x: T` (`Self` the impl's own class),
    // is the in-tree class that owns `to`. The canonical tier matches the callee's scope NAME alone, so std's `Path::new( p )`,
    // `fs::File::open()`, `std::path::PathBuf::from()`, a glob's or the prelude's `String::new()` all commit to an in-tree
    // type's member of that name (a base edge this does not change); an outside root, a std module, a glob that may supply,
    // a prelude name with no in-tree item in scope resolve to no class, and that `-> Self` types nothing.
    bool rustQualifiedTypeOwns( const Reference& r, std::string_view written, NodeId to ) const
    {
        if( r.qualifier.empty() && written.empty() )
        {
            return true;   // a bare or member call (no path written): the language's own lookup
        }
        const NodeId cls = rustQualifierClass( r, written );
        if( cls == kNoNode )
        {
            return false;
        }
        const auto it = methodsByType.find( typeKey( ing.symbols[ cls ].name, "::", ing.symbols[ to ].name ) );
        return it != methodsByType.end() && std::ranges::find( it->second, to ) != it->second.end() && ownedBy( to, cls );
    }
    // the ONE in-tree class a Rust call's written qualifier names, resolved like a written `x: T` (`Self`: the impl's class)
    NodeId rustQualifierClass( const Reference& r, std::string_view written ) const
    {
        const auto [ path, last ] = CallResultTypes::splitLast( written, "::" );
        return path.empty() && last == "Self" ? selfClass( r.fromSymbol )
                                              : types.rustResultClass( r.fileId, r.startByte, path.empty() ? std::string_view{} : written, last );
    }
    // fc1: may the call `r` (written with qualifier `written`) type the locals its result binds through `to`? Another family's
    // own rules decided the edge, and so did a Rust bare call's and a free function's (an inline `mod`'s too). A Rust MEMBER
    // call `T::f()` whose result is written `Self` types them only when T reaches f's class (rustQualifiedTypeOwns). One
    // whose result is written by the type's own name (`-> PathBuf`, a path, inside Result / Option / Box) keeps the base
    // rule unless T resolves to ANOTHER in-tree class or provably leaves the tree (rustPathOutside): `std::path::PathBuf::from()`
    // never types a local onto an in-tree PathBuf whose `from` returns `PathBuf`, while a T the walk cannot follow (a module
    // a glob re-exports, a file outside every crate's tree) keeps the row base proved.
    bool rustQualifierTypes( const Reference& r, std::string_view written, NodeId to, bool spelledSelf ) const
    {
        if( callResultFamilyOf( r.lang ) != CallResultFamily::Rust )
        {
            return true;
        }
        if( spelledSelf )
        {
            return rustQualifiedTypeOwns( r, written, to );
        }
        NodeId one = kNoNode;
        if( r.qualifier.empty() || ownerClass[ to ].empty() || types.classesNamed( ownerClass[ to ], CallResultFamily::Rust, []( NodeId ) { return true; }, one ) == 0
            || rustQualifiedTypeOwns( r, written, to ) )
        {
            return true;
        }
        if( rustQualifierClass( r, written ) != kNoNode )
        {
            return false;
        }
        types.pathCut = false;   // the top-level walk's own cut: a cut walk is no proof that the path stays in the tree
        const bool out = types.rustPathOutside( r.fileId, r.startByte, written );
        return !out && !types.pathCut;
    }
    // rust-receivers: the ONE class `self` names inside `from` (or the method enclosing it): the in-tree class of the method's
    // owner name that owns the method (memberOwnerRuleOf — Rust: its own file and item scope, or the only class of the name);
    // kNoNode when none or several do
    NodeId selfClass( NodeId from ) const
    {
        const NodeId at = walkScopes( from, [ & ]( NodeId s ) { return !ownerClass[ s ].empty(); } );
        if( at == kNoNode )
        {
            return kNoNode;
        }
        NodeId     one    = kNoNode;
        const bool unique = types.classesNamed( ownerClass[ at ], callResultFamilyOf( ing.symbols[ at ].lang ), [ & ]( NodeId c ) { return ownedBy( at, c ); }, one ) == 1;
        return unique ? one : kNoNode;
    }

    // Python `feed = parser.feed; … feed( data )`: the alias names a typed object's method
    bool narrowAliasedMethod( const Reference& r ) const
    {
        if( r.recv != RecvKind::None || r.calleeName.empty() )
        {
            return false;
        }
        NodeId scope = kNoNode;
        const std::pair<std::string, std::string>* alias = aliasedMethod( r.fromSymbol, r.calleeName, scope );
        if( alias == nullptr )
        {
            return false;
        }
        if( isThisRoot( alias->first ) || alias->first == "cls" )
        {
            return methodOf( callerClass( scope ), alias->second, false );   // `write = self.write`: the class's own member
        }
        const std::optional<std::string_view> type = localAt( scope, alias->first, r.startByte );
        return type.has_value() && !type->empty() && methodOf( unalias( r.fileId, *type ), alias->second, false );
    }

    // does module alias `root` (bound in the caller's file) name the file defining `c`
    bool moduleNames( const Reference& r, std::string_view root, NodeId c ) const
    {
        const auto it = moduleAlias.find( keyOf( r.fileId, '#', root ) );
        if( it == moduleAlias.end() || it->second.empty() )
        {
            return false;
        }
        const std::string_view source = it->second;
        const std::string_view target = rootRelPath( ing, ing.symbols[ c ].fileId );
        if( r.lang == Lang::Go )
        {
            // an import path names a package: the candidate's own package import path (its go.mod's module path and the
            // directory below it — a nested module's `quoted/lib` is `example.com/qm/lib` — or the path a local replace
            // maps its directory to) proves it EXACTLY. A candidate with a path, or an import path some in-tree file
            // carries, is proven by nothing else: a directory that merely ends the path is another package
            const std::uint32_t cf = ing.symbols[ c ].fileId;
            if( goPackages != nullptr && ( goPackages->hasPath( cf ) || goPackages->known.contains( key.assign( source ) ) ) )
            {
                return goPackages->names( cf, source );
            }
            // no module facts name this path or the candidate (a tree with no go.mod): its directory must end the path,
            // segment-aligned
            const std::string_view dir = includerDir( target );
            return !dir.empty() && source.size() >= dir.size() && source.ends_with( dir )
                && ( source.size() == dir.size() || source[ source.size() - dir.size() - 1 ] == '/' );
        }
        if( !source.starts_with( "./" ) && !source.starts_with( "../" ) )
        {
            return false;   // a package specifier: outside the tree, or resolved by a bundler this rule does not model
        }
        // join the caller's directory with the relative specifier, then compare without the extension (or /index)
        std::vector<std::string_view> parts;
        std::string_view base = includerDir( rootRelPath( ing, r.fileId ) );
        const auto push = [ & ]( std::string_view p )
        {
            while( !p.empty() )
            {
                const std::size_t slash = p.find( '/' );
                const std::string_view seg = p.substr( 0, slash );
                p = slash == std::string_view::npos ? std::string_view{} : p.substr( slash + 1 );
                if( seg.empty() || seg == "." ) { continue; }
                if( seg == ".." ) { if( !parts.empty() ) { parts.pop_back(); } continue; }
                parts.push_back( seg );
            }
        };
        push( base );
        push( source );
        std::string joined;
        for( std::string_view p : parts ) { if( !joined.empty() ) { joined.push_back( '/' ); } joined.append( p ); }
        std::string_view stem = target;
        if( const std::size_t dot = stem.rfind( '.' ); dot != std::string_view::npos && stem.find( '/', dot ) == std::string_view::npos )
        {
            stem = stem.substr( 0, dot );
        }
        return stem == joined || ( stem.ends_with( "/index" ) && stem.substr( 0, stem.size() - 6 ) == joined );
    }
};

}   // namespace rw
