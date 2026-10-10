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

#include "model.h"
#include "resolve.h"   // includerDir; HashMap / SmallVec through it
#include "smallvec.h"

#include <algorithm>
#include <cstdint>
#include <optional>
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

struct ReceiverEvidence
{
    static constexpr std::size_t kWalkCap = 64;   // classes visited per base walk; deterministic (sorted chaUp)

    const IngestResult&                                   ing;
    const HashMap<std::string, std::vector<std::string>>& chaUp;       // class name → its direct base names (sorted)
    const HashMap<std::string, char>&                     classNames;  // every in-repo class-like name
    std::vector<std::string>                              ownerClass;  // per symbol: the class that owns it, "" none
    std::vector<std::uint8_t>                             staticMember;    // per symbol: 1 = a JS/TS `static` member (the CLASS side)
    HashMap<std::string, rw::SmallVec<NodeId, 2>>         methodsByType;   // "Class::name" → its callables
    HashMap<std::string, std::string>                     memberType;      // "Class#field" → field class ("" = tombstone)
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

    ReceiverEvidence( const IngestResult& i, const HashMap<std::string, std::vector<std::string>>& up, const HashMap<std::string, char>& classes )
        : ing( i ), chaUp( up ), classNames( classes ) {}

    static bool classLike( SymKind k ) noexcept
    {
        return k == SymKind::Class || k == SymKind::Struct || k == SymKind::Interface;
    }
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

