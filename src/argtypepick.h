#pragma once
// argtypepick.h — B2.3 (lane overload-split, test/aritycheck.sh section 3d): a C++ call whose SAME-ARITY overloads the arity
// filter (graph.h B2.2) left tied is bound to the one overload every argument's DECLARED type matches exactly.
//
// The audit row (edge audit 2026-11-17, class 11): envoy's `void WatermarkBuffer::prepend( absl::string_view data ) {
// OwnedImpl::prepend( data ); }` was split onto BOTH OwnedImpl::prepend overloads (string_view and Instance&), prov="split",
// though the parameter's written type names one of them. A split arm onto the overload the call cannot mean is a wrong edge.
//
// THE INVARIANT (C++ overload resolution, [over.match.best] / [over.ics.rank]). Every argument is a NAMED VARIABLE, so an
// lvalue of its declared type. A candidate is PERFECT when each parameter receives its argument by the identity conversion
// with nothing added: the same type taken by value, or by an lvalue reference with exactly the argument's own cv-
// qualification. No implicit conversion sequence ranks above that one, so no other candidate is better on any argument; a
// candidate as good on every argument would make the call ambiguous (ill-formed). So when the code compiles and ONE
// non-template candidate is perfect, that candidate is the one the call selects — whatever conversions (user-defined,
// derived-to-base, standard) the others would need. The pick binds it; anything less than that proof keeps today's split.
//
// What "the same type" is proven by, and every way the proof fails closed (the split stands):
//   * the tier: two or more C++ functions or methods, one name, one scope (one class's own overload set, so no name hiding
//     between them), the same member cv/ref qualifiers (the implicit object argument then ranks them all alike), none a
//     template (a `template <…>` head before the definition, or the brief's rule: a template overload keeps the split);
//   * the arguments: the call's text (read at its start byte) is `name( a, b, … )` with every argument a bare identifier,
//     exactly argCount of them, and the call is not the receiver of a further call (`f( x ).f( y )`: the two calls share a
//     start byte); explicit template arguments refuse;
//   * each argument's declaration: the innermost declaration of the name covering the call (resolve.h's lexical table,
//     buildScopedRecvDecls) is a PARAMETER of the calling definition itself — a local, a lambda parameter, a field or a
//     global refuses (a stated floor: a by-value local is not in that table at all);
//   * the written types: parameter-list text read by --edit-check's tokenizer (cppscopechain.h editCheckTypeTokens);
//     arrays, function pointers, `volatile`, `auto`, `decltype` and variadics refuse. Each identifier the type spells is a
//     builtin word, a <cstdint>/<cstddef> alias, a QUALIFIED name, or the name of an indexed C++ type that no indexed class
//     nests (a template parameter `T` names no indexed type, so it refuses), and the caller and every candidate sit in the
//     same namespace chain (cppFullChainOf minus trailing class labels) — so one spelling names one type in both places;
//   * file text: each file is read whole and must still be the length the index parsed (a stale file refuses).
//   * the receiver: a NAME-ONLY site (graph.h FE-B: no lookup proved the candidates are the receiver's — `real_.f( x )` through
//     an unresolved field) refuses, and a qualified call `Q::f( x )` refuses unless Q is the candidates' own scope (envoy's
//     `proxy_wasm::BufferBase::set( data )` inside a namesake overload set: the set is not the one the call names);
// Never on a SCIP- or binding-pinned site (graph.h runs it inside B2.1/B2.2's guard). Deterministic: a pure function of
// the index and the files it indexed; at most two source files are held at once.
#include "model.h"
#include "resolve.h"            // ScopedRecvDecls / Narrower::innermostCoveringDecl — the lexical declaration of an argument's name
#include "cppscopechain.h"      // editCheckBlankComments / editCheckParamOpen / editCheckSplitParams / editCheckTypeTokens / the chain readers
#include "docparse.h"           // detail::readWholeFile — the one whole-file read
#include "infra/namesplit.h"    // namesplit::isIdentChar

