#pragma once
#if !defined( RIPWIRE_INGEST_TU )
#error "ingest_relations.h is a SECTION of src/ingest.cpp's translation unit - include it only from ingest.cpp (see the ingest-family split note there)"
#endif

// ingest_relations.h — cross-symbol relation capture, moved VERBATIM from ingest.cpp in the
// 2026-08-29 split: base-clause type references (isBaseTypeNode/emitBaseRef/captureBases with the
// Rust impl walk), function-like #define body call edges (the macro-edges round), field/composition
// capture (captureFields), and the import/include layer — importName and the per-language
// specifier readers (C# using, PHP use, JS module loads, preproc include/import), the
// import-container tables by language, directiveTargetOf and captureIncludes. Everything that turns
// one file's AST into edges BETWEEN symbols and files. Same contract as every ingest_*.h: reopens
// `namespace rw` and the unnamed namespace inside it — one TU, one unnamed namespace, internal
// linkage unchanged, zero new API surface — under the RIPWIRE_INGEST_TU guard.

namespace rw
{

namespace
{

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
        "qualified_name",         // C# `class Foo : Ns.Base` — dotted base/interface name; PHP `extends \Ns\Base`
        "name",                   // PHP's identifier node kind — `class Foo extends Bar implements Baz`
        "relative_name",          // PHP `extends namespace\Base` (namespace-relative)
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
// attribution assigns fromSymbol = the derived class. Explicit-syntax langs: C++/TS/JS/Java/Python/Swift/
// C#/PHP. Lua is deliberately absent and it is a DISCLOSED non-goal, not an omission: Lua inheritance IS
// `setmetatable( Derived, { __index = Base } )`, an ordinary runtime call over an ordinary table, so there
// is no syntax to read and a Lua corpus correctly reports no inheritance edges at all.
//
// The base type can sit at one of two depths under the class node (measured against the vendored grammars):
//   DIRECT  — a type node is an immediate child of the clause:
//               C++ base_class_clause → type_identifier ; Swift inheritance_specifier → user_type ;
//               Java superclass → type_identifier ; Python superclasses/argument_list → identifier ;
//               C# base_list → identifier/generic_name/qualified_name (`class Foo : Base, IBar`) ;
//               PHP base_clause / class_interface_clause → name/qualified_name/relative_name. PHP is the
//               only language here whose EXTENDS and IMPLEMENTS clauses are two distinct node kinds that
//               are both DIRECT children of the class node, so both are named above and neither wraps.
//               A trait acquired with `use SomeTrait;` INSIDE the class body is NOT an inheritance edge
//               here — it is a use_declaration under declaration_list, a different shape (disclosed).
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
                                || std::strcmp( ct, "base_list" ) == 0             // C#     : Base, IBar
                                || std::strcmp( ct, "base_clause" ) == 0           // PHP    extends Base
                                || std::strcmp( ct, "class_interface_clause" ) == 0; // PHP  implements I, J
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

// csharpUsingTarget's PHP sibling: the written specifier of a `use` statement. Node shapes read off
// tree-sitter-php v0.24.2's node-types.json and confirmed on a real parse:
//   use Foo\Bar;             namespace_use_declaration > namespace_use_clause > qualified_name
//   use Bar;                 namespace_use_declaration > namespace_use_clause > name
//   use Foo\Bar as Baz;      the same, plus an `alias:` field we deliberately ignore — the DEPENDENCY is
//                            the real name, not the local nickname (mirroring csharpUsingTarget, which
//                            also reports the aliased target rather than the alias)
//   use function Foo\bar;    a `type:` field on the CLAUSE ("function"/"const"); the specifier is
//                            unchanged, so nothing here needs to branch on it
//   use Foo\{A, B};          namespace_use_declaration > namespace_name + namespace_use_group — the
//                            group prefix IS the dependency, so the namespace_name is the right answer
//
// DISCLOSED FLOOR: a comma-grouped `use A\B, C\D;` yields ONE Include (the first clause). One directive
// node can only carry one target through directiveTargetOf, and PSR-12 forbids the multi-clause form, so
// this is the cheap honest cut rather than a reshape of the include record. Same posture as the nesting
// limit above it: a `use` written inside a BRACED `namespace Foo { … }` block is not reached at all,
// because PHP has no entry in isImportContainer (the file-scoped `namespace Foo;` form PSR-12 mandates
// is top-level and unaffected). Both are misses, never wrong answers.
inline std::string phpUseTarget( TSNode useNode, std::string_view src )
{
    const uint32_t cc = ts_node_child_count( useNode );
    for( uint32_t k = 0; k < cc; ++k )
    {
        const TSNode c = ts_node_child( useNode, k );
        if( !ts_node_is_named( c ) )
        {
            continue;
        }
        const char* ct = ts_node_type( c );
        if( std::strcmp( ct, "namespace_name" ) == 0 )      // the `use Foo\{A, B}` group prefix
        {
            return importSpecifierText( c, src );
        }
        if( std::strcmp( ct, "namespace_use_clause" ) != 0 )
        {
            continue;
        }
        const uint32_t gc = ts_node_child_count( c );
        for( uint32_t j = 0; j < gc; ++j )
        {
            const TSNode g = ts_node_child( c, j );
            if( !ts_node_is_named( g ) )
            {
                continue;
            }
            const char* gt = ts_node_type( g );
            if( std::strcmp( gt, "qualified_name" ) == 0 || std::strcmp( gt, "name" ) == 0 )
            {
                return importSpecifierText( g, src );
            }
        }
    }
    return {};
}

// TS/JS `require("./x")` and dynamic `import("./x")` → the written specifier, or empty when this call
// expression is not a module load. Its own function for the same reason csharpUsingTarget and phpUseTarget
// are: one AST shape per language stays a one-line call inside directiveTargetOf, whose grain is one
// branch per grammar spelling rather than one branch plus one nested scan.
//
// THREE conditions, all required, and each is what keeps an ordinary call out of the dependency graph:
//   * the callee is the BARE identifier `require` or `import` — a member expression
//     (`require.resolve("./x")`, `foo.import(x)`) has different `function` node text and is not a module
//     load, so it never matches;
//   * there is EXACTLY ONE argument — `require(a, b)` is not the CommonJS form;
//   * that argument is a STRING LITERAL. A computed specifier (`require(name)`, `require("./" + n)`, a
//     template string) carries no resolvable path, and guessing one would MANUFACTURE a wrong edge — the
//     one thing buildPreciseIncludeAdj's contract forbids. It is dropped, which reads downstream as an
//     unresolvable include: a floor, never a wrong answer.
inline std::string jsModuleLoadTarget( TSNode n, std::string_view src )
{
    const std::string_view callee = nodeFieldText( n, "function", 8, src );
    if( callee != "require" && callee != "import" )
    {
        return {};
    }
    const TSNode ar = ts_node_child_by_field_name( n, "arguments", 9 );
    if( ts_node_is_null( ar ) )
    {
        return {};
    }

    TSNode   only  = { };
    uint32_t named = 0;
    for( uint32_t k = 0, cc = ts_node_child_count( ar ); k < cc; ++k )
    {
        if( const TSNode c = ts_node_child( ar, k );  ts_node_is_named( c ) )
        {
            only = c;
            ++named;
        }
    }
    if( named != 1 || std::strcmp( ts_node_type( only ), "string" ) != 0 )
    {
        return {};
    }
    return importSpecifierText( only, src );   // strips the one quote pair
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

// C/C++/ObjC `#include "x.h"` / `<x.h>` → the bare path, isAngle set from the delimiter. Its own
// function for the same reason csharpUsingTarget, phpUseTarget and jsModuleLoadTarget are: one AST shape
// per language keeps directiveTargetOf's grain at one branch per grammar spelling, instead of one branch
// plus its own null-and-bounds ladder. Empty when the node carries no readable path field.
inline std::string preprocIncludeTarget( TSNode n, std::string_view src, bool& isAngleOut )
{
    const std::string_view spelling = nodeFieldText( n, "path", 4, src );
    return spelling.empty() ? std::string{} : includePathOf( spelling, isAngleOut );
}

// The `#import "x.h"` spelling under the C/C++ grammar. `#import` is `#include` + include-once, so it
// MUST yield the same Include edge — this is the edge that connects a `.metal` shader to the FX headers
// it pulls in (10 of the 45 shaders in the measured reference tree use it). Under the objc grammar it
// already parses as preproc_include; under the C/C++ grammar there is no #import rule, so it lands as the
// generic preproc_call: directive:(preproc_directive) `#import`, argument:(preproc_arg) `"x.h"` / `<x.h>`.
// EVERY other preproc_call (`#pragma`, `#error`, `#warning`, an unknown directive) is not a physical
// dependency — the directive-text check is what keeps them out, so this never widens the include graph
// beyond #import.
inline std::string preprocImportTarget( TSNode n, std::string_view src, bool& isAngleOut )
{
    if( nodeFieldText( n, "directive", 9, src ) != "#import" )
    {
        return {};
    }
    const std::string_view spelling = nodeFieldText( n, "argument", 8, src );   // preproc_arg: runs to end-of-line
    return spelling.empty() ? std::string{} : includePathOf( spelling, isAngleOut );   // the closing delimiter ends the path
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
// Go, Swift, Java, Ruby) get the preprocessor set and nothing else, which is the whole of what their
// grammars nest: Go/Java imports are top-level by language rule.
//
// TS/JS used to be in that "nothing else" list, on the reasoning that ESM `import` is top-level-only and
// "a dynamic `import( … )` is a call expression, not an import_statement". Both halves were true and the
// conclusion was still wrong, because CommonJS `require("./x")` is a call expression too — and it is not
// a corner case, it is how an entire module system spells its dependencies. Measured on webpack: `--deps`
// over its 695-file CommonJS `lib/` reported files="0", i.e. ZERO file→file edges across the whole
// subsystem, and every consumer of that graph (--deps, --arch, cycles, the Lakos health verdict,
// --expand's sibling lift, the SameInclude call-resolution tier, and --impact's import tier) was reading
// an empty table and reporting the emptiness as a horizontal, cycle-free architecture. The four entries
// below are exactly the statement forms a top-level `require` is written in; the call node itself is read
// by directiveTargetOf, which is what keeps every OTHER call expression out.
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

// The FUNCTION-BODY node kinds — read off real parses, not predicted. Entering ANY one of these means
// everything inside it is written INSIDE a function's body, so a require()/import() found there only runs
// when and if that function runs: a real dependency (kParserVer 72's whole point — the importer tier must
// still name the file), but a WEAKER one than a top-level require, hence Include::isLazy. Kept as its own
// table, separate from kJsImportContainers below, because captureIncludes' walk tests membership in exactly
// this list — independently of the container-descent test — to flip `insideFn` for every descendant.
inline constexpr std::array<std::string_view, 6> kJsFunctionContainers = {
    "function_declaration", "function_expression", "generator_function", "generator_function_declaration",
    "arrow_function", "method_definition"
};

inline bool isJsFunctionLike( Lang lang, const char* type ) noexcept
{
    return ( lang == Lang::TypeScript || lang == Lang::JavaScript ) && namesNode( kJsFunctionContainers, type );
}

// TS/JS: every container a `require("./x")` / `import("./x")` call can legitimately sit under.
//
// The first five are the statement forms that wrap a TOP-LEVEL require, kParserVer 71's set — read off
// real parses, not predicted:
//   const X = require("./x");            lexical_declaration → variable_declarator → call_expression
//   const { a } = require("./x");        the same chain (the destructuring is in the declarator's NAME)
//   var X = require("./x");              variable_declaration → variable_declarator → call_expression
//   require("./x");                      expression_statement → call_expression
//   module.exports = require("./x");     expression_statement → assignment_expression → call_expression
//
// kParserVer 72 (fnbody-require lane) adds the rest: a top-level-only walk missed the real shape CommonJS
// LAZY loading takes — read off webpack's own lib/index.js, which the LB-H round (71) had already measured
// and left as a disclosed floor:
//   get ChunkGraph() { return require("./ChunkGraph"); }    — a getter (method_definition) inside an
//                                                               OBJECT LITERAL passed as a call argument
//   const fn = lazyFunction(() => require("./webpack"));    — an arrow_function's CONCISE body, itself a
//                                                               call argument
// Neither is a "function body" in isolation — reaching either one needs the WHOLE chain from the top-level
// statement down: call_expression (so `arguments` is visited) → arguments → object → method_definition
// (or → arrow_function directly) → its body. `statement_block` and `return_statement` cover the ordinary
// `function f() { return require("./x"); }` shape; the control-flow clauses (if/try/for/while/switch) are
// the direct analogue of Python's own body-container list two lanes up, added for the same reason: a
// `require` guarded by a runtime check (`if (!cached) { cached = require("./x"); }`) is still lazy-loaded,
// still a real dependency, and was never reachable through the pre-72 five-entry table either.
// `export_statement` earns its own entry for the same reason: `export function f() { … }` / `export class
// C { … }` / `export default function() { … }` wrap the function-body kinds in TypeScript source (probed
// against test/nestedimportfix/scope_control.ts — its `export async function loader()` body was invisible
// until this entry landed, exactly the pre-72 gap the file exists to prove). `await_expression` earns its
// own entry for the SAME probe: `const dyn = await import("./x")` puts an await_expression BETWEEN the
// variable_declarator and the call_expression, so the dynamic-import half of that same fixture line stayed
// invisible even after export_statement was added — read off the actual match (`--match='(call_expression
// function: (_) @f)'` returns a real `function:` field of text "import" here, so the earlier miss was the
// missing container, never a grammar shape jsModuleLoadTarget could not read).
// EVERY ENTRY still needs the SAME three jsModuleLoadTarget guards (bare require/import callee, one arg, a
// string literal) — this table only widens WHERE the walk looks, never what counts as a hit.
inline constexpr std::array<std::string_view, 34> kJsImportContainers = {
    "lexical_declaration", "variable_declaration", "variable_declarator", "expression_statement", "assignment_expression",
    "statement_block", "return_statement", "labeled_statement", "export_statement",
    "if_statement", "else_clause",
    "try_statement", "catch_clause", "finally_clause",
    "for_statement", "for_in_statement", "while_statement", "do_statement",
    "switch_statement", "switch_case", "switch_default",
    "class_body", "object", "pair", "arguments", "call_expression", "parenthesized_expression", "await_expression",
    // the six function-body KINDS themselves (== kJsFunctionContainers) — a container must also be entered
    // to reach ITS OWN body
    "function_declaration", "function_expression", "generator_function", "generator_function_declaration",
    "arrow_function", "method_definition"
};

// ONE TABLE, not a per-language switch. Adding the TS/JS row made this function an 87-token clone of
// inFileTestScope's dispatch further down — a --quality-delta duplication finding, and a fair one: two
// hand-maintained per-language switches are two places to forget a language. The table form is also what
// CONTRIBUTING §3 asks for ("declarative constexpr tables over scattered switch/if"): which containers a
// language has is DATA, and a language absent from the table simply has none.
struct LangImportContainers { Lang lang; std::span<const std::string_view> nodes; };

inline constexpr std::array<LangImportContainers, 5> kImportContainersByLang = { {
    { Lang::Python,     kPythonImportContainers },
    { Lang::Rust,       kRustImportContainers   },
    { Lang::CSharp,     kCsharpImportContainers },
    { Lang::TypeScript, kJsImportContainers     },
    { Lang::JavaScript, kJsImportContainers     }
} };

inline bool isImportContainer( Lang lang, const char* type ) noexcept
{
    if( isPreprocConditional( type ) )   // every grammar with a preprocessor: C/C++/ObjC/CUDA/Metal + C#
    {
        return true;
    }
    for( const LangImportContainers& e : kImportContainersByLang )
    {
        if( e.lang == lang )
        {
            return namesNode( e.nodes, type );
        }
    }
    return false;
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
// import_declaration; Rust use_declaration + mod_item; C# using_directive; TS/JS call_expression for the
// CommonJS `require("./x")` and dynamic `import("./x")` spellings. LEVER-B B0: non-C imports capture the
// CLEAN written specifier via grammar child fields (module path / quoted specifier / use argument), not a
// sliced clause — the sound resolver input.
//
// `lang` exists for exactly one branch: `call_expression` is a node type in most of our grammars, and a
// C++ or Rust function that happens to be named `require` must never manufacture a dependency edge. The
// language gate makes that impossible by construction rather than by relying on where the walk goes.
//
// `isAngle` is C/C++/ObjC only: `<x.h>` (external) vs `"x.h"` (quote), returned alongside the target so
// path-precise resolution can leave angle includes unresolved. `isLazy` is TS/JS only (kParserVer 72):
// true when `insideFn` says this call sits inside a function-body container — see kJsFunctionContainers
// and captureIncludes' `insideFn` propagation below. Allocates a std::string → not noexcept.
struct DirectiveTarget { std::string target; bool isAngle; bool isLazy; };

// `insideFn` exists for exactly the same one branch `lang` does: whether the call_expression being read
// sits inside a TS/JS function body, per captureIncludes' walk — meaningless (and ignored) everywhere else.
DirectiveTarget directiveTargetOf( TSNode n, const char* t, std::string_view src, Lang lang, bool insideFn )
{
    std::string target;
    bool        isAngle = false;
    bool        isLazy  = false;

    if( std::strcmp( t, "preproc_include" ) == 0 )                       // C++/C/ObjC: exact file path
    {
        target = preprocIncludeTarget( n, src, isAngle );
    }
    else if( std::strcmp( t, "preproc_call" ) == 0 )                     // C++-grammar `#import "x.h"` (ObjC/Metal spelling)
    {
        target = preprocImportTarget( n, src, isAngle );
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
    else if( std::strcmp( t, "call_expression" ) == 0
             && ( lang == Lang::TypeScript || lang == Lang::JavaScript ) )   // TS/JS `require("./x")` / `import("./x")`
    {
        target = jsModuleLoadTarget( n, src );
        isLazy = insideFn && !target.empty();   // kParserVer 72: a hit found inside a function body is LAZY
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
    else if( std::strcmp( t, "namespace_use_declaration" ) == 0 )
    { // PHP `use Foo\Bar;` / `use Foo\Bar as Baz;` / `use function Foo\bar;` / `use Foo\{A, B};`
        // Captured for --uses / --deps visibility, NEVER precise-resolved: PHP has no entry in
        // resolve.h's includeLangOf table, so it falls through to IncludeLang::Other exactly as Java and
        // C# do. The reason is the same one stated there — a PHP namespace does not map 1:1 onto a file
        // (PSR-4 maps it onto a DIRECTORY through a composer.json `autoload` block this tool does not
        // read), so there is no sound string→fileId rule to write, and a wrong narrow is worse than none.
        target = phpUseTarget( n, src );                                 // see phpUseTarget for the shape rationale
    }
    return { std::move( target ), isAngle, isLazy };
}

// Capture #include / import directives (physical dependencies) by walking the file's top-level nodes —
// and the bodies of anything that WRAPS a directive, which tree-sitter does not flatten: preprocessor
// conditionals in the C family and C#, and ordinary language constructs in Python / Rust / C# / TS / JS
// (see isImportContainer). Each node is read by directiveTargetOf above.
// kParserVer 72 cost note: TS/JS's kJsImportContainers now includes call_expression/object/arguments —
// containers a require() sits under with no other purpose — so the walk over a TS/JS file approaches full
// AST size rather than "top-level statements only". Bounded per-node (each node is visited once) and still
// depth-capped by kMaxImportContainerDepth; no perf gate exists in this tree to budget against (see
// CLAUDE.md's "best tool first, then fast" note), and CommonJS's own weight — an entire module system's
// worth of edges was previously invisible (kParserVer 71's LB-H measurement) — is the justification.
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
    // language whose imports are top-level by rule (Go, Java) still costs exactly the old scan.
    // `insideFn` (kParserVer 72, TS/JS only): true once the walk has descended through a function-body
    // container (kJsFunctionContainers) — sticky for every descendant, never cleared, exactly like `depth`
    // is monotonic. It rides the frame rather than being recomputed from ancestry because the walk never
    // keeps the ancestor chain around: this is the one bit of it a lazy-require call needs.
    struct IncFrame { TSNode node; std::uint16_t depth; bool insideFn; };
    std::vector<IncFrame> stack;
    stack.reserve( 64 );
    for( std::size_t i = kids.size(); i > 0; --i )
    {
        stack.push_back( { kids[i - 1], 0, false } );   // nothing is inside a function at the file root
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
        auto [ target, isAngle, isLazy ] = directiveTargetOf( n, t, src, lang, frame.insideFn );

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
                // kParserVer 72: crossing a function-body KIND flips `insideFn` for every descendant of n —
                // sticky, so a nested closure inside an already-lazy function stays lazy, never resets.
                const bool childInsideFn = frame.insideFn || isJsFunctionLike( lang, t );
                collectChildren( n, cursor.cur, kids );   // safe: the seed iteration above is finished
                for( std::size_t i = kids.size(); i > 0; --i )
                {
                    stack.push_back( { kids[i - 1], static_cast<std::uint16_t>( frame.depth + 1 ), childInsideFn } );
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
            incs.push_back( { fileId, isAngle, isLazy, std::move( target ) } );
        }
    }
}
}   // namespace — ingest_relations.h section of ingest.cpp

}   // namespace rw