    void addLocalFact( const std::string& k, const Binding& b )
    {
        const bool                  spanned = b.spanEnd > b.spanStart;
        LocalFact                   f{ spanned ? b.spanStart : 0u, spanned ? b.spanEnd : 0u, b.typeName };
        std::vector<LocalFact>&     facts = localType[ k ];
        if( std::none_of( facts.begin(), facts.end(), [ & ]( const LocalFact& g ) { return g.start == f.start && g.end == f.end && g.type == f.type; } ) )
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
            if( callableKind( s.kind ) && !ownerClass[ s.id ].empty() && receiverHedgeLang( s.lang ) && s.endByte > s.sigEndByte )
            {
                methodsByType[ typeKey( ownerClass[ s.id ], "::", s.name ) ].push_back( s.id );
            }
        }
        const std::size_t N = ing.symbols.size();
        for( const Binding& b : ing.bindings )
        {
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
            // a typed local the extractor also indexed as a symbol of its own (a Go `var c T` inside a function) belongs
            // to the function that declares it
            NodeId from = b.fromSymbol;
            if( !callableKind( ing.symbols[ from ].kind ) && !classLike( ing.symbols[ from ].kind ) )
            {
                if( const NodeId fn = enclosingFn( from ); fn != kNoNode )
                {
                    from = fn;
                }
            }
            const bool typedLocal = b.kind == LocalBindKind::RecvType
                                 || ( b.kind == LocalBindKind::Type && ( ing.symbols[ b.fromSymbol ].lang == Lang::TypeScript
                                                                         || ing.symbols[ b.fromSymbol ].lang == Lang::Python ) );
            if( b.kind == LocalBindKind::StaticMember )
            {
                if( ing.symbols[ from ].name == b.var )   // recorded inside the member's body: the member itself
                {
                    staticMember[ from ] = 1;
                }
            }
            else if( typedLocal && !b.var.empty() )
            {
                addLocalFact( keyOf( from, '#', b.var ), b );
            }
            else if( b.kind == LocalBindKind::MemberType && !b.var.empty() )
            {
                const Symbol&      from  = ing.symbols[ b.fromSymbol ];
                const std::string& owner = classLike( from.kind ) ? from.name : ownerClass[ b.fromSymbol ];
                if( owner.empty() )
                {
                    continue;
                }
                tombstoneInsert( memberType, typeKey( owner, "#", b.var ), b.typeName );
                if( b.isFromAssignment )
                {
                    addBase( owner, b.typeName );
                }
            }
            else if( b.kind == LocalBindKind::MethodAlias && !b.var.empty() )
            {
                const auto [ it, fresh ] = methodAlias.try_emplace( keyOf( from, '#', b.var ), b.typeName, b.importedName );
                if( !fresh && ( it->second.first != b.typeName || it->second.second != b.importedName ) )
                {
                    it->second.first.clear();   // rebound to something else: decide nothing
                }
            }
        }
        active = true;
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
    // visible there; "": one is, and it names no single class.
    std::optional<std::string_view> visibleLocal( NodeId scope, std::string_view var, std::uint32_t site ) const
    {
        const auto it = localType.find( keyOf( scope, '#', var ) );
        if( it == localType.end() )
        {
            return std::nullopt;
        }
        const LocalFact* inner = nullptr;
        bool             innerSplit = false;
        std::optional<std::string_view> whole;
        for( const LocalFact& f : it->second )
        {
            if( f.end == 0 )
            {
                whole = ( whole.has_value() && *whole != f.type ) ? std::string_view{} : std::string_view( f.type );
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
            else if( f.start == inner->start && f.end == inner->end && f.type != inner->type )
            {
                innerSplit = true;
            }
        }
        if( inner == nullptr )
        {
            return whole;
        }
        const std::string_view seen = innerSplit ? std::string_view{} : std::string_view( inner->type );
        return ( whole.has_value() && *whole != seen ) ? std::string_view{} : seen;
    }
    // the local `var` visible at byte `site` of `from` or of a function enclosing it (the innermost that has one)
    std::optional<std::string_view> localAt( NodeId from, std::string_view var, std::uint32_t site ) const
    {
        std::optional<std::string_view> hit;
        walkScopes( from, [ & ]( NodeId scope )
        {
            hit = visibleLocal( scope, var, site );
            return hit.has_value();
        } );
        return hit;
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
    bool namesClass( const Reference& r, std::string_view root, std::string_view cls ) const
    {
        return classNameReceiverLang( r.lang ) && classNames.contains( std::string( cls ) ) && !isLocalName( r.fromSymbol, root );
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
    bool methodOf( std::string_view type, std::string_view name, bool superOnly ) const
    {
        EXPECTS( active, "methodOf reads the tables build() fills" );
        found.clear();
        if( type.empty() )
        {
            return false;
        }
        return walkBaseLevels( type, [ & ]( const std::vector<std::string_view>& level, std::size_t depth )
        {
            if( superOnly && depth == 0 )
            {
                return false;
            }
            for( std::string_view t : level )
            {
                if( const auto it = methodsByType.find( typeKey( t, "::", name ) ); it != methodsByType.end() )
                {
                    for( NodeId c : it->second ) { found.push_back( c ); }
                }
            }
            return !found.empty();
        } );
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
    std::string_view rootClass( const Reference& r, const Chain& ch, bool& isStatic, bool& superOnly ) const
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
        if( const std::optional<std::string_view> t = localAt( r.fromSymbol, root, r.startByte ); t.has_value() && !t->empty() )
        {
            return unalias( r.fileId, *t );
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
    bool narrow( const Reference& r ) const
    {
        // C++, Ruby, Rust and C keep their own receiver rules (Rules 1, 2, 2b, 2c): this one adds the languages that had none
        const bool typedLang = r.lang == Lang::JavaScript || r.lang == Lang::TypeScript || r.lang == Lang::Python || r.lang == Lang::Go
                            || r.lang == Lang::Java || r.lang == Lang::Kotlin || r.lang == Lang::CSharp || r.lang == Lang::Swift;
        if( !active || r.fromSymbol >= ing.symbols.size() || !r.qualifier.empty() || !typedLang )
        {
            return false;
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
        std::string_view type = rootClass( r, ch, isStatic, superOnly );
        if( type.empty() )
        {
            return false;
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
        if( !methodOf( type, r.calleeName, superOnly ) )
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