#include <algorithm>
#include <cstdint>
#include <deque>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace rw
{

// The C/C++ full chain of one definition (enclosing namespaces and classes, then its written qualifier), read off the
// comment-blanked source; nullopt when the reader cannot prove it (graph.h resolveAllByWrittenSpelling's contract). Moved
// here verbatim from graph.h (lane overload-split) so the argument-type pick below reads the same chain.
inline std::optional<std::vector<std::string>> cppFullChainOf( const Symbol& s, std::string_view file )
{
    const std::uint32_t end = std::min<std::uint32_t>( isDefinitionNotDeclaration( s ) ? s.sigEndByte : s.endByte, std::uint32_t( file.size() ) );
    if( end <= s.sigStartByte )
    {
        return std::nullopt;
    }
    const std::size_t nameAt = editCheckParamOpen( file.substr( s.sigStartByte, end - s.sigStartByte ), s.name ).first;
    if( nameAt == std::string_view::npos )
    {
        return std::nullopt;
    }
    const std::size_t                              nameInFile = s.sigStartByte + nameAt;
    const std::optional<EditCheckWrittenQualifier> written    = editCheckWrittenQualifier( file, nameInFile );
    EditCheckBraceLexer                            lexer( file );
    std::optional<std::vector<std::string>>        chain      = lexer.chainAt( nameInFile );
    if( !written || !chain || ( !written->names.empty() && !written->absolute && lexer.usingDirectiveBefore() ) )
    {
        return std::nullopt;
    }
    if( written->absolute )
    {
        chain->clear();
    }
    chain->insert( chain->end(), written->names.begin(), written->names.end() );
    return chain;
}

// One written type, reduced to what overload resolution compares for an lvalue argument: the type without its top-level
// reference and top-level const (`core`), whether that const was there, and the reference kind. `known` is false for any
// spelling the reduction does not cover.
struct ArgTypeShape
{
    std::vector<std::string> core;
    bool                     topConst = false;
    std::uint8_t             ref      = 0;   // 0 none, 1 `&`, 2 `&&`
    bool                     known    = false;
};

// `toks`: one parameter's type tokens (editCheckTypeTokens: the declarator name already dropped)
inline ArgTypeShape argTypeShapeOf( std::vector<std::string> toks )
{
    ArgTypeShape shape;
    constexpr std::string_view kRefuse[]    = { "[", "]", "(", ")", "volatile", "auto", "decltype", "=", "." };
    constexpr std::string_view kElaborate[] = { "struct", "class", "union", "enum", "typename", "register" };
    if( std::ranges::any_of( toks, [ & ]( const std::string& t ) { return std::ranges::find( kRefuse, std::string_view( t ) ) != std::end( kRefuse ); } ) )
    {
        return shape;
    }
    std::erase_if( toks, [ & ]( const std::string& t ) { return std::ranges::find( kElaborate, std::string_view( t ) ) != std::end( kElaborate ); } );
    while( !toks.empty() && toks.back() == "&" && shape.ref < 3 )
    {
        toks.pop_back();
        ++shape.ref;
    }
    if( shape.ref > 2 )
    {
        return shape;
    }
    if( std::ranges::find( toks, std::string( "*" ) ) != toks.end() )
    {
        while( !toks.empty() && toks.back() == "const" )   // `T* const`: the pointer itself is const
        {
            toks.pop_back();
            shape.topConst = true;
        }
    }
    else
    {
        shape.topConst = std::erase( toks, std::string( "const" ) ) != 0;   // `const T` / `T const`: one type, either order
    }
    if( toks.empty() || std::ranges::find( toks, std::string( "&" ) ) != toks.end() )
    {
        return shape;
    }
    shape.core  = std::move( toks );
    shape.known = true;
    return shape;
}

// The identity conversion with nothing added, for an lvalue argument of `arg`'s declared type (see the header)
inline bool argTypePerfect( const ArgTypeShape& arg, const ArgTypeShape& param ) noexcept
{
    if( !arg.known || !param.known || param.ref == 2 || arg.core != param.core )
    {
        return false;
    }
    return param.ref == 0 || param.topConst == arg.topConst;
}

// Where a call's bare-identifier arguments sit in its file text: the `name( … )` at paren depth 0 from the call's start
// byte. nullopt for any other shape (see the header's arguments clause).
inline std::optional<std::vector<std::string_view>> callIdentifierArgs( std::string_view text, std::uint32_t start, std::string_view name )
{
    constexpr std::size_t kWindow = 4096;   // a callee expression longer than this is not read
    int                   depth   = 0;
    for( std::size_t i = start; i < text.size() && i < std::size_t( start ) + kWindow; ++i )
    {
        const char c = text[ i ];
        if( c == '"' || c == '\'' || c == ';' || c == '{' || c == '}' )
        {
            return std::nullopt;   // a literal or a statement boundary before the callee name: not a shape this reads
        }
        depth += ( c == '(' || c == '[' ) ? 1 : ( c == ')' || c == ']' ) ? -1 : 0;
        if( depth != 0 || text.compare( i, name.size(), name ) != 0 || ( i > 0 && namesplit::isIdentChar( text[ i - 1 ] ) )
         || ( i + name.size() < text.size() && namesplit::isIdentChar( text[ i + name.size() ] ) ) )
        {
            continue;
        }
        const std::size_t open = text.find_first_not_of( " \t\r\n", i + name.size() );
        if( open == std::string_view::npos || text[ open ] != '(' )
        {
            return std::nullopt;   // `name<T>( … )`, or the name is not the callee
        }
        std::vector<std::string_view> args;
        std::size_t                   from = open + 1;
        for( std::size_t j = from; j < text.size(); ++j )
        {
            const char d = text[ j ];
            if( d != ',' && d != ')' )
            {
                if( !namesplit::isIdentChar( d ) && d != ' ' && d != '\t' && d != '\r' && d != '\n' )
                {
                    return std::nullopt;   // an argument that is not a bare identifier
                }
                continue;
            }
            const std::size_t b = text.find_first_not_of( " \t\r\n", from );
            const std::size_t e = text.find_last_not_of( " \t\r\n", j - 1 );
            if( b >= j || e < b )
            {
                if( d == ')' && args.empty() && b >= j )
                {
                    return args;   // `name()`
                }
                return std::nullopt;
            }
            const std::string_view arg = text.substr( b, e + 1 - b );
            if( std::ranges::any_of( arg, []( char ch ) { return !namesplit::isIdentChar( ch ); } ) || ( arg[ 0 ] >= '0' && arg[ 0 ] <= '9' ) )
            {
                return std::nullopt;   // `a b` (a macro-built argument) or a number
            }
            args.push_back( arg );
            from = j + 1;
            if( d == ')' )
            {
                const std::size_t after = text.find_first_not_of( " \t\r\n", j + 1 );
                const bool        chained = after != std::string_view::npos && ( text[ after ] == '.' || text[ after ] == '(' || text[ after ] == '['
                                                                                || text.compare( after, 2, "->" ) == 0 );
                return chained ? std::nullopt : std::optional<std::vector<std::string_view>>( std::move( args ) );
            }
        }
        return std::nullopt;
    }
    return std::nullopt;
}

class ArgTypeOverloadPick
{
public:
    ArgTypeOverloadPick( const IngestResult& input, const ScopedRecvDecls& declarations ) : ing( input ), decls( declarations ) {}

    // The one perfect candidate of `tier` for call `r`, or kNoNode (the tier stands). See the header for the contract.
    // receiverProven: the resolver's own lookup proved the candidates are the receiver's (graph.h: not a NAME-ONLY site).
    NodeId pick( const Reference& r, std::span<const NodeId> tier, bool receiverProven )
    {
        if( r.lang != Lang::Cpp || !receiverProven || !r.argCountKnown || r.argCount == 0 || r.fromSymbol == kNoNode || tier.size() < 2
            || !oneOverloadSet( tier, r.argCount ) || ( !r.qualifier.empty() && r.qualifier.str() != ing.symbols[ tier[ 0 ] ].scope ) )
        {
            return kNoNode;
        }
        const Symbol&      caller   = ing.symbols[ r.fromSymbol ];
        const std::string* callText = caller.lang == Lang::Cpp && caller.fileId == r.fileId ? textOf( r.fileId, callerSlot ) : nullptr;
        if( callText == nullptr )
        {
            return kNoNode;
        }
        const std::optional<std::vector<std::string_view>> args = callIdentifierArgs( *callText, r.startByte, r.calleeName.str() );
        if( !args || args->size() != r.argCount )
        {
            return kNoNode;
        }
        const Signature& callerSig = signatureOf( r.fromSymbol );   // memo entries never move (a deque): these references stay valid
        if( !callerSig.ok || !callerSig.namespaces )
        {
            return kNoNode;
        }
        argShapes.clear();
        for( const std::string_view a : *args )
        {
            const ArgTypeShape* shape = argumentShape( r, callerSig, a );
            if( shape == nullptr )
            {
                return kNoNode;
            }
            argShapes.push_back( shape );
        }
        const Signature& firstSig = signatureOf( tier[ 0 ] );
        NodeId           perfect  = kNoNode;
        for( const NodeId c : tier )
        {
            const Signature& sig = signatureOf( c );
            if( !sig.ok || sig.isTemplate || sig.quals != firstSig.quals || sig.namespaces != callerSig.namespaces )
            {
                return kNoNode;
            }
            bool all = ing.symbols[ c ].params == r.argCount;
            for( std::size_t i = 0; all && i < argShapes.size(); ++i )
            {
                all = argTypePerfect( *argShapes[ i ], sig.params[ i ] );
            }
            if( all && perfect != kNoNode )
            {
                return kNoNode;   // two perfect candidates: the call would be ambiguous, so the reading is wrong somewhere
            }
            perfect = all ? c : perfect;
        }
        return perfect;
    }

private:
    // one definition's parameter list, as the pick reads it
    struct Signature
    {
        std::vector<ArgTypeShape>               params;
        std::vector<std::string>                names;    // each parameter's declarator name ("" when it has none)
        std::vector<std::uint32_t>              starts;   // each parameter's text start in the file: where its ParamType record sits
        std::vector<std::uint32_t>              ends;
        std::optional<std::vector<std::string>> namespaces;
        std::string                             quals;
        bool                                    ok         = false;
        bool                                    isTemplate = false;
    };
    // a source file held for the pick: one slot for the calling file, one for the candidates'
    struct FileSlot
    {
        std::uint32_t fileId = UINT32_MAX;
        bool          ok     = false;
        std::string   text;
    };

    // the tier is ONE class's (or namespace's) own overload set: C++ functions or methods of one name and scope, each able to
    // take argCount arguments by its parameter count
    bool oneOverloadSet( std::span<const NodeId> tier, std::uint16_t argCount ) const
    {
        const Symbol& first = ing.symbols[ tier[ 0 ] ];
        return std::ranges::all_of( tier, [ & ]( NodeId c )
        {
            const Symbol& s = ing.symbols[ c ];
            return s.lang == Lang::Cpp && ( s.kind == SymKind::Function || s.kind == SymKind::Method ) && s.name == first.name && s.scope == first.scope
                && s.params >= argCount;
        } );
    }

    const std::string* textOf( std::uint32_t fileId, FileSlot& slot )
    {
        if( slot.fileId != fileId )
        {
            slot.fileId                     = fileId;
            std::optional<std::string> body = docparse::detail::readWholeFile( diskPath( ing, fileId ) );
            const std::uint32_t        want = fileId < ing.fileHealth.size() ? ing.fileHealth[ fileId ].fileBytes : 0u;
            slot.ok                         = body && ( want == 0 || body->size() == want );   // a file edited since the index refuses
            slot.text                       = slot.ok ? std::move( *body ) : std::string();
            if( slot.ok )
            {
                editCheckBlankComments( slot.text );
            }
        }
        return slot.ok ? &slot.text : nullptr;
    }

    // the declared shape of argument `name` at call `r`: the calling definition's own parameter of that name, when it is the
    // innermost declaration of the name covering the call and every identifier its type spells is provable (see the header)
    const ArgTypeShape* argumentShape( const Reference& r, const Signature& callerSig, std::string_view name )
    {
        buildShadowKey( key, r.fromSymbol, name );
        const auto it = decls.byName.find( key );
        if( it == decls.byName.end() )
        {
            return nullptr;
        }
        const ScopedRecvDecl* innermost = Narrower::innermostCoveringDecl( it->second, r.startByte );
        if( innermost == nullptr )
        {
            return nullptr;
        }
        for( std::size_t k = 0; k < callerSig.params.size(); ++k )
        {
            if( callerSig.starts[ k ] <= innermost->declByte && innermost->declByte < callerSig.ends[ k ] && callerSig.names[ k ] == name )
            {
                return provable( callerSig.params[ k ] ) ? &callerSig.params[ k ] : nullptr;
            }
        }
        return nullptr;   // a local, a lambda parameter, a range-for variable: not the definition's own parameter
    }

    // one definition's Signature, read once per run; held in a deque, so a reference handed out stays valid
    const Signature& signatureOf( NodeId id )
    {
        if( const auto it = signatureAt.find( id ); it != signatureAt.end() )
        {
            return signatures[ it->second ];
        }
        const Symbol&      s    = ing.symbols[ id ];
        const std::string* text = textOf( s.fileId, s.fileId == callerSlot.fileId ? callerSlot : candidateSlot );
        signatures.push_back( text == nullptr ? Signature{} : readSignature( s, *text ) );
        signatureAt.emplace( id, std::uint32_t( signatures.size() - 1 ) );
        return signatures.back();
    }

    Signature readSignature( const Symbol& s, std::string_view file )
    {
        Signature           sig;
        const std::uint32_t end = std::min<std::uint32_t>( isDefinitionNotDeclaration( s ) ? s.sigEndByte : s.endByte, std::uint32_t( file.size() ) );
        if( end <= s.sigStartByte || end - s.sigStartByte > kArgTypeSigCap )
        {
            return sig;
        }
        const std::string_view   text           = file.substr( s.sigStartByte, end - s.sigStartByte );
        const auto [ nameAt, open ]             = editCheckParamOpen( text, s.name );
        const EditCheckRawParams raw            = open == std::string_view::npos ? EditCheckRawParams{} : editCheckSplitParams( text, open );
        if( !raw.closed || raw.text.size() != s.params )
        {
            return sig;
        }
        for( std::size_t k = 0; k < raw.text.size(); ++k )
        {
            const std::string_view param = raw.defaulted[ k ] ? raw.text[ k ].substr( 0, raw.text[ k ].find( '=' ) ) : raw.text[ k ];
            if( param.find( "..." ) != std::string_view::npos || param.find( '(' ) != std::string_view::npos )
            {
                return sig;
            }
            const std::vector<std::string> toks = editCheckTokens( param );
            sig.params.push_back( argTypeShapeOf( editCheckTypeTokens( param ) ) );
            sig.names.push_back( !toks.empty() && namesplit::isIdentChar( toks.back()[ 0 ] ) ? toks.back() : std::string() );
            sig.starts.push_back( s.sigStartByte + std::uint32_t( raw.text[ k ].data() - text.data() ) );
            sig.ends.push_back( sig.starts.back() + std::uint32_t( raw.text[ k ].size() ) );
        }
        sig.quals      = editCheckMemberQualifiers( file, s.sigStartByte + raw.closeAt + 1 );
        sig.isTemplate = templateHeadBefore( file, s.sigStartByte ) || text.substr( 0, nameAt ).find( "template" ) != std::string_view::npos;
        sig.namespaces = cppFullChainOf( s, file );
        while( sig.namespaces && !sig.namespaces->empty() && classNames().contains( sig.namespaces->back() ) )
        {
            sig.namespaces->pop_back();   // the class labels: lookup inside them is the nested-type guard's (provable)
        }
        sig.ok = true;
        return sig;
    }

    // a `template <…>` head ends right before the definition: the byte before it (blanks skipped) is a `>` that is not the
    // end of a preprocessor line (`#include <x>`)
    static bool templateHeadBefore( std::string_view file, std::uint32_t at ) noexcept
    {
        const std::size_t last = at == 0 ? std::string_view::npos : file.find_last_not_of( " \t\r\n", at - 1 );
        if( last == std::string_view::npos || file[ last ] != '>' )
        {
            return false;
        }
        const std::size_t lineStart = file.find_last_of( '\n', last );
        const std::size_t first     = file.find_first_not_of( " \t", lineStart == std::string_view::npos ? 0 : lineStart + 1 );
        return first == std::string_view::npos || file[ first ] != '#';
    }

    // every identifier the type spells names one type wherever the namespace chain is the same (see the header)
    bool provable( const ArgTypeShape& shape )
    {
        constexpr std::string_view kBuiltin[] = { "int", "long", "short", "char", "unsigned", "signed", "double", "float", "bool", "void", "wchar_t",
                                                  "char8_t", "char16_t", "char32_t", "const", "size_t", "ptrdiff_t", "intptr_t", "uintptr_t",
                                                  "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t" };
        return shape.known && std::ranges::all_of( shape.core, [ & ]( const std::string& t )
        {
            if( t.empty() || !namesplit::isIdentChar( t[ 0 ] ) || t.find( "::" ) != std::string::npos || std::ranges::find( kBuiltin, std::string_view( t ) ) != std::end( kBuiltin ) )
            {
                return true;   // punctuation (`*`, `<`, `,`), a qualified name, a builtin word
            }
            return typeNames().contains( t ) && !nestedTypeNames().contains( t );
        } );
    }

    // the indexed C++ type names, the class and struct names among them, and the type names some indexed class nests
    // (built on first use: a run with no qualifying call builds none of them)
    static bool typeLike( SymKind k ) noexcept
    {
        return k == SymKind::Class || k == SymKind::Struct || k == SymKind::Interface || k == SymKind::Other || k == SymKind::NamedType
            || k == SymKind::Alias || k == SymKind::FuncType;
    }
    // A type is NESTED when its span lies inside an indexed class's or struct's in the same file (Symbol::scope cannot say:
    // a C++ class's scope is its own name). ing.symbols is in (file, line) order, so the open classes are a stack.
    void buildTypeTables()
    {
        tablesBuilt = true;
        std::vector<const Symbol*> open;
        for( const Symbol& s : ing.symbols )
        {
            if( s.lang != Lang::Cpp || !typeLike( s.kind ) )
            {
                continue;
            }
            types.insert( s.name );
            while( !open.empty() && ( open.back()->fileId != s.fileId || open.back()->endByte <= s.sigStartByte ) )
            {
                open.pop_back();
            }
            if( !open.empty() )
            {
                nested.insert( s.name );
            }
            if( s.kind == SymKind::Class || s.kind == SymKind::Struct )
            {
                classes.insert( s.name );
                open.push_back( &s );
            }
        }
    }
    const HashSet<std::string>& typeNames()
    {
        if( !tablesBuilt ) { buildTypeTables(); }
        return types;
    }
    const HashSet<std::string>& classNames()
    {
        if( !tablesBuilt ) { buildTypeTables(); }
        return classes;
    }
    const HashSet<std::string>& nestedTypeNames()
    {
        if( !tablesBuilt ) { buildTypeTables(); }
        return nested;
    }

    static constexpr std::uint32_t kArgTypeSigCap = 16384;   // --edit-check's kEditCheckSigCap: a longer signature is not read

    const IngestResult&                 ing;
    const ScopedRecvDecls&              decls;
    FileSlot                            callerSlot;
    FileSlot                            candidateSlot;
    std::deque<Signature>               signatures;
    HashMap<NodeId, std::uint32_t>      signatureAt;
    std::vector<const ArgTypeShape*>    argShapes;
    std::string                         key;
    HashSet<std::string>                types;
    HashSet<std::string>                classes;
    HashSet<std::string>                nested;
    bool                                tablesBuilt = false;
};

}   // namespace rw
