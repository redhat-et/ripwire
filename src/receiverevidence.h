#pragma once
// receiverevidence.h — FE-B (test/receiverevidencecheck.sh): what proves a call's RECEIVER, and what does not.
//
// A member call `x.m()` (or, where the receiver is implicit, a bare `m()`) used to bind to every in-repo definition
// spelled `m` that the name ladder reached, and the answer showed each such row as a plain edge — a confident claim
// with nothing behind it but the name. This header holds the two halves of the fix:
//
//   1. ReceiverEvidence::narrow — a RESOLVE rule for receivers the source types: `this`/`self`/`cls` inside a class (and
//      `super`/`base`, through the bases only), a parameter or local whose class is written (a TS/Python/Go annotation, a
//      Go method receiver, a JS `new Foo()` / Python `Foo()` / Go `Foo{}` initializer), a constructed receiver
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

#include <cstdint>
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

inline bool isSuperRoot( std::string_view root ) noexcept
{
    return root == "super" || root == "base";
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
    HashMap<std::string, std::string>                     localType;       // "<fromSymbol>#var" → class ("" = tombstone)
    HashMap<std::string, std::pair<std::string, std::string>> methodAlias; // "<fromSymbol>#var" → ( object var, method )
    HashMap<std::string, std::string>                     moduleAlias;     // "<fileId>#name" → module as written ("" = tombstone)
    std::vector<std::vector<NodeId>>                      fnsByFile;       // fileId → functions/methods sorted by start (enclosing walk)
    std::vector<std::vector<NodeId>>                      classesByFile;   // fileId → class-like symbols sorted by start
    mutable std::string                                   key;
    mutable std::vector<std::string_view>                 frontier;
    mutable rw::SmallVec<NodeId, 2>                       found;
    bool                                                  active = false;
    const HashMap<std::string, char>*                     localNames = nullptr;   // graph.h FieldNarrowTables::localNameSet

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
                tombstoneInsert( localType, keyOf( from, '#', b.var ), b.typeName );
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
    NodeId enclosingFn( NodeId id ) const
    {
        const Symbol& inner = ing.symbols[ id ];
        if( inner.fileId >= fnsByFile.size() )
        {
            return kNoNode;
        }
        NodeId best = kNoNode;
        for( NodeId c : fnsByFile[ inner.fileId ] )
        {
            const Symbol& s = ing.symbols[ c ];
            if( s.sigStartByte > inner.sigStartByte )
            {
                break;
            }
            if( c != id && s.endByte >= inner.endByte && ( s.sigStartByte < inner.sigStartByte || s.endByte > inner.endByte ) )
            {
                best = c;
            }
        }
        return best;
    }
    // the class a typed local names in `from` or a function enclosing it; nullptr when untyped (or tombstoned)
    const std::string* typedLocal( NodeId from, std::string_view var ) const
    {
        NodeId cur = from;
        for( int depth = 0; depth < 8 && cur != kNoNode; ++depth )
        {
            if( const auto it = localType.find( keyOf( cur, '#', var ) ); it != localType.end() )
            {
                return it->second.empty() ? nullptr : &it->second;
            }
            cur = enclosingFn( cur );
        }
        return nullptr;
    }
    const std::pair<std::string, std::string>* aliasedMethod( NodeId from, std::string_view var, NodeId& scope ) const
    {
        NodeId cur = from;
        for( int depth = 0; depth < 8 && cur != kNoNode; ++depth )
        {
            if( const auto it = methodAlias.find( keyOf( cur, '#', var ) ); it != methodAlias.end() )
            {
                scope = cur;
                return it->second.first.empty() ? nullptr : &it->second;
            }
            cur = enclosingFn( cur );
        }
        return nullptr;
    }
    // is `name` a parameter or local of `from` or of a function enclosing it (any binding the extractor recorded)
    bool isLocalName( NodeId from, std::string_view name ) const
    {
        if( localNames == nullptr )
        {
            return false;
        }
        NodeId cur = from;
        for( int depth = 0; depth < 8 && cur != kNoNode; ++depth )
        {
            if( localNames->contains( keyOf( cur, '#', name ) ) || localType.contains( keyOf( cur, '#', name ) ) )
            {
                return true;
            }
            cur = enclosingFn( cur );
        }
        return false;
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
        NodeId cur = from;
        for( int depth = 0; depth < 8 && cur != kNoNode; ++depth )
        {
            if( !ownerClass[ cur ].empty() )
            {
                return ownerClass[ cur ];
            }
            cur = enclosingFn( cur );
        }
        return {};
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
        std::vector<std::string_view> level{ type };
        std::vector<std::string_view> seen{ type };
        for( std::size_t depth = 0; depth < kWalkCap && !level.empty(); ++depth )
        {
            if( !( superOnly && depth == 0 ) )
            {
                for( std::string_view t : level )
                {
                    if( const auto it = methodsByType.find( typeKey( t, "::", name ) ); it != methodsByType.end() )
                    {
                        for( NodeId c : it->second ) { found.push_back( c ); }
                    }
                }
                if( !found.empty() )
                {
                    return true;
                }
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
    // the class of field `field` on `type` (or the shallowest base declaring it); "" unknown
    std::string_view fieldOf( std::string_view type, std::string_view field ) const
    {
        std::vector<std::string_view> level{ type };
        std::vector<std::string_view> seen{ type };
        for( std::size_t depth = 0; depth < kWalkCap && !level.empty(); ++depth )
        {
            for( std::string_view t : level )
            {
                if( const auto it = memberType.find( typeKey( t, "#", field ) ); it != memberType.end() )
                {
                    return it->second;   // "" = tombstone: unknown
                }
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
        return {};
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
        if( isSuperRoot( root ) )
        {
            superOnly = true;
            return callerClass( r.fromSymbol );
        }
        if( const std::string* t = typedLocal( r.fromSymbol, root ) )
        {
            return unalias( r.fileId, *t );
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
        bool classSide = isStatic || ( ch.ctor.empty() && ( isThisRoot( ch.root ) || isSuperRoot( ch.root ) ) && callerIsStatic( r.fromSymbol ) );
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
        const std::string* type = typedLocal( scope, alias->first );
        return type != nullptr && methodOf( unalias( r.fileId, *type ), alias->second, false );
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
            // an import path names a package DIRECTORY; the candidate's directory must end the path, segment-aligned
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
